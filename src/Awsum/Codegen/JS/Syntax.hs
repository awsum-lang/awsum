-- | JavaScript surface AST + pretty-printer for 'Awsum.Codegen.JS'.
--
-- The JS backend builds a value of this AST from Core and renders it to
-- text here — mirroring how the byte backends build a spec ('JvmModule' /
-- 'WasmFunc') and project it. JS has a single projection (text consumed by
-- Node), so there is one renderer; layout is handled by @prettyprinter@
-- rather than hand-rolled string concatenation.
--
-- Identifiers are stored already-mangled: name mangling is a Core→JS
-- concern owned by the builder, not the renderer. Parenthesisation is
-- precedence-driven ('prec' \/ 'binPrec'): a child is wrapped only when its
-- operator binds looser than its context, so the output carries no
-- redundant parens.
module Awsum.Codegen.JS.Syntax
  ( JsStmt (..),
    JsExpr (..),
    UnOp (..),
    BinOp (..),
    UpOp (..),
    renderProgram,
  )
where

import Data.Text qualified as T
import Numeric (showHex)
import Prettyprinter
  ( Doc,
    brackets,
    colon,
    concatWith,
    defaultLayoutOptions,
    dquotes,
    group,
    hardline,
    layoutPretty,
    lbrace,
    lbracket,
    line,
    line',
    lparen,
    nest,
    parens,
    pretty,
    rbrace,
    rbracket,
    rparen,
    semi,
    (<+>),
  )
import Prettyprinter.Render.Text (renderStrict)
import Relude hiding (group)

-- ════════════════════════════════════════════════════════════════════════════
-- AST
-- ════════════════════════════════════════════════════════════════════════════

-- | A JavaScript statement. The subset is exactly what the JS backend
--   emits — generated declarations, the runtime helpers, and the CLI
--   wrapper — no more.
data JsStmt
  = -- | @const n = e;@
    SConst Text JsExpr
  | -- | @let n = e;@ or @let n;@ (uninitialised)
    SLet Text (Maybe JsExpr)
  | -- | expression statement @e;@ (calls, postfix @++@, assignments, the IIFE)
    SExpr JsExpr
  | -- | @return e;@
    SReturn JsExpr
  | -- | @if (c) {…} else {…}@; an empty else list renders without @else@
    SIf JsExpr [JsStmt] [JsStmt]
  | -- | @for (let n = e1; e2; e3) {…}@
    SFor Text JsExpr JsExpr JsExpr [JsStmt]
  | -- | @while (true) {…}@ (the loop body of a TCO'd function)
    SWhileTrue [JsStmt]
  | -- | @switch (e) { case N: {…} … }@; arms are exhaustive (no @default@,
    --   no fallthrough — every arm ends in @return@\/@continue@)
    SSwitch JsExpr [(Integer, [JsStmt])]
  | -- | @continue;@
    SContinue
  | -- | a bare block @{ … }@
    SBlock [JsStmt]
  | -- | @try {…} catch (n) {…}@
    STry [JsStmt] Text [JsStmt]
  | -- | a blank line — a layout directive, not a JS statement. The builder
    --   interleaves these between top-level declarations for legibility; it
    --   renders to nothing, so the line breaks the surrounding 'vsepHard'
    --   already inserts leave one empty line.
    SBlank
  deriving stock (Show)

-- | A JavaScript expression.
data JsExpr
  = EVar Text
  | -- | decimal integer literal (negative renders with a leading @-@)
    ENum Integer
  | -- | hexadecimal integer literal @0x…@ (bit masks, surrogate bounds)
    EHex Integer
  | -- | BigInt literal @…n@
    EBigInt Integer
  | EStr Text
  | -- | regex literal @\/src\/@ (no flags)
    ERegex Text
  | EBool Bool
  | ENull
  | EArray [JsExpr]
  | -- | object literal; keys are bare identifiers
    EObject [(Text, JsExpr)]
  | -- | @e.field@
    EMember JsExpr Text
  | -- | @e[i]@
    EIndex JsExpr JsExpr
  | -- | @f(args)@
    ECall JsExpr [JsExpr]
  | -- | @new C(args)@
    ENew JsExpr [JsExpr]
  | -- | @(params) => { body }@ (always block-bodied)
    EArrow [Text] [JsStmt]
  | -- | @lhs = rhs@ (an expression: also the elements of a 'ESeq' cell-reuse)
    EAssign JsExpr JsExpr
  | EUnary UnOp JsExpr
  | EBin BinOp JsExpr JsExpr
  | -- | postfix @e++@ \/ @e--@
    EUpdate UpOp JsExpr
  | -- | @c ? t : f@
    ECond JsExpr JsExpr JsExpr
  | -- | comma\/sequence expression @(a, b, c)@ (in-place cell reuse)
    ESeq [JsExpr]
  deriving stock (Show)

data UnOp = UNot | UNeg | UTypeof
  deriving stock (Show)

data UpOp = UInc | UDec
  deriving stock (Show)

data BinOp
  = BAdd
  | BSub
  | BMul
  | BEq
  | BNeq
  | BLt
  | BGt
  | BLe
  | BGe
  | BBitAnd
  | BBitOr
  | BUShr
  | BAnd
  | BOr
  deriving stock (Show)

-- ════════════════════════════════════════════════════════════════════════════
-- Public API
-- ════════════════════════════════════════════════════════════════════════════

-- | Render a module (its top-level statements) to text, with a trailing
--   newline for friendlier CLI output. Trailing whitespace is stripped per
--   line so 'SBlank' lines (and any indent a blank line would otherwise
--   inherit from 'nest') come out genuinely empty.
renderProgram :: [JsStmt] -> Text
renderProgram ss =
  unlines (map T.stripEnd (lines (renderStrict (layoutPretty defaultLayoutOptions doc))))
  where
    doc :: Doc ()
    doc = vsepHard (map stmt ss) <> hardline

-- ════════════════════════════════════════════════════════════════════════════
-- Statements
-- ════════════════════════════════════════════════════════════════════════════

stmt :: JsStmt -> Doc ann
stmt = \case
  SConst n e -> "const" <+> pretty n <+> "=" <+> expr 2 e <> semi
  SLet n Nothing -> "let" <+> pretty n <> semi
  SLet n (Just e) -> "let" <+> pretty n <+> "=" <+> expr 2 e <> semi
  SExpr e -> expr 0 e <> semi
  SReturn e -> "return" <+> expr 2 e <> semi
  SIf c t [] -> "if" <+> parens (expr 0 c) <+> block t
  SIf c t el -> "if" <+> parens (expr 0 c) <+> block t <+> "else" <+> block el
  SFor n e1 e2 e3 body ->
    let forHead =
          "let"
            <+> pretty n
            <+> "="
            <+> expr 2 e1
              <> semi
            <+> expr 0 e2
              <> semi
            <+> expr 0 e3
     in "for" <+> parens forHead <+> block body
  SWhileTrue body -> "while" <+> parens "true" <+> block body
  SSwitch e cs -> "switch" <+> parens (expr 0 e) <+> braceBlock (map switchCase cs)
  SContinue -> "continue" <> semi
  SBlock body -> block body
  STry tb cn cb -> "try" <+> block tb <+> "catch" <+> parens (pretty cn) <+> block cb
  SBlank -> mempty

switchCase :: (Integer, [JsStmt]) -> Doc ann
switchCase (tag, body) = "case" <+> pretty tag <> colon <+> block body

-- | A statement block @{ … }@, always multi-line (one statement per line,
--   indented two spaces). @hardline@ keeps it broken regardless of width.
block :: [JsStmt] -> Doc ann
block ss = braceBlock (map stmt ss)

-- | Wrap already-rendered items in a forced-multi-line brace block.
braceBlock :: [Doc ann] -> Doc ann
braceBlock [] = lbrace <> rbrace
braceBlock ds = lbrace <> nest 2 (hardline <> vsepHard ds) <> hardline <> rbrace

-- ════════════════════════════════════════════════════════════════════════════
-- Expressions
-- ════════════════════════════════════════════════════════════════════════════

-- | Render an expression for a context that tolerates operators down to
--   precedence @ctx@; wrap in parens when the expression binds looser.
expr :: Int -> JsExpr -> Doc ann
expr ctx e = if prec e < ctx then parens (exprBody e) else exprBody e

exprBody :: JsExpr -> Doc ann
exprBody = \case
  EVar t -> pretty t
  ENum n -> pretty n
  EHex n -> hexLit n
  EBigInt n -> pretty n <> "n"
  EStr t -> jsString t
  ERegex t -> "/" <> pretty t <> "/"
  EBool b -> if b then "true" else "false"
  ENull -> "null"
  EArray xs -> commaList lbracket rbracket (map (expr 2) xs)
  EObject kvs -> commaList lbrace rbrace (map kv kvs)
  EMember e f -> expr 18 e <> "." <> pretty f
  EIndex e i -> expr 18 e <> brackets (expr 0 i)
  ECall f xs -> expr 18 f <> argList xs
  ENew f xs -> "new" <+> expr 18 f <> argList xs
  EArrow ps body -> commaList lparen rparen (map pretty ps) <+> "=>" <+> block body
  EAssign l r -> expr 18 l <+> "=" <+> expr 2 r
  EUnary UTypeof e -> "typeof" <+> expr 16 e
  EUnary UNot e -> "!" <> expr 16 e
  EUnary UNeg e -> "-" <> expr 16 e
  EBin op l r -> let p = binPrec op in expr p l <+> binOp op <+> expr (p + 1) r
  EUpdate UInc e -> expr 18 e <> "++"
  EUpdate UDec e -> expr 18 e <> "--"
  ECond c t f -> expr 5 c <+> "?" <+> expr 2 t <+> colon <+> expr 2 f
  ESeq xs -> concatWith (\a b -> a <> "," <+> b) (map (expr 2) xs)
  where
    kv (k, v) = pretty k <> colon <+> expr 2 v

argList :: [JsExpr] -> Doc ann
argList xs = commaList lparen rparen (map (expr 2) xs)

-- ════════════════════════════════════════════════════════════════════════════
-- Precedence
-- ════════════════════════════════════════════════════════════════════════════

-- | Each expression's own precedence (higher binds tighter), used by 'expr'
--   to decide parenthesisation. Mirrors the ECMAScript grammar levels.
prec :: JsExpr -> Int
prec = \case
  EVar _ -> 20
  ENum n -> if n < 0 then 16 else 20 -- a leading '-' behaves like unary minus
  EHex _ -> 20
  EBigInt _ -> 20
  EStr _ -> 20
  ERegex _ -> 20
  EBool _ -> 20
  ENull -> 20
  EArray _ -> 20
  EObject _ -> 20
  EMember {} -> 18
  EIndex {} -> 18
  ECall {} -> 18
  ENew {} -> 18
  EArrow {} -> 2
  EAssign {} -> 2
  EUnary {} -> 16
  EBin op _ _ -> binPrec op
  EUpdate {} -> 17
  ECond {} -> 4
  ESeq _ -> 1

binPrec :: BinOp -> Int
binPrec = \case
  BMul -> 14
  BAdd -> 13
  BSub -> 13
  BUShr -> 12
  BLt -> 11
  BGt -> 11
  BLe -> 11
  BGe -> 11
  BEq -> 10
  BNeq -> 10
  BBitAnd -> 9
  BBitOr -> 7
  BAnd -> 6
  BOr -> 5

binOp :: BinOp -> Doc ann
binOp = \case
  BAdd -> "+"
  BSub -> "-"
  BMul -> "*"
  BEq -> "==="
  BNeq -> "!=="
  BLt -> "<"
  BGt -> ">"
  BLe -> "<="
  BGe -> ">="
  BBitAnd -> "&"
  BBitOr -> "|"
  BUShr -> ">>>"
  BAnd -> "&&"
  BOr -> "||"

-- ════════════════════════════════════════════════════════════════════════════
-- Leaves and lists
-- ════════════════════════════════════════════════════════════════════════════

-- | A comma-separated, delimited list. Inline (@[a, b, c]@) when it fits the
--   page width, otherwise one element per line, indented and trailing-comma
--   free.
commaList :: Doc ann -> Doc ann -> [Doc ann] -> Doc ann
commaList open close [] = open <> close
commaList open close ds =
  group (open <> nest 2 (line' <> commaSep ds) <> line' <> close)
  where
    commaSep :: [Doc ann] -> Doc ann
    commaSep = concatWith (\a b -> a <> "," <> line <> b)

-- | One forced line break between successive items.
vsepHard :: [Doc ann] -> Doc ann
vsepHard = concatWith (\a b -> a <> hardline <> b)

-- | Uppercase hexadecimal literal, e.g. @0xFF@.
hexLit :: Integer -> Doc ann
hexLit n = "0x" <> pretty (T.toUpper (toText (showHex n "")))

-- | A double-quoted JS string literal; the escaped characters mirror the parser's.
jsString :: Text -> Doc ann
jsString t = dquotes (pretty (T.concatMap esc t))
  where
    esc :: Char -> Text
    esc = \case
      '\n' -> "\\n"
      '\t' -> "\\t"
      '\r' -> "\\r"
      '"' -> "\\\""
      '\\' -> "\\\\"
      -- Fixed-length Unicode escape (U+0000), not \0: under "use strict" a \0 immediately
      -- followed by a decimal digit is a legacy octal escape (a SyntaxError).
      -- \u consumes exactly four hex digits, so a following digit stays a separate character.
      '\0' -> "\\u0000"
      c -> one c
