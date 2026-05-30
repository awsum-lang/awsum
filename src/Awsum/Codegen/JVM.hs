-- | JVM textual bytecode assembler for Awsum 'Core'.
--
-- Produces a human-readable Jasmin-like text representation of the
-- JVM bytecode that 'Awsum.Codegen.JVM.Assemble' generates as binary.
-- Used for @awsum build -t jvm@ output and snapshot tests.
module Awsum.Codegen.JVM (codegenJVM) where

import Awsum.Codegen.JVM.Assemble (userJvmMethods)
import Awsum.Codegen.JVM.Instr (addInt32Spec, addUInt32Spec, addUInt8Spec, concatSpec, entryArgEitherSpec, eqSpec, eqStringSpec, getArgsSpec, lengthCodePointsSpec, lengthUtf16CodeUnitsSpec, lengthUtf8BytesSpec, mainSpec, mulInt32Spec, mulUInt32Spec, mulUInt8Spec, negInt32Spec, parseInt32Spec, parseUInt32Spec, parseUInt8Spec, predInt32Spec, predUInt32Spec, predUInt8Spec, printSpec, renderMethod, showUInt32Spec, splitOnFirstSpec, stdinReadAllSpec, subInt32Spec, subUInt32Spec, subUInt8Spec, succInt32Spec, succUInt32Spec, succUInt8Spec)
import Awsum.Core
import Awsum.HM (rowTag)
import Awsum.Syntax (Type' (..), noSpan)
import Data.Char qualified as Char
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Relude

-- ════════════════════════════════════════════════════════════════════════════
-- Public API
-- ════════════════════════════════════════════════════════════════════════════

-- | Produce a textual JVM bytecode assembly from a Core program.
codegenJVM :: PreludeTags -> CoreProgram -> Text
codegenJVM ptags prog@(CoreProgram decls) =
  let valNames = Set.fromList [n | CValDef n _ <- decls]
      funNames = Set.fromList [n | CFunDef n _ _ <- decls]
      arities = Map.fromList [(n, length as) | CFunDef n as _ <- decls]
      builtIns = usedBuiltIns prog
      gate cond m = if cond then m else ""
   in T.intercalate "\n"
        $ filter
          (not . T.null)
          [ classHeader,
            "",
            initMethod,
            "",
            gate (Set.member "concatString" builtIns) (concatMethod ptags),
            "",
            gate (Set.member "internalStdoutPrint" builtIns) (printMethod ptags),
            "",
            gate (Set.member "predInt32" builtIns) (predInt32Method ptags),
            "",
            gate (Set.member "predUInt8" builtIns) (predUInt8Method ptags),
            "",
            gate (Set.member "predUInt32" builtIns) (predUInt32Method ptags),
            "",
            gate (Set.member "succInt32" builtIns) (succInt32Method ptags),
            "",
            gate (Set.member "succUInt8" builtIns) (succUInt8Method ptags),
            "",
            gate (Set.member "succUInt32" builtIns) (succUInt32Method ptags),
            "",
            gate (Set.member "eqInt32" builtIns) (eqMethod ptags "__eqInt32" "L_eq_i32"),
            "",
            gate (Set.member "eqUInt8" builtIns) (eqMethod ptags "__eqUInt8" "L_eq_u8"),
            "",
            gate (Set.member "eqUInt32" builtIns) (eqMethod ptags "__eqUInt32" "L_eq_u32"),
            "",
            gate (Set.member "eqString" builtIns) (eqStringMethod ptags),
            "",
            gate (Set.member "addInt32" builtIns) (addInt32Method ptags),
            "",
            gate (Set.member "subInt32" builtIns) (subInt32Method ptags),
            "",
            gate (Set.member "mulInt32" builtIns) (mulInt32Method ptags),
            "",
            gate (Set.member "negInt32" builtIns) (negInt32Method ptags),
            "",
            gate (Set.member "addUInt8" builtIns) (addUInt8Method ptags),
            "",
            gate (Set.member "subUInt8" builtIns) (subUInt8Method ptags),
            "",
            gate (Set.member "mulUInt8" builtIns) (mulUInt8Method ptags),
            "",
            gate (Set.member "addUInt32" builtIns) (addUInt32Method ptags),
            "",
            gate (Set.member "subUInt32" builtIns) (subUInt32Method ptags),
            "",
            gate (Set.member "mulUInt32" builtIns) (mulUInt32Method ptags),
            "",
            gate (Set.member "showUInt32" builtIns) showUInt32Method,
            "",
            gate (Set.member "splitOnFirst" builtIns) (splitOnFirstMethod ptags),
            "",
            gate (Set.member "lengthCodePoints" builtIns) lengthCodePointsMethod,
            "",
            gate (Set.member "lengthUtf16CodeUnits" builtIns) lengthUtf16CodeUnitsMethod,
            "",
            gate (Set.member "lengthUtf8Bytes" builtIns) lengthUtf8BytesMethod,
            "",
            gate (Set.member "parseInt32" builtIns) (parseInt32Method ptags),
            "",
            gate (Set.member "parseUInt8" builtIns) (parseUInt8Method ptags),
            "",
            gate (Set.member "parseUInt32" builtIns) (parseUInt32Method ptags),
            "",
            T.intercalate "\n\n" (map renderMethod (userJvmMethods ptags valNames funNames arities decls)),
            "",
            gate (Set.member "internalGetArgs" builtIns || Set.member "internalStdinReadAllAsUtf16" builtIns) (entryArgEitherMethod ptags),
            "",
            gate (Set.member "internalGetArgs" builtIns) (getArgsMethod ptags),
            "",
            gate (Set.member "internalStdinReadAllAsUtf16" builtIns) stdinReadAllMethod,
            "",
            mainMethod,
            ""
          ]

-- ════════════════════════════════════════════════════════════════════════════
-- Fixed sections
-- ════════════════════════════════════════════════════════════════════════════

classHeader :: Text
classHeader =
  unlines
    [ "; Awsum JVM codegen — Jasmin-like syntax, not compatible with Jasmin.",
      "; This is a textual representation of the bytecode generated by assembleJVM.",
      ".bytecode 55.0",
      ".class public AwsumMain",
      ".super java/lang/Object",
      -- Stashed reference to the 'args' array passed to 'public static
      -- main(String[])'. Read by '__getArgs' to walk every argv element
      -- and build a prelude 'List String' on demand. Always emitted (the
      -- store in 'mainMethod' is unconditional) so the snapshot stays
      -- stable regardless of which built-ins the user program touches.
      ".field private static __argv [Ljava/lang/String;"
    ]

initMethod :: Text
initMethod =
  unlines
    [ ".method <init>()V",
      "  aload_0",
      "  invokespecial java/lang/Object/<init>()V",
      "  return",
      ".end method"
    ]

-- | __concat: implements 'BuiltIn.concatString'. Pre-checks the combined
--   UTF-16 length of both inputs against the language-fixed cap; returns
--   'Right (a + b)' if it fits, 'Left StringTooLong' otherwise (no
--   String.concat call on the rejection path). The cap value (134217728)
--   must stay in sync with 'maxStringLengthUtf16CodeUnits' in
--   'stdlib/Prelude.aww'.
concatMethod :: PreludeTags -> Text
concatMethod ptags =
  renderMethod (concatSpec (ptRight ptags, ptLeft ptags, ptStringTooLong ptags))

-- | __print: low-level platform primitive driven by the prelude's
--   `runIO` via `BuiltIn.internalStdoutPrint`. Returns a Unit value
--   (Object[1] = [Integer(0)]) so the surrounding `case … of Unit ->
--   next` arm in `runIO` dispatches through the standard CCase tag
--   check.
printMethod :: PreludeTags -> Text
printMethod ptags =
  renderMethod (printSpec (ptUnit ptags))

-- predInt32: Int32 -> Either UnderflowError Int32.
--   `Left UnderflowError` on INT32_MIN (tags Left=0, UnderflowError=0);
--   `Right (x - 1)` otherwise (Right=1). Containers are Object[] with
--   boxed Integer tags at [0], matching user CCon emission on the JVM.
predInt32Method :: PreludeTags -> Text
predInt32Method ptags =
  renderMethod (predInt32Spec (ptUnderflowError ptags, ptLeft ptags, ptRight ptags))

-- | @predUInt8@ / @succInt32@ / @succUInt8@ — rendered from their specs in
--   'Awsum.Codegen.JVM.Instr'. Single-branch helpers differing only in the
--   bound (0 / INT32_MAX / 255), the branch (@ifne@ / @if_icmpne@) and
--   @isub@ vs @iadd@; offsets + StackMapTable are resolved by the assembler.
predUInt8Method :: PreludeTags -> Text
predUInt8Method ptags =
  renderMethod (predUInt8Spec (ptUnderflowError ptags, ptLeft ptags, ptRight ptags))

succInt32Method :: PreludeTags -> Text
succInt32Method ptags =
  renderMethod (succInt32Spec (ptOverflowError ptags, ptLeft ptags, ptRight ptags))

succUInt8Method :: PreludeTags -> Text
succUInt8Method ptags =
  renderMethod (succUInt8Spec (ptOverflowError ptags, ptLeft ptags, ptRight ptags))

-- eqString: String -> String -> Bool. Strings flow as java.lang.String,
--   so String.equals delivers the language-level semantics directly:
--   UTF-16 code-unit comparison under the strict-UTF-16 invariant.
eqStringMethod :: PreludeTags -> Text
eqStringMethod ptags =
  renderMethod (eqStringSpec (ptTrue ptags, ptFalse ptags))

-- eqInt32 / eqUInt8: Int32 -> Int32 -> Bool and UInt8 -> UInt8 -> Bool.
--   Both types are boxed as Integer on the JVM, so the two methods have
--   identical bodies but distinct names (parallel to showInt32 vs
--   showUInt8). Returns True=0 or False=1 as a one-slot Object[].
--   A unique label suffix keeps both methods disassemblable in one class.
eqMethod :: PreludeTags -> Text -> Text -> Text
eqMethod ptags name lbl =
  renderMethod (eqSpec name lbl (ptTrue ptags, ptFalse ptags))

-- addInt32: Int32 -> Int32 -> Either ArithError Int32.
--   Promote both operands to long, sum, then range-check against
--   [-2147483648, 2147483647] with `lcmp`. ArithError tags follow the
--   declaration order in `Prelude.aww`: Underflow=0, Overflow=1; Either
--   tags are Left=0, Right=1 as everywhere else in this file.

-- | FNV-1a row tags for @OverflowError@ / @UnderflowError@ as alternatives of
--   the @(UnderflowError | OverflowError)@ error row — the same tags
--   'Awsum.Codegen.JVM.Assemble' computes, so both renderers wrap the error in
--   an identical row cell.
overflowRowTag :: Int32
overflowRowTag = fromIntegral (rowTag (TyCon noSpan "OverflowError"))

underflowRowTag :: Int32
underflowRowTag = fromIntegral (rowTag (TyCon noSpan "UnderflowError"))

-- | FNV-1a row tags for @StringTooLong@ / @UnpairedUtf16Surrogate@ as
--   alternatives of the input-decode error row, used by '__entryArgEither'.
--   Same tags 'Awsum.Codegen.JVM.Assemble' computes.
stringTooLongRowTag :: Int32
stringTooLongRowTag = fromIntegral (rowTag (TyCon noSpan "StringTooLong"))

unpairedSurrogateRowTag :: Int32
unpairedSurrogateRowTag = fromIntegral (rowTag (TyCon noSpan "UnpairedUtf16Surrogate"))

-- | @__addInt32@ / @__subInt32@ — rendered from the int-overflow specs in
--   'Awsum.Codegen.JVM.Instr'. Overflow/underflow is detected with the int
--   sign-bit XOR trick; the error is wrapped in its @(UnderflowError |
--   OverflowError)@ row.
addInt32Method :: PreludeTags -> Text
addInt32Method ptags =
  renderMethod (addInt32Spec (ptOverflowError ptags, ptUnderflowError ptags, ptLeft ptags, ptRight ptags, overflowRowTag, underflowRowTag))

-- addUInt8: UInt8 -> UInt8 -> Either OverflowError UInt8.
--   Both operands are 0..255, so `iadd` produces a value in 0..510 with
--   no JVM-level overflow; one `if_icmple` against 255 picks the branch.
--   On the ok path the sum is already a valid UInt8 — no mask needed.

-- | @__addUInt8@ / @__subUInt8@ / @__mulUInt8@ — rendered from their specs in
--   'Awsum.Codegen.JVM.Instr'. UInt8 fits in @int@ (no long); the error is a
--   single type (no row wrap).
addUInt8Method :: PreludeTags -> Text
addUInt8Method ptags =
  renderMethod (addUInt8Spec (ptOverflowError ptags, ptLeft ptags, ptRight ptags))

-- subInt32: Int32 -> Int32 -> Either (UnderflowError | OverflowError) Int32.
--   Promote both operands to long, subtract, then range-check the result.
--   ArithError tags follow declaration order: Underflow=0, Overflow=1.
--   Mirrors 'addInt32Method' with 'lsub' replacing 'ladd'.
subInt32Method :: PreludeTags -> Text
subInt32Method ptags =
  renderMethod (subInt32Spec (ptOverflowError ptags, ptUnderflowError ptags, ptLeft ptags, ptRight ptags, overflowRowTag, underflowRowTag))

-- mulInt32: Int32 -> Int32 -> Either ArithError Int32.
--   Promote both operands to long, multiply at long width, then range-
--   check the result against [-2147483648, 2147483647] with 'lcmp'.
--   Direction (over vs under): same-sign overflow is positive, opposite-
--   sign is negative — read off `(a ^ b) >= 0`. Slot 2 holds @a@ for
--   the direction split on the err path; slot 3 holds the boxed result
--   on the ok path / boxed AE on the err paths. Mirrors 'addInt32Method'
--   with 'lmul' (0x69) replacing 'ladd'.

-- | @__mulInt32@ — rendered from 'Awsum.Codegen.JVM.Instr.mulInt32Spec'
--   (long-width @lmul@ + @lcmp@ range check); the error is wrapped in its
--   @(UnderflowError | OverflowError)@ row.
mulInt32Method :: PreludeTags -> Text
mulInt32Method ptags =
  renderMethod (mulInt32Spec (ptOverflowError ptags, ptUnderflowError ptags, ptLeft ptags, ptRight ptags, overflowRowTag, underflowRowTag))

-- negInt32: Int32 -> Either OverflowError Int32.
--   Mirrors 'succInt32Method' with INT32_MIN as the boundary and 'ineg'
--   for the non-overflow branch. OverflowError is single-constructor,
--   so its tag is 0 — Left-branch encoding is identical to 'predInt32'.
negInt32Method :: PreludeTags -> Text
negInt32Method ptags =
  renderMethod (negInt32Spec (ptOverflowError ptags, ptLeft ptags, ptRight ptags))

-- subUInt8: UInt8 -> UInt8 -> Either UnderflowError UInt8.
--   Both operands are 0..255 so 'isub' produces a value in -255..255 with
--   no JVM-level overflow; one 'iflt' picks the underflow branch. On the
--   ok path the result is already a valid UInt8 — no mask needed.
subUInt8Method :: PreludeTags -> Text
subUInt8Method ptags =
  renderMethod (subUInt8Spec (ptUnderflowError ptags, ptLeft ptags, ptRight ptags))

-- mulUInt8: UInt8 -> UInt8 -> Either OverflowError UInt8.
--   Both operands are 0..255 so 'imul' produces a value in 0..65025 with
--   no JVM-level overflow (i32 fits the full range). One 'if_icmple'
--   against 255 picks the branch — same shape as 'addUInt8Method' with
--   'imul' replacing 'iadd'. No mask on the ok path since the product
--   is already a valid UInt8 by construction.
mulUInt8Method :: PreludeTags -> Text
mulUInt8Method ptags =
  renderMethod (mulUInt8Spec (ptOverflowError ptags, ptLeft ptags, ptRight ptags))

-- showUInt32: UInt32 -> String. JVM int is signed 32-bit, so values
--   2^31..2^32-1 would render as negative via 'Integer.toString'.
--   'Integer.toUnsignedString' (Java 8+, on our Java 11 floor) prints
--   the unsigned decimal directly.

-- | First helper rendered from the unified instruction IR
--   ('Awsum.Codegen.JVM.Instr'): same text as before, now a total
--   projection of 'showUInt32Spec' — the very value 'assembleMethod' turns
--   into bytes, so text and binary cannot diverge here.
showUInt32Method :: Text
showUInt32Method = renderMethod showUInt32Spec

-- predUInt32: UInt32 -> Either UnderflowError UInt32. The boundary check
--   is also against 0 (same as 'predUInt8'), so the body is structurally
--   identical to predUInt8Method — only the labels are renamed to keep
--   both methods in one class without label collision.

-- | @__predUInt32@ — rendered from the unified instruction IR
--   ('Awsum.Codegen.JVM.Instr.predUInt32Spec'); same text as before, now a
--   total projection of the value 'assembleMethod' turns into bytes.
predUInt32Method :: PreludeTags -> Text
predUInt32Method ptags =
  renderMethod (predUInt32Spec (ptUnderflowError ptags, ptLeft ptags, ptRight ptags))

-- | @__succUInt32@ — rendered from 'Awsum.Codegen.JVM.Instr.succUInt32Spec'.
--   Boundary 4294967295 is the @iconst_m1@ bit pattern; on the ok path
--   @v + 1@ cannot wrap because @v /= 4294967295@ was already checked.
succUInt32Method :: PreludeTags -> Text
succUInt32Method ptags =
  renderMethod (succUInt32Spec (ptOverflowError ptags, ptLeft ptags, ptRight ptags))

-- addUInt32: UInt32 -> UInt32 -> Either OverflowError UInt32. Promote
--   both operands to unsigned long via 'Integer.toUnsignedLong' (Java
--   8+, on our Java 11 floor); the sum lives in [0, 2^33-2].
--   'Long.compareUnsigned' against 4294967295 names the boundary check
--   directly. The l2i on the ok path keeps the low 32 bits — exactly
--   the in-range u32 result.

-- | @__addUInt32@ / @__subUInt32@ / @__mulUInt32@ — rendered from their specs
--   in 'Awsum.Codegen.JVM.Instr'. add/mul widen to @long@ and compare unsigned
--   against the u32 max built as @(1L<<32)-1@ (no @CONSTANT_Long@); sub stays
--   in @int@ via @Integer.compareUnsigned@. UInt32 errors are single types
--   (no row).
addUInt32Method :: PreludeTags -> Text
addUInt32Method ptags =
  renderMethod (addUInt32Spec (ptOverflowError ptags, ptLeft ptags, ptRight ptags))

-- subUInt32: UInt32 -> UInt32 -> Either UnderflowError UInt32. Compare
--   @a < b@ as unsigned via 'Integer.compareUnsigned' (Java 8+, on our
--   Java 11 floor) — negative result means underflow. On the ok path
--   @isub@ at int width gives the correct u32 difference (bit pattern
--   of @a - b mod 2^32@ equals @a - b@ when @a >= b@ in unsigned).
subUInt32Method :: PreludeTags -> Text
subUInt32Method ptags =
  renderMethod (subUInt32Spec (ptUnderflowError ptags, ptLeft ptags, ptRight ptags))

-- mulUInt32: UInt32 -> UInt32 -> Either OverflowError UInt32. The
--   product of two u32 values is in [0, (2^32-1)^2 ≈ 2^64-2^33+1]; this
--   exceeds @Long.MAX_VALUE@, so signed 'lcmp' against 4294967295L
--   would misclassify some overflowing products as in-range.
--   'Long.compareUnsigned' (Java 8+, on our Java 11 floor) compares the
--   product to the u32 boundary correctly across the full u64 range.
--   Both operands are widened via 'Integer.toUnsignedLong'.
mulUInt32Method :: PreludeTags -> Text
mulUInt32Method ptags =
  renderMethod (mulUInt32Spec (ptOverflowError ptags, ptLeft ptags, ptRight ptags))

-- parseUInt32: String -> Either ParseError UInt32. Same shape as
--   'parseUInt8Method' minus the sign handling, with a long accumulator
--   (max running magnitude is 4294967295 * 10 + 9 = 42949672959 — fits
--   in long-signed). On the ok path l2i takes the low 32 bits, which
--   are the correct u32 bit pattern.
parseUInt32Method :: PreludeTags -> Text
parseUInt32Method ptags =
  renderMethod (parseUInt32Spec (ptParseError ptags, ptLeft ptags, ptRight ptags))

-- splitOnFirst: String -> String -> Maybe (Tuple2 String String).
--   Defers substring search to 'String.indexOf(String)', which returns -1
--   on miss and 0 on empty 'sep' — both behaviours match the prelude
--   contract directly. On hit, 'String.substring' allocates fresh
--   String objects (not aliased into the input), then we wrap them in
--   Tuple2 (Object[3], tag 0) inside Just (Object[2], tag 1). On miss
--   we return Nothing (Object[1], tag 0).
splitOnFirstMethod :: PreludeTags -> Text
splitOnFirstMethod ptags =
  renderMethod (splitOnFirstSpec (ptNothing ptags, ptTuple2 ptags, ptJust ptags))

-- lengthCodePoints: String -> UInt32. 'String.codePointCount(0, length())'
--   walks the UTF-16 buffer once and counts surrogate pairs as one
--   codepoint, matching the prelude contract.
lengthCodePointsMethod :: Text
lengthCodePointsMethod = renderMethod lengthCodePointsSpec

-- lengthUtf16CodeUnits: String -> UInt32. JVM strings are UTF-16
--   internally, so 'String.length()' is exactly the code-unit count.
lengthUtf16CodeUnitsMethod :: Text
lengthUtf16CodeUnitsMethod = renderMethod lengthUtf16CodeUnitsSpec

-- lengthUtf8Bytes: String -> UInt32. 'String.getBytes(StandardCharsets.UTF_8)'
--   produces standard (not modified) UTF-8 — supplementary characters
--   come out as four bytes, not six. The intermediate byte array is
--   discarded; if profiling ever flags this, a manual pass over the
--   chars summing 1/2/3/4-byte contributions per code point would
--   avoid it.
lengthUtf8BytesMethod :: Text
lengthUtf8BytesMethod = renderMethod lengthUtf8BytesSpec

-- parseInt32: String -> Either ParseError Int32.
--   Handrolled decimal parser; grammar mirrors Awsum's literal — optional
--   '-', one or more ASCII digits, nothing else. The accumulator is a
--   long, capped at the magnitude `|minInt32|` (2147483648); anything
--   above that fails fast. After the loop, the negative path negates and
--   passes (since `acc <= 2147483648` ⇒ `-acc >= -2147483648`); the
--   positive path range-checks against `maxInt32` (2147483647). Slot 4
--   carries the negative-flag during parsing and is later reused to
--   hold the boxed `ParseError` on the L_parseInt32_fail path — JVM
--   slot reuse is fine because the verifier tracks the type after each
--   instruction.
parseInt32Method :: PreludeTags -> Text
parseInt32Method ptags =
  renderMethod (parseInt32Spec (ptParseError ptags, ptLeft ptags, ptRight ptags))

-- parseUInt8: String -> Either ParseError UInt8.
--   Same shape as 'parseInt32Method' minus the sign handling — UInt8
--   does not represent a negative number — and with an i32 accumulator,
--   since the running magnitude never exceeds 2559 (255 * 10 + 9) before
--   the `> 255` check triggers a fail.

-- | @__parseUInt8@ — rendered from 'Awsum.Codegen.JVM.Instr.parseUInt8Spec'
--   (digit loop with a backward branch; its @full_frame@ / @chop@
--   StackMapTable is derived by the assembler's classifier).
parseUInt8Method :: PreludeTags -> Text
parseUInt8Method ptags =
  renderMethod (parseUInt8Spec (ptParseError ptags, ptLeft ptags, ptRight ptags))

-- | __entryArgEither: wraps argv[1] in 'Either (StringTooLong |
--   UnpairedUtf16Surrogate) String' for the user's 'main'. Two checks:
--     1. Length cap: 'String.length()' is UTF-16 code units (O(1) on
--        JVM), compared to 'maxStringLengthUtf16CodeUnits' (2^27).
--     2. Surrogate pairing: walk code units; high surrogate (D800..DBFF)
--        must be immediately followed by a low surrogate (DC00..DFFF).
--        Standalone or trailing high → 'Left UnpairedUtf16Surrogate'.
--   Cap-check has priority — it short-circuits before the surrogate
--   walk runs. The cap value must stay in sync with
--   'maxStringLengthUtf16CodeUnits' in 'stdlib/Prelude.aww'. Row tags
--   are encoded as signed Int32 (CONSTANT_Integer), wrapping high-bit
--   FNV values to their negative twos-complement; the user-side
--   'Awsum.Core.CRowCase' lowering rewrites to a 'CCase' on the same
--   wrapped value, so the bit patterns match through Integer boxing.
--
--   Layout (identical for both Left arms, only the row tag differs):
--     Right s : Object[2] = [Integer(1), s]
--     Left  e : Object[2] = [Integer(0), row]
--               row   : Object[2] = [Integer(rowTag), inner]
--               inner : Object[1] = [Integer(0)]
--
--   Local slots:
--     V_0 = arg (Object), V_1 = string (after checkcast),
--     V_2 = length, V_3 = i, V_4 = expecting_low (0/1),
--     V_5 = c & 0xFC00 (masked code unit, used to dispatch surrogate),
--     V_6 = inner (transient), V_7 = row (transient).
entryArgEitherMethod :: PreludeTags -> Text
entryArgEitherMethod ptags =
  renderMethod (entryArgEitherSpec (ptRight ptags, ptLeft ptags, ptStringTooLong ptags, ptUnpairedUtf16Surrogate ptags, stringTooLongRowTag, unpairedSurrogateRowTag))

-- | __getArgs: zero-arg helper for 'BuiltIn.internalGetArgs', called
--   from 'runIO''s 'IOGetArgs' arm. Reads the 'args' array stashed in
--   the '__argv' static field by 'mainMethod' and builds a prelude
--   'List String' on demand. Each element is routed through
--   '__entryArgEither' for the strict-UTF-16 validation; the error
--   semantics is all-or-nothing — the first failing element
--   short-circuits the entire call with its 'Left'. Walked
--   right-to-left so the cons chain is built bottom-up without
--   recursion. Per the no-memoisation decision each call returns a
--   fresh chain; argv is invariant during execution so repeat calls
--   are deterministically equal.
--
--   Locals: 0 = argv (String[]), 1 = i (int loop counter), 2 = list
--   (Object[] accumulator), 3 = validated element (Object[] of Either).
getArgsMethod :: PreludeTags -> Text
getArgsMethod ptags =
  renderMethod (getArgsSpec (ptNil ptags, ptCons ptags, ptRight ptags))

-- | __stdinReadAll: zero-arg helper for
--   'BuiltIn.internalStdinReadAllAsUtf16', called from 'runIO''s
--   'IOStdinReadAll' arm. Consumes 'System.in' to EOF into a
--   'ByteArrayOutputStream', decodes the captured bytes as standard
--   UTF-8 via @new String(byte[], StandardCharsets.UTF_8)@, then
--   routes the result through '__entryArgEither' for the same
--   strict-UTF-16 validation 'getArgs' uses.
--
--   The explicit @StandardCharsets.UTF_8@ avoids depending on the
--   platform default charset — that one is influenced by
--   @-Dfile.encoding@ (which the test harness sets to @UTF-8@, but
--   user-deployed JVMs may not). 'System.in.read(byte[], int, int)'
--   never reads the @ANSI@-mangled args path that broke
--   'IO.Args.getArgs' on Windows×JVM, so a property of the form
--   "supplementary-plane character round-trips" passes here when
--   the argv-based variant truncates to @?@.
--
--   Locals: slot 0 = ByteArrayOutputStream baos, slot 1 = byte[] buf
--   (reused for the final byte[] after the loop), slot 2 = int got.
stdinReadAllMethod :: Text
stdinReadAllMethod =
  renderMethod stdinReadAllSpec

mainMethod :: Text
mainMethod =
  renderMethod (mainSpec (mangle "main") (mangle "runIO"))

-- ════════════════════════════════════════════════════════════════════════════
-- User declarations
-- ════════════════════════════════════════════════════════════════════════════

mangle :: Text -> Text
mangle t =
  let ok c = Char.isAlphaNum c || c == '_' || c == '\''
      body = T.map (\c -> if ok c then c else '_') t
   in "v_" <> body
