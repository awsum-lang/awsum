-- | Surface syntax for Awsum.
--
-- Invariants & conventions (enforced by the parser, not the types here):
--  • Module segments (in imports) are UpperCamelCase, value names are lowerCamelCase.
--  • Arrow types are right-associative (a -> b -> c == a -> (b -> c)).
module Awsum.Syntax
  ( Name,
    SrcSpan (..),
    noSpan,
    spanBetween,
    exprSpan,
    Program (..),
    ImportDecl (..),
    Decl (..),
    ConDef (..),
    Type' (..),
    QName (..),
    Op' (..),
    Literal (..),
    Expr (..),
    CaseAlt (..),
    Pattern (..),
    Comment (..),
    Param (..),
    paramName,
    paramSpan,
    typeSpan,
  )
where

import Relude

-- | Source span: start and end positions (1-based, matching Megaparsec and editors).
data SrcSpan = SrcSpan
  { spanStartLine :: !Int,
    spanStartCol :: !Int,
    spanEndLine :: !Int,
    spanEndCol :: !Int
  }
  deriving stock (Show)

-- | SrcSpan equality is always True so that AST equality ignores positions.
--   This lets all existing tests continue working without changing expected values.
instance Eq SrcSpan where _ == _ = True

-- | SrcSpan ordering also ignores positions (mirrors 'Eq') so derived
--   'Ord' on AST nodes with embedded spans compares only the semantic
--   parts. Needed because 'Type'' derives 'Ord' and is used as a key
--   elsewhere.
instance Ord SrcSpan where compare _ _ = EQ

-- | Placeholder span for hand-constructed ASTs (tests, Arbitrary instances).
noSpan :: SrcSpan
noSpan = SrcSpan 0 0 0 0

-- | Combine two spans into one covering both.
spanBetween :: SrcSpan -> SrcSpan -> SrcSpan
spanBetween a b = SrcSpan (spanStartLine a) (spanStartCol a) (spanEndLine b) (spanEndCol b)

-- | Extract the source span from an expression.
exprSpan :: Expr -> SrcSpan
exprSpan = \case
  EVar sp _ -> sp
  EApp sp _ _ -> sp
  EInfix sp _ _ _ -> sp
  EParens sp _ -> sp
  ELit sp _ -> sp
  ECon sp _ -> sp
  ECase sp _ _ _ -> sp

-- | Lexical identifier (kept as 'Text' for simplicity).
--   The parser is responsible for validating case/style rules.
type Name = Text

-- | Qualified module path, e.g. @IO.Stdout@ ⇒ @\"IO\" :| [\"Stdout\"]@.
type ModulePath = NonEmpty Name

-- | A single source file: zero or more imports and a /non-empty/ list of top-level declarations.
--   Parser guarantees @decls@ is 'NonEmpty' (empty programs are rejected).
data Program = Program
  { -- | @import Foo.Bar@
    imports :: [ImportDecl],
    -- | at least one declaration
    decls :: NonEmpty Decl
  }
  deriving stock (Show, Eq)

-- | Import declaration with optional leading comments and trailing inline comment.
--   Leading comments appear before the @import@ keyword on preceding lines;
--   the trailing comment is an optional @-- …@ on the same line.
data ImportDecl = ImportDecl [Comment] ModulePath (Maybe Text)
  deriving stock (Show, Eq)

-- Comments (payloads are stored *without* delimiters)
data Comment
  = LineComment Text -- text after "--"
  | BlockComment Text -- text between "{-" and "-}"
  deriving stock (Show, Eq)

-- | A bound function parameter, with the source span of the identifier.
--   Spans let downstream tooling (warnings, quick-fixes) point at exactly
--   the offending parameter rather than the whole definition.
data Param = Param SrcSpan Name
  deriving stock (Show, Eq)

-- | Extract the textual name of a parameter.
paramName :: Param -> Name
paramName (Param _ n) = n

-- | Extract the source span of a parameter (the identifier itself).
paramSpan :: Param -> SrcSpan
paramSpan (Param sp _) = sp

-- | Top-level declaration.
data Decl
  = -- | Type signature: @main : τ -- comment@
    Sig SrcSpan Name Type' (Maybe Text)
  | -- | Function/value definition: @f x y = e  -- comment@.
    --   The argument list may be empty in the /surface/.
    --   Lowering will treat zero-arg defs as /constants/.
    FunDef SrcSpan Name [Param] Expr (Maybe Text)
  | -- | Sum type declaration: @type Bool = True | False@.
    --   Empty constructor list means uninhabited type (e.g. @type Never@).
    --   Type parameters carry their own span (as 'Param') so the
    --   unused-type-parameter warning can target precisely the identifier.
    TypeDecl SrcSpan Name [Param] [ConDef] (Maybe Text)
  | CommentDecl Comment
  deriving stock (Show, Eq)

-- | Constructor definition inside a 'TypeDecl'.
--   The 'SrcSpan' covers just the constructor's name in the source so
--   quick-fixes (e.g. rename '_C' to 'C') can target it precisely.
--   Field types are stored for future use (e.g. @Just a@); empty for nullary constructors.
data ConDef = ConDef SrcSpan Name [Type']
  deriving stock (Show, Eq)

-- | Surface types. Each constructor carries a 'SrcSpan' covering the
--   portion of source that introduced it, so diagnostics can point at a
--   single type identifier (e.g. a @_A@ reference) instead of the whole
--   signature line. Spans are ignored by derived 'Eq' / 'Ord'.
data Type'
  = -- | Type variable, e.g. 'a'.
    TyVar SrcSpan Name
  | -- | Type constructor, e.g. @\"String\"@, @\"IOUnit\"@.
    TyCon SrcSpan Name
  | -- | Type application, e.g. @Lookup String@.
    TyApp SrcSpan Type' Type'
  | -- | Arrow type @a -> b@ (right-associative by convention).
    TyArrow SrcSpan Type' Type'
  deriving stock (Show, Eq, Ord)

-- | Extract the source span of a type.
typeSpan :: Type' -> SrcSpan
typeSpan = \case
  TyVar sp _ -> sp
  TyCon sp _ -> sp
  TyApp sp _ _ -> sp
  TyArrow sp _ _ -> sp

-- | Qualified value name: module path (possibly empty) + base name.
--   Examples:
--     • @IO.Stdout.print@ ⇒ @QName [\"IO\",\"Stdout\"] \"print\"@
--     • @input@           ⇒ @QName [] \"input\"@
data QName = QName [Name] Name
  deriving stock (Show, Eq, Ord)

-- | Infix operator tags used by the surface syntax.
--   Extend this when new symbolic ops appear (remember to update parser/render/fixities).
data Op'
  = -- | @e1 ++ e2@ (left-associative, lowest precedence among our ops)
    OpConcat
  deriving stock (Show, Eq)

-- | Literals in the surface language.
--   Integer literals are untyped at the syntax level — the type is determined by
--   context during typechecking (no defaulting; see docs/integers.md).
data Literal
  = LString Text
  | LInt Integer
  deriving stock (Show, Eq)

-- | Surface expressions.
data Expr
  = -- | Variable or qualified function name.
    EVar SrcSpan QName
  | -- | Function application (left-associative).
    EApp SrcSpan Expr Expr
  | -- | Infix application (e.g. @++@). Parser assigns fixities.
    EInfix SrcSpan Op' Expr Expr
  | -- | Explicit parentheses as written by the user.
    --   Kept to make render ∘ parse an identity in tests.
    EParens SrcSpan Expr
  | -- | Literal (currently only strings).
    ELit SrcSpan Literal
  | -- | Constructor reference (uppercase, e.g. @True@, @Nothing@).
    ECon SrcSpan Name
  | -- | Pattern matching: @case e of { alt1; alt2; … }@.
    --   The trailing @[Comment]@ holds comments after the last arm — useful for
    --   temporarily commenting-out the last alternative while editing.
    ECase SrcSpan Expr (NonEmpty CaseAlt) [Comment]
  deriving stock (Show, Eq)

-- | A single alternative in a @case@ expression.
--   Leading comments appear before the arm; trailing is an optional inline @-- …@.
--
--   Preserving comments inside indented blocks (before, between, and after arms)
--   lets users comment-out / uncomment individual case arms while editing, without
--   the formatter destroying those comments on save.
data CaseAlt = CaseAlt [Comment] Pattern Expr (Maybe Text)
  deriving stock (Show, Eq)

-- | Patterns for @case@ alternatives.
--   Currently only constructor patterns; variable and wildcard are for future use.
data Pattern
  = -- | Constructor pattern, e.g. @Just x@. The 'SrcSpan' covers the
    --   constructor's name in the source so quick-fixes targeting the
    --   pattern (e.g. rename '_C' to 'C') can edit precisely.
    --   Fields are empty for nullary constructors.
    PCon SrcSpan Name [Pattern]
  | -- | Variable binding (future). Span covers just the identifier.
    PVar SrcSpan Name
  | -- | Wildcard @_@ (future).
    PWild
  deriving stock (Show, Eq)
