-- | /Surface-level/ normalization.
--
-- This pass works on 'Awsum.Syntax' (the user-facing AST) and performs
-- only safe, structure-preserving cleanups that do **not** require types
-- and do **not** change semantics:
--
--   • recursively normalizes subexpressions,
--   • drops explicit parentheses ('EParens') — they are syntactic sugar,
--   • keeps declaration and import order intact (no reordering/deduping here).
--
-- Things this module deliberately does **not** do:
--   • beta/eta reductions, inlining, or any evaluation;
--   • re-association beyond what the parser already guarantees
--     (application is left-assoc; '++' is left-assoc with its precedence);
--   • name resolution or qualification changes.
--
-- If you add new expression forms in 'Awsum.Syntax', extend 'normalizeExpr'
-- with a structurally recursive case (no cleverness).
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
  ECase sp scrut alts cs -> ECase sp (normalizeExpr scrut) (fmap normalizeAlt alts) cs
  where
    normalizeAlt (CaseAlt lc pat body mc) = CaseAlt lc pat (normalizeExpr body) mc
