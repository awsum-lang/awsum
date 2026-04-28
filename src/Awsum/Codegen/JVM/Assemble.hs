-- | JVM .class file assembler for Awsum 'Core'.
--
-- Generates a single @AwsumMain.class@ file (class version 51.0, Java 7+)
-- containing runtime helpers, user declarations, and a @main(String[])@
-- entry point.
--
-- All values are @java\/lang\/Object@; strings are @java\/lang\/String@;
-- function references are @java\/lang\/invoke\/MethodHandle@; @IO Unit@ is @null@.
module Awsum.Codegen.JVM.Assemble (assembleJVM) where

import Awsum.Core
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

-- | Produce a complete .class file as a strict ByteString.
assembleJVM :: CoreProgram -> BS.ByteString
assembleJVM prog =
  let (methods, finalSt) = runState (doAssemble prog) emptyPool
   in toStrict (B.toLazyByteString (buildClassFile finalSt methods))

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
    cache :: Map CPKey Word16
  }

emptyPool :: Pool
emptyPool = Pool {entries = [], nextIdx = 1, cache = Map.empty}

type AsmM = State Pool

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
addUtf8 t = addEntry (KUtf8 t) (CPUtf8 (encodeUtf8 t))

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

addMHandle :: Word8 -> Text -> Text -> Text -> AsmM Word16
addMHandle kind cls name desc = do
  mi <- addMRef cls name desc
  addEntry (KMethodHandle kind cls name desc) (CPMethodHandle kind mi)

-- ════════════════════════════════════════════════════════════════════════════
-- Byte helpers
-- ════════════════════════════════════════════════════════════════════════════

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

-- | @goto@ with a 2-byte signed offset, properly encoded for negative
-- deltas via 'Word16' wrap. Used by TCO to branch backward from inside
-- the body to the method's first instruction (offset 0).
bcGoto :: Int -> [Word8]
bcGoto delta =
  let w = fromIntegral delta :: Word16
   in [0xA7, hi8 w, lo8 w]

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
    mName :: Word16,
    mDesc :: Word16,
    mCode :: [Word8],
    mCodeAttrCount :: Word16,
    mCodeAttrs :: [Word8],
    -- | Maximum operand-stack depth this method ever reaches
    -- (JVM Spec §4.7.3 max_stack). Verifier rejects methods whose
    -- actual depth exceeds the declared value.
    mMaxStack :: Word16,
    -- | Number of local variable slots this method requires
    -- (JVM Spec §4.7.3 max_locals), counting params + every additive
    -- nested 'CCase' / 'CCon' slot. The verifier rejects any
    -- StackMapTable frame whose number_of_locals exceeds this value
    -- with @bad type array size@ — that's what hardcoding it to 256
    -- was producing for deeply nested 'case' programs (depth ≥ ~250).
    mMaxLocals :: Word16
  }

-- ════════════════════════════════════════════════════════════════════════════
-- Full assembly
-- ════════════════════════════════════════════════════════════════════════════

doAssemble :: CoreProgram -> AsmM [MInfo]
doAssemble prog@(CoreProgram decls) = do
  -- Ensure required CP entries exist
  void $ addClass "AwsumMain"
  void $ addClass "java/lang/Object"
  void $ addUtf8 "Code"

  let valNames = Set.fromList [n | CValDef n _ <- decls]
      funNames = Set.fromList [n | CFunDef n _ _ <- decls]
      arities = Map.fromList [(n, length as) | CFunDef n as _ <- decls]
      builtIns = usedBuiltIns prog

  m0 <- mkInit
  -- Runtime helpers are emitted only when referenced in Core, so hello-world
  -- style programs that never call 'showInt32' or 'predInt32' don't pay for them.
  m1s <- if Set.member "concatString" builtIns then (: []) <$> mkConcat else pure []
  m2s <- if Set.member "IO.Stdout.print" builtIns then (: []) <$> mkPrint else pure []
  m3s <- if Set.member "predInt32" builtIns then (: []) <$> mkPredInt32 else pure []
  m3us <- if Set.member "predUInt8" builtIns then (: []) <$> mkPredUInt8 else pure []
  m3sI <- if Set.member "succInt32" builtIns then (: []) <$> mkSuccInt32 else pure []
  m3sU <- if Set.member "succUInt8" builtIns then (: []) <$> mkSuccUInt8 else pure []
  m4s <- if Set.member "eqInt32" builtIns then (: []) <$> mkEq "__eqInt32" else pure []
  m5s <- if Set.member "eqUInt8" builtIns then (: []) <$> mkEq "__eqUInt8" else pure []
  m6s <- if Set.member "addInt32" builtIns then (: []) <$> mkAddInt32 else pure []
  m6sub <- if Set.member "subInt32" builtIns then (: []) <$> mkSubInt32 else pure []
  m6mul <- if Set.member "mulInt32" builtIns then (: []) <$> mkMulInt32 else pure []
  m6neg <- if Set.member "negInt32" builtIns then (: []) <$> mkNegInt32 else pure []
  m6us <- if Set.member "addUInt8" builtIns then (: []) <$> mkAddUInt8 else pure []
  m6usSub <- if Set.member "subUInt8" builtIns then (: []) <$> mkSubUInt8 else pure []
  m6usMul <- if Set.member "mulUInt8" builtIns then (: []) <$> mkMulUInt8 else pure []
  m7s <- if Set.member "splitOnFirst" builtIns then (: []) <$> mkSplitOnFirst else pure []
  m8sI <- if Set.member "parseInt32" builtIns then (: []) <$> mkParseInt32 else pure []
  m8sU <- if Set.member "parseUInt8" builtIns then (: []) <$> mkParseUInt8 else pure []
  userMs <- traverse (mkDecl valNames funNames arities) decls
  mEntry <- mkMain
  pure (m0 : m1s <> m2s <> m3s <> m3us <> m3sI <> m3sU <> m4s <> m5s <> m6s <> m6sub <> m6mul <> m6neg <> m6us <> m6usSub <> m6usMul <> m7s <> m8sI <> m8sU <> userMs <> [mEntry])

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

mkConcat :: AsmM MInfo
mkConcat = do
  ni <- addUtf8 "__concat"
  di <- addUtf8 "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"
  strCls <- addClass "java/lang/String"
  concatRef <- addMRef "java/lang/String" "concat" "(Ljava/lang/String;)Ljava/lang/String;"
  pure
    MInfo
      { mFlags = 0x0008,
        mName = ni,
        mDesc = di,
        mCode =
          bcAload 0
            <> bcCheckCast strCls
            <> bcAload 1
            <> bcCheckCast strCls
            <> bcInvokeVirtual concatRef
            <> [0xB0], -- areturn
        mCodeAttrCount = 0,
        mCodeAttrs = [],
        mMaxStack = 256,
        mMaxLocals = 256
      }

mkPrint :: AsmM MInfo
mkPrint = do
  ni <- addUtf8 "__print"
  di <- addUtf8 "(Ljava/lang/Object;)Ljava/lang/Object;"
  outRef <- addFRef "java/lang/System" "out" "Ljava/io/PrintStream;"
  printRef <- addMRef "java/io/PrintStream" "print" "(Ljava/lang/Object;)V"
  pure
    MInfo
      { mFlags = 0x0008,
        mName = ni,
        mDesc = di,
        mCode =
          bcGetStatic outRef
            <> bcAload 0
            <> bcInvokeVirtual printRef
            <> [0x01, 0xB0], -- aconst_null, areturn
        mCodeAttrCount = 0,
        mCodeAttrs = [],
        mMaxStack = 256,
        mMaxLocals = 256
      }

-- | predInt32: Int32 -> Either UnderflowError Int32.
--   Layout on the JVM: containers are 'Object[]' with a boxed Integer
--   tag at [0] and fields at [1..], matching user CCon emission. Tags:
--   Left=0 (first Either constructor), Right=1, UnderflowError=0.
--   The method unboxes the Integer argument, compares against
--   INT32_MIN via 'if_icmpne', and branches to build either
--   'Left UnderflowError' or 'Right Integer.valueOf(v - 1)'.
--   A StackMapTable entry at the ok-branch target is required because
--   classfile v51+ demands one for any branch.
mkPredInt32 :: AsmM MInfo
mkPredInt32 = do
  ni <- addUtf8 "__predInt32"
  di <- addUtf8 "(Ljava/lang/Object;)Ljava/lang/Object;"
  intCls <- addClass "java/lang/Integer"
  intValRef <- addMRef "java/lang/Integer" "intValue" "()I"
  valueOfRef <- addMRef "java/lang/Integer" "valueOf" "(I)Ljava/lang/Integer;"
  objCls <- addClass "java/lang/Object"
  smtNameIdx <- addUtf8 "StackMapTable"
  minLoad <- bcLoadInt32 (-2147483648)
  let preamble =
        [0x2A] -- aload_0
          <> [0xC0, hi8 intCls, lo8 intCls] -- checkcast Integer
          <> [0xB6, hi8 intValRef, lo8 intValRef] -- invokevirtual intValue()I
          <> [0x3C] -- istore_1
          <> [0x1B] -- iload_1
          <> minLoad
      ifAt = length preamble
      overflow =
        -- Build UnderflowError Object[1] = [Integer(0)]
        [0x04] -- iconst_1 (array length)
          <> [0xBD, hi8 objCls, lo8 objCls] -- anewarray Object
          <> [0x59] -- dup
          <> [0x03] -- iconst_0 (idx)
          <> [0x03] -- iconst_0 (tag value 0 for UnderflowError)
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53] -- aastore
          <> [0x4D] -- astore_2 (save UE)
          -- Build Left Object[2] = [Integer(0), UE]
          <> [0x05] -- iconst_2
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59] -- dup
          <> [0x03] -- iconst_0
          <> [0x03] -- iconst_0 (Left tag)
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53] -- aastore
          <> [0x59] -- dup
          <> [0x04] -- iconst_1 (idx)
          <> [0x2C] -- aload_2
          <> [0x53] -- aastore
          <> [0xB0] -- areturn
      okAt = ifAt + 3 + length overflow
      ok =
        -- Build Right Object[2] = [Integer(1), Integer(v - 1)]
        [0x05] -- iconst_2
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59] -- dup
          <> [0x03] -- iconst_0
          <> [0x04] -- iconst_1 (Right tag)
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53] -- aastore
          <> [0x59] -- dup
          <> [0x04] -- iconst_1 (idx)
          <> [0x1B] -- iload_1
          <> [0x04] -- iconst_1
          <> [0x64] -- isub
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53] -- aastore
          <> [0xB0] -- areturn
      ifRel = okAt - ifAt
      ifBytes = [0xA0, fromIntegral (ifRel `div` 256), fromIntegral (ifRel `mod` 256)]
      code = preamble <> ifBytes <> overflow <> ok
      -- StackMapTable: one append_frame at ok-branch target.
      -- locals change from [Object] (initial) to [Object, int] (after istore_1).
      -- frame_type 252 = append_frame with 1 new local;
      -- verification_type_info tag 1 = ITEM_Integer.
      okAt16 = fromIntegral okAt :: Word16
      smtEntries = [252, hi8 okAt16, lo8 okAt16, 0x01]
      smtEntriesLen = length smtEntries
      smtAttr =
        [hi8 smtNameIdx, lo8 smtNameIdx]
          <> let totalLen = fromIntegral (2 + smtEntriesLen) :: Word32
              in [ fromIntegral (totalLen `div` 16777216),
                   fromIntegral ((totalLen `div` 65536) `mod` 256),
                   fromIntegral ((totalLen `div` 256) `mod` 256),
                   fromIntegral (totalLen `mod` 256)
                 ]
                   <> [0, 1] -- number_of_entries = 1
                   <> smtEntries
  pure
    MInfo
      { mFlags = 0x0008,
        mName = ni,
        mDesc = di,
        mCode = code,
        mCodeAttrCount = 1,
        mCodeAttrs = smtAttr,
        mMaxStack = 256,
        mMaxLocals = 256
      }

-- | predUInt8: UInt8 -> Either UnderflowError UInt8.
--   Mirrors 'mkPredInt32' except the zero check uses 'ifne' (opcode 0x9A,
--   "branch if int != 0") instead of 'if_icmpne' against a pushed
--   constant — no extra push is needed, so the preamble is 9 bytes
--   (aload_0 + checkcast + invokevirtual + istore_1 + iload_1) instead
--   of 12. No mask on (v - 1): when v >= 1 the result is 0..254.
mkPredUInt8 :: AsmM MInfo
mkPredUInt8 = do
  ni <- addUtf8 "__predUInt8"
  di <- addUtf8 "(Ljava/lang/Object;)Ljava/lang/Object;"
  intCls <- addClass "java/lang/Integer"
  intValRef <- addMRef "java/lang/Integer" "intValue" "()I"
  valueOfRef <- addMRef "java/lang/Integer" "valueOf" "(I)Ljava/lang/Integer;"
  objCls <- addClass "java/lang/Object"
  smtNameIdx <- addUtf8 "StackMapTable"
  let preamble =
        [0x2A] -- aload_0
          <> [0xC0, hi8 intCls, lo8 intCls] -- checkcast Integer
          <> [0xB6, hi8 intValRef, lo8 intValRef] -- invokevirtual intValue()I
          <> [0x3C] -- istore_1
          <> [0x1B] -- iload_1
      ifAt = length preamble
      overflow =
        -- UnderflowError instance: Object[1] = [Integer(0)]
        [0x04] -- iconst_1
          <> [0xBD, hi8 objCls, lo8 objCls] -- anewarray Object
          <> [0x59] -- dup
          <> [0x03] -- iconst_0 (index)
          <> [0x03] -- iconst_0 (UE tag)
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53] -- aastore
          <> [0x4D] -- astore_2 (save UE)
          -- Left: Object[2] = [Integer(0), UE]
          <> [0x05] -- iconst_2
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59] -- dup
          <> [0x03] -- iconst_0
          <> [0x03] -- iconst_0 (Left tag)
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53] -- aastore
          <> [0x59] -- dup
          <> [0x04] -- iconst_1 (index)
          <> [0x2C] -- aload_2
          <> [0x53] -- aastore
          <> [0xB0] -- areturn
      okAt = ifAt + 3 + length overflow
      ok =
        -- Right: Object[2] = [Integer(1), Integer(v - 1)]
        [0x05] -- iconst_2
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59] -- dup
          <> [0x03] -- iconst_0
          <> [0x04] -- iconst_1 (Right tag)
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53] -- aastore
          <> [0x59] -- dup
          <> [0x04] -- iconst_1 (index)
          <> [0x1B] -- iload_1
          <> [0x04] -- iconst_1
          <> [0x64] -- isub
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53] -- aastore
          <> [0xB0] -- areturn
      ifRel = okAt - ifAt
      ifBytes = [0x9A, fromIntegral (ifRel `div` 256), fromIntegral (ifRel `mod` 256)]
      code = preamble <> ifBytes <> overflow <> ok
      -- First (and only) frame at okAt. Locals change from [Object]
      -- (initial) to [Object, int] (after istore_1); frame_type 252 =
      -- append_frame with 1 new local (ITEM_Integer = tag 1).
      okAt16 = fromIntegral okAt :: Word16
      smtEntries = [252, hi8 okAt16, lo8 okAt16, 0x01]
      smtEntriesLen = length smtEntries
      smtAttr =
        [hi8 smtNameIdx, lo8 smtNameIdx]
          <> let totalLen = fromIntegral (2 + smtEntriesLen) :: Word32
              in [ fromIntegral (totalLen `div` 16777216),
                   fromIntegral ((totalLen `div` 65536) `mod` 256),
                   fromIntegral ((totalLen `div` 256) `mod` 256),
                   fromIntegral (totalLen `mod` 256)
                 ]
                   <> [0, 1] -- number_of_entries = 1
                   <> smtEntries
  pure
    MInfo
      { mFlags = 0x0008,
        mName = ni,
        mDesc = di,
        mCode = code,
        mCodeAttrCount = 1,
        mCodeAttrs = smtAttr,
        mMaxStack = 256,
        mMaxLocals = 256
      }

-- | succInt32: Int32 -> Either OverflowError Int32.
--   Mirror of 'mkPredInt32' with boundary INT32_MAX and 'iadd' (0x60)
--   instead of 'isub' (0x64). OverflowError is single-constructor, so
--   its boxed-tag is 0 — the Left-branch encoding is byte-identical to
--   the UnderflowError case.
mkSuccInt32 :: AsmM MInfo
mkSuccInt32 = do
  ni <- addUtf8 "__succInt32"
  di <- addUtf8 "(Ljava/lang/Object;)Ljava/lang/Object;"
  intCls <- addClass "java/lang/Integer"
  intValRef <- addMRef "java/lang/Integer" "intValue" "()I"
  valueOfRef <- addMRef "java/lang/Integer" "valueOf" "(I)Ljava/lang/Integer;"
  objCls <- addClass "java/lang/Object"
  smtNameIdx <- addUtf8 "StackMapTable"
  maxLoad <- bcLoadInt32 2147483647
  let preamble =
        [0x2A] -- aload_0
          <> [0xC0, hi8 intCls, lo8 intCls] -- checkcast Integer
          <> [0xB6, hi8 intValRef, lo8 intValRef] -- invokevirtual intValue()I
          <> [0x3C] -- istore_1
          <> [0x1B] -- iload_1
          <> maxLoad
      ifAt = length preamble
      overflow =
        -- OverflowError instance: Object[1] = [Integer(0)]
        [0x04] -- iconst_1
          <> [0xBD, hi8 objCls, lo8 objCls] -- anewarray Object
          <> [0x59] -- dup
          <> [0x03] -- iconst_0 (index)
          <> [0x03] -- iconst_0 (OE tag)
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53] -- aastore
          <> [0x4D] -- astore_2 (save OE)
          -- Left: Object[2] = [Integer(0), OE]
          <> [0x05] -- iconst_2
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59] -- dup
          <> [0x03] -- iconst_0
          <> [0x03] -- iconst_0 (Left tag)
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53] -- aastore
          <> [0x59] -- dup
          <> [0x04] -- iconst_1 (index)
          <> [0x2C] -- aload_2
          <> [0x53] -- aastore
          <> [0xB0] -- areturn
      okAt = ifAt + 3 + length overflow
      ok =
        -- Right: Object[2] = [Integer(1), Integer(v + 1)]
        [0x05] -- iconst_2
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59] -- dup
          <> [0x03] -- iconst_0
          <> [0x04] -- iconst_1 (Right tag)
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53] -- aastore
          <> [0x59] -- dup
          <> [0x04] -- iconst_1 (index)
          <> [0x1B] -- iload_1
          <> [0x04] -- iconst_1
          <> [0x60] -- iadd
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53] -- aastore
          <> [0xB0] -- areturn
      ifRel = okAt - ifAt
      ifBytes = [0xA0, fromIntegral (ifRel `div` 256), fromIntegral (ifRel `mod` 256)]
      code = preamble <> ifBytes <> overflow <> ok
      okAt16 = fromIntegral okAt :: Word16
      smtEntries = [252, hi8 okAt16, lo8 okAt16, 0x01]
      smtEntriesLen = length smtEntries
      smtAttr =
        [hi8 smtNameIdx, lo8 smtNameIdx]
          <> let totalLen = fromIntegral (2 + smtEntriesLen) :: Word32
              in [ fromIntegral (totalLen `div` 16777216),
                   fromIntegral ((totalLen `div` 65536) `mod` 256),
                   fromIntegral ((totalLen `div` 256) `mod` 256),
                   fromIntegral (totalLen `mod` 256)
                 ]
                   <> [0, 1] -- number_of_entries = 1
                   <> smtEntries
  pure
    MInfo
      { mFlags = 0x0008,
        mName = ni,
        mDesc = di,
        mCode = code,
        mCodeAttrCount = 1,
        mCodeAttrs = smtAttr,
        mMaxStack = 256,
        mMaxLocals = 256
      }

-- | succUInt8: UInt8 -> Either OverflowError UInt8.
--   Mirror of 'mkSuccInt32' with boundary 255 ('sipush 255' = 3-byte
--   inline constant, no constant-pool entry) and no mask on (v + 1),
--   which stays in 1..255 when v <= 254.
mkSuccUInt8 :: AsmM MInfo
mkSuccUInt8 = do
  ni <- addUtf8 "__succUInt8"
  di <- addUtf8 "(Ljava/lang/Object;)Ljava/lang/Object;"
  intCls <- addClass "java/lang/Integer"
  intValRef <- addMRef "java/lang/Integer" "intValue" "()I"
  valueOfRef <- addMRef "java/lang/Integer" "valueOf" "(I)Ljava/lang/Integer;"
  objCls <- addClass "java/lang/Object"
  smtNameIdx <- addUtf8 "StackMapTable"
  let preamble =
        [0x2A] -- aload_0
          <> [0xC0, hi8 intCls, lo8 intCls] -- checkcast Integer
          <> [0xB6, hi8 intValRef, lo8 intValRef] -- invokevirtual intValue()I
          <> [0x3C] -- istore_1
          <> [0x1B] -- iload_1
          <> [0x11, 0x00, 0xFF] -- sipush 255
      ifAt = length preamble
      overflow =
        -- OverflowError instance: Object[1] = [Integer(0)]
        [0x04]
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59]
          <> [0x03]
          <> [0x03]
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53]
          <> [0x4D]
          -- Left: Object[2] = [Integer(0), OE]
          <> [0x05]
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59]
          <> [0x03]
          <> [0x03]
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53]
          <> [0x59]
          <> [0x04]
          <> [0x2C]
          <> [0x53]
          <> [0xB0]
      okAt = ifAt + 3 + length overflow
      ok =
        -- Right: Object[2] = [Integer(1), Integer(v + 1)]
        [0x05]
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59]
          <> [0x03]
          <> [0x04]
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53]
          <> [0x59]
          <> [0x04]
          <> [0x1B]
          <> [0x04]
          <> [0x60] -- iadd
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53]
          <> [0xB0]
      ifRel = okAt - ifAt
      ifBytes = [0xA0, fromIntegral (ifRel `div` 256), fromIntegral (ifRel `mod` 256)]
      code = preamble <> ifBytes <> overflow <> ok
      okAt16 = fromIntegral okAt :: Word16
      smtEntries = [252, hi8 okAt16, lo8 okAt16, 0x01]
      smtEntriesLen = length smtEntries
      smtAttr =
        [hi8 smtNameIdx, lo8 smtNameIdx]
          <> let totalLen = fromIntegral (2 + smtEntriesLen) :: Word32
              in [ fromIntegral (totalLen `div` 16777216),
                   fromIntegral ((totalLen `div` 65536) `mod` 256),
                   fromIntegral ((totalLen `div` 256) `mod` 256),
                   fromIntegral (totalLen `mod` 256)
                 ]
                   <> [0, 1]
                   <> smtEntries
  pure
    MInfo
      { mFlags = 0x0008,
        mName = ni,
        mDesc = di,
        mCode = code,
        mCodeAttrCount = 1,
        mCodeAttrs = smtAttr,
        mMaxStack = 256,
        mMaxLocals = 256
      }

-- | eqInt32 / eqUInt8: two values of the same integer type → Bool.
--   On the JVM both Int32 and UInt8 are boxed as 'java.lang.Integer',
--   so the two methods share a single builder parameterised by name.
--   Returns a one-slot 'Object[]' with boxed tag 0 (True) on equal, 1
--   (False) otherwise — matching declaration order in
--   `type Bool = True | False` and user-code CCon emission.
--   Classfile v51+ requires a StackMapTable at the if_icmpne target;
--   locals don't change across the branch (two Object params, no new
--   stores), so a same_frame is sufficient.
mkEq :: Text -> AsmM MInfo
mkEq methodName = do
  ni <- addUtf8 methodName
  di <- addUtf8 "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"
  intCls <- addClass "java/lang/Integer"
  intValRef <- addMRef "java/lang/Integer" "intValue" "()I"
  valueOfRef <- addMRef "java/lang/Integer" "valueOf" "(I)Ljava/lang/Integer;"
  objCls <- addClass "java/lang/Object"
  smtNameIdx <- addUtf8 "StackMapTable"
  let unbox =
        [0xC0, hi8 intCls, lo8 intCls] -- checkcast Integer
          <> [0xB6, hi8 intValRef, lo8 intValRef] -- invokevirtual intValue()I
      preamble =
        [0x2A] -- aload_0
          <> unbox
          <> [0x2B] -- aload_1
          <> unbox
      -- Both branches build a one-slot Object[] holding a boxed tag.
      boolBox tag =
        [0x04] -- iconst_1 (array length)
          <> [0xBD, hi8 objCls, lo8 objCls] -- anewarray Object
          <> [0x59] -- dup
          <> [0x03] -- iconst_0 (index)
          <> [tag] -- iconst_0 (True=0) or iconst_1 (False=1)
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef] -- Integer.valueOf
          <> [0x53] -- aastore
          <> [0xB0] -- areturn
      equalBlock = boolBox 0x03 -- True tag = 0
      notEqualBlock = boolBox 0x04 -- False tag = 1
      ifAt = length preamble
      notEqAt = ifAt + 3 + length equalBlock
      ifRel = notEqAt - ifAt
      ifBytes = [0xA0, fromIntegral (ifRel `div` 256), fromIntegral (ifRel `mod` 256)]
      code = preamble <> ifBytes <> equalBlock <> notEqualBlock
      -- First (and only) frame at notEqAt. offset_delta = notEqAt (first
      -- frame's delta is the raw bci). Locals unchanged from entry
      -- ([Object, Object]), stack empty — a same_frame covers it when
      -- notEqAt <= 63 (which it is: preamble=14, equalBlock=12, so
      -- notEqAt = 14 + 3 + 12 = 29).
      frameType = fromIntegral notEqAt :: Word8
      smtEntries = [frameType]
      smtEntriesLen = length smtEntries
      smtAttr =
        [hi8 smtNameIdx, lo8 smtNameIdx]
          <> let totalLen = fromIntegral (2 + smtEntriesLen) :: Word32
              in [ fromIntegral (totalLen `div` 16777216),
                   fromIntegral ((totalLen `div` 65536) `mod` 256),
                   fromIntegral ((totalLen `div` 256) `mod` 256),
                   fromIntegral (totalLen `mod` 256)
                 ]
                   <> [0, 1] -- number_of_entries = 1
                   <> smtEntries
  pure
    MInfo
      { mFlags = 0x0008,
        mName = ni,
        mDesc = di,
        mCode = code,
        mCodeAttrCount = 1,
        mCodeAttrs = smtAttr,
        mMaxStack = 256,
        mMaxLocals = 256
      }

-- | addInt32: Int32 -> Int32 -> Either ArithError Int32.
--   The signed-overflow check is done with the classical XOR trick — sum
--   wraps modulo 2^32, then `((a ^ sum) & (b ^ sum)) < 0` is true iff
--   the carry into the sign bit differs from the carry out, which is
--   exactly when signed overflow happens. Direction (over vs under) is
--   read off `a >= 0`: same-sign overflow is positive when `a >= 0`,
--   negative otherwise. Containers are 'Object[]' with boxed Integer
--   tags as everywhere else; ArithError tags follow declaration order
--   in `Prelude.aww`: Underflow=0, Overflow=1.
mkAddInt32 :: AsmM MInfo
mkAddInt32 = do
  ni <- addUtf8 "__addInt32"
  di <- addUtf8 "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"
  intCls <- addClass "java/lang/Integer"
  intValRef <- addMRef "java/lang/Integer" "intValue" "()I"
  valueOfRef <- addMRef "java/lang/Integer" "valueOf" "(I)Ljava/lang/Integer;"
  objCls <- addClass "java/lang/Object"
  smtNameIdx <- addUtf8 "StackMapTable"
  let unbox =
        [0xC0, hi8 intCls, lo8 intCls] -- checkcast Integer
          <> [0xB6, hi8 intValRef, lo8 intValRef] -- invokevirtual intValue()I
          -- Slots 0,1 are the two Object params (left untouched). Locals 2,3,4
          -- hold int a, int b, int sum after unboxing; local 5 is reused for
          -- the boxed sum / boxed AE on the way to the final Object[].
      preamble =
        [0x2A] -- aload_0
          <> unbox
          <> [0x3D] -- istore_2 (a → slot 2)
          <> [0x2B] -- aload_1
          <> unbox
          <> [0x3E] -- istore_3 (b → slot 3)
          <> [0x1C] -- iload_2
          <> [0x1D] -- iload_3
          <> [0x60] -- iadd
          <> [0x36, 0x04] -- istore 4 (sum)
          -- compute ((a ^ sum) & (b ^ sum)); a sign-bit set on overflow.
          <> [0x1C] -- iload_2 (a)
          <> [0x15, 0x04] -- iload 4 (sum)
          <> [0x82] -- ixor
          <> [0x1D] -- iload_3 (b)
          <> [0x15, 0x04] -- iload 4 (sum)
          <> [0x82] -- ixor
          <> [0x7E] -- iand
      iflt1At = length preamble
      ok =
        -- Right: Object[2] = [Integer(1), Integer(sum)]
        [0x05] -- iconst_2
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59] -- dup
          <> [0x03] -- iconst_0
          <> [0x04] -- iconst_1 (Right tag)
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53] -- aastore
          <> [0x59] -- dup
          <> [0x04] -- iconst_1
          <> [0x15, 0x04] -- iload 4
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53] -- aastore
          <> [0xB0] -- areturn
      overAt = iflt1At + 3 + length ok
      iflt1Rel = overAt - iflt1At
      iflt1Bytes = [0x9B, hi8 (fromIntegral iflt1Rel), lo8 (fromIntegral iflt1Rel)] :: [Word8]
      -- L_overflow: split on a >= 0 vs a < 0
      overSplit :: [Word8]
      overSplit =
        [0x1C] -- iload_2 (a)
        -- iflt L_under (placeholder, patched below)
      iflt2At = overAt + length overSplit
      arithBox tag =
        -- Object[1] = [Integer(tag)]
        [0x04] -- iconst_1 (length)
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59] -- dup
          <> [0x03] -- iconst_0
          <> [tag] -- iconst_<tag>
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53] -- aastore
          <> [0x3A, 0x05] -- astore 5
      leftWrap =
        -- Left: Object[2] = [Integer(0), Object @ slot 5]
        [0x05]
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59]
          <> [0x03]
          <> [0x03] -- Left tag
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53]
          <> [0x59]
          <> [0x04]
          <> [0x19, 0x05] -- aload 5
          <> [0x53]
          <> [0xB0]
      overBlock = arithBox 0x04 <> leftWrap -- AE tag 1 = Overflow
      underAt = iflt2At + 3 + length overBlock
      iflt2Rel = underAt - iflt2At
      iflt2Bytes = [0x9B, hi8 (fromIntegral iflt2Rel), lo8 (fromIntegral iflt2Rel)]
      underBlock = arithBox 0x03 <> leftWrap -- AE tag 0 = Underflow
      code =
        preamble
          <> iflt1Bytes
          <> ok
          <> overSplit
          <> iflt2Bytes
          <> overBlock
          <> underBlock
      -- Two stack-map frames: at L_overflow (overAt) and L_under (underAt).
      -- Locals at both points: [Object, Object, int, int, int].
      -- Stack at both: empty.
      -- First frame: append_frame with 3 new locals (slots 2/3/4 = int).
      -- Second frame: same_frame (locals identical to previous frame).
      overAt16 = fromIntegral overAt :: Word16
      underDelta = fromIntegral (underAt - overAt - 1) :: Word8
      smtEntries =
        [254, hi8 overAt16, lo8 overAt16, 0x01, 0x01, 0x01]
          <> [underDelta]
      smtEntriesLen = length smtEntries
      smtAttr =
        [hi8 smtNameIdx, lo8 smtNameIdx]
          <> let totalLen = fromIntegral (2 + smtEntriesLen) :: Word32
              in [ fromIntegral (totalLen `div` 16777216),
                   fromIntegral ((totalLen `div` 65536) `mod` 256),
                   fromIntegral ((totalLen `div` 256) `mod` 256),
                   fromIntegral (totalLen `mod` 256)
                 ]
                   <> [0, 2] -- number_of_entries = 2
                   <> smtEntries
  pure
    MInfo
      { mFlags = 0x0008,
        mName = ni,
        mDesc = di,
        mCode = code,
        mCodeAttrCount = 1,
        mCodeAttrs = smtAttr,
        mMaxStack = 256,
        mMaxLocals = 256
      }

-- | addUInt8: UInt8 -> UInt8 -> Either OverflowError UInt8.
--   Both operands are 0..255, so 'iadd' produces 0..510 and a single
--   `if_icmple 255` selects the branch. No widening or masking is
--   needed; on the ok path the sum fits in UInt8 by construction.
mkAddUInt8 :: AsmM MInfo
mkAddUInt8 = do
  ni <- addUtf8 "__addUInt8"
  di <- addUtf8 "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"
  intCls <- addClass "java/lang/Integer"
  intValRef <- addMRef "java/lang/Integer" "intValue" "()I"
  valueOfRef <- addMRef "java/lang/Integer" "valueOf" "(I)Ljava/lang/Integer;"
  objCls <- addClass "java/lang/Object"
  smtNameIdx <- addUtf8 "StackMapTable"
  let unbox =
        [0xC0, hi8 intCls, lo8 intCls]
          <> [0xB6, hi8 intValRef, lo8 intValRef]
      preamble =
        [0x2A] -- aload_0
          <> unbox
          <> [0x2B] -- aload_1
          <> unbox
          <> [0x60] -- iadd
          <> [0x3D] -- istore_2 (sum → slot 2)
          <> [0x1C] -- iload_2
          <> [0x11, 0x00, 0xFF] -- sipush 255
      ifAt = length preamble
      overflow =
        -- OverflowError box: Object[1] = [Integer(0)]
        [0x04]
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59]
          <> [0x03]
          <> [0x03]
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53]
          <> [0x4D] -- astore_2 (overwrite sum slot — no longer needed)
          -- Left: Object[2] = [Integer(0), OE]
          <> [0x05]
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59]
          <> [0x03]
          <> [0x03]
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53]
          <> [0x59]
          <> [0x04]
          <> [0x2C] -- aload_2
          <> [0x53]
          <> [0xB0]
      okAt = ifAt + 3 + length overflow
      ok =
        -- Right: Object[2] = [Integer(1), Integer(sum)]
        [0x05]
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59]
          <> [0x03]
          <> [0x04] -- iconst_1 (Right tag)
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53]
          <> [0x59]
          <> [0x04]
          <> [0x1C] -- iload_2
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53]
          <> [0xB0]
      ifRel = okAt - ifAt
      -- if_icmple: opcode 0xA4. Branch if value2 (top) >= value1 — but we
      -- pushed 255 last, so top = 255, second = sum, and `value1 cmp value2`
      -- in JVM terms is "sum cmp 255". if_icmple branches if sum <= 255.
      ifBytes = [0xA4, hi8 (fromIntegral ifRel), lo8 (fromIntegral ifRel)]
      code = preamble <> ifBytes <> overflow <> ok
      -- One frame at okAt. Locals: [Object, Object, int (slot 2 = sum)].
      -- frame_type 252 = append_frame +1, ITEM_Integer = 1.
      okAt16 = fromIntegral okAt :: Word16
      smtEntries = [252, hi8 okAt16, lo8 okAt16, 0x01]
      smtEntriesLen = length smtEntries
      smtAttr =
        [hi8 smtNameIdx, lo8 smtNameIdx]
          <> let totalLen = fromIntegral (2 + smtEntriesLen) :: Word32
              in [ fromIntegral (totalLen `div` 16777216),
                   fromIntegral ((totalLen `div` 65536) `mod` 256),
                   fromIntegral ((totalLen `div` 256) `mod` 256),
                   fromIntegral (totalLen `mod` 256)
                 ]
                   <> [0, 1]
                   <> smtEntries
  pure
    MInfo
      { mFlags = 0x0008,
        mName = ni,
        mDesc = di,
        mCode = code,
        mCodeAttrCount = 1,
        mCodeAttrs = smtAttr,
        mMaxStack = 256,
        mMaxLocals = 256
      }

-- | subInt32: Int32 -> Int32 -> Either ArithError Int32.
--   Detects signed-subtraction overflow with the XOR trick:
--   '((a ^ b) & (a ^ diff)) < 0' is true iff signed overflow occurred.
--   Direction is read off 'a >= 0' (when subtraction overflows the signs
--   of @a@ and @b@ must differ, so @a >= 0@ implies @b < 0@ which implies
--   positive overflow). ArithError tags follow declaration order:
--   Underflow=0, Overflow=1. Same single-block, no try/catch shape as
--   'mkAddInt32' — keeping the methods structurally parallel.
mkSubInt32 :: AsmM MInfo
mkSubInt32 = do
  ni <- addUtf8 "__subInt32"
  di <- addUtf8 "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"
  intCls <- addClass "java/lang/Integer"
  intValRef <- addMRef "java/lang/Integer" "intValue" "()I"
  valueOfRef <- addMRef "java/lang/Integer" "valueOf" "(I)Ljava/lang/Integer;"
  objCls <- addClass "java/lang/Object"
  smtNameIdx <- addUtf8 "StackMapTable"
  let unbox =
        [0xC0, hi8 intCls, lo8 intCls]
          <> [0xB6, hi8 intValRef, lo8 intValRef]
      preamble =
        [0x2A] -- aload_0
          <> unbox
          <> [0x3D] -- istore_2 (a → slot 2)
          <> [0x2B] -- aload_1
          <> unbox
          <> [0x3E] -- istore_3 (b → slot 3)
          <> [0x1C] -- iload_2
          <> [0x1D] -- iload_3
          <> [0x64] -- isub
          <> [0x36, 0x04] -- istore 4 (diff)
          -- compute ((a ^ b) & (a ^ diff)); sign bit set on overflow.
          <> [0x1C] -- iload_2 (a)
          <> [0x1D] -- iload_3 (b)
          <> [0x82] -- ixor
          <> [0x1C] -- iload_2 (a)
          <> [0x15, 0x04] -- iload 4 (diff)
          <> [0x82] -- ixor
          <> [0x7E] -- iand
      iflt1At = length preamble
      ok =
        -- Right: Object[2] = [Integer(1), Integer(diff)]
        [0x05] -- iconst_2
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59] -- dup
          <> [0x03] -- iconst_0
          <> [0x04] -- iconst_1 (Right tag)
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53] -- aastore
          <> [0x59] -- dup
          <> [0x04] -- iconst_1
          <> [0x15, 0x04] -- iload 4
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53] -- aastore
          <> [0xB0] -- areturn
      overAt = iflt1At + 3 + length ok
      iflt1Rel = overAt - iflt1At
      iflt1Bytes = [0x9B, hi8 (fromIntegral iflt1Rel), lo8 (fromIntegral iflt1Rel)] :: [Word8]
      overSplit :: [Word8]
      overSplit =
        [0x1C] -- iload_2 (a)
        -- iflt L_under (placeholder, patched below)
      iflt2At = overAt + length overSplit
      arithBox tag =
        [0x04]
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59]
          <> [0x03]
          <> [tag]
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53]
          <> [0x3A, 0x05] -- astore 5
      leftWrap =
        [0x05]
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59]
          <> [0x03]
          <> [0x03] -- Left tag
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53]
          <> [0x59]
          <> [0x04]
          <> [0x19, 0x05] -- aload 5
          <> [0x53]
          <> [0xB0]
      overBlock = arithBox 0x04 <> leftWrap -- AE tag 1 = Overflow
      underAt = iflt2At + 3 + length overBlock
      iflt2Rel = underAt - iflt2At
      iflt2Bytes = [0x9B, hi8 (fromIntegral iflt2Rel), lo8 (fromIntegral iflt2Rel)]
      underBlock = arithBox 0x03 <> leftWrap -- AE tag 0 = Underflow
      code =
        preamble
          <> iflt1Bytes
          <> ok
          <> overSplit
          <> iflt2Bytes
          <> overBlock
          <> underBlock
      -- Two stack-map frames mirroring 'mkAddInt32': at overAt (locals
      -- [Object, Object, int, int, int]) and underAt (same locals).
      overAt16 = fromIntegral overAt :: Word16
      underDelta = fromIntegral (underAt - overAt - 1) :: Word8
      smtEntries =
        [254, hi8 overAt16, lo8 overAt16, 0x01, 0x01, 0x01]
          <> [underDelta]
      smtEntriesLen = length smtEntries
      smtAttr =
        [hi8 smtNameIdx, lo8 smtNameIdx]
          <> let totalLen = fromIntegral (2 + smtEntriesLen) :: Word32
              in [ fromIntegral (totalLen `div` 16777216),
                   fromIntegral ((totalLen `div` 65536) `mod` 256),
                   fromIntegral ((totalLen `div` 256) `mod` 256),
                   fromIntegral (totalLen `mod` 256)
                 ]
                   <> [0, 2]
                   <> smtEntries
  pure
    MInfo
      { mFlags = 0x0008,
        mName = ni,
        mDesc = di,
        mCode = code,
        mCodeAttrCount = 1,
        mCodeAttrs = smtAttr,
        mMaxStack = 256,
        mMaxLocals = 256
      }

-- | mulInt32: Int32 -> Int32 -> Either ArithError Int32.
--   Promote both operands to long, multiply at long width, range-check
--   the result against [INT32_MIN, INT32_MAX]. The binary assembler has
--   no CPLong slot (the constant pool only holds CPInteger), so the
--   long bounds are materialised via @ldc N; i2l@ rather than @ldc2_w@.
--   Direction is read off lcmp's result: ifgt → positive overflow
--   (Overflow tag = 1), iflt → negative overflow (Underflow tag = 0).
--   Two stack-map frames at the over / under labels; both points have
--   the long-product still live on the operand stack (consumed by the
--   leading @pop2@), and locals unchanged from entry — encoded as
--   @same_locals_1_stack_item_frame@ (or its extended form) carrying
--   one ITEM_Long on the stack.
mkMulInt32 :: AsmM MInfo
mkMulInt32 = do
  ni <- addUtf8 "__mulInt32"
  di <- addUtf8 "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"
  intCls <- addClass "java/lang/Integer"
  intValRef <- addMRef "java/lang/Integer" "intValue" "()I"
  valueOfRef <- addMRef "java/lang/Integer" "valueOf" "(I)Ljava/lang/Integer;"
  objCls <- addClass "java/lang/Object"
  smtNameIdx <- addUtf8 "StackMapTable"
  ldcMax <- bcLoadInt32 2147483647
  ldcMin <- bcLoadInt32 (-2147483648)
  let unbox =
        [0xC0, hi8 intCls, lo8 intCls]
          <> [0xB6, hi8 intValRef, lo8 intValRef]
      preamble =
        [0x2A] -- aload_0
          <> unbox
          <> [0x85] -- i2l
          <> [0x2B] -- aload_1
          <> unbox
          <> [0x85] -- i2l
          <> [0x69] -- lmul
      rangeUpper =
        [0x5C] -- dup2
          <> ldcMax
          <> [0x85] -- i2l
          <> [0x94] -- lcmp
      ifgtAt = length preamble + length rangeUpper
      rangeLower =
        [0x5C] -- dup2
          <> ldcMin
          <> [0x85] -- i2l
          <> [0x94] -- lcmp
      ifltAt = ifgtAt + 3 + length rangeLower
      ok =
        [0x88] -- l2i
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x4D] -- astore_2
          <> [0x05] -- iconst_2
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59] -- dup
          <> [0x03] -- iconst_0
          <> [0x04] -- iconst_1 (Right tag)
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53] -- aastore
          <> [0x59] -- dup
          <> [0x04] -- iconst_1
          <> [0x2C] -- aload_2
          <> [0x53] -- aastore
          <> [0xB0] -- areturn
      overAt = ifltAt + 3 + length ok
      arithLeft tag =
        [0x58] -- pop2 (drop the dup'd long product)
          <> [0x04] -- iconst_1
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59] -- dup
          <> [0x03] -- iconst_0
          <> [tag]
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53] -- aastore
          <> [0x4D] -- astore_2
          <> [0x05] -- iconst_2
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59] -- dup
          <> [0x03] -- iconst_0
          <> [0x03] -- iconst_0 (Left tag)
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53] -- aastore
          <> [0x59] -- dup
          <> [0x04] -- iconst_1
          <> [0x2C] -- aload_2
          <> [0x53] -- aastore
          <> [0xB0]
      overBlock = arithLeft 0x04 -- AE Overflow = 1
      underAt = overAt + length overBlock
      underBlock = arithLeft 0x03 -- AE Underflow = 0
      ifgtRel = overAt - ifgtAt
      ifltRel = underAt - ifltAt
      ifgtBytes = [0x9D, fromIntegral (ifgtRel `div` 256), fromIntegral (ifgtRel `mod` 256)]
      ifltBytes = [0x9B, fromIntegral (ifltRel `div` 256), fromIntegral (ifltRel `mod` 256)]
      code =
        preamble
          <> rangeUpper
          <> ifgtBytes
          <> rangeLower
          <> ifltBytes
          <> ok
          <> overBlock
          <> underBlock
      -- Frames at overAt and underAt: locals unchanged (still
      -- [Object, Object]), stack carries the dup'd long product (1
      -- ITEM_Long type entry, occupies 2 slots logically but the
      -- verification_type_info is one byte tag + nothing).
      sameLocals1Long ofs prevOfs =
        let delta = if prevOfs < 0 then ofs else ofs - prevOfs - 1
         in if delta <= 63
              then [fromIntegral (64 + delta) :: Word8, 0x04] -- ITEM_Long = 4
              else
                let d = fromIntegral delta :: Word16
                 in [247, hi8 d, lo8 d, 0x04]
      frame1 = sameLocals1Long overAt (-1)
      frame2 = sameLocals1Long underAt overAt
      smtEntries = frame1 <> frame2
      smtEntriesLen = length smtEntries
      smtAttr =
        [hi8 smtNameIdx, lo8 smtNameIdx]
          <> let totalLen = fromIntegral (2 + smtEntriesLen) :: Word32
              in [ fromIntegral (totalLen `div` 16777216),
                   fromIntegral ((totalLen `div` 65536) `mod` 256),
                   fromIntegral ((totalLen `div` 256) `mod` 256),
                   fromIntegral (totalLen `mod` 256)
                 ]
                   <> [0, 2]
                   <> smtEntries
  pure
    MInfo
      { mFlags = 0x0008,
        mName = ni,
        mDesc = di,
        mCode = code,
        mCodeAttrCount = 1,
        mCodeAttrs = smtAttr,
        mMaxStack = 256,
        mMaxLocals = 256
      }

-- | negInt32: Int32 -> Either OverflowError Int32.
--   Mirror of 'mkSuccInt32' with INT32_MIN as the boundary and 'ineg'
--   (0x74) instead of 'iadd 1'. Only minInt32 overflows on negation
--   (its absolute value is one above maxInt32 in two's complement);
--   every other input flips sign exactly. OverflowError is single-
--   constructor, so its boxed-tag is 0 and the Left-branch encoding
--   is byte-identical to predInt32.
mkNegInt32 :: AsmM MInfo
mkNegInt32 = do
  ni <- addUtf8 "__negInt32"
  di <- addUtf8 "(Ljava/lang/Object;)Ljava/lang/Object;"
  intCls <- addClass "java/lang/Integer"
  intValRef <- addMRef "java/lang/Integer" "intValue" "()I"
  valueOfRef <- addMRef "java/lang/Integer" "valueOf" "(I)Ljava/lang/Integer;"
  objCls <- addClass "java/lang/Object"
  smtNameIdx <- addUtf8 "StackMapTable"
  minLoad <- bcLoadInt32 (-2147483648)
  let preamble =
        [0x2A] -- aload_0
          <> [0xC0, hi8 intCls, lo8 intCls] -- checkcast Integer
          <> [0xB6, hi8 intValRef, lo8 intValRef] -- invokevirtual intValue()I
          <> [0x3C] -- istore_1
          <> [0x1B] -- iload_1
          <> minLoad
      ifAt = length preamble
      overflow =
        [0x04] -- iconst_1 (array length)
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59] -- dup
          <> [0x03] -- iconst_0
          <> [0x03] -- iconst_0 (OE tag)
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53] -- aastore
          <> [0x4D] -- astore_2
          <> [0x05] -- iconst_2
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59] -- dup
          <> [0x03] -- iconst_0
          <> [0x03] -- iconst_0 (Left tag)
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53] -- aastore
          <> [0x59] -- dup
          <> [0x04] -- iconst_1
          <> [0x2C] -- aload_2
          <> [0x53] -- aastore
          <> [0xB0] -- areturn
      okAt = ifAt + 3 + length overflow
      ok =
        [0x05] -- iconst_2
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59] -- dup
          <> [0x03] -- iconst_0
          <> [0x04] -- iconst_1 (Right tag)
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53] -- aastore
          <> [0x59] -- dup
          <> [0x04] -- iconst_1
          <> [0x1B] -- iload_1
          <> [0x74] -- ineg
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53] -- aastore
          <> [0xB0] -- areturn
      ifRel = okAt - ifAt
      ifBytes = [0xA0, fromIntegral (ifRel `div` 256), fromIntegral (ifRel `mod` 256)]
      code = preamble <> ifBytes <> overflow <> ok
      okAt16 = fromIntegral okAt :: Word16
      smtEntries = [252, hi8 okAt16, lo8 okAt16, 0x01]
      smtEntriesLen = length smtEntries
      smtAttr =
        [hi8 smtNameIdx, lo8 smtNameIdx]
          <> let totalLen = fromIntegral (2 + smtEntriesLen) :: Word32
              in [ fromIntegral (totalLen `div` 16777216),
                   fromIntegral ((totalLen `div` 65536) `mod` 256),
                   fromIntegral ((totalLen `div` 256) `mod` 256),
                   fromIntegral (totalLen `mod` 256)
                 ]
                   <> [0, 1]
                   <> smtEntries
  pure
    MInfo
      { mFlags = 0x0008,
        mName = ni,
        mDesc = di,
        mCode = code,
        mCodeAttrCount = 1,
        mCodeAttrs = smtAttr,
        mMaxStack = 256,
        mMaxLocals = 256
      }

-- | subUInt8: UInt8 -> UInt8 -> Either UnderflowError UInt8.
--   Both operands are 0..255, so 'isub' produces a value in -255..255 with
--   no JVM-level overflow; one 'iflt' picks the underflow branch. On the
--   ok path the result is already a valid UInt8 — no mask needed.
--   Slot layout: 0/1 = Object params, 2 = int diff (or Object UE on the
--   underflow path). One frame at L_under: locals = [Object, Object, int]
--   appended from entry, frame_type 252 (append_frame +1, ITEM_Integer).
mkSubUInt8 :: AsmM MInfo
mkSubUInt8 = do
  ni <- addUtf8 "__subUInt8"
  di <- addUtf8 "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"
  intCls <- addClass "java/lang/Integer"
  intValRef <- addMRef "java/lang/Integer" "intValue" "()I"
  valueOfRef <- addMRef "java/lang/Integer" "valueOf" "(I)Ljava/lang/Integer;"
  objCls <- addClass "java/lang/Object"
  smtNameIdx <- addUtf8 "StackMapTable"
  let unbox =
        [0xC0, hi8 intCls, lo8 intCls]
          <> [0xB6, hi8 intValRef, lo8 intValRef]
      preamble =
        [0x2A] -- aload_0
          <> unbox
          <> [0x2B] -- aload_1
          <> unbox
          <> [0x64] -- isub
          <> [0x3D] -- istore_2 (diff → slot 2)
          <> [0x1C] -- iload_2
      ifAt = length preamble
      ok =
        -- Right: Object[2] = [Integer(1), Integer(diff)]
        [0x05] -- iconst_2
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59] -- dup
          <> [0x03] -- iconst_0
          <> [0x04] -- iconst_1 (Right tag)
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53] -- aastore
          <> [0x59] -- dup
          <> [0x04] -- iconst_1
          <> [0x1C] -- iload_2
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53] -- aastore
          <> [0xB0] -- areturn
      underAt = ifAt + 3 + length ok
      under =
        -- UnderflowError: Object[1] = [Integer(0)]
        [0x04]
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59]
          <> [0x03]
          <> [0x03] -- UE tag = 0
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53]
          <> [0x4D] -- astore_2 (overwrite int slot — no longer needed)
          -- Left: Object[2] = [Integer(0), UE]
          <> [0x05]
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59]
          <> [0x03]
          <> [0x03] -- Left tag = 0
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53]
          <> [0x59]
          <> [0x04]
          <> [0x2C] -- aload_2 (UE)
          <> [0x53]
          <> [0xB0]
      ifRel = underAt - ifAt
      -- iflt: 0x9B; branches if value < 0.
      ifBytes = [0x9B, fromIntegral (ifRel `div` 256), fromIntegral (ifRel `mod` 256)]
      code = preamble <> ifBytes <> ok <> under
      -- One frame at underAt. Locals: [Object, Object, int (slot 2 = diff)].
      -- frame_type 252 = append_frame +1, ITEM_Integer = 1.
      underAt16 = fromIntegral underAt :: Word16
      smtEntries = [252, hi8 underAt16, lo8 underAt16, 0x01]
      smtEntriesLen = length smtEntries
      smtAttr =
        [hi8 smtNameIdx, lo8 smtNameIdx]
          <> let totalLen = fromIntegral (2 + smtEntriesLen) :: Word32
              in [ fromIntegral (totalLen `div` 16777216),
                   fromIntegral ((totalLen `div` 65536) `mod` 256),
                   fromIntegral ((totalLen `div` 256) `mod` 256),
                   fromIntegral (totalLen `mod` 256)
                 ]
                   <> [0, 1]
                   <> smtEntries
  pure
    MInfo
      { mFlags = 0x0008,
        mName = ni,
        mDesc = di,
        mCode = code,
        mCodeAttrCount = 1,
        mCodeAttrs = smtAttr,
        mMaxStack = 256,
        mMaxLocals = 256
      }

-- | mulUInt8: UInt8 -> UInt8 -> Either OverflowError UInt8.
--   Both operands are 0..255 so 'imul' produces 0..65025 in i32 with no
--   overflow at the JVM level. Same single-block shape as 'mkAddUInt8'
--   with 'imul' (0x68) replacing 'iadd' (0x60); the SMT layout is
--   identical (one append_frame at the ok target, locals grow by +1
--   for the int slot 2 = product).
mkMulUInt8 :: AsmM MInfo
mkMulUInt8 = do
  ni <- addUtf8 "__mulUInt8"
  di <- addUtf8 "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"
  intCls <- addClass "java/lang/Integer"
  intValRef <- addMRef "java/lang/Integer" "intValue" "()I"
  valueOfRef <- addMRef "java/lang/Integer" "valueOf" "(I)Ljava/lang/Integer;"
  objCls <- addClass "java/lang/Object"
  smtNameIdx <- addUtf8 "StackMapTable"
  let unbox =
        [0xC0, hi8 intCls, lo8 intCls]
          <> [0xB6, hi8 intValRef, lo8 intValRef]
      preamble =
        [0x2A] -- aload_0
          <> unbox
          <> [0x2B] -- aload_1
          <> unbox
          <> [0x68] -- imul
          <> [0x3D] -- istore_2 (product → slot 2)
          <> [0x1C] -- iload_2
          <> [0x11, 0x00, 0xFF] -- sipush 255
      ifAt = length preamble
      overflow =
        [0x04]
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59]
          <> [0x03]
          <> [0x03]
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53]
          <> [0x4D] -- astore_2 (overwrite product slot — no longer needed)
          <> [0x05]
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59]
          <> [0x03]
          <> [0x03]
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53]
          <> [0x59]
          <> [0x04]
          <> [0x2C] -- aload_2
          <> [0x53]
          <> [0xB0]
      okAt = ifAt + 3 + length overflow
      ok =
        [0x05]
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59]
          <> [0x03]
          <> [0x04]
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53]
          <> [0x59]
          <> [0x04]
          <> [0x1C] -- iload_2
          <> [0xB8, hi8 valueOfRef, lo8 valueOfRef]
          <> [0x53]
          <> [0xB0]
      ifRel = okAt - ifAt
      -- if_icmple: 0xA4. Branches if sum <= 255 (matches mkAddUInt8 layout).
      ifBytes = [0xA4, hi8 (fromIntegral ifRel), lo8 (fromIntegral ifRel)]
      code = preamble <> ifBytes <> overflow <> ok
      okAt16 = fromIntegral okAt :: Word16
      smtEntries = [252, hi8 okAt16, lo8 okAt16, 0x01]
      smtEntriesLen = length smtEntries
      smtAttr =
        [hi8 smtNameIdx, lo8 smtNameIdx]
          <> let totalLen = fromIntegral (2 + smtEntriesLen) :: Word32
              in [ fromIntegral (totalLen `div` 16777216),
                   fromIntegral ((totalLen `div` 65536) `mod` 256),
                   fromIntegral ((totalLen `div` 256) `mod` 256),
                   fromIntegral (totalLen `mod` 256)
                 ]
                   <> [0, 1]
                   <> smtEntries
  pure
    MInfo
      { mFlags = 0x0008,
        mName = ni,
        mDesc = di,
        mCode = code,
        mCodeAttrCount = 1,
        mCodeAttrs = smtAttr,
        mMaxStack = 256,
        mMaxLocals = 256
      }

-- | splitOnFirst: String -> String -> Maybe (Tuple2 String String).
--   Binary equivalent of 'Awsum.Codegen.JVM.splitOnFirstMethod'. Defers
--   substring search to 'String.indexOf(String)I' which returns -1 on
--   miss and 0 on empty separator — both behaviours match the Prelude
--   contract directly. On hit the two 'String.substring' calls allocate
--   fresh String objects (no aliasing into the input). One stack-map
--   frame at the L_split_found target: locals grow by +1 (slot 2 = int).
mkSplitOnFirst :: AsmM MInfo
mkSplitOnFirst = do
  ni <- addUtf8 "__splitOnFirst"
  di <- addUtf8 "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"
  strCls <- addClass "java/lang/String"
  objCls <- addClass "java/lang/Object"
  intValueOfRef <- addMRef "java/lang/Integer" "valueOf" "(I)Ljava/lang/Integer;"
  indexOfRef <- addMRef "java/lang/String" "indexOf" "(Ljava/lang/String;)I"
  substring2Ref <- addMRef "java/lang/String" "substring" "(II)Ljava/lang/String;"
  substring1Ref <- addMRef "java/lang/String" "substring" "(I)Ljava/lang/String;"
  lengthRef <- addMRef "java/lang/String" "length" "()I"
  smtNameIdx <- addUtf8 "StackMapTable"
  let preamble =
        [0x2B] -- aload_1 (str)
          <> [0xC0, hi8 strCls, lo8 strCls] -- checkcast String
          <> [0x2A] -- aload_0 (sep)
          <> [0xC0, hi8 strCls, lo8 strCls] -- checkcast String
          <> [0xB6, hi8 indexOfRef, lo8 indexOfRef] -- invokevirtual indexOf
          <> [0x3D] -- istore_2 (idx)
          <> [0x1C] -- iload_2
          <> [0x02] -- iconst_m1
      ifAt = length preamble
      nothing =
        -- Nothing: Object[1] = [Integer(0)]
        [0x04] -- iconst_1
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59] -- dup
          <> [0x03] -- iconst_0 (idx)
          <> [0x03] -- iconst_0 (Nothing tag)
          <> [0xB8, hi8 intValueOfRef, lo8 intValueOfRef]
          <> [0x53] -- aastore
          <> [0xB0] -- areturn
      foundAt = ifAt + 3 + length nothing
      ifRel = foundAt - ifAt
      ifBytes = [0xA0, hi8 (fromIntegral ifRel), lo8 (fromIntegral ifRel)]
      foundBlock =
        -- prefix = str.substring(0, idx) → slot 3
        [0x2B] -- aload_1
          <> [0xC0, hi8 strCls, lo8 strCls]
          <> [0x03] -- iconst_0
          <> [0x1C] -- iload_2
          <> [0xB6, hi8 substring2Ref, lo8 substring2Ref]
          <> [0x4E] -- astore_3 (prefix)
          -- suffix = str.substring(idx + sep.length()) → slot 2
          <> [0x2B] -- aload_1
          <> [0xC0, hi8 strCls, lo8 strCls]
          <> [0x1C] -- iload_2
          <> [0x2A] -- aload_0
          <> [0xC0, hi8 strCls, lo8 strCls]
          <> [0xB6, hi8 lengthRef, lo8 lengthRef]
          <> [0x60] -- iadd
          <> [0xB6, hi8 substring1Ref, lo8 substring1Ref]
          <> [0x4D] -- astore_2 (suffix; reuses slot 2 — idx no longer needed)
          -- Tuple2: Object[3] = [Integer(0), prefix, suffix] → slot 3 (reuse)
          <> [0x06] -- iconst_3
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59] -- dup
          <> [0x03] -- iconst_0
          <> [0x03] -- iconst_0 (Tuple2 tag)
          <> [0xB8, hi8 intValueOfRef, lo8 intValueOfRef]
          <> [0x53] -- aastore
          <> [0x59] -- dup
          <> [0x04] -- iconst_1
          <> [0x2D] -- aload_3 (prefix)
          <> [0x53] -- aastore
          <> [0x59] -- dup
          <> [0x05] -- iconst_2
          <> [0x2C] -- aload_2 (suffix)
          <> [0x53] -- aastore
          <> [0x4E] -- astore_3 (tuple; overwrites prefix slot)
          -- Just: Object[2] = [Integer(1), tuple]
          <> [0x05] -- iconst_2
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59] -- dup
          <> [0x03] -- iconst_0
          <> [0x04] -- iconst_1 (Just tag)
          <> [0xB8, hi8 intValueOfRef, lo8 intValueOfRef]
          <> [0x53] -- aastore
          <> [0x59] -- dup
          <> [0x04] -- iconst_1
          <> [0x2D] -- aload_3 (tuple)
          <> [0x53] -- aastore
          <> [0xB0] -- areturn
      code = preamble <> ifBytes <> nothing <> foundBlock
      -- One frame at L_split_found. Locals: [Object, Object, int].
      -- frame_type 252 = append_frame +1, ITEM_Integer (1).
      foundAt16 = fromIntegral foundAt :: Word16
      smtEntries = [252, hi8 foundAt16, lo8 foundAt16, 0x01]
      smtEntriesLen = length smtEntries
      smtAttr =
        [hi8 smtNameIdx, lo8 smtNameIdx]
          <> let totalLen = fromIntegral (2 + smtEntriesLen) :: Word32
              in [ fromIntegral (totalLen `div` 16777216),
                   fromIntegral ((totalLen `div` 65536) `mod` 256),
                   fromIntegral ((totalLen `div` 256) `mod` 256),
                   fromIntegral (totalLen `mod` 256)
                 ]
                   <> [0, 1]
                   <> smtEntries
  pure
    MInfo
      { mFlags = 0x0008,
        mName = ni,
        mDesc = di,
        mCode = code,
        mCodeAttrCount = 1,
        mCodeAttrs = smtAttr,
        mMaxStack = 256,
        mMaxLocals = 256
      }

-- | parseInt32: String -> Either ParseError Int32. Binary equivalent of
--   'Awsum.Codegen.JVM.parseInt32Method'. Same handrolled algorithm as
--   the LLVM and WASM helpers — long accumulator capped at the magnitude
--   `|minInt32|`. The constant 2147483648L is built with the shift trick
--   `iconst_1 i2l bipush 31 lshl` rather than ldc2_w on a long literal,
--   so the assembler does not need a CPLong slot. INT_MAX (2147483647)
--   is loaded via 'bcLoadInt32' and widened with i2l.
--   Locals: 0 = arg, 1 = String s, 2 = int len, 3 = int i, 4 = int neg
--   (later reused as Object slot for the boxed ParseError on the fail
--   path), 5-6 = long acc, 7 = int c.
mkParseInt32 :: AsmM MInfo
mkParseInt32 = do
  ni <- addUtf8 "__parseInt32"
  di <- addUtf8 "(Ljava/lang/Object;)Ljava/lang/Object;"
  strCls <- addClass "java/lang/String"
  objCls <- addClass "java/lang/Object"
  lengthRef <- addMRef "java/lang/String" "length" "()I"
  charAtRef <- addMRef "java/lang/String" "charAt" "(I)C"
  intValueOfRef <- addMRef "java/lang/Integer" "valueOf" "(I)Ljava/lang/Integer;"
  smtNameIdx <- addUtf8 "StackMapTable"
  ldcMaxInt <- bcLoadInt32 2147483647
  let -- block A: aload_0; checkcast; astore_1; aload_1; invokevirtual length; istore_2
      blockA =
        bcAload 0
          <> bcCheckCast strCls
          <> bcAstore 1
          <> bcAload 1
          <> bcInvokeVirtual lengthRef
          <> bcIstore 2
      lenA = length blockA
      -- block B: iload_2  (followed by ifeq L_fail, which we patch in)
      blockB = bcIload 2
      lenB = length blockB
      ifeqAt = lenA + lenB
      -- after ifeq (3 bytes): start of block C
      cAt = ifeqAt + 3
      -- block C: init i=0, neg=0
      blockC = bcIconst 0 <> bcIstore 3 <> bcIconst 0 <> bcIstore 4
      lenC = length blockC
      -- block D: charAt(0); bipush 45
      blockD =
        bcAload 1
          <> bcIconst 0
          <> bcInvokeVirtual charAtRef
          <> [0x10, 45]
      lenD = length blockD
      ifNeAt = cAt + lenC + lenD
      afterIfNe = ifNeAt + 3
      -- block F: minus path (set neg=1, i=1, then load len, push 1)
      blockF =
        bcIconst 1
          <> bcIstore 4
          <> bcIconst 1
          <> bcIstore 3
          <> bcIload 2
          <> bcIconst 1
      lenF = length blockF
      ifEqAt = afterIfNe + lenF
      initAccAt = ifEqAt + 3
      -- block H: lconst_0 (1); lstore 5 (2)
      blockH = [0x09] <> bcLstore 5
      lenH = length blockH
      loopAt = initAccAt + lenH
      -- block I: iload_3; iload_2
      blockI = bcIload 3 <> bcIload 2
      lenI = length blockI
      ifGeAt = loopAt + lenI
      afterIfGe = ifGeAt + 3
      -- block K: charAt(i); istore 7
      blockK =
        bcAload 1
          <> bcIload 3
          <> bcInvokeVirtual charAtRef
          <> bcIstore 7
      lenK = length blockK
      -- block L: iload 7; bipush 48
      blockL = bcIload 7 <> [0x10, 48]
      lenL = length blockL
      ifLtAt = afterIfGe + lenK + lenL
      afterIfLt = ifLtAt + 3
      -- block N: iload 7; bipush 57
      blockN = bcIload 7 <> [0x10, 57]
      lenN = length blockN
      ifGtCharAt = afterIfLt + lenN
      afterIfGtChar = ifGtCharAt + 3
      -- block P: acc = acc * 10 + (c - '0')
      blockP =
        bcLload 5
          <> [0x10, 10] -- bipush 10
          <> [0x85] -- i2l
          <> [0x69] -- lmul
          <> bcIload 7
          <> [0x10, 48]
          <> [0x64] -- isub
          <> [0x85] -- i2l
          <> [0x61] -- ladd
          <> bcLstore 5
      lenP = length blockP
      -- block Q: lload 5; iconst_1; i2l; bipush 31; lshl; lcmp  (compare against 2147483648L)
      blockQ =
        bcLload 5
          <> bcIconst 1
          <> [0x85]
          <> [0x10, 31]
          <> [0x79] -- lshl
          <> [0x94] -- lcmp
      lenQ = length blockQ
      ifGtAccAt = afterIfGtChar + lenP + lenQ
      afterIfGtAcc = ifGtAccAt + 3
      -- block S: iinc 3 1 (3 bytes)
      blockS = [0x84, 3, 1] :: [Word8]
      lenS = length blockS
      gotoLoopAt = afterIfGtAcc + lenS
      -- after goto (3 bytes): L_after_loop
      afterLoopAt = gotoLoopAt + 3
      -- block T: iload 4
      blockT = bcIload 4
      lenT = length blockT
      ifEq2At = afterLoopAt + lenT
      afterIfEq2 = ifEq2At + 3
      -- block U: lload 5; lneg; lstore 5
      blockU = bcLload 5 <> [0x75] <> bcLstore 5
      lenU = length blockU
      gotoBuildAt = afterIfEq2 + lenU
      posCheckAt = gotoBuildAt + 3
      -- block V: lload 5; ldc INT_MAX; i2l; lcmp
      blockV = bcLload 5 <> ldcMaxInt <> [0x85] <> [0x94]
      lenV = length blockV
      ifGtPosAt :: Int
      ifGtPosAt = posCheckAt + lenV
      buildRightAt = ifGtPosAt + 3
      -- block X: build Right (Object[2] = [Integer(1), Integer(acc as int)])
      blockX =
        bcIconst 2
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59]
          <> bcIconst 0
          <> bcIconst 1
          <> [0xB8, hi8 intValueOfRef, lo8 intValueOfRef]
          <> [0x53]
          <> [0x59]
          <> bcIconst 1
          <> bcLload 5
          <> [0x88] -- l2i
          <> [0xB8, hi8 intValueOfRef, lo8 intValueOfRef]
          <> [0x53]
          <> [0xB0]
      lenX = length blockX
      failAt = buildRightAt + lenX
      -- block Y: L_fail body (build Left of ParseError)
      blockY =
        bcIconst 1
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59]
          <> bcIconst 0
          <> bcIconst 0
          <> [0xB8, hi8 intValueOfRef, lo8 intValueOfRef]
          <> [0x53]
          <> bcAstore 4
          <> bcIconst 2
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59]
          <> bcIconst 0
          <> bcIconst 0
          <> [0xB8, hi8 intValueOfRef, lo8 intValueOfRef]
          <> [0x53]
          <> [0x59]
          <> bcIconst 1
          <> bcAload 4
          <> [0x53]
          <> [0xB0]
      -- branch offset helper (16-bit signed via Word16 wrap)
      enc16 :: Int -> [Word8]
      enc16 n = let w = fromIntegral n :: Word16 in [hi8 w, lo8 w]
      ifeqOff = failAt - ifeqAt
      ifNeOff = initAccAt - ifNeAt
      ifEqOff = failAt - ifEqAt
      ifGeOff = afterLoopAt - ifGeAt
      ifLtOff = failAt - ifLtAt
      ifGtCharOff = failAt - ifGtCharAt
      ifGtAccOff = failAt - ifGtAccAt
      gotoLoopOff = loopAt - gotoLoopAt
      ifEq2Off = posCheckAt - ifEq2At
      gotoBuildOff = buildRightAt - gotoBuildAt
      ifGtPosOff = failAt - ifGtPosAt
      code =
        blockA
          <> blockB
          <> [0x99]
          <> enc16 ifeqOff
          <> blockC
          <> blockD
          <> [0xA0]
          <> enc16 ifNeOff
          <> blockF
          <> [0x9F]
          <> enc16 ifEqOff
          <> blockH
          <> blockI
          <> [0xA2]
          <> enc16 ifGeOff
          <> blockK
          <> blockL
          <> [0xA1]
          <> enc16 ifLtOff
          <> blockN
          <> [0xA3]
          <> enc16 ifGtCharOff
          <> blockP
          <> blockQ
          <> [0x9D]
          <> enc16 ifGtAccOff
          <> blockS
          <> [0xA7]
          <> enc16 gotoLoopOff
          <> blockT
          <> [0x99]
          <> enc16 ifEq2Off
          <> blockU
          <> [0xA7]
          <> enc16 gotoBuildOff
          <> blockV
          <> [0x9D]
          <> enc16 ifGtPosOff
          <> blockX
          <> blockY
      -- StackMapTable: 6 frames at L_init_acc, L_loop, L_after_loop,
      -- L_pos_check, L_build_right, L_fail. The first uses full_frame
      -- because we add 4 locals in one go from initial; subsequent
      -- frames use append/same/chop.
      initAcc16 = fromIntegral initAccAt :: Word16
      delta2 = fromIntegral (loopAt - initAccAt - 1) :: Word16
      delta3 = fromIntegral (afterLoopAt - loopAt - 1) :: Word8
      delta4 = fromIntegral (posCheckAt - afterLoopAt - 1) :: Word8
      delta5 = fromIntegral (buildRightAt - posCheckAt - 1) :: Word8
      delta6 = fromIntegral (failAt - buildRightAt - 1) :: Word16
      smtEntries =
        -- Frame 1: full_frame at offset L_init_acc, locals [Object, String, int, int, int]
        [ 255,
          hi8 initAcc16,
          lo8 initAcc16,
          0x00,
          0x05,
          7,
          hi8 objCls,
          lo8 objCls,
          7,
          hi8 strCls,
          lo8 strCls,
          1,
          1,
          1,
          0x00,
          0x00
        ]
          -- Frame 2: append +1 (Long) at L_loop
          <> [252, hi8 delta2, lo8 delta2, 4]
          -- Frame 3: same_frame at L_after_loop (delta fits in 0..63)
          <> [delta3]
          -- Frame 4: same_frame at L_pos_check
          <> [delta4]
          -- Frame 5: same_frame at L_build_right
          <> [delta5]
          -- Frame 6: chop 3 at L_fail (drops Long, int, int → leaves [Object, String, int])
          <> [248, hi8 delta6, lo8 delta6]
      smtEntriesLen = length smtEntries
      smtAttr =
        [hi8 smtNameIdx, lo8 smtNameIdx]
          <> let totalLen = fromIntegral (2 + smtEntriesLen) :: Word32
              in [ fromIntegral (totalLen `div` 16777216),
                   fromIntegral ((totalLen `div` 65536) `mod` 256),
                   fromIntegral ((totalLen `div` 256) `mod` 256),
                   fromIntegral (totalLen `mod` 256)
                 ]
                   <> [0, 6]
                   <> smtEntries
  pure
    MInfo
      { mFlags = 0x0008,
        mName = ni,
        mDesc = di,
        mCode = code,
        mCodeAttrCount = 1,
        mCodeAttrs = smtAttr,
        mMaxStack = 256,
        mMaxLocals = 256
      }

-- | parseUInt8: String -> Either ParseError UInt8. Binary equivalent of
--   'Awsum.Codegen.JVM.parseUInt8Method'. Same handrolled shape as
--   'mkParseInt32' minus the sign handling — UInt8 cannot be negative
--   — and with an i32 accumulator (the running magnitude never exceeds
--   2559 before the > 255 check fails the parse).
--   Locals: 0 = arg, 1 = String s, 2 = int len, 3 = int i, 4 = int acc
--   (later reused as Object on fail path), 5 = int c.
mkParseUInt8 :: AsmM MInfo
mkParseUInt8 = do
  ni <- addUtf8 "__parseUInt8"
  di <- addUtf8 "(Ljava/lang/Object;)Ljava/lang/Object;"
  strCls <- addClass "java/lang/String"
  objCls <- addClass "java/lang/Object"
  lengthRef <- addMRef "java/lang/String" "length" "()I"
  charAtRef <- addMRef "java/lang/String" "charAt" "(I)C"
  intValueOfRef <- addMRef "java/lang/Integer" "valueOf" "(I)Ljava/lang/Integer;"
  smtNameIdx <- addUtf8 "StackMapTable"
  let blockA =
        bcAload 0
          <> bcCheckCast strCls
          <> bcAstore 1
          <> bcAload 1
          <> bcInvokeVirtual lengthRef
          <> bcIstore 2
      lenA = length blockA
      blockB = bcIload 2
      lenB = length blockB
      ifeqAt = lenA + lenB
      cAt = ifeqAt + 3
      blockC = bcIconst 0 <> bcIstore 3 <> bcIconst 0 <> bcIstore 4
      lenC = length blockC
      loopAt = cAt + lenC
      blockI = bcIload 3 <> bcIload 2
      lenI = length blockI
      ifGeAt = loopAt + lenI
      afterIfGe = ifGeAt + 3
      blockK =
        bcAload 1
          <> bcIload 3
          <> bcInvokeVirtual charAtRef
          <> bcIstore 5
      lenK = length blockK
      blockL = bcIload 5 <> [0x10, 48]
      lenL = length blockL
      ifLtAt = afterIfGe + lenK + lenL
      afterIfLt = ifLtAt + 3
      blockN = bcIload 5 <> [0x10, 57]
      lenN = length blockN
      ifGtCharAt = afterIfLt + lenN
      afterIfGtChar = ifGtCharAt + 3
      -- block P: acc = acc * 10 + (c - '0')  (i32 throughout)
      blockP =
        bcIload 4
          <> [0x10, 10]
          <> [0x68] -- imul
          <> bcIload 5
          <> [0x10, 48]
          <> [0x64] -- isub
          <> [0x60] -- iadd
          <> bcIstore 4
      lenP = length blockP
      -- block Q: iload 4; sipush 255
      blockQ = bcIload 4 <> [0x11, 0x00, 0xFF]
      lenQ = length blockQ
      ifGtAccAt = afterIfGtChar + lenP + lenQ
      afterIfGtAcc = ifGtAccAt + 3
      blockS = [0x84, 3, 1] :: [Word8]
      lenS = length blockS
      gotoLoopAt = afterIfGtAcc + lenS
      okAt = gotoLoopAt + 3
      -- block X: build Right (Object[2] = [Integer(1), Integer(acc)])
      blockX =
        bcIconst 2
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59]
          <> bcIconst 0
          <> bcIconst 1
          <> [0xB8, hi8 intValueOfRef, lo8 intValueOfRef]
          <> [0x53]
          <> [0x59]
          <> bcIconst 1
          <> bcIload 4
          <> [0xB8, hi8 intValueOfRef, lo8 intValueOfRef]
          <> [0x53]
          <> [0xB0]
      lenX = length blockX
      failAt = okAt + lenX
      blockY =
        bcIconst 1
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59]
          <> bcIconst 0
          <> bcIconst 0
          <> [0xB8, hi8 intValueOfRef, lo8 intValueOfRef]
          <> [0x53]
          <> bcAstore 4
          <> bcIconst 2
          <> [0xBD, hi8 objCls, lo8 objCls]
          <> [0x59]
          <> bcIconst 0
          <> bcIconst 0
          <> [0xB8, hi8 intValueOfRef, lo8 intValueOfRef]
          <> [0x53]
          <> [0x59]
          <> bcIconst 1
          <> bcAload 4
          <> [0x53]
          <> [0xB0]
      enc16 :: Int -> [Word8]
      enc16 n = let w = fromIntegral n :: Word16 in [hi8 w, lo8 w]
      ifeqOff = failAt - ifeqAt
      ifGeOff = okAt - ifGeAt
      ifLtOff = failAt - ifLtAt
      ifGtCharOff = failAt - ifGtCharAt
      ifGtAccOff = failAt - ifGtAccAt
      gotoLoopOff = loopAt - gotoLoopAt
      code =
        blockA
          <> blockB
          <> [0x99]
          <> enc16 ifeqOff
          <> blockC
          <> blockI
          <> [0xA2]
          <> enc16 ifGeOff
          <> blockK
          <> blockL
          <> [0xA1]
          <> enc16 ifLtOff
          <> blockN
          <> [0xA3]
          <> enc16 ifGtCharOff
          <> blockP
          <> blockQ
          <> [0xA3]
          <> enc16 ifGtAccOff
          <> blockS
          <> [0xA7]
          <> enc16 gotoLoopOff
          <> blockX
          <> blockY
      -- StackMapTable: 3 frames at L_loop, L_ok, L_fail.
      -- Initial frame: [Object]. At L_loop: [Object, String, int len, int i, int acc].
      loop16 = fromIntegral loopAt :: Word16
      delta2 = fromIntegral (okAt - loopAt - 1) :: Word8
      delta3 = fromIntegral (failAt - okAt - 1) :: Word16
      smtEntries =
        -- Frame 1: full_frame at L_loop (locals = 5 entries; can't append 4)
        [ 255,
          hi8 loop16,
          lo8 loop16,
          0x00,
          0x05,
          7,
          hi8 objCls,
          lo8 objCls,
          7,
          hi8 strCls,
          lo8 strCls,
          1,
          1,
          1,
          0x00,
          0x00
        ]
          <> [delta2] -- Frame 2: same_frame at L_ok
          <> [249, hi8 delta3, lo8 delta3] -- Frame 3: chop 2 at L_fail (5 → 3)
      smtEntriesLen = length smtEntries
      smtAttr =
        [hi8 smtNameIdx, lo8 smtNameIdx]
          <> let totalLen = fromIntegral (2 + smtEntriesLen) :: Word32
              in [ fromIntegral (totalLen `div` 16777216),
                   fromIntegral ((totalLen `div` 65536) `mod` 256),
                   fromIntegral ((totalLen `div` 256) `mod` 256),
                   fromIntegral (totalLen `mod` 256)
                 ]
                   <> [0, 3]
                   <> smtEntries
  pure
    MInfo
      { mFlags = 0x0008,
        mName = ni,
        mDesc = di,
        mCode = code,
        mCodeAttrCount = 1,
        mCodeAttrs = smtAttr,
        mMaxStack = 256,
        mMaxLocals = 256
      }

mkMain :: AsmM MInfo
mkMain = do
  ni <- addUtf8 "main"
  di <- addUtf8 "([Ljava/lang/String;)V"
  emptyIdx <- addStr ""
  vMainRef <- addMRef "AwsumMain" (mangle "main") (objMethodDesc 1)
  smtNameIdx <- addUtf8 "StackMapTable"
  objClsIdx <- addClass "java/lang/Object"
  let ldcEmpty = bcLdc emptyIdx
      ldcLen = length ldcEmpty
      -- Layout:
      -- 0: aload_0           (1)
      -- 1: arraylength        (1)
      -- 2: iconst_1           (1)
      -- 3: if_icmpge          (3)  → has_arg at offset (6 + ldcLen + 3)
      -- 6: ldc ""             (ldcLen)
      -- 6+L: goto             (3)  → call_main at offset (6 + ldcLen + 3 + 3)
      -- 6+L+3: aload_0       (1)   [has_arg]
      -- 6+L+4: iconst_0      (1)
      -- 6+L+5: aaload         (1)
      -- 6+L+6: invokestatic  (3)   [call_main]
      -- 6+L+9: pop            (1)
      -- 6+L+10: return        (1)
      hasArg = 6 + ldcLen + 3
      callMain = hasArg + 3
      ifRel = hasArg - 3 :: Int
      gotoRel = callMain - (6 + ldcLen) :: Int
      -- StackMapTable: two frames at branch targets
      -- 1) has_arg: same_frame (same locals as initial, empty stack)
      --    frame_type = offset_delta = hasArg (first entry, <= 63)
      -- 2) call_main: same_locals_1_stack_item (stack = [Object])
      --    offset_delta = callMain - hasArg - 1 = 2
      --    frame_type = 64 + 2 = 66
      --    verification_type_info = Object_variable_info(tag=7, cpool_index)
      smtEntries =
        [fromIntegral hasArg] -- same_frame at has_arg
          <> [66, 7, hi8 objClsIdx, lo8 objClsIdx] -- same_locals_1_stack_item at call_main
      smtEntriesLen = length smtEntries
      -- StackMapTable attribute: name(2) + length(4) + num_entries(2) + entries
      smtAttr =
        [hi8 smtNameIdx, lo8 smtNameIdx]
          <> let totalLen = fromIntegral (2 + smtEntriesLen) :: Word32
              in [fromIntegral (totalLen `div` 16777216), fromIntegral ((totalLen `div` 65536) `mod` 256), fromIntegral ((totalLen `div` 256) `mod` 256), fromIntegral (totalLen `mod` 256)]
                   <> [0, 2] -- number_of_entries = 2
                   <> smtEntries
  pure
    MInfo
      { mFlags = 0x0009,
        mName = ni,
        mDesc = di,
        mCode =
          bcAload 0
            <> [0xBE] -- arraylength
            <> [0x04] -- iconst_1
            <> [0xA2, fromIntegral (ifRel `div` 256), fromIntegral (ifRel `mod` 256)] -- if_icmpge
            <> ldcEmpty
            <> [0xA7, fromIntegral (gotoRel `div` 256), fromIntegral (gotoRel `mod` 256)] -- goto
            <> bcAload 0 -- has_arg
            <> [0x03] -- iconst_0
            <> [0x32] -- aaload
            <> bcInvokeStatic vMainRef -- call_main
            <> [0x57] -- pop
            <> [0xB1], -- return
        mCodeAttrCount = 1,
        mCodeAttrs = smtAttr,
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
    cNextLocal :: Int
  }

-- | Number of *additional* local slots a body needs beyond its
-- parameters — sums the additive nesting of 'CCase' (1 array slot +
-- max-binding count per level) and propagates through subexpressions.
-- Mirrors the slot allocation in 'emitExpr' / 'emitTailBin'. Used to
-- fill the @max_locals@ field of the Code attribute (JVM Spec §4.7.3);
-- hardcoding 256 there caused @ClassFormatError: bad type array size@
-- on programs whose StackMapTable referenced a slot index ≥ 256.
exprMaxLocals :: CExpr -> Int
exprMaxLocals = \case
  -- 'CCase' burns 2 slots per level (arrSlot for the @Object[]@,
  -- tagSlot for the unboxed @int@ tag) plus @maxBindings@ binding
  -- slots reserved across every arm — see 'emitExpr' / 'emitTailCase'
  -- comments for why bindings are sized to the widest arm.
  CCase _ alts ->
    let thisLevel = 2 + foldl' max 0 [length vs | (_, vs, _) <- alts]
        armMax = foldl' max 0 [exprMaxLocals b | (_, _, b) <- alts]
     in thisLevel + armMax
  CCall f xs -> foldl' max 0 (exprMaxLocals f : map exprMaxLocals xs)
  CCon _ fields -> foldl' max 0 (map exprMaxLocals fields)
  CLoop b -> exprMaxLocals b
  CContinue xs -> foldl' max 0 (map exprMaxLocals xs)
  _ -> 0

-- | Maximum operand-stack depth a body ever reaches. Mirrors the
-- emission shape: 'CCon' uses a dup/stelem chain so each nesting
-- level pins one extra slot on the stack across the next field's
-- evaluation; 'CCase' clears the stack at @astore@ and only peaks
-- transiently while extracting the tag; 'CCall' stacks args
-- left-to-right. Used to fill the @max_stack@ field of the Code
-- attribute (JVM Spec §4.7.3).
exprMaxStack :: CExpr -> Int
exprMaxStack = \case
  CString _ -> 1
  CIntLit _ _ -> 1
  CBuiltIn _ -> 1
  CVar _ -> 1
  CCon _ fields ->
    -- Per-field emission shape is @dup; iconst i; <field>; aastore@,
    -- so the array + index already pin two slots on the stack across
    -- the field's evaluation, and a third slot is pushed by the dup
    -- itself before the index — peak per level is 3 + max field depth.
    -- The tag store @dup; iconst 0; iconst tag; invokestatic
    -- Integer.valueOf; aastore@ peaks at 4 independently.
    let maxFld = foldl' max 0 (map exprMaxStack fields)
     in max 4 (3 + maxFld)
  CCase scrut alts ->
    -- Scrutinee leaves +1, then dup+iconst+aaload+ checkcast +invokevirtual peaks at ~3,
    -- arms emit independently after astore drops to 0.
    foldl' max 3 (exprMaxStack scrut : [exprMaxStack b | (_, _, b) <- alts])
  CCall f xs ->
    -- Conservative bound: assume the first-class shape, where the
    -- callee occupies one stack slot across the evaluation of every
    -- arg (CBuiltIn / direct-CFunDef calls do not, but overestimating
    -- by one slot is harmless and keeps this helper context-free —
    -- 'exprMaxStack' has no view of @cFunDefs@). A CVar callee that
    -- happens to be a *parameter* (and so is *not* in @cFunDefs@) is
    -- a first-class call and absolutely needs the +1; treating every
    -- @CCall@ uniformly avoids the silent under-count that crashed
    -- @v_compose@ / @v_apply@ / @v__apply_map@ with @VerifyError:
    -- Operand stack overflow@.
    let argDepths = map exprMaxStack xs
        fD = exprMaxStack f
        nXs = length xs
        seqArgs base = foldl' max base [base + i + d | (i, d) <- zip [0 :: Int ..] argDepths]
     in max fD (max (seqArgs 1) (nXs + 1))
  CLoop b -> exprMaxStack b
  CContinue xs ->
    let argDepths = map exprMaxStack xs
     in foldl' max 0 [i + d | (i, d) <- zip [0 :: Int ..] argDepths]

-- | Metadata about branch targets (for StackMapTable generation)
data BranchTarget = BranchTarget
  { btOffset :: Int, -- bytecode offset of the branch target
    btLocals :: Int, -- number of local variables at this point
    btArrSlot :: Int, -- slot number for the array local (if applicable)
    btTagSlot :: Int, -- slot number for the tag local (if applicable)
    btIsJoinPoint :: Bool -- True for join points (gotos), False for if_icmpne targets
  }
  deriving stock (Show, Eq)

-- | Result of expression compilation with branch metadata.
-- 'cwIntSlots' lists every local slot the emitted bytecode stores an int
-- into. In user-code emission this is exclusively case-tag storage from
-- 'CCase' arms; carrying it alongside 'cwBranchTargets' lets
-- 'caseSMT' resolve slot types correctly even for single-arm cases
-- which produce no 'BranchTarget' but still occupy a tag slot. Without
-- it, an outer 'BranchTarget' that doesn't itself touch the inner case's
-- tag slot would describe that slot as 'Object' in its frame, while the
-- verifier sees @int@ from the path through the inner arm — a merge of
-- @int + Object@ is @Top@ and the class-load fails.
data CodeWithMeta = CodeWithMeta
  { cwCode :: [Word8],
    cwBranchTargets :: [BranchTarget],
    cwIntSlots :: [Int]
  }

-- | Construct a 'CodeWithMeta' with no case-tag side effects. The vast
-- majority of leaf emitters never store an int, so this convenience
-- avoids littering every call site with a third empty argument.
cwm :: [Word8] -> [BranchTarget] -> CodeWithMeta
cwm code bts = CodeWithMeta code bts []

-- | Glue together one or more sub-expression metas plus a suffix
-- bytecode (typically @invokestatic@ / @invokevirtual@ for a builtin
-- call). Concatenates code, propagates branch targets and int slots
-- from every sub-expression. Lets call sites stop hand-wiring three
-- fields per emitter.
cwmWrap :: [Word8] -> [CodeWithMeta] -> CodeWithMeta
cwmWrap suffix metas =
  CodeWithMeta
    { cwCode = concatMap cwCode metas <> suffix,
      cwBranchTargets = concatMap cwBranchTargets metas,
      cwIntSlots = concatMap cwIntSlots metas
    }

mkDecl :: Set Text -> Set Text -> Map Text Int -> CDecl -> AsmM MInfo
mkDecl valDefs funDefs arities = \case
  -- TCO-wrapped body. The method's first bytecode byte (offset 0) is the
  -- implicit @L_tco_loop@: JVM already gives us a StackMapTable frame
  -- there based on the method signature. 'CContinue' evaluates new args,
  -- @astore@s them into parameter slots in reverse (LIFO), and @goto@s
  -- back to offset 0. Value tails emit their own @areturn@, so the
  -- method body needs no fallthrough @areturn@.
  CFunDef nm args (CLoop body) -> do
    let paramMap = Map.fromList (zip args [0 ..])
        ctx =
          ECtx
            { cParams = paramMap,
              cLocals = Map.empty,
              cValDefs = valDefs,
              cFunDefs = funDefs,
              cArities = arities,
              cNextLocal = length args
            }
        maxLocals = fromIntegral (length args + exprMaxLocals body) :: Word16
        maxStack = fromIntegral (max 1 (exprMaxStack body)) :: Word16
    ni <- addUtf8 (mangle nm)
    di <- addUtf8 (objMethodDesc (length args))
    codeMeta <- emitTailBin ctx args 0 body
    -- The @goto@ emitted by 'CContinue' branches back to offset 0, so
    -- the JVM verifier requires an explicit StackMapTable frame there
    -- (the implicit initial frame is not enough once offset 0 is a real
    -- branch target). The locals at entry are the @length args@ param
    -- slots, all @java/lang/Object@, and the operand stack is empty —
    -- matching the signature-derived initial state exactly.
    let tcoLoopTarget =
          BranchTarget
            { btOffset = 0,
              btLocals = length args,
              btArrSlot = -1,
              btTagSlot = -1,
              btIsJoinPoint = False
            }
    (smtCount, smtBytes) <- caseSMT ctx (tcoLoopTarget : codeMeta.cwBranchTargets) codeMeta.cwIntSlots
    pure MInfo {mFlags = 0x0008, mName = ni, mDesc = di, mCode = codeMeta.cwCode, mCodeAttrCount = smtCount, mCodeAttrs = smtBytes, mMaxStack = maxStack, mMaxLocals = maxLocals}
  CFunDef nm args body -> do
    let paramMap = Map.fromList (zip args [0 ..])
        ctx =
          ECtx
            { cParams = paramMap,
              cLocals = Map.empty,
              cValDefs = valDefs,
              cFunDefs = funDefs,
              cArities = arities,
              cNextLocal = length args
            }
        maxLocals = fromIntegral (length args + exprMaxLocals body) :: Word16
        maxStack = fromIntegral (max 1 (exprMaxStack body)) :: Word16
    ni <- addUtf8 (mangle nm)
    di <- addUtf8 (objMethodDesc (length args))
    codeMeta <- emitExpr ctx body
    (smtCount, smtBytes) <- caseSMT ctx codeMeta.cwBranchTargets codeMeta.cwIntSlots
    pure MInfo {mFlags = 0x0008, mName = ni, mDesc = di, mCode = codeMeta.cwCode <> [0xB0], mCodeAttrCount = smtCount, mCodeAttrs = smtBytes, mMaxStack = maxStack, mMaxLocals = maxLocals}
  CValDef nm rhs -> do
    let ctx =
          ECtx
            { cParams = Map.empty,
              cLocals = Map.empty,
              cValDefs = valDefs,
              cFunDefs = funDefs,
              cArities = arities,
              cNextLocal = 0
            }
        maxLocals = fromIntegral (exprMaxLocals rhs) :: Word16
        maxStack = fromIntegral (max 1 (exprMaxStack rhs)) :: Word16
    ni <- addUtf8 (mangle nm)
    di <- addUtf8 "()Ljava/lang/Object;"
    codeMeta <- emitExpr ctx rhs
    (smtCount, smtBytes) <- caseSMT ctx codeMeta.cwBranchTargets codeMeta.cwIntSlots
    pure MInfo {mFlags = 0x0008, mName = ni, mDesc = di, mCode = codeMeta.cwCode <> [0xB0], mCodeAttrCount = smtCount, mCodeAttrs = smtBytes, mMaxStack = maxStack, mMaxLocals = maxLocals}

-- ════════════════════════════════════════════════════════════════════════════
-- Expression codegen (bytecode bytes)
-- ════════════════════════════════════════════════════════════════════════════

-- | Emit bytecode that leaves the expression result on top of the operand stack.
--   Returns bytecode and metadata about branch targets for StackMapTable generation.
emitExpr :: ECtx -> CExpr -> AsmM CodeWithMeta
emitExpr ctx = \case
  CString s -> do
    idx <- addStr s
    pure $ cwm (bcLdc idx) []
  CVar n
    | Just slot <- Map.lookup n ctx.cLocals ->
        pure $ cwm (bcAload slot) []
    | Just slot <- Map.lookup n ctx.cParams ->
        pure $ cwm (bcAload slot) []
    | n `Set.member` ctx.cValDefs -> do
        ref <- addMRef "AwsumMain" (mangle n) "()Ljava/lang/Object;"
        pure $ cwm (bcInvokeStatic ref) []
    | n `Set.member` ctx.cFunDefs -> do
        let arity = fromMaybe 0 (Map.lookup n ctx.cArities)
        hi <- addMHandle 6 "AwsumMain" (mangle n) (objMethodDesc arity)
        pure $ cwm (bcLdc hi) []
    | otherwise ->
        pure $ cwm [0x01] [] -- aconst_null
  CBuiltIn _ ->
    pure $ cwm [0x01] [] -- aconst_null; dispatched from CCall
  CIntLit n it -> do
    -- Both Int32 and UInt8 are represented as java.lang.Integer on the JVM.
    -- UInt8 uses Integer (not java.lang.Byte) because Java byte is signed
    -- 8-bit — storing an Integer lets the value space stay 0..255 without
    -- surprises when we later add arithmetic.
    let n32 = fromInteger n :: Int32
    pushCode <- bcLoadInt32 n32
    valueOfRef <- addMRef "java/lang/Integer" "valueOf" "(I)Ljava/lang/Integer;"
    let _ = it -- reserved for future per-type boxing (e.g. Long for Int64)
    pure $ cwm (pushCode <> bcInvokeStatic valueOfRef) []
  CCon tag fields -> do
    -- Create Object[] container: [tag_as_Integer, field1, field2, ...]
    let nSlots = 1 + length fields
    intRef <- addMRef "java/lang/Integer" "valueOf" "(I)Ljava/lang/Integer;"
    objCls <- addClass "java/lang/Object"
    let allocCode = bcIconst nSlots <> [0xBD, hi8 objCls, lo8 objCls] -- anewarray
        storeTag =
          [0x59] -- dup
            <> bcIconst 0
            <> bcIconst tag
            <> bcInvokeStatic intRef
            <> [0x53] -- aastore
    fieldMetas <- forM (zip fields [1 :: Int ..]) $ \(fld, i) -> do
      fldMeta <- emitExpr ctx fld
      pure
        CodeWithMeta
          { cwCode = [0x59] <> bcIconst i <> fldMeta.cwCode <> [0x53],
            cwBranchTargets = fldMeta.cwBranchTargets,
            cwIntSlots = fldMeta.cwIntSlots
          }
    let allTargets = concatMap cwBranchTargets fieldMetas
        allCode = allocCode <> storeTag <> concatMap cwCode fieldMetas
        allIntSlots = concatMap cwIntSlots fieldMetas
    pure CodeWithMeta {cwCode = allCode, cwBranchTargets = allTargets, cwIntSlots = allIntSlots}
  CCase scrut alts -> do
    intCls <- addClass "java/lang/Integer"
    intValRef <- addMRef "java/lang/Integer" "intValue" "()I"
    arrCls <- addClass "[Ljava/lang/Object;"
    scrutMeta <- emitExpr ctx scrut
    let sorted = sortWith (\(t, _, _) -> t) alts
        -- Local slots: arrSlot stores the Object[], tagSlot stores the int tag
        arrSlot = ctx.cNextLocal
        tagSlot = arrSlot + 1
        bindSlotStart = tagSlot + 1
        loadArr = bcAload arrSlot
    -- Emit arm bodies with bound variables
    let maxBindingsCount = foldl' max 0 [length vars | (_, vars, _) <- sorted]
    armMetasWithLocals <- forM sorted $ \(_, vars, body) -> do
      let bindings = zip vars [bindSlotStart ..]
          -- Advance cNextLocal past *every* arm's potential bindings, not just
          -- this arm's. Otherwise a sibling arm with more vars and a sibling
          -- arm with fewer vars would each open inner cases at different
          -- slot indices that overlap in the outer case's join-point frame:
          -- one path leaves slot K bound to an inner case's tag (int), the
          -- other leaves it bound to an outer-binding (Object), and the
          -- verifier merge of int + Object is Top — but the SMT codegen
          -- emits Object, which the verifier rejects on class load. Mirrors
          -- the tail-position emitter ('emitTailCase' below) which has
          -- always used 'bindSlotStart + maxBindingsCount' for the same
          -- reason.
          ctx' = ctx {cLocals = foldl' (\m (v, s) -> Map.insert v s m) ctx.cLocals bindings, cNextLocal = bindSlotStart + maxBindingsCount}
          bindCode =
            concatMap
              ( \((_, slot), i) ->
                  loadArr <> bcIconst (i :: Int) <> [0x32] <> bcAstore slot
              )
              (zip bindings [1 :: Int ..])
          -- Pad unused binding slots with null to match maxBindingsCount
          numUnusedSlots = maxBindingsCount - length vars
          paddingCode =
            if numUnusedSlots > 0
              then
                concatMap
                  (\slot -> [0x01] <> bcAstore slot) -- aconst_null, astore
                  [bindSlotStart + length vars .. bindSlotStart + maxBindingsCount - 1]
              else []
          -- Only count this arm's bindings, not nested case locals
          armLocals = bindSlotStart + maxBindingsCount
          bindCodeLen = length bindCode + length paddingCode
      bodyMeta <- emitExpr ctx' body
      -- Branch targets will be adjusted later in buildChainWithTargets
      pure
        ( ( CodeWithMeta
              { cwCode = bindCode <> paddingCode <> bodyMeta.cwCode,
                cwBranchTargets = bodyMeta.cwBranchTargets,
                cwIntSlots = bodyMeta.cwIntSlots
              },
            bindCodeLen
          ),
          armLocals
        )
    let armMetasWithBindLen = map fst armMetasWithLocals
        armMetas = map fst armMetasWithBindLen
        bindLens = map snd armMetasWithBindLen
        tags = [t | (t, _, _) <- sorted]
        loadTag = bcIload tagSlot
        extractAndStore =
          bcCheckCast arrCls
            <> bcAstore arrSlot
            <> loadArr
            <> bcIconst 0
            <> [0x32] -- aaload
            <> bcCheckCast intCls
            <> bcInvokeVirtual intValRef
            <> bcIstore tagSlot
        preambleLen = length scrutMeta.cwCode + length extractAndStore

        -- Build chain and collect branch targets
        buildChainWithTargets :: Int -> [(Int, CodeWithMeta, Int)] -> ([Word8], [BranchTarget])
        buildChainWithTargets _ [] = ([0x01], [])
        buildChainWithTargets offset [(_, armMeta, bindLen)] =
          -- Single arm: adjust nested targets to account for offset + bindCode
          let adjustedTargets = map (\bt -> bt {btOffset = bt.btOffset + offset + bindLen}) armMeta.cwBranchTargets
           in (armMeta.cwCode, adjustedTargets)
        buildChainWithTargets offset ((tag', armMeta, bindLen) : rest) =
          let loadLen = length loadTag
              iconLen = length (bcIconst tag')
              bodyLen = length armMeta.cwCode
              gotoLen :: Int
              gotoLen = 3
              skipOffset = 3 + bodyLen + gotoLen
              -- The branch target is where if_icmpne jumps: after current arm + goto
              nextBranchOffset = offset + loadLen + iconLen + skipOffset
              (restCode, restTargets) = buildChainWithTargets nextBranchOffset rest
              restLen = length restCode
              gotoOffset = restLen + gotoLen
              cmpCode = loadTag <> bcIconst tag' <> [0xA0, fromIntegral (skipOffset `div` 256), fromIntegral (skipOffset `mod` 256)]
              gotoCode = [0xA7, fromIntegral (gotoOffset `div` 256), fromIntegral (gotoOffset `mod` 256)]
              myTarget = BranchTarget nextBranchOffset bindSlotStart arrSlot tagSlot False -- if_icmpne target
              -- Adjust nested branch target offsets: body starts after cmpCode + bindCode
              armBodyStartOffset = offset + loadLen + iconLen + 3 + bindLen
              adjustedArmTargets = map (\bt -> bt {btOffset = bt.btOffset + armBodyStartOffset}) armMeta.cwBranchTargets
              combinedTargets = myTarget : adjustedArmTargets ++ restTargets
           in (cmpCode <> armMeta.cwCode <> gotoCode <> restCode, combinedTargets)

        (chainCode, branchTargets) = buildChainWithTargets preambleLen (zip3 tags armMetas bindLens)
        -- Add join point for multi-arm cases (where goto jumps)
        -- For nested cases this is needed; for top-level it points past the end but won't be used
        hasMultipleArms = length sorted > 1
        joinPointOffset = preambleLen + length chainCode
        maxLocals = bindSlotStart + maxBindingsCount
        joinPointTarget = ([BranchTarget joinPointOffset maxLocals arrSlot tagSlot True | hasMultipleArms]) -- join point
        allTargets = scrutMeta.cwBranchTargets ++ branchTargets ++ joinPointTarget
        finalCode = scrutMeta.cwCode <> extractAndStore <> chainCode
        -- 'tagSlot' itself is stored as an int by 'extractAndStore'; it's
        -- valid even for single-arm cases (which produce no BranchTarget)
        -- and must reach 'caseSMT' so outer-frame slot type resolution
        -- accounts for it.
        allIntSlots = tagSlot : scrutMeta.cwIntSlots ++ concatMap cwIntSlots armMetas
    pure CodeWithMeta {cwCode = finalCode, cwBranchTargets = allTargets, cwIntSlots = allIntSlots}
  CCall f xs ->
    case f of
      CBuiltIn "IO.Stdout.print" | [x] <- xs -> do
        xMeta <- emitExpr ctx x
        ref <- addMRef "AwsumMain" "__print" "(Ljava/lang/Object;)Ljava/lang/Object;"
        pure $ cwmWrap (bcInvokeStatic ref) [xMeta]
      CBuiltIn name
        | name == "showInt32" || name == "showUInt8",
          [x] <- xs -> do
            -- The value on the stack is a java.lang.Integer (how CIntLit
            -- emits both Int32 and UInt8). Cast to Integer and call its
            -- toString() — decimal representation with no padding or signs
            -- beyond '-', matching snprintf("%d") on LLVM.
            xMeta <- emitExpr ctx x
            intCls <- addClass "java/lang/Integer"
            toStr <- addMRef "java/lang/Integer" "toString" "()Ljava/lang/String;"
            pure $ cwmWrap (bcCheckCast intCls <> bcInvokeVirtual toStr) [xMeta]
      CBuiltIn "predInt32" | [x] <- xs -> do
        xMeta <- emitExpr ctx x
        ref <- addMRef "AwsumMain" "__predInt32" "(Ljava/lang/Object;)Ljava/lang/Object;"
        pure $ cwmWrap (bcInvokeStatic ref) [xMeta]
      CBuiltIn "predUInt8" | [x] <- xs -> do
        xMeta <- emitExpr ctx x
        ref <- addMRef "AwsumMain" "__predUInt8" "(Ljava/lang/Object;)Ljava/lang/Object;"
        pure $ cwmWrap (bcInvokeStatic ref) [xMeta]
      CBuiltIn "succInt32" | [x] <- xs -> do
        xMeta <- emitExpr ctx x
        ref <- addMRef "AwsumMain" "__succInt32" "(Ljava/lang/Object;)Ljava/lang/Object;"
        pure $ cwmWrap (bcInvokeStatic ref) [xMeta]
      CBuiltIn "succUInt8" | [x] <- xs -> do
        xMeta <- emitExpr ctx x
        ref <- addMRef "AwsumMain" "__succUInt8" "(Ljava/lang/Object;)Ljava/lang/Object;"
        pure $ cwmWrap (bcInvokeStatic ref) [xMeta]
      CBuiltIn name
        | name == "eqInt32" || name == "eqUInt8",
          [a, b] <- xs -> do
            aMeta <- emitExpr ctx a
            bMeta <- emitExpr ctx b
            let fn = if name == "eqInt32" then "__eqInt32" else "__eqUInt8"
            ref <- addMRef "AwsumMain" fn "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"
            pure $ cwmWrap (bcInvokeStatic ref) [aMeta, bMeta]
      CBuiltIn name
        | name == "addInt32" || name == "addUInt8" || name == "subInt32" || name == "subUInt8" || name == "mulUInt8" || name == "mulInt32",
          [a, b] <- xs -> do
            aMeta <- emitExpr ctx a
            bMeta <- emitExpr ctx b
            let fn = case name of
                  "addInt32" -> "__addInt32"
                  "addUInt8" -> "__addUInt8"
                  "subInt32" -> "__subInt32"
                  "subUInt8" -> "__subUInt8"
                  "mulInt32" -> "__mulInt32"
                  _ -> "__mulUInt8"
            ref <- addMRef "AwsumMain" fn "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"
            pure $ cwmWrap (bcInvokeStatic ref) [aMeta, bMeta]
      CBuiltIn "negInt32" | [x] <- xs -> do
        xMeta <- emitExpr ctx x
        ref <- addMRef "AwsumMain" "__negInt32" "(Ljava/lang/Object;)Ljava/lang/Object;"
        pure $ cwmWrap (bcInvokeStatic ref) [xMeta]
      CBuiltIn "concatString" | [a, b] <- xs -> do
        aMeta <- emitExpr ctx a
        bMeta <- emitExpr ctx b
        ref <- addMRef "AwsumMain" "__concat" "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"
        pure $ cwmWrap (bcInvokeStatic ref) [aMeta, bMeta]
      CBuiltIn "splitOnFirst" | [a, b] <- xs -> do
        aMeta <- emitExpr ctx a
        bMeta <- emitExpr ctx b
        ref <- addMRef "AwsumMain" "__splitOnFirst" "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"
        pure $ cwmWrap (bcInvokeStatic ref) [aMeta, bMeta]
      CBuiltIn name
        | name == "parseInt32" || name == "parseUInt8",
          [x] <- xs -> do
            xMeta <- emitExpr ctx x
            let fn = if name == "parseInt32" then "__parseInt32" else "__parseUInt8"
            ref <- addMRef "AwsumMain" fn "(Ljava/lang/Object;)Ljava/lang/Object;"
            pure $ cwmWrap (bcInvokeStatic ref) [xMeta]
      CBuiltIn n ->
        error ("JVM codegen: unknown builtin '" <> n <> "' reached CCall (typecheck should have rejected it)")
      CVar n | n `Set.member` ctx.cFunDefs -> do
        -- Direct call to known function
        argMetas <- traverse (emitExpr ctx) xs
        ref <- addMRef "AwsumMain" (mangle n) (objMethodDesc (length xs))
        pure $ cwmWrap (bcInvokeStatic ref) argMetas
      _ -> do
        -- Indirect call via MethodHandle
        -- Stack layout: MethodHandle arg1 arg2 ...
        fMeta <- emitExpr ctx f
        mhCls <- addClass "java/lang/invoke/MethodHandle"
        argMetas <- traverse (emitExpr ctx) xs
        let invokeDesc = objMethodDesc (length xs)
        ref <- addMRef "java/lang/invoke/MethodHandle" "invoke" invokeDesc
        let allCode = fMeta.cwCode <> bcCheckCast mhCls <> concatMap cwCode argMetas <> bcInvokeVirtual ref
            allTargets = fMeta.cwBranchTargets ++ concatMap cwBranchTargets argMetas
            allIntSlots = fMeta.cwIntSlots ++ concatMap cwIntSlots argMetas
        pure CodeWithMeta {cwCode = allCode, cwBranchTargets = allTargets, cwIntSlots = allIntSlots}
  CLoop _ -> error "JVM Assemble: CLoop reached emitExpr (non-tail position)"
  CContinue _ -> error "JVM Assemble: CContinue reached emitExpr (non-tail position)"

-- | Emit @body@ in tail position under the implicit @L_tco_loop:@ label
-- at method offset 0. 'CContinue' evaluates new parameter values onto
-- the operand stack (so cross-parameter reads see the old bindings),
-- pops them back into the parameter locals in reverse (LIFO), and
-- @goto@s the method's first byte. Tail value shapes emit their own
-- @areturn@. 'CCase' dispatches via an @if_icmpne@ chain where each
-- arm self-terminates — no @goto join@ is needed. StackMapTable entries
-- are collected for every @if_icmpne@ target; offset 0 needs no entry
-- because the method signature gives the implicit initial frame.
emitTailBin :: ECtx -> [Text] -> Int -> CExpr -> AsmM CodeWithMeta
emitTailBin ctx0 params = goTop ctx0
  where
    goTop :: ECtx -> Int -> CExpr -> AsmM CodeWithMeta
    goTop ctx offset = \case
      CContinue newArgs -> emitContinue ctx offset newArgs
      CCase scrut alts -> emitTailCase ctx offset scrut alts
      other -> emitTailValue ctx other

    emitContinue :: ECtx -> Int -> [CExpr] -> AsmM CodeWithMeta
    emitContinue ctx offset newArgs = do
      argMetas <- traverse (emitExpr ctx) newArgs
      let argBytes = concatMap cwCode argMetas
          -- Nested branch targets inside arg evaluations would need offset
          -- adjustment, but in practice argument expressions rarely contain
          -- CCase; the existing CCon/CCall paths also pass them through
          -- without adjustment, so we match that convention.
          argTargets = concatMap cwBranchTargets argMetas
          paramSlots :: [Int]
          paramSlots =
            [ fromMaybe
                (error $ "JVM Assemble: no param slot for " <> show p)
                (Map.lookup p ctx.cParams)
            | p <- params
            ]
          astoreBytes :: [Word8]
          astoreBytes = concat [bcAstore s | s <- reverse paramSlots]
          gotoStart :: Int
          gotoStart = offset + length argBytes + length astoreBytes
          delta :: Int
          delta = negate gotoStart
          gotoBytes = bcGoto delta
          argIntSlots = concatMap cwIntSlots argMetas
      pure
        CodeWithMeta
          { cwCode = argBytes <> astoreBytes <> gotoBytes,
            cwBranchTargets = argTargets,
            cwIntSlots = argIntSlots
          }

    emitTailValue :: ECtx -> CExpr -> AsmM CodeWithMeta
    emitTailValue ctx expr = do
      meta <- emitExpr ctx expr
      pure
        CodeWithMeta
          { cwCode = meta.cwCode <> [0xB0],
            cwBranchTargets = meta.cwBranchTargets,
            cwIntSlots = meta.cwIntSlots
          } -- areturn
    emitTailCase :: ECtx -> Int -> CExpr -> [(Int, [Text], CExpr)] -> AsmM CodeWithMeta
    emitTailCase ctx offset scrut alts = do
      intCls <- addClass "java/lang/Integer"
      intValRef <- addMRef "java/lang/Integer" "intValue" "()I"
      arrCls <- addClass "[Ljava/lang/Object;"
      scrutMeta <- emitExpr ctx scrut
      let sorted = sortWith (\(t, _, _) -> t) alts
          arrSlot = ctx.cNextLocal
          tagSlot = arrSlot + 1
          bindSlotStart = tagSlot + 1
          loadArr = bcAload arrSlot
          loadTag = bcIload tagSlot
          maxBindingsCount = foldl' max 0 [length vs | (_, vs, _) <- sorted]
          extractAndStore =
            bcCheckCast arrCls
              <> bcAstore arrSlot
              <> loadArr
              <> bcIconst 0
              <> [0x32] -- aaload
              <> bcCheckCast intCls
              <> bcInvokeVirtual intValRef
              <> bcIstore tagSlot
          preambleLen = length scrutMeta.cwCode + length extractAndStore
          armsBaseOffset = offset + preambleLen
      -- Emit each arm's body in tail form. The binding code depends on
      -- ctx; the body offset depends on the chain built so far — so we
      -- fold across arms, threading the running arm-start offset and
      -- accumulating code + branch targets.
      let goArms :: Int -> [(Int, [Text], CExpr)] -> AsmM ([Word8], [BranchTarget], [Int])
          goArms _ [] =
            -- Empty CCase: emit aconst_null so the stack is consistent.
            -- Should not happen for well-typed programs.
            pure ([0x01], [], [])
          goArms armOffset [(_, vars, armBody)] = do
            let bindings = zip vars [bindSlotStart ..]
                ctx' =
                  ctx
                    { cLocals = foldl' (\m (v, s) -> Map.insert v s m) ctx.cLocals bindings,
                      cNextLocal = bindSlotStart + maxBindingsCount
                    }
                bindCode :: [Word8]
                bindCode =
                  concatMap
                    ( \((_, slot), i) ->
                        loadArr <> bcIconst (i :: Int) <> [0x32] <> bcAstore slot
                    )
                    (zip bindings [1 :: Int ..])
                numUnusedSlots = maxBindingsCount - length vars
                paddingCode :: [Word8]
                paddingCode =
                  if numUnusedSlots > 0
                    then
                      concatMap
                        (\slot -> [0x01] <> bcAstore slot)
                        [bindSlotStart + length vars .. bindSlotStart + maxBindingsCount - 1]
                    else []
                prefix = bindCode <> paddingCode
                bodyStart = armOffset + length prefix
            bodyMeta <- goTop ctx' bodyStart armBody
            pure (prefix <> bodyMeta.cwCode, bodyMeta.cwBranchTargets, bodyMeta.cwIntSlots)
          goArms armOffset ((tag, vars, armBody) : rest) = do
            let cmpPrefixBytes = loadTag <> bcIconst tag
                cmpPrefixLen = length cmpPrefixBytes
                icmpneLen :: Int
                icmpneLen = 3
                bindings = zip vars [bindSlotStart ..]
                ctx' =
                  ctx
                    { cLocals = foldl' (\m (v, s) -> Map.insert v s m) ctx.cLocals bindings,
                      cNextLocal = bindSlotStart + maxBindingsCount
                    }
                bindCode :: [Word8]
                bindCode =
                  concatMap
                    ( \((_, slot), i) ->
                        loadArr <> bcIconst (i :: Int) <> [0x32] <> bcAstore slot
                    )
                    (zip bindings [1 :: Int ..])
                numUnusedSlots = maxBindingsCount - length vars
                paddingCode :: [Word8]
                paddingCode =
                  if numUnusedSlots > 0
                    then
                      concatMap
                        (\slot -> [0x01] <> bcAstore slot)
                        [bindSlotStart + length vars .. bindSlotStart + maxBindingsCount - 1]
                    else []
                prefix = bindCode <> paddingCode
                bodyStart = armOffset + cmpPrefixLen + icmpneLen + length prefix
            bodyMeta <- goTop ctx' bodyStart armBody
            let armBodyLen = length bodyMeta.cwCode
                -- @if_icmpne@ target is the next arm's start — after
                -- cmpPrefix + icmpne + bind/padding + arm body.
                skipOff = icmpneLen + length prefix + armBodyLen
                nextArmOffset = armOffset + cmpPrefixLen + skipOff
                icmpneBytes =
                  [ 0xA0,
                    fromIntegral (skipOff `div` 256),
                    fromIntegral (skipOff `mod` 256)
                  ]
                myTarget =
                  BranchTarget
                    { -- At the branch target the next arm's bindings have
                      -- not been stored yet, so only slots up to (but not
                      -- including) 'bindSlotStart' are live. Mirrors the
                      -- non-tail 'CCase' emission — see 'emitExpr'.
                      btOffset = nextArmOffset,
                      btLocals = bindSlotStart,
                      btArrSlot = arrSlot,
                      btTagSlot = tagSlot,
                      btIsJoinPoint = False
                    }
            (restBytes, restTargets, restIntSlots) <- goArms nextArmOffset rest
            pure
              ( cmpPrefixBytes <> icmpneBytes <> prefix <> bodyMeta.cwCode <> restBytes,
                myTarget : bodyMeta.cwBranchTargets <> restTargets,
                bodyMeta.cwIntSlots <> restIntSlots
              )
      (chainBytes, chainTargets, chainIntSlots) <- goArms armsBaseOffset sorted
      let allBytes = scrutMeta.cwCode <> extractAndStore <> chainBytes
          allTargets = scrutMeta.cwBranchTargets <> chainTargets
          -- 'tagSlot' itself is stored as an int by 'extractAndStore';
          -- include it so 'caseSMT' types it correctly even for
          -- single-arm cases that produce no BranchTarget.
          allIntSlots = tagSlot : scrutMeta.cwIntSlots <> chainIntSlots
      pure CodeWithMeta {cwCode = allBytes, cwBranchTargets = allTargets, cwIntSlots = allIntSlots}

-- ════════════════════════════════════════════════════════════════════════════
-- StackMapTable for CCase branches
-- ════════════════════════════════════════════════════════════════════════════

-- | Compute StackMapTable attribute from collected branch targets and
--   the union of all slots ever stored as @int@ (case-tag slots that
--   may have come from cases with no 'BranchTarget' of their own —
--   i.e. single-arm cases that did not need an @if_icmpne@). The latter
--   is required because the verifier sees @int@ in such slots from
--   paths that pass through an inner case body, and the SMT type at
--   any outer-frame target must agree with that observation rather
--   than blindly defaulting to @Object@.
caseSMT :: ECtx -> [BranchTarget] -> [Int] -> AsmM (Word16, [Word8])
caseSMT _ctx targets intSlots
  | null targets = pure (0, [])
  | otherwise = do
      smtNameIdx <- addUtf8 "StackMapTable"
      objClsIdx <- addClass "java/lang/Object"
      arrClsIdx <- addClass "[Ljava/lang/Object;"
      let sorted = sortOn btOffset targets
          -- Deduplicate by offset, keeping the target with the NARROWEST
          -- live-locals set. Nested 'CCase's emit their own join-point
          -- targets, and when no instructions sit between inner and outer
          -- joins (typical when the inner case is the last expression of
          -- an outer arm) the targets collapse onto the same bytecode
          -- offset. The stackmap at that offset must describe the
          -- intersection of live locals across every incoming edge — the
          -- outermost case's (smaller) frame — because outer-arm gotos
          -- arrive there with only the outer case's slots defined. Slots
          -- above this min are treated as @top@ by the verifier, which is
          -- safe because no post-join code reads them.
          deduped = Map.elems $ Map.fromListWith (\a b -> if a.btLocals <= b.btLocals then a else b) [(t.btOffset, t) | t <- sorted]
          dedupedSorted = sortOn btOffset deduped
      pure (1, buildSMTAttr smtNameIdx arrClsIdx objClsIdx dedupedSorted)
  where
    intSlotSet :: Set Int
    intSlotSet = Set.fromList intSlots
    buildSMTAttr :: Word16 -> Word16 -> Word16 -> [BranchTarget] -> [Word8]
    buildSMTAttr smtNameIdx arrClsIdx objClsIdx targets' =
      let frameBytes = buildFrames targets' (-1) targets'
          attrLen = 2 + length frameBytes
          nTargets = length targets'
       in [hi8 smtNameIdx, lo8 smtNameIdx]
            <> encodeU4 attrLen
            <> [fromIntegral (nTargets `div` 256), fromIntegral (nTargets `mod` 256)]
            <> frameBytes
      where
        -- Collect all (arrSlot, tagSlot) pairs from all targets for type resolution
        buildFrames :: [BranchTarget] -> Int -> [BranchTarget] -> [Word8]
        buildFrames _ _ [] = []
        buildFrames allTgts prev (bt : rest) =
          let delta = if prev == -1 then bt.btOffset else bt.btOffset - prev - 1
              currentLocals = bt.btLocals
              allArrTagPairs = [(t.btArrSlot, t.btTagSlot) | t <- allTgts]
              localsTypes = buildLocalsTypes allArrTagPairs bt
              -- Join points are reached by an explicit @goto@ emitted
              -- after the arm body has left its value on the stack, so
              -- SMT records one 'Object' there. Every other target is
              -- an @if_icmpne@ landing site, which is reached after the
              -- comparison has popped both ints — the stack is empty.
              -- (Pre-TCO this happened to coincide with "last frame",
              -- because the join always sat at the highest offset; the
              -- TCO path has no join, so we must not infer it.)
              frame
                | bt.btIsJoinPoint =
                    [255]
                      <> encodeDelta delta
                      <> encodeU2 currentLocals
                      <> localsTypes
                      <> encodeU2 1
                      <> [0x07, hi8 objClsIdx, lo8 objClsIdx]
                | otherwise =
                    [255]
                      <> encodeDelta delta
                      <> encodeU2 currentLocals
                      <> localsTypes
                      <> encodeU2 0
           in frame <> buildFrames allTgts bt.btOffset rest

        buildLocalsTypes :: [(Int, Int)] -> BranchTarget -> [Word8]
        buildLocalsTypes allArrTagPairs bt =
          let n = bt.btLocals
           in if n <= 1
                then concat (replicate n [0x07, hi8 objClsIdx, lo8 objClsIdx])
                else
                  -- Build types for each slot, checking all arr/tag pairs
                  let slotTypes = [slotType i | i <- [0 .. n - 1]]
                      slotType i
                        | i == 0 = [0x07, hi8 objClsIdx, lo8 objClsIdx] -- param
                        | any (\(arr, _) -> arr == i) allArrTagPairs = [0x07, hi8 arrClsIdx, lo8 arrClsIdx] -- array
                        | any (\(_, tag) -> tag == i) allArrTagPairs = [0x01] -- int tag
                        -- 'intSlotSet' captures tagSlots from cases that
                        -- never produced a 'BranchTarget' (single-arm
                        -- cases). Without this, the verifier sees @int@
                        -- in such slots along paths through the inner
                        -- arm body but the SMT here would say @Object@,
                        -- which is unmergeable with @int@.
                        | i `Set.member` intSlotSet = [0x01]
                        | otherwise = [0x07, hi8 objClsIdx, lo8 objClsIdx] -- binding
                   in concat slotTypes

        encodeDelta :: Int -> [Word8]
        encodeDelta d = [fromIntegral (d `div` 256), fromIntegral (d `mod` 256)]

        encodeU2 :: Int -> [Word8]
        encodeU2 n = [fromIntegral (n `div` 256), fromIntegral (n `mod` 256)]

        encodeU4 :: Int -> [Word8]
        encodeU4 n =
          [ fromIntegral (n `div` 16777216),
            fromIntegral ((n `div` 65536) `mod` 256),
            fromIntegral ((n `div` 256) `mod` 256),
            fromIntegral (n `mod` 256)
          ]

-- ════════════════════════════════════════════════════════════════════════════
-- Name mangling & descriptors
-- ════════════════════════════════════════════════════════════════════════════

mangle :: Text -> Text
mangle t =
  let ok c = Char.isAlphaNum c || c == '_' || c == '\''
      body = T.map (\c -> if ok c then c else '_') t
   in "v_" <> body

-- | @(Ljava/lang/Object;...)Ljava/lang/Object;@ for N args.
objMethodDesc :: Int -> Text
objMethodDesc n =
  "(" <> T.replicate n "Ljava/lang/Object;" <> ")Ljava/lang/Object;"

-- ════════════════════════════════════════════════════════════════════════════
-- Class file serialization
-- ════════════════════════════════════════════════════════════════════════════

buildClassFile :: Pool -> [MInfo] -> B.Builder
buildClassFile st methods =
  let cpList = reverse st.entries
      thisCls = lkup (KClass "AwsumMain")
      superCls = lkup (KClass "java/lang/Object")
      codeUtf8 = lkup (KUtf8 "Code")
   in mconcat
        [ B.word32BE 0xCAFEBABE,
          B.word16BE 0, -- minor version
          B.word16BE 51, -- major version (Java 7)
          B.word16BE st.nextIdx, -- constant_pool_count
          foldMap encodeCPEntry cpList,
          B.word16BE 0x0021, -- ACC_PUBLIC | ACC_SUPER
          B.word16BE thisCls,
          B.word16BE superCls,
          B.word16BE 0, -- interfaces
          B.word16BE 0, -- fields
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
        <> B.word16BE mi.mMaxStack
        <> B.word16BE mi.mMaxLocals
        <> B.word32BE codeLen
        <> B.byteString codeBS
        <> B.word16BE 0 -- exception table
        <> B.word16BE mi.mCodeAttrCount
        <> B.byteString codeAttrsBS
