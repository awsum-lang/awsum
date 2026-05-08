-- | Reynolds defunctionalization for residual function values.
--
-- Runs after 'Awsum.Defunctionalize' has eliminated every statically
-- resolvable HOF call site; whatever first-class function value is
-- left flows through positions Defunctionalize cannot specialise:
--
--   * stored in a constructor field (@type Box = Box (Int32 -> Int32)@,
--     @IOGetArgs (String -> IO e a)@),
--   * passed as a HOF argument when the HOF is itself a residual
--     value (call through case-arm-binder),
--   * captured into a partial application with local captures inside
--     a function the HOF specialiser could not reach.
--
-- This pass closes the gap by encoding every such closure as a tagged
-- ADT and routing every residual call through a per-arity @apply_k@
-- dispatcher — the same Reynolds primitive 'Awsum.Cps' uses for
-- continuation chains. After the pass no first-class function value
-- remains anywhere in Core: every 'CCall' has either a top-level fn
-- in callee position or one of the synthetic @apply_k@ helpers, and
-- every formerly fn-typed value is a 'CCon' carrying the closure's
-- captures.
--
-- ## Pipeline position
--
-- Between 'Awsum.Defunctionalize' (with its tree-shake) and
-- 'saturateProgram'. Saturate asserts that no partial application
-- with local captures survives Defunctionalize — an invariant the
-- pre-IOGetArgs world enjoyed for free because every closure with
-- captures could be HOF-specialised. Once a closure can flow into a
-- constructor field, that invariant breaks unless 'LowerClosures'
-- encodes the partial application into a 'CCon' first.
--
-- ## Algorithm
--
-- One walk per top-level decl. Each closure value (bare 'CVar' to a
-- top-level fn in non-callee position, or partial application
-- 'CCall (CVar f) args' with @length args < arity f@) is rewritten
-- to @CCon shapeTag captures@. Each residual call site
-- @CCall (CVar n) args@ where @n@ is not a top-level fn is rewritten
-- to @CCall (CVar (apply_k)) (CVar n : args)@.
--
-- Tag assignment is per-arity: every closure shape @(helper,
-- captureCount)@ gets a tag in the namespace of its remaining-arity
-- dispatcher (@apply_(arity helper - captureCount)@). Same shape
-- always lands in the same dispatcher because captureCount is
-- structural — a closure's remaining arity is fixed once the helper
-- is known.
--
-- Per-arity dispatchers:
--
-- @
--   apply_k closure x_1 .. x_k = case closure of
--     0 (cap_0_0 .. cap_0_{m_0-1}) -> helper_0 cap_0_0 .. cap_0_{m_0-1} x_1 .. x_k
--     1 (cap_1_0 .. cap_1_{m_1-1}) -> helper_1 cap_1_0 .. cap_1_{m_1-1} x_1 .. x_k
--     ...
-- @
--
-- ## What stays untouched
--
-- Saturated direct calls (@CCall (CVar f) args@ with
-- @length args == arity f@) and 'CBuiltIn' references — both are
-- already first-order. Closure values whose helper is a 'CBuiltIn'
-- do not arise (built-ins are referenced only in callee position by
-- the lowering pipeline).
module Awsum.LowerClosures (lowerClosuresProgram) where

import Awsum.Core
import Awsum.Syntax (Name)
import Data.List (elemIndex)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Relude

-- | A closure's identity: which top-level helper, with how many of
-- its parameters already captured. Two closures with the same shape
-- share a tag.
type ClosureShape = (Name, Int)

-- | Layout of one apply_k dispatcher: shapes that flow through it,
-- in the order they were assigned tags (tag = list index).
data ApplyDispatcher = ApplyDispatcher
  { adRemainingArity :: !Int,
    adShapes :: ![ClosureShape]
  }
  deriving stock (Show, Eq)

-- | Top-level entry. Returns a Core program with every residual
-- function value replaced by a tagged 'CCon' and every residual call
-- routed through an @apply_k@ dispatcher; the dispatchers are
-- appended at the end.
lowerClosuresProgram :: CoreProgram -> CoreProgram
lowerClosuresProgram (CoreProgram decls) =
  let arities = Map.fromList [(n, length args) | CFunDef n args _ <- decls]
      shapeMap = collectShapes arities decls
      residualArities = collectResidualArities arities decls
      -- Ensure a dispatcher exists for every arity that appears as a
      -- residual call site, even when no closure shape currently flows
      -- through it. Without this, 'runIO''s 'IOGetArgs' arm calls
      -- '$apply1' on programs that never construct an 'IOGetArgs'
      -- value — the call is dead at runtime, but the codegen still
      -- needs '$apply1' to be defined for the binary to link.
      arityKeysWithEmpty =
        Map.unionWith
          (<>)
          shapeMap
          (Map.fromSet (const []) residualArities)
      dispatchers = buildDispatchers arities arityKeysWithEmpty
      shapeTagOf = shapeTagOfFn dispatchers
      rewritten = map (rewriteDecl arities shapeTagOf) decls
   in CoreProgram (rewritten <> map dispatcherDecl dispatchers)

-- | All closure shapes referenced anywhere in the program, grouped by
-- their remaining arity. Each shape appears once even if used at
-- many sites; shapes within one remaining-arity bucket are
-- alphabetically ordered for snapshot stability and readability.
collectShapes :: Map Name Int -> [CDecl] -> Map Int [ClosureShape]
collectShapes arities decls =
  let shapes = Set.toAscList $ foldMap (declShapes arities) decls
   in Map.map sort
        $ Map.fromListWith
          (<>)
          [ (remainingArity, [(helper, captureCount)])
          | (helper, captureCount) <- shapes,
            Just helperArity <- [Map.lookup helper arities],
            let remainingArity = helperArity - captureCount
          ]

-- | Closure shapes referenced inside one declaration. Walks every
-- value-position sub-expression looking for bare references and
-- partial applications of top-level functions.
declShapes :: Map Name Int -> CDecl -> Set ClosureShape
declShapes arities = \case
  CFunDef _ _ body -> exprShapes arities body
  CValDef _ rhs -> exprShapes arities rhs

-- | Set of arities used at residual call sites — calls
-- @CCall (CVar n) args@ where @n@ is not a top-level fn.
-- Independent of closure-flow: a residual call may appear in a
-- function body whose runtime path never executes (e.g. the
-- 'IOGetArgs' arm of 'runIO' in a program that never constructs
-- 'IOGetArgs'); the corresponding dispatcher must still exist for
-- the codegen to emit a valid binary.
collectResidualArities :: Map Name Int -> [CDecl] -> Set Int
collectResidualArities arities = foldMap declArities
  where
    declArities = \case
      CFunDef _ _ body -> exprArities body
      CValDef _ rhs -> exprArities rhs

    exprArities = \case
      CCall (CVar n) args
        | Nothing <- Map.lookup n arities ->
            Set.singleton (length args) <> foldMap exprArities args
      CCall callee args -> exprArities callee <> foldMap exprArities args
      CCon _ fs -> foldMap exprArities fs
      CCase s alts -> exprArities s <> foldMap (\(_, _, b) -> exprArities b) alts
      CRow _ v -> exprArities v
      CRowCase s alts -> exprArities s <> foldMap (\(_, _, b) -> exprArities b) alts
      CLoop b -> exprArities b
      CContinue xs -> foldMap exprArities xs
      CVar _ -> mempty
      CString _ -> mempty
      CIntLit _ _ -> mempty
      CBuiltIn _ -> mempty

-- | Closure shapes referenced in an expression. The 'callee'
-- argument tracks whether the immediately-enclosing expression is a
-- 'CCall' callee (in which case bare 'CVar' references are direct
-- calls, not closures).
exprShapes :: Map Name Int -> CExpr -> Set ClosureShape
exprShapes arities = goValue
  where
    -- In value position: bare 'CVar' to a top-level fn is a
    -- zero-capture closure; partial application is an N-capture
    -- closure.
    goValue = \case
      CVar n
        | Just _ <- Map.lookup n arities -> Set.singleton (n, 0)
        | otherwise -> mempty
      CCall (CVar f) args
        | Just ar <- Map.lookup f arities,
          length args < ar ->
            Set.singleton (f, length args) <> foldMap goValue args
      CCall callee args -> goCallee callee <> foldMap goValue args
      CCon _ fs -> foldMap goValue fs
      CCase s alts -> goValue s <> foldMap (\(_, _, b) -> goValue b) alts
      CRow _ v -> goValue v
      CRowCase s alts -> goValue s <> foldMap (\(_, _, b) -> goValue b) alts
      CLoop b -> goValue b
      CContinue xs -> foldMap goValue xs
      CString _ -> mempty
      CIntLit _ _ -> mempty
      CBuiltIn _ -> mempty

    -- In callee position: a 'CVar' to a top-level fn is a direct
    -- call, not a closure. Walk through to collect shapes from
    -- nested expressions.
    goCallee = \case
      CVar _ -> mempty
      CBuiltIn _ -> mempty
      e -> goValue e

-- | Build one 'ApplyDispatcher' per used remaining arity. Shapes are
-- stable-sorted (already 'Set'-ordered by 'collectShapes') so tag
-- assignment is deterministic across runs.
buildDispatchers :: Map Name Int -> Map Int [ClosureShape] -> [ApplyDispatcher]
buildDispatchers _arities shapeMap =
  [ ApplyDispatcher {adRemainingArity = k, adShapes = shapes}
  | (k, shapes) <- Map.toAscList shapeMap
  ]

-- | Lookup function: shape → (dispatcher's remaining arity, tag
-- within that dispatcher). 'Nothing' for an unrecognised shape (a
-- closure whose helper has an unknown arity, e.g. a 'CBuiltIn' —
-- shouldn't arise after Defunctionalize but we tolerate it).
shapeTagOfFn :: [ApplyDispatcher] -> ClosureShape -> Maybe (Int, Int)
shapeTagOfFn dispatchers shape =
  listToMaybe
    [ (adRemainingArity ad, tag)
    | ad <- dispatchers,
      Just tag <- [elemIndex shape (adShapes ad)]
    ]

-- | Apply the rewrite to one declaration's body.
rewriteDecl :: Map Name Int -> (ClosureShape -> Maybe (Int, Int)) -> CDecl -> CDecl
rewriteDecl arities tagOf = \case
  CFunDef n args body -> CFunDef n args (rewriteExpr arities tagOf body)
  CValDef n rhs -> CValDef n (rewriteExpr arities tagOf rhs)

-- | Rewrite an expression: encode closure values, route residual
-- calls through the right apply_k dispatcher.
rewriteExpr :: Map Name Int -> (ClosureShape -> Maybe (Int, Int)) -> CExpr -> CExpr
rewriteExpr arities tagOf = goValue
  where
    goValue = \case
      CVar n
        | Just _ <- Map.lookup n arities,
          Just (_, tag) <- tagOf (n, 0) ->
            CCon tag []
      e@(CVar _) -> e
      CCall (CVar f) args
        | Just ar <- Map.lookup f arities,
          length args < ar,
          Just (_, tag) <- tagOf (f, length args) ->
            CCon tag (map goValue args)
      CCall (CVar n) args
        | Nothing <- Map.lookup n arities ->
            -- Residual call: callee is a parameter or arm-binder.
            -- Route through apply_k with the closure prepended.
            let args' = map goValue args
             in CCall (CVar (applyName (length args'))) (CVar n : args')
      CCall callee args ->
        CCall (goCallee callee) (map goValue args)
      CCon tag fs -> CCon tag (map goValue fs)
      CCase s alts -> CCase (goValue s) (map (\(t, vs, b) -> (t, vs, goValue b)) alts)
      CRow t v -> CRow t (goValue v)
      CRowCase s alts -> CRowCase (goValue s) (map (\(t, v, b) -> (t, v, goValue b)) alts)
      CLoop b -> CLoop (goValue b)
      CContinue xs -> CContinue (map goValue xs)
      e@(CString _) -> e
      e@(CIntLit _ _) -> e
      e@(CBuiltIn _) -> e

    -- Callee position: leave 'CVar' / 'CBuiltIn' direct, recurse
    -- through anything else as a value.
    goCallee = \case
      e@(CVar _) -> e
      e@(CBuiltIn _) -> e
      e -> goValue e

-- | Materialise an 'ApplyDispatcher' as a 'CFunDef'.
--
-- @
--   apply_k closure x_1 .. x_k = case closure of
--     0 (cap0_0 .. cap0_{m_0-1}) -> helper_0 cap0_0 .. cap0_{m_0-1} x_1 .. x_k
--     ...
-- @
dispatcherDecl :: ApplyDispatcher -> CDecl
dispatcherDecl ad =
  let k :: Int
      k = adRemainingArity ad
      closureParam :: Name
      closureParam = "$cl"
      argParams :: [Name]
      argParams = ["$arg" <> show i | i <- [0 .. k - 1]]
      params :: [Name]
      params = closureParam : argParams
      arms :: [(Int, [Name], CExpr)]
      arms =
        [ ( tag,
            captureNames,
            CCall (CVar helper) (map CVar (captureNames <> argParams))
          )
        | (tag, (helper, captureCount)) <- zip [0 ..] (adShapes ad),
          let captureNames :: [Name]
              captureNames = ["$cap" <> show tag <> "_" <> show i | i <- [0 .. captureCount - 1]]
        ]
   in CFunDef (applyName k) params (CCase (CVar closureParam) arms)

-- | Canonical name of the @apply_k@ dispatcher.
applyName :: Int -> Name
applyName k = "$apply" <> show k
