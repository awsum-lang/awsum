-- | Uniquify local binders that collide with a top-level name.
--
-- After lowering, a function parameter or a @CCase@ / @CRowCase@ arm
-- binder may share a bare name with a top-level declaration. That is
-- legal in the language — cross-module shadowing is explicitly allowed,
-- so the prelude's @bindIO io k = case io of IOGetArgs cont -> …@ binds a
-- pattern variable @cont@ that coexists with a user top-level @cont@ — but
-- it breaks every later pass that disambiguates a bare @CVar n@ between
-- "local reference" and "top-level reference" by looking @n@ up in the
-- global declaration table ('Awsum.Defunctionalize', 'Awsum.LowerClosures',
-- the self-call analysis in 'Awsum.Cps'). Such a pass resolves the local
-- @cont@ to the unrelated top-level @cont@, treats it as a statically
-- known function, drops the binder's captures, and emits a dangling
-- closure — at runtime, @v_cont is not a function@.
--
-- This pass restores the invariant those passes rely on, and that
-- 'Awsum.Core' documents ("names in Core are unique … a flat name-keyed
-- map suffices"): every local binder whose name collides with a top-level
-- name is renamed to a fresh @$@-tagged name (user identifiers cannot
-- contain @$@, so the fresh name collides with neither user source names
-- nor the @$@-prefixed names later passes mint), and references in the
-- binder's scope are rewritten to match. Run once after lowering and
-- before 'Awsum.Defunctionalize'; from there on, resolving a bare name
-- against the global table is sound.
--
-- Scoping. A rename environment is threaded through the walk and maps a
-- shadowed name to its fresh replacement for the extent of that binder's
-- scope only — so sibling @CCase@ arms that independently reuse a name
-- (legal: not nested shadowing) stay independent, and an outer rename
-- never leaks past a same-named inner binder.
module Awsum.UniquifyLocals (uniquifyLocals) where

import Awsum.Core
import Awsum.Syntax (Name)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Relude

-- | Rename every local binder that collides with a top-level name. The
--   'State' carries the set of names already in use anywhere in the
--   program, so a freshly minted replacement collides with nothing.
uniquifyLocals :: CoreProgram -> CoreProgram
uniquifyLocals (CoreProgram decls) =
  let topNames = Set.fromList (map declName decls)
      reserved = foldMap allNames decls
   in CoreProgram (evalState (traverse (uniquifyDecl topNames) decls) reserved)

declName :: CDecl -> Name
declName = \case
  CFunDef n _ _ -> n
  CValDef n _ -> n

-- | A monotonic, program-wide fresh-name supply gated on the reserved
--   set, so two renames never coincide and a mint never reuses an
--   existing name (synthetic or otherwise).
freshName :: Name -> State (Set Name) Name
freshName base = go (0 :: Int)
  where
    go k = do
      used <- get
      let candidate = base <> "$u" <> show k
      if Set.member candidate used
        then go (k + 1)
        else do
          modify (Set.insert candidate)
          pure candidate

uniquifyDecl :: Set Name -> CDecl -> State (Set Name) CDecl
uniquifyDecl topNames = \case
  CFunDef n params body -> do
    (params', env) <- renameBinders topNames Map.empty params
    CFunDef n params' <$> goExpr topNames env body
  CValDef n rhs -> CValDef n <$> goExpr topNames Map.empty rhs

-- | Decide one binder: rename it when it collides with a top-level name,
--   otherwise keep it and (defensively) drop any stale outer mapping for
--   the same name so it can't leak into this fresh binding's scope.
renameBinder :: Set Name -> Map Name Name -> Name -> State (Set Name) (Name, Map Name Name)
renameBinder topNames env b
  | Set.member b topNames = do
      b' <- freshName b
      pure (b', Map.insert b b' env)
  | otherwise = pure (b, Map.delete b env)

renameBinders :: Set Name -> Map Name Name -> [Name] -> State (Set Name) ([Name], Map Name Name)
renameBinders topNames = go []
  where
    go acc env [] = pure (reverse acc, env)
    go acc env (b : bs) = do
      (b', env') <- renameBinder topNames env b
      go (b' : acc) env' bs

goExpr :: Set Name -> Map Name Name -> CExpr -> State (Set Name) CExpr
goExpr topNames = go
  where
    ref env x = Map.findWithDefault x x env
    go env = \case
      CVar x -> pure (CVar (ref env x))
      e@(CString _) -> pure e
      e@(CIntLit _ _) -> pure e
      e@(CBuiltIn _) -> pure e
      CCall callee args -> CCall <$> go env callee <*> traverse (go env) args
      CCon t fs -> CCon t <$> traverse (go env) fs
      CRow t v -> CRow t <$> go env v
      CCase s alts -> CCase <$> go env s <*> traverse (goAlt env) alts
      CRowCase s alts -> CRowCase <$> go env s <*> traverse (goRowAlt env) alts
      CLoop b -> CLoop <$> go env b
      CContinue xs -> CContinue <$> traverse (go env) xs
      CDrop k x b -> CDrop k (ref env x) <$> go env b
      CReuse rm x t fs -> CReuse rm (ref env x) t <$> traverse (go env) fs
      CLet x rhs body -> do
        rhs' <- go env rhs
        (x', env') <- renameBinder topNames env x
        CLet x' rhs' <$> go env' body
      CProj x i -> pure (CProj (ref env x) i)
      CJoin {} -> error "UniquifyLocals: CJoin is minted by Awsum.Simplify, which runs later"
      CJump {} -> error "UniquifyLocals: CJump is minted by Awsum.Simplify, which runs later"
    goAlt env (t, vs, b) = do
      (vs', env') <- renameBinders topNames env vs
      (t,vs',) <$> go env' b
    goRowAlt env (t, v, b) = do
      (v', env') <- renameBinder topNames env v
      (t,v',) <$> go env' b

-- | Every name mentioned in a declaration — its own name, its binders,
--   and every referenced name — used to seed the reserved set so a
--   minted replacement is globally fresh.
allNames :: CDecl -> Set Name
allNames = \case
  CFunDef n ps body -> Set.fromList (n : ps) <> exprNames body
  CValDef n body -> Set.insert n (exprNames body)
  where
    exprNames = \case
      CVar x -> Set.singleton x
      CString _ -> mempty
      CIntLit _ _ -> mempty
      CBuiltIn _ -> mempty
      CCall callee args -> exprNames callee <> foldMap exprNames args
      CCon _ fs -> foldMap exprNames fs
      CRow _ v -> exprNames v
      CCase s alts -> exprNames s <> foldMap (\(_, vs, b) -> Set.fromList vs <> exprNames b) alts
      CRowCase s alts -> exprNames s <> foldMap (\(_, v, b) -> Set.insert v (exprNames b)) alts
      CLoop b -> exprNames b
      CContinue xs -> foldMap exprNames xs
      CDrop _ x b -> Set.insert x (exprNames b)
      CReuse _ x _ fs -> Set.insert x (foldMap exprNames fs)
      CLet x rhs body -> Set.insert x (exprNames rhs <> exprNames body)
      CProj x _ -> Set.singleton x
      CJoin {} -> error "UniquifyLocals: CJoin is minted by Awsum.Simplify, which runs later"
      CJump {} -> error "UniquifyLocals: CJump is minted by Awsum.Simplify, which runs later"
