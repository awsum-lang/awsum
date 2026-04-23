-- | CPS + defunctionalization pass for non-tail self-recursion.
--
-- Core-to-Core transformation that eliminates non-tail self-recursive
-- calls so the system stack no longer grows with recursion depth. The
-- shape of the rewrite, one function at a time:
--
-- @
-- f args = body                                                 -- body buries a non-tail self-call
-- @
--
-- is rewritten to the triple:
--
-- @
-- f args             = f_cps args KTop                          -- wrapper
-- f_cps args k       = <body, CPS'd; every non-tail self-call   -- self-tail via K chain
--                       becomes f_cps newArgs (K_i k caps..)>
-- f_apply k x        = case k of                                 -- self-tail, dispatch over K
--                        KTop                   -> x
--                        K_i (k_parent, caps..) -> <post-call   -- caps closed over
--                                                    continuation
--                                                    w/ 'received'
--                                                    = x>
-- @
--
-- After the pass, @f_cps@ and @f_apply@ are self-tail-recursive, so the
-- existing 'Awsum.Tco' pass folds them both into 'CLoop' \/ 'CContinue'.
-- The "stack" for the old non-tail recursion lives in the @K@ chain on
-- the heap (one boxed @[tag, parent_k, captured..]@ cell per non-tail
-- call, like any other ADT on every backend).
--
-- Non-tail self-calls are handled in /any/ non-tail position — @CCon@
-- field, @CCall@ argument, scrutinee of an arbitrary 'CCase'. The
-- transformer walks in evaluation order (left to right), and at each
-- non-tail self-call site generates a fresh @K_i@ whose @apply@
-- handler rebuilds the surrounding expression with the received value
-- substituted at the call position. Multiple self-calls in one
-- expression chain naturally: each generates its own @K_i@, and the
-- @apply@ handler of an earlier @K_i@ can itself emit a tail call to
-- @f_cps@ with a later @K_j@.
--
-- The same defunctionalization primitive drives 'Awsum.Scc' (mutual
-- recursion via SCC-merge): merge SCCs into one self-recursive
-- function with a "function tag", then this pass picks up any
-- resulting non-tail self-calls.
--
-- **Canonical name for the current continuation.** Throughout the
-- generated code the continuation variable is named @$k@: it is the
-- second parameter of @$cps$f@, it is the first parameter of
-- @$apply$f@, and each @K_i@ arm in @$apply$f@ rebinds its captured
-- parent-k back to @$k@ (Core-level shadowing). Every CPS-built body
-- references @$k@ freely, and in each scope it resolves to the right
-- binder. Awsum's surface-level no-shadowing rule is a typechecker
-- concern and doesn't apply to the post-elaboration Core we generate.
module Awsum.Cps (cpsProgram) where

import Awsum.Core
import Awsum.Syntax (Name)
import Data.Set qualified as Set
import Relude

-- | Run the pass over every top-level declaration. Functions with at
-- least one non-tail self-call get replaced by the @(wrapper, $cps$f,

-- $apply$f)@ trio; everything else passes through untouched.

cpsProgram :: CoreProgram -> CoreProgram
cpsProgram (CoreProgram ds) =
  let topLevelNames = Set.fromList (map declName ds)
   in CoreProgram (concatMap (transformDecl topLevelNames) ds)
  where
    declName (CFunDef n _ _) = n
    declName (CValDef n _) = n

transformDecl :: Set Name -> CDecl -> [CDecl]
transformDecl topLevel = \case
  CFunDef f params body
    | hasNonTailSelfCall f body ->
        cpsDefunc topLevel f params body
    | otherwise -> [CFunDef f params body]
  d@CValDef {} -> [d]

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
      CCon _ fs -> any inNonTail fs
      CLoop b -> inNonTail b
      CContinue xs -> any inNonTail xs
      _ -> False

-- | Free variables of a Core expression. Arm pattern binders scope over
-- their body only and are subtracted.
freeVars :: CExpr -> Set Name
freeVars = \case
  CVar n -> Set.singleton n
  CString _ -> mempty
  CIntLit _ _ -> mempty
  CBuiltIn _ -> mempty
  CCall c xs -> freeVars c <> foldMap freeVars xs
  CCon _ fs -> foldMap freeVars fs
  CCase s alts -> freeVars s <> foldMap armFv alts
  CLoop b -> freeVars b
  CContinue xs -> foldMap freeVars xs
  where
    armFv (_, bound, body) = freeVars body `Set.difference` Set.fromList bound

-- | One defunctionalized continuation.
data KCon = KCon
  { kconTag :: !Int,
    -- | Outer-scope names this @K@ instance carries forward (in the
    -- order they appear as fields). Emitted both on the build site
    -- (@CCon tag (k : captured)@) and destructured in the apply arm.
    kconCaptured :: ![Name],
    -- | Name of the "received" value in the apply body — the value
    -- that comes back from the recursive call and replaces the
    -- original call site inside 'kconApplyBody'.
    kconReceivedVar :: !Name,
    -- | CPS'd post-call continuation. References @$k@ for the parent
    -- continuation (bound by the apply arm), 'kconReceivedVar' for
    -- the call's result, and free names in 'kconCaptured'.
    kconApplyBody :: !CExpr
  }

data CpsState = CpsState
  { -- | Next K tag to allocate; tag 0 is reserved for @KTop@.
    cpsNextTag :: !Int,
    -- | Fresh-name counter for received-value binders ($rcv_0, ...).
    cpsNextVarId :: !Int,
    -- | Allocated K constructors in reverse allocation order.
    cpsCons :: ![KCon]
  }

type CpsM = State CpsState

freshReceivedName :: CpsM Name
freshReceivedName = do
  n <- gets cpsNextVarId
  modify' (\s -> s {cpsNextVarId = n + 1})
  pure ("$rcv_" <> show n)

freshTag :: CpsM Int
freshTag = do
  t <- gets cpsNextTag
  modify' (\s -> s {cpsNextTag = t + 1})
  pure t

registerK :: KCon -> CpsM ()
registerK kc = modify' (\s -> s {cpsCons = kc : cpsCons s})

-- | CPS-defunctionalize one top-level function with non-tail self-recursion.
cpsDefunc :: Set Name -> Name -> [Name] -> CExpr -> [CDecl]
cpsDefunc topLevel f params body =
  let cpsName, applyName, kParam, xParam :: Name
      cpsName = "$cps$" <> f
      applyName = "$apply$" <> f
      kParam = "$k"
      xParam = "$x"
      -- Generated names are globally accessible top-level functions;
      -- adding them to the "skip" set keeps them out of 'K_i' captures.
      topLevel' = topLevel <> Set.fromList [cpsName, applyName]
      initial = CpsState {cpsNextTag = 1, cpsNextVarId = 0, cpsCons = []}
      env = CpsEnv {cpsSelfF = f, cpsName = cpsName, cpsApplyName = applyName, cpsKName = kParam, cpsTopLevel = topLevel'}
      (cpsBody, finalState) = runState (goTail env body) initial
      kcons = reverse (cpsCons finalState)
      applyBody = genApplyBody kParam xParam kcons
   in [ CFunDef f params (CCall (CVar cpsName) (map CVar params ++ [CCon 0 []])),
        CFunDef cpsName (params ++ [kParam]) cpsBody,
        CFunDef applyName [kParam, xParam] applyBody
      ]

-- | Names and settings threaded through the transformer.
data CpsEnv = CpsEnv
  { cpsSelfF :: !Name,
    cpsName :: !Name,
    cpsApplyName :: !Name,
    -- | Canonical name of the current continuation. Always @$k@ in the
    -- generated code; kept as a field for clarity.
    cpsKName :: !Name,
    -- | Top-level names that should never be counted as @K_i@ captures
    -- (they're globally accessible).
    cpsTopLevel :: !(Set Name)
  }

-- | Transform an expression in tail position: its value flows to the
-- current continuation @$k@ via @$apply$f $k <value>@.
goTail :: CpsEnv -> CExpr -> CpsM CExpr
goTail env = go
  where
    go = \case
      -- Tail self-call: rewrite to '$cps$f newArgs $k'.
      CCall (CVar n) args
        | n == env.cpsSelfF ->
            goArgs env args $ \argVals ->
              pure (CCall (CVar env.cpsName) (argVals ++ [CVar env.cpsKName]))
      -- Tail case.
      CCase scrut alts ->
        goNonTail env scrut $ \scrutVal -> do
          alts' <- forM alts $ \(t, vs, b) -> do
            b' <- goTail env b
            pure (t, vs, b')
          pure (CCase scrutVal alts')
      -- Tail general call (non-self).
      CCall callee args ->
        goArgs env args $ \argVals ->
          pure (applyK env (CCall callee argVals))
      -- Tail constructor.
      CCon tag fields ->
        goArgs env fields $ \fieldVals ->
          pure (applyK env (CCon tag fieldVals))
      -- Tail trivial: pass straight to apply.
      other -> pure (applyK env other)

-- | Build @$apply$f $k e@.
applyK :: CpsEnv -> CExpr -> CExpr
applyK env e = CCall (CVar env.cpsApplyName) [CVar env.cpsKName, e]

-- | Process a list of sub-expressions left-to-right in non-tail
-- context, collecting each into a trivial value expression and handing
-- the full list to @kont@. When a self-call surfaces inside any one,
-- later arguments land inside the emitted K's apply body (the call to
-- @$cps$f@ with a K becomes terminal at that point).
goArgs :: CpsEnv -> [CExpr] -> ([CExpr] -> CpsM CExpr) -> CpsM CExpr
goArgs env = go []
  where
    go :: [CExpr] -> [CExpr] -> ([CExpr] -> CpsM CExpr) -> CpsM CExpr
    go acc [] kont = kont (reverse acc)
    go acc (e : es) kont =
      goNonTail env e $ \val -> go (val : acc) es kont

-- | Transform a single sub-expression in non-tail context. The @kont@
-- callback builds the /rest of the computation/: given a value
-- expression for @e@'s result, it returns the Core code that uses it.
--
-- If @e@ is trivial (variable, literal, constructor / call without
-- buried self-calls), we call @kont@ directly with the value. If @e@
-- harbours a self-call, we allocate a fresh @K_i@, stash the CPS'd
-- @kont (CVar receivedVar)@ as its apply-body, and emit a tail call to
-- @$cps$f@ with that K. Control does not come back to us after such a
-- call — the rest of the expression lives in @K_i@'s apply body.
goNonTail :: CpsEnv -> CExpr -> (CExpr -> CpsM CExpr) -> CpsM CExpr
goNonTail env expr kont = case expr of
  -- Trivial: pass through.
  CVar _ -> kont expr
  CString _ -> kont expr
  CIntLit _ _ -> kont expr
  CBuiltIn _ -> kont expr
  -- Non-self call: evaluate args in non-tail, then synchronous call.
  CCall (CVar n) args
    | n == env.cpsSelfF ->
        -- Non-tail self-call — the heart of the pass.
        goArgs env args $ \argVals -> do
          rcvName <- freshReceivedName
          tag <- freshTag
          postExpr <- kont (CVar rcvName)
          -- Capture every free var of postExpr that is (a) not the
          -- received value, (b) not the canonical continuation name
          -- (the arm rebinds that), (c) not a top-level name, (d) not
          -- a BuiltIn reference. Sorted for snapshot determinism.
          let captured =
                Set.toAscList
                  $ freeVars postExpr
                  `Set.difference` Set.fromList [rcvName, env.cpsKName]
                  `Set.difference` env.cpsTopLevel
          registerK
            KCon
              { kconTag = tag,
                kconCaptured = captured,
                kconReceivedVar = rcvName,
                kconApplyBody = postExpr
              }
          pure
            ( CCall
                (CVar env.cpsName)
                (argVals ++ [CCon tag (CVar env.cpsKName : map CVar captured)])
            )
  CCall callee args ->
    goArgs env args $ \argVals ->
      kont (CCall callee argVals)
  -- Non-self constructor: evaluate fields, construct, pass to kont.
  CCon tag fields ->
    goArgs env fields $ \fieldVals ->
      kont (CCon tag fieldVals)
  -- Non-tail case: scrut non-tail; each arm body non-tail feeds kont.
  -- @kont@ is structurally duplicated across arms, but each invocation
  -- builds its own Core expression — if one arm's kont emits a K, the
  -- other arms still see the same logical continuation (they rebuild
  -- their own view of it).
  CCase scrut alts ->
    goNonTail env scrut $ \scrutVal -> do
      alts' <- forM alts $ \(t, vs, b) -> do
        b' <- goNonTail env b kont
        pure (t, vs, b')
      pure (CCase scrutVal alts')
  -- 'CLoop' / 'CContinue' are produced by 'Awsum.Tco' /after/ this
  -- pass, so seeing them here would be a pipeline bug.
  CLoop _ ->
    error "Awsum.Cps: CLoop reached goNonTail — Cps must run before Tco"
  CContinue _ ->
    error "Awsum.Cps: CContinue reached goNonTail — Cps must run before Tco"

-- | Build the body of @$apply$f@.
--
-- @
--   case $k of
--     0                     -> $x                                 -- KTop
--     i ($pk_i, caps..)     -> <post-call continuation with $x as
--                                 rcv and $pk_i as the parent
--                                 continuation>
-- @
--
-- Each K_i arm destructures its captured parent continuation into a
-- fresh name @$pk_i@ (not @$k@): @$k@ is already the apply function's
-- parameter, and some backends (e.g. JS) emit arm binders as @const@
-- — a rebinding under the same name would break 'Awsum.Tco's loop-bottom
-- assignment to the parameter slot. We alpha-rename the post-call body
-- so every @$k@ reference flips to @$pk_i@, and similarly the received
-- variable becomes @$x@.
genApplyBody :: Name -> Name -> [KCon] -> CExpr
genApplyBody kParam xParam kcons =
  CCase (CVar kParam) (topArm : map kconArm kcons)
  where
    topArm = (0, [], CVar xParam)

    kconArm kcon =
      let pkName :: Name
          pkName = "$pk_" <> show (kconTag kcon)
          binders = pkName : kconCaptured kcon
          -- Two alpha-renames: 'kconReceivedVar' → $x (received value
          -- lives in the apply's second parameter), and kParam ($k)
          -- → pkName (parent continuation lives in the arm binder).
          renamed =
            alphaRename kParam pkName
              $ alphaRename (kconReceivedVar kcon) xParam (kconApplyBody kcon)
       in (kconTag kcon, binders, renamed)

-- | Replace every free occurrence of @from@ in @e@ with @to@. Arm
-- binders shadow, so don't descend under one that reintroduces @from@.
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
      | from `elem` vs = (t, vs, b) -- shadowed; don't rename further in
      | otherwise = (t, vs, go b)
