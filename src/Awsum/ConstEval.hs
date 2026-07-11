-- | Compile-time evaluators for built-in operations that have a runtime
-- counterpart in Awsum — a prelude function or a per-target codegen built-in.
-- The defining property: each evaluator computes, in Haskell, exactly the
-- value the runtime would produce, so the two can be differentially compared.
--
-- This is the single source of truth for that semantics, with two consumers:
--
--   * 'Awsum.Simplify.constFold' folds a built-in call over literal operands
--     at compile time, projecting the 'IntOutcome' into a Core cell;
--   * the property suite's oracle ("Awsum.PropertySpec") projects the same
--     'IntOutcome' into the stdout marker it expects, and the
--     @constFold-differential@ property then asserts fold == runtime on every
--     backend.
--
-- The per-target runtime helpers (LLVM\/JVM\/CLR\/WASM\/JS codegen) cannot
-- share code with Haskell — they emit target instructions — so they remain a
-- second implementation, validated against this one by the differential.
-- Two implementations total, not three.
--
-- __Scope.__ Only operations with a runtime twin live here. The structural
-- rewrites of "Awsum.Simplify" (case-of-known-constructor, case-of-case
-- fusion, function inlining, the @let@ family) have no runtime operation to
-- mirror and stay there. Evaluators for other domains (strings, sequences)
-- join this module as they gain a foldable, runtime-mirrored form.
module Awsum.ConstEval
  ( IntOutcome (..),
    ArithError (..),
    ErrShape (..),
    evalInt,
    intOperandType,
    intTypeLo,
    intTypeHi,
    foldableIntBuiltins,
  )
where

import Awsum.Core (IntType (..), intSigned, intWidth)
import Awsum.Syntax (Name)
import Data.Map.Strict qualified as Map
import Relude

-- | The abstract result of evaluating an integer built-in over literal
--   operands — what the runtime helper returns, before any backend codegen
--   or string rendering. 'Awsum.Simplify.constFold' builds the Core cell from
--   it; the property oracle renders the marker string from it.
data IntOutcome
  = -- | @Right v@ — the in-range result, at the result type.
    IntValue !IntType !Integer
  | -- | @Left …@ — an overflow\/underflow failure, with the shape of the
    --   @Left@ payload (see 'ErrShape').
    IntError !ErrShape !ArithError
  | -- | A @Bool@ result (the equalities).
    IntBool !Bool
  deriving stock (Eq, Show)

-- | Which arithmetic failure occurred.
data ArithError = ErrOverflow | ErrUnderflow
  deriving stock (Eq, Show)

-- | The shape of an operation's @Left@ payload. Signed @add@\/@sub@\/@mul@
--   reach both failure directions, so their error is the two-label structural
--   row @(UnderflowError | OverflowError)@ ('RowTwoLabel'); every other
--   operation has one reachable direction and a bare single-constructor error
--   ('BareSingle'). The oracle ignores this distinction; 'constFold' builds
--   the matching cell.
data ErrShape = RowTwoLabel | BareSingle
  deriving stock (Eq, Show)

-- | One foldable built-in: the type every operand must carry (the result
--   type too, except for the @Bool@-returning equalities) and a total
--   evaluator over the operand list — 'Nothing' for an arity that cannot
--   occur after typechecking.
data IntOp = IntOp
  { opOperand :: !IntType,
    opEval :: [Integer] -> Maybe IntOutcome
  }

-- | The single source of truth: every foldable integer built-in, its operand
--   type, and its compile-time semantics. Width and bounds come from the
--   operation (not its operands), so a mistyped literal can never fold under
--   the wrong width.
intOps :: Map Name IntOp
intOps =
  Map.fromList
    [ -- Signed add\/sub\/mul: both directions reachable → two-label row error.
      ("addInt32", bin TInt32 (\a b -> signed (a + b))),
      ("subInt32", bin TInt32 (\a b -> signed (a - b))),
      ("mulInt32", bin TInt32 (\a b -> signed (a * b))),
      ("negInt32", un TInt32 (\a -> if a == intTypeLo TInt32 then bareOver else val TInt32 (negate a))),
      ("succInt32", un TInt32 (succOf TInt32)),
      ("predInt32", un TInt32 (predOf TInt32)),
      ("eqInt32", bin TInt32 (\a b -> IntBool (a == b))),
      ("addUInt8", bin TUInt8 (overOf TUInt8 (+))),
      ("subUInt8", bin TUInt8 (subOf TUInt8)),
      ("mulUInt8", bin TUInt8 (overOf TUInt8 (*))),
      ("succUInt8", un TUInt8 (succOf TUInt8)),
      ("predUInt8", un TUInt8 (predOf TUInt8)),
      ("eqUInt8", bin TUInt8 (\a b -> IntBool (a == b))),
      ("addUInt32", bin TUInt32 (overOf TUInt32 (+))),
      ("subUInt32", bin TUInt32 (subOf TUInt32)),
      ("mulUInt32", bin TUInt32 (overOf TUInt32 (*))),
      ("succUInt32", un TUInt32 (succOf TUInt32)),
      ("predUInt32", un TUInt32 (predOf TUInt32)),
      ("eqUInt32", bin TUInt32 (\a b -> IntBool (a == b)))
    ]
  where
    signed r
      | r > intTypeHi TInt32 = IntError RowTwoLabel ErrOverflow
      | r < intTypeLo TInt32 = IntError RowTwoLabel ErrUnderflow
      | otherwise = val TInt32 r
    -- Unsigned add\/mul: one direction (overflow) → bare error.
    overOf ty f a b = let r = f a b in if r > intTypeHi ty then bareOver else val ty r
    -- Unsigned sub: one direction (underflow) → bare error.
    subOf ty a b = if a < b then bareUnder else val ty (a - b)
    succOf ty a = if a == intTypeHi ty then bareOver else val ty (a + 1)
    predOf ty a = if a == intTypeLo ty then bareUnder else val ty (a - 1)
    val = IntValue
    bareOver = IntError BareSingle ErrOverflow
    bareUnder = IntError BareSingle ErrUnderflow
    bin ty f = IntOp ty (\case [a, b] -> Just (f a b); _ -> Nothing)
    un ty f = IntOp ty (\case [a] -> Just (f a); _ -> Nothing)

-- | Evaluate a built-in call over integer operands. 'Nothing' when the
--   operation is not a foldable int built-in, or the arity disagrees.
evalInt :: Name -> [Integer] -> Maybe IntOutcome
evalInt op xs = Map.lookup op intOps >>= \o -> opEval o xs

-- | The operand type every operand of a foldable int built-in must carry —
--   'Awsum.Simplify.constFold' uses it to refuse folding a literal of the
--   wrong type. 'Nothing' when the operation is not a foldable int built-in.
intOperandType :: Name -> Maybe IntType
intOperandType op = opOperand <$> Map.lookup op intOps

-- | Every foldable integer built-in — the coverage anchor for the property
--   suite's generator: an entry added here without a matching generator case
--   (or vice versa) fails the coverage check.
foldableIntBuiltins :: Set Name
foldableIntBuiltins = Map.keysSet intOps

-- | Inclusive low\/high bound of an integer type's runtime range — the same
--   bounds the per-target helpers range-check against.
intTypeLo, intTypeHi :: IntType -> Integer
intTypeLo ty = if intSigned ty then negate (2 ^ (intWidth ty - 1)) else 0
intTypeHi ty = if intSigned ty then 2 ^ (intWidth ty - 1) - 1 else 2 ^ intWidth ty - 1
