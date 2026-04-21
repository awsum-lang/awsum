-- | JVM .class file assembler for Awsum 'Core'.
--
-- Generates a single @AwsumMain.class@ file (class version 51.0, Java 7+)
-- containing runtime helpers, user declarations, and a @main(String[])@
-- entry point.
--
-- All values are @java\/lang\/Object@; strings are @java\/lang\/String@;
-- function references are @java\/lang\/invoke\/MethodHandle@; IOUnit is @null@.
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

bcAload :: Int -> [Word8]
bcAload n
  | n <= 3 = [fromIntegral (0x2A + n)]
  | otherwise = [0x19, fromIntegral n]

bcAstore :: Int -> [Word8]
bcAstore n
  | n <= 3 = [fromIntegral (0x4B + n)] -- astore_0..astore_3
  | otherwise = [0x3A, fromIntegral n]

bcIload :: Int -> [Word8]
bcIload n
  | n <= 3 = [fromIntegral (0x1A + n)] -- iload_0..iload_3
  | otherwise = [0x15, fromIntegral n]

bcIstore :: Int -> [Word8]
bcIstore n
  | n <= 3 = [fromIntegral (0x3B + n)] -- istore_0..istore_3
  | otherwise = [0x36, fromIntegral n]

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
    mCodeAttrs :: [Word8]
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
      prims = usedPrims prog
      builtIns = usedBuiltIns prog

  m0 <- mkInit
  -- Runtime helpers are emitted only when referenced in Core, so hello-world
  -- style programs that never call 'showInt32' or 'predInt32' don't pay for them.
  m1s <- if Set.member PrimConcat prims then (: []) <$> mkConcat else pure []
  m2s <- if Set.member PrimPrint prims then (: []) <$> mkPrint else pure []
  m3s <- if Set.member "predInt32" builtIns then (: []) <$> mkPredInt32 else pure []
  userMs <- traverse (mkDecl valNames funNames arities) decls
  mEntry <- mkMain
  pure (m0 : m1s <> m2s <> m3s <> userMs <> [mEntry])

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
      { mFlags = 0x0001,
        mName = ni,
        mDesc = di,
        mCode =
          bcAload 0
            <> bcInvokeSpecial ref
            <> [0xB1], -- return
        mCodeAttrCount = 0,
        mCodeAttrs = []
      }

mkConcat :: AsmM MInfo
mkConcat = do
  ni <- addUtf8 "__concat"
  di <- addUtf8 "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"
  strCls <- addClass "java/lang/String"
  concatRef <- addMRef "java/lang/String" "concat" "(Ljava/lang/String;)Ljava/lang/String;"
  pure
    MInfo
      { mFlags = 0x0009,
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
        mCodeAttrs = []
      }

mkPrint :: AsmM MInfo
mkPrint = do
  ni <- addUtf8 "__print"
  di <- addUtf8 "(Ljava/lang/Object;)Ljava/lang/Object;"
  outRef <- addFRef "java/lang/System" "out" "Ljava/io/PrintStream;"
  printRef <- addMRef "java/io/PrintStream" "print" "(Ljava/lang/Object;)V"
  pure
    MInfo
      { mFlags = 0x0009,
        mName = ni,
        mDesc = di,
        mCode =
          bcGetStatic outRef
            <> bcAload 0
            <> bcInvokeVirtual printRef
            <> [0x01, 0xB0], -- aconst_null, areturn
        mCodeAttrCount = 0,
        mCodeAttrs = []
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
      { mFlags = 0x0009,
        mName = ni,
        mDesc = di,
        mCode = code,
        mCodeAttrCount = 1,
        mCodeAttrs = smtAttr
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
        mCodeAttrs = smtAttr
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

-- | Metadata about branch targets (for StackMapTable generation)
data BranchTarget = BranchTarget
  { btOffset :: Int, -- bytecode offset of the branch target
    btLocals :: Int, -- number of local variables at this point
    btArrSlot :: Int, -- slot number for the array local (if applicable)
    btTagSlot :: Int, -- slot number for the tag local (if applicable)
    btIsJoinPoint :: Bool -- True for join points (gotos), False for if_icmpne targets
  }
  deriving stock (Show, Eq)

-- | Result of expression compilation with branch metadata
data CodeWithMeta = CodeWithMeta
  { cwCode :: [Word8],
    cwBranchTargets :: [BranchTarget]
  }

mkDecl :: Set Text -> Set Text -> Map Text Int -> CDecl -> AsmM MInfo
mkDecl valDefs funDefs arities = \case
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
    ni <- addUtf8 (mangle nm)
    di <- addUtf8 (objMethodDesc (length args))
    codeMeta <- emitExpr ctx body
    (smtCount, smtBytes) <- caseSMT ctx codeMeta.cwBranchTargets
    pure MInfo {mFlags = 0x0009, mName = ni, mDesc = di, mCode = codeMeta.cwCode <> [0xB0], mCodeAttrCount = smtCount, mCodeAttrs = smtBytes}
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
    ni <- addUtf8 (mangle nm)
    di <- addUtf8 "()Ljava/lang/Object;"
    codeMeta <- emitExpr ctx rhs
    (smtCount, smtBytes) <- caseSMT ctx codeMeta.cwBranchTargets
    pure MInfo {mFlags = 0x0009, mName = ni, mDesc = di, mCode = codeMeta.cwCode <> [0xB0], mCodeAttrCount = smtCount, mCodeAttrs = smtBytes}

-- ════════════════════════════════════════════════════════════════════════════
-- Expression codegen (bytecode bytes)
-- ════════════════════════════════════════════════════════════════════════════

-- | Emit bytecode that leaves the expression result on top of the operand stack.
--   Returns bytecode and metadata about branch targets for StackMapTable generation.
emitExpr :: ECtx -> CExpr -> AsmM CodeWithMeta
emitExpr ctx = \case
  CString s -> do
    idx <- addStr s
    pure $ CodeWithMeta (bcLdc idx) []
  CVar n
    | Just slot <- Map.lookup n ctx.cLocals ->
        pure $ CodeWithMeta (bcAload slot) []
    | Just slot <- Map.lookup n ctx.cParams ->
        pure $ CodeWithMeta (bcAload slot) []
    | n `Set.member` ctx.cValDefs -> do
        ref <- addMRef "AwsumMain" (mangle n) "()Ljava/lang/Object;"
        pure $ CodeWithMeta (bcInvokeStatic ref) []
    | n `Set.member` ctx.cFunDefs -> do
        let arity = fromMaybe 0 (Map.lookup n ctx.cArities)
        hi <- addMHandle 6 "AwsumMain" (mangle n) (objMethodDesc arity)
        pure $ CodeWithMeta (bcLdc hi) []
    | otherwise ->
        pure $ CodeWithMeta [0x01] [] -- aconst_null
  CPrim _ ->
    pure $ CodeWithMeta [0x01] [] -- aconst_null
  CBuiltIn _ ->
    pure $ CodeWithMeta [0x01] [] -- aconst_null; dispatched from CCall
  CIntLit n it -> do
    -- Both Int32 and UInt8 are represented as java.lang.Integer on the JVM.
    -- UInt8 uses Integer (not java.lang.Byte) because Java byte is signed
    -- 8-bit — storing an Integer lets the value space stay 0..255 without
    -- surprises when we later add arithmetic.
    let n32 = fromInteger n :: Int32
    pushCode <- bcLoadInt32 n32
    valueOfRef <- addMRef "java/lang/Integer" "valueOf" "(I)Ljava/lang/Integer;"
    let _ = it -- reserved for future per-type boxing (e.g. Long for Int64)
    pure $ CodeWithMeta (pushCode <> bcInvokeStatic valueOfRef) []
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
      pure (CodeWithMeta ([0x59] <> bcIconst i <> fldMeta.cwCode <> [0x53]) fldMeta.cwBranchTargets)
    let allTargets = concatMap cwBranchTargets fieldMetas
        allCode = allocCode <> storeTag <> concatMap cwCode fieldMetas
    pure $ CodeWithMeta allCode allTargets
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
          ctx' = ctx {cLocals = foldl' (\m (v, s) -> Map.insert v s m) ctx.cLocals bindings, cNextLocal = bindSlotStart + length vars}
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
      pure ((CodeWithMeta (bindCode <> paddingCode <> bodyMeta.cwCode) bodyMeta.cwBranchTargets, bindCodeLen), armLocals)
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
    pure $ CodeWithMeta finalCode allTargets
  CCall f xs ->
    case f of
      CPrim PrimConcat | [a, b] <- xs -> do
        aMeta <- emitExpr ctx a
        bMeta <- emitExpr ctx b
        ref <- addMRef "AwsumMain" "__concat" "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"
        pure
          $ CodeWithMeta
            (aMeta.cwCode <> bMeta.cwCode <> bcInvokeStatic ref)
            (aMeta.cwBranchTargets ++ bMeta.cwBranchTargets)
      CPrim PrimPrint | [x] <- xs -> do
        xMeta <- emitExpr ctx x
        ref <- addMRef "AwsumMain" "__print" "(Ljava/lang/Object;)Ljava/lang/Object;"
        pure
          $ CodeWithMeta
            (xMeta.cwCode <> bcInvokeStatic ref)
            xMeta.cwBranchTargets
      CPrim (PrimShowInt _) | [x] <- xs -> do
        -- The value on the stack is a java.lang.Integer (how CIntLit emits
        -- both Int32 and UInt8). Cast to Integer and call its toString() —
        -- decimal representation with no padding or signs beyond '-', matching
        -- snprintf("%d") on LLVM and tostring() on Lua.
        xMeta <- emitExpr ctx x
        intCls <- addClass "java/lang/Integer"
        toStr <- addMRef "java/lang/Integer" "toString" "()Ljava/lang/String;"
        pure
          $ CodeWithMeta
            (xMeta.cwCode <> bcCheckCast intCls <> bcInvokeVirtual toStr)
            xMeta.cwBranchTargets
      CBuiltIn name
        | name == "showInt32" || name == "showUInt8",
          [x] <- xs -> do
            xMeta <- emitExpr ctx x
            intCls <- addClass "java/lang/Integer"
            toStr <- addMRef "java/lang/Integer" "toString" "()Ljava/lang/String;"
            pure
              $ CodeWithMeta
                (xMeta.cwCode <> bcCheckCast intCls <> bcInvokeVirtual toStr)
                xMeta.cwBranchTargets
      CBuiltIn "predInt32" | [x] <- xs -> do
        xMeta <- emitExpr ctx x
        ref <- addMRef "AwsumMain" "__predInt32" "(Ljava/lang/Object;)Ljava/lang/Object;"
        pure
          $ CodeWithMeta
            (xMeta.cwCode <> bcInvokeStatic ref)
            xMeta.cwBranchTargets
      CBuiltIn n ->
        error ("JVM codegen: unknown builtin '" <> n <> "' reached CCall (typecheck should have rejected it)")
      CVar n | n `Set.member` ctx.cFunDefs -> do
        -- Direct call to known function
        argMetas <- traverse (emitExpr ctx) xs
        ref <- addMRef "AwsumMain" (mangle n) (objMethodDesc (length xs))
        let allCode = concatMap cwCode argMetas <> bcInvokeStatic ref
            allTargets = concatMap cwBranchTargets argMetas
        pure $ CodeWithMeta allCode allTargets
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
        pure $ CodeWithMeta allCode allTargets

-- ════════════════════════════════════════════════════════════════════════════
-- StackMapTable for CCase branches
-- ════════════════════════════════════════════════════════════════════════════

-- | Compute StackMapTable attribute from collected branch targets.
caseSMT :: ECtx -> [BranchTarget] -> AsmM (Word16, [Word8])
caseSMT _ctx targets
  | null targets = pure (0, [])
  | otherwise = do
      smtNameIdx <- addUtf8 "StackMapTable"
      objClsIdx <- addClass "java/lang/Object"
      arrClsIdx <- addClass "[Ljava/lang/Object;"
      let sorted = sortOn btOffset targets
          -- Deduplicate by offset, keeping the one with max btLocals
          deduped = Map.elems $ Map.fromListWith (\a b -> if a.btLocals >= b.btLocals then a else b) [(t.btOffset, t) | t <- sorted]
          dedupedSorted = sortOn btOffset deduped
      pure (1, buildSMTAttr smtNameIdx arrClsIdx objClsIdx dedupedSorted)
  where
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
              isLastFrame = null rest
              currentLocals = bt.btLocals
              allArrTagPairs = [(t.btArrSlot, t.btTagSlot) | t <- allTgts]
              localsTypes = buildLocalsTypes allArrTagPairs bt
              -- Use full_frame for everything except simple cases
              frame
                | bt.btIsJoinPoint || isLastFrame =
                    -- Join point or last frame: has return value on stack
                    [255]
                      <> encodeDelta delta
                      <> encodeU2 currentLocals
                      <> localsTypes
                      <> encodeU2 1
                      <> [0x07, hi8 objClsIdx, lo8 objClsIdx] -- 1 Object on stack
                | otherwise =
                    -- if_icmpne target: empty stack
                    [255]
                      <> encodeDelta delta
                      <> encodeU2 currentLocals
                      <> localsTypes
                      <> encodeU2 0 -- empty stack
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
        <> B.word16BE 256 -- max_stack
        <> B.word16BE 256 -- max_locals
        <> B.word32BE codeLen
        <> B.byteString codeBS
        <> B.word16BE 0 -- exception table
        <> B.word16BE mi.mCodeAttrCount
        <> B.byteString codeAttrsBS
