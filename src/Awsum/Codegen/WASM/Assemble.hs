-- | WebAssembly binary (.wasm) assembler for Awsum 'Core'.
--
-- Generates a single @.wasm@ module with WASI imports for I\/O.
-- All values are @i32@ (pointers into linear memory). Strings are
-- null-terminated bytes. Bump allocator for dynamic memory.
-- @funcref@ table for higher-order functions.
module Awsum.Codegen.WASM.Assemble (assembleWASM) where

import Awsum.Core
import Awsum.HM (rowTag)
import Awsum.Syntax (Type' (..), noSpan)
import Data.Bits (shiftR, (.&.), (.|.))
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

-- | Produce a complete .wasm binary as a strict ByteString.
assembleWASM :: PreludeTags -> CoreProgram -> BS.ByteString
assembleWASM ptags prog = toStrict (B.toLazyByteString (buildModule ptags prog))

-- ════════════════════════════════════════════════════════════════════════════
-- LEB128 encoding
-- ════════════════════════════════════════════════════════════════════════════

encodeULEB128 :: Word32 -> [Word8]
encodeULEB128 n
  | n < 128 = [fromIntegral n]
  | otherwise = fromIntegral (n .&. 0x7F .|. 0x80) : encodeULEB128 (n `shiftR` 7)

encodeSLEB128 :: Int32 -> [Word8]
encodeSLEB128 n
  | n >= -64 && n < 64 = [fromIntegral (n .&. 0x7F)]
  | otherwise = fromIntegral (n .&. 0x7F .|. 0x80) : encodeSLEB128 (n `shiftR` 7)

-- | SLEB128 encoder for 64-bit signed values. Same algorithm as
--   'encodeSLEB128', wider type so i64 constants outside the i32 range
--   (e.g. 4294967295 in 'codeAddU32', 'codeMulU32', 'codeParseUInt32')
--   round-trip without truncation.
encodeSLEB128I64 :: Int64 -> [Word8]
encodeSLEB128I64 n
  | n >= -64 && n < 64 = [fromIntegral (n .&. 0x7F)]
  | otherwise = fromIntegral (n .&. 0x7F .|. 0x80) : encodeSLEB128I64 (n `shiftR` 7)

encodeVec :: [[Word8]] -> [Word8]
encodeVec items = encodeULEB128 (fromIntegral (length items)) <> concat items

encodeBytes :: [Word8] -> [Word8]
encodeBytes bs = encodeULEB128 (fromIntegral (length bs)) <> bs

encodeName :: Text -> [Word8]
encodeName t =
  let bs = BS.unpack (encodeUtf8 t)
   in encodeULEB128 (fromIntegral (length bs)) <> bs

-- ════════════════════════════════════════════════════════════════════════════
-- WASM opcodes
-- ════════════════════════════════════════════════════════════════════════════

opUnreachable :: Word8
opUnreachable = 0x00

opBlock, opLoop, opIf, opElse, opEnd :: Word8
opBlock = 0x02
opLoop = 0x03
opIf = 0x04
opElse = 0x05
opEnd = 0x0B

opBr, opBrIf, opCall, opCallIndirect, opDrop :: Word8
opBr = 0x0C
opBrIf = 0x0D
opCall = 0x10
opCallIndirect = 0x11
opDrop = 0x1A

opLocalGet, opLocalSet, opLocalTee, opGlobalGet, opGlobalSet :: Word8
opLocalGet = 0x20
opLocalSet = 0x21
opLocalTee = 0x22
opGlobalGet = 0x23
opGlobalSet = 0x24

opI32Load, opI32Load8U, opI32Store, opI32Store8 :: Word8
opI32Load = 0x28
opI32Load8U = 0x2D
opI32Store = 0x36
opI32Store8 = 0x3A

opI32Const :: Word8
opI32Const = 0x41

opMemorySize, opMemoryGrow :: Word8
opMemorySize = 0x3F
opMemoryGrow = 0x40

opI32Eqz, opI32Eq, opI32Ne, opI32Add, opI32Mul, opI32And, opI32LtU, opI32GtU, opI32GeU :: Word8
opI32Eqz = 0x45
opI32Eq = 0x46
opI32Ne = 0x47
opI32Add = 0x6A
opI32Mul = 0x6C
opI32And = 0x71
opI32LtU = 0x49
opI32GtU = 0x4B
opI32GeU = 0x4F

opI32Sub, opI32DivU, opI32RemU, opI32LtS, opI32Xor, opI32GeS :: Word8
opI32Sub = 0x6B
opI32DivU = 0x6E
opI32RemU = 0x70
opI32LtS = 0x48
opI32Xor = 0x73
opI32GeS = 0x4E

-- Keep '$__free' in the runtime even though no codegen path
-- currently calls it (transitional stub no-ops every
-- 'CDrop' until full RC lands on WASM binary). Defining the
-- index here documents the runtime ABI and stops GHC from
-- warning that the binding is unused.
_referenceIdxFreeForFutureUse :: (Word32, Word32, Word32, Word32, Word32)
_referenceIdxFreeForFutureUse = (idxFree, idxAllocShaped, idxIncRef, idxFreeRecursive, idxFreeWorklistPush)

-- Ctz / Clz / Shl / LeU / Return for '$__alloc' and '$__free'
-- freelist arithmetic.
opI32Clz, opI32Ctz, opI32Shl, opI32LeU, opReturn :: Word8
opI32Clz = 0x67
opI32Ctz = 0x68
opI32Shl = 0x74
opI32LeU = 0x4D
opReturn = 0x0F

opI64Const, opI64Add, opI64Sub, opI64Mul, opI64Shl, opI64LtS, opI64GtS, opI64GtU, opI32WrapI64, opI64ExtendI32S, opI64ExtendI32U :: Word8
opI64Const = 0x42
opI64Add = 0x7C
opI64Sub = 0x7D
opI64Mul = 0x7E
opI64Shl = 0x86
opI64LtS = 0x53
opI64GtS = 0x55
opI64GtU = 0x56
opI32WrapI64 = 0xA7
opI64ExtendI32S = 0xAC
opI64ExtendI32U = 0xAD

-- WASM type encoding
valtypeI32, valtypeI64 :: Word8
valtypeI32 = 0x7F
valtypeI64 = 0x7E

blocktypeVoid :: Word8
blocktypeVoid = 0x40

blocktypeI32 :: Word8
blocktypeI32 = valtypeI32

-- ════════════════════════════════════════════════════════════════════════════
-- Analysis context
-- ════════════════════════════════════════════════════════════════════════════

data WasmInfo = WasmInfo
  { wiStringPool :: Map Text Int, -- string -> memory offset
    wiHeapStart :: Int,
    wiValDefs :: Set Text,
    wiFunDefs :: Set Text,
    wiArities :: Map Text Int,
    wiTableMap :: Map Text Int, -- func name -> table index
    wiFunList :: [Text], -- all CFunDef names in decl order
    wiIndirectArities :: Set Int,
    -- Function indices (imports first, then locals)
    wiFuncIdx :: Map Text Word32, -- name -> function index
    -- Globally-unique constructor tags for prelude types — runtime
    -- helpers built here construct values of these types out of band
    -- of user code so they need to match the user's CCon/CCase
    -- numbering.
    wiTags :: PreludeTags
  }

-- | Emit "store tag @n@ at offset 0 of the cell pointed to by local
-- @cellLocal@" — i.e. the byte sequence
-- @local.get cellLocal; i32.const n; i32.store offset=0@. Used
-- everywhere a runtime helper writes the tag word into a freshly
-- allocated CCon-shaped cell.
storeTagBytes :: Word32 -> Int -> [Word8]
storeTagBytes cellLocal tagValue =
  [opLocalGet]
    <> encodeULEB128 cellLocal
    <> [opI32Const]
    <> encodeSLEB128 (fromIntegral tagValue)
    <> [opI32Store, 0x02, 0x00]

-- Import count: fd_write(0), args_sizes_get(1), args_get(2), fd_read(3)
importCount :: Word32
importCount = 4

-- Runtime helper count: __alloc, __free, __memcpy,
-- __concat, __print, __box_i32, __show_i32, __show_u32, __predInt32,
-- __predUInt8, __predUInt32, __succInt32, __succUInt8, __succUInt32,
-- __eq_i32, __addInt32, __subInt32, __mulInt32, __negInt32, __addUInt8,
-- __subUInt8, __mulUInt8, __addUInt32, __subUInt32, __mulUInt32,
-- __splitOnFirst, __parseInt32, __parseUInt8, __parseUInt32,
-- __lengthCodePoints, __lengthUtf16CodeUnits, __lengthUtf8Bytes,
-- __entryArgEither, __utf16_of_range, __getArgs,
-- __stdinReadAll, __alloc_shaped, __inc_ref, __free_recursive,
-- __free_worklist_push, __memcmp, __eqString
runtimeCount :: Word32
runtimeCount = 42

-- Runtime helper function indices (after imports). '$__free' slots
-- in right after '$__alloc'. The RC helpers (@__alloc_shaped,
-- __inc_ref, __free_recursive, __free_worklist_push@) sit at the
-- end so the earlier indices stay stable when new helpers are
-- appended.
idxAlloc, idxFree, idxMemcpy, idxConcat, idxPrint, idxBoxI32, idxShowI32, idxShowU32, idxPredI32, idxPredU8, idxPredU32, idxSuccI32, idxSuccU8, idxSuccU32, idxEqI32, idxAddI32, idxSubI32, idxMulI32, idxNegI32, idxAddU8, idxSubU8, idxMulU8, idxAddU32, idxSubU32, idxMulU32, idxSplitOnFirst, idxParseI32, idxParseU8, idxParseU32, idxLengthCodePoints, idxLengthUtf16CodeUnits, idxLengthBytesAsUtf8, idxEntryArgEither, idxUtf16OfRange, idxGetArgs, idxStdinReadAll, idxAllocShaped, idxIncRef, idxFreeRecursive, idxFreeWorklistPush, idxMemcmp, idxEqString :: Word32
idxAlloc = importCount
idxFree = importCount + 1
idxMemcpy = importCount + 2
idxConcat = importCount + 3
idxPrint = importCount + 4
idxBoxI32 = importCount + 5
idxShowI32 = importCount + 6
idxShowU32 = importCount + 7
idxPredI32 = importCount + 8
idxPredU8 = importCount + 9
idxPredU32 = importCount + 10
idxSuccI32 = importCount + 11
idxSuccU8 = importCount + 12
idxSuccU32 = importCount + 13
idxEqI32 = importCount + 14
idxAddI32 = importCount + 15
idxSubI32 = importCount + 16
idxMulI32 = importCount + 17
idxNegI32 = importCount + 18
idxAddU8 = importCount + 19
idxSubU8 = importCount + 20
idxMulU8 = importCount + 21
idxAddU32 = importCount + 22
idxSubU32 = importCount + 23
idxMulU32 = importCount + 24
idxSplitOnFirst = importCount + 25
idxParseI32 = importCount + 26
idxParseU8 = importCount + 27
idxParseU32 = importCount + 28
idxLengthCodePoints = importCount + 29
idxLengthUtf16CodeUnits = importCount + 30
idxLengthBytesAsUtf8 = importCount + 31
idxEntryArgEither = importCount + 32
idxUtf16OfRange = importCount + 33
idxGetArgs = importCount + 34
idxStdinReadAll = importCount + 35
idxAllocShaped = importCount + 36
idxIncRef = importCount + 37
idxFreeRecursive = importCount + 38
idxFreeWorklistPush = importCount + 39
idxMemcmp = importCount + 40
idxEqString = importCount + 41

buildInfo :: PreludeTags -> CoreProgram -> WasmInfo
buildInfo ptags prog@(CoreProgram decls) =
  let (pool, _emptyOff, heapStart) = buildStringPool prog
      valNames = Set.fromList [n | CValDef n _ <- decls]
      funNames = Set.fromList [n | CFunDef n _ _ <- decls]
      arities = Map.fromList [(n, length as) | CFunDef n as _ <- decls]
      funList = [n | CFunDef n _ _ <- decls]
      tableMap = Map.fromList (zip funList [0 :: Int ..])
      indArities = collectIndirectArities prog funNames
      -- User function indices start after imports + runtime helpers
      userStart = importCount + runtimeCount
      allDecls = [(n, fromIntegral i + userStart) | (i, d) <- zip [0 :: Int ..] decls, let n = declName d]
      -- _start is the last function
      startIdx = userStart + fromIntegral (length decls)
      funcIdx = Map.fromList $ allDecls <> [("_start", startIdx)]
   in WasmInfo
        { wiStringPool = pool,
          wiHeapStart = heapStart,
          wiValDefs = valNames,
          wiFunDefs = funNames,
          wiArities = arities,
          wiTableMap = tableMap,
          wiFunList = funList,
          wiIndirectArities = indArities,
          wiFuncIdx = funcIdx,
          wiTags = ptags
        }

declName :: CDecl -> Text
declName = \case
  CFunDef n _ _ -> n
  CValDef n _ -> n

-- ════════════════════════════════════════════════════════════════════════════
-- String pool (shared logic with WASM.hs)
-- ════════════════════════════════════════════════════════════════════════════

scratchSize :: Int
scratchSize = 64

-- | 20-byte header prepended to every string in the pool. Layout:
--   12-byte allocator header (flag + refcount + shape) + 8-byte
--   string length header (utf8_bytes : i32 LE, utf16_units : i32
--   LE). The user pointer is @flag_start + 12@; from the user
--   pointer the legacy layout holds (byte_count at +0, utf16 at +4,
--   payload at +8). No NUL terminator. Mirrors
--   'Awsum.Codegen.WASM.stringHeaderSize'.
stringHeaderSize :: Int
stringHeaderSize = 20

-- | UTF-16 code unit count (BMP -> 1, supplementary -> 2). Mirrors
--   'Awsum.Codegen.WASM.utf16CountOfText'.
utf16CountOfText :: Text -> Int
utf16CountOfText = T.foldl' (\n c -> n + if Char.ord c > 0xFFFF then 2 else 1) (0 :: Int)

-- | Each string entry has a 12-byte @{i32 flag = 0, i32
--   refcount = 0, i32 shape = 0}@ prefix in front of the legacy 8-byte
--   length header. The map values are USER pointers (flag_start + 12);
--   from a user pointer the layout is unchanged (byte_count at +0,
--   utf16 at +4, payload at +8).
buildStringPool :: CoreProgram -> (Map Text Int, Int, Int)
buildStringPool (CoreProgram decls) =
  let strs = ordNub $ "" : concatMap stringsInDecl decls
      entrySize s = stringHeaderSize + BS.length (encodeUtf8 s)
      flagStartScan = scanl (+) scratchSize (map entrySize strs)
      flagStarts = take (length strs) flagStartScan
      userPtrs = map (+ 12) flagStarts
      pool = Map.fromList (zip strs userPtrs)
      emptyOff = fromMaybe (scratchSize + 12) (Map.lookup "" pool)
      heapStart = fromMaybe scratchSize $ viaNonEmpty Relude.last flagStartScan
   in (pool, emptyOff, heapStart)

stringsInDecl :: CDecl -> [Text]
stringsInDecl = \case
  CFunDef _ _ body -> stringsInExpr body
  CValDef _ rhs -> stringsInExpr rhs

stringsInExpr :: CExpr -> [Text]
stringsInExpr = \case
  CString s -> [s]
  CVar _ -> []
  CIntLit _ _ -> []
  CBuiltIn _ -> []
  CCon _ fields -> concatMap stringsInExpr fields
  CCase scrut alts -> stringsInExpr scrut <> concatMap (\(_, _, body) -> stringsInExpr body) alts
  CRow _ v -> stringsInExpr v
  CRowCase scrut alts -> stringsInExpr scrut <> concatMap (\(_, _, body) -> stringsInExpr body) alts
  CCall f xs -> stringsInExpr f <> concatMap stringsInExpr xs
  CLoop b -> stringsInExpr b
  CContinue xs -> concatMap stringsInExpr xs
  CDrop _ _ body -> stringsInExpr body
  CReuse _ _ fs -> concatMap stringsInExpr fs

collectIndirectArities :: CoreProgram -> Set Text -> Set Int
collectIndirectArities (CoreProgram decls) funNames =
  Set.fromList $ concatMap (collectInDecl funNames) decls
  where
    collectInDecl :: Set Text -> CDecl -> [Int]
    collectInDecl fns = \case
      CFunDef _ args body -> collectInExpr fns (Set.fromList args) body
      CValDef _ rhs -> collectInExpr fns Set.empty rhs

    collectInExpr :: Set Text -> Set Text -> CExpr -> [Int]
    collectInExpr fns params = \case
      CCall f xs ->
        let fromF = case f of
              CVar n | n `Set.member` params -> [length xs]
              _ -> []
            fromChildren = collectInExpr fns params f <> concatMap (collectInExpr fns params) xs
         in fromF <> fromChildren
      _ -> []

-- ════════════════════════════════════════════════════════════════════════════
-- Type section
-- ════════════════════════════════════════════════════════════════════════════

-- | Build type section. Returns (section_bytes, type_index_map).
--
-- We deduplicate function types. Types needed:
--   - WASI imports: (i32,i32,i32,i32)->i32, (i32,i32)->i32
--   - Runtime helpers: various arities (0,1,2,3 params) -> i32, plus memcpy (3 params) -> void
--   - User functions: N params -> i32, or 0 params -> i32 (ValDef)
--   - _start: () -> void
--   - Indirect call types: per arity
--
-- We represent types as (params, has_result):
--   (N_i32_params, True)  = (param i32 ... i32) (result i32)
--   (N_i32_params, False) = (param i32 ... i32)
data FuncType = FuncType Int Bool -- param_count, has_result
  deriving stock (Eq, Ord, Show)

buildTypeSection :: WasmInfo -> CoreProgram -> ([Word8], Map FuncType Word32)
buildTypeSection info (CoreProgram decls) =
  let -- Collect all needed function types
      needed :: [FuncType]
      needed =
        ordNub
          -- WASI imports
          $ [ FuncType 4 True, -- fd_write
              FuncType 2 True, -- args_sizes_get
              FuncType 2 True, -- args_get (dedup with above)
              FuncType 4 True -- fd_read (dedup with fd_write)
            ]
          -- Runtime helpers
          <> [ FuncType 1 True, -- __alloc(i32)->i32
               FuncType 1 False, -- __free(i32)->void
               FuncType 3 False, -- __memcpy(i32,i32,i32)->void
               FuncType 2 True, -- __concat (dedup with args_sizes_get)
               FuncType 1 True, -- __print (dedup with __alloc)
               FuncType 0 True, -- __getArgs()->i32
               FuncType 2 True, -- __utf16_of_range(p, len) (dedup with __concat)
               FuncType 2 True, -- __alloc_shaped(size, shape)->i32 (dedup with __concat)
               FuncType 1 False, -- __inc_ref(p)->void (dedup with __free)
               FuncType 1 False, -- __free_recursive(p)->void (dedup with __free)
               FuncType 1 False, -- __free_worklist_push(p)->void (dedup with __free)
               FuncType 3 True -- __memcmp(a,b,len)->i32 (new shape)
             ]
          -- User functions
          <> [funcTypeOfDecl d | d <- decls]
          -- _start
          <> [FuncType 0 False]
          -- Indirect call types
          <> [FuncType a True | a <- Set.toList info.wiIndirectArities]
      typeMap :: Map FuncType Word32
      typeMap = Map.fromList (zip needed [0 ..])
      encodeFT (FuncType nParams hasResult) =
        [0x60] -- functype marker
          <> encodeVec (replicate nParams [valtypeI32])
          <> if hasResult
            then encodeVec [[valtypeI32]]
            else encodeVec []
      content = encodeVec (map encodeFT needed)
   in (buildSection 1 content, typeMap)

funcTypeOfDecl :: CDecl -> FuncType
funcTypeOfDecl = \case
  CFunDef _ args _ -> FuncType (length args) True
  CValDef _ _ -> FuncType 0 True

-- ════════════════════════════════════════════════════════════════════════════
-- Import section
-- ════════════════════════════════════════════════════════════════════════════

buildImportSection :: Map FuncType Word32 -> [Word8]
buildImportSection typeMap =
  let wasi :: Text
      wasi = "wasi_snapshot_preview1"
      mkImport :: Text -> FuncType -> [Word8]
      mkImport name ft =
        encodeName wasi
          <> encodeName name
          <> [0x00] -- func import
          <> encodeULEB128 (lookupType ft typeMap)
      content =
        encodeVec
          [ mkImport "fd_write" (FuncType 4 True),
            mkImport "args_sizes_get" (FuncType 2 True),
            mkImport "args_get" (FuncType 2 True),
            mkImport "fd_read" (FuncType 4 True)
          ]
   in buildSection 2 content

-- ════════════════════════════════════════════════════════════════════════════
-- Function section
-- ════════════════════════════════════════════════════════════════════════════

buildFunctionSection :: WasmInfo -> Map FuncType Word32 -> CoreProgram -> [Word8]
buildFunctionSection _info typeMap (CoreProgram decls) =
  let -- Local functions: runtime helpers + user decls + _start
      localTypes =
        -- Runtime helpers
        [ lookupType (FuncType 1 True) typeMap, -- __alloc
          lookupType (FuncType 1 False) typeMap, -- __free
          lookupType (FuncType 3 False) typeMap, -- __memcpy
          lookupType (FuncType 2 True) typeMap, -- __concat
          lookupType (FuncType 1 True) typeMap, -- __print
          lookupType (FuncType 1 True) typeMap, -- __box_i32
          lookupType (FuncType 1 True) typeMap, -- __show_i32
          lookupType (FuncType 1 True) typeMap, -- __show_u32
          lookupType (FuncType 1 True) typeMap, -- __predInt32
          lookupType (FuncType 1 True) typeMap, -- __predUInt8
          lookupType (FuncType 1 True) typeMap, -- __predUInt32
          lookupType (FuncType 1 True) typeMap, -- __succInt32
          lookupType (FuncType 1 True) typeMap, -- __succUInt8
          lookupType (FuncType 1 True) typeMap, -- __succUInt32
          lookupType (FuncType 2 True) typeMap, -- __eq_i32
          lookupType (FuncType 2 True) typeMap, -- __addInt32
          lookupType (FuncType 2 True) typeMap, -- __subInt32
          lookupType (FuncType 2 True) typeMap, -- __mulInt32
          lookupType (FuncType 1 True) typeMap, -- __negInt32
          lookupType (FuncType 2 True) typeMap, -- __addUInt8
          lookupType (FuncType 2 True) typeMap, -- __subUInt8
          lookupType (FuncType 2 True) typeMap, -- __mulUInt8
          lookupType (FuncType 2 True) typeMap, -- __addUInt32
          lookupType (FuncType 2 True) typeMap, -- __subUInt32
          lookupType (FuncType 2 True) typeMap, -- __mulUInt32
          lookupType (FuncType 2 True) typeMap, -- __splitOnFirst
          lookupType (FuncType 1 True) typeMap, -- __parseInt32
          lookupType (FuncType 1 True) typeMap, -- __parseUInt8
          lookupType (FuncType 1 True) typeMap, -- __parseUInt32
          lookupType (FuncType 1 True) typeMap, -- __lengthCodePoints
          lookupType (FuncType 1 True) typeMap, -- __lengthUtf16CodeUnits
          lookupType (FuncType 1 True) typeMap, -- __lengthUtf8Bytes
          lookupType (FuncType 2 True) typeMap, -- __entryArgEither(ptr, len)
          lookupType (FuncType 2 True) typeMap, -- __utf16_of_range
          lookupType (FuncType 0 True) typeMap, -- __getArgs
          lookupType (FuncType 0 True) typeMap, -- __stdinReadAll
          lookupType (FuncType 2 True) typeMap, -- __alloc_shaped
          lookupType (FuncType 1 False) typeMap, -- __inc_ref
          lookupType (FuncType 1 False) typeMap, -- __free_recursive
          lookupType (FuncType 1 False) typeMap, -- __free_worklist_push
          lookupType (FuncType 3 True) typeMap, -- __memcmp
          lookupType (FuncType 2 True) typeMap -- __eqString
        ]
          -- User declarations
          <> [lookupType (funcTypeOfDecl d) typeMap | d <- decls]
          -- _start
          <> [lookupType (FuncType 0 False) typeMap]
      content = encodeVec (map encodeULEB128 localTypes)
   in buildSection 3 content

-- ════════════════════════════════════════════════════════════════════════════
-- Table section
-- ════════════════════════════════════════════════════════════════════════════

buildTableSection :: WasmInfo -> [Word8]
buildTableSection info =
  let n = length info.wiFunList
   in if n == 0
        then [] -- no table needed
        else
          let content =
                encodeVec
                  [ [0x70] -- funcref
                      <> [0x00] -- limits: has_max = false
                      <> encodeULEB128 (fromIntegral n)
                  ]
           in buildSection 4 content

-- ════════════════════════════════════════════════════════════════════════════
-- Memory section
-- ════════════════════════════════════════════════════════════════════════════

-- | Initial pages must cover scratch + data section (literals are
--   written at module-instantiate time, before any 'memory.grow').
--   Heap allocations live above 'heapStart' and grow dynamically.
buildMemorySection :: WasmInfo -> [Word8]
buildMemorySection info =
  let initialPages :: Word32
      initialPages = max 1 (fromIntegral ((info.wiHeapStart + wasmPageSize - 1) `div` wasmPageSize))
      content =
        encodeVec
          [ [0x00] -- limits: no max
              <> encodeULEB128 initialPages
          ]
   in buildSection 5 content

-- | A WebAssembly memory page is 64 KiB.
wasmPageSize :: Int
wasmPageSize = 65536

-- ════════════════════════════════════════════════════════════════════════════
-- Global section
-- ════════════════════════════════════════════════════════════════════════════

buildGlobalSection :: WasmInfo -> [Word8]
buildGlobalSection info =
  let mutI32Init :: Int -> [Word8]
      mutI32Init initial =
        [valtypeI32, 0x01]
          <> [opI32Const]
          <> encodeSLEB128 (fromIntegral initial)
          <> [opEnd]
      content =
        encodeVec
          [ mutI32Init info.wiHeapStart,
            -- '$__wl_buf' / '$__wl_top' / '$__wl_cap': worklist
            -- state backing '$__free_recursive' — see the matching
            -- WAT comment in 'Awsum.Codegen.WASM.global'. Indices
            -- 1 / 2 / 3 in the global section; the existing
            -- '$heap' stays at index 0 so '__alloc' / bump-path
            -- references remain valid.
            mutI32Init 0,
            mutI32Init 0,
            mutI32Init 0
          ]
   in buildSection 6 content

-- ════════════════════════════════════════════════════════════════════════════
-- Export section
-- ════════════════════════════════════════════════════════════════════════════

buildExportSection :: WasmInfo -> [Word8]
buildExportSection info =
  let startIdx = fromMaybe 0 (Map.lookup "_start" info.wiFuncIdx)
      content =
        encodeVec
          [ encodeName "_start" <> [0x00] <> encodeULEB128 startIdx, -- func export
            encodeName "memory" <> [0x02] <> encodeULEB128 0 -- memory export
          ]
   in buildSection 7 content

-- ════════════════════════════════════════════════════════════════════════════
-- Element section
-- ════════════════════════════════════════════════════════════════════════════

buildElementSection :: WasmInfo -> [Word8]
buildElementSection info
  | null info.wiFunList = []
  | otherwise =
      let funcIdxs = [fromMaybe 0 (Map.lookup n info.wiFuncIdx) | n <- info.wiFunList]
          content =
            encodeVec
              [ [0x00] -- active segment, table 0
                  <> [opI32Const]
                  <> encodeSLEB128 0
                  <> [opEnd]
                  <> encodeVec (map encodeULEB128 funcIdxs)
              ]
       in buildSection 9 content

-- ════════════════════════════════════════════════════════════════════════════
-- Code section
-- ════════════════════════════════════════════════════════════════════════════

buildCodeSection :: WasmInfo -> Map FuncType Word32 -> CoreProgram -> [Word8]
buildCodeSection info typeMap (CoreProgram decls) =
  let bodies =
        -- Runtime helpers
        [ codeAlloc,
          codeFree,
          codeMemcpy,
          codeConcat info,
          codePrint info,
          codeBoxI32 info,
          codeShowI32 info,
          codeShowU32 info,
          codePredI32 info,
          codePredU8 info,
          codePredU32 info,
          codeSuccI32 info,
          codeSuccU8 info,
          codeSuccU32 info,
          codeEqI32 info,
          codeAddI32 info,
          codeSubI32 info,
          codeMulI32 info,
          codeNegI32 info,
          codeAddU8 info,
          codeSubU8 info,
          codeMulU8 info,
          codeAddU32 info,
          codeSubU32 info,
          codeMulU32 info,
          codeSplitOnFirst info,
          codeParseInt32 info,
          codeParseUInt8 info,
          codeParseUInt32 info,
          codeLengthCodePoints,
          codeLengthUtf16CodeUnits,
          codeLengthBytesAsUtf8,
          codeEntryArgEither info,
          codeUtf16OfRange,
          codeGetArgs (wiTags info),
          codeStdinReadAll,
          codeAllocShaped,
          codeIncRef,
          codeFreeRecursive,
          codeFreeWorklistPush,
          codeMemcmp,
          codeEqString info
        ]
          -- User declarations
          <> map (codeUserDecl info typeMap) decls
          -- _start
          <> [codeStart info]
      content = encodeVec bodies
   in buildSection 10 content

-- | Encode a function body: local declarations + instructions + end.
encodeBody :: [Word8] -> [Word8] -> [Word8]
encodeBody locals instrs =
  let body = locals <> instrs <> [opEnd]
   in encodeBytes body

-- | Encode local variable declarations.
encodeLocals :: Int -> [Word8]
encodeLocals n
  | n == 0 = encodeULEB128 0
  | otherwise = encodeVec [encodeULEB128 (fromIntegral n) <> [valtypeI32]]

-- ════════════════════════════════════════════════════════════════════════════
-- Runtime helper bodies
-- ════════════════════════════════════════════════════════════════════════════

-- '$__alloc(size)' is a thin wrapper that calls
-- '$__alloc_shaped(size, 0)'. Existing helper alloc sites that
-- allocate scalars / strings / nullary cells keep their default
-- shape=0; CCon emit and helpers that build ADT cells with ptr
-- fields call '$__alloc_shaped' directly with the cell's arity.
codeAlloc :: [Word8]
codeAlloc =
  encodeBody (encodeLocals 0)
    $ concat
      [ [opLocalGet],
        encodeULEB128 0,
        [opI32Const],
        encodeSLEB128 0,
        [opCall],
        encodeULEB128 idxAllocShaped
      ]

-- '$__alloc_shaped(size, shape)' does the actual bump +
-- per-size-bin freelist work and stores the caller-supplied
-- @shape@ into the cell header at offset 8 (relative to block
-- start).
--
-- Locals (in addition to '$size'=slot 0, '$shape'=slot 1 params):
--   slot 2 = $rounded   — size rounded up to power-of-2, min 8
--   slot 3 = $bin_addr  — linear-memory address of bin head pointer
--   slot 4 = $head      — current bin head (potential reuse block)
--   slot 5 = $ptr       — bump-path block start
--
-- Bin heads live in linear memory at offsets 24..63 (10 size
-- classes, bytes 0..23 reserved for WASI scratch). Free-block
-- layout while in bin: flag at block+0 preserved (size class).
-- Next-ptr stashed at block+8 (the shape slot, repurposed while
-- free). On pop: reload next-ptr, re-init refcount=1, shape=@$shape@.
codeAllocShaped :: [Word8]
codeAllocShaped =
  encodeBody (encodeLocals 4)
    $ concat
      [ -- rounded = 1 << (32 - clz(size - 1))
        [opI32Const],
        encodeSLEB128 1,
        [opI32Const],
        encodeSLEB128 32,
        [opLocalGet],
        encodeULEB128 0,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Sub],
        [opI32Clz],
        [opI32Sub],
        [opI32Shl],
        [opLocalSet],
        encodeULEB128 2,
        -- if rounded < 8: rounded = 8
        [opLocalGet],
        encodeULEB128 2,
        [opI32Const],
        encodeSLEB128 8,
        [opI32LtU],
        [opIf, blocktypeVoid],
        [opI32Const],
        encodeSLEB128 8,
        [opLocalSet],
        encodeULEB128 2,
        [opEnd],
        -- if rounded <= 4096: try popping bin
        [opLocalGet],
        encodeULEB128 2,
        [opI32Const],
        encodeSLEB128 4096,
        [opI32LeU],
        [opIf, blocktypeVoid],
        -- bin_addr = 24 + ((ctz(rounded) - 3) << 2)  (bins live at 24..63)
        [opI32Const],
        encodeSLEB128 24,
        [opLocalGet],
        encodeULEB128 2,
        [opI32Ctz],
        [opI32Const],
        encodeSLEB128 3,
        [opI32Sub],
        [opI32Const],
        encodeSLEB128 2,
        [opI32Shl],
        [opI32Add],
        [opLocalSet],
        encodeULEB128 3,
        -- head = i32.load bin_addr
        [opLocalGet],
        encodeULEB128 3,
        [opI32Load, 0x02, 0x00],
        [opLocalSet],
        encodeULEB128 4,
        -- if head != 0: pop bin, re-init header, return head + 12
        [opLocalGet],
        encodeULEB128 4,
        [opIf, blocktypeVoid],
        -- bin_addr := load(head + 8)  ; pop next-ptr from shape slot
        [opLocalGet],
        encodeULEB128 3,
        [opLocalGet],
        encodeULEB128 4,
        [opI32Const],
        encodeSLEB128 8,
        [opI32Add],
        [opI32Load, 0x02, 0x00],
        [opI32Store, 0x02, 0x00],
        -- store(head + 4) := 1  ; refcount = 1
        [opLocalGet],
        encodeULEB128 4,
        [opI32Const],
        encodeSLEB128 4,
        [opI32Add],
        [opI32Const],
        encodeSLEB128 1,
        [opI32Store, 0x02, 0x00],
        -- store(head + 8) := shape
        [opLocalGet],
        encodeULEB128 4,
        [opI32Const],
        encodeSLEB128 8,
        [opI32Add],
        [opLocalGet],
        encodeULEB128 1,
        [opI32Store, 0x02, 0x00],
        -- return head + 12
        [opLocalGet],
        encodeULEB128 4,
        [opI32Const],
        encodeSLEB128 12,
        [opI32Add],
        [opReturn],
        [opEnd], -- end inner if
        [opEnd], -- end outer if (rounded <= 4096)
        -- Bump path: ptr = (heap + 3) & ~3
        [opGlobalGet],
        encodeULEB128 0,
        [opI32Const],
        encodeSLEB128 3,
        [opI32Add],
        [opI32Const],
        encodeSLEB128 (-4),
        [opI32And],
        [opLocalSet],
        encodeULEB128 5,
        -- heap = ptr + 12 + rounded
        [opLocalGet],
        encodeULEB128 5,
        [opI32Const],
        encodeSLEB128 12,
        [opI32Add],
        [opLocalGet],
        encodeULEB128 2,
        [opI32Add],
        [opGlobalSet],
        encodeULEB128 0,
        -- Grow loop.
        [opLoop, blocktypeVoid],
        [opGlobalGet],
        encodeULEB128 0,
        [opMemorySize, 0x00],
        [opI32Const],
        encodeSLEB128 65536,
        [opI32Mul],
        [opI32GtU],
        [opIf, blocktypeVoid],
        [opI32Const],
        encodeSLEB128 1,
        [opMemoryGrow, 0x00],
        [opI32Const],
        encodeSLEB128 (-1),
        [opI32Eq],
        [opIf, blocktypeVoid],
        [opUnreachable],
        [opEnd], -- end inner if (trap branch)
        [opBr],
        encodeULEB128 1, -- restart loop
        [opEnd], -- end outer if
        [opEnd], -- end loop
        -- store flag at ptr[0] = rounded
        [opLocalGet],
        encodeULEB128 5,
        [opLocalGet],
        encodeULEB128 2,
        [opI32Store, 0x02, 0x00],
        -- store refcount at ptr[4] = 1
        [opLocalGet],
        encodeULEB128 5,
        [opI32Const],
        encodeSLEB128 4,
        [opI32Add],
        [opI32Const],
        encodeSLEB128 1,
        [opI32Store, 0x02, 0x00],
        -- store shape at ptr[8] = $shape
        [opLocalGet],
        encodeULEB128 5,
        [opI32Const],
        encodeSLEB128 8,
        [opI32Add],
        [opLocalGet],
        encodeULEB128 1,
        [opI32Store, 0x02, 0x00],
        -- return ptr + 12
        [opLocalGet],
        encodeULEB128 5,
        [opI32Const],
        encodeSLEB128 12,
        [opI32Add]
      ]

-- '$__inc_ref(p)' bumps the refcount at @p - 8@ unless
-- the cell is a literal (flag == 0).
codeIncRef :: [Word8]
codeIncRef =
  encodeBody (encodeLocals 1)
    $ concat
      [ -- flag = load (p - 12)
        [opLocalGet],
        encodeULEB128 0,
        [opI32Const],
        encodeSLEB128 12,
        [opI32Sub],
        [opI32Load, 0x02, 0x00],
        [opLocalSet],
        encodeULEB128 1,
        -- if flag == 0: return
        [opLocalGet],
        encodeULEB128 1,
        [opI32Eqz],
        [opIf, blocktypeVoid],
        [opReturn],
        [opEnd],
        -- store (p - 8) := load (p - 8) + 1
        [opLocalGet],
        encodeULEB128 0,
        [opI32Const],
        encodeSLEB128 8,
        [opI32Sub],
        [opLocalGet],
        encodeULEB128 0,
        [opI32Const],
        encodeSLEB128 8,
        [opI32Sub],
        [opI32Load, 0x02, 0x00],
        [opI32Const],
        encodeSLEB128 1,
        [opI32Add],
        [opI32Store, 0x02, 0x00]
      ]

-- '$__free_recursive(p)' dec's refcount at @p - 8@. On
-- hitting 0 it reads shape at @p - 4@ and cascades: non-last
-- children are pushed onto the global worklist (see
-- '$__free_worklist_push' / WAT 'rtFreeRecursive' for the matching
-- text-form rationale); the last slot is taken as the new @$p@ in
-- the outer loop and the current block is returned to its bin via
-- '$__free'. When the current cell needs no further work
-- (literal, refcount > 0, or shape == 0) the helper pops the next
-- pending pointer from the worklist; on an empty worklist it
-- returns. The system-stack footprint is O(1) regardless of
-- cascade shape: deep frontiers grow the worklist (heap), not
-- the stack. Awsum immutability keeps the cell graph acyclic so
-- the cascade terminates.
--
-- Locals (in addition to '$p' param at slot 0):
--   slot 1 = $flag
--   slot 2 = $rc
--   slot 3 = $shape
--   slot 4 = $i (push-loop index, then tail-jump child temp)
--   slot 5 = $top (worklist top during pop)
codeFreeRecursive :: [Word8]
codeFreeRecursive =
  encodeBody (encodeLocals 5)
    $ concat
      [ -- (block $done   — outermost wrapper, br depth N+1 from any
        --                  enclosed point exits the helper.
        [opBlock, blocktypeVoid],
        -- (loop $outer   — re-entered for every new @$p@ (tail-jump
        --                  or worklist pop).
        [opLoop, blocktypeVoid],
        -- Load: flag = (p - 12)
        [opLocalGet],
        encodeULEB128 0,
        [opI32Const],
        encodeSLEB128 12,
        [opI32Sub],
        [opI32Load, 0x02, 0x00],
        [opLocalSet],
        encodeULEB128 1,
        -- (block $next   — fall-through here moves to the pop
        --                  section. br $next (depth 0 from inside)
        --                  is the "this cell needs no cascading
        --                  work" exit.
        [opBlock, blocktypeVoid],
        -- br_if to next if flag == 0 (literal short-circuit)
        [opLocalGet],
        encodeULEB128 1,
        [opI32Eqz],
        [opBrIf],
        encodeULEB128 0,
        -- Load: rc = (p - 8) - 1
        [opLocalGet],
        encodeULEB128 0,
        [opI32Const],
        encodeSLEB128 8,
        [opI32Sub],
        [opI32Load, 0x02, 0x00],
        [opI32Const],
        encodeSLEB128 1,
        [opI32Sub],
        [opLocalSet],
        encodeULEB128 2,
        -- store(p - 8, $rc)
        [opLocalGet],
        encodeULEB128 0,
        [opI32Const],
        encodeSLEB128 8,
        [opI32Sub],
        [opLocalGet],
        encodeULEB128 2,
        [opI32Store, 0x02, 0x00],
        -- br_if $next if $rc != 0 (still shared)
        [opLocalGet],
        encodeULEB128 2,
        [opBrIf],
        encodeULEB128 0,
        -- Load: shape = (p - 4)
        [opLocalGet],
        encodeULEB128 0,
        [opI32Const],
        encodeSLEB128 4,
        [opI32Sub],
        [opI32Load, 0x02, 0x00],
        [opLocalSet],
        encodeULEB128 3,
        -- if $shape == 0: __free(p); br $next (depth 1 from inside
        -- the (if (then ...)): 0=if, 1=$next).
        [opLocalGet],
        encodeULEB128 3,
        [opI32Eqz],
        [opIf, blocktypeVoid],
        [opLocalGet],
        encodeULEB128 0,
        [opCall],
        encodeULEB128 idxFree,
        [opBr],
        encodeULEB128 1,
        [opEnd], -- end if
        -- Push children at slots 1..shape-1 onto the worklist.
        -- Init: i = 1
        [opI32Const],
        encodeSLEB128 1,
        [opLocalSet],
        encodeULEB128 4,
        -- (block $push_break (loop $push_loop ...))
        [opBlock, blocktypeVoid],
        [opLoop, blocktypeVoid],
        -- br_if $push_break (depth 1) if $i >= $shape
        [opLocalGet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 3,
        [opI32GeU],
        [opBrIf],
        encodeULEB128 1,
        -- call $__free_worklist_push(load(p + i*4))
        [opLocalGet],
        encodeULEB128 0,
        [opLocalGet],
        encodeULEB128 4,
        [opI32Const],
        encodeSLEB128 2,
        [opI32Shl],
        [opI32Add],
        [opI32Load, 0x02, 0x00],
        [opCall],
        encodeULEB128 idxFreeWorklistPush,
        -- i++
        [opLocalGet],
        encodeULEB128 4,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Add],
        [opLocalSet],
        encodeULEB128 4,
        -- br $push_loop (depth 0)
        [opBr],
        encodeULEB128 0,
        [opEnd], -- end $push_loop
        [opEnd], -- end $push_break
        -- Tail-jump: $i = load(p + shape*4); __free(p); p = $i;
        -- br $outer (depth 1: 0=$next, 1=$outer).
        [opLocalGet],
        encodeULEB128 0,
        [opLocalGet],
        encodeULEB128 3,
        [opI32Const],
        encodeSLEB128 2,
        [opI32Shl],
        [opI32Add],
        [opI32Load, 0x02, 0x00],
        [opLocalSet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 0,
        [opCall],
        encodeULEB128 idxFree,
        [opLocalGet],
        encodeULEB128 4,
        [opLocalSet],
        encodeULEB128 0,
        [opBr],
        encodeULEB128 1,
        [opEnd], -- end $next
        -- Pop section (control falls here on flag == 0 / rc != 0 /
        -- shape == 0). Try to pop the next pointer; if the
        -- worklist is empty, exit via $done.
        -- Load: top = global __wl_top
        [opGlobalGet],
        encodeULEB128 2,
        [opLocalSet],
        encodeULEB128 5,
        -- br_if $done (depth 1: 0=$outer, 1=$done) if top == 0
        [opLocalGet],
        encodeULEB128 5,
        [opI32Eqz],
        [opBrIf],
        encodeULEB128 1,
        -- Decrement: top = top - 1; __wl_top = top
        [opLocalGet],
        encodeULEB128 5,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Sub],
        [opLocalSet],
        encodeULEB128 5,
        [opLocalGet],
        encodeULEB128 5,
        [opGlobalSet],
        encodeULEB128 2,
        -- Load: p = (__wl_buf + top*4)
        [opGlobalGet],
        encodeULEB128 1,
        [opLocalGet],
        encodeULEB128 5,
        [opI32Const],
        encodeSLEB128 2,
        [opI32Shl],
        [opI32Add],
        [opI32Load, 0x02, 0x00],
        [opLocalSet],
        encodeULEB128 0,
        -- br $outer (depth 0)
        [opBr],
        encodeULEB128 0,
        [opEnd], -- end $outer
        [opEnd] -- end $done
      ]

-- '$__free_worklist_push(p)' appends @$p@ onto the worklist
-- buffer pointed to by '$__wl_buf' (i32 indices: 0=$heap,
-- 1=$__wl_buf, 2=$__wl_top, 3=$__wl_cap). Grows the buffer
-- (initial 16 entries, doubles thereafter) when @$top == $cap@.
-- Old buffers that fit a size class (≤ 4096 bytes ⇔ ≤ 1024
-- entries) are returned to the bin via '$__free' on grow; larger
-- ones leak — total leak stays ≤ 2× current capacity because
-- doubling halves each predecessor.
--
-- Locals (in addition to '$p' param at slot 0):
--   slot 1 = $top
--   slot 2 = $cap
--   slot 3 = $new_cap
--   slot 4 = $new_buf
--   slot 5 = $old_buf
--   slot 6 = $i (copy-loop index)
codeFreeWorklistPush :: [Word8]
codeFreeWorklistPush =
  encodeBody (encodeLocals 6)
    $ concat
      [ -- Load: top = global __wl_top
        [opGlobalGet],
        encodeULEB128 2,
        [opLocalSet],
        encodeULEB128 1,
        -- Load: cap = global __wl_cap
        [opGlobalGet],
        encodeULEB128 3,
        [opLocalSet],
        encodeULEB128 2,
        -- if top == cap: grow
        [opLocalGet],
        encodeULEB128 1,
        [opLocalGet],
        encodeULEB128 2,
        [opI32Eq],
        [opIf, blocktypeVoid],
        -- Pick new_cap = (cap == 0) ? 16 : (cap << 1)
        [opLocalGet],
        encodeULEB128 2,
        [opI32Eqz],
        [opIf, blocktypeI32],
        [opI32Const],
        encodeSLEB128 16,
        [opElse],
        [opLocalGet],
        encodeULEB128 2,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Shl],
        [opEnd], -- end if blocktypeI32
        [opLocalSet],
        encodeULEB128 3,
        -- Alloc: new_buf = __alloc_shaped(new_cap << 2, 0)
        [opLocalGet],
        encodeULEB128 3,
        [opI32Const],
        encodeSLEB128 2,
        [opI32Shl],
        [opI32Const],
        encodeSLEB128 0,
        [opCall],
        encodeULEB128 idxAllocShaped,
        [opLocalSet],
        encodeULEB128 4,
        -- Stash: old_buf = global __wl_buf
        [opGlobalGet],
        encodeULEB128 1,
        [opLocalSet],
        encodeULEB128 5,
        -- Copy old contents: for i in 0..top: new_buf[i*4] = old_buf[i*4]
        [opI32Const],
        encodeSLEB128 0,
        [opLocalSet],
        encodeULEB128 6,
        [opBlock, blocktypeVoid],
        [opLoop, blocktypeVoid],
        -- br_if $copy_break (depth 1) if i >= top
        [opLocalGet],
        encodeULEB128 6,
        [opLocalGet],
        encodeULEB128 1,
        [opI32GeU],
        [opBrIf],
        encodeULEB128 1,
        -- new_buf[i*4] = old_buf[i*4]
        [opLocalGet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 6,
        [opI32Const],
        encodeSLEB128 2,
        [opI32Shl],
        [opI32Add],
        [opLocalGet],
        encodeULEB128 5,
        [opLocalGet],
        encodeULEB128 6,
        [opI32Const],
        encodeSLEB128 2,
        [opI32Shl],
        [opI32Add],
        [opI32Load, 0x02, 0x00],
        [opI32Store, 0x02, 0x00],
        -- i++
        [opLocalGet],
        encodeULEB128 6,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Add],
        [opLocalSet],
        encodeULEB128 6,
        [opBr],
        encodeULEB128 0,
        [opEnd], -- end loop
        [opEnd], -- end block $copy_break
        -- if old_buf != 0: __free(old_buf)
        [opLocalGet],
        encodeULEB128 5,
        [opIf, blocktypeVoid],
        [opLocalGet],
        encodeULEB128 5,
        [opCall],
        encodeULEB128 idxFree,
        [opEnd],
        -- Store: __wl_buf = new_buf; __wl_cap = new_cap
        [opLocalGet],
        encodeULEB128 4,
        [opGlobalSet],
        encodeULEB128 1,
        [opLocalGet],
        encodeULEB128 3,
        [opGlobalSet],
        encodeULEB128 3,
        [opEnd], -- end if (top == cap)
        -- Store: __wl_buf[top*4] = p
        [opGlobalGet],
        encodeULEB128 1,
        [opLocalGet],
        encodeULEB128 1,
        [opI32Const],
        encodeSLEB128 2,
        [opI32Shl],
        [opI32Add],
        [opLocalGet],
        encodeULEB128 0,
        [opI32Store, 0x02, 0x00],
        -- Store: __wl_top = top + 1
        [opLocalGet],
        encodeULEB128 1,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Add],
        [opGlobalSet],
        encodeULEB128 2
      ]

-- '$__free(p)' returns a block to the matching bin
-- freelist, or no-ops on literal pointers (flag=0). Block layout:
-- block[0..4] preserved as 'flag' (= size class); block[8..12]
-- becomes the next-ptr in the freelist (the shape slot is repurposed
-- while free; '__alloc' re-initialises it to 0 on pop).
--
-- Locals (in addition to '$p' param at slot 0):
--   slot 1 = $flag     — i32 read from p - 12
--   slot 2 = $bin_addr — same arithmetic as in '__alloc'
--   slot 3 = $cur      — current bin head (becomes the new next-ptr)
codeFree :: [Word8]
codeFree =
  encodeBody (encodeLocals 3)
    $ concat
      [ -- flag = i32.load (p - 12)
        [opLocalGet],
        encodeULEB128 0,
        [opI32Const],
        encodeSLEB128 12,
        [opI32Sub],
        [opI32Load, 0x02, 0x00],
        [opLocalSet],
        encodeULEB128 1,
        -- if flag == 0: return (literal)
        [opLocalGet],
        encodeULEB128 1,
        [opI32Eqz],
        [opIf, blocktypeVoid],
        [opReturn],
        [opEnd],
        -- if flag > 4096: return (huge, no bin)
        [opLocalGet],
        encodeULEB128 1,
        [opI32Const],
        encodeSLEB128 4096,
        [opI32GtU],
        [opIf, blocktypeVoid],
        [opReturn],
        [opEnd],
        -- bin_addr = 24 + ((ctz(flag) - 3) << 2)
        [opI32Const],
        encodeSLEB128 24,
        [opLocalGet],
        encodeULEB128 1,
        [opI32Ctz],
        [opI32Const],
        encodeSLEB128 3,
        [opI32Sub],
        [opI32Const],
        encodeSLEB128 2,
        [opI32Shl],
        [opI32Add],
        [opLocalSet],
        encodeULEB128 2,
        -- cur = i32.load bin_addr
        [opLocalGet],
        encodeULEB128 2,
        [opI32Load, 0x02, 0x00],
        [opLocalSet],
        encodeULEB128 3,
        -- store cur into (p - 4) (next-ptr lives at block+8 = p - 4)
        [opLocalGet],
        encodeULEB128 0,
        [opI32Const],
        encodeSLEB128 4,
        [opI32Sub],
        [opLocalGet],
        encodeULEB128 3,
        [opI32Store, 0x02, 0x00],
        -- store (p - 12) into *bin_addr (new bin head = block)
        [opLocalGet],
        encodeULEB128 2,
        [opLocalGet],
        encodeULEB128 0,
        [opI32Const],
        encodeSLEB128 12,
        [opI32Sub],
        [opI32Store, 0x02, 0x00]
      ]

-- __memcpy(dst: i32, src: i32, len: i32)
-- local $i: i32
codeMemcpy :: [Word8]
codeMemcpy =
  encodeBody
    (encodeLocals 1)
    $ concat
      [ -- i = 0
        [opI32Const],
        encodeSLEB128 0,
        [opLocalSet],
        encodeULEB128 3,
        -- block $break
        [opBlock, blocktypeVoid],
        -- loop $loop
        [opLoop, blocktypeVoid],
        -- br_if $break (i >= len)
        [opLocalGet],
        encodeULEB128 3, -- i
        [opLocalGet],
        encodeULEB128 2, -- len
        [opI32GeU],
        [opBrIf],
        encodeULEB128 1,
        -- i32.store8 (dst+i) (i32.load8_u (src+i))
        [opLocalGet],
        encodeULEB128 0, -- dst
        [opLocalGet],
        encodeULEB128 3, -- i
        [opI32Add],
        [opLocalGet],
        encodeULEB128 1, -- src
        [opLocalGet],
        encodeULEB128 3, -- i
        [opI32Add],
        [opI32Load8U, 0x00, 0x00],
        [opI32Store8, 0x00, 0x00],
        -- i = i + 1
        [opLocalGet],
        encodeULEB128 3,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Add],
        [opLocalSet],
        encodeULEB128 3,
        -- br $loop
        [opBr],
        encodeULEB128 0,
        [opEnd],
        [opEnd]
      ]

-- __memcmp(a: i32, b: i32, len: i32) -> i32
-- Returns 1 iff all 'len' bytes at addresses 'a' and 'b' agree, 0 on
-- first mismatch. Driver for '__eqString' after the byte-count
-- short-circuit. Different shape from libc 'memcmp' (which returns a
-- tri-state ordering): equality alone is enough for string equality
-- and 'opReturn' on first mismatch lets the loop exit early.
-- Locals: $i(3).
codeMemcmp :: [Word8]
codeMemcmp =
  encodeBody
    (encodeLocals 1)
    $ concat
      [ -- i = 0
        [opI32Const],
        encodeSLEB128 0,
        [opLocalSet],
        encodeULEB128 3,
        -- block $break
        [opBlock, blocktypeVoid],
        -- loop $loop
        [opLoop, blocktypeVoid],
        -- br_if $break (i >= len)
        [opLocalGet],
        encodeULEB128 3, -- i
        [opLocalGet],
        encodeULEB128 2, -- len
        [opI32GeU],
        [opBrIf],
        encodeULEB128 1,
        -- if (a[i] != b[i]) return 0
        [opLocalGet],
        encodeULEB128 0, -- a
        [opLocalGet],
        encodeULEB128 3, -- i
        [opI32Add],
        [opI32Load8U, 0x00, 0x00],
        [opLocalGet],
        encodeULEB128 1, -- b
        [opLocalGet],
        encodeULEB128 3, -- i
        [opI32Add],
        [opI32Load8U, 0x00, 0x00],
        [opI32Ne],
        [opIf, blocktypeVoid],
        [opI32Const],
        encodeSLEB128 0,
        [opReturn],
        [opEnd],
        -- i = i + 1
        [opLocalGet],
        encodeULEB128 3,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Add],
        [opLocalSet],
        encodeULEB128 3,
        -- br $loop
        [opBr],
        encodeULEB128 0,
        [opEnd], -- end loop
        [opEnd], -- end block
        -- All bytes matched: return 1.
        [opI32Const],
        encodeSLEB128 1
      ]

-- __eqString(a: i32, b: i32) -> i32
-- eqString : String -> String -> Bool. Strings are length-prefixed
-- (byte_count @ offset 0, utf16_count @ offset 4, payload @ offset 8).
-- Strict-UTF-16 ⇒ equal UTF-16 ⇔ equal UTF-8 bytes, so byte_count
-- check + '__memcmp' on the payload is sufficient. Returns a one-slot
-- Bool container ([tag]); True=0, False=1 per declaration order.
-- Locals: $ba(2) $bb(3) $cell(4) $eq(5).
codeEqString :: WasmInfo -> [Word8]
codeEqString info =
  let ptags = wiTags info
   in encodeBody
        (encodeLocals 4)
        $ concat
          [ -- ba = i32.load(a)
            [opLocalGet],
            encodeULEB128 0,
            [opI32Load, 0x02, 0x00],
            [opLocalSet],
            encodeULEB128 2,
            -- bb = i32.load(b)
            [opLocalGet],
            encodeULEB128 1,
            [opI32Load, 0x02, 0x00],
            [opLocalSet],
            encodeULEB128 3,
            -- cell = __alloc(4)
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 4,
            -- if (ba == bb)
            [opLocalGet],
            encodeULEB128 2,
            [opLocalGet],
            encodeULEB128 3,
            [opI32Eq],
            [opIf, blocktypeVoid],
            -- eq = __memcmp(a + 8, b + 8, ba)
            [opLocalGet],
            encodeULEB128 0,
            [opI32Const],
            encodeSLEB128 8,
            [opI32Add],
            [opLocalGet],
            encodeULEB128 1,
            [opI32Const],
            encodeSLEB128 8,
            [opI32Add],
            [opLocalGet],
            encodeULEB128 2,
            [opCall],
            encodeULEB128 idxMemcmp,
            [opLocalSet],
            encodeULEB128 5,
            -- if eq then store True else store False
            [opLocalGet],
            encodeULEB128 5,
            [opIf, blocktypeVoid],
            storeTagBytes 4 (ptTrue ptags),
            [opElse],
            storeTagBytes 4 (ptFalse ptags),
            [opEnd],
            [opElse],
            -- lengths differ → False
            storeTagBytes 4 (ptFalse ptags),
            [opEnd],
            -- Callee owns args; dec both before returning the cell.
            decArgBin 0,
            decArgBin 1,
            [opLocalGet],
            encodeULEB128 4
          ]

-- __utf16_of_range(p: i32, len: i32) -> i32
-- Counts UTF-16 code units in a UTF-8 byte range. Used by
-- '__splitOnFirst' to set the utf16 prefix on each output substring.
-- Locals (after 2 params): $i(2), $n(3), $b(4).
codeUtf16OfRange :: [Word8]
codeUtf16OfRange =
  encodeBody
    (encodeLocals 3)
    $ concat
      [ -- i = 0
        [opI32Const],
        encodeSLEB128 0,
        [opLocalSet],
        encodeULEB128 2,
        -- n = 0
        [opI32Const],
        encodeSLEB128 0,
        [opLocalSet],
        encodeULEB128 3,
        [opBlock, blocktypeVoid],
        [opLoop, blocktypeVoid],
        -- if i >= len break
        [opLocalGet],
        encodeULEB128 2,
        [opLocalGet],
        encodeULEB128 1,
        [opI32GeU],
        [opBrIf],
        encodeULEB128 1,
        -- b = i32.load8_u (p + i)
        [opLocalGet],
        encodeULEB128 0,
        [opLocalGet],
        encodeULEB128 2,
        [opI32Add],
        [opI32Load8U, 0x00, 0x00],
        [opLocalSet],
        encodeULEB128 4,
        -- if (b & 0xC0) != 0x80
        [opLocalGet],
        encodeULEB128 4,
        [opI32Const],
        encodeSLEB128 0xC0,
        [opI32And],
        [opI32Const],
        encodeSLEB128 0x80,
        [opI32Ne],
        [opIf, blocktypeVoid],
        -- inner if (b & 0xF8) == 0xF0 then n+=2 else n+=1
        [opLocalGet],
        encodeULEB128 4,
        [opI32Const],
        encodeSLEB128 0xF8,
        [opI32And],
        [opI32Const],
        encodeSLEB128 0xF0,
        [opI32Eq],
        [opIf, blocktypeVoid],
        [opLocalGet],
        encodeULEB128 3,
        [opI32Const],
        encodeSLEB128 2,
        [opI32Add],
        [opLocalSet],
        encodeULEB128 3,
        [opElse],
        [opLocalGet],
        encodeULEB128 3,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Add],
        [opLocalSet],
        encodeULEB128 3,
        [opEnd], -- end inner if
        [opEnd], -- end outer if
        -- i = i + 1
        [opLocalGet],
        encodeULEB128 2,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Add],
        [opLocalSet],
        encodeULEB128 2,
        [opBr],
        encodeULEB128 0,
        [opEnd], -- end loop
        [opEnd], -- end block
        [opLocalGet],
        encodeULEB128 3
      ]

-- __concat(a: i32, b: i32) -> i32
-- Length-prefixed concat. O(1) cap-check via header.
-- Locals (after 2 params): $ba(2), $bb(3), $ua(4), $ub(5),

-- $usum(6), \$bsum(7), $stl(8), $cell(9), $buf(10).

codeConcat :: WasmInfo -> [Word8]
codeConcat info =
  let ptags = wiTags info
   in encodeBody
        (encodeLocals 9)
        $ concat
          [ -- ba = i32.load(a)
            [opLocalGet],
            encodeULEB128 0,
            [opI32Load, 0x02, 0x00],
            [opLocalSet],
            encodeULEB128 2,
            -- ua = i32.load offset=4 (a)
            [opLocalGet],
            encodeULEB128 0,
            [opI32Load, 0x02, 0x04],
            [opLocalSet],
            encodeULEB128 4,
            -- bb = i32.load(b)
            [opLocalGet],
            encodeULEB128 1,
            [opI32Load, 0x02, 0x00],
            [opLocalSet],
            encodeULEB128 3,
            -- ub = i32.load offset=4 (b)
            [opLocalGet],
            encodeULEB128 1,
            [opI32Load, 0x02, 0x04],
            [opLocalSet],
            encodeULEB128 5,
            -- usum = ua + ub
            [opLocalGet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 5,
            [opI32Add],
            [opLocalSet],
            encodeULEB128 6,
            -- if (usum >u 134217728)
            [opLocalGet],
            encodeULEB128 6,
            [opI32Const],
            encodeSLEB128 134217728,
            [opI32GtU],
            [opIf, blocktypeVoid],
            -- then: Left StringTooLong
            --   stl = __alloc(4); store StringTooLong tag
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 8,
            [opLocalGet],
            encodeULEB128 8,
            [opI32Const],
            encodeSLEB128 (fromIntegral (ptStringTooLong ptags)),
            [opI32Store, 0x02, 0x00],
            --   cell = __alloc(8); store Left tag; store offset=4 cell stl
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 9,
            [opLocalGet],
            encodeULEB128 9,
            [opI32Const],
            encodeSLEB128 (fromIntegral (ptLeft ptags)),
            [opI32Store, 0x02, 0x00],
            [opLocalGet],
            encodeULEB128 9,
            [opLocalGet],
            encodeULEB128 8,
            [opI32Store, 0x02, 0x04],
            [opElse],
            -- else: bsum = ba + bb; buf = alloc(8 + bsum)
            [opLocalGet],
            encodeULEB128 2,
            [opLocalGet],
            encodeULEB128 3,
            [opI32Add],
            [opLocalSet],
            encodeULEB128 7,
            --   buf = __alloc(bsum + 8)
            [opLocalGet],
            encodeULEB128 7,
            [opI32Const],
            encodeSLEB128 8,
            [opI32Add],
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 10,
            --   write header: byte_count = bsum, utf16_count = usum
            [opLocalGet],
            encodeULEB128 10,
            [opLocalGet],
            encodeULEB128 7,
            [opI32Store, 0x02, 0x00],
            [opLocalGet],
            encodeULEB128 10,
            [opLocalGet],
            encodeULEB128 6,
            [opI32Store, 0x02, 0x04],
            --   __memcpy(buf+8, a+8, ba)
            [opLocalGet],
            encodeULEB128 10,
            [opI32Const],
            encodeSLEB128 8,
            [opI32Add],
            [opLocalGet],
            encodeULEB128 0,
            [opI32Const],
            encodeSLEB128 8,
            [opI32Add],
            [opLocalGet],
            encodeULEB128 2,
            [opCall],
            encodeULEB128 idxMemcpy,
            --   __memcpy(buf+8+ba, b+8, bb)
            [opLocalGet],
            encodeULEB128 10,
            [opI32Const],
            encodeSLEB128 8,
            [opI32Add],
            [opLocalGet],
            encodeULEB128 2,
            [opI32Add],
            [opLocalGet],
            encodeULEB128 1,
            [opI32Const],
            encodeSLEB128 8,
            [opI32Add],
            [opLocalGet],
            encodeULEB128 3,
            [opCall],
            encodeULEB128 idxMemcpy,
            --   cell = __alloc(8); store Right tag; store offset=4 cell buf
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 9,
            [opLocalGet],
            encodeULEB128 9,
            [opI32Const],
            encodeSLEB128 (fromIntegral (ptRight ptags)),
            [opI32Store, 0x02, 0x00],
            [opLocalGet],
            encodeULEB128 9,
            [opLocalGet],
            encodeULEB128 10,
            [opI32Store, 0x02, 0x04],
            [opEnd],
            -- Callee takes ownership; dec both args before return.
            decArgBin 0,
            decArgBin 1,
            [opLocalGet],
            encodeULEB128 9
          ]

-- __print(s: i32) -> i32
-- locals: $len (slot 1), $unit (slot 2)
-- Returns a Unit value (alloc(4); store tag 0) so the surrounding
-- `case … of Unit -> next` arm in the prelude's `runIO` dispatches
-- through the standard CCase tag check.
codePrint :: WasmInfo -> [Word8]
codePrint info =
  let ptags = wiTags info
   in encodeBody
        (encodeLocals 2)
        $ concat
          [ -- len = i32.load(s) — byte_count from header (O(1))
            [opLocalGet],
            encodeULEB128 0,
            [opI32Load, 0x02, 0x00],
            [opLocalSet],
            encodeULEB128 1,
            -- i32.store offset=0 (i32.const 0) (s + 8)  -- iov_base = payload
            [opI32Const],
            encodeSLEB128 0,
            [opLocalGet],
            encodeULEB128 0,
            [opI32Const],
            encodeSLEB128 8,
            [opI32Add],
            [opI32Store, 0x02, 0x00], -- align=2 (4-byte), offset=0
            -- i32.store offset=4 (i32.const 0) len  -- iov_len
            [opI32Const],
            encodeSLEB128 0,
            [opLocalGet],
            encodeULEB128 1,
            [opI32Store, 0x02, 0x04], -- align=2, offset=4
            -- drop(fd_write(1, 0, 1, 8))
            [opI32Const],
            encodeSLEB128 1, -- fd = stdout
            [opI32Const],
            encodeSLEB128 0, -- iovs ptr
            [opI32Const],
            encodeSLEB128 1, -- iovs_len
            [opI32Const],
            encodeSLEB128 8, -- nwritten ptr
            [opCall],
            encodeULEB128 0, -- fd_write (import index 0)
            [opDrop],
            -- Build Unit value: unit = __alloc(4); store Unit tag; return unit
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 2,
            storeTagBytes 2 (ptUnit ptags),
            -- Callee takes ownership; dec the string arg before return.
            decArgBin 0,
            [opLocalGet],
            encodeULEB128 2
          ]

-- __predInt32(p: i32) -> i32
-- predInt32: Int32 -> Either UnderflowError Int32.
--   Container layout matches user CCon emission on WASM: i32 tag at
--   offset 0, i32 fields at offsets 4, 8, ... Tags: Left=0, Right=1,
--   UnderflowError=0. Returns `Left UnderflowError` on INT32_MIN,
--   `Right (v - 1)` otherwise.
-- Locals: $v(1) $ue(2) $box(3) $cell(4)
codePredI32 :: WasmInfo -> [Word8]
codePredI32 info =
  let ptags = wiTags info
   in encodeBody
        (encodeLocals 4)
        $ concat
          [ -- v = i32.load(p)
            [opLocalGet],
            encodeULEB128 0,
            [opI32Load, 0x02, 0x00],
            [opLocalSet],
            encodeULEB128 1,
            -- if (v == INT32_MIN)
            [opLocalGet],
            encodeULEB128 1,
            [opI32Const],
            encodeSLEB128 (-2147483648),
            [opI32Eq],
            [opIf, blocktypeVoid],
            -- then: Left UnderflowError
            -- ue = __alloc(4); store UnderflowError tag
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 2,
            storeTagBytes 2 (ptUnderflowError ptags),
            -- cell = __alloc(8); store Left tag; store[offset=4] ue
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 4,
            storeTagBytes 4 (ptLeft ptags),
            [opLocalGet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 2,
            [opI32Store, 0x02, 0x04],
            [opElse],
            -- else: Right (v - 1)
            -- box = __alloc(4); store (v - 1)
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 3,
            [opLocalGet],
            encodeULEB128 3,
            [opLocalGet],
            encodeULEB128 1,
            [opI32Const],
            encodeSLEB128 1,
            [opI32Sub],
            [opI32Store, 0x02, 0x00],
            -- cell = __alloc(8); store Right tag; store[offset=4] box
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 4,
            storeTagBytes 4 (ptRight ptags),
            [opLocalGet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 3,
            [opI32Store, 0x02, 0x04],
            [opEnd],
            -- Callee takes ownership; dec the arg before return.
            decArgBin 0,
            -- return cell
            [opLocalGet],
            encodeULEB128 4
          ]

-- __predUInt8(p: i32) -> i32
-- predUInt8: UInt8 -> Either UnderflowError UInt8.
--   Mirrors 'codePredI32' but checks against 0 (via 'i32.eqz') instead
--   of INT32_MIN, and subtracts without masking — (v - 1) is in 0..254
--   when v >= 1, so it stays in UInt8 range naturally. Same locals
--   layout: $v(1) $ue(2) $box(3) $cell(4).
codePredU8 :: WasmInfo -> [Word8]
codePredU8 info =
  let ptags = wiTags info
   in encodeBody
        (encodeLocals 4)
        $ concat
          [ -- v = i32.load(p)
            [opLocalGet],
            encodeULEB128 0,
            [opI32Load, 0x02, 0x00],
            [opLocalSet],
            encodeULEB128 1,
            -- if (i32.eqz v)
            [opLocalGet],
            encodeULEB128 1,
            [opI32Eqz],
            [opIf, blocktypeVoid],
            -- then: Left UnderflowError
            -- ue = __alloc(4); store UnderflowError tag
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 2,
            storeTagBytes 2 (ptUnderflowError ptags),
            -- cell = __alloc(8); store Left tag; store[offset=4] ue
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 4,
            storeTagBytes 4 (ptLeft ptags),
            [opLocalGet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 2,
            [opI32Store, 0x02, 0x04],
            [opElse],
            -- else: Right (v - 1)
            -- box = __alloc(4); store (v - 1)
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 3,
            [opLocalGet],
            encodeULEB128 3,
            [opLocalGet],
            encodeULEB128 1,
            [opI32Const],
            encodeSLEB128 1,
            [opI32Sub],
            [opI32Store, 0x02, 0x00],
            -- cell = __alloc(8); store Right tag; store[offset=4] box
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 4,
            storeTagBytes 4 (ptRight ptags),
            [opLocalGet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 3,
            [opI32Store, 0x02, 0x04],
            [opEnd],
            -- Callee takes ownership; dec the arg before return.
            decArgBin 0,
            [opLocalGet],
            encodeULEB128 4
          ]

-- __succInt32(p: i32) -> i32
-- succInt32: Int32 -> Either OverflowError Int32.
--   Mirrors 'codePredI32' with boundary INT32_MAX and i32.add instead of
--   i32.sub. OverflowError is single-constructor, so its inner-box tag is
--   0 (same as UnderflowError) — encoding is bit-identical to the
--   predecessor case on this axis.
-- Locals: $v(1) $oe(2) $box(3) $cell(4)
codeSuccI32 :: WasmInfo -> [Word8]
codeSuccI32 info =
  let ptags = wiTags info
   in encodeBody
        (encodeLocals 4)
        $ concat
          [ -- v = i32.load(p)
            [opLocalGet],
            encodeULEB128 0,
            [opI32Load, 0x02, 0x00],
            [opLocalSet],
            encodeULEB128 1,
            -- if (v == INT32_MAX)
            [opLocalGet],
            encodeULEB128 1,
            [opI32Const],
            encodeSLEB128 2147483647,
            [opI32Eq],
            [opIf, blocktypeVoid],
            -- then: Left OverflowError
            -- oe = __alloc(4); store OverflowError tag
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 2,
            storeTagBytes 2 (ptOverflowError ptags),
            -- cell = __alloc(8); store Left tag; store[offset=4] oe
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 4,
            storeTagBytes 4 (ptLeft ptags),
            [opLocalGet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 2,
            [opI32Store, 0x02, 0x04],
            [opElse],
            -- else: Right (v + 1)
            -- box = __alloc(4); store (v + 1)
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 3,
            [opLocalGet],
            encodeULEB128 3,
            [opLocalGet],
            encodeULEB128 1,
            [opI32Const],
            encodeSLEB128 1,
            [opI32Add],
            [opI32Store, 0x02, 0x00],
            -- cell = __alloc(8); store Right tag; store[offset=4] box
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 4,
            storeTagBytes 4 (ptRight ptags),
            [opLocalGet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 3,
            [opI32Store, 0x02, 0x04],
            [opEnd],
            -- Callee takes ownership; dec the arg before return.
            decArgBin 0,
            -- return cell
            [opLocalGet],
            encodeULEB128 4
          ]

-- __succUInt8(p: i32) -> i32
-- succUInt8: UInt8 -> Either OverflowError UInt8.
--   Mirrors 'codeSuccI32' but checks against 255. Masking is unnecessary —
--   (v + 1) is in 1..255 when v <= 254, so the result stays in UInt8 range
--   naturally. Same locals layout: $v(1) $oe(2) $box(3) $cell(4).
codeSuccU8 :: WasmInfo -> [Word8]
codeSuccU8 info =
  let ptags = wiTags info
   in encodeBody
        (encodeLocals 4)
        $ concat
          [ -- v = i32.load(p)
            [opLocalGet],
            encodeULEB128 0,
            [opI32Load, 0x02, 0x00],
            [opLocalSet],
            encodeULEB128 1,
            -- if (v == 255)
            [opLocalGet],
            encodeULEB128 1,
            [opI32Const],
            encodeSLEB128 255,
            [opI32Eq],
            [opIf, blocktypeVoid],
            -- then: Left OverflowError
            -- oe = __alloc(4); store OverflowError tag
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 2,
            storeTagBytes 2 (ptOverflowError ptags),
            -- cell = __alloc(8); store Left tag; store[offset=4] oe
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 4,
            storeTagBytes 4 (ptLeft ptags),
            [opLocalGet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 2,
            [opI32Store, 0x02, 0x04],
            [opElse],
            -- else: Right (v + 1)
            -- box = __alloc(4); store (v + 1)
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 3,
            [opLocalGet],
            encodeULEB128 3,
            [opLocalGet],
            encodeULEB128 1,
            [opI32Const],
            encodeSLEB128 1,
            [opI32Add],
            [opI32Store, 0x02, 0x00],
            -- cell = __alloc(8); store Right tag; store[offset=4] box
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 4,
            storeTagBytes 4 (ptRight ptags),
            [opLocalGet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 3,
            [opI32Store, 0x02, 0x04],
            [opEnd],
            -- Callee takes ownership; dec the arg before return.
            decArgBin 0,
            [opLocalGet],
            encodeULEB128 4
          ]

-- __eq_i32(a: i32, b: i32) -> i32
-- eqInt32 / eqUInt8: compare two boxed integers, return a Bool container.
--   Int32 and UInt8 both flow as pointers to i32 cells (UInt8 values are
--   stored masked to 0..255), so one helper handles both. True=0, False=1
--   matches declaration order in `type Bool = True | False`.
-- Locals: $cell(2) — single i32 local, in addition to the two params.
codeEqI32 :: WasmInfo -> [Word8]
codeEqI32 info =
  let ptags = wiTags info
   in encodeBody
        (encodeLocals 1)
        $ concat
          [ -- cell = __alloc(4)
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 2,
            -- if (i32.load(a) == i32.load(b))
            [opLocalGet],
            encodeULEB128 0,
            [opI32Load, 0x02, 0x00],
            [opLocalGet],
            encodeULEB128 1,
            [opI32Load, 0x02, 0x00],
            [opI32Eq],
            [opIf, blocktypeVoid],
            -- then: store True tag
            storeTagBytes 2 (ptTrue ptags),
            [opElse],
            -- else: store False tag
            storeTagBytes 2 (ptFalse ptags),
            [opEnd],
            -- Callee takes ownership; dec both args before return.
            decArgBin 0,
            decArgBin 1,
            -- return cell
            [opLocalGet],
            encodeULEB128 2
          ]

-- __addInt32(pa: i32, pb: i32) -> i32
-- addInt32: Int32 -> Int32 -> Either ArithError Int32. Signed-overflow
-- detected via the XOR trick: '(a ^ s) & (b ^ s) < 0' (i32.lt_s 0)
-- holds iff the carry into the sign bit differs from the carry out.
-- Direction is read off 'a >= 0' (i32.ge_s 0) — same-sign overflow is
-- positive when a >= 0, negative otherwise. ArithError tags follow
-- Prelude.aww declaration order: Underflow=0, Overflow=1.
-- Locals: $a(2) $b(3) $s(4) $ae(5) $box(6) $cell(7).

-- | FNV-1a 32-bit row tags for the prelude's nominal labels used by
--   the Int32 arithmetic builtins. Computed via 'rowTag' so the
--   runtime helpers stay in lockstep with 'Awsum.HM.canonicalLabel'
--   without hard-coded magic numbers. Cast to 'Int32' so they fit the
--   'encodeSLEB128' input type — the bit pattern is preserved across
--   the cast and matches what the user-side 'CRowCase' compares against.
underflowRowTag :: Int32
underflowRowTag = fromIntegral (rowTag (TyCon noSpan "UnderflowError"))

overflowRowTag :: Int32
overflowRowTag = fromIntegral (rowTag (TyCon noSpan "OverflowError"))

codeAddI32 :: WasmInfo -> [Word8]
codeAddI32 info =
  let ptags = wiTags info
   in encodeBody
        (encodeLocals 7)
        $ concat
          [ -- a = i32.load(pa)
            [opLocalGet],
            encodeULEB128 0,
            [opI32Load, 0x02, 0x00],
            [opLocalSet],
            encodeULEB128 2,
            -- b = i32.load(pb)
            [opLocalGet],
            encodeULEB128 1,
            [opI32Load, 0x02, 0x00],
            [opLocalSet],
            encodeULEB128 3,
            -- s = a + b
            [opLocalGet],
            encodeULEB128 2,
            [opLocalGet],
            encodeULEB128 3,
            [opI32Add],
            [opLocalSet],
            encodeULEB128 4,
            -- if (((a ^ s) & (b ^ s)) < 0)  result i32
            [opLocalGet],
            encodeULEB128 2,
            [opLocalGet],
            encodeULEB128 4,
            [opI32Xor],
            [opLocalGet],
            encodeULEB128 3,
            [opLocalGet],
            encodeULEB128 4,
            [opI32Xor],
            [opI32And],
            [opI32Const],
            encodeSLEB128 0,
            [opI32LtS],
            [opIf, blocktypeVoid],
            -- then: Left (CRow rowTag (CCon (UnderflowError|OverflowError) [])).
            -- inner = __alloc(4); store ctor-tag (OverflowError if a >= 0, UnderflowError otherwise)
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 5,
            [opLocalGet],
            encodeULEB128 5,
            [opLocalGet],
            encodeULEB128 2,
            [opI32Const],
            encodeSLEB128 0,
            [opI32GeS],
            [opIf, blocktypeI32],
            [opI32Const],
            encodeSLEB128 (fromIntegral (ptOverflowError ptags)),
            [opElse],
            [opI32Const],
            encodeSLEB128 (fromIntegral (ptUnderflowError ptags)),
            [opEnd],
            [opI32Store, 0x02, 0x00],
            -- row = __alloc(8); store rowTag(if a >= 0 then OverflowError else UnderflowError);
            --                   store inner at offset=4
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 6,
            [opLocalGet],
            encodeULEB128 6,
            [opLocalGet],
            encodeULEB128 2,
            [opI32Const],
            encodeSLEB128 0,
            [opI32GeS],
            [opIf, blocktypeI32],
            [opI32Const],
            encodeSLEB128 overflowRowTag,
            [opElse],
            [opI32Const],
            encodeSLEB128 underflowRowTag,
            [opEnd],
            [opI32Store, 0x02, 0x00],
            [opLocalGet],
            encodeULEB128 6,
            [opLocalGet],
            encodeULEB128 5,
            [opI32Store, 0x02, 0x04],
            -- cell = __alloc(8); store Left tag; store row at offset=4
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 8,
            storeTagBytes 8 (ptLeft ptags),
            [opLocalGet],
            encodeULEB128 8,
            [opLocalGet],
            encodeULEB128 6,
            [opI32Store, 0x02, 0x04],
            [opElse],
            -- else: Right s
            -- box = __alloc(4); store s
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 7,
            [opLocalGet],
            encodeULEB128 7,
            [opLocalGet],
            encodeULEB128 4,
            [opI32Store, 0x02, 0x00],
            -- cell = __alloc(8); store Right tag; store offset=4 box
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 8,
            storeTagBytes 8 (ptRight ptags),
            [opLocalGet],
            encodeULEB128 8,
            [opLocalGet],
            encodeULEB128 7,
            [opI32Store, 0x02, 0x04],
            [opEnd],
            -- Callee takes ownership; dec both args before return.
            decArgBin 0,
            decArgBin 1,
            -- return cell
            [opLocalGet],
            encodeULEB128 8
          ]

-- __addUInt8(pa: i32, pb: i32) -> i32
-- addUInt8: UInt8 -> UInt8 -> Either OverflowError UInt8. Sum is in
-- 0..510 so a single 'i32.gt_u 255' check picks the branch — no
-- widening, no mask on the ok path.
-- Locals: $s(2) $oe(3) $box(4) $cell(5).
codeAddU8 :: WasmInfo -> [Word8]
codeAddU8 info =
  let ptags = wiTags info
   in encodeBody
        (encodeLocals 4)
        $ concat
          [ [opLocalGet],
            encodeULEB128 0,
            [opI32Load, 0x02, 0x00],
            [opLocalGet],
            encodeULEB128 1,
            [opI32Load, 0x02, 0x00],
            [opI32Add],
            [opLocalSet],
            encodeULEB128 2,
            [opLocalGet],
            encodeULEB128 2,
            [opI32Const],
            encodeSLEB128 255,
            [opI32GtU],
            [opIf, blocktypeVoid],
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 3,
            storeTagBytes 3 (ptOverflowError ptags),
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 5,
            storeTagBytes 5 (ptLeft ptags),
            [opLocalGet],
            encodeULEB128 5,
            [opLocalGet],
            encodeULEB128 3,
            [opI32Store, 0x02, 0x04],
            [opElse],
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 2,
            [opI32Store, 0x02, 0x00],
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 5,
            storeTagBytes 5 (ptRight ptags),
            [opLocalGet],
            encodeULEB128 5,
            [opLocalGet],
            encodeULEB128 4,
            [opI32Store, 0x02, 0x04],
            [opEnd],
            -- Callee takes ownership; dec both args before return.
            decArgBin 0,
            decArgBin 1,
            [opLocalGet],
            encodeULEB128 5
          ]

-- __subInt32(pa: i32, pb: i32) -> i32
-- subInt32: Int32 -> Int32 -> Either ArithError Int32. Same XOR-based
-- signed-overflow detection as 'codeAddI32', with i32.sub replacing
-- i32.add and the second XOR comparing 'a' vs 'diff' (the standard
-- subtraction overflow check). Direction (over vs under) is read off
-- 'a >= 0', identical to 'codeAddI32'.
-- Locals: $a(2) $b(3) $d(4) $ae(5) $box(6) $cell(7).
codeSubI32 :: WasmInfo -> [Word8]
codeSubI32 info =
  let ptags = wiTags info
   in encodeBody
        (encodeLocals 7)
        $ concat
          [ [opLocalGet],
            encodeULEB128 0,
            [opI32Load, 0x02, 0x00],
            [opLocalSet],
            encodeULEB128 2,
            [opLocalGet],
            encodeULEB128 1,
            [opI32Load, 0x02, 0x00],
            [opLocalSet],
            encodeULEB128 3,
            [opLocalGet],
            encodeULEB128 2,
            [opLocalGet],
            encodeULEB128 3,
            [opI32Sub],
            [opLocalSet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 2,
            [opLocalGet],
            encodeULEB128 3,
            [opI32Xor],
            [opLocalGet],
            encodeULEB128 2,
            [opLocalGet],
            encodeULEB128 4,
            [opI32Xor],
            [opI32And],
            [opI32Const],
            encodeSLEB128 0,
            [opI32LtS],
            [opIf, blocktypeVoid],
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 5,
            [opLocalGet],
            encodeULEB128 5,
            [opLocalGet],
            encodeULEB128 2,
            [opI32Const],
            encodeSLEB128 0,
            [opI32GeS],
            [opIf, blocktypeI32],
            [opI32Const],
            encodeSLEB128 (fromIntegral (ptOverflowError ptags)),
            [opElse],
            [opI32Const],
            encodeSLEB128 (fromIntegral (ptUnderflowError ptags)),
            [opEnd],
            [opI32Store, 0x02, 0x00],
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 6,
            [opLocalGet],
            encodeULEB128 6,
            [opLocalGet],
            encodeULEB128 2,
            [opI32Const],
            encodeSLEB128 0,
            [opI32GeS],
            [opIf, blocktypeI32],
            [opI32Const],
            encodeSLEB128 overflowRowTag,
            [opElse],
            [opI32Const],
            encodeSLEB128 underflowRowTag,
            [opEnd],
            [opI32Store, 0x02, 0x00],
            [opLocalGet],
            encodeULEB128 6,
            [opLocalGet],
            encodeULEB128 5,
            [opI32Store, 0x02, 0x04],
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 8,
            storeTagBytes 8 (ptLeft ptags),
            [opLocalGet],
            encodeULEB128 8,
            [opLocalGet],
            encodeULEB128 6,
            [opI32Store, 0x02, 0x04],
            [opElse],
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 7,
            [opLocalGet],
            encodeULEB128 7,
            [opLocalGet],
            encodeULEB128 4,
            [opI32Store, 0x02, 0x00],
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 8,
            storeTagBytes 8 (ptRight ptags),
            [opLocalGet],
            encodeULEB128 8,
            [opLocalGet],
            encodeULEB128 7,
            [opI32Store, 0x02, 0x04],
            [opEnd],
            -- Callee takes ownership; dec both args before return.
            decArgBin 0,
            decArgBin 1,
            [opLocalGet],
            encodeULEB128 8
          ]

-- __mulInt32(pa: i32, pb: i32) -> i32
-- mulInt32: Int32 -> Int32 -> Either ArithError Int32. Both operands
-- are sign-extended to i64, multiplied at long width, and the result
-- range-checked against [INT32_MIN, INT32_MAX] via 'i64.gt_s' and
-- 'i64.lt_s'. Direction: i64.gt_s → Overflow (tag 1), i64.lt_s →
-- Underflow (tag 0). On the ok path, 'i32.wrap_i64' truncates back
-- to i32 — faithful when the result is in i32 range by the comparison.
-- Locals (after the two i32 params): $p (i64, slot 2),

-- $ae(i32, slot 3), $box(i32, slot 4), $cell(i32, slot 5).

codeMulI32 :: WasmInfo -> [Word8]
codeMulI32 info =
  let ptags = wiTags info
   in encodeBody
        -- 1 i64 local + 4 i32 locals — must be encoded as two separate
        -- (count, valtype) pairs in the WASM locals declaration. The
        -- extra i32 slot vs the old (Either ArithError Int32) shape holds
        -- the row-wrap box that sits between the inner @CCon@ and the
        -- outer @Left@.
        (encodeVec [encodeULEB128 1 <> [valtypeI64], encodeULEB128 4 <> [valtypeI32]])
        $ concat
          [ -- p = i64.extend_i32_s(load(pa)) * i64.extend_i32_s(load(pb))
            [opLocalGet],
            encodeULEB128 0,
            [opI32Load, 0x02, 0x00],
            [opI64ExtendI32S],
            [opLocalGet],
            encodeULEB128 1,
            [opI32Load, 0x02, 0x00],
            [opI64ExtendI32S],
            [opI64Mul],
            [opLocalSet],
            encodeULEB128 2,
            -- if (p > maxInt32 as i64)
            [opLocalGet],
            encodeULEB128 2,
            [opI64Const],
            encodeSLEB128 2147483647,
            [opI64GtS],
            [opIf, blocktypeVoid],
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 3,
            storeTagBytes 3 (ptOverflowError ptags),
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 6,
            [opLocalGet],
            encodeULEB128 6,
            [opI32Const],
            encodeSLEB128 overflowRowTag,
            [opI32Store, 0x02, 0x00],
            [opLocalGet],
            encodeULEB128 6,
            [opLocalGet],
            encodeULEB128 3,
            [opI32Store, 0x02, 0x04],
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 5,
            storeTagBytes 5 (ptLeft ptags),
            [opLocalGet],
            encodeULEB128 5,
            [opLocalGet],
            encodeULEB128 6,
            [opI32Store, 0x02, 0x04],
            [opElse],
            [opLocalGet],
            encodeULEB128 2,
            [opI64Const],
            encodeSLEB128 (-2147483648),
            [opI64LtS],
            [opIf, blocktypeVoid],
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 3,
            storeTagBytes 3 (ptUnderflowError ptags),
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 6,
            [opLocalGet],
            encodeULEB128 6,
            [opI32Const],
            encodeSLEB128 underflowRowTag,
            [opI32Store, 0x02, 0x00],
            [opLocalGet],
            encodeULEB128 6,
            [opLocalGet],
            encodeULEB128 3,
            [opI32Store, 0x02, 0x04],
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 5,
            storeTagBytes 5 (ptLeft ptags),
            [opLocalGet],
            encodeULEB128 5,
            [opLocalGet],
            encodeULEB128 6,
            [opI32Store, 0x02, 0x04],
            [opElse],
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 2,
            [opI32WrapI64],
            [opI32Store, 0x02, 0x00],
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 5,
            storeTagBytes 5 (ptRight ptags),
            [opLocalGet],
            encodeULEB128 5,
            [opLocalGet],
            encodeULEB128 4,
            [opI32Store, 0x02, 0x04],
            [opEnd],
            [opEnd],
            -- Callee takes ownership; dec both args before return.
            decArgBin 0,
            decArgBin 1,
            [opLocalGet],
            encodeULEB128 5
          ]

-- __negInt32(p: i32) -> i32
-- negInt32: Int32 -> Either OverflowError Int32. Mirror of 'codeSuccI32'
-- with INT32_MIN as the boundary and 'i32.sub 0 v' for the ok branch.
-- Locals: $v(1) $oe(2) $box(3) $cell(4).
codeNegI32 :: WasmInfo -> [Word8]
codeNegI32 info =
  let ptags = wiTags info
   in encodeBody
        (encodeLocals 4)
        $ concat
          [ [opLocalGet],
            encodeULEB128 0,
            [opI32Load, 0x02, 0x00],
            [opLocalSet],
            encodeULEB128 1,
            [opLocalGet],
            encodeULEB128 1,
            [opI32Const],
            encodeSLEB128 (-2147483648),
            [opI32Eq],
            [opIf, blocktypeVoid],
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 2,
            storeTagBytes 2 (ptOverflowError ptags),
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 4,
            storeTagBytes 4 (ptLeft ptags),
            [opLocalGet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 2,
            [opI32Store, 0x02, 0x04],
            [opElse],
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 3,
            [opLocalGet],
            encodeULEB128 3,
            [opI32Const],
            encodeSLEB128 0,
            [opLocalGet],
            encodeULEB128 1,
            [opI32Sub],
            [opI32Store, 0x02, 0x00],
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 4,
            storeTagBytes 4 (ptRight ptags),
            [opLocalGet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 3,
            [opI32Store, 0x02, 0x04],
            [opEnd],
            -- Callee takes ownership; dec the arg before return.
            decArgBin 0,
            [opLocalGet],
            encodeULEB128 4
          ]

-- __subUInt8(pa: i32, pb: i32) -> i32
-- subUInt8: UInt8 -> UInt8 -> Either UnderflowError UInt8. The i32
-- difference is in -255..255; one 'i32.lt_s 0' check picks the underflow
-- branch — no widening or mask needed.
-- Locals: $d(2) $ue(3) $box(4) $cell(5).
codeSubU8 :: WasmInfo -> [Word8]
codeSubU8 info =
  let ptags = wiTags info
   in encodeBody
        (encodeLocals 4)
        $ concat
          [ -- d = i32.load(pa) - i32.load(pb)
            [opLocalGet],
            encodeULEB128 0,
            [opI32Load, 0x02, 0x00],
            [opLocalGet],
            encodeULEB128 1,
            [opI32Load, 0x02, 0x00],
            [opI32Sub],
            [opLocalSet],
            encodeULEB128 2,
            -- if (d < 0)
            [opLocalGet],
            encodeULEB128 2,
            [opI32Const],
            encodeSLEB128 0,
            [opI32LtS],
            [opIf, blocktypeVoid],
            -- then: Left UnderflowError
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 3,
            storeTagBytes 3 (ptUnderflowError ptags),
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 5,
            storeTagBytes 5 (ptLeft ptags),
            [opLocalGet],
            encodeULEB128 5,
            [opLocalGet],
            encodeULEB128 3,
            [opI32Store, 0x02, 0x04],
            [opElse],
            -- else: Right d
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 2,
            [opI32Store, 0x02, 0x00],
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 5,
            storeTagBytes 5 (ptRight ptags),
            [opLocalGet],
            encodeULEB128 5,
            [opLocalGet],
            encodeULEB128 4,
            [opI32Store, 0x02, 0x04],
            [opEnd],
            -- Callee takes ownership; dec both args before return.
            decArgBin 0,
            decArgBin 1,
            [opLocalGet],
            encodeULEB128 5
          ]

-- __mulUInt8(pa: i32, pb: i32) -> i32
-- mulUInt8: UInt8 -> UInt8 -> Either OverflowError UInt8. Inputs in
-- 0..255 give an i32 product in 0..65025 — well within i32 range. A
-- single 'i32.gt_u 255' check picks the branch.
-- Locals: $p(2) $oe(3) $box(4) $cell(5).
codeMulU8 :: WasmInfo -> [Word8]
codeMulU8 info =
  let ptags = wiTags info
   in encodeBody
        (encodeLocals 4)
        $ concat
          [ -- p = i32.load(pa) * i32.load(pb)
            [opLocalGet],
            encodeULEB128 0,
            [opI32Load, 0x02, 0x00],
            [opLocalGet],
            encodeULEB128 1,
            [opI32Load, 0x02, 0x00],
            [opI32Mul],
            [opLocalSet],
            encodeULEB128 2,
            -- if (p > 255)
            [opLocalGet],
            encodeULEB128 2,
            [opI32Const],
            encodeSLEB128 255,
            [opI32GtU],
            [opIf, blocktypeVoid],
            -- then: Left OverflowError
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 3,
            storeTagBytes 3 (ptOverflowError ptags),
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 5,
            storeTagBytes 5 (ptLeft ptags),
            [opLocalGet],
            encodeULEB128 5,
            [opLocalGet],
            encodeULEB128 3,
            [opI32Store, 0x02, 0x04],
            [opElse],
            -- else: Right p
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 2,
            [opI32Store, 0x02, 0x00],
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 5,
            storeTagBytes 5 (ptRight ptags),
            [opLocalGet],
            encodeULEB128 5,
            [opLocalGet],
            encodeULEB128 4,
            [opI32Store, 0x02, 0x04],
            [opEnd],
            -- Callee takes ownership; dec both args before return.
            decArgBin 0,
            decArgBin 1,
            [opLocalGet],
            encodeULEB128 5
          ]

-- __predUInt32(p: i32) -> i32
-- predUInt32: UInt32 -> Either UnderflowError UInt32. Identical body
-- to 'codePredU8' — the underflow boundary is also 0 and i32.eqz / i32.sub
-- work bit-pattern-identically for u32.
-- Locals: $v(1) $ue(2) $box(3) $cell(4).
codePredU32 :: WasmInfo -> [Word8]
codePredU32 info =
  let ptags = wiTags info
   in encodeBody
        (encodeLocals 4)
        $ concat
          [ [opLocalGet],
            encodeULEB128 0,
            [opI32Load, 0x02, 0x00],
            [opLocalSet],
            encodeULEB128 1,
            [opLocalGet],
            encodeULEB128 1,
            [opI32Eqz],
            [opIf, blocktypeVoid],
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 2,
            storeTagBytes 2 (ptUnderflowError ptags),
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 4,
            storeTagBytes 4 (ptLeft ptags),
            [opLocalGet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 2,
            [opI32Store, 0x02, 0x04],
            [opElse],
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 3,
            [opLocalGet],
            encodeULEB128 3,
            [opLocalGet],
            encodeULEB128 1,
            [opI32Const],
            encodeSLEB128 1,
            [opI32Sub],
            [opI32Store, 0x02, 0x00],
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 4,
            storeTagBytes 4 (ptRight ptags),
            [opLocalGet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 3,
            [opI32Store, 0x02, 0x04],
            [opEnd],
            -- Callee takes ownership; dec the arg before return.
            decArgBin 0,
            [opLocalGet],
            encodeULEB128 4
          ]

-- __succUInt32(p: i32) -> i32
-- succUInt32: UInt32 -> Either OverflowError UInt32. Mirrors 'codeSuccU8'
-- but checks against 4294967295 — encoded as 'i32.const -1' (same bit
-- pattern). On the ok path '(v + 1)' wraps modulo 2^32, but since v is
-- already known to be < 4294967295, the result fits in u32 without wrap.
-- Locals: $v(1) $oe(2) $box(3) $cell(4).
codeSuccU32 :: WasmInfo -> [Word8]
codeSuccU32 info =
  let ptags = wiTags info
   in encodeBody
        (encodeLocals 4)
        $ concat
          [ [opLocalGet],
            encodeULEB128 0,
            [opI32Load, 0x02, 0x00],
            [opLocalSet],
            encodeULEB128 1,
            [opLocalGet],
            encodeULEB128 1,
            [opI32Const],
            encodeSLEB128 (-1),
            [opI32Eq],
            [opIf, blocktypeVoid],
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 2,
            storeTagBytes 2 (ptOverflowError ptags),
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 4,
            storeTagBytes 4 (ptLeft ptags),
            [opLocalGet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 2,
            [opI32Store, 0x02, 0x04],
            [opElse],
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 3,
            [opLocalGet],
            encodeULEB128 3,
            [opLocalGet],
            encodeULEB128 1,
            [opI32Const],
            encodeSLEB128 1,
            [opI32Add],
            [opI32Store, 0x02, 0x00],
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 4,
            storeTagBytes 4 (ptRight ptags),
            [opLocalGet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 3,
            [opI32Store, 0x02, 0x04],
            [opEnd],
            -- Callee takes ownership; dec the arg before return.
            decArgBin 0,
            [opLocalGet],
            encodeULEB128 4
          ]

-- __addUInt32(pa: i32, pb: i32) -> i32
-- addUInt32: UInt32 -> UInt32 -> Either OverflowError UInt32. Promote
-- both operands to i64 (extend_i32_u, unsigned), sum at 64-bit width,
-- compare against 4294967295. The sum fits in i64 signed (max ~2*2^32),
-- so 'i64.gt_s' is equivalent to 'i64.gt_u' here — but keep gt_u for
-- semantic clarity with 'codeMulU32'.
-- Locals: 1 i64 ($s) + 4 i32 ($oe, $box, $cell, padding) — slots 2..5
-- with the i64 in slot 2.
codeAddU32 :: WasmInfo -> [Word8]
codeAddU32 info =
  let ptags = wiTags info
   in encodeBody
        (encodeVec [encodeULEB128 1 <> [valtypeI64], encodeULEB128 3 <> [valtypeI32]])
        $ concat
          [ -- s = i64.extend_i32_u(load(pa)) + i64.extend_i32_u(load(pb))
            [opLocalGet],
            encodeULEB128 0,
            [opI32Load, 0x02, 0x00],
            [opI64ExtendI32U],
            [opLocalGet],
            encodeULEB128 1,
            [opI32Load, 0x02, 0x00],
            [opI64ExtendI32U],
            [opI64Add],
            [opLocalSet],
            encodeULEB128 2,
            -- if (s >u 4294967295)
            [opLocalGet],
            encodeULEB128 2,
            [opI64Const],
            encodeSLEB128I64 4294967295,
            [opI64GtU],
            [opIf, blocktypeVoid],
            -- then: Left OverflowError
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 3,
            storeTagBytes 3 (ptOverflowError ptags),
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 5,
            storeTagBytes 5 (ptLeft ptags),
            [opLocalGet],
            encodeULEB128 5,
            [opLocalGet],
            encodeULEB128 3,
            [opI32Store, 0x02, 0x04],
            [opElse],
            -- else: Right (i32.wrap_i64 s)
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 2,
            [opI32WrapI64],
            [opI32Store, 0x02, 0x00],
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 5,
            storeTagBytes 5 (ptRight ptags),
            [opLocalGet],
            encodeULEB128 5,
            [opLocalGet],
            encodeULEB128 4,
            [opI32Store, 0x02, 0x04],
            [opEnd],
            -- Callee takes ownership; dec both args before return.
            decArgBin 0,
            decArgBin 1,
            [opLocalGet],
            encodeULEB128 5
          ]

-- __subUInt32(pa: i32, pb: i32) -> i32
-- subUInt32: UInt32 -> UInt32 -> Either UnderflowError UInt32. Compare
-- 'a <u b' at i32 width (treats both stored cells as unsigned), then
-- 'i32.sub' produces the correct difference on the ok path.
-- Locals: $a(2) $b(3) $ue(4) $box(5) $cell(6).
codeSubU32 :: WasmInfo -> [Word8]
codeSubU32 info =
  let ptags = wiTags info
   in encodeBody
        (encodeLocals 5)
        $ concat
          [ -- a = i32.load(pa)
            [opLocalGet],
            encodeULEB128 0,
            [opI32Load, 0x02, 0x00],
            [opLocalSet],
            encodeULEB128 2,
            -- b = i32.load(pb)
            [opLocalGet],
            encodeULEB128 1,
            [opI32Load, 0x02, 0x00],
            [opLocalSet],
            encodeULEB128 3,
            -- if (a <u b)
            [opLocalGet],
            encodeULEB128 2,
            [opLocalGet],
            encodeULEB128 3,
            [opI32LtU],
            [opIf, blocktypeVoid],
            -- then: Left UnderflowError
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 4,
            storeTagBytes 4 (ptUnderflowError ptags),
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 6,
            storeTagBytes 6 (ptLeft ptags),
            [opLocalGet],
            encodeULEB128 6,
            [opLocalGet],
            encodeULEB128 4,
            [opI32Store, 0x02, 0x04],
            [opElse],
            -- else: Right (a - b)
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 5,
            [opLocalGet],
            encodeULEB128 5,
            [opLocalGet],
            encodeULEB128 2,
            [opLocalGet],
            encodeULEB128 3,
            [opI32Sub],
            [opI32Store, 0x02, 0x00],
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 6,
            storeTagBytes 6 (ptRight ptags),
            [opLocalGet],
            encodeULEB128 6,
            [opLocalGet],
            encodeULEB128 5,
            [opI32Store, 0x02, 0x04],
            [opEnd],
            -- Callee takes ownership; dec both args before return.
            decArgBin 0,
            decArgBin 1,
            [opLocalGet],
            encodeULEB128 6
          ]

-- __mulUInt32(pa: i32, pb: i32) -> i32
-- mulUInt32: UInt32 -> UInt32 -> Either OverflowError UInt32. Promote
-- both operands to i64 unsigned, multiply at 64-bit width, compare
-- against 4294967295 with 'i64.gt_u'. The product (2^32-1)^2 ≈ 1.8 *
-- 2^63 fits in u64 but not in i64 signed, so we *must* use 'i64.gt_u'
-- here (where 'codeAddU32' could use either).
-- Locals: 1 i64 ($p) + 3 i32 ($oe, $box, $cell) — i64 in slot 2.
codeMulU32 :: WasmInfo -> [Word8]
codeMulU32 info =
  let ptags = wiTags info
   in encodeBody
        (encodeVec [encodeULEB128 1 <> [valtypeI64], encodeULEB128 3 <> [valtypeI32]])
        $ concat
          [ -- p = i64.extend_i32_u(load(pa)) * i64.extend_i32_u(load(pb))
            [opLocalGet],
            encodeULEB128 0,
            [opI32Load, 0x02, 0x00],
            [opI64ExtendI32U],
            [opLocalGet],
            encodeULEB128 1,
            [opI32Load, 0x02, 0x00],
            [opI64ExtendI32U],
            [opI64Mul],
            [opLocalSet],
            encodeULEB128 2,
            -- if (p >u 4294967295)
            [opLocalGet],
            encodeULEB128 2,
            [opI64Const],
            encodeSLEB128I64 4294967295,
            [opI64GtU],
            [opIf, blocktypeVoid],
            -- then: Left OverflowError
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 3,
            storeTagBytes 3 (ptOverflowError ptags),
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 5,
            storeTagBytes 5 (ptLeft ptags),
            [opLocalGet],
            encodeULEB128 5,
            [opLocalGet],
            encodeULEB128 3,
            [opI32Store, 0x02, 0x04],
            [opElse],
            -- else: Right (i32.wrap_i64 p)
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 2,
            [opI32WrapI64],
            [opI32Store, 0x02, 0x00],
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 5,
            storeTagBytes 5 (ptRight ptags),
            [opLocalGet],
            encodeULEB128 5,
            [opLocalGet],
            encodeULEB128 4,
            [opI32Store, 0x02, 0x04],
            [opEnd],
            -- Callee takes ownership; dec both args before return.
            decArgBin 0,
            decArgBin 1,
            [opLocalGet],
            encodeULEB128 5
          ]

-- __splitOnFirst(sep: i32, str: i32) -> i32
-- splitOnFirst: String -> String -> Maybe (Tuple2 String String). Hand-
-- rolled byte scan since WASM has no built-in substring search. The
-- empty-separator and "separator longer than str" cases are handled
-- implicitly by the loop bounds.
-- Locals (beyond the two params): $sep_len(2) $str_len(3) $i(4) $j(5)
-- pos(6) $match(7) $prefix(8) $suffix(9) $tuple(10) $cell(11)

-- $suf_len(12) \$u16(13).

codeSplitOnFirst :: WasmInfo -> [Word8]
codeSplitOnFirst info =
  let ptags = wiTags info
   in encodeBody
        (encodeLocals 12)
        $ concat
          [ -- sep_len = i32.load($sep) — byte_count from header
            [opLocalGet],
            encodeULEB128 0,
            [opI32Load, 0x02, 0x00],
            [opLocalSet],
            encodeULEB128 2,
            -- str_len = i32.load($str)
            [opLocalGet],
            encodeULEB128 1,
            [opI32Load, 0x02, 0x00],
            [opLocalSet],
            encodeULEB128 3,
            -- pos = -1
            [opI32Const],
            encodeSLEB128 (-1),
            [opLocalSet],
            encodeULEB128 6,
            -- i = 0
            [opI32Const],
            encodeSLEB128 0,
            [opLocalSet],
            encodeULEB128 4,
            -- block $break
            [opBlock, blocktypeVoid],
            --   loop $loop
            [opLoop, blocktypeVoid],
            --     br_if $break (i + sep_len > str_len)
            [opLocalGet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 2,
            [opI32Add],
            [opLocalGet],
            encodeULEB128 3,
            [opI32GtU],
            [opBrIf],
            encodeULEB128 1, -- depth 1 = $break
            --     $j = 0
            [opI32Const],
            encodeSLEB128 0,
            [opLocalSet],
            encodeULEB128 5,
            --     $match = 1
            [opI32Const],
            encodeSLEB128 1,
            [opLocalSet],
            encodeULEB128 7,
            --     block $check_break
            [opBlock, blocktypeVoid],
            --       loop $check_loop
            [opLoop, blocktypeVoid],
            --         br_if $check_break (j == sep_len)  — full match: leave $match=1
            [opLocalGet],
            encodeULEB128 5,
            [opLocalGet],
            encodeULEB128 2,
            [opI32Eq],
            [opBrIf],
            encodeULEB128 1, -- depth 1 = $check_break
            --         if (str_payload[i+j] != sep_payload[j]) — load with offset=8
            [opLocalGet],
            encodeULEB128 1, -- str
            [opLocalGet],
            encodeULEB128 4, -- i
            [opI32Add],
            [opLocalGet],
            encodeULEB128 5, -- j
            [opI32Add],
            [opI32Load8U, 0x00, 0x08],
            [opLocalGet],
            encodeULEB128 0, -- sep
            [opLocalGet],
            encodeULEB128 5, -- j
            [opI32Add],
            [opI32Load8U, 0x00, 0x08],
            [opI32Ne],
            [opIf, blocktypeVoid],
            --           $match = 0; br $check_break
            [opI32Const],
            encodeSLEB128 0,
            [opLocalSet],
            encodeULEB128 7,
            [opBr],
            encodeULEB128 2, -- if=0, check_loop=1, check_break=2
            [opEnd], -- end if
            --         $j = $j + 1
            [opLocalGet],
            encodeULEB128 5,
            [opI32Const],
            encodeSLEB128 1,
            [opI32Add],
            [opLocalSet],
            encodeULEB128 5,
            --         br $check_loop
            [opBr],
            encodeULEB128 0,
            [opEnd], -- end loop $check_loop
            [opEnd], -- end block $check_break
            --     if ($match)  → record pos and break out
            [opLocalGet],
            encodeULEB128 7,
            [opIf, blocktypeVoid],
            --       $pos = $i
            [opLocalGet],
            encodeULEB128 4,
            [opLocalSet],
            encodeULEB128 6,
            --       br $break  (if=0, loop=1, break=2)
            [opBr],
            encodeULEB128 2,
            [opEnd], -- end if
            --     $i = $i + 1
            [opLocalGet],
            encodeULEB128 4,
            [opI32Const],
            encodeSLEB128 1,
            [opI32Add],
            [opLocalSet],
            encodeULEB128 4,
            --     br $loop
            [opBr],
            encodeULEB128 0,
            [opEnd], -- end loop $loop
            [opEnd], -- end block $break
            -- if ($pos == -1) Nothing else Just (Tuple2 prefix suffix)
            [opLocalGet],
            encodeULEB128 6,
            [opI32Const],
            encodeSLEB128 (-1),
            [opI32Eq],
            [opIf, blocktypeVoid],
            --   Nothing: cell = alloc 4; store tag
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 11,
            storeTagBytes 11 (ptNothing ptags),
            [opElse],
            --   prefix = alloc(8 + pos) — length-prefixed.
            [opLocalGet],
            encodeULEB128 6, -- pos
            [opI32Const],
            encodeSLEB128 8,
            [opI32Add],
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 8, -- prefix
            --     header.byte_count = pos
            [opLocalGet],
            encodeULEB128 8,
            [opLocalGet],
            encodeULEB128 6,
            [opI32Store, 0x02, 0x00],
            --     u16 = __utf16_of_range(str+8, pos)
            [opLocalGet],
            encodeULEB128 1,
            [opI32Const],
            encodeSLEB128 8,
            [opI32Add],
            [opLocalGet],
            encodeULEB128 6,
            [opCall],
            encodeULEB128 idxUtf16OfRange,
            [opLocalSet],
            encodeULEB128 13,
            --     header.utf16_count = u16
            [opLocalGet],
            encodeULEB128 8,
            [opLocalGet],
            encodeULEB128 13,
            [opI32Store, 0x02, 0x04],
            --     memcpy(prefix+8, str+8, pos)
            [opLocalGet],
            encodeULEB128 8,
            [opI32Const],
            encodeSLEB128 8,
            [opI32Add],
            [opLocalGet],
            encodeULEB128 1,
            [opI32Const],
            encodeSLEB128 8,
            [opI32Add],
            [opLocalGet],
            encodeULEB128 6,
            [opCall],
            encodeULEB128 idxMemcpy,
            --   suf_len = str_len - pos - sep_len
            [opLocalGet],
            encodeULEB128 3, -- str_len
            [opLocalGet],
            encodeULEB128 6, -- pos
            [opI32Sub],
            [opLocalGet],
            encodeULEB128 2, -- sep_len
            [opI32Sub],
            [opLocalSet],
            encodeULEB128 12, -- suf_len
            --   suffix = alloc(8 + suf_len) — length-prefixed.
            [opLocalGet],
            encodeULEB128 12,
            [opI32Const],
            encodeSLEB128 8,
            [opI32Add],
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 9, -- suffix
            --     header.byte_count = suf_len
            [opLocalGet],
            encodeULEB128 9,
            [opLocalGet],
            encodeULEB128 12,
            [opI32Store, 0x02, 0x00],
            --     u16 = __utf16_of_range(str+8 + pos + sep_len, suf_len)
            [opLocalGet],
            encodeULEB128 1,
            [opI32Const],
            encodeSLEB128 8,
            [opI32Add],
            [opLocalGet],
            encodeULEB128 6,
            [opI32Add],
            [opLocalGet],
            encodeULEB128 2,
            [opI32Add],
            [opLocalGet],
            encodeULEB128 12,
            [opCall],
            encodeULEB128 idxUtf16OfRange,
            [opLocalSet],
            encodeULEB128 13,
            --     header.utf16_count = u16
            [opLocalGet],
            encodeULEB128 9,
            [opLocalGet],
            encodeULEB128 13,
            [opI32Store, 0x02, 0x04],
            --     memcpy(suffix+8, str+8+pos+sep_len, suf_len)
            [opLocalGet],
            encodeULEB128 9,
            [opI32Const],
            encodeSLEB128 8,
            [opI32Add],
            [opLocalGet],
            encodeULEB128 1,
            [opI32Const],
            encodeSLEB128 8,
            [opI32Add],
            [opLocalGet],
            encodeULEB128 6,
            [opI32Add],
            [opLocalGet],
            encodeULEB128 2,
            [opI32Add],
            [opLocalGet],
            encodeULEB128 12,
            [opCall],
            encodeULEB128 idxMemcpy,
            --   tuple = alloc 12; [Tuple2 tag, prefix, suffix]
            [opI32Const],
            encodeSLEB128 12,
            [opI32Const],
            encodeSLEB128 2,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 10, -- tuple
            storeTagBytes 10 (ptTuple2 ptags),
            [opLocalGet],
            encodeULEB128 10,
            [opLocalGet],
            encodeULEB128 8,
            [opI32Store, 0x02, 0x04],
            [opLocalGet],
            encodeULEB128 10,
            [opLocalGet],
            encodeULEB128 9,
            [opI32Store, 0x02, 0x08],
            --   cell = alloc 8; [Just tag, tuple]
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 11, -- cell
            storeTagBytes 11 (ptJust ptags),
            [opLocalGet],
            encodeULEB128 11,
            [opLocalGet],
            encodeULEB128 10,
            [opI32Store, 0x02, 0x04],
            [opEnd], -- end if/else (cell in slot 11)
            -- Callee takes ownership; dec both args before return.
            decArgBin 0,
            decArgBin 1,
            [opLocalGet],
            encodeULEB128 11
          ]

-- __parseInt32(s: i32) -> i32
-- parseInt32: String -> Either ParseError Int32. Hand-rolled byte
-- scan; the int64 accumulator is capped at the magnitude `|minInt32|`
-- using the shift trick `(1 << 31)L`. On any failure path we set
-- `$failed = 1` and `br $exit`; the final `if` after the block builds
-- Right or Left ParseError.
-- Locals (beyond the param): $len(1) $i(2) $neg(3) $c(4) $box(5)
-- cell(6) $pe(7) $failed(8) $acc(9 — i64).
codeParseInt32 :: WasmInfo -> [Word8]
codeParseInt32 info =
  let ptags = wiTags info
      -- Two local groups: 8 i32, then 1 i64.
      locals =
        encodeULEB128 2
          <> encodeULEB128 8
          <> [valtypeI32]
          <> encodeULEB128 1
          <> [valtypeI64]
   in encodeBody locals
        $ concat
          [ -- failed = 0
            [opI32Const],
            encodeSLEB128 0,
            [opLocalSet],
            encodeULEB128 8,
            -- acc = 0L
            [opI64Const],
            encodeSLEB128 0,
            [opLocalSet],
            encodeULEB128 9,
            -- len = i32.load($s) — byte_count from header
            [opLocalGet],
            encodeULEB128 0,
            [opI32Load, 0x02, 0x00],
            [opLocalSet],
            encodeULEB128 1,
            -- block $exit (depth 0 within)
            [opBlock, blocktypeVoid],
            --   if (i32.eqz $len) { $failed = 1; br $exit }
            [opLocalGet],
            encodeULEB128 1,
            [opI32Eqz],
            [opIf, blocktypeVoid],
            [opI32Const],
            encodeSLEB128 1,
            [opLocalSet],
            encodeULEB128 8,
            [opBr],
            encodeULEB128 1,
            [opEnd],
            --   $i = 0
            [opI32Const],
            encodeSLEB128 0,
            [opLocalSet],
            encodeULEB128 2,
            --   $neg = 0
            [opI32Const],
            encodeSLEB128 0,
            [opLocalSet],
            encodeULEB128 3,
            --   if (load8_u $s+8 == 45) { $neg = 1; $i = 1; if ($len == 1) { … } }
            [opLocalGet],
            encodeULEB128 0,
            [opI32Load8U, 0x00, 0x08], -- payload byte 0 = (s + 8 + 0)
            [opI32Const],
            encodeSLEB128 45,
            [opI32Eq],
            [opIf, blocktypeVoid],
            [opI32Const],
            encodeSLEB128 1,
            [opLocalSet],
            encodeULEB128 3,
            [opI32Const],
            encodeSLEB128 1,
            [opLocalSet],
            encodeULEB128 2,
            [opLocalGet],
            encodeULEB128 1,
            [opI32Const],
            encodeSLEB128 1,
            [opI32Eq],
            [opIf, blocktypeVoid],
            [opI32Const],
            encodeSLEB128 1,
            [opLocalSet],
            encodeULEB128 8,
            [opBr],
            encodeULEB128 2, -- inner if=0, outer if=1, $exit=2
            [opEnd],
            [opEnd],
            --   block $loop_break (depth 0 within $loop_break)
            [opBlock, blocktypeVoid],
            --     loop $loop
            [opLoop, blocktypeVoid],
            --       br_if $loop_break (i >= len)  → depth 1
            [opLocalGet],
            encodeULEB128 2,
            [opLocalGet],
            encodeULEB128 1,
            [opI32GeU],
            [opBrIf],
            encodeULEB128 1,
            --       $c = i32.load8_u(payload + i) ≡ load8_u offset=8 of (s + i)
            [opLocalGet],
            encodeULEB128 0,
            [opLocalGet],
            encodeULEB128 2,
            [opI32Add],
            [opI32Load8U, 0x00, 0x08],
            [opLocalSet],
            encodeULEB128 4,
            --       if (c < 48) { $failed = 1; br $exit }
            [opLocalGet],
            encodeULEB128 4,
            [opI32Const],
            encodeSLEB128 48,
            [opI32LtU],
            [opIf, blocktypeVoid],
            [opI32Const],
            encodeSLEB128 1,
            [opLocalSet],
            encodeULEB128 8,
            [opBr],
            encodeULEB128 3, -- if=0, $loop=1, $loop_break=2, $exit=3
            [opEnd],
            --       if (c > 57) { $failed = 1; br $exit }
            [opLocalGet],
            encodeULEB128 4,
            [opI32Const],
            encodeSLEB128 57,
            [opI32GtU],
            [opIf, blocktypeVoid],
            [opI32Const],
            encodeSLEB128 1,
            [opLocalSet],
            encodeULEB128 8,
            [opBr],
            encodeULEB128 3,
            [opEnd],
            --       $acc = $acc * 10 + extend_u(c - '0')
            [opLocalGet],
            encodeULEB128 9,
            [opI64Const],
            encodeSLEB128 10,
            [opI64Mul],
            [opLocalGet],
            encodeULEB128 4,
            [opI32Const],
            encodeSLEB128 48,
            [opI32Sub],
            [opI64ExtendI32U],
            [opI64Add],
            [opLocalSet],
            encodeULEB128 9,
            --       if ($acc > (1 << 31)L) { $failed = 1; br $exit }
            [opLocalGet],
            encodeULEB128 9,
            [opI64Const],
            encodeSLEB128 1,
            [opI64Const],
            encodeSLEB128 31,
            [opI64Shl],
            [opI64GtS],
            [opIf, blocktypeVoid],
            [opI32Const],
            encodeSLEB128 1,
            [opLocalSet],
            encodeULEB128 8,
            [opBr],
            encodeULEB128 3,
            [opEnd],
            --       $i = $i + 1
            [opLocalGet],
            encodeULEB128 2,
            [opI32Const],
            encodeSLEB128 1,
            [opI32Add],
            [opLocalSet],
            encodeULEB128 2,
            --       br $loop
            [opBr],
            encodeULEB128 0,
            [opEnd], -- end loop
            [opEnd], -- end block $loop_break
            --   if ($neg) { $acc = 0 - $acc } else { if ($acc > 2147483647L) fail }
            [opLocalGet],
            encodeULEB128 3,
            [opIf, blocktypeVoid],
            [opI64Const],
            encodeSLEB128 0,
            [opLocalGet],
            encodeULEB128 9,
            [opI64Sub],
            [opLocalSet],
            encodeULEB128 9,
            [opElse],
            [opLocalGet],
            encodeULEB128 9,
            [opI64Const],
            encodeSLEB128 2147483647,
            [opI64GtS],
            [opIf, blocktypeVoid],
            [opI32Const],
            encodeSLEB128 1,
            [opLocalSet],
            encodeULEB128 8,
            [opBr],
            encodeULEB128 2, -- inner if=0, outer if-else=1, $exit=2
            [opEnd],
            [opEnd],
            [opEnd], -- end block $exit
            -- if ($failed) Left else Right
            [opLocalGet],
            encodeULEB128 8,
            [opIf, blocktypeVoid],
            -- pe = alloc 4; store ParseError tag
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 7,
            storeTagBytes 7 (ptParseError ptags),
            -- cell = alloc 8; Left tag; offset 4 = pe
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 6,
            storeTagBytes 6 (ptLeft ptags),
            [opLocalGet],
            encodeULEB128 6,
            [opLocalGet],
            encodeULEB128 7,
            [opI32Store, 0x02, 0x04],
            [opElse],
            -- box = alloc 4; store wrap_i64($acc)
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 5,
            [opLocalGet],
            encodeULEB128 5,
            [opLocalGet],
            encodeULEB128 9,
            [opI32WrapI64],
            [opI32Store, 0x02, 0x00],
            -- cell = alloc 8; Right tag; offset 4 = box
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 6,
            storeTagBytes 6 (ptRight ptags),
            [opLocalGet],
            encodeULEB128 6,
            [opLocalGet],
            encodeULEB128 5,
            [opI32Store, 0x02, 0x04],
            [opEnd], -- end if/else (cell in slot 6)
            -- Callee takes ownership; dec the arg before return.
            decArgBin 0,
            [opLocalGet],
            encodeULEB128 6
          ]

-- __parseUInt8(s: i32) -> i32
-- Same shape as 'codeParseInt32' minus the sign handling, with an i32
-- accumulator (the running magnitude never exceeds 2559 before the
-- > 255 check fails the parse).
-- Locals: $len(1) $i(2) $acc(3) $c(4) $box(5) $cell(6) $pe(7) $failed(8).
codeParseUInt8 :: WasmInfo -> [Word8]
codeParseUInt8 info =
  let ptags = wiTags info
   in encodeBody (encodeLocals 8)
        $ concat
          [ -- failed = 0
            [opI32Const],
            encodeSLEB128 0,
            [opLocalSet],
            encodeULEB128 8,
            -- acc = 0
            [opI32Const],
            encodeSLEB128 0,
            [opLocalSet],
            encodeULEB128 3,
            -- len = i32.load($s) — byte_count from header
            [opLocalGet],
            encodeULEB128 0,
            [opI32Load, 0x02, 0x00],
            [opLocalSet],
            encodeULEB128 1,
            -- block $exit
            [opBlock, blocktypeVoid],
            [opLocalGet],
            encodeULEB128 1,
            [opI32Eqz],
            [opIf, blocktypeVoid],
            [opI32Const],
            encodeSLEB128 1,
            [opLocalSet],
            encodeULEB128 8,
            [opBr],
            encodeULEB128 1,
            [opEnd],
            [opI32Const],
            encodeSLEB128 0,
            [opLocalSet],
            encodeULEB128 2,
            --   block $loop_break
            [opBlock, blocktypeVoid],
            [opLoop, blocktypeVoid],
            [opLocalGet],
            encodeULEB128 2,
            [opLocalGet],
            encodeULEB128 1,
            [opI32GeU],
            [opBrIf],
            encodeULEB128 1,
            -- c = i32.load8_u(payload + i) — load8_u offset=8 of (s + i)
            [opLocalGet],
            encodeULEB128 0,
            [opLocalGet],
            encodeULEB128 2,
            [opI32Add],
            [opI32Load8U, 0x00, 0x08],
            [opLocalSet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 4,
            [opI32Const],
            encodeSLEB128 48,
            [opI32LtU],
            [opIf, blocktypeVoid],
            [opI32Const],
            encodeSLEB128 1,
            [opLocalSet],
            encodeULEB128 8,
            [opBr],
            encodeULEB128 3,
            [opEnd],
            [opLocalGet],
            encodeULEB128 4,
            [opI32Const],
            encodeSLEB128 57,
            [opI32GtU],
            [opIf, blocktypeVoid],
            [opI32Const],
            encodeSLEB128 1,
            [opLocalSet],
            encodeULEB128 8,
            [opBr],
            encodeULEB128 3,
            [opEnd],
            [opLocalGet],
            encodeULEB128 3,
            [opI32Const],
            encodeSLEB128 10,
            [opI32Mul],
            [opLocalGet],
            encodeULEB128 4,
            [opI32Const],
            encodeSLEB128 48,
            [opI32Sub],
            [opI32Add],
            [opLocalSet],
            encodeULEB128 3,
            [opLocalGet],
            encodeULEB128 3,
            [opI32Const],
            encodeSLEB128 255,
            [opI32GtU],
            [opIf, blocktypeVoid],
            [opI32Const],
            encodeSLEB128 1,
            [opLocalSet],
            encodeULEB128 8,
            [opBr],
            encodeULEB128 3,
            [opEnd],
            [opLocalGet],
            encodeULEB128 2,
            [opI32Const],
            encodeSLEB128 1,
            [opI32Add],
            [opLocalSet],
            encodeULEB128 2,
            [opBr],
            encodeULEB128 0,
            [opEnd], -- end loop
            [opEnd], -- end block $loop_break
            [opEnd], -- end block $exit
            -- if ($failed) Left else Right
            [opLocalGet],
            encodeULEB128 8,
            [opIf, blocktypeVoid],
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 7,
            storeTagBytes 7 (ptParseError ptags),
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 6,
            storeTagBytes 6 (ptLeft ptags),
            [opLocalGet],
            encodeULEB128 6,
            [opLocalGet],
            encodeULEB128 7,
            [opI32Store, 0x02, 0x04],
            [opElse],
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 5,
            [opLocalGet],
            encodeULEB128 5,
            [opLocalGet],
            encodeULEB128 3,
            [opI32Store, 0x02, 0x00],
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 6,
            storeTagBytes 6 (ptRight ptags),
            [opLocalGet],
            encodeULEB128 6,
            [opLocalGet],
            encodeULEB128 5,
            [opI32Store, 0x02, 0x04],
            [opEnd], -- end if/else (cell in slot 6)
            -- Callee takes ownership; dec the arg before return.
            decArgBin 0,
            [opLocalGet],
            encodeULEB128 6
          ]

-- __parseUInt32(s: i32) -> i32
-- Same shape as 'codeParseUInt8' but with an i64 accumulator (running
-- magnitude up to 4294967295 * 10 + 9 = 42949672959 fits in i64) and
-- a '> 4294967295' fast-fail check. On the ok path the i64 accumulator
-- is wrapped to i32 — the bit pattern of values 0..4294967295 in i64
-- and i32-as-u32 is identical.
-- Locals: $len(1, i32) $i(2, i32) $c(3, i32) $box(4, i32) $cell(5, i32)

-- $pe(6, i32) $failed(7, i32) $acc(8, i64).

codeParseUInt32 :: WasmInfo -> [Word8]
codeParseUInt32 info =
  let ptags = wiTags info
   in encodeBody
        (encodeVec [encodeULEB128 7 <> [valtypeI32], encodeULEB128 1 <> [valtypeI64]])
        $ concat
          [ -- failed = 0
            [opI32Const],
            encodeSLEB128 0,
            [opLocalSet],
            encodeULEB128 7,
            -- acc = 0 (i64)
            [opI64Const],
            encodeSLEB128 0,
            [opLocalSet],
            encodeULEB128 8,
            -- len = i32.load($s) — byte_count from header
            [opLocalGet],
            encodeULEB128 0,
            [opI32Load, 0x02, 0x00],
            [opLocalSet],
            encodeULEB128 1,
            -- block $exit
            [opBlock, blocktypeVoid],
            -- if (len == 0) { failed = 1; br $exit }
            [opLocalGet],
            encodeULEB128 1,
            [opI32Eqz],
            [opIf, blocktypeVoid],
            [opI32Const],
            encodeSLEB128 1,
            [opLocalSet],
            encodeULEB128 7,
            [opBr],
            encodeULEB128 1,
            [opEnd],
            -- i = 0
            [opI32Const],
            encodeSLEB128 0,
            [opLocalSet],
            encodeULEB128 2,
            --   block $loop_break / loop $loop
            [opBlock, blocktypeVoid],
            [opLoop, blocktypeVoid],
            -- br_if $loop_break (i >=u len)
            [opLocalGet],
            encodeULEB128 2,
            [opLocalGet],
            encodeULEB128 1,
            [opI32GeU],
            [opBrIf],
            encodeULEB128 1,
            -- c = i32.load8_u(payload + i) ≡ load8_u offset=8 of (s + i)
            [opLocalGet],
            encodeULEB128 0,
            [opLocalGet],
            encodeULEB128 2,
            [opI32Add],
            [opI32Load8U, 0x00, 0x08],
            [opLocalSet],
            encodeULEB128 3,
            -- if (c <u 48) { failed = 1; br $exit }
            [opLocalGet],
            encodeULEB128 3,
            [opI32Const],
            encodeSLEB128 48,
            [opI32LtU],
            [opIf, blocktypeVoid],
            [opI32Const],
            encodeSLEB128 1,
            [opLocalSet],
            encodeULEB128 7,
            [opBr],
            encodeULEB128 3,
            [opEnd],
            -- if (c >u 57) { failed = 1; br $exit }
            [opLocalGet],
            encodeULEB128 3,
            [opI32Const],
            encodeSLEB128 57,
            [opI32GtU],
            [opIf, blocktypeVoid],
            [opI32Const],
            encodeSLEB128 1,
            [opLocalSet],
            encodeULEB128 7,
            [opBr],
            encodeULEB128 3,
            [opEnd],
            -- acc = acc * 10 + i64.extend_i32_u(c - 48)
            [opLocalGet],
            encodeULEB128 8,
            [opI64Const],
            encodeSLEB128 10,
            [opI64Mul],
            [opLocalGet],
            encodeULEB128 3,
            [opI32Const],
            encodeSLEB128 48,
            [opI32Sub],
            [opI64ExtendI32U],
            [opI64Add],
            [opLocalSet],
            encodeULEB128 8,
            -- if (acc >u 4294967295) { failed = 1; br $exit }
            [opLocalGet],
            encodeULEB128 8,
            [opI64Const],
            encodeSLEB128I64 4294967295,
            [opI64GtU],
            [opIf, blocktypeVoid],
            [opI32Const],
            encodeSLEB128 1,
            [opLocalSet],
            encodeULEB128 7,
            [opBr],
            encodeULEB128 3,
            [opEnd],
            -- i = i + 1
            [opLocalGet],
            encodeULEB128 2,
            [opI32Const],
            encodeSLEB128 1,
            [opI32Add],
            [opLocalSet],
            encodeULEB128 2,
            -- br $loop
            [opBr],
            encodeULEB128 0,
            [opEnd], -- end loop
            [opEnd], -- end block $loop_break
            [opEnd], -- end block $exit
            -- if ($failed) Left ParseError else Right (wrap_i64 acc)
            [opLocalGet],
            encodeULEB128 7,
            [opIf, blocktypeVoid],
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 6,
            storeTagBytes 6 (ptParseError ptags),
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 5,
            storeTagBytes 5 (ptLeft ptags),
            [opLocalGet],
            encodeULEB128 5,
            [opLocalGet],
            encodeULEB128 6,
            [opI32Store, 0x02, 0x04],
            [opElse],
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 4,
            [opLocalGet],
            encodeULEB128 8,
            [opI32WrapI64],
            [opI32Store, 0x02, 0x00],
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 5,
            storeTagBytes 5 (ptRight ptags),
            [opLocalGet],
            encodeULEB128 5,
            [opLocalGet],
            encodeULEB128 4,
            [opI32Store, 0x02, 0x04],
            [opEnd], -- end if/else (cell in slot 5)
            -- Callee takes ownership; dec the arg before return.
            decArgBin 0,
            [opLocalGet],
            encodeULEB128 5
          ]

-- __box_i32(v: i32) -> i32
-- Allocate a 4-byte cell, store v, return pointer.
-- local $p: i32 (slot 1)
codeBoxI32 :: WasmInfo -> [Word8]
codeBoxI32 _info =
  encodeBody
    (encodeLocals 1)
    $ concat
      [ -- p = __alloc(4)
        [opI32Const],
        encodeSLEB128 4,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 1,
        -- i32.store(p, v)
        [opLocalGet],
        encodeULEB128 1,
        [opLocalGet],
        encodeULEB128 0,
        [opI32Store, 0x02, 0x00], -- align=2 (4-byte), offset=0
        -- return p
        [opLocalGet],
        encodeULEB128 1
      ]

-- __show_i32(p: i32) -> i32
-- Read value from box, render decimal representation in fresh 16-byte buffer
-- (worst case: "-2147483648" = 11 chars + null). Returns a pointer to the
-- first character. Same routine handles Int32 (signed) and UInt8 (always
-- positive 0..255) — i32.lt_s is false for the UInt8 value space.
--
-- Locals: $v(1) $buf(2) $pos(3) $neg(4) $mag(5) $digit(6)
-- (param p is slot 0)
codeShowI32 :: WasmInfo -> [Word8]
codeShowI32 _info =
  encodeBody
    (encodeLocals 7)
    $ concat
      [ -- v = i32.load(p)
        [opLocalGet],
        encodeULEB128 0,
        [opI32Load, 0x02, 0x00],
        [opLocalSet],
        encodeULEB128 1,
        -- buf = __alloc(24) — 8-byte header + 16-byte scratch
        [opI32Const],
        encodeSLEB128 24,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 2,
        -- pos = 23 (rightmost position in the scratch range buf+8..buf+23)
        [opI32Const],
        encodeSLEB128 23,
        [opLocalSet],
        encodeULEB128 3,
        -- if v < 0 (signed) then neg=1, mag=-v else neg=0, mag=v
        [opLocalGet],
        encodeULEB128 1,
        [opI32Const],
        encodeSLEB128 0,
        [opI32LtS],
        [opIf, blocktypeVoid],
        [opI32Const],
        encodeSLEB128 1,
        [opLocalSet],
        encodeULEB128 4,
        [opI32Const],
        encodeSLEB128 0,
        [opLocalGet],
        encodeULEB128 1,
        [opI32Sub],
        [opLocalSet],
        encodeULEB128 5,
        [opElse],
        [opI32Const],
        encodeSLEB128 0,
        [opLocalSet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 1,
        [opLocalSet],
        encodeULEB128 5,
        [opEnd],
        -- if mag == 0 then write '0' at buf+pos; pos -= 1
        -- else loop while mag != 0: digit=mag%10; store '0'+digit at buf+pos; pos-=1; mag/=10
        [opLocalGet],
        encodeULEB128 5,
        [opI32Eqz],
        [opIf, blocktypeVoid],
        -- write '0' at buf+pos
        [opLocalGet],
        encodeULEB128 2,
        [opLocalGet],
        encodeULEB128 3,
        [opI32Add],
        [opI32Const],
        encodeSLEB128 48, -- '0'
        [opI32Store8, 0x00, 0x00],
        -- pos -= 1
        [opLocalGet],
        encodeULEB128 3,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Sub],
        [opLocalSet],
        encodeULEB128 3,
        [opElse],
        -- block $done / loop $loop
        [opBlock, blocktypeVoid],
        [opLoop, blocktypeVoid],
        -- br_if $done (mag == 0)
        [opLocalGet],
        encodeULEB128 5,
        [opI32Eqz],
        [opBrIf],
        encodeULEB128 1,
        -- digit = mag % 10
        [opLocalGet],
        encodeULEB128 5,
        [opI32Const],
        encodeSLEB128 10,
        [opI32RemU],
        [opLocalSet],
        encodeULEB128 6,
        -- store '0' + digit at buf+pos
        [opLocalGet],
        encodeULEB128 2,
        [opLocalGet],
        encodeULEB128 3,
        [opI32Add],
        [opLocalGet],
        encodeULEB128 6,
        [opI32Const],
        encodeSLEB128 48,
        [opI32Add],
        [opI32Store8, 0x00, 0x00],
        -- pos -= 1
        [opLocalGet],
        encodeULEB128 3,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Sub],
        [opLocalSet],
        encodeULEB128 3,
        -- mag /= 10
        [opLocalGet],
        encodeULEB128 5,
        [opI32Const],
        encodeSLEB128 10,
        [opI32DivU],
        [opLocalSet],
        encodeULEB128 5,
        -- br $loop
        [opBr],
        encodeULEB128 0,
        [opEnd], -- end loop
        [opEnd], -- end block $done
        [opEnd], -- end else
        -- if neg then store '-' at buf+pos; pos -= 1
        [opLocalGet],
        encodeULEB128 4,
        [opIf, blocktypeVoid],
        [opLocalGet],
        encodeULEB128 2,
        [opLocalGet],
        encodeULEB128 3,
        [opI32Add],
        [opI32Const],
        encodeSLEB128 45, -- '-'
        [opI32Store8, 0x00, 0x00],
        [opLocalGet],
        encodeULEB128 3,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Sub],
        [opLocalSet],
        encodeULEB128 3,
        [opEnd],
        -- blen = 23 - pos
        [opI32Const],
        encodeSLEB128 23,
        [opLocalGet],
        encodeULEB128 3,
        [opI32Sub],
        [opLocalSet],
        encodeULEB128 7,
        -- __memcpy(buf+8, buf+pos+1, blen)
        [opLocalGet],
        encodeULEB128 2,
        [opI32Const],
        encodeSLEB128 8,
        [opI32Add],
        [opLocalGet],
        encodeULEB128 2,
        [opLocalGet],
        encodeULEB128 3,
        [opI32Add],
        [opI32Const],
        encodeSLEB128 1,
        [opI32Add],
        [opLocalGet],
        encodeULEB128 7,
        [opCall],
        encodeULEB128 idxMemcpy,
        -- write header: byte_count = blen, utf16_count = blen (ASCII)
        [opLocalGet],
        encodeULEB128 2,
        [opLocalGet],
        encodeULEB128 7,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 2,
        [opLocalGet],
        encodeULEB128 7,
        [opI32Store, 0x02, 0x04],
        -- Callee takes ownership; dec the arg before return.
        decArgBin 0,
        -- return buf
        [opLocalGet],
        encodeULEB128 2
      ]

-- __show_u32(p: i32) -> i32
-- Render an unsigned 32-bit value as decimal. Mirrors 'codeShowI32' but
-- skips the negative-sign branch — the input bit pattern is treated as
-- unsigned end-to-end (i32.div_u / i32.rem_u), so values 2^31..2^32-1
-- render correctly without an erroneous '-' prefix.
--
-- Locals: $v(1) $buf(2) $pos(3) $digit(4)
codeShowU32 :: WasmInfo -> [Word8]
codeShowU32 _info =
  encodeBody
    (encodeLocals 5)
    $ concat
      [ -- v = i32.load(p)
        [opLocalGet],
        encodeULEB128 0,
        [opI32Load, 0x02, 0x00],
        [opLocalSet],
        encodeULEB128 1,
        -- buf = __alloc(24) — 8-byte header + 16-byte scratch
        [opI32Const],
        encodeSLEB128 24,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 2,
        -- pos = 23
        [opI32Const],
        encodeSLEB128 23,
        [opLocalSet],
        encodeULEB128 3,
        -- if v == 0 then write '0' at buf+pos; pos -= 1
        -- else loop while v != 0: digit=v%10; store '0'+digit at buf+pos; pos-=1; v/=10
        [opLocalGet],
        encodeULEB128 1,
        [opI32Eqz],
        [opIf, blocktypeVoid],
        [opLocalGet],
        encodeULEB128 2,
        [opLocalGet],
        encodeULEB128 3,
        [opI32Add],
        [opI32Const],
        encodeSLEB128 48,
        [opI32Store8, 0x00, 0x00],
        [opLocalGet],
        encodeULEB128 3,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Sub],
        [opLocalSet],
        encodeULEB128 3,
        [opElse],
        [opBlock, blocktypeVoid],
        [opLoop, blocktypeVoid],
        [opLocalGet],
        encodeULEB128 1,
        [opI32Eqz],
        [opBrIf],
        encodeULEB128 1,
        -- digit = v % 10 (unsigned)
        [opLocalGet],
        encodeULEB128 1,
        [opI32Const],
        encodeSLEB128 10,
        [opI32RemU],
        [opLocalSet],
        encodeULEB128 4,
        -- store '0' + digit at buf+pos
        [opLocalGet],
        encodeULEB128 2,
        [opLocalGet],
        encodeULEB128 3,
        [opI32Add],
        [opLocalGet],
        encodeULEB128 4,
        [opI32Const],
        encodeSLEB128 48,
        [opI32Add],
        [opI32Store8, 0x00, 0x00],
        -- pos -= 1
        [opLocalGet],
        encodeULEB128 3,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Sub],
        [opLocalSet],
        encodeULEB128 3,
        -- v /= 10 (unsigned)
        [opLocalGet],
        encodeULEB128 1,
        [opI32Const],
        encodeSLEB128 10,
        [opI32DivU],
        [opLocalSet],
        encodeULEB128 1,
        [opBr],
        encodeULEB128 0,
        [opEnd], -- end loop
        [opEnd], -- end block
        [opEnd], -- end if/else
        -- blen = 23 - pos
        [opI32Const],
        encodeSLEB128 23,
        [opLocalGet],
        encodeULEB128 3,
        [opI32Sub],
        [opLocalSet],
        encodeULEB128 4,
        -- __memcpy(buf+8, buf+pos+1, blen)
        [opLocalGet],
        encodeULEB128 2,
        [opI32Const],
        encodeSLEB128 8,
        [opI32Add],
        [opLocalGet],
        encodeULEB128 2,
        [opLocalGet],
        encodeULEB128 3,
        [opI32Add],
        [opI32Const],
        encodeSLEB128 1,
        [opI32Add],
        [opLocalGet],
        encodeULEB128 4,
        [opCall],
        encodeULEB128 idxMemcpy,
        -- write header: byte_count = blen, utf16_count = blen
        [opLocalGet],
        encodeULEB128 2,
        [opLocalGet],
        encodeULEB128 4,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 2,
        [opLocalGet],
        encodeULEB128 4,
        [opI32Store, 0x02, 0x04],
        -- Callee takes ownership; dec the arg before return.
        decArgBin 0,
        -- return buf
        [opLocalGet],
        encodeULEB128 2
      ]

-- __lengthUtf8Bytes(s: i32) -> i32
-- Strings are null-terminated UTF-8 byte buffers, so '__strlen' is the
-- answer; box the result in a 4-byte cell. Locals: $box(1).
codeLengthBytesAsUtf8 :: [Word8]
codeLengthBytesAsUtf8 =
  encodeBody
    (encodeLocals 1)
    $ concat
      [ -- box = __alloc(4)
        [opI32Const],
        encodeSLEB128 4,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 1,
        -- store at box: i32.load (s + 0) — byte_count from header
        [opLocalGet],
        encodeULEB128 1,
        [opLocalGet],
        encodeULEB128 0,
        [opI32Load, 0x02, 0x00],
        [opI32Store, 0x02, 0x00],
        -- Callee takes ownership; dec the arg before return.
        decArgBin 0,
        -- return box
        [opLocalGet],
        encodeULEB128 1
      ]

-- __lengthCodePoints(s: i32) -> i32
-- Walks UTF-8 bytes; counts every byte whose top two bits are not 10.
-- Bound is header byte_count (offset 0); payload starts at offset 8.
-- Locals: $i(1), $n(2), $b(3), $box(4), $len(5), $payload(6).
codeLengthCodePoints :: [Word8]
codeLengthCodePoints =
  encodeBody
    (encodeLocals 6)
    $ concat
      [ -- len = i32.load(s)
        [opLocalGet],
        encodeULEB128 0,
        [opI32Load, 0x02, 0x00],
        [opLocalSet],
        encodeULEB128 5,
        -- payload = s + 8
        [opLocalGet],
        encodeULEB128 0,
        [opI32Const],
        encodeSLEB128 8,
        [opI32Add],
        [opLocalSet],
        encodeULEB128 6,
        -- i = 0; n = 0
        [opI32Const],
        encodeSLEB128 0,
        [opLocalSet],
        encodeULEB128 1,
        [opI32Const],
        encodeSLEB128 0,
        [opLocalSet],
        encodeULEB128 2,
        -- block $break
        [opBlock, blocktypeVoid],
        -- loop $loop
        [opLoop, blocktypeVoid],
        -- if i >= len break
        [opLocalGet],
        encodeULEB128 1,
        [opLocalGet],
        encodeULEB128 5,
        [opI32GeU],
        [opBrIf],
        encodeULEB128 1, -- to $break
        -- b = i32.load8_u (payload + i)
        [opLocalGet],
        encodeULEB128 6,
        [opLocalGet],
        encodeULEB128 1,
        [opI32Add],
        [opI32Load8U, 0x00, 0x00],
        [opLocalSet],
        encodeULEB128 3,
        -- if (b & 0xC0) != 0x80: n++
        [opLocalGet],
        encodeULEB128 3,
        [opI32Const],
        encodeSLEB128 0xC0,
        [opI32And],
        [opI32Const],
        encodeSLEB128 0x80,
        [opI32Ne],
        [opIf, blocktypeVoid],
        [opLocalGet],
        encodeULEB128 2,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Add],
        [opLocalSet],
        encodeULEB128 2,
        [opEnd],
        -- i = i + 1
        [opLocalGet],
        encodeULEB128 1,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Add],
        [opLocalSet],
        encodeULEB128 1,
        -- br $loop
        [opBr],
        encodeULEB128 0,
        [opEnd], -- end loop
        [opEnd], -- end block
        -- box = __alloc(4); store n; return box
        [opI32Const],
        encodeSLEB128 4,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 2,
        [opI32Store, 0x02, 0x00],
        -- Callee takes ownership; dec the arg before return.
        decArgBin 0,
        [opLocalGet],
        encodeULEB128 4
      ]

-- __lengthUtf16CodeUnits(s: i32) -> i32
-- Walks UTF-8 bytes; counts 1 for every codepoint start except 4-byte
-- starts (top five bits = 11110), which need a UTF-16 surrogate pair
-- and contribute 2. Continuation bytes are skipped. Locals:

-- O(1): the utf16 count is cached in the second i32 of the header.
codeLengthUtf16CodeUnits :: [Word8]
codeLengthUtf16CodeUnits =
  encodeBody
    (encodeLocals 1)
    $ concat
      [ -- box = __alloc(4); local 1 = $box
        [opI32Const],
        encodeSLEB128 4,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 1,
        -- box stores i32.load (s + 4)
        [opLocalGet],
        encodeULEB128 1,
        [opLocalGet],
        encodeULEB128 0,
        [opI32Load, 0x02, 0x04],
        [opI32Store, 0x02, 0x00],
        -- Callee takes ownership; dec the arg before return.
        decArgBin 0,
        [opLocalGet],
        encodeULEB128 1
      ]

-- __getArgs() -> i32. Zero-arg helper for 'BuiltIn.internalGetArgs',
-- called from 'runIO''s 'IOGetArgs' arm. Reads the full argv via WASI
-- 'args_sizes_get' / 'args_get' and walks it from index argc-1 down to
-- 1 (index 0 is the program name, skipped), validating each element
-- via '__entryArgEither' and consing it onto a prelude 'List String'.
-- All-or-nothing error semantics — the first failing element
-- short-circuits with its 'Left'. On success the list is wrapped in
-- 'Right'. Walked right-to-left so order is preserved at the head; an
-- argv of just [exe] yields 'Right Nil'. Mirrors the WAT 'rtGetArgs'
-- in 'Awsum.Codegen.WASM' byte-for-byte.
--
-- Locals (10, all i32): 0 = argc, 1 = ptrs, 2 = buf, 3 = i,
-- 4 = p (current arg pointer), 5 = l (its byte length),
-- 6 = cell (Either from __entryArgEither), 7 = head (String ptr),
-- 8 = acc (list accumulator), 9 = consC.
codeGetArgs :: PreludeTags -> [Word8]
codeGetArgs ptags =
  encodeBody
    (encodeLocals 10)
    $ concat
      [ -- acc = __alloc_shaped(4, 0); store ptNil
        [opI32Const],
        encodeSLEB128 4,
        [opI32Const],
        encodeSLEB128 0,
        [opCall],
        encodeULEB128 idxAllocShaped,
        [opLocalSet],
        encodeULEB128 8,
        [opLocalGet],
        encodeULEB128 8,
        [opI32Const],
        encodeSLEB128 (fromIntegral (ptNil ptags) :: Int32),
        [opI32Store, 0x02, 0x00],
        -- drop(args_sizes_get(12, 16))
        [opI32Const],
        encodeSLEB128 12,
        [opI32Const],
        encodeSLEB128 16,
        [opCall],
        encodeULEB128 1, -- args_sizes_get (import index 1)
        [opDrop],
        -- argc = i32.load(12)
        [opI32Const],
        encodeSLEB128 0,
        [opI32Load, 0x02, 0x0C],
        [opLocalSet],
        encodeULEB128 0,
        -- if (argc >= 2)
        [opLocalGet],
        encodeULEB128 0,
        [opI32Const],
        encodeSLEB128 2,
        [opI32GeU],
        [opIf, blocktypeVoid],
        -- buf = __alloc(i32.load(16))
        [opI32Const],
        encodeSLEB128 0,
        [opI32Load, 0x02, 0x10],
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 2,
        -- ptrs = __alloc(argc * 4)
        [opLocalGet],
        encodeULEB128 0,
        [opI32Const],
        encodeSLEB128 4,
        [opI32Mul],
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 1,
        -- drop(args_get(ptrs, buf))
        [opLocalGet],
        encodeULEB128 1,
        [opLocalGet],
        encodeULEB128 2,
        [opCall],
        encodeULEB128 2, -- args_get (import index 2)
        [opDrop],
        -- i = argc
        [opLocalGet],
        encodeULEB128 0,
        [opLocalSet],
        encodeULEB128 3,
        -- block $break / loop $loop
        [opBlock, blocktypeVoid],
        [opLoop, blocktypeVoid],
        -- br_if $break (i <= 1)   [break is depth 1 from inside $loop]
        [opLocalGet],
        encodeULEB128 3,
        [opI32Const],
        encodeSLEB128 1,
        [opI32LeU],
        [opBrIf],
        encodeULEB128 1,
        -- i = i - 1
        [opLocalGet],
        encodeULEB128 3,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Sub],
        [opLocalSet],
        encodeULEB128 3,
        -- p = i32.load(ptrs + i*4)
        [opLocalGet],
        encodeULEB128 1,
        [opLocalGet],
        encodeULEB128 3,
        [opI32Const],
        encodeSLEB128 4,
        [opI32Mul],
        [opI32Add],
        [opI32Load, 0x02, 0x00],
        [opLocalSet],
        encodeULEB128 4,
        -- l = 0
        [opI32Const],
        encodeSLEB128 0,
        [opLocalSet],
        encodeULEB128 5,
        -- block $scanbrk / loop $scan: strlen(p)
        [opBlock, blocktypeVoid],
        [opLoop, blocktypeVoid],
        -- br_if $scanbrk (p[l] == 0)   [scanbrk is depth 1 from inside $scan]
        [opLocalGet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 5,
        [opI32Add],
        [opI32Load8U, 0x00, 0x00],
        [opI32Eqz],
        [opBrIf],
        encodeULEB128 1,
        -- l += 1
        [opLocalGet],
        encodeULEB128 5,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Add],
        [opLocalSet],
        encodeULEB128 5,
        [opBr],
        encodeULEB128 0,
        [opEnd], -- end loop $scan
        [opEnd], -- end block $scanbrk
        -- cell = __entryArgEither(p, l)
        [opLocalGet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 5,
        [opCall],
        encodeULEB128 idxEntryArgEither,
        [opLocalSet],
        encodeULEB128 6,
        -- if (load cell == ptLeft) return cell
        [opLocalGet],
        encodeULEB128 6,
        [opI32Load, 0x02, 0x00],
        [opI32Const],
        encodeSLEB128 (fromIntegral (ptLeft ptags) :: Int32),
        [opI32Eq],
        [opIf, blocktypeVoid],
        [opLocalGet],
        encodeULEB128 6,
        [opReturn],
        [opEnd],
        -- head = load offset=4 cell
        [opLocalGet],
        encodeULEB128 6,
        [opI32Load, 0x02, 0x04],
        [opLocalSet],
        encodeULEB128 7,
        -- free the Either box (non-recursive; String transferred to Cons)
        [opLocalGet],
        encodeULEB128 6,
        [opCall],
        encodeULEB128 idxFree,
        -- consC = __alloc_shaped(12, 2); store ptCons; head; acc
        [opI32Const],
        encodeSLEB128 12,
        [opI32Const],
        encodeSLEB128 2,
        [opCall],
        encodeULEB128 idxAllocShaped,
        [opLocalSet],
        encodeULEB128 9,
        [opLocalGet],
        encodeULEB128 9,
        [opI32Const],
        encodeSLEB128 (fromIntegral (ptCons ptags) :: Int32),
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 9,
        [opLocalGet],
        encodeULEB128 7,
        [opI32Store, 0x02, 0x04],
        [opLocalGet],
        encodeULEB128 9,
        [opLocalGet],
        encodeULEB128 8,
        [opI32Store, 0x02, 0x08],
        -- acc = consC
        [opLocalGet],
        encodeULEB128 9,
        [opLocalSet],
        encodeULEB128 8,
        [opBr],
        encodeULEB128 0, -- br $loop
        [opEnd], -- end loop $loop
        [opEnd], -- end block $break
        [opEnd], -- end if (argc >= 2)
        -- cell = __alloc_shaped(8, 1); store ptRight; acc
        [opI32Const],
        encodeSLEB128 8,
        [opI32Const],
        encodeSLEB128 1,
        [opCall],
        encodeULEB128 idxAllocShaped,
        [opLocalSet],
        encodeULEB128 6,
        [opLocalGet],
        encodeULEB128 6,
        [opI32Const],
        encodeSLEB128 (fromIntegral (ptRight ptags) :: Int32),
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 6,
        [opLocalGet],
        encodeULEB128 8,
        [opI32Store, 0x02, 0x04],
        -- return cell (implicit)
        [opLocalGet],
        encodeULEB128 6
      ]

-- __stdinReadAll() -> i32. Zero-arg helper for
-- 'BuiltIn.internalStdinReadAllAsUtf16'. Reads fd 0 via WASI 'fd_read'
-- in chunks into a growing '__alloc'-managed buffer (start 4 KiB,
-- double on full), then writes a 0 sentinel past the data and routes
-- the (buf, len) pair through the length-aware '__entryArgEither'.
--
-- WASM has no realloc; growing means '__alloc' a bigger cell and
-- '__memcpy' the existing bytes over. The old cell leaks for the
-- rest of the program — bounded waste, doubling strategy.
--
-- iovec scratch at address 16/20 (ptr, len), nread_out at 12. These
-- overlap with '__getArgs's args-size scratch but the two helpers
-- never run concurrently (WASM is single-threaded).
--
-- Locals: 0=buf, 1=cap, 2=total, 3=remain, 4=newbuf, 5=newcap, 6=got.
codeStdinReadAll :: [Word8]
codeStdinReadAll =
  encodeBody
    (encodeLocals 7)
    $ concat
      [ -- cap = 4096
        [opI32Const],
        encodeSLEB128 4096,
        [opLocalSet],
        encodeULEB128 1,
        -- buf = __alloc(cap)
        [opLocalGet],
        encodeULEB128 1,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 0,
        -- total = 0
        [opI32Const],
        encodeSLEB128 0,
        [opLocalSet],
        encodeULEB128 2,
        -- block $break_read / loop $read_loop
        [opBlock, blocktypeVoid],
        [opLoop, blocktypeVoid],
        -- remain = cap - total
        [opLocalGet],
        encodeULEB128 1,
        [opLocalGet],
        encodeULEB128 2,
        [opI32Sub],
        [opLocalSet],
        encodeULEB128 3,
        -- if remain < 4096: grow
        [opLocalGet],
        encodeULEB128 3,
        [opI32Const],
        encodeSLEB128 4096,
        [opI32LtU],
        [opIf, blocktypeVoid],
        -- newcap = cap * 2
        [opLocalGet],
        encodeULEB128 1,
        [opI32Const],
        encodeSLEB128 2,
        [opI32Mul],
        [opLocalSet],
        encodeULEB128 5,
        -- newbuf = __alloc(newcap)
        [opLocalGet],
        encodeULEB128 5,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 4,
        -- __memcpy(newbuf, buf, total)
        [opLocalGet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 0,
        [opLocalGet],
        encodeULEB128 2,
        [opCall],
        encodeULEB128 idxMemcpy,
        -- buf = newbuf
        [opLocalGet],
        encodeULEB128 4,
        [opLocalSet],
        encodeULEB128 0,
        -- cap = newcap
        [opLocalGet],
        encodeULEB128 5,
        [opLocalSet],
        encodeULEB128 1,
        -- remain = cap - total
        [opLocalGet],
        encodeULEB128 1,
        [opLocalGet],
        encodeULEB128 2,
        [opI32Sub],
        [opLocalSet],
        encodeULEB128 3,
        [opEnd], -- end grow-if
        -- store at 16: buf + total       (iovec[0].ptr)
        [opI32Const],
        encodeSLEB128 16,
        [opLocalGet],
        encodeULEB128 0,
        [opLocalGet],
        encodeULEB128 2,
        [opI32Add],
        [opI32Store, 0x02, 0x00],
        -- store at 20: remain            (iovec[0].len)
        [opI32Const],
        encodeSLEB128 20,
        [opLocalGet],
        encodeULEB128 3,
        [opI32Store, 0x02, 0x00],
        -- drop(fd_read(0, 16, 1, 12))
        [opI32Const],
        encodeSLEB128 0, -- fd
        [opI32Const],
        encodeSLEB128 16, -- iovs
        [opI32Const],
        encodeSLEB128 1, -- iovs_len
        [opI32Const],
        encodeSLEB128 12, -- nread_out
        [opCall],
        encodeULEB128 3, -- fd_read (import index 3)
        [opDrop],
        -- got = *12
        [opI32Const],
        encodeSLEB128 0,
        [opI32Load, 0x02, 0x0C],
        [opLocalSet],
        encodeULEB128 6,
        -- if got == 0 br $break_read (depth 1)
        [opLocalGet],
        encodeULEB128 6,
        [opI32Eqz],
        [opBrIf],
        encodeULEB128 1,
        -- total += got
        [opLocalGet],
        encodeULEB128 2,
        [opLocalGet],
        encodeULEB128 6,
        [opI32Add],
        [opLocalSet],
        encodeULEB128 2,
        -- br $read_loop (depth 0)
        [opBr],
        encodeULEB128 0,
        [opEnd], -- end loop
        [opEnd], -- end block
        -- buf[total] = 0  (one-past-end safe byte for decoder peek)
        [opLocalGet],
        encodeULEB128 0,
        [opLocalGet],
        encodeULEB128 2,
        [opI32Add],
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store8, 0x00, 0x00],
        -- call __entryArgEither(buf, total)
        [opLocalGet],
        encodeULEB128 0,
        [opLocalGet],
        encodeULEB128 2,
        [opCall],
        encodeULEB128 idxEntryArgEither
      ]

-- __entryArgEither(arg: i32, len: i32) -> i32
-- Length-aware UTF-8 byte scanner running two checks:
--   (1) UTF-16 code unit count vs cap (134217728 = 2^27), short-circuit
--       on overflow.
--   (2) Surrogate-encoded byte triplets ('ED A0..BF 80..BF') — standard
--       UTF-8 (RFC 3629) forbids these, but WTF-8 / CESU-8 / Java
--       modified UTF-8 emit them. Sticky flag, no early exit (cap-check
--       has priority).
-- Returns:
--   * Right(arg-as-string)        on fit + no surrogates
--   * Left StringTooLong          on cap overflow (regardless of surrogates)
--   * Left UnpairedUtf16Surrogate on surrogates with cap respected
-- Mirrors the WAT-text 'rtEntryArgEither' (identical observable behaviour).
-- Cap value and FNV-1a row tags for "StringTooLong" /
-- "UnpairedUtf16Surrogate" must stay in sync with
-- 'maxStringLengthUtf16CodeUnits' in 'stdlib/Prelude.aww'.
--
-- Callers guarantee @arg[len]@ is a readable byte for the
-- surrogate-detection branch's one-past-end peek (NUL terminator
-- for argv, an explicit zero past the read region for stdin).
--
-- Params: arg(0) len(1).
-- Locals: i(2) n(3) b(4) surr(5) inner(6) row(7) cell(8) wrapped(9).

codeEntryArgEither :: WasmInfo -> [Word8]
codeEntryArgEither info =
  let ptags = wiTags info
   in encodeBody
        (encodeLocals 8)
        $ concat
          [ -- i = 0
            [opI32Const],
            encodeSLEB128 0,
            [opLocalSet],
            encodeULEB128 2,
            -- n = 0
            [opI32Const],
            encodeSLEB128 0,
            [opLocalSet],
            encodeULEB128 3,
            -- surr = 0
            [opI32Const],
            encodeSLEB128 0,
            [opLocalSet],
            encodeULEB128 5,
            -- block $break_scan
            [opBlock, blocktypeVoid],
            -- loop $scan_loop
            [opLoop, blocktypeVoid],
            -- Length-aware termination: if (i == len) br $break_scan
            [opLocalGet],
            encodeULEB128 2,
            [opLocalGet],
            encodeULEB128 1,
            [opI32Eq],
            [opBrIf],
            encodeULEB128 1,
            -- b = i32.load8_u(arg + i)
            [opLocalGet],
            encodeULEB128 0,
            [opLocalGet],
            encodeULEB128 2,
            [opI32Add],
            [opI32Load8U, 0x00, 0x00],
            [opLocalSet],
            encodeULEB128 4,
            -- if ((b & 0xC0) != 0x80) — not a continuation byte
            [opLocalGet],
            encodeULEB128 4,
            [opI32Const],
            encodeSLEB128 0xC0,
            [opI32And],
            [opI32Const],
            encodeSLEB128 0x80,
            [opI32Ne],
            [opIf, blocktypeVoid],
            -- if (b == 0xED) check next byte for surrogate range
            [opLocalGet],
            encodeULEB128 4,
            [opI32Const],
            encodeSLEB128 0xED,
            [opI32Eq],
            [opIf, blocktypeVoid],
            -- peek arg[i+1]
            [opLocalGet],
            encodeULEB128 0,
            [opLocalGet],
            encodeULEB128 2,
            [opI32Const],
            encodeSLEB128 1,
            [opI32Add],
            [opI32Add],
            [opI32Load8U, 0x00, 0x00],
            [opI32Const],
            encodeSLEB128 0xE0,
            [opI32And],
            [opI32Const],
            encodeSLEB128 0xA0,
            [opI32Eq],
            [opIf, blocktypeVoid],
            -- surr = 1
            [opI32Const],
            encodeSLEB128 1,
            [opLocalSet],
            encodeULEB128 5,
            [opEnd], -- end surr-set if
            [opEnd], -- end b == 0xED if
            -- if ((b & 0xF8) == 0xF0) n += 2 else n += 1
            [opLocalGet],
            encodeULEB128 4,
            [opI32Const],
            encodeSLEB128 0xF8,
            [opI32And],
            [opI32Const],
            encodeSLEB128 0xF0,
            [opI32Eq],
            [opIf, blocktypeVoid],
            -- then: n += 2
            [opLocalGet],
            encodeULEB128 3,
            [opI32Const],
            encodeSLEB128 2,
            [opI32Add],
            [opLocalSet],
            encodeULEB128 3,
            [opElse],
            -- else: n += 1
            [opLocalGet],
            encodeULEB128 3,
            [opI32Const],
            encodeSLEB128 1,
            [opI32Add],
            [opLocalSet],
            encodeULEB128 3,
            [opEnd], -- end inner if (n increment)
            -- short-circuit: if (n >u 134217728) br $break_scan
            [opLocalGet],
            encodeULEB128 3,
            [opI32Const],
            encodeSLEB128 134217728,
            [opI32GtU],
            [opBrIf],
            encodeULEB128 2,
            [opEnd], -- end outer if (non-continuation)
            -- i = i + 1
            [opLocalGet],
            encodeULEB128 2,
            [opI32Const],
            encodeSLEB128 1,
            [opI32Add],
            [opLocalSet],
            encodeULEB128 2,
            [opBr],
            encodeULEB128 0,
            [opEnd], -- end loop
            [opEnd], -- end block
            -- if (n >u 134217728) → Left StringTooLong (cap-check has priority)
            [opLocalGet],
            encodeULEB128 3,
            [opI32Const],
            encodeSLEB128 134217728,
            [opI32GtU],
            [opIf, blocktypeI32],
            -- inner = __alloc(4); store inner StringTooLong tag
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 6,
            storeTagBytes 6 (ptStringTooLong ptags),
            -- row = __alloc_shaped(8, 1); fill row[0]=tag, row[4]=inner
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 7,
            [opLocalGet],
            encodeULEB128 7,
            [opI32Const],
            encodeSLEB128 (fromIntegral stringTooLongTagWord),
            [opI32Store, 0x02, 0x00],
            [opLocalGet],
            encodeULEB128 7,
            [opLocalGet],
            encodeULEB128 6,
            [opI32Store, 0x02, 0x04],
            -- cell = __alloc_shaped(8, 1); fill cell[0]=LeftTag, cell[4]=row
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 8,
            storeTagBytes 8 (ptLeft ptags),
            [opLocalGet],
            encodeULEB128 8,
            [opLocalGet],
            encodeULEB128 7,
            [opI32Store, 0x02, 0x04],
            [opLocalGet],
            encodeULEB128 8,
            [opElse],
            -- else: nested if (surr) → UnpairedUtf16Surrogate else Right
            [opLocalGet],
            encodeULEB128 5,
            [opIf, blocktypeI32],
            -- then: build Left(UnpairedUtf16Surrogate row-wrapped)
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 6,
            storeTagBytes 6 (ptUnpairedUtf16Surrogate ptags),
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 7,
            [opLocalGet],
            encodeULEB128 7,
            [opI32Const],
            encodeSLEB128 (fromIntegral unpairedSurrogateTagWord),
            [opI32Store, 0x02, 0x00],
            [opLocalGet],
            encodeULEB128 7,
            [opLocalGet],
            encodeULEB128 6,
            [opI32Store, 0x02, 0x04],
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 8,
            storeTagBytes 8 (ptLeft ptags),
            [opLocalGet],
            encodeULEB128 8,
            [opLocalGet],
            encodeULEB128 7,
            [opI32Store, 0x02, 0x04],
            [opLocalGet],
            encodeULEB128 8,
            [opElse],
            -- else: build Right(wrapped) where wrapped is a length-prefixed
            -- copy of arg (i bytes, n utf16 units). On the normal exit
            -- path i == len, so we size the result by i.
            -- wrapped = __alloc(i + 8)
            [opLocalGet],
            encodeULEB128 2,
            [opI32Const],
            encodeSLEB128 8,
            [opI32Add],
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 9,
            -- header.byte_count = i
            [opLocalGet],
            encodeULEB128 9,
            [opLocalGet],
            encodeULEB128 2,
            [opI32Store, 0x02, 0x00],
            -- header.utf16_count = n
            [opLocalGet],
            encodeULEB128 9,
            [opLocalGet],
            encodeULEB128 3,
            [opI32Store, 0x02, 0x04],
            -- memcpy(wrapped+8, arg, i)
            [opLocalGet],
            encodeULEB128 9,
            [opI32Const],
            encodeSLEB128 8,
            [opI32Add],
            [opLocalGet],
            encodeULEB128 0,
            [opLocalGet],
            encodeULEB128 2,
            [opCall],
            encodeULEB128 idxMemcpy,
            -- cell = __alloc_shaped(8, 1); fill cell[0]=RightTag, cell[4]=wrapped
            [opI32Const],
            encodeSLEB128 8,
            [opI32Const],
            encodeSLEB128 1,
            [opCall],
            encodeULEB128 idxAllocShaped,
            [opLocalSet],
            encodeULEB128 8,
            storeTagBytes 8 (ptRight ptags),
            [opLocalGet],
            encodeULEB128 8,
            [opLocalGet],
            encodeULEB128 9,
            [opI32Store, 0x02, 0x04],
            [opLocalGet],
            encodeULEB128 8,
            [opEnd], -- end nested if (surr / Right)
            [opEnd] -- end outer if (cap)
          ]
  where
    stringTooLongTagWord :: Word32
    stringTooLongTagWord = rowTag (TyCon noSpan "StringTooLong")
    unpairedSurrogateTagWord :: Word32
    unpairedSurrogateTagWord = rowTag (TyCon noSpan "UnpairedUtf16Surrogate")

-- ════════════════════════════════════════════════════════════════════════════
-- User declaration code
-- ════════════════════════════════════════════════════════════════════════════

-- | Maximum CCon nesting depth (number of $__con_N locals needed).
exprMaxConDepth :: CExpr -> Int
exprMaxConDepth = \case
  CCon _ fields -> 1 + foldl' max 0 (map exprMaxConDepth fields)
  CCase s alts -> max (exprMaxConDepth s) (foldl' max 0 [exprMaxConDepth b | (_, _, b) <- alts])
  CRow _ v -> 1 + exprMaxConDepth v
  CRowCase s alts -> max (exprMaxConDepth s) (foldl' max 0 [exprMaxConDepth b | (_, _, b) <- alts])
  CCall f xs -> foldl' max (exprMaxConDepth f) (map exprMaxConDepth xs)
  CLoop b -> exprMaxConDepth b
  CContinue xs -> foldl' max 0 (map exprMaxConDepth xs)
  CDrop _ _ b -> exprMaxConDepth b
  _ -> 0

exprHasCCase :: CExpr -> Bool
exprHasCCase = \case
  CCase {} -> True
  CRowCase {} -> True
  CCall f xs -> exprHasCCase f || any exprHasCCase xs
  CLoop b -> exprHasCCase b
  CContinue xs -> any exprHasCCase xs
  CDrop _ _ b -> exprHasCCase b
  _ -> False

-- | Worst-case concurrently-live case-arm binding count. Outer-arm
-- bindings remain live inside inner-case arm bodies, so nested 'CCase's
-- must get fresh slots on top of their ancestors — take the per-arm
-- sum, not the max. See 'bindArmVars' for the matching slot-base bump.
exprMaxBoundVars :: CExpr -> Int
exprMaxBoundVars = \case
  CCase _ alts -> foldl' max 0 [length vs + exprMaxBoundVars b | (_, vs, b) <- alts]
  CRowCase _ alts -> foldl' max 0 [1 + exprMaxBoundVars b | (_, _, b) <- alts]
  CRow _ v -> exprMaxBoundVars v
  CCall f xs -> foldl' max 0 (exprMaxBoundVars f : map exprMaxBoundVars xs)
  CCon _ fs -> foldl' max 0 (map exprMaxBoundVars fs)
  CLoop b -> exprMaxBoundVars b
  CContinue xs -> foldl' max 0 (map exprMaxBoundVars xs)
  CDrop _ _ b -> exprMaxBoundVars b
  _ -> 0

-- | Max stack depth of fresh case-scrutinees concurrently
-- alive on any execution path. Each 'CCase'/'CRowCase' whose scrut
-- isn't a 'CVar' (borrow) pushes one onto the stash stack and pops
-- it at the arm terminator; nested fresh-scrut cases require
-- distinct slots so the WASM binary can dec each at its own arm
-- terminator without losing the outer's pointer.
exprMaxFreshScrutDepth :: CExpr -> Int
exprMaxFreshScrutDepth = \case
  CCase scrut alts ->
    let scrutFresh = isNothing (sourceCVarBin scrut)
        scrutD = exprMaxFreshScrutDepth scrut
        armsD = foldl' max 0 [exprMaxFreshScrutDepth b | (_, _, b) <- alts]
     in max scrutD ((if scrutFresh then 1 else 0) + armsD)
  CRowCase scrut alts ->
    let scrutFresh = isNothing (sourceCVarBin scrut)
        scrutD = exprMaxFreshScrutDepth scrut
        armsD = foldl' max 0 [exprMaxFreshScrutDepth b | (_, _, b) <- alts]
     in max scrutD ((if scrutFresh then 1 else 0) + armsD)
  CRow _ v -> exprMaxFreshScrutDepth v
  CCall f xs -> foldl' max 0 (exprMaxFreshScrutDepth f : map exprMaxFreshScrutDepth xs)
  CCon _ fs -> foldl' max 0 (map exprMaxFreshScrutDepth fs)
  CLoop b -> exprMaxFreshScrutDepth b
  CContinue xs -> foldl' max 0 (map exprMaxFreshScrutDepth xs)
  CDrop _ _ b -> exprMaxFreshScrutDepth b
  CReuse _ _ fs -> foldl' max 0 (map exprMaxFreshScrutDepth fs)
  _ -> 0

codeUserDecl :: WasmInfo -> Map FuncType Word32 -> CDecl -> [Word8]
codeUserDecl info typeMap = \case
  -- TCO-wrapped body. WASM params are already mutable locals, so we only
  -- need 'nParams' extra slots to buffer 'CContinue' arguments (so a new
  -- value computed from the old parameter doesn't see a half-updated
  -- slot). The whole body runs inside @(loop $tco_top (result i32))@,
  -- and 'CContinue' becomes @br@ targeting this loop at the current depth.
  CFunDef _nm args (CLoop body) ->
    let nParams = fromIntegral (length args) :: Word32
        paramMap = Map.fromList (zip args [0 :: Word32 ..])
        conDepthNeeded = exprMaxConDepth body
        needsScrut = exprHasCCase body
        conBaseSlot = nParams
        nextAfterCon = conBaseSlot + fromIntegral conDepthNeeded
        scrutSlot = nextAfterCon
        nextAfterScrut = if needsScrut then scrutSlot + 1 else scrutSlot
        boundBase = nextAfterScrut
        maxBV = exprMaxBoundVars body
        nextAfterBound = boundBase + fromIntegral maxBV
        tcoTempBase = nextAfterBound
        afterTco = tcoTempBase + nParams
        dropTmpSlot = afterTco
        incRefTempSlot = dropTmpSlot + 1
        freshScrutBase = incRefTempSlot + 1
        freshScrutNeeded = fromIntegral (exprMaxFreshScrutDepth body) :: Word32
        totalSlots = freshScrutBase + freshScrutNeeded
        nExtraLocals = fromIntegral (totalSlots - nParams) :: Int
        ctx =
          ExprCtx
            { ecParams = paramMap,
              ecLocals = Map.empty,
              ecValDefs = info.wiValDefs,
              ecFunDefs = info.wiFunDefs,
              ecArities = info.wiArities,
              ecStringPool = info.wiStringPool,
              ecTableMap = info.wiTableMap,
              ecFuncIdx = info.wiFuncIdx,
              ecTypeMap = typeMap,
              ecIndirectArities = info.wiIndirectArities,
              ecConBaseSlot = conBaseSlot,
              ecConDepth = 0,
              ecScrutSlot = scrutSlot,
              ecBoundBase = boundBase,
              ecDropTmpSlot = dropTmpSlot,
              ecIncRefTempSlot = incRefTempSlot,
              ecFreshScrutBase = freshScrutBase,
              ecArmPatternByScrut = Map.empty
            }
        bodyBytes = emitTailBin tcoTempBase args 0 ctx body
     in encodeBody
          (encodeLocals nExtraLocals)
          ([opLoop, blocktypeI32] <> bodyBytes <> [opEnd])
  CFunDef _nm args body ->
    let nParams = fromIntegral (length args) :: Word32
        paramMap = Map.fromList (zip args [0 :: Word32 ..])
        conDepthNeeded = exprMaxConDepth body
        needsScrut = exprHasCCase body
        conBaseSlot = nParams
        nextAfterCon = conBaseSlot + fromIntegral conDepthNeeded
        scrutSlot = nextAfterCon
        nextAfterScrut = if needsScrut then scrutSlot + 1 else scrutSlot
        boundBase = nextAfterScrut
        maxBV = exprMaxBoundVars body
        afterBound = boundBase + fromIntegral maxBV
        dropTmpSlot = afterBound
        incRefTempSlot = dropTmpSlot + 1
        freshScrutBase = incRefTempSlot + 1
        freshScrutNeeded = fromIntegral (exprMaxFreshScrutDepth body) :: Word32
        totalSlots = freshScrutBase + freshScrutNeeded
        nExtraLocals = fromIntegral (totalSlots - nParams) :: Int
        ctx =
          ExprCtx
            { ecParams = paramMap,
              ecLocals = Map.empty,
              ecValDefs = info.wiValDefs,
              ecFunDefs = info.wiFunDefs,
              ecArities = info.wiArities,
              ecStringPool = info.wiStringPool,
              ecTableMap = info.wiTableMap,
              ecFuncIdx = info.wiFuncIdx,
              ecTypeMap = typeMap,
              ecIndirectArities = info.wiIndirectArities,
              ecConBaseSlot = conBaseSlot,
              ecConDepth = 0,
              ecScrutSlot = scrutSlot,
              ecBoundBase = boundBase,
              ecDropTmpSlot = dropTmpSlot,
              ecIncRefTempSlot = incRefTempSlot,
              ecFreshScrutBase = freshScrutBase,
              ecArmPatternByScrut = Map.empty
            }
     in encodeBody (encodeLocals nExtraLocals) (emitNonLoopBodyBin ctx args body)
  CValDef _nm rhs ->
    let conDepthNeeded = exprMaxConDepth rhs
        needsScrut = exprHasCCase rhs
        conBaseSlot = 0 :: Word32
        nextAfterCon = conBaseSlot + fromIntegral conDepthNeeded
        scrutSlot = nextAfterCon
        nextAfterScrut = if needsScrut then scrutSlot + 1 else scrutSlot
        boundBase = nextAfterScrut
        maxBV = exprMaxBoundVars rhs
        afterBound = boundBase + fromIntegral maxBV
        dropTmpSlot = afterBound
        incRefTempSlot = dropTmpSlot + 1
        freshScrutBase = incRefTempSlot + 1
        freshScrutNeeded = fromIntegral (exprMaxFreshScrutDepth rhs) :: Word32
        totalSlots = freshScrutBase + freshScrutNeeded
        nExtraLocals = fromIntegral totalSlots :: Int
        ctx =
          ExprCtx
            { ecParams = Map.empty,
              ecLocals = Map.empty,
              ecValDefs = info.wiValDefs,
              ecFunDefs = info.wiFunDefs,
              ecArities = info.wiArities,
              ecStringPool = info.wiStringPool,
              ecTableMap = info.wiTableMap,
              ecFuncIdx = info.wiFuncIdx,
              ecTypeMap = typeMap,
              ecIndirectArities = info.wiIndirectArities,
              ecConBaseSlot = conBaseSlot,
              ecConDepth = 0,
              ecScrutSlot = scrutSlot,
              ecBoundBase = boundBase,
              ecDropTmpSlot = dropTmpSlot,
              ecIncRefTempSlot = incRefTempSlot,
              ecFreshScrutBase = freshScrutBase,
              ecArmPatternByScrut = Map.empty
            }
     in encodeBody (encodeLocals nExtraLocals) (emitExpr ctx rhs)

-- _start: builds the IO tree via v_main and hands it to v_runIO,
-- dropping the Unit result. 'main' takes no arguments; user code reads
-- argv through 'IO.Args.getArgs' inside the IO chain (lowers to an
-- 'IOGetArgs' constructor whose runIO arm calls '__getArgs').
codeStart :: WasmInfo -> [Word8]
codeStart info =
  let mainIdx = fromMaybe 0 (Map.lookup "main" info.wiFuncIdx)
      runIOIdx = fromMaybe (error "no v_runIO") (Map.lookup "runIO" info.wiFuncIdx)
   in encodeBody
        (encodeLocals 0)
        $ concat
          [ -- v_main is a zero-arg value (CValDef) building the IO tree;
            -- 'runIO' walks it for effects and returns Unit (discarded).
            -- User code reads argv through 'IO.Args.getArgs' inside
            -- the chain; that lowers to an 'IOGetArgs' constructor
            -- whose runIO arm calls '__getArgs' (re-reads WASI on
            -- each call).
            [opCall],
            encodeULEB128 mainIdx,
            [opCall],
            encodeULEB128 runIOIdx,
            [opDrop]
          ]

-- ════════════════════════════════════════════════════════════════════════════
-- Expression code generation
-- ════════════════════════════════════════════════════════════════════════════

data ExprCtx = ExprCtx
  { ecParams :: Map Text Word32,
    ecLocals :: Map Text Word32, -- case-bound variable → local slot
    ecValDefs :: Set Text,
    ecFunDefs :: Set Text,
    ecArities :: Map Text Int,
    ecStringPool :: Map Text Int,
    ecTableMap :: Map Text Int,
    ecFuncIdx :: Map Text Word32,
    ecTypeMap :: Map FuncType Word32,
    ecIndirectArities :: Set Int,
    ecConBaseSlot :: Word32, -- first local slot for $__con_N
    ecConDepth :: Int, -- current CCon nesting depth
    ecScrutSlot :: Word32, -- local slot for $__scrut
    ecBoundBase :: Word32, -- first local slot for case-bound variables
    ecDropTmpSlot :: Word32, -- Local slot for $__drop_tmp
    ecIncRefTempSlot :: Word32, -- Scratch slot for inc-on-CVar tees
    ecFreshScrutBase :: Word32, -- First slot of the fresh-scrut stash

    -- | Linear-scrutinee elision: for each in-scope 'CCase' /
    -- 'CRowCase' whose scrutinee is a 'CVar n', records the arm's
    -- pattern variables. 'CReuse n t fs' inside the arm body
    -- checks @ecArmPatternByScrut[n]@ to detect self-move slots
    -- (@fs[i] == CVar vs[i]@) and skip their dec-old + inc-new
    -- + store entirely — the slot's pointer is already what we
    -- wanted.
    ecArmPatternByScrut :: Map Text [Text]
  }

emitExpr :: ExprCtx -> CExpr -> [Word8]
emitExpr ctx = \case
  CString s ->
    let offset = fromMaybe (error $ "string not in pool: " <> show s) (Map.lookup s ctx.ecStringPool)
     in [opI32Const] <> encodeSLEB128 (fromIntegral offset)
  CVar n
    | Just slot <- Map.lookup n ctx.ecLocals ->
        [opLocalGet] <> encodeULEB128 slot
    | Just slot <- Map.lookup n ctx.ecParams ->
        [opLocalGet] <> encodeULEB128 slot
    | n `Set.member` ctx.ecValDefs ->
        let fIdx = fromMaybe 0 (Map.lookup n ctx.ecFuncIdx)
         in [opCall] <> encodeULEB128 fIdx
    | n `Set.member` ctx.ecFunDefs ->
        let tblIdx = fromMaybe 0 (Map.lookup n ctx.ecTableMap)
         in [opI32Const] <> encodeSLEB128 (fromIntegral tblIdx)
    | otherwise ->
        [opI32Const] <> encodeSLEB128 0
  CBuiltIn _ ->
    [opI32Const] <> encodeSLEB128 0 -- invariant: not a standalone term; dispatched from CCall
  CIntLit n _ ->
    let n32 = fromInteger n :: Int32
     in [opI32Const]
          <> encodeSLEB128 n32
          <> [opCall]
          <> encodeULEB128 idxBoxI32
  CCon tag fields ->
    let nSlots = 1 + length fields
        nFields = length fields
        conSlot = ctx.ecConBaseSlot + fromIntegral ctx.ecConDepth
        nestedCtx = ctx {ecConDepth = ctx.ecConDepth + 1}
        -- Allocate (nSlots * 4) bytes with shape inline
        -- via '$__alloc_shaped(size, shape)'.
        allocCode =
          [opI32Const]
            <> encodeSLEB128 (fromIntegral (nSlots * 4))
            <> [opI32Const]
            <> encodeSLEB128 (fromIntegral nFields)
            <> [opCall]
            <> encodeULEB128 idxAllocShaped
            <> [opLocalSet]
            <> encodeULEB128 conSlot
        -- store tag at offset 0
        tagCode =
          [opLocalGet]
            <> encodeULEB128 conSlot
            <> [opI32Const]
            <> encodeSLEB128 (fromIntegral tag)
            <> [opI32Store]
            <> encodeULEB128 2
            <> encodeULEB128 0
        -- store each field at offset (i+1)*4 then inc-on-CVar
        storeField (fld, i) =
          [opLocalGet]
            <> encodeULEB128 conSlot
            <> emitExpr nestedCtx fld
            <> [opI32Store]
            <> encodeULEB128 2
            <> encodeULEB128 (fromIntegral ((i + 1) * 4 :: Int))
            <> incStoredFieldBin nestedCtx conSlot (i + 1) fld
        fieldCode = concatMap storeField (zip fields [0 :: Int ..])
        -- return pointer
        retCode = [opLocalGet] <> encodeULEB128 conSlot
     in allocCode <> tagCode <> fieldCode <> retCode
  CCase scrut alts ->
    let sorted = sortWith (\(t, _, _) -> t) alts
     in emitCaseChain ctx scrut sorted
  -- Row injection / dispatch: same wire layout as one-field 'CCon' /
  -- 'CCase', so delegate.
  CRow tag v -> emitExpr ctx (CCon (fromIntegral tag) [v])
  CRowCase scrut alts ->
    emitExpr ctx (CCase scrut [(fromIntegral t, [v], b) | (t, v, b) <- alts])
  CCall f xs ->
    case f of
      CBuiltIn "internalStdoutPrint"
        | [x] <- xs ->
            emitArgWithIncBin ctx x
              <> [opCall]
              <> encodeULEB128 idxPrint
      -- 'BuiltIn.internalGetArgs' — call '__getArgs', which re-reads
      -- argv via WASI 'args_get' and routes the result through
      -- '__entryArgEither'.
      CBuiltIn "internalGetArgs"
        | [] <- xs ->
            [opCall] <> encodeULEB128 idxGetArgs
      -- 'BuiltIn.internalStdinReadAllAsUtf16' — call '__stdinReadAll',
      -- which consumes fd 0 to EOF via WASI 'fd_read' and routes the
      -- bytes through '__entryArgEither'.
      CBuiltIn "internalStdinReadAllAsUtf16"
        | [] <- xs ->
            [opCall] <> encodeULEB128 idxStdinReadAll
      CBuiltIn name
        | name == "showInt32" || name == "showUInt8",
          [x] <- xs ->
            emitArgWithIncBin ctx x
              <> [opCall]
              <> encodeULEB128 idxShowI32
      CBuiltIn "showUInt32"
        | [x] <- xs ->
            emitArgWithIncBin ctx x
              <> [opCall]
              <> encodeULEB128 idxShowU32
      CBuiltIn "predInt32"
        | [x] <- xs ->
            emitArgWithIncBin ctx x
              <> [opCall]
              <> encodeULEB128 idxPredI32
      CBuiltIn "predUInt8"
        | [x] <- xs ->
            emitArgWithIncBin ctx x
              <> [opCall]
              <> encodeULEB128 idxPredU8
      CBuiltIn "predUInt32"
        | [x] <- xs ->
            emitArgWithIncBin ctx x
              <> [opCall]
              <> encodeULEB128 idxPredU32
      CBuiltIn "succInt32"
        | [x] <- xs ->
            emitArgWithIncBin ctx x
              <> [opCall]
              <> encodeULEB128 idxSuccI32
      CBuiltIn "succUInt8"
        | [x] <- xs ->
            emitArgWithIncBin ctx x
              <> [opCall]
              <> encodeULEB128 idxSuccU8
      CBuiltIn "succUInt32"
        | [x] <- xs ->
            emitArgWithIncBin ctx x
              <> [opCall]
              <> encodeULEB128 idxSuccU32
      CBuiltIn name
        | name == "eqInt32" || name == "eqUInt8" || name == "eqUInt32",
          [a, b] <- xs ->
            emitArgWithIncBin ctx a
              <> emitArgWithIncBin ctx b
              <> [opCall]
              <> encodeULEB128 idxEqI32
      CBuiltIn "eqString"
        | [a, b] <- xs ->
            emitArgWithIncBin ctx a
              <> emitArgWithIncBin ctx b
              <> [opCall]
              <> encodeULEB128 idxEqString
      CBuiltIn name
        | name == "addInt32" || name == "addUInt8" || name == "addUInt32" || name == "subInt32" || name == "subUInt8" || name == "subUInt32" || name == "mulUInt8" || name == "mulUInt32" || name == "mulInt32",
          [a, b] <- xs ->
            let idx = case name of
                  "addInt32" -> idxAddI32
                  "addUInt8" -> idxAddU8
                  "addUInt32" -> idxAddU32
                  "subInt32" -> idxSubI32
                  "subUInt8" -> idxSubU8
                  "subUInt32" -> idxSubU32
                  "mulInt32" -> idxMulI32
                  "mulUInt32" -> idxMulU32
                  _ -> idxMulU8
             in emitArgWithIncBin ctx a
                  <> emitArgWithIncBin ctx b
                  <> [opCall]
                  <> encodeULEB128 idx
      CBuiltIn "negInt32"
        | [x] <- xs ->
            emitArgWithIncBin ctx x
              <> [opCall]
              <> encodeULEB128 idxNegI32
      CBuiltIn "splitOnFirst"
        | [a, b] <- xs ->
            emitArgWithIncBin ctx a
              <> emitArgWithIncBin ctx b
              <> [opCall]
              <> encodeULEB128 idxSplitOnFirst
      CBuiltIn name
        | name == "parseInt32" || name == "parseUInt8" || name == "parseUInt32",
          [x] <- xs ->
            let idx = case name of
                  "parseInt32" -> idxParseI32
                  "parseUInt32" -> idxParseU32
                  _ -> idxParseU8
             in emitArgWithIncBin ctx x
                  <> [opCall]
                  <> encodeULEB128 idx
      CBuiltIn name
        | name == "lengthCodePoints" || name == "lengthUtf16CodeUnits" || name == "lengthUtf8Bytes",
          [x] <- xs ->
            let idx = case name of
                  "lengthCodePoints" -> idxLengthCodePoints
                  "lengthUtf16CodeUnits" -> idxLengthUtf16CodeUnits
                  _ -> idxLengthBytesAsUtf8
             in emitArgWithIncBin ctx x
                  <> [opCall]
                  <> encodeULEB128 idx
      CBuiltIn "concatString"
        | [a, b] <- xs ->
            emitArgWithIncBin ctx a
              <> emitArgWithIncBin ctx b
              <> [opCall]
              <> encodeULEB128 idxConcat
      CBuiltIn n ->
        error ("WASM codegen: unknown builtin '" <> n <> "' reached CCall (typecheck should have rejected it)")
      CVar n
        | n `Set.member` ctx.ecFunDefs ->
            -- User CCall — caller-side inc on each CVar
            -- ptr-arg (borrow that needs its own ref for the
            -- callee's param slot). Builtins above bypass this:
            -- they only READ args, never store them.
            let fIdx = fromMaybe 0 (Map.lookup n ctx.ecFuncIdx)
             in concatMap (emitArgWithIncBin ctx) xs
                  <> [opCall]
                  <> encodeULEB128 fIdx
      _ ->
        -- Indirect user CCall (HOF dispatched through $applyN
        -- after Cps/LowerClosures). Same caller-side inc rule.
        let arity = length xs
            typeIdx = lookupType (FuncType arity True) ctx.ecTypeMap
         in concatMap (emitArgWithIncBin ctx) xs
              <> emitExpr ctx f
              <> [opCallIndirect]
              <> encodeULEB128 typeIdx
              <> encodeULEB128 0 -- table index 0
  CLoop _ -> error "WASM Assemble: CLoop in non-tail position (pipeline bug — should only appear at function-body-tail)"
  CContinue _ -> error "WASM Assemble: CContinue in non-tail position (pipeline bug — should only appear inside a CLoop)"
  -- Evaluate body, stash its value in $__drop_tmp,
  -- call $__free_recursive on the binder, then reload the captured
  -- result. If the body's tail itself is @CVar n@ (we're returning
  -- the same binder we're about to dec), inc the result first so
  -- the dec balances and the returned cell stays alive — same
  -- move-semantics rule the LLVM CDrop emit uses.
  CDrop _ n body ->
    let bodyBytes = emitExpr ctx body
        slot = lookupBinderSlot ctx n
        moveInc = case sourceCVarBin body of
          Just m
            | m == n ->
                [opLocalGet]
                  <> encodeULEB128 ctx.ecDropTmpSlot
                  <> [opCall]
                  <> encodeULEB128 idxIncRef
          _ -> []
     in [opBlock, blocktypeI32]
          <> bodyBytes
          <> [opLocalSet]
          <> encodeULEB128 ctx.ecDropTmpSlot
          <> moveInc
          <> [opLocalGet]
          <> encodeULEB128 slot
          <> [opCall]
          <> encodeULEB128 idxFreeRecursive
          <> [opLocalGet]
          <> encodeULEB128 ctx.ecDropTmpSlot
          <> [opEnd]
  -- Cell reuse. In-place mutation of the user-pointer
  -- at @n@: write tag at offset 0, fields at offsets 4, 8, …
  -- No '__alloc' (skip bin pop), no '__free' (skip bin push).
  -- The flag header at @n - 4@ stays untouched so a later 'CDrop'
  -- correctly returns the cell to the per-size bin freelist.
  --
  -- Invariant from 'Awsum.Reuse.rewriteFirstCCon': @length fields@
  -- equals the matched arm's pattern arity, so the cell has at
  -- least @1 + length fields@ slots — every store stays in bounds.
  CReuse n tag fields ->
    let nSlot = lookupBinderSlot ctx n
        nFields = length fields
        -- Self-move elision: when @fields[i] == CVar v@
        -- where @v@ is the arm-pattern binder at the same slot
        -- index, the slot already holds the matching pointer —
        -- dec-old + store + inc-new cancel. Lookup goes through
        -- 'ecArmPatternByScrut[n]'.
        armVars = Map.findWithDefault [] n ctx.ecArmPatternByScrut
        nthMaybe :: Int -> [a] -> Maybe a
        nthMaybe i xs = listToMaybe (drop i xs)
        isSelfMoveAt :: Int -> Bool
        isSelfMoveAt slotIdx =
          case (nthMaybe (slotIdx - 1) fields, nthMaybe (slotIdx - 1) armVars) of
            (Just (CVar v), Just w) -> v == w
            _ -> False
        -- Dec each old slot value before overwrite (the
        -- cell's existing ref-via-slot dies). Self-move slots
        -- skip dec entirely (slot value is preserved).
        decOldSlot i
          | isSelfMoveAt (i + 1) = []
          | otherwise =
              [opLocalGet]
                <> encodeULEB128 nSlot
                <> [opI32Load]
                <> encodeULEB128 2
                <> encodeULEB128 (fromIntegral ((i + 1) * 4 :: Int))
                <> [opCall]
                <> encodeULEB128 idxFreeRecursive
        decOldCode = concatMap decOldSlot [0 .. nFields - 1]
        -- store tag at offset 0
        tagCode =
          [opLocalGet]
            <> encodeULEB128 nSlot
            <> [opI32Const]
            <> encodeSLEB128 (fromIntegral tag)
            <> [opI32Store]
            <> encodeULEB128 2
            <> encodeULEB128 0
        -- Store each field at offset (i+1)*4 with the
        -- inc-on-CVar discipline (same rule as CCon — the new
        -- slot takes its own reference iff source is a heap
        -- borrow). Self-move slots skip store + inc entirely.
        storeField (fld, i)
          | isSelfMoveAt (i + 1) = []
          | otherwise =
              [opLocalGet]
                <> encodeULEB128 nSlot
                <> emitExpr ctx fld
                <> [opI32Store]
                <> encodeULEB128 2
                <> encodeULEB128 (fromIntegral ((i + 1) * 4 :: Int))
                <> incStoredFieldBin ctx nSlot (i + 1) fld
        fieldCode = concatMap storeField (zip fields [0 :: Int ..])
        -- return pointer
        retCode = [opLocalGet] <> encodeULEB128 nSlot
     in decOldCode <> tagCode <> fieldCode <> retCode

-- | Resolve a parameter or case-arm binder name to its WASM local slot.
-- 'CDrop' only ever drops names introduced as function
-- parameters ('ecParams') or case/row-case binders ('ecLocals'); a
-- lookup miss is a pipeline bug.
lookupBinderSlot :: ExprCtx -> Text -> Word32
lookupBinderSlot ctx n
  | Just slot <- Map.lookup n ctx.ecLocals = slot
  | Just slot <- Map.lookup n ctx.ecParams = slot
  | otherwise = error $ "WASM Assemble: CDrop on unknown binder: " <> show n

-- | WASM-binary mirror of LLVM's 'sourceCVar' — return the
-- binder name if the expression's tail is a 'CVar' (possibly under
-- 'CDrop' wrappers). Used to detect borrow positions that need a
-- caller-side @__inc_ref@.
sourceCVarBin :: CExpr -> Maybe Text
sourceCVarBin = \case
  CVar n -> Just n
  CDrop _ _ body -> sourceCVarBin body
  _ -> Nothing

-- | Does the expression's tail produce a /heap-allocated
-- borrow/ — a 'CVar' that resolves to a param or case-pattern
-- binder, not a fn-table reference or a 'CValDef' getter call.
-- Function references on WASM are i32 table indices (small
-- integers), and 'CValDef' references compile to a getter call
-- that returns a fresh allocation; both look like 'CVar n' in IR
-- but neither is a heap-pointer borrow, so they must not be
-- inc'd. The LLVM backend doesn't care because @__inc_ref@ on
-- non-heap addresses reads a stray byte and skips on flag != 1.
isHeapBorrow :: ExprCtx -> CExpr -> Bool
isHeapBorrow ctx = \case
  CVar n -> not (Set.member n ctx.ecValDefs || Set.member n ctx.ecFunDefs)
  CDrop _ _ body -> isHeapBorrow ctx body
  _ -> False

-- | After storing a ptr value at @conSlot + slotIdx*4@, if
-- the source expression's tail is a heap-borrow 'CVar', emit
-- @(call $__inc_ref (i32.load offset=slotIdx*4 conSlot))@. Mirrors
-- 'incIfCVarStored' in 'Awsum.Codegen.WASM' (text codegen).
incStoredFieldBin :: ExprCtx -> Word32 -> Int -> CExpr -> [Word8]
incStoredFieldBin ctx conSlot slotIdx fld
  | isHeapBorrow ctx fld =
      [opLocalGet]
        <> encodeULEB128 conSlot
        <> [opI32Load]
        <> encodeULEB128 2
        <> encodeULEB128 (fromIntegral (slotIdx * 4 :: Int))
        <> [opCall]
        <> encodeULEB128 idxIncRef
  | otherwise = []

-- | Emit a value and, when its tail is a heap-borrow
-- 'CVar', tee the result through @$__inc_ref_temp@ and call
-- @$__inc_ref@ before yielding the value back on the stack. Used
-- at user-CCall arg evaluation and 'CContinue' arg evaluation
-- where there's no destination slot to load back from.
emitArgWithIncBin :: ExprCtx -> CExpr -> [Word8]
emitArgWithIncBin ctx fld
  | isHeapBorrow ctx fld =
      emitExpr ctx fld
        <> [opLocalTee]
        <> encodeULEB128 ctx.ecIncRefTempSlot
        <> [opCall]
        <> encodeULEB128 idxIncRef
        <> [opLocalGet]
        <> encodeULEB128 ctx.ecIncRefTempSlot
  | otherwise = emitExpr ctx fld

-- | Emit a case expression as nested if/else in binary WASM.
-- Stores scrutinee pointer to $__scrut, loads tag, then chains if/else arms.
emitCaseChain :: ExprCtx -> CExpr -> [(Int, [Text], CExpr)] -> [Word8]
emitCaseChain _ctx _scrut [] = [opI32Const] <> encodeSLEB128 0 -- unreachable
emitCaseChain ctx scrut alts =
  let scrutSlot = ctx.ecScrutSlot
      scrutFresh = isNothing (sourceCVarBin scrut)
      scrutName = sourceCVarBin scrut
      -- evaluate scrutinee and store to scrut local
      storeCode =
        emitExpr ctx scrut
          <> [opLocalSet]
          <> encodeULEB128 scrutSlot
   in storeCode <> emitArmChain ctx scrutName scrutFresh alts

-- | Dec the scrut after 'bindArmVars' has extracted the
-- arm's binders. Case-binders were inc'd at extract so their cells
-- survive even if cascade-free of scrut decs the slot-ref. Only
-- fires when @scrutFresh@ — borrowed scruts (CVar source) keep
-- their original owner.
scrutDecAfterBind :: ExprCtx -> Bool -> [Word8]
scrutDecAfterBind ctx scrutFresh
  | scrutFresh =
      [opLocalGet]
        <> encodeULEB128 ctx.ecScrutSlot
        <> [opCall]
        <> encodeULEB128 idxFreeRecursive
  | otherwise = []

-- | Emit the if/else chain for case arms (scrutinee already in $__scrut).
-- @scrutFresh@ marks whether the scrut is a fresh allocation that
-- must be dec'd after each arm's bindArmVars (no other owner once
-- the case completes). @scrutName@ is the binder name of the
-- scrutinee when it's a 'CVar' — recorded in
-- 'ecArmPatternByScrut' so a nested 'CReuse' can detect
-- self-moves.
emitArmChain :: ExprCtx -> Maybe Text -> Bool -> [(Int, [Text], CExpr)] -> [Word8]
emitArmChain _ctx _scrutName _scrutFresh [] = [opI32Const] <> encodeSLEB128 0
emitArmChain ctx scrutName scrutFresh [(_, vars, body)] =
  -- Last arm: bind vars and emit body, no tag comparison needed
  let (bindCode, ctx') = bindArmVars ctx vars
      ctx'' = recordArmPattern ctx' scrutName vars
   in bindCode <> scrutDecAfterBind ctx scrutFresh <> emitExpr ctx'' body
emitArmChain ctx scrutName scrutFresh ((tag, vars, body) : rest) =
  let scrutSlot = ctx.ecScrutSlot
      -- load tag from scrutinee container (i32 at offset 0)
      loadTag =
        [opLocalGet]
          <> encodeULEB128 scrutSlot
          <> [opI32Load]
          <> encodeULEB128 2
          <> encodeULEB128 0
      cmpCode =
        [opI32Const]
          <> encodeSLEB128 (fromIntegral tag)
          <> [0x46] -- i32.eq
      (bindCode, ctx') = bindArmVars ctx vars
      ctx'' = recordArmPattern ctx' scrutName vars
   in loadTag
        <> cmpCode
        <> [opIf, blocktypeI32]
        <> bindCode
        <> scrutDecAfterBind ctx scrutFresh
        <> emitExpr ctx'' body
        <> [opElse]
        <> emitArmChain ctx scrutName scrutFresh rest
        <> [opEnd]

-- | Linear-scrutinee elision helper: extend 'ecArmPatternByScrut' if
-- the scrut is a 'CVar' (Just name). No-op otherwise.
recordArmPattern :: ExprCtx -> Maybe Text -> [Text] -> ExprCtx
recordArmPattern ctx scrutName vars = case scrutName of
  Just n -> ctx {ecArmPatternByScrut = Map.insert n vars ctx.ecArmPatternByScrut}
  Nothing -> ctx

-- | Bind case arm variables: load fields from scrutinee container into locals.
-- The returned context advances 'ecBoundBase' past the fresh slots so any
-- nested 'CCase' inside the arm body allocates beyond the still-live outer
-- bindings. Slot demand is bounded by 'exprMaxBoundVars' (sum across the
-- deepest nesting path).
bindArmVars :: ExprCtx -> [Text] -> ([Word8], ExprCtx)
bindArmVars ctx vars =
  let base = ctx.ecBoundBase
      scrutSlot = ctx.ecScrutSlot
      bindOne v i =
        let slot = base + fromIntegral i
            offset = fromIntegral ((i + 1) * 4 :: Int)
            -- Inc each extracted ptr-binder so the local
            -- binding takes its own ref. The matching dec at arm
            -- end is the 'CDrop' wrap that 'Awsum.Lifetime' adds.
            bc =
              [opLocalGet]
                <> encodeULEB128 scrutSlot
                <> [opI32Load]
                <> encodeULEB128 2
                <> encodeULEB128 offset
                <> [opLocalSet]
                <> encodeULEB128 slot
                <> [opLocalGet]
                <> encodeULEB128 slot
                <> [opCall]
                <> encodeULEB128 idxIncRef
         in (bc, (v, slot))
      results = zipWith bindOne vars [0 :: Int ..]
      code = concatMap fst results
      newLocals = foldl' (\m (v, slot) -> Map.insert v slot m) ctx.ecLocals (map snd results)
      ctx' =
        ctx
          { ecLocals = newLocals,
            ecBoundBase = base + fromIntegral (length vars)
          }
   in (code, ctx')

-- | Emit @body@ in tail position under @(loop $tco_top (result i32) ...)@.
--
-- 'depth' counts how many nested @opIf@ / @opBlock@ / @opLoop@ scopes
-- sit between the current point and the @tco_top@ loop header. 'CContinue'
-- emits @br depth@ to restart it; all other tail shapes produce an @i32@
-- value that becomes the loop's (and the function's) result.
--
-- The @tcoTempBase@ slot is the first of @arity@ scratch locals used to
-- buffer 'CContinue' arguments, so a new value that reads a still-old
-- parameter sees the old binding rather than a half-updated one.
emitTailBin :: Word32 -> [Text] -> Word32 -> ExprCtx -> CExpr -> [Word8]
emitTailBin tcoTempBase params depth ctx =
  emitTailBinPending tcoTempBase params depth ctx [] 0

-- | Emit `(call $__free_recursive (local.get freshScrutSlot[i]))`
-- for every fresh-scrut stash slot in current scope (depths 0..n-1).
-- Slots live at `ecFreshScrutBase + i`.
emitFreshScrutDecs :: ExprCtx -> Int -> [Word8]
emitFreshScrutDecs ctx freshScrutDepth =
  concat
    [ [opLocalGet]
        <> encodeULEB128 (ctx.ecFreshScrutBase + fromIntegral i)
        <> [opCall]
        <> encodeULEB128 idxFreeRecursive
    | i <- [0 .. freshScrutDepth - 1]
    ]

-- | Emit a non-'CLoop' 'CFunDef' body with value-tail
-- param decs. Mirror of 'emitNonLoopBody' in LLVM: walks the
-- tail-form and emits dec at each terminal, with per-arm
-- precision for 'CCase'/'CRowCase' bodies so an arm returning a
-- 'CVar' param is "moved" out instead of being freed.
emitNonLoopBodyBin :: ExprCtx -> [Text] -> CExpr -> [Word8]
emitNonLoopBodyBin ctx0 params = go ctx0 [] 0
  where
    go :: ExprCtx -> [Text] -> Int -> CExpr -> [Word8]
    go ctx pending freshScrutDepth = \case
      CCase scrut alts ->
        let sorted = sortWith (\(t, _, _) -> t) alts
            scrutFresh = isNothing (sourceCVarBin scrut)
            scrutName = sourceCVarBin scrut
            freshStashSlot = ctx.ecFreshScrutBase + fromIntegral freshScrutDepth
            scrutCode =
              if scrutFresh
                then
                  emitExpr ctx scrut
                    <> [opLocalTee]
                    <> encodeULEB128 freshStashSlot
                    <> [opLocalSet]
                    <> encodeULEB128 ctx.ecScrutSlot
                else
                  emitExpr ctx scrut
                    <> [opLocalSet]
                    <> encodeULEB128 ctx.ecScrutSlot
            freshScrutDepth' = if scrutFresh then freshScrutDepth + 1 else freshScrutDepth
         in scrutCode <> goCaseChain ctx scrutName pending freshScrutDepth' sorted
      CRowCase scrut alts ->
        go ctx pending freshScrutDepth (CCase scrut [(fromIntegral t, [v], b) | (t, v, b) <- alts])
      CDrop _ n body -> go ctx (n : pending) freshScrutDepth body
      other ->
        let resultName = sourceCVarBin other
            inResult m = Just m == resultName
            pendingToDec = filter (not . inResult) pending
            paramsToDec =
              [ p
              | p <- params,
                not (inResult p),
                p `notElem` pending
              ]
            toDec = pendingToDec <> paramsToDec
            scrutDecs = emitFreshScrutDecs ctx freshScrutDepth
         in drainPendingBin ctx toDec (scrutDecs <> emitExpr ctx other)

    -- Per-arm dec: each arm body emits its own (potentially
    -- different) param decs based on its own tail-form. Each arm
    -- self-terminates with a value (the function's 'if (result
    -- i32) ...' chain unifies them through WASM's structured
    -- control flow).
    goCaseChain :: ExprCtx -> Maybe Text -> [Text] -> Int -> [(Int, [Text], CExpr)] -> [Word8]
    goCaseChain _ _ _ _ [] = [opI32Const] <> encodeSLEB128 0 -- unreachable
    goCaseChain ctx scrutName pending freshScrutDepth [(_, vars, body)] =
      let (bindCode, ctx') = bindArmVars ctx vars
          ctx'' = recordArmPattern ctx' scrutName vars
       in bindCode <> go ctx'' pending freshScrutDepth body
    goCaseChain ctx scrutName pending freshScrutDepth ((tag, vars, body) : rest) =
      [opLocalGet]
        <> encodeULEB128 ctx.ecScrutSlot
        <> [opI32Load]
        <> encodeULEB128 2
        <> encodeULEB128 0
        <> [opI32Const]
        <> encodeSLEB128 (fromIntegral tag)
        <> [opI32Eq]
        <> [opIf, blocktypeI32]
        <> ( let (bindCode, ctx') = bindArmVars ctx vars
                 ctx'' = recordArmPattern ctx' scrutName vars
              in bindCode <> go ctx'' pending freshScrutDepth body
           )
        <> [opElse]
        <> goCaseChain ctx scrutName pending freshScrutDepth rest
        <> [opEnd]

-- | Walk a tail-position expression, accumulating 'CDrop' binders into
-- a 'pending' stack drained at every terminator (CContinue / value).
-- 'CCase' arms inherit the same 'pending' through 'emitTailArmChain'.
-- @freshScrutDepth@ counts how many fresh case-scrutinees are
-- currently stashed in `ecFreshScrutBase`-indexed slots; each
-- terminator dec's them.
emitTailBinPending :: Word32 -> [Text] -> Word32 -> ExprCtx -> [Text] -> Int -> CExpr -> [Word8]
emitTailBinPending tcoTempBase params depth ctx pending freshScrutDepth = \case
  CContinue newArgs ->
    let -- Buffer each new arg into the scratch slot (so a new value
        -- that reads an old param sees the pre-update value).
        evals =
          concat
            [ emitExpr ctx a
                <> [opLocalSet]
                <> encodeULEB128 (tcoTempBase + fromIntegral i)
            | (i, a) <- zip [0 :: Int ..] newArgs
            ]
        -- Inc each ptr-arg whose source is a CVar (borrow
        -- → the next-iter slot takes its own ref). Fresh sources
        -- carry their @+1@ from @$__alloc@.
        incs =
          concat
            [ case sourceCVarBin a of
                Just _ ->
                  [opLocalGet]
                    <> encodeULEB128 (tcoTempBase + fromIntegral i)
                    <> [opCall]
                    <> encodeULEB128 idxIncRef
                Nothing -> []
            | (i, a) <- zip [0 :: Int ..] newArgs
            ]
        scrutDecs = emitFreshScrutDecs ctx freshScrutDepth
        frees = concatMap (emitFreeOf ctx) pending
        paramSlots =
          [ fromMaybe (error $ "WASM Assemble: no param slot for " <> show p) (Map.lookup p ctx.ecParams)
          | p <- params
          ]
        copies =
          concat
            [ [opLocalGet]
                <> encodeULEB128 (tcoTempBase + fromIntegral i)
                <> [opLocalSet]
                <> encodeULEB128 ps
            | (i, ps) <- zip [0 :: Int ..] paramSlots
            ]
     in evals <> incs <> scrutDecs <> frees <> copies <> [opBr] <> encodeULEB128 depth
  CCase scrut alts ->
    let sorted = sortWith (\(t, _, _) -> t) alts
        scrutFresh = isNothing (sourceCVarBin scrut)
        scrutName = sourceCVarBin scrut
        freshStashSlot = ctx.ecFreshScrutBase + fromIntegral freshScrutDepth
        -- If scrut is fresh, tee through the fresh-scrut stash
        -- slot before storing to ecScrutSlot so arm terminators
        -- can dec it later (the dispatch slot may be overwritten
        -- by inner cases, but the stash survives).
        scrutCode =
          if scrutFresh
            then
              emitExpr ctx scrut
                <> [opLocalTee]
                <> encodeULEB128 freshStashSlot
                <> [opLocalSet]
                <> encodeULEB128 ctx.ecScrutSlot
            else
              emitExpr ctx scrut
                <> [opLocalSet]
                <> encodeULEB128 ctx.ecScrutSlot
        freshScrutDepth' = if scrutFresh then freshScrutDepth + 1 else freshScrutDepth
     in scrutCode <> emitTailArmChain tcoTempBase params depth ctx scrutName pending freshScrutDepth' sorted
  -- Push the drop onto the pending stack; drain at terminator.
  CDrop _ n body -> emitTailBinPending tcoTempBase params depth ctx (n : pending) freshScrutDepth body
  other ->
    let -- Value-tail decs with move-semantics carve-out.
        -- Result-CVar matching a pending or param is "moved" out;
        -- everything else is dec'd.
        resultName = sourceCVarBin other
        inResult m = Just m == resultName
        pendingToDec = filter (not . inResult) pending
        paramsToDec =
          [ p
          | p <- params,
            not (inResult p),
            p `notElem` pending
          ]
        toDec = pendingToDec <> paramsToDec
        scrutDecs = emitFreshScrutDecs ctx freshScrutDepth
     in drainPendingBin ctx toDec (scrutDecs <> emitExpr ctx other)

-- | Drain pending drops at a value-producing tail. Wraps the value
-- expression in @(block (result i32) (local.set $__drop_tmp …) …frees…
-- (local.get $__drop_tmp))@. Empty pending → no wrapping.
drainPendingBin :: ExprCtx -> [Text] -> [Word8] -> [Word8]
drainPendingBin _ [] valueBytes = valueBytes
drainPendingBin ctx pending valueBytes =
  [opBlock, blocktypeI32]
    <> valueBytes
    <> [opLocalSet]
    <> encodeULEB128 ctx.ecDropTmpSlot
    <> concatMap (emitFreeOf ctx) pending
    <> [opLocalGet]
    <> encodeULEB128 ctx.ecDropTmpSlot
    <> [opEnd]

-- | Emit @(call $__free_recursive (local.get $<binder>))@.
-- The binder must be a function param ('ecParams') or a
-- case-pattern binder ('ecLocals') already in scope.
emitFreeOf :: ExprCtx -> Text -> [Word8]
emitFreeOf ctx n =
  let slot = lookupBinderSlot ctx n
   in [opLocalGet]
        <> encodeULEB128 slot
        <> [opCall]
        <> encodeULEB128 idxFreeRecursive

-- | Emit @(call $__free_recursive (local.get N))@ for a
-- builtin-helper arg in slot N. Builtins take ownership of their
-- args (same model as user CCalls): caller-side inc-on-CVar (via
-- 'emitArgWithIncBin') balances callee-side dec at helper exit.
-- Used inside the @code…@ helper bodies.
decArgBin :: Word32 -> [Word8]
decArgBin slot =
  [opLocalGet]
    <> encodeULEB128 slot
    <> [opCall]
    <> encodeULEB128 idxFreeRecursive

-- | Tail version of 'emitArmChain': each arm is emitted in tail form so
-- it either produces an @i32@ result or terminates with a @br@ back to
-- the loop. Nesting into an @opIf@ increases 'depth' by one for both the
-- then-body and the else-continuation.
emitTailArmChain :: Word32 -> [Text] -> Word32 -> ExprCtx -> Maybe Text -> [Text] -> Int -> [(Int, [Text], CExpr)] -> [Word8]
emitTailArmChain _ _ _ _ _ _ _ [] = [opI32Const] <> encodeSLEB128 0
emitTailArmChain tcoTempBase params depth ctx scrutName pending freshScrutDepth [(_, vars, body)] =
  let (bindCode, ctx') = bindArmVars ctx vars
      ctx'' = recordArmPattern ctx' scrutName vars
   in bindCode <> emitTailBinPending tcoTempBase params depth ctx'' pending freshScrutDepth body
emitTailArmChain tcoTempBase params depth ctx scrutName pending freshScrutDepth ((tag, vars, body) : rest) =
  let scrutSlot = ctx.ecScrutSlot
      loadTag =
        [opLocalGet]
          <> encodeULEB128 scrutSlot
          <> [opI32Load]
          <> encodeULEB128 2
          <> encodeULEB128 0
      cmpCode =
        [opI32Const]
          <> encodeSLEB128 (fromIntegral tag)
          <> [0x46] -- i32.eq
      (bindCode, ctx') = bindArmVars ctx vars
      ctx'' = recordArmPattern ctx' scrutName vars
   in loadTag
        <> cmpCode
        <> [opIf, blocktypeI32]
        <> bindCode
        <> emitTailBinPending tcoTempBase params (depth + 1) ctx'' pending freshScrutDepth body
        <> [opElse]
        <> emitTailArmChain tcoTempBase params (depth + 1) ctx scrutName pending freshScrutDepth rest
        <> [opEnd]

-- ════════════════════════════════════════════════════════════════════════════
-- Data section
-- ════════════════════════════════════════════════════════════════════════════

buildDataSection :: WasmInfo -> [Word8]
buildDataSection info =
  let pool = sortWith snd (Map.toList info.wiStringPool)
      mkSegment (s, userPtr) =
        let payload = BS.unpack (encodeUtf8 s)
            byteCount = length payload
            utf16Count = utf16CountOfText s
            -- 12-byte {flag=0, refcount=0, shape=0} prefix
            -- marks the segment as a literal so '$__free' and
            -- '$__free_recursive' no-op on it. user_ptr =
            -- flag_start + 12, so the data write starts at user_ptr - 12.
            header =
              i32LeBytes 0 -- flag
                <> i32LeBytes 0 -- refcount
                <> i32LeBytes 0 -- shape
                <> i32LeBytes byteCount
                <> i32LeBytes utf16Count
            flagStart = userPtr - 12
         in [0x00] -- active, memory 0
              <> [opI32Const]
              <> encodeSLEB128 (fromIntegral flagStart)
              <> [opEnd]
              <> encodeBytes (header <> payload)
      content = encodeVec (map mkSegment pool)
   in buildSection 11 content

-- | Encode an Int as 4 little-endian bytes for the data-section header.
i32LeBytes :: Int -> [Word8]
i32LeBytes n =
  [fromIntegral ((n `shiftR` (8 * i)) .&. 0xFF) | i <- [0 .. 3 :: Int]]

-- ════════════════════════════════════════════════════════════════════════════
-- Module assembly
-- ════════════════════════════════════════════════════════════════════════════

buildModule :: PreludeTags -> CoreProgram -> B.Builder
buildModule ptags prog =
  let info = buildInfo ptags prog
      (typeSec, typeMap) = buildTypeSection info prog
      importSec = buildImportSection typeMap
      funcSec = buildFunctionSection info typeMap prog
      tableSec = buildTableSection info
      memorySec = buildMemorySection info
      globalSec = buildGlobalSection info
      exportSec = buildExportSection info
      elemSec = buildElementSection info
      codeSec = buildCodeSection info typeMap prog
      dataSec = buildDataSection info
   in B.byteString wasmMagic
        <> foldMap B.word8 typeSec
        <> foldMap B.word8 importSec
        <> foldMap B.word8 funcSec
        <> foldMap B.word8 tableSec
        <> foldMap B.word8 memorySec
        <> foldMap B.word8 globalSec
        <> foldMap B.word8 exportSec
        <> foldMap B.word8 elemSec
        <> foldMap B.word8 codeSec
        <> foldMap B.word8 dataSec

wasmMagic :: BS.ByteString
wasmMagic = BS.pack [0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00]

-- ════════════════════════════════════════════════════════════════════════════
-- Helpers
-- ════════════════════════════════════════════════════════════════════════════

buildSection :: Word8 -> [Word8] -> [Word8]
buildSection sectionId content =
  [sectionId] <> encodeULEB128 (fromIntegral (length content)) <> content

lookupType :: FuncType -> Map FuncType Word32 -> Word32
lookupType ft m = fromMaybe (error $ "type not in map: " <> show ft) (Map.lookup ft m)
