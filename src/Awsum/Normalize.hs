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
  Sig n t mc -> Sig n t mc
  FunDef n as e mc -> FunDef n as (normalizeExpr e) mc
  TypeDecl n tvs cs mc -> TypeDecl n tvs cs mc
  CommentDecl c -> CommentDecl c

-- | Normalize an expression by recursively normalizing children and
--   erasing explicit parentheses (they are not semantically relevant).
--
-- Invariants after this pass:
--   • No 'EParens' remain.
--   • The tree shape is otherwise preserved (no re-association beyond recursion).
normalizeExpr :: Expr -> Expr
normalizeExpr = \case
  EVar q -> EVar q
  ELit (LString s) -> ELit (LString s)
  EApp f x -> EApp (normalizeExpr f) (normalizeExpr x)
  EInfix OpConcat l r -> EInfix OpConcat (normalizeExpr l) (normalizeExpr r)
  EParens e -> normalizeExpr e
  ECon n -> ECon n
  ECase scrut alts cs -> ECase (normalizeExpr scrut) (fmap normalizeAlt alts) cs
  where
    normalizeAlt (CaseAlt lc pat body mc) = CaseAlt lc pat (normalizeExpr body) mc
