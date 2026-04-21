-- | Awsum Core IR (intermediate representation).
--
--   • call-by-value,
--   • zero-arg surface defs are lowered to /constants/ ('CValDef').
--
-- Invariants (assumed by codegens and passes):
--   • 'CPrim' must only appear in the /function position/ of 'CCall' (never as a standalone term).
--   • Arity of 'CCall' arguments must match the primitive being called.
--   • 'CValDef' models a pure /constant/ (no effects by construction).
--   • Names in 'CVar' refer either to top-level defs or function parameters.
module Awsum.Core
  ( Prim (..),
    IntType (..),
    intSigned,
    intWidth,
    intTypeName,
    CExpr (..),
    CDecl (..),
    CoreProgram (..),
  )
where

import Awsum.Syntax (Name)
import Relude

-- | Built-in primitives known to the backends.
-- Extend this enum when you add new operations (e.g. 'PrimLen', 'PrimTake', …).
data Prim
  = -- | String concatenation.
    PrimConcat
  | -- | Print to stdout (returns unit conceptually).
    PrimPrint
  | -- | Render an integer value of a given type as a String.
    --   The 'IntType' is carried on the primitive so each backend dispatches
    --   on a concrete variant (never on a (signed, width) pair with fallbacks).
    PrimShowInt IntType
  deriving stock (Show, Eq)

-- | Concrete built-in integer type. One constructor per shipped type so
--   every pattern match is exhaustive — adding a future variant (Int64,
--   UInt32, …) forces every backend and codegen site to handle it rather
--   than silently falling through an @_ -> error@ catch-all.
data IntType = TInt32 | TUInt8
  deriving stock (Show, Eq, Ord)

-- | True iff the type's value space is signed. Keeps the old (signed, width)
--   query pattern available without re-introducing invalid combinations at
--   the type level.
intSigned :: IntType -> Bool
intSigned = \case
  TInt32 -> True
  TUInt8 -> False

-- | Bit width of the type's runtime representation (32 for 'TInt32',
--   8 for 'TUInt8').
intWidth :: IntType -> Int
intWidth = \case
  TInt32 -> 32
  TUInt8 -> 8

-- | Canonical surface name of an 'IntType' (e.g. @Int32@, @UInt8@).
intTypeName :: IntType -> Name
intTypeName = \case
  TInt32 -> "Int32"
  TUInt8 -> "UInt8"

-- | Core expressions.
data CExpr
  = -- | A primitive /as a callee/. By invariant, never a standalone value.
    CPrim Prim
  | -- | Local or top-level variable reference.
    CVar Name
  | -- | String literal (already unescaped).
    CString Text
  | -- | Integer literal tagged with its declared type.
    --   Value is stored as arbitrary-precision 'Integer'; the typechecker
    --   has already verified it fits in 'IntType''s range.
    CIntLit Integer IntType
  | -- | Function/primitive application; left-associated by construction.
    CCall CExpr [CExpr]
  | -- | Constructor: integer tag + fields (fields empty for nullary constructors).
    CCon Int [CExpr]
  | -- | Case expression: scrutinee + alternatives @[(tag, bound-var names, body)]@.
    CCase CExpr [(Int, [Name], CExpr)]
  deriving stock (Show, Eq)

-- | Top-level Core declarations.
data CDecl
  = -- | First-order function: @f x1 .. xn = body@.
    CFunDef Name [Name] CExpr
  | -- | Constant value: @c = rhs@ (zero-arg defs lower here).
    CValDef Name CExpr
  deriving stock (Show, Eq)

-- | A Core program is just a list of top-level declarations.
-- Backends may choose any emission order if they respect language scoping rules.
newtype CoreProgram = CoreProgram {cdecls :: [CDecl]}
  deriving stock (Show, Eq)
