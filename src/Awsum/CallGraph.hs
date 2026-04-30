-- | Call-graph utilities shared between the recursion-related Core
-- passes ('Awsum.Scc', 'Awsum.Cps') and the post-pipeline stack-safety
-- verifier ('Awsum.StackSafety').
--
-- Keeping one source of truth for "what's a call-graph edge" avoids
-- subtle drift: all passes agree on how to count direct calls, when to
-- treat a 'CVar' as a first-class function reference, and which calls
-- qualify as self-calls in tail position.
module Awsum.CallGraph
  ( -- * Top-level traversal
    declName,

    -- * Call graph
    CoreCallGraph,
    buildCallGraph,
    stronglyConnected,

    -- * Self-call analysis
    hasNonTailSelfCall,
    containsSelfCall,
  )
where

import Awsum.Core
import Awsum.Syntax (Name)
import Data.Graph qualified as G
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Relude

-- | The (direct) call graph of a 'CoreProgram': every top-level name
-- mapped to the set of other top-level names it references. Edges
-- include both direct 'CCall (CVar n)' and first-class 'CVar n' uses
-- so higher-order references participate in SCC detection; the set is
-- intersected with the program's top-level names so locals and
-- 'CBuiltIn's do not contribute.
type CoreCallGraph = Map Name (Set Name)

-- | Top-level name of a Core declaration.
declName :: CDecl -> Name
declName = \case
  CFunDef n _ _ -> n
  CValDef n _ -> n

-- | Build 'CoreCallGraph' from a 'CoreProgram'. Only edges to other
-- /top-level/ names are kept; parameters, arm-bound variables, and
-- 'CBuiltIn' references are discarded because they cannot participate
-- in recursion cycles.
buildCallGraph :: CoreProgram -> CoreCallGraph
buildCallGraph (CoreProgram ds) =
  let topLevels = Set.fromList (map declName ds)
   in Map.fromList [(declName d, callees topLevels d) | d <- ds]
  where
    callees :: Set Name -> CDecl -> Set Name
    callees tops (CFunDef _ _ body) = calls body `Set.intersection` tops
    callees tops (CValDef _ body) = calls body `Set.intersection` tops

    calls :: CExpr -> Set Name
    calls = \case
      CCall (CVar n) args -> Set.insert n (foldMap calls args)
      CCall c args -> calls c <> foldMap calls args
      CCon _ fs -> foldMap calls fs
      CCase s alts -> calls s <> foldMap (\(_, _, b) -> calls b) alts
      CRow _ v -> calls v
      CRowCase s alts -> calls s <> foldMap (\(_, _, b) -> calls b) alts
      CVar n -> Set.singleton n
      CLoop b -> calls b
      CContinue xs -> foldMap calls xs
      CString _ -> mempty
      CIntLit _ _ -> mempty
      CBuiltIn _ -> mempty

-- | Strongly-connected components of a 'CoreProgram', in reverse
-- topological order (sinks first — 'Data.Graph.stronglyConnComp'
-- convention).
stronglyConnected :: CoreProgram -> [G.SCC Name]
stronglyConnected prog =
  let graph = buildCallGraph prog
      edges = [(n, n, Set.toList cs) | (n, cs) <- Map.toList graph]
   in G.stronglyConnComp edges

-- | True iff @body@ contains a call to @f@ in a non-tail position.
-- Walks top-down tracking tail context: the function body itself is
-- tail, each 'CCase' arm /inside a tail case/ is tail, and everything
-- else (scrutinees, call arguments, 'CCon' fields) is non-tail.
hasNonTailSelfCall :: Name -> CExpr -> Bool
hasNonTailSelfCall f = inTail
  where
    inTail = \case
      CCall (CVar n) args | n == f -> any inNonTail args
      CCall callee args -> inNonTail callee || any inNonTail args
      CCase scrut alts -> inNonTail scrut || any (\(_, _, b) -> inTail b) alts
      CRow _ v -> inNonTail v
      CRowCase scrut alts -> inNonTail scrut || any (\(_, _, b) -> inTail b) alts
      CCon _ fs -> any inNonTail fs
      CLoop b -> inTail b
      CContinue xs -> any inNonTail xs
      CVar _ -> False
      CString _ -> False
      CIntLit _ _ -> False
      CBuiltIn _ -> False

    inNonTail = \case
      CCall (CVar n) _ | n == f -> True
      CCall callee args -> inNonTail callee || any inNonTail args
      CCase scrut alts -> inNonTail scrut || any (\(_, _, b) -> inNonTail b) alts
      CRow _ v -> inNonTail v
      CRowCase scrut alts -> inNonTail scrut || any (\(_, _, b) -> inNonTail b) alts
      CCon _ fs -> any inNonTail fs
      CLoop b -> inNonTail b
      CContinue xs -> any inNonTail xs
      _ -> False

-- | Any call to @f@ anywhere in this sub-expression (tail or not).
-- Useful for validating arm-body restrictions in CPS'd code.
containsSelfCall :: Name -> CExpr -> Bool
containsSelfCall f = go
  where
    go = \case
      CCall (CVar n) _ | n == f -> True
      CCall callee args -> go callee || any go args
      CCase scrut alts -> go scrut || any (\(_, _, b) -> go b) alts
      CRow _ v -> go v
      CRowCase scrut alts -> go scrut || any (\(_, _, b) -> go b) alts
      CCon _ fs -> any go fs
      CLoop b -> go b
      CContinue xs -> any go xs
      _ -> False
