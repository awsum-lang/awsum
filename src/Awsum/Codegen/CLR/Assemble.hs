-- | CLR PE/.NET assembly binary assembler for Awsum 'Core'.
--
-- Generates a single @AwsumMain.dll@ (.NET 9.0) containing runtime helpers,
-- user declarations, and a @Main(string[])@ entry point.
--
-- All values are @System.Object@; strings are @System.String@;
-- function references are @System.Func@ delegates; IOUnit is @null@.
--
-- The PE file is assembled directly in Haskell — no ilasm, no csc, no MSBuild.
-- Only @dotnet@ is needed to run the output.
module Awsum.Codegen.CLR.Assemble (assembleCLR) where

import Awsum.Core
import Data.Bits (complement, shiftL, shiftR, (.&.), (.|.))
import Data.ByteString qualified as BS
import Data.ByteString.Builder qualified as B
import Data.Char qualified as Char
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Relude

-- ════════════════════════════════════════════════════════════════════════════
-- Public API
-- ════════════════════════════════════════════════════════════════════════════

-- | Produce a complete .NET PE DLL as a strict ByteString.
assembleCLR :: CoreProgram -> BS.ByteString
assembleCLR prog =
  let (methods, st) = runState (doAssemble prog) emptyPool
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
    -- TypeRef table rows: (resScopeCoded, nameStrIdx, nsStrIdx)
    pTR :: [(Word16, Word16, Word16)],
    pTRn :: Word32,
    pTRc :: Map (Word16, Text, Text) Word32,
    -- TypeSpec table rows: blobIdx
    pTS :: [Word16],
    pTSn :: Word32,
    pTSc :: Map [Word8] Word32,
    -- MemberRef table rows: (parentCoded, nameStrIdx, sigBlobIdx)
    pMR :: [(Word16, Word16, Word16)],
    pMRn :: Word32,
    pMRc :: Map (Word16, Text, [Word8]) Word32,
    -- Param table rows: (flags, sequence, nameStrIdx)
    pPM :: [(Word16, Word16, Word16)],
    pPMn :: Word32,
    -- StandAloneSig table rows: blobIdx (for LocalVarSig)
    pSAS :: [Word16],
    pSASn :: Word32
  }

type AsmM = State Pool

emptyPool :: Pool
emptyPool =
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
      pSASn = 0
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
addTypeRef :: Word16 -> Text -> Text -> AsmM Word32
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
      put st' {pTR = st'.pTR <> [(resScope, w16 ni, w16 nsi)], pTRn = row, pTRc = Map.insert key row st'.pTRc}
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
      put st' {pTS = st'.pTS <> [w16 bi], pTSn = row, pTSc = Map.insert sig row st'.pTSc}
      pure row

-- | Add MemberRef row. Returns 1-based row number.
addMemberRef :: Word16 -> Text -> [Word8] -> AsmM Word32
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
      put st' {pMR = st'.pMR <> [(parent, w16 ni, w16 si)], pMRn = row, pMRc = Map.insert key row st'.pMRc}
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
  put st {pSAS = st.pSAS <> [w16 bi], pSASn = row}
  pure (0x11000000 .|. row)

-- | Add a StandAloneSig row for a LocalVarSig.
-- nLocals = number of locals: local 0 is object[], rest are object.
-- Returns the metadata token (table 0x11 << 24 | row).
--
-- The Count field is a *compressed* unsigned integer per
-- ECMA-335 §II.23.2 (1, 2, or 4 bytes); plain @fromIntegral@ would
-- silently truncate for nLocals ≥ 128 and produce a malformed
-- signature that the runtime rejects with @InvalidProgramException@.
addLocalSig :: Int -> AsmM Word32
addLocalSig nLocals = do
  let -- LocalVarSig: 0x07, count, types...
      -- local 0: object[] (SZARRAY + OBJECT), rest: object
      localTypes = [0x1D, 0x1C] <> replicate (nLocals - 1) 0x1C
      countBytes = compressU (fromIntegral nLocals)
      blob = (0x07 : countBytes) <> localTypes
  addLocalSigBytes blob

-- | Count the number of local variable slots needed for a CExpr.
-- A 'CCase' consumes @1@ slot for its array plus room for its widest
-- arm-binding set; nested cases inside an arm body need the SAME slot
-- 0 and binding slots after the outer bindings, so the demand is
-- additive: this level's @1 + maxBindings@ plus whatever the richest
-- nested case inside the arms asks for. A 'CCon' consumes @1@ slot
-- for its array tmp, additive with whatever its richest field needs —
-- nested 'CCon's stack tmp slots so a chain like @Right (Right ...)@
-- of depth N needs N tmp slots.
exprLocalsNeeded :: CExpr -> Int
exprLocalsNeeded = \case
  CCase _ alts ->
    let thisLevel = 1 + foldl' max 0 [length vs | (_, vs, _) <- alts]
        armMax = foldl' max 0 [exprLocalsNeeded b | (_, _, b) <- alts]
     in thisLevel + armMax
  CCall f xs -> foldl' max 0 (exprLocalsNeeded f : map exprLocalsNeeded xs)
  CCon _ fields -> 1 + foldl' max 0 (map exprLocalsNeeded fields)
  CLoop b -> exprLocalsNeeded b
  CContinue xs -> foldl' max 0 (map exprLocalsNeeded xs)
  _ -> 0

-- | Maximum operand-stack depth needed by 'emitExpr' / 'emitTailBin'
-- for this expression. Used to fill the @MaxStack@ field of the fat
-- method header (ECMA-335 §II.25.4.3) — the verifier rejects methods
-- whose actual depth exceeds the declared @MaxStack@. A safe upper
-- bound on every code path; not an exact peak.
exprStackDepth :: CExpr -> Int
exprStackDepth = \case
  CString _ -> 1
  CIntLit _ _ -> 1
  CBuiltIn _ -> 1
  -- CVar in fundef position emits ldnull + ldftn + newobj, peaking at 2.
  CVar _ -> 2
  -- After the temp-local rewrite: stloc empties the stack between
  -- field stores, so the peak per level is max(3 for the tag store,
  -- 2 + field depth for each field). Nested CCons no longer compound.
  CCon _ fields ->
    let maxFld = foldl' max 0 (map exprStackDepth fields)
     in max 3 (2 + maxFld)
  -- scrut peak (emit), stloc → 0, ldloc/ldc/ldelem/unbox → 2 (tag on stack at depth 1),
  -- chain dup/ldc/bne → 3, then arms at depth 0.
  CCase scrut alts ->
    let scrutD = exprStackDepth scrut
        armMax = foldl' max 0 [exprStackDepth b | (_, _, b) <- alts]
     in foldl' max 0 [scrutD, 3, armMax]
  -- Args emitted sequentially. A first-class CCall additionally
  -- pushes the callee before evaluating args, hence the +1 for
  -- the non-builtin / non-direct path. The result occupies one slot.
  CCall f xs ->
    let argDepths = map exprStackDepth xs
        fD = exprStackDepth f
        nXs = length xs
        seqArgs base = foldl' max base [base + i + d | (i, d) <- zip [0 :: Int ..] argDepths]
     in case f of
          CBuiltIn _ -> max (seqArgs 0) 1
          CVar _ -> max (seqArgs 0) (max nXs 1)
          _ -> max fD (max (seqArgs 1) (nXs + 1))
  CLoop b -> exprStackDepth b
  CContinue xs ->
    let argDepths = map exprStackDepth xs
     in foldl' max 0 [i + d | (i, d) <- zip [0 :: Int ..] argDepths]

-- ════════════════════════════════════════════════════════════════════════════
-- Coded index helpers
-- ════════════════════════════════════════════════════════════════════════════

-- ResolutionScope: 2-bit tag. 10 = AssemblyRef.
resScopeAR :: Word32 -> Word16
resScopeAR row = fromIntegral ((row `shiftL` 2) .|. 0x02)

-- TypeDefOrRef: 2-bit tag. 01 = TypeRef.
tdorTR :: Word32 -> Word16
tdorTR row = fromIntegral ((row `shiftL` 2) .|. 0x01)

-- MemberRefParent: 3-bit tag. 001 = TypeRef, 100 = TypeSpec.
mrpTR :: Word32 -> Word16
mrpTR row = fromIntegral ((row `shiftL` 3) .|. 0x01)

mrpTS :: Word32 -> Word16
mrpTS row = fromIntegral ((row `shiftL` 3) .|. 0x04)

-- ════════════════════════════════════════════════════════════════════════════
-- Signature construction
-- ════════════════════════════════════════════════════════════════════════════

-- Element types
etVoid, etString, etObject, etNativeInt :: Word8
etVoid = 0x01
etString = 0x0E
etObject = 0x1C
etNativeInt = 0x18

etSZArray :: Word8
etSZArray = 0x1D

-- | Static method sig: DEFAULT, N params (all object), returns retType.
sigStatic :: Word8 -> Int -> [Word8]
sigStatic retType n = [0x00, fromIntegral n, retType] <> replicate n etObject

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

cilLdstr, cilCall, cilCallvirt, cilNewobj, cilCastclass, cilLdftn :: Word32 -> [Word8]
cilLdstr tok = 0x72 : w32le tok
cilCall tok = 0x28 : w32le tok
cilCallvirt tok = 0x6F : w32le tok
cilNewobj tok = 0x73 : w32le tok
cilCastclass tok = 0x74 : w32le tok
cilLdftn tok = [0xFE, 0x06] <> w32le tok

cilRet, cilPop, cilLdnull, cilLdlen, cilConvI4, cilLdcI4_0, cilLdcI4_1, cilLdelemRef :: [Word8]
cilRet = [0x2A]
cilPop = [0x26]
cilLdnull = [0x14]
cilLdlen = [0x8E]
cilConvI4 = [0x69]
cilLdcI4_0 = [0x16]
cilLdcI4_1 = [0x17]
cilLdelemRef = [0x9A]

cilBgeS, cilBrS, cilBneUnS, cilBltS, cilBleS :: Word8 -> [Word8]
cilBgeS off = [0x2F, off]
cilBrS off = [0x2B, off]
cilBneUnS off = [0x33, off] -- bne.un.s: 1-byte signed offset
cilBltS off = [0x32, off] -- blt.s: 1-byte signed offset
cilBleS off = [0x31, off] -- ble.s: 1-byte signed offset

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

cilBrfalse, cilBeq, cilBge, cilBgt, cilBlt :: Int32 -> [Word8]
cilBrfalse off = 0x39 : w32le (fromIntegral off :: Word32)
cilBeq off = 0x3B : w32le (fromIntegral off :: Word32)
cilBge off = 0x3C : w32le (fromIntegral off :: Word32)
cilBgt off = 0x3D : w32le (fromIntegral off :: Word32)
cilBlt off = 0x3F : w32le (fromIntegral off :: Word32)

cilNeg, cilMul, cilConvI8, cilShl :: [Word8]
cilNeg = [0x65]
cilMul = [0x5A]
cilConvI8 = [0x6A]
cilShl = [0x62]

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

w16 :: Word32 -> Word16
w16 = fromIntegral

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
    mName :: Word16, -- #Strings index
    mSig :: Word16, -- #Blob index
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

  -- Pre-compute method name → MethodDef token map. Runtime helpers are
  -- included only when referenced in Core so hello-style programs don't
  -- carry @__predInt32@ or (eventually) other unused primitives. Token
  -- numbers stay contiguous — '.ctor' is always row 1, then whichever
  -- helpers are kept, then user decls, then Main.
  let prog = CoreProgram decls
      builtIns = usedBuiltIns prog
      declName' (CFunDef n _ _) = n
      declName' (CValDef n _) = n
      userNames = [mangle (declName' d) | d <- decls]
      helperNames =
        [".ctor"]
          <> [ n
             | (n, keep) <-
                 [ ("__concat", Set.member "concatString" builtIns),
                   ("__print", Set.member "IO.Stdout.print" builtIns),
                   ("__predInt32", Set.member "predInt32" builtIns),
                   ("__predUInt8", Set.member "predUInt8" builtIns),
                   ("__succInt32", Set.member "succInt32" builtIns),
                   ("__succUInt8", Set.member "succUInt8" builtIns),
                   ("__eqInt32", Set.member "eqInt32" builtIns),
                   ("__eqUInt8", Set.member "eqUInt8" builtIns),
                   ("__addInt32", Set.member "addInt32" builtIns),
                   ("__subInt32", Set.member "subInt32" builtIns),
                   ("__mulInt32", Set.member "mulInt32" builtIns),
                   ("__negInt32", Set.member "negInt32" builtIns),
                   ("__addUInt8", Set.member "addUInt8" builtIns),
                   ("__subUInt8", Set.member "subUInt8" builtIns),
                   ("__mulUInt8", Set.member "mulUInt8" builtIns),
                   ("__splitOnFirst", Set.member "splitOnFirst" builtIns),
                   ("__parseInt32", Set.member "parseInt32" builtIns),
                   ("__parseUInt8", Set.member "parseUInt8" builtIns)
                 ],
               keep
             ]
      allNames = helperNames <> userNames <> ["Main"]
      tokMap = Map.fromList [(n, tokMD (fromIntegral i)) | (i, n) <- zip ([1 ..] :: [Int]) allNames]

  let valNames = Set.fromList [n | CValDef n _ <- decls]
      funNames = Set.fromList [n | CFunDef n _ _ <- decls]
      arities = Map.fromList [(n, length as) | CFunDef n as _ <- decls]
      ctx = ECtx {eParams = Map.empty, eLocals = Map.empty, eNextScratch = 0, eValDefs = valNames, eFunDefs = funNames, eArities = arities, eToks = tokMap}

  m0 <- mkInit
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
  userMs <- traverse (mkDecl ctx) decls
  mEntry <- mkMain tokMap
  pure (m0 : m1s <> m2s <> m3s <> m3us <> m3sI <> m3sU <> m4s <> m5s <> m6s <> m6sub <> m6mul <> m6neg <> m6us <> m6usSub <> m6usMul <> m7s <> m8sI <> m8sU <> userMs <> [mEntry])

-- ════════════════════════════════════════════════════════════════════════════
-- Fixed methods
-- ════════════════════════════════════════════════════════════════════════════

mkInit :: AsmM MInfo
mkInit = do
  ni <- w16 <$> addStr ".ctor"
  si <- w16 <$> addBlob (sigInstance etVoid [])
  ps <- addParams 0
  let code = cilLdarg 0 <> cilCall (tokMR 1) <> cilRet -- MemberRef 1 = Object::.ctor
  pure MInfo {mImplFlags = 0, mFlags = 0x1886, mName = ni, mSig = si, mParamList = ps, mCode = code, mLocalSigTok = 0, mMaxStack = 16}

mkConcat :: AsmM MInfo
mkConcat = do
  ni <- w16 <$> addStr "__concat"
  si <- w16 <$> addBlob (sigStatic etObject 2)
  ps <- addParams 2
  let code = cilLdarg 0 <> cilLdarg 1 <> cilCall (tokMR 2) <> cilRet -- MemberRef 2 = String.Concat
  pure MInfo {mImplFlags = 0, mFlags = 0x0096, mName = ni, mSig = si, mParamList = ps, mCode = code, mLocalSigTok = 0, mMaxStack = 16}

mkPrint :: AsmM MInfo
mkPrint = do
  ni <- w16 <$> addStr "__print"
  si <- w16 <$> addBlob (sigStatic etObject 1)
  ps <- addParams 1
  let code = cilLdarg 0 <> cilCall (tokMR 3) <> cilLdnull <> cilRet -- MemberRef 3 = Console.Write
  pure MInfo {mImplFlags = 0, mFlags = 0x0096, mName = ni, mSig = si, mParamList = ps, mCode = code, mLocalSigTok = 0, mMaxStack = 16}

-- | predInt32: Int32 -> Either UnderflowError Int32.
--   Binary equivalent of the CIL in 'Awsum.Codegen.CLR.predInt32Method'.
--   Locals: V_0 int32 (unboxed argument), V_1 object (UnderflowError
--   instance held across the Left-array build).
mkPredInt32 :: AsmM MInfo
mkPredInt32 = do
  ni <- w16 <$> addStr "__predInt32"
  si <- w16 <$> addBlob (sigStatic etObject 1)
  ps <- addParams 1
  trInt32 <- addTypeRef (resScopeAR 1) "Int32" "System"
  trObj <- addTypeRef (resScopeAR 1) "Object" "System"
  -- LocalVarSig: 0x07, count=2, ELEMENT_TYPE_I4 (0x08), ELEMENT_TYPE_OBJECT (0x1C)
  localTok <- addLocalSigBytes [0x07, 0x02, 0x08, 0x1C]
  let boxInt32 = cilBox (tokTR trInt32)
      newarrObj = cilNewarr (tokTR trObj)
      overflow =
        -- UnderflowError instance: object[1] with boxed Int32(0) at [0]
        cilLdcI4 1
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 0
          <> boxInt32
          <> cilStelemRef
          <> cilStloc 1
          -- Left: object[2] = [boxed Int32(0) tag, UE]
          <> cilLdcI4 2
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 0
          <> boxInt32
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 1
          <> cilLdloc 1
          <> cilStelemRef
          <> cilRet
      okBranch =
        -- Right: object[2] = [boxed Int32(1) tag, boxed Int32(v - 1)]
        cilLdcI4 2
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 1
          <> boxInt32
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 1
          <> cilLdloc 0
          <> cilLdcI4 1
          <> cilSub
          <> boxInt32
          <> cilStelemRef
          <> cilRet
      branchOffset = fromIntegral (length overflow) :: Word8
      code =
        cilLdarg 0
          <> cilUnboxAny (tokTR trInt32)
          <> cilStloc 0
          <> cilLdloc 0
          <> cilLdcI4 (-2147483648)
          <> cilBneUnS branchOffset
          <> overflow
          <> okBranch
  pure MInfo {mImplFlags = 0, mFlags = 0x0096, mName = ni, mSig = si, mParamList = ps, mCode = code, mLocalSigTok = localTok, mMaxStack = 16}

-- | predUInt8: UInt8 -> Either UnderflowError UInt8.
--   Binary equivalent of the CIL in 'Awsum.Codegen.CLR.predUInt8Method'.
--   Same local layout as 'mkPredInt32' (V_0 int32, V_1 object); only the
--   boundary constant changes — 'cilLdcI4 0' vs MIN_VALUE. Since
--   'cilLdcI4 0' uses the 1-byte short form 'ldc.i4.0', the preamble is
--   4 bytes shorter than predInt32, but 'branchOffset = length overflow'
--   is unchanged because it measures the gap between the branch and the
--   ok block, not the preamble.
mkPredUInt8 :: AsmM MInfo
mkPredUInt8 = do
  ni <- w16 <$> addStr "__predUInt8"
  si <- w16 <$> addBlob (sigStatic etObject 1)
  ps <- addParams 1
  trInt32 <- addTypeRef (resScopeAR 1) "Int32" "System"
  trObj <- addTypeRef (resScopeAR 1) "Object" "System"
  localTok <- addLocalSigBytes [0x07, 0x02, 0x08, 0x1C]
  let boxInt32 = cilBox (tokTR trInt32)
      newarrObj = cilNewarr (tokTR trObj)
      overflow =
        -- UnderflowError instance: object[1] with boxed Int32(0) at [0]
        cilLdcI4 1
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 0
          <> boxInt32
          <> cilStelemRef
          <> cilStloc 1
          -- Left: object[2] = [boxed Int32(0) tag, UE]
          <> cilLdcI4 2
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 0
          <> boxInt32
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 1
          <> cilLdloc 1
          <> cilStelemRef
          <> cilRet
      okBranch =
        -- Right: object[2] = [boxed Int32(1) tag, boxed Int32(v - 1)]
        cilLdcI4 2
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 1
          <> boxInt32
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 1
          <> cilLdloc 0
          <> cilLdcI4 1
          <> cilSub
          <> boxInt32
          <> cilStelemRef
          <> cilRet
      branchOffset = fromIntegral (length overflow) :: Word8
      code =
        cilLdarg 0
          <> cilUnboxAny (tokTR trInt32)
          <> cilStloc 0
          <> cilLdloc 0
          <> cilLdcI4 0
          <> cilBneUnS branchOffset
          <> overflow
          <> okBranch
  pure MInfo {mImplFlags = 0, mFlags = 0x0096, mName = ni, mSig = si, mParamList = ps, mCode = code, mLocalSigTok = localTok, mMaxStack = 16}

-- | succInt32: Int32 -> Either OverflowError Int32.
--   Binary equivalent of 'Awsum.Codegen.CLR.succInt32Method'. Mirror of
--   'mkPredInt32' with INT32_MAX as the boundary and 'cilAdd' for the
--   non-overflow branch. OverflowError shares UnderflowError's tag (0),
--   so the Left-branch encoding is byte-identical.
mkSuccInt32 :: AsmM MInfo
mkSuccInt32 = do
  ni <- w16 <$> addStr "__succInt32"
  si <- w16 <$> addBlob (sigStatic etObject 1)
  ps <- addParams 1
  trInt32 <- addTypeRef (resScopeAR 1) "Int32" "System"
  trObj <- addTypeRef (resScopeAR 1) "Object" "System"
  localTok <- addLocalSigBytes [0x07, 0x02, 0x08, 0x1C]
  let boxInt32 = cilBox (tokTR trInt32)
      newarrObj = cilNewarr (tokTR trObj)
      overflow =
        cilLdcI4 1
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 0
          <> boxInt32
          <> cilStelemRef
          <> cilStloc 1
          <> cilLdcI4 2
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 0
          <> boxInt32
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 1
          <> cilLdloc 1
          <> cilStelemRef
          <> cilRet
      okBranch =
        cilLdcI4 2
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 1
          <> boxInt32
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 1
          <> cilLdloc 0
          <> cilLdcI4 1
          <> cilAdd
          <> boxInt32
          <> cilStelemRef
          <> cilRet
      branchOffset = fromIntegral (length overflow) :: Word8
      code =
        cilLdarg 0
          <> cilUnboxAny (tokTR trInt32)
          <> cilStloc 0
          <> cilLdloc 0
          <> cilLdcI4 2147483647
          <> cilBneUnS branchOffset
          <> overflow
          <> okBranch
  pure MInfo {mImplFlags = 0, mFlags = 0x0096, mName = ni, mSig = si, mParamList = ps, mCode = code, mLocalSigTok = localTok, mMaxStack = 16}

-- | succUInt8: UInt8 -> Either OverflowError UInt8.
--   Binary equivalent of 'Awsum.Codegen.CLR.succUInt8Method'. Same local
--   layout as 'mkSuccInt32'; boundary constant is 255 (emits 5-byte long
--   'ldc.i4' since it's outside the signed-byte range of 'ldc.i4.s').
mkSuccUInt8 :: AsmM MInfo
mkSuccUInt8 = do
  ni <- w16 <$> addStr "__succUInt8"
  si <- w16 <$> addBlob (sigStatic etObject 1)
  ps <- addParams 1
  trInt32 <- addTypeRef (resScopeAR 1) "Int32" "System"
  trObj <- addTypeRef (resScopeAR 1) "Object" "System"
  localTok <- addLocalSigBytes [0x07, 0x02, 0x08, 0x1C]
  let boxInt32 = cilBox (tokTR trInt32)
      newarrObj = cilNewarr (tokTR trObj)
      overflow =
        cilLdcI4 1
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 0
          <> boxInt32
          <> cilStelemRef
          <> cilStloc 1
          <> cilLdcI4 2
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 0
          <> boxInt32
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 1
          <> cilLdloc 1
          <> cilStelemRef
          <> cilRet
      okBranch =
        cilLdcI4 2
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 1
          <> boxInt32
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 1
          <> cilLdloc 0
          <> cilLdcI4 1
          <> cilAdd
          <> boxInt32
          <> cilStelemRef
          <> cilRet
      branchOffset = fromIntegral (length overflow) :: Word8
      code =
        cilLdarg 0
          <> cilUnboxAny (tokTR trInt32)
          <> cilStloc 0
          <> cilLdloc 0
          <> cilLdcI4 255
          <> cilBneUnS branchOffset
          <> overflow
          <> okBranch
  pure MInfo {mImplFlags = 0, mFlags = 0x0096, mName = ni, mSig = si, mParamList = ps, mCode = code, mLocalSigTok = localTok, mMaxStack = 16}

-- | eqInt32 / eqUInt8: two integers of the same type → Bool.
--   Binary equivalent of the CIL in 'Awsum.Codegen.CLR.eqMethod'.
--   Both Int32 and UInt8 are boxed as System.Int32 (how CIntLit emits
--   them), so the two methods share a single builder parameterised by
--   name. No locals — both args are unboxed directly onto the eval
--   stack before 'bne.un.s', so mLocalSigTok = 0 (tiny header is fine).
mkEq :: Text -> AsmM MInfo
mkEq methodName = do
  ni <- w16 <$> addStr methodName
  si <- w16 <$> addBlob (sigStatic etObject 2)
  ps <- addParams 2
  trInt32 <- addTypeRef (resScopeAR 1) "Int32" "System"
  trObj <- addTypeRef (resScopeAR 1) "Object" "System"
  let boxInt32 = cilBox (tokTR trInt32)
      newarrObj = cilNewarr (tokTR trObj)
      boolBox tagVal =
        -- One-slot object[] holding a boxed Int32 tag.
        cilLdcI4 1
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 tagVal
          <> boxInt32
          <> cilStelemRef
          <> cilRet
      equalBlock = boolBox 0 -- True tag = 0
      notEqualBlock = boolBox 1 -- False tag = 1
      branchOffset = fromIntegral (length equalBlock) :: Word8
      code =
        cilLdarg 0
          <> cilUnboxAny (tokTR trInt32)
          <> cilLdarg 1
          <> cilUnboxAny (tokTR trInt32)
          <> cilBneUnS branchOffset
          <> equalBlock
          <> notEqualBlock
  pure MInfo {mImplFlags = 0, mFlags = 0x0096, mName = ni, mSig = si, mParamList = ps, mCode = code, mLocalSigTok = 0, mMaxStack = 16}

-- | addInt32: Int32 -> Int32 -> Either ArithError Int32.
--   Binary equivalent of 'Awsum.Codegen.CLR.addInt32Method'. Locals
--   layout: V_0/V_1 = unboxed int operands, V_2 = wrapping sum,
--   V_3 = boxed ArithError between Left construction and Object[2]
--   wrap. Overflow detection uses the XOR trick — same logic as the
--   JVM 'mkAddInt32', single-block, no try/catch needed.
mkAddInt32 :: AsmM MInfo
mkAddInt32 = do
  ni <- w16 <$> addStr "__addInt32"
  si <- w16 <$> addBlob (sigStatic etObject 2)
  ps <- addParams 2
  trInt32 <- addTypeRef (resScopeAR 1) "Int32" "System"
  trObj <- addTypeRef (resScopeAR 1) "Object" "System"
  -- locals: int32 V_0, int32 V_1, int32 V_2, object V_3
  localTok <- addLocalSigBytes [0x07, 0x04, 0x08, 0x08, 0x08, 0x1C]
  let boxInt32 = cilBox (tokTR trInt32)
      newarrObj = cilNewarr (tokTR trObj)
      makeLeft tagBytes =
        cilLdcI4 1
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> tagBytes
          <> boxInt32
          <> cilStelemRef
          <> cilStloc 3
          <> cilLdcI4 2
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 0 -- Left tag
          <> boxInt32
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 1
          <> cilLdloc 3
          <> cilStelemRef
          <> cilRet
      overBlock = makeLeft (cilLdcI4 1) -- ArithError Overflow = 1
      underBlock = makeLeft (cilLdcI4 0) -- ArithError Underflow = 0
      okBlock =
        cilLdcI4 2
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 1 -- Right tag
          <> boxInt32
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 1
          <> cilLdloc 2
          <> boxInt32
          <> cilStelemRef
          <> cilRet
      blt2Off = fromIntegral (length overBlock) :: Word8
      overSplit =
        cilLdloc 0 -- a
          <> cilLdcI4 0
          <> cilBltS blt2Off -- if a < 0 → underBlock
      blt1Off = fromIntegral (length okBlock) :: Word8
      preamble =
        cilLdarg 0
          <> cilUnboxAny (tokTR trInt32)
          <> cilStloc 0
          <> cilLdarg 1
          <> cilUnboxAny (tokTR trInt32)
          <> cilStloc 1
          <> cilLdloc 0
          <> cilLdloc 1
          <> cilAdd
          <> cilStloc 2
          <> cilLdloc 0
          <> cilLdloc 2
          <> cilXor
          <> cilLdloc 1
          <> cilLdloc 2
          <> cilXor
          <> cilAnd
          <> cilLdcI4 0
          <> cilBltS blt1Off -- if (a^sum)&(b^sum) < 0 → overSplit
      code =
        preamble
          <> okBlock
          <> overSplit
          <> overBlock
          <> underBlock
  pure MInfo {mImplFlags = 0, mFlags = 0x0096, mName = ni, mSig = si, mParamList = ps, mCode = code, mLocalSigTok = localTok, mMaxStack = 16}

-- | addUInt8: UInt8 -> UInt8 -> Either OverflowError UInt8.
--   Binary equivalent of 'Awsum.Codegen.CLR.addUInt8Method'. Both
--   inputs are 0..255 so 'add' yields 0..510 in i32 and a single
--   'ble.s' against 255 picks the branch — no widening needed.
mkAddUInt8 :: AsmM MInfo
mkAddUInt8 = do
  ni <- w16 <$> addStr "__addUInt8"
  si <- w16 <$> addBlob (sigStatic etObject 2)
  ps <- addParams 2
  trInt32 <- addTypeRef (resScopeAR 1) "Int32" "System"
  trObj <- addTypeRef (resScopeAR 1) "Object" "System"
  -- locals: int32 V_0 (sum), object V_1 (Left payload)
  localTok <- addLocalSigBytes [0x07, 0x02, 0x08, 0x1C]
  let boxInt32 = cilBox (tokTR trInt32)
      newarrObj = cilNewarr (tokTR trObj)
      okBlock =
        cilLdcI4 2
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 1 -- Right tag
          <> boxInt32
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 1
          <> cilLdloc 0
          <> boxInt32
          <> cilStelemRef
          <> cilRet
      overBlock =
        cilLdcI4 1
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 0 -- OverflowError tag
          <> boxInt32
          <> cilStelemRef
          <> cilStloc 1
          <> cilLdcI4 2
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 0 -- Left tag
          <> boxInt32
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 1
          <> cilLdloc 1
          <> cilStelemRef
          <> cilRet
      bleOff = fromIntegral (length overBlock) :: Word8
      preamble =
        cilLdarg 0
          <> cilUnboxAny (tokTR trInt32)
          <> cilLdarg 1
          <> cilUnboxAny (tokTR trInt32)
          <> cilAdd
          <> cilStloc 0
          <> cilLdloc 0
          <> cilLdcI4 255
          <> cilBleS bleOff -- if sum <= 255 → okBlock
      code =
        preamble
          <> overBlock
          <> okBlock
  pure MInfo {mImplFlags = 0, mFlags = 0x0096, mName = ni, mSig = si, mParamList = ps, mCode = code, mLocalSigTok = localTok, mMaxStack = 16}

-- | subInt32: Int32 -> Int32 -> Either ArithError Int32.
--   Binary equivalent of 'Awsum.Codegen.CLR.subInt32Method'. Same XOR
--   overflow trick as 'mkAddInt32', with 'cilSub' replacing 'cilAdd' in
--   the preamble — kept structurally parallel to make the two methods
--   easy to read together.
mkSubInt32 :: AsmM MInfo
mkSubInt32 = do
  ni <- w16 <$> addStr "__subInt32"
  si <- w16 <$> addBlob (sigStatic etObject 2)
  ps <- addParams 2
  trInt32 <- addTypeRef (resScopeAR 1) "Int32" "System"
  trObj <- addTypeRef (resScopeAR 1) "Object" "System"
  -- locals: int32 V_0, int32 V_1, int32 V_2, object V_3
  localTok <- addLocalSigBytes [0x07, 0x04, 0x08, 0x08, 0x08, 0x1C]
  let boxInt32 = cilBox (tokTR trInt32)
      newarrObj = cilNewarr (tokTR trObj)
      makeLeft tagBytes =
        cilLdcI4 1
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> tagBytes
          <> boxInt32
          <> cilStelemRef
          <> cilStloc 3
          <> cilLdcI4 2
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 0 -- Left tag
          <> boxInt32
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 1
          <> cilLdloc 3
          <> cilStelemRef
          <> cilRet
      overBlock = makeLeft (cilLdcI4 1) -- ArithError Overflow = 1
      underBlock = makeLeft (cilLdcI4 0) -- ArithError Underflow = 0
      okBlock =
        cilLdcI4 2
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 1 -- Right tag
          <> boxInt32
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 1
          <> cilLdloc 2
          <> boxInt32
          <> cilStelemRef
          <> cilRet
      blt2Off = fromIntegral (length overBlock) :: Word8
      overSplit =
        cilLdloc 0 -- a
          <> cilLdcI4 0
          <> cilBltS blt2Off -- if a < 0 → underBlock
      blt1Off = fromIntegral (length okBlock) :: Word8
      preamble =
        cilLdarg 0
          <> cilUnboxAny (tokTR trInt32)
          <> cilStloc 0
          <> cilLdarg 1
          <> cilUnboxAny (tokTR trInt32)
          <> cilStloc 1
          <> cilLdloc 0
          <> cilLdloc 1
          <> cilSub
          <> cilStloc 2
          <> cilLdloc 0
          <> cilLdloc 1
          <> cilXor
          <> cilLdloc 0
          <> cilLdloc 2
          <> cilXor
          <> cilAnd
          <> cilLdcI4 0
          <> cilBltS blt1Off -- if (a^b)&(a^diff) < 0 → overSplit
      code =
        preamble
          <> okBlock
          <> overSplit
          <> overBlock
          <> underBlock
  pure MInfo {mImplFlags = 0, mFlags = 0x0096, mName = ni, mSig = si, mParamList = ps, mCode = code, mLocalSigTok = localTok, mMaxStack = 16}

-- | mulInt32: Int32 -> Int32 -> Either ArithError Int32.
--   Binary equivalent of 'Awsum.Codegen.CLR.mulInt32Method'. Both
--   operands are widened to int64, multiplied at long width, and the
--   result range-checked against [INT32_MIN, INT32_MAX]. Direction is
--   read off the comparison result — bgt → Overflow, blt → Underflow.
--   Locals: V_0/V_1 = unboxed int operands, V_2 = int64 product,
--   V_3 = boxed ArithError staged before the Object[2] wrap.
mkMulInt32 :: AsmM MInfo
mkMulInt32 = do
  ni <- w16 <$> addStr "__mulInt32"
  si <- w16 <$> addBlob (sigStatic etObject 2)
  ps <- addParams 2
  trInt32 <- addTypeRef (resScopeAR 1) "Int32" "System"
  trObj <- addTypeRef (resScopeAR 1) "Object" "System"
  -- locals: int32 V_0, int32 V_1, int64 V_2, object V_3
  -- ELEMENT_TYPE_I4 = 0x08, ELEMENT_TYPE_I8 = 0x0A, ELEMENT_TYPE_OBJECT = 0x1C
  localTok <- addLocalSigBytes [0x07, 0x04, 0x08, 0x08, 0x0A, 0x1C]
  let boxInt32 = cilBox (tokTR trInt32)
      newarrObj = cilNewarr (tokTR trObj)
      makeLeft tagBytes =
        cilLdcI4 1
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> tagBytes
          <> boxInt32
          <> cilStelemRef
          <> cilStloc 3
          <> cilLdcI4 2
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 0 -- Left tag
          <> boxInt32
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 1
          <> cilLdloc 3
          <> cilStelemRef
          <> cilRet
      overBlock = makeLeft (cilLdcI4 1) -- Overflow = 1
      underBlock = makeLeft (cilLdcI4 0) -- Underflow = 0
      okBlock =
        cilLdcI4 2
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 1 -- Right tag
          <> boxInt32
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 1
          <> cilLdloc 2
          <> [0x69] -- conv.i4 (truncate int64 → int32)
          <> boxInt32
          <> cilStelemRef
          <> cilRet
      -- After the second 'blt' branch (which can take us to underBlock),
      -- the next bytes are the ok block. To reach overBlock we have to
      -- step past okBlock; to reach underBlock we step past okBlock and
      -- overBlock. Both branches use the 4-byte forms (cilBgt/cilBlt)
      -- since their relative offsets can exceed 1 byte.
      bltUnderOff = fromIntegral (length okBlock + length overBlock) :: Int32
      checkLower =
        cilLdloc 2
          <> cilLdcI4 (-2147483648)
          <> cilConvI8
          <> cilBlt bltUnderOff
      bgtOverOff = fromIntegral (length checkLower + length okBlock) :: Int32
      checkUpper =
        cilLdloc 2
          <> cilLdcI4 2147483647
          <> cilConvI8
          <> cilBgt bgtOverOff
      preamble =
        cilLdarg 0
          <> cilUnboxAny (tokTR trInt32)
          <> cilStloc 0
          <> cilLdarg 1
          <> cilUnboxAny (tokTR trInt32)
          <> cilStloc 1
          <> cilLdloc 0
          <> cilConvI8
          <> cilLdloc 1
          <> cilConvI8
          <> cilMul
          <> cilStloc 2
      code =
        preamble
          <> checkUpper
          <> checkLower
          <> okBlock
          <> overBlock
          <> underBlock
  pure MInfo {mImplFlags = 0, mFlags = 0x0096, mName = ni, mSig = si, mParamList = ps, mCode = code, mLocalSigTok = localTok, mMaxStack = 16}

-- | negInt32: Int32 -> Either OverflowError Int32.
--   Binary equivalent of 'Awsum.Codegen.CLR.negInt32Method'. Mirror of
--   'mkSuccInt32' with INT32_MIN as the boundary and 'cilNeg' for the
--   ok branch. OverflowError shares the single-constructor tag (0), so
--   the Left-branch encoding is byte-identical to 'mkSuccInt32'.
mkNegInt32 :: AsmM MInfo
mkNegInt32 = do
  ni <- w16 <$> addStr "__negInt32"
  si <- w16 <$> addBlob (sigStatic etObject 1)
  ps <- addParams 1
  trInt32 <- addTypeRef (resScopeAR 1) "Int32" "System"
  trObj <- addTypeRef (resScopeAR 1) "Object" "System"
  localTok <- addLocalSigBytes [0x07, 0x02, 0x08, 0x1C]
  let boxInt32 = cilBox (tokTR trInt32)
      newarrObj = cilNewarr (tokTR trObj)
      overflow =
        cilLdcI4 1
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 0
          <> boxInt32
          <> cilStelemRef
          <> cilStloc 1
          <> cilLdcI4 2
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 0
          <> boxInt32
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 1
          <> cilLdloc 1
          <> cilStelemRef
          <> cilRet
      okBranch =
        cilLdcI4 2
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 1
          <> boxInt32
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 1
          <> cilLdloc 0
          <> cilNeg
          <> boxInt32
          <> cilStelemRef
          <> cilRet
      branchOffset = fromIntegral (length overflow) :: Word8
      code =
        cilLdarg 0
          <> cilUnboxAny (tokTR trInt32)
          <> cilStloc 0
          <> cilLdloc 0
          <> cilLdcI4 (-2147483648)
          <> cilBneUnS branchOffset
          <> overflow
          <> okBranch
  pure MInfo {mImplFlags = 0, mFlags = 0x0096, mName = ni, mSig = si, mParamList = ps, mCode = code, mLocalSigTok = localTok, mMaxStack = 16}

-- | subUInt8: UInt8 -> UInt8 -> Either UnderflowError UInt8.
--   Binary equivalent of 'Awsum.Codegen.CLR.subUInt8Method'. Both
--   inputs are 0..255 so 'sub' yields a value in -255..255 in i32 and
--   a single 'blt.s' against 0 picks the underflow branch.
mkSubUInt8 :: AsmM MInfo
mkSubUInt8 = do
  ni <- w16 <$> addStr "__subUInt8"
  si <- w16 <$> addBlob (sigStatic etObject 2)
  ps <- addParams 2
  trInt32 <- addTypeRef (resScopeAR 1) "Int32" "System"
  trObj <- addTypeRef (resScopeAR 1) "Object" "System"
  -- locals: int32 V_0 (diff), object V_1 (Left payload)
  localTok <- addLocalSigBytes [0x07, 0x02, 0x08, 0x1C]
  let boxInt32 = cilBox (tokTR trInt32)
      newarrObj = cilNewarr (tokTR trObj)
      okBlock =
        cilLdcI4 2
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 1 -- Right tag
          <> boxInt32
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 1
          <> cilLdloc 0
          <> boxInt32
          <> cilStelemRef
          <> cilRet
      underBlock =
        cilLdcI4 1
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 0 -- UnderflowError tag
          <> boxInt32
          <> cilStelemRef
          <> cilStloc 1
          <> cilLdcI4 2
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 0 -- Left tag
          <> boxInt32
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 1
          <> cilLdloc 1
          <> cilStelemRef
          <> cilRet
      bltOff = fromIntegral (length okBlock) :: Word8
      preamble =
        cilLdarg 0
          <> cilUnboxAny (tokTR trInt32)
          <> cilLdarg 1
          <> cilUnboxAny (tokTR trInt32)
          <> cilSub
          <> cilStloc 0
          <> cilLdloc 0
          <> cilLdcI4 0
          <> cilBltS bltOff -- if diff < 0 → underBlock
      code =
        preamble
          <> okBlock
          <> underBlock
  pure MInfo {mImplFlags = 0, mFlags = 0x0096, mName = ni, mSig = si, mParamList = ps, mCode = code, mLocalSigTok = localTok, mMaxStack = 16}

-- | mulUInt8: UInt8 -> UInt8 -> Either OverflowError UInt8.
--   Binary equivalent of 'Awsum.Codegen.CLR.mulUInt8Method'. Same shape
--   as 'mkAddUInt8' with 'cilMul' replacing 'cilAdd'; both produce a
--   value in 0..65025 in i32 from inputs in 0..255.
mkMulUInt8 :: AsmM MInfo
mkMulUInt8 = do
  ni <- w16 <$> addStr "__mulUInt8"
  si <- w16 <$> addBlob (sigStatic etObject 2)
  ps <- addParams 2
  trInt32 <- addTypeRef (resScopeAR 1) "Int32" "System"
  trObj <- addTypeRef (resScopeAR 1) "Object" "System"
  -- locals: int32 V_0 (product), object V_1 (Left payload)
  localTok <- addLocalSigBytes [0x07, 0x02, 0x08, 0x1C]
  let boxInt32 = cilBox (tokTR trInt32)
      newarrObj = cilNewarr (tokTR trObj)
      okBlock =
        cilLdcI4 2
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 1 -- Right tag
          <> boxInt32
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 1
          <> cilLdloc 0
          <> boxInt32
          <> cilStelemRef
          <> cilRet
      overBlock =
        cilLdcI4 1
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 0 -- OverflowError tag
          <> boxInt32
          <> cilStelemRef
          <> cilStloc 1
          <> cilLdcI4 2
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 0 -- Left tag
          <> boxInt32
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 1
          <> cilLdloc 1
          <> cilStelemRef
          <> cilRet
      bleOff = fromIntegral (length overBlock) :: Word8
      preamble =
        cilLdarg 0
          <> cilUnboxAny (tokTR trInt32)
          <> cilLdarg 1
          <> cilUnboxAny (tokTR trInt32)
          <> cilMul
          <> cilStloc 0
          <> cilLdloc 0
          <> cilLdcI4 255
          <> cilBleS bleOff -- if product <= 255 → okBlock
      code =
        preamble
          <> overBlock
          <> okBlock
  pure MInfo {mImplFlags = 0, mFlags = 0x0096, mName = ni, mSig = si, mParamList = ps, mCode = code, mLocalSigTok = localTok, mMaxStack = 16}

-- | splitOnFirst: String -> String -> Maybe (Tuple2 String String).
--   Binary equivalent of 'Awsum.Codegen.CLR.splitOnFirstMethod'. Defers
--   substring search to 'String.IndexOf(string)' (returns -1 on miss,
--   0 on empty separator — both behaviours match the prelude contract
--   directly). On hit the two 'String.Substring' calls allocate fresh
--   strings (CLR strings are immutable; substrings are owning copies,
--   not aliases). Locals: 0..1 = unboxed String operands, 2 = idx,
--   3..4 = prefix/suffix, 5 = boxed Tuple2 staged before the Just wrap.
mkSplitOnFirst :: AsmM MInfo
mkSplitOnFirst = do
  ni <- w16 <$> addStr "__splitOnFirst"
  si <- w16 <$> addBlob (sigStatic etObject 2)
  ps <- addParams 2
  trInt32 <- addTypeRef (resScopeAR 1) "Int32" "System"
  trObj <- addTypeRef (resScopeAR 1) "Object" "System"
  trStr <- addTypeRef (resScopeAR 1) "String" "System"
  indexOfRef <- addMemberRef (mrpTR trStr) "IndexOf" (sigInstance 0x08 [etString])
  substring2Ref <- addMemberRef (mrpTR trStr) "Substring" (sigInstance etString [0x08, 0x08])
  substring1Ref <- addMemberRef (mrpTR trStr) "Substring" (sigInstance etString [0x08])
  lengthRef <- addMemberRef (mrpTR trStr) "get_Length" (sigInstance 0x08 [])
  -- locals: 6 (string V_0, string V_1, int32 V_2, string V_3, string V_4, object V_5)
  localTok <- addLocalSigBytes [0x07, 0x06, etString, etString, 0x08, etString, etString, etObject]
  let boxInt32 = cilBox (tokTR trInt32)
      newarrObj = cilNewarr (tokTR trObj)
      castStr = cilCastclass (tokTR trStr)
      nothingBlock =
        -- Nothing: object[1] = [box(0)]
        cilLdcI4 1
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 0
          <> boxInt32
          <> cilStelemRef
          <> cilRet
      foundBlock =
        -- prefix = str.Substring(0, idx) → V_3
        cilLdloc 1
          <> cilLdcI4 0
          <> cilLdloc 2
          <> cilCallvirt (tokMR substring2Ref)
          <> cilStloc 3
          -- suffix = str.Substring(idx + sep.Length) → V_4
          <> cilLdloc 1
          <> cilLdloc 2
          <> cilLdloc 0
          <> cilCallvirt (tokMR lengthRef)
          <> cilAdd
          <> cilCallvirt (tokMR substring1Ref)
          <> cilStloc 4
          -- Tuple2: object[3] = [box(0), prefix, suffix] → V_5
          <> cilLdcI4 3
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 0
          <> boxInt32
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 1
          <> cilLdloc 3
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 2
          <> cilLdloc 4
          <> cilStelemRef
          <> cilStloc 5
          -- Just: object[2] = [box(1), tuple]
          <> cilLdcI4 2
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 1
          <> boxInt32
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 1
          <> cilLdloc 5
          <> cilStelemRef
          <> cilRet
      branchOffset = fromIntegral (length nothingBlock) :: Word8
      preamble =
        cilLdarg 0
          <> castStr
          <> cilStloc 0
          <> cilLdarg 1
          <> castStr
          <> cilStloc 1
          <> cilLdloc 1
          <> cilLdloc 0
          <> cilCallvirt (tokMR indexOfRef)
          <> cilStloc 2
          <> cilLdloc 2
          <> cilLdcI4 (-1)
          <> cilBneUnS branchOffset
      code = preamble <> nothingBlock <> foundBlock
  pure MInfo {mImplFlags = 0, mFlags = 0x0096, mName = ni, mSig = si, mParamList = ps, mCode = code, mLocalSigTok = localTok, mMaxStack = 16}

-- | parseInt32: String -> Either ParseError Int32. Binary equivalent
--   of 'Awsum.Codegen.CLR.parseInt32Method'. Same handrolled algorithm
--   as the JVM and LLVM helpers — int64 accumulator capped at the
--   magnitude `|minInt32|`. The constant 2147483648 is built with the
--   shift trick `1 << 31`.
--   Locals: 0 = string s, 1 = int len, 2 = int i, 3 = int neg,
--   4 = int64 acc, 5 = int c, 6 = object (Left payload on fail).
mkParseInt32 :: AsmM MInfo
mkParseInt32 = do
  ni <- w16 <$> addStr "__parseInt32"
  si <- w16 <$> addBlob (sigStatic etObject 1)
  ps <- addParams 1
  trInt32 <- addTypeRef (resScopeAR 1) "Int32" "System"
  trObj <- addTypeRef (resScopeAR 1) "Object" "System"
  trStr <- addTypeRef (resScopeAR 1) "String" "System"
  lengthRef <- addMemberRef (mrpTR trStr) "get_Length" (sigInstance 0x08 [])
  charsRef <- addMemberRef (mrpTR trStr) "get_Chars" (sigInstance 0x03 [0x08])
  -- locals: string, int32, int32, int32, int64, int32, object
  localTok <- addLocalSigBytes [0x07, 0x07, etString, 0x08, 0x08, 0x08, 0x0A, 0x08, etObject]
  let boxInt32 = cilBox (tokTR trInt32)
      newarrObj = cilNewarr (tokTR trObj)
      castStr = cilCastclass (tokTR trStr)
      callLength = cilCallvirt (tokMR lengthRef)
      callChars = cilCallvirt (tokMR charsRef)
      -- ───── code blocks (offsets computed bottom-up) ─────
      -- A: load arg → s, get length → len
      blockA =
        cilLdarg 0
          <> castStr
          <> cilStloc 0
          <> cilLdloc 0
          <> callLength
          <> cilStloc 1
      lenA = length blockA
      -- B: ldloc len; brfalse L_fail
      blockB = cilLdloc 1
      lenB = length blockB
      brfalse1At = lenA + lenB
      after1 = brfalse1At + 5
      -- C: i=0; neg=0
      blockC = cilLdcI4 0 <> cilStloc 2 <> cilLdcI4 0 <> cilStloc 3
      lenC = length blockC
      -- D: charAt(0); push 45
      blockD =
        cilLdloc 0
          <> cilLdcI4 0
          <> callChars
          <> cilLdcI4 45
      lenD = length blockD
      bneAt = after1 + lenC + lenD
      after2 = bneAt + 2
      -- F: minus path setup
      blockF =
        cilLdcI4 1
          <> cilStloc 3
          <> cilLdcI4 1
          <> cilStloc 2
          <> cilLdloc 1
          <> cilLdcI4 1
      lenF = length blockF
      beq1At = after2 + lenF
      initAccAt = beq1At + 5
      -- H: acc = 0L
      blockH = cilLdcI4 0 <> cilConvI8 <> cilStloc 4
      lenH = length blockH
      loopAt = initAccAt + lenH
      -- I: ldloc i; ldloc len
      blockI = cilLdloc 2 <> cilLdloc 1
      lenI = length blockI
      bgeAfterAt = loopAt + lenI
      afterBge = bgeAfterAt + 5
      -- K: charAt(i); stloc 5
      blockK = cilLdloc 0 <> cilLdloc 2 <> callChars <> cilStloc 5
      lenK = length blockK
      -- L: ldloc 5; ldc 48
      blockL = cilLdloc 5 <> cilLdcI4 48
      lenL = length blockL
      bltLowAt = afterBge + lenK + lenL
      afterBltLow = bltLowAt + 5
      -- N: ldloc 5; ldc 57
      blockN = cilLdloc 5 <> cilLdcI4 57
      lenN = length blockN
      bgtHighAt = afterBltLow + lenN
      afterBgtHigh = bgtHighAt + 5
      -- P: acc = acc * 10 + (c - '0')
      blockP =
        cilLdloc 4
          <> cilLdcI4 10
          <> cilConvI8
          <> cilMul
          <> cilLdloc 5
          <> cilLdcI4 48
          <> cilSub
          <> cilConvI8
          <> cilAdd
          <> cilStloc 4
      lenP = length blockP
      -- Q: ldloc acc; (1 << 31)L
      blockQ =
        cilLdloc 4
          <> cilLdcI4 1
          <> cilConvI8
          <> cilLdcI4 31
          <> cilShl
      lenQ = length blockQ
      bgtAccAt = afterBgtHigh + lenP + lenQ
      afterBgtAcc = bgtAccAt + 5
      -- S: i++
      blockS = cilLdloc 2 <> cilLdcI4 1 <> cilAdd <> cilStloc 2
      lenS = length blockS
      brLoopAt = afterBgtAcc + lenS
      afterBrLoop = brLoopAt + 5
      -- T (after_loop): ldloc neg
      blockT = cilLdloc 3
      lenT = length blockT
      brfalseNegAt = afterBrLoop + lenT
      afterBrfalseNeg = brfalseNegAt + 5
      -- U: acc = -acc
      blockU = cilLdloc 4 <> cilNeg <> cilStloc 4
      lenU = length blockU
      brBuildAt = afterBrfalseNeg + lenU
      posCheckAt = brBuildAt + 5
      -- V: ldloc acc; INT_MAX as long
      blockV = cilLdloc 4 <> cilLdcI4 2147483647 <> cilConvI8
      lenV = length blockV
      bgtPosAt = posCheckAt + lenV
      buildRightAt = bgtPosAt + 5
      -- X: build Right
      blockX =
        cilLdcI4 2
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 1
          <> boxInt32
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 1
          <> cilLdloc 4
          <> cilConvI4
          <> boxInt32
          <> cilStelemRef
          <> cilRet
      lenX = length blockX
      failAt = buildRightAt + lenX
      -- Y: build Left ParseError
      blockY =
        cilLdcI4 1
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 0
          <> boxInt32
          <> cilStelemRef
          <> cilStloc 6
          <> cilLdcI4 2
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 0
          <> boxInt32
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 1
          <> cilLdloc 6
          <> cilStelemRef
          <> cilRet
      -- Branch offsets (from byte after the branch to target)
      brfalse1Off = fromIntegral (failAt - after1) :: Int32
      bneOff = fromIntegral (initAccAt - after2) :: Word8
      beq1Off = fromIntegral (failAt - initAccAt) :: Int32
      bgeAfterOff = fromIntegral (afterBrLoop - afterBge) :: Int32
      bltLowOff = fromIntegral (failAt - afterBltLow) :: Int32
      bgtHighOff = fromIntegral (failAt - afterBgtHigh) :: Int32
      bgtAccOff = fromIntegral (failAt - afterBgtAcc) :: Int32
      brLoopOff = fromIntegral (loopAt - afterBrLoop) :: Int32
      brfalseNegOff = fromIntegral (posCheckAt - afterBrfalseNeg) :: Int32
      brBuildOff = fromIntegral (buildRightAt - (brBuildAt + 5)) :: Int32
      bgtPosOff = fromIntegral (failAt - buildRightAt) :: Int32
      code =
        blockA
          <> blockB
          <> cilBrfalse brfalse1Off
          <> blockC
          <> blockD
          <> cilBneUnS bneOff
          <> blockF
          <> cilBeq beq1Off
          <> blockH
          <> blockI
          <> cilBge bgeAfterOff
          <> blockK
          <> blockL
          <> cilBlt bltLowOff
          <> blockN
          <> cilBgt bgtHighOff
          <> blockP
          <> blockQ
          <> cilBgt bgtAccOff
          <> blockS
          <> cilBr brLoopOff
          <> blockT
          <> cilBrfalse brfalseNegOff
          <> blockU
          <> cilBr brBuildOff
          <> blockV
          <> cilBgt bgtPosOff
          <> blockX
          <> blockY
  pure MInfo {mImplFlags = 0, mFlags = 0x0096, mName = ni, mSig = si, mParamList = ps, mCode = code, mLocalSigTok = localTok, mMaxStack = 16}

-- | parseUInt8: String -> Either ParseError UInt8. Same shape as
--   'mkParseInt32' minus the sign handling — UInt8 cannot represent a
--   negative number — and with an i32 accumulator (the running
--   magnitude never exceeds 2559 before the > 255 check fails).
--   Locals: 0 = string s, 1 = int len, 2 = int i, 3 = int acc,
--   4 = int c, 5 = object (Left payload on fail).
mkParseUInt8 :: AsmM MInfo
mkParseUInt8 = do
  ni <- w16 <$> addStr "__parseUInt8"
  si <- w16 <$> addBlob (sigStatic etObject 1)
  ps <- addParams 1
  trInt32 <- addTypeRef (resScopeAR 1) "Int32" "System"
  trObj <- addTypeRef (resScopeAR 1) "Object" "System"
  trStr <- addTypeRef (resScopeAR 1) "String" "System"
  lengthRef <- addMemberRef (mrpTR trStr) "get_Length" (sigInstance 0x08 [])
  charsRef <- addMemberRef (mrpTR trStr) "get_Chars" (sigInstance 0x03 [0x08])
  -- locals: string, int32 (×4), object
  localTok <- addLocalSigBytes [0x07, 0x06, etString, 0x08, 0x08, 0x08, 0x08, etObject]
  let boxInt32 = cilBox (tokTR trInt32)
      newarrObj = cilNewarr (tokTR trObj)
      castStr = cilCastclass (tokTR trStr)
      callLength = cilCallvirt (tokMR lengthRef)
      callChars = cilCallvirt (tokMR charsRef)
      blockA =
        cilLdarg 0
          <> castStr
          <> cilStloc 0
          <> cilLdloc 0
          <> callLength
          <> cilStloc 1
      lenA = length blockA
      blockB = cilLdloc 1
      lenB = length blockB
      brfalse1At = lenA + lenB
      after1 = brfalse1At + 5
      blockC = cilLdcI4 0 <> cilStloc 2 <> cilLdcI4 0 <> cilStloc 3
      lenC = length blockC
      loopAt = after1 + lenC
      blockI = cilLdloc 2 <> cilLdloc 1
      lenI = length blockI
      bgeAt = loopAt + lenI
      afterBge = bgeAt + 5
      blockK = cilLdloc 0 <> cilLdloc 2 <> callChars <> cilStloc 4
      lenK = length blockK
      blockL = cilLdloc 4 <> cilLdcI4 48
      lenL = length blockL
      bltAt = afterBge + lenK + lenL
      afterBlt = bltAt + 5
      blockN = cilLdloc 4 <> cilLdcI4 57
      lenN = length blockN
      bgtCharAt = afterBlt + lenN
      afterBgtChar = bgtCharAt + 5
      blockP =
        cilLdloc 3
          <> cilLdcI4 10
          <> cilMul
          <> cilLdloc 4
          <> cilLdcI4 48
          <> cilSub
          <> cilAdd
          <> cilStloc 3
      lenP = length blockP
      blockQ = cilLdloc 3 <> cilLdcI4 255
      lenQ = length blockQ
      bgtAccAt = afterBgtChar + lenP + lenQ
      afterBgtAcc = bgtAccAt + 5
      blockS = cilLdloc 2 <> cilLdcI4 1 <> cilAdd <> cilStloc 2
      lenS = length blockS
      brLoopAt = afterBgtAcc + lenS
      okAt = brLoopAt + 5
      blockX =
        cilLdcI4 2
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 1
          <> boxInt32
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 1
          <> cilLdloc 3
          <> boxInt32
          <> cilStelemRef
          <> cilRet
      lenX = length blockX
      failAt = okAt + lenX
      blockY =
        cilLdcI4 1
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 0
          <> boxInt32
          <> cilStelemRef
          <> cilStloc 5
          <> cilLdcI4 2
          <> newarrObj
          <> cilDup
          <> cilLdcI4 0
          <> cilLdcI4 0
          <> boxInt32
          <> cilStelemRef
          <> cilDup
          <> cilLdcI4 1
          <> cilLdloc 5
          <> cilStelemRef
          <> cilRet
      brfalse1Off = fromIntegral (failAt - after1) :: Int32
      bgeOff = fromIntegral (okAt - afterBge) :: Int32
      bltOff = fromIntegral (failAt - afterBlt) :: Int32
      bgtCharOff = fromIntegral (failAt - afterBgtChar) :: Int32
      bgtAccOff = fromIntegral (failAt - afterBgtAcc) :: Int32
      brLoopOff = fromIntegral (loopAt - okAt) :: Int32
      code =
        blockA
          <> blockB
          <> cilBrfalse brfalse1Off
          <> blockC
          <> blockI
          <> cilBge bgeOff
          <> blockK
          <> blockL
          <> cilBlt bltOff
          <> blockN
          <> cilBgt bgtCharOff
          <> blockP
          <> blockQ
          <> cilBgt bgtAccOff
          <> blockS
          <> cilBr brLoopOff
          <> blockX
          <> blockY
  pure MInfo {mImplFlags = 0, mFlags = 0x0096, mName = ni, mSig = si, mParamList = ps, mCode = code, mLocalSigTok = localTok, mMaxStack = 16}

mkMain :: Map Text Word32 -> AsmM MInfo
mkMain tokMap = do
  ni <- w16 <$> addStr "Main"
  si <- w16 <$> addBlob [0x00, 0x01, etVoid, etSZArray, etString]
  ps <- addParams 1
  emptyTok <- addUS ""
  let vMainTok = fromMaybe (error "no v_main") (Map.lookup (mangle "main") tokMap)
      code =
        cilLdarg 0 -- 0: 1
          <> cilLdlen -- 1: 1
          <> cilConvI4 -- 2: 1
          <> cilLdcI4_1 -- 3: 1
          <> cilBgeS 7 -- 4: 2  → offset 13
          <> cilLdstr emptyTok -- 6: 5
          <> cilBrS 3 -- 11: 2  → offset 16
          <> cilLdarg 0 -- 13: 1 (has_arg)
          <> cilLdcI4_0 -- 14: 1
          <> cilLdelemRef -- 15: 1
          <> cilCall vMainTok -- 16: 5 (call_main)
          <> cilPop -- 21: 1
          <> cilRet -- 22: 1
  pure MInfo {mImplFlags = 0, mFlags = 0x0096, mName = ni, mSig = si, mParamList = ps, mCode = code, mLocalSigTok = 0, mMaxStack = 16}

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
    eToks :: Map Text Word32
  }

mkDecl :: ECtx -> CDecl -> AsmM MInfo
mkDecl baseCtx = \case
  -- TCO-wrapped body. The method's argument slots are already mutable,
  -- so 'CContinue' evaluates new args onto the stack, pops them back
  -- into slots via @starg@ (reverse order, stack is LIFO), and branches
  -- to offset 0 (the method's first byte) via a 4-byte @br@. Tail value
  -- arms emit their own @ret@; no trailing fallthrough @ret@ is added.
  CFunDef nm args (CLoop body) -> do
    let ctx = baseCtx {eParams = Map.fromList (zip args [0 ..])}
        nLocals = exprLocalsNeeded body
        maxStack = fromIntegral (max 1 (exprStackDepth body)) :: Word16
    ni <- w16 <$> addStr (mangle nm)
    si <- w16 <$> addBlob (sigStatic etObject (length args))
    ps <- addParams (length args)
    localTok <- if nLocals > 0 then addLocalSig nLocals else pure 0
    code <- emitTailBin ctx args body
    pure MInfo {mImplFlags = 0, mFlags = 0x0096, mName = ni, mSig = si, mParamList = ps, mCode = code, mLocalSigTok = localTok, mMaxStack = maxStack}
  CFunDef nm args body -> do
    let ctx = baseCtx {eParams = Map.fromList (zip args [0 ..])}
        nLocals = exprLocalsNeeded body
        maxStack = fromIntegral (max 1 (exprStackDepth body)) :: Word16
    ni <- w16 <$> addStr (mangle nm)
    si <- w16 <$> addBlob (sigStatic etObject (length args))
    ps <- addParams (length args)
    localTok <- if nLocals > 0 then addLocalSig nLocals else pure 0
    code <- emitExpr ctx body
    pure MInfo {mImplFlags = 0, mFlags = 0x0096, mName = ni, mSig = si, mParamList = ps, mCode = code <> cilRet, mLocalSigTok = localTok, mMaxStack = maxStack}
  CValDef nm rhs -> do
    let ctx = baseCtx {eParams = Map.empty}
        nLocals = exprLocalsNeeded rhs
        maxStack = fromIntegral (max 1 (exprStackDepth rhs)) :: Word16
    ni <- w16 <$> addStr (mangle nm)
    si <- w16 <$> addBlob (sigStatic etObject 0)
    ps <- addParams 0
    localTok <- if nLocals > 0 then addLocalSig nLocals else pure 0
    code <- emitExpr ctx rhs
    pure MInfo {mImplFlags = 0, mFlags = 0x0096, mName = ni, mSig = si, mParamList = ps, mCode = code <> cilRet, mLocalSigTok = localTok, mMaxStack = maxStack}

-- ════════════════════════════════════════════════════════════════════════════
-- Expression codegen
-- ════════════════════════════════════════════════════════════════════════════

emitExpr :: ECtx -> CExpr -> AsmM [Word8]
emitExpr ctx = \case
  CString s -> do
    tok <- addUS s
    pure (cilLdstr tok)
  CVar n
    | Just slot <- Map.lookup n ctx.eLocals ->
        pure (cilLdloc slot)
    | Just slot <- Map.lookup n ctx.eParams ->
        pure (cilLdarg slot)
    | n `Set.member` ctx.eValDefs ->
        let tok = lkTok ctx (mangle n)
         in pure (cilCall tok)
    | n `Set.member` ctx.eFunDefs -> do
        let arity = fromMaybe 0 (Map.lookup n ctx.eArities)
            tok = lkTok ctx (mangle n)
        (_, ctorTok, _) <- funcTokens arity
        pure (cilLdnull <> cilLdftn tok <> cilNewobj ctorTok)
    | otherwise ->
        pure cilLdnull
  CBuiltIn _ -> pure cilLdnull -- invariant: not a standalone term; dispatched from CCall
  CIntLit n it -> do
    -- Both Int32 and UInt8 are represented as boxed System.Int32 on the CLR,
    -- matching the JVM treatment (boxed Integer). Avoids a separate boxing
    -- path for unsigned widths while keeping the value space correct — the
    -- typechecker has already validated 'n' against the declared range.
    trInt32 <- addTypeRef (resScopeAR 1) "Int32" "System"
    let n32 = fromInteger n :: Int32
        _ = it
    pure (cilLdcI4 (fromIntegral n32) <> cilBox (tokTR trInt32))
  CCon tag fields -> do
    -- Create Object[] container: [tag_as_boxed_Int32, field1, field2, ...].
    -- Strategy: allocate the array, stash it in a per-CCon temp local,
    -- then for each slot reload from the local before stelem.ref. Keeps
    -- the operand stack flat (peak ~3) regardless of how deeply fields
    -- nest — `Right (Right (Right ...))` of arbitrary depth no longer
    -- linearly grows the stack and so no longer trips the verifier's
    -- @MaxStack@ check (ECMA-335 §II.25.4.3). The naïve dup-and-stelem
    -- chain we used to emit pinned the partially built array on the
    -- stack across each field's evaluation, peaking at ~2N for depth N.
    let nSlots = 1 + length fields
        tmpSlot = ctx.eNextScratch
        ctx' = ctx {eNextScratch = tmpSlot + 1}
    trObj <- addTypeRef (resScopeAR 1) "Object" "System"
    trInt32 <- addTypeRef (resScopeAR 1) "Int32" "System"
    let allocAndStash = cilLdcI4 nSlots <> cilNewarr (tokTR trObj) <> cilStloc tmpSlot
        storeTag =
          cilLdloc tmpSlot
            <> cilLdcI4 0
            <> cilLdcI4 tag
            <> cilBox (tokTR trInt32)
            <> cilStelemRef
    fieldCodes <- forM (zip fields [1 :: Int ..]) $ \(fld, i) -> do
      fldCode <- emitExpr ctx' fld
      pure (cilLdloc tmpSlot <> cilLdcI4 i <> fldCode <> cilStelemRef)
    pure (allocAndStash <> storeTag <> concat fieldCodes <> cilLdloc tmpSlot)
  CCase scrut alts -> do
    trInt32 <- addTypeRef (resScopeAR 1) "Int32" "System"
    scrutCode <- emitExpr ctx scrut
    let sorted = sortWith (\(t, _, _) -> t) alts
        -- Allocate fresh slots beyond anything currently in scope so
        -- nested 'CCase's never clobber outer arm bindings. The outer
        -- array in slot 'arrSlot' stays live for the duration of the
        -- arm body. 'eNextScratch' is the canonical "next free slot"
        -- counter — it accounts for outer 'arrSlot's and 'CCon' tmps
        -- that 'eLocals' doesn't track. Slot demand matches
        -- 'exprLocalsNeeded'.
        arrSlot = ctx.eNextScratch
        maxBindings = foldl' max 0 [length vs | (_, vs, _) <- sorted]
        bindSlotStart = arrSlot + 1
        nextScratch' = bindSlotStart + maxBindings
    -- Emit arm bodies with bound variables
    armCodes <- forM sorted $ \(_, vars, body) -> do
      let bindings = zip vars [bindSlotStart ..]
          ctx' =
            ctx
              { eLocals = foldl' (\m (v, s) -> Map.insert v s m) ctx.eLocals bindings,
                eNextScratch = nextScratch'
              }
          -- Extract bound vars: for each, ldloc arr, ldc index, ldelem.ref, stloc slot
          bindCode =
            concatMap
              ( \((_, slot), i) ->
                  cilLdloc arrSlot <> cilLdcI4 (i :: Int) <> cilLdelemRef' <> cilStloc slot
              )
              (zip bindings [1 :: Int ..])
      bodyCode <- emitExpr ctx' body
      pure (bindCode <> bodyCode)
    let tags = [t | (t, _, _) <- sorted]
        -- Extract tag: stloc arr; ldloc arr; ldc 0; ldelem.ref; unbox.any Int32
        extractAndStore =
          cilStloc arrSlot
            <> cilLdloc arrSlot
            <> cilLdcI4 0
            <> cilLdelemRef'
            <> cilUnboxAny (tokTR trInt32)
        -- Build if/else chain on the int tag value
        i32le :: Int -> [Word8]
        i32le n = w32le (fromIntegral n :: Word32)
        buildChain :: [(Int, [Word8])] -> [Word8]
        buildChain [] = cilLdnull
        buildChain [(_, armCode)] = [0x26] <> armCode -- pop tag int, emit body
        buildChain ((tag', armCode) : rest) =
          let restCode = buildChain rest
              popLen :: Int
              popLen = 1
              brLen :: Int
              brLen = 5 -- br (1 opcode + 4 offset)
              skipLen = popLen + length armCode + brLen
              joinLen = length restCode
           in [0x25] -- dup
                <> cilLdcI4 tag'
                <> [0x40]
                <> i32le skipLen -- bne.un
                <> [0x26] -- pop
                <> armCode
                <> [0x38]
                <> i32le joinLen -- br
                <> restCode
        chainCode = buildChain (zip tags armCodes)
    pure (scrutCode <> extractAndStore <> chainCode)
  CCall f xs -> case f of
    CBuiltIn "IO.Stdout.print" | [x] <- xs -> do
      cx <- emitExpr ctx x
      pure (cx <> cilCall (lkTok ctx "__print"))
    CBuiltIn name
      | name == "showInt32" || name == "showUInt8",
        [x] <- xs -> do
          -- Call 'object::ToString()' virtually: boxed Int32 dispatches to
          -- System.Int32.ToString(), producing the culture-invariant decimal
          -- representation (culture only affects floats, which we do not emit).
          cx <- emitExpr ctx x
          trObj <- addTypeRef (resScopeAR 1) "Object" "System"
          toStrRef <- addMemberRef (mrpTR trObj) "ToString" (sigInstance etString [])
          pure (cx <> cilCallvirt (tokMR toStrRef))
    CBuiltIn "predInt32" | [x] <- xs -> do
      cx <- emitExpr ctx x
      pure (cx <> cilCall (lkTok ctx "__predInt32"))
    CBuiltIn "predUInt8" | [x] <- xs -> do
      cx <- emitExpr ctx x
      pure (cx <> cilCall (lkTok ctx "__predUInt8"))
    CBuiltIn "succInt32" | [x] <- xs -> do
      cx <- emitExpr ctx x
      pure (cx <> cilCall (lkTok ctx "__succInt32"))
    CBuiltIn "succUInt8" | [x] <- xs -> do
      cx <- emitExpr ctx x
      pure (cx <> cilCall (lkTok ctx "__succUInt8"))
    CBuiltIn name
      | name == "eqInt32" || name == "eqUInt8",
        [a, b] <- xs -> do
          ca <- emitExpr ctx a
          cb <- emitExpr ctx b
          let fn = if name == "eqInt32" then "__eqInt32" else "__eqUInt8"
          pure (ca <> cb <> cilCall (lkTok ctx fn))
    CBuiltIn name
      | name == "addInt32" || name == "addUInt8" || name == "subInt32" || name == "subUInt8" || name == "mulUInt8" || name == "mulInt32",
        [a, b] <- xs -> do
          ca <- emitExpr ctx a
          cb <- emitExpr ctx b
          let fn = case name of
                "addInt32" -> "__addInt32"
                "addUInt8" -> "__addUInt8"
                "subInt32" -> "__subInt32"
                "subUInt8" -> "__subUInt8"
                "mulInt32" -> "__mulInt32"
                _ -> "__mulUInt8"
          pure (ca <> cb <> cilCall (lkTok ctx fn))
    CBuiltIn "negInt32" | [x] <- xs -> do
      cx <- emitExpr ctx x
      pure (cx <> cilCall (lkTok ctx "__negInt32"))
    CBuiltIn "concatString" | [a, b] <- xs -> do
      ca <- emitExpr ctx a
      cb <- emitExpr ctx b
      pure (ca <> cb <> cilCall (lkTok ctx "__concat"))
    CBuiltIn "splitOnFirst" | [a, b] <- xs -> do
      ca <- emitExpr ctx a
      cb <- emitExpr ctx b
      pure (ca <> cb <> cilCall (lkTok ctx "__splitOnFirst"))
    CBuiltIn name
      | name == "parseInt32" || name == "parseUInt8",
        [x] <- xs -> do
          cx <- emitExpr ctx x
          let fn = if name == "parseInt32" then "__parseInt32" else "__parseUInt8"
          pure (cx <> cilCall (lkTok ctx fn))
    CBuiltIn n ->
      error ("CLR codegen: unknown builtin '" <> n <> "' reached CCall (typecheck should have rejected it)")
    CVar n | n `Set.member` ctx.eFunDefs -> do
      argCodes <- traverse (emitExpr ctx) xs
      pure (concat argCodes <> cilCall (lkTok ctx (mangle n)))
    _ -> do
      fCode <- emitExpr ctx f
      let arity = length xs
      (tsTok, _, invTok) <- funcTokens arity
      argCodes <- traverse (emitExpr ctx) xs
      pure (fCode <> cilCastclass tsTok <> concat argCodes <> cilCallvirt invTok)
  CLoop _ -> error "CLR Assemble: CLoop reached emitExpr (non-tail position)"
  CContinue _ -> error "CLR Assemble: CContinue reached emitExpr (non-tail position)"

-- | Emit @body@ in tail position under @IL_tco_loop:@ (offset 0 of the
-- method code). 'CContinue' evaluates new argument values, pops them
-- into argument slots with @starg.s@ (reverse order — stack is LIFO),
-- and emits a 4-byte @br@ back to offset 0; the offset is computed
-- relative to the byte position of the @br@ itself, which we track by
-- threading a running offset through the traversal. Tail value shapes
-- end with their own @ret@; 'CCase' dispatches via a dup/bne chain
-- where each arm self-terminates, so no join / fallthrough is needed.
emitTailBin :: ECtx -> [Text] -> CExpr -> AsmM [Word8]
emitTailBin ctx0 params = fmap fst . goTop ctx0 0
  where
    goTop :: ECtx -> Int -> CExpr -> AsmM ([Word8], Int)
    goTop ctx offset = \case
      CContinue newArgs -> emitContinue ctx offset newArgs
      CCase scrut alts -> emitTailCase ctx offset scrut alts
      other -> emitTailValue ctx offset other

    emitContinue :: ECtx -> Int -> [CExpr] -> AsmM ([Word8], Int)
    emitContinue ctx offset newArgs = do
      argCodes <- traverse (emitExpr ctx) newArgs
      let paramSlots :: [Int]
          paramSlots =
            [ fromMaybe (error $ "CLR Assemble: no arg slot for " <> show p) (Map.lookup p ctx.eParams)
            | p <- params
            ]
          stargBytes :: [Word8]
          stargBytes = concat [cilStarg s | s <- reverse paramSlots]
          argBytes :: [Word8]
          argBytes = concat argCodes
          brStart :: Int
          brStart = offset + length argBytes + length stargBytes
          brLen :: Int
          brLen = 5
          delta :: Int32
          delta = fromIntegral (negate (brStart + brLen))
          brBytes = cilBr delta
      pure (argBytes <> stargBytes <> brBytes, brStart + brLen)

    emitTailValue :: ECtx -> Int -> CExpr -> AsmM ([Word8], Int)
    emitTailValue ctx offset expr = do
      code <- emitExpr ctx expr
      let bytes = code <> cilRet
      pure (bytes, offset + length bytes)

    emitTailCase :: ECtx -> Int -> CExpr -> [(Int, [Text], CExpr)] -> AsmM ([Word8], Int)
    emitTailCase ctx offset scrut alts = do
      trInt32 <- addTypeRef (resScopeAR 1) "Int32" "System"
      scrutCode <- emitExpr ctx scrut
      let sorted = sortWith (\(t, _, _) -> t) alts
          -- Mirror non-tail 'CCase': pull arrSlot and bindSlotStart from
          -- 'eNextScratch' so nested constructs (CCase or CCon) inside an
          -- arm body see a counter that already accounts for outer
          -- scratch slots. See the comment on 'emitExpr' for 'CCase'.
          arrSlot = ctx.eNextScratch
          maxBindings = foldl' max 0 [length vs | (_, vs, _) <- sorted]
          bindSlotStart = arrSlot + 1
          nextScratch' = bindSlotStart + maxBindings
          extractAndStore =
            cilStloc arrSlot
              <> cilLdloc arrSlot
              <> cilLdcI4 0
              <> cilLdelemRef'
              <> cilUnboxAny (tokTR trInt32)
          prefix = scrutCode <> extractAndStore
          chainStartOffset = offset + length prefix
      (chainBytes, endOffset) <- buildTailChain ctx arrSlot nextScratch' chainStartOffset sorted bindSlotStart
      pure (prefix <> chainBytes, endOffset)

    buildTailChain :: ECtx -> Int -> Int -> Int -> [(Int, [Text], CExpr)] -> Int -> AsmM ([Word8], Int)
    buildTailChain _ _ _ offset [] _ =
      pure (cilLdnull <> cilRet, offset + length cilLdnull + length cilRet)
    buildTailChain ctx arrSlot nextScratch' offset [(_, vars, armBody)] bindStart = do
      let bindings = zip vars [bindStart ..]
          ctx' =
            ctx
              { eLocals = foldl' (\m (v, s) -> Map.insert v s m) ctx.eLocals bindings,
                eNextScratch = nextScratch'
              }
          bindCode :: [Word8]
          bindCode =
            concatMap
              ( \((_, slot), i) ->
                  cilLdloc arrSlot <> cilLdcI4 (i :: Int) <> cilLdelemRef' <> cilStloc slot
              )
              (zip bindings [1 :: Int ..])
          popTag :: [Word8]
          popTag = cilPop
          armPrefix = popTag <> bindCode
          armStart = offset + length armPrefix
      (armBytes, endOff) <- goTop ctx' armStart armBody
      pure (armPrefix <> armBytes, endOff)
    buildTailChain ctx arrSlot nextScratch' offset ((tag, vars, armBody) : rest) bindStart = do
      let dupCode :: [Word8]
          dupCode = [0x25] -- dup
          ldcCode :: [Word8]
          ldcCode = cilLdcI4 tag
          bneLen :: Int
          bneLen = 5
          bindings = zip vars [bindStart ..]
          ctx' =
            ctx
              { eLocals = foldl' (\m (v, s) -> Map.insert v s m) ctx.eLocals bindings,
                eNextScratch = nextScratch'
              }
          bindCode :: [Word8]
          bindCode =
            concatMap
              ( \((_, slot), i) ->
                  cilLdloc arrSlot <> cilLdcI4 (i :: Int) <> cilLdelemRef' <> cilStloc slot
              )
              (zip bindings [1 :: Int ..])
          popTag :: [Word8]
          popTag = cilPop
          armPrefixLen = length dupCode + length ldcCode + bneLen
          armStart = offset + armPrefixLen + length popTag + length bindCode
      (armBytes, armEnd) <- goTop ctx' armStart armBody
      let skipLen = length popTag + length bindCode + length armBytes
      (restBytes, restEnd) <- buildTailChain ctx arrSlot nextScratch' armEnd rest bindStart
      let bne = cilBneUn (fromIntegral skipLen)
      pure
        ( dupCode <> ldcCode <> bne <> popTag <> bindCode <> armBytes <> restBytes,
          restEnd
        )

lkTok :: ECtx -> Text -> Word32
lkTok ctx n = fromMaybe (error $ "no token: " <> n) (Map.lookup n ctx.eToks)

-- ════════════════════════════════════════════════════════════════════════════
-- Higher-order function support (Func delegates)
-- ════════════════════════════════════════════════════════════════════════════

-- | Get (typeSpecToken, ctorToken, invokeToken) for Func delegate of given arity.
funcTokens :: Int -> AsmM (Word32, Word32, Word32)
funcTokens arity = do
  -- TypeRef for System.Func`(arity+1) in System.Runtime
  let funcName = "Func`" <> show (arity + 1)
  trRow <- addTypeRef (resScopeAR 1) funcName "System"

  -- TypeSpec: GENERICINST CLASS TypeDefOrRef GenArgCount GenArgs
  let coded = tdorTR trRow
      tsSig = [0x15, 0x12] <> compressU (fromIntegral coded) <> [fromIntegral (arity + 1)] <> replicate (arity + 1) etObject
  tsRow <- addTypeSpec tsSig

  -- MemberRef: .ctor(object, native int) on TypeSpec
  ctorRow <- addMemberRef (mrpTS tsRow) ".ctor" (sigInstance etVoid [etObject, etNativeInt])
  -- MemberRef: Invoke(!0, ..., !(N-1)) -> !N on TypeSpec (uses generic type vars)
  let etVar i = [0x13] <> compressU (fromIntegral i)
      invokeSig = [0x20, fromIntegral arity] <> etVar arity <> concatMap etVar [0 .. arity - 1]
  invokeRow <- addMemberRef (mrpTS tsRow) "Invoke" invokeSig

  pure (tokTS tsRow, tokMR ctorRow, tokMR invokeRow)

-- ════════════════════════════════════════════════════════════════════════════
-- Method body encoding
-- ════════════════════════════════════════════════════════════════════════════

-- | Encode method body with CIL tiny or fat header.
-- Tiny header (1 byte) implies @MaxStack = 8@ — we only pick it when
-- the method is short and has no locals, in which case we have already
-- verified the actual stack depth fits. The fat header (12 bytes)
-- carries an explicit @MaxStack@; we emit the per-method value passed
-- in @maxStack@. Hardcoding @MaxStack = 16@ here, as this code did
-- before, was the root cause of @System.InvalidProgramException@ when
-- a single method's stack peaked above 16 — see
-- ECMA-335 §II.25.4.3 and the design note in
-- @awsum-management/clr-maxstack-and-ccon-stack-depth.md@.
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
          <> [0] -- HeapSizes (all 2-byte)
          <> [1] -- Reserved
          <> w64le valid
          <> w64le 0 -- Sorted

      -- Module row (10 bytes)
      moduleRow =
        w16le 0 -- Generation
          <> w16le (w16 $ lkStr st "AwsumMain.dll")
          <> w16le 1 -- Mvid (GUID index)
          <> w16le 0 -- EncId
          <> w16le 0 -- EncBaseId

      -- TypeDef rows (14 bytes each)
      typeDefRows =
        -- <Module>
        w32le 0
          <> w16le (w16 $ lkStr st "<Module>")
          <> w16le 0
          <> w16le 0
          <> w16le 1
          <> w16le 1
          -- AwsumMain
          <> w32le 0x00100001
          <> w16le (w16 $ lkStr st "AwsumMain")
          <> w16le 0
          <> w16le (tdorTR 1) -- extends System.Object (TypeRef row 1)
          <> w16le 1 -- FieldList
          <> w16le 1 -- MethodList

      -- MethodDef rows (14 bytes each)
      methodDefRows = concat [mkMDRow rva m | (rva, m) <- zip methodRVAs methods]

      -- Param rows (6 bytes each)
      paramRows = concatMap (\(f, s, n) -> w16le f <> w16le s <> w16le n) st.pPM

      -- TypeRef rows (6 bytes each)
      typeRefRows = concatMap (\(rs, n, ns) -> w16le rs <> w16le n <> w16le ns) st.pTR

      -- MemberRef rows (6 bytes each)
      memberRefRows = concatMap (\(c, n, s) -> w16le c <> w16le n <> w16le s) st.pMR

      -- StandAloneSig rows (2 bytes each, table 0x11)
      standAloneSigRows = if hasSAS then concatMap w16le st.pSAS else []

      -- TypeSpec rows (2 bytes each)
      typeSpecRows = if hasTS then concatMap w16le st.pTS else []

      -- Assembly row (22 bytes)
      assemblyRow =
        w32le 0x8004 -- HashAlgId: SHA1
          <> w16le 0
          <> w16le 0
          <> w16le 0
          <> w16le 0 -- Version 0.0.0.0
          <> w32le 0 -- Flags
          <> w16le 0 -- PublicKey
          <> w16le (w16 $ lkStr st "AwsumMain")
          <> w16le 0 -- Culture

      -- AssemblyRef rows (20 bytes each)
      pkt = lkBlob st [0xB0, 0x3F, 0x5F, 0x7F, 0x11, 0xD5, 0x0A, 0x3A]
      mkAR name =
        w16le 9
          <> w16le 0
          <> w16le 0
          <> w16le 0 -- Version 9.0.0.0
          <> w32le 0 -- Flags
          <> w16le (w16 pkt) -- PublicKeyOrToken
          <> w16le (w16 $ lkStr st name)
          <> w16le 0 -- Culture
          <> w16le 0 -- HashValue
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

mkMDRow :: Word32 -> MInfo -> [Word8]
mkMDRow rva m =
  w32le rva
    <> w16le m.mImplFlags
    <> w16le m.mFlags
    <> w16le m.mName
    <> w16le m.mSig
    <> w16le (w16 m.mParamList)

-- ════════════════════════════════════════════════════════════════════════════
-- Lookup helpers for serialization
-- ════════════════════════════════════════════════════════════════════════════

lkStr :: Pool -> Text -> Word32
lkStr st t = fromMaybe 0 (Map.lookup t st.pStrC)

lkBlob :: Pool -> [Word8] -> Word32
lkBlob st sig = fromMaybe 0 (Map.lookup sig st.pBlobC)

-- ════════════════════════════════════════════════════════════════════════════
-- Name mangling
-- ════════════════════════════════════════════════════════════════════════════

mangle :: Text -> Text
mangle t =
  let ok c = Char.isAlphaNum c || c == '_' || c == '\''
      body = T.map (\c -> if ok c then c else '_') t
   in "v_" <> body
