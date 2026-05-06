-- | /Surface-level/ normalization.
--
-- Works on 'Awsum.Syntax' (user-facing AST). Safe, structure-preserving
-- cleanups; no type info, no semantic change:
--
--   • recursively normalizes subexpressions,
--   • drops explicit parentheses ('EParens'),
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
import Relude

-- | Normalize a whole program. We leave imports as-is (order and spelling),
--   and normalize every top-level declaration.
normalizeProgram :: Program -> Program
normalizeProgram p@Program {imports, decls} =
  p
    { decls = fmap normalizeDecl decls,
      imports = imports
    }

-- | Normalize a top-level declaration.
--   Signatures are kept verbatim; function/value bodies are normalized.
normalizeDecl :: Decl -> Decl
normalizeDecl = \case
  Sig sp n t mc -> Sig sp n t mc
  FunDef sp n as e mc -> FunDef sp n as (normalizeExpr e) mc
  TypeDecl sp n tvs cs mc -> TypeDecl sp n tvs cs mc
  CommentDecl c -> CommentDecl c

-- | Normalize an expression by recursively normalizing children and
--   erasing explicit parentheses (they are not semantically relevant).
--
-- Invariants after this pass:
--   • No 'EParens' remain.
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
  ELam sp params body -> ELam sp params (normalizeExpr body)
  EDo sp stmts -> EDo sp (map normalizeDoStmt stmts)
  ELet sp pat mAnnot e body -> ELet sp pat mAnnot (normalizeExpr e) (normalizeExpr body)
  where
    normalizeAlt (CaseAlt lc pat body mc) = CaseAlt lc pat (normalizeExpr body) mc
    normalizeDoStmt = \case
      DoBind sp pat e -> DoBind sp pat (normalizeExpr e)
      DoLet sp pat mAnnot e -> DoLet sp pat mAnnot (normalizeExpr e)
      DoExpr sp e -> DoExpr sp (normalizeExpr e)
