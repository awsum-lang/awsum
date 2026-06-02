-- | Defunctionalisation pass.
--
-- Eliminates first-class function values at call sites where the
-- closure can be resolved statically: each such HOF call has its
-- @fn@-typed slot replaced with a first-order specialisation whose
-- parameter list adds the closure's captures up front. Residual
-- closures that flow through positions this pass cannot specialise
-- (stored in constructor fields, passed through case-arm-binders,
-- captured into partial applications inside non-statically-resolvable
-- HOFs) are handled by the next pass, 'Awsum.LowerClosures'. After
-- the two passes run in sequence, no first-class function value
-- remains in any reachable position.
--
-- ## What is a closure?
--
-- After 'liftLambda' in 'Awsum.ElaborateLower' has lifted every
-- surface 'ELam' to a top-level helper, a function-typed expression
-- in Core has one of three shapes:
--
--   * @CVar f@ where @f@ is a top-level 'CFunDef' — bare reference,
--     no captures.
--   * @CCall (CVar f) [a_0 .. a_{k-1}]@ where @f@ has arity @n@ and
--     @k < n@ — partial application bound to the first @k@
--     parameters. Capture exprs are evaluated at the construction site.
--   * @CVar p@ where @p@ is a function-typed parameter of an
--     enclosing function — a "pass-through" closure whose semantics
--     come from the surrounding specialisation context.
--
-- ## Specialisation
--
-- For each call site @f x_0 ... x_{n-1}@ whose callee @f@ is a
-- top-level function with one or more function-typed parameters, we
-- generate a specialised copy of @f@:
--
--   * Each function-typed parameter slot is /removed/.
--   * The closure's captures are /appended/ to the parameter list
--     (so they flow as ordinary first-order values).
--   * Inside the body, every @CCall (CVar p) args@ where @p@ was a
--     function-typed parameter is rewritten as
--     @CCall (CVar helper) (captures ++ args)@. Pass-through HOFs
--     (@applyTwice f x = applyOnce f (applyOnce f x)@) trigger
--     recursive specialisations sharing the same memoised name.
--
-- Specialisations are memoised by structural shape —
-- @(HOF, [(slot, helper, capture-count)])@ — so call sites with
-- structurally identical closures share one specialised function;
-- only the runtime values in the capture parameters differ.
-- Self-recursive HOFs are safe because the memo entry is recorded
-- /before/ the body is walked, so the recursive call resolves to the
-- in-flight name.
--
-- ## Not handled here (deferred to 'Awsum.LowerClosures')
--
--   * Function values stored in constructor fields (@type FnBox =
--     FnBox (Int32 -> Int32)@). 'asClosure' returns 'Nothing' on
--     such a 'CCon' field, so the closure survives this pass.
--   * Function values flowing through case-arm-binders and partial
--     applications inside non-statically-resolvable HOFs.
--
-- 'Awsum.LowerClosures' encodes each surviving closure as a tagged
-- 'CCon' and routes every residual call through a per-arity @$applyN@
-- dispatcher, so by the end of the two passes nothing function-typed
-- remains in any reachable position.
--
-- ## Pipeline position
--
-- Between the post-lowering tree-shake and 'Awsum.LowerClosures'. Tree-shake
-- re-runs afterwards to drop the now-unreachable original HOFs.
module Awsum.Defunctionalize (defunctionalizeProgram) where

import Awsum.Core
import Awsum.Syntax (Name)
import Awsum.Typing (TypeError (..))
import Data.Map.Strict qualified as M
import Data.Set qualified as Set
import Relude

-- | A function value identified at a specific call site: the
--   underlying top-level helper, the captured-argument expressions
--   prefixing the helper's full argument list, and the helper's
--   total arity.
data Closure = Closure
  { closHelper :: !Name,
    closCaptures :: ![CExpr],
    closHelperArity :: !Int
  }
  deriving stock (Show, Eq)

-- | Structural shape of a closure. Two closures share a specialisation
--   when their shapes match — only the runtime values inside
--   'closCaptures' differ.
type ClosureShape = (Name, Int)

closureShape :: Closure -> ClosureShape
closureShape c = (closHelper c, length (closCaptures c))

-- | Memoisation key for a HOF specialisation. Records which
--   parameter slots were function-typed and the closure shape that
--   flowed into each.
data SpecKey = SpecKey
  { skHof :: !Name,
    skSlots :: ![(Int, ClosureShape)]
  }
  deriving stock (Show, Eq, Ord)

-- | Mapping from function-typed parameter names visible in the
--   enclosing specialised body to their resolved closures. The
--   capture expressions inside each 'Closure' are 'CVar' references
--   to the enclosing specialisation's own parameters, so they make
--   sense in that scope.
type SpecEnv = Map Name Closure

data SpecState = SpecState
  { ssMemo :: !(Map SpecKey Name),
    ssDecls :: !(Map Name CDecl),
    ssNewDecls :: ![CDecl],
    ssArities :: !(Map Name Int),
    ssFresh :: !Int
  }

type SpecM = StateT SpecState (Either TypeError)

freshSpecName :: Name -> SpecM Name
freshSpecName base = do
  s <- get
  put s {ssFresh = ssFresh s + 1}
  pure ("$df$" <> base <> "$" <> show (ssFresh s))

-- | If @e@ statically denotes a function value, return its closure.
--   Bare top-level 'CFunDef' references count as zero-capture
--   closures; partial applications of one count as N-capture
--   closures; pass-through references to function-typed parameters
--   are looked up in the enclosing 'SpecEnv'.
asClosure :: SpecEnv -> Map Name Int -> CExpr -> Maybe Closure
asClosure env arities = \case
  CVar n
    | Just c <- M.lookup n env -> Just c
    | Just ar <- M.lookup n arities -> Just (Closure n [] ar)
  CCall (CVar n) args
    | Just ar <- M.lookup n arities,
      length args < ar ->
        Just (Closure n args ar)
  _ -> Nothing

-- | Top-level entry point. Returns a Core program in which every
--   call site has been specialised for its statically-known closure;
--   no first-class function value remains in any reachable position.
defunctionalizeProgram :: CoreProgram -> Either TypeError CoreProgram
defunctionalizeProgram (CoreProgram decls) = do
  let arities = M.fromList [(n, length args) | CFunDef n args _ <- decls]
      declsMap = M.fromList [(declName d, d) | d <- decls]
      initial =
        SpecState
          { ssMemo = M.empty,
            ssDecls = declsMap,
            ssNewDecls = [],
            ssArities = arities,
            ssFresh = 0
          }
  (transformed, finalState) <- runStateT (traverse transformTopDecl decls) initial
  pure $ CoreProgram (transformed <> reverse (ssNewDecls finalState))
  where
    declName (CFunDef n _ _) = n
    declName (CValDef n _) = n

-- | Walk a top-level declaration with an empty 'SpecEnv'. Any HOF
--   call inside is processed; captures escape via newly-emitted
--   specialised decls accumulated in 'ssNewDecls'.
transformTopDecl :: CDecl -> SpecM CDecl
transformTopDecl = \case
  CFunDef n args body -> CFunDef n args <$> transformExpr M.empty body
  CValDef n rhs -> CValDef n <$> transformExpr M.empty rhs

-- | Walk a Core expression, specialising any HOF call encountered.
transformExpr :: SpecEnv -> CExpr -> SpecM CExpr
transformExpr env = go
  where
    go = \case
      e@(CVar _) -> pure e
      e@(CString _) -> pure e
      e@(CIntLit _ _) -> pure e
      e@(CBuiltIn _) -> pure e
      CCon t fs -> CCon t <$> traverse go fs
      CCase s alts -> do
        s' <- go s
        alts' <- traverse (\(t, vs, b) -> (t,vs,) <$> go b) alts
        pure (CCase s' alts')
      CRow t v -> CRow t <$> go v
      CRowCase s alts -> do
        s' <- go s
        alts' <- traverse (\(t, v, b) -> (t,v,) <$> go b) alts
        pure (CRowCase s' alts')
      CLoop b -> CLoop <$> go b
      CContinue xs -> CContinue <$> traverse go xs
      CDrop k n b -> CDrop k n <$> go b
      CReuse n t fs -> CReuse n t <$> traverse go fs
      CCall callee args -> transformCall env callee args

-- | Transform a 'CCall'. Three shapes matter:
--
--     * Callee is a function-typed parameter resolved via 'env' —
--       rewrite as @helper(captures ++ args)@ and recurse so any
--       inner HOF call is handled too.
--     * Callee is a known top-level function and one or more
--       arguments are statically function values — specialise the
--       callee for the closures flowing in.
--     * Otherwise — structural recursion on the arguments.
transformCall :: SpecEnv -> CExpr -> [CExpr] -> SpecM CExpr
transformCall env callee args = do
  arities <- gets ssArities
  case callee of
    CVar n | Just clos <- M.lookup n env -> do
      args' <- traverse (transformExpr env) args
      let fullArgs = closCaptures clos <> args'
      if closHelper clos == n
        then
          -- Self-closure: the combinator's slot-parameter name collided with
          -- the passed function's own name, so 'n' maps to a closure whose
          -- helper is 'n' itself. Recursing with the same 'env' would not
          -- terminate (M.lookup n env keeps yielding the same closure). Drop
          -- 'n' from env and re-resolve, so it dispatches as the top-level
          -- function it is (captures prepended) rather than looping.
          transformCall (M.delete n env) (CVar n) fullArgs
        else transformCall env (CVar (closHelper clos)) fullArgs
    CVar f | Just _ <- M.lookup f arities -> do
      let slotClosures =
            [ (i, c)
            | (i, arg) <- zip [0 ..] args,
              Just c <- [asClosure env arities arg]
            ]
      if null slotClosures
        then do
          args' <- traverse (transformExpr env) args
          pure (CCall (CVar f) args')
        else specializeAndCall env f args slotClosures
    _ -> do
      callee' <- transformExpr env callee
      args' <- traverse (transformExpr env) args
      pure (CCall callee' args')

-- | Look up or create a specialisation of @f@ for the given closure
--   shapes, then build the rewritten call site expression.
specializeAndCall ::
  SpecEnv ->
  Name ->
  [CExpr] ->
  [(Int, Closure)] ->
  SpecM CExpr
specializeAndCall env f origArgs slotClosures = do
  let key =
        SpecKey
          { skHof = f,
            skSlots = [(i, closureShape c) | (i, c) <- slotClosures]
          }
  memo <- gets ssMemo
  specName <- case M.lookup key memo of
    Just n -> pure n
    Nothing -> do
      n <- freshSpecName f
      modify (\s -> s {ssMemo = M.insert key n (ssMemo s)})
      generateSpec n f slotClosures
      pure n
  let slotIndices = Set.fromList (map fst slotClosures)
      keptArgs = [a | (i, a) <- zip [0 ..] origArgs, not (Set.member i slotIndices)]
      captureArgs = concatMap (closCaptures . snd) slotClosures
  keptArgs' <- traverse (transformExpr env) keptArgs
  captureArgs' <- traverse (transformExpr env) captureArgs
  pure (CCall (CVar specName) (keptArgs' <> captureArgs'))

-- | Materialise a specialised 'CFunDef'. The function-typed slot
--   parameters are replaced with one fresh parameter per capture,
--   and the body is walked with each removed slot bound to a
--   closure whose capture expressions reference those fresh
--   parameters.
generateSpec :: Name -> Name -> [(Int, Closure)] -> SpecM ()
generateSpec specName origName slotClosures = do
  declsMap <- gets ssDecls
  case M.lookup origName declsMap of
    Just (CFunDef _ origParams origBody) -> do
      let slotMap = M.fromList slotClosures
          slotIndices = Set.fromList (M.keys slotMap)
          keptParams =
            [ p
            | (i, p) <- zip [0 ..] origParams,
              not (Set.member i slotIndices)
            ]
          captureNamesPerSlot =
            [ (i, [specName <> "$cap" <> show i <> "$" <> show j | j <- [0 .. length (closCaptures clos) - 1]])
            | (i, clos) <- M.toAscList slotMap
            ]
          captureParams = concatMap snd captureNamesPerSlot
          newParams = keptParams <> captureParams
          paramByIndex = M.fromList (zip [0 ..] origParams)
          slotEnv =
            M.fromList
              [ ( paramByIndex M.! i,
                  Closure (closHelper clos) (map CVar capNames) (closHelperArity clos)
                )
              | (i, capNames) <- captureNamesPerSlot,
                let clos = slotMap M.! i
              ]
      newBody <- transformExpr slotEnv origBody
      let newDecl = CFunDef specName newParams newBody
      modify
        ( \s ->
            s
              { ssNewDecls = newDecl : ssNewDecls s,
                ssArities = M.insert specName (length newParams) (ssArities s)
              }
        )
    Just (CValDef _ _) ->
      lift
        $ Left
        $ TELowering
          ( "defunctionalize: cannot specialise a non-function declaration "
              <> origName
          )
    Nothing ->
      lift
        $ Left
        $ TELowering
          ("defunctionalize: missing declaration for " <> origName)
