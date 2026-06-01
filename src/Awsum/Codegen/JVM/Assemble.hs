-- | JVM .class file assembler for Awsum 'Core'.
--
-- Generates a single @AwsumMain.class@ file (class version 55.0, Java 11+)
-- containing runtime helpers, user declarations, and a @main(String[])@
-- entry point.
--
-- All values are @java\/lang\/Object@; strings are @java\/lang\/String@;
-- function references are @java\/lang\/invoke\/MethodHandle@; @IO Unit@ is @null@.
module Awsum.Codegen.JVM.Assemble (assembleJVM, JvmLimitExceeded (..), renderJvmLimitExceeded, userJvmMethods, JvmModule (..), jvmModule, jvmModuleMethods) where

import Awsum.Codegen.JVM.Instr (ClassRef (..), FieldRef (..), Frame (..), JvmInstr (..), JvmMethod (..), LabelId (..), MethodRef (..), VType (..), addInt32Spec, addUInt32Spec, addUInt8Spec, concatSpec, entryArgEitherSpec, eqSpec, eqStringSpec, getArgsSpec, lengthCodePointsSpec, lengthUtf16CodeUnitsSpec, lengthUtf8BytesSpec, mainSpec, mulInt32Spec, mulUInt32Spec, mulUInt8Spec, negInt32Spec, parseInt32Spec, parseUInt32Spec, parseUInt8Spec, predInt32Spec, predUInt32Spec, predUInt8Spec, printSpec, showUInt32Spec, splitOnFirstSpec, stdinReadAllSpec, subInt32Spec, subUInt32Spec, subUInt8Spec, succInt32Spec, succUInt32Spec, succUInt8Spec)
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

-- | A method whose assembled bytecode crosses 'jvmMaxMethodCodeBytes', with
--   its name and actual byte size for the diagnostic.
data JvmLimitExceeded = JvmMethodTooLarge
  { jleMethod :: Text,
    jleBytes :: Int
  }
  deriving stock (Eq, Show)

-- | Render a 'JvmLimitExceeded' as the build-time error the user sees: the
--   method, its size against the 65535-byte ceiling, and — only for the
--   compiler-synthesised @$scc$@ \/ @$cps$@ functions no user wrote — one line
--   on where the method came from. Long synthesised names are abbreviated.
renderJvmLimitExceeded :: JvmLimitExceeded -> Text
renderJvmLimitExceeded (JvmMethodTooLarge name n) =
  "JVM target — "
    <> subject
    <> " compiles to "
    <> show n
    <> " bytes, over the JVM's hard limit of 65535 bytes per method."
    <> provenance
    <> " This program can't be built for the JVM target."
  where
    synthetic = any (`T.isPrefixOf` name) ["$scc$", "$cps$", "$apply$"]
    subject
      | synthetic = "synthetic method `" <> abbreviate name <> "`"
      | otherwise = "function `" <> abbreviate name <> "`"
    provenance
      | "$scc$" `T.isPrefixOf` name =
          " (`$scc$…` is one function the compiler fuses from a mutual-recursion group to keep it stack-safe.)"
      | "$cps$" `T.isPrefixOf` name || "$apply$" `T.isPrefixOf` name =
          " (`$cps$…` is the continuation-passing form the compiler synthesises to make non-tail recursion stack-safe.)"
      | otherwise = ""
    abbreviate t
      | T.length t <= 48 = t
      | otherwise = T.take 47 t <> "…"

-- | Produce a complete .class file as a strict ByteString, unless some method
--   crosses the JVM's per-method bytecode ceiling ('jvmMaxMethodCodeBytes') —
--   in which case the program is refused for this target ('JvmLimitExceeded').
assembleJVM :: PreludeTags -> CoreProgram -> Either JvmLimitExceeded BS.ByteString
assembleJVM ptags prog =
  let (methods, finalSt) = runState (doAssemble prog) (emptyPool ptags)
      argvFieldNameIdx = fromMaybe (error "assembleJVM: missing __argv name") (Map.lookup (KUtf8 "__argv") finalSt.cache)
      argvFieldDescIdx = fromMaybe (error "assembleJVM: missing __argv descriptor") (Map.lookup (KUtf8 "[Ljava/lang/String;") finalSt.cache)
   in case finalSt.oversizedMethods of
        ((nm, n) : _) -> Left (JvmMethodTooLarge nm n)
        [] -> Right (toStrict (B.toLazyByteString (buildClassFile finalSt argvFieldNameIdx argvFieldDescIdx methods)))

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
    labelCtr :: Int,
    -- | Methods whose assembled @Code@ crossed 'jvmMaxMethodCodeBytes',
    -- in encounter order, as @(name, byteSize)@. Recorded by
    -- 'assembleMethod' at the one point the final bytes and the method
    -- name are both in hand; 'assembleJVM' turns a non-empty list into a
    -- 'JvmLimitExceeded' rather than emitting a class the JVM would reject
    -- at load.
    oversizedMethods :: [(Text, Int)]
  }

emptyPool :: PreludeTags -> Pool
emptyPool ptags = Pool {entries = [], nextIdx = 1, cache = Map.empty, poolTags = ptags, labelCtr = 0, oversizedMethods = []}

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

-- | Assemble a 'JvmMethod' to its 'MInfo'. @max_stack@ / @max_locals@ come
--   from the shared spec — the honest verifier limits, the same values the
--   text declares.
assembleMethod :: JvmMethod -> AsmM MInfo
assembleMethod m = do
  ni <- addUtf8 (jmName m)
  di <- addUtf8 (jmDesc m)
  (code, attrCount, attrs) <- assembleBody (entryLocalsFromDesc (jmDesc m)) (jmBody m)
  -- The one point where this method's final bytes and its name coexist:
  -- record an over-limit body for 'assembleJVM' to refuse (JVM Spec §4.7.3
  -- caps 'code_length' at 65535).
  when (length code > jvmMaxMethodCodeBytes)
    $ modify' (\st -> st {oversizedMethods = st.oversizedMethods <> [(jmName m, length code)]})
  pure
    MInfo
      { mFlags = if jmPublic m then 0x0009 else 0x0008,
        mName = ni,
        mDesc = di,
        mCode = code,
        mCodeAttrCount = attrCount,
        mCodeAttrs = attrs,
        mMaxStack = fromIntegral (jmMaxStack m),
        mMaxLocals = fromIntegral (jmMaxLocals m)
      }

-- | The verifier locals at method entry, derived from the descriptor — the
--   baseline the first StackMapTable frame diffs against. Every migrated
--   helper's parameters are @java/lang/Object@, so this is one 'VObject' per
--   param; extend when a migrated method takes a non-Object parameter.
entryLocalsFromDesc :: Text -> [VType]
entryLocalsFromDesc desc =
  let paramSec = T.takeWhile (/= ')') (T.dropWhile (/= '(') desc)
   in replicate (T.count "Ljava/lang/Object;" paramSec) (VObject (ClassRef "java/lang/Object"))

-- | Lower a method body to @(code, smtAttrCount, smtAttrBytes)@ in a single
--   pass plus a backpatch: branches emit a 3-byte placeholder whose offset is
--   filled once every label's bci is known, and labels carrying a 'Frame'
--   become the StackMapTable. This is the one place branch offsets are
--   computed — every helper and the user-code emitter ('emitExprI') route
--   their branches and frames through it.
assembleBody :: [VType] -> [JvmInstr] -> AsmM ([Word8], Word16, [Word8])
assembleBody entryLocals body = do
  (chunksRev, _bci, labels, patchesRev, framesRev) <-
    foldlM stepBody ([], 0, Map.empty, [], []) body
  let code0 = concat (reverse chunksRev)
      resolved =
        [ (branchBci + 1, fromIntegral (labels Map.! tgt - branchBci) :: Word16)
        | (branchBci, tgt) <- reverse patchesRev
        ]
      code = applyOffsetPatches code0 resolved
      -- Deduplicate frames that resolved to the same bci, keeping the one with
      -- the NARROWEST locals. Nested cases emit their own join 'Label' which,
      -- when the inner case is the last expression of an outer arm, lands on
      -- the same byte as the outer join; the verifier needs exactly one frame
      -- there describing the intersection of live locals across every incoming
      -- edge (the outermost, smaller frame). 'Map.fromListWith' over the bci
      -- collapses them; 'Map.elems' returns them in ascending-bci order, which
      -- is also what 'buildStackMapTable' needs.
      frames =
        Map.elems
          $ Map.fromListWith
            (\a b -> if length (frLocals (snd a)) <= length (frLocals (snd b)) then a else b)
            [(bci, (bci, f)) | (bci, f) <- reverse framesRev]
  if null frames
    then pure (code, 0, [])
    else do
      smtNameIdx <- addUtf8 "StackMapTable"
      classMap <- resolveFrameClasses frames
      pure (code, 1, buildStackMapTable classMap entryLocals smtNameIdx frames)
  where
    stepBody (chunks, bci, labels, patches, frames) = \case
      Label l mframe ->
        pure (chunks, bci, Map.insert l bci labels, patches, maybe frames (\f -> (bci, f) : frames) mframe)
      Ifeq l -> branch 0x99 l chunks bci labels patches frames
      Ifne l -> branch 0x9A l chunks bci labels patches frames
      Iflt l -> branch 0x9B l chunks bci labels patches frames
      Ifle l -> branch 0x9E l chunks bci labels patches frames
      Ifgt l -> branch 0x9D l chunks bci labels patches frames
      IfICmpEq l -> branch 0x9F l chunks bci labels patches frames
      IfICmpNe l -> branch 0xA0 l chunks bci labels patches frames
      IfICmpLe l -> branch 0xA4 l chunks bci labels patches frames
      IfICmpLt l -> branch 0xA1 l chunks bci labels patches frames
      IfICmpGt l -> branch 0xA3 l chunks bci labels patches frames
      IfICmpGe l -> branch 0xA2 l chunks bci labels patches frames
      Goto l -> branch 0xA7 l chunks bci labels patches frames
      instr -> do
        bs <- assembleInstr instr
        pure (bs : chunks, bci + length bs, labels, patches, frames)
    branch op l chunks bci labels patches frames =
      pure ([op, 0, 0] : chunks, bci + 3, labels, (bci, l) : patches, frames)

-- | Replace the two offset bytes at each @(hiPos, offset)@ in a code stream.
applyOffsetPatches :: [Word8] -> [(Int, Word16)] -> [Word8]
applyOffsetPatches code patches =
  let pm = Map.fromList (concatMap (\(p, off) -> [(p, hi8 off), (p + 1, lo8 off)]) patches)
   in zipWith (\i b -> Map.findWithDefault b i pm) [0 ..] code

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
              [ gate (Set.member "internalGetArgs" builtIns || Set.member "internalStdinReadAllAsUtf16" builtIns) [entryArgEitherSpec (ptRight ptags, ptLeft ptags, ptStringTooLong ptags, ptUnpairedUtf16Surrogate ptags, stringTooLongRowTag, unpairedSurrogateRowTag)],
                gate (Set.member "internalGetArgs" builtIns) [getArgsSpec (ptNil ptags, ptCons ptags, ptRight ptags)],
                gate (Set.member "internalStdinReadAllAsUtf16" builtIns) [stdinReadAllSpec],
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
    -- | Method-global slot-type info for the unified 'emitExprI' frame
    -- builder: which slot indices ever serve as a 'CCase' @arrSlot@
    -- (@Object[]@) and which as a @tagSlot@ (@int@). Computed once per
    -- method by 'buildSlotKinds' and constant across the whole body, so
    -- each 'Label''s absolute 'Frame' can be typed inline at emit time, with
    -- no post-pass: a slot is @Object[]@ if it is /ever/ an arr slot in the
    -- method, @int@ if a tag slot, else @Object@ (the global-union rule).
    cArrSlots :: Set Int,
    cTagSlots :: Set Int
  }

-- | Number of *additional* local slots a body needs beyond its
-- parameters — sums the additive nesting of 'CCase' (1 array slot +
-- max-binding count per level) and propagates through subexpressions.
-- Mirrors the slot allocation in 'emitExprI' / 'emitTailBinI'. Used to
-- fill the @max_locals@ field of the Code attribute (JVM Spec §4.7.3);
-- hardcoding 256 there caused @ClassFormatError: bad type array size@
-- on programs whose StackMapTable referenced a slot index ≥ 256.
exprMaxLocals :: CExpr -> Int
exprMaxLocals = \case
  -- 'CCase' burns 2 slots per level (arrSlot for the @Object[]@,
  -- tagSlot for the unboxed @int@ tag) plus @maxBindings@ binding
  -- slots reserved across every arm — see 'emitExprI' / 'emitTailCase'
  -- comments for why bindings are sized to the widest arm.
  CCase _ alts ->
    let thisLevel = 2 + foldl' max 0 [length vs | (_, vs, _) <- alts]
        armMax = foldl' max 0 [exprMaxLocals b | (_, _, b) <- alts]
     in thisLevel + armMax
  CRowCase _ alts ->
    -- Same shape as a 'CCase' with one binder per arm (the row's
    -- value), so two slots (scrutinee + unboxed tag) plus the binding.
    let thisLevel = 3 :: Int
        armMax = foldl' max 0 [exprMaxLocals b | (_, _, b) <- alts]
     in thisLevel + armMax
  CRow _ v -> exprMaxLocals v
  CCall f xs ->
    -- A 'CCase' nested in an argument position would push StackMapTable
    -- frames whose declared (empty) stack disagrees with the verifier-
    -- derived stack (which still holds prior args). 'emitExprI' / 'CCall'
    -- routes each argument through a fresh local when this happens —
    -- 'length xs' slots — plus one more for the function value on the
    -- indirect-call path. Conservative: charge @length xs + 1@ whenever
    -- either side has a case, since 'exprMaxLocals' has no context to
    -- distinguish the direct and indirect paths.
    let save =
          if exprContainsCase f || any exprContainsCase xs
            then length xs + 1
            else 0
     in save + foldl' max 0 (exprMaxLocals f : map exprMaxLocals xs)
  CCon _ fields -> foldl' max 0 (map exprMaxLocals fields)
  CLoop b -> exprMaxLocals b
  CContinue xs -> foldl' max 0 (map exprMaxLocals xs)
  CDrop _ _ b -> exprMaxLocals b
  CReuse _ _ fs -> foldl' max 0 (map exprMaxLocals fs)
  _ -> 0

-- | Does the expression contain a 'CCase' (or 'CRowCase') anywhere?
-- 'CCall' (and any other multi-sub-expr emitter that leaves prior
-- values on the operand stack) needs to know this so it can route
-- each argument through a fresh local instead of leaving prior args
-- exposed when a nested case's StackMapTable kicks in.
exprContainsCase :: CExpr -> Bool
exprContainsCase = \case
  CCase {} -> True
  CRowCase {} -> True
  CRow _ v -> exprContainsCase v
  CCall f xs -> exprContainsCase f || any exprContainsCase xs
  CCon _ fs -> any exprContainsCase fs
  CDrop _ _ b -> exprContainsCase b
  CReuse _ _ fs -> any exprContainsCase fs
  CLoop b -> exprContainsCase b
  CContinue xs -> any exprContainsCase xs
  _ -> False

-- | Gate for a non-tail 'declJvmMethod' clause: which expressions 'emitExprI'
--   accepts as a method body / value. A /multi-arm/ 'CCase' / 'CRowCase' is
--   accepted in any /stack-empty/ position — the body, a case-arm body, a case
--   scrutinee, a 'CDrop' body — and in a 'CCall' argument (handled by
--   'emitArgsViaLocalsI'); a /single-arm/ case (frame-free) is accepted
--   anywhere via 'noMultiArmCase', including a 'CCon' / 'CReuse' field or a
--   'CRow' value (non-empty-stack positions a multi-arm case cannot occupy).
--   'CLoop' is the tail form, gated separately by 'emitTailIOk'. The cases this
--   returns 'False' for never arise — the lowering keeps multi-arm cases out of
--   non-empty-stack positions (verified: a strict probe found zero
--   fall-through to 'declJvmMethod''s error guards across the whole corpus).
emitIOk :: CExpr -> Bool
emitIOk = \case
  CCase s alts -> not (null alts) && emitIOk s && all (\(_, _, b) -> emitIOk b) alts
  CRowCase s alts -> not (null alts) && emitIOk s && all (\(_, _, b) -> emitIOk b) alts
  -- Cell fields / row values are emitted at a non-empty operand stack, so a
  -- multi-arm case (whose frames declare an empty stack) cannot appear there —
  -- but a single-arm case carries no frames, so it is fine. 'noMultiArmCase'
  -- allows single-arm/branch-free, excludes multi-arm.
  CRow _ v -> noMultiArmCase v
  CCon _ fs -> all noMultiArmCase fs
  CReuse _ _ fs -> all noMultiArmCase fs
  -- Cases in arguments are handled (save-to-locals via 'emitArgsViaLocalsI');
  -- 'f' is a builtin or known function (the indirect MethodHandle path is dead
  -- after LowerClosures), so it carries no case.
  CCall f xs -> not (exprContainsCase f) && all emitIOk xs
  CDrop _ _ b -> emitIOk b
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
  CRow _ v -> noMultiArmCase v
  CCall f xs -> noMultiArmCase f && all noMultiArmCase xs
  CCon _ fs -> all noMultiArmCase fs
  CReuse _ _ fs -> all noMultiArmCase fs
  CDrop _ _ b -> noMultiArmCase b
  CLoop b -> noMultiArmCase b
  CContinue xs -> all noMultiArmCase xs
  _ -> True

-- | Gate for the TCO 'declJvmMethod' clause (@CFunDef _ _ (CLoop body)@):
--   which loop bodies 'emitTailBinI' accepts. Tail position recurses into arm
--   bodies (each self-terminating); 'CContinue' args allow only single-arm
--   ('noMultiArmCase') cases, since they are evaluated straight onto the stack
--   with no save-to-locals on the continue path (and 'exprMaxLocals' reserves
--   no save slots there); a value tail and a case scrutinee are ordinary
--   'emitIOk' expressions.
emitTailIOk :: CExpr -> Bool
emitTailIOk = \case
  CContinue xs -> all noMultiArmCase xs
  CCase s alts -> not (null alts) && emitIOk s && all (\(_, _, b) -> emitTailIOk b) alts
  CRowCase s alts -> not (null alts) && emitIOk s && all (\(_, _, b) -> emitTailIOk b) alts
  CDrop _ _ b -> emitTailIOk b
  other -> emitIOk other

-- | Method-global slot kinds for the unified frame builder: the set of slot
--   indices that ever serve as a 'CCase' @arrSlot@ (verifier type @Object[]@)
--   and the set that serve as a @tagSlot@ (@int@). Threads @next@ (the running
--   'cNextLocal') exactly as the emitter allocates — @arrSlot = next@,
--   @tagSlot = next+1@, bindings from @next+2@, arms continue past the widest
--   arm's bindings — so each 'Label' frame can be typed inline at emit time,
--   so each 'Label' frame can be typed inline at emit time (a slot is
--   @Object[]@ if ever an arr slot, @int@ if a tag slot). Slots in neither set
--   are params or pattern bindings (→ @Object@).
buildSlotKinds :: Int -> CExpr -> (Set Int, Set Int)
buildSlotKinds next = \case
  CCase scrut alts ->
    let arrSlot = next
        tagSlot = next + 1
        bindSlotStart = tagSlot + 1
        maxBindings = foldl' max 0 [length vs | (_, vs, _) <- alts]
        next' = bindSlotStart + maxBindings
        armKinds = map (\(_, _, b) -> buildSlotKinds next' b) alts
        (arrs, tags) = unionPairs (buildSlotKinds next scrut : armKinds)
     in (Set.insert arrSlot arrs, Set.insert tagSlot tags)
  CRowCase scrut alts -> buildSlotKinds next (CCase scrut [(fromIntegral t, [v], b) | (t, v, b) <- alts])
  CRow _ v -> buildSlotKinds next v
  CCall f xs ->
    -- When an arg contains a case, 'emitArgsViaLocalsI' reserves @length xs@
    -- save slots at @next@ and emits each arg with 'cNextLocal' advanced past
    -- them — mirror that so a nested case's arr/tag slots land at the right
    -- index. Save slots themselves hold Object arg values (not arr/tag).
    let argsNext = if any exprContainsCase xs then next + length xs else next
     in unionPairs (buildSlotKinds next f : map (buildSlotKinds argsNext) xs)
  CCon _ fs -> unionPairs (map (buildSlotKinds next) fs)
  CReuse _ _ fs -> unionPairs (map (buildSlotKinds next) fs)
  CDrop _ _ b -> buildSlotKinds next b
  CLoop b -> buildSlotKinds next b
  CContinue xs -> unionPairs (map (buildSlotKinds next) xs)
  _ -> (Set.empty, Set.empty)
  where
    unionPairs ps = (Set.unions (map fst ps), Set.unions (map snd ps))

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
  CRowCase scrut alts ->
    -- Same emission shape as 'CCase' (delegated to it in 'emitExprI');
    -- mirror the bound here.
    foldl' max 3 (exprMaxStack scrut : [exprMaxStack b | (_, _, b) <- alts])
  CRow _ v ->
    -- Same shape as a one-field 'CCon': dup + tag store peaks at 4 and
    -- one field push.
    max 4 (3 + exprMaxStack v)
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
  -- Liveness annotation; codegen-transparent (no extra stack slots).
  -- Stack budget == wrapped body's.
  CDrop _ _ b -> exprMaxStack b
  -- Cell reuse. On the JVM it falls through to 'CCon' (fresh
  -- alloc), so stack budget matches an equivalent 'CCon tag fs'.
  CReuse _ tag fs -> exprMaxStack (CCon tag fs)

-- | Build the 'JvmMethod' for one user declaration — the single source
--   consumed by both 'mkDecl' (→ classfile bytes via 'assembleMethod') and
--   the text renderer (→ Jasmin via 'renderMethod'). Every form routes
--   through the unified 'emitExprI' / 'emitTailBinI'; the 'emitIOk' /
--   'emitTailIOk' gates are total over the lowering's output (a multi-arm
--   case never reaches a non-empty-stack position — confirmed by a strict
--   probe finding zero fall-through across the whole test corpus), so the
--   fallbacks are unreachable guards that fail loudly rather than miscompile.
declJvmMethod :: Set Text -> Set Text -> Map Text Int -> CDecl -> AsmM JvmMethod
declJvmMethod valDefs funDefs arities = \case
  -- TCO loop. The entry 'Label' (offset 0) is the 'CContinue' goto target and
  -- carries the signature-derived frame ([Object × nParams], empty stack).
  CFunDef nm args (CLoop body) | emitTailIOk body -> do
    loopLbl <- freshLabel "L_tco"
    let (arrSlots, tagSlots) = buildSlotKinds (length args) body
        ctx = mkCtx (Map.fromList (zip args [0 ..])) (length args) arrSlots tagSlots
        loopFrame = Frame (replicate (length args) (VObject objectClassRef)) []
    bodyI <- emitTailBinI ctx args loopLbl body
    pure (userMethod (mangle nm) (objMethodDesc (length args)) body (length args) (Label loopLbl (Just loopFrame) : bodyI))
  CFunDef nm args body | emitIOk body -> do
    let (arrSlots, tagSlots) = buildSlotKinds (length args) body
        ctx = mkCtx (Map.fromList (zip args [0 ..])) (length args) arrSlots tagSlots
    instrs <- emitExprI ctx body
    pure (userMethod (mangle nm) (objMethodDesc (length args)) body (length args) (instrs <> [AReturn]))
  CValDef nm rhs | emitIOk rhs -> do
    let (arrSlots, tagSlots) = buildSlotKinds 0 rhs
        ctx = mkCtx Map.empty 0 arrSlots tagSlots
    instrs <- emitExprI ctx rhs
    pure (userMethod (mangle nm) "()Ljava/lang/Object;" rhs 0 (instrs <> [AReturn]))
  CFunDef nm _ _ -> error ("JVM: unified emitter gate missed function " <> nm)
  CValDef nm _ -> error ("JVM: unified emitter gate missed value " <> nm)
  where
    mkCtx params next arrSlots tagSlots =
      ECtx
        { cParams = params,
          cLocals = Map.empty,
          cValDefs = valDefs,
          cFunDefs = funDefs,
          cArities = arities,
          cNextLocal = next,
          cUninitSlots = Set.empty,
          cArrSlots = arrSlots,
          cTagSlots = tagSlots
        }
    userMethod name desc body nParams instrs =
      JvmMethod
        { jmName = name,
          jmDesc = desc,
          jmPublic = False,
          jmMaxStack = max 1 (exprMaxStack body),
          jmMaxLocals = nParams + exprMaxLocals body,
          jmBody = instrs
        }

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
  CIntLit n _ ->
    pure [LoadInt32 (fromInteger n :: Int32), InvokeStatic integerValueOfRef]
  CCon tag fields -> emitCellI ctx [PushInt (1 + length fields), ANewArray objectClassRef] (fromIntegral tag) fields
  -- In-place cell reuse: aload the existing Object[] and overwrite its slots,
  -- no fresh anewarray. Managed heap → no refcount branch (memory-management.md).
  CReuse n tag fields -> do
    let slot = case Map.lookup n ctx.cLocals of
          Just s -> s
          Nothing -> case Map.lookup n ctx.cParams of
            Just s -> s
            Nothing -> error ("emitExprI: CReuse on unknown binder " <> n)
    emitCellI ctx [Aload slot, CheckCast objectArrayRef] (fromIntegral tag) fields
  CCall f xs -> emitCallI ctx f xs
  CRow tag v -> emitExprI ctx (CCon (fromIntegral tag) [v])
  CDrop _ _ body -> emitExprI ctx body
  -- Single-arm case: exhaustive over one constructor, so no @if_icmpne@, no
  -- join, no branch targets — hence no StackMapTable. The tag is still
  -- extracted and stored (dead, but it keeps the slot allocation in step with
  -- 'exprMaxLocals' / 'buildSlotKinds', which charge a tag slot per case),
  -- then the fields are bound and the body runs.
  CCase scrut [(_, vars, body)] -> emitSingleArmCaseI ctx scrut vars body
  CCase scrut alts | not (null alts) -> emitMultiArmCaseI ctx scrut alts
  CCase {} -> error "emitExprI: empty CCase (uninhabited scrutinee) — the gates should exclude it"
  CRowCase scrut alts -> emitExprI ctx (CCase scrut [(fromIntegral t, [v], b) | (t, v, b) <- alts])
  CLoop _ -> error "emitExprI: CLoop reached (non-tail position)"
  CContinue _ -> error "emitExprI: CContinue reached (non-tail position)"

-- | A single-arm 'CCase' / 'CRowCase' (one constructor, exhaustive): unbox the
--   scrutinee @Object[]@, extract the boxed tag (dead — kept for slot-count
--   parity with 'exprMaxLocals'), bind each field, then the body. No branches.
emitSingleArmCaseI :: ECtx -> CExpr -> [Text] -> CExpr -> AsmM [JvmInstr]
emitSingleArmCaseI ctx scrut vars body = do
  scrutI <- emitExprI ctx scrut
  let arrSlot = ctx.cNextLocal
      tagSlot = arrSlot + 1
      bindSlotStart = tagSlot + 1
      bindings = zip vars [bindSlotStart ..]
      ctx' =
        ctx
          { cLocals = foldl' (\m (v, s) -> Map.insert v s m) ctx.cLocals bindings,
            cNextLocal = bindSlotStart + length vars
          }
      extractAndStore =
        [ CheckCast objectArrayRef,
          Astore arrSlot,
          Aload arrSlot,
          PushInt 0,
          Aaload,
          CheckCast integerClassRef,
          InvokeVirtual (MethodRef "java/lang/Integer" "intValue" "()I"),
          Istore tagSlot
        ]
      bindCode = concatMap (\((_, slot), i) -> [Aload arrSlot, PushInt i, Aaload, Astore slot]) (zip bindings [1 :: Int ..])
  bodyI <- emitExprI ctx' body
  pure $ scrutI <> extractAndStore <> bindCode <> bodyI

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

-- | Multi-arm 'CCase' (≥2 arms): an @if_icmpne@ chain where each arm extracts
--   its bindings (padded to the widest arm so the join frame is consistent),
--   runs its body, and @goto@s the join; the last arm falls through. Each arm
--   label and the join carry an absolute 'Frame' computed inline from the
--   method-global slot kinds in 'ctx'; as '[JvmInstr]' the assembler resolves
--   the @if_icmpne@ offsets and StackMapTable end-to-end.
emitMultiArmCaseI :: ECtx -> CExpr -> [(Int, [Text], CExpr)] -> AsmM [JvmInstr]
emitMultiArmCaseI ctx scrut alts = do
  scrutI <- emitExprI ctx scrut
  let sorted = sortWith (\(t, _, _) -> t) alts
      arrSlot = ctx.cNextLocal
      tagSlot = arrSlot + 1
      bindSlotStart = tagSlot + 1
      maxBindings = foldl' max 0 [length vs | (_, vs, _) <- sorted]
      next' = bindSlotStart + maxBindings
      n = length sorted
      extractAndStore =
        [ CheckCast objectArrayRef,
          Astore arrSlot,
          Aload arrSlot,
          PushInt 0,
          Aaload,
          CheckCast integerClassRef,
          InvokeVirtual (MethodRef "java/lang/Integer" "intValue" "()I"),
          Istore tagSlot
        ]
      ifFrame = frameAtI ctx bindSlotStart False
      joinFrame = frameAtI ctx next' True
  joinLbl <- freshLabel "L_join"
  armLbls <- replicateM (n - 1) (freshLabel "L_arm") -- labels for arms 1..n-1
  armBodies <- forM sorted $ \(tag, vars, body) -> do
    let bindings = zip vars [bindSlotStart ..]
        ctx' = ctx {cLocals = foldl' (\m (v, s) -> Map.insert v s m) ctx.cLocals bindings, cNextLocal = next'}
        bindCode = concatMap (\((_, slot), j) -> [Aload arrSlot, PushInt j, Aaload, Astore slot]) (zip bindings [1 :: Int ..])
        padCode = concatMap (\slot -> [AconstNull, Astore slot]) [bindSlotStart + length vars .. next' - 1]
    bodyI <- emitExprI ctx' body
    pure (tag, bindCode <> padCode <> bodyI)
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
  pure $ scrutI <> extractAndStore <> chainCode <> [Label joinLbl (Just joinFrame)]

-- | Shared cell builder for 'CCon' / 'CReuse': @<allocOrLoad>@ leaves the
--   @Object[]@ on the stack, then store the boxed tag at [0] and each field at
--   [1..]. Per-field shape is a dup/iconst/aastore chain.
emitCellI :: ECtx -> [JvmInstr] -> Int32 -> [CExpr] -> AsmM [JvmInstr]
emitCellI ctx alloc tag fields = do
  fieldCode <- forM (zip fields [1 :: Int ..]) $ \(fld, i) -> do
    fldInstrs <- emitExprI ctx fld
    pure ([Dup, PushInt i] <> fldInstrs <> [AAStore])
  pure $ alloc <> [Dup, PushInt 0, LoadInt32 tag, InvokeStatic integerValueOfRef, AAStore] <> concat fieldCode

-- | Evaluate each arg with an empty operand stack by saving every arg into a
--   fresh local, then load them all back in order ready for the call. Used
--   when any arg contains a 'CCase'
--   (its frames declare an empty stack, which prior args on the stack would
--   contradict). Save slot @i = cNextLocal + i@; each arg is emitted with
--   'cNextLocal' advanced past all save slots and the not-yet-stored save slots
--   ('save_i' onward) added to 'cUninitSlots' so the case frames type them
--   @top@ via 'slotVTypeI'.
emitArgsViaLocalsI :: ECtx -> [CExpr] -> AsmM [JvmInstr]
emitArgsViaLocalsI ctx args = do
  let firstSlot = ctx.cNextLocal
      nArgs = length args
  argChunks <- forM (zip args [0 ..]) $ \(arg, i) -> do
    let slot = firstSlot + i
        uninitForArg = Set.fromList [firstSlot + j | j <- [i .. nArgs - 1]] `Set.union` ctx.cUninitSlots
        ctx' = ctx {cNextLocal = firstSlot + nArgs, cUninitSlots = uninitForArg}
    ai <- emitExprI ctx' arg
    pure (ai <> [Astore slot])
  pure $ concat argChunks <> [Aload (firstSlot + i) | i <- [0 .. nArgs - 1]]

-- | 'CCall' dispatch for the unified emitter: every prelude built-in becomes an
--   @invokestatic@ to its @AwsumMain.__helper@, direct calls to known functions
--   become @invokestatic@ to the mangled name. Args go through 'callArgs',
--   which routes case-containing args through 'emitArgsViaLocalsI'.
emitCallI :: ECtx -> CExpr -> [CExpr] -> AsmM [JvmInstr]
emitCallI ctx f xs = case f of
  CBuiltIn "internalStdoutPrint" | [x] <- xs -> unary x "__print"
  CBuiltIn "internalStdinReadAllAsUtf16"
    | [] <- xs ->
        pure [InvokeStatic (MethodRef "AwsumMain" "__stdinReadAll" "()Ljava/lang/Object;")]
  CBuiltIn "internalGetArgs"
    | [] <- xs ->
        pure [InvokeStatic (MethodRef "AwsumMain" "__getArgs" "()Ljava/lang/Object;")]
  CBuiltIn name
    | name == "showInt32" || name == "showUInt8",
      [x] <- xs -> do
        ai <- callArgs [x]
        pure $ ai <> [CheckCast integerClassRef, InvokeVirtual (MethodRef "java/lang/Integer" "toString" "()Ljava/lang/String;")]
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
      CDrop _ n body -> goTop ctx (n : pending) body
      other -> emitTailValue ctx pending other
    emitContinue ctx pending newArgs = do
      argsI <- concat <$> traverse (emitExprI ctx) newArgs -- gate keeps these case-free
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
      scrutI <- emitExprI ctx scrut
      let sorted = sortWith (\(t, _, _) -> t) alts
          arrSlot = ctx.cNextLocal
          tagSlot = arrSlot + 1
          bindSlotStart = tagSlot + 1
          maxBindings = foldl' max 0 [length vs | (_, vs, _) <- sorted]
          next' = bindSlotStart + maxBindings
          n = length sorted
          extractAndStore =
            [ CheckCast objectArrayRef,
              Astore arrSlot,
              Aload arrSlot,
              PushInt 0,
              Aaload,
              CheckCast integerClassRef,
              InvokeVirtual (MethodRef "java/lang/Integer" "intValue" "()I"),
              Istore tagSlot
            ]
          ifFrame = frameAtI ctx bindSlotStart False
      armLbls <- replicateM (n - 1) (freshLabel "L_tarm")
      armChunks <- forM sorted $ \(tag, vars, body) -> do
        let bindings = zip vars [bindSlotStart ..]
            ctx' = ctx {cLocals = foldl' (\m (v, s) -> Map.insert v s m) ctx.cLocals bindings, cNextLocal = next'}
            bindCode = concatMap (\((_, slot), j) -> [Aload arrSlot, PushInt j, Aaload, Astore slot]) (zip bindings [1 :: Int ..])
            padCode = concatMap (\slot -> [AconstNull, Astore slot]) [bindSlotStart + length vars .. next' - 1]
        bodyI <- goTop ctx' pending body -- arm body is itself tail
        pure (bindCode <> padCode <> bodyI, tag)
      let preLabels = Nothing : map Just armLbls
          nextTargets = map Just armLbls <> [Nothing]
          buildArm ((armCode, tag), (preLbl, nextLbl)) =
            maybe [] (\l -> [Label l (Just ifFrame)]) preLbl
              <> maybe [] (\l -> [Iload tagSlot, LoadInt32 (fromIntegral tag), IfICmpNe l]) nextLbl
              <> armCode -- self-terminating; no goto-join
          chainCode = concatMap buildArm (zip armChunks (zip preLabels nextTargets))
      pure $ scrutI <> extractAndStore <> chainCode

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
        <> B.word16BE mi.mMaxStack
        <> B.word16BE mi.mMaxLocals
        <> B.word32BE codeLen
        <> B.byteString codeBS
        <> B.word16BE 0 -- exception table
        <> B.word16BE mi.mCodeAttrCount
        <> B.byteString codeAttrsBS
