-- | Surface syntax for Awsum.
--
-- Invariants & conventions (enforced by the parser, not the types here):
--  • Module segments (in imports) are UpperCamelCase, value names are lowerCamelCase.
--  • Arrow types are right-associative (a -> b -> c == a -> (b -> c)).
module Awsum.Syntax
  ( Name,
    Program (..),
    ImportDecl (..),
    Decl (..),
    Type' (..),
    QName (..),
    Op' (..),
    Literal (..),
    Expr (..),
    Comment (..),
  )
where

import Relude

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

-- | Import declaration. Kept as a 'newtype' so we can extend with
--   aliasing/hiding lists in the future without breaking signatures.
newtype ImportDecl = ImportDecl ModulePath
  deriving stock (Show, Eq)

-- Comments (payloads are stored *without* delimiters)
data Comment
  = LineComment Text -- text after "--"
  | BlockComment Text -- text between "{-" and "-}"
  deriving stock (Show, Eq)

-- | Top-level declaration.
data Decl
  = -- | Type signature: @main : τ -- comment@
    Sig Name Type' (Maybe Text)
  | -- | Function/value definition: @f x y = e  -- comment@.
    --   The argument list may be empty in the /surface/.
    --   Lowering will treat zero-arg defs as /constants/.
    FunDef Name [Name] Expr (Maybe Text)
  | CommentDecl Comment
  deriving stock (Show, Eq)

-- | Surface types. For MVP we only have type constructors (e.g. @String@, @IOUnit@)
--   and arrows. Application (like @IO ()@) is not modeled here yet.
data Type'
  = -- | type variable, e.g. 'a'
    TyVar Name
  | -- | Type constructor, e.g. @\"String\"@, @\"IOUnit\"@.
    TyCon Name
  | -- | Arrow type @a -> b@ (right-associative by convention).
    TyArrow Type' Type'
  deriving stock (Show, Eq)

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
--   At the moment we only support double-quoted string literals.
data Literal = LString Text
  deriving stock (Show, Eq)

-- | Surface expressions.
data Expr
  = -- | Variable or qualified function name.
    EVar QName
  | -- | Function application (left-associative).
    EApp Expr Expr
  | -- | Infix application (e.g. @++@). Parser assigns fixities.
    EInfix Op' Expr Expr
  | -- | Explicit parentheses as written by the user.
    --   Kept to make render ∘ parse an identity in tests.
    EParens Expr
  | -- | Literal (currently only strings).
    ELit Literal
  deriving stock (Show, Eq)
