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
import Data.Char qualified as Char
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
    renderDeclName name <> " : " <> renderType ty <> renderTrailingComment mc
  FunDef _sp name args e mc ->
    ( case args of
        [] -> renderDeclName name <> " = " <> renderExpr e
        _ -> renderDeclName name <> " " <> T.intercalate " " (map paramName args) <> " = " <> renderExpr e
    )
      <> renderTrailingComment mc
  TypeDecl _sp name tvars cons mc ->
    "type "
      <> name
      <> (if null tvars then "" else " " <> T.intercalate " " (map paramName tvars))
      <> (if null cons then "" else " = " <> T.intercalate " | " (map renderConDef cons))
      <> renderTrailingComment mc
  CommentDecl c ->
    renderComment c
  where
    renderConDef (ConDef _ n []) = n
    renderConDef (ConDef _ n fs) = n <> " " <> T.intercalate " " (map (renderTypePrec 3) fs)
    renderTrailingComment = maybe ("" :: Text) (" --" <>)

-- | Wrap a top-level declaration name in parens when it's an operator
--   (e.g. @"++"@ renders as @(++)@), so @renderProgram . parseProgram@ is
--   a fixpoint on files that declare operators in the prelude style.
renderDeclName :: Name -> Text
renderDeclName n
  | T.null n = n
  | isBinderStart (T.head n) = n
  | otherwise = "(" <> n <> ")"
  where
    isBinderStart c = Char.isLower c || c == '_'

renderComment :: Comment -> Text
renderComment = \case
  LineComment t -> "--" <> t
  BlockComment t ->
    let trimmed = T.strip t
     in if T.null trimmed then "{- -}" else "{- " <> trimmed <> " -}"

-- ── Types ───────────────────────────────────────────────────────────────────

-- | Entry point for types (uses a small precedence machine).
renderType :: Type' -> Text
renderType = renderTypePrec 0

-- | @ctx@ is the precedence context we are printing into:
--   0 (top) < 1 (|) < 2 (->) < 3 (app) < 4 (atom).
--   We parenthesize when the inner precedence is strictly lower than the context.
renderTypePrec :: Int -> Type' -> Text
renderTypePrec ctx = \case
  TyVar _ n -> n
  TyCon _ n -> n
  TyApp _ f x ->
    let s = renderTypePrec 3 f <> " " <> renderTypePrec 4 x
     in if 3 < ctx then parens s else s
  TyArrow _ t1 t2 ->
    let l = renderTypePrec 3 t1
        r = renderTypePrec 2 t2
        s = l <> " -> " <> r
     in if 2 < ctx then parens s else s
  TyOr _ t1 t2 ->
    -- @|@ is lower precedence than @->@, so a 'TyOr' on the LHS of an
    -- arrow needs parens (caller's @ctx@ pushes us above 1) and our own
    -- branches render at arrow-level (2): an arrow inside @T1 | T2@
    -- prints unparenthesised (`A -> B | C` re-parses to `(A -> B) | C`,
    -- the original AST), but a nested 'TyOr' on the LHS does need parens
    -- to preserve grouping when re-parsed.
    let l = renderTypePrec 2 t1
        r = renderTypePrec 1 t2
        s = l <> " | " <> r
     in if 1 < ctx then parens s else s

-- ── Expressions ─────────────────────────────────────────────────────────────

-- | Entry point for expressions (small precedence machine mirroring the parser).
renderExpr :: Expr -> Text
renderExpr = renderExprPrec 0 0

-- | @ctx@ is the precedence context:
--   0 (top) < 1 (++) < 2 (app) < 3 (atom).
--   @indent@ is the current indentation level (number of spaces) for case branches.
--   We parenthesize when inner precedence is strictly lower than @ctx@.
--   Special case: explicit 'EParens' are always preserved verbatim to make
--   parse ∘ render round-trip possible in tests.
renderExprPrec :: Int -> Int -> Expr -> Text
renderExprPrec ctx indent e =
  case e of
    EParens _sp e' ->
      -- Preserve user parentheses exactly as written.
      parens (renderExprPrec 0 indent e')
    ECase _sp scrut alts trailingComments ->
      -- Case is always at top precedence; parenthesize if nested.
      let s = "case " <> renderExprPrec 0 indent scrut <> " of\n" <> renderCaseAlts (indent + 2) alts trailingComments
       in if 0 < ctx then parens s else s
    ELam _sp params body ->
      -- Lambda body extends as far right as possible — same precedence
      -- as 'case', so nested usage adds parens.
      let paramsText = T.intercalate " " (map paramName params)
          s = "\\" <> paramsText <> " -> " <> renderExprPrec 0 indent body
       in if 0 < ctx then parens s else s
    EDo _sp stmts ->
      let stmtLines = map (renderDoStmt (indent + 2)) stmts
          inner = T.intercalate ("\n" <> T.replicate (indent + 2) " ") stmtLines
          s = "do\n" <> T.replicate (indent + 2) " " <> inner
       in if 0 < ctx then parens s else s
    _ ->
      let (prec, s) = case e of
            EVar _sp' q -> (3, renderQName q)
            ELit _sp' (LString t) -> (3, "\"" <> escape t <> "\"")
            ELit _sp' (LInt n) -> (3, show n)
            ECon _sp' n -> (3, n)
            EBuiltIn _sp' n -> (3, "BuiltIn." <> n)
            -- Application is left-assoc: print f at prec 2, arg at atom-precedence
            -- so nested apps on the right get parenthesized.
            EApp _sp' f x ->
              let f' = renderExprPrec 2 indent f
                  x' = renderExprPrec 3 indent x
               in (2, f' <> " " <> x')
            -- For left-assoc @++@: we print the right operand at a tighter
            -- context (2) so a chained ++ on the right becomes parenthesized.
            -- This preserves the original associativity in round-trips.
            EInfix _sp' OpConcat l r ->
              let l' = renderExprPrec 1 indent l
                  r' = renderExprPrec 2 indent r
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

renderCaseAlts :: Int -> NonEmpty CaseAlt -> [Comment] -> Text
renderCaseAlts indent alts trailingComments =
  T.intercalate "\n" (map renderCaseAlt (toList alts) <> map renderIndentedComment trailingComments)
  where
    pad = T.replicate indent " "
    renderCaseAlt (CaseAlt leadingComments pat body mc) =
      T.intercalate
        "\n"
        ( map renderIndentedComment leadingComments
            <> [pad <> renderPattern pat <> " -> " <> renderExprPrec 0 indent body <> renderTrailingComment mc]
        )
    renderIndentedComment c = pad <> renderComment c
    renderTrailingComment = maybe ("" :: Text) (" --" <>)

-- | Render a single 'do' statement with the given indentation.
renderDoStmt :: Int -> DoStmt -> Text
renderDoStmt indent = \case
  DoBind _ pat e -> renderPattern pat <> " <- " <> renderExprPrec 0 indent e
  DoLet _ n e -> "let " <> n <> " = " <> renderExprPrec 0 indent e
  DoExpr _ e -> renderExprPrec 0 indent e

renderPattern :: Pattern -> Text
renderPattern = \case
  PCon _ n [] -> n
  PCon _ n ps -> n <> " " <> T.intercalate " " (map renderPatternAtom ps)
  PVar _ n -> n
  PWild _ -> "_"
  PAscribe _ p ty -> "(" <> renderPattern p <> " : " <> renderType ty <> ")"

-- | Render an atomic pattern, parenthesizing nested constructor applications.
--   'PAscribe' is already self-parenthesised by 'renderPattern' so it's
--   already an atom; no extra parens are needed here.
renderPatternAtom :: Pattern -> Text
renderPatternAtom p@(PCon _ _ (_ : _)) = "(" <> renderPattern p <> ")"
renderPatternAtom p = renderPattern p

-- | Utility: surround text with parentheses.
parens :: Text -> Text
parens t = "(" <> t <> ")"

-- | Render a qualified or unqualified name.
renderQName :: QName -> Text
renderQName (QName mods n) =
  case mods of
    [] -> n
    _ -> T.intercalate "." (mods <> [n])
