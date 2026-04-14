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

-- | Add a StandAloneSig row for a LocalVarSig.
-- nLocals = number of locals: local 0 is object[], rest are object.
-- Returns the metadata token (table 0x11 << 24 | row).
addLocalSig :: Int -> AsmM Word32
addLocalSig nLocals = do
  let -- LocalVarSig: 0x07, count, types...
      -- local 0: object[] (SZARRAY + OBJECT), rest: object
      localTypes = [0x1D, 0x1C] <> replicate (nLocals - 1) 0x1C
      blob = 0x07 : fromIntegral nLocals : localTypes
  bi <- addBlob blob
  st <- get
  let row = st.pSASn + 1
  put st {pSAS = st.pSAS <> [w16 bi], pSASn = row}
  pure (0x11000000 .|. row)

-- | Count the number of local variable slots needed for a CExpr.
-- Returns 0 if no CCase is present; otherwise 1 (arrSlot) + max bound vars.
exprLocalsNeeded :: CExpr -> Int
exprLocalsNeeded = \case
  CCase _ alts -> 1 + foldl' max 0 [length vs | (_, vs, _) <- alts]
  CCall f xs -> foldl' max 0 (exprLocalsNeeded f : map exprLocalsNeeded xs)
  CCon _ fields -> foldl' max 0 (map exprLocalsNeeded fields)
  _ -> 0

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

cilBgeS, cilBrS :: Word8 -> [Word8]
cilBgeS off = [0x2F, off]
cilBrS off = [0x2B, off]

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
    mLocalSigTok :: Word32 -- StandAloneSig token for locals (0 = no locals)
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

  -- Pre-compute method name → MethodDef token map
  let declName' (CFunDef n _ _) = n
      declName' (CValDef n _) = n
      userNames = [mangle (declName' d) | d <- decls]
      allNames = [".ctor", "__concat", "__print"] <> userNames <> ["Main"]
      tokMap = Map.fromList [(n, tokMD (fromIntegral i)) | (i, n) <- zip ([1 ..] :: [Int]) allNames]

  let valNames = Set.fromList [n | CValDef n _ <- decls]
      funNames = Set.fromList [n | CFunDef n _ _ <- decls]
      arities = Map.fromList [(n, length as) | CFunDef n as _ <- decls]
      ctx = ECtx {eParams = Map.empty, eLocals = Map.empty, eValDefs = valNames, eFunDefs = funNames, eArities = arities, eToks = tokMap}

  m0 <- mkInit
  m1 <- mkConcat
  m2 <- mkPrint
  userMs <- traverse (mkDecl ctx) decls
  mEntry <- mkMain tokMap
  pure (m0 : m1 : m2 : userMs <> [mEntry])

-- ════════════════════════════════════════════════════════════════════════════
-- Fixed methods
-- ════════════════════════════════════════════════════════════════════════════

mkInit :: AsmM MInfo
mkInit = do
  ni <- w16 <$> addStr ".ctor"
  si <- w16 <$> addBlob (sigInstance etVoid [])
  ps <- addParams 0
  let code = cilLdarg 0 <> cilCall (tokMR 1) <> cilRet -- MemberRef 1 = Object::.ctor
  pure MInfo {mImplFlags = 0, mFlags = 0x1886, mName = ni, mSig = si, mParamList = ps, mCode = code, mLocalSigTok = 0}

mkConcat :: AsmM MInfo
mkConcat = do
  ni <- w16 <$> addStr "__concat"
  si <- w16 <$> addBlob (sigStatic etObject 2)
  ps <- addParams 2
  let code = cilLdarg 0 <> cilLdarg 1 <> cilCall (tokMR 2) <> cilRet -- MemberRef 2 = String.Concat
  pure MInfo {mImplFlags = 0, mFlags = 0x0096, mName = ni, mSig = si, mParamList = ps, mCode = code, mLocalSigTok = 0}

mkPrint :: AsmM MInfo
mkPrint = do
  ni <- w16 <$> addStr "__print"
  si <- w16 <$> addBlob (sigStatic etObject 1)
  ps <- addParams 1
  let code = cilLdarg 0 <> cilCall (tokMR 3) <> cilLdnull <> cilRet -- MemberRef 3 = Console.Write
  pure MInfo {mImplFlags = 0, mFlags = 0x0096, mName = ni, mSig = si, mParamList = ps, mCode = code, mLocalSigTok = 0}

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
  pure MInfo {mImplFlags = 0, mFlags = 0x0096, mName = ni, mSig = si, mParamList = ps, mCode = code, mLocalSigTok = 0}

-- ════════════════════════════════════════════════════════════════════════════
-- User declaration methods
-- ════════════════════════════════════════════════════════════════════════════

data ECtx = ECtx
  { eParams :: Map Text Int,
    eLocals :: Map Text Int, -- case-bound variable → ldloc slot
    eValDefs :: Set Text,
    eFunDefs :: Set Text,
    eArities :: Map Text Int,
    eToks :: Map Text Word32
  }

mkDecl :: ECtx -> CDecl -> AsmM MInfo
mkDecl baseCtx = \case
  CFunDef nm args body -> do
    let ctx = baseCtx {eParams = Map.fromList (zip args [0 ..])}
        nLocals = exprLocalsNeeded body
    ni <- w16 <$> addStr (mangle nm)
    si <- w16 <$> addBlob (sigStatic etObject (length args))
    ps <- addParams (length args)
    localTok <- if nLocals > 0 then addLocalSig nLocals else pure 0
    code <- emitExpr ctx body
    pure MInfo {mImplFlags = 0, mFlags = 0x0096, mName = ni, mSig = si, mParamList = ps, mCode = code <> cilRet, mLocalSigTok = localTok}
  CValDef nm rhs -> do
    let ctx = baseCtx {eParams = Map.empty}
        nLocals = exprLocalsNeeded rhs
    ni <- w16 <$> addStr (mangle nm)
    si <- w16 <$> addBlob (sigStatic etObject 0)
    ps <- addParams 0
    localTok <- if nLocals > 0 then addLocalSig nLocals else pure 0
    code <- emitExpr ctx rhs
    pure MInfo {mImplFlags = 0, mFlags = 0x0096, mName = ni, mSig = si, mParamList = ps, mCode = code <> cilRet, mLocalSigTok = localTok}

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
  CPrim _ -> pure cilLdnull
  CCon tag fields -> do
    -- Create Object[] container: [tag_as_boxed_Int32, field1, field2, ...]
    let nSlots = 1 + length fields
    trObj <- addTypeRef (resScopeAR 1) "Object" "System"
    trInt32 <- addTypeRef (resScopeAR 1) "Int32" "System"
    let allocCode = cilLdcI4 nSlots <> cilNewarr (tokTR trObj)
        storeTag =
          cilDup
            <> cilLdcI4 0
            <> cilLdcI4 tag
            <> cilBox (tokTR trInt32)
            <> cilStelemRef
    fieldCodes <- forM (zip fields [1 :: Int ..]) $ \(fld, i) -> do
      fldCode <- emitExpr ctx fld
      pure (cilDup <> cilLdcI4 i <> fldCode <> cilStelemRef)
    pure (allocCode <> storeTag <> concat fieldCodes)
  CCase scrut alts -> do
    trInt32 <- addTypeRef (resScopeAR 1) "Int32" "System"
    scrutCode <- emitExpr ctx scrut
    let sorted = sortWith (\(t, _, _) -> t) alts
        -- Store array to local 0, extract tag to local 1
        arrSlot = 0 :: Int
        bindSlotStart = 1 :: Int
    -- Emit arm bodies with bound variables
    armCodes <- forM sorted $ \(_, vars, body) -> do
      let bindings = zip vars [bindSlotStart ..]
          ctx' = ctx {eLocals = foldl' (\m (v, s) -> Map.insert v s m) ctx.eLocals bindings}
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
                <> [0x40] <> i32le skipLen -- bne.un
                <> [0x26] -- pop
                <> armCode
                <> [0x38] <> i32le joinLen -- br
                <> restCode
        chainCode = buildChain (zip tags armCodes)
    pure (scrutCode <> extractAndStore <> chainCode)
  CCall f xs -> case f of
    CPrim PrimConcat | [a, b] <- xs -> do
      ca <- emitExpr ctx a
      cb <- emitExpr ctx b
      pure (ca <> cb <> cilCall (lkTok ctx "__concat"))
    CPrim PrimPrint | [x] <- xs -> do
      cx <- emitExpr ctx x
      pure (cx <> cilCall (lkTok ctx "__print"))
    CVar n | n `Set.member` ctx.eFunDefs -> do
      argCodes <- traverse (emitExpr ctx) xs
      pure (concat argCodes <> cilCall (lkTok ctx (mangle n)))
    _ -> do
      fCode <- emitExpr ctx f
      let arity = length xs
      (tsTok, _, invTok) <- funcTokens arity
      argCodes <- traverse (emitExpr ctx) xs
      pure (fCode <> cilCastclass tsTok <> concat argCodes <> cilCallvirt invTok)

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
encodeBody :: Word32 -> [Word8] -> [Word8]
encodeBody localSigTok code
  | len < 64 && localSigTok == 0 = fromIntegral ((len `shiftL` 2) .|. 0x02) : code -- tiny
  | otherwise =
      let flags = if localSigTok /= 0 then 0x3013 else 0x3003 -- 0x0010 = InitLocals
       in w16le flags <> w16le 16 <> w32le (fromIntegral len) <> w32le localSigTok <> code -- fat
  where
    len = length code

-- | Lay out method bodies after CLI header. Returns (list of RVA, all body bytes, end offset).
layoutBodies :: [MInfo] -> ([Word32], [Word8], Int)
layoutBodies = go peCliHdrSize [] []
  where
    go off rvas bytes [] = (reverse rvas, concat (reverse bytes), off)
    go off rvas bytes (m : ms) =
      let code = m.mCode
          hasFat = length code >= 64 || m.mLocalSigTok /= 0
          off' = if hasFat then align4 off else off
          pad = replicate (off' - off) 0x00
          body = encodeBody m.mLocalSigTok code
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
