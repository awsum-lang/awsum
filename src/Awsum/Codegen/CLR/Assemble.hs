-- | CLR PE/.NET assembly binary assembler for Awsum 'Core'.
--
-- Generates a single @AwsumMain.dll@ (.NET 9.0) containing runtime helpers,
-- user declarations, and a @Main(string[])@ entry point.
--
-- All values are @System.Object@; strings are @System.String@;
-- function references are @System.Func@ delegates; @IO Unit@ is @null@.
--
-- The PE file is assembled directly in Haskell — no ilasm, no csc, no MSBuild.
-- Only @dotnet@ is needed to run the output.
module Awsum.Codegen.CLR.Assemble
  ( assembleCLR,
    -- The one gated method list both projections render from
    -- ('Awsum.Codegen.CLR' for text, 'assembleCLR' for bytes).
    CilModule (..),
    cilModule,
    cilModuleMethods,
    -- ECMA-335 metadata index widths, exposed for the boundary unit test.
    MetaWidths (..),
    clrMetaWidths,
  )
where

import Awsum.Codegen.CLR.Instr (CilInstr (..), CilMemberRef (..), CilMethod (..), CilTypeRef (..), LabelId (..), SigElem (..), addInt32Spec, addUInt32Spec, addUInt8Spec, concatSpec, entryArgEitherSpec, eqSpec, eqStringSpec, getArgsSpec, int32Ref, lengthCodePointsSpec, lengthUtf16CodeUnitsSpec, lengthUtf8BytesSpec, mainSpec, maxLocalsOf, maxStackOf, mulInt32Spec, mulUInt32Spec, mulUInt8Spec, negInt32Spec, objectRef, parseInt32Spec, parseUInt32Spec, parseUInt8Spec, predInt32Spec, predUInt32Spec, predUInt8Spec, printSpec, showUInt32Spec, splitOnFirstSpec, stdinReadAllBytesSpec, stdinReadAllSpec, strRef, subInt32Spec, subUInt32Spec, subUInt8Spec, succInt32Spec, succUInt32Spec, succUInt8Spec)
import Awsum.Codegen.Mangle (mangle)
import Awsum.Codegen.ReuseSchedule (ReuseStore (..), reuseSlotElided, scheduleReuse)
import Awsum.Core
import Data.Bits (complement, shiftL, shiftR, (.&.), (.|.))
import Data.ByteString qualified as BS
import Data.ByteString.Builder qualified as B
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text.Encoding qualified as TE
import Relude

-- ════════════════════════════════════════════════════════════════════════════
-- Public API
-- ════════════════════════════════════════════════════════════════════════════

-- | Produce a complete .NET PE DLL as a strict ByteString.
assembleCLR :: PreludeTags -> CoreProgram -> BS.ByteString
assembleCLR ptags prog =
  let (methods, st) = runState (doAssemble prog) (emptyPool ptags)
   in toStrict (B.toLazyByteString (buildPE st methods))

-- ════════════════════════════════════════════════════════════════════════════
-- PE layout constants
-- ════════════════════════════════════════════════════════════════════════════

peFileAlign, peSectAlign, peTextRVA, peTextFileOff, peCliHdrSize :: Int
peFileAlign = 0x200
peSectAlign = 0x2000
peTextRVA = peSectAlign -- .text section RVA = 0x2000
peTextFileOff = peFileAlign -- .text section file offset = 0x200
peCliHdrSize = 72

-- ════════════════════════════════════════════════════════════════════════════
-- Pool state (heaps + metadata tables)
-- ════════════════════════════════════════════════════════════════════════════

data Pool = Pool
  { -- #Strings heap (identifiers, null-terminated UTF-8)
    pStr :: [Word8],
    pStrOff :: Word32,
    pStrC :: Map Text Word32,
    -- #US heap (user string literals for ldstr, UTF-16LE)
    pUS :: [Word8],
    pUSOff :: Word32,
    pUSC :: Map Text Word32,
    -- #Blob heap (signatures)
    pBlob :: [Word8],
    pBlobOff :: Word32,
    pBlobC :: Map [Word8] Word32,
    -- TypeRef table rows: (resScopeCoded, nameStrIdx, nsStrIdx). Heap and
    -- coded indices are kept at full 'Word32' width; 'buildTables' narrows
    -- each to 2 or 4 bytes per the ECMA-335 HeapSizes / rowcount rules.
    pTR :: [(Word32, Word32, Word32)],
    pTRn :: Word32,
    pTRc :: Map (Word32, Text, Text) Word32,
    -- TypeSpec table rows: blobIdx
    pTS :: [Word32],
    pTSn :: Word32,
    pTSc :: Map [Word8] Word32,
    -- MemberRef table rows: (parentCoded, nameStrIdx, sigBlobIdx)
    pMR :: [(Word32, Word32, Word32)],
    pMRn :: Word32,
    pMRc :: Map (Word32, Text, [Word8]) Word32,
    -- Param table rows: (flags, sequence, nameStrIdx). flags/sequence are
    -- true 2-byte columns; only the name is a (heap-width) #Strings index.
    pPM :: [(Word16, Word16, Word32)],
    pPMn :: Word32,
    -- StandAloneSig table rows: blobIdx (for LocalVarSig)
    pSAS :: [Word32],
    pSASn :: Word32,
    -- Globally unique constructor tags for prelude types, threaded
    -- in through 'assembleCLR' so the runtime helpers built here
    -- match the user's CCon/CCase encoding.
    pTags :: PreludeTags,
    -- Name → MethodDef token map (set once, before any method is
    -- emitted). 'assembleCilMethod' resolves a 'CallNamed' to its token
    -- through this; the call stays symbolic until then.
    pTokMap :: Map Text Word32
  }

type AsmM = State Pool

-- | Read the threaded-in 'PreludeTags' from the assembler state.
askPreludeTags :: AsmM PreludeTags
askPreludeTags = gets pTags

emptyPool :: PreludeTags -> Pool
emptyPool ptags =
  Pool
    { pStr = [0x00],
      pStrOff = 1,
      pStrC = Map.empty,
      pUS = [0x00],
      pUSOff = 1,
      pUSC = Map.empty,
      pBlob = [0x00],
      pBlobOff = 1,
      pBlobC = Map.empty,
      pTR = [],
      pTRn = 0,
      pTRc = Map.empty,
      pTS = [],
      pTSn = 0,
      pTSc = Map.empty,
      pMR = [],
      pMRn = 0,
      pMRc = Map.empty,
      pPM = [],
      pPMn = 0,
      pSAS = [],
      pSASn = 0,
      pTags = ptags,
      pTokMap = Map.empty
    }

-- ════════════════════════════════════════════════════════════════════════════
-- Heap management
-- ════════════════════════════════════════════════════════════════════════════

-- | Add a string to #Strings heap. Returns offset.
addStr :: Text -> AsmM Word32
addStr t = do
  st <- get
  case Map.lookup t st.pStrC of
    Just off -> pure off
    Nothing -> do
      let bytes = BS.unpack (encodeUtf8 t) <> [0x00]
          off = st.pStrOff
      put st {pStr = st.pStr <> bytes, pStrOff = off + fromIntegral (length bytes), pStrC = Map.insert t off st.pStrC}
      pure off

-- | Add a user string literal to #US heap. Returns full ldstr token.
addUS :: Text -> AsmM Word32
addUS t = do
  st <- get
  case Map.lookup t st.pUSC of
    Just off -> pure (0x70000000 .|. off)
    Nothing -> do
      let utf16 = BS.unpack (TE.encodeUtf16LE t)
          dataLen = length utf16 + 1 -- +1 for trailing byte
          entry = compressU (fromIntegral dataLen) <> utf16 <> [0x01]
          off = st.pUSOff
      put st {pUS = st.pUS <> entry, pUSOff = off + fromIntegral (length entry), pUSC = Map.insert t off st.pUSC}
      pure (0x70000000 .|. off)

-- | Add a signature to #Blob heap. Returns offset.
addBlob :: [Word8] -> AsmM Word32
addBlob sig = do
  st <- get
  case Map.lookup sig st.pBlobC of
    Just off -> pure off
    Nothing -> do
      let entry = compressU (fromIntegral (length sig)) <> sig
          off = st.pBlobOff
      put st {pBlob = st.pBlob <> entry, pBlobOff = off + fromIntegral (length entry), pBlobC = Map.insert sig off st.pBlobC}
      pure off

-- | CLI compressed unsigned integer encoding.
compressU :: Word32 -> [Word8]
compressU n
  | n < 0x80 = [fromIntegral n]
  | n < 0x4000 = [fromIntegral (0x80 .|. (n `shiftR` 8)), fromIntegral (n .&. 0xFF)]
  | otherwise =
      [ fromIntegral (0xC0 .|. (n `shiftR` 24)),
        fromIntegral ((n `shiftR` 16) .&. 0xFF),
        fromIntegral ((n `shiftR` 8) .&. 0xFF),
        fromIntegral (n .&. 0xFF)
      ]

-- ════════════════════════════════════════════════════════════════════════════
-- Table management
-- ════════════════════════════════════════════════════════════════════════════

-- | Add TypeRef row. Returns 1-based row number.
addTypeRef :: Word32 -> Text -> Text -> AsmM Word32
addTypeRef resScope name ns = do
  st <- get
  let key = (resScope, name, ns)
  case Map.lookup key st.pTRc of
    Just row -> pure row
    Nothing -> do
      ni <- addStr name
      nsi <- addStr ns
      st' <- get
      let row = st'.pTRn + 1
      put st' {pTR = st'.pTR <> [(resScope, ni, nsi)], pTRn = row, pTRc = Map.insert key row st'.pTRc}
      pure row

-- | Add TypeSpec row. Returns 1-based row number.
addTypeSpec :: [Word8] -> AsmM Word32
addTypeSpec sig = do
  st <- get
  case Map.lookup sig st.pTSc of
    Just row -> pure row
    Nothing -> do
      bi <- addBlob sig
      st' <- get
      let row = st'.pTSn + 1
      put st' {pTS = st'.pTS <> [bi], pTSn = row, pTSc = Map.insert sig row st'.pTSc}
      pure row

-- | Add MemberRef row. Returns 1-based row number.
addMemberRef :: Word32 -> Text -> [Word8] -> AsmM Word32
addMemberRef parent name sig = do
  st <- get
  let key = (parent, name, sig)
  case Map.lookup key st.pMRc of
    Just row -> pure row
    Nothing -> do
      ni <- addStr name
      si <- addBlob sig
      st' <- get
      let row = st'.pMRn + 1
      put st' {pMR = st'.pMR <> [(parent, ni, si)], pMRn = row, pMRc = Map.insert key row st'.pMRc}
      pure row

-- | Add N param entries. Returns the starting row (1-based).
addParams :: Int -> AsmM Word32
addParams 0 = gets (\s -> s.pPMn + 1)
addParams n = do
  st <- get
  let startRow = st.pPMn + 1
      newPs = [(0, fromIntegral i, 0) | i <- [1 .. n]]
  put st {pPM = st.pPM <> newPs, pPMn = st.pPMn + fromIntegral n}
  pure startRow

-- | Add a StandAloneSig row from an arbitrary LocalVarSig blob and
--   return its metadata token (table 0x11 << 24 | row).
addLocalSigBytes :: [Word8] -> AsmM Word32
addLocalSigBytes blob = do
  bi <- addBlob blob
  st <- get
  let row = st.pSASn + 1
  put st {pSAS = st.pSAS <> [bi], pSASn = row}
  pure (0x11000000 .|. row)

-- ════════════════════════════════════════════════════════════════════════════
-- Coded index helpers
-- ════════════════════════════════════════════════════════════════════════════

-- Coded indices keep full 'Word32' width; buildTables narrows each to 2 or 4
-- bytes per the ECMA-335 rule for its tag width and the rowcounts it codes over.

-- ResolutionScope: 2-bit tag. 10 = AssemblyRef.
resScopeAR :: Word32 -> Word32
resScopeAR row = (row `shiftL` 2) .|. 0x02

-- TypeDefOrRef: 2-bit tag. 01 = TypeRef.
tdorTR :: Word32 -> Word32
tdorTR row = (row `shiftL` 2) .|. 0x01

-- MemberRefParent: 3-bit tag. 001 = TypeRef, 100 = TypeSpec.
mrpTR :: Word32 -> Word32
mrpTR row = (row `shiftL` 3) .|. 0x01

-- ════════════════════════════════════════════════════════════════════════════
-- Signature construction
-- ════════════════════════════════════════════════════════════════════════════

-- Element types
etVoid, etString, etObject :: Word8
etVoid = 0x01
etString = 0x0E
etObject = 0x1C

-- | Static method sig: DEFAULT, N params (all object), returns retType.
-- | Instance method sig: HASTHIS, paramTypes, returns retType.
sigInstance :: Word8 -> [Word8] -> [Word8]
sigInstance retType pts = [0x20, fromIntegral (length pts), retType] <> pts

-- ════════════════════════════════════════════════════════════════════════════
-- Token construction
-- ════════════════════════════════════════════════════════════════════════════

mkTok :: Word8 -> Word32 -> Word32
mkTok tbl row = (fromIntegral tbl `shiftL` 24) .|. row

tokTR :: Word32 -> Word32
tokTR = mkTok 0x01 -- TypeRef

tokMD :: Word32 -> Word32
tokMD = mkTok 0x06 -- MethodDef

tokMR :: Word32 -> Word32
tokMR = mkTok 0x0A -- MemberRef

tokTS :: Word32 -> Word32
tokTS = mkTok 0x1B -- TypeSpec

-- ════════════════════════════════════════════════════════════════════════════
-- CIL opcodes
-- ════════════════════════════════════════════════════════════════════════════

cilLdarg :: Int -> [Word8]
cilLdarg 0 = [0x02]
cilLdarg 1 = [0x03]
cilLdarg 2 = [0x04]
cilLdarg 3 = [0x05]
cilLdarg n
  | n <= 255 = [0x0E, fromIntegral n]
  | otherwise = [0xFE, 0x09] <> w16le (fromIntegral n)

cilLdstr, cilCall, cilCallvirt, cilNewobj, cilCastclass :: Word32 -> [Word8]
cilLdstr tok = 0x72 : w32le tok
cilCall tok = 0x28 : w32le tok
cilCallvirt tok = 0x6F : w32le tok
cilNewobj tok = 0x73 : w32le tok
cilCastclass tok = 0x74 : w32le tok

cilRet, cilPop, cilLdnull, cilLdlen, cilConvI4 :: [Word8]
cilRet = [0x2A]
cilPop = [0x26]
cilLdnull = [0x14]
cilLdlen = [0x8E]
cilConvI4 = [0x69]

cilXor, cilAnd :: [Word8]
cilXor = [0x61]
cilAnd = [0x5F]

-- | @br@ with a 4-byte signed offset — used by TCO to jump back to the
-- method's @IL_tco_loop:@ position, which can be hundreds of bytes away
-- inside a non-trivial body.
cilBr :: Int32 -> [Word8]
cilBr off = 0x38 : w32le (fromIntegral off :: Word32)

-- | @bne.un@ with a 4-byte signed offset — same reason as 'cilBr'.
cilBneUn :: Int32 -> [Word8]
cilBneUn off = 0x40 : w32le (fromIntegral off :: Word32)

cilBrfalse, cilBrtrue, cilBeq, cilBge, cilBgt, cilBlt, cilBle, cilBgtUn, cilBltUn :: Int32 -> [Word8]
cilBrfalse off = 0x39 : w32le (fromIntegral off :: Word32)
cilBrtrue off = 0x3A : w32le (fromIntegral off :: Word32)
cilBeq off = 0x3B : w32le (fromIntegral off :: Word32)
cilBge off = 0x3C : w32le (fromIntegral off :: Word32)
cilBgt off = 0x3D : w32le (fromIntegral off :: Word32)
cilBlt off = 0x3F : w32le (fromIntegral off :: Word32)
cilBle off = 0x3E : w32le (fromIntegral off :: Word32) -- ble: signed <=, 4-byte offset
cilBgtUn off = 0x42 : w32le (fromIntegral off :: Word32) -- bgt.un: unsigned >, 4-byte offset
cilBltUn off = 0x44 : w32le (fromIntegral off :: Word32) -- blt.un: unsigned <, 4-byte offset

cilNeg, cilMul, cilDiv, cilConvI8, cilShl, cilConvU8, cilConvU4 :: [Word8]
cilNeg = [0x65]
cilMul = [0x5A]
cilDiv = [0x5B] -- div: signed integer division
cilConvI8 = [0x6A]
cilShl = [0x62]
cilConvU8 = [0x6E] -- conv.u8: zero-extend top of stack to uint64
cilConvU4 = [0x6D] -- conv.u4: truncate / unsigned-narrow to uint32

-- | @ldc.i8 <imm64>@ — push a signed-int64 literal. Used by UInt32
-- helpers to materialise 4294967295 as a long boundary without
-- relying on a CPLong-style indirection.
cilLdcI8 :: Int64 -> [Word8]
cilLdcI8 n = 0x21 : w64le (fromIntegral n :: Word64)

-- | @starg.s <n>@ / long form — stores the top of stack into argument
-- slot @n@. Used by 'CContinue' to rebind parameters in place before
-- branching back to the loop head.
cilStarg :: Int -> [Word8]
cilStarg n
  | n <= 255 = [0x10, fromIntegral n]
  | otherwise = [0xFE, 0x0B] <> w16le (fromIntegral n)

cilSub :: [Word8]
cilSub = [0x59]

cilAdd :: [Word8]
cilAdd = [0x58]

cilBox, cilUnboxAny :: Word32 -> [Word8]
cilBox tok = 0x8C : w32le tok
cilUnboxAny tok = 0xA5 : w32le tok

cilLdcI4 :: Int -> [Word8]
cilLdcI4 n
  | n >= 0 && n <= 8 = [fromIntegral (0x16 + n)] -- ldc.i4.0 .. ldc.i4.8
  | n == -1 = [0x15] -- ldc.i4.m1
  | n >= -128 && n <= 127 = [0x1F, fromIntegral n] -- ldc.i4.s
  | otherwise = 0x20 : w32le (fromIntegral n) -- ldc.i4

cilStloc :: Int -> [Word8]
cilStloc n
  | n <= 3 = [fromIntegral (0x0A + n)] -- stloc.0..stloc.3
  | n <= 255 = [0x13, fromIntegral n] -- stloc.s
  | otherwise = [0xFE, 0x0E] <> w16le (fromIntegral n)

cilLdloc :: Int -> [Word8]
cilLdloc n
  | n <= 3 = [fromIntegral (0x06 + n)] -- ldloc.0..ldloc.3
  | n <= 255 = [0x11, fromIntegral n] -- ldloc.s
  | otherwise = [0xFE, 0x0C] <> w16le (fromIntegral n)

cilDup, cilStelemRef, cilLdelemRef' :: [Word8]
cilDup = [0x25]
cilStelemRef = [0xA2]
cilLdelemRef' = [0x9A]

cilNewarr :: Word32 -> [Word8]
cilNewarr tok = 0x8D : w32le tok

-- ════════════════════════════════════════════════════════════════════════════
-- Byte helpers
-- ════════════════════════════════════════════════════════════════════════════

w16le :: Word16 -> [Word8]
w16le w = [fromIntegral (w .&. 0xFF), fromIntegral (w `shiftR` 8)]

w32le :: Word32 -> [Word8]
w32le w =
  [ fromIntegral (w .&. 0xFF),
    fromIntegral ((w `shiftR` 8) .&. 0xFF),
    fromIntegral ((w `shiftR` 16) .&. 0xFF),
    fromIntegral ((w `shiftR` 24) .&. 0xFF)
  ]

w64le :: Word64 -> [Word8]
w64le w = w32le (fromIntegral (w .&. 0xFFFFFFFF)) <> w32le (fromIntegral (w `shiftR` 32))

align4 :: Int -> Int
align4 n = (n + 3) .&. complement 3

padTo4 :: [Word8] -> [Word8]
padTo4 bs = bs <> replicate (align4 (length bs) - length bs) 0

alignToN :: Int -> Int -> Int
alignToN a n = ((n + a - 1) `div` a) * a

-- ════════════════════════════════════════════════════════════════════════════
-- Method info
-- ════════════════════════════════════════════════════════════════════════════

data MInfo = MInfo
  { mImplFlags :: Word16,
    mFlags :: Word16,
    mName :: Word32, -- #Strings index (narrowed per HeapSizes in buildTables)
    mSig :: Word32, -- #Blob index (narrowed per HeapSizes in buildTables)
    mParamList :: Word32, -- first Param row (1-based)
    mCode :: [Word8], -- CIL bytecode
    mLocalSigTok :: Word32, -- StandAloneSig token for locals (0 = no locals)

    -- | Maximum operand-stack depth this method needs at any point
    -- during execution (ECMA-335 §II.25.4.3). Encoded into the fat
    -- method header; tiny-format methods (no locals, code < 64 bytes)
    -- use the implicit MaxStack of 8 from the standard and ignore
    -- this field. Verifier rejects any method whose actual depth
    -- exceeds the declared value with @InvalidProgramException@.
    mMaxStack :: Word16
  }

-- ════════════════════════════════════════════════════════════════════════════
-- Module value (single source for text + bytes)
-- ════════════════════════════════════════════════════════════════════════════

-- | The gated, ordered methods of one program's @AwsumMain@ class. Both
--   'Awsum.Codegen.CLR.codegenCLR' (text) and 'assembleCLR' (bytes) derive from
--   this one value, so gating is decided once. Grouped so the text renderer
--   reproduces the existing blank-line layout: 'clmHelpers' and 'clmEntry'
--   single-spaced, 'clmUserDefs' double-spaced. The @.ctor@ and the class
--   framing are fixed and live in the renderers. The byte assembler assigns
--   MethodDef tokens by position in @.ctor@ : 'cilModuleMethods'; @Main@ is
--   always last, so its entry-point token is stable.
data CilModule = CilModule
  { clmHelpers :: [CilMethod],
    clmUserDefs :: [CilMethod],
    clmEntry :: [CilMethod]
  }

-- | The flat method list (helpers, then user declarations, then entry + @Main@).
cilModuleMethods :: CilModule -> [CilMethod]
cilModuleMethods m = clmHelpers m <> clmUserDefs m <> clmEntry m

-- | Lower a program to its 'CilModule' — the gating decision, made once.
cilModule :: PreludeTags -> CoreProgram -> CilModule
cilModule ptags prog@(CoreProgram decls) =
  let valNames = Set.fromList [n | CValDef n _ <- decls]
      funNames = Set.fromList [n | CFunDef n _ _ <- decls]
      arities = Map.fromList [(n, length as) | CFunDef n as _ <- decls]
      ectx = ECtx {eParams = Map.empty, eLocals = Map.empty, eNextScratch = 0, eValDefs = valNames, eFunDefs = funNames, eArities = arities, eJoinTargets = Map.empty, eArmPatternByScrut = Map.empty}
      builtIns = usedBuiltIns prog
      gate cond ms = if cond then ms else []
   in CilModule
        { clmHelpers =
            concat
              [ gate (Set.member "concatString" builtIns) [concatSpec (ptRight ptags) (ptLeft ptags) (ptStringTooLong ptags)],
                gate (Set.member "internalStdoutPrint" builtIns) [printSpec (ptUnit ptags)],
                gate (Set.member "predInt32" builtIns) [predInt32Spec (ptUnderflowError ptags) (ptLeft ptags) (ptRight ptags)],
                gate (Set.member "predUInt8" builtIns) [predUInt8Spec (ptUnderflowError ptags) (ptLeft ptags) (ptRight ptags)],
                gate (Set.member "predUInt32" builtIns) [predUInt32Spec (ptUnderflowError ptags) (ptLeft ptags) (ptRight ptags)],
                gate (Set.member "succInt32" builtIns) [succInt32Spec (ptOverflowError ptags) (ptLeft ptags) (ptRight ptags)],
                gate (Set.member "succUInt8" builtIns) [succUInt8Spec (ptOverflowError ptags) (ptLeft ptags) (ptRight ptags)],
                gate (Set.member "succUInt32" builtIns) [succUInt32Spec (ptOverflowError ptags) (ptLeft ptags) (ptRight ptags)],
                gate (Set.member "eqInt32" builtIns) [eqSpec "__eqInt32" "IL_eq_i32" (ptTrue ptags) (ptFalse ptags)],
                gate (Set.member "eqUInt8" builtIns) [eqSpec "__eqUInt8" "IL_eq_u8" (ptTrue ptags) (ptFalse ptags)],
                gate (Set.member "eqUInt32" builtIns) [eqSpec "__eqUInt32" "IL_eq_u32" (ptTrue ptags) (ptFalse ptags)],
                gate (Set.member "eqString" builtIns) [eqStringSpec (ptTrue ptags) (ptFalse ptags)],
                gate (Set.member "addInt32" builtIns) [addInt32Spec (ptRight ptags) (ptOverflowError ptags) (ptUnderflowError ptags) (ptLeft ptags)],
                gate (Set.member "subInt32" builtIns) [subInt32Spec (ptRight ptags) (ptOverflowError ptags) (ptUnderflowError ptags) (ptLeft ptags)],
                gate (Set.member "mulInt32" builtIns) [mulInt32Spec (ptRight ptags) (ptOverflowError ptags) (ptUnderflowError ptags) (ptLeft ptags)],
                gate (Set.member "negInt32" builtIns) [negInt32Spec (ptOverflowError ptags) (ptLeft ptags) (ptRight ptags)],
                gate (Set.member "addUInt8" builtIns) [addUInt8Spec (ptRight ptags) (ptOverflowError ptags) (ptLeft ptags)],
                gate (Set.member "subUInt8" builtIns) [subUInt8Spec (ptRight ptags) (ptUnderflowError ptags) (ptLeft ptags)],
                gate (Set.member "mulUInt8" builtIns) [mulUInt8Spec (ptRight ptags) (ptOverflowError ptags) (ptLeft ptags)],
                gate (Set.member "addUInt32" builtIns) [addUInt32Spec (ptRight ptags) (ptOverflowError ptags) (ptLeft ptags)],
                gate (Set.member "subUInt32" builtIns) [subUInt32Spec (ptRight ptags) (ptUnderflowError ptags) (ptLeft ptags)],
                gate (Set.member "mulUInt32" builtIns) [mulUInt32Spec (ptRight ptags) (ptOverflowError ptags) (ptLeft ptags)],
                gate (Set.member "showUInt32" builtIns) [showUInt32Spec],
                gate (Set.member "splitOnFirst" builtIns) [splitOnFirstSpec (ptNothing ptags) (ptTuple2 ptags) (ptJust ptags)],
                gate (Set.member "lengthCodePoints" builtIns) [lengthCodePointsSpec],
                gate (Set.member "lengthUtf16CodeUnits" builtIns) [lengthUtf16CodeUnitsSpec],
                gate (Set.member "lengthUtf8Bytes" builtIns) [lengthUtf8BytesSpec],
                gate (Set.member "parseInt32" builtIns) [parseInt32Spec (ptRight ptags) (ptParseError ptags) (ptLeft ptags)],
                gate (Set.member "parseUInt8" builtIns) [parseUInt8Spec (ptRight ptags) (ptParseError ptags) (ptLeft ptags)],
                gate (Set.member "parseUInt32" builtIns) [parseUInt32Spec (ptRight ptags) (ptParseError ptags) (ptLeft ptags)]
              ],
          clmUserDefs = map (declCilMethod ectx) decls,
          clmEntry =
            concat
              [ gate (Set.member "internalGetArgs" builtIns) [entryArgEitherSpec (ptRight ptags) (ptStringTooLong ptags) (ptUnpairedUtf16Surrogate ptags) (ptLeft ptags)],
                gate (Set.member "internalGetArgs" builtIns) [getArgsSpec (ptRight ptags) (ptNil ptags) (ptCons ptags)],
                gate (Set.member "internalStdinReadAllString" builtIns) [stdinReadAllSpec (ptRight ptags) (ptStringTooLong ptags) (ptInvalidUtf8 ptags) (ptLeft ptags)],
                gate (Set.member "internalStdinReadAllBytes" builtIns) [stdinReadAllBytesSpec (ptNil ptags) (ptCons ptags)],
                [mainSpec]
              ]
        }

-- ════════════════════════════════════════════════════════════════════════════
-- Assembly logic
-- ════════════════════════════════════════════════════════════════════════════

doAssemble :: CoreProgram -> AsmM [MInfo]
doAssemble (CoreProgram decls) = do
  -- Pre-register strings needed by metadata serialization
  void $ addStr ""
  void $ addStr "AwsumMain.dll"
  void $ addStr "AwsumMain"
  void $ addStr "<Module>"
  void $ addStr "System.Runtime"
  void $ addStr "System.Console"

  -- Pre-register BCL public key token blob
  void $ addBlob [0xB0, 0x3F, 0x5F, 0x7F, 0x11, 0xD5, 0x0A, 0x3A]

  -- TypeRefs: AssemblyRef 1 = System.Runtime, AssemblyRef 2 = System.Console
  void $ addTypeRef (resScopeAR 1) "Object" "System" -- row 1
  void $ addTypeRef (resScopeAR 2) "Console" "System" -- row 2
  void $ addTypeRef (resScopeAR 1) "String" "System" -- row 3

  -- MemberRefs (fixed rows 1-3)
  void $ addMemberRef (mrpTR 1) ".ctor" (sigInstance etVoid [])
  void $ addMemberRef (mrpTR 3) "Concat" [0x00, 0x02, etString, etObject, etObject]
  void $ addMemberRef (mrpTR 2) "Write" [0x00, 0x01, etVoid, etObject]

  -- The gated method list, decided once in 'cilModule'. 'allNames' assigns
  -- MethodDef tokens by position: '.ctor' is row 1, then each method in
  -- 'cilModuleMethods' order (helpers, user decls, entry, with 'Main' last).
  -- Helpers/entry are gated, so hello-style programs don't carry unused
  -- primitives, and the tokens stay contiguous. The text projection
  -- ('Awsum.Codegen.CLR') renders the same list.
  ptags <- askPreludeTags
  let methodList = cilModuleMethods (cilModule ptags (CoreProgram decls))
      allNames = ".ctor" : map cmName methodList
      tokMap = Map.fromList [(n, tokMD (fromIntegral i)) | (i, n) <- zip ([1 ..] :: [Int]) allNames]

  -- Make the name→token map available to 'assembleCilMethod' (resolves
  -- 'CallNamed' in emitted user methods). Set once, before any method.
  modify (\p -> p {pTokMap = tokMap})
  -- Every method beyond '.ctor' comes from the one 'cilModule' value. First-class
  -- function values (closures) are the only Core shape 'declCilMethod' does not
  -- lower — but 'LowerClosures' removes them all before codegen, so 'emitExprI'
  -- errors rather than handling them (a probe confirmed 0 occurrences).
  m0 <- mkInit
  ms <- traverse assembleCilMethod methodList
  pure (m0 : ms)

-- ════════════════════════════════════════════════════════════════════════════
-- Fixed methods
-- ════════════════════════════════════════════════════════════════════════════

mkInit :: AsmM MInfo
mkInit = do
  ni <- addStr ".ctor"
  si <- addBlob (sigInstance etVoid [])
  ps <- addParams 0
  let code = cilLdarg 0 <> cilCall (tokMR 1) <> cilRet -- MemberRef 1 = Object::.ctor
  pure MInfo {mImplFlags = 0, mFlags = 0x1881, mName = ni, mSig = si, mParamList = ps, mCode = code, mLocalSigTok = 0, mMaxStack = 16}

-- | Byte projection of a 'CilMethod' (the binary counterpart of
--   'Awsum.Codegen.CLR.Instr.renderCilMethod'): resolve every symbolic operand
--   to its metadata token and emit the CIL byte stream + 'MInfo'. @.maxstack@
--   comes from the spec (derived by 'maxStackOf').
assembleCilMethod :: CilMethod -> AsmM MInfo
assembleCilMethod m = do
  ni <- addStr (cmName m)
  retBytes <- sigElemBytes (cmRet m)
  paramBytes <- concat <$> traverse sigElemBytes (cmParams m)
  si <- addBlob ([0x00, fromIntegral (length (cmParams m))] <> retBytes <> paramBytes)
  ps <- addParams (length (cmParams m))
  localTok <-
    if null (cmLocals m)
      then pure 0
      else do
        localBytes <- concat <$> traverse sigElemBytes (cmLocals m)
        addLocalSigBytes ((0x07 : compressU (fromIntegral (length (cmLocals m)))) <> localBytes)
  code <- emitBody (cmBody m)
  pure
    MInfo
      { mImplFlags = 0,
        mFlags = 0x0091,
        mName = ni,
        mSig = si,
        mParamList = ps,
        mCode = code,
        mLocalSigTok = localTok,
        mMaxStack = fromIntegral (maxStackOf (cmBody m))
      }
  where
    -- A signature element as blob bytes. Flat element types are a single byte;
    -- @class@ / @valuetype@ are 0x12 / 0x11 followed by a compressed
    -- TypeDefOrRef-coded token (so this is monadic — it interns the typeref).
    sigElemBytes :: SigElem -> AsmM [Word8]
    sigElemBytes = \case
      SeObject -> pure [0x1C]
      SeString -> pure [0x0E]
      SeInt32 -> pure [0x08]
      SeUInt8 -> pure [0x05]
      SeInt64 -> pure [0x0A]
      SeChar -> pure [0x03]
      SeBool -> pure [0x02]
      SeVoid -> pure [0x01]
      SeClass tr -> tdorBytes 0x12 tr
      SeValueType tr -> tdorBytes 0x11 tr
      SeSZArray e -> (0x1D :) <$> sigElemBytes e
      where
        tdorBytes prefix (CilTypeRef asm ns name) = do
          r <- addTypeRef (resScopeAR (fromIntegral asm)) name ns
          pure (prefix : compressU (tdorTR r))
    trTok :: CilTypeRef -> AsmM Word32
    trTok (CilTypeRef asm ns name) = tokTR <$> addTypeRef (resScopeAR (fromIntegral asm)) name ns
    mrTok :: CilMemberRef -> AsmM Word32
    mrTok (CilMemberRef parent name isInst ret params) = do
      pr <- addTypeRef (resScopeAR (fromIntegral parent.ctrAsm)) parent.ctrName parent.ctrNs
      retB <- sigElemBytes ret
      paramBs <- concat <$> traverse sigElemBytes params
      let sig = [if isInst then 0x20 else 0x00, fromIntegral (length params)] <> retB <> paramBs
      tokMR <$> addMemberRef (mrpTR pr) name sig
    -- Pure byte length of one instruction. Token-bearing instructions are a
    -- fixed 5 bytes regardless of the resolved token, so branch-offset
    -- resolution needs no metadata-table state.
    instrLen :: CilInstr -> Int
    instrLen = \case
      Ldarg n -> if n <= 3 then 1 else if n <= 255 then 2 else 4
      Ldloc n -> if n <= 3 then 1 else if n <= 255 then 2 else 4
      Stloc n -> if n <= 3 then 1 else if n <= 255 then 2 else 4
      Starg n -> if n <= 255 then 2 else 4
      LdcI4 n
        | (n >= 0 && n <= 8) || n == -1 -> 1
        | n >= -128 && n <= 127 -> 2
        | otherwise -> 5
      Dup -> 1
      Pop -> 1
      Newarr _ -> 5
      StelemRef -> 1
      LdelemRef -> 1
      LdelemU1 -> 1
      Box _ -> 5
      UnboxAny _ -> 5
      Castclass _ -> 5
      CastObjArr -> 5
      Call _ -> 5
      Callvirt _ -> 5
      Newobj _ -> 5
      Ldlen -> 1
      Ldstr _ -> 5
      Ldnull -> 1
      CallNamed _ _ -> 5
      Add -> 1
      Sub -> 1
      Neg -> 1
      Mul -> 1
      Div -> 1
      Xor -> 1
      And -> 1
      Shl -> 1
      ConvI4 -> 1
      ConvI8 -> 1
      ConvU4 -> 1
      ConvU8 -> 1
      LdcI8 _ -> 9
      BneUn _ -> 5
      Brfalse _ -> 5
      Brtrue _ -> 5
      Br _ -> 5
      Beq _ -> 5
      Bge _ -> 5
      Blt _ -> 5
      Ble _ -> 5
      Bgt _ -> 5
      BgtUn _ -> 5
      BltUn _ -> 5
      Label _ -> 0
      Ret -> 1
    -- Byte offset of every label within the method body (labels are 0-width).
    labelOffsets :: Map Text Int
    labelOffsets = go 0 (cmBody m)
      where
        go _ [] = mempty
        go off (Label (LabelId l) : rest) = Map.insert l off (go off rest)
        go off (i : rest) = go (off + instrLen i) rest
    -- A long branch's operand is the signed delta from the byte *after* the
    -- 5-byte branch to the target label.
    branchOff :: Int -> LabelId -> Int32
    branchOff off (LabelId l) = case Map.lookup l labelOffsets of
      Just tgt -> fromIntegral (tgt - (off + 5))
      Nothing -> error ("CLR.Assemble.assembleCilMethod: undefined branch label " <> l)
    emitBody :: [CilInstr] -> AsmM [Word8]
    emitBody = go 0
      where
        go _ [] = pure []
        go off (i : rest) = do
          bs <- asmInstr off i
          (bs <>) <$> go (off + instrLen i) rest
    asmInstr :: Int -> CilInstr -> AsmM [Word8]
    asmInstr off = \case
      Ldarg n -> pure (cilLdarg n)
      Ldloc n -> pure (cilLdloc n)
      Stloc n -> pure (cilStloc n)
      Starg n -> pure (cilStarg n)
      LdcI4 n -> pure (cilLdcI4 n)
      Dup -> pure cilDup
      Pop -> pure cilPop
      Newarr tr -> cilNewarr <$> trTok tr
      StelemRef -> pure cilStelemRef
      LdelemRef -> pure cilLdelemRef'
      LdelemU1 -> pure [0x91]
      Box tr -> cilBox <$> trTok tr
      UnboxAny tr -> cilUnboxAny <$> trTok tr
      Castclass tr -> cilCastclass <$> trTok tr
      CastObjArr -> cilCastclass . tokTS <$> addTypeSpec [0x1D, 0x1C]
      Call mr -> cilCall <$> mrTok mr
      Callvirt mr -> cilCallvirt <$> mrTok mr
      Newobj mr -> cilNewobj <$> mrTok mr
      Ldlen -> pure cilLdlen
      Ldstr s -> cilLdstr <$> addUS s
      Ldnull -> pure cilLdnull
      CallNamed name _ -> do
        tm <- gets pTokMap
        pure (cilCall (fromMaybe (error ("CLR.Assemble: no token for " <> name)) (Map.lookup name tm)))
      Add -> pure cilAdd
      Sub -> pure cilSub
      Neg -> pure cilNeg
      Mul -> pure cilMul
      Div -> pure cilDiv
      Xor -> pure cilXor
      And -> pure cilAnd
      Shl -> pure cilShl
      ConvI4 -> pure cilConvI4
      ConvI8 -> pure cilConvI8
      ConvU4 -> pure cilConvU4
      ConvU8 -> pure cilConvU8
      LdcI8 n -> pure (cilLdcI8 n)
      BneUn l -> pure (cilBneUn (branchOff off l))
      Brfalse l -> pure (cilBrfalse (branchOff off l))
      Brtrue l -> pure (cilBrtrue (branchOff off l))
      Br l -> pure (cilBr (branchOff off l))
      Beq l -> pure (cilBeq (branchOff off l))
      Bge l -> pure (cilBge (branchOff off l))
      Blt l -> pure (cilBlt (branchOff off l))
      Ble l -> pure (cilBle (branchOff off l))
      Bgt l -> pure (cilBgt (branchOff off l))
      BgtUn l -> pure (cilBgtUn (branchOff off l))
      BltUn l -> pure (cilBltUn (branchOff off l))
      Label _ -> pure []
      Ret -> pure cilRet

-- ════════════════════════════════════════════════════════════════════════════
-- User declaration methods
-- ════════════════════════════════════════════════════════════════════════════

data ECtx = ECtx
  { eParams :: Map Text Int,
    eLocals :: Map Text Int, -- case-bound variable → ldloc slot

    -- | Next free local slot for *scratch* use — the temp slot a
    -- 'CCon' uses to hold its array between field stores, and the
    -- array slot a 'CCase' uses to hold its scrutinee. Threaded
    -- through nested constructs (rather than recomputed from
    -- 'eLocals') because scratch slots are not user-visible and so
    -- never appear in 'eLocals'; without this counter, two sibling
    -- 'CCon's at the same nesting level would alias the same slot.
    eNextScratch :: Int,
    eValDefs :: Set Text,
    eFunDefs :: Set Text,
    eArities :: Map Text Int,
    -- | Join points in scope: name → (body label, parameter slots, tail
    -- 'pending' depth at the node — a tail-mode jump drains only the
    -- parameter drops accumulated after that point; the rest stays for the
    -- join body's own terminals). The slots are reserved at the 'CJoin'
    -- (the scratch counter advances past them for everything inside), so
    -- no scratch user — an argument's own case, a cell temp — can alias a
    -- parameter another jump argument has already stored.
    eJoinTargets :: Map Text (Text, [Int], Int),
    -- | The binders of the innermost enclosing case arm per (in-place
    -- 'CVar') scrutinee name — the slot map the 'CReuse' store schedule
    -- reads ('Awsum.Codegen.ReuseSchedule').
    eArmPatternByScrut :: Map Text [Text]
  }

-- ════════════════════════════════════════════════════════════════════════════
-- Unified text+binary emitter for user declarations
-- ════════════════════════════════════════════════════════════════════════════

-- | The static helper name for each prelude built-in (the key in the
-- name→token map). Identity-ish for arithmetic, but several differ.
builtinHelperName :: Map Text Text
builtinHelperName =
  Map.fromList
    [ ("internalStdoutPrint", "__print"),
      ("internalGetArgs", "__getArgs"),
      ("internalStdinReadAllString", "__stdinReadAll"),
      ("internalStdinReadAllBytes", "__stdinReadAllBytes"),
      ("showUInt32", "__showUInt32"),
      ("predInt32", "__predInt32"),
      ("predUInt8", "__predUInt8"),
      ("predUInt32", "__predUInt32"),
      ("succInt32", "__succInt32"),
      ("succUInt8", "__succUInt8"),
      ("succUInt32", "__succUInt32"),
      ("negInt32", "__negInt32"),
      ("eqInt32", "__eqInt32"),
      ("eqUInt8", "__eqUInt8"),
      ("eqUInt32", "__eqUInt32"),
      ("eqString", "__eqString"),
      ("addInt32", "__addInt32"),
      ("addUInt8", "__addUInt8"),
      ("addUInt32", "__addUInt32"),
      ("subInt32", "__subInt32"),
      ("subUInt8", "__subUInt8"),
      ("subUInt32", "__subUInt32"),
      ("mulInt32", "__mulInt32"),
      ("mulUInt8", "__mulUInt8"),
      ("mulUInt32", "__mulUInt32"),
      ("concatString", "__concat"),
      ("splitOnFirst", "__splitOnFirst"),
      ("parseInt32", "__parseInt32"),
      ("parseUInt8", "__parseUInt8"),
      ("parseUInt32", "__parseUInt32"),
      ("lengthCodePoints", "__lengthCodePoints"),
      ("lengthUtf16CodeUnits", "__lengthUtf16CodeUnits"),
      ("lengthUtf8Bytes", "__lengthUtf8Bytes")
    ]

-- | A fresh, method-scoped label name. The counter is the 'State Int'; each
-- method's body is emitted starting from 0 ('declCilMethod'), and labels are
-- resolved per-method by 'assembleCilMethod', so there is no cross-method clash.
freshLabel :: State Int Text
freshLabel = do
  n <- get
  put (n + 1)
  pure ("IL_c" <> show n)

-- | Emitter for the first-order subset of Core. Produces symbolic
-- '[CilInstr]' — operands resolved later by
-- 'assembleCilMethod' (tokens) / 'renderCilMethod' (text); the only effect is
-- fresh-label allocation.
emitExprI :: ECtx -> CExpr -> State Int [CilInstr]
emitExprI ctx = \case
  CString s -> pure [Ldstr s]
  CVar n
    | Just slot <- Map.lookup n ctx.eLocals -> pure [Ldloc slot]
    | Just slot <- Map.lookup n ctx.eParams -> pure [Ldarg slot]
    | n `Set.member` ctx.eValDefs -> pure [CallNamed (mangle n) 0]
    | n `Set.member` ctx.eFunDefs ->
        error ("CLR codegen: first-class function value " <> n <> " — LowerClosures should have eliminated it")
    | otherwise -> pure [Ldnull]
  CBuiltIn _ -> pure [Ldnull]
  CIntLit n _ -> pure [LdcI4 (fromIntegral (fromInteger n :: Int32)), Box int32Ref]
  CCon tag fields -> emitCellI ctx tag fields
  CRow tag v -> emitCellI ctx (fromIntegral tag) [v]
  -- A guarded reuse cannot mutate here (possibly shared cell, no refcount
  -- header on the managed heap) — it lowers as the allocation it replaced;
  -- only a loop-private 'ReuseUnique' pack/continuation mutates in place.
  CReuse ReuseGuarded _ tag fields -> emitCellI ctx tag fields
  CReuse ReuseUnique n tag fields -> emitReuseI ctx n tag fields
  CDrop _ body -> emitExprI ctx body
  CCall f xs -> emitCallI ctx f xs
  CCase scrut alts -> emitCaseI ctx scrut alts
  CRowCase scrut alts -> emitCaseI ctx scrut [(fromIntegral t, [v], b) | (t, v, b) <- alts]
  CProj n slot -> do
    base <- emitExprI ctx (CVar n)
    pure (base <> [CastObjArr, LdcI4 slot, LdelemRef])
  -- Bind: rhs into a scratch local (typed @object@ like every non-zero
  -- slot), body with the binder in scope. Managed heap — no inc, and the
  -- binder's 'CDrop' is a no-op (locals scope out; cf. 'emitTailI').
  CLet x rhs body -> do
    rhsI <- emitExprI ctx rhs
    let slot = ctx.eNextScratch
        ctx' = ctx {eLocals = Map.insert x slot ctx.eLocals, eNextScratch = slot + 1}
    bodyI <- emitExprI ctx' body
    pure (rhsI <> [Stloc slot] <> bodyI)
  CJoin j ps body inner -> emitJoinI ctx j ps body inner
  CJump j _ -> error ("CLR codegen: CJump to " <> j <> " in non-tail position — jumps live only in tail positions of their join's inner expression")
  other -> error ("CLR.Assemble.emitExprI: ungated form " <> show other)

-- | A 'CCon'/'CRow' cell: @object[1+n]@ with the boxed tag at slot 0 and each
-- field at slot i+1. Allocated into a scratch local so the operand stack stays
-- flat regardless of field nesting.
emitCellI :: ECtx -> Int -> [CExpr] -> State Int [CilInstr]
emitCellI ctx tag fields = do
  let nSlots = 1 + length fields
      tmpSlot = ctx.eNextScratch
      ctx' = ctx {eNextScratch = tmpSlot + 1}
  fieldCodes <- forM (zip fields [1 :: Int ..]) $ \(fld, i) -> do
    fc <- emitExprI ctx' fld
    pure ([Ldloc tmpSlot, LdcI4 i] <> fc <> [StelemRef])
  pure
    ( [LdcI4 nSlots, Newarr objectRef, Stloc tmpSlot]
        <> [Ldloc tmpSlot, LdcI4 0, LdcI4 tag, Box int32Ref, StelemRef]
        <> concat fieldCodes
        <> [Ldloc tmpSlot]
    )

-- | The per-arm elision for one case: binders the 'CReuse' store schedule
--   reads straight off the cell. The CLR evaluates any field inline (cases
--   run on a parked operand stack natively), so every extern passes.
clrArmElided :: CExpr -> [Text] -> CExpr -> Set Text
clrArmElided scrut vs b = case scrut of
  CVar nm -> reuseSlotElided (const True) nm vs b
  _ -> Set.empty

-- | Register the matched arm's binders for the scheduled 'CReuse'
--   lowering inside the arm body.
clrArmPatternCtx :: CExpr -> [Text] -> ECtx -> ECtx
clrArmPatternCtx scrut vs c = case scrut of
  CVar nm -> c {eArmPatternByScrut = Map.insert nm vs c.eArmPatternByScrut}
  _ -> c

-- | 'CReuse' — in-place rewrite of the @object[]@ at binder @n@'s slot (Lean-4
-- style cell reuse). Like 'emitCellI' but instead of @newarr@ it loads the
-- binder, @castclass object[]@s it (slots are typed plain @object@), and stashes
-- it; then re-stores the tag and fields in place.
emitReuseI :: ECtx -> Text -> Int -> [CExpr] -> State Int [CilInstr]
emitReuseI ctx n tag fields = do
  let tmpSlot = ctx.eNextScratch
      ctx' = ctx {eNextScratch = tmpSlot + 1}
      loadN = case Map.lookup n ctx.eLocals of
        Just s -> Ldloc s
        Nothing -> case Map.lookup n ctx.eParams of
          Just s -> Ldarg s
          Nothing -> error ("CLR.Assemble.emitReuseI: unknown binder " <> show n)
      armVars = Map.findWithDefault [] n ctx.eArmPatternByScrut
      (stores, _breakers) = scheduleReuse armVars fields
      fieldAt i = fromMaybe (error "CLR: CReuse store schedule slot out of range") (fields !!? (i - 1))
  -- Stores in dependency order ('Awsum.Codegen.ReuseSchedule'): the acyclic
  -- permutation part reads the old slots straight off the cell, a cycle
  -- reads its one extracted binder, unrelated fields evaluate as ever. Arm
  -- extraction skips the binders the schedule reads off the cell.
  storeCodes <- forM stores $ \case
    StoreFromSlot dst src ->
      pure [Ldloc tmpSlot, LdcI4 dst, Ldloc tmpSlot, LdcI4 src, LdelemRef, StelemRef]
    StoreFromBinder dst b ->
      let loadB = case Map.lookup b ctx.eLocals of
            Just s -> Ldloc s
            Nothing -> error ("CLR: CReuse cycle breaker has no extracted slot: " <> show b)
       in pure [Ldloc tmpSlot, LdcI4 dst, loadB, StelemRef]
    StoreExtern dst -> do
      fc <- emitExprI ctx' (fieldAt dst)
      pure ([Ldloc tmpSlot, LdcI4 dst] <> fc <> [StelemRef])
  pure
    ( [loadN, CastObjArr, Stloc tmpSlot]
        <> [Ldloc tmpSlot, LdcI4 0, LdcI4 tag, Box int32Ref, StelemRef]
        <> concat storeCodes
        <> [Ldloc tmpSlot]
    )

-- | A 'CCall': built-ins dispatch to their @__helper@ (or @ToString@ for
-- @show{Int32,UInt8}@); a direct named-function call to @v_name@.
emitCallI :: ECtx -> CExpr -> [CExpr] -> State Int [CilInstr]
emitCallI ctx f xs = case f of
  CBuiltIn name
    | name == "showInt32" || name == "showUInt8",
      [x] <- xs -> do
        cx <- emitExprI ctx x
        pure (cx <> [Callvirt (CilMemberRef objectRef "ToString" True SeString [])])
  -- byteToHexStringNoPrefix: 'String.Format("{0:x2}", boxedByte)' — the "x2"
  -- format renders the boxed Int32 as two lowercase zero-padded hex digits.
  CBuiltIn "byteToHexStringNoPrefix"
    | [x] <- xs -> do
        cx <- emitExprI ctx x
        pure ([Ldstr "{0:x2}"] <> cx <> [Call (CilMemberRef strRef "Format" False SeString [SeString, SeObject])])
  CBuiltIn name
    | Just helper <- Map.lookup name builtinHelperName -> do
        argCodes <- traverse (emitExprI ctx) xs
        pure (concat argCodes <> [CallNamed helper (length xs)])
  CBuiltIn n ->
    error ("CLR codegen: unknown builtin '" <> n <> "' reached emitExprI")
  CVar n
    | n `Set.member` ctx.eFunDefs -> do
        argCodes <- traverse (emitExprI ctx) xs
        pure (concat argCodes <> [CallNamed (mangle n) (length xs)])
  _ -> error "CLR.Assemble.emitExprI: first-class call reached (should be gated)"

-- | The in-place load of a case scrutinee that is already a named local or
-- parameter: load + @castclass object[]@, the same shape as 'CProj'. 'Nothing'
-- for anything that needs evaluation into the scratch slot — calls,
-- constructions, and a 'CVar' naming a 'CValDef' (a getter call returning a
-- fresh cell each time).
scrutInPlaceLoad :: ECtx -> CExpr -> Maybe [CilInstr]
scrutInPlaceLoad ctx = \case
  CVar n
    | Just slot <- Map.lookup n ctx.eLocals -> Just [Ldloc slot, CastObjArr]
    | Just slot <- Map.lookup n ctx.eParams -> Just [Ldarg slot, CastObjArr]
    | n `Set.member` ctx.eValDefs || n `Set.member` ctx.eFunDefs -> Nothing
    | otherwise -> error ("CLR.Assemble: case scrutinee names unknown binder: " <> show n)
  _ -> Nothing

-- | Dispatch head of a case: the head instructions (ending with the unboxed
-- tag on the stack), the per-read scrutinee-array load for arm bindings, and
-- the first free slot for those bindings. An in-place scrutinee
-- ('scrutInPlaceLoad') is re-loaded per read and consumes no scratch slot;
-- anything else evaluates once into @arrSlot@. Whichever slots this takes are
-- counted off the emitted stream by 'maxLocalsOf' — no separate sizing to keep
-- in step.
scrutDispatchI :: ECtx -> CExpr -> State Int ([CilInstr], [CilInstr], Int)
scrutDispatchI ctx scrut = case scrutInPlaceLoad ctx scrut of
  Just load -> pure (load <> [LdcI4 0, LdelemRef, UnboxAny int32Ref], load, ctx.eNextScratch)
  Nothing -> do
    scrutI <- emitExprI ctx scrut
    let arrSlot = ctx.eNextScratch
    pure (scrutI <> [Stloc arrSlot, Ldloc arrSlot, LdcI4 0, LdelemRef, UnboxAny int32Ref], [Ldloc arrSlot], arrSlot + 1)

-- | Non-tail 'CCase' dispatch (the binary if-chain, not the text's switch).
-- Resolve the dispatch head ('scrutDispatchI'), extract the boxed tag, and
-- walk a dup/bne.un chain:
-- each non-final arm pops the tag, binds its fields, runs its body, and jumps
-- to the join; the final arm pops and runs, falling through to the join. Every
-- arm leaves its result on the stack, so the join is entered at depth 1+.
emitCaseI :: ECtx -> CExpr -> [(Int, [Text], CExpr)] -> State Int [CilInstr]
emitCaseI ctx scrut alts = do
  (headCode, loadScrut, bindSlotStart) <- scrutDispatchI ctx scrut
  let sorted = sortWith (\(t, _, _) -> t) alts
      nextScratch' = bindSlotStart + foldl' max 0 [length vs | (_, vs, _) <- sorted]
      emitArm vars body = do
        let bindings = zip vars [bindSlotStart ..]
            elided = clrArmElided scrut vars body
            bindCode = concat [loadScrut <> [LdcI4 i, LdelemRef, Stloc slot] | ((v, slot), i) <- zip bindings [1 :: Int ..], binderUsedIn v body, not (Set.member v elided)]
            ctx' = clrArmPatternCtx scrut vars (ctx {eLocals = foldl' (\m (v, s) -> Map.insert v s m) ctx.eLocals bindings, eNextScratch = nextScratch'})
        bodyCode <- emitExprI ctx' body
        pure (bindCode <> bodyCode)
  joinLbl <- freshLabel
  let buildChain [] = pure [Ldnull]
      buildChain [(_, vars, body)] = do
        armCode <- emitArm vars body
        pure (Pop : armCode)
      buildChain ((tag, vars, body) : rest) = do
        armCode <- emitArm vars body
        nextLbl <- freshLabel
        restCode <- buildChain rest
        pure
          ( [Dup, LdcI4 tag, BneUn (LabelId nextLbl), Pop]
              <> armCode
              <> [Br (LabelId joinLbl), Label (LabelId nextLbl)]
              <> restCode
          )
  chain <- buildChain sorted
  pure (headCode <> chain <> [Label (LabelId joinLbl)])

-- | Expression-position 'CJoin' (a non-loop method body, a 'CValDef'
-- right-hand side, or any nested value position — the operand stack is
-- whatever the context left there; CIL labels only need each /incoming
-- edge/ to agree, and all of this construct's edges sit on top of the
-- context's stack). Layout is flat: the inner expression's value arms push
-- their result and @br@ the after label, its jump arms store the join
-- parameters and @br@ the body label; the body (an ordinary 'emitExprI'
-- value) sits between the two labels and falls through to the after label —
-- entered at depth 1 from every edge, the same merge shape as
-- 'emitCaseI''s join.
--
-- The parameter slots are reserved at the node (the scratch counter
-- advances past them for everything inside), and a jump's arguments
-- evaluate one at a time straight into them — the parameters are in scope
-- only inside the body, so no argument can read them and the 'CContinue'
-- reverse-@starg@ two-step is unnecessary. Jumps appear only at arm roots
-- of the inner case (under the 'CDrop' wrappers 'Awsum.Lifetime' adds —
-- transparent here, managed heap; the case itself may sit under 'CLet'
-- bindings floated out of its scrutinee): anything deeper is a jump in
-- non-tail position, which the node's invariant excludes and the
-- 'emitExprI' arm rejects loudly.
emitJoinI :: ECtx -> Text -> [Text] -> CExpr -> CExpr -> State Int [CilInstr]
emitJoinI ctx j ps body inner = do
  bodyLbl <- freshLabel
  afterLbl <- freshLabel
  let psSlots = [ctx.eNextScratch .. ctx.eNextScratch + length ps - 1]
      ctxIn = ctx {eNextScratch = ctx.eNextScratch + length ps}
      ctxJ = ctxIn {eJoinTargets = Map.insert j (bodyLbl, psSlots, 0) ctxIn.eJoinTargets}
      ctxB = ctxIn {eLocals = foldl' (\m (p, s) -> Map.insert p s m) ctxIn.eLocals (zip ps psSlots)}
  innerI <- goInner ctxJ afterLbl inner
  bodyI <- emitExprI ctxB body
  pure (innerI <> [Label (LabelId bodyLbl)] <> bodyI <> [Label (LabelId afterLbl)])
  where
    -- The inner expression: a case — possibly under 'CLet' bindings floated
    -- out of its scrutinee and the 'CDrop' wrappers 'Awsum.Lifetime' places
    -- around those binders (transparent here, managed heap) — whose arms
    -- either jump or produce bypass values; or a degenerate root (the
    -- dispatch collapsed away after the fusion), which takes the same two
    -- routes without the chain.
    goInner :: ECtx -> Text -> CExpr -> State Int [CilInstr]
    goInner ctxJ afterLbl = \case
      CLet x rhs b -> do
        rhsI <- emitExprI ctxJ rhs
        let slot = ctxJ.eNextScratch
            ctx' = ctxJ {eLocals = Map.insert x slot ctxJ.eLocals, eNextScratch = slot + 1}
        bodyI <- goInner ctx' afterLbl b
        pure (rhsI <> [Stloc slot] <> bodyI)
      CDrop _ b -> goInner ctxJ afterLbl b
      CCase scrut alts -> goInnerCase ctxJ afterLbl scrut alts
      CRowCase scrut alts ->
        goInnerCase ctxJ afterLbl scrut [(fromIntegral t, [v], b) | (t, v, b) <- alts]
      other -> armRoute ctxJ afterLbl other
    -- The dispatch chain of the inner case: the same dup/bne.un ladder as
    -- 'emitCaseI', except every arm ends in its own @br@ (value → after,
    -- jump → body), so there is no fall-through join.
    goInnerCase :: ECtx -> Text -> CExpr -> [(Int, [Text], CExpr)] -> State Int [CilInstr]
    goInnerCase ctxJ afterLbl scrut alts = do
      (headCode, loadScrut, bindSlotStart) <- scrutDispatchI ctxJ scrut
      let sorted = sortWith (\(t, _, _) -> t) alts
          nextScratch' = bindSlotStart + foldl' max 0 [length vs | (_, vs, _) <- sorted]
          emitArm vars b = do
            let bindings = zip vars [bindSlotStart ..]
                elided = clrArmElided scrut vars b
                bindCode = concat [loadScrut <> [LdcI4 i, LdelemRef, Stloc slot] | ((v, slot), i) <- zip bindings [1 :: Int ..], binderUsedIn v b, not (Set.member v elided)]
                ctx' = clrArmPatternCtx scrut vars (ctxJ {eLocals = foldl' (\m (v, s) -> Map.insert v s m) ctxJ.eLocals bindings, eNextScratch = nextScratch'})
            routeI <- armRoute ctx' afterLbl b
            pure (bindCode <> routeI)
          buildChain [] = pure [Ldnull, Br (LabelId afterLbl)]
          buildChain [(_, vars, b)] = (Pop :) <$> emitArm vars b
          buildChain ((tag, vars, b) : rest) = do
            armCode <- emitArm vars b
            nextLbl <- freshLabel
            restCode <- buildChain rest
            pure
              ( [Dup, LdcI4 tag, BneUn (LabelId nextLbl), Pop]
                  <> armCode
                  <> [Label (LabelId nextLbl)]
                  <> restCode
              )
      chain <- buildChain sorted
      pure (headCode <> chain)
    -- One inner-arm body: a jump (under its transparent drop wrappers)
    -- stores its arguments and branches to the join body; anything else is
    -- an ordinary value that branches to the after label.
    armRoute :: ECtx -> Text -> CExpr -> State Int [CilInstr]
    armRoute ctxA afterLbl b0 = case peelDrops b0 of
      CJump j' args
        | Just (lbl, slots, _) <- Map.lookup j' ctxA.eJoinTargets -> do
            argStores <- forM (zip args slots) $ \(a, s) -> do
              ai <- emitExprI ctxA a
              pure (ai <> [Stloc s])
            pure (concat argStores <> [Br (LabelId lbl)])
      CJump j' _ -> error ("CLR codegen: CJump to unknown join " <> j' <> " (pipeline bug)")
      _ -> do
        valI <- emitExprI ctxA b0
        pure (valI <> [Br (LabelId afterLbl)])
    peelDrops :: CExpr -> CExpr
    peelDrops = \case
      CDrop _ b -> peelDrops b
      e -> e

-- | Tail-position emitter for a 'CLoop' body. The loop head is @loopLbl@
-- (placed at the method start by 'declCilMethod'); 'CContinue' evaluates the
-- new args, drains drops for binders it does not rebind (@ldnull; starg@), rebinds the
-- parameters with @starg@ in reverse (stack is LIFO), and @br@s back to the
-- head. Tail values end in @ret@; a tail 'CCase' dispatches like the non-tail
-- one but each arm self-terminates (recursive tail emit) — no join. @pending@
-- is the buffered list of dropped parameter names, drained at each terminator.
emitTailI :: ECtx -> [Text] -> Text -> CExpr -> State Int [CilInstr]
emitTailI baseCtx params loopLbl = go baseCtx []
  where
    drainDrops :: ECtx -> [Text] -> [CilInstr]
    drainDrops ctx pending = concat [[Ldnull, Starg s] | n <- pending, Just s <- [Map.lookup n ctx.eParams]]
    go :: ECtx -> [Text] -> CExpr -> State Int [CilInstr]
    go ctx pending = \case
      CContinue newArgs -> do
        argCodes <- traverse (emitExprI ctx) newArgs
        let paramSlots = [fromMaybe (error ("CLR.Assemble.emitTailI: no arg slot for " <> show p)) (Map.lookup p ctx.eParams) | p <- params]
            stargs = concatMap (\s -> [Starg s]) (reverse paramSlots)
            -- A param this 'CContinue' rebinds needs no null-out: the
            -- 'starg' overwrites the slot with nothing allocating in
            -- between, so its old graph is already unreachable on the next
            -- iteration. Drops on binders not rebound here still drain.
            dropsNotRebound = filter (`notElem` params) pending
        pure (concat argCodes <> drainDrops ctx dropsNotRebound <> stargs <> [Br (LabelId loopLbl)])
      CCase scrut alts -> tailCase ctx pending scrut alts
      CRowCase scrut alts -> tailCase ctx pending scrut [(fromIntegral t, [v], b) | (t, v, b) <- alts]
      CDrop n body -> go ctx (n : pending) body
      CLet x rhs body -> do
        rhsI <- emitExprI ctx rhs
        let slot = ctx.eNextScratch
            ctx' = ctx {eLocals = Map.insert x slot ctx.eLocals, eNextScratch = slot + 1}
        bodyCode <- go ctx' pending body
        pure (rhsI <> [Stloc slot] <> bodyCode)
      -- Native join point: the inner expression continues the tail walk with
      -- the target registered (its jumps store the parameter slots and @br@
      -- the body label; its value tails @ret@ and its 'CContinue' arms @br@
      -- the loop head, both past the body); the body follows the label with
      -- the parameters in scope. The parameter slots are reserved at the
      -- node — the scratch counter advances past them for everything inside.
      -- Whatever was pending at the node stays pending for the body: those
      -- binders wrap the whole join and die at its terminals.
      CJoin j ps body inner -> do
        bodyLbl <- freshLabel
        let psSlots = [ctx.eNextScratch .. ctx.eNextScratch + length ps - 1]
            ctxIn = ctx {eNextScratch = ctx.eNextScratch + length ps}
            ctxJ = ctxIn {eJoinTargets = Map.insert j (bodyLbl, psSlots, length pending) ctxIn.eJoinTargets}
            ctxB = ctxIn {eLocals = foldl' (\m (p, s) -> Map.insert p s m) ctxIn.eLocals (zip ps psSlots)}
        innerI <- go ctxJ pending inner
        bodyI <- go ctxB pending body
        pure (innerI <> [Label (LabelId bodyLbl)] <> bodyI)
      -- Mirror of 'CContinue', branching forward: evaluate each argument
      -- straight into its parameter slot (the parameters are not in scope
      -- inside the inner expression, so no argument can read them — no
      -- reverse-@starg@ two-step), drain the parameter drops accumulated
      -- since the node (the jumping arm's deaths; the body still runs, so
      -- they would stay GC roots through it), and @br@ the body label. The
      -- base pending stays for the body's own terminals.
      CJump j args
        | Just (lbl, slots, base) <- Map.lookup j ctx.eJoinTargets -> do
            argStores <- forM (zip args slots) $ \(a, s) -> do
              ai <- emitExprI ctx a
              pure (ai <> [Stloc s])
            let delta = take (length pending - base) pending
            pure (concat argStores <> drainDrops ctx delta <> [Br (LabelId lbl)])
      CJump j _ -> error ("CLR codegen: CJump to unknown join " <> j <> " (pipeline bug)")
      other -> do
        code <- emitExprI ctx other
        pure (code <> drainDrops ctx pending <> [Ret])
    tailCase :: ECtx -> [Text] -> CExpr -> [(Int, [Text], CExpr)] -> State Int [CilInstr]
    tailCase ctx pending scrut alts = do
      (headCode, loadScrut, bindSlotStart) <- scrutDispatchI ctx scrut
      let sorted = sortWith (\(t, _, _) -> t) alts
          nextScratch' = bindSlotStart + foldl' max 0 [length vs | (_, vs, _) <- sorted]
          armTail vars body = do
            let bindings = zip vars [bindSlotStart ..]
                elided = clrArmElided scrut vars body
                bindCode = concat [loadScrut <> [LdcI4 i, LdelemRef, Stloc slot] | ((v, slot), i) <- zip bindings [1 :: Int ..], binderUsedIn v body, not (Set.member v elided)]
                ctx' = clrArmPatternCtx scrut vars (ctx {eLocals = foldl' (\m (v, s) -> Map.insert v s m) ctx.eLocals bindings, eNextScratch = nextScratch'})
            tc <- go ctx' pending body
            pure (bindCode <> tc)
          buildChain [] = pure [Ldnull, Ret]
          buildChain [(_, vars, body)] = (Pop :) <$> armTail vars body
          buildChain ((tag, vars, body) : rest) = do
            at <- armTail vars body
            nextLbl <- freshLabel
            rc <- buildChain rest
            pure ([Dup, LdcI4 tag, BneUn (LabelId nextLbl), Pop] <> at <> [Label (LabelId nextLbl)] <> rc)
      chain <- buildChain sorted
      pure (headCode <> chain)

-- | Lower a first-order 'CDecl' to a 'CilMethod' (the value both
-- projections consume). Pure: all operands stay symbolic; the only state is the
-- per-method fresh-label counter (started at 0). Locals layout — slot 0 is
-- @object[]@ (the 'CCon' scratch), the rest @object@.
declCilMethod :: ECtx -> CDecl -> CilMethod
declCilMethod baseCtx = \case
  CFunDef nm args (CLoop body) ->
    let ctx = baseCtx {eParams = Map.fromList (zip args [0 ..]), eLocals = Map.empty, eNextScratch = 0}
        loopLbl = "IL_tco_loop" :: Text
        -- Loop head at the start; tail arms/values self-terminate, so no
        -- trailing Ret.
        instrs = Label (LabelId loopLbl) : evalState (emitTailI ctx args loopLbl body) 0
     in CilMethod
          { cmName = mangle nm,
            cmRet = SeObject,
            cmParams = replicate (length args) SeObject,
            cmLocals = userLocals (maxLocalsOf instrs),
            cmBody = instrs
          }
  CFunDef nm args body ->
    let ctx = baseCtx {eParams = Map.fromList (zip args [0 ..]), eLocals = Map.empty, eNextScratch = 0}
        instrs = evalState (emitExprI ctx body) 0 <> [Ret]
     in CilMethod
          { cmName = mangle nm,
            cmRet = SeObject,
            cmParams = replicate (length args) SeObject,
            cmLocals = userLocals (maxLocalsOf instrs),
            cmBody = instrs
          }
  CValDef nm rhs ->
    let ctx = baseCtx {eParams = Map.empty, eLocals = Map.empty, eNextScratch = 0}
        instrs = evalState (emitExprI ctx rhs) 0 <> [Ret]
     in CilMethod
          { cmName = mangle nm,
            cmRet = SeObject,
            cmParams = [],
            cmLocals = userLocals (maxLocalsOf instrs),
            cmBody = instrs
          }
  where
    -- @.locals@ count read back off the emitted stream ('maxLocalsOf'), so it
    -- cannot disagree with the slots the emitter assigned. Slot 0 is the
    -- @object[]@ scratch (cells / case scrutinee); the rest are @object@.
    userLocals n
      | n <= 0 = []
      | otherwise = SeSZArray SeObject : replicate (n - 1) SeObject

-- ════════════════════════════════════════════════════════════════════════════
-- Method body encoding
-- ════════════════════════════════════════════════════════════════════════════

-- | Encode method body with CIL tiny or fat header.
-- Tiny header (1 byte) implies @MaxStack = 8@ — we only pick it when
-- the method is short and has no locals, in which case we have already
-- verified the actual stack depth fits. The fat header (12 bytes)
-- carries an explicit @MaxStack@; we emit the per-method value passed
-- in @maxStack@. It must be ≥ the method's true stack peak, or the runtime
-- rejects the method with @System.InvalidProgramException@ — see
-- ECMA-335 §II.25.4.3.
encodeBody :: Word32 -> Word16 -> [Word8] -> [Word8]
encodeBody localSigTok maxStack code
  | len < 64 && localSigTok == 0 && maxStack <= 8 = fromIntegral ((len `shiftL` 2) .|. 0x02) : code -- tiny
  | otherwise =
      let flags = if localSigTok /= 0 then 0x3013 else 0x3003 -- 0x0010 = InitLocals
       in w16le flags <> w16le maxStack <> w32le (fromIntegral len) <> w32le localSigTok <> code -- fat
  where
    len = length code

-- | Lay out method bodies after CLI header. Returns (list of RVA, all body bytes, end offset).
layoutBodies :: [MInfo] -> ([Word32], [Word8], Int)
layoutBodies = go peCliHdrSize [] []
  where
    go off rvas bytes [] = (reverse rvas, concat (reverse bytes), off)
    go off rvas bytes (m : ms) =
      let code = m.mCode
          hasFat = length code >= 64 || m.mLocalSigTok /= 0 || m.mMaxStack > 8
          off' = if hasFat then align4 off else off
          pad = replicate (off' - off) 0x00
          body = encodeBody m.mLocalSigTok m.mMaxStack code
          rva = fromIntegral peTextRVA + fromIntegral off'
       in go (off' + length body) (rva : rvas) ((pad <> body) : bytes) ms

-- ════════════════════════════════════════════════════════════════════════════
-- PE file serialization
-- ════════════════════════════════════════════════════════════════════════════

buildPE :: Pool -> [MInfo] -> B.Builder
buildPE st methods =
  let (methodRVAs, bodyBytes, bodyEndOff) = layoutBodies methods
      metaOff = align4 bodyEndOff
      metaBytes = buildMetadata st methods methodRVAs
      metaLen = length metaBytes
      metaRVA = fromIntegral (peTextRVA + metaOff)
      textContentLen = metaOff + metaLen
      textRawSize = alignToN peFileAlign textContentLen
      textVirtSize = textContentLen
      imageSize = peTextRVA + alignToN peSectAlign textVirtSize
      entryTok = tokMD (fromIntegral (length methods))
      headersLen :: Int
      headersLen = 128 + 4 + 20 + 224 + 40 -- = 416
      headerPad = peFileAlign - headersLen
      bodyToMetaPad = metaOff - bodyEndOff
      sectionEndPad = textRawSize - textContentLen
   in mconcat
        [ -- DOS Header (128 bytes)
          B.byteString $ BS.pack $ [0x4D, 0x5A] <> replicate 58 0 <> w32le 0x80 <> replicate 64 0,
          -- PE Signature (4 bytes)
          B.byteString $ BS.pack [0x50, 0x45, 0x00, 0x00],
          -- COFF Header (20 bytes)
          bsCOFF,
          -- Optional Header (224 bytes)
          bsOptional (fromIntegral textRawSize) (fromIntegral imageSize),
          -- .text section header (40 bytes)
          bsSectHdr (fromIntegral textVirtSize) (fromIntegral textRawSize),
          -- Padding to FileAlignment
          B.byteString (BS.replicate headerPad 0),
          -- CLI Header (72 bytes)
          bsCliHdr metaRVA (fromIntegral metaLen) entryTok,
          -- Method bodies
          B.byteString (BS.pack bodyBytes),
          -- Alignment padding to metadata
          B.byteString (BS.replicate bodyToMetaPad 0),
          -- Metadata
          B.byteString (BS.pack metaBytes),
          -- Padding to fill raw section
          B.byteString (BS.replicate sectionEndPad 0)
        ]

-- ════════════════════════════════════════════════════════════════════════════
-- PE header builders
-- ════════════════════════════════════════════════════════════════════════════

bsCOFF :: B.Builder
bsCOFF =
  B.byteString
    $ BS.pack
    $ concat
      [ w16le 0x014C, -- Machine: I386
        w16le 1, -- NumberOfSections
        w32le 0, -- TimeDateStamp
        w32le 0, -- PointerToSymbolTable
        w32le 0, -- NumberOfSymbols
        w16le 0xE0, -- SizeOfOptionalHeader (224)
        w16le 0x2102 -- Characteristics: EXECUTABLE_IMAGE | 32BIT_MACHINE | DLL
      ]

bsOptional :: Word32 -> Word32 -> B.Builder
bsOptional sizeOfCode sizeOfImage =
  B.byteString
    $ BS.pack
    $ concat
      [ -- Standard fields (28 bytes)
        w16le 0x010B, -- Magic: PE32
        [0x06, 0x00], -- LinkerVersion
        w32le sizeOfCode,
        w32le 0, -- SizeOfInitializedData
        w32le 0, -- SizeOfUninitializedData
        w32le 0, -- AddressOfEntryPoint (0 for managed)
        w32le (fromIntegral peTextRVA), -- BaseOfCode
        w32le 0, -- BaseOfData
        -- Windows-specific fields (68 bytes)
        w32le 0x00400000, -- ImageBase
        w32le (fromIntegral peSectAlign),
        w32le (fromIntegral peFileAlign),
        w16le 4,
        w16le 0, -- OS Version
        w16le 0,
        w16le 0, -- Image Version
        w16le 6,
        w16le 0, -- Subsystem Version
        w32le 0, -- Win32VersionValue
        w32le sizeOfImage,
        w32le (fromIntegral peFileAlign), -- SizeOfHeaders
        w32le 0, -- CheckSum
        w16le 3, -- Subsystem: CONSOLE
        w16le 0x8540, -- DllCharacteristics
        w32le 0x00100000, -- SizeOfStackReserve
        w32le 0x00001000, -- SizeOfStackCommit
        w32le 0x00100000, -- SizeOfHeapReserve
        w32le 0x00001000, -- SizeOfHeapCommit
        w32le 0, -- LoaderFlags
        w32le 16, -- NumberOfRvaAndSizes
        -- Data directories: 14 entries of zeros, then CLI Runtime Header, then zeros
        replicate (14 * 8) 0,
        w32le (fromIntegral peTextRVA), -- Entry 14 RVA: CLI header
        w32le (fromIntegral peCliHdrSize), -- Entry 14 Size
        w32le 0,
        w32le 0 -- Entry 15
      ]

bsSectHdr :: Word32 -> Word32 -> B.Builder
bsSectHdr virtSize rawSize =
  B.byteString
    $ BS.pack
    $ concat
      [ [0x2E, 0x74, 0x65, 0x78, 0x74, 0x00, 0x00, 0x00], -- ".text"
        w32le virtSize,
        w32le (fromIntegral peTextRVA),
        w32le rawSize,
        w32le (fromIntegral peTextFileOff),
        w32le 0, -- PointerToRelocations
        w32le 0, -- PointerToLineNumbers
        w16le 0, -- NumberOfRelocations
        w16le 0, -- NumberOfLineNumbers
        w32le 0x60000020 -- CODE | EXECUTE | READ
      ]

bsCliHdr :: Word32 -> Word32 -> Word32 -> B.Builder
bsCliHdr metaRVA metaSize entryTok =
  B.byteString
    $ BS.pack
    $ concat
      [ w32le (fromIntegral peCliHdrSize), -- cb
        w16le 2,
        w16le 5, -- RuntimeVersion 2.5
        w32le metaRVA,
        w32le metaSize,
        w32le 1, -- Flags: COMIMAGE_FLAGS_ILONLY
        w32le entryTok,
        replicate 48 0 -- Resources thru ManagedNativeHeader (6×8)
      ]

-- ════════════════════════════════════════════════════════════════════════════
-- Metadata serialization
-- ════════════════════════════════════════════════════════════════════════════

buildMetadata :: Pool -> [MInfo] -> [Word32] -> [Word8]
buildMetadata st methods methodRVAs =
  let -- Build streams
      tablesData = buildTables st methods methodRVAs
      stringsData = padTo4 st.pStr
      usData = padTo4 st.pUS
      guidData :: [Word8]
      guidData = replicate 16 0 -- fixed zero GUID
      blobData = padTo4 st.pBlob

      -- Stream header name bytes (padded to 4)
      nmTbl = padTo4 [0x23, 0x7E, 0x00] -- "#~"
      nmStr = padTo4 $ BS.unpack (encodeUtf8 @Text "#Strings") <> [0x00]
      nmUS = padTo4 [0x23, 0x55, 0x53, 0x00] -- "#US"
      nmGUID = padTo4 $ BS.unpack (encodeUtf8 @Text "#GUID") <> [0x00]
      nmBlob = padTo4 $ BS.unpack (encodeUtf8 @Text "#Blob") <> [0x00]

      -- Stream header sizes: 4(offset) + 4(size) + name
      shLen nm = 8 + length nm
      shTotal = shLen nmTbl + shLen nmStr + shLen nmUS + shLen nmGUID + shLen nmBlob

      -- Metadata root header: 32 bytes (fixed)
      rootHdrLen :: Int
      rootHdrLen = 32

      -- Stream data offsets (relative to metadata root)
      dataStart = rootHdrLen + shTotal
      tblOff = dataStart
      strOff = tblOff + length tablesData
      usOff = strOff + length stringsData
      guidOff = usOff + length usData
      blobOff = guidOff + length guidData

      -- Root header
      rootHdr =
        [0x42, 0x53, 0x4A, 0x42] -- "BSJB"
          <> w16le 1
          <> w16le 1 -- version 1.1
          <> w32le 0 -- reserved
          <> w32le 12 -- version string length
          <> BS.unpack (encodeUtf8 @Text "v4.0.30319")
          <> [0x00, 0x00] -- padded to 12
          <> w16le 0 -- flags
          <> w16le 5 -- number of streams

      -- Stream headers
      sh off' sz nm = w32le (fromIntegral off') <> w32le (fromIntegral sz) <> nm
      streamHdrs =
        sh tblOff (length tablesData) nmTbl
          <> sh strOff (length stringsData) nmStr
          <> sh usOff (length usData) nmUS
          <> sh guidOff (length guidData) nmGUID
          <> sh blobOff (length blobData) nmBlob
   in rootHdr <> streamHdrs <> tablesData <> stringsData <> usData <> guidData <> blobData

-- ════════════════════════════════════════════════════════════════════════════
-- #~ stream (metadata tables)
-- ════════════════════════════════════════════════════════════════════════════

-- | ECMA-335 §II.24.2.6 metadata index widths, in bytes (2 or 4). A heap index
--   widens once that heap exceeds 0xFFFF bytes (and the bit is recorded in
--   'mwHeapSizes', the @#~@ HeapSizes byte); a simple table index widens once
--   the target table reaches 2^16 rows; a coded index of @k@ tag bits widens
--   once the largest table it can reference reaches 2^(16−k) rows. The widths
--   are otherwise hard-coded to 2 bytes, which silently corrupts a @.dll@ whose
--   #Strings heap (or a table) outgrows 16-bit indices.
data MetaWidths = MetaWidths
  { mwStr :: Int, -- #Strings heap index
    mwGuid :: Int, -- #GUID heap index
    mwBlob :: Int, -- #Blob heap index
    mwHeapSizes :: Word8, -- the #~ HeapSizes byte (bit0 #Strings, bit1 #GUID, bit2 #Blob)
    mwField :: Int, -- simple index into Field
    mwMethodDef :: Int, -- simple index into MethodDef
    mwParam :: Int, -- simple index into Param
    mwResScope :: Int, -- coded ResolutionScope (2 tag bits)
    mwTdor :: Int, -- coded TypeDefOrRef (2 tag bits)
    mwMrp :: Int -- coded MemberRefParent (3 tag bits)
  }
  deriving stock (Eq, Show)

-- | Derive the index widths from the final heap sizes (in bytes, as written in
--   the stream headers) and table row counts. Pure and total so the boundary
--   values can be pinned by a unit test.
clrMetaWidths :: Int -> Int -> Int -> Word32 -> Word32 -> Word32 -> Word32 -> MetaWidths
clrMetaWidths strBytes guidBytes blobBytes nTR nMD nPM nTS =
  let heapW n = if n > 0xFFFF then 4 else 2
      simpleW rows = if rows >= (0x10000 :: Word32) then 4 else 2
      codedW tagBits rows = if foldr max 0 rows >= ((0x10000 :: Word32) `shiftR` tagBits) then 4 else 2
      strW = heapW strBytes
      guidW = heapW guidBytes
      blobW = heapW blobBytes
   in MetaWidths
        { mwStr = strW,
          mwGuid = guidW,
          mwBlob = blobW,
          mwHeapSizes =
            (if strW == 4 then 0x01 else 0)
              .|. (if guidW == 4 then 0x02 else 0)
              .|. (if blobW == 4 then 0x04 else 0),
          mwField = simpleW 0, -- the Field table is empty
          mwMethodDef = simpleW nMD,
          mwParam = simpleW nPM,
          mwResScope = codedW 2 [1, 0, 2, nTR], -- Module, ModuleRef, AssemblyRef, TypeRef
          mwTdor = codedW 2 [2, nTR, nTS], -- TypeDef, TypeRef, TypeSpec
          mwMrp = codedW 3 [2, nTR, 0, nMD, nTS] -- TypeDef, TypeRef, ModuleRef, MethodDef, TypeSpec
        }

buildTables :: Pool -> [MInfo] -> [Word32] -> [Word8]
buildTables st methods methodRVAs =
  let nTR = st.pTRn
      nMD = fromIntegral (length methods) :: Word32
      nPM = st.pPMn
      nMR = st.pMRn
      nTS = st.pTSn
      nSAS = st.pSASn
      hasTS = nTS > 0
      hasSAS = nSAS > 0

      -- Index widths from the final heaps + row counts. Heap sizes are the
      -- padded stream sizes ('align4' of the heap byte length, which equals the
      -- offset cursor), i.e. exactly the Size values written in the stream
      -- headers — so the width a reader derives from those Sizes matches ours.
      ws = clrMetaWidths (align4 (fromIntegral st.pStrOff)) 16 (align4 (fromIntegral st.pBlobOff)) nTR nMD nPM nTS
      strW = ws.mwStr
      guidW = ws.mwGuid
      blobW = ws.mwBlob
      tdorW = ws.mwTdor
      rsW = ws.mwResScope
      mrpW = ws.mwMrp
      fieldW = ws.mwField
      methodW = ws.mwMethodDef
      paramW = ws.mwParam
      -- Emit a heap / table / coded index at its computed byte width.
      ix width v = if width == 4 then w32le v else w16le (fromIntegral v)

      valid :: Word64
      valid =
        0x01 -- Module
          .|. 0x02 -- TypeRef
          .|. 0x04 -- TypeDef
          .|. 0x40 -- MethodDef
          .|. 0x100 -- Param
          .|. 0x400 -- MemberRef
          .|. (if hasSAS then 0x20000 else 0) -- StandAloneSig (table 0x11)
          .|. (if hasTS then 0x08000000 else 0) -- TypeSpec
          .|. 0x100000000 -- Assembly
          .|. 0x800000000 -- AssemblyRef
      rowCounts =
        w32le 1 -- Module
          <> w32le nTR
          <> w32le 2 -- TypeDef
          <> w32le nMD
          <> w32le nPM
          <> w32le nMR
          <> (if hasSAS then w32le nSAS else [])
          <> (if hasTS then w32le nTS else [])
          <> w32le 1 -- Assembly
          <> w32le 2 -- AssemblyRef
      hdr =
        w32le 0 -- Reserved
          <> [2, 0] -- MajorVersion, MinorVersion
          <> [ws.mwHeapSizes] -- HeapSizes: per-heap index width (0x01 #Strings, 0x02 #GUID, 0x04 #Blob)
          <> [1] -- Reserved
          <> w64le valid
          <> w64le 0 -- Sorted

      -- Module row
      moduleRow =
        w16le 0 -- Generation
          <> ix strW (lkStr st "AwsumMain.dll") -- Name
          <> ix guidW 1 -- Mvid (GUID index)
          <> ix guidW 0 -- EncId
          <> ix guidW 0 -- EncBaseId

      -- TypeDef rows
      typeDefRows =
        -- <Module>
        w32le 0 -- Flags
          <> ix strW (lkStr st "<Module>") -- Name
          <> ix strW 0 -- Namespace
          <> ix tdorW 0 -- Extends (null)
          <> ix fieldW 1 -- FieldList
          <> ix methodW 1 -- MethodList
          -- AwsumMain
          <> w32le 0x00100001 -- Flags
          <> ix strW (lkStr st "AwsumMain") -- Name
          <> ix strW 0 -- Namespace
          <> ix tdorW (tdorTR 1) -- Extends System.Object (TypeRef row 1)
          <> ix fieldW 1 -- FieldList
          <> ix methodW 1 -- MethodList

      -- MethodDef rows
      mkMDRow rva m =
        w32le rva -- RVA
          <> w16le m.mImplFlags
          <> w16le m.mFlags
          <> ix strW m.mName -- Name
          <> ix blobW m.mSig -- Signature
          <> ix paramW m.mParamList -- ParamList
      methodDefRows = concat [mkMDRow rva m | (rva, m) <- zip methodRVAs methods]

      -- Param rows: flags / sequence (fixed 2-byte) + Name (#Strings)
      paramRows = concatMap (\(f, s, n) -> w16le f <> w16le s <> ix strW n) st.pPM

      -- TypeRef rows: ResolutionScope (coded) + Name + Namespace
      typeRefRows = concatMap (\(rs, n, ns) -> ix rsW rs <> ix strW n <> ix strW ns) st.pTR

      -- MemberRef rows: Class (coded) + Name + Signature (#Blob)
      memberRefRows = concatMap (\(c, n, s) -> ix mrpW c <> ix strW n <> ix blobW s) st.pMR

      -- StandAloneSig rows (table 0x11): Signature (#Blob)
      standAloneSigRows = if hasSAS then concatMap (ix blobW) st.pSAS else []

      -- TypeSpec rows: Signature (#Blob)
      typeSpecRows = if hasTS then concatMap (ix blobW) st.pTS else []

      -- Assembly row
      assemblyRow =
        w32le 0x8004 -- HashAlgId: SHA1
          <> w16le 0
          <> w16le 0
          <> w16le 0
          <> w16le 0 -- Version 0.0.0.0
          <> w32le 0 -- Flags
          <> ix blobW 0 -- PublicKey (#Blob)
          <> ix strW (lkStr st "AwsumMain") -- Name
          <> ix strW 0 -- Culture

      -- AssemblyRef rows
      pkt = lkBlob st [0xB0, 0x3F, 0x5F, 0x7F, 0x11, 0xD5, 0x0A, 0x3A]
      mkAR name =
        w16le 9
          <> w16le 0
          <> w16le 0
          <> w16le 0 -- Version 9.0.0.0
          <> w32le 0 -- Flags
          <> ix blobW pkt -- PublicKeyOrToken (#Blob)
          <> ix strW (lkStr st name) -- Name
          <> ix strW 0 -- Culture
          <> ix blobW 0 -- HashValue (#Blob)
      assemblyRefRows = mkAR "System.Runtime" <> mkAR "System.Console"
   in hdr
        <> rowCounts
        <> moduleRow
        <> typeRefRows
        <> typeDefRows
        <> methodDefRows
        <> paramRows
        <> memberRefRows
        <> standAloneSigRows
        <> typeSpecRows
        <> assemblyRow
        <> assemblyRefRows

-- ════════════════════════════════════════════════════════════════════════════
-- Lookup helpers for serialization
-- ════════════════════════════════════════════════════════════════════════════

lkStr :: Pool -> Text -> Word32
lkStr st t = fromMaybe 0 (Map.lookup t st.pStrC)

lkBlob :: Pool -> [Word8] -> Word32
lkBlob st sig = fromMaybe 0 (Map.lookup sig st.pBlobC)
