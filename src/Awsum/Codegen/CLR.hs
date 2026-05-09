-- | CLR textual CIL assembler for Awsum 'Core'.
--
-- Produces a human-readable ilasm-like text representation of the
-- CIL bytecode that 'Awsum.Codegen.CLR.Assemble' generates as binary.
-- Used for @awsum asm -t clr@ output and snapshot tests.
module Awsum.Codegen.CLR (codegenCLR) where

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

-- | Produce a textual CIL assembly from a Core program.
codegenCLR :: PreludeTags -> CoreProgram -> Text
codegenCLR ptags prog@(CoreProgram decls) =
  let valNames = Set.fromList [n | CValDef n _ <- decls]
      funNames = Set.fromList [n | CFunDef n _ _ <- decls]
      arities = Map.fromList [(n, length as) | CFunDef n as _ <- decls]
      ctx = Ctx {cValDefs = valNames, cFunDefs = funNames, cArities = arities}
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
            T.intercalate "\n\n" (map (emitDecl ctx) decls),
            "",
            gate (Set.member "internalGetArgs" builtIns) (entryArgEitherMethod ptags),
            "",
            gate (Set.member "internalGetArgs" builtIns) getArgsMethod,
            "",
            mainMethod,
            "",
            classClose,
            ""
          ]

-- ════════════════════════════════════════════════════════════════════════════
-- Context
-- ════════════════════════════════════════════════════════════════════════════

data Ctx = Ctx
  { cValDefs :: Set Text,
    cFunDefs :: Set Text,
    cArities :: Map Text Int
  }

-- | Emit the CIL instruction for "push integer N onto the eval stack".
-- Picks the tightest encoding the CIL offers: 'ldc.i4.<N>' for [0, 8],
-- 'ldc.i4.m1' for -1, 'ldc.i4.s <byte>' for one-byte signed,
-- otherwise full 'ldc.i4 <int32>'.
pushIntInsn :: Int -> Text
pushIntInsn n
  | n >= 0 && n <= 8 = "    ldc.i4." <> show n
  | n == -1 = "    ldc.i4.m1"
  | n >= -128 && n <= 127 = "    ldc.i4.s " <> show n
  | otherwise = "    ldc.i4 " <> show n

-- | Lines for "push tag @n@, then box it as @System.Int32@". Used
-- every time a constructor tag is stored into an @object[]@ slot at
-- the call site that builds a CCon-shaped value.
boxedTagLines :: Int -> [Text]
boxedTagLines n =
  [ pushIntInsn n,
    "    box [System.Runtime]System.Int32"
  ]

-- | Lines that build @object[1] = [box(tag)]@ (a nullary 'CCon')
-- and leave it on the stack.
makeNullaryCellLines :: Int -> [Text]
makeNullaryCellLines tag =
  [ "    ldc.i4.1",
    "    newarr [System.Runtime]System.Object",
    "    dup",
    "    ldc.i4.0"
  ]
    <> boxedTagLines tag
    <> ["    stelem.ref"]

-- | Lines that build @object[2] = [box(tag), <value loaded by ldlocInsn>]@
-- (a one-field 'CCon') and leave it on the stack. @ldlocInsn@ is the
-- raw line emitting the load — typically @"    ldloc.<n>"@.
makeUnaryCellFromLocalLines :: Int -> Text -> [Text]
makeUnaryCellFromLocalLines tag ldlocInsn =
  [ "    ldc.i4.2",
    "    newarr [System.Runtime]System.Object",
    "    dup",
    "    ldc.i4.0"
  ]
    <> boxedTagLines tag
    <> [ "    stelem.ref",
         "    dup",
         "    ldc.i4.1",
         ldlocInsn,
         "    stelem.ref"
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
concatMethod ptags =
  T.intercalate "\n"
    $ [ "  .method private hidebysig static object __concat(object, object) cil managed",
        "  {",
        "    .maxstack 5",
        "    .locals init (object V_0)",
        -- UTF-16 length of arg 0 (widened to i8).
        "    ldarg.0",
        "    castclass [System.Runtime]System.String",
        "    callvirt instance int32 [System.Runtime]System.String::get_Length()",
        "    conv.i8",
        -- UTF-16 length of arg 1 (widened to i8).
        "    ldarg.1",
        "    castclass [System.Runtime]System.String",
        "    callvirt instance int32 [System.Runtime]System.String::get_Length()",
        "    conv.i8",
        "    add",
        -- maxStringLengthUtf16CodeUnits = 134217728 (= 2^27).
        -- Keep in sync with 'maxStringLengthUtf16CodeUnits' in
        -- 'stdlib/Prelude.aww'.
        "    ldc.i8 134217728",
        "    bgt.un IL_concat_too_long",
        -- Length OK: do String.Concat and wrap in Right.
        "    ldarg.0",
        "    ldarg.1",
        "    call string [System.Runtime]System.String::Concat(object, object)",
        "    stloc.0",
        -- Build Right(result): object[2] = [box(rightTag), result]
        "    ldc.i4.2",
        "    newarr [System.Runtime]System.Object",
        "    dup",
        "    ldc.i4.0"
      ]
    <> boxedTagLines (ptRight ptags)
    <> [ "    stelem.ref",
         "    dup",
         "    ldc.i4.1",
         "    ldloc.0",
         "    stelem.ref",
         "    ret",
         "  IL_concat_too_long:"
       ]
    -- Inner StringTooLong CCon, then wrap in Left.
    <> makeNullaryCellLines (ptStringTooLong ptags)
    <> ["    stloc.0"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "    ldloc.0"
    <> [ "    ret",
         "  }",
         ""
       ]

-- | __print: low-level platform primitive driven by the prelude's
--   `runIO` via `BuiltIn.internalStdoutPrint`. Returns a Unit value
--   (object[1] = [boxed Int32 0]) so the surrounding `case … of Unit
--   -> next` arm in `runIO` dispatches through the standard CCase
--   tag check.
printMethod :: PreludeTags -> Text
printMethod ptags =
  T.intercalate "\n"
    $ [ "  .method private hidebysig static object __print(object) cil managed",
        "  {",
        "    .maxstack 4",
        "    ldarg.0",
        "    call void [System.Console]System.Console::Write(object)"
      ]
    <> makeNullaryCellLines (ptUnit ptags)
    <> [ "    ret",
         "  }",
         ""
       ]

-- predInt32: Int32 -> Either UnderflowError Int32.
--   Containers are object[] (newarr) with boxed Int32 tag at [0] and
--   fields at [1..], matching user CCon emission on the CLR. Tags:
--   Left=0, Right=1, UnderflowError=0.
predInt32Method :: PreludeTags -> Text
predInt32Method ptags =
  T.intercalate "\n"
    $ [ "  .method private hidebysig static object __predInt32(object) cil managed",
        "  {",
        "    .maxstack 5",
        "    .locals init (int32 V_0, object V_1)",
        "    ldarg.0",
        "    unbox.any [System.Runtime]System.Int32",
        "    stloc.0",
        "    ldloc.0",
        "    ldc.i4 -2147483648",
        "    bne.un.s IL_pred_ok"
      ]
    <> makeNullaryCellLines (ptUnderflowError ptags)
    <> ["    stloc.1"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "    ldloc.1"
    <> [ "    ret",
         "  IL_pred_ok:",
         "    ldc.i4.2",
         "    newarr [System.Runtime]System.Object",
         "    dup",
         "    ldc.i4.0"
       ]
    <> boxedTagLines (ptRight ptags)
    <> [ "    stelem.ref",
         "    dup",
         "    ldc.i4.1",
         "    ldloc.0",
         "    ldc.i4.1",
         "    sub",
         "    box [System.Runtime]System.Int32",
         "    stelem.ref",
         "    ret",
         "  }",
         ""
       ]

-- predUInt8: UInt8 -> Either UnderflowError UInt8.
--   Mirrors 'predInt32Method' except the boundary check is against 0.
--   UInt8 values are boxed as System.Int32 (how CIntLit emits them), so
--   the unbox is the same. 'bne.un.s' against a pushed 0 (short form
--   ldc.i4.0) jumps to the ok block when the value is non-zero;
--   otherwise we fall through to the overflow block.
predUInt8Method :: PreludeTags -> Text
predUInt8Method ptags =
  T.intercalate "\n"
    $ [ "  .method private hidebysig static object __predUInt8(object) cil managed",
        "  {",
        "    .maxstack 5",
        "    .locals init (int32 V_0, object V_1)",
        "    ldarg.0",
        "    unbox.any [System.Runtime]System.Int32",
        "    stloc.0",
        "    ldloc.0",
        "    ldc.i4.0",
        "    bne.un.s IL_predu8_ok"
      ]
    <> makeNullaryCellLines (ptUnderflowError ptags)
    <> ["    stloc.1"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "    ldloc.1"
    <> [ "    ret",
         "  IL_predu8_ok:",
         "    ldc.i4.2",
         "    newarr [System.Runtime]System.Object",
         "    dup",
         "    ldc.i4.0"
       ]
    <> boxedTagLines (ptRight ptags)
    <> [ "    stelem.ref",
         "    dup",
         "    ldc.i4.1",
         "    ldloc.0",
         "    ldc.i4.1",
         "    sub",
         "    box [System.Runtime]System.Int32",
         "    stelem.ref",
         "    ret",
         "  }",
         ""
       ]

-- succInt32: Int32 -> Either OverflowError Int32.
--   Mirror of 'predInt32Method' with INT32_MAX as the boundary and 'add'
--   for the non-overflow branch. OverflowError tag is 0 (single-
--   constructor type), so the Left-branch encoding is identical to the
--   UnderflowError case in predInt32.
succInt32Method :: PreludeTags -> Text
succInt32Method ptags =
  T.intercalate "\n"
    $ [ "  .method private hidebysig static object __succInt32(object) cil managed",
        "  {",
        "    .maxstack 5",
        "    .locals init (int32 V_0, object V_1)",
        "    ldarg.0",
        "    unbox.any [System.Runtime]System.Int32",
        "    stloc.0",
        "    ldloc.0",
        "    ldc.i4 2147483647",
        "    bne.un.s IL_succ_ok"
      ]
    <> makeNullaryCellLines (ptOverflowError ptags)
    <> ["    stloc.1"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "    ldloc.1"
    <> [ "    ret",
         "  IL_succ_ok:",
         "    ldc.i4.2",
         "    newarr [System.Runtime]System.Object",
         "    dup",
         "    ldc.i4.0"
       ]
    <> boxedTagLines (ptRight ptags)
    <> [ "    stelem.ref",
         "    dup",
         "    ldc.i4.1",
         "    ldloc.0",
         "    ldc.i4.1",
         "    add",
         "    box [System.Runtime]System.Int32",
         "    stelem.ref",
         "    ret",
         "  }",
         ""
       ]

-- succUInt8: UInt8 -> Either OverflowError UInt8.
--   Mirrors 'succInt32Method' except the boundary is 255. 'ldc.i4 255' is
--   used (the short form 'ldc.i4.s' operand is signed byte and would push
--   -1 instead of 255). No mask on (v + 1) — when v <= 254 the result
--   is in 1..255.
succUInt8Method :: PreludeTags -> Text
succUInt8Method ptags =
  T.intercalate "\n"
    $ [ "  .method private hidebysig static object __succUInt8(object) cil managed",
        "  {",
        "    .maxstack 5",
        "    .locals init (int32 V_0, object V_1)",
        "    ldarg.0",
        "    unbox.any [System.Runtime]System.Int32",
        "    stloc.0",
        "    ldloc.0",
        "    ldc.i4 255",
        "    bne.un.s IL_succu8_ok"
      ]
    <> makeNullaryCellLines (ptOverflowError ptags)
    <> ["    stloc.1"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "    ldloc.1"
    <> [ "    ret",
         "  IL_succu8_ok:",
         "    ldc.i4.2",
         "    newarr [System.Runtime]System.Object",
         "    dup",
         "    ldc.i4.0"
       ]
    <> boxedTagLines (ptRight ptags)
    <> [ "    stelem.ref",
         "    dup",
         "    ldc.i4.1",
         "    ldloc.0",
         "    ldc.i4.1",
         "    add",
         "    box [System.Runtime]System.Int32",
         "    stelem.ref",
         "    ret",
         "  }",
         ""
       ]

-- eqInt32 / eqUInt8: two integers of the same type → Bool.
--   On the CLR both Int32 and UInt8 values are boxed as Int32 (that's how
--   CIntLit emits them), so the two methods share a single builder
--   parameterised by name and a label suffix. Returns a one-slot object[]
--   with boxed tag 0 (True) on equal, 1 (False) otherwise.
eqMethod :: PreludeTags -> Text -> Text -> Text
eqMethod ptags name lbl =
  T.intercalate "\n"
    $ [ "  .method private hidebysig static object " <> name <> "(object, object) cil managed",
        "  {",
        "    .maxstack 5",
        "    ldarg.0",
        "    unbox.any [System.Runtime]System.Int32",
        "    ldarg.1",
        "    unbox.any [System.Runtime]System.Int32",
        "    bne.un.s " <> lbl <> "_ne"
      ]
    <> makeNullaryCellLines (ptTrue ptags)
    <> [ "    ret",
         "  " <> lbl <> "_ne:"
       ]
    <> makeNullaryCellLines (ptFalse ptags)
    <> [ "    ret",
         "  }",
         ""
       ]

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
addInt32Method ptags =
  T.intercalate "\n"
    $ [ "  .method private hidebysig static object __addInt32(object, object) cil managed",
        "  {",
        "    .maxstack 4",
        "    .locals init (int32 V_0, int32 V_1, int32 V_2, object V_3)",
        "    ldarg.0",
        "    unbox.any [System.Runtime]System.Int32",
        "    stloc.0",
        "    ldarg.1",
        "    unbox.any [System.Runtime]System.Int32",
        "    stloc.1",
        "    ldloc.0",
        "    ldloc.1",
        "    add",
        "    stloc.2",
        "    ldloc.0",
        "    ldloc.2",
        "    xor",
        "    ldloc.1",
        "    ldloc.2",
        "    xor",
        "    and",
        "    ldc.i4.0",
        "    blt.s IL_addi32_over",
        "    ldc.i4.2",
        "    newarr [System.Runtime]System.Object",
        "    dup",
        "    ldc.i4.0"
      ]
    <> boxedTagLines (ptRight ptags)
    <> [ "    stelem.ref",
         "    dup",
         "    ldc.i4.1",
         "    ldloc.2",
         "    box [System.Runtime]System.Int32",
         "    stelem.ref",
         "    ret",
         "  IL_addi32_over:",
         "    ldloc.0",
         "    ldc.i4.0",
         "    blt.s IL_addi32_under"
       ]
    <> makeNullaryCellLines (ptOverflowError ptags)
    <> ["    stloc.3"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "    ldloc.3"
    <> [ "    ret",
         "  IL_addi32_under:"
       ]
    <> makeNullaryCellLines (ptUnderflowError ptags)
    <> ["    stloc.3"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "    ldloc.3"
    <> [ "    ret",
         "  }",
         ""
       ]

-- addUInt8: UInt8 -> UInt8 -> Either OverflowError UInt8.
--   Both operands are 0..255 so 'add' yields 0..510 in i32 and a single
--   'ble' against 255 selects the branch. No mask on the ok path — the
--   sum is already a valid UInt8 value when the comparison falls through.
addUInt8Method :: PreludeTags -> Text
addUInt8Method ptags =
  T.intercalate "\n"
    $ [ "  .method private hidebysig static object __addUInt8(object, object) cil managed",
        "  {",
        "    .maxstack 4",
        "    .locals init (int32 V_0, object V_1)",
        "    ldarg.0",
        "    unbox.any [System.Runtime]System.Int32",
        "    ldarg.1",
        "    unbox.any [System.Runtime]System.Int32",
        "    add",
        "    stloc.0",
        "    ldloc.0",
        "    ldc.i4 255",
        "    ble.s IL_addu8_ok"
      ]
    <> makeNullaryCellLines (ptOverflowError ptags)
    <> ["    stloc.1"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "    ldloc.1"
    <> [ "    ret",
         "  IL_addu8_ok:",
         "    ldc.i4.2",
         "    newarr [System.Runtime]System.Object",
         "    dup",
         "    ldc.i4.0"
       ]
    <> boxedTagLines (ptRight ptags)
    <> [ "    stelem.ref",
         "    dup",
         "    ldc.i4.1",
         "    ldloc.0",
         "    box [System.Runtime]System.Int32",
         "    stelem.ref",
         "    ret",
         "  }",
         ""
       ]

-- subInt32: Int32 -> Int32 -> Either ArithError Int32.
--   XOR-based signed-overflow detection: '(a ^ b) & (a ^ diff)' has its
--   sign bit set iff signed subtraction overflowed. Direction is read
--   off 'a >= 0' — when subtraction overflows the signs of @a@ and @b@
--   must differ, so @a >= 0@ implies @b < 0@ which implies positive
--   overflow. Same single-block, no try/catch shape as 'addInt32Method'.
subInt32Method :: PreludeTags -> Text
subInt32Method ptags =
  T.intercalate "\n"
    $ [ "  .method private hidebysig static object __subInt32(object, object) cil managed",
        "  {",
        "    .maxstack 4",
        "    .locals init (int32 V_0, int32 V_1, int32 V_2, object V_3)",
        "    ldarg.0",
        "    unbox.any [System.Runtime]System.Int32",
        "    stloc.0",
        "    ldarg.1",
        "    unbox.any [System.Runtime]System.Int32",
        "    stloc.1",
        "    ldloc.0",
        "    ldloc.1",
        "    sub",
        "    stloc.2",
        "    ldloc.0",
        "    ldloc.1",
        "    xor",
        "    ldloc.0",
        "    ldloc.2",
        "    xor",
        "    and",
        "    ldc.i4.0",
        "    blt.s IL_subi32_over",
        "    ldc.i4.2",
        "    newarr [System.Runtime]System.Object",
        "    dup",
        "    ldc.i4.0"
      ]
    <> boxedTagLines (ptRight ptags)
    <> [ "    stelem.ref",
         "    dup",
         "    ldc.i4.1",
         "    ldloc.2",
         "    box [System.Runtime]System.Int32",
         "    stelem.ref",
         "    ret",
         "  IL_subi32_over:",
         "    ldloc.0",
         "    ldc.i4.0",
         "    blt.s IL_subi32_under"
       ]
    <> makeNullaryCellLines (ptOverflowError ptags)
    <> ["    stloc.3"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "    ldloc.3"
    <> [ "    ret",
         "  IL_subi32_under:"
       ]
    <> makeNullaryCellLines (ptUnderflowError ptags)
    <> ["    stloc.3"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "    ldloc.3"
    <> [ "    ret",
         "  }",
         ""
       ]

-- mulInt32: Int32 -> Int32 -> Either ArithError Int32.
--   Promote both operands to int64, multiply at long width, range-check
--   the result against [INT32_MIN, INT32_MAX] with @bgt@/@blt@ on long
--   values. Direction (over vs under) is read off the lcmp result —
--   ifgt → Overflow, iflt → Underflow. ArithError tags follow
--   declaration order: Underflow = 0, Overflow = 1.
mulInt32Method :: PreludeTags -> Text
mulInt32Method ptags =
  T.intercalate "\n"
    $ [ "  .method private hidebysig static object __mulInt32(object, object) cil managed",
        "  {",
        "    .maxstack 5",
        "    .locals init (int32 V_0, int32 V_1, int64 V_2, object V_3)",
        "    ldarg.0",
        "    unbox.any [System.Runtime]System.Int32",
        "    stloc.0",
        "    ldarg.1",
        "    unbox.any [System.Runtime]System.Int32",
        "    stloc.1",
        "    ldloc.0",
        "    conv.i8",
        "    ldloc.1",
        "    conv.i8",
        "    mul",
        "    stloc.2",
        "    ldloc.2",
        "    ldc.i4 2147483647",
        "    conv.i8",
        "    bgt IL_muli32_over",
        "    ldloc.2",
        "    ldc.i4 -2147483648",
        "    conv.i8",
        "    blt IL_muli32_under",
        "    ldc.i4.2",
        "    newarr [System.Runtime]System.Object",
        "    dup",
        "    ldc.i4.0"
      ]
    <> boxedTagLines (ptRight ptags)
    <> [ "    stelem.ref",
         "    dup",
         "    ldc.i4.1",
         "    ldloc.2",
         "    conv.i4",
         "    box [System.Runtime]System.Int32",
         "    stelem.ref",
         "    ret",
         "  IL_muli32_over:"
       ]
    <> makeNullaryCellLines (ptOverflowError ptags)
    <> ["    stloc.3"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "    ldloc.3"
    <> [ "    ret",
         "  IL_muli32_under:"
       ]
    <> makeNullaryCellLines (ptUnderflowError ptags)
    <> ["    stloc.3"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "    ldloc.3"
    <> [ "    ret",
         "  }",
         ""
       ]

-- negInt32: Int32 -> Either OverflowError Int32.
--   Mirror of 'succInt32Method' with INT32_MIN as the boundary and 'neg'
--   for the non-overflow branch. OverflowError is single-constructor, so
--   its tag is 0 — Left-branch encoding is identical to predInt32.
negInt32Method :: PreludeTags -> Text
negInt32Method ptags =
  T.intercalate "\n"
    $ [ "  .method private hidebysig static object __negInt32(object) cil managed",
        "  {",
        "    .maxstack 5",
        "    .locals init (int32 V_0, object V_1)",
        "    ldarg.0",
        "    unbox.any [System.Runtime]System.Int32",
        "    stloc.0",
        "    ldloc.0",
        "    ldc.i4 -2147483648",
        "    bne.un.s IL_neg_ok"
      ]
    <> makeNullaryCellLines (ptOverflowError ptags)
    <> ["    stloc.1"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "    ldloc.1"
    <> [ "    ret",
         "  IL_neg_ok:",
         "    ldc.i4.2",
         "    newarr [System.Runtime]System.Object",
         "    dup",
         "    ldc.i4.0"
       ]
    <> boxedTagLines (ptRight ptags)
    <> [ "    stelem.ref",
         "    dup",
         "    ldc.i4.1",
         "    ldloc.0",
         "    neg",
         "    box [System.Runtime]System.Int32",
         "    stelem.ref",
         "    ret",
         "  }",
         ""
       ]

-- subUInt8: UInt8 -> UInt8 -> Either UnderflowError UInt8.
--   Both operands are 0..255 so 'sub' yields a value in -255..255 in i32
--   and a single 'blt' against 0 picks the underflow branch. No mask on
--   the ok path — the result is already a valid UInt8 by construction.
subUInt8Method :: PreludeTags -> Text
subUInt8Method ptags =
  T.intercalate "\n"
    $ [ "  .method private hidebysig static object __subUInt8(object, object) cil managed",
        "  {",
        "    .maxstack 4",
        "    .locals init (int32 V_0, object V_1)",
        "    ldarg.0",
        "    unbox.any [System.Runtime]System.Int32",
        "    ldarg.1",
        "    unbox.any [System.Runtime]System.Int32",
        "    sub",
        "    stloc.0",
        "    ldloc.0",
        "    ldc.i4.0",
        "    blt.s IL_subu8_under",
        "    ldc.i4.2",
        "    newarr [System.Runtime]System.Object",
        "    dup",
        "    ldc.i4.0"
      ]
    <> boxedTagLines (ptRight ptags)
    <> [ "    stelem.ref",
         "    dup",
         "    ldc.i4.1",
         "    ldloc.0",
         "    box [System.Runtime]System.Int32",
         "    stelem.ref",
         "    ret",
         "  IL_subu8_under:"
       ]
    <> makeNullaryCellLines (ptUnderflowError ptags)
    <> ["    stloc.1"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "    ldloc.1"
    <> [ "    ret",
         "  }",
         ""
       ]

-- mulUInt8: UInt8 -> UInt8 -> Either OverflowError UInt8.
--   Both operands are 0..255 so 'mul' yields 0..65025 in i32 with no
--   CIL-level overflow; one 'ble.s' against 255 picks the branch.
--   Same shape as 'addUInt8Method' with 'mul' replacing 'add'.
mulUInt8Method :: PreludeTags -> Text
mulUInt8Method ptags =
  T.intercalate "\n"
    $ [ "  .method private hidebysig static object __mulUInt8(object, object) cil managed",
        "  {",
        "    .maxstack 4",
        "    .locals init (int32 V_0, object V_1)",
        "    ldarg.0",
        "    unbox.any [System.Runtime]System.Int32",
        "    ldarg.1",
        "    unbox.any [System.Runtime]System.Int32",
        "    mul",
        "    stloc.0",
        "    ldloc.0",
        "    ldc.i4 255",
        "    ble.s IL_mulu8_ok"
      ]
    <> makeNullaryCellLines (ptOverflowError ptags)
    <> ["    stloc.1"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "    ldloc.1"
    <> [ "    ret",
         "  IL_mulu8_ok:",
         "    ldc.i4.2",
         "    newarr [System.Runtime]System.Object",
         "    dup",
         "    ldc.i4.0"
       ]
    <> boxedTagLines (ptRight ptags)
    <> [ "    stelem.ref",
         "    dup",
         "    ldc.i4.1",
         "    ldloc.0",
         "    box [System.Runtime]System.Int32",
         "    stelem.ref",
         "    ret",
         "  }",
         ""
       ]

-- showUInt32: UInt32 -> String. The Awsum literal lowers to a boxed
--   System.Int32 (same as Int32 / UInt8). Re-box as System.UInt32 (bit
--   pattern preserved) and call the virtual ToString() — UInt32's
--   override prints unsigned-decimal, so values 2^31..2^32-1 don't
--   render as negative.
showUInt32Method :: Text
showUInt32Method =
  unlines
    [ "  .method private hidebysig static object __showUInt32(object) cil managed",
      "  {",
      "    .maxstack 4",
      "    ldarg.0",
      "    unbox.any [System.Runtime]System.Int32",
      "    box [System.Runtime]System.UInt32",
      "    callvirt instance string [System.Runtime]System.Object::ToString()",
      "    ret",
      "  }"
    ]

-- predUInt32: UInt32 -> Either UnderflowError UInt32. The boundary
--   check is also against 0 (same as predUInt8), so the body is
--   structurally identical to 'predUInt8Method' — only the labels
--   differ. (v - 1) wraps modulo 2^32 in i32, but on the ok path
--   v >= 1 so the result is in [0, 2^32-2], no wrap.
predUInt32Method :: PreludeTags -> Text
predUInt32Method ptags =
  T.intercalate "\n"
    $ [ "  .method private hidebysig static object __predUInt32(object) cil managed",
        "  {",
        "    .maxstack 5",
        "    .locals init (int32 V_0, object V_1)",
        "    ldarg.0",
        "    unbox.any [System.Runtime]System.Int32",
        "    stloc.0",
        "    ldloc.0",
        "    ldc.i4.0",
        "    bne.un.s IL_predu32_ok"
      ]
    <> makeNullaryCellLines (ptUnderflowError ptags)
    <> ["    stloc.1"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "    ldloc.1"
    <> [ "    ret",
         "  IL_predu32_ok:",
         "    ldc.i4.2",
         "    newarr [System.Runtime]System.Object",
         "    dup",
         "    ldc.i4.0"
       ]
    <> boxedTagLines (ptRight ptags)
    <> [ "    stelem.ref",
         "    dup",
         "    ldc.i4.1",
         "    ldloc.0",
         "    ldc.i4.1",
         "    sub",
         "    box [System.Runtime]System.Int32",
         "    stelem.ref",
         "    ret",
         "  }",
         ""
       ]

-- succUInt32: UInt32 -> Either OverflowError UInt32. Boundary 4294967295
--   encoded as 'ldc.i4.m1' (= -1, identical bit pattern when interpreted
--   as u32). On the ok path v + 1 wraps in i32, but since v != -1 the
--   result is in [1, 2^32-1] — no wrap.
succUInt32Method :: PreludeTags -> Text
succUInt32Method ptags =
  T.intercalate "\n"
    $ [ "  .method private hidebysig static object __succUInt32(object) cil managed",
        "  {",
        "    .maxstack 5",
        "    .locals init (int32 V_0, object V_1)",
        "    ldarg.0",
        "    unbox.any [System.Runtime]System.Int32",
        "    stloc.0",
        "    ldloc.0",
        "    ldc.i4.m1",
        "    bne.un.s IL_succu32_ok"
      ]
    <> makeNullaryCellLines (ptOverflowError ptags)
    <> ["    stloc.1"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "    ldloc.1"
    <> [ "    ret",
         "  IL_succu32_ok:",
         "    ldc.i4.2",
         "    newarr [System.Runtime]System.Object",
         "    dup",
         "    ldc.i4.0"
       ]
    <> boxedTagLines (ptRight ptags)
    <> [ "    stelem.ref",
         "    dup",
         "    ldc.i4.1",
         "    ldloc.0",
         "    ldc.i4.1",
         "    add",
         "    box [System.Runtime]System.Int32",
         "    stelem.ref",
         "    ret",
         "  }",
         ""
       ]

-- addUInt32: UInt32 -> UInt32 -> Either OverflowError UInt32. Promote
--   both operands to uint64 (`conv.u8` zero-extends a u32 bit pattern),
--   add, compare against 4294967295 with `bgt.un` (unsigned greater).
--   The sum lives in [0, 2*2^32-2] so the i64 add doesn't itself
--   overflow.
addUInt32Method :: PreludeTags -> Text
addUInt32Method ptags =
  T.intercalate "\n"
    $ [ "  .method private hidebysig static object __addUInt32(object, object) cil managed",
        "  {",
        "    .maxstack 5",
        "    .locals init (int64 V_0, object V_1)",
        "    ldarg.0",
        "    unbox.any [System.Runtime]System.Int32",
        "    conv.u8",
        "    ldarg.1",
        "    unbox.any [System.Runtime]System.Int32",
        "    conv.u8",
        "    add",
        "    stloc.0",
        "    ldloc.0",
        "    ldc.i8 4294967295",
        "    bgt.un.s IL_addu32_over",
        "    ldc.i4.2",
        "    newarr [System.Runtime]System.Object",
        "    dup",
        "    ldc.i4.0"
      ]
    <> boxedTagLines (ptRight ptags)
    <> [ "    stelem.ref",
         "    dup",
         "    ldc.i4.1",
         "    ldloc.0",
         "    conv.u4",
         "    box [System.Runtime]System.Int32",
         "    stelem.ref",
         "    ret",
         "  IL_addu32_over:"
       ]
    <> makeNullaryCellLines (ptOverflowError ptags)
    <> ["    stloc.1"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "    ldloc.1"
    <> [ "    ret",
         "  }",
         ""
       ]

-- subUInt32: UInt32 -> UInt32 -> Either UnderflowError UInt32. Compare
--   `a < b` with `blt.un.s` — unsigned less-than on i32 stack values
--   uses the bit pattern as u32. On the ok path 'sub' at i32 gives the
--   correct u32 difference (bit pattern of a - b mod 2^32 equals a - b
--   when a >= b unsigned).
subUInt32Method :: PreludeTags -> Text
subUInt32Method ptags =
  T.intercalate "\n"
    $ [ "  .method private hidebysig static object __subUInt32(object, object) cil managed",
        "  {",
        "    .maxstack 4",
        "    .locals init (int32 V_0, int32 V_1, object V_2)",
        "    ldarg.0",
        "    unbox.any [System.Runtime]System.Int32",
        "    stloc.0",
        "    ldarg.1",
        "    unbox.any [System.Runtime]System.Int32",
        "    stloc.1",
        "    ldloc.0",
        "    ldloc.1",
        "    blt.un.s IL_subu32_under",
        "    ldc.i4.2",
        "    newarr [System.Runtime]System.Object",
        "    dup",
        "    ldc.i4.0"
      ]
    <> boxedTagLines (ptRight ptags)
    <> [ "    stelem.ref",
         "    dup",
         "    ldc.i4.1",
         "    ldloc.0",
         "    ldloc.1",
         "    sub",
         "    box [System.Runtime]System.Int32",
         "    stelem.ref",
         "    ret",
         "  IL_subu32_under:"
       ]
    <> makeNullaryCellLines (ptUnderflowError ptags)
    <> ["    stloc.2"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "    ldloc.2"
    <> [ "    ret",
         "  }",
         ""
       ]

-- mulUInt32: UInt32 -> UInt32 -> Either OverflowError UInt32. Promote
--   both operands to uint64 via 'conv.u8', multiply at int64 stack
--   width (the bit pattern of the result is the low 64 bits of the
--   true u32*u32 product, which fits exactly in u64). Compare against
--   4294967295 with 'bgt.un'.
mulUInt32Method :: PreludeTags -> Text
mulUInt32Method ptags =
  T.intercalate "\n"
    $ [ "  .method private hidebysig static object __mulUInt32(object, object) cil managed",
        "  {",
        "    .maxstack 5",
        "    .locals init (int64 V_0, object V_1)",
        "    ldarg.0",
        "    unbox.any [System.Runtime]System.Int32",
        "    conv.u8",
        "    ldarg.1",
        "    unbox.any [System.Runtime]System.Int32",
        "    conv.u8",
        "    mul",
        "    stloc.0",
        "    ldloc.0",
        "    ldc.i8 4294967295",
        "    bgt.un.s IL_mulu32_over",
        "    ldc.i4.2",
        "    newarr [System.Runtime]System.Object",
        "    dup",
        "    ldc.i4.0"
      ]
    <> boxedTagLines (ptRight ptags)
    <> [ "    stelem.ref",
         "    dup",
         "    ldc.i4.1",
         "    ldloc.0",
         "    conv.u4",
         "    box [System.Runtime]System.Int32",
         "    stelem.ref",
         "    ret",
         "  IL_mulu32_over:"
       ]
    <> makeNullaryCellLines (ptOverflowError ptags)
    <> ["    stloc.1"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "    ldloc.1"
    <> [ "    ret",
         "  }",
         ""
       ]

-- parseUInt32: String -> Either ParseError UInt32. Same shape as
--   'parseUInt8Method' minus the > 255 cap, with an int64 accumulator
--   and a > 4294967295 cap (max running magnitude is
--   4294967295 * 10 + 9 = 42949672959, fits in i64 signed).
parseUInt32Method :: PreludeTags -> Text
parseUInt32Method ptags =
  T.intercalate "\n"
    $ [ "  .method private hidebysig static object __parseUInt32(object) cil managed",
        "  {",
        "    .maxstack 4",
        "    .locals init (string V_0, int32 V_1, int32 V_2, int64 V_3, int32 V_4, object V_5)",
        "    ldarg.0",
        "    castclass [System.Runtime]System.String",
        "    stloc.0",
        "    ldloc.0",
        "    callvirt instance int32 [System.Runtime]System.String::get_Length()",
        "    stloc.1",
        "    ldloc.1",
        "    brfalse IL_parseUInt32_fail",
        "    ldc.i4.0",
        "    stloc.2",
        "    ldc.i4.0",
        "    conv.i8",
        "    stloc.3",
        "  IL_parseUInt32_loop:",
        "    ldloc.2",
        "    ldloc.1",
        "    bge IL_parseUInt32_ok",
        "    ldloc.0",
        "    ldloc.2",
        "    callvirt instance char [System.Runtime]System.String::get_Chars(int32)",
        "    stloc.s 4",
        "    ldloc.s 4",
        "    ldc.i4.s 48",
        "    blt IL_parseUInt32_fail",
        "    ldloc.s 4",
        "    ldc.i4.s 57",
        "    bgt IL_parseUInt32_fail",
        "    ldloc.3",
        "    ldc.i4.s 10",
        "    conv.i8",
        "    mul",
        "    ldloc.s 4",
        "    ldc.i4.s 48",
        "    sub",
        "    conv.i8",
        "    add",
        "    stloc.3",
        "    ldloc.3",
        "    ldc.i8 4294967295",
        "    bgt IL_parseUInt32_fail",
        "    ldloc.2",
        "    ldc.i4.1",
        "    add",
        "    stloc.2",
        "    br IL_parseUInt32_loop",
        "  IL_parseUInt32_ok:",
        "    ldc.i4.2",
        "    newarr [System.Runtime]System.Object",
        "    dup",
        "    ldc.i4.0"
      ]
    <> boxedTagLines (ptRight ptags)
    <> [ "    stelem.ref",
         "    dup",
         "    ldc.i4.1",
         "    ldloc.3",
         "    conv.u4",
         "    box [System.Runtime]System.Int32",
         "    stelem.ref",
         "    ret",
         "  IL_parseUInt32_fail:"
       ]
    <> makeNullaryCellLines (ptParseError ptags)
    <> ["    stloc.s 5"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "    ldloc.s 5"
    <> [ "    ret",
         "  }",
         ""
       ]

-- parseInt32: String -> Either ParseError Int32. Handrolled decimal
--   parser; same shape as the LLVM and JVM helpers — long accumulator
--   capped at the magnitude `|minInt32|`. Constant `2147483648L` is
--   built with the shift trick `1 << 31` (avoids needing a CPLong-style
--   literal in the binary assembler).
parseInt32Method :: PreludeTags -> Text
parseInt32Method ptags =
  T.intercalate "\n"
    $ [ "  .method private hidebysig static object __parseInt32(object) cil managed",
        "  {",
        "    .maxstack 4",
        "    .locals init (string V_0, int32 V_1, int32 V_2, int32 V_3, int64 V_4, int32 V_5, object V_6)",
        "    ldarg.0",
        "    castclass [System.Runtime]System.String",
        "    stloc.0",
        "    ldloc.0",
        "    callvirt instance int32 [System.Runtime]System.String::get_Length()",
        "    stloc.1",
        "    ldloc.1",
        "    brfalse IL_parseInt32_fail",
        "    ldc.i4.0",
        "    stloc.2",
        "    ldc.i4.0",
        "    stloc.3",
        "    ldloc.0",
        "    ldc.i4.0",
        "    callvirt instance char [System.Runtime]System.String::get_Chars(int32)",
        "    ldc.i4.s 45",
        "    bne.un.s IL_parseInt32_init_acc",
        "    ldc.i4.1",
        "    stloc.3",
        "    ldc.i4.1",
        "    stloc.2",
        "    ldloc.1",
        "    ldc.i4.1",
        "    beq IL_parseInt32_fail",
        "  IL_parseInt32_init_acc:",
        "    ldc.i4.0",
        "    conv.i8",
        "    stloc.s 4",
        "  IL_parseInt32_loop:",
        "    ldloc.2",
        "    ldloc.1",
        "    bge IL_parseInt32_after_loop",
        "    ldloc.0",
        "    ldloc.2",
        "    callvirt instance char [System.Runtime]System.String::get_Chars(int32)",
        "    stloc.s 5",
        "    ldloc.s 5",
        "    ldc.i4.s 48",
        "    blt IL_parseInt32_fail",
        "    ldloc.s 5",
        "    ldc.i4.s 57",
        "    bgt IL_parseInt32_fail",
        "    ldloc.s 4",
        "    ldc.i4.s 10",
        "    conv.i8",
        "    mul",
        "    ldloc.s 5",
        "    ldc.i4.s 48",
        "    sub",
        "    conv.i8",
        "    add",
        "    stloc.s 4",
        "    ldloc.s 4",
        "    ldc.i4.1",
        "    conv.i8",
        "    ldc.i4.s 31",
        "    shl",
        "    bgt IL_parseInt32_fail",
        "    ldloc.2",
        "    ldc.i4.1",
        "    add",
        "    stloc.2",
        "    br IL_parseInt32_loop",
        "  IL_parseInt32_after_loop:",
        "    ldloc.3",
        "    brfalse IL_parseInt32_pos_check",
        "    ldloc.s 4",
        "    neg",
        "    stloc.s 4",
        "    br IL_parseInt32_build_right",
        "  IL_parseInt32_pos_check:",
        "    ldloc.s 4",
        "    ldc.i4 2147483647",
        "    conv.i8",
        "    bgt IL_parseInt32_fail",
        "  IL_parseInt32_build_right:",
        "    ldc.i4.2",
        "    newarr [System.Runtime]System.Object",
        "    dup",
        "    ldc.i4.0"
      ]
    <> boxedTagLines (ptRight ptags)
    <> [ "    stelem.ref",
         "    dup",
         "    ldc.i4.1",
         "    ldloc.s 4",
         "    conv.i4",
         "    box [System.Runtime]System.Int32",
         "    stelem.ref",
         "    ret",
         "  IL_parseInt32_fail:"
       ]
    <> makeNullaryCellLines (ptParseError ptags)
    <> ["    stloc.s 6"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "    ldloc.s 6"
    <> [ "    ret",
         "  }",
         ""
       ]

-- parseUInt8: String -> Either ParseError UInt8. Same shape as
--   'parseInt32Method' minus the sign handling — UInt8 cannot represent
--   a negative number — and with an i32 accumulator (the running
--   magnitude never exceeds 2559 before the > 255 check fails).
parseUInt8Method :: PreludeTags -> Text
parseUInt8Method ptags =
  T.intercalate "\n"
    $ [ "  .method private hidebysig static object __parseUInt8(object) cil managed",
        "  {",
        "    .maxstack 4",
        "    .locals init (string V_0, int32 V_1, int32 V_2, int32 V_3, int32 V_4, object V_5)",
        "    ldarg.0",
        "    castclass [System.Runtime]System.String",
        "    stloc.0",
        "    ldloc.0",
        "    callvirt instance int32 [System.Runtime]System.String::get_Length()",
        "    stloc.1",
        "    ldloc.1",
        "    brfalse IL_parseUInt8_fail",
        "    ldc.i4.0",
        "    stloc.2",
        "    ldc.i4.0",
        "    stloc.3",
        "  IL_parseUInt8_loop:",
        "    ldloc.2",
        "    ldloc.1",
        "    bge IL_parseUInt8_ok",
        "    ldloc.0",
        "    ldloc.2",
        "    callvirt instance char [System.Runtime]System.String::get_Chars(int32)",
        "    stloc.s 4",
        "    ldloc.s 4",
        "    ldc.i4.s 48",
        "    blt IL_parseUInt8_fail",
        "    ldloc.s 4",
        "    ldc.i4.s 57",
        "    bgt IL_parseUInt8_fail",
        "    ldloc.3",
        "    ldc.i4.s 10",
        "    mul",
        "    ldloc.s 4",
        "    ldc.i4.s 48",
        "    sub",
        "    add",
        "    stloc.3",
        "    ldloc.3",
        "    ldc.i4 255",
        "    bgt IL_parseUInt8_fail",
        "    ldloc.2",
        "    ldc.i4.1",
        "    add",
        "    stloc.2",
        "    br IL_parseUInt8_loop",
        "  IL_parseUInt8_ok:",
        "    ldc.i4.2",
        "    newarr [System.Runtime]System.Object",
        "    dup",
        "    ldc.i4.0"
      ]
    <> boxedTagLines (ptRight ptags)
    <> [ "    stelem.ref",
         "    dup",
         "    ldc.i4.1",
         "    ldloc.3",
         "    box [System.Runtime]System.Int32",
         "    stelem.ref",
         "    ret",
         "  IL_parseUInt8_fail:"
       ]
    <> makeNullaryCellLines (ptParseError ptags)
    <> ["    stloc.s 5"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "    ldloc.s 5"
    <> [ "    ret",
         "  }",
         ""
       ]

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
splitOnFirstMethod ptags =
  T.intercalate "\n"
    $ [ "  .method private hidebysig static object __splitOnFirst(object, object) cil managed",
        "  {",
        "    .maxstack 5",
        "    .locals init (string V_0, string V_1, int32 V_2, string V_3, string V_4, object V_5)",
        "    ldarg.0",
        "    castclass [System.Runtime]System.String",
        "    stloc.0",
        "    ldarg.1",
        "    castclass [System.Runtime]System.String",
        "    stloc.1",
        "    ldloc.1",
        "    ldloc.0",
        "    ldc.i4.4",
        "    callvirt instance int32 [System.Runtime]System.String::IndexOf(string, valuetype [System.Runtime]System.StringComparison)",
        "    stloc.2",
        "    ldloc.2",
        "    ldc.i4.m1",
        "    bne.un.s IL_split_found"
      ]
    <> makeNullaryCellLines (ptNothing ptags)
    <> [ "    ret",
         "  IL_split_found:",
         "    ldloc.1",
         "    ldc.i4.0",
         "    ldloc.2",
         "    callvirt instance string [System.Runtime]System.String::Substring(int32, int32)",
         "    stloc.3",
         "    ldloc.1",
         "    ldloc.2",
         "    ldloc.0",
         "    callvirt instance int32 [System.Runtime]System.String::get_Length()",
         "    add",
         "    callvirt instance string [System.Runtime]System.String::Substring(int32)",
         "    stloc.4",
         "    ldc.i4.3",
         "    newarr [System.Runtime]System.Object",
         "    dup",
         "    ldc.i4.0"
       ]
    <> boxedTagLines (ptTuple2 ptags)
    <> [ "    stelem.ref",
         "    dup",
         "    ldc.i4.1",
         "    ldloc.3",
         "    stelem.ref",
         "    dup",
         "    ldc.i4.2",
         "    ldloc.4",
         "    stelem.ref",
         "    stloc.5",
         "    ldc.i4.2",
         "    newarr [System.Runtime]System.Object",
         "    dup",
         "    ldc.i4.0"
       ]
    <> boxedTagLines (ptJust ptags)
    <> [ "    stelem.ref",
         "    dup",
         "    ldc.i4.1",
         "    ldloc.5",
         "    stelem.ref",
         "    ret",
         "  }",
         ""
       ]

-- lengthCodePoints: String -> UInt32. UTF-32 byte count divided by 4
--   gives the code-point count exactly — every Unicode scalar is one
--   four-byte UTF-32 unit, surrogate pairs collapse to a single unit.
--   Cleaner than walking the string and pairing surrogates by hand.
lengthCodePointsMethod :: Text
lengthCodePointsMethod =
  unlines
    [ "  .method private hidebysig static object __lengthCodePoints(object) cil managed",
      "  {",
      "    .maxstack 3",
      "    .locals init (string V_0)",
      "    ldarg.0",
      "    castclass [System.Runtime]System.String",
      "    stloc.0",
      "    call class [System.Runtime]System.Text.Encoding [System.Runtime]System.Text.Encoding::get_UTF32()",
      "    ldloc.0",
      "    callvirt instance int32 [System.Runtime]System.Text.Encoding::GetByteCount(string)",
      "    ldc.i4.4",
      "    div",
      "    box [System.Runtime]System.Int32",
      "    ret",
      "  }"
    ]

-- lengthUtf16CodeUnits: String -> UInt32. .NET strings are UTF-16
--   internally so 'String.Length' is the code-unit count by definition.
lengthUtf16CodeUnitsMethod :: Text
lengthUtf16CodeUnitsMethod =
  unlines
    [ "  .method private hidebysig static object __lengthUtf16CodeUnits(object) cil managed",
      "  {",
      "    .maxstack 1",
      "    ldarg.0",
      "    castclass [System.Runtime]System.String",
      "    callvirt instance int32 [System.Runtime]System.String::get_Length()",
      "    box [System.Runtime]System.Int32",
      "    ret",
      "  }"
    ]

-- lengthUtf8Bytes: String -> UInt32. 'Encoding.UTF8.GetByteCount(s)'
--   returns the standard UTF-8 byte count without materialising the
--   bytes themselves.
lengthUtf8BytesMethod :: Text
lengthUtf8BytesMethod =
  unlines
    [ "  .method private hidebysig static object __lengthUtf8Bytes(object) cil managed",
      "  {",
      "    .maxstack 2",
      "    call class [System.Runtime]System.Text.Encoding [System.Runtime]System.Text.Encoding::get_UTF8()",
      "    ldarg.0",
      "    castclass [System.Runtime]System.String",
      "    callvirt instance int32 [System.Runtime]System.Text.Encoding::GetByteCount(string)",
      "    box [System.Runtime]System.Int32",
      "    ret",
      "  }"
    ]

-- | __getArgs: zero-arg helper for 'BuiltIn.internalGetArgs'. Reads
--   the cached argv[0] from the "awsum.argv0" environment variable
--   ('Main' stashed it via 'SetEnvironmentVariable' on entry) and
--   routes it through '__entryArgEither' for strict-UTF-16
--   validation. Per the no-memoisation decision each call yields a
--   fresh Either cell; argv is invariant during execution so repeat
--   calls are deterministically equal.
getArgsMethod :: Text
getArgsMethod =
  unlines
    [ "  .method private hidebysig static object __getArgs() cil managed",
      "  {",
      "    .maxstack 1",
      "    ldstr \"awsum.argv0\"",
      "    call string [System.Runtime]System.Environment::GetEnvironmentVariable(string)",
      "    call object AwsumMain::__entryArgEither(object)",
      "    ret",
      "  }"
    ]

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
entryArgEitherMethod ptags =
  T.intercalate "\n"
    $ [ "  .method private hidebysig static object __entryArgEither(object) cil managed",
        "  {",
        "    .maxstack 5",
        -- V_0 = String (cast), V_1 = length, V_2 = i, V_3 = expecting_low,
        -- V_4 = c & 0xFC00, V_5 = inner, V_6 = row.
        "    .locals init (string V_0, int32 V_1, int32 V_2, int32 V_3, int32 V_4, object V_5, object V_6)",
        "    ldarg.0",
        "    castclass [System.Runtime]System.String",
        "    stloc.0",
        "    ldloc.0",
        "    callvirt instance int32 [System.Runtime]System.String::get_Length()",
        "    stloc.1",
        -- maxStringLengthUtf16CodeUnits = 134217728 (= 2^27). Cap-check first.
        "    ldloc.1",
        "    ldc.i4 134217728",
        "    bgt IL_entry_too_long",
        -- Surrogate scan: walk UTF-16 code units.
        "    ldc.i4.0",
        "    stloc.2",
        "    ldc.i4.0",
        "    stloc.3",
        "  IL_entry_scan:",
        "    ldloc.2",
        "    ldloc.1",
        "    bge IL_entry_scan_done",
        "    ldloc.0",
        "    ldloc.2",
        "    callvirt instance char [System.Runtime]System.String::get_Chars(int32)",
        "    ldc.i4 64512", -- 0xFC00
        "    and",
        "    stloc.s 4",
        "    ldloc.s 4",
        "    ldloc.3",
        "    brfalse IL_entry_no_low_expected",
        -- expecting_low: must be DC00.
        "    ldloc.s 4",
        "    ldc.i4 56320", -- 0xDC00
        "    bne.un IL_entry_unpaired",
        "    ldc.i4.0",
        "    stloc.3",
        "    br IL_entry_inc",
        "  IL_entry_no_low_expected:",
        "    ldloc.s 4",
        "    ldc.i4 56320", -- 0xDC00
        "    beq IL_entry_unpaired",
        "    ldloc.s 4",
        "    ldc.i4 55296", -- 0xD800
        "    bne.un IL_entry_inc",
        "    ldc.i4.1",
        "    stloc.3",
        "    br IL_entry_inc",
        "  IL_entry_inc:",
        "    ldloc.2",
        "    ldc.i4.1",
        "    add",
        "    stloc.2",
        "    br IL_entry_scan",
        "  IL_entry_scan_done:",
        -- Trailing high surrogate (last code unit was high without low pair).
        "    ldloc.3",
        "    brtrue IL_entry_unpaired",
        -- Right(input): object[2] = [box(rightTag), input]
        "    ldc.i4.2",
        "    newarr [System.Runtime]System.Object",
        "    dup",
        "    ldc.i4.0"
      ]
    <> boxedTagLines (ptRight ptags)
    <> [ "    stelem.ref",
         "    dup",
         "    ldc.i4.1",
         "    ldarg.0",
         "    stelem.ref",
         "    ret",
         "  IL_entry_too_long:"
       ]
    <> makeNullaryCellLines (ptStringTooLong ptags)
    <> [ "    stloc.s 5",
         "    ldc.i4.2",
         "    newarr [System.Runtime]System.Object",
         "    dup",
         "    ldc.i4.0",
         "    ldc.i4 " <> stringTooLongRowTag,
         "    box [System.Runtime]System.Int32",
         "    stelem.ref",
         "    dup",
         "    ldc.i4.1",
         "    ldloc.s 5",
         "    stelem.ref",
         "    stloc.s 6"
       ]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "    ldloc.s 6"
    <> [ "    ret",
         "  IL_entry_unpaired:"
       ]
    <> makeNullaryCellLines (ptUnpairedUtf16Surrogate ptags)
    <> [ "    stloc.s 5",
         "    ldc.i4.2",
         "    newarr [System.Runtime]System.Object",
         "    dup",
         "    ldc.i4.0",
         "    ldc.i4 " <> unpairedSurrogateRowTag,
         "    box [System.Runtime]System.Int32",
         "    stelem.ref",
         "    dup",
         "    ldc.i4.1",
         "    ldloc.s 5",
         "    stelem.ref",
         "    stloc.s 6"
       ]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "    ldloc.s 6"
    <> [ "    ret",
         "  }",
         ""
       ]
  where
    stringTooLongRowTag :: Text
    stringTooLongRowTag = show (fromIntegral (rowTag (TyCon noSpan "StringTooLong")) :: Int32)
    unpairedSurrogateRowTag :: Text
    unpairedSurrogateRowTag = show (fromIntegral (rowTag (TyCon noSpan "UnpairedUtf16Surrogate")) :: Int32)

mainMethod :: Text
mainMethod =
  unlines
    [ "  .method private hidebysig static void Main(string[]) cil managed",
      "  {",
      "    .entrypoint",
      "    .locals init (object input)",
      -- Force stdout to UTF-8 before any user code runs. On Windows with a
      -- piped or redirected stdout, the default 'Console.OutputEncoding'
      -- falls back to the system ANSI code page, which encodes each UTF-16
      -- code unit individually — supplementary code points then collapse to
      -- "??" because their two surrogate units each become a separate '?'.
      -- Setting UTF-8 keeps the byte stream identical to the other backends.
      "    call class [System.Runtime]System.Text.Encoding [System.Runtime]System.Text.Encoding::get_UTF8()",
      "    call void [System.Console]System.Console::set_OutputEncoding(class [System.Runtime]System.Text.Encoding)",
      "    ldarg.0",
      "    ldlen",
      "    conv.i4",
      "    ldc.i4.1",
      "    bge.s has_arg",
      "    ldstr \"\"",
      "    br.s call_main",
      "  has_arg:",
      "    ldarg.0",
      "    ldc.i4.0",
      "    ldelem.ref",
      "  call_main:",
      -- Cache argv[0] for 'BuiltIn.internalGetArgs' (called from
      -- 'runIO''s 'IOGetArgs' arm) via a process-wide environment
      -- variable. 'main' itself takes no arguments (signature
      -- 'IO Never Unit'); user code reads argv through
      -- 'IO.Args.getArgs' inside the IO chain. CIL has no direct
      -- 'swap' opcode so we route through 'input' local: stloc; ldstr;
      -- ldloc; castclass; call SetEnv (returns void).
      "    stloc.0",
      "    ldstr \"awsum.argv0\"",
      "    ldloc.0",
      "    castclass string",
      "    call void [System.Runtime]System.Environment::SetEnvironmentVariable(string, string)",
      -- v_main is a zero-arg value (CValDef): build the IO tree.
      "    call object AwsumMain::" <> mangle "main" <> "()",
      -- Hand the IO tree to `runIO`, which walks it and performs the
      -- effects via `BuiltIn.internalStdoutPrint`. `runIO` returns
      -- Unit; we discard it.
      "    call object AwsumMain::" <> mangle "runIO" <> "(object)",
      "    pop",
      "    ret",
      "  }"
    ]

-- ════════════════════════════════════════════════════════════════════════════
-- User declarations
-- ════════════════════════════════════════════════════════════════════════════

emitDecl :: Ctx -> CDecl -> Text
emitDecl ctx = \case
  -- TCO-wrapped body. The method's argument slots are already mutable
  -- (@starg@), so there is no separate alloca ceremony: a 'CContinue'
  -- evaluates its new argument values, pops them into the argument
  -- slots (reverse order, since the stack is LIFO), and jumps back to
  -- the @IL_tco_loop@ label placed at the method's first instruction.
  -- Every real return path evaluates its value and emits its own @ret@;
  -- 'CContinue' paths end in @br IL_tco_loop@ instead.
  CFunDef nm args (CLoop body) ->
    let varMap = Map.fromList [(a, "    ldarg" <> ldargSuffix i) | (a, i) <- zip args [0 ..]]
        desc = objMethodDesc (length args)
        bodyText = emitTailText ctx varMap args body
     in unlines
          [ "  .method private hidebysig static object " <> mangle nm <> desc <> " cil managed",
            "  {",
            "  IL_tco_loop:",
            bodyText,
            "  }"
          ]
  CFunDef nm args body ->
    let varMap = Map.fromList [(a, "    ldarg" <> ldargSuffix i) | (a, i) <- zip args [0 ..]]
        desc = objMethodDesc (length args)
        bodyText = emitExprText ctx varMap body
     in unlines
          [ "  .method private hidebysig static object " <> mangle nm <> desc <> " cil managed",
            "  {",
            bodyText,
            "    ret",
            "  }"
          ]
  CValDef nm rhs ->
    let bodyText = emitExprText ctx Map.empty rhs
     in unlines
          [ "  .method private hidebysig static object " <> mangle nm <> "() cil managed",
            "  {",
            bodyText,
            "    ret",
            "  }"
          ]

-- ════════════════════════════════════════════════════════════════════════════
-- Expression emission (text)
-- ════════════════════════════════════════════════════════════════════════════

-- | Next free @ldloc@ slot beyond everything currently mapped in
-- 'varMap'. Parameter entries render as @ldarg@ and don't occupy local
-- slots; nested 'CCase's extend the map with 'ldloc' entries and this
-- counter keeps them from reusing an outer arm's slot.
nextLocSlot :: Map Text Text -> Int
nextLocSlot = length . filter isLdloc . Map.elems
  where
    isLdloc t = "    ldloc" `T.isPrefixOf` t

emitExprText :: Ctx -> Map Text Text -> CExpr -> Text
emitExprText ctx varMap = \case
  CString s ->
    "    ldstr " <> show s
  CVar n
    | Just instr <- Map.lookup n varMap -> instr
    | n `Set.member` ctx.cValDefs ->
        "    call object AwsumMain::" <> mangle n <> "()"
    | n `Set.member` ctx.cFunDefs ->
        let arity = fromMaybe 0 (Map.lookup n ctx.cArities)
         in "    ldftn object AwsumMain::"
              <> mangle n
              <> objMethodDesc arity
              <> "\n"
              <> "    newobj instance void class [System.Runtime]System.Func`"
              <> show (arity + 1)
              <> "<"
              <> T.intercalate ", " (replicate (arity + 1) "object")
              <> ">::.ctor(object, native int)"
    | otherwise ->
        "    ldnull"
  CIntLit n _ ->
    -- Same shape as the binary assembler: push Int32 and box to System.Object.
    T.intercalate
      "\n"
      [ "    ldc.i4 " <> show (fromInteger n :: Int32),
        "    box [System.Runtime]System.Int32"
      ]
  CBuiltIn _ ->
    "    ldnull" -- invariant: not a standalone term; dispatched from CCall
  CCon tag fields ->
    let nSlots = 1 + length fields
        storeTag =
          [ "    dup",
            emitLdcI4 0,
            emitLdcI4 tag,
            "    box [System.Runtime]System.Int32",
            "    stelem.ref"
          ]
        storeFields =
          [ "    dup\n" <> emitLdcI4 (i :: Int) <> "\n" <> emitExprText ctx varMap fld <> "\n    stelem.ref"
          | (fld, i) <- zip fields [1 ..]
          ]
     in T.intercalate "\n"
          $ [emitLdcI4 nSlots, "    newarr [System.Runtime]System.Object"]
          <> storeTag
          <> storeFields
  -- Row injection / dispatch: delegate to CCon / CCase emit.
  CRow tag v -> emitExprText ctx varMap (CCon (fromIntegral tag) [v])
  CRowCase scrut alts ->
    emitExprText ctx varMap (CCase scrut [(fromIntegral t, [v], b) | (t, v, b) <- alts])
  CCase scrut alts ->
    let sorted = sortWith (\(t, _, _) -> t) alts
        scrutText = emitExprText ctx varMap scrut
        -- Extract tag: dup arr, ldc 0, ldelem.ref, unbox Int32
        extractTag =
          T.intercalate
            "\n"
            [ "    dup",
              emitLdcI4 0,
              "    ldelem.ref",
              "    unbox.any [System.Runtime]System.Int32"
            ]
        armLabels = ["IL_arm_" <> show tag | (tag, _, _) <- sorted]
        joinLabel :: Text
        joinLabel = "IL_join"
        switchText = "    switch (" <> T.intercalate ", " armLabels <> ")"
        -- Allocate fresh slots beyond every binding already live so
        -- nested 'CCase's never clobber outer-arm bindings. Params
        -- live in 'ldarg' slots and don't count against local slots.
        baseSlot = nextLocSlot varMap
        emitArm (_, vars, body) lbl =
          let bindings = zip vars [baseSlot ..]
              storeCode =
                T.concat
                  [ "    dup\n" <> emitLdcI4 (i :: Int) <> "\n    ldelem.ref\n    stloc" <> ldlocSuffix slot <> "\n"
                  | ((_, slot), i) <- zip bindings [1 :: Int ..]
                  ]
              varMap' = foldl' (\m (v, slot) -> Map.insert v ("    ldloc" <> ldlocSuffix slot) m) varMap bindings
           in "  " <> lbl <> ":\n" <> storeCode <> "    pop\n" <> emitExprText ctx varMap' body <> "\n    br.s " <> joinLabel
        armTexts = [emitArm alt lbl | (alt, lbl) <- zip sorted armLabels]
     in T.intercalate "\n"
          $ [scrutText, extractTag, switchText]
          <> armTexts
          <> ["  " <> joinLabel <> ":"]
  CCall f xs ->
    case f of
      CBuiltIn "internalStdoutPrint"
        | [x] <- xs ->
            T.intercalate
              "\n"
              [ emitExprText ctx varMap x,
                "    call object AwsumMain::__print(object)"
              ]
      -- 'BuiltIn.internalGetArgs' — call AwsumMain::__getArgs(), which
      -- reads the cached argv[0] (set in 'Main' via
      -- 'SetEnvironmentVariable') and routes it through
      -- '__entryArgEither'.
      CBuiltIn "internalGetArgs"
        | [] <- xs -> "    call object AwsumMain::__getArgs()"
      CBuiltIn name
        | name == "showInt32" || name == "showUInt8",
          [x] <- xs ->
            T.intercalate
              "\n"
              [ emitExprText ctx varMap x,
                "    callvirt instance string [System.Runtime]System.Object::ToString()"
              ]
      CBuiltIn "showUInt32"
        | [x] <- xs ->
            T.intercalate
              "\n"
              [ emitExprText ctx varMap x,
                "    call object AwsumMain::__showUInt32(object)"
              ]
      CBuiltIn "predInt32"
        | [x] <- xs ->
            T.intercalate
              "\n"
              [ emitExprText ctx varMap x,
                "    call object AwsumMain::__predInt32(object)"
              ]
      CBuiltIn "predUInt8"
        | [x] <- xs ->
            T.intercalate
              "\n"
              [ emitExprText ctx varMap x,
                "    call object AwsumMain::__predUInt8(object)"
              ]
      CBuiltIn "predUInt32"
        | [x] <- xs ->
            T.intercalate
              "\n"
              [ emitExprText ctx varMap x,
                "    call object AwsumMain::__predUInt32(object)"
              ]
      CBuiltIn "succInt32"
        | [x] <- xs ->
            T.intercalate
              "\n"
              [ emitExprText ctx varMap x,
                "    call object AwsumMain::__succInt32(object)"
              ]
      CBuiltIn "succUInt8"
        | [x] <- xs ->
            T.intercalate
              "\n"
              [ emitExprText ctx varMap x,
                "    call object AwsumMain::__succUInt8(object)"
              ]
      CBuiltIn "succUInt32"
        | [x] <- xs ->
            T.intercalate
              "\n"
              [ emitExprText ctx varMap x,
                "    call object AwsumMain::__succUInt32(object)"
              ]
      CBuiltIn name
        | name == "eqInt32" || name == "eqUInt8" || name == "eqUInt32",
          [a, b] <- xs ->
            let fn = case name of
                  "eqInt32" -> "__eqInt32"
                  "eqUInt8" -> "__eqUInt8"
                  _ -> "__eqUInt32"
             in T.intercalate
                  "\n"
                  [ emitExprText ctx varMap a,
                    emitExprText ctx varMap b,
                    "    call object AwsumMain::" <> fn <> "(object, object)"
                  ]
      CBuiltIn name
        | name == "addInt32" || name == "addUInt8" || name == "addUInt32" || name == "subInt32" || name == "subUInt8" || name == "subUInt32" || name == "mulUInt8" || name == "mulUInt32" || name == "mulInt32",
          [a, b] <- xs ->
            let fn = case name of
                  "addInt32" -> "__addInt32"
                  "addUInt8" -> "__addUInt8"
                  "addUInt32" -> "__addUInt32"
                  "subInt32" -> "__subInt32"
                  "subUInt8" -> "__subUInt8"
                  "subUInt32" -> "__subUInt32"
                  "mulInt32" -> "__mulInt32"
                  "mulUInt32" -> "__mulUInt32"
                  _ -> "__mulUInt8"
             in T.intercalate
                  "\n"
                  [ emitExprText ctx varMap a,
                    emitExprText ctx varMap b,
                    "    call object AwsumMain::" <> fn <> "(object, object)"
                  ]
      CBuiltIn "negInt32"
        | [x] <- xs ->
            T.intercalate
              "\n"
              [ emitExprText ctx varMap x,
                "    call object AwsumMain::__negInt32(object)"
              ]
      CBuiltIn "concatString"
        | [a, b] <- xs ->
            T.intercalate
              "\n"
              [ emitExprText ctx varMap a,
                emitExprText ctx varMap b,
                "    call object AwsumMain::__concat(object, object)"
              ]
      CBuiltIn "splitOnFirst"
        | [a, b] <- xs ->
            T.intercalate
              "\n"
              [ emitExprText ctx varMap a,
                emitExprText ctx varMap b,
                "    call object AwsumMain::__splitOnFirst(object, object)"
              ]
      CBuiltIn name
        | name == "parseInt32" || name == "parseUInt8" || name == "parseUInt32",
          [x] <- xs ->
            let fn = case name of
                  "parseInt32" -> "__parseInt32"
                  "parseUInt32" -> "__parseUInt32"
                  _ -> "__parseUInt8"
             in T.intercalate
                  "\n"
                  [ emitExprText ctx varMap x,
                    "    call object AwsumMain::" <> fn <> "(object)"
                  ]
      CBuiltIn name
        | name == "lengthCodePoints" || name == "lengthUtf16CodeUnits" || name == "lengthUtf8Bytes",
          [x] <- xs ->
            let fn = case name of
                  "lengthCodePoints" -> "__lengthCodePoints"
                  "lengthUtf16CodeUnits" -> "__lengthUtf16CodeUnits"
                  _ -> "__lengthUtf8Bytes"
             in T.intercalate
                  "\n"
                  [ emitExprText ctx varMap x,
                    "    call object AwsumMain::" <> fn <> "(object)"
                  ]
      CBuiltIn n ->
        error ("CLR codegen: unknown builtin '" <> n <> "' reached CCall (typecheck should have rejected it)")
      CVar n
        | n `Set.member` ctx.cFunDefs ->
            let argTexts = map (emitExprText ctx varMap) xs
                desc = objMethodDesc (length xs)
             in T.intercalate "\n"
                  $ argTexts
                  <> ["    call object AwsumMain::" <> mangle n <> desc]
      _ ->
        let fText = emitExprText ctx varMap f
            argTexts = map (emitExprText ctx varMap) xs
            arity = length xs
            funcType =
              "class [System.Runtime]System.Func`"
                <> show (arity + 1)
                <> "<"
                <> T.intercalate ", " (replicate (arity + 1) "object")
                <> ">"
            invokeDesc = "(" <> T.intercalate ", " (replicate arity "object") <> ")"
         in T.intercalate "\n"
              $ [fText, "    castclass " <> funcType]
              <> argTexts
              <> ["    callvirt instance object " <> funcType <> "::Invoke" <> invokeDesc]
  CLoop _ -> error "CLR codegen: CLoop reached emitExprText (non-tail position)"
  CContinue _ -> error "CLR codegen: CContinue reached emitExprText (non-tail position)"

-- | Emit @body@ in tail position under @IL_tco_loop:@.
-- 'CContinue' evaluates its new arguments (so old parameter reads see
-- the pre-update values), pops them into argument slots in reverse —
-- the CIL stack is LIFO, so the last-evaluated value is on top and
-- needs to land in the last argument slot — then @br IL_tco_loop@.
-- Any other tail shape computes a value and ends with its own @ret@.
-- 'CCase' chains structurally so each arm terminates itself.
emitTailText :: Ctx -> Map Text Text -> [Text] -> CExpr -> Text
emitTailText ctx varMap _params = go varMap
  where
    go :: Map Text Text -> CExpr -> Text
    go vmap = \case
      CContinue newArgs ->
        let evals = T.intercalate "\n" [emitExprText ctx vmap a | a <- newArgs]
            stargs =
              T.intercalate
                "\n"
                [ "    starg.s " <> show i
                | i <- reverse [0 .. length newArgs - 1]
                ]
         in evals <> "\n" <> stargs <> "\n    br IL_tco_loop"
      CCase scrut alts ->
        let sorted = sortWith (\(t, _, _) -> t) alts
            scrutText = emitExprText ctx vmap scrut
            extractTag =
              T.intercalate
                "\n"
                [ "    dup",
                  emitLdcI4 0,
                  "    ldelem.ref",
                  "    unbox.any [System.Runtime]System.Int32"
                ]
            armLabels = ["IL_tco_arm_" <> show tag | (tag, _, _) <- sorted]
            switchText = "    switch (" <> T.intercalate ", " armLabels <> ")"
            baseSlot = nextLocSlot vmap
            emitArm (_, vars, body) lbl =
              let bindings = zip vars [baseSlot ..]
                  storeCode =
                    T.concat
                      [ "    dup\n" <> emitLdcI4 (i :: Int) <> "\n    ldelem.ref\n    stloc" <> ldlocSuffix slot <> "\n"
                      | ((_, slot), i) <- zip bindings [1 :: Int ..]
                      ]
                  vmap' = foldl' (\m (v, slot) -> Map.insert v ("    ldloc" <> ldlocSuffix slot) m) vmap bindings
               in "  " <> lbl <> ":\n" <> storeCode <> "    pop\n" <> go vmap' body
            armTexts = [emitArm alt lbl | (alt, lbl) <- zip sorted armLabels]
         in T.intercalate "\n"
              $ [scrutText, extractTag, switchText]
              <> armTexts
      other ->
        emitExprText ctx vmap other <> "\n    ret"

-- ════════════════════════════════════════════════════════════════════════════
-- Helpers
-- ════════════════════════════════════════════════════════════════════════════

mangle :: Text -> Text
mangle t =
  let ok c = Char.isAlphaNum c || c == '_' || c == '\''
      body = T.map (\c -> if ok c then c else '_') t
   in "v_" <> body

objMethodDesc :: Int -> Text
objMethodDesc n =
  "(" <> T.intercalate ", " (replicate n "object") <> ")"

ldargSuffix :: Int -> Text
ldargSuffix n
  | n <= 3 = "." <> show n
  | otherwise = " " <> show n

ldlocSuffix :: Int -> Text
ldlocSuffix n
  | n <= 3 = "." <> show n
  | otherwise = ".s " <> show n

emitLdcI4 :: Int -> Text
emitLdcI4 n
  | n >= 0 && n <= 8 = "    ldc.i4." <> show n
  | n == -1 = "    ldc.i4.m1"
  | n >= -128 && n <= 127 = "    ldc.i4.s " <> show n
  | otherwise = "    ldc.i4 " <> show n
