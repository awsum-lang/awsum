-- | SCC merge pass for mutual recursion.
--
-- Finds strongly connected components (Tarjan) in the Core call graph.
-- For every cyclic component with more than one function, merges the
-- members into a single self-recursive function whose parameter is a
-- sum-typed @CCon tag args@ value — one tag per SCC member, fields
-- carrying that member's original arguments. Cross-calls within the
-- SCC become self-calls on the merged function with a different tag;
-- non-SCC callers still reach each original name through a one-line
-- wrapper that packs its args into the right @CCon@. The canonical
-- "merge mutual recursion by tagging" transformation; the same
-- defunctionalization-by-Reynolds primitive used in 'Awsum.Cps', just
-- applied to "which function is active" instead of "what to do after
-- this call returns".
--
-- Why this works for stack safety:
--
--   * After merge, the SCC contains only self-recursion. Tail
--     cross-calls fold into 'CLoop' \/ 'CContinue' via 'Awsum.Tco'.
--     Non-tail cross-calls become non-tail self-calls and get picked
--     up by 'Awsum.Cps' — the K chain carries the
--     continuation through the fused function body.
--   * No backend needs a new opcode or runtime: the merged function
--     is an ordinary self-recursive 'CFunDef', the tag is an ordinary
--     'CCon' dispatched by an ordinary 'CCase'.
--
-- **Heterogeneous arity.** The sum-typed args shape means members can
-- have different arities (or different parameter types, though Awsum's
-- types are erased at Core level so that is invisible to us) — each
-- tag's fields correspond to exactly one member's parameter list.
-- Classic parser-combinator style (@parseExpr : Input -> Result@ and
-- @parseBinary : Input -> Int -> Result@ calling each other) works out
-- of the box.
--
-- Current restrictions (the plan skips the SCC and leaves its members
-- intact when they fail):
--
--   * Every member must be a 'CFunDef' (no constants). Mutually
--     recursive top-level values have no fixed point and are a
--     user-level error; 'Awsum.StackSafety.verifyStackSafety' rejects
--     them with a diagnostic before this pass runs.
--
-- See @docs\/recursion.md@ for the full pipeline story.
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
-- Trivial (acyclic or single-member) SCCs are passed through; for each
-- merged SCC we emit @$scc$<joined names>@ plus N one-line wrappers
-- preserving the original public names.
sccMergeProgram :: CoreProgram -> CoreProgram
sccMergeProgram prog@(CoreProgram ds) =
  let declMap = Map.fromList [(declName d, d) | d <- ds]
      sccs = stronglyConnected prog
      -- Classify: each SCC either triggers a merge (resulting in one
      -- merged CFunDef + N wrappers, replacing its members) or is left
      -- as-is.
      sccOutputs = map (processScc declMap) sccs
      mergedNames = Set.unions [Set.fromList (sccReplaced out) | out <- sccOutputs]
      -- Keep original declarations that weren't part of any merged SCC,
      -- preserving the source order.
      kept = [d | d <- ds, not (declName d `Set.member` mergedNames)]
      -- Merged decls (merged fn + wrappers) appended at end in SCC order.
      added = concatMap sccAdded sccOutputs
   in CoreProgram (kept <> added)

-- | Output for one SCC: the names it replaced (removed from decls) and
-- the new decls it introduced (merged + wrappers). Trivial/skipped SCCs
-- have both empty.
data SccOutput = SccOutput
  { sccReplaced :: [Name],
    sccAdded :: [CDecl]
  }

processScc :: Map Name CDecl -> G.SCC Name -> SccOutput
processScc declMap = \case
  G.AcyclicSCC _ -> SccOutput [] []
  G.CyclicSCC [_] ->
    -- Single-member cyclic SCC = a self-recursive function. Already
    -- handled by TCO + Cps; merging would be a no-op.
    SccOutput [] []
  G.CyclicSCC members ->
    case planMerge declMap members of
      Nothing -> SccOutput [] [] -- unsupported SCC, leave as-is
      Just (merged, wrappers) ->
        SccOutput
          { sccReplaced = members,
            sccAdded = merged : wrappers
          }

-- | Build the @$scc$@ merged function and its wrappers, or fail out
-- and let the SCC pass through untouched (happens only when a member
-- is a 'CValDef' — arity and parameter count are handled via a
-- sum-typed argument value, so heterogeneity is no obstacle).
--
-- Emission shape:
--
-- @
--   $scc$…( $args ) =
--     case $args of
--       0 (p_0_0, p_0_1, …) -> <body of f_0 with cross-calls rewritten>
--       1 (p_1_0, p_1_1, …) -> <body of f_1 with cross-calls rewritten>
--       …
--
--   f_i(p_0, p_1, …) = $scc$… (CCon i [p_0, p_1, …])              -- wrapper
-- @
--
-- Arm binders are the /original/ parameter names of each member, so
-- that member's body references resolve naturally — no alpha-rename
-- required. This also removes the homogeneous-arity restriction: each
-- tag carries exactly the number of fields that member expects.
planMerge :: Map Name CDecl -> [Name] -> Maybe (CDecl, [CDecl])
planMerge declMap members = do
  memberDecls <- traverse (`Map.lookup` declMap) members
  parts <- traverse asFun memberDecls
  -- Sort by name for a stable tag assignment regardless of call-graph order.
  let sorted = sortWith (\(n, _, _) -> n) parts
      names = [n | (n, _, _) <- sorted]
      memberSet = Set.fromList names
      mergedName = "$scc$" <> T.intercalate "_" names
      argsParam :: Name
      argsParam = "$args"
      alts =
        [ (i, ps, rewriteCrossCalls memberSet mergedName names body)
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
                [CCon i (map CVar origParams)]
            )
        | (i, (n, origParams, _)) <- zip [0 ..] sorted
        ]
  Just (mergedDecl, wrappers)
  where
    asFun :: CDecl -> Maybe (Name, [Name], CExpr)
    asFun = \case
      CFunDef n ps b -> Just (n, ps, b)
      CValDef {} -> Nothing

-- | Redirect every direct call @f_j(x, y, …)@ to a fellow SCC member
-- into a tail call on the merged function with its args packed into a
-- tagged 'CCon'. Everything else is traversed structurally and left
-- alone.
rewriteCrossCalls :: Set Name -> Name -> [Name] -> CExpr -> CExpr
rewriteCrossCalls memberSet mergedName memberOrder = go
  where
    tagFor :: Name -> Int
    tagFor n = case elemIndex n memberOrder of
      Just i -> i
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
      CLoop b -> CLoop (go b)
      CContinue xs -> CContinue (map go xs)
      e@(CVar _) -> e
      e@(CString _) -> e
      e@(CIntLit _ _) -> e
      e@(CBuiltIn _) -> e
