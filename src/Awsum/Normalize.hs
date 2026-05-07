-- | /Surface-level/ normalization.
--
-- Works on 'Awsum.Syntax' (user-facing AST). Safe, structure-preserving
-- cleanups; no type info, no semantic change:
--
--   • recursively normalizes subexpressions,
--   • drops explicit parentheses ('EParens'),
--   • collapses 'ParamPat (PVar n)' to 'Param n' (the parser
--     canonicalises @(x)@ in parameter position back to a bare
--     binder; the AST representation must agree),
--   • collapses an empty trailing-comment 'Just ""' to 'Nothing'
--     (the renderer emits a bare @--@ which the parser canonicalises
--     to no comment),
--   • keeps declaration and import order intact.
--
-- Deliberately /not/ done: beta/eta, inlining, evaluation; re-association
-- beyond what the parser guarantees; name resolution.
--
-- New 'Awsum.Syntax' expression forms get a structurally recursive case
-- in 'normalizeExpr' (no cleverness).
module Awsum.Normalize
  ( normalizeProgram,
    normalizeDecl,
    normalizeExpr,
  )
where

import Awsum.Syntax
import Data.Text qualified as T
import Relude

-- | Normalize a whole program. We normalize every import (leading /
--   trailing comments) and every top-level declaration.
normalizeProgram :: Program -> Program
normalizeProgram p@Program {imports, decls} =
  p
    { decls = fmap normalizeDecl decls,
      imports = fmap normalizeImport imports
    }

-- | Normalize an import: collapse an empty trailing comment to
--   'Nothing'; leading comments are preserved as-is.
normalizeImport :: ImportDecl -> ImportDecl
normalizeImport (ImportDecl lc m mc) = ImportDecl lc m (normalizeTrailing mc)

-- | Normalize a top-level declaration.
--   Signatures are kept verbatim; function/value bodies are normalized.
normalizeDecl :: Decl -> Decl
normalizeDecl = \case
  Sig sp n t mc -> Sig sp n t (normalizeTrailing mc)
  FunDef sp n as e mc -> FunDef sp n (map normalizeParam as) (normalizeExpr e) (normalizeTrailing mc)
  TypeDecl sp n tvs cs mc -> TypeDecl sp n (map normalizeParam tvs) cs (normalizeTrailing mc)
  CommentDecl c -> CommentDecl c

-- | Collapse @ParamPat (PVar n)@ to @Param n@ — the parser
--   canonicalises @(x)@ back to a bare binder, so the two AST shapes
--   are equivalent and must compare equal.
normalizeParam :: Param -> Param
normalizeParam = \case
  ParamPat _ (PVar sp n) -> Param sp n
  p -> p

-- | An empty trailing-comment text (rendered as a bare @--@) round-trips
--   through the parser as 'Nothing', so collapse here.
normalizeTrailing :: Maybe Text -> Maybe Text
normalizeTrailing (Just t) | T.null t = Nothing
normalizeTrailing m = m

-- | Normalize an expression by recursively normalizing children and
--   erasing explicit parentheses (they are not semantically relevant).
--
-- Invariants after this pass:
--   • No 'EParens' remain.
--   • Lambda / let / case-alt / do-let parameters are normalized
--     (no @ParamPat (PVar n)@ shapes survive).
--   • The tree shape is otherwise preserved (no re-association beyond recursion).
normalizeExpr :: Expr -> Expr
normalizeExpr = \case
  EVar sp q -> EVar sp q
  ELit sp (LString s) -> ELit sp (LString s)
  ELit sp (LInt n) -> ELit sp (LInt n)
  EApp sp f x -> EApp sp (normalizeExpr f) (normalizeExpr x)
  EInfix sp OpConcat l r -> EInfix sp OpConcat (normalizeExpr l) (normalizeExpr r)
  EParens _sp e -> normalizeExpr e
  ECon sp n -> ECon sp n
  EBuiltIn sp n -> EBuiltIn sp n
  ECase sp scrut alts cs -> ECase sp (normalizeExpr scrut) (fmap normalizeAlt alts) cs
  ELam sp params body -> ELam sp (map normalizeParam params) (normalizeExpr body)
  EDo sp stmts -> EDo sp (map normalizeDoStmt stmts)
  ELet sp pat mAnnot e body -> ELet sp pat mAnnot (normalizeExpr e) (normalizeExpr body)
  where
    -- 'mkCaseAlt' re-derives the constructor from the normalized body,
    -- so a body that changed shape (rare — normalization is structural)
    -- still ends up in the right variant.
    normalizeAlt alt = mkCaseAlt (caseAltLeading alt) (caseAltPattern alt) (normalizeExpr (caseAltBody alt)) (normalizeTrailing (caseAltTrailing alt))
    normalizeDoStmt = \case
      DoBind sp pat e -> DoBind sp pat (normalizeExpr e)
      DoLet sp pat mAnnot e -> DoLet sp pat mAnnot (normalizeExpr e)
      DoExpr sp e -> DoExpr sp (normalizeExpr e)
