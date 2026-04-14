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
doAssemble (CoreProgram decls) = do
  -- Ensure required CP entries exist
  void $ addClass "AwsumMain"
  void $ addClass "java/lang/Object"
  void $ addUtf8 "Code"

  let valNames = Set.fromList [n | CValDef n _ <- decls]
      funNames = Set.fromList [n | CFunDef n _ _ <- decls]
      arities = Map.fromList [(n, length as) | CFunDef n as _ <- decls]

  m0 <- mkInit
  m1 <- mkConcat
  m2 <- mkPrint
  userMs <- traverse (mkDecl valNames funNames arities) decls
  mEntry <- mkMain
  pure (m0 : m1 : m2 : userMs <> [mEntry])

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
    code <- emitExpr ctx body
    (smtCount, smtBytes) <- caseSMT ctx body
    pure MInfo {mFlags = 0x0009, mName = ni, mDesc = di, mCode = code <> [0xB0], mCodeAttrCount = smtCount, mCodeAttrs = smtBytes}
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
    code <- emitExpr ctx rhs
    (smtCount, smtBytes) <- caseSMT ctx rhs
    pure MInfo {mFlags = 0x0009, mName = ni, mDesc = di, mCode = code <> [0xB0], mCodeAttrCount = smtCount, mCodeAttrs = smtBytes}

-- ════════════════════════════════════════════════════════════════════════════
-- Expression codegen (bytecode bytes)
-- ════════════════════════════════════════════════════════════════════════════

-- | Emit bytecode that leaves the expression result on top of the operand stack.
emitExpr :: ECtx -> CExpr -> AsmM [Word8]
emitExpr ctx = \case
  CString s -> do
    idx <- addStr s
    pure (bcLdc idx)
  CVar n
    | Just slot <- Map.lookup n ctx.cLocals ->
        pure (bcAload slot)
    | Just slot <- Map.lookup n ctx.cParams ->
        pure (bcAload slot)
    | n `Set.member` ctx.cValDefs -> do
        ref <- addMRef "AwsumMain" (mangle n) "()Ljava/lang/Object;"
        pure (bcInvokeStatic ref)
    | n `Set.member` ctx.cFunDefs -> do
        let arity = fromMaybe 0 (Map.lookup n ctx.cArities)
        hi <- addMHandle 6 "AwsumMain" (mangle n) (objMethodDesc arity)
        pure (bcLdc hi)
    | otherwise ->
        pure [0x01] -- aconst_null
  CPrim _ ->
    pure [0x01] -- aconst_null
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
    fieldCodes <- forM (zip fields [1 :: Int ..]) $ \(fld, i) -> do
      fldCode <- emitExpr ctx fld
      pure ([0x59] <> bcIconst i <> fldCode <> [0x53]) -- dup, iconst i, <field>, aastore
    pure (allocCode <> storeTag <> concat fieldCodes)
  CCase scrut alts -> do
    intCls <- addClass "java/lang/Integer"
    intValRef <- addMRef "java/lang/Integer" "intValue" "()I"
    arrCls <- addClass "[Ljava/lang/Object;"
    scrutCode <- emitExpr ctx scrut
    let sorted = sortWith (\(t, _, _) -> t) alts
        -- Local slots: arrSlot stores the Object[], tagSlot stores the int tag
        arrSlot = ctx.cNextLocal
        tagSlot = arrSlot + 1
        bindSlotStart = tagSlot + 1
        loadArr = bcAload arrSlot
    -- Emit arm bodies with bound variables
    armCodes <- forM sorted $ \(_, vars, body) -> do
      let bindings = zip vars [bindSlotStart ..]
          ctx' = ctx {cLocals = foldl' (\m (v, s) -> Map.insert v s m) ctx.cLocals bindings}
          bindCode =
            concatMap
              ( \((_, slot), i) ->
                  loadArr <> bcIconst (i :: Int) <> [0x32] <> bcAstore slot
              )
              (zip bindings [1 :: Int ..])
      bodyCode <- emitExpr ctx' body
      pure (bindCode <> bodyCode)
    let tags = [t | (t, _, _) <- sorted]
        loadTag = bcIload tagSlot
        buildChain [] = [0x01] -- aconst_null fallback
        buildChain [(_, armCode)] = armCode
        buildChain ((tag', armCode) : rest) =
          let restCode = buildChain rest
              bodyLen = length armCode
              gotoLen :: Int
              gotoLen = 3
              skipOffset = 3 + bodyLen + gotoLen
              restLen = length restCode
              gotoOffset = restLen + gotoLen
              cmpCode = loadTag <> bcIconst tag' <> [0xA0, fromIntegral (skipOffset `div` 256), fromIntegral (skipOffset `mod` 256)]
              gotoCode = [0xA7, fromIntegral (gotoOffset `div` 256), fromIntegral (gotoOffset `mod` 256)]
           in cmpCode <> armCode <> gotoCode <> restCode
        chainCode = buildChain (zip tags armCodes)
        extractAndStore =
          bcCheckCast arrCls -- cast to Object[] for verifier
            <> bcAstore arrSlot
            <> loadArr
            <> bcIconst 0
            <> [0x32] -- aaload
            <> bcCheckCast intCls
            <> bcInvokeVirtual intValRef
            <> bcIstore tagSlot
    pure (scrutCode <> extractAndStore <> chainCode)
  CCall f xs ->
    case f of
      CPrim PrimConcat | [a, b] <- xs -> do
        ca <- emitExpr ctx a
        cb <- emitExpr ctx b
        ref <- addMRef "AwsumMain" "__concat" "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"
        pure (ca <> cb <> bcInvokeStatic ref)
      CPrim PrimPrint | [x] <- xs -> do
        cx <- emitExpr ctx x
        ref <- addMRef "AwsumMain" "__print" "(Ljava/lang/Object;)Ljava/lang/Object;"
        pure (cx <> bcInvokeStatic ref)
      CVar n | n `Set.member` ctx.cFunDefs -> do
        -- Direct call to known function
        argCodes <- traverse (emitExpr ctx) xs
        ref <- addMRef "AwsumMain" (mangle n) (objMethodDesc (length xs))
        pure (concat argCodes <> bcInvokeStatic ref)
      _ -> do
        -- Indirect call via MethodHandle
        -- Stack layout: MethodHandle arg1 arg2 ...
        fCode <- emitExpr ctx f
        mhCls <- addClass "java/lang/invoke/MethodHandle"
        argCodes <- traverse (emitExpr ctx) xs
        let invokeDesc = objMethodDesc (length xs)
        ref <- addMRef "java/lang/invoke/MethodHandle" "invoke" invokeDesc
        pure (fCode <> bcCheckCast mhCls <> concat argCodes <> bcInvokeVirtual ref)

-- ════════════════════════════════════════════════════════════════════════════
-- StackMapTable for CCase branches
-- ════════════════════════════════════════════════════════════════════════════

-- | Compute StackMapTable attribute for methods with top-level CCase.
-- Must mirror the bytecode layout from emitExpr CCase exactly:
--   preamble: scrutCode + astore(arrSlot) + aload(arrSlot) + iconst_0 + aaload
--             + checkcast + invokevirtual + istore(tagSlot)
--   chain:    [iload(tagSlot) + iconst(tag) + if_icmpne + armCode + goto]* + lastArmCode
caseSMT :: ECtx -> CExpr -> AsmM (Word16, [Word8])
caseSMT ctx (CCase scrut alts) = do
  let sorted = sortWith (\(t, _, _) -> t) alts
      nAlts = length sorted
  if nAlts <= 1
    then pure (0, [])
    else do
      smtNameIdx <- addUtf8 "StackMapTable"
      objClsIdx <- addClass "java/lang/Object"
      arrClsIdx <- addClass "[Ljava/lang/Object;"
      scrutCode <- emitExpr ctx scrut
      let arrSlot = ctx.cNextLocal
          tagSlot = arrSlot + 1
          bindSlotStart = tagSlot + 1
          loadArr = bcAload arrSlot
      -- Compute arm codes INCLUDING bind code (must match emitExpr CCase)
      armCodes <- forM sorted $ \(_, vars, body) -> do
        let bindings = zip vars [bindSlotStart ..]
            ctx' = ctx {cLocals = foldl' (\m (v, s) -> Map.insert v s m) ctx.cLocals bindings}
            bindCode =
              concatMap
                ( \((_, slot), i) ->
                    loadArr <> bcIconst (i :: Int) <> [0x32] <> bcAstore slot
                )
                (zip bindings [1 :: Int ..])
        bodyCode <- emitExpr ctx' body
        pure (bindCode <> bodyCode)
      let tags = [t | (t, _, _) <- sorted]
          -- Preamble: scrutCode + checkcast(arrCls) + astore + aload + iconst_0 + aaload + checkcast(intCls) + invokevirtual + istore
          astoreLen = length (bcAstore arrSlot)
          aloadLen = length (bcAload arrSlot)
          istoreLen = length (bcIstore tagSlot)
          loadLen = length (bcIload tagSlot)
          preambleLen = length scrutCode + 3 + astoreLen + aloadLen + 1 + 1 + 3 + 3 + istoreLen
          armLens = map length armCodes
          iconLens = map (length . bcIconst) tags
          computeTargets pos [] = ([], pos)
          computeTargets pos ((il, al) : rest) =
            let target = pos + loadLen + il + 3 + al + 3
                (ts, final) = computeTargets target rest
             in (target : ts, final)
          initInfo = zip iconLens (take (nAlts - 1) armLens)
          (ifTargets, lastArmStart) = computeTargets preambleLen initInfo
          lastArmLen = case drop (nAlts - 1) armLens of
            (len : _) -> len
            _ -> 0
          joinPoint = lastArmStart + lastArmLen
          targets = ifTargets ++ [joinPoint]
      pure (1, buildSMTAttr smtNameIdx arrClsIdx objClsIdx targets)
caseSMT _ _ = pure (0, [])

-- | Build StackMapTable attribute bytes for CCase branch targets.
-- Locals at branch targets: [Object^N, Object[](arr), int(tag)] where N = method params.
-- First frame uses append_frame (adding Object[] + int locals), middle frames use same_frame,
-- last frame (join point) uses same_locals_1_stack_item_frame with Object on stack.
buildSMTAttr :: Word16 -> Word16 -> Word16 -> [Int] -> [Word8]
buildSMTAttr smtNameIdx arrClsIdx objClsIdx targets =
  let nEntries = length targets
      frameBytes = buildFrames (-1) targets
      attrLen = 2 + length frameBytes
   in [hi8 smtNameIdx, lo8 smtNameIdx]
        <> encodeU4 attrLen
        <> [fromIntegral (nEntries `div` 256), fromIntegral (nEntries `mod` 256)]
        <> frameBytes
  where
    buildFrames :: Int -> [Int] -> [Word8]
    buildFrames _ [] = []
    buildFrames prev (t : rest) =
      let delta = t - prev - 1
          frame
            | prev == -1 =
                -- append_frame tag 253: adds 2 locals (Object[] for arr, int for tag)
                [253, fromIntegral (delta `div` 256), fromIntegral (delta `mod` 256), 7, hi8 arrClsIdx, lo8 arrClsIdx, 1]
            | null rest =
                -- same_locals_1_stack_item_frame: Object on stack (join point)
                if delta <= 63
                  then [fromIntegral (64 + delta), 7, hi8 objClsIdx, lo8 objClsIdx]
                  else [247, fromIntegral (delta `div` 256), fromIntegral (delta `mod` 256), 7, hi8 objClsIdx, lo8 objClsIdx]
            | otherwise =
                -- same_frame: empty stack, same locals (if_icmpne target)
                if delta <= 63
                  then [fromIntegral delta]
                  else [251, fromIntegral (delta `div` 256), fromIntegral (delta `mod` 256)]
       in frame <> buildFrames t rest
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
