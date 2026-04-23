-- | SCC merge pass for mutual recursion.
--
-- Finds strongly connected components (Tarjan) in the Core call graph.
-- For every cyclic component with more than one function, merges the
-- members into a single self-recursive function with a "function tag"
-- parameter; cross-calls within the SCC become self-calls on the merged
-- function with a different tag; non-SCC callers still reach each
-- original name through a one-line wrapper. The canonical "merge
-- mutual recursion by tagging" transformation; the same
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
-- MVP restrictions (the plan skips the SCC and leaves its members
-- intact when any of these fail):
--
--   * Every member must be a 'CFunDef' (no constants).
--   * All members share the same arity. Awsum's types are erased at
--     Core level, so we can only check arity, not full type equality;
--     different-arity SCCs would need a sum-of-args codomain that is
--     out of scope for MVP.
--
-- See @docs\/recursion.md@ for the full pipeline story.
module Awsum.Scc (sccMergeProgram) where

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
sccMergeProgram (CoreProgram ds) =
  let declMap = Map.fromList [(declName d, d) | d <- ds]
      topLevels = Map.keysSet declMap
      sccs = stronglyConnected topLevels ds
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
-- and let the SCC pass through untouched.
planMerge :: Map Name CDecl -> [Name] -> Maybe (CDecl, [CDecl])
planMerge declMap members = do
  memberDecls <- traverse (`Map.lookup` declMap) members
  parts <- traverse asFun memberDecls
  -- All members must share arity.
  let arities = map (\(_, ps, _) -> length ps) parts
  guard (all (== head' arities) (tail' arities))
  -- Sort by name for a stable layout regardless of call-graph order.
  let sorted = sortWith (\(n, _, _) -> n) parts
      names = [n | (n, _, _) <- sorted]
      memberSet = Set.fromList names
      mergedName = "$scc$" <> T.intercalate "_" names
      fnParam :: Name
      fnParam = "$fn"
      -- Use unified positional argument names so bodies from different
      -- members can live in one scope without clashing on their
      -- original param names.
      arity = length (head' (map (\(_, ps, _) -> ps) sorted))
      argParams = ["$arg_" <> show i | i <- [0 .. arity - 1]]
      alts =
        [ (i, [], rewriteBody memberSet mergedName names (ps, body) argParams)
        | (i, (_, ps, body)) <- zip [0 ..] sorted
        ]
      mergedBody = CCase (CVar fnParam) alts
      mergedDecl = CFunDef mergedName (fnParam : argParams) mergedBody
      wrappers =
        [ CFunDef
            n
            origParams
            ( CCall
                (CVar mergedName)
                (CCon i [] : map CVar origParams)
            )
        | (i, (n, origParams, _)) <- zip [0 ..] sorted
        ]
  Just (mergedDecl, wrappers)
  where
    asFun :: CDecl -> Maybe (Name, [Name], CExpr)
    asFun = \case
      CFunDef n ps b -> Just (n, ps, b)
      CValDef {} -> Nothing
    head' xs = fromMaybe (error "Awsum.Scc: empty SCC") (viaNonEmpty head xs)
    tail' xs = fromMaybe [] (viaNonEmpty tail xs)

-- | Rewrite a member's body for emission inside the merged function:
--
--   1. Alpha-rename the member's own parameter names to the merged
--      function's unified names (@$arg_0@, @$arg_1@, …).
--   2. Redirect every call to a fellow SCC member into a self-call on
--      the merged function, tagged by that member's position.
rewriteBody :: Set Name -> Name -> [Name] -> ([Name], CExpr) -> [Name] -> CExpr
rewriteBody memberSet mergedName memberOrder (origParams, body) unifiedParams =
  let renamed = foldr (\(a, b) e -> alphaRename a b e) body (zip origParams unifiedParams)
   in rewriteCalls renamed
  where
    tagFor :: Name -> Int
    tagFor n = case elemIndex n memberOrder of
      Just i -> i
      Nothing -> error ("Awsum.Scc: tagFor: not an SCC member: " <> n)

    rewriteCalls :: CExpr -> CExpr
    rewriteCalls = \case
      CCall (CVar n) args
        | n `Set.member` memberSet ->
            CCall
              (CVar mergedName)
              (CCon (tagFor n) [] : map rewriteCalls args)
      CCall c args -> CCall (rewriteCalls c) (map rewriteCalls args)
      CCon t fs -> CCon t (map rewriteCalls fs)
      CCase s alts -> CCase (rewriteCalls s) [(t, vs, rewriteCalls b) | (t, vs, b) <- alts]
      CLoop b -> CLoop (rewriteCalls b)
      CContinue xs -> CContinue (map rewriteCalls xs)
      e@(CVar _) -> e
      e@(CString _) -> e
      e@(CIntLit _ _) -> e
      e@(CBuiltIn _) -> e

-- | Alpha-rename free occurrences of @from@ to @to@. Arm binders that
-- reintroduce @from@ shadow, so we stop descending there.
alphaRename :: Name -> Name -> CExpr -> CExpr
alphaRename from to = go
  where
    go = \case
      CVar n | n == from -> CVar to
      e@(CVar _) -> e
      e@(CString _) -> e
      e@(CIntLit _ _) -> e
      e@(CBuiltIn _) -> e
      CCall c xs -> CCall (go c) (map go xs)
      CCon t fs -> CCon t (map go fs)
      CCase s alts -> CCase (go s) (map goAlt alts)
      CLoop b -> CLoop (go b)
      CContinue xs -> CContinue (map go xs)
    goAlt (t, vs, b)
      | from `elem` vs = (t, vs, b)
      | otherwise = (t, vs, go b)

-- | Build the call graph and run Tarjan to produce SCCs in topological
-- order (sinks first). Only direct call-graph edges via @CCall (CVar
-- n)@ are counted, restricted to top-level names (parameters and
-- 'CBuiltIn' references don't contribute to the graph).
stronglyConnected :: Set Name -> [CDecl] -> [G.SCC Name]
stronglyConnected topLevels ds =
  let edges =
        [ (declName d, declName d, Set.toList (callees d))
        | d <- ds
        ]
   in G.stronglyConnComp edges
  where
    callees :: CDecl -> Set Name
    callees (CFunDef _ _ body) = calls body `Set.intersection` topLevels
    callees (CValDef _ body) = calls body `Set.intersection` topLevels

    calls :: CExpr -> Set Name
    calls = \case
      CCall (CVar n) args -> Set.insert n (foldMap calls args)
      CCall c args -> calls c <> foldMap calls args
      CCon _ fs -> foldMap calls fs
      CCase s alts -> calls s <> foldMap (\(_, _, b) -> calls b) alts
      CVar n -> Set.singleton n -- first-class function reference
      CLoop b -> calls b
      CContinue xs -> foldMap calls xs
      CString _ -> mempty
      CIntLit _ _ -> mempty
      CBuiltIn _ -> mempty

declName :: CDecl -> Name
declName = \case
  CFunDef n _ _ -> n
  CValDef n _ -> n
