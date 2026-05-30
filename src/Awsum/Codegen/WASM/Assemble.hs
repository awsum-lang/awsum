-- | WebAssembly binary (.wasm) assembler for Awsum 'Core'.
--
-- Generates a single @.wasm@ module with WASI imports for I\/O.
-- All values are @i32@ (pointers into linear memory). Strings are
-- length-prefixed (a stored UTF-8 byte count and UTF-16 unit count in the
-- header; no NUL terminator). Per-size-bin freelist allocator
-- (@__alloc_shaped@). @funcref@ table for higher-order functions.
module Awsum.Codegen.WASM.Assemble
  ( assembleWASM,
    -- Exposed for the WAT text renderer ('Awsum.Codegen.WASM') so both
    -- projections resolve calls through one shared name→index map and the
    -- same user-code 'WasmFunc' specs (no dual emitter).
    runtimeFuncIdx,
    WasmInfo,
    buildInfo,
    buildTypeSection,
    userDeclFunc,
    startFunc,
  )
where

import Awsum.Codegen.WASM.Instr (BlockType (..), MemArg (..), ValType (..), WasmFunc (..), WasmInstr (..), addI32Spec, addU32Spec, addU8Spec, allocShapedSpec, allocSpec, boxI32Spec, concatSpec, entryArgEitherSpec, eqI32Spec, eqStringSpec, freeRecursiveSpec, freeSpec, freeWorklistPushSpec, getArgsSpec, incRefSpec, lengthCodePointsSpec, lengthUtf16CodeUnitsSpec, lengthUtf8BytesSpec, memcmpSpec, memcpySpec, mulI32Spec, mulU32Spec, mulU8Spec, negI32Spec, parseInt32Spec, parseUInt32Spec, parseUInt8Spec, predI32Spec, predU32Spec, predU8Spec, printSpec, showI32Spec, showU32Spec, splitOnFirstSpec, stdinReadAllSpec, subI32Spec, subU32Spec, subU8Spec, succI32Spec, succU32Spec, succU8Spec, utf16OfRangeSpec)
import Awsum.Core
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

-- ════════════════════════════════════════════════════════════════════════════
-- Binary projection of a 'WasmFunc'
-- ════════════════════════════════════════════════════════════════════════════

-- | The shared name→function-index map. Imports occupy 0..3; runtime helpers
--   follow at fixed indices. The assembler resolves a 'Call' target through
--   this, so
--   the WAT text and the @.wasm@ bytes cannot disagree on which function a
--   name denotes.
runtimeFuncIdx :: Map Text Word32
runtimeFuncIdx =
  Map.fromList
    [ -- WASI host imports occupy indices 0..3.
      ("fd_write", 0),
      ("args_sizes_get", 1),
      ("args_get", 2),
      ("fd_read", 3),
      ("__alloc", idxAlloc),
      ("__alloc_shaped", idxAllocShaped),
      ("__free", idxFree),
      ("__free_recursive", idxFreeRecursive),
      ("__free_worklist_push", idxFreeWorklistPush),
      ("__memcpy", idxMemcpy),
      ("__memcmp", idxMemcmp),
      ("__entryArgEither", idxEntryArgEither),
      ("__utf16_of_range", idxUtf16OfRange)
    ]

-- | Byte projection of a 'WasmFunc' — the code-section entry (locals vector +
--   linear instruction bytes + @end@), the binary counterpart of
--   'Awsum.Codegen.WASM.Instr.renderWat'. The function's type lives in the type
--   / function sections, built separately.
assembleFunc :: Map Text Word32 -> WasmFunc -> [Word8]
assembleFunc idxMap f =
  encodeBody (encodeLocalsVec (wfLocals f)) (concatMap (asmInstr idxMap) (wfBody f))

-- | Encode a @.locals@ vector, grouping consecutive same-typed locals into one
--   @(count, valtype)@ entry as the binary format requires.
encodeLocalsVec :: [ValType] -> [Word8]
encodeLocalsVec [] = encodeULEB128 0
encodeLocalsVec vts = encodeVec [encodeULEB128 (fromIntegral (length g)) <> [valtypeOf (unsafeHead g)] | g <- group vts]
  where
    valtypeOf I32 = valtypeI32
    valtypeOf I64 = valtypeI64
    unsafeHead (x : _) = x
    unsafeHead [] = error "encodeLocalsVec: empty group"

asmInstr :: Map Text Word32 -> WasmInstr -> [Word8]
asmInstr idxMap = \case
  I32Const n -> [opI32Const] <> encodeSLEB128 (fromIntegral n)
  Call name -> [opCall] <> encodeULEB128 (lookupIdx name)
  CallIdx idx -> [opCall] <> encodeULEB128 (fromIntegral idx)
  CallIndirect ty -> [opCallIndirect] <> encodeULEB128 (fromIntegral ty) <> encodeULEB128 0
  LocalGet n -> [opLocalGet] <> encodeULEB128 (fromIntegral n)
  LocalSet n -> [opLocalSet] <> encodeULEB128 (fromIntegral n)
  LocalTee n -> [opLocalTee] <> encodeULEB128 (fromIntegral n)
  GlobalGet n -> [opGlobalGet] <> encodeULEB128 (fromIntegral n)
  GlobalSet n -> [opGlobalSet] <> encodeULEB128 (fromIntegral n)
  I32Load (MemArg a o) -> [opI32Load] <> encodeULEB128 (fromIntegral a) <> encodeULEB128 (fromIntegral o)
  I32Store (MemArg a o) -> [opI32Store] <> encodeULEB128 (fromIntegral a) <> encodeULEB128 (fromIntegral o)
  I32Load8U (MemArg a o) -> [opI32Load8U] <> encodeULEB128 (fromIntegral a) <> encodeULEB128 (fromIntegral o)
  I32Store8 (MemArg a o) -> [opI32Store8] <> encodeULEB128 (fromIntegral a) <> encodeULEB128 (fromIntegral o)
  Block bt -> [opBlock, blockTypeByte bt]
  Loop bt -> [opLoop, blockTypeByte bt]
  If bt -> [opIf, blockTypeByte bt]
  Else -> [opElse]
  End -> [opEnd]
  Br n -> [opBr] <> encodeULEB128 (fromIntegral n)
  BrIf n -> [opBrIf] <> encodeULEB128 (fromIntegral n)
  Return -> [opReturn]
  Unreachable -> [opUnreachable]
  Drop -> [opDrop]
  I32Add -> [opI32Add]
  I32Sub -> [opI32Sub]
  I32Mul -> [opI32Mul]
  I32DivU -> [opI32DivU]
  I32RemU -> [opI32RemU]
  I32And -> [opI32And]
  I32Xor -> [opI32Xor]
  I32Shl -> [opI32Shl]
  I32Eqz -> [opI32Eqz]
  I32Eq -> [opI32Eq]
  I32Ne -> [opI32Ne]
  I32LtS -> [opI32LtS]
  I32LtU -> [opI32LtU]
  I32GeS -> [opI32GeS]
  I32GeU -> [opI32GeU]
  I32GtU -> [opI32GtU]
  I32LeU -> [opI32LeU]
  I32Ctz -> [opI32Ctz]
  I32Clz -> [opI32Clz]
  I64Const n -> [opI64Const] <> encodeSLEB128I64 (fromIntegral n)
  I64Add -> [opI64Add]
  I64Sub -> [opI64Sub]
  I64Mul -> [opI64Mul]
  I64Shl -> [opI64Shl]
  I64LtS -> [opI64LtS]
  I64GtS -> [opI64GtS]
  I64GtU -> [opI64GtU]
  I32WrapI64 -> [opI32WrapI64]
  I64ExtendI32S -> [opI64ExtendI32S]
  I64ExtendI32U -> [opI64ExtendI32U]
  MemorySize -> [opMemorySize, 0x00]
  MemoryGrow -> [opMemoryGrow, 0x00]
  where
    lookupIdx name = fromMaybe (error ("WASM.Assemble: no index for " <> name)) (Map.lookup name idxMap)

-- | The single-byte encoding of a structured block's result type.
blockTypeByte :: BlockType -> Word8
blockTypeByte = \case
  BtVoid -> blocktypeVoid
  BtI32 -> valtypeI32
  BtI64 -> valtypeI64

-- ════════════════════════════════════════════════════════════════════════════
-- Runtime helper bodies
-- ════════════════════════════════════════════════════════════════════════════

-- '$__alloc(size)' is a thin wrapper that calls
-- '$__alloc_shaped(size, 0)'. Existing helper alloc sites that
-- allocate scalars / strings / nullary cells keep their default
-- shape=0; CCon emit and helpers that build ADT cells with ptr
-- fields call '$__alloc_shaped' directly with the cell's arity.
codeAlloc :: [Word8]
codeAlloc = assembleFunc runtimeFuncIdx allocSpec

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
codeAllocShaped = assembleFunc runtimeFuncIdx allocShapedSpec

-- '$__inc_ref(p)' bumps the refcount at @p - 8@ unless
-- the cell is a literal (flag == 0).
codeIncRef :: [Word8]
codeIncRef = assembleFunc runtimeFuncIdx incRefSpec

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
codeFreeRecursive = assembleFunc runtimeFuncIdx freeRecursiveSpec

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
codeFreeWorklistPush = assembleFunc runtimeFuncIdx freeWorklistPushSpec

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
codeFree = assembleFunc runtimeFuncIdx freeSpec

-- __memcpy(dst: i32, src: i32, len: i32)
-- local $i: i32
codeMemcpy :: [Word8]
codeMemcpy = assembleFunc runtimeFuncIdx memcpySpec

-- __memcmp(a: i32, b: i32, len: i32) -> i32
-- Returns 1 iff all 'len' bytes at addresses 'a' and 'b' agree, 0 on
-- first mismatch. Driver for '__eqString' after the byte-count
-- short-circuit. Different shape from libc 'memcmp' (which returns a
-- tri-state ordering): equality alone is enough for string equality
-- and 'opReturn' on first mismatch lets the loop exit early.
-- Locals: $i(3).
codeMemcmp :: [Word8]
codeMemcmp = assembleFunc runtimeFuncIdx memcmpSpec

-- __eqString(a: i32, b: i32) -> i32
-- eqString : String -> String -> Bool. Strings are length-prefixed
-- (byte_count @ offset 0, utf16_count @ offset 4, payload @ offset 8).
-- Strict-UTF-16 ⇒ equal UTF-16 ⇔ equal UTF-8 bytes, so byte_count
-- check + '__memcmp' on the payload is sufficient. Returns a one-slot
-- Bool container ([tag]); True=0, False=1 per declaration order.
-- Locals: $ba(2) $bb(3) $cell(4) $eq(5).
codeEqString :: WasmInfo -> [Word8]
codeEqString info = assembleFunc runtimeFuncIdx (eqStringSpec (wiTags info))

-- __utf16_of_range(p: i32, len: i32) -> i32
-- Counts UTF-16 code units in a UTF-8 byte range. Used by
-- '__splitOnFirst' to set the utf16 prefix on each output substring.
-- Locals (after 2 params): $i(2), $n(3), $b(4).
codeUtf16OfRange :: [Word8]
codeUtf16OfRange = assembleFunc runtimeFuncIdx utf16OfRangeSpec

-- __concat(a: i32, b: i32) -> i32
-- Length-prefixed concat. O(1) cap-check via header.
-- Locals (after 2 params): $ba(2), $bb(3), $ua(4), $ub(5),

-- $usum(6), \$bsum(7), $stl(8), $cell(9), $buf(10).

codeConcat :: WasmInfo -> [Word8]
codeConcat info = assembleFunc runtimeFuncIdx (concatSpec (wiTags info))

-- __print(s: i32) -> i32
-- locals: $len (slot 1), $unit (slot 2)
-- Returns a Unit value (alloc(4); store tag 0) so the surrounding
-- `case … of Unit -> next` arm in the prelude's `runIO` dispatches
-- through the standard CCase tag check.
codePrint :: WasmInfo -> [Word8]
codePrint info = assembleFunc runtimeFuncIdx (printSpec (wiTags info))

-- __predInt32(p: i32) -> i32
-- predInt32: Int32 -> Either UnderflowError Int32.
--   Container layout matches user CCon emission on WASM: i32 tag at
--   offset 0, i32 fields at offsets 4, 8, ... Tags: Left=0, Right=1,
--   UnderflowError=0. Returns `Left UnderflowError` on INT32_MIN,
--   `Right (v - 1)` otherwise.
-- Locals: $v(1) $ue(2) $box(3) $cell(4)
codePredI32 :: WasmInfo -> [Word8]
codePredI32 info = assembleFunc runtimeFuncIdx (predI32Spec (wiTags info))

-- __predUInt8(p: i32) -> i32
-- predUInt8: UInt8 -> Either UnderflowError UInt8.
--   Mirrors 'codePredI32' but checks against 0 (via 'i32.eqz') instead
--   of INT32_MIN, and subtracts without masking — (v - 1) is in 0..254
--   when v >= 1, so it stays in UInt8 range naturally. Same locals
--   layout: $v(1) $ue(2) $box(3) $cell(4).
codePredU8 :: WasmInfo -> [Word8]
codePredU8 info = assembleFunc runtimeFuncIdx (predU8Spec (wiTags info))

-- __succInt32(p: i32) -> i32
-- succInt32: Int32 -> Either OverflowError Int32.
--   Mirrors 'codePredI32' with boundary INT32_MAX and i32.add instead of
--   i32.sub. OverflowError is single-constructor, so its inner-box tag is
--   0 (same as UnderflowError) — encoding is bit-identical to the
--   predecessor case on this axis.
-- Locals: $v(1) $oe(2) $box(3) $cell(4)
codeSuccI32 :: WasmInfo -> [Word8]
codeSuccI32 info = assembleFunc runtimeFuncIdx (succI32Spec (wiTags info))

-- __succUInt8(p: i32) -> i32
-- succUInt8: UInt8 -> Either OverflowError UInt8.
--   Mirrors 'codeSuccI32' but checks against 255. Masking is unnecessary —
--   (v + 1) is in 1..255 when v <= 254, so the result stays in UInt8 range
--   naturally. Same locals layout: $v(1) $oe(2) $box(3) $cell(4).
codeSuccU8 :: WasmInfo -> [Word8]
codeSuccU8 info = assembleFunc runtimeFuncIdx (succU8Spec (wiTags info))

-- __eq_i32(a: i32, b: i32) -> i32
-- eqInt32 / eqUInt8: compare two boxed integers, return a Bool container.
--   Int32 and UInt8 both flow as pointers to i32 cells (UInt8 values are
--   stored masked to 0..255), so one helper handles both. True=0, False=1
--   matches declaration order in `type Bool = True | False`.
-- Locals: $cell(2) — single i32 local, in addition to the two params.
codeEqI32 :: WasmInfo -> [Word8]
codeEqI32 info = assembleFunc runtimeFuncIdx (eqI32Spec (wiTags info))

-- __addInt32(pa: i32, pb: i32) -> i32
-- addInt32: Int32 -> Int32 -> Either ArithError Int32. Signed-overflow
-- detected via the XOR trick: '(a ^ s) & (b ^ s) < 0' (i32.lt_s 0)
-- holds iff the carry into the sign bit differs from the carry out.
-- Direction is read off 'a >= 0' (i32.ge_s 0) — same-sign overflow is
-- positive when a >= 0, negative otherwise. ArithError tags follow
-- Prelude.aww declaration order: Underflow=0, Overflow=1.
-- Locals: $a(2) $b(3) $s(4) $ae(5) $box(6) $cell(7).

codeAddI32 :: WasmInfo -> [Word8]
codeAddI32 info = assembleFunc runtimeFuncIdx (addI32Spec (wiTags info))

-- __addUInt8(pa: i32, pb: i32) -> i32
-- addUInt8: UInt8 -> UInt8 -> Either OverflowError UInt8. Sum is in
-- 0..510 so a single 'i32.gt_u 255' check picks the branch — no
-- widening, no mask on the ok path.
-- Locals: $s(2) $oe(3) $box(4) $cell(5).
codeAddU8 :: WasmInfo -> [Word8]
codeAddU8 info = assembleFunc runtimeFuncIdx (addU8Spec (wiTags info))

-- __subInt32(pa: i32, pb: i32) -> i32
-- subInt32: Int32 -> Int32 -> Either ArithError Int32. Same XOR-based
-- signed-overflow detection as 'codeAddI32', with i32.sub replacing
-- i32.add and the second XOR comparing 'a' vs 'diff' (the standard
-- subtraction overflow check). Direction (over vs under) is read off
-- 'a >= 0', identical to 'codeAddI32'.
-- Locals: $a(2) $b(3) $d(4) $ae(5) $box(6) $cell(7).
codeSubI32 :: WasmInfo -> [Word8]
codeSubI32 info = assembleFunc runtimeFuncIdx (subI32Spec (wiTags info))

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
codeMulI32 info = assembleFunc runtimeFuncIdx (mulI32Spec (wiTags info))

-- __negInt32(p: i32) -> i32
-- negInt32: Int32 -> Either OverflowError Int32. Mirror of 'codeSuccI32'
-- with INT32_MIN as the boundary and 'i32.sub 0 v' for the ok branch.
-- Locals: $v(1) $oe(2) $box(3) $cell(4).
codeNegI32 :: WasmInfo -> [Word8]
codeNegI32 info = assembleFunc runtimeFuncIdx (negI32Spec (wiTags info))

-- __subUInt8(pa: i32, pb: i32) -> i32
-- subUInt8: UInt8 -> UInt8 -> Either UnderflowError UInt8. The i32
-- difference is in -255..255; one 'i32.lt_s 0' check picks the underflow
-- branch — no widening or mask needed.
-- Locals: $d(2) $ue(3) $box(4) $cell(5).
codeSubU8 :: WasmInfo -> [Word8]
codeSubU8 info = assembleFunc runtimeFuncIdx (subU8Spec (wiTags info))

-- __mulUInt8(pa: i32, pb: i32) -> i32
-- mulUInt8: UInt8 -> UInt8 -> Either OverflowError UInt8. Inputs in
-- 0..255 give an i32 product in 0..65025 — well within i32 range. A
-- single 'i32.gt_u 255' check picks the branch.
-- Locals: $p(2) $oe(3) $box(4) $cell(5).
codeMulU8 :: WasmInfo -> [Word8]
codeMulU8 info = assembleFunc runtimeFuncIdx (mulU8Spec (wiTags info))

-- __predUInt32(p: i32) -> i32
-- predUInt32: UInt32 -> Either UnderflowError UInt32. Identical body
-- to 'codePredU8' — the underflow boundary is also 0 and i32.eqz / i32.sub
-- work bit-pattern-identically for u32.
-- Locals: $v(1) $ue(2) $box(3) $cell(4).
codePredU32 :: WasmInfo -> [Word8]
codePredU32 info = assembleFunc runtimeFuncIdx (predU32Spec (wiTags info))

-- __succUInt32(p: i32) -> i32
-- succUInt32: UInt32 -> Either OverflowError UInt32. Mirrors 'codeSuccU8'
-- but checks against 4294967295 — encoded as 'i32.const -1' (same bit
-- pattern). On the ok path '(v + 1)' wraps modulo 2^32, but since v is
-- already known to be < 4294967295, the result fits in u32 without wrap.
-- Locals: $v(1) $oe(2) $box(3) $cell(4).
codeSuccU32 :: WasmInfo -> [Word8]
codeSuccU32 info = assembleFunc runtimeFuncIdx (succU32Spec (wiTags info))

-- __addUInt32(pa: i32, pb: i32) -> i32
-- addUInt32: UInt32 -> UInt32 -> Either OverflowError UInt32. Promote
-- both operands to i64 (extend_i32_u, unsigned), sum at 64-bit width,
-- compare against 4294967295. The sum fits in i64 signed (max ~2*2^32),
-- so 'i64.gt_s' is equivalent to 'i64.gt_u' here — but keep gt_u for
-- semantic clarity with 'codeMulU32'.
-- Locals: 1 i64 ($s) + 4 i32 ($oe, $box, $cell, padding) — slots 2..5
-- with the i64 in slot 2.
codeAddU32 :: WasmInfo -> [Word8]
codeAddU32 info = assembleFunc runtimeFuncIdx (addU32Spec (wiTags info))

-- __subUInt32(pa: i32, pb: i32) -> i32
-- subUInt32: UInt32 -> UInt32 -> Either UnderflowError UInt32. Compare
-- 'a <u b' at i32 width (treats both stored cells as unsigned), then
-- 'i32.sub' produces the correct difference on the ok path.
-- Locals: $a(2) $b(3) $ue(4) $box(5) $cell(6).
codeSubU32 :: WasmInfo -> [Word8]
codeSubU32 info = assembleFunc runtimeFuncIdx (subU32Spec (wiTags info))

-- __mulUInt32(pa: i32, pb: i32) -> i32
-- mulUInt32: UInt32 -> UInt32 -> Either OverflowError UInt32. Promote
-- both operands to i64 unsigned, multiply at 64-bit width, compare
-- against 4294967295 with 'i64.gt_u'. The product (2^32-1)^2 ≈ 1.8 *
-- 2^63 fits in u64 but not in i64 signed, so we *must* use 'i64.gt_u'
-- here (where 'codeAddU32' could use either).
-- Locals: 1 i64 ($p) + 3 i32 ($oe, $box, $cell) — i64 in slot 2.
codeMulU32 :: WasmInfo -> [Word8]
codeMulU32 info = assembleFunc runtimeFuncIdx (mulU32Spec (wiTags info))

-- __splitOnFirst(sep: i32, str: i32) -> i32
-- splitOnFirst: String -> String -> Maybe (Tuple2 String String). Hand-
-- rolled byte scan since WASM has no built-in substring search. The
-- empty-separator and "separator longer than str" cases are handled
-- implicitly by the loop bounds.
-- Locals (beyond the two params): $sep_len(2) $str_len(3) $i(4) $j(5)
-- pos(6) $match(7) $prefix(8) $suffix(9) $tuple(10) $cell(11)

-- $suf_len(12) \$u16(13).

codeSplitOnFirst :: WasmInfo -> [Word8]
codeSplitOnFirst info = assembleFunc runtimeFuncIdx (splitOnFirstSpec (wiTags info))

-- __parseInt32(s: i32) -> i32
-- parseInt32: String -> Either ParseError Int32. Hand-rolled byte
-- scan; the int64 accumulator is capped at the magnitude `|minInt32|`
-- using the shift trick `(1 << 31)L`. On any failure path we set
-- `$failed = 1` and `br $exit`; the final `if` after the block builds
-- Right or Left ParseError.
-- Locals (beyond the param): $len(1) $i(2) $neg(3) $c(4) $box(5)
-- cell(6) $pe(7) $failed(8) $acc(9 — i64).
codeParseInt32 :: WasmInfo -> [Word8]
codeParseInt32 info = assembleFunc runtimeFuncIdx (parseInt32Spec (wiTags info))

-- __parseUInt8(s: i32) -> i32
-- Same shape as 'codeParseInt32' minus the sign handling, with an i32
-- accumulator (the running magnitude never exceeds 2559 before the
-- > 255 check fails the parse).
-- Locals: $len(1) $i(2) $acc(3) $c(4) $box(5) $cell(6) $pe(7) $failed(8).
codeParseUInt8 :: WasmInfo -> [Word8]
codeParseUInt8 info = assembleFunc runtimeFuncIdx (parseUInt8Spec (wiTags info))

-- __parseUInt32(s: i32) -> i32
-- Same shape as 'codeParseUInt8' but with an i64 accumulator (running
-- magnitude up to 4294967295 * 10 + 9 = 42949672959 fits in i64) and
-- a '> 4294967295' fast-fail check. On the ok path the i64 accumulator
-- is wrapped to i32 — the bit pattern of values 0..4294967295 in i64
-- and i32-as-u32 is identical.
-- Locals: $len(1, i32) $i(2, i32) $c(3, i32) $box(4, i32) $cell(5, i32)

-- $pe(6, i32) $failed(7, i32) $acc(8, i64).

codeParseUInt32 :: WasmInfo -> [Word8]
codeParseUInt32 info = assembleFunc runtimeFuncIdx (parseUInt32Spec (wiTags info))

-- __box_i32(v: i32) -> i32
-- Allocate a 4-byte cell, store v, return pointer.
-- local $p: i32 (slot 1)
codeBoxI32 :: WasmInfo -> [Word8]
codeBoxI32 _info = assembleFunc runtimeFuncIdx boxI32Spec

-- __show_i32(p: i32) -> i32
-- Read value from box, render decimal representation in fresh 16-byte buffer
-- (worst case: "-2147483648" = 11 chars + null). Returns a pointer to the
-- first character. Same routine handles Int32 (signed) and UInt8 (always
-- positive 0..255) — i32.lt_s is false for the UInt8 value space.
--
-- Locals: $v(1) $buf(2) $pos(3) $neg(4) $mag(5) $digit(6)
-- (param p is slot 0)
codeShowI32 :: WasmInfo -> [Word8]
codeShowI32 _info = assembleFunc runtimeFuncIdx showI32Spec

-- __show_u32(p: i32) -> i32
-- Render an unsigned 32-bit value as decimal. Mirrors 'codeShowI32' but
-- skips the negative-sign branch — the input bit pattern is treated as
-- unsigned end-to-end (i32.div_u / i32.rem_u), so values 2^31..2^32-1
-- render correctly without an erroneous '-' prefix.
--
-- Locals: $v(1) $buf(2) $pos(3) $digit(4)
codeShowU32 :: WasmInfo -> [Word8]
codeShowU32 _info = assembleFunc runtimeFuncIdx showU32Spec

-- __lengthUtf8Bytes(s: i32) -> i32
-- The stored UTF-8 byte count is the header word at s+0 (O(1) load); box the
-- result in a 4-byte cell. Locals: $box(1).
codeLengthBytesAsUtf8 :: [Word8]
codeLengthBytesAsUtf8 = assembleFunc runtimeFuncIdx lengthUtf8BytesSpec

-- __lengthCodePoints(s: i32) -> i32
-- Walks UTF-8 bytes; counts every byte whose top two bits are not 10.
-- Bound is header byte_count (offset 0); payload starts at offset 8.
-- Locals: $i(1), $n(2), $b(3), $box(4), $len(5), $payload(6).
codeLengthCodePoints :: [Word8]
codeLengthCodePoints = assembleFunc runtimeFuncIdx lengthCodePointsSpec

-- __lengthUtf16CodeUnits(s: i32) -> i32
-- Walks UTF-8 bytes; counts 1 for every codepoint start except 4-byte
-- starts (top five bits = 11110), which need a UTF-16 surrogate pair
-- and contribute 2. Continuation bytes are skipped. Locals:

-- O(1): the utf16 count is cached in the second i32 of the header.
codeLengthUtf16CodeUnits :: [Word8]
codeLengthUtf16CodeUnits = assembleFunc runtimeFuncIdx lengthUtf16CodeUnitsSpec

-- __getArgs() -> i32. Zero-arg helper for 'BuiltIn.internalGetArgs',
-- called from 'runIO''s 'IOGetArgs' arm. Reads the full argv via WASI
-- 'args_sizes_get' / 'args_get' and walks it from index argc-1 down to
-- 1 (index 0 is the program name, skipped), validating each element
-- via '__entryArgEither' and consing it onto a prelude 'List String'.
-- All-or-nothing error semantics — the first failing element
-- short-circuits with its 'Left'. On success the list is wrapped in
-- 'Right'. Walked right-to-left so order is preserved at the head; an
-- argv of just [exe] yields 'Right Nil'. Both the WAT text
-- ('Awsum.Codegen.WASM') and these bytes render from the shared
-- 'getArgsSpec', so they cannot disagree.
--
-- Locals (10, all i32): 0 = argc, 1 = ptrs, 2 = buf, 3 = i,
-- 4 = p (current arg pointer), 5 = l (its byte length),
-- 6 = cell (Either from __entryArgEither), 7 = head (String ptr),
-- 8 = acc (list accumulator), 9 = consC.
codeGetArgs :: PreludeTags -> [Word8]
codeGetArgs ptags = assembleFunc runtimeFuncIdx (getArgsSpec ptags)

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
codeStdinReadAll = assembleFunc runtimeFuncIdx stdinReadAllSpec

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
codeEntryArgEither info = assembleFunc runtimeFuncIdx (entryArgEitherSpec (wiTags info))

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

-- _start: builds the IO tree via v_main and hands it to v_runIO,
-- dropping the Unit result. 'main' takes no arguments; user code reads
-- argv through 'IO.Args.getArgs' inside the IO chain (lowers to an
-- 'IOGetArgs' constructor whose runIO arm calls '__getArgs').

-- | @_start@ as a 'WasmFunc'. @v_main@ is a zero-arg value (CValDef) building the
--   IO tree; @runIO@ walks it for effects and returns Unit (discarded). User
--   code reads argv through @IO.Args.getArgs@ inside the chain (an @IOGetArgs@
--   constructor whose runIO arm calls @__getArgs@). Void result.
startFunc :: WasmInfo -> WasmFunc
startFunc info =
  let mainIdx = fromMaybe 0 (Map.lookup "main" info.wiFuncIdx)
      runIOIdx = fromMaybe (error "no v_runIO") (Map.lookup "runIO" info.wiFuncIdx)
   in WasmFunc
        { wfName = "_start",
          wfParams = [],
          wfResults = [],
          wfLocals = [],
          wfBody = [CallIdx (fromIntegral mainIdx), CallIdx (fromIntegral runIOIdx), Drop]
        }

codeStart :: WasmInfo -> [Word8]
codeStart info = assembleFunc runtimeFuncIdx (startFunc info)

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

-- | Resolve a parameter or case-arm binder name to its WASM local slot.
-- 'CDrop' only ever drops names introduced as function
-- parameters ('ecParams') or case/row-case binders ('ecLocals'); a
-- lookup miss is a pipeline bug.
lookupBinderSlot :: ExprCtx -> Text -> Word32
lookupBinderSlot ctx n
  | Just slot <- Map.lookup n ctx.ecLocals = slot
  | Just slot <- Map.lookup n ctx.ecParams = slot
  | otherwise = error $ "WASM Assemble: CDrop on unknown binder: " <> show n

-- | Return the binder name if the expression's tail is a 'CVar'
-- (possibly under 'CDrop' wrappers). Used to detect borrow positions
-- that need a caller-side @__inc_ref@.
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
-- inc'd.
isHeapBorrow :: ExprCtx -> CExpr -> Bool
isHeapBorrow ctx = \case
  CVar n -> not (Set.member n ctx.ecValDefs || Set.member n ctx.ecFunDefs)
  CDrop _ _ body -> isHeapBorrow ctx body
  _ -> False

-- | Linear-scrutinee elision helper: extend 'ecArmPatternByScrut' if
-- the scrut is a 'CVar' (Just name). No-op otherwise.
recordArmPattern :: ExprCtx -> Maybe Text -> [Text] -> ExprCtx
recordArmPattern ctx scrutName vars = case scrutName of
  Just n -> ctx {ecArmPatternByScrut = Map.insert n vars ctx.ecArmPatternByScrut}
  Nothing -> ctx

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

-- ════════════════════════════════════════════════════════════════════════════
-- User-code emitter ([WasmInstr] projection)
-- ════════════════════════════════════════════════════════════════════════════

emitExprI :: ExprCtx -> CExpr -> [WasmInstr]
emitExprI ctx = \case
  CString s ->
    let offset = fromMaybe (error $ "string not in pool: " <> show s) (Map.lookup s ctx.ecStringPool)
     in [I32Const offset]
  CVar n
    | Just slot <- Map.lookup n ctx.ecLocals ->
        [LocalGet (fromIntegral slot)]
    | Just slot <- Map.lookup n ctx.ecParams ->
        [LocalGet (fromIntegral slot)]
    | n `Set.member` ctx.ecValDefs ->
        let fIdx = fromMaybe 0 (Map.lookup n ctx.ecFuncIdx)
         in [CallIdx (fromIntegral fIdx)]
    | n `Set.member` ctx.ecFunDefs ->
        let tblIdx = fromMaybe 0 (Map.lookup n ctx.ecTableMap)
         in [I32Const tblIdx]
    | otherwise ->
        [I32Const 0]
  CBuiltIn _ ->
    [I32Const 0] -- invariant: not a standalone term; dispatched from CCall
  CIntLit n _ ->
    let n32 = fromInteger n :: Int32
     in [I32Const (fromIntegral n32)]
          <> [CallIdx (fromIntegral idxBoxI32)]
  CCon tag fields ->
    let nSlots = 1 + length fields
        nFields = length fields
        conSlot = ctx.ecConBaseSlot + fromIntegral ctx.ecConDepth
        nestedCtx = ctx {ecConDepth = ctx.ecConDepth + 1}
        -- Allocate (nSlots * 4) bytes with shape inline
        -- via '$__alloc_shaped(size, shape)'.
        allocCode =
          [I32Const (nSlots * 4)]
            <> [I32Const nFields]
            <> [CallIdx (fromIntegral idxAllocShaped)]
            <> [LocalSet (fromIntegral conSlot)]
        -- store tag at offset 0
        tagCode =
          [LocalGet (fromIntegral conSlot)]
            <> [I32Const tag]
            <> [I32Store (MemArg 2 (0 :: Int))]
        -- store each field at offset (i+1)*4 then inc-on-CVar
        storeField (fld, i) =
          [LocalGet (fromIntegral conSlot)]
            <> emitExprI nestedCtx fld
            <> [I32Store (MemArg 2 ((i + 1) * 4 :: Int))]
            <> incStoredFieldI nestedCtx conSlot (i + 1) fld
        fieldCode = concatMap storeField (zip fields [0 :: Int ..])
        -- return pointer
        retCode = [LocalGet (fromIntegral conSlot)]
     in allocCode <> tagCode <> fieldCode <> retCode
  CCase scrut alts ->
    let sorted = sortWith (\(t, _, _) -> t) alts
     in emitCaseChainI ctx scrut sorted
  -- Row injection / dispatch: same wire layout as one-field 'CCon' /
  -- 'CCase', so delegate.
  CRow tag v -> emitExprI ctx (CCon (fromIntegral tag) [v])
  CRowCase scrut alts ->
    emitExprI ctx (CCase scrut [(fromIntegral t, [v], b) | (t, v, b) <- alts])
  CCall f xs ->
    case f of
      CBuiltIn "internalStdoutPrint"
        | [x] <- xs ->
            emitArgWithIncI ctx x
              <> [CallIdx (fromIntegral idxPrint)]
      -- 'BuiltIn.internalGetArgs' — call '__getArgs', which re-reads
      -- argv via WASI 'args_get' and routes the result through
      -- '__entryArgEither'.
      CBuiltIn "internalGetArgs"
        | [] <- xs ->
            [CallIdx (fromIntegral idxGetArgs)]
      -- 'BuiltIn.internalStdinReadAllAsUtf16' — call '__stdinReadAll',
      -- which consumes fd 0 to EOF via WASI 'fd_read' and routes the
      -- bytes through '__entryArgEither'.
      CBuiltIn "internalStdinReadAllAsUtf16"
        | [] <- xs ->
            [CallIdx (fromIntegral idxStdinReadAll)]
      CBuiltIn name
        | name == "showInt32" || name == "showUInt8",
          [x] <- xs ->
            emitArgWithIncI ctx x
              <> [CallIdx (fromIntegral idxShowI32)]
      CBuiltIn "showUInt32"
        | [x] <- xs ->
            emitArgWithIncI ctx x
              <> [CallIdx (fromIntegral idxShowU32)]
      CBuiltIn "predInt32"
        | [x] <- xs ->
            emitArgWithIncI ctx x
              <> [CallIdx (fromIntegral idxPredI32)]
      CBuiltIn "predUInt8"
        | [x] <- xs ->
            emitArgWithIncI ctx x
              <> [CallIdx (fromIntegral idxPredU8)]
      CBuiltIn "predUInt32"
        | [x] <- xs ->
            emitArgWithIncI ctx x
              <> [CallIdx (fromIntegral idxPredU32)]
      CBuiltIn "succInt32"
        | [x] <- xs ->
            emitArgWithIncI ctx x
              <> [CallIdx (fromIntegral idxSuccI32)]
      CBuiltIn "succUInt8"
        | [x] <- xs ->
            emitArgWithIncI ctx x
              <> [CallIdx (fromIntegral idxSuccU8)]
      CBuiltIn "succUInt32"
        | [x] <- xs ->
            emitArgWithIncI ctx x
              <> [CallIdx (fromIntegral idxSuccU32)]
      CBuiltIn name
        | name == "eqInt32" || name == "eqUInt8" || name == "eqUInt32",
          [a, b] <- xs ->
            emitArgWithIncI ctx a
              <> emitArgWithIncI ctx b
              <> [CallIdx (fromIntegral idxEqI32)]
      CBuiltIn "eqString"
        | [a, b] <- xs ->
            emitArgWithIncI ctx a
              <> emitArgWithIncI ctx b
              <> [CallIdx (fromIntegral idxEqString)]
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
             in emitArgWithIncI ctx a
                  <> emitArgWithIncI ctx b
                  <> [CallIdx (fromIntegral idx)]
      CBuiltIn "negInt32"
        | [x] <- xs ->
            emitArgWithIncI ctx x
              <> [CallIdx (fromIntegral idxNegI32)]
      CBuiltIn "splitOnFirst"
        | [a, b] <- xs ->
            emitArgWithIncI ctx a
              <> emitArgWithIncI ctx b
              <> [CallIdx (fromIntegral idxSplitOnFirst)]
      CBuiltIn name
        | name == "parseInt32" || name == "parseUInt8" || name == "parseUInt32",
          [x] <- xs ->
            let idx = case name of
                  "parseInt32" -> idxParseI32
                  "parseUInt32" -> idxParseU32
                  _ -> idxParseU8
             in emitArgWithIncI ctx x
                  <> [CallIdx (fromIntegral idx)]
      CBuiltIn name
        | name == "lengthCodePoints" || name == "lengthUtf16CodeUnits" || name == "lengthUtf8Bytes",
          [x] <- xs ->
            let idx = case name of
                  "lengthCodePoints" -> idxLengthCodePoints
                  "lengthUtf16CodeUnits" -> idxLengthUtf16CodeUnits
                  _ -> idxLengthBytesAsUtf8
             in emitArgWithIncI ctx x
                  <> [CallIdx (fromIntegral idx)]
      CBuiltIn "concatString"
        | [a, b] <- xs ->
            emitArgWithIncI ctx a
              <> emitArgWithIncI ctx b
              <> [CallIdx (fromIntegral idxConcat)]
      CBuiltIn n ->
        error ("WASM codegen: unknown builtin '" <> n <> "' reached CCall (typecheck should have rejected it)")
      CVar n
        | n `Set.member` ctx.ecFunDefs ->
            -- User CCall — caller-side inc on each CVar
            -- ptr-arg (borrow that needs its own ref for the
            -- callee's param slot). Builtins above bypass this:
            -- they only READ args, never store them.
            let fIdx = fromMaybe 0 (Map.lookup n ctx.ecFuncIdx)
             in concatMap (emitArgWithIncI ctx) xs
                  <> [CallIdx (fromIntegral fIdx)]
      _ ->
        -- Indirect user CCall (HOF dispatched through $applyN
        -- after Cps/LowerClosures). Same caller-side inc rule.
        let arity = length xs
            typeIdx = lookupType (FuncType arity True) ctx.ecTypeMap
         in concatMap (emitArgWithIncI ctx) xs
              <> emitExprI ctx f
              <> [CallIndirect (fromIntegral typeIdx)]
  CLoop _ -> error "WASM Assemble: CLoop in non-tail position (pipeline bug — should only appear at function-body-tail)"
  CContinue _ -> error "WASM Assemble: CContinue in non-tail position (pipeline bug — should only appear inside a CLoop)"
  -- Evaluate body, stash its value in $__drop_tmp,
  -- call $__free_recursive on the binder, then reload the captured
  -- result. If the body's tail itself is @CVar n@ (we're returning
  -- the same binder we're about to dec), inc the result first so
  -- the dec balances and the returned cell stays alive (the
  -- move-semantics rule for a returned binder).
  CDrop _ n body ->
    let bodyBytes = emitExprI ctx body
        slot = lookupBinderSlot ctx n
        moveInc = case sourceCVarBin body of
          Just m
            | m == n ->
                [LocalGet (fromIntegral ctx.ecDropTmpSlot)]
                  <> [CallIdx (fromIntegral idxIncRef)]
          _ -> []
     in [Block BtI32]
          <> bodyBytes
          <> [LocalSet (fromIntegral ctx.ecDropTmpSlot)]
          <> moveInc
          <> [LocalGet (fromIntegral slot)]
          <> [CallIdx (fromIntegral idxFreeRecursive)]
          <> [LocalGet (fromIntegral ctx.ecDropTmpSlot)]
          <> [End]
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
              [LocalGet (fromIntegral nSlot)]
                <> [I32Load (MemArg 2 ((i + 1) * 4 :: Int))]
                <> [CallIdx (fromIntegral idxFreeRecursive)]
        decOldCode = concatMap decOldSlot [0 .. nFields - 1]
        -- store tag at offset 0
        tagCode =
          [LocalGet (fromIntegral nSlot)]
            <> [I32Const tag]
            <> [I32Store (MemArg 2 (0 :: Int))]
        -- Store each field at offset (i+1)*4 with the
        -- inc-on-CVar discipline (same rule as CCon — the new
        -- slot takes its own reference iff source is a heap
        -- borrow). Self-move slots skip store + inc entirely.
        storeField (fld, i)
          | isSelfMoveAt (i + 1) = []
          | otherwise =
              [LocalGet (fromIntegral nSlot)]
                <> emitExprI ctx fld
                <> [I32Store (MemArg 2 ((i + 1) * 4 :: Int))]
                <> incStoredFieldI ctx nSlot (i + 1) fld
        fieldCode = concatMap storeField (zip fields [0 :: Int ..])
        -- return pointer
        retCode = [LocalGet (fromIntegral nSlot)]
     in decOldCode <> tagCode <> fieldCode <> retCode

-- | After storing a ptr value at @conSlot + slotIdx*4@, if
-- the source expression's tail is a heap-borrow 'CVar', emit
-- @(call $__inc_ref (i32.load offset=slotIdx*4 conSlot))@. Mirrors
-- 'incIfCVarStored' in 'Awsum.Codegen.WASM' (text codegen).
incStoredFieldI :: ExprCtx -> Word32 -> Int -> CExpr -> [WasmInstr]
incStoredFieldI ctx conSlot slotIdx fld
  | isHeapBorrow ctx fld =
      [LocalGet (fromIntegral conSlot)]
        <> [I32Load (MemArg 2 (slotIdx * 4 :: Int))]
        <> [CallIdx (fromIntegral idxIncRef)]
  | otherwise = []

-- | Emit a value and, when its tail is a heap-borrow
-- 'CVar', tee the result through @$__inc_ref_temp@ and call
-- @$__inc_ref@ before yielding the value back on the stack. Used
-- at user-CCall arg evaluation and 'CContinue' arg evaluation
-- where there's no destination slot to load back from.
emitArgWithIncI :: ExprCtx -> CExpr -> [WasmInstr]
emitArgWithIncI ctx fld
  | isHeapBorrow ctx fld =
      emitExprI ctx fld
        <> [LocalTee (fromIntegral ctx.ecIncRefTempSlot)]
        <> [CallIdx (fromIntegral idxIncRef)]
        <> [LocalGet (fromIntegral ctx.ecIncRefTempSlot)]
  | otherwise = emitExprI ctx fld

-- | Emit a case expression as nested if/else in binary WASM.
-- Stores scrutinee pointer to $__scrut, loads tag, then chains if/else arms.
emitCaseChainI :: ExprCtx -> CExpr -> [(Int, [Text], CExpr)] -> [WasmInstr]
emitCaseChainI _ctx _scrut [] = [I32Const 0] -- unreachable
emitCaseChainI ctx scrut alts =
  let scrutSlot = ctx.ecScrutSlot
      scrutFresh = isNothing (sourceCVarBin scrut)
      scrutName = sourceCVarBin scrut
      -- evaluate scrutinee and store to scrut local
      storeCode =
        emitExprI ctx scrut
          <> [LocalSet (fromIntegral scrutSlot)]
   in storeCode <> emitArmChainI ctx scrutName scrutFresh alts

-- | Dec the scrut after 'bindArmVars' has extracted the
-- arm's binders. Case-binders were inc'd at extract so their cells
-- survive even if cascade-free of scrut decs the slot-ref. Only
-- fires when @scrutFresh@ — borrowed scruts (CVar source) keep
-- their original owner.
scrutDecAfterBindI :: ExprCtx -> Bool -> [WasmInstr]
scrutDecAfterBindI ctx scrutFresh
  | scrutFresh =
      [LocalGet (fromIntegral ctx.ecScrutSlot)]
        <> [CallIdx (fromIntegral idxFreeRecursive)]
  | otherwise = []

-- | Emit the if/else chain for case arms (scrutinee already in $__scrut).
-- @scrutFresh@ marks whether the scrut is a fresh allocation that
-- must be dec'd after each arm's bindArmVars (no other owner once
-- the case completes). @scrutName@ is the binder name of the
-- scrutinee when it's a 'CVar' — recorded in
-- 'ecArmPatternByScrut' so a nested 'CReuse' can detect
-- self-moves.
emitArmChainI :: ExprCtx -> Maybe Text -> Bool -> [(Int, [Text], CExpr)] -> [WasmInstr]
emitArmChainI _ctx _scrutName _scrutFresh [] = [I32Const 0]
emitArmChainI ctx scrutName scrutFresh [(_, vars, body)] =
  -- Last arm: bind vars and emit body, no tag comparison needed
  let (bindCode, ctx') = bindArmVarsI ctx vars
      ctx'' = recordArmPattern ctx' scrutName vars
   in bindCode <> scrutDecAfterBindI ctx scrutFresh <> emitExprI ctx'' body
emitArmChainI ctx scrutName scrutFresh ((tag, vars, body) : rest) =
  let scrutSlot = ctx.ecScrutSlot
      -- load tag from scrutinee container (i32 at offset 0)
      loadTag =
        [LocalGet (fromIntegral scrutSlot)]
          <> [I32Load (MemArg 2 (0 :: Int))]
      cmpCode =
        [I32Const tag]
          <> [I32Eq] -- i32.eq
      (bindCode, ctx') = bindArmVarsI ctx vars
      ctx'' = recordArmPattern ctx' scrutName vars
   in loadTag
        <> cmpCode
        <> [If BtI32]
        <> bindCode
        <> scrutDecAfterBindI ctx scrutFresh
        <> emitExprI ctx'' body
        <> [Else]
        <> emitArmChainI ctx scrutName scrutFresh rest
        <> [End]

-- | Bind case arm variables: load fields from scrutinee container into locals.
-- The returned context advances 'ecBoundBase' past the fresh slots so any
-- nested 'CCase' inside the arm body allocates beyond the still-live outer
-- bindings. Slot demand is bounded by 'exprMaxBoundVars' (sum across the
-- deepest nesting path).
bindArmVarsI :: ExprCtx -> [Text] -> ([WasmInstr], ExprCtx)
bindArmVarsI ctx vars =
  let base = ctx.ecBoundBase
      scrutSlot = ctx.ecScrutSlot
      bindOne v i =
        let slot = base + fromIntegral i
            offset = (i + 1) * 4 :: Int
            -- Inc each extracted ptr-binder so the local
            -- binding takes its own ref. The matching dec at arm
            -- end is the 'CDrop' wrap that 'Awsum.Lifetime' adds.
            bc =
              [LocalGet (fromIntegral scrutSlot)]
                <> [I32Load (MemArg 2 offset)]
                <> [LocalSet (fromIntegral slot)]
                <> [LocalGet (fromIntegral slot)]
                <> [CallIdx (fromIntegral idxIncRef)]
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

emitTailI :: Word32 -> [Text] -> Word32 -> ExprCtx -> CExpr -> [WasmInstr]
emitTailI tcoTempBase params depth ctx =
  emitTailPendingI tcoTempBase params depth ctx [] 0

-- | Emit `(call $__free_recursive (local.get freshScrutSlot[i]))`
-- for every fresh-scrut stash slot in current scope (depths 0..n-1).
-- Slots live at `ecFreshScrutBase + i`.
emitFreshScrutDecsI :: ExprCtx -> Int -> [WasmInstr]
emitFreshScrutDecsI ctx freshScrutDepth =
  concat
    [ [LocalGet (fromIntegral (ctx.ecFreshScrutBase + fromIntegral i))]
        <> [CallIdx (fromIntegral idxFreeRecursive)]
    | i <- [0 .. freshScrutDepth - 1]
    ]

-- | Emit a non-'CLoop' 'CFunDef' body with value-tail
-- param decs. Walks the tail-form and emits dec at each terminal,
-- with per-arm
-- precision for 'CCase'/'CRowCase' bodies so an arm returning a
-- 'CVar' param is "moved" out instead of being freed.
emitNonLoopBodyI :: ExprCtx -> [Text] -> CExpr -> [WasmInstr]
emitNonLoopBodyI ctx0 params = go ctx0 [] 0
  where
    go :: ExprCtx -> [Text] -> Int -> CExpr -> [WasmInstr]
    go ctx pending freshScrutDepth = \case
      CCase scrut alts ->
        let sorted = sortWith (\(t, _, _) -> t) alts
            scrutFresh = isNothing (sourceCVarBin scrut)
            scrutName = sourceCVarBin scrut
            freshStashSlot = ctx.ecFreshScrutBase + fromIntegral freshScrutDepth
            scrutCode =
              if scrutFresh
                then
                  emitExprI ctx scrut
                    <> [LocalTee (fromIntegral freshStashSlot)]
                    <> [LocalSet (fromIntegral ctx.ecScrutSlot)]
                else
                  emitExprI ctx scrut
                    <> [LocalSet (fromIntegral ctx.ecScrutSlot)]
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
            scrutDecs = emitFreshScrutDecsI ctx freshScrutDepth
         in drainPendingI ctx toDec (scrutDecs <> emitExprI ctx other)

    -- Per-arm dec: each arm body emits its own (potentially
    -- different) param decs based on its own tail-form. Each arm
    -- self-terminates with a value (the function's 'if (result
    -- i32) ...' chain unifies them through WASM's structured
    -- control flow).
    goCaseChain :: ExprCtx -> Maybe Text -> [Text] -> Int -> [(Int, [Text], CExpr)] -> [WasmInstr]
    goCaseChain _ _ _ _ [] = [I32Const 0] -- unreachable
    goCaseChain ctx scrutName pending freshScrutDepth [(_, vars, body)] =
      let (bindCode, ctx') = bindArmVarsI ctx vars
          ctx'' = recordArmPattern ctx' scrutName vars
       in bindCode <> go ctx'' pending freshScrutDepth body
    goCaseChain ctx scrutName pending freshScrutDepth ((tag, vars, body) : rest) =
      [LocalGet (fromIntegral ctx.ecScrutSlot)]
        <> [I32Load (MemArg 2 0)]
        <> [I32Const tag]
        <> [I32Eq]
        <> [If BtI32]
        <> ( let (bindCode, ctx') = bindArmVarsI ctx vars
                 ctx'' = recordArmPattern ctx' scrutName vars
              in bindCode <> go ctx'' pending freshScrutDepth body
           )
        <> [Else]
        <> goCaseChain ctx scrutName pending freshScrutDepth rest
        <> [End]

-- | Walk a tail-position expression, accumulating 'CDrop' binders into
-- a 'pending' stack drained at every terminator (CContinue / value).
-- 'CCase' arms inherit the same 'pending' through 'emitTailArmChainI'.
-- @freshScrutDepth@ counts how many fresh case-scrutinees are
-- currently stashed in `ecFreshScrutBase`-indexed slots; each
-- terminator dec's them.
emitTailPendingI :: Word32 -> [Text] -> Word32 -> ExprCtx -> [Text] -> Int -> CExpr -> [WasmInstr]
emitTailPendingI tcoTempBase params depth ctx pending freshScrutDepth = \case
  CContinue newArgs ->
    let -- Buffer each new arg into the scratch slot (so a new value
        -- that reads an old param sees the pre-update value).
        evals =
          concat
            [ emitExprI ctx a
                <> [LocalSet (fromIntegral (tcoTempBase + fromIntegral i))]
            | (i, a) <- zip [0 :: Int ..] newArgs
            ]
        -- Inc each ptr-arg whose source is a CVar (borrow
        -- → the next-iter slot takes its own ref). Fresh sources
        -- carry their @+1@ from @$__alloc@.
        incs =
          concat
            [ case sourceCVarBin a of
                Just _ ->
                  [LocalGet (fromIntegral (tcoTempBase + fromIntegral i))]
                    <> [CallIdx (fromIntegral idxIncRef)]
                Nothing -> []
            | (i, a) <- zip [0 :: Int ..] newArgs
            ]
        scrutDecs = emitFreshScrutDecsI ctx freshScrutDepth
        frees = concatMap (emitFreeOfI ctx) pending
        paramSlots =
          [ fromMaybe (error $ "WASM Assemble: no param slot for " <> show p) (Map.lookup p ctx.ecParams)
          | p <- params
          ]
        copies =
          concat
            [ [LocalGet (fromIntegral (tcoTempBase + fromIntegral i))]
                <> [LocalSet (fromIntegral ps)]
            | (i, ps) <- zip [0 :: Int ..] paramSlots
            ]
     in evals <> incs <> scrutDecs <> frees <> copies <> [Br (fromIntegral depth)]
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
              emitExprI ctx scrut
                <> [LocalTee (fromIntegral freshStashSlot)]
                <> [LocalSet (fromIntegral ctx.ecScrutSlot)]
            else
              emitExprI ctx scrut
                <> [LocalSet (fromIntegral ctx.ecScrutSlot)]
        freshScrutDepth' = if scrutFresh then freshScrutDepth + 1 else freshScrutDepth
     in scrutCode <> emitTailArmChainI tcoTempBase params depth ctx scrutName pending freshScrutDepth' sorted
  -- Push the drop onto the pending stack; drain at terminator.
  CDrop _ n body -> emitTailPendingI tcoTempBase params depth ctx (n : pending) freshScrutDepth body
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
        scrutDecs = emitFreshScrutDecsI ctx freshScrutDepth
     in drainPendingI ctx toDec (scrutDecs <> emitExprI ctx other)

-- | Drain pending drops at a value-producing tail. Wraps the value
-- expression in @(block (result i32) (local.set $__drop_tmp …) …frees…
-- (local.get $__drop_tmp))@. Empty pending → no wrapping.
drainPendingI :: ExprCtx -> [Text] -> [WasmInstr] -> [WasmInstr]
drainPendingI _ [] valueBytes = valueBytes
drainPendingI ctx pending valueBytes =
  [Block BtI32]
    <> valueBytes
    <> [LocalSet (fromIntegral ctx.ecDropTmpSlot)]
    <> concatMap (emitFreeOfI ctx) pending
    <> [LocalGet (fromIntegral ctx.ecDropTmpSlot)]
    <> [End]

-- | Emit @(call $__free_recursive (local.get $<binder>))@.
-- The binder must be a function param ('ecParams') or a
-- case-pattern binder ('ecLocals') already in scope.
emitFreeOfI :: ExprCtx -> Text -> [WasmInstr]
emitFreeOfI ctx n =
  let slot = lookupBinderSlot ctx n
   in [LocalGet (fromIntegral slot)]
        <> [CallIdx (fromIntegral idxFreeRecursive)]

-- | Tail version of 'emitArmChainI': each arm is emitted in tail form so
-- it either produces an @i32@ result or terminates with a @br@ back to
-- the loop. Nesting into an @opIf@ increases 'depth' by one for both the
-- then-body and the else-continuation.
emitTailArmChainI :: Word32 -> [Text] -> Word32 -> ExprCtx -> Maybe Text -> [Text] -> Int -> [(Int, [Text], CExpr)] -> [WasmInstr]
emitTailArmChainI _ _ _ _ _ _ _ [] = [I32Const 0]
emitTailArmChainI tcoTempBase params depth ctx scrutName pending freshScrutDepth [(_, vars, body)] =
  let (bindCode, ctx') = bindArmVarsI ctx vars
      ctx'' = recordArmPattern ctx' scrutName vars
   in bindCode <> emitTailPendingI tcoTempBase params depth ctx'' pending freshScrutDepth body
emitTailArmChainI tcoTempBase params depth ctx scrutName pending freshScrutDepth ((tag, vars, body) : rest) =
  let scrutSlot = ctx.ecScrutSlot
      loadTag =
        [LocalGet (fromIntegral scrutSlot)]
          <> [I32Load (MemArg 2 0)]
      cmpCode =
        [I32Const tag]
          <> [I32Eq] -- i32.eq
      (bindCode, ctx') = bindArmVarsI ctx vars
      ctx'' = recordArmPattern ctx' scrutName vars
   in loadTag
        <> cmpCode
        <> [If BtI32]
        <> bindCode
        <> emitTailPendingI tcoTempBase params (depth + 1) ctx'' pending freshScrutDepth body
        <> [Else]
        <> emitTailArmChainI tcoTempBase params (depth + 1) ctx scrutName pending freshScrutDepth rest
        <> [End]

-- | The WAT label for a user declaration — mirrors the text codegen's @mangle@
--   (@v_@ prefix, non-identifier chars to @_@). Only the text projection
--   ('renderWat') consumes @wfName@; the binary ignores it.
userFuncLabel :: Text -> Text
userFuncLabel n = "v_" <> T.map (\c -> if Char.isAlphaNum c || c == '_' || c == '\'' then c else '_') n

-- | Builds a user declaration's 'WasmFunc' so both the binary and text
--   projections derive from it. The body uses the '*I'
--   emitters. @wfName@ carries the raw Core name; the text projection mangles
--   it. @wfParams@/@wfResults@ feed the WAT header only — the type/function
--   sections are built elsewhere from the same arities.
userDeclFunc :: WasmInfo -> Map FuncType Word32 -> CDecl -> WasmFunc
userDeclFunc info typeMap = \case
  CFunDef nm args (CLoop body) ->
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
        ctx = userExprCtx info typeMap paramMap conBaseSlot scrutSlot boundBase dropTmpSlot incRefTempSlot freshScrutBase
     in WasmFunc
          { wfName = userFuncLabel nm,
            wfParams = replicate (length args) I32,
            wfResults = [I32],
            wfLocals = replicate nExtraLocals I32,
            wfBody = [Loop BtI32] <> emitTailI tcoTempBase args 0 ctx body <> [End]
          }
  CFunDef nm args body ->
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
        ctx = userExprCtx info typeMap paramMap conBaseSlot scrutSlot boundBase dropTmpSlot incRefTempSlot freshScrutBase
     in WasmFunc
          { wfName = userFuncLabel nm,
            wfParams = replicate (length args) I32,
            wfResults = [I32],
            wfLocals = replicate nExtraLocals I32,
            wfBody = emitNonLoopBodyI ctx args body
          }
  CValDef nm rhs ->
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
        ctx = userExprCtx info typeMap Map.empty conBaseSlot scrutSlot boundBase dropTmpSlot incRefTempSlot freshScrutBase
     in WasmFunc
          { wfName = userFuncLabel nm,
            wfParams = [],
            wfResults = [I32],
            wfLocals = replicate nExtraLocals I32,
            wfBody = emitExprI ctx rhs
          }

-- | Shared 'ExprCtx' constructor for 'userDeclFunc' (factors out the identical
--   record build across the three 'CDecl' shapes).
userExprCtx :: WasmInfo -> Map FuncType Word32 -> Map Text Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> Word32 -> ExprCtx
userExprCtx info typeMap paramMap conBaseSlot scrutSlot boundBase dropTmpSlot incRefTempSlot freshScrutBase =
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

-- | Binary projection of a user declaration: the 'WasmFunc' → bytes. The
--   text projection ('Awsum.Codegen.WASM') renders the same 'userDeclFunc'
--   value, so the two cannot diverge.
codeUserDecl :: WasmInfo -> Map FuncType Word32 -> CDecl -> [Word8]
codeUserDecl info typeMap decl = assembleFunc runtimeFuncIdx (userDeclFunc info typeMap decl)
