-- | Awsum surface /parser/ (Megaparsec).
--
-- Grammar (informal):
--   Program ::= { Import } { TopDecl [newline] }+
--   Import  ::= "import" ModPath
--   TopDecl ::= Sig | FunDef | Comment
--   Sig     ::= lident ":" Type
--   FunDef  ::= lident { lident } "=" Expr
--   Type    ::= Type "->" Type | TypeAtom         -- right-assoc
--   TypeAtom::= UIdent | "(" Type ")"
--   Expr    ::= Lambda | Let | Do | Case | Pipe
--   Pipe    ::= PipeOp { "|>" PipeOp }            -- left-assoc, lowest infix
--   PipeOp  ::= Lambda | Let | Do | Case | Concat -- Expr without Pipe (for left-assoc)
--   Concat  ::= App { "++" App }                  -- left-assoc
--   App     ::= Atom { Atom }                     -- left-assoc
--   Atom    ::= QName | "(" Expr ")" | StringLit
--   QName   ::= { UIdent "." } lident
--
-- Whitespace & comments:
--   • Tokens use 'sc' (horizontal space + line/block comments, does NOT consume newlines).
--   • To preserve trailing inline comments on the same line as a decl, we use
--     the “NoLineComments” variants (which DO NOT skip line comments) on the
--     right-hand side of signatures/definitions and then capture an optional
--     trailing '-- …' before newline/EOF.
--   • Top-level block comments are captured as 'CommentDecl' via a simple
--     non-nested "{- -}" parser; skipping elsewhere still supports nested
--     block comments via Megaparsec's block comment consumer.
--
-- Operator precedence (lowest to highest):
--   1) "|>"   (left-assoc)   — pure syntactic rewrite to application; not a name
--   2) "++"   (left-assoc)
--   3) application (left-assoc)
--   4) atoms
--
-- NOTE: We treat a /declaration terminator/ as either an explicit newline or EOF.
--       This makes multi-decl files unambiguous without semicolons.
module Awsum.Parser (parseProgram, parseProgramDiagnostic) where

import Awsum.Syntax
import Data.Char qualified as Char
import Data.Text qualified as T
import Relude
import Text.Megaparsec (Parsec, eof, try)
import Text.Megaparsec qualified as P
import Text.Megaparsec.Char qualified as C
import Text.Megaparsec.Char.Lexer qualified as L

-- Megaparsec over 'Text'
type Parser = Parsec Void Text

-- ────────────────────────────────────────────────────────────────────────────
-- Space consumers & lexeme/symbol helpers
-- ────────────────────────────────────────────────────────────────────────────

-- | Skip /horizontal/ space + comments (does NOT consume newlines).
sc :: Parser ()
sc = L.space C.hspace1 (L.skipLineComment "--") (L.skipBlockComment "{-" "-}")

-- | Spaces + block comments, but **no** line comments (so '--' stays visible).
scNoLineComments :: Parser ()
scNoLineComments = L.space C.hspace1 P.empty (L.skipBlockComment "{-" "-}")

-- | Attach space consumer to a token parser.
lexeme :: Parser a -> Parser a
lexeme = L.lexeme sc

-- | Parse a symbolic token (like "->" or "(") and consume trailing 'sc'.
symbol :: Text -> Parser Text
symbol = L.symbol sc

-- | Convenience for string symbols under 'sc'.
sym :: String -> Parser Text
sym = symbol . toText

-- Helpers bound to the “no line comments” consumer.
lexemeNoLine :: Parser a -> Parser a
lexemeNoLine = L.lexeme scNoLineComments

symbolNoLine :: Text -> Parser Text
symbolNoLine = L.symbol scNoLineComments

symNoLine :: String -> Parser Text
symNoLine = symbolNoLine . toText

-- Whitespace-only (no comments) — handy when peeking for trailing line comments.
hspaceNoComments :: Parser ()
hspaceNoComments = L.space C.hspace1 P.empty P.empty

skipBlankLinesNoComments :: Parser ()
skipBlankLinesNoComments = void $ P.many (try (hspaceNoComments *> C.eol))

-- ────────────────────────────────────────────────────────────────────────────
-- Identifiers & reserved words
-- ────────────────────────────────────────────────────────────────────────────

-- | Tail characters allowed in identifiers.
identChar :: Parser Char
identChar = C.alphaNumChar <|> C.char '_' <|> C.char '\''

-- | Predicate for identifier tails (used by 'takeWhileP').
isIdentTail :: Char -> Bool
isIdentTail c = Char.isAlphaNum c || c == '_' || c == '\''

-- | First character allowed in a /binder/ (function parameter or pattern
--   variable): a regular lowercase letter OR an underscore. The underscore
--   forms (@_@ alone or @_foo@) signal an intentionally unused binding.
isBinderStart :: Char -> Bool
isBinderStart c = Char.isLower c || c == '_'

-- | Reserved words that cannot be used as identifiers.
reserved :: [Text]
reserved = ["import", "type", "case", "of", "do", "let", "in", "empty"]

-- | Recognize a reserved word /without/ swallowing identifier tails.
--   e.g. parsing \"import\" will fail on \"importX\".
rword :: Text -> Parser ()
rword w = (lexeme . try) (P.chunk w *> P.notFollowedBy identChar)

rwordS :: String -> Parser ()
rwordS = rword . toText

-- | Reserved word under no-line-comments space consumer.
rwordNoLine :: Text -> Parser ()
rwordNoLine w = (lexemeNoLine . try) (P.chunk w *> P.notFollowedBy identChar)

-- | Lower-case-or-underscore identifier (value/function name, parameter,
--   pattern variable, type variable). Rejects reserved words.
--   Names starting with @_@ are syntactically valid but semantically
--   "intentionally unused" — referencing them is rejected by the typechecker
--   with a dedicated error, and they are excluded from the unused-binding
--   warnings.
lident :: Parser Name
lident = (lexeme . try) $ do
  x <- P.satisfy isBinderStart
  xs <- P.takeWhileP (Just "ident tail") isIdentTail
  let w = T.cons x xs
  guard (w `notElem` reserved)
  pure w

-- | Top-level declaration name: an 'lident' or a parenthesised operator like
--   @(++)@. The operator form lets the prelude spell the infix symbol itself —
--   e.g. @(++) = BuiltIn.concatString@ — so go-to-definition on @a ++ b@ lands
--   on the same binding, instead of a differently-named helper.
--   The internal 'Name' stored for @(++)@ is @"++"@.
declName :: Parser Name
declName = parenOp <|> lident
  where
    parenOp =
      lexeme . try $ do
        _ <- C.char '('
        op <- P.chunk "++"
        _ <- C.char ')'
        pure op

-- | Upper-case identifier (module/type constructor name), without the
--   lexeme/whitespace handling — wrapped by 'uidentNoLine' or used
--   directly by callers that have their own whitespace strategy.
--   Accepts:
--     • @Foo@ — the normal shape;
--     • @_Foo@ — explicitly marked as intentionally unused;
--     • @_@ — bare underscore, parsed so the typechecker can reject it
--       with a friendlier message than Megaparsec's default.
--   Does NOT accept @_foo@ (underscore + lowercase): that's a value-style
--   name and would be ambiguous as a type/constructor.
uidentBody :: Parser Name
uidentBody = do
  underscore <- P.option "" (T.singleton <$> C.char '_')
  if T.null underscore
    then do
      x <- C.upperChar
      xs <- P.takeWhileP (Just "ident tail") isIdentTail
      pure (T.cons x xs)
    else
      P.choice
        [ -- "_X..." — the typical "intentionally unused" shape.
          do
            x <- C.upperChar
            xs <- P.takeWhileP (Just "ident tail") isIdentTail
            pure (underscore <> T.cons x xs),
          -- Bare "_" — only when the next char isn't part of a name,
          -- so "_foo" doesn't sneak in as "_" + leftover.
          P.notFollowedBy (P.satisfy isIdentTail) $> underscore
        ]

-- No-line-comment variants (used where we must not eat '--').
lidentNoLine :: Parser Name
lidentNoLine = (lexemeNoLine . try) $ do
  x <- P.satisfy isBinderStart
  xs <- P.takeWhileP (Just "ident tail") isIdentTail
  let w = T.cons x xs
  guard (w `notElem` reserved)
  pure w

uidentNoLine :: Parser Name
uidentNoLine = (lexemeNoLine . try) uidentBody

-- | Parse the textual form of a binder (function parameter / pattern
--   variable head). Accepts @_@, @_foo@, or @foo@; reserved words are
--   rejected. Does NOT consume trailing whitespace.
binderName :: Parser Name
binderName = try $ do
  x <- P.satisfy isBinderStart
  xs <- P.takeWhileP (Just "ident tail") isIdentTail
  let w = T.cons x xs
  guard (w `notElem` reserved)
  pure w

-- | Parse a function-parameter binder together with its source span (covers
--   only the identifier itself, not trailing whitespace), so quick-fixes
--   that target a single parameter have the right edit range.
paramBinder :: Parser Param
paramBinder = paramBinderG sc

-- | Variant of 'paramBinder' for contexts (type declarations) that
--   must not swallow trailing @--@ line comments. Always a simple
--   name — type parameters can't be destructuring patterns.
paramBinderNoLine :: Parser Param
paramBinderNoLine = do
  start <- P.getSourcePos
  name <- binderName
  end <- P.getSourcePos
  scNoLineComments
  pure (Param (toSrcSpan start end) name)

-- | Generic parameter parser. A function parameter is either a
--   simple binder name (the common case: @f x y = …@) or a
--   parens-wrapped destructuring pattern (@f (Tuple3 a b c) = …@).
--   The parens are mandatory for destructuring — without them,
--   @f Tuple3 a b c = …@ would be ambiguous between «one
--   pattern with three fields» and «four bare-name parameters».
--
--   When the parens-wrapped pattern collapses to a 'PVar' (i.e.
--   the user wrote @(x)@ instead of @x@), we still produce a
--   'Param' rather than 'ParamPat': the round-trip will lose
--   the redundant parens, which the formatter's overall stance
--   («canonical layout, no decorative parens») already does
--   for 'EParens' elsewhere.
paramBinderG :: Parser () -> Parser Param
paramBinderG spaceConsumer = do
  start <- P.getSourcePos
  pat <- patternBinder <|> nameBinder
  end <- P.getSourcePos
  spaceConsumer
  let sp = toSrcSpan start end
  pure $ case pat of
    Left n -> Param sp n
    Right (PVar _ n) -> Param sp n
    Right p -> ParamPat sp p
  where
    nameBinder = Left <$> binderName
    patternBinder = Right <$> P.try pParenOrAscribePattern

-- ────────────────────────────────────────────────────────────────────────────
-- Entry point
-- ────────────────────────────────────────────────────────────────────────────

-- | Parse a full program from 'Text'.
parseProgram :: Text -> Either Text Program
parseProgram src =
  case P.parse (pProgram <* eof) "<stdin>" src of
    Left e -> Left (toText (P.errorBundlePretty e))
    Right p -> Right p

-- | Parse with structured error output (line, column, message) for IDE integration.
parseProgramDiagnostic :: Text -> Either [(SrcSpan, Text)] Program
parseProgramDiagnostic src =
  case P.parse (pProgram <* eof) "<stdin>" src of
    Right p -> Right p
    Left bundle ->
      let errs = toList (P.bundleErrors bundle)
          posState = P.bundlePosState bundle
       in Left (extractErrors posState errs)
  where
    extractErrors :: P.PosState Text -> [P.ParseError Text Void] -> [(SrcSpan, Text)]
    extractErrors _ [] = []
    extractErrors ps (e : rest) =
      let (_, ps') = P.reachOffset (P.errorOffset e) ps
          pos = P.pstateSourcePos ps'
          l = P.unPos (P.sourceLine pos)
          c = P.unPos (P.sourceColumn pos)
          sp = SrcSpan l c l c
          msg = toText (P.parseErrorTextPretty e)
       in (sp, T.stripEnd msg) : extractErrors ps' rest

-- ────────────────────────────────────────────────────────────────────────────
-- Source position helpers
-- ────────────────────────────────────────────────────────────────────────────

-- | Convert a Megaparsec 'P.SourcePos' pair to a 'SrcSpan'.
toSrcSpan :: P.SourcePos -> P.SourcePos -> SrcSpan
toSrcSpan start end =
  SrcSpan
    (P.unPos (P.sourceLine start))
    (P.unPos (P.sourceColumn start))
    (P.unPos (P.sourceLine end))
    (P.unPos (P.sourceColumn end))

-- | Run a parser and capture the span around it.
withSpan :: Parser a -> Parser (SrcSpan, a)
withSpan p = do
  start <- P.getSourcePos
  result <- p
  end <- P.getSourcePos
  pure (toSrcSpan start end, result)

-- Program ────────────────────────────────────────────────────────────────────

pProgram :: Parser Program
pProgram = do
  modCom <- pOptionalModuleComment
  -- Imports come in two flavours: the FIRST import must not carry any
  -- leading comments (those would be module-comment material that was
  -- either consumed above or is a syntactic mistake), but later
  -- imports may have leading comments — that's how a "commented-out
  -- import" between live imports is expressed. If the file has no
  -- imports at all the first parser falls through and ordinary
  -- top-level parsing (CommentDecl, decls) takes over.
  firstImp <- P.optional (try pImportNoLeading)
  imps <- case firstImp of
    Just imp -> do
      rest <- P.many (try pImport)
      pure (imp : rest)
    Nothing -> pure []
  skipBlankLinesNoComments
  ds <- P.some (pTopDeclOrComment <* skipBlankLinesNoComments)
  let declsNE = case ds of
        d : rest -> d :| rest
        [] -> error "impossible: P.some returned []"
  pure Program {moduleComment = modCom, imports = imps, decls = attachDocs declsNE}

-- | Optional single block-comment header at the very top of a file.
--   Form: exactly one @{- … -}@ block. Whether it is followed by a
--   blank line or sits glued to the next line is a formatting concern
--   handled by 'awsum format' — the parser accepts both shapes and
--   returns the block's text without delimiters.
--
--   Forbidden in this position:
--
--     * line comments — line comments at the very top of the file are
--       surfaced as a parse error pointing the user at @{- … -}@.
--     * a second block comment immediately after the first — the
--       second @{-@ ends up in "before-first-import" position which
--       'pProgram' rejects (it tries 'pImportNoLeading' first; with
--       a stray @{-@ in the way that fails to commit, and the next
--       attempt parses the @{-@ as a 'CommentDecl' or — if it is
--       followed by @import@ — falls into 'pImport' which would
--       attach it as a leading comment of the first import, which
--       in turn the elaborator catches as misplaced module-comment
--       material).
--
--   When absent (the file does not start with @{-@), returns 'Nothing'
--   without consuming anything beyond leading blank lines.
pOptionalModuleComment :: Parser (Maybe Text)
pOptionalModuleComment = do
  skipBlankLinesNoComments
  P.notFollowedBy (P.chunk "--")
    P.<?> "no line comments allowed at the top of the file (use a {- module comment -} block instead)"
  P.optional $ try $ do
    txt <- pBlockCommentText
    hspaceNoComments
    void C.eol <|> P.eof
    -- Distinguishes a /module/ comment from a /doc/ comment on the
    -- first declaration. A module comment is followed by a blank
    -- line (the canonical formatter shape), end-of-file, or an
    -- @import@. A leading block comment immediately followed by a
    -- top-level declaration is the doc of that declaration —
    -- 'attachDocs' lifts it into the decl's 'docComment' field; the
    -- 'try' above rolls back so the block isn't consumed here.
    moduleCommentTrailing
    skipBlankLinesNoComments
    pure txt
  where
    moduleCommentTrailing :: Parser ()
    moduleCommentTrailing =
      P.choice
        [ void (P.lookAhead (try (hspaceNoComments *> C.eol))),
          P.eof,
          void (P.lookAhead (try (hspaceNoComments *> P.chunk "import")))
        ]

-- | First-import variant: no leading comments allowed. Such comments
--   would either be module-comment material (which 'pOptionalModuleComment'
--   handles above) or a misplaced "commented-out import" before any
--   live import. We commit on the literal 'import' keyword, so any
--   stray '{-' or '--' here causes this combinator to fail without
--   consuming input — letting 'pProgram' fall through to declaration
--   parsing.
pImportNoLeading :: Parser ImportDecl
pImportNoLeading = do
  skipBlankLinesNoComments
  hspaceNoComments
  rwordNoLine "import"
  modPath <- pModPath
  tcom <- pTrailingLineCommentMaybe
  endLineOrEOF
  pure (ImportDecl [] modPath tcom)

pImport :: Parser ImportDecl
pImport = do
  skipBlankLinesNoComments
  leadComments <- P.many $ try $ do
    hspaceNoComments
    c <- (LineComment <$> pLineCommentText) <|> (BlockComment <$> pBlockCommentText)
    hspaceNoComments
    void C.eol
    skipBlankLinesNoComments
    pure c
  hspaceNoComments
  rwordNoLine "import"
  modPath <- pModPath
  tcom <- pTrailingLineCommentMaybe
  endLineOrEOF
  pure (ImportDecl leadComments modPath tcom)

pModPath :: Parser (NonEmpty Name)
pModPath = do
  h <- uidentNoLine
  ts <- P.many (symNoLine "." *> uidentNoLine)
  pure (h :| ts)

-- Top-level items ────────────────────────────────────────────────────────────

-- | Top-level item: either a top-level comment or a declaration.
pTopDeclOrComment :: Parser Decl
pTopDeclOrComment =
  pTopComment
    <|> pTypeDeclWithEnd
    <|> try pSigWithEnd
    <|> pFunDefWithEnd

-- | Top-level comments. Both forms — @-- …@ line and @{- … -}@ block —
--   are captured into 'CommentDecl' with the span of the comment
--   delimiters and content. The span is consumed by 'attachDocs' to
--   decide whether the comment is adjacent (no blank line) to the next
--   declaration and should be lifted into its 'docComment' field.
--
--   Block-comment text is captured by the balanced 'pBlockCommentText',
--   so nested @{- … -}@ inside the comment body is preserved verbatim.
--
--   The captured 'end' position is taken /before/ the optional trailing
--   newline on a line comment. Otherwise consuming the @\n@ would push
--   the end position to the start of the next line, making
--   \"comment-then-decl on adjacent lines\" indistinguishable from
--   \"comment-then-blank-line-then-decl\" (the rule that decides whether
--   the comment becomes a docstring).
pTopComment :: Parser Decl
pTopComment = do
  hspaceNoComments
  start <- P.getSourcePos
  (c, end) <-
    ( do
        t <- pLineCommentText
        e <- P.getSourcePos
        _ <- P.optional C.eol
        pure (LineComment t, e)
    )
      <|> ( do
              t <- pBlockCommentText
              e <- P.getSourcePos
              pure (BlockComment t, e)
          )
  pure (CommentDecl (toSrcSpan start end) c)

pLineCommentText :: Parser Text
pLineCommentText = do
  _ <- P.chunk "--"
  P.takeWhileP (Just "not newline") (/= '\n')

-- | Block comment text with **balanced** nesting: @{- outer {- inner -} more -}@
--   is captured as one comment (text @"outer {- inner -} more"@), not two
--   declarations. The previous @manyTill anySingle "-}"@ form was a latent bug
--   that closed the comment at the first @-}@ and left the rest of the content
--   to confuse downstream parsing.
--
--   Implementation: maintain a depth counter, descending into nested @{-@ and
--   ascending out of matching @-}@. On EOF with the counter still positive the
--   parser fails with an explicit \"unterminated block comment\" message. The
--   error position is at EOF rather than at the opening @{-@ — pointing at the
--   opening @{-@ would be friendlier, but @P.setOffset@ inside @fail@ produced
--   unrelated locations in Megaparsec's error bundle, so the simpler form is
--   used; the message is the actionable part.
pBlockCommentText :: Parser Text
pBlockCommentText = do
  _ <- P.chunk "{-"
  toText <$> go (1 :: Int) []
  where
    go 0 acc = pure (reverse acc)
    go depth acc = do
      atEof <- P.atEnd
      when atEof
        $ fail "unterminated block comment: reached end of file while still inside a '{- ... -}' block"
      P.choice
        [ P.chunk "{-" *> go (depth + 1) ('-' : '{' : acc),
          P.chunk "-}"
            *> if depth == 1
              then go 0 acc
              else go (depth - 1) ('}' : '-' : acc),
          P.anySingle >>= \c -> go depth (c : acc)
        ]

-- Declarations ───────────────────────────────────────────────────────────────

-- | Signature line: keep inline trailing '-- …' if present.
pSigWithEnd :: Parser Decl
pSigWithEnd = do
  start <- P.getSourcePos
  name <- declName
  _ <- sym ":"
  ty <- pTypeNoLineComments
  tcom <- pTrailingLineCommentMaybe
  end <- P.getSourcePos
  endLineOrEOF
  pure (Sig (toSrcSpan start end) name ty tcom Nothing)

-- | Sum type declaration. Two surface forms:
--
--   @type Lookup a = Found a | NotFound@ — ordinary form. Zero
--   constructors (no @=@) declares an uninhabited type that is still
--   a /distinct row label/: @type Never@ here would unify only with
--   itself.
--
--   @empty type X@ — declared as the row identity. Forbidden:
--   parameters and constructors; the parser fails fast with a
--   dedicated message if either appears. All @empty type@
--   declarations interchange in row positions; see
--   'Awsum.HM.rowSubsume' and the @TyEmpty@ constructor in
--   'Awsum.Syntax.Type''.
pTypeDeclWithEnd :: Parser Decl
pTypeDeclWithEnd = do
  start <- P.getSourcePos
  emptyKind <- P.option NotEmpty (Empty <$ rwordS "empty")
  rwordS "type"
  -- 'uidentNoLine' (not the line-comment-aware variant) so a
  -- trailing '-- …' on the declaration's line stays for
  -- 'pTrailingLineCommentMaybe' to pick up; otherwise the
  -- line-comment-aware 'lexeme' would consume it as whitespace.
  name <- uidentNoLine
  -- 'empty type' forbids parameters and constructors. Look for them
  -- in the input and fail with a tailored message rather than letting
  -- the parser silently reinterpret the declaration.
  case emptyKind of
    Empty -> do
      mTvarStart <- P.optional (P.lookAhead paramBinderNoLine)
      whenJust mTvarStart $ \_ ->
        fail "'empty type' must have no type parameters"
      mEq <- P.optional (P.lookAhead (sym "="))
      whenJust mEq $ \_ ->
        fail "'empty type' must have no constructors (drop the '=' clause)"
    NotEmpty -> pass
  tvars <- P.many paramBinderNoLine
  cons <- P.option [] $ do
    -- '=' may sit on the header line (one- or two-constructor compact
    -- form, @type Foo = A | B@) or on a fresh indented continuation
    -- line (multi-constructor form emitted by the formatter when the
    -- list has three or more constructors). 'optIndentedContinuation'
    -- is rollback-safe: when there is no indented continuation it
    -- consumes nothing.
    optIndentedContinuation
    _ <- sym "="
    firstCon <- pConDefNoLine
    -- Each subsequent '|' is allowed on the same line (compact form)
    -- or at the start of a fresh indented continuation line. The
    -- 'try' makes the lookahead for the '|' and its preceding
    -- newline roll back cleanly when there are no more constructors,
    -- so the trailing '--' / 'endLineOrEOF' below see the input as if
    -- the parser had stopped right after the last 'pConDefNoLine'.
    restCons <- P.many $ try $ do
      optIndentedContinuation
      _ <- symNoLine "|"
      pConDefNoLine
    pure (firstCon : restCons)
  tcom <- pTrailingLineCommentMaybe
  end <- P.getSourcePos
  endLineOrEOF
  pure (TypeDecl (toSrcSpan start end) name tvars cons tcom emptyKind Nothing)

-- | Constructor definition: @Found a@ or @NotFound@. The constructor's
--   name span (captured before trailing whitespace) is preserved so
--   rename quick-fixes can target it precisely.
pConDefNoLine :: Parser ConDef
pConDefNoLine = do
  start <- P.getSourcePos
  name <- try uidentBody
  end <- P.getSourcePos
  scNoLineComments
  flds <- P.many pTypeAtomNoLineComments
  pure (ConDef (toSrcSpan start end) name flds)

-- | Definition line: keep inline trailing '-- …' if present.
pFunDefWithEnd :: Parser Decl
pFunDefWithEnd = do
  start <- P.getSourcePos
  name <- declName
  args <- P.many paramBinder
  -- 'symNoLine' (not 'sym') so a trailing '-- …' immediately after
  -- '=' is left for 'pTrailingLineCommentMaybe' below; the
  -- line-comment-aware 'lexeme' inside plain 'sym' would otherwise
  -- absorb it as whitespace (along with the following indent line),
  -- and the comment would be silently dropped on multi-line bodies.
  _ <- symNoLine "="
  -- Optional trailing comment on the '=' line. Only meaningful when
  -- the body is a multi-line form (ECase / ELet / EDo) — for
  -- single-line bodies the canonical comment position is /after/ the
  -- body, captured by 'tcomAfterBody' below. We try here too so that
  -- a hand-written single-line shape with a comment in this position
  -- (e.g. @f x = -- weird\n  body@) doesn't lose the comment.
  tcomBeforeBody <- pTrailingLineCommentMaybe
  -- Allow the body to start on the following indented line — the
  -- formatter emits this shape for any 'let' body so the
  -- 'let'/'in' columns line up predictably; a '_' optional newline
  -- here keeps the rule permissive enough that hand-written
  -- 'name args =\n  body' parses too. The expression parser
  -- handles its own further layout from there.
  _ <- P.optional $ try $ do
    void C.eol
    skipBlankLinesNoComments
    hspaceNoComments
  e <- pExprNoLineComments
  case e of
    ECase {} -> do
      end <- P.getSourcePos
      -- Multi-line case expression already consumed trailing newlines.
      -- We may be at the start of the next content line or EOF.
      pure (FunDef (toSrcSpan start end) name args e tcomBeforeBody Nothing)
    ELet {} -> do
      -- Same as 'ECase': a 'let' block may span multiple lines, so
      -- 'endLineOrEOF' below would mis-fire. The let parser has
      -- already consumed through the trailing body expression.
      end <- P.getSourcePos
      pure (FunDef (toSrcSpan start end) name args e tcomBeforeBody Nothing)
    EDo {} -> do
      -- Same multi-line layout as ECase/ELet.
      end <- P.getSourcePos
      pure (FunDef (toSrcSpan start end) name args e tcomBeforeBody Nothing)
    _ -> do
      tcomAfterBody <- pTrailingLineCommentMaybe
      end <- P.getSourcePos
      endLineOrEOF
      -- Single-line bodies: prefer the after-body comment when both
      -- positions are filled. The renderer only ever fills one; the
      -- '<|>' fallback is for unusual hand-written input.
      pure (FunDef (toSrcSpan start end) name args e (tcomAfterBody <|> tcomBeforeBody) Nothing)

-- | Consume spaces (not comments), then an optional trailing line comment.
pTrailingLineCommentMaybe :: Parser (Maybe Text)
pTrailingLineCommentMaybe = do
  hspaceNoComments
  P.optional pLineCommentText

-- | End of declaration: newline or EOF.
endLineOrEOF :: Parser ()
endLineOrEOF = void C.eol <|> P.eof

-- | Consume an optional indented continuation: a newline followed by
--   any number of blank lines and finally landing at any column @> 1@.
--   Used by 'pTypeDeclWithEnd' to allow the @=@ and each subsequent
--   @|@ in a multi-line ADT declaration to appear on a fresh indented
--   line. Rollback-safe — when there is no eol next, or when the next
--   non-blank content sits at column 1, consumes nothing.
optIndentedContinuation :: Parser ()
optIndentedContinuation = void $ P.optional $ try $ do
  void C.eol
  skipBlankLinesNoComments
  hspaceNoComments
  lvl <- L.indentLevel
  guard (lvl > P.pos1)

-- Types (right-assoc arrows) ────────────────────────────────────────────────

-- | Types with a space consumer that does not skip line comments.
--   Grammar: Type = TypeApp , { "->" , Type } ;
-- | Top-level type expression: a chain of @|@-separated arrow types.
--   @|@ has lower precedence than @->@, so @(A | B) -> C@ requires
--   explicit parens around the union to keep it on the LHS of the arrow
--   (without parens, @A | B -> C@ parses as @A | (B -> C)@). Right-
--   associative as parsed; the unifier later treats @|@ set-associatively.
pTypeNoLineComments :: Parser Type'
pTypeNoLineComments = do
  t1 <- pTypeArrowNoLineComments
  P.option
    t1
    ( do
        _ <- symNoLine "|"
        t2 <- pTypeNoLineComments
        pure (TyOr (spanBetween (typeSpan t1) (typeSpan t2)) t1 t2)
    )

-- | Arrow-type layer: @a -> b@, right-associative.
pTypeArrowNoLineComments :: Parser Type'
pTypeArrowNoLineComments = do
  t1 <- pTypeAppNoLineComments
  P.option
    t1
    ( do
        _ <- symNoLine "->"
        t2 <- pTypeArrowNoLineComments
        pure (TyArrow (spanBetween (typeSpan t1) (typeSpan t2)) t1 t2)
    )

-- | Type application: @Lookup String@, left-associative.
--   Grammar: TypeApp = TypeAtom , { TypeAtom } ;
pTypeAppNoLineComments :: Parser Type'
pTypeAppNoLineComments = do
  t <- pTypeAtomNoLineComments
  ts <- P.many pTypeAtomNoLineComments
  pure (foldl' appWithSpan t ts)
  where
    appWithSpan f x = TyApp (spanBetween (typeSpan f) (typeSpan x)) f x

-- | A single type atom: constructor, variable, or parenthesized type.
--   The span captured here covers just the identifier (or the whole
--   parenthesised expression), so a diagnostic targeting e.g. @_A@ in
--   @foo : _A -> String@ highlights only @_A@.
pTypeAtomNoLineComments :: Parser Type'
pTypeAtomNoLineComments =
  pTyConAtom
    <|> pTyVarAtom
    <|> pTyParens
  where
    pTyConAtom = do
      start <- P.getSourcePos
      n <- try uidentBody
      end <- P.getSourcePos
      scNoLineComments
      pure (TyCon (toSrcSpan start end) n)
    pTyVarAtom = do
      start <- P.getSourcePos
      n <- try $ do
        x <- P.satisfy isBinderStart
        xs <- P.takeWhileP (Just "ident tail") isIdentTail
        let w = T.cons x xs
        guard (w `notElem` reserved)
        pure w
      end <- P.getSourcePos
      scNoLineComments
      pure (TyVar (toSrcSpan start end) n)
    pTyParens = do
      start <- P.getSourcePos
      _ <- symNoLine "("
      inner <- pTypeNoLineComments
      _ <- symNoLine ")"
      end <- P.getSourcePos
      -- Span covers the parentheses so the whole parenthesised type is
      -- addressable, not just its inner atom.
      pure (reSpan (toSrcSpan start end) inner)
    -- Replace the top-level span of a type. Used after parsing parens to
    -- grow the inner span out to the enclosing '(' ')'.
    reSpan sp = \case
      TyVar _ n -> TyVar sp n
      TyCon _ n -> TyCon sp n
      -- The parser never directly produces 'TyEmpty' (resolution from
      -- a name to the empty-type marker happens later, in
      -- 'Awsum.Typing'); this branch is here only so 'reSpan' is
      -- exhaustive over 'Type''.
      TyEmpty _ n -> TyEmpty sp n
      TyApp _ f x -> TyApp sp f x
      TyArrow _ a b -> TyArrow sp a b
      TyOr _ a b -> TyOr sp a b

-- Expressions ───────────────────────────────────────────────────────────────

-- | Lowest precedence layer: @\\x -> …@, @let …@, @do …@, @case …@, or
--   a @|>@ pipe chain (which itself bottoms out in a @++@ chain).
pExprNoLineComments :: Parser Expr
pExprNoLineComments =
  pLambdaNoLineComments
    <|> pLetNoLineComments
    <|> pDoNoLineComments
    <|> pCaseNoLineComments
    <|> pPipeNoLineComments

-- | Left-associative chain of @PipeOp@ separated by @|>@. The right-hand
--   side parses through 'pPipeOpNoLineComments' rather than recursing
--   into 'pPipeNoLineComments' so that @x |> y |> z@ binds as
--   @(x |> y) |> z@; using 'pExprNoLineComments' on the right would
--   make it right-associative.
--
--   The right-hand side still admits a lambda / @let@ / @do@ / @case@
--   (so @x |> \\y -> y@ is @(\\y -> y) x@), since these constructs
--   have the same precedence rank as the pipe chain itself — they
--   just don't loop.
--
--   A @|>@ may appear either on the same line as the previous
--   'PipeOp' or on a new indented line. The new-line form requires
--   strictly positive indent so a top-level declaration starting at
--   column 1 cannot be mistaken for a chain continuation. The
--   formatter normalises to the multi-line form for chains of two or
--   more operators; chains of one operator stay inline.
pPipeNoLineComments :: Parser Expr
pPipeNoLineComments = do
  x <- pConcatNoLineComments
  let pipeOnNewLine = do
        void C.eol
        skipBlankLinesNoComments
        hspaceNoComments
        lvl <- L.indentLevel
        guard (lvl > P.pos1)
      rest acc =
        ( do
            _ <- try (P.optional (try pipeOnNewLine) *> symNoLine "|>")
            y <- pPipeOpNoLineComments
            rest (EInfix (spanBetween (exprSpan acc) (exprSpan y)) OpPipe acc y)
        )
          <|> pure acc
  rest x

-- | RHS of a @|>@: every alternative of 'pExprNoLineComments' /except/
--   'pPipeNoLineComments' itself. Splitting this layer is what enforces
--   left-associativity for @|>@.
pPipeOpNoLineComments :: Parser Expr
pPipeOpNoLineComments =
  pLambdaNoLineComments
    <|> pLetNoLineComments
    <|> pDoNoLineComments
    <|> pCaseNoLineComments
    <|> pConcatNoLineComments

-- | Let-binding. Two surface shapes are accepted, both producing a
--   chain of nested 'ELet's:
--
--     * Inline single binding:  @let n = e in body@
--     * Layout multi-binding:   @let n1 = e1@ on the first line,
--       additional @ni = ei@ aligned on subsequent lines at the
--       same column as @n1@, and @in body@ on a line whose
--       indentation is /strictly less/ than the bindings column
--       (Haskell convention: @in@ is dedented relative to the
--       bindings).
--
--   The body extends as far right as possible (same precedence as
--   'case' / lambda). The bound name is a regular lower-case
--   identifier; pattern bindings on the LHS of @=@ are not
--   supported yet.
pLetNoLineComments :: Parser Expr
pLetNoLineComments = do
  rwordNoLine "let"
  -- The column where the first binding's name starts is the
  -- reference for any continuation bindings.
  refCol <- L.indentLevel
  firstBind <- pLetBinding
  restBinds <- P.many $ try $ do
    void C.eol
    hspaceNoComments
    lvl <- L.indentLevel
    guard (lvl == refCol)
    pLetBinding
  -- 'in' is either inline after the last binding's RHS, or on a
  -- new line at any column strictly less than the bindings column.
  let pInDedented = try $ do
        void C.eol
        hspaceNoComments
        lvl <- L.indentLevel
        guard (lvl < refCol)
        rwordNoLine "in"
  pInDedented <|> rwordNoLine "in"
  body <- pExprNoLineComments
  let buildChain = foldr (\(bsp, n, mAnnot, e) acc -> ELet bsp n mAnnot e acc) body
  pure (buildChain (firstBind : restBinds))
  where
    -- A let-binding's LHS is a pattern, so destructuring forms
    -- like @let (Tuple3 a b c) = e@ work alongside the simple
    -- @let n = e@ shape. The ascription path is the same:
    -- @let pat : T = e@ — but the typechecker rejects an
    -- ascription on a non-'PVar' pattern (the ascription
    -- belongs on the right-hand side, not the destructured
    -- binder). Without an ascription, 'PVar'-let synthesises
    -- the RHS as before; non-'PVar'-let desugars to a
    -- single-arm 'ECase' which the standard exhaustiveness
    -- check then validates.
    pLetBinding :: Parser (SrcSpan, Pattern, Maybe Type', Expr)
    pLetBinding = do
      bspS <- P.getSourcePos
      pat <- pPatternNoLineComments
      mAnnot <- P.optional $ try $ do
        _ <- symNoLine ":"
        pTypeNoLineComments
      _ <- symNoLine "="
      e <- pExprNoLineComments
      bspE <- P.getSourcePos
      pure (toSrcSpan bspS bspE, pat, mAnnot, e)

-- | Lambda abstraction: @\\x y -> body@. At least one parameter; the
--   body extends as far right as possible (same precedence as 'case').
pLambdaNoLineComments :: Parser Expr
pLambdaNoLineComments = do
  start <- P.getSourcePos
  _ <- symNoLine "\\"
  params <-
    P.some (paramBinderG scNoLineComments)
  _ <- symNoLine "->"
  body <- pExprNoLineComments
  end <- P.getSourcePos
  pure (ELam (toSrcSpan start end) params body)

-- Left-associative chain of @App@ separated by @++@.
pConcatNoLineComments :: Parser Expr
pConcatNoLineComments = do
  x <- pAppNoLineComments
  let rest acc =
        ( do
            _ <- symNoLine "++"
            y <- pAppNoLineComments
            rest (EInfix (spanBetween (exprSpan acc) (exprSpan y)) OpConcat acc y)
        )
          <|> pure acc
  rest x

-- Left-associative application (one or more atoms).
pAppNoLineComments :: Parser Expr
pAppNoLineComments = do
  t0 <- pAtomNoLineComments
  ts <- P.many pAtomNoLineComments
  pure (foldl' (\f x -> EApp (spanBetween (exprSpan f) (exprSpan x)) f x) t0 ts)

-- Atomic expression: qualified/unqualified name, constructor, parenthesized expr, or string literal.
pAtomNoLineComments :: Parser Expr
pAtomNoLineComments =
  pQualifiedNameExprNoLineComments
    <|> pConNoLineComments
    <|> pParensNoLineComments
    <|> pLitNoLineComments

pConNoLineComments :: Parser Expr
pConNoLineComments = do
  (sp, n) <- withSpan uidentNoLine
  pure (ECon sp n)

pParensNoLineComments :: Parser Expr
pParensNoLineComments = do
  start <- P.getSourcePos
  _ <- symNoLine "("
  e <- pExprNoLineComments
  -- Optional expression-level type ascription: @(e : T)@. Symmetric
  -- to 'pParenOrAscribePattern' on the pattern side. The ':' cannot
  -- appear inside a bare expression, so there is no ambiguity with
  -- @pExprNoLineComments@ above — if a ':' follows here, it is the
  -- ascription colon, full stop.
  --
  -- Wrapped in 'try' because we also allow an optional newline + indent
  -- before the @':'@ — needed for multi-line inner expressions
  -- (@(case … of … \\n : T)@). If the newline is consumed but no @':'@
  -- follows, we backtrack so the closing-paren-on-fresh-line path
  -- below picks up the same newline.
  ascription <- P.optional $ P.try $ do
    _ <- P.optional $ try $ do
      void C.eol
      skipBlankLinesNoComments
      hspaceNoComments
    _ <- symNoLine ":"
    pTypeNoLineComments
  -- Allow optional newline + indent before ')' so a multi-line block
  -- form inside parens can close on a fresh line. The renderer needs
  -- this whenever wrapping ECase / EDo, because a trailing '--' on
  -- the last arm of a nested case would otherwise eat the ')' (line
  -- comments extend to end-of-line).
  _ <- P.optional $ try $ do
    void C.eol
    skipBlankLinesNoComments
    hspaceNoComments
  _ <- symNoLine ")"
  end <- P.getSourcePos
  let sp = toSrcSpan start end
  pure $ case ascription of
    Just ty -> EAscribe sp e ty
    Nothing -> EParens sp e

pLitNoLineComments :: Parser Expr
pLitNoLineComments =
  pStringLit <|> pIntLit
  where
    pStringLit = do
      (sp, s) <- withSpan pStringLitNoLineComments
      pure (ELit sp (LString s))
    pIntLit = do
      (sp, n) <- withSpan pIntLitNoLineComments
      pure (ELit sp (LInt n))

-- Literals ──────────────────────────────────────────────────────────────────

-- | Double-quoted string literal with standard escapes.
--   Supported escapes: \n \t \r \" \\ \0
pStringLitNoLineComments :: Parser Text
pStringLitNoLineComments = lexemeNoLine $ do
  _ <- C.char '"'
  chars <- P.manyTill stringChar (C.char '"')
  pure (toText chars)

-- | Integer literal: optional '-' followed by one or more decimal digits,
--   with optional '_' separators *between* digits (a readability affordance —
--   '1_000_000' parses to the same Integer as '1000000', '10_00', or '1_0_0_0').
--
--   Forbidden positions for '_':
--     • leading: '_1' is rejected (would clash with underscore-prefixed names)
--     • trailing: '1_' is rejected
--     • adjacent to another '_': '1__2' is rejected
--     • immediately after the sign: '-_1' is rejected
--
--   The '-' must be adjacent to the first digit (no whitespace), so future
--   binary operators will not collide with negative literals. Range validation
--   happens in the typechecker against the declared type.
pIntLitNoLineComments :: Parser Integer
pIntLitNoLineComments = lexemeNoLine $ do
  -- 'try' is restricted to the [-]?digit prefix so that backtracking
  -- happens only when this isn't a literal at all (e.g. a bare '-' in a
  -- different position). Once the first digit is committed, malformed
  -- '_' placement produces a real parse error rather than rolling back.
  (sign, firstDigit) <- try $ do
    s <- P.option 1 (C.char '-' $> (-1))
    d <- P.satisfy Char.isDigit
    pure (s, d)
  rest <- P.many digitOrSepDigit
  pure (sign * readDecimal (toText (firstDigit : rest)))
  where
    -- A digit, or '_' immediately followed by a digit. '_' alone is not
    -- a valid continuation: if '_' matches but the next char isn't a
    -- digit, we fail with "expected digit" — that's how trailing and
    -- doubled '_' get rejected.
    digitOrSepDigit :: Parser Char
    digitOrSepDigit =
      P.satisfy Char.isDigit
        <|> (C.char '_' *> P.satisfy Char.isDigit)
    readDecimal :: Text -> Integer
    readDecimal = T.foldl' (\acc c -> acc * 10 + toInteger (Char.digitToInt c)) 0

-- Shared helpers for string literal parsing
stringChar :: Parser Char
stringChar =
  (C.char '\\' *> escape)
    <|> P.satisfy (\c -> c /= '"' && c /= '\\')

escape :: Parser Char
escape =
  P.choice
    [ '\n' <$ C.char 'n',
      '\t' <$ C.char 't',
      '\r' <$ C.char 'r',
      '\"' <$ C.char '"',
      '\\' <$ C.char '\\',
      '\NUL' <$ C.char '0'
    ]

-- Qualified / unqualified names ─────────────────────────────────────────────

-- | Parse a qualified name expression:
--     IO.Stdout.print  →  QName ["IO","Stdout"] "print"
--     input           →  QName [] "input"
--     BuiltIn.foo     →  EBuiltIn _ "foo"  (reserved compiler namespace;
--                         not a regular module — see 'Awsum.Syntax.EBuiltIn').
pQualifiedNameExprNoLineComments :: Parser Expr
pQualifiedNameExprNoLineComments = do
  (sp, (mods, name)) <- withSpan $ do
    let qualified = do
          ms <- P.some (try (uidentNoLine <* symNoLine ".")) -- IO.
          (ms,) <$> lidentNoLine -- print
        unqual = ([],) <$> lidentNoLine
    try qualified <|> unqual
  case mods of
    ["BuiltIn"] -> pure (EBuiltIn sp name)
    _ -> pure (EVar sp (QName mods name))

-- Do-notation ──────────────────────────────────────────────────────────────

-- | Parse a single 'do'-block statement.
--
--   * @x <- expr@ binds a value and feeds the continuation
--     ('DoBind').
--   * @let n = expr@ introduces a non-monadic binding ('DoLet').
--   * Bare @expr@ is the block's result when last, or a side-effect-
--     only step otherwise ('DoExpr'); the typechecker rejects
--     non-final 'DoExpr' in a hardcoded-Either world.
pDoStmtNoLineComments :: Parser DoStmt
pDoStmtNoLineComments =
  P.choice
    [ try pDoBind,
      try pDoLet,
      pDoExpr
    ]
  where
    pDoBind = do
      start <- P.getSourcePos
      pat <- pPatternNoLineComments
      _ <- symNoLine "<-"
      e <- pExprNoLineComments
      end <- P.getSourcePos
      pure (DoBind (toSrcSpan start end) pat e)
    pDoLet = do
      start <- P.getSourcePos
      rwordNoLine "let"
      pat <- pPatternNoLineComments
      mAnnot <- P.optional $ try $ do
        _ <- symNoLine ":"
        pTypeNoLineComments
      _ <- symNoLine "="
      e <- pExprNoLineComments
      end <- P.getSourcePos
      pure (DoLet (toSrcSpan start end) pat mAnnot e)
    pDoExpr = do
      start <- P.getSourcePos
      e <- pExprNoLineComments
      end <- P.getSourcePos
      pure (DoExpr (toSrcSpan start end) e)

-- | @do@ followed by indentation-aligned statements.
--   The first statement establishes the reference indentation; later
--   statements must align at the same column. Comments inside the
--   block are not parsed in this iteration — keep the block tight.
--
--   A trailing line comment on the @do@ line itself (@f = do -- note@)
--   is swallowed before the newline so it doesn't break the parse;
--   the comment text is currently discarded (re-attaching it to the
--   AST is left for a future iteration that also handles inline
--   comments between statements).
pDoNoLineComments :: Parser Expr
pDoNoLineComments = do
  start <- P.getSourcePos
  rwordNoLine "do"
  void pTrailingLineCommentMaybe
  void C.eol
  skipBlankLinesNoComments
  hspaceNoComments
  ref <- L.indentLevel
  firstStmt <- pDoStmtNoLineComments
  restStmts <-
    P.many
      ( try $ do
          void C.eol
          hspaceNoComments
          lvl <- L.indentLevel
          guard (lvl == ref)
          pDoStmtNoLineComments
      )
  end <- P.getSourcePos
  pure (EDo (toSrcSpan start end) (firstStmt : restStmts))

-- Case expressions ─────────────────────────────────────────────────────────

-- | Flat item inside a @case … of@ block: either a comment or an arm.
data CaseItem
  = CaseItemComment Comment
  | CaseItemArm Pattern Expr (Maybe Text)

-- | Parse a line or block comment (without consuming the trailing newline).
pCaseComment :: Parser Comment
pCaseComment =
  (LineComment <$> pLineCommentText)
    <|> (BlockComment <$> pBlockCommentText)

-- | Parse a case arm: @Pattern -> Expr [-- trailing]@.
pCaseArmItem :: Parser CaseItem
pCaseArmItem = do
  pat <- pPatternNoLineComments
  _ <- symNoLine "->"
  body <- pExprNoLineComments
  CaseItemArm pat body <$> pTrailingLineCommentMaybe

-- | @case expr of@ followed by indentation-aligned alternatives (and comments).
--
--   Comment indentation is lenient: any indented comment (column > 1) between
--   @of@ and the next top-level item is accepted regardless of its exact column.
--   Misaligned comments do not break compilation; the formatter normalizes them
--   to match the arm indentation.  This is intentional: users can freely
--   comment-out / uncomment individual case arms while editing.
--
--   The reference indentation is established by the /first arm/, not the first
--   comment (a leading comment at a weird column must not shift the reference).
pCaseNoLineComments :: Parser Expr
pCaseNoLineComments = do
  start <- P.getSourcePos
  rwordNoLine "case"
  scrut <- pConcatNoLineComments
  rwordNoLine "of"
  void C.eol -- newline after "of"
  -- Leading comments before the first arm (any column > 1).
  leadComments <- P.many $ try $ do
    skipBlankLinesNoComments
    hspaceNoComments
    lvl <- L.indentLevel
    guard (lvl > P.pos1) -- must be indented (not a top-level comment)
    c <- pCaseComment
    hspaceNoComments
    void C.eol
    pure (CaseItemComment c)
  -- First arm establishes the reference indentation.
  skipBlankLinesNoComments
  hspaceNoComments
  ref <- L.indentLevel
  firstArm <- pCaseArmItem
  -- Remaining items: comments at any column > 1, arms at exactly ref.
  -- A blank line terminates the case block (no skipBlankLinesNoComments here).
  restItems <-
    P.many
      ( try $ do
          void C.eol
          hspaceNoComments
          lvl <- L.indentLevel
          (guard (lvl > P.pos1) *> (CaseItemComment <$> pCaseComment <* hspaceNoComments))
            <|> (guard (lvl == ref) *> pCaseArmItem)
      )
  end <- P.getSourcePos
  let (alts, trailingComments) = groupCaseItems (leadComments ++ [firstArm] ++ restItems)
  case alts of
    a : rest -> pure (ECase (toSrcSpan start end) scrut (a :| rest) trailingComments)
    [] -> fail "case expression must have at least one alternative"

-- | Group flat case items into structured alternatives.
--   Comments before an arm become its leading @[Comment]@;
--   comments after the last arm become the trailing @[Comment]@ on 'ECase'.
--
--   Constructor choice mirrors the parser-level invariant captured in
--   'CaseAlt' / 'isBlockBody': a block-form body that ends inside its
--   own last arm/stmt cannot have outer-arm trailing because the inner
--   trailing-slot eats it. When the parser observed a trailing comment
--   ('Just _'), the body must be leaf-form (the parser couldn't have
--   reached 'pTrailingLineCommentMaybe' otherwise) — emit 'CaseAltLeaf'.
--   With no trailing, we still emit 'CaseAltLeaf' for leaf-form bodies
--   (so a future trailing can be added without changing the
--   constructor) and 'CaseAltBlock' for block-form ones.
groupCaseItems :: [CaseItem] -> ([CaseAlt], [Comment])
groupCaseItems = go []
  where
    go pendingComments [] = ([], pendingComments)
    go pendingComments (CaseItemComment c : rest) = go (pendingComments <> [c]) rest
    go pendingComments (CaseItemArm pat body mc : rest) =
      let alt = case mc of
            Just _ -> CaseAltLeaf pendingComments pat body mc
            Nothing
              | isBlockBody body -> CaseAltBlock pendingComments pat body
              | otherwise -> CaseAltLeaf pendingComments pat body Nothing
          (alts, trailing) = go [] rest
       in (alt : alts, trailing)

-- | Pattern: constructor with optional sub-patterns, or variable binding.
--   @Found value@ parses as @PCon span "Found" [PVar "value"]@.
--   The constructor name's span is captured before trailing whitespace
--   so quick-fixes (rename '_C' to 'C') target only the identifier.
pPatternNoLineComments :: Parser Pattern
pPatternNoLineComments =
  pConPattern
    <|> pPVar
    <|> pParenOrAscribePattern

-- | Constructor pattern with possible sub-patterns.
pConPattern :: Parser Pattern
pConPattern = do
  (sp, name) <- pConHead
  pats <- P.many pPatternAtomNoLineComments
  pure (PCon sp name pats)

-- | Atomic pattern: a variable, a nullary constructor, or a parenthesized
--   pattern (optionally with a trailing @':' type@ ascription —
--   @(x : Int32)@). Parens are part of the ascription syntax: without
--   them the @':'@ would collide with the case-arrow @'->'@.
pPatternAtomNoLineComments :: Parser Pattern
pPatternAtomNoLineComments =
  pPVar
    <|> ((\(sp, n) -> PCon sp n []) <$> pConHead)
    <|> pParenOrAscribePattern

-- | Parenthesised pattern with an optional type ascription.
--   @(p)@      → @p@ as-is (no AST change beyond span).
--   @(p : T)@  → @PAscribe sp p T@ where @sp@ covers the whole @(...)@.
pParenOrAscribePattern :: Parser Pattern
pParenOrAscribePattern = do
  start <- P.getSourcePos
  _ <- symNoLine "("
  inner <- pPatternNoLineComments
  ascription <- P.optional $ do
    _ <- symNoLine ":"
    pTypeNoLineComments
  _ <- symNoLine ")"
  end <- P.getSourcePos
  pure $ case ascription of
    Just ty -> PAscribe (toSrcSpan start end) inner ty
    Nothing -> inner

-- | Parse a constructor name and its source span (covers only the name,
--   not trailing whitespace). 'uidentBody' also accepts a bare @_@ (for
--   error reporting on @type _ = …@ etc.); in pattern position the bare
--   underscore is the wildcard, so we explicitly reject it here so the
--   alternative 'pPVar' branch picks it up as 'PWild'.
pConHead :: Parser (SrcSpan, Name)
pConHead = do
  start <- P.getSourcePos
  name <- try $ do
    n <- uidentBody
    guard (n /= "_")
    pure n
  end <- P.getSourcePos
  scNoLineComments
  pure (toSrcSpan start end, name)

-- | Parse a variable-binding pattern, capturing the span of the identifier
--   /before/ trailing whitespace is consumed, so the span covers only the
--   ident itself (no trailing space) — gives tight caret placement in errors.
--   The bare underscore @_@ is desugared to 'PWild' (no binding).
pPVar :: Parser Pattern
pPVar = do
  start <- P.getSourcePos
  name <- binderName
  end <- P.getSourcePos
  scNoLineComments
  let sp = toSrcSpan start end
  pure $ if name == "_" then PWild sp else PVar sp name

-- ────────────────────────────────────────────────────────────────────────────
-- Post-parse: attach adjacent leading comments to the following declaration
-- ────────────────────────────────────────────────────────────────────────────

-- | Lift 'CommentDecl's that are textually adjacent (no blank line) to the
--   next declaration into that declaration's 'docComment' field. Comments
--   separated from the next decl by a blank line, or trailing the file with
--   no following decl, remain as standalone 'CommentDecl's.
--
--   Mixed forms stack arbitrarily — a chain of @--@ lines, a chain of
--   @{- … -}@ blocks, or any mix, all attach as one doc as long as no blank
--   line breaks the chain. Inside a chain the texts are joined by a single
--   newline.
--
--   Per-form normalisation before joining:
--
--     * one leading space stripped from each @--@ line (so the typical
--       @-- prose@ habit produces clean markdown, not @ prose@);
--
--     * @T.strip@ on each @{- … -}@ block (drops the conventional
--       @\' content \'@ padding without disturbing internal indent — markdown
--       code blocks survive).
--
--   The final joined string is also @T.strip@-ed (in case the chain starts
--   or ends with whitespace-only lines).
attachDocs :: NonEmpty Decl -> NonEmpty Decl
attachDocs declsNE = case go [] (toList declsNE) of
  [] -> declsNE -- defensive; the algorithm preserves input length
  x : xs -> x :| xs
  where
    go :: [Decl] -> [Decl] -> [Decl]
    go pending [] = reverse pending
    go pending (d : rest) = case d of
      CommentDecl {} -> go (d : pending) rest
      _ ->
        let (detached, attached) = splitAdjacent (declSpan d) (reverse pending)
            doc = case attached of
              [] -> Nothing
              cs -> Just (joinedDocText cs)
            d' = setDeclDocComment doc d
         in detached ++ [d'] ++ go [] rest

    -- 'comments' is in source order (oldest first, closest-to-decl last).
    -- Walk back from the decl: the longest suffix where each comment is
    -- adjacent to the next (or to the decl at the tail) becomes the doc.
    splitAdjacent :: SrcSpan -> [Decl] -> ([Decl], [Decl])
    splitAdjacent declSp comments = walkBack declSp [] (reverse comments)
      where
        walkBack _ attached [] = ([], attached)
        walkBack anchor attached (c : older) =
          if isAdjacent (declSpan c) anchor
            then walkBack (declSpan c) (c : attached) older
            else (reverse (c : older), attached)

    -- Comment ends on line L; next thing starts on line M.
    -- Adjacent iff M - L <= 1 (same line, or next line — at most one EOL
    -- between them, i.e. no blank line).
    isAdjacent :: SrcSpan -> SrcSpan -> Bool
    isAdjacent before after = spanStartLine after - spanEndLine before <= 1

    joinedDocText :: [Decl] -> Text
    joinedDocText cs = T.strip (T.intercalate "\n" (map oneDocText cs))

    oneDocText :: Decl -> Text
    oneDocText (CommentDecl _ (LineComment t)) =
      -- '-- foo' captures ' foo'; '--foo' captures 'foo'. Drop one
      -- leading space so the canonical '-- prose' style becomes 'prose'.
      case T.uncons t of
        Just (' ', rest) -> rest
        _ -> t
    oneDocText (CommentDecl _ (BlockComment t)) = T.strip t
    oneDocText _ = "" -- unreachable: 'pending' only collects CommentDecls
