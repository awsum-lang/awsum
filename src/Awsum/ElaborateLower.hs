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
import Awsum.Typing (TypeError (..), typecheckProgram)
import Data.Map.Strict qualified as M
import Data.Text qualified as T
import Relude

-- | Constructor tag environment: maps constructor name → integer tag.
type ConTagEnv = M.Map Name Int

-- | Build constructor tag environment from @type@ declarations.
--   Each constructor gets a 0-based index within its type definition.
buildConTagEnv :: [Decl] -> ConTagEnv
buildConTagEnv ds =
  M.fromList
    [ (cName, idx)
    | TypeDecl _ _ cs _ <- ds,
      (ConDef cName _, idx) <- zip (toList cs) [0 ..]
    ]

-- | Check the surface program (types) and lower it to Core IR.
--   On success we return a Core program that codegens can consume directly.
elaborateLowerProgram :: Program -> Either TypeError CoreProgram
elaborateLowerProgram prog = do
  -- 1) Elaboration step (MVP): just typecheck; no evidence/dictionaries yet.
  typecheckProgram prog
  -- 2) Lowering: drop signatures, convert defs/exprs. Fail gracefully on unknown primitives.
  let tags = buildConTagEnv (toList (decls prog))
  mds <- traverse (lowerDecl tags) (toList (decls prog))
  pure $ CoreProgram (catMaybes mds)

-- | Lower a top-level declaration.
--   • Type signatures and type declarations are erased (they already influenced checking).
--   • Zero-arg defs become constants ('CValDef'), others become first-order functions.
lowerDecl :: ConTagEnv -> Decl -> Either TypeError (Maybe CDecl)
lowerDecl tags = \case
  Sig {} -> Right Nothing
  CommentDecl _ -> Right Nothing
  TypeDecl {} -> Right Nothing
  FunDef n args body _ -> do
    body' <- lowerExpr tags body
    pure $ Just $ case args of
      [] -> CValDef n body' -- zero-arg def ⇒ constant
      _ -> CFunDef n args body'

-- | Lower a surface expression to Core.
--     • drop explicit parentheses,
--     • translate string literals verbatim,
--     • map @e1 ++ e2@ to a primitive call,
--     • flatten left-associated application into a single 'CCall',
--     • map constructors to integer tags,
--     • map @case@ to tag-based dispatch.
lowerExpr :: ConTagEnv -> Expr -> Either TypeError CExpr
lowerExpr tags = \case
  EParens e -> lowerExpr tags e
  EVar qn -> lowerVar qn
  ELit (LString t) -> Right (CString t)
  EInfix OpConcat l r -> CCall (CPrim PrimConcat) <$> sequenceA [lowerExpr tags l, lowerExpr tags r]
  ECon name -> case M.lookup name tags of
    Just tag -> Right (CCon tag [])
    Nothing -> Left (TELowering ("unknown constructor: " <> name))
  ECase scrut alts _ -> do
    scrut' <- lowerExpr tags scrut
    alts' <- traverse (lowerAlt tags) (toList alts)
    Right (CCase scrut' alts')
  EApp f x -> do
    let (f0, xs) = collectApps f [x]
    f0' <- lowerExpr tags f0
    xs' <- traverse (lowerExpr tags) xs
    Right (CCall f0' xs')

-- | Lower a single case alternative: look up the constructor tag and lower the body.
lowerAlt :: ConTagEnv -> CaseAlt -> Either TypeError (Int, [Name], CExpr)
lowerAlt tags (CaseAlt _ (PCon cName _) body _) = do
  tag <- maybeToRight (TELowering ("unknown constructor in pattern: " <> cName)) (M.lookup cName tags)
  body' <- lowerExpr tags body
  Right (tag, [], body')
lowerAlt _ CaseAlt {} =
  Left (TELowering "only constructor patterns are supported in case")

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
--     • @IO.Stdout.print@  → 'PrimPrint'
--     • Unqualified names  → Core variables.
--
--   Everything else: fail fast with a helpful message.
lowerVar :: QName -> Either TypeError CExpr
lowerVar (QName mods n) =
  case mods of
    [] -> Right (CVar n)
    ["IO", "Stdout"] | n == "print" -> Right (CPrim PrimPrint)
    _ ->
      Left
        $ TELowering
        $ "unsupported qualified name: "
        <> prettyQName mods n
  where
    prettyQName ms name = T.intercalate "." (ms <> [name])
