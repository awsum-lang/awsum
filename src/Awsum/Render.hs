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
    let header = case args of
          [] -> renderDeclName name
          _ -> renderDeclName name <> " " <> T.intercalate " " (map renderParam args)
        -- Multi-line body forms (ECase / ELet / EDo) cannot carry a
        -- trailing comment after the body — the parser would not see
        -- it on the FunDef's '=' line and would promote it to a
        -- sibling 'CommentDecl'. When 'mc' is present and the body is
        -- multi-line, render the comment on the '=' line and start the
        -- body on the following indented line; the parser accepts this
        -- shape via 'tcomBeforeBody' in 'pFunDefWithEnd'.
        bodyAndComment = case e of
          ELet {} ->
            let (binds, finalBody) = collectLetChain e
                blk = renderLetBlock 2 binds finalBody
             in " =" <> renderTrailingComment mc <> "\n  " <> blk
          ECase {} ->
            -- Without a comment, keep the keyword on the '=' line
            -- ('f x = case … of …') for compatibility with the
            -- existing layout. With a comment, push the body to the
            -- next line so the '=' line is free for the comment.
            case mc of
              Just _ -> " =" <> renderTrailingComment mc <> "\n  " <> renderExpr e
              Nothing -> " = " <> renderExpr e
          EDo {} ->
            case mc of
              Just _ -> " =" <> renderTrailingComment mc <> "\n  " <> renderExpr e
              Nothing -> " = " <> renderExpr e
          _ -> " = " <> renderExpr e <> renderTrailingComment mc
     in header <> bodyAndComment
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
    -- Constructor fields are parsed by 'pTypeAtomNoLineComments' — only
    -- atomic types (TyVar / TyCon / parenthesised). Anything more
    -- complex (TyApp like @IO e a@, TyArrow, TyOr) MUST be parenthesised
    -- on output, otherwise @parse . render@ produces a different AST
    -- (e.g. @Con String IO e a@ would become four single-token fields
    -- instead of @[String, IO e a]@). Using precedence 4 (atom) here
    -- forces the renderer to wrap any non-atom in parens.
    renderConDef (ConDef _ n fs) = n <> " " <> T.intercalate " " (map (renderTypePrec 4) fs)
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
      -- Arm column is established by the first arm itself
      -- (`pCaseNoLineComments` reads `L.indentLevel` after `of`), so
      -- placing arms at indent+2 works regardless of where the 'case'
      -- keyword lands on the line. Scrutinee is rendered at ctx=1 because
      -- the parser's scrutinee grammar ('pConcatNoLineComments') only
      -- accepts atoms, applications and '++' chains — block forms
      -- (ELet / ELam / ECase / EDo) must be wrapped in parens or they
      -- don't reparse. When wrapping in parens, close ')' on a fresh
      -- line so a trailing '--' on the last arm doesn't swallow it.
      let s = "case " <> renderExprPrec 1 indent scrut <> " of\n" <> renderCaseAlts (indent + 2) alts trailingComments
       in if 0 < ctx then "(" <> s <> "\n" <> T.replicate indent " " <> ")" else s
    ELam _sp params body ->
      -- Lambda body extends as far right as possible — same precedence
      -- as 'case', so nested usage adds parens. When the lambda is
      -- itself wrapped in parens, render the body at ctx=1 so any
      -- block-form body (ECase/EDo) gets its own paren wrapping,
      -- preventing a trailing '--' on a nested case arm from eating
      -- the lambda's closing paren.
      let paramsText = T.intercalate " " (map renderParam params)
          bodyCtx = if 0 < ctx then 1 else 0
          s = "\\" <> paramsText <> " -> " <> renderExprPrec bodyCtx indent body
       in if 0 < ctx then parens s else s
    EDo _sp stmts ->
      -- Same close-paren-on-newline trick as 'ECase' — the last
      -- DoStmt (typically a DoExpr containing a case) might end on
      -- a trailing comment that would otherwise swallow the ')'.
      let stmtLines = map (renderDoStmt (indent + 2)) stmts
          inner = T.intercalate ("\n" <> T.replicate (indent + 2) " ") stmtLines
          s = "do\n" <> T.replicate (indent + 2) " " <> inner
       in if 0 < ctx then "(" <> s <> "\n" <> T.replicate indent " " <> ")" else s
    ELet {} ->
      -- Nested 'let' (i.e., not the function-body position handled
      -- in 'renderDecl FunDef'). Single-binding renders as a 2-line
      -- block; a chain of nested 'ELet's collapses to an inline
      -- chain so it stays compact when embedded inside arguments
      -- or other expressions ('print (let a = e1 in let b = e2 in
      -- body)' stays on one line modulo the body itself).
      let (binds, finalBody) = collectLetChain e
          s = case binds of
            [single] -> renderLetBlock indent [single] finalBody
            _ -> renderLetInlineChain indent binds finalBody
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
  DoLet _ pat mAnnot e ->
    let annot = maybe "" (\t -> " : " <> renderType t) mAnnot
     in "let " <> renderPatternAtom pat <> annot <> " = " <> renderExprPrec 0 indent e
  -- ctx=1 so block forms at the head of a DoExpr (specifically ELet)
  -- get wrapped in parens. Without that wrap, the parser's 'pDoLet'
  -- greedily consumes 'let pat = expr' as a do-block-let and leaves
  -- the trailing 'in body' stranded; explicit parens force the full
  -- expression parser to handle 'let pat = expr in body' as one atom.
  -- Wrapping ELam too is benign (no parser ambiguity, just extra parens
  -- in output) and keeps the rule uniform with the other ctx>0 sites.
  DoExpr _ e -> renderExprPrec 1 indent e

-- ── Let-block helpers ───────────────────────────────────────────────────────

-- | Walk a chain of nested 'ELet's and return the bindings in source
--   order plus the eventual non-'ELet' body. Each binding carries
--   its optional type ascription. A single 'ELet a Nothing e body'
--   where @body@ is not itself an 'ELet' returns
--   @([(_, a, Nothing, e)], body)@.
collectLetChain :: Expr -> ([(SrcSpan, Pattern, Maybe Type', Expr)], Expr)
collectLetChain = \case
  ELet sp pat mAnnot rhs body ->
    let (rest, finalBody) = collectLetChain body
     in ((sp, pat, mAnnot, rhs) : rest, finalBody)
  other -> ([], other)

-- | Render a let-block in Haskell-style layout. The @indent@
--   parameter is the column at which the @let@ keyword itself
--   begins (so caller is responsible for placing whatever comes
--   before @let@ on the current line).
--
--   Layout (indices in 0-based offsets):
--
-- @
--     <indent>    let n1 = e1
--     <indent+4>      n2 = e2
--     <indent+1>   in body
-- @
--
--   Single-binding still gets the 2-line shape — the user opted in
--   to "split into 2 lines" for every let, not just multi-binding
--   ones — so a one-binding let is rendered as:
--
-- @
--     <indent>    let n = e
--     <indent+1>   in body
-- @
renderLetBlock :: Int -> [(SrcSpan, Pattern, Maybe Type', Expr)] -> Expr -> Text
renderLetBlock indent binds finalBody =
  let bindCol = indent + 4 -- column of the binding name (after "let ")
      inCol = indent + 1 -- column of "in" — one space indented past "let"
      bodyCol = inCol + 3 -- column of the body that follows "in "
      pad k = T.replicate k " "
      annotText = maybe "" (\t -> " : " <> renderType t)
      bindText (_, pat, mAnnot, rhs) = renderPatternAtom pat <> annotText mAnnot <> " = " <> renderExprPrec 0 bindCol rhs
      firstBind = case binds of
        (b : _) -> b
        [] -> error "renderLetBlock called with no bindings"
      restBinds = drop 1 binds
      firstLine = "let " <> bindText firstBind
      restLines = map (\b -> pad bindCol <> bindText b) restBinds
      inLine = pad inCol <> "in " <> renderExprPrec 0 bodyCol finalBody
   in T.intercalate "\n" (firstLine : restLines ++ [inLine])

-- | Render a chain of 'ELet's as a single inline string @let n1 = e1
--   in let n2 = e2 in body@. Used when the chain appears in a nested
--   position (function argument, infix operand, etc.) where the
--   layout form would be hard to align without column tracking.
renderLetInlineChain :: Int -> [(SrcSpan, Pattern, Maybe Type', Expr)] -> Expr -> Text
renderLetInlineChain indent binds finalBody =
  T.concat
    [ "let " <> renderPatternAtom pat <> annotText mAnnot <> " = " <> renderExprPrec 0 indent rhs <> " in "
    | (_, pat, mAnnot, rhs) <- binds
    ]
    <> renderExprPrec 0 indent finalBody
  where
    annotText = maybe "" (\t -> " : " <> renderType t)

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

-- | Render a function parameter. 'Param' (the common
--   simple-name case) prints as the bare identifier. 'ParamPat'
--   (destructuring patterns introduced via 'paramBinder')
--   always rounds-trips inside parentheses — the parens are
--   syntactically required at the param-binder level so the
--   pattern can be distinguished from a sequence of bare-name
--   parameters.
renderParam :: Param -> Text
renderParam (Param _ n) = n
renderParam (ParamPat _ pat) = "(" <> renderPattern pat <> ")"

-- | Utility: surround text with parentheses.
parens :: Text -> Text
parens t = "(" <> t <> ")"

-- | Render a qualified or unqualified name.
renderQName :: QName -> Text
renderQName (QName mods n) =
  case mods of
    [] -> n
    _ -> T.intercalate "." (mods <> [n])
