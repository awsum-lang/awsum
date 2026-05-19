-- | JVM textual bytecode assembler for Awsum 'Core'.
--
-- Produces a human-readable Jasmin-like text representation of the
-- JVM bytecode that 'Awsum.Codegen.JVM.Assemble' generates as binary.
-- Used for @awsum build -t jvm@ output and snapshot tests.
module Awsum.Codegen.JVM (codegenJVM) where

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
      ctx = Ctx {cValDefs = valNames, cFunDefs = funNames, cArities = arities}
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
            T.intercalate "\n\n" (map (emitDecl ctx) decls),
            "",
            gate (Set.member "internalGetArgs" builtIns || Set.member "internalStdinReadAllAsUtf16" builtIns) (entryArgEitherMethod ptags),
            "",
            gate (Set.member "internalGetArgs" builtIns) getArgsMethod,
            "",
            gate (Set.member "internalStdinReadAllAsUtf16" builtIns) stdinReadAllMethod,
            "",
            mainMethod,
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

-- | Emit the JVM bytecode line for "push integer N onto the operand
-- stack". Picks the tightest instruction the JVM offers for the
-- value: 'iconst_<N>' for [-1, 5], 'bipush' for one-byte signed,
-- 'sipush' for two-byte signed, otherwise 'ldc' (constant-pool
-- indirection).
pushIntInsn :: Int -> Text
pushIntInsn n
  | n >= -1 && n <= 5 = "  iconst_" <> if n == -1 then "m1" else show n
  | n >= -128 && n <= 127 = "  bipush " <> show n
  | n >= -32768 && n <= 32767 = "  sipush " <> show n
  | otherwise = "  ldc " <> show n

-- | Lines for "push tag @n@, then box it as @java.lang.Integer@".
-- Used every time a constructor tag is stored into an @Object[]@
-- slot at the call site that builds a CCon-shaped value.
boxedTagLines :: Int -> [Text]
boxedTagLines n =
  [ pushIntInsn n,
    "  invokestatic java/lang/Integer/valueOf(I)Ljava/lang/Integer;"
  ]

-- | Lines that build @Object[1] = [Integer(tag)]@ (a nullary 'CCon')
-- and leave it on the stack. Caller decides what to do with it
-- (typically @astore_<n>@ or @areturn@).
makeNullaryCellLines :: Int -> [Text]
makeNullaryCellLines tag =
  [ "  iconst_1",
    "  anewarray java/lang/Object",
    "  dup",
    "  iconst_0"
  ]
    <> boxedTagLines tag
    <> ["  aastore"]

-- | Lines that build @Object[2] = [Integer(tag), <value loaded by aloadInsn>]@
-- (a one-field 'CCon') and leave it on the stack. @aloadInsn@ is the
-- raw line emitting the load — typically @"  aload_<n>"@.
makeUnaryCellFromLocalLines :: Int -> Text -> [Text]
makeUnaryCellFromLocalLines tag aloadInsn =
  [ "  iconst_2",
    "  anewarray java/lang/Object",
    "  dup",
    "  iconst_0"
  ]
    <> boxedTagLines tag
    <> [ "  aastore",
         "  dup",
         "  iconst_1",
         aloadInsn,
         "  aastore"
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
      ".super java/lang/Object"
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
  T.intercalate "\n"
    $ [ ".method static __concat(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
        "  .limit stack 6",
        "  .limit locals 3",
        -- Compute UTF-16 length of each input. java.lang.String.length()
        -- is exactly UTF-16 code units (JVM stores strings as UTF-16),
        -- so this is the right unit for the cap check directly.
        "  aload_0",
        "  checkcast java/lang/String",
        "  invokevirtual java/lang/String/length()I",
        "  i2l",
        "  aload_1",
        "  checkcast java/lang/String",
        "  invokevirtual java/lang/String/length()I",
        "  i2l",
        "  ladd",
        -- maxStringLengthUtf16CodeUnits = 134217728 (= 2^27).
        -- Keep in sync with 'maxStringLengthUtf16CodeUnits' in
        -- 'stdlib/Prelude.aww'.
        "  ldc2_w 134217728",
        "  lcmp",
        "  ifgt L_concat_too_long",
        -- Length OK: do String.concat and wrap in Right.
        "  aload_0",
        "  checkcast java/lang/String",
        "  aload_1",
        "  checkcast java/lang/String",
        "  invokevirtual java/lang/String/concat(Ljava/lang/String;)Ljava/lang/String;",
        "  astore_2",
        -- Build Right(result): Object[2] = [Integer(rightTag), result].
        "  iconst_2",
        "  anewarray java/lang/Object",
        "  dup",
        "  iconst_0"
      ]
    <> boxedTagLines (ptRight ptags)
    <> [ "  aastore",
         "  dup",
         "  iconst_1",
         "  aload_2",
         "  aastore",
         "  areturn",
         "L_concat_too_long:",
         -- Build Left(StringTooLong). StringTooLong cell: Object[1] = [Integer(stl)].
         "  iconst_1",
         "  anewarray java/lang/Object",
         "  dup",
         "  iconst_0"
       ]
    <> boxedTagLines (ptStringTooLong ptags)
    <> [ "  aastore",
         "  astore_2",
         -- Left cell: Object[2] = [Integer(left), stl].
         "  iconst_2",
         "  anewarray java/lang/Object",
         "  dup",
         "  iconst_0"
       ]
    <> boxedTagLines (ptLeft ptags)
    <> [ "  aastore",
         "  dup",
         "  iconst_1",
         "  aload_2",
         "  aastore",
         "  areturn",
         ".end method",
         ""
       ]

-- | __print: low-level platform primitive driven by the prelude's
--   `runIO` via `BuiltIn.internalStdoutPrint`. Returns a Unit value
--   (Object[1] = [Integer(0)]) so the surrounding `case … of Unit ->
--   next` arm in `runIO` dispatches through the standard CCase tag
--   check.
printMethod :: PreludeTags -> Text
printMethod ptags =
  T.intercalate "\n"
    $ [ ".method static __print(Ljava/lang/Object;)Ljava/lang/Object;",
        "  getstatic java/lang/System/out Ljava/io/PrintStream;",
        "  aload_0",
        "  invokevirtual java/io/PrintStream/print(Ljava/lang/Object;)V",
        -- Build Unit value: Object[1] = [Integer(unit)]
        "  iconst_1",
        "  anewarray java/lang/Object",
        "  dup",
        "  iconst_0"
      ]
    <> boxedTagLines (ptUnit ptags)
    <> [ "  aastore",
         "  areturn",
         ".end method",
         ""
       ]

-- predInt32: Int32 -> Either UnderflowError Int32.
--   `Left UnderflowError` on INT32_MIN (tags Left=0, UnderflowError=0);
--   `Right (x - 1)` otherwise (Right=1). Containers are Object[] with
--   boxed Integer tags at [0], matching user CCon emission on the JVM.
predInt32Method :: PreludeTags -> Text
predInt32Method ptags =
  T.intercalate "\n"
    $ [ ".method static __predInt32(Ljava/lang/Object;)Ljava/lang/Object;",
        "  .limit stack 5",
        "  .limit locals 3",
        "  aload_0",
        "  checkcast java/lang/Integer",
        "  invokevirtual java/lang/Integer/intValue()I",
        "  istore_1",
        "  iload_1",
        "  ldc -2147483648",
        "  if_icmpne L_pred_ok"
      ]
    <> makeNullaryCellLines (ptUnderflowError ptags)
    <> ["  astore_2"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "  aload_2"
    <> [ "  areturn",
         "L_pred_ok:",
         "  iconst_2",
         "  anewarray java/lang/Object",
         "  dup",
         "  iconst_0"
       ]
    <> boxedTagLines (ptRight ptags)
    <> [ "  aastore",
         "  dup",
         "  iconst_1",
         "  iload_1",
         "  iconst_1",
         "  isub",
         "  invokestatic java/lang/Integer/valueOf(I)Ljava/lang/Integer;",
         "  aastore",
         "  areturn",
         ".end method",
         ""
       ]

-- predUInt8: UInt8 -> Either UnderflowError UInt8.
--   `Left UnderflowError` on 0; `Right (v - 1)` otherwise. UInt8 flows as
--   a boxed Integer (same representation as Int32 on the JVM), so the
--   method structure mirrors predInt32 — the only differences are the
--   zero check (via 'ifne' against 0) and the absence of any mask on
--   (v - 1), which is guaranteed to be in 0..254 when v >= 1.
predUInt8Method :: PreludeTags -> Text
predUInt8Method ptags =
  T.intercalate "\n"
    $ [ ".method static __predUInt8(Ljava/lang/Object;)Ljava/lang/Object;",
        "  .limit stack 5",
        "  .limit locals 3",
        "  aload_0",
        "  checkcast java/lang/Integer",
        "  invokevirtual java/lang/Integer/intValue()I",
        "  istore_1",
        "  iload_1",
        "  ifne L_predu8_ok"
      ]
    <> makeNullaryCellLines (ptUnderflowError ptags)
    <> ["  astore_2"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "  aload_2"
    <> [ "  areturn",
         "L_predu8_ok:",
         "  iconst_2",
         "  anewarray java/lang/Object",
         "  dup",
         "  iconst_0"
       ]
    <> boxedTagLines (ptRight ptags)
    <> [ "  aastore",
         "  dup",
         "  iconst_1",
         "  iload_1",
         "  iconst_1",
         "  isub",
         "  invokestatic java/lang/Integer/valueOf(I)Ljava/lang/Integer;",
         "  aastore",
         "  areturn",
         ".end method",
         ""
       ]

-- succInt32: Int32 -> Either OverflowError Int32.
--   Mirror of predInt32Method with INT32_MAX as the boundary and 'iadd'
--   for the non-overflow branch. OverflowError is single-constructor, so
--   its tag is 0 — the error-branch encoding is identical to the
--   UnderflowError case in predInt32.
succInt32Method :: PreludeTags -> Text
succInt32Method ptags =
  T.intercalate "\n"
    $ [ ".method static __succInt32(Ljava/lang/Object;)Ljava/lang/Object;",
        "  .limit stack 5",
        "  .limit locals 3",
        "  aload_0",
        "  checkcast java/lang/Integer",
        "  invokevirtual java/lang/Integer/intValue()I",
        "  istore_1",
        "  iload_1",
        "  ldc 2147483647",
        "  if_icmpne L_succ_ok"
      ]
    <> makeNullaryCellLines (ptOverflowError ptags)
    <> ["  astore_2"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "  aload_2"
    <> [ "  areturn",
         "L_succ_ok:",
         "  iconst_2",
         "  anewarray java/lang/Object",
         "  dup",
         "  iconst_0"
       ]
    <> boxedTagLines (ptRight ptags)
    <> [ "  aastore",
         "  dup",
         "  iconst_1",
         "  iload_1",
         "  iconst_1",
         "  iadd",
         "  invokestatic java/lang/Integer/valueOf(I)Ljava/lang/Integer;",
         "  aastore",
         "  areturn",
         ".end method",
         ""
       ]

-- succUInt8: UInt8 -> Either OverflowError UInt8.
--   Mirrors succInt32Method with boundary 255. Since v <= 254 on the ok
--   path, (v + 1) is in 1..255, so no mask is needed to stay in UInt8
--   range. 'sipush' is used for 255 (outside the 'bipush' signed byte
--   range but inside signed short).
succUInt8Method :: PreludeTags -> Text
succUInt8Method ptags =
  T.intercalate "\n"
    $ [ ".method static __succUInt8(Ljava/lang/Object;)Ljava/lang/Object;",
        "  .limit stack 5",
        "  .limit locals 3",
        "  aload_0",
        "  checkcast java/lang/Integer",
        "  invokevirtual java/lang/Integer/intValue()I",
        "  istore_1",
        "  iload_1",
        "  sipush 255",
        "  if_icmpne L_succu8_ok"
      ]
    <> makeNullaryCellLines (ptOverflowError ptags)
    <> ["  astore_2"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "  aload_2"
    <> [ "  areturn",
         "L_succu8_ok:",
         "  iconst_2",
         "  anewarray java/lang/Object",
         "  dup",
         "  iconst_0"
       ]
    <> boxedTagLines (ptRight ptags)
    <> [ "  aastore",
         "  dup",
         "  iconst_1",
         "  iload_1",
         "  iconst_1",
         "  iadd",
         "  invokestatic java/lang/Integer/valueOf(I)Ljava/lang/Integer;",
         "  aastore",
         "  areturn",
         ".end method",
         ""
       ]

-- eqInt32 / eqUInt8: Int32 -> Int32 -> Bool and UInt8 -> UInt8 -> Bool.
--   Both types are boxed as Integer on the JVM, so the two methods have
--   identical bodies but distinct names (parallel to showInt32 vs
--   showUInt8). Returns True=0 or False=1 as a one-slot Object[].
--   A unique label suffix keeps both methods disassemblable in one class.
eqMethod :: PreludeTags -> Text -> Text -> Text
eqMethod ptags name lbl =
  T.intercalate "\n"
    $ [ ".method static " <> name <> "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
        "  .limit stack 5",
        "  .limit locals 2",
        "  aload_0",
        "  checkcast java/lang/Integer",
        "  invokevirtual java/lang/Integer/intValue()I",
        "  aload_1",
        "  checkcast java/lang/Integer",
        "  invokevirtual java/lang/Integer/intValue()I",
        "  if_icmpne " <> lbl <> "_ne"
      ]
    <> makeNullaryCellLines (ptTrue ptags)
    <> [ "  areturn",
         lbl <> "_ne:"
       ]
    <> makeNullaryCellLines (ptFalse ptags)
    <> [ "  areturn",
         ".end method",
         ""
       ]

-- addInt32: Int32 -> Int32 -> Either ArithError Int32.
--   Promote both operands to long, sum, then range-check against
--   [-2147483648, 2147483647] with `lcmp`. ArithError tags follow the
--   declaration order in `Prelude.aww`: Underflow=0, Overflow=1; Either
--   tags are Left=0, Right=1 as everywhere else in this file.
addInt32Method :: PreludeTags -> Text
addInt32Method ptags =
  T.intercalate "\n"
    $ [ ".method static __addInt32(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
        "  .limit stack 6",
        "  .limit locals 3",
        "  aload_0",
        "  checkcast java/lang/Integer",
        "  invokevirtual java/lang/Integer/intValue()I",
        "  i2l",
        "  aload_1",
        "  checkcast java/lang/Integer",
        "  invokevirtual java/lang/Integer/intValue()I",
        "  i2l",
        "  ladd",
        "  dup2",
        "  ldc2_w 2147483647",
        "  lcmp",
        "  ifgt L_addi32_over",
        "  dup2",
        "  ldc2_w -2147483648",
        "  lcmp",
        "  iflt L_addi32_under",
        "  l2i",
        "  invokestatic java/lang/Integer/valueOf(I)Ljava/lang/Integer;",
        "  astore_2",
        "  iconst_2",
        "  anewarray java/lang/Object",
        "  dup",
        "  iconst_0"
      ]
    <> boxedTagLines (ptRight ptags)
    <> [ "  aastore",
         "  dup",
         "  iconst_1",
         "  aload_2",
         "  aastore",
         "  areturn",
         "L_addi32_over:",
         "  pop2"
       ]
    <> makeNullaryCellLines (ptOverflowError ptags)
    <> ["  astore_2"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "  aload_2"
    <> [ "  areturn",
         "L_addi32_under:",
         "  pop2"
       ]
    <> makeNullaryCellLines (ptUnderflowError ptags)
    <> ["  astore_2"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "  aload_2"
    <> [ "  areturn",
         ".end method",
         ""
       ]

-- addUInt8: UInt8 -> UInt8 -> Either OverflowError UInt8.
--   Both operands are 0..255, so `iadd` produces a value in 0..510 with
--   no JVM-level overflow; one `if_icmple` against 255 picks the branch.
--   On the ok path the sum is already a valid UInt8 — no mask needed.
addUInt8Method :: PreludeTags -> Text
addUInt8Method ptags =
  T.intercalate "\n"
    $ [ ".method static __addUInt8(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
        "  .limit stack 5",
        "  .limit locals 3",
        "  aload_0",
        "  checkcast java/lang/Integer",
        "  invokevirtual java/lang/Integer/intValue()I",
        "  aload_1",
        "  checkcast java/lang/Integer",
        "  invokevirtual java/lang/Integer/intValue()I",
        "  iadd",
        "  istore_2",
        "  iload_2",
        "  sipush 255",
        "  if_icmple L_addu8_ok"
      ]
    <> makeNullaryCellLines (ptOverflowError ptags)
    <> ["  astore_2"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "  aload_2"
    <> [ "  areturn",
         "L_addu8_ok:",
         "  iconst_2",
         "  anewarray java/lang/Object",
         "  dup",
         "  iconst_0"
       ]
    <> boxedTagLines (ptRight ptags)
    <> [ "  aastore",
         "  dup",
         "  iconst_1",
         "  iload_2",
         "  invokestatic java/lang/Integer/valueOf(I)Ljava/lang/Integer;",
         "  aastore",
         "  areturn",
         ".end method",
         ""
       ]

-- subInt32: Int32 -> Int32 -> Either (UnderflowError | OverflowError) Int32.
--   Promote both operands to long, subtract, then range-check the result.
--   ArithError tags follow declaration order: Underflow=0, Overflow=1.
--   Mirrors 'addInt32Method' with 'lsub' replacing 'ladd'.
subInt32Method :: PreludeTags -> Text
subInt32Method ptags =
  T.intercalate "\n"
    $ [ ".method static __subInt32(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
        "  .limit stack 6",
        "  .limit locals 3",
        "  aload_0",
        "  checkcast java/lang/Integer",
        "  invokevirtual java/lang/Integer/intValue()I",
        "  i2l",
        "  aload_1",
        "  checkcast java/lang/Integer",
        "  invokevirtual java/lang/Integer/intValue()I",
        "  i2l",
        "  lsub",
        "  dup2",
        "  ldc2_w 2147483647",
        "  lcmp",
        "  ifgt L_subi32_over",
        "  dup2",
        "  ldc2_w -2147483648",
        "  lcmp",
        "  iflt L_subi32_under",
        "  l2i",
        "  invokestatic java/lang/Integer/valueOf(I)Ljava/lang/Integer;",
        "  astore_2",
        "  iconst_2",
        "  anewarray java/lang/Object",
        "  dup",
        "  iconst_0"
      ]
    <> boxedTagLines (ptRight ptags)
    <> [ "  aastore",
         "  dup",
         "  iconst_1",
         "  aload_2",
         "  aastore",
         "  areturn",
         "L_subi32_over:",
         "  pop2"
       ]
    <> makeNullaryCellLines (ptOverflowError ptags)
    <> ["  astore_2"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "  aload_2"
    <> [ "  areturn",
         "L_subi32_under:",
         "  pop2"
       ]
    <> makeNullaryCellLines (ptUnderflowError ptags)
    <> ["  astore_2"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "  aload_2"
    <> [ "  areturn",
         ".end method",
         ""
       ]

-- mulInt32: Int32 -> Int32 -> Either ArithError Int32.
--   Promote both operands to long, multiply at long width, then range-
--   check the result against [-2147483648, 2147483647] with 'lcmp'.
--   Direction (over vs under): same-sign overflow is positive, opposite-
--   sign is negative — read off `(a ^ b) >= 0`. Slot 2 holds @a@ for
--   the direction split on the err path; slot 3 holds the boxed result
--   on the ok path / boxed AE on the err paths. Mirrors 'addInt32Method'
--   with 'lmul' (0x69) replacing 'ladd'.
mulInt32Method :: PreludeTags -> Text
mulInt32Method ptags =
  T.intercalate "\n"
    $ [ ".method static __mulInt32(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
        "  .limit stack 6",
        "  .limit locals 4",
        "  aload_0",
        "  checkcast java/lang/Integer",
        "  invokevirtual java/lang/Integer/intValue()I",
        "  istore_2",
        "  aload_1",
        "  checkcast java/lang/Integer",
        "  invokevirtual java/lang/Integer/intValue()I",
        "  istore_3",
        "  iload_2",
        "  i2l",
        "  iload_3",
        "  i2l",
        "  lmul",
        "  dup2",
        "  ldc2_w 2147483647",
        "  lcmp",
        "  ifgt L_muli32_split",
        "  dup2",
        "  ldc2_w -2147483648",
        "  lcmp",
        "  ifge L_muli32_ok",
        "L_muli32_split:",
        "  pop2",
        "  iload_2",
        "  iload_3",
        "  ixor",
        "  iflt L_muli32_under"
      ]
    <> makeNullaryCellLines (ptOverflowError ptags)
    <> ["  astore_2"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "  aload_2"
    <> [ "  areturn",
         "L_muli32_under:"
       ]
    <> makeNullaryCellLines (ptUnderflowError ptags)
    <> ["  astore_2"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "  aload_2"
    <> [ "  areturn",
         "L_muli32_ok:",
         "  l2i",
         "  invokestatic java/lang/Integer/valueOf(I)Ljava/lang/Integer;",
         "  astore_2",
         "  iconst_2",
         "  anewarray java/lang/Object",
         "  dup",
         "  iconst_0"
       ]
    <> boxedTagLines (ptRight ptags)
    <> [ "  aastore",
         "  dup",
         "  iconst_1",
         "  aload_2",
         "  aastore",
         "  areturn",
         ".end method",
         ""
       ]

-- negInt32: Int32 -> Either OverflowError Int32.
--   Mirrors 'succInt32Method' with INT32_MIN as the boundary and 'ineg'
--   for the non-overflow branch. OverflowError is single-constructor,
--   so its tag is 0 — Left-branch encoding is identical to 'predInt32'.
negInt32Method :: PreludeTags -> Text
negInt32Method ptags =
  T.intercalate "\n"
    $ [ ".method static __negInt32(Ljava/lang/Object;)Ljava/lang/Object;",
        "  .limit stack 5",
        "  .limit locals 3",
        "  aload_0",
        "  checkcast java/lang/Integer",
        "  invokevirtual java/lang/Integer/intValue()I",
        "  istore_1",
        "  iload_1",
        "  ldc -2147483648",
        "  if_icmpne L_neg_ok"
      ]
    <> makeNullaryCellLines (ptOverflowError ptags)
    <> ["  astore_2"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "  aload_2"
    <> [ "  areturn",
         "L_neg_ok:",
         "  iconst_2",
         "  anewarray java/lang/Object",
         "  dup",
         "  iconst_0"
       ]
    <> boxedTagLines (ptRight ptags)
    <> [ "  aastore",
         "  dup",
         "  iconst_1",
         "  iload_1",
         "  ineg",
         "  invokestatic java/lang/Integer/valueOf(I)Ljava/lang/Integer;",
         "  aastore",
         "  areturn",
         ".end method",
         ""
       ]

-- subUInt8: UInt8 -> UInt8 -> Either UnderflowError UInt8.
--   Both operands are 0..255 so 'isub' produces a value in -255..255 with
--   no JVM-level overflow; one 'iflt' picks the underflow branch. On the
--   ok path the result is already a valid UInt8 — no mask needed.
subUInt8Method :: PreludeTags -> Text
subUInt8Method ptags =
  T.intercalate "\n"
    $ [ ".method static __subUInt8(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
        "  .limit stack 5",
        "  .limit locals 3",
        "  aload_0",
        "  checkcast java/lang/Integer",
        "  invokevirtual java/lang/Integer/intValue()I",
        "  aload_1",
        "  checkcast java/lang/Integer",
        "  invokevirtual java/lang/Integer/intValue()I",
        "  isub",
        "  istore_2",
        "  iload_2",
        "  iflt L_subu8_under",
        "  iconst_2",
        "  anewarray java/lang/Object",
        "  dup",
        "  iconst_0"
      ]
    <> boxedTagLines (ptRight ptags)
    <> [ "  aastore",
         "  dup",
         "  iconst_1",
         "  iload_2",
         "  invokestatic java/lang/Integer/valueOf(I)Ljava/lang/Integer;",
         "  aastore",
         "  areturn",
         "L_subu8_under:"
       ]
    <> makeNullaryCellLines (ptUnderflowError ptags)
    <> ["  astore_2"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "  aload_2"
    <> [ "  areturn",
         ".end method",
         ""
       ]

-- mulUInt8: UInt8 -> UInt8 -> Either OverflowError UInt8.
--   Both operands are 0..255 so 'imul' produces a value in 0..65025 with
--   no JVM-level overflow (i32 fits the full range). One 'if_icmple'
--   against 255 picks the branch — same shape as 'addUInt8Method' with
--   'imul' replacing 'iadd'. No mask on the ok path since the product
--   is already a valid UInt8 by construction.
mulUInt8Method :: PreludeTags -> Text
mulUInt8Method ptags =
  T.intercalate "\n"
    $ [ ".method static __mulUInt8(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
        "  .limit stack 5",
        "  .limit locals 3",
        "  aload_0",
        "  checkcast java/lang/Integer",
        "  invokevirtual java/lang/Integer/intValue()I",
        "  aload_1",
        "  checkcast java/lang/Integer",
        "  invokevirtual java/lang/Integer/intValue()I",
        "  imul",
        "  istore_2",
        "  iload_2",
        "  sipush 255",
        "  if_icmple L_mulu8_ok"
      ]
    <> makeNullaryCellLines (ptOverflowError ptags)
    <> ["  astore_2"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "  aload_2"
    <> [ "  areturn",
         "L_mulu8_ok:",
         "  iconst_2",
         "  anewarray java/lang/Object",
         "  dup",
         "  iconst_0"
       ]
    <> boxedTagLines (ptRight ptags)
    <> [ "  aastore",
         "  dup",
         "  iconst_1",
         "  iload_2",
         "  invokestatic java/lang/Integer/valueOf(I)Ljava/lang/Integer;",
         "  aastore",
         "  areturn",
         ".end method",
         ""
       ]

-- showUInt32: UInt32 -> String. JVM int is signed 32-bit, so values
--   2^31..2^32-1 would render as negative via 'Integer.toString'.
--   'Integer.toUnsignedString' (Java 8+, on our Java 11 floor) prints
--   the unsigned decimal directly.
showUInt32Method :: Text
showUInt32Method =
  unlines
    [ ".method static __showUInt32(Ljava/lang/Object;)Ljava/lang/Object;",
      "  .limit stack 1",
      "  .limit locals 1",
      "  aload_0",
      "  checkcast java/lang/Integer",
      "  invokevirtual java/lang/Integer/intValue()I",
      "  invokestatic java/lang/Integer/toUnsignedString(I)Ljava/lang/String;",
      "  areturn",
      ".end method"
    ]

-- predUInt32: UInt32 -> Either UnderflowError UInt32. The boundary check
--   is also against 0 (same as 'predUInt8'), so the body is structurally
--   identical to predUInt8Method — only the labels are renamed to keep
--   both methods in one class without label collision.
predUInt32Method :: PreludeTags -> Text
predUInt32Method ptags =
  T.intercalate "\n"
    $ [ ".method static __predUInt32(Ljava/lang/Object;)Ljava/lang/Object;",
        "  .limit stack 5",
        "  .limit locals 3",
        "  aload_0",
        "  checkcast java/lang/Integer",
        "  invokevirtual java/lang/Integer/intValue()I",
        "  istore_1",
        "  iload_1",
        "  ifne L_predu32_ok"
      ]
    <> makeNullaryCellLines (ptUnderflowError ptags)
    <> ["  astore_2"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "  aload_2"
    <> [ "  areturn",
         "L_predu32_ok:",
         "  iconst_2",
         "  anewarray java/lang/Object",
         "  dup",
         "  iconst_0"
       ]
    <> boxedTagLines (ptRight ptags)
    <> [ "  aastore",
         "  dup",
         "  iconst_1",
         "  iload_1",
         "  iconst_1",
         "  isub",
         "  invokestatic java/lang/Integer/valueOf(I)Ljava/lang/Integer;",
         "  aastore",
         "  areturn",
         ".end method",
         ""
       ]

-- succUInt32: UInt32 -> Either OverflowError UInt32. Boundary 4294967295
--   is encoded as @iconst_m1@ — identical bit pattern when stored as
--   signed i32. On the ok path '(v + 1)' wraps modulo 2^32, but since
--   we already checked v != 4294967295, the result is in 1..4294967295
--   (no wrap).
succUInt32Method :: PreludeTags -> Text
succUInt32Method ptags =
  T.intercalate "\n"
    $ [ ".method static __succUInt32(Ljava/lang/Object;)Ljava/lang/Object;",
        "  .limit stack 5",
        "  .limit locals 3",
        "  aload_0",
        "  checkcast java/lang/Integer",
        "  invokevirtual java/lang/Integer/intValue()I",
        "  istore_1",
        "  iload_1",
        "  iconst_m1",
        "  if_icmpne L_succu32_ok"
      ]
    <> makeNullaryCellLines (ptOverflowError ptags)
    <> ["  astore_2"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "  aload_2"
    <> [ "  areturn",
         "L_succu32_ok:",
         "  iconst_2",
         "  anewarray java/lang/Object",
         "  dup",
         "  iconst_0"
       ]
    <> boxedTagLines (ptRight ptags)
    <> [ "  aastore",
         "  dup",
         "  iconst_1",
         "  iload_1",
         "  iconst_1",
         "  iadd",
         "  invokestatic java/lang/Integer/valueOf(I)Ljava/lang/Integer;",
         "  aastore",
         "  areturn",
         ".end method",
         ""
       ]

-- addUInt32: UInt32 -> UInt32 -> Either OverflowError UInt32. Promote
--   both operands to unsigned long via 'Integer.toUnsignedLong' (Java
--   8+, on our Java 11 floor); the sum lives in [0, 2^33-2].
--   'Long.compareUnsigned' against 4294967295 names the boundary check
--   directly. The l2i on the ok path keeps the low 32 bits — exactly
--   the in-range u32 result.
addUInt32Method :: PreludeTags -> Text
addUInt32Method ptags =
  T.intercalate "\n"
    $ [ ".method static __addUInt32(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
        "  .limit stack 6",
        "  .limit locals 3",
        "  aload_0",
        "  checkcast java/lang/Integer",
        "  invokevirtual java/lang/Integer/intValue()I",
        "  invokestatic java/lang/Integer/toUnsignedLong(I)J",
        "  aload_1",
        "  checkcast java/lang/Integer",
        "  invokevirtual java/lang/Integer/intValue()I",
        "  invokestatic java/lang/Integer/toUnsignedLong(I)J",
        "  ladd",
        "  dup2",
        "  ldc2_w 4294967295",
        "  invokestatic java/lang/Long/compareUnsigned(JJ)I",
        "  ifgt L_addu32_over",
        "  l2i",
        "  invokestatic java/lang/Integer/valueOf(I)Ljava/lang/Integer;",
        "  astore_2",
        "  iconst_2",
        "  anewarray java/lang/Object",
        "  dup",
        "  iconst_0"
      ]
    <> boxedTagLines (ptRight ptags)
    <> [ "  aastore",
         "  dup",
         "  iconst_1",
         "  aload_2",
         "  aastore",
         "  areturn",
         "L_addu32_over:",
         "  pop2"
       ]
    <> makeNullaryCellLines (ptOverflowError ptags)
    <> ["  astore_2"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "  aload_2"
    <> [ "  areturn",
         ".end method",
         ""
       ]

-- subUInt32: UInt32 -> UInt32 -> Either UnderflowError UInt32. Compare
--   @a < b@ as unsigned via 'Integer.compareUnsigned' (Java 8+, on our
--   Java 11 floor) — negative result means underflow. On the ok path
--   @isub@ at int width gives the correct u32 difference (bit pattern
--   of @a - b mod 2^32@ equals @a - b@ when @a >= b@ in unsigned).
subUInt32Method :: PreludeTags -> Text
subUInt32Method ptags =
  T.intercalate "\n"
    $ [ ".method static __subUInt32(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
        "  .limit stack 4",
        "  .limit locals 5",
        "  aload_0",
        "  checkcast java/lang/Integer",
        "  invokevirtual java/lang/Integer/intValue()I",
        "  istore_2",
        "  aload_1",
        "  checkcast java/lang/Integer",
        "  invokevirtual java/lang/Integer/intValue()I",
        "  istore_3",
        "  iload_2",
        "  iload_3",
        "  invokestatic java/lang/Integer/compareUnsigned(II)I",
        "  iflt L_subu32_under",
        "  iload_2",
        "  iload_3",
        "  isub",
        "  invokestatic java/lang/Integer/valueOf(I)Ljava/lang/Integer;",
        "  astore 4",
        "  iconst_2",
        "  anewarray java/lang/Object",
        "  dup",
        "  iconst_0"
      ]
    <> boxedTagLines (ptRight ptags)
    <> [ "  aastore",
         "  dup",
         "  iconst_1",
         "  aload 4",
         "  aastore",
         "  areturn",
         "L_subu32_under:"
       ]
    <> makeNullaryCellLines (ptUnderflowError ptags)
    <> ["  astore 4"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "  aload 4"
    <> [ "  areturn",
         ".end method",
         ""
       ]

-- mulUInt32: UInt32 -> UInt32 -> Either OverflowError UInt32. The
--   product of two u32 values is in [0, (2^32-1)^2 ≈ 2^64-2^33+1]; this
--   exceeds @Long.MAX_VALUE@, so signed 'lcmp' against 4294967295L
--   would misclassify some overflowing products as in-range.
--   'Long.compareUnsigned' (Java 8+, on our Java 11 floor) compares the
--   product to the u32 boundary correctly across the full u64 range.
--   Both operands are widened via 'Integer.toUnsignedLong'.
mulUInt32Method :: PreludeTags -> Text
mulUInt32Method ptags =
  T.intercalate "\n"
    $ [ ".method static __mulUInt32(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
        "  .limit stack 6",
        "  .limit locals 4",
        "  aload_0",
        "  checkcast java/lang/Integer",
        "  invokevirtual java/lang/Integer/intValue()I",
        "  invokestatic java/lang/Integer/toUnsignedLong(I)J",
        "  aload_1",
        "  checkcast java/lang/Integer",
        "  invokevirtual java/lang/Integer/intValue()I",
        "  invokestatic java/lang/Integer/toUnsignedLong(I)J",
        "  lmul",
        "  lstore_2",
        "  lload_2",
        "  ldc2_w 4294967295",
        "  invokestatic java/lang/Long/compareUnsigned(JJ)I",
        "  ifgt L_mulu32_over",
        "  lload_2",
        "  l2i",
        "  invokestatic java/lang/Integer/valueOf(I)Ljava/lang/Integer;",
        "  astore_2",
        "  iconst_2",
        "  anewarray java/lang/Object",
        "  dup",
        "  iconst_0"
      ]
    <> boxedTagLines (ptRight ptags)
    <> [ "  aastore",
         "  dup",
         "  iconst_1",
         "  aload_2",
         "  aastore",
         "  areturn",
         "L_mulu32_over:"
       ]
    <> makeNullaryCellLines (ptOverflowError ptags)
    <> ["  astore_2"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "  aload_2"
    <> [ "  areturn",
         ".end method",
         ""
       ]

-- parseUInt32: String -> Either ParseError UInt32. Same shape as
--   'parseUInt8Method' minus the sign handling, with a long accumulator
--   (max running magnitude is 4294967295 * 10 + 9 = 42949672959 — fits
--   in long-signed). On the ok path l2i takes the low 32 bits, which
--   are the correct u32 bit pattern.
parseUInt32Method :: PreludeTags -> Text
parseUInt32Method ptags =
  T.intercalate "\n"
    $ [ ".method static __parseUInt32(Ljava/lang/Object;)Ljava/lang/Object;",
        "  .limit stack 5",
        "  .limit locals 8",
        "  aload_0",
        "  checkcast java/lang/String",
        "  astore_1",
        "  aload_1",
        "  invokevirtual java/lang/String/length()I",
        "  istore_2",
        "  iload_2",
        "  ifeq L_parseUInt32_fail",
        "  iconst_0",
        "  istore_3",
        "  lconst_0",
        "  lstore 4",
        "L_parseUInt32_loop:",
        "  iload_3",
        "  iload_2",
        "  if_icmpge L_parseUInt32_ok",
        "  aload_1",
        "  iload_3",
        "  invokevirtual java/lang/String/charAt(I)C",
        "  istore 6",
        "  iload 6",
        "  bipush 48",
        "  if_icmplt L_parseUInt32_fail",
        "  iload 6",
        "  bipush 57",
        "  if_icmpgt L_parseUInt32_fail",
        "  lload 4",
        "  bipush 10",
        "  i2l",
        "  lmul",
        "  iload 6",
        "  bipush 48",
        "  isub",
        "  i2l",
        "  ladd",
        "  lstore 4",
        "  lload 4",
        "  ldc2_w 4294967295",
        "  lcmp",
        "  ifgt L_parseUInt32_fail",
        "  iinc 3 1",
        "  goto L_parseUInt32_loop",
        "L_parseUInt32_ok:",
        "  iconst_2",
        "  anewarray java/lang/Object",
        "  dup",
        "  iconst_0"
      ]
    <> boxedTagLines (ptRight ptags)
    <> [ "  aastore",
         "  dup",
         "  iconst_1",
         "  lload 4",
         "  l2i",
         "  invokestatic java/lang/Integer/valueOf(I)Ljava/lang/Integer;",
         "  aastore",
         "  areturn",
         "L_parseUInt32_fail:"
       ]
    <> makeNullaryCellLines (ptParseError ptags)
    <> ["  astore 4"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "  aload 4"
    <> [ "  areturn",
         ".end method",
         ""
       ]

-- splitOnFirst: String -> String -> Maybe (Tuple2 String String).
--   Defers substring search to 'String.indexOf(String)', which returns -1
--   on miss and 0 on empty 'sep' — both behaviours match the prelude
--   contract directly. On hit, 'String.substring' allocates fresh
--   String objects (not aliased into the input), then we wrap them in
--   Tuple2 (Object[3], tag 0) inside Just (Object[2], tag 1). On miss
--   we return Nothing (Object[1], tag 0).
splitOnFirstMethod :: PreludeTags -> Text
splitOnFirstMethod ptags =
  T.intercalate "\n"
    $ [ ".method static __splitOnFirst(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
        "  .limit stack 5",
        "  .limit locals 4",
        "  aload_1",
        "  checkcast java/lang/String",
        "  aload_0",
        "  checkcast java/lang/String",
        "  invokevirtual java/lang/String/indexOf(Ljava/lang/String;)I",
        "  istore_2",
        "  iload_2",
        "  iconst_m1",
        "  if_icmpne L_split_found"
      ]
    <> makeNullaryCellLines (ptNothing ptags)
    <> [ "  areturn",
         "L_split_found:",
         "  aload_1",
         "  checkcast java/lang/String",
         "  iconst_0",
         "  iload_2",
         "  invokevirtual java/lang/String/substring(II)Ljava/lang/String;",
         "  astore_3",
         "  aload_1",
         "  checkcast java/lang/String",
         "  iload_2",
         "  aload_0",
         "  checkcast java/lang/String",
         "  invokevirtual java/lang/String/length()I",
         "  iadd",
         "  invokevirtual java/lang/String/substring(I)Ljava/lang/String;",
         "  astore_2",
         "  iconst_3",
         "  anewarray java/lang/Object",
         "  dup",
         "  iconst_0"
       ]
    <> boxedTagLines (ptTuple2 ptags)
    <> [ "  aastore",
         "  dup",
         "  iconst_1",
         "  aload_3",
         "  aastore",
         "  dup",
         "  iconst_2",
         "  aload_2",
         "  aastore",
         "  astore_3",
         "  iconst_2",
         "  anewarray java/lang/Object",
         "  dup",
         "  iconst_0"
       ]
    <> boxedTagLines (ptJust ptags)
    <> [ "  aastore",
         "  dup",
         "  iconst_1",
         "  aload_3",
         "  aastore",
         "  areturn",
         ".end method",
         ""
       ]

-- lengthCodePoints: String -> UInt32. 'String.codePointCount(0, length())'
--   walks the UTF-16 buffer once and counts surrogate pairs as one
--   codepoint, matching the prelude contract.
lengthCodePointsMethod :: Text
lengthCodePointsMethod =
  unlines
    [ ".method static __lengthCodePoints(Ljava/lang/Object;)Ljava/lang/Object;",
      "  .limit stack 3",
      "  .limit locals 2",
      "  aload_0",
      "  checkcast java/lang/String",
      "  astore_1",
      "  aload_1",
      "  iconst_0",
      "  aload_1",
      "  invokevirtual java/lang/String/length()I",
      "  invokevirtual java/lang/String/codePointCount(II)I",
      "  invokestatic java/lang/Integer/valueOf(I)Ljava/lang/Integer;",
      "  areturn",
      ".end method"
    ]

-- lengthUtf16CodeUnits: String -> UInt32. JVM strings are UTF-16
--   internally, so 'String.length()' is exactly the code-unit count.
lengthUtf16CodeUnitsMethod :: Text
lengthUtf16CodeUnitsMethod =
  unlines
    [ ".method static __lengthUtf16CodeUnits(Ljava/lang/Object;)Ljava/lang/Object;",
      "  .limit stack 2",
      "  .limit locals 1",
      "  aload_0",
      "  checkcast java/lang/String",
      "  invokevirtual java/lang/String/length()I",
      "  invokestatic java/lang/Integer/valueOf(I)Ljava/lang/Integer;",
      "  areturn",
      ".end method"
    ]

-- lengthUtf8Bytes: String -> UInt32. 'String.getBytes(StandardCharsets.UTF_8)'
--   produces standard (not modified) UTF-8 — supplementary characters
--   come out as four bytes, not six. The intermediate byte array is
--   discarded; if profiling ever flags this, a manual pass over the
--   chars summing 1/2/3/4-byte contributions per code point would
--   avoid it.
lengthUtf8BytesMethod :: Text
lengthUtf8BytesMethod =
  unlines
    [ ".method static __lengthUtf8Bytes(Ljava/lang/Object;)Ljava/lang/Object;",
      "  .limit stack 2",
      "  .limit locals 1",
      "  aload_0",
      "  checkcast java/lang/String",
      "  getstatic java/nio/charset/StandardCharsets/UTF_8 Ljava/nio/charset/Charset;",
      "  invokevirtual java/lang/String/getBytes(Ljava/nio/charset/Charset;)[B",
      "  arraylength",
      "  invokestatic java/lang/Integer/valueOf(I)Ljava/lang/Integer;",
      "  areturn",
      ".end method"
    ]

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
  T.intercalate "\n"
    $ [ ".method static __parseInt32(Ljava/lang/Object;)Ljava/lang/Object;",
        "  .limit stack 5",
        "  .limit locals 8",
        "  aload_0",
        "  checkcast java/lang/String",
        "  astore_1",
        "  aload_1",
        "  invokevirtual java/lang/String/length()I",
        "  istore_2",
        "  iload_2",
        "  ifeq L_parseInt32_fail",
        "  iconst_0",
        "  istore_3",
        "  iconst_0",
        "  istore 4",
        "  aload_1",
        "  iconst_0",
        "  invokevirtual java/lang/String/charAt(I)C",
        "  bipush 45",
        "  if_icmpne L_parseInt32_init_acc",
        "  iconst_1",
        "  istore 4",
        "  iconst_1",
        "  istore_3",
        "  iload_2",
        "  iconst_1",
        "  if_icmpeq L_parseInt32_fail",
        "L_parseInt32_init_acc:",
        "  lconst_0",
        "  lstore 5",
        "L_parseInt32_loop:",
        "  iload_3",
        "  iload_2",
        "  if_icmpge L_parseInt32_after_loop",
        "  aload_1",
        "  iload_3",
        "  invokevirtual java/lang/String/charAt(I)C",
        "  istore 7",
        "  iload 7",
        "  bipush 48",
        "  if_icmplt L_parseInt32_fail",
        "  iload 7",
        "  bipush 57",
        "  if_icmpgt L_parseInt32_fail",
        "  lload 5",
        "  bipush 10",
        "  i2l",
        "  lmul",
        "  iload 7",
        "  bipush 48",
        "  isub",
        "  i2l",
        "  ladd",
        "  lstore 5",
        "  lload 5",
        "  ldc2_w 2147483648",
        "  lcmp",
        "  ifgt L_parseInt32_fail",
        "  iinc 3 1",
        "  goto L_parseInt32_loop",
        "L_parseInt32_after_loop:",
        "  iload 4",
        "  ifeq L_parseInt32_pos_check",
        "  lload 5",
        "  lneg",
        "  lstore 5",
        "  goto L_parseInt32_build_right",
        "L_parseInt32_pos_check:",
        "  lload 5",
        "  ldc 2147483647",
        "  i2l",
        "  lcmp",
        "  ifgt L_parseInt32_fail",
        "L_parseInt32_build_right:",
        "  iconst_2",
        "  anewarray java/lang/Object",
        "  dup",
        "  iconst_0"
      ]
    <> boxedTagLines (ptRight ptags)
    <> [ "  aastore",
         "  dup",
         "  iconst_1",
         "  lload 5",
         "  l2i",
         "  invokestatic java/lang/Integer/valueOf(I)Ljava/lang/Integer;",
         "  aastore",
         "  areturn",
         "L_parseInt32_fail:"
       ]
    <> makeNullaryCellLines (ptParseError ptags)
    <> ["  astore 4"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "  aload 4"
    <> [ "  areturn",
         ".end method",
         ""
       ]

-- parseUInt8: String -> Either ParseError UInt8.
--   Same shape as 'parseInt32Method' minus the sign handling — UInt8
--   does not represent a negative number — and with an i32 accumulator,
--   since the running magnitude never exceeds 2559 (255 * 10 + 9) before
--   the `> 255` check triggers a fail.
parseUInt8Method :: PreludeTags -> Text
parseUInt8Method ptags =
  T.intercalate "\n"
    $ [ ".method static __parseUInt8(Ljava/lang/Object;)Ljava/lang/Object;",
        "  .limit stack 4",
        "  .limit locals 6",
        "  aload_0",
        "  checkcast java/lang/String",
        "  astore_1",
        "  aload_1",
        "  invokevirtual java/lang/String/length()I",
        "  istore_2",
        "  iload_2",
        "  ifeq L_parseUInt8_fail",
        "  iconst_0",
        "  istore_3",
        "  iconst_0",
        "  istore 4",
        "L_parseUInt8_loop:",
        "  iload_3",
        "  iload_2",
        "  if_icmpge L_parseUInt8_ok",
        "  aload_1",
        "  iload_3",
        "  invokevirtual java/lang/String/charAt(I)C",
        "  istore 5",
        "  iload 5",
        "  bipush 48",
        "  if_icmplt L_parseUInt8_fail",
        "  iload 5",
        "  bipush 57",
        "  if_icmpgt L_parseUInt8_fail",
        "  iload 4",
        "  bipush 10",
        "  imul",
        "  iload 5",
        "  bipush 48",
        "  isub",
        "  iadd",
        "  istore 4",
        "  iload 4",
        "  sipush 255",
        "  if_icmpgt L_parseUInt8_fail",
        "  iinc 3 1",
        "  goto L_parseUInt8_loop",
        "L_parseUInt8_ok:",
        "  iconst_2",
        "  anewarray java/lang/Object",
        "  dup",
        "  iconst_0"
      ]
    <> boxedTagLines (ptRight ptags)
    <> [ "  aastore",
         "  dup",
         "  iconst_1",
         "  iload 4",
         "  invokestatic java/lang/Integer/valueOf(I)Ljava/lang/Integer;",
         "  aastore",
         "  areturn",
         "L_parseUInt8_fail:"
       ]
    <> makeNullaryCellLines (ptParseError ptags)
    <> ["  astore 4"]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "  aload 4"
    <> [ "  areturn",
         ".end method",
         ""
       ]

-- | __entryArgEither: wraps argv[1] in 'Either (StringTooLong |
--   UnpairedUtf16Surrogate) String' for the user's 'main'. Two checks:
--     1. Length cap: 'String.length()' is UTF-16 code units (O(1) on
--        JVM), compared to 'maxStringLengthUtf16CodeUnits' (2^27).
--     2. Surrogate pairing: walk code units; high surrogate (D800..DBFF)
--        must be immediately followed by a low surrogate (DC00..DFFF).
--        Standalone or trailing high → 'Left UnpairedUtf16Surrogate'.
--   Cap-check has priority — it short-circuits before the surrogate
--   walk runs. Cap value and FNV-1a row tags for "StringTooLong" /
--   "UnpairedUtf16Surrogate" must stay in sync with
--   'maxStringLengthUtf16CodeUnits' in 'stdlib/Prelude.aww' and the
--   matching constants in 'Awsum.Codegen.{LLVM,CLR,WASM,JS}'. Row tags
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
  T.intercalate "\n"
    $ [ ".method static __entryArgEither(Ljava/lang/Object;)Ljava/lang/Object;",
        "  .limit stack 6",
        "  .limit locals 8",
        "  aload_0",
        "  checkcast java/lang/String",
        "  astore_1",
        "  aload_1",
        "  invokevirtual java/lang/String/length()I",
        "  istore_2",
        -- maxStringLengthUtf16CodeUnits = 134217728 (= 2^27). Cap-check first.
        "  iload_2",
        "  ldc 134217728",
        "  if_icmpgt L_entry_too_long",
        -- Surrogate scan: walk UTF-16 code units, ensure pairing.
        "  iconst_0",
        "  istore_3",
        "  iconst_0",
        "  istore 4",
        "L_entry_scan:",
        "  iload_3",
        "  iload_2",
        "  if_icmpge L_entry_scan_done",
        "  aload_1",
        "  iload_3",
        "  invokevirtual java/lang/String/charAt(I)C",
        -- Mask top 6 bits: surrogate range U+D800..U+DFFF shares prefix,
        -- with bit 10 distinguishing high (0) from low (1).
        "  ldc 64512", -- 0xFC00
        "  iand",
        "  istore 5",
        "  iload 4",
        "  ifne L_entry_check_low",
        -- !expecting_low: standalone low → fail; high → set flag; else nothing.
        "  iload 5",
        "  ldc 56320", -- 0xDC00
        "  if_icmpeq L_entry_unpaired",
        "  iload 5",
        "  ldc 55296", -- 0xD800
        "  if_icmpne L_entry_inc",
        "  iconst_1",
        "  istore 4",
        "  goto L_entry_inc",
        "L_entry_check_low:",
        -- expecting_low: must be low surrogate; else fail.
        "  iload 5",
        "  ldc 56320", -- 0xDC00
        "  if_icmpne L_entry_unpaired",
        "  iconst_0",
        "  istore 4",
        "  goto L_entry_inc",
        "L_entry_inc:",
        "  iinc 3 1",
        "  goto L_entry_scan",
        "L_entry_scan_done:",
        -- Trailing high surrogate (last code unit was high, no low followed).
        "  iload 4",
        "  ifne L_entry_unpaired",
        -- Right(input): Object[2] = [Integer(rightTag), input]
        "  iconst_2",
        "  anewarray java/lang/Object",
        "  dup",
        "  iconst_0"
      ]
    <> boxedTagLines (ptRight ptags)
    -- Right(input): Object[2] = [Integer(rightTag), input]
    <> [ "  aastore",
         "  dup",
         "  iconst_1",
         "  aload_0",
         "  aastore",
         "  areturn",
         "L_entry_too_long:"
       ]
    -- inner: StringTooLong CCon — Object[1] = [Integer(stl)]
    <> makeNullaryCellLines (ptStringTooLong ptags)
    -- row: CRow — Object[2] = [Integer(stringTooLongRowTag), inner]
    <> [ "  astore 6",
         "  iconst_2",
         "  anewarray java/lang/Object",
         "  dup",
         "  iconst_0",
         "  ldc " <> stringTooLongRowTagText,
         "  invokestatic java/lang/Integer/valueOf(I)Ljava/lang/Integer;",
         "  aastore",
         "  dup",
         "  iconst_1",
         "  aload 6",
         "  aastore",
         "  astore 7"
       ]
    -- left: Either Left — Object[2] = [Integer(left), row]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "  aload 7"
    <> [ "  areturn",
         "L_entry_unpaired:"
       ]
    -- inner: UnpairedUtf16Surrogate CCon — Object[1] = [Integer(us)]
    <> makeNullaryCellLines (ptUnpairedUtf16Surrogate ptags)
    -- row: CRow — Object[2] = [Integer(unpairedSurrogateRowTag), inner]
    <> [ "  astore 6",
         "  iconst_2",
         "  anewarray java/lang/Object",
         "  dup",
         "  iconst_0",
         "  ldc " <> unpairedSurrogateRowTagText,
         "  invokestatic java/lang/Integer/valueOf(I)Ljava/lang/Integer;",
         "  aastore",
         "  dup",
         "  iconst_1",
         "  aload 6",
         "  aastore",
         "  astore 7"
       ]
    -- left: Either Left — Object[2] = [Integer(left), row]
    <> makeUnaryCellFromLocalLines (ptLeft ptags) "  aload 7"
    <> [ "  areturn",
         ".end method",
         ""
       ]
  where
    stringTooLongRowTagText :: Text
    stringTooLongRowTagText = show (fromIntegral (rowTag (TyCon noSpan "StringTooLong")) :: Int32)
    unpairedSurrogateRowTagText :: Text
    unpairedSurrogateRowTagText = show (fromIntegral (rowTag (TyCon noSpan "UnpairedUtf16Surrogate")) :: Int32)

-- | __getArgs: zero-arg helper for 'BuiltIn.internalGetArgs', called
--   from 'runIO''s 'IOGetArgs' arm. Reads the cached argv[0] from the
--   "awsum.argv0" system property (set in 'mainMethod' above) and
--   routes it through '__entryArgEither' for the strict-UTF-16
--   validation. Per the no-memoisation decision each call returns a
--   fresh 'Either' cell; argv is invariant during execution so repeat
--   calls are deterministically equal.
getArgsMethod :: Text
getArgsMethod =
  unlines
    [ ".method static __getArgs()" <> objDesc,
      "  .limit stack 2",
      "  .limit locals 1",
      "  ldc \"awsum.argv0\"",
      "  invokestatic java/lang/System/getProperty(Ljava/lang/String;)Ljava/lang/String;",
      "  invokestatic AwsumMain/__entryArgEither(" <> objDesc <> ")" <> objDesc,
      "  areturn",
      ".end method"
    ]

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
  unlines
    [ ".method static __stdinReadAll()" <> objDesc,
      "  .limit stack 4",
      "  .limit locals 3",
      "  new java/io/ByteArrayOutputStream",
      "  dup",
      "  invokespecial java/io/ByteArrayOutputStream/<init>()V",
      "  astore_0",
      "  sipush 8192",
      "  newarray byte",
      "  astore_1",
      "L_stdin_loop:",
      "  getstatic java/lang/System/in Ljava/io/InputStream;",
      "  aload_1",
      "  iconst_0",
      "  sipush 8192",
      "  invokevirtual java/io/InputStream/read([BII)I",
      "  istore_2",
      "  iload_2",
      "  ifle L_stdin_done",
      "  aload_0",
      "  aload_1",
      "  iconst_0",
      "  iload_2",
      "  invokevirtual java/io/ByteArrayOutputStream/write([BII)V",
      "  goto L_stdin_loop",
      "L_stdin_done:",
      "  aload_0",
      "  invokevirtual java/io/ByteArrayOutputStream/toByteArray()[B",
      "  astore_1",
      "  new java/lang/String",
      "  dup",
      "  aload_1",
      "  getstatic java/nio/charset/StandardCharsets/UTF_8 Ljava/nio/charset/Charset;",
      "  invokespecial java/lang/String/<init>([BLjava/nio/charset/Charset;)V",
      "  invokestatic AwsumMain/__entryArgEither(" <> objDesc <> ")" <> objDesc,
      "  areturn",
      ".end method"
    ]

mainMethod :: Text
mainMethod =
  unlines
    [ ".method public static main([Ljava/lang/String;)V",
      -- Force System.out to UTF-8 before any user code runs. JVM startup
      -- bakes the host's default charset into the original PrintStream
      -- wrapping FileDescriptor.out, so on Windows with a non-UTF-8 ANSI
      -- code page (the usual case) every supplementary code point printed
      -- by 'IO.Stdout.print' would arrive at stdout as "??" — one '?' per
      -- UTF-16 code unit. 'System.setOut' replaces the static field
      -- behind 'java.lang.System.out' for everyone in the process,
      -- including our own '__print' helper which reads it via 'getstatic'.
      "  new java/io/PrintStream",
      "  dup",
      "  new java/io/FileOutputStream",
      "  dup",
      "  getstatic java/io/FileDescriptor/out Ljava/io/FileDescriptor;",
      "  invokespecial java/io/FileOutputStream/<init>(Ljava/io/FileDescriptor;)V",
      "  iconst_1",
      -- The Charset-taking PrintStream constructor was added in Java 18;
      -- the String-encoding form has been there since Java 5, so we go
      -- through that. UTF-8 is always supported, so the
      -- UnsupportedEncodingException declared on the constructor never
      -- fires and the JVM verifier is happy without a throws clause.
      "  ldc \"UTF-8\"",
      "  invokespecial java/io/PrintStream/<init>(Ljava/io/OutputStream;ZLjava/lang/String;)V",
      "  invokestatic java/lang/System/setOut(Ljava/io/PrintStream;)V",
      "  aload_0",
      "  arraylength",
      "  iconst_1",
      "  if_icmpge has_arg",
      "  ldc \"\"",
      "  goto call_main",
      "has_arg:",
      "  aload_0",
      "  iconst_0",
      "  aaload",
      "call_main:",
      -- Cache argv[0] for 'BuiltIn.internalGetArgs' (called from
      -- 'runIO''s 'IOGetArgs' arm). 'main' itself takes no arguments
      -- (its signature is 'IO Never Unit'); user code reads argv via
      -- 'IO.Args.getArgs' inside the IO chain. Argv is invariant for
      -- the JVM process lifetime, so one 'setProperty' at entry is
      -- enough; '__getArgs' below reads the same key. The 'aaload'
      -- above returned Object; cast to String for the
      -- 'setProperty(String, String)' signature.
      "  checkcast java/lang/String",
      "  ldc \"awsum.argv0\"",
      "  swap",
      "  invokestatic java/lang/System/setProperty(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;",
      "  pop",
      -- v_main is a zero-arg value (CValDef): build the IO tree.
      "  invokestatic AwsumMain/" <> mangle "main" <> "()" <> objDesc,
      -- Hand the IO tree to `runIO`, which walks it and performs the
      -- effects via `BuiltIn.internalStdoutPrint`. `runIO` returns
      -- Unit (the IOPure terminator's payload); we discard it.
      "  invokestatic AwsumMain/" <> mangle "runIO" <> "(" <> objDesc <> ")" <> objDesc,
      "  pop",
      "  return",
      ".end method"
    ]

-- ════════════════════════════════════════════════════════════════════════════
-- User declarations
-- ════════════════════════════════════════════════════════════════════════════

emitDecl :: Ctx -> CDecl -> Text
emitDecl ctx = \case
  -- TCO-wrapped body. JVM method parameters already sit in local slots
  -- 0..n-1 and are mutable via @astore@, so a 'CContinue' evaluates its
  -- new values onto the operand stack, pops them back into the param
  -- slots (reverse order — stack is LIFO), and @goto@s the method's
  -- first instruction labelled @L_tco_loop@. Every real return path
  -- ends with its own @areturn@; no fallthrough @areturn@ is emitted.
  CFunDef nm args (CLoop body) ->
    let paramCtx = Map.fromList (zip args [0 ..])
        desc = objMethodDescText (length args)
        bodyText = emitTailText ctx paramCtx args body
     in unlines
          [ ".method static " <> mangle nm <> desc,
            "L_tco_loop:",
            bodyText,
            ".end method"
          ]
  CFunDef nm args body ->
    let paramCtx = Map.fromList (zip args [0 ..])
        desc = objMethodDescText (length args)
        bodyText = emitExprText ctx paramCtx body
     in unlines
          [ ".method static " <> mangle nm <> desc,
            bodyText,
            "  areturn",
            ".end method"
          ]
  CValDef nm rhs ->
    let bodyText = emitExprText ctx Map.empty rhs
     in unlines
          [ ".method static " <> mangle nm <> "()" <> objDesc,
            bodyText,
            "  areturn",
            ".end method"
          ]

-- ════════════════════════════════════════════════════════════════════════════
-- Expression emission (text)
-- ════════════════════════════════════════════════════════════════════════════

emitExprText :: Ctx -> Map Text Int -> CExpr -> Text
emitExprText ctx paramMap = \case
  CString s ->
    "  ldc " <> show s
  CVar n
    | Just slot <- Map.lookup n paramMap ->
        "  aload" <> aloadSuffix slot
    | n `Set.member` ctx.cValDefs ->
        "  invokestatic AwsumMain/" <> mangle n <> "()" <> objDesc
    | n `Set.member` ctx.cFunDefs ->
        let arity = fromMaybe 0 (Map.lookup n ctx.cArities)
         in "  ldc [MethodHandle REF_invokeStatic AwsumMain." <> mangle n <> objMethodDescText arity <> "]"
    | otherwise ->
        "  aconst_null"
  CBuiltIn _ ->
    "  aconst_null" -- invariant: not a standalone term; dispatched from CCall
  CIntLit n _ ->
    -- Same representation as the binary assembler: push int and box via Integer.valueOf.
    T.intercalate
      "\n"
      [ emitIconstBig (fromInteger n :: Int32),
        "  invokestatic java/lang/Integer/valueOf(I)Ljava/lang/Integer;"
      ]
  CCon tag fields ->
    let nSlots = 1 + length fields
        storeTag =
          [ "  dup",
            emitIconst 0,
            emitIconst tag,
            "  invokestatic java/lang/Integer/valueOf(I)Ljava/lang/Integer;",
            "  aastore"
          ]
        storeFields =
          [ "  dup\n" <> emitIconst (i :: Int) <> "\n" <> emitExprText ctx paramMap fld <> "\n  aastore"
          | (fld, i) <- zip fields [1 ..]
          ]
     in T.intercalate "\n"
          $ [emitIconst nSlots, "  anewarray java/lang/Object"]
          <> storeTag
          <> storeFields
  -- Row injection / dispatch: delegate to CCon / CCase.
  CRow tag v -> emitExprText ctx paramMap (CCon (fromIntegral tag) [v])
  CRowCase scrut alts ->
    emitExprText ctx paramMap (CCase scrut [(fromIntegral t, [v], b) | (t, v, b) <- alts])
  CCase scrut alts ->
    let sorted = sortWith (\(t, _, _) -> t) alts
        scrutText = emitExprText ctx paramMap scrut
        -- Extract tag: arr[0] → unbox Integer → int
        extractTag =
          T.intercalate
            "\n"
            [ "  dup",
              emitIconst 0,
              "  aaload",
              "  checkcast java/lang/Integer",
              "  invokevirtual java/lang/Integer/intValue()I"
            ]
        armLabels = ["L_arm_" <> show tag | (tag, _, _) <- sorted]
        joinLabel :: Text
        joinLabel = "L_join"
        switchText =
          "  lookupswitch"
            <> T.concat ["\n    " <> show tag <> ": " <> lbl | ((tag, _, _), lbl) <- zip sorted armLabels]
            <> "\n    default: "
            <> fromMaybe "L_default" (viaNonEmpty head armLabels)
        nextSlot = foldl' max (-1) (Map.elems paramMap) + 1
        -- Each arm: store bound vars to locals, pop array, emit body
        emitArm (_, vars, body) lbl =
          let bindings = zip vars [nextSlot ..]
              storeCode =
                T.concat
                  [ "  dup\n" <> emitIconst (i :: Int) <> "\n  aaload\n  astore" <> astoreSuffix slot <> "\n"
                  | ((_, slot), i) <- zip bindings [1 :: Int ..]
                  ]
              paramMap' = foldl' (\m (v, slot) -> Map.insert v slot m) paramMap bindings
           in lbl <> ":\n" <> storeCode <> "  pop\n" <> emitExprText ctx paramMap' body <> "\n  goto " <> joinLabel
        armTexts = [emitArm alt lbl | (alt, lbl) <- zip sorted armLabels]
     in T.intercalate "\n"
          $ [scrutText, extractTag, switchText]
          <> armTexts
          <> [joinLabel <> ":"]
  CCall f xs ->
    case f of
      -- Internal print primitive used by the prelude's `runIO`.
      -- Emits the same `__print` invocation the legacy
      -- `IO.Stdout.print` arm used to call directly.
      CBuiltIn "internalStdoutPrint"
        | [x] <- xs ->
            T.intercalate
              "\n"
              [ emitExprText ctx paramMap x,
                "  invokestatic AwsumMain/__print(Ljava/lang/Object;)Ljava/lang/Object;"
              ]
      -- Zero-arg primitive driving 'runIO''s 'IOGetArgs' arm: re-reads
      -- the cached argv[0] (stashed at entry via System.setProperty)
      -- and wraps it in 'Either (StringTooLong | UnpairedUtf16Surrogate)
      -- String' via '__entryArgEither'.
      CBuiltIn "internalGetArgs"
        | [] <- xs -> "  invokestatic AwsumMain/__getArgs()" <> objDesc
      -- Zero-arg primitive driving 'runIO''s 'IOStdinReadAll' arm:
      -- consumes 'System.in' to EOF and wraps the decoded contents in
      -- 'Either (StringTooLong | UnpairedUtf16Surrogate) String' via
      -- '__stdinReadAll'.
      CBuiltIn "internalStdinReadAllAsUtf16"
        | [] <- xs -> "  invokestatic AwsumMain/__stdinReadAll()" <> objDesc
      CBuiltIn name
        | name == "showInt32" || name == "showUInt8",
          [x] <- xs ->
            T.intercalate
              "\n"
              [ emitExprText ctx paramMap x,
                "  checkcast java/lang/Integer",
                "  invokevirtual java/lang/Integer/toString()Ljava/lang/String;"
              ]
      CBuiltIn "showUInt32"
        | [x] <- xs ->
            T.intercalate
              "\n"
              [ emitExprText ctx paramMap x,
                "  invokestatic AwsumMain/__showUInt32(Ljava/lang/Object;)Ljava/lang/Object;"
              ]
      CBuiltIn "predInt32"
        | [x] <- xs ->
            T.intercalate
              "\n"
              [ emitExprText ctx paramMap x,
                "  invokestatic AwsumMain/__predInt32(Ljava/lang/Object;)Ljava/lang/Object;"
              ]
      CBuiltIn "predUInt8"
        | [x] <- xs ->
            T.intercalate
              "\n"
              [ emitExprText ctx paramMap x,
                "  invokestatic AwsumMain/__predUInt8(Ljava/lang/Object;)Ljava/lang/Object;"
              ]
      CBuiltIn "predUInt32"
        | [x] <- xs ->
            T.intercalate
              "\n"
              [ emitExprText ctx paramMap x,
                "  invokestatic AwsumMain/__predUInt32(Ljava/lang/Object;)Ljava/lang/Object;"
              ]
      CBuiltIn "succInt32"
        | [x] <- xs ->
            T.intercalate
              "\n"
              [ emitExprText ctx paramMap x,
                "  invokestatic AwsumMain/__succInt32(Ljava/lang/Object;)Ljava/lang/Object;"
              ]
      CBuiltIn "succUInt8"
        | [x] <- xs ->
            T.intercalate
              "\n"
              [ emitExprText ctx paramMap x,
                "  invokestatic AwsumMain/__succUInt8(Ljava/lang/Object;)Ljava/lang/Object;"
              ]
      CBuiltIn "succUInt32"
        | [x] <- xs ->
            T.intercalate
              "\n"
              [ emitExprText ctx paramMap x,
                "  invokestatic AwsumMain/__succUInt32(Ljava/lang/Object;)Ljava/lang/Object;"
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
                  [ emitExprText ctx paramMap a,
                    emitExprText ctx paramMap b,
                    "  invokestatic AwsumMain/" <> fn <> "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"
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
                  [ emitExprText ctx paramMap a,
                    emitExprText ctx paramMap b,
                    "  invokestatic AwsumMain/" <> fn <> "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"
                  ]
      CBuiltIn "negInt32"
        | [x] <- xs ->
            T.intercalate
              "\n"
              [ emitExprText ctx paramMap x,
                "  invokestatic AwsumMain/__negInt32(Ljava/lang/Object;)Ljava/lang/Object;"
              ]
      CBuiltIn "concatString"
        | [a, b] <- xs ->
            T.intercalate
              "\n"
              [ emitExprText ctx paramMap a,
                emitExprText ctx paramMap b,
                "  invokestatic AwsumMain/__concat(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"
              ]
      CBuiltIn "splitOnFirst"
        | [a, b] <- xs ->
            T.intercalate
              "\n"
              [ emitExprText ctx paramMap a,
                emitExprText ctx paramMap b,
                "  invokestatic AwsumMain/__splitOnFirst(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"
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
                  [ emitExprText ctx paramMap x,
                    "  invokestatic AwsumMain/" <> fn <> "(Ljava/lang/Object;)Ljava/lang/Object;"
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
                  [ emitExprText ctx paramMap x,
                    "  invokestatic AwsumMain/" <> fn <> "(Ljava/lang/Object;)Ljava/lang/Object;"
                  ]
      CBuiltIn n ->
        error ("JVM codegen: unknown builtin '" <> n <> "' reached CCall (typecheck should have rejected it)")
      CVar n
        | n `Set.member` ctx.cFunDefs ->
            let argTexts = map (emitExprText ctx paramMap) xs
                desc = objMethodDescText (length xs)
             in T.intercalate "\n"
                  $ argTexts
                  <> ["  invokestatic AwsumMain/" <> mangle n <> desc]
      _ ->
        let fText = emitExprText ctx paramMap f
            argTexts = map (emitExprText ctx paramMap) xs
            desc = objMethodDescText (length xs)
         in T.intercalate "\n"
              $ [fText, "  checkcast java/lang/invoke/MethodHandle"]
              <> argTexts
              <> ["  invokevirtual java/lang/invoke/MethodHandle/invoke" <> desc]
  CLoop _ -> error "JVM codegen: CLoop reached emitExprText (non-tail position)"
  CContinue _ -> error "JVM codegen: CContinue reached emitExprText (non-tail position)"
  -- Liveness annotation; backend treats as a transparent wrapper
  -- since the managed GC handles reclaim (null-assignment is the
  -- early-root-snip equivalent).
  CDrop _ _ body -> emitExprText ctx paramMap body
  -- Cell reuse. In-place mutation of the existing
  -- 'Object[]' at slot of @n@: write tag at index 0, fields at
  -- indices 1..k via 'aastore'. No fresh 'anewarray' — the JIT
  -- can hoist the still-allocated array out of repeated young-gen
  -- pressure. Net stack: leaves the reused array on the operand
  -- stack, identical shape to 'CCon'.
  --
  -- Invariant from 'Awsum.Reuse.rewriteFirstCCon': @length fields@
  -- equals the matched arm's pattern arity, so the array already
  -- has at least @1 + length fields@ slots.
  CReuse n tag fields ->
    let slot =
          fromMaybe (error $ "JVM codegen: CReuse on unknown binder " <> show n)
            $ Map.lookup n paramMap
        -- 'aload' pushes 'java/lang/Object'; 'aastore' wants
        -- '[Ljava/lang/Object;', so insert a 'checkcast' as in CCase.
        loadCell = "  aload" <> aloadSuffix slot <> "\n  checkcast [Ljava/lang/Object;"
        storeTag =
          [ "  dup",
            emitIconst 0,
            emitIconst tag,
            "  invokestatic java/lang/Integer/valueOf(I)Ljava/lang/Integer;",
            "  aastore"
          ]
        storeFields =
          [ "  dup\n" <> emitIconst (i :: Int) <> "\n" <> emitExprText ctx paramMap fld <> "\n  aastore"
          | (fld, i) <- zip fields [1 ..]
          ]
     in T.intercalate "\n"
          $ [loadCell]
          <> storeTag
          <> storeFields

-- | Emit @body@ in tail position under @L_tco_loop:@. 'CContinue'
-- evaluates new argument values onto the operand stack (so old reads of
-- a parameter still see the old value), pops them into the parameter
-- locals in reverse (LIFO stack), and @goto L_tco_loop@. Any other tail
-- shape evaluates a value and ends with @areturn@. 'CCase' chains via
-- @lookupswitch@ where each arm self-terminates — no @goto L_join@.
-- 'CDrop' wrappers accumulate as a 'pending' stack. At every
-- terminator the stack drains as @aconst_null; astore <slot>@
-- sequences — one per dropped binder. On a 'CContinue' the drains
-- land between the buffered arg evaluations and the param @astore@s
-- (operand stack net-effect zero per drain, so the buffered values are
-- still on top in order). On a value-producing tail they land between
-- the result computation and @areturn@. All Awsum heap values are
-- @Object[]@ references on the JVM, so the slots are reference-typed
-- and @astore@ is always legal; no per-kind dispatch is needed.
emitTailText :: Ctx -> Map Text Int -> [Text] -> CExpr -> Text
emitTailText ctx paramMap params = go paramMap []
  where
    go :: Map Text Int -> [Text] -> CExpr -> Text
    go pmap pending = \case
      CContinue newArgs ->
        let evals = T.intercalate "\n" [emitExprText ctx pmap a | a <- newArgs]
            frees =
              T.intercalate
                "\n"
                [ "  aconst_null\n  astore" <> astoreSuffix s
                | n <- pending,
                  Just s <- [binderSlot pmap n]
                ]
            astores =
              T.intercalate
                "\n"
                [ "  astore" <> astoreSuffix (paramSlot p)
                | p <- reverse params
                ]
            sep s = if T.null s then "" else s <> "\n"
         in evals <> "\n" <> sep frees <> astores <> "\n  goto L_tco_loop"
      CCase scrut alts ->
        let sorted = sortWith (\(t, _, _) -> t) alts
            scrutText = emitExprText ctx pmap scrut
            extractTag =
              T.intercalate
                "\n"
                [ "  dup",
                  emitIconst 0,
                  "  aaload",
                  "  checkcast java/lang/Integer",
                  "  invokevirtual java/lang/Integer/intValue()I"
                ]
            armLabels = ["L_tco_arm_" <> show tag | (tag, _, _) <- sorted]
            switchText =
              "  lookupswitch"
                <> T.concat ["\n    " <> show tag <> ": " <> lbl | ((tag, _, _), lbl) <- zip sorted armLabels]
                <> "\n    default: "
                <> fromMaybe "L_tco_default" (viaNonEmpty head armLabels)
            nextSlot = foldl' max (-1) (Map.elems pmap) + 1
            emitArm (_, vars, armBody) lbl =
              let bindings = zip vars [nextSlot ..]
                  storeCode =
                    T.concat
                      [ "  dup\n" <> emitIconst (i :: Int) <> "\n  aaload\n  astore" <> astoreSuffix slot <> "\n"
                      | ((_, slot), i) <- zip bindings [1 :: Int ..]
                      ]
                  pmap' = foldl' (\m (v, slot) -> Map.insert v slot m) pmap bindings
               in lbl <> ":\n" <> storeCode <> "  pop\n" <> go pmap' pending armBody
            armTexts = [emitArm alt lbl | (alt, lbl) <- zip sorted armLabels]
         in T.intercalate "\n"
              $ [scrutText, extractTag, switchText]
              <> armTexts
      -- Push the drop onto 'pending'; drain at the next terminator.
      CDrop _ n body -> go pmap (n : pending) body
      other ->
        let valText = emitExprText ctx pmap other
            frees =
              T.intercalate
                "\n"
                [ "  aconst_null\n  astore" <> astoreSuffix s
                | n <- pending,
                  Just s <- [binderSlot pmap n]
                ]
            sep s = if T.null s then "" else s <> "\n"
         in valText <> "\n" <> sep frees <> "  areturn"

    paramSlot :: Text -> Int
    paramSlot p =
      fromMaybe (error $ "JVM codegen: no slot for param " <> show p) (Map.lookup p paramMap)

    -- Arm-binder CDrops may come through 'pending' before
    -- 'pmap' has the binder (corner cases in tail-case emission).
    -- Returning @Nothing@ skips emit — managed GC handles the
    -- block-scoped slot naturally.
    binderSlot :: Map Text Int -> Text -> Maybe Int
    binderSlot pmap n = Map.lookup n pmap

emitIconst :: Int -> Text
emitIconst n
  | n >= 0 && n <= 5 = "  iconst_" <> show n
  | n >= -128 && n <= 127 = "  bipush " <> show n
  | otherwise = "  sipush " <> show n

-- | Textual form of 'bcLoadInt32' from the binary assembler: any Int32 value
--   using the compact instruction that fits. Values outside the sipush range
--   become 'ldc' on a CPInteger — we render that as @ldc N@ and trust the
--   reader (snapshot) to know the pool has the entry (the binary path adds
--   it explicitly).
emitIconstBig :: Int32 -> Text
emitIconstBig n
  | n >= -32768 && n <= 32767 = emitIconst (fromIntegral n)
  | otherwise = "  ldc " <> show n

-- ════════════════════════════════════════════════════════════════════════════
-- Helpers
-- ════════════════════════════════════════════════════════════════════════════

mangle :: Text -> Text
mangle t =
  let ok c = Char.isAlphaNum c || c == '_' || c == '\''
      body = T.map (\c -> if ok c then c else '_') t
   in "v_" <> body

objDesc :: Text
objDesc = "Ljava/lang/Object;"

objMethodDescText :: Int -> Text
objMethodDescText n =
  "(" <> T.replicate n objDesc <> ")" <> objDesc

aloadSuffix :: Int -> Text
aloadSuffix n
  | n <= 3 = "_" <> show n
  | otherwise = " " <> show n

astoreSuffix :: Int -> Text
astoreSuffix n
  | n <= 3 = "_" <> show n
  | otherwise = " " <> show n
