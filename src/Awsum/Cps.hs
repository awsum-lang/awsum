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
      -- above — scrutinee non-tail, each arm body in tail position, so a buried
      -- self-call in an arm is CPS'd instead of being wrapped whole in 'applyK'
      -- with the self-call left un-CPS'd.
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
      -- is CPS'd, then apply the continuation to the tagged value.
      CRow tag v ->
        goNonTail env v $ \vVal ->
          pure (applyK env (CRow tag vVal))
      -- Tail trivial leaves: hand the value straight to the continuation.
      e@(CVar _) -> pure (applyK env e)
      e@(CString _) -> pure (applyK env e)
      e@(CIntLit _ _) -> pure (applyK env e)
      e@(CBuiltIn _) -> pure (applyK env e)
      -- Impossible in Cps's input: every node below is minted by a later pass
      -- (see 'goNonTail'). Enumerated so a catch-all can't silently wrap one in
      -- 'applyK' and bury a self-call sitting in its tail sub-position.
      CLoop _ -> error "Awsum.Cps: CLoop reached goTail — Cps must run before Tco"
      CContinue _ -> error "Awsum.Cps: CContinue reached goTail — Cps must run before Tco"
      CDrop {} -> error "Awsum.Cps: CDrop reached goTail — Cps must run before insertDrops"
      CReuse {} -> error "Awsum.Cps: CReuse reached goTail — Cps must run before insertReuse"
      CLet {} -> error "Awsum.Cps: CLet reached goTail — Cps must run before Simplify"
      CProj {} -> error "Awsum.Cps: CProj reached goTail — Cps must run before Simplify"
      CJoin {} -> error "Awsum.Cps: CJoin reached goTail — Cps must run before Simplify"
      CJump {} -> error "Awsum.Cps: CJump reached goTail — Cps must run before Simplify"

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
  -- Every constructor below is minted by a /later/ pass, so reaching it in
  -- Cps's input is a pipeline bug. Enumerated (no catch-all) so a future
  -- 'CExpr' node surfaces as an incomplete-pattern failure, not a silent slip.
  --
  -- 'CLoop' / 'CContinue' are produced by 'Awsum.Tco' /after/ this pass.
  CLoop _ ->
    error "Awsum.Cps: CLoop reached goNonTail — Cps must run before Tco"
  CContinue _ ->
    error "Awsum.Cps: CContinue reached goNonTail — Cps must run before Tco"
  -- 'CDrop' is produced by 'Awsum.Lifetime.insertDrops' /after/ Tco.
  CDrop {} ->
    error "Awsum.Cps: CDrop reached goNonTail — Cps must run before insertDrops"
  -- 'CReuse' is produced by 'Awsum.Reuse.insertReuse' /after/ insertDrops.
  CReuse {} ->
    error "Awsum.Cps: CReuse reached goNonTail — Cps must run before insertReuse"
  -- 'CLet' / 'CProj' / 'CJoin' / 'CJump' are minted by 'Awsum.Simplify' /after/ Tco.
  CLet {} ->
    error "Awsum.Cps: CLet reached goNonTail — Cps must run before Simplify"
  CProj {} ->
    error "Awsum.Cps: CProj reached goNonTail — Cps must run before Simplify"
  CJoin {} ->
    error "Awsum.Cps: CJoin reached goNonTail — Cps must run before Simplify"
  CJump {} ->
    error "Awsum.Cps: CJump reached goNonTail — Cps must run before Simplify"

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
          -- Two renames: 'kconReceivedVar' → $x (received value lives in
          -- the apply's second parameter), and kParam ($k) → pkName (parent
          -- continuation lives in the arm binder). 'Awsum.Core.renameVar'
          -- is fresh-target, so folding the two doesn't capture.
          renamed =
            renameVar kParam pkName
              $ renameVar (kconReceivedVar kcon) xParam (kconApplyBody kcon)
       in (kconTag kcon, binders, renamed)
