-- | CLR textual CIL assembler for Awsum 'Core'.
--
-- Produces a human-readable ilasm-like text representation of the
-- CIL bytecode that 'Awsum.Codegen.CLR.Assemble' generates as binary.
-- Used for @awsum asm -t clr@ output and snapshot tests.
module Awsum.Codegen.CLR (codegenCLR) where

import Awsum.Codegen.CLR.Assemble (ECtx (..), declCilMethod)
import Awsum.Codegen.CLR.Instr (addInt32Spec, addUInt32Spec, addUInt8Spec, concatSpec, entryArgEitherSpec, eqSpec, eqStringSpec, getArgsSpec, lengthCodePointsSpec, lengthUtf16CodeUnitsSpec, lengthUtf8BytesSpec, mainSpec, mulInt32Spec, mulUInt32Spec, mulUInt8Spec, negInt32Spec, parseInt32Spec, parseUInt32Spec, parseUInt8Spec, predInt32Spec, predUInt32Spec, predUInt8Spec, printSpec, renderCilMethod, showUInt32Spec, splitOnFirstSpec, stdinReadAllSpec, subInt32Spec, subUInt32Spec, subUInt8Spec, succInt32Spec, succUInt32Spec, succUInt8Spec)
import Awsum.Core
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Relude

-- ════════════════════════════════════════════════════════════════════════════
-- Public API
-- ════════════════════════════════════════════════════════════════════════════

-- | Produce a textual CIL assembly from a Core program.
codegenCLR :: PreludeTags -> CoreProgram -> Text
codegenCLR ptags prog@(CoreProgram decls) =
  let valNames = Set.fromList [n | CValDef n _ <- decls]
      funNames = Set.fromList [n | CFunDef n _ _ <- decls]
      arities = Map.fromList [(n, length as) | CFunDef n as _ <- decls]
      -- Base context for 'declCilMethod' (the shared Core→CilMethod lowering).
      -- 'CallNamed' renders the name symbolically; the binary assembler resolves
      -- it to a token from 'pTokMap'.
      ectx = ECtx {eParams = Map.empty, eLocals = Map.empty, eNextScratch = 0, eValDefs = valNames, eFunDefs = funNames, eArities = arities}
      renderUserDecl d = renderCilMethod (declCilMethod ectx d)
      builtIns = usedBuiltIns prog
      gate cond m = if cond then m else ""
   in T.intercalate "\n"
        $ filter
          (not . T.null)
          [ assemblyHeader,
            "",
            classOpen,
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
            gate (Set.member "eqInt32" builtIns) (eqMethod ptags "__eqInt32" "IL_eq_i32"),
            "",
            gate (Set.member "eqUInt8" builtIns) (eqMethod ptags "__eqUInt8" "IL_eq_u8"),
            "",
            gate (Set.member "eqUInt32" builtIns) (eqMethod ptags "__eqUInt32" "IL_eq_u32"),
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
            gate (Set.member "lengthCodePoints" builtIns) lengthCodePointsMethod,
            gate (Set.member "lengthUtf16CodeUnits" builtIns) lengthUtf16CodeUnitsMethod,
            gate (Set.member "lengthUtf8Bytes" builtIns) lengthUtf8BytesMethod,
            "",
            gate (Set.member "parseInt32" builtIns) (parseInt32Method ptags),
            "",
            gate (Set.member "parseUInt8" builtIns) (parseUInt8Method ptags),
            "",
            gate (Set.member "parseUInt32" builtIns) (parseUInt32Method ptags),
            "",
            T.intercalate "\n\n" (map renderUserDecl decls),
            "",
            gate (Set.member "internalGetArgs" builtIns || Set.member "internalStdinReadAllAsUtf16" builtIns) (entryArgEitherMethod ptags),
            "",
            gate (Set.member "internalGetArgs" builtIns) (getArgsMethod ptags),
            gate (Set.member "internalStdinReadAllAsUtf16" builtIns) stdinReadAllMethod,
            "",
            mainMethod,
            "",
            classClose,
            ""
          ]

-- ════════════════════════════════════════════════════════════════════════════
-- Fixed sections
-- ════════════════════════════════════════════════════════════════════════════

assemblyHeader :: Text
assemblyHeader =
  unlines
    [ "// Awsum CLR codegen — ilasm-like syntax, not compatible with ilasm.",
      "// This is a textual representation of the bytecode generated by assembleCLR.",
      ".assembly extern System.Runtime {}",
      ".assembly extern System.Console {}",
      ".assembly AwsumMain {}",
      ".module AwsumMain.dll"
    ]

classOpen :: Text
classOpen = ".class public auto ansi AwsumMain extends [System.Runtime]System.Object\n{"

classClose :: Text
classClose = "}"

initMethod :: Text
initMethod =
  unlines
    [ "  .method private hidebysig specialname rtspecialname instance void .ctor() cil managed",
      "  {",
      "    ldarg.0",
      "    call instance void [System.Runtime]System.Object::.ctor()",
      "    ret",
      "  }"
    ]

-- | __concat: implements 'BuiltIn.concatString'. Pre-checks the combined
--   UTF-16 length of both inputs against the language-fixed cap; returns
--   'Right (a + b)' if it fits, 'Left StringTooLong' otherwise. The cap
--   value (134217728 = 2^27) must stay in sync with
--   'maxStringLengthUtf16CodeUnits' in 'stdlib/Prelude.aww'.
--   System.String::get_Length() returns UTF-16 code units (CLR strings
--   are UTF-16 natively), so the check unit matches the language-level
--   cap directly. Both lengths are widened to int64 before summing to
--   stay defensive against any input that overshoots the invariant.
concatMethod :: PreludeTags -> Text
concatMethod ptags = renderCilMethod (concatSpec (ptRight ptags) (ptLeft ptags) (ptStringTooLong ptags))

-- | __print: low-level platform primitive driven by the prelude's
--   `runIO` via `BuiltIn.internalStdoutPrint`. Returns a Unit value
--   (object[1] = [boxed Int32 0]) so the surrounding `case … of Unit
--   -> next` arm in `runIO` dispatches through the standard CCase
--   tag check.
printMethod :: PreludeTags -> Text
printMethod ptags = renderCilMethod (printSpec (ptUnit ptags))

-- predInt32: Int32 -> Either UnderflowError Int32.
--   Containers are object[] (newarr) with boxed Int32 tag at [0] and
--   fields at [1..], matching user CCon emission on the CLR. Tags:
--   Left=0, Right=1, UnderflowError=0.
predInt32Method :: PreludeTags -> Text
predInt32Method ptags = renderCilMethod (predInt32Spec (ptUnderflowError ptags) (ptLeft ptags) (ptRight ptags))

-- predUInt8: UInt8 -> Either UnderflowError UInt8.
--   Mirrors 'predInt32Method' except the boundary check is against 0.
--   UInt8 values are boxed as System.Int32 (how CIntLit emits them), so
--   the unbox is the same. 'bne.un' against a pushed 0 (short form
--   ldc.i4.0) jumps to the ok block when the value is non-zero;
--   otherwise we fall through to the overflow block.
predUInt8Method :: PreludeTags -> Text
predUInt8Method ptags = renderCilMethod (predUInt8Spec (ptUnderflowError ptags) (ptLeft ptags) (ptRight ptags))

-- succInt32: Int32 -> Either OverflowError Int32.
--   Mirror of 'predInt32Method' with INT32_MAX as the boundary and 'add'
--   for the non-overflow branch. OverflowError tag is 0 (single-
--   constructor type), so the Left-branch encoding is identical to the
--   UnderflowError case in predInt32.
succInt32Method :: PreludeTags -> Text
succInt32Method ptags = renderCilMethod (succInt32Spec (ptOverflowError ptags) (ptLeft ptags) (ptRight ptags))

-- succUInt8: UInt8 -> Either OverflowError UInt8.
--   Mirrors 'succInt32Method' except the boundary is 255. 'ldc.i4 255' is
--   used (the short form 'ldc.i4.s' operand is signed byte and would push
--   -1 instead of 255). No mask on (v + 1) — when v <= 254 the result
--   is in 1..255.
succUInt8Method :: PreludeTags -> Text
succUInt8Method ptags = renderCilMethod (succUInt8Spec (ptOverflowError ptags) (ptLeft ptags) (ptRight ptags))

-- eqInt32 / eqUInt8: two integers of the same type → Bool.
--   On the CLR both Int32 and UInt8 values are boxed as Int32 (that's how
--   CIntLit emits them), so the two methods share a single builder
--   parameterised by name and a label suffix. Returns a one-slot object[]
--   with boxed tag 0 (True) on equal, 1 (False) otherwise.
eqMethod :: PreludeTags -> Text -> Text -> Text
eqMethod ptags name lbl = renderCilMethod (eqSpec name lbl (ptTrue ptags) (ptFalse ptags))

-- eqString: String -> String -> Bool. Strings flow as System.String
--   (boxed inside an object reference), so the static
--   'String.op_Equality(string, string) bool' delivers UTF-16 code-unit
--   equality directly. Inputs need 'castclass' rather than 'unbox.any'
--   because reference types aren't boxed value types.
eqStringMethod :: PreludeTags -> Text
eqStringMethod ptags = renderCilMethod (eqStringSpec (ptTrue ptags) (ptFalse ptags))

-- addInt32: Int32 -> Int32 -> Either (UnderflowError | OverflowError) Int32.
--   Signed overflow detected with the XOR trick: '(a ^ sum) & (b ^ sum)'
--   has its sign bit set iff the carry into the sign bit differs from
--   the carry out (= signed overflow). Direction is read off 'a >= 0'
--   so a single 'blt' separates OverflowError (positive overflow) from
--   UnderflowError (negative). Error side wraps three nested Object[]s:
--   inner @CCon@ (single-ctor tag 0), row (FNV-1a tag of label name),
--   outer Left. Avoids 'add.ovf' / try-catch — keeps the method
--   single-block and verifiable.
addInt32Method :: PreludeTags -> Text
addInt32Method ptags = renderCilMethod (addInt32Spec (ptRight ptags) (ptOverflowError ptags) (ptUnderflowError ptags) (ptLeft ptags))

-- addUInt8: UInt8 -> UInt8 -> Either OverflowError UInt8.
--   Both operands are 0..255 so 'add' yields 0..510 in i32 and a single
--   'ble' against 255 selects the branch. No mask on the ok path — the
--   sum is already a valid UInt8 value when the comparison falls through.
addUInt8Method :: PreludeTags -> Text
addUInt8Method ptags = renderCilMethod (addUInt8Spec (ptRight ptags) (ptOverflowError ptags) (ptLeft ptags))

-- subInt32: Int32 -> Int32 -> Either ArithError Int32.
--   XOR-based signed-overflow detection: '(a ^ b) & (a ^ diff)' has its
--   sign bit set iff signed subtraction overflowed. Direction is read
--   off 'a >= 0' — when subtraction overflows the signs of @a@ and @b@
--   must differ, so @a >= 0@ implies @b < 0@ which implies positive
--   overflow. Same single-block, no try/catch shape as 'addInt32Method'.
subInt32Method :: PreludeTags -> Text
subInt32Method ptags = renderCilMethod (subInt32Spec (ptRight ptags) (ptOverflowError ptags) (ptUnderflowError ptags) (ptLeft ptags))

-- mulInt32: Int32 -> Int32 -> Either ArithError Int32.
--   Promote both operands to int64, multiply at long width, range-check
--   the result against [INT32_MIN, INT32_MAX] with @bgt@/@blt@ on long
--   values. Direction (over vs under) is read off the lcmp result —
--   ifgt → Overflow, iflt → Underflow. ArithError tags follow
--   declaration order: Underflow = 0, Overflow = 1.
mulInt32Method :: PreludeTags -> Text
mulInt32Method ptags = renderCilMethod (mulInt32Spec (ptRight ptags) (ptOverflowError ptags) (ptUnderflowError ptags) (ptLeft ptags))

-- negInt32: Int32 -> Either OverflowError Int32.
--   Mirror of 'succInt32Method' with INT32_MIN as the boundary and 'neg'
--   for the non-overflow branch. OverflowError is single-constructor, so
--   its tag is 0 — Left-branch encoding is identical to predInt32.
negInt32Method :: PreludeTags -> Text
negInt32Method ptags = renderCilMethod (negInt32Spec (ptOverflowError ptags) (ptLeft ptags) (ptRight ptags))

-- subUInt8: UInt8 -> UInt8 -> Either UnderflowError UInt8.
--   Both operands are 0..255 so 'sub' yields a value in -255..255 in i32
--   and a single 'blt' against 0 picks the underflow branch. No mask on
--   the ok path — the result is already a valid UInt8 by construction.
subUInt8Method :: PreludeTags -> Text
subUInt8Method ptags = renderCilMethod (subUInt8Spec (ptRight ptags) (ptUnderflowError ptags) (ptLeft ptags))

-- mulUInt8: UInt8 -> UInt8 -> Either OverflowError UInt8.
--   Both operands are 0..255 so 'mul' yields 0..65025 in i32 with no
--   CIL-level overflow; one 'ble' against 255 picks the branch.
--   Same shape as 'addUInt8Method' with 'mul' replacing 'add'.
mulUInt8Method :: PreludeTags -> Text
mulUInt8Method ptags = renderCilMethod (mulUInt8Spec (ptRight ptags) (ptOverflowError ptags) (ptLeft ptags))

-- showUInt32: UInt32 -> String. The Awsum literal lowers to a boxed
--   System.Int32 (same as Int32 / UInt8). Re-box as System.UInt32 (bit
--   pattern preserved) and call the virtual ToString() — UInt32's
--   override prints unsigned-decimal, so values 2^31..2^32-1 don't
--   render as negative.
showUInt32Method :: Text
showUInt32Method = renderCilMethod showUInt32Spec

-- predUInt32: UInt32 -> Either UnderflowError UInt32. The boundary
--   check is also against 0 (same as predUInt8), so the body is
--   structurally identical to 'predUInt8Method' — only the labels
--   differ. (v - 1) wraps modulo 2^32 in i32, but on the ok path
--   v >= 1 so the result is in [0, 2^32-2], no wrap.
predUInt32Method :: PreludeTags -> Text
predUInt32Method ptags = renderCilMethod (predUInt32Spec (ptUnderflowError ptags) (ptLeft ptags) (ptRight ptags))

-- succUInt32: UInt32 -> Either OverflowError UInt32. Boundary 4294967295
--   encoded as 'ldc.i4.m1' (= -1, identical bit pattern when interpreted
--   as u32). On the ok path v + 1 wraps in i32, but since v != -1 the
--   result is in [1, 2^32-1] — no wrap.
succUInt32Method :: PreludeTags -> Text
succUInt32Method ptags = renderCilMethod (succUInt32Spec (ptOverflowError ptags) (ptLeft ptags) (ptRight ptags))

-- addUInt32: UInt32 -> UInt32 -> Either OverflowError UInt32. Promote
--   both operands to uint64 (`conv.u8` zero-extends a u32 bit pattern),
--   add, compare against 4294967295 with `bgt.un` (unsigned greater).
--   The sum lives in [0, 2*2^32-2] so the i64 add doesn't itself
--   overflow.
addUInt32Method :: PreludeTags -> Text
addUInt32Method ptags = renderCilMethod (addUInt32Spec (ptRight ptags) (ptOverflowError ptags) (ptLeft ptags))

-- subUInt32: UInt32 -> UInt32 -> Either UnderflowError UInt32. Compare
--   `a < b` with `blt.un` — unsigned less-than on i32 stack values
--   uses the bit pattern as u32. On the ok path 'sub' at i32 gives the
--   correct u32 difference (bit pattern of a - b mod 2^32 equals a - b
--   when a >= b unsigned).
subUInt32Method :: PreludeTags -> Text
subUInt32Method ptags = renderCilMethod (subUInt32Spec (ptRight ptags) (ptUnderflowError ptags) (ptLeft ptags))

-- mulUInt32: UInt32 -> UInt32 -> Either OverflowError UInt32. Promote
--   both operands to uint64 via 'conv.u8', multiply at int64 stack
--   width (the bit pattern of the result is the low 64 bits of the
--   true u32*u32 product, which fits exactly in u64). Compare against
--   4294967295 with 'bgt.un'.
mulUInt32Method :: PreludeTags -> Text
mulUInt32Method ptags = renderCilMethod (mulUInt32Spec (ptRight ptags) (ptOverflowError ptags) (ptLeft ptags))

-- parseUInt32: String -> Either ParseError UInt32. Same shape as
--   'parseUInt8Method' minus the > 255 cap, with an int64 accumulator
--   and a > 4294967295 cap (max running magnitude is
--   4294967295 * 10 + 9 = 42949672959, fits in i64 signed).
parseUInt32Method :: PreludeTags -> Text
parseUInt32Method ptags = renderCilMethod (parseUInt32Spec (ptRight ptags) (ptParseError ptags) (ptLeft ptags))

-- parseInt32: String -> Either ParseError Int32. Handrolled decimal
--   parser — long accumulator capped at the magnitude `|minInt32|`.
--   Constant `2147483648L` is built with the shift trick `1 << 31`
--   (avoids needing a CPLong-style literal in the binary assembler).
parseInt32Method :: PreludeTags -> Text
parseInt32Method ptags = renderCilMethod (parseInt32Spec (ptRight ptags) (ptParseError ptags) (ptLeft ptags))

-- parseUInt8: String -> Either ParseError UInt8. Same shape as
--   'parseInt32Method' minus the sign handling — UInt8 cannot represent
--   a negative number — and with an i32 accumulator (the running
--   magnitude never exceeds 2559 before the > 255 check fails).
parseUInt8Method :: PreludeTags -> Text
parseUInt8Method ptags = renderCilMethod (parseUInt8Spec (ptRight ptags) (ptParseError ptags) (ptLeft ptags))

-- splitOnFirst: String -> String -> Maybe (Tuple2 String String).
--   Defers substring search to 'String.IndexOf(string, Ordinal)' —
--   culture-sensitive (the no-StringComparison overload's default) goes
--   through ICU's UCA on .NET-on-Unix and silently misses substrings
--   that *are* physically present when the haystack contains
--   supplementary-plane code points. Ordinal compares UTF-16 code units
--   directly, matching what every other backend does (byte/code-unit
--   scan) — so cross-backend equivalence holds. Returns -1 on miss and
--   0 on empty 'sep'; both match the prelude contract directly. On hit,
--   'String.Substring' allocates fresh strings (CLR strings are
--   immutable; substrings are owning copies, not aliases). Containers:
--   Maybe Nothing=0, Just=1; Tuple2 has one constructor (tag 0).
splitOnFirstMethod :: PreludeTags -> Text
splitOnFirstMethod ptags = renderCilMethod (splitOnFirstSpec (ptNothing ptags) (ptTuple2 ptags) (ptJust ptags))

-- lengthCodePoints: String -> UInt32. UTF-32 byte count divided by 4
--   gives the code-point count exactly — every Unicode scalar is one
--   four-byte UTF-32 unit, surrogate pairs collapse to a single unit.
--   Cleaner than walking the string and pairing surrogates by hand.
lengthCodePointsMethod :: Text
lengthCodePointsMethod = renderCilMethod lengthCodePointsSpec

-- lengthUtf16CodeUnits: String -> UInt32. .NET strings are UTF-16
--   internally so 'String.Length' is the code-unit count by definition.
lengthUtf16CodeUnitsMethod :: Text
lengthUtf16CodeUnitsMethod = renderCilMethod lengthUtf16CodeUnitsSpec

-- lengthUtf8Bytes: String -> UInt32. 'Encoding.UTF8.GetByteCount(s)'
--   returns the standard UTF-8 byte count without materialising the
--   bytes themselves.
lengthUtf8BytesMethod :: Text
lengthUtf8BytesMethod = renderCilMethod lengthUtf8BytesSpec

-- | __getArgs: zero-arg helper for 'BuiltIn.internalGetArgs'. Reads
--   the 'args' array stashed in '__argv' by 'Main' and builds a
--   prelude 'List String' on demand. Each element routes through
--   '__entryArgEither' for strict-UTF-16 validation; the error
--   semantics is all-or-nothing — the first failing element
--   short-circuits with its 'Left'. Walked right-to-left so the
--   cons chain is built bottom-up without recursion.
--
--   Locals: 0 = argv (string[]), 1 = i (int32), 2 = list (object[]),
--   3 = validated (object[]).
getArgsMethod :: PreludeTags -> Text
getArgsMethod ptags = renderCilMethod (getArgsSpec (ptRight ptags) (ptNil ptags) (ptCons ptags))

-- | __stdinReadAll: zero-arg helper for
--   'BuiltIn.internalStdinReadAllAsUtf16', called from 'runIO''s
--   'IOStdinReadAll' arm. Reads 'Console.OpenStandardInput()' through a
--   'StreamReader' wired to an explicit UTF-8 'Encoding', then routes
--   the resulting 'string' through '__entryArgEither' for the
--   strict-UTF-16 validation 'getArgs' uses.
--
--   The explicit UTF-8 'Encoding' avoids depending on
--   'Console.InputEncoding', whose default on Windows is the legacy
--   OEM code page — the same class of host-encoding bug that broke
--   'IO.Args.getArgs' for supplementary-plane characters. 'StreamReader'
--   over 'OpenStandardInput' reads raw bytes from fd 0 unaffected by
--   the console-input knob.
stdinReadAllMethod :: Text
stdinReadAllMethod = renderCilMethod stdinReadAllSpec

-- | __entryArgEither: wraps argv[1] in 'Either (StringTooLong | …) String'
--   for the user's 'main'. 'System.String::get_Length' returns UTF-16
--   code units (CLR strings are UTF-16 natively), so the cap check is a
--   single i32 comparison. Returns 'Right input' on fit, three-layer
--   row-tagged 'Left StringTooLong' on overflow.
--
--   Cap value (134217728 = 2^27) and the FNV-1a row tag for
--   "StringTooLong" must stay in sync with 'maxStringLengthUtf16CodeUnits'
--   in 'stdlib/Prelude.aww'.
entryArgEitherMethod :: PreludeTags -> Text
entryArgEitherMethod ptags = renderCilMethod (entryArgEitherSpec (ptRight ptags) (ptStringTooLong ptags) (ptUnpairedUtf16Surrogate ptags) (ptLeft ptags))

mainMethod :: Text
mainMethod = renderCilMethod mainSpec
