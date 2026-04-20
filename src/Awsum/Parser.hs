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
--   Expr    ::= Concat
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
--   1) "++"   (left-assoc)
--   2) application (left-assoc)
--   3) atoms
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
reserved = ["import", "type", "case", "of"]

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

-- | Upper-case identifier (module/type constructor name).
--   Accepts:
--     • @Foo@ — the normal shape;
--     • @_Foo@ — explicitly marked as intentionally unused;
--     • @_@ — bare underscore, parsed so the typechecker can reject it
--       with a friendlier message than Megaparsec's default.
--   Does NOT accept @_foo@ (underscore + lowercase): that's a value-style
--   name and would be ambiguous as a type/constructor.
uident :: Parser Name
uident = (lexeme . try) uidentBody

-- | Inner shape of 'uident', without the lexeme/whitespace handling.
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
paramBinder = do
  start <- P.getSourcePos
  name <- binderName
  end <- P.getSourcePos
  sc
  pure (Param (toSrcSpan start end) name)

-- | Variant of 'paramBinder' for contexts (type declarations) that must
--   not swallow trailing @--@ line comments.
paramBinderNoLine :: Parser Param
paramBinderNoLine = do
  start <- P.getSourcePos
  name <- binderName
  end <- P.getSourcePos
  scNoLineComments
  pure (Param (toSrcSpan start end) name)

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
  imps <- P.many (try pImport)
  skipBlankLinesNoComments
  ds <- P.some (pTopDeclOrComment <* skipBlankLinesNoComments)
  let declsNE = case ds of
        d : rest -> d :| rest
        [] -> error "impossible: P.some returned []"
  pure Program {imports = imps, decls = declsNE}

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

-- | Top-level comments (non-nested capture for '{- -}', nesting still works in
--   the skipper; line comments capture until end-of-line).
pTopComment :: Parser Decl
pTopComment = do
  hspaceNoComments
  CommentDecl
    <$> ( (LineComment <$> pLineCommentText <* P.optional C.eol)
            <|> (BlockComment <$> pBlockCommentText)
        )

pLineCommentText :: Parser Text
pLineCommentText = do
  _ <- P.chunk "--"
  P.takeWhileP (Just "not newline") (/= '\n')

pBlockCommentText :: Parser Text
pBlockCommentText = do
  _ <- P.chunk "{-"
  txt <- P.manyTill P.anySingle (P.chunk "-}")
  pure (toText txt)

-- Declarations ───────────────────────────────────────────────────────────────

-- | Signature line: keep inline trailing '-- …' if present.
pSigWithEnd :: Parser Decl
pSigWithEnd = do
  start <- P.getSourcePos
  name <- lident
  _ <- sym ":"
  ty <- pTypeNoLineComments
  tcom <- pTrailingLineCommentMaybe
  end <- P.getSourcePos
  endLineOrEOF
  pure (Sig (toSrcSpan start end) name ty tcom)

-- | Sum type declaration: @type Lookup a = Found a | NotFound@.
--   Empty constructor list (no @=@) declares an uninhabited type: @type Never@.
pTypeDeclWithEnd :: Parser Decl
pTypeDeclWithEnd = do
  start <- P.getSourcePos
  rwordS "type"
  name <- uident
  tvars <- P.many paramBinderNoLine
  cons <- P.option [] $ do
    _ <- sym "="
    firstCon <- pConDefNoLine
    restCons <- P.many (symNoLine "|" *> pConDefNoLine)
    pure (firstCon : restCons)
  tcom <- pTrailingLineCommentMaybe
  end <- P.getSourcePos
  endLineOrEOF
  pure (TypeDecl (toSrcSpan start end) name tvars cons tcom)

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
  name <- lident
  args <- P.many paramBinder
  _ <- sym "="
  e <- pExprNoLineComments
  case e of
    ECase {} -> do
      end <- P.getSourcePos
      -- Multi-line case expression already consumed trailing newlines.
      -- We may be at the start of the next content line or EOF.
      pure (FunDef (toSrcSpan start end) name args e Nothing)
    _ -> do
      tcom <- pTrailingLineCommentMaybe
      end <- P.getSourcePos
      endLineOrEOF
      pure (FunDef (toSrcSpan start end) name args e tcom)

-- | Consume spaces (not comments), then an optional trailing line comment.
pTrailingLineCommentMaybe :: Parser (Maybe Text)
pTrailingLineCommentMaybe = do
  hspaceNoComments
  P.optional pLineCommentText

-- | End of declaration: newline or EOF.
endLineOrEOF :: Parser ()
endLineOrEOF = void C.eol <|> P.eof

-- Types (right-assoc arrows) ────────────────────────────────────────────────

-- | Types with a space consumer that does not skip line comments.
--   Grammar: Type = TypeApp , { "->" , Type } ;
pTypeNoLineComments :: Parser Type'
pTypeNoLineComments = do
  t1 <- pTypeAppNoLineComments
  P.option
    t1
    ( do
        _ <- symNoLine "->"
        t2 <- pTypeNoLineComments
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
      TyApp _ f x -> TyApp sp f x
      TyArrow _ a b -> TyArrow sp a b

-- Expressions ───────────────────────────────────────────────────────────────

-- | Lowest precedence layer: @case@ (multi-line) or @++@ chain.
pExprNoLineComments :: Parser Expr
pExprNoLineComments = pCaseNoLineComments <|> pConcatNoLineComments

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
  _ <- symNoLine ")"
  end <- P.getSourcePos
  pure (EParens (toSrcSpan start end) e)

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

-- | Integer literal: optional '-' followed by one or more decimal digits.
--   The '-' must be adjacent to the digits (no whitespace), so future binary
--   operators will not collide with negative literals.
--   Range validation happens at the type-check stage against the declared type.
pIntLitNoLineComments :: Parser Integer
pIntLitNoLineComments = lexemeNoLine $ try $ do
  sign <- P.option 1 (C.char '-' $> (-1))
  digits <- P.takeWhile1P (Just "digit") Char.isDigit
  pure (sign * readDecimal digits)
  where
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
pQualifiedNameExprNoLineComments :: Parser Expr
pQualifiedNameExprNoLineComments = do
  (sp, q) <- withSpan $ do
    let qualified = do
          mods <- P.some (try (uidentNoLine <* symNoLine ".")) -- IO.
          QName mods <$> lidentNoLine -- print
        unqual = QName [] <$> lidentNoLine
    try qualified <|> unqual
  pure (EVar sp q)

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
groupCaseItems :: [CaseItem] -> ([CaseAlt], [Comment])
groupCaseItems = go []
  where
    go pendingComments [] = ([], pendingComments)
    go pendingComments (CaseItemComment c : rest) = go (pendingComments <> [c]) rest
    go pendingComments (CaseItemArm pat body mc : rest) =
      let alt = CaseAlt pendingComments pat body mc
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

-- | Constructor pattern with possible sub-patterns.
pConPattern :: Parser Pattern
pConPattern = do
  (sp, name) <- pConHead
  pats <- P.many pPatternAtomNoLineComments
  pure (PCon sp name pats)

-- | Atomic pattern: a variable, a nullary constructor, or a parenthesized pattern.
pPatternAtomNoLineComments :: Parser Pattern
pPatternAtomNoLineComments =
  pPVar
    <|> ((\(sp, n) -> PCon sp n []) <$> pConHead)
    <|> P.between (symNoLine "(") (symNoLine ")") pPatternNoLineComments

-- | Parse a constructor name and its source span (covers only the name,
--   not trailing whitespace).
pConHead :: Parser (SrcSpan, Name)
pConHead = do
  start <- P.getSourcePos
  name <- try uidentBody
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
  pure $ if name == "_" then PWild else PVar (toSrcSpan start end) name
