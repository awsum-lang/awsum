-- | Single-pass /elaboration + lowering/ from surface 'Awsum.Syntax' to 'Awsum.Core'.
--
-- Why one pass?  For the MVP we do the minimal work:
--   1) /Elaboration/ : rely on the type checker to validate the program
--      (no dictionaries/implicit args yet).
--   2) /Lowering/    : erase surface sugar and map built-ins to Core primitives.
--
-- Notes:
--   • We treat zero-argument top-level defs as /constants/ ('CValDef').
--   • We erase explicit type signatures ('Sig') — they are checked, then dropped.
--   • Qualified names are resolved here to primitives (e.g. @IO.Stdout.print@).
--   • Application is flattened to a single 'CCall' with all arguments (left-assoc).
--
-- Invariants (assumed by codegen/tests):
--   • After lowering, zero-arg defs do NOT become functions; they are 'CValDef'.
--   • 'CPrim' only appears in callee position of 'CCall'.
--   • Unsupported qualified names fail fast with a clear error.
module Awsum.ElaborateLower (elaborateLowerProgram) where

import Awsum.Core
import Awsum.Syntax
import Awsum.Typing (TypeError, typecheckProgram)
import Data.Text qualified as T
import Relude

-- | Check the surface program (types) and lower it to Core IR.
--   On success we return a Core program that codegens can consume directly.
elaborateLowerProgram :: Program -> Either TypeError CoreProgram
elaborateLowerProgram prog = do
  -- 1) Elaboration step (MVP): just typecheck; no evidence/dictionaries yet.
  typecheckProgram prog
  -- 2) Lowering: drop signatures, convert defs/exprs.
  let ds = toList (decls prog)
  pure $ CoreProgram (mapMaybe lowerDecl ds)

-- | Lower a top-level declaration.
--   • Type signatures are erased (they already influenced checking).
--   • Zero-arg defs become constants ('CValDef'), others become first-order functions.
lowerDecl :: Decl -> Maybe CDecl
lowerDecl = \case
  Sig _ _ _ -> Nothing
  FunDef n args body _ ->
    Just
      $ case args of
        [] -> CValDef n (lowerExpr body) -- zero-arg def ⇒ constant
        _ -> CFunDef n args (lowerExpr body)
  CommentDecl _ -> Nothing

-- | Lower a surface expression to Core.
--     • drop explicit parentheses,
--     • translate string literals verbatim,
--     • map @e1 ++ e2@ to a primitive call,
--     • flatten left-associated application into a single 'CCall'.
lowerExpr :: Expr -> CExpr
lowerExpr = \case
  EParens e -> lowerExpr e
  EVar qn -> lowerVar qn
  ELit (LString t) -> CString t
  EInfix OpConcat l r -> CCall (CPrim PrimConcat) [lowerExpr l, lowerExpr r]
  EApp f x ->
    let (f0, xs) = collectApps f [x]
     in CCall (lowerExpr f0) (map lowerExpr xs)

-- | Collect a chain of applications into (head, args) in left-to-right order.
--   Example:
--     collectApps (f a b) []  ==>  (f, [a,b])
collectApps :: Expr -> [Expr] -> (Expr, [Expr])
collectApps f acc = case f of
  EApp f' x' -> collectApps f' (x' : acc)
  _ -> (f, acc)

-- | Lower a (possibly qualified) variable to either a Core variable
--   or a primitive.  This is the single place that knows about
--   the surface names of built-ins for the MVP.
--
--   Supported:
--     • @IO.Stdout.print@   → 'PrimPrint'
--     • Unqualified names  → Core variables.
--
--   Everything else: fail fast with a helpful message.
lowerVar :: (HasCallStack) => QName -> CExpr
lowerVar (QName mods n) =
  case mods of
    [] -> CVar n
    ["IO", "Stdout"] | n == "print" -> CPrim PrimPrint
    _ ->
      error
        $ "ElaborateLower: unsupported qualified name: "
        <> T.intercalate "." (mods <> [n])
