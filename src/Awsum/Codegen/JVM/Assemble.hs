-- | JVM .class file assembler for Awsum 'Core'.
--
-- Generates a single @AwsumMain.class@ file (class version 55.0, Java 11+)
-- containing runtime helpers, user declarations, and a @main(String[])@
-- entry point.
--
-- All values are @java\/lang\/Object@; strings are @java\/lang\/String@;
-- function references are @java\/lang\/invoke\/MethodHandle@; @IO Unit@ is @null@.
module Awsum.Codegen.JVM.Assemble (assembleJVM, JvmLimitExceeded (..), renderJvmLimitExceeded, jvmU2Max, methodLimitViolations, selectLimit, userJvmMethods, JvmModule (..), jvmModule, jvmModuleMethods) where

import Awsum.Codegen.JVM.Instr (ClassRef (..), FieldRef (..), Frame (..), JvmInstr (..), JvmMethod (..), LabelId (..), MethodRef (..), VType (..), addInt32Spec, addUInt32Spec, addUInt8Spec, concatSpec, entryArgEitherSpec, eqSpec, eqStringSpec, getArgsSpec, lengthCodePointsSpec, lengthUtf16CodeUnitsSpec, lengthUtf8BytesSpec, mainSpec, methodMaxLocals, methodMaxStack, mulInt32Spec, mulUInt32Spec, mulUInt8Spec, negInt32Spec, parseInt32Spec, parseUInt32Spec, parseUInt8Spec, predInt32Spec, predUInt32Spec, predUInt8Spec, printSpec, showUInt32Spec, splitOnFirstSpec, stdinDecodeStrictSpec, stdinReadAllBytesSpec, stdinReadAllSpec, subInt32Spec, subUInt32Spec, subUInt8Spec, succInt32Spec, succUInt32Spec, succUInt8Spec)
import Awsum.Codegen.Mangle (mangle)
import Awsum.Codegen.ReuseSchedule (ReuseStore (..), reuseSlotElided, scheduleReuse)
import Awsum.Core
import Awsum.HM (rowTag)
import Awsum.Syntax (Type' (..), noSpan)
import Data.Bits qualified as Bits
import Data.ByteString qualified as BS
import Data.ByteString.Builder qualified as B
import Data.Char qualified as Char
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Relude

-- ════════════════════════════════════════════════════════════════════════════
-- Public API
-- ════════════════════════════════════════════════════════════════════════════

-- | The JVM caps a method's @Code@ attribute at 65535 bytes (@code_length@,
--   JVM Spec §4.7.3). A larger method yields a class the JVM rejects at load
--   time, so we refuse it at compile time instead — a per-target compile-time
--   limit (see docs/targets.md). The other four targets impose no such cap and
--   are deliberately not restricted to match.
jvmMaxMethodCodeBytes :: Int
jvmMaxMethodCodeBytes = 65535

-- | Several class-file fields are u2 (16-bit) and so cap their value at 65535:
--   @constant_pool_count@ (§4.1), a method's @max_stack@ / @max_locals@
--   (§4.7.3), and each @CONSTANT_Utf8_info@ @length@ (§4.4.7). A value past this
--   wraps on write and silently corrupts the @.class@, which the JVM then
--   rejects at load with @ClassFormatError@; we refuse the program at compile
--   time instead — the same discipline as 'jvmMaxMethodCodeBytes'. The other
--   four backends have no comparable limit and are deliberately not restricted.
jvmU2Max :: Int
jvmU2Max = 65535

-- | A JVM class-file limit a program would overflow. Each variant maps to a
--   field that cannot represent the program — a u2 field, or for
--   'JvmMethodTooLarge' the spec-bounded @code_length@. 'assembleJVM' reports
--   the highest-priority one ('selectLimit') rather than emitting a @.class@ the
--   JVM would reject at load; 'renderJvmLimitExceeded' explains it.
data JvmLimitExceeded
  = -- | A method's assembled @Code@ exceeds 'jvmMaxMethodCodeBytes' (§4.7.3):
    --   method name, actual byte size.
    JvmMethodTooLarge Text Int
  | -- | More constant-pool entries than @constant_pool_count@ (u2) can address
    --   (§4.1): the required count.
    JvmConstantPoolOverflow Int
  | -- | A single @CONSTANT_Utf8_info@ longer than its u2 @length@ field (§4.4.7)
    --   — in practice a function with an extreme parameter count, whose method
    --   descriptor is the over-long string: a short preview, the byte length.
    JvmConstantTooLong Text Int
  | -- | A method needing more than 'jvmU2Max' @max_stack@ slots (§4.7.3):
    --   method name, the value.
    JvmMaxStackTooLarge Text Int
  | -- | A method needing more than 'jvmU2Max' @max_locals@ slots (§4.7.3):
    --   method name, the value.
    JvmMaxLocalsTooLarge Text Int
  deriving stock (Eq, Show)

-- | Lower number = reported first when a program crosses several limits at once
--   (a high-arity function trips both its descriptor's Utf8 length and
--   @max_locals@; we surface the descriptor, the actionable cause). Code-length
--   and Utf8 length are concrete per-method causes; the pool count is
--   whole-program; @max_stack@ / @max_locals@ are bounded by code / descriptor
--   length and so are only ever reached alongside one of the above — they rank
--   last.
limitPriority :: JvmLimitExceeded -> Int
limitPriority = \case
  JvmMethodTooLarge {} -> 0
  JvmConstantTooLong {} -> 1
  JvmConstantPoolOverflow {} -> 2
  JvmMaxStackTooLarge {} -> 3
  JvmMaxLocalsTooLarge {} -> 4

-- | The limit to report from those a program exceeds: the highest-priority
--   ('limitPriority'), ties broken by encounter order ('sortOn' is stable).
--   'Nothing' means no limit was crossed.
selectLimit :: [JvmLimitExceeded] -> Maybe JvmLimitExceeded
selectLimit = viaNonEmpty head . sortOn limitPriority

-- | Every u2 limit a single method's computed figures cross — the one source of
--   truth shared by 'assembleMethod' and its test. @code_length@ uses
--   'jvmMaxMethodCodeBytes' (a u4 field the spec still caps at 65535);
--   @max_stack@ / @max_locals@ use 'jvmU2Max'.
methodLimitViolations :: Text -> Int -> Int -> Int -> [JvmLimitExceeded]
methodLimitViolations name codeLen maxStack maxLocals =
  [JvmMethodTooLarge name codeLen | codeLen > jvmMaxMethodCodeBytes]
    <> [JvmMaxStackTooLarge name maxStack | maxStack > jvmU2Max]
    <> [JvmMaxLocalsTooLarge name maxLocals | maxLocals > jvmU2Max]

-- | Render a 'JvmLimitExceeded' as the build-time error the user sees. For an
--   over-large method, name the method (and, for a compiler-synthesised @$scc$@
--   \/ @$cps$@ function no user wrote, one line on where it came from); for the
--   whole-class limits, state the limit and the figure that crossed it. Long
--   synthesised names and string previews are abbreviated.
renderJvmLimitExceeded :: JvmLimitExceeded -> Text
renderJvmLimitExceeded = \case
  JvmMethodTooLarge name n ->
    let synthetic = any (`T.isPrefixOf` name) ["$scc$", "$cps$", "$apply$"]
        subject
          | synthetic = "synthetic method `" <> abbreviate name <> "`"
          | otherwise = "function `" <> abbreviate name <> "`"
        provenance
          | "$scc$" `T.isPrefixOf` name =
              " (`$scc$…` is one function the compiler fuses from a mutual-recursion group to keep it stack-safe.)"
          | "$cps$" `T.isPrefixOf` name || "$apply$" `T.isPrefixOf` name =
              " (`$cps$…` is the continuation-passing form the compiler synthesises to make non-tail recursion stack-safe.)"
          | otherwise = ""
     in "JVM target — "
          <> subject
          <> " compiles to "
          <> show n
          <> " bytes, over the JVM's hard limit of 65535 bytes per method."
          <> provenance
          <> cantBuild
  JvmConstantPoolOverflow count ->
    "JVM target — this program needs "
      <> show count
      <> " constant-pool entries, over the JVM's hard limit of 65535 (constant_pool_count is a 16-bit field, JVM Spec §4.1)."
      <> cantBuild
  JvmConstantTooLong preview n ->
    "JVM target — a constant-pool string entry is "
      <> show n
      <> " bytes, over the JVM's hard limit of 65535 bytes per entry (CONSTANT_Utf8_info length is a 16-bit field, JVM Spec §4.4.7): `"
      <> abbreviate preview
      <> "`. This is almost always a function with an extreme number of parameters."
      <> cantBuild
  JvmMaxStackTooLarge name n ->
    "JVM target — method `"
      <> abbreviate name
      <> "` needs "
      <> show n
      <> " operand-stack slots, over the JVM's hard limit of 65535 (max_stack is a 16-bit field, JVM Spec §4.7.3)."
      <> cantBuild
  JvmMaxLocalsTooLarge name n ->
    "JVM target — method `"
      <> abbreviate name
      <> "` needs "
      <> show n
      <> " local-variable slots, over the JVM's hard limit of 65535 (max_locals is a 16-bit field, JVM Spec §4.7.3)."
      <> cantBuild
  where
    cantBuild :: Text
    cantBuild = " This program can't be built for the JVM target."
    abbreviate t
      | T.length t <= 48 = t
      | otherwise = T.take 47 t <> "…"

-- | Produce a complete .class file as a strict ByteString, unless the program
--   crosses one of the JVM's class-file limits ('JvmLimitExceeded') — a method
--   over the bytecode ceiling, or a u2 field (constant-pool count, a method's
--   @max_stack@ / @max_locals@, a single Utf8 entry's length) that cannot
--   represent it — in which case the program is refused for this target.
assembleJVM :: PreludeTags -> CoreProgram -> Either JvmLimitExceeded BS.ByteString
assembleJVM ptags prog =
  let (methods, finalSt) = runState (doAssemble prog) (emptyPool ptags)
      argvFieldNameIdx = fromMaybe (error "assembleJVM: missing __argv name") (Map.lookup (KUtf8 "__argv") finalSt.cache)
      argvFieldDescIdx = fromMaybe (error "assembleJVM: missing __argv descriptor") (Map.lookup (KUtf8 "[Ljava/lang/String;") finalSt.cache)
      -- Per-method limits, read from the assembled methods (outside the State —
      -- see 'assembleMethod'): code_length, max_stack, max_locals.
      methodViolations =
        concatMap (\mi -> methodLimitViolations mi.miName (length mi.mCode) mi.mMaxStack mi.mMaxLocals) methods
      -- Whole-class u2 limits, read from the final pool — faithful even though
      -- 'nextIdx' wraps, because the entry-list length never does:
      -- 'constant_pool_count' is the entry count + 1, and each
      -- 'CONSTANT_Utf8_info' length must fit its own u2 field.
      poolCount = length finalSt.entries + 1
      poolViolation = [JvmConstantPoolOverflow poolCount | poolCount > jvmU2Max]
      utf8Violations =
        [ JvmConstantTooLong (utf8Preview bs) (BS.length bs)
        | CPUtf8 bs <- finalSt.entries,
          BS.length bs > jvmU2Max
        ]
   in case selectLimit (methodViolations <> poolViolation <> utf8Violations) of
        Just v -> Left v
        Nothing -> Right (toStrict (B.toLazyByteString (buildClassFile finalSt argvFieldNameIdx argvFieldDescIdx methods)))

-- | A short, printable preview of a (modified-UTF-8) constant-pool string for a
--   diagnostic. The over-long entries are method descriptors / names, which are
--   ASCII, so decoding the leading bytes leniently reproduces them.
utf8Preview :: ByteString -> Text
utf8Preview = decodeUtf8 . BS.take 48

-- ════════════════════════════════════════════════════════════════════════════
-- Constant pool types
-- ════════════════════════════════════════════════════════════════════════════

data CPEntry
  = CPUtf8 ByteString
  | CPInteger Int32
  | CPString Word16
  | CPClass Word16
  | CPNameAndType Word16 Word16
  | CPFieldref Word16 Word16
  | CPMethodref Word16 Word16
  | CPMethodHandle Word8 Word16
  | CPMethodType Word16

data CPKey
  = KUtf8 Text
  | KInteger Int32
  | KString Text
  | KClass Text
  | KNaT Text Text
  | KFieldref Text Text Text
  | KMethodref Text Text Text
  | KMethodHandle Word8 Text Text Text
  | KMethodType Text
  deriving stock (Eq, Ord)

data Pool = Pool
  { entries :: [CPEntry], -- reverse order
    nextIdx :: Word16,
    cache :: Map CPKey Word16,
    -- | Globally-unique constructor tags for prelude types, threaded
    -- in through 'assembleJVM' so that runtime helpers built here
    -- match the user's user-side 'CCon' / 'CCase' encoding.
    poolTags :: PreludeTags,
    -- | Monotonic counter for generating unique 'LabelId's in the
    -- unified user-code emitter ('emitExprI'). Labels only need to be
    -- unique within one 'JvmMethod' body, but a global counter trivially
    -- guarantees that.
    labelCtr :: Int
  }

emptyPool :: PreludeTags -> Pool
emptyPool ptags = Pool {entries = [], nextIdx = 1, cache = Map.empty, poolTags = ptags, labelCtr = 0}

-- | A fresh, unique 'LabelId' with the given prefix (e.g. @"L_case"@).
freshLabel :: Text -> AsmM LabelId
freshLabel prefix = do
  n <- gets labelCtr
  modify (\p -> p {labelCtr = n + 1})
  pure (LabelId (prefix <> show n))

type AsmM = State Pool

-- | Read the 'PreludeTags' record threaded through 'AsmM'. The
-- constructor-tag fields ('ptLeft', 'ptRight', 'ptUnderflowError',
-- ...) are needed every time a runtime helper builds a CCon-shaped
-- value out of band of user code.
askPreludeTags :: AsmM PreludeTags
askPreludeTags = gets poolTags

addEntry :: CPKey -> CPEntry -> AsmM Word16
addEntry key entry = do
  st <- get
  case Map.lookup key st.cache of
    Just idx -> pure idx
    Nothing -> do
      let idx = st.nextIdx
      put
        st
          { entries = entry : st.entries,
            nextIdx = idx + 1,
            cache = Map.insert key idx st.cache
          }
      pure idx

addUtf8 :: Text -> AsmM Word16
addUtf8 t = addEntry (KUtf8 t) (CPUtf8 (modifiedUtf8 t))

-- | Encode a 'Text' as JVM "modified UTF-8" (the constant-pool string
--   encoding). Differs from standard UTF-8 in two places:
--
--   * U+0000 is encoded as the two-byte sequence @C0 80@, never @00@,
--     so a NUL inside a string never terminates the constant-pool entry.
--   * Supplementary code points (U+10000..U+10FFFF) are first split into
--     a UTF-16 surrogate pair, and each surrogate is then encoded as a
--     three-byte sequence — six bytes total per supplementary codepoint,
--     not the four bytes standard UTF-8 would use.
--
--   Both deviations matter: a class file emitted with standard UTF-8
--   for these cases is rejected by the verifier as
--   @ClassFormatError: Illegal UTF8 string in constant pool@.
modifiedUtf8 :: Text -> ByteString
modifiedUtf8 = BS.pack . concatMap encChar . toString
  where
    encChar :: Char -> [Word8]
    encChar c =
      let cp = Char.ord c
       in case () of
            _
              | cp == 0x0000 -> [0xC0, 0x80]
              | cp <= 0x007F -> [fromIntegral cp]
              | cp <= 0x07FF ->
                  [ fromIntegral (0xC0 Bits..|. Bits.shiftR cp 6),
                    fromIntegral (0x80 Bits..|. (cp Bits..&. 0x3F))
                  ]
              | cp <= 0xFFFF -> threeByte cp
              | otherwise ->
                  let v = cp - 0x10000
                      hi = 0xD800 + Bits.shiftR v 10
                      lo = 0xDC00 + (v Bits..&. 0x3FF)
                   in threeByte hi <> threeByte lo
    threeByte cp =
      [ fromIntegral (0xE0 Bits..|. Bits.shiftR cp 12),
        fromIntegral (0x80 Bits..|. (Bits.shiftR cp 6 Bits..&. 0x3F)),
        fromIntegral (0x80 Bits..|. (cp Bits..&. 0x3F))
      ]

addInt :: Int32 -> AsmM Word16
addInt n = addEntry (KInteger n) (CPInteger n)

addClass :: Text -> AsmM Word16
addClass name = do
  ni <- addUtf8 name
  addEntry (KClass name) (CPClass ni)

addStr :: Text -> AsmM Word16
addStr s = do
  ui <- addUtf8 s
  addEntry (KString s) (CPString ui)

addNaT :: Text -> Text -> AsmM Word16
addNaT name desc = do
  ni <- addUtf8 name
  di <- addUtf8 desc
  addEntry (KNaT name desc) (CPNameAndType ni di)

addMRef :: Text -> Text -> Text -> AsmM Word16
addMRef cls name desc = do
  ci <- addClass cls
  ni <- addNaT name desc
  addEntry (KMethodref cls name desc) (CPMethodref ci ni)

addFRef :: Text -> Text -> Text -> AsmM Word16
addFRef cls name desc = do
  ci <- addClass cls
  ni <- addNaT name desc
  addEntry (KFieldref cls name desc) (CPFieldref ci ni)

hi8 :: Word16 -> Word8
hi8 w = fromIntegral (w `div` 256)

lo8 :: Word16 -> Word8
lo8 w = fromIntegral (w `mod` 256)

-- ════════════════════════════════════════════════════════════════════════════
-- Bytecode instruction helpers
-- ════════════════════════════════════════════════════════════════════════════

bcLdc :: Word16 -> [Word8]
bcLdc idx
  | idx <= 255 = [0x12, fromIntegral idx]
  | otherwise = [0x13, hi8 idx, lo8 idx]

-- For slots ≥ 256, the JVM Spec §6.5 requires the @wide@ prefix
-- (0xC4) to extend the operand to 2 bytes — the bare instruction
-- form uses an unsigned 8-bit operand and silently truncates anything
-- larger. Without @wide@, @astore 256@ encodes as @astore 0@,
-- overwriting the method parameter slot and producing
-- @ClassCastException@ / @VerifyError@ at the first use. This bites
-- on programs whose @CCase@ nesting pushes @cNextLocal@ past 255.
bcAload :: Int -> [Word8]
bcAload n
  | n <= 3 = [fromIntegral (0x2A + n)]
  | n <= 255 = [0x19, fromIntegral n]
  | otherwise = [0xC4, 0x19, hi8 (fromIntegral n :: Word16), lo8 (fromIntegral n :: Word16)]

bcAstore :: Int -> [Word8]
bcAstore n
  | n <= 3 = [fromIntegral (0x4B + n)] -- astore_0..astore_3
  | n <= 255 = [0x3A, fromIntegral n]
  | otherwise = [0xC4, 0x3A, hi8 (fromIntegral n :: Word16), lo8 (fromIntegral n :: Word16)]

bcIload :: Int -> [Word8]
bcIload n
  | n <= 3 = [fromIntegral (0x1A + n)] -- iload_0..iload_3
  | n <= 255 = [0x15, fromIntegral n]
  | otherwise = [0xC4, 0x15, hi8 (fromIntegral n :: Word16), lo8 (fromIntegral n :: Word16)]

bcIstore :: Int -> [Word8]
bcIstore n
  | n <= 3 = [fromIntegral (0x3B + n)] -- istore_0..istore_3
  | n <= 255 = [0x36, fromIntegral n]
  | otherwise = [0xC4, 0x36, hi8 (fromIntegral n :: Word16), lo8 (fromIntegral n :: Word16)]

bcLload :: Int -> [Word8]
bcLload n
  | n <= 3 = [fromIntegral (0x1E + n)] -- lload_0..lload_3
  | n <= 255 = [0x16, fromIntegral n]
  | otherwise = [0xC4, 0x16, hi8 (fromIntegral n :: Word16), lo8 (fromIntegral n :: Word16)]

bcLstore :: Int -> [Word8]
bcLstore n
  | n <= 3 = [fromIntegral (0x3F + n)] -- lstore_0..lstore_3
  | n <= 255 = [0x37, fromIntegral n]
  | otherwise = [0xC4, 0x37, hi8 (fromIntegral n :: Word16), lo8 (fromIntegral n :: Word16)]

bcInvokeStatic :: Word16 -> [Word8]
bcInvokeStatic ref = [0xB8, hi8 ref, lo8 ref]

bcInvokeVirtual :: Word16 -> [Word8]
bcInvokeVirtual ref = [0xB6, hi8 ref, lo8 ref]

bcInvokeSpecial :: Word16 -> [Word8]
bcInvokeSpecial ref = [0xB7, hi8 ref, lo8 ref]

bcCheckCast :: Word16 -> [Word8]
bcCheckCast cls = [0xC0, hi8 cls, lo8 cls]

bcGetStatic :: Word16 -> [Word8]
bcGetStatic ref = [0xB2, hi8 ref, lo8 ref]

bcIconst :: Int -> [Word8]
bcIconst n
  | n >= 0 && n <= 5 = [fromIntegral (0x03 + n)] -- iconst_0..iconst_5
  | n >= -128 && n <= 127 = [0x10, fromIntegral n] -- bipush
  | otherwise = [0x11, fromIntegral (n `div` 256), fromIntegral (n `mod` 256)] -- sipush

-- | FNV-1a 32-bit row tags for the prelude's nominal labels used by
--   the Int32 arithmetic builtins. Computed via 'rowTag' so the
--   runtime helpers stay in lockstep with 'Awsum.HM.canonicalLabel'.
--   Cast to 'Int32' so 'bcLoadInt32' / 'addInt' accept them — the bit
--   pattern survives the cast and matches what the user-side
--   'CRowCase' compares against.
underflowRowTag :: Int32
underflowRowTag = fromIntegral (rowTag (TyCon noSpan "UnderflowError"))

overflowRowTag :: Int32
overflowRowTag = fromIntegral (rowTag (TyCon noSpan "OverflowError"))

-- | StringTooLong row tag, used when the entry-point glue rejects a
--   too-long argv[1] and hands user code 'Left StringTooLong' through
--   the row '(StringTooLong | UnpairedUtf16Surrogate)'. Word32 wraps to
--   signed Int32 (CONSTANT_Integer); user-side row dispatch uses the
--   same wrapping so bit patterns match.
stringTooLongRowTag :: Int32
stringTooLongRowTag = fromIntegral (rowTag (TyCon noSpan "StringTooLong"))

-- | UnpairedUtf16Surrogate row tag, used when '__entryArgEither' detects
--   an unpaired surrogate in argv[1] (high surrogate not followed by a
--   low surrogate, standalone low, or trailing high). Word32 wraps to
--   signed Int32 the same way 'stringTooLongRowTag' does.
unpairedSurrogateRowTag :: Int32
unpairedSurrogateRowTag = fromIntegral (rowTag (TyCon noSpan "UnpairedUtf16Surrogate"))

-- | InvalidUtf8 row tag, used when '__stdinDecodeStrict' rejects malformed
--   UTF-8 read from stdin. Word32 wraps to signed Int32 the same way
--   'stringTooLongRowTag' does.
invalidUtf8RowTag :: Int32
invalidUtf8RowTag = fromIntegral (rowTag (TyCon noSpan "InvalidUtf8"))

-- | Push an arbitrary signed 32-bit integer on the stack.
--   Uses iconst/bipush/sipush for values that fit in a short, otherwise
--   loads a CPInteger from the constant pool via ldc.
bcLoadInt32 :: Int32 -> AsmM [Word8]
bcLoadInt32 n
  | n >= -32768 && n <= 32767 = pure (bcIconst (fromIntegral n))
  | otherwise = do
      idx <- addInt n
      pure (bcLdc idx)

-- ════════════════════════════════════════════════════════════════════════════
-- Method type
-- ════════════════════════════════════════════════════════════════════════════

data MInfo = MInfo
  { mFlags :: Word16,
    -- | The method's human name (e.g. @"v_main"@, @"$cps$f"@), carried so the
    -- per-method limit checks in 'assembleJVM' can name the offender; 'mName' is
    -- its constant-pool index, which a diagnostic can't render.
    miName :: Text,
    mName :: Word16,
    mDesc :: Word16,
    mCode :: [Word8],
    mCodeAttrCount :: Word16,
    mCodeAttrs :: [Word8],
    -- | Maximum operand-stack depth this method ever reaches
    -- (JVM Spec §4.7.3 max_stack). Verifier rejects methods whose
    -- actual depth exceeds the declared value. Kept as the honest 'Int':
    -- 'assembleJVM' refuses a program where it crosses 'jvmU2Max', and
    -- 'encodeMethod' truncates to the u2 field only once that is ruled out.
    mMaxStack :: Int,
    -- | Number of local variable slots this method requires
    -- (JVM Spec §4.7.3 max_locals), counting params + every additive
    -- nested 'CCase' / 'CCon' slot. The verifier rejects any
    -- StackMapTable frame whose number_of_locals exceeds this value
    -- with @bad type array size@ — that's what hardcoding it to 256
    -- was producing for deeply nested 'case' programs (depth ≥ ~250).
    -- 'Int' for the same reason as 'mMaxStack'.
    mMaxLocals :: Int
  }

-- ════════════════════════════════════════════════════════════════════════════
-- Unified instruction IR → bytes
-- ════════════════════════════════════════════════════════════════════════════

-- | Total, decision-free byte projection of one /non-branch, non-label/
--   instruction: the symbolic operand is resolved against the constant pool,
--   the opcode is fixed. Branches and labels are handled by 'assembleBody'
--   (they need the label→offset map); reaching them here is a pipeline bug.
--   The text twin is 'Awsum.Codegen.JVM.Instr.renderInstr'.
assembleInstr :: JvmInstr -> AsmM [Word8]
assembleInstr = \case
  Aload n -> pure (bcAload n)
  Astore n -> pure (bcAstore n)
  Iload n -> pure (bcIload n)
  Istore n -> pure (bcIstore n)
  Lload n -> pure (bcLload n)
  Lstore n -> pure (bcLstore n)
  PushInt n -> assemblePushInt n
  LoadInt32 n -> bcLoadInt32 n
  CheckCast (ClassRef c) -> bcCheckCast <$> addClass c
  ANewArray (ClassRef c) -> (\i -> [0xBD, hi8 i, lo8 i]) <$> addClass c
  New (ClassRef c) -> (\i -> [0xBB, hi8 i, lo8 i]) <$> addClass c
  NewArrayByte -> pure [0xBC, 0x08]
  Dup -> pure [0x59]
  Dup2 -> pure [0x5C]
  Pop2 -> pure [0x58]
  AAStore -> pure [0x53]
  IAdd -> pure [0x60]
  ISub -> pure [0x64]
  IMul -> pure [0x68]
  INeg -> pure [0x74]
  IXor -> pure [0x82]
  IAnd -> pure [0x7E]
  I2L -> pure [0x85]
  L2I -> pure [0x88]
  LConst0 -> pure [0x09]
  LConst1 -> pure [0x0A]
  LAdd -> pure [0x61]
  LSub -> pure [0x65]
  LMul -> pure [0x69]
  LNeg -> pure [0x75]
  LShl -> pure [0x79]
  LCmp -> pure [0x94]
  InvokeVirtual (MethodRef owner name desc) -> bcInvokeVirtual <$> addMRef owner name desc
  InvokeStatic (MethodRef owner name desc) -> bcInvokeStatic <$> addMRef owner name desc
  InvokeSpecial (MethodRef owner name desc) -> bcInvokeSpecial <$> addMRef owner name desc
  GetStatic (FieldRef owner name desc) -> bcGetStatic <$> addFRef owner name desc
  PutStatic (FieldRef owner name desc) -> (\r -> [0xB3, hi8 r, lo8 r]) <$> addFRef owner name desc
  LdcString s -> bcLdc <$> addStr s
  Pop -> pure [0x57]
  ArrayLength -> pure [0xBE]
  Aaload -> pure [0x32]
  Baload -> pure [0x33]
  AconstNull -> pure [0x01]
  AReturn -> pure [0xB0]
  Return -> pure [0xB1]
  Iinc slot delta -> pure [0x84, fromIntegral slot, fromIntegral delta]
  Ifeq _ -> viaBody "Ifeq"
  Ifne _ -> viaBody "Ifne"
  Iflt _ -> viaBody "Iflt"
  Ifle _ -> viaBody "Ifle"
  Ifgt _ -> viaBody "Ifgt"
  IfICmpEq _ -> viaBody "IfICmpEq"
  IfICmpNe _ -> viaBody "IfICmpNe"
  IfICmpLe _ -> viaBody "IfICmpLe"
  IfICmpLt _ -> viaBody "IfICmpLt"
  IfICmpGt _ -> viaBody "IfICmpGt"
  IfICmpGe _ -> viaBody "IfICmpGe"
  Goto _ -> viaBody "Goto"
  Label _ _ -> viaBody "Label"
  where
    viaBody opName = error ("assembleInstr: " <> opName <> " must go through assembleBody")

-- | Push an 'Int' with the tightest opcode — mirrors
--   'Awsum.Codegen.JVM.Instr.renderPushInt' exactly (so text and bytes agree):
--   @iconst_m1@ for -1, @iconst_<n>@ for 0..5, @bipush@ / @sipush@ for
--   one/two signed bytes, else @ldc@ a 'CPInteger'.
assemblePushInt :: Int -> AsmM [Word8]
assemblePushInt n
  | n == -1 = pure [0x02]
  | n >= 0 && n <= 5 = pure [fromIntegral (0x03 + n)]
  | n >= -128 && n <= 127 = pure [0x10, fromIntegral n]
  | n >= -32768 && n <= 32767 = pure (let w = fromIntegral n :: Word16 in [0x11, hi8 w, lo8 w])
  | otherwise = bcLdc <$> addInt (fromIntegral n)

-- | Assemble a 'JvmMethod' to its 'MInfo'. @max_stack@ / @max_locals@ come from
--   the shared spec — the honest verifier limits, the same values the text
--   declares. The class-file limits a method can cross
--   ('methodLimitViolations') are checked in 'assembleJVM' from the assembled
--   'MInfo' list, deliberately *not* here: forcing the figures per method inside
--   the pool-building State retains each intermediate body and turns assembly
--   quadratic, so the checks run once, after 'runState'.
assembleMethod :: JvmMethod -> AsmM MInfo
assembleMethod m = do
  ni <- addUtf8 (jmName m)
  di <- addUtf8 (jmDesc m)
  (code, attrCount, attrs) <- assembleBody (entryLocalsFromDesc (jmDesc m)) (jmBody m)
  pure
    MInfo
      { mFlags = if jmPublic m then 0x0009 else 0x0008,
        miName = jmName m,
        mName = ni,
        mDesc = di,
        mCode = code,
        mCodeAttrCount = attrCount,
        mCodeAttrs = attrs,
        mMaxStack = methodMaxStack m,
        mMaxLocals = methodMaxLocals m
      }

-- | The verifier locals at method entry, derived from the descriptor — the
--   baseline the first StackMapTable frame diffs against. Every migrated
--   helper's parameters are @java/lang/Object@, so this is one 'VObject' per
--   param; extend when a migrated method takes a non-Object parameter.
entryLocalsFromDesc :: Text -> [VType]
entryLocalsFromDesc desc =
  let paramSec = T.takeWhile (/= ')') (T.dropWhile (/= '(') desc)
   in replicate (T.count "Ljava/lang/Object;" paramSec) (VObject (ClassRef "java/lang/Object"))

-- | One item in a method body during assembly: a fixed byte run, a branch
--   whose encoding (and thus size) depends on how far its target sits, or a
--   label (zero bytes) optionally carrying a StackMapTable frame.
data Item
  = IBytes [Word8]
  | -- | opcode · is-it-an-unconditional-@goto@ · target label
    IBranch Word8 Bool LabelId
  | ILabel LabelId (Maybe Frame)

-- | Lower a method body to @(code, smtAttrCount, smtAttrBytes)@ in three steps:
--   assemble each non-branch once (keeping branches and labels symbolic), relax
--   branch widths to a fixpoint, then emit with final offsets and build the
--   StackMapTable from the final label positions. JVM short branches carry a
--   signed 16-bit offset (s2, ±32767); past that a @goto@ widens to @goto_w@
--   (s4) and a conditional is rewritten @if<¬cond> SKIP; goto_w TARGET; SKIP:@,
--   the synthesized @SKIP@ reusing the target's frame ('skipFrameFor'). When
--   nothing overflows — every method that fits comfortably in 32 KB — the bytes
--   are identical to the un-widened encoding. The one place branch offsets are
--   computed; every helper and the user-code emitter ('emitExprI') route their
--   branches and frames through it.
assembleBody :: [VType] -> [JvmInstr] -> AsmM ([Word8], Word16, [Word8])
assembleBody entryLocals body = do
  items <- traverse toItem body
  let wides = relaxBranches items
      starts = scanl' (+) 0 [itemSize wides i it | (i, it) <- zip [0 ..] items]
      withStart = zip3 [0 :: Int ..] starts items
      labelPos = Map.fromList [(l, s) | (_, s, ILabel l _) <- withStart]
      frameOf = Map.fromList [(l, f) | ILabel l (Just f) <- items]
      code = concatMap (\(i, s, it) -> emitItem labelPos wides i s it) withStart
      -- Explicit frames at branch-target labels, plus a synthesized frame at
      -- every widened conditional's @SKIP@ (its fall-through, at branch + 8).
      labelFrames = [(s, f) | (_, s, ILabel _ (Just f)) <- withStart]
      skipFrames =
        [ (s + 8, skipFrameFor frameOf tgt)
        | (i, s, IBranch _ False tgt) <- withStart,
          i `Set.member` wides
        ]
      -- Deduplicate frames at the same offset, keeping the one with the
      -- NARROWEST locals. Nested cases emit their own join 'Label' which,
      -- when the inner case is the last expression of an outer arm, lands on
      -- the same byte as the outer join; the verifier needs exactly one frame
      -- there describing the intersection of live locals across every incoming
      -- edge (the outermost, smaller frame). 'Map.fromListWith' over the offset
      -- collapses them; 'Map.elems' returns them in ascending-offset order,
      -- which is also what 'buildStackMapTable' needs.
      frames =
        Map.elems
          $ Map.fromListWith
            (\a b -> if length (frLocals (snd a)) <= length (frLocals (snd b)) then a else b)
            [(off, (off, f)) | (off, f) <- labelFrames <> skipFrames]
  if null frames
    then pure (code, 0, [])
    else do
      smtNameIdx <- addUtf8 "StackMapTable"
      classMap <- resolveFrameClasses frames
      pure (code, 1, buildStackMapTable classMap entryLocals smtNameIdx frames)

-- | Lift one 'JvmInstr' into an 'Item': branches stay symbolic (their width is
--   decided by 'relaxBranches'); every other instruction is assembled to its
--   fixed bytes now, interning constants in the pool exactly once.
toItem :: JvmInstr -> AsmM Item
toItem = \case
  Label l mframe -> pure (ILabel l mframe)
  Ifeq l -> pure (IBranch 0x99 False l)
  Ifne l -> pure (IBranch 0x9A False l)
  Iflt l -> pure (IBranch 0x9B False l)
  Ifle l -> pure (IBranch 0x9E False l)
  Ifgt l -> pure (IBranch 0x9D False l)
  IfICmpEq l -> pure (IBranch 0x9F False l)
  IfICmpNe l -> pure (IBranch 0xA0 False l)
  IfICmpLe l -> pure (IBranch 0xA4 False l)
  IfICmpLt l -> pure (IBranch 0xA1 False l)
  IfICmpGt l -> pure (IBranch 0xA3 False l)
  IfICmpGe l -> pure (IBranch 0xA2 False l)
  Goto l -> pure (IBranch 0xA7 True l)
  instr -> IBytes <$> assembleInstr instr

-- | Byte size of item @i@ under the current wide set. A narrow branch is 3
--   bytes; a wide @goto@ is @goto_w@ (5); a wide conditional is
--   @if<¬cond> (3) + goto_w (5)@ = 8.
itemSize :: Set Int -> Int -> Item -> Int
itemSize wides i = \case
  IBytes bs -> length bs
  ILabel _ _ -> 0
  IBranch _ isGoto _
    | not (i `Set.member` wides) -> 3
    | isGoto -> 5
    | otherwise -> 8

-- | Promote branches to their wide form until a fixpoint: assume all narrow,
--   compute offsets, widen every branch whose s2 offset overflows, repeat.
--   Widening only grows sizes, so the set is monotonic and the loop terminates;
--   in the common case (no overflow) it returns empty after one pass, leaving
--   every byte identical to the un-widened encoding.
relaxBranches :: [Item] -> Set Int
relaxBranches items = go Set.empty
  where
    go wides =
      let starts = scanl' (+) 0 [itemSize wides i it | (i, it) <- zip [0 ..] items]
          withStart = zip3 [0 :: Int ..] starts items
          labelPos = Map.fromList [(l, s) | (_, s, ILabel l _) <- withStart]
          newWides =
            [ i
            | (i, s, IBranch _ _ tgt) <- withStart,
              not (i `Set.member` wides),
              let off = Map.findWithDefault 0 tgt labelPos - s,
              off < -32768 || off > 32767
            ]
       in if null newWides then wides else go (foldr Set.insert wides newWides)

-- | Emit one item's bytes given the final label offsets and wide set.
emitItem :: Map LabelId Int -> Set Int -> Int -> Int -> Item -> [Word8]
emitItem labelPos wides i start = \case
  IBytes bs -> bs
  ILabel _ _ -> []
  IBranch op isGoto tgt ->
    let target = Map.findWithDefault 0 tgt labelPos
     in if not (i `Set.member` wides)
          then op : s2 (target - start)
          else
            if isGoto
              then 0xC8 : s4 (target - start) -- goto_w
              else [invertCond op, 0, 8] <> (0xC8 : s4 (target - (start + 3)))

-- | The StackMapTable frame for the synthesized @SKIP@ of a widened
--   conditional. A conditional's fall-through and its branch target share
--   verifier state in this codegen — both reached with an empty stack and the
--   same locals (the compare popped its operands and nothing is bound before
--   either edge) — so @SKIP@ reuses the target's frame. The empty-stack check
--   makes a future conditional that violates this fail loudly here rather than
--   emit a class the verifier rejects.
skipFrameFor :: Map LabelId Frame -> LabelId -> Frame
skipFrameFor frameOf tgt = case Map.lookup tgt frameOf of
  Just f
    | null (frStack f) -> f
    | otherwise -> error "assembleBody: cannot widen a conditional whose target frame has a non-empty operand stack"
  Nothing -> error "assembleBody: cannot widen a conditional whose target carries no StackMapTable frame"

-- | Big-endian signed 16-bit branch offset (narrow @goto@ / @if*@).
s2 :: Int -> [Word8]
s2 off = let w = fromIntegral off :: Word16 in [hi8 w, lo8 w]

-- | Big-endian signed 32-bit branch offset (@goto_w@).
s4 :: Int -> [Word8]
s4 off =
  let w = fromIntegral off :: Word32
   in [ fromIntegral (Bits.shiftR w 24),
        fromIntegral (Bits.shiftR w 16),
        fromIntegral (Bits.shiftR w 8),
        fromIntegral w
      ]

-- | Invert a conditional-branch opcode, to skip over the @goto_w@ when a
--   conditional's target is too far for a 16-bit offset.
invertCond :: Word8 -> Word8
invertCond = \case
  0x99 -> 0x9A -- ifeq → ifne
  0x9A -> 0x99 -- ifne → ifeq
  0x9B -> 0x9C -- iflt → ifge
  0x9C -> 0x9B -- ifge → iflt
  0x9D -> 0x9E -- ifgt → ifle
  0x9E -> 0x9D -- ifle → ifgt
  0x9F -> 0xA0 -- if_icmpeq → if_icmpne
  0xA0 -> 0x9F -- if_icmpne → if_icmpeq
  0xA1 -> 0xA2 -- if_icmplt → if_icmpge
  0xA2 -> 0xA1 -- if_icmpge → if_icmplt
  0xA3 -> 0xA4 -- if_icmpgt → if_icmple
  0xA4 -> 0xA3 -- if_icmple → if_icmpgt
  other -> error ("assembleBody.invertCond: not a conditional-branch opcode: " <> show other)

-- | Pre-resolve every 'ClassRef' that appears as a 'VObject' in a frame to its
--   CONSTANT_Class index, so the frame classifier ('buildStackMapTable') can
--   stay a pure function (all constant-pool interning happens here, up front).
resolveFrameClasses :: [(Int, Frame)] -> AsmM (Map Text Word16)
resolveFrameClasses frames = do
  let names = ordNub [c | (_, f) <- frames, VObject (ClassRef c) <- frLocals f <> frStack f]
  idxs <- traverse addClass names
  pure (Map.fromList (zip names idxs))

-- | Build the StackMapTable attribute bytes from the frame-carrying labels (in
--   bci order). Each label carries an /absolute/ 'Frame' ({locals, stack});
--   this classifies it against the previous frame (the method-entry locals for
--   the first one) into same / same-extended / same-locals-1-stack /
--   append / chop / full per JVM Spec §4.7.4 — so the frame /kind/ is derived
--   here, never chosen in the IR. @offset_delta@: the bci for the first frame,
--   @bci - prevBci - 1@ thereafter.
buildStackMapTable :: Map Text Word16 -> [VType] -> Word16 -> [(Int, Frame)] -> [Word8]
buildStackMapTable classMap entryLocals nameIdx frames =
  let entries = go entryLocals (-1) frames
      go _ _ [] = []
      go prevLocals prevBci ((bci, f) : rest) =
        frameBytes prevLocals f (fromIntegral (bci - prevBci - 1)) <> go (frLocals f) bci rest
      totalLen = fromIntegral (2 + length entries) :: Word32
   in [hi8 nameIdx, lo8 nameIdx] <> w32 totalLen <> w16 (fromIntegral (length frames)) <> entries
  where
    frameBytes :: [VType] -> Frame -> Word16 -> [Word8]
    frameBytes prevLocals (Frame locals stack) delta
      | null stack && locals == prevLocals && delta <= 63 =
          [fromIntegral delta] -- same_frame
      | null stack && locals == prevLocals =
          [251] <> w16 delta -- same_frame_extended
      | [s] <- stack,
        locals == prevLocals,
        delta <= 63 =
          [fromIntegral (64 + delta)] <> vtypeBytes s -- same_locals_1_stack_item
      | [s] <- stack,
        locals == prevLocals =
          [247] <> w16 delta <> vtypeBytes s -- ..._extended
      | null stack,
        prevLocals `isPrefixOf'` locals,
        appendK >= 1,
        appendK <= 3 =
          [fromIntegral (251 + appendK)] <> w16 delta <> concatMap vtypeBytes (drop (length prevLocals) locals) -- append
      | null stack,
        locals `isPrefixOf'` prevLocals,
        chopK >= 1,
        chopK <= 3 =
          [fromIntegral (251 - chopK)] <> w16 delta -- chop
      | otherwise =
          [255] -- full_frame
            <> w16 delta
            <> w16 (fromIntegral (length locals))
            <> concatMap vtypeBytes locals
            <> w16 (fromIntegral (length stack))
            <> concatMap vtypeBytes stack
      where
        appendK = length locals - length prevLocals
        chopK = length prevLocals - length locals
    isPrefixOf' a b = a == take (length a) b
    vtypeBytes :: VType -> [Word8]
    vtypeBytes VInteger = [0x01]
    vtypeBytes VLong = [0x04]
    vtypeBytes VTop = [0x00]
    vtypeBytes (VObject (ClassRef c)) =
      let i = Map.findWithDefault 0 c classMap in [0x07, hi8 i, lo8 i]
    w16 wd = [hi8 wd, lo8 wd]
    w32 wd =
      [ fromIntegral (wd `div` 16777216),
        fromIntegral ((wd `div` 65536) `mod` 256),
        fromIntegral ((wd `div` 256) `mod` 256),
        fromIntegral (wd `mod` 256)
      ]

-- ════════════════════════════════════════════════════════════════════════════
-- Module value (single source for text + bytes)
-- ════════════════════════════════════════════════════════════════════════════

-- | The gated, ordered methods of one program's @AwsumMain@ class. Both
--   'Awsum.Codegen.JVM.codegenJVM' (text) and 'assembleJVM' (bytes) derive from
--   this one value, so gating is decided once and the two cannot disagree on
--   which methods exist. Grouped so the text renderer reproduces the existing
--   blank-line layout: 'jmHelpers' and 'jmEntry' single-spaced, 'jmUserDefs'
--   double-spaced. The @<init>@ method and the class framing are fixed and live
--   in the renderers. (The byte assembler emits the flat 'jvmModuleMethods'; the
--   methods-table order does not affect execution.)
data JvmModule = JvmModule
  { jmHelpers :: [JvmMethod],
    jmUserDefs :: [JvmMethod],
    jmEntry :: [JvmMethod]
  }

-- | The flat method list (helpers, then user declarations, then entry + @main@).
jvmModuleMethods :: JvmModule -> [JvmMethod]
jvmModuleMethods m = jmHelpers m <> jmUserDefs m <> jmEntry m

-- | Lower a program to its 'JvmModule' — the gating decision, made once.
jvmModule :: PreludeTags -> CoreProgram -> JvmModule
jvmModule ptags prog@(CoreProgram decls) =
  let valNames = Set.fromList [n | CValDef n _ <- decls]
      funNames = Set.fromList [n | CFunDef n _ _ <- decls]
      arities = Map.fromList [(n, length as) | CFunDef n as _ <- decls]
      builtIns = usedBuiltIns prog
      gate cond ms = if cond then ms else []
   in JvmModule
        { jmHelpers =
            concat
              [ gate (Set.member "concatString" builtIns) [concatSpec (ptRight ptags, ptLeft ptags, ptStringTooLong ptags)],
                gate (Set.member "internalStdoutPrint" builtIns) [printSpec (ptUnit ptags)],
                gate (Set.member "predInt32" builtIns) [predInt32Spec (ptUnderflowError ptags, ptLeft ptags, ptRight ptags)],
                gate (Set.member "predUInt8" builtIns) [predUInt8Spec (ptUnderflowError ptags, ptLeft ptags, ptRight ptags)],
                gate (Set.member "predUInt32" builtIns) [predUInt32Spec (ptUnderflowError ptags, ptLeft ptags, ptRight ptags)],
                gate (Set.member "succInt32" builtIns) [succInt32Spec (ptOverflowError ptags, ptLeft ptags, ptRight ptags)],
                gate (Set.member "succUInt8" builtIns) [succUInt8Spec (ptOverflowError ptags, ptLeft ptags, ptRight ptags)],
                gate (Set.member "succUInt32" builtIns) [succUInt32Spec (ptOverflowError ptags, ptLeft ptags, ptRight ptags)],
                gate (Set.member "eqInt32" builtIns) [eqSpec "__eqInt32" "L_eq_i32" (ptTrue ptags, ptFalse ptags)],
                gate (Set.member "eqUInt8" builtIns) [eqSpec "__eqUInt8" "L_eq_u8" (ptTrue ptags, ptFalse ptags)],
                gate (Set.member "eqUInt32" builtIns) [eqSpec "__eqUInt32" "L_eq_u32" (ptTrue ptags, ptFalse ptags)],
                gate (Set.member "eqString" builtIns) [eqStringSpec (ptTrue ptags, ptFalse ptags)],
                gate (Set.member "addInt32" builtIns) [addInt32Spec (ptOverflowError ptags, ptUnderflowError ptags, ptLeft ptags, ptRight ptags, overflowRowTag, underflowRowTag)],
                gate (Set.member "subInt32" builtIns) [subInt32Spec (ptOverflowError ptags, ptUnderflowError ptags, ptLeft ptags, ptRight ptags, overflowRowTag, underflowRowTag)],
                gate (Set.member "mulInt32" builtIns) [mulInt32Spec (ptOverflowError ptags, ptUnderflowError ptags, ptLeft ptags, ptRight ptags, overflowRowTag, underflowRowTag)],
                gate (Set.member "negInt32" builtIns) [negInt32Spec (ptOverflowError ptags, ptLeft ptags, ptRight ptags)],
                gate (Set.member "addUInt8" builtIns) [addUInt8Spec (ptOverflowError ptags, ptLeft ptags, ptRight ptags)],
                gate (Set.member "subUInt8" builtIns) [subUInt8Spec (ptUnderflowError ptags, ptLeft ptags, ptRight ptags)],
                gate (Set.member "mulUInt8" builtIns) [mulUInt8Spec (ptOverflowError ptags, ptLeft ptags, ptRight ptags)],
                gate (Set.member "addUInt32" builtIns) [addUInt32Spec (ptOverflowError ptags, ptLeft ptags, ptRight ptags)],
                gate (Set.member "subUInt32" builtIns) [subUInt32Spec (ptUnderflowError ptags, ptLeft ptags, ptRight ptags)],
                gate (Set.member "mulUInt32" builtIns) [mulUInt32Spec (ptOverflowError ptags, ptLeft ptags, ptRight ptags)],
                gate (Set.member "showUInt32" builtIns) [showUInt32Spec],
                gate (Set.member "splitOnFirst" builtIns) [splitOnFirstSpec (ptNothing ptags, ptTuple2 ptags, ptJust ptags)],
                gate (Set.member "lengthCodePoints" builtIns) [lengthCodePointsSpec],
                gate (Set.member "lengthUtf16CodeUnits" builtIns) [lengthUtf16CodeUnitsSpec],
                gate (Set.member "lengthUtf8Bytes" builtIns) [lengthUtf8BytesSpec],
                gate (Set.member "parseInt32" builtIns) [parseInt32Spec (ptParseError ptags, ptLeft ptags, ptRight ptags)],
                gate (Set.member "parseUInt8" builtIns) [parseUInt8Spec (ptParseError ptags, ptLeft ptags, ptRight ptags)],
                gate (Set.member "parseUInt32" builtIns) [parseUInt32Spec (ptParseError ptags, ptLeft ptags, ptRight ptags)]
              ],
          jmUserDefs = userJvmMethods ptags valNames funNames arities decls,
          jmEntry =
            concat
              [ gate (Set.member "internalGetArgs" builtIns) [entryArgEitherSpec (ptRight ptags, ptLeft ptags, ptStringTooLong ptags, ptUnpairedUtf16Surrogate ptags, stringTooLongRowTag, unpairedSurrogateRowTag)],
                gate (Set.member "internalGetArgs" builtIns) [getArgsSpec (ptNil ptags, ptCons ptags, ptRight ptags)],
                gate (Set.member "internalStdinReadAllString" builtIns) [stdinReadAllSpec, stdinDecodeStrictSpec (ptRight ptags, ptLeft ptags, ptStringTooLong ptags, ptInvalidUtf8 ptags, stringTooLongRowTag, invalidUtf8RowTag)],
                gate (Set.member "internalStdinReadAllBytes" builtIns) [stdinReadAllBytesSpec (ptNil ptags, ptCons ptags)],
                [mainSpec (mangle "main") (mangle "runIO")]
              ]
        }

-- ════════════════════════════════════════════════════════════════════════════
-- Full assembly
-- ════════════════════════════════════════════════════════════════════════════

doAssemble :: CoreProgram -> AsmM [MInfo]
doAssemble prog = do
  -- Ensure required CP entries exist
  void $ addClass "AwsumMain"
  void $ addClass "java/lang/Object"
  void $ addUtf8 "Code"
  -- Static field '__argv : [Ljava/lang/String;' — set by 'mkMain' to
  -- the 'args' array, read by 'mkGetArgs' to build a prelude 'List
  -- String'. Always declared so the class layout stays stable across
  -- programs that touch / don't touch 'IO.Args.getArgs'.
  void $ addUtf8 "__argv"
  void $ addUtf8 "[Ljava/lang/String;"

  ptags <- askPreludeTags
  m0 <- mkInit
  -- Every method beyond '<init>' comes from the one 'jvmModule' value, so the
  -- gating and ordering match the text projection ('Awsum.Codegen.JVM') exactly.
  -- The methods-table order does not affect execution.
  ms <- traverse assembleMethod (jvmModuleMethods (jvmModule ptags prog))
  pure (m0 : ms)

-- ════════════════════════════════════════════════════════════════════════════
-- Fixed methods
-- ════════════════════════════════════════════════════════════════════════════

mkInit :: AsmM MInfo
mkInit = do
  ni <- addUtf8 "<init>"
  di <- addUtf8 "()V"
  ref <- addMRef "java/lang/Object" "<init>" "()V"
  pure
    MInfo
      { mFlags = 0x0000,
        miName = "<init>",
        mName = ni,
        mDesc = di,
        mCode =
          bcAload 0
            <> bcInvokeSpecial ref
            <> [0xB1], -- return
        mCodeAttrCount = 0,
        mCodeAttrs = [],
        mMaxStack = 256,
        mMaxLocals = 256
      }

-- ════════════════════════════════════════════════════════════════════════════
-- User declaration methods
-- ════════════════════════════════════════════════════════════════════════════

data ECtx = ECtx
  { cParams :: Map Text Int,
    cLocals :: Map Text Int, -- case-bound variable → aload slot
    cValDefs :: Set Text,
    cFunDefs :: Set Text,
    cArities :: Map Text Int,
    cNextLocal :: Int,
    -- | Slots reserved by an enclosing 'emitArgsViaLocalsI' that have
    -- not yet been written by the @astore@ at the end of their arg.
    -- These slots are below 'cNextLocal' (so the case codegen sees
    -- them inside the 'btLocals' range of its branch-target frames)
    -- but the verifier knows them as @top@ at the case bci — so the
    -- StackMapTable must declare @top@ here too. Without this we'd
    -- declare them as 'Object' (positional default) and fail
    -- verification.
    cUninitSlots :: Set Int,
    -- | /Live/ slot-type info for the unified 'emitExprI' frame builder:
    -- the slot indices serving as a 'CCase' @arrSlot@ (@Object[]@) or
    -- @tagSlot@ (@int@) in the cases /enclosing the current emission
    -- point/. Each case emitter adds its own pair for the extent of its
    -- arms (and frames), so a 'Label''s absolute 'Frame' is typed from
    -- exactly the regions whose reads are still ahead. A completed
    -- sibling subtree's slots revert to the @Object@ default — its stale
    -- @Object[]@ content is assignable to @Object@, and nothing reads it
    -- again — where a method-global union would declare the dead kind and
    -- contradict a path that has since re-stored the index with a plain
    -- binder (two subtrees may give one index different roles; observed
    -- when function inlining first produced a deep scrutinee whose
    -- spilled call-arg case landed on the enclosing case's bind region).
    cArrSlots :: Set Int,
    cTagSlots :: Set Int,
    -- | Method-global slot for each 'CLet' binder and each 'CJoin'
    -- parameter, assigned by 'namedSlotAssignments' into a dedicated region
    -- between the parameters and the structural slots. A named binder cannot
    -- share an index with the structural allocation: indices there are typed
    -- by the global-union rule above, and a binder's plain @Object@ at an
    -- index some /other/ subtree uses as an @arrSlot@ would poison every
    -- frame in the binder's scope. The region keeps the global typing exact:
    -- named slots are @Object@ everywhere, @top@ (via 'cUninitSlots') before
    -- their store — for a join parameter that means @top@ throughout the
    -- join's inner expression (the stores sit just before each jump's
    -- @goto@) and @Object@ from the join-body label on (every incoming edge
    -- has stored it).
    cNamedSlots :: Map Text Int,
    -- | The binders of the innermost enclosing case arm per (in-place
    -- 'CVar') scrutinee name — the slot map the 'CReuse' store schedule
    -- reads ('Awsum.Codegen.ReuseSchedule').
    cArmPatternByScrut :: Map Text [Text],
    -- | Join points in scope: name → (body label, parameters, 'pending'
    -- depth at the node — a tail-mode jump nulls only what was dropped
    -- after that point; the rest stays for the join body's own terminals).
    cJoinTargets :: Map Text (LabelId, [Text], Int)
  }

-- | Does the expression contain a 'CCase' (or 'CRowCase') anywhere?
-- 'CCall' (and any other multi-sub-expr emitter that leaves prior
-- values on the operand stack) needs to know this so it can route
-- each argument through a fresh local instead of leaving prior args
-- exposed when a nested case's StackMapTable kicks in.
exprContainsCase :: CExpr -> Bool
exprContainsCase = \case
  CCase {} -> True
  CRowCase {} -> True
  -- A join point carries StackMapTable frames of its own (its labels), so
  -- every empty-stack routing that applies to a multi-arm case applies to
  -- it — even to a degenerate one whose dispatch collapsed away.
  CJoin {} -> True
  CJump _ args -> any exprContainsCase args
  CRow _ v -> exprContainsCase v
  CCall f xs -> exprContainsCase f || any exprContainsCase xs
  CCon _ fs -> any exprContainsCase fs
  CDrop _ b -> exprContainsCase b
  CReuse _ _ _ fs -> any exprContainsCase fs
  CLoop b -> exprContainsCase b
  CContinue xs -> any exprContainsCase xs
  CLet _ rhs b -> exprContainsCase rhs || exprContainsCase b
  _ -> False

-- | Gate for a non-tail 'declJvmMethod' clause: which expressions 'emitExprI'
--   accepts as a method body / value. A /multi-arm/ 'CCase' / 'CRowCase' is
--   accepted in any /stack-empty/ position — the body, a case-arm body, a case
--   scrutinee, a 'CDrop' body — and in every position that spills to save
--   locals first: a 'CCall' argument ('emitArgsViaLocalsI') and a 'CCon' /
--   'CReuse' field or 'CRow' value ('emitCellI'). A /single-arm/ case
--   (frame-free) is accepted anywhere via 'noMultiArmCase'. 'CLoop' is the
--   tail form, gated separately by 'emitTailIOk'. The only remaining 'False'
--   shape is a multi-arm case in a callee position, which cannot arise:
--   'Awsum.LowerClosures' routes any function-valued case through the
--   @$applyN@ dispatcher, moving the case into an argument.
emitIOk :: CExpr -> Bool
emitIOk = \case
  CCase s alts -> not (null alts) && emitIOk s && all (\(_, _, b) -> emitIOk b) alts
  CRowCase s alts -> not (null alts) && emitIOk s && all (\(_, _, b) -> emitIOk b) alts
  -- Cell fields holding a multi-arm case route through save-locals in
  -- 'emitCellI' (same discipline as call args), so any emittable expression
  -- is accepted; branch-free fields keep the inline dup/aastore shape.
  CRow _ v -> emitIOk v
  CCon _ fs -> all emitIOk fs
  CReuse _ _ _ fs -> all emitIOk fs
  -- Cases in arguments are handled (save-to-locals via 'emitArgsViaLocalsI');
  -- 'f' is a builtin or known function (the indirect MethodHandle path is dead
  -- after LowerClosures), so it carries no case.
  CCall f xs -> not (exprContainsCase f) && all emitIOk xs
  CDrop _ b -> emitIOk b
  CLet _ rhs b -> emitIOk rhs && emitIOk b
  -- The gates police stack discipline only; a jump's positional legality
  -- (tail of its join's inner) is the emitters' loud-error job, exactly as
  -- for 'CLoop' / 'CContinue' placement.
  CJoin _ _ body inner -> emitIOk body && emitIOk inner
  CJump _ args -> all emitIOk args
  CLoop _ -> False
  CContinue _ -> False
  _ -> True

-- | True when the expression contains no /multi-arm/ 'CCase' / 'CRowCase'
--   anywhere. A multi-arm case emits an @if_icmpne@ chain with StackMapTable
--   frames that assume an empty operand stack, so it cannot sit in a non-empty-
--   stack position (a cell field, a row value); a single-arm case carries no
--   frames and is fine there.
noMultiArmCase :: CExpr -> Bool
noMultiArmCase = \case
  CCase s alts -> length alts <= 1 && noMultiArmCase s && all (\(_, _, b) -> noMultiArmCase b) alts
  CRowCase s alts -> length alts <= 1 && noMultiArmCase s && all (\(_, _, b) -> noMultiArmCase b) alts
  -- A join point's labels carry frames that assume an empty operand stack,
  -- exactly like a multi-arm case's — it cannot sit in a non-empty-stack
  -- position regardless of its inner dispatch's shape.
  CJoin {} -> False
  CJump {} -> False
  CRow _ v -> noMultiArmCase v
  CCall f xs -> noMultiArmCase f && all noMultiArmCase xs
  CCon _ fs -> all noMultiArmCase fs
  CReuse _ _ _ fs -> all noMultiArmCase fs
  CDrop _ b -> noMultiArmCase b
  CLoop b -> noMultiArmCase b
  CContinue xs -> all noMultiArmCase xs
  CLet _ rhs b -> noMultiArmCase rhs && noMultiArmCase b
  _ -> True

-- | Gate for the TCO 'declJvmMethod' clause (@CFunDef _ _ (CLoop body)@):
--   which loop bodies 'emitTailBinI' accepts. Tail position recurses into arm
--   bodies (each self-terminating); 'CContinue' args spill through save
--   locals when one holds a multi-arm case ('emitContinue'), so they are
--   ordinary 'emitIOk' expressions — as are a value tail and a case
--   scrutinee.
emitTailIOk :: CExpr -> Bool
emitTailIOk = \case
  CContinue xs -> all emitIOk xs
  CCase s alts -> not (null alts) && emitIOk s && all (\(_, _, b) -> emitTailIOk b) alts
  CRowCase s alts -> not (null alts) && emitIOk s && all (\(_, _, b) -> emitTailIOk b) alts
  CDrop _ b -> emitTailIOk b
  CLet _ rhs b -> emitIOk rhs && emitTailIOk b
  -- Inner and body continue the tail walk (their arms may continue the
  -- loop, return, or jump); jump arguments are ordinary value expressions.
  CJoin _ _ body inner -> emitTailIOk body && emitTailIOk inner
  CJump _ args -> all emitIOk args
  other -> emitIOk other

-- | Build the 'JvmMethod' for one user declaration — the single source
--   consumed by both 'mkDecl' (→ classfile bytes via 'assembleMethod') and
--   the text renderer (→ Jasmin via 'renderMethod'). Every form routes
--   through the unified 'emitExprI' / 'emitTailBinI'; every position that
--   cannot host a multi-arm case's frames spills to save locals first (call
--   args, cell fields, continue args), so the 'emitIOk' / 'emitTailIOk' gates are total over
--   the lowering's output and the fallbacks are unreachable guards that fail
--   loudly rather than miscompile. (The cell-field spill exists because the
--   gate /was/ reachable: @IO.Stdout.print (case x of …)@ lowers the case
--   into an 'IOStdoutPrint' cell field — the lazy-IO lowering puts user
--   expressions into constructor fields, so any branchy argument to an IO
--   platform built-in lands there.)
declJvmMethod :: Set Text -> Set Text -> Map Text Int -> CDecl -> AsmM JvmMethod
declJvmMethod valDefs funDefs arities = \case
  -- TCO loop. The entry 'Label' (offset 0) is the 'CContinue' goto target and
  -- carries the signature-derived frame ([Object × nParams], empty stack).
  CFunDef nm args (CLoop body) | emitTailIOk body -> do
    loopLbl <- freshLabel "L_tco"
    let namedSlots = namedSlotAssignments (length args) body
        next0 = length args + Map.size namedSlots
        ctx = mkCtx (Map.fromList (zip args [0 ..])) next0 namedSlots
        loopFrame = Frame (replicate (length args) (VObject objectClassRef)) []
    bodyI <- emitTailBinI ctx args loopLbl body
    pure (userMethod (mangle nm) (objMethodDesc (length args)) (Label loopLbl (Just loopFrame) : bodyI))
  CFunDef nm args body | emitIOk body -> do
    let namedSlots = namedSlotAssignments (length args) body
        next0 = length args + Map.size namedSlots
        ctx = mkCtx (Map.fromList (zip args [0 ..])) next0 namedSlots
    instrs <- emitExprI ctx body
    pure (userMethod (mangle nm) (objMethodDesc (length args)) (instrs <> [AReturn]))
  CValDef nm rhs | emitIOk rhs -> do
    let namedSlots = namedSlotAssignments 0 rhs
        next0 = Map.size namedSlots
        ctx = mkCtx Map.empty next0 namedSlots
    instrs <- emitExprI ctx rhs
    pure (userMethod (mangle nm) "()Ljava/lang/Object;" (instrs <> [AReturn]))
  CFunDef nm _ _ -> error ("JVM: unified emitter gate missed function " <> nm)
  CValDef nm _ -> error ("JVM: unified emitter gate missed value " <> nm)
  where
    mkCtx params next namedSlots =
      ECtx
        { cParams = params,
          cLocals = Map.empty,
          cValDefs = valDefs,
          cFunDefs = funDefs,
          cArities = arities,
          cNextLocal = next,
          -- Every named slot starts life unwritten: any frame materialising
          -- before the binder's 'Astore' on a given path must declare @top@
          -- there. 'emitLetBindI' removes a let's slot for the binder's
          -- scope; the join emitters remove a join's parameter slots for the
          -- body.
          cUninitSlots = Set.fromList (Map.elems namedSlots),
          -- Case regions register themselves as emission enters them.
          cArrSlots = Set.empty,
          cTagSlots = Set.empty,
          cNamedSlots = namedSlots,
          cArmPatternByScrut = Map.empty,
          cJoinTargets = Map.empty
        }
    -- @max_stack@ / @max_locals@ are not set here — 'renderMethod' /
    -- 'assembleMethod' derive them from 'jmBody' ('methodMaxStack' /
    -- 'methodMaxLocals'), the one path shared with every hand-written helper, so
    -- the declared limits cannot disagree with the instructions the method
    -- actually emits.
    userMethod name desc instrs =
      JvmMethod
        { jmName = name,
          jmDesc = desc,
          jmPublic = False,
          jmBody = instrs
        }

-- | Method-global slot for every named binder — each 'CLet' binder and each
--   'CJoin' parameter — in walk order, starting at @base@ (right after the
--   parameters; the structural region starts past them). Binder names are
--   unique within a declaration — the simplifier freshens every name it
--   mints — and the slot map relies on it.
namedSlotAssignments :: Int -> CExpr -> Map Text Int
namedSlotAssignments base e =
  let names = namedBinders e
      m = Map.fromList (zip names [base ..])
   in if Map.size m == length names
        then m
        else error "JVM namedSlotAssignments: duplicate named binders in one declaration"
  where
    namedBinders :: CExpr -> [Text]
    namedBinders = go
    go = \case
      CLet x rhs b -> go rhs <> (x : go b)
      -- Like a let, the binders precede their scope (the body); the inner
      -- expression's own binders come first, mirroring a let's rhs.
      CJoin _ ps b i -> go i <> ps <> go b
      CJump _ args -> concatMap go args
      CCall f xs -> go f <> concatMap go xs
      CCon _ fs -> concatMap go fs
      CRow _ v -> go v
      CCase s alts -> go s <> concatMap (\(_, _, b) -> go b) alts
      CRowCase s alts -> go s <> concatMap (\(_, _, b) -> go b) alts
      CLoop b -> go b
      CContinue xs -> concatMap go xs
      CDrop _ b -> go b
      CReuse _ _ _ fs -> concatMap go fs
      CVar _ -> []
      CProj _ _ -> []
      CString _ -> []
      CIntLit _ _ -> []
      CBuiltIn _ -> []

-- | The user-declaration 'JvmMethod's for a program, in order. The text
--   renderer ('Awsum.Codegen.JVM') projects these with 'renderMethod' and the
--   binary assembler with 'assembleMethod' — one source, so the @.j@ snapshot
--   is a faithful view of the shipped @.class@. The label counter is threaded
--   across all declarations (unique 'LabelId's); a fresh 'Pool' is fine since
--   the text projection ignores the constant pool.
userJvmMethods :: PreludeTags -> Set Text -> Set Text -> Map Text Int -> [CDecl] -> [JvmMethod]
userJvmMethods ptags valDefs funDefs arities decls =
  evalState (traverse (declJvmMethod valDefs funDefs arities) decls) (emptyPool ptags)

-- ════════════════════════════════════════════════════════════════════════════
-- Expression codegen (bytecode bytes)
-- ════════════════════════════════════════════════════════════════════════════

integerValueOfRef :: MethodRef
integerValueOfRef = MethodRef "java/lang/Integer" "valueOf" "(I)Ljava/lang/Integer;"

integerClassRef :: ClassRef
integerClassRef = ClassRef "java/lang/Integer"

objectClassRef :: ClassRef
objectClassRef = ClassRef "java/lang/Object"

objectArrayRef :: ClassRef
objectArrayRef = ClassRef "[Ljava/lang/Object;"

-- | The unified user-code emitter: lowers a Core expression to '[JvmInstr]'
--   (the shared instruction IR), so both 'renderMethod' (text) and
--   'assembleMethod' (bytes) are driven from one source. Handles every non-tail form — leaves, 'CCon' /
--   'CReuse' cells, calls, and single- and multi-arm 'CCase' / 'CRowCase'
--   (with 'Label'-carried frames). The MethodHandle / function-as-value paths
--   are dead after LowerClosures (no first-class fn value survives — confirmed:
--   zero MethodHandle uses in any snapshot) and error. Memory semantics match
--   memory-management.md: 'CDrop' is transparent here (host GC; the only real
--   JVM drop is the parameter null-store at 'CContinue', in the tail emitter),
--   and 'CReuse' is an in-place @aastore@ rewrite with no refcount branch.
emitExprI :: ECtx -> CExpr -> AsmM [JvmInstr]
emitExprI ctx = \case
  CString s -> pure [LdcString s]
  CVar n
    | Just slot <- Map.lookup n ctx.cLocals -> pure [Aload slot]
    | Just slot <- Map.lookup n ctx.cParams -> pure [Aload slot]
    | n `Set.member` ctx.cValDefs ->
        pure [InvokeStatic (MethodRef "AwsumMain" (mangle n) "()Ljava/lang/Object;")]
    | n `Set.member` ctx.cFunDefs ->
        error ("emitExprI: function-as-value (MethodHandle) for " <> n <> " — unreachable after LowerClosures")
    | otherwise -> pure [AconstNull]
  CBuiltIn _ -> pure [AconstNull] -- dispatched from CCall; bare CBuiltIn is unreachable
  CLet x rhs body -> do
    (bindI, ctx') <- emitLetBindI ctx x rhs
    bodyI <- emitExprI ctx' body
    pure (bindI <> bodyI)
  CProj n slot -> do
    base <- emitExprI ctx (CVar n)
    pure (base <> [CheckCast objectArrayRef, PushInt slot, Aaload])
  CIntLit n _ ->
    pure [LoadInt32 (fromInteger n :: Int32), InvokeStatic integerValueOfRef]
  CCon tag fields -> emitCellI ctx [PushInt (1 + length fields), ANewArray objectClassRef] (fromIntegral tag) fields
  -- A guarded reuse cannot mutate here: the cell may be shared (the caller
  -- can retain the structure) and the managed heap has no refcount header
  -- to check, so it lowers as the allocation it replaced. Only
  -- 'ReuseUnique' — an Scc pack / Cps continuation, loop-private by
  -- construction — overwrites the existing Object[] in place
  -- (memory-management.md).
  CReuse ReuseGuarded _ tag fields -> emitExprI ctx (CCon tag fields)
  CReuse ReuseUnique n tag fields -> do
    let slot = case Map.lookup n ctx.cLocals of
          Just s -> s
          Nothing -> case Map.lookup n ctx.cParams of
            Just s -> s
            Nothing -> error ("emitExprI: CReuse on unknown binder " <> n)
        cellA = [Aload slot, CheckCast objectArrayRef]
        armVars = Map.findWithDefault [] n ctx.cArmPatternByScrut
        (stores, _breakers) = scheduleReuse armVars fields
        fieldAt i = fromMaybe (error "JVM: CReuse store schedule slot out of range") (fields !!? (i - 1))
        externs = [fieldAt dst | StoreExtern dst <- stores]
    if all noMultiArmCase externs
      then do
        -- Stores in dependency order ('Awsum.Codegen.ReuseSchedule'): the
        -- acyclic permutation part reads the old slots straight off the
        -- cell, a cycle reads its one extracted binder, unrelated fields
        -- evaluate inline (gated branch-free above — a multi-arm case
        -- cannot run on a parked operand stack). Arm extraction skips the
        -- binders the schedule reads off the cell ('reuseSlotElided').
        let tagI = cellA <> [PushInt 0, LoadInt32 (fromIntegral tag), InvokeStatic integerValueOfRef, AAStore]
            storeI = \case
              StoreFromSlot dst src ->
                pure (cellA <> [PushInt dst] <> cellA <> [PushInt src, Aaload, AAStore])
              StoreFromBinder dst b ->
                let bslot = case Map.lookup b ctx.cLocals of
                      Just s -> s
                      Nothing -> error ("JVM: CReuse cycle breaker has no extracted slot: " <> b)
                 in pure (cellA <> [PushInt dst, Aload bslot, AAStore])
              StoreExtern dst -> do
                fI <- emitExprI ctx (fieldAt dst)
                pure (cellA <> [PushInt dst] <> fI <> [AAStore])
        storeIs <- traverse storeI stores
        pure (tagI <> concat storeIs <> cellA)
      else
        -- A branchy extern needs the save-locals discipline; the
        -- unscheduled path reads every binder, and 'reuseSlotElided'
        -- excludes nodes like this one, so extraction agrees.
        emitCellI ctx cellA (fromIntegral tag) fields
  CCall f xs -> emitCallI ctx f xs
  CRow tag v -> emitExprI ctx (CCon (fromIntegral tag) [v])
  CDrop _ body -> emitExprI ctx body
  -- Single-arm case: exhaustive over one constructor, so no @if_icmpne@, no
  -- join, no branch targets — hence no StackMapTable. No compare reads a
  -- tag, so none is extracted ('caseHeadI'); the fields are bound and the
  -- body runs.
  CCase scrut [(_, vars, body)] -> emitSingleArmCaseI ctx scrut vars body
  CCase scrut alts | not (null alts) -> emitMultiArmCaseI ctx scrut alts
  CCase {} -> error "emitExprI: empty CCase (uninhabited scrutinee) — the gates should exclude it"
  CRowCase scrut alts -> emitExprI ctx (CCase scrut [(fromIntegral t, [v], b) | (t, v, b) <- alts])
  CLoop _ -> error "emitExprI: CLoop reached (non-tail position)"
  CContinue _ -> error "emitExprI: CContinue reached (non-tail position)"
  CJoin j ps body inner -> emitJoinExprI ctx j ps body inner
  CJump j _ -> error ("JVM codegen: CJump to " <> j <> " in non-tail position — jumps live only in tail positions of their join's inner expression")

-- | Bind a 'CLet': evaluate the rhs (during which the binder's slot is
--   still in 'cUninitSlots', so any frame inside the rhs declares it @top@),
--   store it into the binder's dedicated slot ('cLetSlots'), and return the
--   context for the body — binder in scope, slot no longer uninitialised.
--   Works at any operand-stack depth: the rhs adds one value, the @astore@
--   pops it. Shared by 'emitExprI' and 'emitTailBinI'.
emitLetBindI :: ECtx -> Text -> CExpr -> AsmM ([JvmInstr], ECtx)
emitLetBindI ctx x rhs = do
  let slot = case Map.lookup x ctx.cNamedSlots of
        Just s -> s
        Nothing -> error ("JVM emitLetBindI: no let slot for binder " <> x)
      ctx' =
        ctx
          { cLocals = Map.insert x slot ctx.cLocals,
            cUninitSlots = Set.delete slot ctx.cUninitSlots
          }
  rhsI <- emitExprI ctx rhs
  pure (rhsI <> [Astore slot], ctx')

-- | The in-place load of a case scrutinee that is already a named local or
--   parameter: load + @checkcast@, the same shape as 'CProj'. The slot's type
--   in every frame stays the positional @Object@ — the cast re-derives
--   @Object[]@ on the stack at each read, so no 'cArrSlots' registration is
--   needed. 'Nothing' for anything that must evaluate into an @arrSlot@
--   copy — calls, constructions, and a 'CVar' naming a 'CValDef' (a getter
--   call). Whichever slots this path takes are counted straight off the
--   emitted stream by 'maxLocalsOf' — no separate sizing to keep in step.
scrutInPlaceLoad :: ECtx -> CExpr -> Maybe [JvmInstr]
scrutInPlaceLoad ctx = \case
  CVar n
    | Just slot <- Map.lookup n ctx.cLocals -> Just [Aload slot, CheckCast objectArrayRef]
    | Just slot <- Map.lookup n ctx.cParams -> Just [Aload slot, CheckCast objectArrayRef]
    | n `Set.member` ctx.cValDefs || n `Set.member` ctx.cFunDefs -> Nothing
    | otherwise -> error ("JVM Assemble: case scrutinee names unknown binder: " <> show n)
  _ -> Nothing

-- | Dispatch head of a 'CCase' / 'CRowCase': the head instructions, the
--   per-read scrutinee-array load for arm bindings, the tag slot (read by
--   each arm compare; 'Nothing' for a single-arm case — no compare reads a
--   tag, so none is extracted and no slot is taken), the first binding
--   slot, and the region-registered context for frames. An in-place
--   scrutinee ('scrutInPlaceLoad') is re-loaded per read and skips the
--   @arrSlot@ copy. The head slots it takes are counted from the emitted
--   stream by 'maxLocalsOf' — no separate sizing to keep in step.
caseHeadI :: ECtx -> CExpr -> Int -> AsmM ([JvmInstr], [JvmInstr], Maybe Int, Int, ECtx)
caseHeadI ctx scrut nAlts = do
  (arrHead, loadScrut, afterArr, ctxArr) <- case scrutInPlaceLoad ctx scrut of
    Just load -> pure ([], load, ctx.cNextLocal, ctx)
    Nothing -> do
      scrutI <- emitExprI ctx scrut
      let arrSlot = ctx.cNextLocal
      pure
        ( scrutI <> [CheckCast objectArrayRef, Astore arrSlot],
          [Aload arrSlot],
          arrSlot + 1,
          -- No frames of its own when single-arm, but a frame inside an arm
          -- body covers this region and must type it (see 'cArrSlots').
          ctx {cArrSlots = Set.insert arrSlot ctx.cArrSlots}
        )
  if nAlts == 1
    then pure (arrHead, loadScrut, Nothing, afterArr, ctxArr)
    else do
      let tagSlot = afterArr
          regCtx = ctxArr {cTagSlots = Set.insert tagSlot ctxArr.cTagSlots}
          tagHead =
            loadScrut
              <> [ PushInt 0,
                   Aaload,
                   CheckCast integerClassRef,
                   InvokeVirtual (MethodRef "java/lang/Integer" "intValue" "()I"),
                   Istore tagSlot
                 ]
      pure (arrHead <> tagHead, loadScrut, Just tagSlot, tagSlot + 1, regCtx)

-- | A single-arm 'CCase' / 'CRowCase' (one constructor, exhaustive): bind
--   each field, then the body. No branches, no tag read; an in-place
--   scrutinee makes the head disappear entirely.
emitSingleArmCaseI :: ECtx -> CExpr -> [Text] -> CExpr -> AsmM [JvmInstr]
emitSingleArmCaseI ctx scrut vars body = do
  (headI, loadScrut, _noTag, bindSlotStart, regCtx) <- caseHeadI ctx scrut 1
  let next' = bindSlotStart + length vars
      (stored, regCtx') = bindRegion (armElidedFor scrut) regCtx bindSlotStart next' [(0, vars, body)]
      bindings = zip vars [bindSlotStart ..]
      ctx' =
        armPatternCtx
          scrut
          vars
          regCtx'
            { cLocals = foldl' (\m (v, s) -> Map.insert v s m) regCtx'.cLocals bindings,
              cNextLocal = next'
            }
      bindCode = armBindStores (armElidedFor scrut vars body) stored loadScrut bindSlotStart next' vars body
  bodyI <- emitExprI ctx' body
  pure $ headI <> bindCode <> bodyI

-- | The verifier type of local slot @i@ at a branch target, from the method-
--   global slot kinds: an uninitialised save slot is @top@, a 'CCase' arr slot
--   is @Object[]@, a tag slot is @int@,
--   everything else (params, pattern bindings) is @Object@.
slotVTypeI :: ECtx -> Int -> VType
slotVTypeI ctx i
  | i `Set.member` ctx.cUninitSlots = VTop
  | i `Set.member` ctx.cArrSlots = VObject objectArrayRef
  | i `Set.member` ctx.cTagSlots = VInteger
  | otherwise = VObject objectClassRef

-- | Absolute 'Frame' at a branch target: slots @0 .. nLocals-1@ typed by
--   'slotVTypeI'; the stack is @[Object]@ at a join point (the arm result is
--   live) and empty at an @if_icmpne@ landing site (the compare popped both
--   ints).
frameAtI :: ECtx -> Int -> Bool -> Frame
frameAtI ctx nLocals isJoin =
  Frame
    { frLocals = [slotVTypeI ctx i | i <- [0 .. nLocals - 1]],
      frStack = [VObject objectClassRef | isJoin]
    }

-- | A case's shared bind region @[bindSlotStart .. next' - 1]@, split by
--   whether any arm actually extracts into the slot ('binderUsedIn' its own
--   body). The dead complement — slots only ever null-filled — is registered
--   in 'cUninitSlots' for the arms' subtree, so every frame in scope types
--   them @top@ and no store is needed to satisfy it: a slot no arm writes
--   can never hold a stale reference. Slots some arm does extract keep the
--   null-store in the arms that don't ('armBindStores') — the frames type
--   the whole region @Object@, and a previous loop iteration may have parked
--   a since-dead reference there that the null releases for the GC.

-- | The per-arm elision for one case: binders the 'CReuse' store schedule
--   reads straight off the cell ('reuseSlotElided', gated by
--   'noMultiArmCase' on extern fields — a branchy extern routes the node
--   through the unscheduled save-locals path, which reads every binder).
--   Only an in-place 'CVar' scrutinee qualifies; 'Awsum.Reuse' rewrites no
--   other shape.
armElidedFor :: CExpr -> [Text] -> CExpr -> Set Text
armElidedFor scrut vs b = case scrut of
  CVar nm -> reuseSlotElided noMultiArmCase nm vs b
  _ -> Set.empty

-- | Register the matched arm's binders for the scheduled 'CReuse'
--   lowering inside the arm body.
armPatternCtx :: CExpr -> [Text] -> ECtx -> ECtx
armPatternCtx scrut vs c = case scrut of
  CVar nm -> c {cArmPatternByScrut = Map.insert nm vs c.cArmPatternByScrut}
  _ -> c

bindRegion :: ([Text] -> CExpr -> Set Text) -> ECtx -> Int -> Int -> [(Int, [Text], CExpr)] -> (Set Int, ECtx)
bindRegion armElided regCtx bindSlotStart next' sorted =
  let stored =
        Set.fromList
          [ slot
          | (_, vs, b) <- sorted,
            let el = armElided vs b,
            (v, slot) <- zip vs [bindSlotStart ..],
            binderUsedIn v b,
            not (Set.member v el)
          ]
      dead = Set.fromList [bindSlotStart .. next' - 1] `Set.difference` stored
   in (stored, regCtx {cUninitSlots = regCtx.cUninitSlots `Set.union` dead})

-- | One arm's entry stores over the shared bind region: extract the binders
--   the arm reads, null the stored-elsewhere slots it doesn't (its own
--   unread binders and the padding up to the widest sibling), skip the dead
--   ones ('bindRegion').
armBindStores :: Set Text -> Set Int -> [JvmInstr] -> Int -> Int -> [Text] -> CExpr -> [JvmInstr]
armBindStores elided stored loadScrut bindSlotStart next' vars body =
  concatMap bindOne (zip (zip vars [bindSlotStart ..]) [1 :: Int ..]) <> padCode
  where
    bindOne ((v, slot), i)
      | binderUsedIn v body, not (Set.member v elided) = loadScrut <> [PushInt i, Aaload, Astore slot]
      | slot `Set.member` stored = [AconstNull, Astore slot]
      | otherwise = []
    padCode =
      concatMap
        (\slot -> [AconstNull, Astore slot])
        (filter (`Set.member` stored) [bindSlotStart + length vars .. next' - 1])

-- | Multi-arm 'CCase' (≥2 arms): an @if_icmpne@ chain where each arm extracts
--   its bindings (padded to the widest arm so the join frame is consistent),
--   runs its body, and @goto@s the join; the last arm falls through. Each arm
--   label and the join carry an absolute 'Frame' computed inline from the
--   method-global slot kinds in 'ctx'; as '[JvmInstr]' the assembler resolves
--   the @if_icmpne@ offsets and StackMapTable end-to-end.
emitMultiArmCaseI :: ECtx -> CExpr -> [(Int, [Text], CExpr)] -> AsmM [JvmInstr]
emitMultiArmCaseI ctx scrut alts = do
  (headI, loadScrut, mTagSlot, bindSlotStart, regCtx) <- caseHeadI ctx scrut (length alts)
  let sorted = sortWith (\(t, _, _) -> t) alts
      tagSlot = fromMaybe (error "JVM caseHeadI: no tag slot for a multi-arm chain") mTagSlot
      maxBindings = foldl' max 0 [length vs | (_, vs, _) <- sorted]
      next' = bindSlotStart + maxBindings
      n = length sorted
      (stored, regCtx') = bindRegion (armElidedFor scrut) regCtx bindSlotStart next' sorted
      ifFrame = frameAtI regCtx' bindSlotStart False
      joinFrame = frameAtI regCtx' next' True
  joinLbl <- freshLabel "L_join"
  armLbls <- replicateM (n - 1) (freshLabel "L_arm") -- labels for arms 1..n-1
  armBodies <- forM sorted $ \(tag, vars, body) -> do
    let bindings = zip vars [bindSlotStart ..]
        ctx' = armPatternCtx scrut vars (regCtx' {cLocals = foldl' (\m (v, s) -> Map.insert v s m) regCtx'.cLocals bindings, cNextLocal = next'})
        bindCode = armBindStores (armElidedFor scrut vars body) stored loadScrut bindSlotStart next' vars body
    bodyI <- emitExprI ctx' body
    pure (tag, bindCode <> bodyI)
  -- Per arm: an optional preceding label (the @if_icmpne@ landing site from
  -- the previous arm; none for arm 0) and an optional next-arm target (the
  -- @if_icmpne@ destination; none for the last arm, which falls through).
  let preLabels = Nothing : map Just armLbls -- length n
      nextTargets = map Just armLbls <> [Nothing] -- length n
      buildArm ((tag, armCode), (preLbl, nextLbl)) =
        maybe [] (\l -> [Label l (Just ifFrame)]) preLbl
          <> maybe [] (\l -> [Iload tagSlot, LoadInt32 (fromIntegral tag), IfICmpNe l]) nextLbl
          <> armCode
          <> maybe [] (const [Goto joinLbl]) nextLbl
      chainCode = concatMap buildArm (zip armBodies (zip preLabels nextTargets))
  pure $ headI <> chainCode <> [Label joinLbl (Just joinFrame)]

-- | The slot of a 'CJoin' parameter in the named region ('cNamedSlots').
namedSlotOf :: ECtx -> Text -> Int
namedSlotOf ctx p =
  fromMaybe
    (error ("JVM: no named slot for join parameter " <> p))
    (Map.lookup p ctx.cNamedSlots)

-- | Expression-position 'CJoin' (a non-loop function body, a 'CValDef'
--   right-hand side, or — via the save-locals routing — a call argument or
--   cell field): the value-producing form. Layout is flat: the inner
--   expression's value arms push their result and @goto@ the after label,
--   its jump arms store the join parameters and @goto@ the body label; the
--   body (an ordinary 'emitExprI' value) sits between the two labels and
--   falls through to the after label, which carries the one-item-stack
--   frame — the same merge shape as a multi-arm case's join label.
--
--   Frames: the body label's frame types the parameters @Object@ (every
--   incoming edge has stored them — 'cUninitSlots' minus the parameter
--   slots); the after label's frame keeps them @top@ (a value arm reaches
--   it without storing them, and @Object@ from the body edge widens to
--   @top@). Both describe the node's extent ('cNextLocal') — the inner
--   case's own region is dead past its dispatch, and when the body's tail
--   is itself a multi-arm case whose join label lands on the after label's
--   byte, the assembler's same-offset dedup keeps this narrower frame.
--
--   Jumps appear only at arm roots of the inner case (under the 'CDrop'
--   wrappers 'Awsum.Lifetime' adds — transparent here, the JVM drops
--   nothing in expression position; the case itself may sit under 'CLet'
--   bindings floated out of its scrutinee): anything deeper is a jump in
--   non-tail position, which the node's invariant excludes and the
--   'emitExprI' arm rejects loudly. Jump arguments evaluate one at a time,
--   each stored straight into its parameter slot — the parameters are in
--   scope only inside the body, so an argument cannot read them and the
--   'CContinue' parallel-assignment two-step is unnecessary; each argument
--   starts on an empty stack, so a multi-arm case inside one needs no
--   save-locals routing.
emitJoinExprI :: ECtx -> Text -> [Text] -> CExpr -> CExpr -> AsmM [JvmInstr]
emitJoinExprI ctx j ps body inner = do
  bodyLbl <- freshLabel "L_jbody"
  afterLbl <- freshLabel "L_jafter"
  let psSlots = map (namedSlotOf ctx) ps
      ctxJ = ctx {cJoinTargets = Map.insert j (bodyLbl, ps, 0) ctx.cJoinTargets}
      ctxB =
        ctx
          { cLocals = foldl' (\m (p, s) -> Map.insert p s m) ctx.cLocals (zip ps psSlots),
            cUninitSlots = flipfoldl' Set.delete ctx.cUninitSlots psSlots
          }
      bodyFrame = frameAtI ctxB ctx.cNextLocal False
      afterFrame = frameAtI ctx ctx.cNextLocal True
  innerI <- goInner ctxJ afterLbl inner
  bodyI <- emitExprI ctxB body
  pure (innerI <> [Label bodyLbl (Just bodyFrame)] <> bodyI <> [Label afterLbl (Just afterFrame)])
  where
    -- The inner expression: a case — possibly under 'CLet' bindings floated
    -- out of its scrutinee and the 'CDrop' wrappers 'Awsum.Lifetime' places
    -- around those binders (transparent here, managed heap) — whose arms
    -- either jump or produce bypass values; or a degenerate root (the
    -- dispatch collapsed away after the fusion), which takes the same two
    -- routes without the chain.
    goInner :: ECtx -> LabelId -> CExpr -> AsmM [JvmInstr]
    goInner ctxJ afterLbl = \case
      CLet x rhs b -> do
        (bindI, ctx') <- emitLetBindI ctxJ x rhs
        bodyI <- goInner ctx' afterLbl b
        pure (bindI <> bodyI)
      CDrop _ b -> goInner ctxJ afterLbl b
      CCase scrut alts -> goInnerCase ctxJ afterLbl scrut alts
      CRowCase scrut alts ->
        goInnerCase ctxJ afterLbl scrut [(fromIntegral t, [v], b) | (t, v, b) <- alts]
      other -> armRoute ctxJ afterLbl other
    -- The dispatch chain of the inner case: the same @if_icmpne@ ladder as
    -- 'emitMultiArmCaseI' (bindings padded to the widest arm — a frame
    -- inside a later sibling's body covers the whole bind region), except
    -- every arm ends in its own @goto@ (value → after, jump → body), so
    -- there is no fall-through join.
    goInnerCase :: ECtx -> LabelId -> CExpr -> [(Int, [Text], CExpr)] -> AsmM [JvmInstr]
    goInnerCase ctxJ afterLbl scrut alts = do
      (headI, loadScrut, mTagSlot, bindSlotStart, regCtx) <- caseHeadI ctxJ scrut (length alts)
      let sorted = sortWith (\(t, _, _) -> t) alts
          tagSlot = fromMaybe (error "JVM caseHeadI: no tag slot for a multi-arm chain") mTagSlot
          maxBindings = foldl' max 0 [length vs | (_, vs, _) <- sorted]
          next' = bindSlotStart + maxBindings
          n = length sorted
          (stored, regCtx') = bindRegion (armElidedFor scrut) regCtx bindSlotStart next' sorted
          ifFrame = frameAtI regCtx' bindSlotStart False
      armLbls <- replicateM (n - 1) (freshLabel "L_jarm")
      armChunks <- forM sorted $ \(tag, vars, b) -> do
        let bindings = zip vars [bindSlotStart ..]
            ctx' = armPatternCtx scrut vars (regCtx' {cLocals = foldl' (\m (v, s) -> Map.insert v s m) regCtx'.cLocals bindings, cNextLocal = next'})
            bindCode = armBindStores (armElidedFor scrut vars b) stored loadScrut bindSlotStart next' vars b
        routeI <- armRoute ctx' afterLbl b
        pure (tag, bindCode <> routeI)
      let preLabels = Nothing : map Just armLbls
          nextTargets = map Just armLbls <> [Nothing]
          buildArm ((tag, armCode), (preLbl, nextLbl)) =
            maybe [] (\l -> [Label l (Just ifFrame)]) preLbl
              <> maybe [] (\l -> [Iload tagSlot, LoadInt32 (fromIntegral tag), IfICmpNe l]) nextLbl
              <> armCode
          chainCode = concatMap buildArm (zip armChunks (zip preLabels nextTargets))
      pure (headI <> chainCode)
    -- One inner-arm body: a jump (under its transparent drop wrappers)
    -- stores its arguments and branches to the join body; anything else is
    -- an ordinary value that trampolines to the after label.
    armRoute :: ECtx -> LabelId -> CExpr -> AsmM [JvmInstr]
    armRoute ctxA afterLbl b0 = case peelDrops b0 of
      CJump j' args
        | Just (lbl, tps, _) <- Map.lookup j' ctxA.cJoinTargets -> do
            argStores <- forM (zip args tps) $ \(a, p) -> do
              ai <- emitExprI ctxA a
              pure (ai <> [Astore (namedSlotOf ctxA p)])
            pure (concat argStores <> [Goto lbl])
      CJump j' _ -> error ("JVM codegen: CJump to unknown join " <> j' <> " (pipeline bug)")
      _ -> do
        valI <- emitExprI ctxA b0
        pure (valI <> [Goto afterLbl])
    peelDrops :: CExpr -> CExpr
    peelDrops = \case
      CDrop _ b -> peelDrops b
      e -> e

-- | Shared cell builder for 'CCon' / 'CReuse': @<allocOrLoad>@ leaves the
--   @Object[]@ on the stack, then store the boxed tag at [0] and each field at
--   [1..]. Per-field shape is a dup/iconst/aastore chain.
--
--   When a field contains a /multi-arm/ case, its StackMapTable frames would
--   declare an empty operand stack while the cell ref (and dup'd index) still
--   sit there — so every field is first evaluated into a save local
--   ('saveExprsToLocalsI', the same discipline 'emitArgsViaLocalsI' applies to
--   call args) and the cell is then built from the locals. Field evaluation
--   order is unchanged (left-to-right); only the alloc moves after it, which
--   is unobservable — Core is pure, effects are data. The branch-free path
--   keeps the inline shape so existing output is untouched.
emitCellI :: ECtx -> [JvmInstr] -> Int32 -> [CExpr] -> AsmM [JvmInstr]
emitCellI ctx alloc tag fields
  | all noMultiArmCase fields = do
      fieldCode <- forM (zip fields [1 :: Int ..]) $ \(fld, i) -> do
        fldInstrs <- emitExprI ctx fld
        pure ([Dup, PushInt i] <> fldInstrs <> [AAStore])
      pure $ alloc <> tagStore <> concat fieldCode
  | otherwise = do
      (saves, slots) <- saveExprsToLocalsI ctx fields
      pure $ saves <> alloc <> tagStore <> concat [[Dup, PushInt i, Aload s, AAStore] | (s, i) <- zip slots [1 :: Int ..]]
  where
    tagStore = [Dup, PushInt 0, LoadInt32 tag, InvokeStatic integerValueOfRef, AAStore]

-- | Evaluate each expression with an empty operand stack into a fresh save
--   local; returns the save code and the slot per expression. Save slot
--   @i = cNextLocal + i@; each expression is emitted with 'cNextLocal'
--   advanced past all save slots and the not-yet-stored save slots
--   ('save_i' onward) added to 'cUninitSlots' so a nested case's frames type
--   them @top@ via 'slotVTypeI'. Shared by 'emitArgsViaLocalsI' (call args)
--   and 'emitCellI' (cell fields holding a multi-arm case).
saveExprsToLocalsI :: ECtx -> [CExpr] -> AsmM ([JvmInstr], [Int])
saveExprsToLocalsI ctx exprs = do
  let firstSlot = ctx.cNextLocal
      n = length exprs
  chunks <- forM (zip exprs [0 ..]) $ \(e, i) -> do
    let slot = firstSlot + i
        uninitForExpr = Set.fromList [firstSlot + j | j <- [i .. n - 1]] `Set.union` ctx.cUninitSlots
        ctx' = ctx {cNextLocal = firstSlot + n, cUninitSlots = uninitForExpr}
    ei <- emitExprI ctx' e
    pure (ei <> [Astore slot])
  pure (concat chunks, [firstSlot .. firstSlot + n - 1])

-- | Evaluate each arg with an empty operand stack by saving every arg into a
--   fresh local ('saveExprsToLocalsI'), then load them all back in order ready
--   for the call. Used when any arg contains a 'CCase' (its frames declare an
--   empty stack, which prior args on the stack would contradict).
emitArgsViaLocalsI :: ECtx -> [CExpr] -> AsmM [JvmInstr]
emitArgsViaLocalsI ctx args = do
  (saves, slots) <- saveExprsToLocalsI ctx args
  pure $ saves <> map Aload slots

-- | 'CCall' dispatch for the unified emitter: every prelude built-in becomes an
--   @invokestatic@ to its @AwsumMain.__helper@, direct calls to known functions
--   become @invokestatic@ to the mangled name. Args go through 'callArgs',
--   which routes case-containing args through 'emitArgsViaLocalsI'.
emitCallI :: ECtx -> CExpr -> [CExpr] -> AsmM [JvmInstr]
emitCallI ctx f xs = case f of
  CBuiltIn "internalStdoutPrint" | [x] <- xs -> unary x "__print"
  CBuiltIn "internalStdinReadAllString"
    | [] <- xs ->
        pure [InvokeStatic (MethodRef "AwsumMain" "__stdinReadAll" "()Ljava/lang/Object;")]
  CBuiltIn "internalStdinReadAllBytes"
    | [] <- xs ->
        pure [InvokeStatic (MethodRef "AwsumMain" "__stdinReadAllBytes" "()Ljava/lang/Object;")]
  CBuiltIn "internalGetArgs"
    | [] <- xs ->
        pure [InvokeStatic (MethodRef "AwsumMain" "__getArgs" "()Ljava/lang/Object;")]
  CBuiltIn name
    | name == "showInt32" || name == "showUInt8",
      [x] <- xs -> do
        ai <- callArgs [x]
        pure $ ai <> [CheckCast integerClassRef, InvokeVirtual (MethodRef "java/lang/Integer" "toString" "()Ljava/lang/String;")]
  -- byteToHexStringNoPrefix: 'Integer.toHexString(256 + v).substring(1)' —
  -- adding 256 forces a leading "1" so the result is always 3 chars
  -- ("100".."1ff"); dropping it leaves two zero-padded lowercase hex digits.
  CBuiltIn "byteToHexStringNoPrefix"
    | [x] <- xs -> do
        ai <- callArgs [x]
        pure
          $ ai
          <> [ CheckCast integerClassRef,
               InvokeVirtual (MethodRef "java/lang/Integer" "intValue" "()I"),
               PushInt 256,
               IAdd,
               InvokeStatic (MethodRef "java/lang/Integer" "toHexString" "(I)Ljava/lang/String;"),
               PushInt 1,
               InvokeVirtual (MethodRef "java/lang/String" "substring" "(I)Ljava/lang/String;")
             ]
  CBuiltIn "showUInt32" | [x] <- xs -> unary x "__showUInt32"
  CBuiltIn "predInt32" | [x] <- xs -> unary x "__predInt32"
  CBuiltIn "predUInt8" | [x] <- xs -> unary x "__predUInt8"
  CBuiltIn "predUInt32" | [x] <- xs -> unary x "__predUInt32"
  CBuiltIn "succInt32" | [x] <- xs -> unary x "__succInt32"
  CBuiltIn "succUInt8" | [x] <- xs -> unary x "__succUInt8"
  CBuiltIn "succUInt32" | [x] <- xs -> unary x "__succUInt32"
  CBuiltIn "negInt32" | [x] <- xs -> unary x "__negInt32"
  CBuiltIn name
    | name == "eqInt32" || name == "eqUInt8" || name == "eqUInt32" || name == "eqString",
      [a, b] <- xs ->
        binary a b $ case name of
          "eqInt32" -> "__eqInt32"
          "eqUInt8" -> "__eqUInt8"
          "eqUInt32" -> "__eqUInt32"
          _ -> "__eqString"
  CBuiltIn name
    | name `elem` ["addInt32", "addUInt8", "addUInt32", "subInt32", "subUInt8", "subUInt32", "mulInt32", "mulUInt8", "mulUInt32"],
      [a, b] <- xs ->
        binary a b $ case name of
          "addInt32" -> "__addInt32"
          "addUInt8" -> "__addUInt8"
          "addUInt32" -> "__addUInt32"
          "subInt32" -> "__subInt32"
          "subUInt8" -> "__subUInt8"
          "subUInt32" -> "__subUInt32"
          "mulInt32" -> "__mulInt32"
          "mulUInt32" -> "__mulUInt32"
          _ -> "__mulUInt8"
  CBuiltIn "concatString" | [a, b] <- xs -> binary a b "__concat"
  CBuiltIn "splitOnFirst" | [a, b] <- xs -> binary a b "__splitOnFirst"
  CBuiltIn name
    | name == "parseInt32" || name == "parseUInt8" || name == "parseUInt32",
      [x] <- xs ->
        unary x $ case name of
          "parseInt32" -> "__parseInt32"
          "parseUInt32" -> "__parseUInt32"
          _ -> "__parseUInt8"
  CBuiltIn name
    | name == "lengthCodePoints" || name == "lengthUtf16CodeUnits" || name == "lengthUtf8Bytes",
      [x] <- xs ->
        unary x $ case name of
          "lengthCodePoints" -> "__lengthCodePoints"
          "lengthUtf16CodeUnits" -> "__lengthUtf16CodeUnits"
          _ -> "__lengthUtf8Bytes"
  CBuiltIn n ->
    error ("emitExprI: unknown builtin '" <> n <> "' reached CCall")
  CVar n | n `Set.member` ctx.cFunDefs -> do
    argInstrs <- callArgs xs
    pure $ argInstrs <> [InvokeStatic (MethodRef "AwsumMain" (mangle n) (objMethodDesc (length xs)))]
  _ -> error "emitExprI: indirect (MethodHandle) call — unreachable after LowerClosures"
  where
    -- Emit the arguments, leaving them on the stack in order ready for the
    -- call's @invoke@. When any arg contains a 'CCase' the prior args would
    -- still be on the stack at the case's branch targets, so route every arg
    -- through a fresh local first ('emitArgsViaLocalsI', which marks the not-
    -- yet-stored save slots @top@ in those frames); otherwise emit inline.
    callArgs args
      | any exprContainsCase args = emitArgsViaLocalsI ctx args
      | otherwise = concat <$> traverse (emitExprI ctx) args
    unary x fn = do
      ai <- callArgs [x]
      pure $ ai <> [InvokeStatic (MethodRef "AwsumMain" fn "(Ljava/lang/Object;)Ljava/lang/Object;")]
    binary a b fn = do
      ai <- callArgs [a, b]
      pure $ ai <> [InvokeStatic (MethodRef "AwsumMain" fn "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;")]

-- | Tail-position emitter: lowers a tail-form Core expression to '[JvmInstr]'.
--   @loopLbl@ is the method's entry label (a 'CContinue' loops back to it). 'CContinue' evaluates the new parameter
--   values onto the stack, drains the drops for binders it does not rebind, @astore@s the
--   values into the param slots in reverse (LIFO, so cross-parameter reads see
--   the old bindings), and @goto@s @loopLbl@. A value tail drains drops then
--   @areturn@s. A tail 'CCase' dispatches via an @if_icmpne@ chain where each
--   arm body is itself tail (self-terminating) — so there is no join frame,
--   only an 'ifFrame' at each next-arm label. 'CDrop' buffers a parameter drop
--   ('pending') drained at the next terminator (memory-management.md: JVM
--   parameter drop = @aconst_null; astore@; arm binders are GC-collected).
emitTailBinI :: ECtx -> [Text] -> LabelId -> CExpr -> AsmM [JvmInstr]
emitTailBinI ctx0 params loopLbl = goTop ctx0 []
  where
    binderSlot ctx n = Map.lookup n ctx.cLocals <|> Map.lookup n ctx.cParams
    pendingDrops ctx = concatMap (maybe [] (\s -> [AconstNull, Astore s]) . binderSlot ctx)
    goTop ctx pending = \case
      CContinue newArgs -> emitContinue ctx pending newArgs
      CCase scrut alts -> emitTailCase ctx pending scrut alts
      CRowCase scrut alts -> emitTailCase ctx pending scrut [(fromIntegral t, [v], b) | (t, v, b) <- alts]
      CDrop n body -> goTop ctx (n : pending) body
      CLet x rhs body -> do
        (bindI, ctx') <- emitLetBindI ctx x rhs
        bodyI <- goTop ctx' pending body
        pure (bindI <> bodyI)
      -- Native join point: the inner expression continues the tail walk with
      -- the target registered (its jumps store the parameter slots and
      -- @goto@ the body label; its value tails @areturn@ and its 'CContinue'
      -- arms @goto@ the loop entry, both past the body); the body follows
      -- the label, emitted with the parameters in scope — their slots leave
      -- 'cUninitSlots', since every edge into the label has stored them.
      -- Whatever was pending at the node stays pending for the body: those
      -- binders wrap the whole join and die at its terminals.
      CJoin j ps body inner -> do
        bodyLbl <- freshLabel "L_jbody"
        let psSlots = map (namedSlotOf ctx) ps
            ctxJ = ctx {cJoinTargets = Map.insert j (bodyLbl, ps, length pending) ctx.cJoinTargets}
            ctxB =
              ctx
                { cLocals = foldl' (\m (p, s) -> Map.insert p s m) ctx.cLocals (zip ps psSlots),
                  cUninitSlots = flipfoldl' Set.delete ctx.cUninitSlots psSlots
                }
            bodyFrame = frameAtI ctxB ctx.cNextLocal False
        innerI <- goTop ctxJ pending inner
        bodyI <- goTop ctxB pending body
        pure (innerI <> [Label bodyLbl (Just bodyFrame)] <> bodyI)
      -- Mirror of 'CContinue', branching forward: evaluate each argument on
      -- an empty stack straight into its parameter slot (the parameters are
      -- not in scope inside the inner expression, so no argument can read
      -- them — no parallel-assignment two-step, and a multi-arm case in an
      -- argument needs no save-locals routing), null the parameter drops
      -- accumulated since the node (the jumping arm's deaths; the body
      -- still runs, so they would stay GC roots through it), and @goto@ the
      -- body label. The base pending stays for the body's own terminals.
      CJump j args
        | Just (lbl, tps, base) <- Map.lookup j ctx.cJoinTargets -> do
            argStores <- forM (zip args tps) $ \(a, p) -> do
              ai <- emitExprI ctx a
              pure (ai <> [Astore (namedSlotOf ctx p)])
            let delta = take (length pending - base) pending
            pure (concat argStores <> pendingDrops ctx delta <> [Goto lbl])
      CJump j _ -> error ("JVM codegen: CJump to unknown join " <> j <> " (pipeline bug)")
      other -> emitTailValue ctx pending other
    emitContinue ctx pending newArgs = do
      -- A multi-arm case in an argument cannot evaluate while prior args sit
      -- on the operand stack (its frames declare it empty) — route all args
      -- through save locals first, like call args and cell fields. The
      -- parallel-assignment discipline holds on both paths: every new value
      -- is fully computed (on the stack or in locals) before the first
      -- param slot is overwritten.
      argsI <-
        if all noMultiArmCase newArgs
          then concat <$> traverse (emitExprI ctx) newArgs
          else do
            (saves, slots) <- saveExprsToLocalsI ctx newArgs
            pure (saves <> map Aload slots)
      let paramSlots = [fromMaybe (error ("JVM Assemble: no param slot for " <> p)) (Map.lookup p ctx.cParams) | p <- params]
          astores = concatMap (\s -> [Astore s]) (reverse paramSlots)
          -- A param this 'CContinue' rebinds needs no null-out: the
          -- 'astore' overwrites the slot with nothing allocating in
          -- between, so its old graph is already unreachable on the next
          -- iteration. Drops on binders not rebound here still drain.
          dropsNotRebound = filter (`notElem` params) pending
      pure $ argsI <> pendingDrops ctx dropsNotRebound <> astores <> [Goto loopLbl]
    emitTailValue ctx pending expr = do
      ei <- emitExprI ctx expr
      pure $ ei <> pendingDrops ctx pending <> [AReturn]
    emitTailCase ctx pending scrut alts = do
      (headI, loadScrut, mTagSlot, bindSlotStart, regCtx) <- caseHeadI ctx scrut (length alts)
      let sorted = sortWith (\(t, _, _) -> t) alts
          tagSlot = fromMaybe (error "JVM caseHeadI: no tag slot for a multi-arm chain") mTagSlot
          maxBindings = foldl' max 0 [length vs | (_, vs, _) <- sorted]
          next' = bindSlotStart + maxBindings
          n = length sorted
          (stored, regCtx') = bindRegion (armElidedFor scrut) regCtx bindSlotStart next' sorted
          ifFrame = frameAtI regCtx' bindSlotStart False
      armLbls <- replicateM (n - 1) (freshLabel "L_tarm")
      armChunks <- forM sorted $ \(tag, vars, body) -> do
        let bindings = zip vars [bindSlotStart ..]
            ctx' = armPatternCtx scrut vars (regCtx' {cLocals = foldl' (\m (v, s) -> Map.insert v s m) regCtx'.cLocals bindings, cNextLocal = next'})
            bindCode = armBindStores (armElidedFor scrut vars body) stored loadScrut bindSlotStart next' vars body
        bodyI <- goTop ctx' pending body -- arm body is itself tail
        pure (bindCode <> bodyI, tag)
      let preLabels = Nothing : map Just armLbls
          nextTargets = map Just armLbls <> [Nothing]
          buildArm ((armCode, tag), (preLbl, nextLbl)) =
            maybe [] (\l -> [Label l (Just ifFrame)]) preLbl
              <> maybe [] (\l -> [Iload tagSlot, LoadInt32 (fromIntegral tag), IfICmpNe l]) nextLbl
              <> armCode -- self-terminating; no goto-join
          chainCode = concatMap buildArm (zip armChunks (zip preLabels nextTargets))
      pure $ headI <> chainCode

-- | @(Ljava/lang/Object;...)Ljava/lang/Object;@ for N args.
objMethodDesc :: Int -> Text
objMethodDesc n =
  "(" <> T.replicate n "Ljava/lang/Object;" <> ")Ljava/lang/Object;"

-- ════════════════════════════════════════════════════════════════════════════
-- Class file serialization
-- ════════════════════════════════════════════════════════════════════════════

buildClassFile :: Pool -> Word16 -> Word16 -> [MInfo] -> B.Builder
buildClassFile st argvFieldNameIdx argvFieldDescIdx methods =
  let cpList = reverse st.entries
      thisCls = lkup (KClass "AwsumMain")
      superCls = lkup (KClass "java/lang/Object")
      codeUtf8 = lkup (KUtf8 "Code")
      -- One static field: 'private static __argv [Ljava/lang/String;'.
      -- ACC_PRIVATE | ACC_STATIC = 0x000A. Zero attributes.
      argvField =
        B.word16BE 0x000A
          <> B.word16BE argvFieldNameIdx
          <> B.word16BE argvFieldDescIdx
          <> B.word16BE 0
   in mconcat
        [ B.word32BE 0xCAFEBABE,
          B.word16BE 0, -- minor version
          B.word16BE 55, -- major version (Java 11)
          B.word16BE st.nextIdx, -- constant_pool_count
          foldMap encodeCPEntry cpList,
          B.word16BE 0x0021, -- ACC_PUBLIC | ACC_SUPER
          B.word16BE thisCls,
          B.word16BE superCls,
          B.word16BE 0, -- interfaces
          B.word16BE 1, -- fields
          argvField,
          B.word16BE (fromIntegral (length methods)),
          foldMap (encodeMethod codeUtf8) methods,
          B.word16BE 0 -- class attributes
        ]
  where
    lkup :: CPKey -> Word16
    lkup k = fromMaybe (error "missing CP entry") (Map.lookup k st.cache)

encodeCPEntry :: CPEntry -> B.Builder
encodeCPEntry = \case
  CPUtf8 bs ->
    B.word8 1 <> B.word16BE (fromIntegral (BS.length bs)) <> B.byteString bs
  CPInteger v ->
    B.word8 3 <> B.int32BE v
  CPString i ->
    B.word8 8 <> B.word16BE i
  CPClass i ->
    B.word8 7 <> B.word16BE i
  CPNameAndType a b ->
    B.word8 12 <> B.word16BE a <> B.word16BE b
  CPFieldref a b ->
    B.word8 9 <> B.word16BE a <> B.word16BE b
  CPMethodref a b ->
    B.word8 10 <> B.word16BE a <> B.word16BE b
  CPMethodHandle k r ->
    B.word8 15 <> B.word8 k <> B.word16BE r
  CPMethodType d ->
    B.word8 16 <> B.word16BE d

encodeMethod :: Word16 -> MInfo -> B.Builder
encodeMethod codeNameIdx mi =
  let codeBS = BS.pack mi.mCode
      codeAttrsBS = BS.pack mi.mCodeAttrs
      codeLen = fromIntegral (BS.length codeBS) :: Word32
      codeAttrsLen = fromIntegral (BS.length codeAttrsBS) :: Word32
      -- Code attribute length: max_stack(2) + max_locals(2) + code_length(4)
      --   + code + exception_table_length(2) + attributes_count(2) + attributes
      attrLen = 2 + 2 + 4 + codeLen + 2 + 2 + codeAttrsLen :: Word32
   in B.word16BE mi.mFlags
        <> B.word16BE mi.mName
        <> B.word16BE mi.mDesc
        <> B.word16BE 1 -- 1 attribute (Code)
        <> B.word16BE codeNameIdx
        <> B.word32BE attrLen
        <> B.word16BE (fromIntegral mi.mMaxStack)
        <> B.word16BE (fromIntegral mi.mMaxLocals)
        <> B.word32BE codeLen
        <> B.byteString codeBS
        <> B.word16BE 0 -- exception table
        <> B.word16BE mi.mCodeAttrCount
        <> B.byteString codeAttrsBS
