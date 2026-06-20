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
    -- projections emit the same gated 'WasmFunc' list and resolve calls
    -- through one shared name→index map (no dual emitter).
    funcIdxMap,
    WasmInfo (wiGatedHelpers),
    buildInfo,
    buildTypeSection,
    userDeclFunc,
    startFunc,
  )
where

import Awsum.Codegen.WASM.Instr (BlockType (..), MemArg (..), ValType (..), WasmFunc (..), WasmInstr (..), addI32Spec, addU32Spec, addU8Spec, allocShapedSpec, allocSpec, boxI32Spec, byteToHexSpec, concatSpec, entryArgEitherSpec, eqI32Spec, eqStringSpec, freeRecursiveSpec, freeSpec, freeWorklistPushSpec, getArgsSpec, incRefSpec, lengthCodePointsSpec, lengthUtf16CodeUnitsSpec, lengthUtf8BytesSpec, maxLocalsOf, memcmpSpec, memcpySpec, mulI32Spec, mulU32Spec, mulU8Spec, negI32Spec, parseInt32Spec, parseUInt32Spec, parseUInt8Spec, predI32Spec, predU32Spec, predU8Spec, printSpec, readStdinSpec, showI32Spec, showU32Spec, splitOnFirstSpec, stdinDecodeStrictSpec, stdinReadAllBytesSpec, stdinReadAllSpec, subI32Spec, subU32Spec, subU8Spec, succI32Spec, succU32Spec, succU8Spec, utf16OfRangeSpec)
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
    -- The runtime helpers this program actually needs (reachable from user
    -- code + _start), in canonical order. Both projections emit exactly these.
    wiGatedHelpers :: [WasmFunc],
    -- Function indices (imports, then gated helpers, then user decls, then
    -- _start). Resolves every 'Call' by name in both projections.
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

buildInfo :: PreludeTags -> CoreProgram -> WasmInfo
buildInfo ptags prog@(CoreProgram decls) =
  let (pool, _emptyOff, heapStart) = buildStringPool prog
      valNames = Set.fromList [n | CValDef n _ <- decls]
      funNames = Set.fromList [n | CFunDef n _ _ <- decls]
      arities = Map.fromList [(n, length as) | CFunDef n as _ <- decls]
      funList = [n | CFunDef n _ _ <- decls]
      tableMap = Map.fromList (zip funList [0 :: Int ..])
      indArities = collectIndirectArities prog funNames
      -- Build the user functions and _start first (they 'Call' helpers by
      -- name, not index), then keep only the runtime helpers reachable from
      -- them. 'info0' carries everything 'userDeclFunc' needs except the index
      -- map, which depends on how many helpers survive gating.
      info0 =
        WasmInfo
          { wiStringPool = pool,
            wiHeapStart = heapStart,
            wiValDefs = valNames,
            wiFunDefs = funNames,
            wiArities = arities,
            wiTableMap = tableMap,
            wiFunList = funList,
            wiIndirectArities = indArities,
            wiGatedHelpers = [],
            wiFuncIdx = Map.empty,
            wiTags = ptags
          }
      typeMap = snd (buildTypeSection info0 prog)
      userFuncs = [userDeclFunc info0 typeMap d | d <- decls]
      gated = reachableHelpers (runtimeHelperFuncs ptags) (userFuncs <> [startFunc])
      userStart = importCount + fromIntegral (length gated)
      helperIdx = [(wfName f, importCount + fromIntegral i) | (i, f) <- zip [0 :: Int ..] gated]
      userIdx = [(declName d, userStart + fromIntegral i) | (i, d) <- zip [0 :: Int ..] decls]
      startIdx = userStart + fromIntegral (length decls)
      imports = [("fd_write", 0), ("args_sizes_get", 1), ("args_get", 2), ("fd_read", 3)] :: [(Text, Word32)]
      funcIdx = Map.fromList (imports <> helperIdx <> userIdx <> [("_start", startIdx)])
   in info0 {wiGatedHelpers = gated, wiFuncIdx = funcIdx}

-- | All runtime helpers, in canonical index order. Each program emits the
--   reachable subset ('reachableHelpers').
runtimeHelperFuncs :: PreludeTags -> [WasmFunc]
runtimeHelperFuncs ptags =
  [ allocSpec,
    freeSpec,
    memcpySpec,
    concatSpec ptags,
    printSpec ptags,
    boxI32Spec,
    byteToHexSpec,
    showI32Spec,
    showU32Spec,
    predI32Spec ptags,
    predU8Spec ptags,
    predU32Spec ptags,
    succI32Spec ptags,
    succU8Spec ptags,
    succU32Spec ptags,
    eqI32Spec ptags,
    addI32Spec ptags,
    subI32Spec ptags,
    mulI32Spec ptags,
    negI32Spec ptags,
    addU8Spec ptags,
    subU8Spec ptags,
    mulU8Spec ptags,
    addU32Spec ptags,
    subU32Spec ptags,
    mulU32Spec ptags,
    splitOnFirstSpec ptags,
    parseInt32Spec ptags,
    parseUInt8Spec ptags,
    parseUInt32Spec ptags,
    lengthCodePointsSpec,
    lengthUtf16CodeUnitsSpec,
    lengthUtf8BytesSpec,
    entryArgEitherSpec ptags,
    utf16OfRangeSpec,
    getArgsSpec ptags,
    readStdinSpec,
    stdinReadAllSpec,
    stdinReadAllBytesSpec ptags,
    stdinDecodeStrictSpec ptags,
    allocShapedSpec,
    incRefSpec,
    freeRecursiveSpec,
    freeWorklistPushSpec,
    memcmpSpec,
    eqStringSpec ptags
  ]

-- | The runtime helpers reachable from @roots@ (user functions + @_start@):
--   every helper a root calls, transitively closed over helper-to-helper
--   calls. The result keeps the canonical order of @candidates@. Import calls
--   (WASI) are not helpers and drop out of the intersection.
reachableHelpers :: [WasmFunc] -> [WasmFunc] -> [WasmFunc]
reachableHelpers candidates roots =
  let byName = Map.fromList [(wfName f, f) | f <- candidates]
      helperNames = Map.keysSet byName
      callsOf f = Set.fromList [n | Call n <- wfBody f]
      go acc todo
        | Set.null todo = acc
        | otherwise =
            let acc' = acc <> todo
                deps = Set.unions [callsOf f | n <- Set.toList todo, Just f <- [Map.lookup n byName]]
                next = Set.intersection deps helperNames Set.\\ acc'
             in go acc' next
      reached = go Set.empty (Set.intersection (Set.unions (map callsOf roots)) helperNames)
   in filter (\f -> Set.member (wfName f) reached) candidates

-- | A function's WASM type: parameter count + whether it returns a value.
funcTypeOf :: WasmFunc -> FuncType
funcTypeOf f = FuncType (length (wfParams f)) (not (null (wfResults f)))

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
  CDrop _ body -> stringsInExpr body
  CReuse _ _ _ fs -> concatMap stringsInExpr fs
  CLet _ rhs body -> stringsInExpr rhs <> stringsInExpr body
  CProj _ _ -> []
  CJoin _ _ body inner -> stringsInExpr body <> stringsInExpr inner
  CJump _ args -> concatMap stringsInExpr args

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
      CJoin _ _ body inner -> collectInExpr fns params body <> collectInExpr fns params inner
      CJump _ args -> concatMap (collectInExpr fns params) args
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
buildFunctionSection info typeMap (CoreProgram decls) =
  let -- Local functions: gated runtime helpers + user decls + _start, each by
      -- its type index. The order matches 'buildCodeSection' / 'wiFuncIdx'.
      localTypes =
        [lookupType (funcTypeOf f) typeMap | f <- info.wiGatedHelpers]
          <> [lookupType (funcTypeOfDecl d) typeMap | d <- decls]
          <> [lookupType (FuncType 0 False) typeMap] -- _start
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
        -- Gated runtime helpers, then user declarations, then _start — the same
        -- order as 'wiFuncIdx' and 'buildFunctionSection'.
        [assembleFunc (funcIdxMap info) f | f <- info.wiGatedHelpers]
          <> map (codeUserDecl info typeMap) decls
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

-- | The full name→index map for a program (imports, gated runtime helpers,
--   user declarations, @_start@). Every 'Call' in both projections resolves
--   through this; helper indices reflect the gated set.
funcIdxMap :: WasmInfo -> Map Text Word32
funcIdxMap = wiFuncIdx

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

-- __concat(a: i32, b: i32) -> i32
-- Length-prefixed concat. O(1) cap-check via header.
-- Locals (after 2 params): $ba(2), $bb(3), $ua(4), $ub(5),

-- $usum(6), \$bsum(7), $stl(8), $cell(9), $buf(10).

-- __addInt32(pa: i32, pb: i32) -> i32
-- addInt32: Int32 -> Int32 -> Either ArithError Int32. Signed-overflow
-- detected via the XOR trick: '(a ^ s) & (b ^ s) < 0' (i32.lt_s 0)
-- holds iff the carry into the sign bit differs from the carry out.
-- Direction is read off 'a >= 0' (i32.ge_s 0) — same-sign overflow is
-- positive when a >= 0, negative otherwise. ArithError tags follow
-- Prelude.aww declaration order: Underflow=0, Overflow=1.
-- Locals: $a(2) $b(3) $s(4) $ae(5) $box(6) $cell(7).

-- __mulInt32(pa: i32, pb: i32) -> i32
-- mulInt32: Int32 -> Int32 -> Either ArithError Int32. Both operands
-- are sign-extended to i64, multiplied at long width, and the result
-- range-checked against [INT32_MIN, INT32_MAX] via 'i64.gt_s' and
-- 'i64.lt_s'. Direction: i64.gt_s → Overflow (tag 1), i64.lt_s →
-- Underflow (tag 0). On the ok path, 'i32.wrap_i64' truncates back
-- to i32 — faithful when the result is in i32 range by the comparison.
-- Locals (after the two i32 params): $p (i64, slot 2),

-- $ae(i32, slot 3), $box(i32, slot 4), $cell(i32, slot 5).

-- __splitOnFirst(sep: i32, str: i32) -> i32
-- splitOnFirst: String -> String -> Maybe (Tuple2 String String). Hand-
-- rolled byte scan since WASM has no built-in substring search. The
-- empty-separator and "separator longer than str" cases are handled
-- implicitly by the loop bounds.
-- Locals (beyond the two params): $sep_len(2) $str_len(3) $i(4) $j(5)
-- pos(6) $match(7) $prefix(8) $suffix(9) $tuple(10) $cell(11)

-- $suf_len(12) \$u16(13).

-- __parseUInt32(s: i32) -> i32
-- Same shape as 'codeParseUInt8' but with an i64 accumulator (running
-- magnitude up to 4294967295 * 10 + 9 = 42949672959 fits in i64) and
-- a '> 4294967295' fast-fail check. On the ok path the i64 accumulator
-- is wrapped to i32 — the bit pattern of values 0..4294967295 in i64
-- and i32-as-u32 is identical.
-- Locals: $len(1, i32) $i(2, i32) $c(3, i32) $box(4, i32) $cell(5, i32)

-- $pe(6, i32) $failed(7, i32) $acc(8, i64).

-- __lengthUtf16CodeUnits(s: i32) -> i32
-- Walks UTF-8 bytes; counts 1 for every codepoint start except 4-byte
-- starts (top five bits = 11110), which need a UTF-16 surrogate pair
-- and contribute 2. Continuation bytes are skipped. Locals:

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

-- ════════════════════════════════════════════════════════════════════════════
-- User declaration code
-- ════════════════════════════════════════════════════════════════════════════

-- | A case scrutinee that is already a named local or parameter is
-- dispatched in place — tag reads and binder extraction go through the
-- variable's own slot, with no copy into a scrutinee local. The copy is
-- refcount-neutral (a borrowed 'CVar' scrut is never inc'd), so eliding it
-- is too. Anything else — calls, constructions, drop/let-wrapped tails,
-- and a 'CVar' naming a global (a 'CValDef' getter call or fn-table
-- index) — evaluates once into a fresh local ('scrutDispatchI').
scrutInPlace :: Set Text -> Set Text -> CExpr -> Bool
scrutInPlace valDefs funDefs = \case
  CVar n -> not (Set.member n valDefs || Set.member n funDefs)
  _ -> False

-- _start: builds the IO tree via v_main and hands it to v_runIO,
-- dropping the Unit result. 'main' takes no arguments; user code reads
-- argv through 'IO.Args.getArgs' inside the IO chain (lowers to an
-- 'IOGetArgs' constructor whose runIO arm calls '__getArgs').

-- | @_start@ as a 'WasmFunc'. @v_main@ is a zero-arg value (CValDef) building the
--   IO tree; @runIO@ walks it for effects and returns Unit (discarded). User
--   code reads argv through @IO.Args.getArgs@ inside the chain (an @IOGetArgs@
--   constructor whose runIO arm calls @__getArgs@). Void result.
startFunc :: WasmFunc
startFunc =
  WasmFunc
    { wfName = "_start",
      wfParams = [],
      wfResults = [],
      wfLocals = [],
      wfBody = [Call "main", Call "runIO", Drop]
    }

codeStart :: WasmInfo -> [Word8]
codeStart info = assembleFunc (funcIdxMap info) startFunc

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
    ecTypeMap :: Map FuncType Word32,
    ecIndirectArities :: Set Int,
    -- | Next free local slot. Every local — con-build temp, case scrutinee
    -- copy, arm binder, let binder, drop/inc-ref scratch, fresh-scrut stash,
    -- join parameter/result, TCO arg buffer — is drawn from here and the
    -- counter advanced for the scope the slot stays live in. Threaded
    -- functionally, so sibling scopes (case arms, a constructor's fields, a
    -- join's two branches) each start from the same value and reuse; the
    -- high-water mark, read back off the emitted stream by 'maxLocalsOf',
    -- sizes the @.locals@ vector. Starts at the parameter count (params
    -- occupy slots @0..nParams-1@).
    ecNextLocal :: Word32,
    -- | Linear-scrutinee elision: for each in-scope 'CCase' /
    -- 'CRowCase' whose scrutinee is a 'CVar n', records the arm's
    -- pattern variables. 'CReuse n t fs' inside the arm body
    -- checks @ecArmPatternByScrut[n]@ to detect self-move slots
    -- (@fs[i] == CVar vs[i]@) and skip their dec-old + inc-new
    -- + store entirely — the slot's pointer is already what we
    -- wanted.
    ecArmPatternByScrut :: Map Text [Text],
    -- | Join lowering: name → dedicated local slot for each in-scope join
    -- parameter, populated at each 'CJoin' node (its parameters and result
    -- local are drawn from 'ecNextLocal' on entry). The in-scope jump targets
    -- ('ecJoinTargets') carry the structural level the join's body block sits
    -- at plus the pending\/fresh-scrut baselines recorded at the node (a jump
    -- releases exactly what accumulated since).
    ecJoinParamSlots :: Map Text Word32,
    ecJoinTargets :: Map Text WJoinTarget,
    -- | @Just (resultSlot, afterLevel)@ while a tail walk is inside a
    -- 'CJoin' (either branch): a value terminal stores into the result
    -- local and branches to the after block instead of yielding by
    -- fallthrough — so the dispatch chains are 'BtVoid' there (every
    -- path leaves by 'Br').
    ecTailJoin :: Maybe (Word32, Word32)
  }

-- | Branch target of an in-scope 'CJoin' in the WASM emitters. @wjLevel@
-- is the walk's block-nesting counter measured /inside/ the join's body
-- block — a 'CJump' at counter @d@ branches @d − wjLevel@ levels out to
-- reach it, and a bypass value branches one further to the after block.
data WJoinTarget = WJoinTarget
  { wjLevel :: Word32,
    wjParams :: [Text],
    wjPendingBase :: Int,
    wjScrutBase :: Int
  }

-- | Draw the next free local slot, advancing the counter so the slot stays
-- reserved for whatever scope the returned context threads into. A transient
-- temp whose lifetime spans no sub-emission (a drop or inc-ref scratch) reads
-- @ctx.ecNextLocal@ directly without advancing — nothing live can collide.
freshLocal :: ExprCtx -> (Word32, ExprCtx)
freshLocal ctx = (ctx.ecNextLocal, ctx {ecNextLocal = ctx.ecNextLocal + 1})

-- | Draw @n@ consecutive free local slots (@n == 0@ yields none).
freshLocals :: Int -> ExprCtx -> ([Word32], ExprCtx)
freshLocals n ctx
  | n <= 0 = ([], ctx)
  | otherwise = (take n [ctx.ecNextLocal ..], ctx {ecNextLocal = ctx.ecNextLocal + fromIntegral n})

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
  -- The move shape — a drop returning its own binder — leaves the
  -- 'CDrop' emission /owned/ (the move-inc fired before the dec), so it
  -- is not a borrow source. Any other tail passes through, as does a
  -- let's body.
  CDrop n body -> case sourceCVarBin body of
    Just m | m == n -> Nothing
    other -> other
  CLet _ _ body -> sourceCVarBin body
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
  -- Mirrors 'sourceCVarBin': the move shape leaves the drop owned.
  CDrop n body -> case sourceCVarBin body of
    Just m | m == n -> False
    _ -> isHeapBorrow ctx body
  CLet _ _ body -> isHeapBorrow ctx body
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
        [Call n]
    | n `Set.member` ctx.ecFunDefs ->
        let tblIdx = fromMaybe 0 (Map.lookup n ctx.ecTableMap)
         in [I32Const tblIdx]
    | otherwise ->
        [I32Const 0]
  CBuiltIn _ ->
    [I32Const 0] -- invariant: not a standalone term; dispatched from CCall
    -- Bind: evaluate the rhs into a fresh bound-vars slot. A heap-borrow rhs
    -- ('CVar' of a param/binder) incs so the binding owns its own ref — the
    -- same discipline as a stored cell field ('incStoredFieldI'); a fresh
    -- source transfers its @+1@. The matching dec is the binder's 'CDrop'.
  CLet x rhs body ->
    let (bindCode, ctx') = bindLetI ctx x rhs
     in bindCode <> emitExprI ctx' body
  -- Load slot @slot@ of cell @n@ and take an owning ref (tee through
  -- @$__inc_ref@, like 'emitArgWithIncI'). The inc matches the extract-inc
  -- the un-inlined binder would get; the binder is skipped in
  -- 'bindArmVarsI' and gets no 'CDrop', so the net refcount is unchanged.
  CProj n slot ->
    -- A leaf inc-ref scratch: the field load is already on the stack, so the
    -- next free slot is safe to borrow without advancing the counter.
    let tmp = ctx.ecNextLocal
     in emitExprI ctx (CVar n)
          <> [I32Load (MemArg 2 (slot * 4 :: Int))]
          <> [LocalTee (fromIntegral tmp)]
          <> [Call "__inc_ref"]
          <> [LocalGet (fromIntegral tmp)]
  CIntLit n _ ->
    let n32 = fromInteger n :: Int32
     in [I32Const (fromIntegral n32)]
          <> [Call "__box_i32"]
  CCon tag fields ->
    let nSlots = 1 + length fields
        nFields = length fields
        -- The cell pointer lives in 'conSlot' across every field's evaluation
        -- (a nested 'CCon' draws its own from the advanced counter); the
        -- fields are sequential, so they reuse everything above 'conSlot'.
        (conSlot, nestedCtx) = freshLocal ctx
        -- Allocate (nSlots * 4) bytes with shape inline
        -- via '$__alloc_shaped(size, shape)'.
        allocCode =
          [I32Const (nSlots * 4)]
            <> [I32Const nFields]
            <> [Call "__alloc_shaped"]
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
              <> [Call "__print"]
      -- 'BuiltIn.internalGetArgs' — call '__getArgs', which re-reads
      -- argv via WASI 'args_get' and routes the result through
      -- '__entryArgEither'.
      CBuiltIn "internalGetArgs"
        | [] <- xs ->
            [Call "__getArgs"]
      -- 'BuiltIn.internalStdinReadAllString' — call '__stdinReadAll',
      -- which consumes fd 0 to EOF via WASI 'fd_read' and strict-UTF-8
      -- decodes the bytes via '__stdinDecodeStrict'.
      CBuiltIn "internalStdinReadAllString"
        | [] <- xs ->
            [Call "__stdinReadAll"]
      -- 'BuiltIn.internalStdinReadAllBytes' — call '__stdinReadAllBytes',
      -- which consumes fd 0 to EOF and returns the raw bytes as 'List UInt8'.
      CBuiltIn "internalStdinReadAllBytes"
        | [] <- xs ->
            [Call "__stdinReadAllBytes"]
      CBuiltIn name
        | name == "showInt32" || name == "showUInt8",
          [x] <- xs ->
            emitArgWithIncI ctx x
              <> [Call "__show_i32"]
      CBuiltIn "byteToHexStringNoPrefix"
        | [x] <- xs ->
            emitArgWithIncI ctx x
              <> [Call "__byteToHex"]
      CBuiltIn "showUInt32"
        | [x] <- xs ->
            emitArgWithIncI ctx x
              <> [Call "__show_u32"]
      CBuiltIn "predInt32"
        | [x] <- xs ->
            emitArgWithIncI ctx x
              <> [Call "__predInt32"]
      CBuiltIn "predUInt8"
        | [x] <- xs ->
            emitArgWithIncI ctx x
              <> [Call "__predUInt8"]
      CBuiltIn "predUInt32"
        | [x] <- xs ->
            emitArgWithIncI ctx x
              <> [Call "__predUInt32"]
      CBuiltIn "succInt32"
        | [x] <- xs ->
            emitArgWithIncI ctx x
              <> [Call "__succInt32"]
      CBuiltIn "succUInt8"
        | [x] <- xs ->
            emitArgWithIncI ctx x
              <> [Call "__succUInt8"]
      CBuiltIn "succUInt32"
        | [x] <- xs ->
            emitArgWithIncI ctx x
              <> [Call "__succUInt32"]
      CBuiltIn name
        | name == "eqInt32" || name == "eqUInt8" || name == "eqUInt32",
          [a, b] <- xs ->
            emitArgWithIncI ctx a
              <> emitArgWithIncI ctx b
              <> [Call "__eq_i32"]
      CBuiltIn "eqString"
        | [a, b] <- xs ->
            emitArgWithIncI ctx a
              <> emitArgWithIncI ctx b
              <> [Call "__eqString"]
      CBuiltIn name
        | name == "addInt32" || name == "addUInt8" || name == "addUInt32" || name == "subInt32" || name == "subUInt8" || name == "subUInt32" || name == "mulUInt8" || name == "mulUInt32" || name == "mulInt32",
          [a, b] <- xs ->
            emitArgWithIncI ctx a
              <> emitArgWithIncI ctx b
              <> [Call ("__" <> name)]
      CBuiltIn "negInt32"
        | [x] <- xs ->
            emitArgWithIncI ctx x
              <> [Call "__negInt32"]
      CBuiltIn "splitOnFirst"
        | [a, b] <- xs ->
            emitArgWithIncI ctx a
              <> emitArgWithIncI ctx b
              <> [Call "__splitOnFirst"]
      CBuiltIn name
        | name == "parseInt32" || name == "parseUInt8" || name == "parseUInt32",
          [x] <- xs ->
            emitArgWithIncI ctx x
              <> [Call ("__" <> name)]
      CBuiltIn name
        | name == "lengthCodePoints" || name == "lengthUtf16CodeUnits" || name == "lengthUtf8Bytes",
          [x] <- xs ->
            emitArgWithIncI ctx x
              <> [Call ("__" <> name)]
      CBuiltIn "concatString"
        | [a, b] <- xs ->
            emitArgWithIncI ctx a
              <> emitArgWithIncI ctx b
              <> [Call "__concat"]
      CBuiltIn n ->
        error ("WASM codegen: unknown builtin '" <> n <> "' reached CCall (typecheck should have rejected it)")
      CVar n
        | n `Set.member` ctx.ecFunDefs ->
            -- User CCall — caller-side inc on each CVar
            -- ptr-arg (borrow that needs its own ref for the
            -- callee's param slot). Builtins above bypass this:
            -- they only READ args, never store them.
            concatMap (emitArgWithIncI ctx) xs
              <> [Call n]
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
  CDrop n body ->
    let bodyBytes = emitExprI ctx body
        slot = lookupBinderSlot ctx n
        -- A leaf scratch: the body's value is captured here while the dropped
        -- binder is freed. The body emitted on the same counter, so its slots
        -- are dead by now and this one is free to reuse.
        tmp = ctx.ecNextLocal
        moveInc = case sourceCVarBin body of
          Just m
            | m == n ->
                [LocalGet (fromIntegral tmp)]
                  <> [Call "__inc_ref"]
          _ -> []
     in [Block BtI32]
          <> bodyBytes
          <> [LocalSet (fromIntegral tmp)]
          <> moveInc
          <> [LocalGet (fromIntegral slot)]
          <> [Call "__free_recursive"]
          <> [LocalGet (fromIntegral tmp)]
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
  CReuse mode n tag fields ->
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
                <> [Call "__free_recursive"]
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
        inPlaceCode = decOldCode <> tagCode <> fieldCode <> retCode
     in case mode of
          -- A loop-private pack/continuation cell: in place, no branch.
          ReuseUnique -> inPlaceCode
          -- A user-visible cell: mutate only when the runtime refcount
          -- proves unique ownership (the caller may retain the
          -- structure); otherwise build the cell the reuse replaced and
          -- release this reference. The dec-olds preceding the field
          -- evaluation on the in-place leg are what make a /nested/
          -- guarded check meaningful, exactly as on LLVM: by the time an
          -- inner reuse runs its own check, this cell's slot reference
          -- to it is already released, so rc==1 iff nothing else holds
          -- it; on the copy leg no dec has happened and the inner copies
          -- too, leaving a shared original intact.
          ReuseGuarded ->
            [ LocalGet (fromIntegral nSlot),
              I32Const 8,
              I32Sub,
              I32Load (MemArg 2 (0 :: Int)),
              I32Const 1,
              I32Eq,
              If BtI32
            ]
              <> inPlaceCode
              <> [Else]
              <> emitExprI ctx (CCon tag fields)
              <> [LocalGet (fromIntegral nSlot), Call "__free_recursive"]
              <> [End]
  CJoin j ps body inner -> emitJoinExprI ctx j ps body inner
  CJump j _ -> error ("WASM Assemble: CJump to " <> j <> " in non-tail position — jumps live only in tail positions of their join's inner expression")

-- | After storing a ptr value at @conSlot + slotIdx*4@, if
-- the source expression's tail is a heap-borrow 'CVar', emit
-- @(call $__inc_ref (i32.load offset=slotIdx*4 conSlot))@. Mirrors
-- 'incIfCVarStored' in 'Awsum.Codegen.WASM' (text codegen).
incStoredFieldI :: ExprCtx -> Word32 -> Int -> CExpr -> [WasmInstr]
incStoredFieldI ctx conSlot slotIdx fld
  | isHeapBorrow ctx fld =
      [LocalGet (fromIntegral conSlot)]
        <> [I32Load (MemArg 2 (slotIdx * 4 :: Int))]
        <> [Call "__inc_ref"]
  | otherwise = []

-- | Emit a value and, when its tail is a heap-borrow
-- 'CVar', tee the result through @$__inc_ref_temp@ and call
-- @$__inc_ref@ before yielding the value back on the stack. Used
-- at user-CCall arg evaluation and 'CContinue' arg evaluation
-- where there's no destination slot to load back from.
emitArgWithIncI :: ExprCtx -> CExpr -> [WasmInstr]
emitArgWithIncI ctx fld
  | isHeapBorrow ctx fld =
      -- Leaf inc-ref scratch: the value is on the stack before the tee, so the
      -- next free slot is safe to borrow without advancing the counter.
      let tmp = ctx.ecNextLocal
       in emitExprI ctx fld
            <> [LocalTee (fromIntegral tmp)]
            <> [Call "__inc_ref"]
            <> [LocalGet (fromIntegral tmp)]
  | otherwise = emitExprI ctx fld

-- | Bind a 'CLet': evaluate the rhs into the next bound-vars slot (the same
-- region case-arm binders draw from; 'exprMaxBoundVars' sizes it), inc when
-- the rhs is a heap borrow, and return the context with the binder in scope.
-- Shared by the non-tail, loop-tail and value-tail emitters.
bindLetI :: ExprCtx -> Text -> CExpr -> ([WasmInstr], ExprCtx)
bindLetI ctx x rhs =
  let (slot, ctxN) = freshLocal ctx
      ctx' = ctxN {ecLocals = Map.insert x slot ctxN.ecLocals}
      incCode
        | isHeapBorrow ctx rhs = [LocalGet (fromIntegral slot), Call "__inc_ref"]
        | otherwise = []
   in (emitExprI ctx rhs <> [LocalSet (fromIntegral slot)] <> incCode, ctx')

-- | Expression-position join point (a cell field, a call argument, a
-- 'CLet' right-hand side — @main@'s fused IO chains are the dominant
-- shape). The construct is the same two void blocks the tail walks use,
-- with the value routed through the nesting-level result local: the inner
-- case's value arms store it and branch past the body to the after block,
-- its jump arms store the join parameters and branch to the body block;
-- the body's owned value (inc-if-borrow, the expression-position
-- invariant) lands in the same local, the join parameters are released
-- right after it — inc the new owner before the old one's dec — and the
-- whole construct yields by loading the local.
--
-- Jumps appear only at arm roots of the inner case (under the 'CDrop'
-- wrappers 'Awsum.Lifetime' adds; the case itself may sit under 'CLet'
-- bindings floated out of its scrutinee, each under its own 'CDrop'):
-- anything deeper would be a jump in non-tail position, which the node's
-- invariant excludes — so the block depths here are the emitter's own
-- if-chain levels, statically known. Releases accumulated above the
-- dispatch (a crossed 'CDrop' joins the pending list) and the fresh inner
-- scrutinee follow the existing expression-case discipline: released once
-- per path, uniformly on jump and value arms — the same discipline the
-- tail walks express through their @pending@ stacks.
emitJoinExprI :: ExprCtx -> Text -> [Text] -> CExpr -> CExpr -> [WasmInstr]
emitJoinExprI ctx j ps body inner =
  let (resSlot, ctxR) = freshLocal ctx
      (paramSlots, ctxN0) = freshLocals (length ps) ctxR
      psMap = Map.fromList (zip ps paramSlots)
      -- The result local and the join parameters are live across both
      -- branches; 'ecJoinParamSlots' carries the params so a jump in the inner
      -- expression finds them, 'ecLocals' so the body reads them as 'CVar'.
      ctxN = ctxN0 {ecJoinParamSlots = Map.union psMap ctxN0.ecJoinParamSlots}
      ctxB = ctxN {ecLocals = Map.union psMap ctxN.ecLocals}
      psDecs = concatMap (emitFreeOfI ctxB) ps
      bodyCode =
        emitArgWithIncI ctxB body
          <> [LocalSet (fromIntegral resSlot)]
          <> psDecs
      innerCode = goInner ctxN [] inner
   in [Block BtVoid, Block BtVoid]
        <> innerCode
        <> [End]
        <> bodyCode
        <> [End]
        <> [LocalGet (fromIntegral resSlot)]
  where
    goInner ctxN pending = \case
      CRowCase scrut alts -> goInner ctxN pending (CCase scrut [(fromIntegral t, [v], b) | (t, v, b) <- alts])
      CCase scrut alts ->
        let sorted = sortWith (\(t, _, _) -> t) alts
            scrutFresh = isNothing (sourceCVarBin scrut)
            scrutName = sourceCVarBin scrut
            (storeCode, dispatchSlot, ctxN') = scrutDispatchI ctxN scrut
         in storeCode
              <> armChain ctxN' pending dispatchSlot scrutName scrutFresh (0 :: Int) sorted
      -- A let floated out of the inner case's scrutinee wraps the whole
      -- inner expression: bind it and continue.
      CLet x rhs b ->
        let (letCode, ctx') = bindLetI ctxN x rhs
         in letCode <> goInner ctx' pending b
      -- A drop above the dispatch (a let binder whose scope is the whole
      -- inner expression): the dec joins the per-path releases below.
      CDrop n b -> goInner ctxN (n : pending) b
      -- Degenerate inner — the fusion's case collapsed afterwards to a
      -- bare jump or a plain value.
      other -> armBody ctxN pending (0 :: Int) other
    armChain _ _ _ _ _ _ [] = [Unreachable]
    armChain ctxN pending dispatchSlot scrutName scrutFresh lvl [(_, vars, b)] =
      let (bindCode, ctx') = bindArmVarsI ctxN dispatchSlot vars b
          ctx'' = recordArmPattern ctx' scrutName vars
       in bindCode <> scrutDecAfterBindI dispatchSlot scrutFresh <> armBody ctx'' pending lvl b
    armChain ctxN pending dispatchSlot scrutName scrutFresh lvl ((tag, vars, b) : rest) =
      [LocalGet (fromIntegral dispatchSlot)]
        <> [I32Load (MemArg 2 (0 :: Int))]
        <> [I32Const tag]
        <> [I32Eq]
        <> [If BtVoid]
        <> ( let (bindCode, ctx') = bindArmVarsI ctxN dispatchSlot vars b
                 ctx'' = recordArmPattern ctx' scrutName vars
              in bindCode <> scrutDecAfterBindI dispatchSlot scrutFresh <> armBody ctx'' pending (lvl + 1) b
           )
        <> [Else]
        <> armChain ctxN pending dispatchSlot scrutName scrutFresh (lvl + 1) rest
        <> [End]
    -- One inner-arm body at @lvl@ if-levels inside the body block. The
    -- @pending@ releases (drops crossed above the dispatch) fire on both
    -- paths: a jump after its argument incs, a value after its owned
    -- result.
    armBody ctxA pending lvl b0 =
      let resSlot = ctx.ecNextLocal
          pendingDecs = concatMap (emitFreeOfI ctxA) pending
       in case peelJoinDrops b0 of
            (dropped, CJump j' args)
              | j' == j ->
                  let evalStores =
                        concat
                          [ emitExprI ctxA a <> [LocalSet (fromIntegral (joinParamSlot ctxA q))]
                          | (a, q) <- zip args ps
                          ]
                      incs =
                        concat
                          [ [LocalGet (fromIntegral (joinParamSlot ctxA q)), Call "__inc_ref"]
                          | (a, q) <- zip args ps,
                            isHeapBorrow ctxA a
                          ]
                      dropDecs = concatMap (emitFreeOfI ctxA) dropped
                   in evalStores <> incs <> dropDecs <> pendingDecs <> [Br lvl]
              | otherwise -> error ("WASM Assemble: CJump to foreign join " <> j' <> " in expression position (pipeline bug)")
            _ ->
              emitArgWithIncI ctxA b0
                <> [LocalSet (fromIntegral resSlot)]
                <> pendingDecs
                <> [Br (lvl + 1)]

-- | Strip the 'CDrop' wrappers around a jumping arm body; the binders are
-- released at the jump, after the argument incs.
peelJoinDrops :: CExpr -> ([Text], CExpr)
peelJoinDrops = \case
  CDrop n b -> first (n :) (peelJoinDrops b)
  e -> ([], e)

-- | Dispatch source of a case: the variable's own slot when the scrutinee
-- is in place ('scrutInPlace'), with no store code; otherwise evaluate it
-- once into @$__scrut@. Must mirror 'exprNeedsScrutSlot', which sizes the
-- @$__scrut@ region at layout time. In-place reads are all emitted before
-- any arm-body code runs (tag compares chain ahead of the arms, binder
-- extraction opens the arm), so no rebind can come between them and the
-- dispatch.
scrutDispatchI :: ExprCtx -> CExpr -> ([WasmInstr], Word32, ExprCtx)
scrutDispatchI ctx scrut
  | scrutInPlace ctx.ecValDefs ctx.ecFunDefs scrut,
    CVar n <- scrut =
      case Map.lookup n ctx.ecLocals of
        Just slot -> ([], slot, ctx)
        Nothing -> case Map.lookup n ctx.ecParams of
          Just slot -> ([], slot, ctx)
          Nothing -> error $ "WASM Assemble: case scrutinee names unknown binder: " <> show n
  | otherwise =
      -- Evaluate the scrutinee once into its own fresh slot; the returned
      -- context keeps it reserved so the arms (which read it for tag and
      -- binder extraction) and any inner case draw beyond it.
      let (slot, ctx') = freshLocal ctx
       in (emitExprI ctx scrut <> [LocalSet (fromIntegral slot)], slot, ctx')

-- | Emit a case expression as nested if/else in binary WASM.
-- Resolves the dispatch slot ('scrutDispatchI'), loads tag, then chains
-- if/else arms.
emitCaseChainI :: ExprCtx -> CExpr -> [(Int, [Text], CExpr)] -> [WasmInstr]
emitCaseChainI _ctx _scrut [] = [I32Const 0] -- unreachable
emitCaseChainI ctx scrut alts =
  let scrutFresh = isNothing (sourceCVarBin scrut)
      scrutName = sourceCVarBin scrut
      (storeCode, dispatchSlot, ctx') = scrutDispatchI ctx scrut
   in storeCode <> emitArmChainI ctx' dispatchSlot scrutName scrutFresh alts

-- | Dec the scrut after 'bindArmVars' has extracted the
-- arm's binders. Case-binders were inc'd at extract so their cells
-- survive even if cascade-free of scrut decs the slot-ref. Only
-- fires when @scrutFresh@ — borrowed scruts (CVar source) keep
-- their original owner.
scrutDecAfterBindI :: Word32 -> Bool -> [WasmInstr]
scrutDecAfterBindI dispatchSlot scrutFresh
  | scrutFresh =
      [LocalGet (fromIntegral dispatchSlot)]
        <> [Call "__free_recursive"]
  | otherwise = []

-- | Emit the if/else chain for case arms (scrutinee readable from
-- @dispatchSlot@ — @$__scrut@ or the variable's own slot, per
-- 'scrutDispatchI'). @scrutFresh@ marks whether the scrut is a fresh
-- allocation that must be dec'd after each arm's bindArmVars (no other
-- owner once the case completes). @scrutName@ is the binder name of the
-- scrutinee when it's a 'CVar' — recorded in
-- 'ecArmPatternByScrut' so a nested 'CReuse' can detect
-- self-moves.
emitArmChainI :: ExprCtx -> Word32 -> Maybe Text -> Bool -> [(Int, [Text], CExpr)] -> [WasmInstr]
emitArmChainI _ctx _dispatchSlot _scrutName _scrutFresh [] = [I32Const 0]
emitArmChainI ctx dispatchSlot scrutName scrutFresh [(_, vars, body)] =
  -- Last arm: bind vars and emit body, no tag comparison needed.
  -- 'emitArgWithIncI' (not plain 'emitExprI') so an arm whose tail is a
  -- borrowed 'CVar' incs it on the way out — an expression-position case
  -- yields an /owned/ value for whatever consumes it, exactly as the call
  -- boundary it may have been inlined from would have.
  let (bindCode, ctx') = bindArmVarsI ctx dispatchSlot vars body
      ctx'' = recordArmPattern ctx' scrutName vars
   in bindCode <> scrutDecAfterBindI dispatchSlot scrutFresh <> emitArgWithIncI ctx'' body
emitArmChainI ctx dispatchSlot scrutName scrutFresh ((tag, vars, body) : rest) =
  let -- load tag from scrutinee container (i32 at offset 0)
      loadTag =
        [LocalGet (fromIntegral dispatchSlot)]
          <> [I32Load (MemArg 2 (0 :: Int))]
      cmpCode =
        [I32Const tag]
          <> [I32Eq] -- i32.eq
      (bindCode, ctx') = bindArmVarsI ctx dispatchSlot vars body
      ctx'' = recordArmPattern ctx' scrutName vars
   in loadTag
        <> cmpCode
        <> [If BtI32]
        <> bindCode
        <> scrutDecAfterBindI dispatchSlot scrutFresh
        <> emitArgWithIncI ctx'' body
        <> [Else]
        <> emitArmChainI ctx dispatchSlot scrutName scrutFresh rest
        <> [End]

-- | Bind case arm variables: load fields from the scrutinee container (read
-- through @srcSlot@, the case's dispatch slot) into locals. The returned
-- context advances 'ecBoundBase' past the fresh slots so any
-- nested 'CCase' inside the arm body allocates beyond the still-live outer
-- bindings. Slot demand is bounded by 'exprMaxBoundVars' (sum across the
-- deepest nesting path).
bindArmVarsI :: ExprCtx -> Word32 -> [Text] -> CExpr -> ([WasmInstr], ExprCtx)
bindArmVarsI ctx srcSlot vars body =
  let base = ctx.ecNextLocal
      bindOne v i =
        let slot = base + fromIntegral i
            offset = (i + 1) * 4 :: Int
            -- Inc each extracted ptr-binder so the local binding takes its
            -- own ref; the matching dec is the 'CDrop' wrap 'Awsum.Lifetime'
            -- adds. A binder unused in the body (Simplify inlined it into a
            -- 'CProj' of the scrutinee) is skipped entirely — not extracted,
            -- not inc'd, and Lifetime emits no 'CDrop' for it.
            bc
              | binderUsedIn v body =
                  [LocalGet (fromIntegral srcSlot)]
                    <> [I32Load (MemArg 2 offset)]
                    <> [LocalSet (fromIntegral slot)]
                    <> [LocalGet (fromIntegral slot)]
                    <> [Call "__inc_ref"]
              | otherwise = []
         in (bc, (v, slot))
      results = zipWith bindOne vars [0 :: Int ..]
      code = concatMap fst results
      newLocals = foldl' (\m (v, slot) -> Map.insert v slot m) ctx.ecLocals (map snd results)
      ctx' =
        ctx
          { ecLocals = newLocals,
            ecNextLocal = base + fromIntegral (length vars)
          }
   in (code, ctx')

emitTailI :: [Text] -> Word32 -> ExprCtx -> CExpr -> [WasmInstr]
emitTailI params depth ctx =
  emitTailPendingI params depth ctx [] []

-- | The dedicated local of a join parameter.
joinParamSlot :: ExprCtx -> Text -> Word32
joinParamSlot ctx p =
  fromMaybe (error ("WASM Assemble: no join-param slot for " <> p)) (Map.lookup p ctx.ecJoinParamSlots)

-- | Finish a value terminal of a tail walk: inside a join, the value
-- routes to the join's result local and branches to the after block;
-- outside, it stays on the stack (fallthrough yield).
joinValueFinishI :: ExprCtx -> Word32 -> [WasmInstr]
joinValueFinishI ctx depth = case ctx.ecTailJoin of
  Just (resSlot, afterLevel) ->
    [LocalSet (fromIntegral resSlot), Br (fromIntegral (depth - afterLevel))]
  Nothing -> []

-- | The dispatch-chain block type of a tail walk: i32 normally (arms
-- yield by fallthrough), void inside a join (every path leaves by 'Br').
tailChainBt :: ExprCtx -> BlockType
tailChainBt ctx = maybe BtI32 (const BtVoid) ctx.ecTailJoin

-- | Emit `(call $__free_recursive (local.get s))` for every fresh case
-- scrutinee currently stashed in scope. Each fresh tail-scrutinee's dispatch
-- slot doubles as its stash (counter-allocated, so an inner case never
-- overwrites it), and the slots accumulate into the threaded list as cases
-- nest; every terminator drains them.
emitFreshScrutDecsI :: [Word32] -> [WasmInstr]
emitFreshScrutDecsI = concatMap (\s -> [LocalGet (fromIntegral s)] <> [Call "__free_recursive"])

-- | Emit a non-'CLoop' 'CFunDef' body with value-tail
-- param decs. Walks the tail-form and emits dec at each terminal,
-- with per-arm
-- precision for 'CCase'/'CRowCase' bodies so an arm returning a
-- 'CVar' param is "moved" out instead of being freed.
emitNonLoopBodyI :: ExprCtx -> [Text] -> CExpr -> [WasmInstr]
emitNonLoopBodyI ctx0 params = go ctx0 0 [] []
  where
    go :: ExprCtx -> Word32 -> [Text] -> [Word32] -> CExpr -> [WasmInstr]
    go ctx depth pending freshScrutSlots = \case
      CCase scrut alts ->
        let sorted = sortWith (\(t, _, _) -> t) alts
            scrutFresh = isNothing (sourceCVarBin scrut)
            scrutName = sourceCVarBin scrut
            -- A fresh tail scrutinee evaluates into its own counter slot, which
            -- doubles as the stash (inner cases draw beyond it, so it is never
            -- overwritten) and is freed at each terminator.
            (scrutCode, dispatchSlot, ctx', freshScrutSlots') =
              if scrutFresh
                then
                  let (s, c') = freshLocal ctx
                   in (emitExprI ctx scrut <> [LocalSet (fromIntegral s)], s, c', freshScrutSlots <> [s])
                else
                  let (sc, ds, c') = scrutDispatchI ctx scrut
                   in (sc, ds, c', freshScrutSlots)
         in scrutCode <> goCaseChain ctx' depth dispatchSlot scrutName pending freshScrutSlots' sorted
      CRowCase scrut alts ->
        go ctx depth pending freshScrutSlots (CCase scrut [(fromIntegral t, [v], b) | (t, v, b) <- alts])
      CDrop n body -> go ctx depth (n : pending) freshScrutSlots body
      CLet x rhs body ->
        let (bindCode, ctx') = bindLetI ctx x rhs
         in bindCode <> go ctx' depth pending freshScrutSlots body
      -- Native join point: see 'emitTailPendingI' — the same construct,
      -- without the loop bookkeeping.
      CJoin j ps body inner ->
        let (resSlot, ctxR) = freshLocal ctx
            (paramSlots, ctxN0) = freshLocals (length ps) ctxR
            psMap = Map.fromList (zip ps paramSlots)
            wj = WJoinTarget (depth + 2) ps (length pending) (length freshScrutSlots)
            jmode = Just (resSlot, depth + 1)
            ctxJ =
              ctxN0
                { ecJoinTargets = Map.insert j wj ctxN0.ecJoinTargets,
                  ecJoinParamSlots = Map.union psMap ctxN0.ecJoinParamSlots,
                  ecTailJoin = jmode
                }
            ctxB = ctxJ {ecLocals = Map.union psMap ctxJ.ecLocals}
            innerCode = go ctxJ (depth + 2) pending freshScrutSlots inner
            bodyCode = go ctxB (depth + 1) (ps <> pending) freshScrutSlots body
         in [Block BtVoid, Block BtVoid]
              <> innerCode
              <> [End]
              <> bodyCode
              <> [End]
              <> [LocalGet (fromIntegral resSlot)]
              <> joinValueFinishI ctx depth
      CJump j args
        | Just wj <- Map.lookup j ctx.ecJoinTargets ->
            emitJumpI ctx depth pending freshScrutSlots wj args
      CJump j _ -> error ("WASM Assemble: CJump to unknown join " <> j <> " (pipeline bug)")
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
            scrutDecs = emitFreshScrutDecsI freshScrutSlots
         in drainPendingI ctx toDec (scrutDecs <> emitExprI ctx other)
              <> joinValueFinishI ctx depth

    -- Per-arm dec: each arm body emits its own (potentially
    -- different) param decs based on its own tail-form. Each arm
    -- self-terminates with a value (the function's 'if (result
    -- i32) ...' chain unifies them through WASM's structured
    -- control flow; inside a join every path leaves by 'Br', so the
    -- chain is void).
    goCaseChain :: ExprCtx -> Word32 -> Word32 -> Maybe Text -> [Text] -> [Word32] -> [(Int, [Text], CExpr)] -> [WasmInstr]
    goCaseChain ctx _ _ _ _ _ [] = case ctx.ecTailJoin of
      Just _ -> [Unreachable]
      Nothing -> [I32Const 0] -- unreachable
    goCaseChain ctx depth dispatchSlot scrutName pending freshScrutSlots [(_, vars, body)] =
      let (bindCode, ctx') = bindArmVarsI ctx dispatchSlot vars body
          ctx'' = recordArmPattern ctx' scrutName vars
       in bindCode <> go ctx'' depth pending freshScrutSlots body
    goCaseChain ctx depth dispatchSlot scrutName pending freshScrutSlots ((tag, vars, body) : rest) =
      [LocalGet (fromIntegral dispatchSlot)]
        <> [I32Load (MemArg 2 0)]
        <> [I32Const tag]
        <> [I32Eq]
        <> [If (tailChainBt ctx)]
        <> ( let (bindCode, ctx') = bindArmVarsI ctx dispatchSlot vars body
                 ctx'' = recordArmPattern ctx' scrutName vars
              in bindCode <> go ctx'' (depth + 1) pending freshScrutSlots body
           )
        <> [Else]
        <> goCaseChain ctx (depth + 1) dispatchSlot scrutName pending freshScrutSlots rest
        <> [End]

-- | The jump itself, shared by both tail walks: evaluate each argument
-- straight into its parameter slot (the slots are fresh names no argument
-- can read — no parallel-assignment hazard), inc the borrowed ones (the
-- parameter takes its own reference; fresh sources carry their @+1@),
-- release the fresh scrutinees and pending binders accumulated since the
-- join node, branch.
emitJumpI :: ExprCtx -> Word32 -> [Text] -> [Word32] -> WJoinTarget -> [CExpr] -> [WasmInstr]
emitJumpI ctx depth pending freshScrutSlots wj args =
  let evalStores =
        concat
          [ emitExprI ctx a <> [LocalSet (fromIntegral (joinParamSlot ctx p))]
          | (a, p) <- zip args wj.wjParams
          ]
      incs =
        concat
          [ [LocalGet (fromIntegral (joinParamSlot ctx p)), Call "__inc_ref"]
          | (a, p) <- zip args wj.wjParams,
            isHeapBorrow ctx a
          ]
      -- Release the fresh scrutinees stashed since the join node ('wjScrutBase'
      -- records how many were live at the node; the rest accumulated inside).
      scrutDecs = emitFreshScrutDecsI (drop wj.wjScrutBase freshScrutSlots)
      frees = concatMap (emitFreeOfI ctx) (take (length pending - wj.wjPendingBase) pending)
   in evalStores <> incs <> scrutDecs <> frees <> [Br (fromIntegral (depth - wj.wjLevel))]

-- | Walk a tail-position expression, accumulating 'CDrop' binders into
-- a 'pending' stack drained at every terminator (CContinue / value).
-- 'CCase' arms inherit the same 'pending' through 'emitTailArmChainI'.
-- @freshScrutSlots@ are the slots holding fresh case-scrutinees currently
-- stashed in scope; each terminator dec's them.
emitTailPendingI :: [Text] -> Word32 -> ExprCtx -> [Text] -> [Word32] -> CExpr -> [WasmInstr]
emitTailPendingI params depth ctx pending freshScrutSlots = \case
  CContinue newArgs ->
    let -- Buffer each new arg into a fresh scratch slot (so a new value that
        -- reads an old param sees the pre-update value), above every live
        -- binder; the buffers are dead after the back-edge. They must be
        -- reserved before the args are emitted — an arg that builds a cell or
        -- dispatches a case would otherwise draw the same slots and clobber an
        -- already-buffered value, so the args run on the advanced counter.
        (tcoSlots, ctxT) = freshLocals (length newArgs) ctx
        tcoSlotAt i = fromMaybe (error "WASM Assemble: CContinue arg index out of range") (listToMaybe (drop i tcoSlots))
        evals =
          concat
            [ emitExprI ctxT a
                <> [LocalSet (fromIntegral (tcoSlotAt i))]
            | (i, a) <- zip [0 :: Int ..] newArgs
            ]
        -- Inc each ptr-arg whose source is a CVar (borrow
        -- → the next-iter slot takes its own ref). Fresh sources
        -- carry their @+1@ from @$__alloc@.
        incs =
          concat
            [ case sourceCVarBin a of
                Just _ ->
                  [LocalGet (fromIntegral (tcoSlotAt i))]
                    <> [Call "__inc_ref"]
                Nothing -> []
            | (i, a) <- zip [0 :: Int ..] newArgs
            ]
        scrutDecs = emitFreshScrutDecsI freshScrutSlots
        frees = concatMap (emitFreeOfI ctx) pending
        paramSlots =
          [ fromMaybe (error $ "WASM Assemble: no param slot for " <> show p) (Map.lookup p ctx.ecParams)
          | p <- params
          ]
        copies =
          concat
            [ [LocalGet (fromIntegral (tcoSlotAt i))]
                <> [LocalSet (fromIntegral ps)]
            | (i, ps) <- zip [0 :: Int ..] paramSlots
            ]
     in evals <> incs <> scrutDecs <> frees <> copies <> [Br (fromIntegral depth)]
  CCase scrut alts ->
    let sorted = sortWith (\(t, _, _) -> t) alts
        scrutFresh = isNothing (sourceCVarBin scrut)
        scrutName = sourceCVarBin scrut
        -- A fresh tail scrutinee evaluates into its own counter slot, which
        -- doubles as the stash (inner cases draw beyond it, so it is never
        -- overwritten) and is freed at each terminator.
        (scrutCode, dispatchSlot, ctx', freshScrutSlots') =
          if scrutFresh
            then
              let (s, c') = freshLocal ctx
               in (emitExprI ctx scrut <> [LocalSet (fromIntegral s)], s, c', freshScrutSlots <> [s])
            else
              let (sc, ds, c') = scrutDispatchI ctx scrut
               in (sc, ds, c', freshScrutSlots)
     in scrutCode <> emitTailArmChainI params depth ctx' dispatchSlot scrutName pending freshScrutSlots' sorted
  -- Row dispatch: same wire layout as a one-field 'CCase', so delegate. This
  -- keeps a 'CContinue' in a row-case arm in tail position; without it the arm
  -- falls to the value 'other' path, whose emitter rejects 'CContinue'.
  CRowCase scrut alts ->
    emitTailPendingI params depth ctx pending freshScrutSlots (CCase scrut [(fromIntegral t, [v], b) | (t, v, b) <- alts])
  -- Push the drop onto the pending stack; drain at terminator.
  CDrop n body -> emitTailPendingI params depth ctx (n : pending) freshScrutSlots body
  -- Bind, then the body continues in tail position (its 'CDrop' for the
  -- binder lands on the pending stack like any other).
  CLet x rhs body ->
    let (bindCode, ctx') = bindLetI ctx x rhs
     in bindCode <> emitTailPendingI params depth ctx' pending freshScrutSlots body
  -- Native join point: inner runs inside two void blocks (jumps 'Br' to
  -- the body block's end, bypass values 'Br' one further to the after
  -- block via 'ecTailJoin'); the body runs between the two 'End's with
  -- the join parameters joined onto @pending@ — the value-tail release
  -- with the move carve-out is the function-parameter discipline they
  -- follow. A 'CContinue' anywhere inside still targets the loop: the
  -- walk's depth counter grows by the blocks opened here, so its 'Br'
  -- arithmetic stays right.
  CJoin j ps body inner ->
    let (resSlot, ctxR) = freshLocal ctx
        (paramSlots, ctxN0) = freshLocals (length ps) ctxR
        psMap = Map.fromList (zip ps paramSlots)
        wj = WJoinTarget (depth + 2) ps (length pending) (length freshScrutSlots)
        jmode = Just (resSlot, depth + 1)
        ctxJ =
          ctxN0
            { ecJoinTargets = Map.insert j wj ctxN0.ecJoinTargets,
              ecJoinParamSlots = Map.union psMap ctxN0.ecJoinParamSlots,
              ecTailJoin = jmode
            }
        ctxB = ctxJ {ecLocals = Map.union psMap ctxJ.ecLocals}
        innerCode = emitTailPendingI params (depth + 2) ctxJ pending freshScrutSlots inner
        bodyCode = emitTailPendingI params (depth + 1) ctxB (ps <> pending) freshScrutSlots body
     in [Block BtVoid, Block BtVoid]
          <> innerCode
          <> [End]
          <> bodyCode
          <> [End]
          <> [LocalGet (fromIntegral resSlot)]
          <> joinValueFinishI ctx depth
  CJump j args
    | Just wj <- Map.lookup j ctx.ecJoinTargets ->
        emitJumpI ctx depth pending freshScrutSlots wj args
  CJump j _ -> error ("WASM Assemble: CJump to unknown join " <> j <> " (pipeline bug)")
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
        scrutDecs = emitFreshScrutDecsI freshScrutSlots
     in drainPendingI ctx toDec (scrutDecs <> emitExprI ctx other)
          <> joinValueFinishI ctx depth

-- | Drain pending drops at a value-producing tail. Wraps the value
-- expression in @(block (result i32) (local.set $__drop_tmp …) …frees…
-- (local.get $__drop_tmp))@. Empty pending → no wrapping.
drainPendingI :: ExprCtx -> [Text] -> [WasmInstr] -> [WasmInstr]
drainPendingI _ [] valueBytes = valueBytes
drainPendingI ctx pending valueBytes =
  -- Leaf scratch: the value is captured here while the pending binders are
  -- freed. 'valueBytes' was emitted on the same counter, so its slots are
  -- dead and this one is free to reuse.
  let tmp = ctx.ecNextLocal
   in [Block BtI32]
        <> valueBytes
        <> [LocalSet (fromIntegral tmp)]
        <> concatMap (emitFreeOfI ctx) pending
        <> [LocalGet (fromIntegral tmp)]
        <> [End]

-- | Emit @(call $__free_recursive (local.get $<binder>))@.
-- The binder must be a function param ('ecParams') or a
-- case-pattern binder ('ecLocals') already in scope.
emitFreeOfI :: ExprCtx -> Text -> [WasmInstr]
emitFreeOfI ctx n =
  let slot = lookupBinderSlot ctx n
   in [LocalGet (fromIntegral slot)]
        <> [Call "__free_recursive"]

-- | Tail version of 'emitArmChainI': each arm is emitted in tail form so
-- it either produces an @i32@ result or terminates with a @br@ back to
-- the loop. Nesting into an @opIf@ increases 'depth' by one for both the
-- then-body and the else-continuation.
emitTailArmChainI :: [Text] -> Word32 -> ExprCtx -> Word32 -> Maybe Text -> [Text] -> [Word32] -> [(Int, [Text], CExpr)] -> [WasmInstr]
emitTailArmChainI _ _ ctx _ _ _ _ [] = case ctx.ecTailJoin of
  Just _ -> [Unreachable]
  Nothing -> [I32Const 0]
emitTailArmChainI params depth ctx dispatchSlot scrutName pending freshScrutSlots [(_, vars, body)] =
  let (bindCode, ctx') = bindArmVarsI ctx dispatchSlot vars body
      ctx'' = recordArmPattern ctx' scrutName vars
   in bindCode <> emitTailPendingI params depth ctx'' pending freshScrutSlots body
emitTailArmChainI params depth ctx dispatchSlot scrutName pending freshScrutSlots ((tag, vars, body) : rest) =
  let loadTag =
        [LocalGet (fromIntegral dispatchSlot)]
          <> [I32Load (MemArg 2 0)]
      cmpCode =
        [I32Const tag]
          <> [I32Eq] -- i32.eq
      (bindCode, ctx') = bindArmVarsI ctx dispatchSlot vars body
      ctx'' = recordArmPattern ctx' scrutName vars
   in loadTag
        <> cmpCode
        <> [If (tailChainBt ctx)]
        <> bindCode
        <> emitTailPendingI params (depth + 1) ctx'' pending freshScrutSlots body
        <> [Else]
        <> emitTailArmChainI params (depth + 1) ctx dispatchSlot scrutName pending freshScrutSlots rest
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
        ctx = userExprCtx info typeMap paramMap nParams
        instrs = [Loop BtI32] <> emitTailI args 0 ctx body <> [End]
     in WasmFunc
          { wfName = userFuncLabel nm,
            wfParams = replicate (length args) I32,
            wfResults = [I32],
            wfLocals = replicate (extraLocals nParams instrs) I32,
            wfBody = instrs
          }
  CFunDef nm args body ->
    let nParams = fromIntegral (length args) :: Word32
        paramMap = Map.fromList (zip args [0 :: Word32 ..])
        ctx = userExprCtx info typeMap paramMap nParams
        instrs = emitNonLoopBodyI ctx args body
     in WasmFunc
          { wfName = userFuncLabel nm,
            wfParams = replicate (length args) I32,
            wfResults = [I32],
            wfLocals = replicate (extraLocals nParams instrs) I32,
            wfBody = instrs
          }
  CValDef nm rhs ->
    let ctx = userExprCtx info typeMap Map.empty 0
        instrs = emitExprI ctx rhs
     in WasmFunc
          { wfName = userFuncLabel nm,
            wfParams = [],
            wfResults = [I32],
            wfLocals = replicate (extraLocals 0 instrs) I32,
            wfBody = instrs
          }
  where
    -- The @.locals@ vector spans every slot the body touches beyond the
    -- parameters, read straight off the emitted stream ('maxLocalsOf') so it
    -- tracks the slots the emitter actually drew from 'ecNextLocal' — no
    -- second prediction over the source IR to drift against.
    extraLocals :: Word32 -> [WasmInstr] -> Int
    extraLocals nParams instrs = max 0 (maxLocalsOf instrs - fromIntegral nParams)

-- | Shared 'ExprCtx' constructor for 'userDeclFunc'. The local counter starts
--   right after the parameters; every other local is drawn from it during
--   emission.
userExprCtx :: WasmInfo -> Map FuncType Word32 -> Map Text Word32 -> Word32 -> ExprCtx
userExprCtx info typeMap paramMap nParams =
  ExprCtx
    { ecParams = paramMap,
      ecLocals = Map.empty,
      ecValDefs = info.wiValDefs,
      ecFunDefs = info.wiFunDefs,
      ecArities = info.wiArities,
      ecStringPool = info.wiStringPool,
      ecTableMap = info.wiTableMap,
      ecTypeMap = typeMap,
      ecIndirectArities = info.wiIndirectArities,
      ecNextLocal = nParams,
      ecArmPatternByScrut = Map.empty,
      ecJoinParamSlots = Map.empty,
      ecJoinTargets = Map.empty,
      ecTailJoin = Nothing
    }

-- | Binary projection of a user declaration: the 'WasmFunc' → bytes. The
--   text projection ('Awsum.Codegen.WASM') renders the same 'userDeclFunc'
--   value, so the two cannot diverge.
codeUserDecl :: WasmInfo -> Map FuncType Word32 -> CDecl -> [Word8]
codeUserDecl info typeMap decl = assembleFunc (funcIdxMap info) (userDeclFunc info typeMap decl)
