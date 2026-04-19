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
--   • Non-nullary constructors used as values (not at head of application)
--     are eta-expanded into synthetic wrapper functions.
--
-- Invariants (assumed by codegen/tests):
--   • After lowering, zero-arg defs do NOT become functions; they are 'CValDef'.
--   • 'CPrim' only appears in callee position of 'CCall'.
--   • Unsupported qualified names fail fast with a clear error.
module Awsum.ElaborateLower (elaborateLowerProgram) where

import Awsum.Core
import Awsum.Syntax
import Awsum.Typing (TypeError (..), typecheckProgram)
import Control.Monad (foldM)
import Data.List (groupBy)
import Data.Map.Strict qualified as M
import Data.Text qualified as T
import Relude

-- | Constructor info: maps constructor name → (tag, arity).
type ConInfoEnv = M.Map Name (Int, Int)

-- | Build constructor info from @type@ declarations.
--   Each constructor gets a 0-based tag and its arity (number of fields).
buildConInfo :: [Decl] -> ConInfoEnv
buildConInfo ds =
  M.fromList
    [ (cName, (idx, length cFields))
    | TypeDecl _sp _ _ cs _ <- ds,
      (ConDef cName cFields, idx) <- zip cs [0 ..]
    ]

-- | Synthetic name for a constructor wrapper function.
--   Uses @$con$@ prefix which cannot collide with user-defined names.
conWrapperName :: Name -> Name
conWrapperName name = "$con$" <> name

-- | Generate wrapper 'CFunDef's for every non-nullary constructor.
--   E.g. @type Box a = Box a@ produces:
--     @CFunDef "$con$Box" ["$x0"] (CCon 0 [CVar "$x0"])@
genConWrappers :: ConInfoEnv -> [CDecl]
genConWrappers conInfo =
  [ CFunDef (conWrapperName name) params (CCon tag (map CVar params))
  | (name, (tag, arity)) <- M.toList conInfo,
    arity > 0,
    let params = ["$x" <> show i | i <- [0 .. arity - 1]]
  ]

-- | Check the surface program (types) and lower it to Core IR.
--   On success we return a Core program that codegens can consume directly.
elaborateLowerProgram :: Program -> Either TypeError CoreProgram
elaborateLowerProgram prog = do
  -- 1) Elaboration step (MVP): just typecheck; no evidence/dictionaries yet.
  typecheckProgram prog
  -- 2) Lowering: drop signatures, convert defs/exprs. Fail gracefully on unknown primitives.
  let conInfo = buildConInfo (toList (decls prog))
  mds <- traverse (lowerDecl conInfo) (toList (decls prog))
  pure $ CoreProgram (catMaybes mds <> genConWrappers conInfo)

-- | Lower a top-level declaration.
--   • Type signatures and type declarations are erased (they already influenced checking).
--   • Zero-arg defs become constants ('CValDef'), others become first-order functions.
lowerDecl :: ConInfoEnv -> Decl -> Either TypeError (Maybe CDecl)
lowerDecl conInfo = \case
  Sig {} -> Right Nothing
  CommentDecl _ -> Right Nothing
  TypeDecl {} -> Right Nothing
  FunDef _sp n args body _ -> do
    body' <- lowerExpr conInfo body
    pure $ Just $ case args of
      [] -> CValDef n body' -- zero-arg def ⇒ constant
      _ -> CFunDef n args body'

-- | Lower a surface expression to Core.
--     • drop explicit parentheses,
--     • translate string literals verbatim,
--     • map @e1 ++ e2@ to a primitive call,
--     • flatten left-associated application into a single 'CCall',
--     • map constructors to integer tags,
--     • non-nullary constructors used as values become wrapper references,
--     • map @case@ to tag-based dispatch.
lowerExpr :: ConInfoEnv -> Expr -> Either TypeError CExpr
lowerExpr conInfo = \case
  EParens _sp e -> lowerExpr conInfo e
  EVar _sp qn -> lowerVar qn
  ELit _sp (LString t) -> Right (CString t)
  EInfix _sp OpConcat l r -> CCall (CPrim PrimConcat) <$> sequenceA [lowerExpr conInfo l, lowerExpr conInfo r]
  ECon _sp name -> case M.lookup name conInfo of
    Just (tag, 0) -> Right (CCon tag [])
    Just (_tag, _arity) -> Right (CVar (conWrapperName name))
    Nothing -> Left (TELowering ("unknown constructor: " <> name))
  ECase _sp scrut alts _ -> do
    scrut' <- lowerExpr conInfo scrut
    alts' <- traverse (lowerAlt conInfo) (toList alts)
    -- Group alts by tag and merge nested patterns
    merged <- mergeAlts alts'
    Right (CCase scrut' merged)
  EApp _sp f x -> do
    let (f0, xs) = collectApps f [x]
    case f0 of
      ECon _sp' name -> case M.lookup name conInfo of
        Just (tag, _arity) -> do
          xs' <- traverse (lowerExpr conInfo) xs
          Right (CCon tag xs')
        Nothing -> Left (TELowering ("unknown constructor: " <> name))
      _ -> do
        f0' <- lowerExpr conInfo f0
        xs' <- traverse (lowerExpr conInfo) xs
        Right (CCall f0' xs')

-- | Lower a single case alternative: look up the constructor tag,
--   desugar nested patterns into nested CCase, and lower the body.
lowerAlt :: ConInfoEnv -> CaseAlt -> Either TypeError (Int, [Name], CExpr)
lowerAlt conInfo (CaseAlt _ (PCon cName pats) body _) = do
  (tag, _arity) <- maybeToRight (TELowering ("unknown constructor in pattern: " <> cName)) (M.lookup cName conInfo)
  body' <- lowerExpr conInfo body
  let (topVars, wrappedBody) = desugarPats conInfo "__" 0 pats body'
  Right (tag, topVars, wrappedBody)
lowerAlt _ CaseAlt {} =
  Left (TELowering "only constructor patterns are supported in case")

-- | Merge case alternatives that have the same outer tag.
--   When multiple alts match the same constructor with nested patterns,
--   merge their inner case expressions into a single nested case.
--   Example: @Ok (Ok x) -> ...@ and @Ok (Err x) -> ...@ both have tag 0 for Ok,
--   so we merge them into a single alt with a nested case on the inner Result.
mergeAlts :: [(Int, [Name], CExpr)] -> Either TypeError [(Int, [Name], CExpr)]
mergeAlts alts =
  let grouped = groupBy (\(t1, _, _) (t2, _, _) -> t1 == t2) (sortOn (\(t, _, _) -> t) alts)
   in traverse mergeGroup grouped >>= Right . concat
  where
    mergeGroup :: [(Int, [Name], CExpr)] -> Either TypeError [(Int, [Name], CExpr)]
    mergeGroup [] = Right []
    mergeGroup [alt] = Right [alt]
    mergeGroup ((tag, vars, body) : rest) = do
      -- Check if all alts in this group have the same structure
      -- (same number of vars, all bodies are CCase on the first var)
      case (body, map (\(_, vs, b) -> (vs, b)) rest) of
        (CCase (CVar scrutVar) innerAlts, otherBodies) -> do
          -- Check if all other bodies are also CCase on their first var
          allInnerAlts <- foldM collectInnerAlts innerAlts otherBodies
          -- Recursively merge the collected inner alternatives
          mergedInnerAlts <- mergeAlts allInnerAlts
          -- Use a consistent variable name (take from first alt)
          Right [(tag, vars, CCase (CVar scrutVar) mergedInnerAlts)]
        _ ->
          -- Not all bodies are CCase, or they don't match - this is an error
          -- (patterns with same outer constructor but different nesting structure)
          Left (TELowering $ "conflicting pattern shapes for constructor tag " <> show tag)

    collectInnerAlts :: [(Int, [Name], CExpr)] -> ([Name], CExpr) -> Either TypeError [(Int, [Name], CExpr)]
    collectInnerAlts acc (_vars, CCase (CVar _scrutVar) innerAlts) =
      Right (acc <> innerAlts)
    collectInnerAlts _ _ =
      Left (TELowering "conflicting pattern shapes in merge")

-- | Desugar a list of sub-patterns into flat variable bindings,
--   wrapping the body in nested CCase for any nested constructor patterns.
--   Uses path-based naming (e.g. @__p0@, @__p0_p0@) for fresh variables.
desugarPats :: ConInfoEnv -> Text -> Int -> [Pattern] -> CExpr -> ([Name], CExpr)
desugarPats _ _ _ [] body = ([], body)
desugarPats conInfo prefix idx (p : ps) body =
  let (restVars, restBody) = desugarPats conInfo prefix (idx + 1) ps body
   in case p of
        PVar n -> (n : restVars, restBody)
        PWild ->
          let fresh = prefix <> "w" <> show idx
           in (fresh : restVars, restBody)
        PCon innerCon innerPats ->
          let fresh = prefix <> "p" <> show idx
              innerTag = maybe 0 fst (M.lookup innerCon conInfo)
              innerPrefix = fresh <> "_"
              (innerVars, innerBody) = desugarPats conInfo innerPrefix 0 innerPats restBody
           in (fresh : restVars, CCase (CVar fresh) [(innerTag, innerVars, innerBody)])

-- | Collect a chain of applications into (head, args) in left-to-right order.
--   Example:
--     collectApps (f a b) []  ==>  (f, [a,b])
collectApps :: Expr -> [Expr] -> (Expr, [Expr])
collectApps f acc = case f of
  EApp _sp f' x' -> collectApps f' (x' : acc)
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
