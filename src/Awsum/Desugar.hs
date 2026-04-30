-- | Surface-AST desugaring pass run before typechecking.
--
-- Translates @do@-blocks into nested 'bindEither' calls and uses
-- 'const' / η-reduction to eliminate the resulting lambdas /at
-- desugar time/, before they need to be typechecked or lifted:
--
-- @
-- do { a <- e1; b <- e2; pureEither b }
-- @
--
-- becomes
--
-- @
-- bindEither e1 (const (bindEither e2 pureEither))
-- @
--
-- (the inner @\\b -> pureEither b@ η-reduces to @pureEither@; the
-- outer @\\a -> ...@ has @a@ unused, so it becomes @const ...@).
--
-- The trailing expression is the user's verbatim — typically a
-- 'pureEither' application, which is just an ordinary prelude
-- function. There is no @pure@ soft keyword: writing @pure x@ in a
-- @do@ block is a plain unbound-name error like anywhere else, and
-- once type classes land 'pure' will return as a polymorphic
-- function rather than as a syntactic rewrite.
--
-- The rewrite is purely syntactic and hard-coded to the @Either@
-- shape — there is no type-class dispatch yet.
--
-- This iteration deliberately rejects do-blocks where the
-- continuation cannot be expressed without a real lambda — i.e.
-- where the bound name is used inside the rest of the block. Such
-- blocks need lambda lifting, which is not yet wired through
-- lowering.
module Awsum.Desugar (desugarProgram, DesugarError (..)) where

import Awsum.Syntax
import Data.Set qualified as S
import Relude

-- | Reasons the desugarer can refuse a 'do' block. Surfaced as part
--   of the lowering error channel by 'Awsum.ElaborateLower'.
data DesugarError
  = -- | A 'do'-block bind uses a non-'PVar'/'PWild' pattern. Carries
    --   the bind's source span.
    DesugarUnsupportedBindPattern SrcSpan
  | -- | A 'do' block contains a 'let' statement. Reserved for the
    --   future; the typechecker rejects it earlier in normal flow.
    DesugarUnsupportedLet SrcSpan
  | -- | The bound name of a 'do'-bind is used by the continuation
    --   such that the lambda cannot be eliminated by η or 'const'.
    --   Carries the bind's source span and the bound name.
    DesugarBindNameStillUsed SrcSpan Name
  deriving stock (Show, Eq)

-- | Run the desugarer over a 'Program'. Pure tree rewrite — no extra
--   declarations are introduced, only the body of each 'FunDef' is
--   rewritten in place.
desugarProgram :: Program -> Either DesugarError Program
desugarProgram p = do
  decls' <- traverse desugarDecl (decls p)
  pure p {decls = decls'}

desugarDecl :: Decl -> Either DesugarError Decl
desugarDecl = \case
  FunDef sp n params body c -> FunDef sp n params <$> desugarExpr body <*> pure c
  d -> pure d

desugarExpr :: Expr -> Either DesugarError Expr
desugarExpr = \case
  EDo sp stmts -> desugarDo sp stmts
  ELam sp params body -> ELam sp params <$> desugarExpr body
  EApp sp f x -> EApp sp <$> desugarExpr f <*> desugarExpr x
  EInfix sp op l r -> EInfix sp op <$> desugarExpr l <*> desugarExpr r
  EParens sp e -> EParens sp <$> desugarExpr e
  ECase sp scrut alts cs -> do
    scrut' <- desugarExpr scrut
    alts' <- traverse desugarCaseAlt alts
    pure (ECase sp scrut' alts' cs)
  e -> pure e
  where
    desugarCaseAlt (CaseAlt c pat body mc) = do
      body' <- desugarExpr body
      pure (CaseAlt c pat body' mc)

-- | Translate a 'do'-block into a chain of 'bindEither' /
--   'pureEither' calls. Each continuation is expressed without a
--   surface lambda by η-reduction or wrapping in 'const'.
desugarDo :: SrcSpan -> [DoStmt] -> Either DesugarError Expr
desugarDo sp = go
  where
    go [] = Right (EVar sp (QName [] "$emptyDoBlock"))
    go [DoExpr _ e] = desugarExpr e
    go (DoBind bsp pat e : rest) = do
      e' <- desugarExpr e
      param <- case pat of
        PVar _ n -> Right n
        PWild _ -> Right "$do_w"
        _ -> Left (DesugarUnsupportedBindPattern bsp)
      body <- go rest
      cont <- mkContinuation bsp param body
      let bindRef = EVar sp (QName [] "bindEither")
      Right (EApp sp (EApp sp bindRef e') cont)
    go (DoLet lsp _ _ : _) = Left (DesugarUnsupportedLet lsp)
    -- Bare expression in a non-final position is rejected; the
    -- typechecker also flags this, but we catch it here too so the
    -- desugar output stays well-formed.
    go (DoExpr esp _ : _ : _) = Left (DesugarBindNameStillUsed esp "<non-final-expr>")

    -- Express @\\param -> body@ as either @body[param→…]@ via
    -- η-reduction, or as @const body@ when @param@ is unused, or
    -- (if neither shortcut applies) emit a real surface 'ELam' for
    -- the lowering pass to lambda-lift. The first two cases avoid
    -- generating a lambda at all, which keeps the lowered Core flat
    -- when possible.
    mkContinuation _bsp param body
      -- η: \x -> f x  →  f, when x is not free in f.
      | EApp _ f (EVar _ (QName [] x)) <- body,
        x == param,
        not (paramFreeIn param f) =
          Right f
      -- const: \x -> e  →  const e, when x is not free in e.
      | not (paramFreeIn param body) =
          Right (EApp sp (EVar sp (QName [] "const")) body)
      -- General case: introduce a real lambda; lowering lifts it.
      | otherwise = Right (ELam sp [Param sp param] body)

-- | Free-variable check: does @name@ occur as an unbound 'EVar' in
--   the expression?
paramFreeIn :: Name -> Expr -> Bool
paramFreeIn n = go
  where
    go = \case
      EVar _ (QName [] m) -> m == n
      EVar _ _ -> False
      EApp _ f x -> go f || go x
      EInfix _ _ l r -> go l || go r
      EParens _ e -> go e
      ELit _ _ -> False
      ECon _ _ -> False
      EBuiltIn _ _ -> False
      ECase _ scrut alts _ ->
        go scrut
          || any (\(CaseAlt _ pat body _) -> not (boundByPattern n pat) && go body) (toList alts)
      ELam _ ps body ->
        n `S.notMember` S.fromList (map paramName ps) && go body
      EDo {} -> False -- post-desugar this shouldn't appear

    -- Is @n@ bound by the pattern (and therefore shadowed in the arm
    -- body)? Variable patterns bind their name; constructor patterns
    -- recurse into sub-patterns.
    boundByPattern n0 = goP
      where
        goP (PVar _ m) = m == n0
        goP (PWild _) = False
        goP (PCon _ _ inner) = any goP inner
        goP (PAscribe _ inner _) = goP inner
