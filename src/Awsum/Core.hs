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
  deriving stock (Show, Eq)

-- | Core expressions.
data CExpr
  = -- | A primitive /as a callee/. By invariant, never a standalone value.
    CPrim Prim
  | -- | Local or top-level variable reference.
    CVar Name
  | -- | String literal (already unescaped).
    CString Text
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
