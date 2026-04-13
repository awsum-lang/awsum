-- | Surface /renderer/ (pretty-printer) for 'Awsum.Syntax'.
--
-- Precedence (low → high):
--   1. @++@          (left-associative)
--   2. application   (left-associative)
--   3. atoms
--
-- Notes:
--   • We add a trailing newline to the whole program for friendlier CLI UX.
--   • String escaping matches the parser: \n \t \r \" \\ \0
module Awsum.Render
  ( renderProgram,
    renderDecl,
    renderType,
    renderExpr,
  )
where

import Awsum.Syntax
import Data.Text qualified as T
import Relude

-- | Render a whole program.
--   Emits imports (if any), then a blank line, then top-level declarations.
--   Separates top-level definitions with a blank line.
--   Keeps a type signature attached to its definition.
--   Always ends with a trailing newline.
renderProgram :: Program -> Text
renderProgram Program {imports, decls} =
  let ims = fmap renderImport imports
      blocks = groupDeclBlocks (toList decls)
      body = T.intercalate "\n\n" blocks <> "\n"
   in case ims of
        [] -> body
        _ -> T.intercalate "\n" ims <> "\n\n" <> body

-- | Group a type signature with the immediately following definition
--   (when they share the same name) so they render as a single block.
--   All other top-level items become their own blocks. Blocks are then
--   separated by a blank line by 'renderProgram'.
groupDeclBlocks :: [Decl] -> [Text]
groupDeclBlocks = \case
  (Sig sp1 n ty sigComment : FunDef sp2 n' args e defComment : rest)
    | n == n' ->
        (renderDecl (Sig sp1 n ty sigComment) <> "\n" <> renderDecl (FunDef sp2 n' args e defComment)) : groupDeclBlocks rest
  (d : rest) ->
    renderDecl d : groupDeclBlocks rest
  [] -> []

-- | Render a single import (with optional leading comments and trailing comment).
renderImport :: ImportDecl -> Text
renderImport (ImportDecl comments mods tcom) =
  let commentLines = map renderComment comments
      importLine = "import " <> T.intercalate "." (toList mods) <> maybe "" (" --" <>) tcom
   in case commentLines of
        [] -> importLine
        _ -> T.intercalate "\n" commentLines <> "\n" <> importLine

-- | Render a top-level declaration.
renderDecl :: Decl -> Text
renderDecl = \case
  Sig _sp name ty mc ->
    name <> " : " <> renderType ty <> renderTrailingComment mc
  FunDef _sp name args e mc ->
    ( case args of
        [] -> name <> " = " <> renderExpr e
        _ -> name <> " " <> T.intercalate " " args <> " = " <> renderExpr e
    )
      <> renderTrailingComment mc
  TypeDecl _sp name tvars cons mc ->
    "type "
      <> name
      <> (if null tvars then "" else " " <> T.intercalate " " tvars)
      <> " = "
      <> T.intercalate " | " (map renderConDef (toList cons))
      <> renderTrailingComment mc
  CommentDecl c ->
    renderComment c
  where
    renderConDef (ConDef n []) = n
    renderConDef (ConDef n fs) = n <> " " <> T.intercalate " " (map (renderTypePrec 3) fs)
    renderTrailingComment = maybe ("" :: Text) (" --" <>)

renderComment :: Comment -> Text
renderComment = \case
  LineComment t -> "--" <> t
  BlockComment t -> "{-" <> t <> "-}"

-- ── Types ───────────────────────────────────────────────────────────────────

-- | Entry point for types (uses a small precedence machine).
renderType :: Type' -> Text
renderType = renderTypePrec 0

-- | @ctx@ is the precedence context we are printing into:
--   0 (top) < 1 (->) < 2 (app) < 3 (atom).
--   We parenthesize when the inner precedence is strictly lower than the context.
renderTypePrec :: Int -> Type' -> Text
renderTypePrec ctx = \case
  TyVar n -> n
  TyCon n -> n
  TyApp f x ->
    let s = renderTypePrec 2 f <> " " <> renderTypePrec 3 x
     in if 2 < ctx then parens s else s
  TyArrow t1 t2 ->
    let l = renderTypePrec 2 t1
        r = renderTypePrec 1 t2
        s = l <> " -> " <> r
     in if 1 < ctx then parens s else s

-- ── Expressions ─────────────────────────────────────────────────────────────

-- | Entry point for expressions (small precedence machine mirroring the parser).
renderExpr :: Expr -> Text
renderExpr = renderExprPrec 0

-- | @ctx@ is the precedence context:
--   0 (top) < 1 (++) < 2 (app) < 3 (atom).
--   We parenthesize when inner precedence is strictly lower than @ctx@.
--   Special case: explicit 'EParens' are always preserved verbatim to make
--   parse ∘ render round-trip possible in tests.
renderExprPrec :: Int -> Expr -> Text
renderExprPrec ctx e =
  case e of
    EParens _sp e' ->
      -- Preserve user parentheses exactly as written.
      parens (renderExprPrec 0 e')
    ECase _sp scrut alts trailingComments ->
      -- Case is always at top precedence; parenthesize if nested.
      let s = "case " <> renderExprPrec 0 scrut <> " of\n" <> renderCaseAlts alts trailingComments
       in if 0 < ctx then parens s else s
    _ ->
      let (prec, s) = case e of
            EVar _sp' q -> (3, renderQName q)
            ELit _sp' (LString t) -> (3, "\"" <> escape t <> "\"")
            ECon _sp' n -> (3, n)
            -- Application is left-assoc: print f at prec 2, arg at atom-precedence
            -- so nested apps on the right get parenthesized.
            EApp _sp' f x ->
              let f' = renderExprPrec 2 f
                  x' = renderExprPrec 3 x
               in (2, f' <> " " <> x')
            -- For left-assoc @++@: we print the right operand at a tighter
            -- context (2) so a chained ++ on the right becomes parenthesized.
            -- This preserves the original associativity in round-trips.
            EInfix _sp' OpConcat l r ->
              let l' = renderExprPrec 1 l
                  r' = renderExprPrec 2 r
               in (1, l' <> " ++ " <> r')
       in if prec < ctx then parens s else s
  where
    -- Matches the parser's escape table.
    escape :: Text -> Text
    escape = T.concatMap $ \c -> case c of
      '\n' -> "\\n"
      '\t' -> "\\t"
      '\r' -> "\\r"
      '\"' -> "\\\""
      '\\' -> "\\\\"
      '\0' -> "\\0"
      _ -> one c

renderCaseAlts :: NonEmpty CaseAlt -> [Comment] -> Text
renderCaseAlts alts trailingComments =
  T.intercalate "\n" (map renderCaseAlt (toList alts) <> map renderIndentedComment trailingComments)
  where
    renderCaseAlt (CaseAlt leadingComments pat body mc) =
      T.intercalate
        "\n"
        ( map renderIndentedComment leadingComments
            <> ["  " <> renderPattern pat <> " -> " <> renderExprPrec 0 body <> renderTrailingComment mc]
        )
    renderIndentedComment c = "  " <> renderComment c
    renderTrailingComment = maybe ("" :: Text) (" --" <>)

renderPattern :: Pattern -> Text
renderPattern = \case
  PCon n [] -> n
  PCon n ps -> n <> " " <> T.intercalate " " (map renderPattern ps)
  PVar n -> n
  PWild -> "_"

-- | Utility: surround text with parentheses.
parens :: Text -> Text
parens t = "(" <> t <> ")"

-- | Render a qualified or unqualified name.
renderQName :: QName -> Text
renderQName (QName mods n) =
  case mods of
    [] -> n
    _ -> T.intercalate "." (mods <> [n])
