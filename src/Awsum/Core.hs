-- | Awsum Core IR (intermediate representation).
--
--   • call-by-value,
--   • zero-arg surface defs are lowered to /constants/ ('CValDef').
--
-- Invariants (assumed by codegens and passes):
--   • 'CBuiltIn' must only appear in the /function position/ of 'CCall' (never as a standalone term).
--   • Arity of 'CCall' arguments must match the built-in being called.
--   • 'CValDef' models a pure /constant/ (no effects by construction).
--   • Names in 'CVar' refer either to top-level defs or function parameters.
--   • 'CLoop' appears only at the top of a 'CFunDef' body, produced by the
--     TCO pass. Inside the wrapped body, self-recursive tail calls have
--     been replaced with 'CContinue'.
--   • 'CContinue' appears only inside a 'CLoop' wrapping the same function.
--     Its argument list has the same arity as the enclosing function's
--     parameter list, positionally matched.
module Awsum.Core
  ( IntType (..),
    intSigned,
    intWidth,
    intTypeName,
    CExpr (..),
    CDecl (..),
    CoreProgram (..),
    usedBuiltIns,
    usesIntLit,
  )
where

import Awsum.Syntax (Name)
import Data.Set qualified as Set
import Relude

-- | Concrete built-in integer type. One constructor per shipped type so
--   every pattern match is exhaustive — adding a future variant (Int64,
--   …) forces every backend and codegen site to handle it rather
--   than silently falling through an @_ -> error@ catch-all.
data IntType = TInt32 | TUInt8 | TUInt32
  deriving stock (Show, Eq, Ord)

-- | True iff the type's value space is signed. Keeps the old (signed, width)
--   query pattern available without re-introducing invalid combinations at
--   the type level.
intSigned :: IntType -> Bool
intSigned = \case
  TInt32 -> True
  TUInt8 -> False
  TUInt32 -> False

-- | Bit width of the type's runtime representation (32 for 'TInt32' /
--   'TUInt32', 8 for 'TUInt8').
intWidth :: IntType -> Int
intWidth = \case
  TInt32 -> 32
  TUInt8 -> 8
  TUInt32 -> 32

-- | Canonical surface name of an 'IntType' (e.g. @Int32@, @UInt8@, @UInt32@).
intTypeName :: IntType -> Name
intTypeName = \case
  TInt32 -> "Int32"
  TUInt8 -> "UInt8"
  TUInt32 -> "UInt32"

-- | Core expressions.
data CExpr
  = -- | Local or top-level variable reference.
    CVar Name
  | -- | String literal (already unescaped).
    CString Text
  | -- | Integer literal tagged with its declared type.
    --   Value is stored as arbitrary-precision 'Integer'; the typechecker
    --   has already verified it fits in 'IntType''s range.
    CIntLit Integer IntType
  | -- | Function/built-in application; left-associated by construction.
    CCall CExpr [CExpr]
  | -- | Constructor: integer tag + fields (fields empty for nullary constructors).
    CCon Int [CExpr]
  | -- | Case expression: scrutinee + alternatives @[(tag, bound-var names, body)]@.
    CCase CExpr [(Int, [Name], CExpr)]
  | -- | Row-tagged value: a 32-bit hash that identifies the row label
    --   plus the underlying value of the alternative type. Produced at
    --   lowering time when an expression is implicitly injected into a
    --   structural-sum position — e.g. the call @f "hi"@ with
    --   @f : (Int32 | String) -> …@ wraps @"hi"@ in
    --   @CRow (rowTag String) "hi"@. Distinct from 'CCon' so backends
    --   can pick a representation appropriate for hash-based dispatch
    --   (typically an inline @{tag, value}@ box) without conflating it
    --   with positional nominal constructors.
    CRow Word32 CExpr
  | -- | Row case: scrutinee + alternatives keyed by the same 32-bit
    --   hash that 'CRow' used at injection time. Each arm binds the
    --   row's underlying value to a single name (the inner pattern of
    --   a 'PAscribe' arm in the surface). Dispatch is by exact hash
    --   equality; the typechecker has already proved exhaustiveness
    --   over the closed row.
    CRowCase CExpr [(Word32, Name, CExpr)]
  | -- | Reference to a compiler-provided built-in. The 'Name' is either
    --   an unqualified prelude built-in (e.g. @showInt32@) looked up in
    --   'Awsum.BuiltIn', or a dotted qualified name (e.g.
    --   @IO.Stdout.print@) looked up in the program type's platform
    --   table ('Awsum.Program.platformTable'). Every backend dispatches
    --   on this name to emit the per-target implementation.
    CBuiltIn Name
  | -- | Function body wrapped by the TCO pass. Semantically the value of
    --   the wrapped expression, operationally a jump label: when the body
    --   evaluates to a 'CContinue', execution jumps back to the label with
    --   the function's parameters re-bound to the continue arguments. Only
    --   appears at the top of a 'CFunDef' body.
    CLoop CExpr
  | -- | Positional re-entry into the nearest enclosing 'CLoop' with fresh
    --   parameter values. Produced by the TCO pass in place of a self-tail
    --   call. Arity must match the enclosing function's parameter list.
    CContinue [CExpr]
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

-- | Every 'CBuiltIn' name referenced in the program. Backends gate
--   runtime helpers (@__print@, @__predInt32@, future @__addInt32@, ...)
--   on this so programs that don't touch a given built-in don't pay for it.
usedBuiltIns :: CoreProgram -> Set Name
usedBuiltIns (CoreProgram ds) = foldMap declBuiltIns ds
  where
    declBuiltIns (CFunDef _ _ body) = exprBuiltIns body
    declBuiltIns (CValDef _ body) = exprBuiltIns body
    exprBuiltIns = \case
      CBuiltIn n -> Set.singleton n
      CVar _ -> mempty
      CString _ -> mempty
      CIntLit _ _ -> mempty
      CCall f xs -> exprBuiltIns f <> foldMap exprBuiltIns xs
      CCon _ fs -> foldMap exprBuiltIns fs
      CCase s alts -> exprBuiltIns s <> foldMap (\(_, _, b) -> exprBuiltIns b) alts
      CRow _ v -> exprBuiltIns v
      CRowCase s alts -> exprBuiltIns s <> foldMap (\(_, _, b) -> exprBuiltIns b) alts
      CLoop b -> exprBuiltIns b
      CContinue xs -> foldMap exprBuiltIns xs

-- | Does the program contain any integer literal? Backends that rely on
--   boxing helpers (e.g. WASM's @__box_i32@) can drop them when the
--   answer is 'False'.
usesIntLit :: CoreProgram -> Bool
usesIntLit (CoreProgram ds) = any declHasInt ds
  where
    declHasInt (CFunDef _ _ body) = exprHasInt body
    declHasInt (CValDef _ body) = exprHasInt body
    exprHasInt = \case
      CIntLit _ _ -> True
      CBuiltIn _ -> False
      CVar _ -> False
      CString _ -> False
      CCall f xs -> exprHasInt f || any exprHasInt xs
      CCon _ fs -> any exprHasInt fs
      CCase s alts -> exprHasInt s || any (\(_, _, b) -> exprHasInt b) alts
      CRow _ v -> exprHasInt v
      CRowCase s alts -> exprHasInt s || any (\(_, _, b) -> exprHasInt b) alts
      CLoop b -> exprHasInt b
      CContinue xs -> any exprHasInt xs
