-- | SCC merge pass for mutual recursion.
--
-- Finds strongly connected components (Tarjan) in the Core call graph.
-- For every cyclic component with more than one function, merges the
-- members into a single self-recursive function whose parameter is a
-- sum-typed @CCon tag args@ — one tag per member, fields carrying
-- that member's original arguments. Cross-calls within the SCC become
-- self-calls on the merged function with a different tag; outside
-- callers reach each original name through a one-line wrapper that
-- packs its args into the right @CCon@. The same
-- defunctionalization-by-Reynolds primitive used in 'Awsum.Cps',
-- applied to "which function is active" instead of "what to do after
-- this call returns".
--
-- Why this works for stack safety:
--
--   * The SCC now contains only self-recursion. Tail cross-calls fold
--     into 'CLoop' \/ 'CContinue' via 'Awsum.Tco'; non-tail ones go
--     through 'Awsum.Cps'.
--   * No backend needs a new opcode: the merged function is an
--     ordinary 'CFunDef', the tag an ordinary 'CCon' dispatched by an
--     ordinary 'CCase'.
--
-- Heterogeneous arity falls out of the sum-typed argument: each tag's
-- fields correspond to exactly one member's parameter list. Classic
-- parser-combinator style — @parseExpr : Input -> Result@ and
-- @parseBinary : Input -> Int -> Result@ calling each other — works
-- without homogenising arities.
--
-- Restriction: every member must be a 'CFunDef'. Mutually recursive
-- 'CValDef's have no fixed point; 'Awsum.StackSafety.verifyStackSafety'
-- rejects them before this pass runs.
--
-- See @docs\/recursion.md@.
module Awsum.Scc (sccMergeProgram) where

import Awsum.CallGraph (declName, stronglyConnected)
import Awsum.Core
import Awsum.Syntax (Name)
import Data.Graph qualified as G
import Data.List (elemIndex)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Relude

-- | Run SCC analysis and merge every non-trivial cyclic SCC.
-- Trivial SCCs (acyclic or single-member) pass through; merged ones
-- emit @$scc$<joined names>@ plus N wrappers preserving the originals.
--
-- Each merged SCC's sum-type tags are allocated from a globally
-- monotonic supply seeded with 'nextFreshConTag', so every member's
-- tag is unique across the whole program (no collision with nominal
-- constructor tags or with other SCCs' merged sum types).
sccMergeProgram :: CoreProgram -> CoreProgram
sccMergeProgram prog@(CoreProgram ds) =
  let declMap = Map.fromList [(declName d, d) | d <- ds]
      sccs = stronglyConnected prog
      baseTag = nextFreshConTag prog
      (_, sccOutputs) = mapAccumL (processScc declMap) baseTag sccs
      mergedNames = Set.unions [Set.fromList (sccReplaced out) | out <- sccOutputs]
      -- Keep originals not part of any merged SCC, preserving source order.
      kept = [d | d <- ds, not (declName d `Set.member` mergedNames)]
      added = concatMap sccAdded sccOutputs
   in CoreProgram (kept <> added)

-- | Output for one SCC: names it replaced and decls it introduced.
-- Trivial/skipped SCCs have both empty.
data SccOutput = SccOutput
  { sccReplaced :: [Name],
    sccAdded :: [CDecl]
  }

-- | Stateful SCC processing: takes the next-free tag, produces an
-- updated next-free tag (advanced by the number of tags this SCC
-- consumed) plus the SCC's output.
processScc :: Map Name CDecl -> Int -> G.SCC Name -> (Int, SccOutput)
processScc declMap nextTag = \case
  G.AcyclicSCC _ -> (nextTag, SccOutput [] [])
  G.CyclicSCC [_] ->
    -- Self-recursion — already handled by TCO + Cps.
    (nextTag, SccOutput [] [])
  G.CyclicSCC members ->
    case planMerge nextTag declMap members of
      Nothing -> (nextTag, SccOutput [] []) -- unsupported SCC, leave as-is
      Just (merged, wrappers, consumed) ->
        ( nextTag + consumed,
          SccOutput
            { sccReplaced = members,
              sccAdded = merged : wrappers
            }
        )

-- | Build the @$scc$@ merged function and its wrappers, or 'Nothing'
-- if a member is a 'CValDef' (the only blocker).
--
-- Member tags are allocated as @baseTag, baseTag+1, …@ — globally
-- unique across the program. The returned 'Int' is the number of
-- tags consumed (the SCC's member count when the merge succeeds), so
-- the caller can advance the supply.
--
-- Emission shape:
--
-- @
--   $scc$…( $args ) =
--     case $args of
--       baseTag     (p_0_0, p_0_1, …) -> <body of f_0 with cross-calls rewritten>
--       baseTag + 1 (p_1_0, p_1_1, …) -> <body of f_1 with cross-calls rewritten>
--       …
--
--   f_i(p_0, p_1, …) = $scc$… (CCon (baseTag + i) [p_0, p_1, …])    -- wrapper
-- @
--
-- Arm binders are each member's /original/ parameter names — body
-- references resolve naturally, no alpha-rename.
planMerge :: Int -> Map Name CDecl -> [Name] -> Maybe (CDecl, [CDecl], Int)
planMerge baseTag declMap members = do
  memberDecls <- traverse (`Map.lookup` declMap) members
  parts <- traverse asFun memberDecls
  -- Sort by name for a stable tag assignment regardless of call-graph order.
  let sorted = sortWith (\(n, _, _) -> n) parts
      names = [n | (n, _, _) <- sorted]
      memberSet = Set.fromList names
      mergedName = "$scc$" <> T.intercalate "_" names
      argsParam :: Name
      argsParam = "$args"
      tagOf :: Int -> Int
      tagOf i = baseTag + i
      alts =
        [ (tagOf i, ps, rewriteCrossCalls memberSet mergedName names tagOf body)
        | (i, (_, ps, body)) <- zip [0 ..] sorted
        ]
      mergedBody = CCase (CVar argsParam) alts
      mergedDecl = CFunDef mergedName [argsParam] mergedBody
      wrappers =
        [ CFunDef
            n
            origParams
            ( CCall
                (CVar mergedName)
                [CCon (tagOf i) (map CVar origParams)]
            )
        | (i, (n, origParams, _)) <- zip [0 ..] sorted
        ]
  Just (mergedDecl, wrappers, length sorted)
  where
    asFun :: CDecl -> Maybe (Name, [Name], CExpr)
    asFun = \case
      CFunDef n ps b -> Just (n, ps, b)
      CValDef {} -> Nothing

-- | Redirect every direct call to a fellow SCC member into a tail call
-- on the merged function with args packed into a tagged 'CCon'.
-- Structural traversal otherwise. The @tagOf@ argument maps the
-- member's positional index in @memberOrder@ to its globally unique
-- tag.
rewriteCrossCalls :: Set Name -> Name -> [Name] -> (Int -> Int) -> CExpr -> CExpr
rewriteCrossCalls memberSet mergedName memberOrder tagOf = go
  where
    tagFor :: Name -> Int
    tagFor n = case elemIndex n memberOrder of
      Just i -> tagOf i
      Nothing -> error ("Awsum.Scc: tagFor: not an SCC member: " <> n)

    go :: CExpr -> CExpr
    go = \case
      CCall (CVar n) args
        | n `Set.member` memberSet ->
            CCall
              (CVar mergedName)
              [CCon (tagFor n) (map go args)]
      CCall c args -> CCall (go c) (map go args)
      CCon t fs -> CCon t (map go fs)
      CCase s alts -> CCase (go s) [(t, vs, go b) | (t, vs, b) <- alts]
      CRow t v -> CRow t (go v)
      CRowCase s alts -> CRowCase (go s) [(t, v, go b) | (t, v, b) <- alts]
      CLoop b -> CLoop (go b)
      CContinue xs -> CContinue (map go xs)
      CDrop n b -> CDrop n (go b)
      CReuse rm n t fs -> CReuse rm n t (map go fs)
      CLet x rhs body -> CLet x (go rhs) (go body)
      CJoin {} -> error "Scc: CJoin is minted by Awsum.Simplify, which runs later"
      CJump {} -> error "Scc: CJump is minted by Awsum.Simplify, which runs later"
      e@(CProj _ _) -> e
      e@(CVar _) -> e
      e@(CString _) -> e
      e@(CIntLit _ _) -> e
      e@(CBuiltIn _) -> e
