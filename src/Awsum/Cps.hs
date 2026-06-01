-- | CPS + defunctionalization pass for non-tail self-recursion.
--
-- Eliminates non-tail self-recursive calls so the system stack no
-- longer grows with recursion depth. The rewrite:
--
-- @
-- f args = body                                                 -- body buries a non-tail self-call
-- @
--
-- becomes the triple:
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
-- @f_cps@ and @f_apply@ are self-tail-recursive, so 'Awsum.Tco' folds
-- both into 'CLoop' \/ 'CContinue'. The "stack" for the old non-tail
-- recursion lives in the @K@ chain on the heap — one boxed
-- @[tag, parent_k, captured..]@ cell per non-tail call, like any other
-- ADT on every backend.
--
-- Non-tail self-calls are handled in /any/ non-tail position — @CCon@
-- field, @CCall@ argument, 'CCase' scrutinee. The transformer walks
-- left-to-right; at each non-tail self-call it allocates a fresh @K_i@
-- whose @apply@ handler rebuilds the surrounding expression with the
-- received value substituted at the call position. Multiple self-calls
-- in one expression chain naturally: each gets its own @K_i@, and an
-- earlier @K_i@'s apply can tail-call @f_cps@ with a later @K_j@.
--
-- The same defunctionalization primitive drives 'Awsum.Scc' (mutual
-- recursion via SCC-merge): merge SCCs into one self-recursive
-- function with a "function tag", then this pass picks up any
-- resulting non-tail self-calls.
--
-- The current continuation is always named @$k@: second parameter of
-- @$cps$f@, first of @$apply$f@, and each @K_i@ arm rebinds its
-- captured parent-k back to @$k@ (Core-level shadowing). Awsum's
-- no-shadowing rule is a typechecker concern; post-elaboration Core
-- is exempt.
module Awsum.Cps (cpsProgram) where

import Awsum.CallGraph (hasNonTailSelfCall)
import Awsum.Core
import Awsum.Syntax (Name)
import Data.Set qualified as Set
import Relude

-- | Run over every top-level declaration. Functions with at least one
-- non-tail self-call get replaced by the @(wrapper, $cps$f, $apply$f)@
-- trio; everything else passes through.
--
-- The K-sum-type's tags (@KTop@ and @K_i@) are allocated from a
-- program-wide supply seeded by 'nextFreshConTag', so each CPS'd
-- function's continuations land in a tag range disjoint from every
-- other type — including other CPS'd functions' K-sum-types.
cpsProgram :: CoreProgram -> CoreProgram
cpsProgram prog@(CoreProgram ds) =
  let topLevelNames = Set.fromList (map declName ds)
      baseTag = nextFreshConTag prog
      (_, transformed) = mapAccumL (transformDecl topLevelNames) baseTag ds
   in CoreProgram (concat transformed)
  where
    declName (CFunDef n _ _) = n
    declName (CValDef n _) = n

transformDecl :: Set Name -> Int -> CDecl -> (Int, [CDecl])
transformDecl topLevel nextTag = \case
  CFunDef f params body
    | hasNonTailSelfCall f body ->
        let (decls, consumed) = cpsDefunc nextTag topLevel f params body
         in (nextTag + consumed, decls)
    | otherwise -> (nextTag, [CFunDef f params body])
  d@CValDef {} -> (nextTag, [d])

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
  CRow _ v -> freeVars v
  CRowCase s alts -> freeVars s <> foldMap rowArmFv alts
  CLoop b -> freeVars b
  CContinue xs -> foldMap freeVars xs
  CDrop _ n b -> Set.delete n (freeVars b)
  CReuse n _ fs -> Set.insert n (foldMap freeVars fs)
  where
    armFv (_, bound, body) = freeVars body `Set.difference` Set.fromList bound
    rowArmFv (_, bound, body) = freeVars body `Set.difference` Set.singleton bound

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
  { -- | Next K tag to allocate. The function's @KTop@ tag was
    -- consumed before this state was constructed (it sits at
    -- @baseTag@); 'cpsNextTag' starts at @baseTag + 1@.
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

-- | CPS-defunctionalize one top-level function with non-tail
-- self-recursion. Returns the generated decls and the number of K
-- tags consumed (always at least 1 for @KTop@; one extra per
-- non-tail self-call discovered in the body).
--
-- @baseTag@ is this function's allocation base in the program-wide
-- K-tag namespace: @KTop@ takes @baseTag@, each @K_i@ takes
-- @baseTag + i@ for @i = 1, 2, …@.
cpsDefunc :: Int -> Set Name -> Name -> [Name] -> CExpr -> ([CDecl], Int)
cpsDefunc baseTag topLevel f params body =
  let cpsName, applyName, kParam, xParam :: Name
      cpsName = "$cps$" <> f
      applyName = "$apply$" <> f
      kParam = "$k"
      xParam = "$x"
      kTopTag = baseTag
      -- Generated names are globally accessible top-level functions;
      -- adding them to the "skip" set keeps them out of 'K_i' captures.
      topLevel' = topLevel <> Set.fromList [cpsName, applyName]
      initial = CpsState {cpsNextTag = baseTag + 1, cpsNextVarId = 0, cpsCons = []}
      env = CpsEnv {cpsSelfF = f, cpsName = cpsName, cpsApplyName = applyName, cpsKName = kParam, cpsTopLevel = topLevel'}
      (cpsBody, finalState) = runState (goTail env body) initial
      kcons = reverse (cpsCons finalState)
      applyBody = genApplyBody kTopTag kParam xParam kcons
      consumed = cpsNextTag finalState - baseTag
   in ( [ CFunDef f params (CCall (CVar cpsName) (map CVar params ++ [CCon kTopTag []])),
          CFunDef cpsName (params ++ [kParam]) cpsBody,
          CFunDef applyName [kParam, xParam] applyBody
        ],
        consumed
      )

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
      -- Tail row-case (structural sum): same shape as the nominal 'CCase'
      -- above — scrutinee non-tail, each arm body in tail position. Without
      -- this arm a tail-position row-case falls to the 'other' catch-all,
      -- which wraps the whole case (self-call and all) in 'applyK' and leaves
      -- a buried non-tail self-call un-CPS'd.
      CRowCase scrut alts ->
        goNonTail env scrut $ \scrutVal -> do
          alts' <- forM alts $ \(t, v, b) -> do
            b' <- goTail env b
            pure (t, v, b')
          pure (CRowCase scrutVal alts')
      -- Tail general call (non-self).
      CCall callee args ->
        goArgs env args $ \argVals ->
          pure (applyK env (CCall callee argVals))
      -- Tail constructor.
      CCon tag fields ->
        goArgs env fields $ \fieldVals ->
          pure (applyK env (CCon tag fieldVals))
      -- Tail row injection: the injected value is the only sub-expression,
      -- like a one-field 'CCon' — evaluate it non-tail so a buried self-call
      -- is CPS'd, then apply the continuation to the tagged value. Identical
      -- to the 'other' catch-all when the value harbours no self-call.
      CRow tag v ->
        goNonTail env v $ \vVal ->
          pure (applyK env (CRow tag vVal))
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
  -- Row-tagged value: same shape as a one-field 'CCon' from this
  -- pass's perspective — the inner value is the only sub-expression
  -- that might harbour self-calls.
  CRow tag v ->
    goNonTail env v $ \vVal ->
      kont (CRow tag vVal)
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
  CRowCase scrut alts ->
    goNonTail env scrut $ \scrutVal -> do
      alts' <- forM alts $ \(t, v, b) -> do
        b' <- goNonTail env b kont
        pure (t, v, b')
      pure (CRowCase scrutVal alts')
  -- 'CLoop' / 'CContinue' are produced by 'Awsum.Tco' /after/ this
  -- pass, so seeing them here would be a pipeline bug.
  CLoop _ ->
    error "Awsum.Cps: CLoop reached goNonTail — Cps must run before Tco"
  CContinue _ ->
    error "Awsum.Cps: CContinue reached goNonTail — Cps must run before Tco"
  -- 'CDrop' is produced by 'Awsum.Lifetime.insertDrops' /after/ Tco,
  -- so seeing it here would also be a pipeline bug.
  CDrop {} ->
    error "Awsum.Cps: CDrop reached goNonTail — Cps must run before insertDrops"
  -- 'CReuse' is produced by 'Awsum.Reuse.insertReuse' /after/
  -- insertDrops (which is after Tco, which is after Cps), so seeing
  -- it here would also be a pipeline bug.
  CReuse {} ->
    error "Awsum.Cps: CReuse reached goNonTail — Cps must run before insertReuse"

-- | Build the body of @$apply$f@.
--
-- @
--   case $k of
--     kTopTag               -> $x                                 -- KTop
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
genApplyBody :: Int -> Name -> Name -> [KCon] -> CExpr
genApplyBody kTopTag kParam xParam kcons =
  CCase (CVar kParam) (topArm : map kconArm kcons)
  where
    topArm = (kTopTag, [], CVar xParam)

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
      CRow t v -> CRow t (go v)
      CRowCase s alts -> CRowCase (go s) (map goRowAlt alts)
      CLoop b -> CLoop (go b)
      CContinue xs -> CContinue (map go xs)
      CDrop k n b
        | n == from -> CDrop k n b -- the drop kills 'from'; stop descending
        | otherwise -> CDrop k n (go b)
      CReuse n t fs
        | n == from -> CReuse to t (map go fs)
        | otherwise -> CReuse n t (map go fs)

    goAlt (t, vs, b)
      | from `elem` vs = (t, vs, b) -- shadowed; don't rename further in
      | otherwise = (t, vs, go b)

    goRowAlt (t, v, b)
      | v == from = (t, v, b) -- shadowed
      | otherwise = (t, v, go b)
