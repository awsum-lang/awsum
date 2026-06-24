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
    renderProgramCompact,
  )
where

import Awsum.Pretty (vsepHard)
import Data.Text qualified as T
import Numeric (showHex)
import Prettyprinter
  ( Doc,
    LayoutOptions (..),
    PageWidth (..),
    SimpleDocStream (..),
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
  | -- | labelled block @l: {…}@ — a 'CJoin': the block holds the join's
    --   inner expression, the join body sits right after it
    SLabeled Text [JsStmt]
  | -- | @break l;@ — a 'CJump': exits the labelled block into the join body
    SBreak Text
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
  | -- | arrow function @params => body@. A single-'SReturn' body renders as an
    --   expression (@x => e@); any other body renders as a block (@x => { … }@).
    --   A lone parameter drops its parens; zero or two-plus take @(…)@.
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
--   newline for friendlier CLI output. 'SBlank' renders to 'mempty', and
--   prettyprinter never emits trailing whitespace — an empty line (including a
--   blank line nested inside the IIFE under 'nest') comes out genuinely empty —
--   so the text needs no post-pass.
renderProgram :: [JsStmt] -> Text
renderProgram ss = renderStrict (layoutPretty defaultLayoutOptions (programDoc ss))

-- | The whole module as one 'Doc' — shared by the pretty and compact
--   renderers so they emit the same tokens, differing only in layout.
programDoc :: [JsStmt] -> Doc ()
programDoc ss = vsepHard (map stmt ss) <> hardline

-- | Render a module to a single line: the same tokens as 'renderProgram',
--   but every layout newline (and its indentation) dropped. This is the
--   artifact @awsum build@ \/ @run@ ship — the runtime never needs it
--   indented, and a right-nested @case@ chain or long nested data literal
--   would otherwise carry O(depth) leading spaces per line (the readable
--   form stays available via @awsum asm -t js@). Laying out at 'Unbounded'
--   width keeps every @group@ flat (so soft breaks collapse to a space or
--   nothing), leaving only the forced 'hardline's between statements; those
--   are dropped here. Safe because every statement is @;@- or @}@-terminated
--   and no @\/\/@ comments are emitted, so removing a newline never fuses two
--   tokens.
renderProgramCompact :: [JsStmt] -> Text
renderProgramCompact ss =
  renderStrict (dropLines (layoutPretty unbounded (programDoc ss)))
  where
    unbounded = defaultLayoutOptions {layoutPageWidth = Unbounded}
    dropLines :: SimpleDocStream ann -> SimpleDocStream ann
    dropLines = \case
      SLine _ rest -> dropLines rest
      SChar c rest -> SChar c (dropLines rest)
      SText l t rest -> SText l t (dropLines rest)
      SAnnPush a rest -> SAnnPush a (dropLines rest)
      SAnnPop rest -> SAnnPop (dropLines rest)
      SEmpty -> SEmpty
      SFail -> SFail

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
  SLabeled l body -> pretty l <> colon <+> block body
  SBreak l -> "break" <+> pretty l <> semi
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
  -- A bare decimal-integer receiver must be parenthesised: @5.toString@ lexes
  -- @5.@ as a number, so the member access is a syntax error. (Hex/BigInt
  -- literals have no decimal point and are safe; negative literals are already
  -- parenthesised by precedence.) The builder never emits this — every integer
  -- literal is wrapped in @| 0@ / @& 0xFF@ / @>>> 0@ — but the renderer owns
  -- correctness for any valid expression, not just the ones in use today.
  EMember (ENum n) f -> parens (pretty n) <> "." <> pretty f
  EMember e f -> expr 18 e <> "." <> pretty f
  EIndex e i -> expr 18 e <> brackets (expr 0 i)
  ECall f xs -> expr 18 f <> argList xs
  ENew f xs -> "new" <+> expr 18 f <> argList xs
  EArrow ps [SReturn e] -> arrowHead ps <+> "=>" <> arrowBody e
  EArrow ps body -> arrowHead ps <+> "=>" <+> block body
  EAssign l r -> expr 18 l <+> "=" <+> expr 2 r
  EUnary UTypeof e -> "typeof" <+> expr 16 e
  EUnary UNot e -> "!" <> expr 16 e
  -- A unary minus whose operand itself renders with a leading @-@ (a nested
  -- negation or a negative literal) would lex as @--@ (prefix decrement), so
  -- the operand is parenthesised: @-(-x)@, not @--x@. The builder only ever
  -- negates a bare variable, so this never fires today — but the renderer
  -- stays correct for any operand.
  EUnary UNeg e
    | minusLed e -> "-" <> parens (exprBody e)
    | otherwise -> "-" <> expr 16 e
  EBin op l r ->
    let p = binPrec op
     in case binAssoc op of
          AssocLeft -> expr p l <+> binOp op <+> expr (p + 1) r
          AssocRight -> expr (p + 1) l <+> binOp op <+> expr p r
  EUpdate UInc e -> expr 18 e <> "++"
  EUpdate UDec e -> expr 18 e <> "--"
  ECond c t f -> expr 5 c <+> "?" <+> expr 2 t <+> colon <+> expr 2 f
  ESeq xs -> concatWith (\a b -> a <> "," <+> b) (map (expr 2) xs)
  where
    kv (k, v) = pretty k <> colon <+> expr 2 v

argList :: [JsExpr] -> Doc ann
argList xs = commaList lparen rparen (map (expr 2) xs)

-- | An arrow's parameter list. A lone parameter needs no parens (params are
--   always plain identifiers, never destructuring, so @x =>@ is always safe);
--   zero or two-plus parameters take @(…)@.
arrowHead :: [Text] -> Doc ann
arrowHead [p] = pretty p
arrowHead ps = commaList lparen rparen (map pretty ps)

-- | A single-return arrow's body as an expression, folded onto the next line
--   (indented) when it doesn't fit beside @=>@, inline when it does. An object
--   literal is parenthesised — a @{@ immediately after @=>@ lexes as a block,
--   not an object. Otherwise the body renders like a @return@ operand
--   (precedence 2): a comma\/sequence expression is wrapped, a conditional or
--   binary is not.
arrowBody :: JsExpr -> Doc ann
arrowBody e = group (nest 2 (line <> body))
  where
    body = case e of
      EObject _ -> parens (exprBody e)
      _ -> expr 2 e

-- | Does this expression render with a leading @-@ — a nested unary minus or a
--   negative numeric literal? Such an operand under a unary minus must be
--   parenthesised so the two @-@ don't lex as a single @--@ token.
minusLed :: JsExpr -> Bool
minusLed = \case
  EUnary UNeg _ -> True
  ENum n -> n < 0
  EHex n -> n < 0
  _ -> False

-- ════════════════════════════════════════════════════════════════════════════
-- Precedence
-- ════════════════════════════════════════════════════════════════════════════

-- | Each expression's own precedence (higher binds tighter), used by 'expr'
--   to decide parenthesisation. Mirrors the ECMAScript grammar levels.
prec :: JsExpr -> Int
prec = \case
  EVar _ -> 20
  ENum n -> if n < 0 then 16 else 20 -- a leading '-' behaves like unary minus
  EHex n -> if n < 0 then 16 else 20 -- negative hex renders with a leading '-'
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

-- | Associativity, consulted by 'EBin' to decide which operand may share the
--   operator's precedence (the other must bind one level tighter). Every
--   current 'BinOp' is left-associative; the explicit, wildcard-free table
--   forces a future right-associative addition (e.g. exponentiation) to state
--   its associativity rather than silently inherit left-assoc parenthesisation.
data Assoc = AssocLeft | AssocRight

binAssoc :: BinOp -> Assoc
binAssoc = \case
  BAdd -> AssocLeft
  BSub -> AssocLeft
  BMul -> AssocLeft
  BEq -> AssocLeft
  BNeq -> AssocLeft
  BLt -> AssocLeft
  BGt -> AssocLeft
  BLe -> AssocLeft
  BGe -> AssocLeft
  BBitAnd -> AssocLeft
  BBitOr -> AssocLeft
  BUShr -> AssocLeft
  BAnd -> AssocLeft
  BOr -> AssocLeft

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

-- | Uppercase hexadecimal literal, e.g. @0xFF@.
hexLit :: Integer -> Doc ann
hexLit n
  | n < 0 = "-0x" <> hexDigits (negate n)
  | otherwise = "0x" <> hexDigits n
  where
    hexDigits x = pretty (T.toUpper (toText (showHex x "")))

-- | A double-quoted JS string literal. The control escapes mirror the parser's;
--   NUL and the U+2028 \/ U+2029 separators additionally use fixed-length @\\u@
--   escapes — JS string-literal hazards the source layer doesn't have.
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
      -- U+2028 LINE SEPARATOR / U+2029 PARAGRAPH SEPARATOR terminate a string
      -- literal on pre-ES2019 engines (the "JSON is not a JS subset" hazard);
      -- a fixed-length \u escape keeps them inside the literal on every engine.
      '\x2028' -> "\\u2028"
      '\x2029' -> "\\u2029"
      c -> one c
