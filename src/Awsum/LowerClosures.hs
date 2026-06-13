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
-- to @CCon shapeTag captures@. Each residual call @CCall callee args@
-- whose @callee@ is not a direct top-level fn or built-in — a binder,
-- or a value computed by over-application — is rewritten to
-- @CCall (CVar (apply_k)) (callee : args)@.
--
-- Tags are per-shape: every closure shape @(helper, captureCount)@ has
-- one globally-unique tag used wherever that closure is built (static
-- site or grown at runtime) and matched (any dispatcher it flows
-- through). Allocated from 'nextFreshConTag' in @(remaining, helper,
-- captureCount)@ order, which matches the prior per-arity allocation —
-- a program whose shape set is unchanged keeps its tags.
--
-- ## Generalised apply (saturate + grow)
--
-- A closure of shape @(helper, c)@ has remaining arity
-- @r = arity helper - c@. The language requires every top-level
-- 'CFunDef' to bind all its arrow-arity parameters, so @r@ is the
-- closure's true arrow-remaining and a well-typed application supplies
-- @k <= r@ arguments — over-application of a closure value (@k > r@)
-- cannot occur. Dispatcher @apply_k@ therefore handles two cases per
-- shape with @r >= k@:
--
-- @
--   apply_k cl x_1 .. x_k = case cl of
--     tag (cap_0 .. cap_{c-1}) -> helper cap_0 .. cap_{c-1} x_1 .. x_k  -- r == k: saturate
--     tag (cap_0 .. cap_{c-1}) -> growTag (cap_0 .. cap_{c-1} x_1 .. x_k) -- r >  k: grow
-- @
--
-- The grow arm builds a /larger/ closure @(helper, c+k)@ at runtime —
-- the defunctionalised equivalent of an STG @PAP@ — instead of calling
-- @helper@. The shape set is closed under growth ('closeUnderGrow') so
-- every grow target has a tag.
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
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Relude

-- | A closure's identity: which top-level helper, with how many of
-- its parameters already captured. Two closures with the same shape
-- share a tag.
type ClosureShape = (Name, Int)

-- | Top-level entry. Returns a Core program with every residual
-- function value replaced by a tagged 'CCon' and every residual call
-- routed through an @apply_k@ dispatcher; the dispatchers are
-- appended at the end. Shape tags are allocated from a program-wide
-- supply seeded by 'nextFreshConTag' so they don't collide with any
-- nominal-constructor tag.
lowerClosuresProgram :: CoreProgram -> CoreProgram
lowerClosuresProgram prog@(CoreProgram decls) =
  let arities = Map.fromList [(n, length args) | CFunDef n args _ <- decls]
      observed = foldMap (declShapes arities) decls
      -- Every arity at which a closure value is applied; each needs an
      -- @apply_k@ dispatcher. Seeds 'closeUnderGrow' (which @k@s can
      -- grow a closure) and decides which dispatchers to emit.
      applyArities = collectResidualArities arities decls
      shapes = closeUnderGrow arities applyArities observed
      shapeTag = assignTags (nextFreshConTag prog) arities shapes
      rewritten = map (rewriteDecl arities shapeTag) decls
      dispatchers =
        map (dispatcherDecl arities shapeTag shapes) (Set.toAscList applyArities)
   in CoreProgram (rewritten <> dispatchers)

-- | Remaining (uncaptured) arity of a closure shape. The language
-- requires every top-level 'CFunDef' to bind all its arrow-arity
-- parameters, so this equals the closure's true arrow-remaining and a
-- well-typed application never supplies more than @r@ arguments.
remainingArity :: Map Name Int -> ClosureShape -> Int
remainingArity arities (helper, captureCount) =
  maybe 0 (subtract captureCount) (Map.lookup helper arities)

-- | Close a shape set under /growth/: a closure @(h, c)@ applied to
-- fewer arguments than its remaining arity (@k < r@) yields a larger
-- closure @(h, c+k)@ built at runtime by the @apply_k@ dispatcher.
-- Gated by the residual-call arities actually present, so a grown
-- shape is only minted when some call site could produce it. Iterates
-- to a fixpoint because a grown closure can itself be grown.
closeUnderGrow :: Map Name Int -> Set Int -> Set ClosureShape -> Set ClosureShape
closeUnderGrow arities applyArities = go
  where
    go shapes =
      let shapes' = shapes <> foldMap grow1 (Set.toList shapes)
       in if Set.size shapes' == Set.size shapes then shapes else go shapes'
    grow1 s@(helper, captureCount) =
      let r = remainingArity arities s
       in Set.fromList
            [ (helper, captureCount + k)
            | k <- Set.toList applyArities,
              k >= 1,
              k < r
            ]

-- | One globally-unique tag per closure shape, allocated from a supply
-- seeded by 'nextFreshConTag' so they never collide with a
-- nominal-constructor tag. Order — @(remaining, helper, captureCount)@
-- — matches the previous per-arity bucket allocation, so a program
-- whose shape set is unchanged keeps its tags.
assignTags :: Int -> Map Name Int -> Set ClosureShape -> Map ClosureShape Int
assignTags baseTag arities shapes =
  Map.fromList (zip ordered [baseTag ..])
  where
    ordered = sortOn (\s@(helper, captureCount) -> (remainingArity arities s, helper, captureCount)) (Set.toList shapes)

-- | Closure shapes referenced inside one declaration. Walks every
-- value-position sub-expression looking for bare references and
-- partial applications of top-level functions.
declShapes :: Map Name Int -> CDecl -> Set ClosureShape
declShapes arities = \case
  CFunDef _ _ body -> exprShapes arities body
  CValDef _ rhs -> exprShapes arities rhs

-- | True iff a 'CCall' with this callee is a /direct/ call — a known
-- top-level function or a built-in — rather than an application of a
-- closure value that must route through an @apply_k@ dispatcher.
isDirectCallee :: Map Name Int -> CExpr -> Bool
isDirectCallee arities = \case
  CVar f -> Map.member f arities
  CBuiltIn _ -> True
  _ -> False

-- | Every arity at which a closure value is applied — calls whose
-- callee is not a direct top-level function or built-in: a residual
-- binder (@CCall (CVar n) args@, @n@ not top-level) or a value
-- computed by over-application (@CCall (CCall …) args@). Each such
-- site routes through @apply_k@. Independent of closure-flow: the
-- dispatcher must exist even when no closure of the right remaining
-- arity currently flows through it (e.g. the 'IOGetArgs' arm of
-- 'runIO' in a program that never constructs 'IOGetArgs').
collectResidualArities :: Map Name Int -> [CDecl] -> Set Int
collectResidualArities arities = foldMap declArities
  where
    declArities = \case
      CFunDef _ _ body -> exprArities body
      CValDef _ rhs -> exprArities rhs

    exprArities = \case
      CCall callee args ->
        (if isDirectCallee arities callee then mempty else Set.singleton (length args))
          <> exprArities callee
          <> foldMap exprArities args
      CCon _ fs -> foldMap exprArities fs
      CCase s alts -> exprArities s <> foldMap (\(_, _, b) -> exprArities b) alts
      CRow _ v -> exprArities v
      CRowCase s alts -> exprArities s <> foldMap (\(_, _, b) -> exprArities b) alts
      CLoop b -> exprArities b
      CContinue xs -> foldMap exprArities xs
      CDrop _ _ b -> exprArities b
      CReuse _ _ _ fs -> foldMap exprArities fs
      CLet _ rhs body -> exprArities rhs <> exprArities body
      CJoin {} -> error "LowerClosures: CJoin is minted by Awsum.Simplify, which runs later"
      CJump {} -> error "LowerClosures: CJump is minted by Awsum.Simplify, which runs later"
      CProj _ _ -> mempty
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
      CDrop _ _ b -> goValue b
      CReuse _ _ _ fs -> foldMap goValue fs
      CLet _ rhs body -> goValue rhs <> goValue body
      CJoin {} -> error "LowerClosures: CJoin is minted by Awsum.Simplify, which runs later"
      CJump {} -> error "LowerClosures: CJump is minted by Awsum.Simplify, which runs later"
      CProj _ _ -> mempty
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

-- | Apply the rewrite to one declaration's body.
rewriteDecl :: Map Name Int -> Map ClosureShape Int -> CDecl -> CDecl
rewriteDecl arities shapeTag = \case
  CFunDef n args body -> CFunDef n args (rewriteExpr arities shapeTag body)
  CValDef n rhs -> CValDef n (rewriteExpr arities shapeTag rhs)

-- | Rewrite an expression: encode closure values as tagged 'CCon's and
-- route every residual application through the right @apply_k@
-- dispatcher.
rewriteExpr :: Map Name Int -> Map ClosureShape Int -> CExpr -> CExpr
rewriteExpr arities shapeTag = goValue
  where
    goValue = \case
      -- Bare top-level reference in value position: a zero-capture closure.
      CVar n
        | Just tag <- Map.lookup (n, 0) shapeTag -> CCon tag []
      e@(CVar _) -> e
      -- Partial application in value position: an N-capture closure.
      CCall (CVar f) args
        | Just ar <- Map.lookup f arities,
          length args < ar,
          Just tag <- Map.lookup (f, length args) shapeTag ->
            CCon tag (map goValue args)
      -- Saturated direct call to a top-level function — already first-order.
      CCall (CVar f) args
        | Map.member f arities ->
            CCall (CVar f) (map goValue args)
      -- Direct built-in call.
      CCall (CBuiltIn b) args ->
        CCall (CBuiltIn b) (map goValue args)
      -- Residual application: the callee is a closure value (a binder,
      -- or a value computed by over-application). Route through
      -- @apply_k@ with the closure prepended.
      CCall callee args ->
        CCall (CVar (applyName (length args))) (goValue callee : map goValue args)
      CCon tag fs -> CCon tag (map goValue fs)
      CCase s alts -> CCase (goValue s) (map (\(t, vs, b) -> (t, vs, goValue b)) alts)
      CRow t v -> CRow t (goValue v)
      CRowCase s alts -> CRowCase (goValue s) (map (\(t, v, b) -> (t, v, goValue b)) alts)
      CLoop b -> CLoop (goValue b)
      CContinue xs -> CContinue (map goValue xs)
      CDrop k n b -> CDrop k n (goValue b)
      CReuse rm n tag fs -> CReuse rm n tag (map goValue fs)
      CLet x rhs body -> CLet x (goValue rhs) (goValue body)
      CJoin {} -> error "LowerClosures: CJoin is minted by Awsum.Simplify, which runs later"
      CJump {} -> error "LowerClosures: CJump is minted by Awsum.Simplify, which runs later"
      e@(CProj _ _) -> e
      e@(CString _) -> e
      e@(CIntLit _ _) -> e
      e@(CBuiltIn _) -> e

-- | Materialise the @apply_k@ dispatcher: one arm per closure shape
-- whose remaining arity is at least @k@. A shape with @r == k@
-- saturates its helper; a shape with @r > k@ grows into the larger
-- closure @(helper, c + k)@ — always present in the shape set because
-- 'closeUnderGrow' added it for this @k@.
--
-- @
--   apply_k cl x_1 .. x_k = case cl of
--     tag (cap_0 .. cap_{c-1}) -> helper cap_0 .. cap_{c-1} x_1 .. x_k  -- r == k
--     tag (cap_0 .. cap_{c-1}) -> CCon growTag (cap_0 .. cap_{c-1} x_1 .. x_k)  -- r > k
-- @
dispatcherDecl :: Map Name Int -> Map ClosureShape Int -> Set ClosureShape -> Int -> CDecl
dispatcherDecl arities shapeTag shapes k =
  let closureParam :: Name
      closureParam = "$cl"
      argParams :: [Name]
      argParams = ["$arg" <> show i | i <- [0 .. k - 1]]
      params :: [Name]
      params = closureParam : argParams
      armShapes :: [ClosureShape]
      armShapes =
        sortOn
          (`Map.lookup` shapeTag)
          [s | s <- Set.toList shapes, remainingArity arities s >= k]
      arms :: [(Int, [Name], CExpr)]
      arms =
        [ (tag, captureNames, body)
        | s@(helper, captureCount) <- armShapes,
          Just tag <- [Map.lookup s shapeTag],
          let captureNames :: [Name]
              captureNames = ["$cap" <> show tag <> "_" <> show i | i <- [0 .. captureCount - 1]]
              allArgs :: [CExpr]
              allArgs = map CVar (captureNames <> argParams)
              body :: CExpr
              body
                | remainingArity arities s == k = CCall (CVar helper) allArgs
                | otherwise = CCon (shapeTag Map.! (helper, captureCount + k)) allArgs
        ]
   in CFunDef (applyName k) params (CCase (CVar closureParam) arms)

-- | Canonical name of the @apply_k@ dispatcher.
applyName :: Int -> Name
applyName k = "$apply" <> show k
