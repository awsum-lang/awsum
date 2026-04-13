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
module Awsum.Parser (parseProgram) where

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
skipBlankLinesNoComments = void $ P.many (hspaceNoComments *> C.eol)

-- ────────────────────────────────────────────────────────────────────────────
-- Identifiers & reserved words
-- ────────────────────────────────────────────────────────────────────────────

-- | Tail characters allowed in identifiers.
identChar :: Parser Char
identChar = C.alphaNumChar <|> C.char '_' <|> C.char '\''

-- | Predicate for identifier tails (used by 'takeWhileP').
isIdentTail :: Char -> Bool
isIdentTail c = Char.isAlphaNum c || c == '_' || c == '\''

-- | Recognize a reserved word /without/ swallowing identifier tails.
--   e.g. parsing \"import\" will fail on \"importX\".
rword :: Text -> Parser ()
rword w = (lexeme . try) (P.chunk w *> P.notFollowedBy identChar)

rwordS :: String -> Parser ()
rwordS = rword . toText

-- | Lower-case identifier (value/function name).
lident :: Parser Name
lident = (lexeme . try) $ do
  x <- C.lowerChar
  xs <- P.takeWhileP (Just "ident tail") isIdentTail
  pure (T.cons x xs)

-- | Upper-case identifier (module/type constructor name).
uident :: Parser Name
uident = (lexeme . try) $ do
  x <- C.upperChar
  xs <- P.takeWhileP (Just "ident tail") isIdentTail
  pure (T.cons x xs)

-- No-line-comment variants (used where we must not eat '--').
lidentNoLine :: Parser Name
lidentNoLine = (lexemeNoLine . try) $ do
  x <- C.lowerChar
  xs <- P.takeWhileP (Just "ident tail") isIdentTail
  pure (T.cons x xs)

uidentNoLine :: Parser Name
uidentNoLine = (lexemeNoLine . try) $ do
  x <- C.upperChar
  xs <- P.takeWhileP (Just "ident tail") isIdentTail
  pure (T.cons x xs)

-- ────────────────────────────────────────────────────────────────────────────
-- Entry point
-- ────────────────────────────────────────────────────────────────────────────

-- | Parse a full program from 'Text'.
parseProgram :: Text -> Either Text Program
parseProgram src =
  case P.parse (pProgram <* eof) "<stdin>" src of
    Left e -> Left (toText (P.errorBundlePretty e))
    Right p -> Right p

-- Program ────────────────────────────────────────────────────────────────────

pProgram :: Parser Program
pProgram = do
  imps <- P.many pImport
  skipBlankLinesNoComments
  ds <- P.some (pTopDeclOrComment <* skipBlankLinesNoComments)
  let declsNE = case ds of
        d : rest -> d :| rest
        [] -> error "impossible: P.some returned []"
  pure Program {imports = imps, decls = declsNE}

pImport :: Parser ImportDecl
pImport = do
  rwordS "import"
  imp <- ImportDecl <$> pModPath
  -- We don't preserve trailing comments on imports (by design).
  _ <- lexeme (void C.eol) <|> P.eof
  pure imp

pModPath :: Parser (NonEmpty Name)
pModPath = do
  h <- uident
  ts <- P.many (sym "." *> uident)
  pure (h :| ts)

-- Top-level items ────────────────────────────────────────────────────────────

-- | Top-level item: either a top-level comment or a declaration.
pTopDeclOrComment :: Parser Decl
pTopDeclOrComment =
  pTopComment
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
  name <- lident
  _ <- sym ":"
  ty <- pTypeNoLineComments
  tcom <- pTrailingLineCommentMaybe
  endLineOrEOF
  pure (Sig name ty tcom)

-- | Definition line: keep inline trailing '-- …' if present.
pFunDefWithEnd :: Parser Decl
pFunDefWithEnd = do
  name <- lident
  args <- P.many lident
  _ <- sym "="
  e <- pExprNoLineComments
  tcom <- pTrailingLineCommentMaybe
  endLineOrEOF
  pure (FunDef name args e tcom)

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
pTypeNoLineComments :: Parser Type'
pTypeNoLineComments = do
  t1 <- pTypeAtomNoLineComments
  (TyArrow t1 <$> (symNoLine "->" *> pTypeNoLineComments)) <|> pure t1
  where
    pTypeAtomNoLineComments =
      (TyCon <$> uidentNoLine)
        <|> (TyVar <$> lidentNoLine)
        <|> P.between (symNoLine "(") (symNoLine ")") pTypeNoLineComments

-- Expressions ───────────────────────────────────────────────────────────────

-- | Lowest precedence layer (currently only @++@) under no-line-comments space.
pExprNoLineComments :: Parser Expr
pExprNoLineComments = pConcatNoLineComments
  where
    -- Left-associative chain of @App@ separated by @++@.
    pConcatNoLineComments = do
      x <- pAppNoLineComments
      let rest acc =
            ( do
                _ <- symNoLine "++"
                y <- pAppNoLineComments
                rest (EInfix OpConcat acc y)
            )
              <|> pure acc
      rest x
    -- Left-associative application (one or more atoms).
    pAppNoLineComments = do
      t0 <- pAtomNoLineComments
      ts <- P.many pAtomNoLineComments
      pure (foldl' EApp t0 ts)
    -- Atomic expression: qualified/unqualified name, parenthesized expr, or string literal.
    pAtomNoLineComments =
      pQualifiedNameExprNoLineComments
        <|> (EParens <$> P.between (symNoLine "(") (symNoLine ")") pExprNoLineComments)
        <|> (ELit . LString <$> pStringLitNoLineComments)

-- Literals ──────────────────────────────────────────────────────────────────

-- | Double-quoted string literal with standard escapes.
--   Supported escapes: \n \t \r \" \\ \0
pStringLitNoLineComments :: Parser Text
pStringLitNoLineComments = lexemeNoLine $ do
  _ <- C.char '"'
  chars <- P.manyTill stringChar (C.char '"')
  pure (toText chars)

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
  let qualified = do
        mods <- P.some (try (uidentNoLine <* symNoLine ".")) -- IO.
        QName mods <$> lidentNoLine -- print
      unqual = QName [] <$> lidentNoLine
  EVar <$> (try qualified <|> unqual)
