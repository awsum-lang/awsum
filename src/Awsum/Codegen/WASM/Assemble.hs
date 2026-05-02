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
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Relude

-- ════════════════════════════════════════════════════════════════════════════
-- Public API
-- ════════════════════════════════════════════════════════════════════════════

-- | Produce a complete .wasm binary as a strict ByteString.
assembleWASM :: CoreProgram -> BS.ByteString
assembleWASM prog = toStrict (B.toLazyByteString (buildModule prog))

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

opLocalGet, opLocalSet, opGlobalGet, opGlobalSet :: Word8
opLocalGet = 0x20
opLocalSet = 0x21
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

opI64Const, opI64Add, opI64Sub, opI64Mul, opI64Shl, opI64LtS, opI64GtS, opI32WrapI64, opI64ExtendI32S, opI64ExtendI32U :: Word8
opI64Const = 0x42
opI64Add = 0x7C
opI64Sub = 0x7D
opI64Mul = 0x7E
opI64Shl = 0x86
opI64LtS = 0x53
opI64GtS = 0x55
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
    wiEmptyOff :: Int, -- offset of "" in pool
    wiHeapStart :: Int,
    wiValDefs :: Set Text,
    wiFunDefs :: Set Text,
    wiArities :: Map Text Int,
    wiTableMap :: Map Text Int, -- func name -> table index
    wiFunList :: [Text], -- all CFunDef names in decl order
    wiIndirectArities :: Set Int,
    -- Function indices (imports first, then locals)
    wiFuncIdx :: Map Text Word32 -- name -> function index
  }

-- Import count: fd_write(0), args_sizes_get(1), args_get(2)
importCount :: Word32
importCount = 3

-- Runtime helper count: __strlen, __alloc, __memcpy, __concat, __print,
-- __box_i32, __show_i32, __predInt32, __predUInt8, __succInt32, __succUInt8,
-- __eq_i32, __addInt32, __subInt32, __mulInt32, __negInt32, __addUInt8,
-- __subUInt8, __mulUInt8, __splitOnFirst, __parseInt32, __parseUInt8, __get_arg
runtimeCount :: Word32
runtimeCount = 23

-- Runtime helper function indices (after imports)
idxStrlen, idxAlloc, idxMemcpy, idxConcat, idxPrint, idxBoxI32, idxShowI32, idxPredI32, idxPredU8, idxSuccI32, idxSuccU8, idxEqI32, idxAddI32, idxSubI32, idxMulI32, idxNegI32, idxAddU8, idxSubU8, idxMulU8, idxSplitOnFirst, idxParseI32, idxParseU8, idxGetArg :: Word32
idxStrlen = importCount
idxAlloc = importCount + 1
idxMemcpy = importCount + 2
idxConcat = importCount + 3
idxPrint = importCount + 4
idxBoxI32 = importCount + 5
idxShowI32 = importCount + 6
idxPredI32 = importCount + 7
idxPredU8 = importCount + 8
idxSuccI32 = importCount + 9
idxSuccU8 = importCount + 10
idxEqI32 = importCount + 11
idxAddI32 = importCount + 12
idxSubI32 = importCount + 13
idxMulI32 = importCount + 14
idxNegI32 = importCount + 15
idxAddU8 = importCount + 16
idxSubU8 = importCount + 17
idxMulU8 = importCount + 18
idxSplitOnFirst = importCount + 19
idxParseI32 = importCount + 20
idxParseU8 = importCount + 21
idxGetArg = importCount + 22

buildInfo :: CoreProgram -> WasmInfo
buildInfo prog@(CoreProgram decls) =
  let (pool, emptyOff, heapStart) = buildStringPool prog
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
          wiEmptyOff = emptyOff,
          wiHeapStart = heapStart,
          wiValDefs = valNames,
          wiFunDefs = funNames,
          wiArities = arities,
          wiTableMap = tableMap,
          wiFunList = funList,
          wiIndirectArities = indArities,
          wiFuncIdx = funcIdx
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

buildStringPool :: CoreProgram -> (Map Text Int, Int, Int)
buildStringPool (CoreProgram decls) =
  let strs = ordNub $ "" : concatMap stringsInDecl decls
      offsets = scanl (\off s -> off + T.length s + 1) scratchSize strs
      pool = Map.fromList (zip strs offsets)
      emptyOff = fromMaybe scratchSize (Map.lookup "" pool)
      heapStart = fromMaybe scratchSize $ viaNonEmpty Relude.last (zipWith (\s o -> o + T.length s + 1) strs offsets)
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
              FuncType 2 True -- args_get (dedup with above)
            ]
          -- Runtime helpers
          <> [ FuncType 1 True, -- __strlen(i32)->i32
               FuncType 1 True, -- __alloc (dedup)
               FuncType 3 False, -- __memcpy(i32,i32,i32)->void
               FuncType 2 True, -- __concat (dedup with args_sizes_get)
               FuncType 1 True, -- __print (dedup with __strlen)
               FuncType 0 True -- __get_arg()->i32
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
            mkImport "args_get" (FuncType 2 True)
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
        [ lookupType (FuncType 1 True) typeMap, -- __strlen
          lookupType (FuncType 1 True) typeMap, -- __alloc
          lookupType (FuncType 3 False) typeMap, -- __memcpy
          lookupType (FuncType 2 True) typeMap, -- __concat
          lookupType (FuncType 1 True) typeMap, -- __print
          lookupType (FuncType 1 True) typeMap, -- __box_i32
          lookupType (FuncType 1 True) typeMap, -- __show_i32
          lookupType (FuncType 1 True) typeMap, -- __predInt32
          lookupType (FuncType 1 True) typeMap, -- __predUInt8
          lookupType (FuncType 1 True) typeMap, -- __succInt32
          lookupType (FuncType 1 True) typeMap, -- __succUInt8
          lookupType (FuncType 2 True) typeMap, -- __eq_i32
          lookupType (FuncType 2 True) typeMap, -- __addInt32
          lookupType (FuncType 2 True) typeMap, -- __subInt32
          lookupType (FuncType 2 True) typeMap, -- __mulInt32
          lookupType (FuncType 1 True) typeMap, -- __negInt32
          lookupType (FuncType 2 True) typeMap, -- __addUInt8
          lookupType (FuncType 2 True) typeMap, -- __subUInt8
          lookupType (FuncType 2 True) typeMap, -- __mulUInt8
          lookupType (FuncType 2 True) typeMap, -- __splitOnFirst
          lookupType (FuncType 1 True) typeMap, -- __parseInt32
          lookupType (FuncType 1 True) typeMap, -- __parseUInt8
          lookupType (FuncType 0 True) typeMap -- __get_arg
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

buildMemorySection :: [Word8]
buildMemorySection =
  let content =
        encodeVec
          [ [0x00] -- limits: no max
              <> encodeULEB128 1 -- initial: 1 page (64KB)
          ]
   in buildSection 5 content

-- ════════════════════════════════════════════════════════════════════════════
-- Global section
-- ════════════════════════════════════════════════════════════════════════════

buildGlobalSection :: WasmInfo -> [Word8]
buildGlobalSection info =
  let content =
        encodeVec
          [ [valtypeI32, 0x01] -- i32, mutable
              <> [opI32Const]
              <> encodeSLEB128 (fromIntegral info.wiHeapStart)
              <> [opEnd]
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
        [ codeStrlen,
          codeAlloc,
          codeMemcpy,
          codeConcat info,
          codePrint info,
          codeBoxI32 info,
          codeShowI32 info,
          codePredI32 info,
          codePredU8 info,
          codeSuccI32 info,
          codeSuccU8 info,
          codeEqI32 info,
          codeAddI32 info,
          codeSubI32 info,
          codeMulI32 info,
          codeNegI32 info,
          codeAddU8 info,
          codeSubU8 info,
          codeMulU8 info,
          codeSplitOnFirst info,
          codeParseInt32 info,
          codeParseUInt8 info,
          codeGetArg info
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

-- __strlen(s: i32) -> i32
-- local $len: i32
codeStrlen :: [Word8]
codeStrlen =
  encodeBody
    (encodeLocals 1) -- 1 local: $len (slot 1)
    $ concat
      [ -- local.set $len 0
        [opI32Const],
        encodeSLEB128 0,
        [opLocalSet],
        encodeULEB128 1,
        -- block $break
        [opBlock, blocktypeVoid],
        -- loop $loop
        [opLoop, blocktypeVoid],
        -- br_if $break (i32.eqz (i32.load8_u (s + len)))
        [opLocalGet],
        encodeULEB128 0, -- s
        [opLocalGet],
        encodeULEB128 1, -- len
        [opI32Add],
        [opI32Load8U, 0x00, 0x00], -- align=0, offset=0
        [opI32Eqz],
        [opBrIf],
        encodeULEB128 1, -- break (label 1)
        -- len = len + 1
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
        -- end loop, end block
        [opEnd],
        [opEnd],
        -- return len
        [opLocalGet],
        encodeULEB128 1
      ]

-- __alloc(size: i32) -> i32
-- local $ptr: i32
codeAlloc :: [Word8]
codeAlloc =
  encodeBody
    (encodeLocals 1)
    $ concat
      [ -- ptr = (heap + 3) & ~3  (4-byte align)
        [opGlobalGet],
        encodeULEB128 0,
        [opI32Const],
        encodeSLEB128 3,
        [opI32Add],
        [opI32Const],
        encodeSLEB128 (-4),
        [opI32And],
        [opLocalSet],
        encodeULEB128 1,
        -- global.set $heap (ptr + size)
        [opLocalGet],
        encodeULEB128 1, -- ptr
        [opLocalGet],
        encodeULEB128 0, -- size
        [opI32Add],
        [opGlobalSet],
        encodeULEB128 0,
        -- Grow loop: while heap > memory.size * 65536, grow by 1 page.
        -- A single grow is not enough when one allocation (or one CPS
        -- non-tail unwind) overshoots memory by more than one page;
        -- keep growing until the heap fits. Falls through when it does.
        [opLoop, blocktypeVoid],
        [opGlobalGet],
        encodeULEB128 0, -- heap
        [opMemorySize, 0x00],
        [opI32Const],
        encodeSLEB128 65536,
        [opI32Mul],
        [opI32GtU],
        [opIf, blocktypeVoid],
        [opI32Const],
        encodeSLEB128 1, -- 1 page
        [opMemoryGrow, 0x00], -- grows memory, pushes old size or -1
        [opDrop], -- discard result
        [opBr], -- br $grow_loop (restart the outer loop)
        encodeULEB128 1, -- 1 level up: past the 'if', back to the loop
        [opEnd], -- end if
        [opEnd], -- end loop
        -- return ptr
        [opLocalGet],
        encodeULEB128 1
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

-- __concat(a: i32, b: i32) -> i32
-- locals: $la, $lb, $buf (slots 2,3,4)
codeConcat :: WasmInfo -> [Word8]
codeConcat _info =
  encodeBody
    (encodeLocals 3)
    $ concat
      [ -- la = __strlen(a)
        [opLocalGet],
        encodeULEB128 0,
        [opCall],
        encodeULEB128 idxStrlen,
        [opLocalSet],
        encodeULEB128 2,
        -- lb = __strlen(b)
        [opLocalGet],
        encodeULEB128 1,
        [opCall],
        encodeULEB128 idxStrlen,
        [opLocalSet],
        encodeULEB128 3,
        -- buf = __alloc(la + lb + 1)
        [opLocalGet],
        encodeULEB128 2,
        [opLocalGet],
        encodeULEB128 3,
        [opI32Add],
        [opI32Const],
        encodeSLEB128 1,
        [opI32Add],
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 4,
        -- __memcpy(buf, a, la)
        [opLocalGet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 0,
        [opLocalGet],
        encodeULEB128 2,
        [opCall],
        encodeULEB128 idxMemcpy,
        -- __memcpy(buf+la, b, lb)
        [opLocalGet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 2,
        [opI32Add],
        [opLocalGet],
        encodeULEB128 1,
        [opLocalGet],
        encodeULEB128 3,
        [opCall],
        encodeULEB128 idxMemcpy,
        -- i32.store8 (buf+la+lb) 0
        [opLocalGet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 2,
        [opI32Add],
        [opLocalGet],
        encodeULEB128 3,
        [opI32Add],
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store8, 0x00, 0x00],
        -- return buf
        [opLocalGet],
        encodeULEB128 4
      ]

-- __print(s: i32) -> i32
-- local: $len (slot 1)
codePrint :: WasmInfo -> [Word8]
codePrint _info =
  encodeBody
    (encodeLocals 1)
    $ concat
      [ -- len = __strlen(s)
        [opLocalGet],
        encodeULEB128 0,
        [opCall],
        encodeULEB128 idxStrlen,
        [opLocalSet],
        encodeULEB128 1,
        -- i32.store offset=0 (i32.const 0) s  -- iov_base
        [opI32Const],
        encodeSLEB128 0,
        [opLocalGet],
        encodeULEB128 0,
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
        -- return 0
        [opI32Const],
        encodeSLEB128 0
      ]

-- __predInt32(p: i32) -> i32
-- predInt32: Int32 -> Either UnderflowError Int32.
--   Container layout matches user CCon emission on WASM: i32 tag at
--   offset 0, i32 fields at offsets 4, 8, ... Tags: Left=0, Right=1,
--   UnderflowError=0. Returns `Left UnderflowError` on INT32_MIN,
--   `Right (v - 1)` otherwise.
-- Locals: $v(1) $ue(2) $box(3) $cell(4)
codePredI32 :: WasmInfo -> [Word8]
codePredI32 _info =
  encodeBody
    (encodeLocals 4)
    $ concat
      [ -- v = i32.load(p)
        [opLocalGet],
        encodeULEB128 0,
        [opI32Load, 0x02, 0x00],
        [opLocalSet],
        encodeULEB128 1,
        -- if (v == INT32_MIN) result i32
        [opLocalGet],
        encodeULEB128 1,
        [opI32Const],
        encodeSLEB128 (-2147483648),
        [opI32Eq],
        [opIf, blocktypeI32],
        -- then: Left UnderflowError
        -- ue = __alloc(4); store tag 0
        [opI32Const],
        encodeSLEB128 4,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 2,
        [opLocalGet],
        encodeULEB128 2,
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store, 0x02, 0x00],
        -- cell = __alloc(8); store tag 0; store[offset=4] ue
        [opI32Const],
        encodeSLEB128 8,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 4,
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 2,
        [opI32Store, 0x02, 0x04],
        [opLocalGet],
        encodeULEB128 4,
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
        -- cell = __alloc(8); store tag 1; store[offset=4] box
        [opI32Const],
        encodeSLEB128 8,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 4,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 3,
        [opI32Store, 0x02, 0x04],
        [opLocalGet],
        encodeULEB128 4,
        [opEnd]
      ]

-- __predUInt8(p: i32) -> i32
-- predUInt8: UInt8 -> Either UnderflowError UInt8.
--   Mirrors 'codePredI32' but checks against 0 (via 'i32.eqz') instead
--   of INT32_MIN, and subtracts without masking — (v - 1) is in 0..254
--   when v >= 1, so it stays in UInt8 range naturally. Same locals
--   layout: $v(1) $ue(2) $box(3) $cell(4).
codePredU8 :: WasmInfo -> [Word8]
codePredU8 _info =
  encodeBody
    (encodeLocals 4)
    $ concat
      [ -- v = i32.load(p)
        [opLocalGet],
        encodeULEB128 0,
        [opI32Load, 0x02, 0x00],
        [opLocalSet],
        encodeULEB128 1,
        -- if (i32.eqz v) result i32
        [opLocalGet],
        encodeULEB128 1,
        [opI32Eqz],
        [opIf, blocktypeI32],
        -- then: Left UnderflowError
        -- ue = __alloc(4); store tag 0
        [opI32Const],
        encodeSLEB128 4,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 2,
        [opLocalGet],
        encodeULEB128 2,
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store, 0x02, 0x00],
        -- cell = __alloc(8); store tag 0; store[offset=4] ue
        [opI32Const],
        encodeSLEB128 8,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 4,
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 2,
        [opI32Store, 0x02, 0x04],
        [opLocalGet],
        encodeULEB128 4,
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
        -- cell = __alloc(8); store tag 1; store[offset=4] box
        [opI32Const],
        encodeSLEB128 8,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 4,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 3,
        [opI32Store, 0x02, 0x04],
        [opLocalGet],
        encodeULEB128 4,
        [opEnd]
      ]

-- __succInt32(p: i32) -> i32
-- succInt32: Int32 -> Either OverflowError Int32.
--   Mirrors 'codePredI32' with boundary INT32_MAX and i32.add instead of
--   i32.sub. OverflowError is single-constructor, so its inner-box tag is
--   0 (same as UnderflowError) — encoding is bit-identical to the
--   predecessor case on this axis.
-- Locals: $v(1) $oe(2) $box(3) $cell(4)
codeSuccI32 :: WasmInfo -> [Word8]
codeSuccI32 _info =
  encodeBody
    (encodeLocals 4)
    $ concat
      [ -- v = i32.load(p)
        [opLocalGet],
        encodeULEB128 0,
        [opI32Load, 0x02, 0x00],
        [opLocalSet],
        encodeULEB128 1,
        -- if (v == INT32_MAX) result i32
        [opLocalGet],
        encodeULEB128 1,
        [opI32Const],
        encodeSLEB128 2147483647,
        [opI32Eq],
        [opIf, blocktypeI32],
        -- then: Left OverflowError
        -- oe = __alloc(4); store tag 0
        [opI32Const],
        encodeSLEB128 4,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 2,
        [opLocalGet],
        encodeULEB128 2,
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store, 0x02, 0x00],
        -- cell = __alloc(8); store tag 0; store[offset=4] oe
        [opI32Const],
        encodeSLEB128 8,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 4,
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 2,
        [opI32Store, 0x02, 0x04],
        [opLocalGet],
        encodeULEB128 4,
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
        -- cell = __alloc(8); store tag 1; store[offset=4] box
        [opI32Const],
        encodeSLEB128 8,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 4,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 3,
        [opI32Store, 0x02, 0x04],
        [opLocalGet],
        encodeULEB128 4,
        [opEnd]
      ]

-- __succUInt8(p: i32) -> i32
-- succUInt8: UInt8 -> Either OverflowError UInt8.
--   Mirrors 'codeSuccI32' but checks against 255. Masking is unnecessary —
--   (v + 1) is in 1..255 when v <= 254, so the result stays in UInt8 range
--   naturally. Same locals layout: $v(1) $oe(2) $box(3) $cell(4).
codeSuccU8 :: WasmInfo -> [Word8]
codeSuccU8 _info =
  encodeBody
    (encodeLocals 4)
    $ concat
      [ -- v = i32.load(p)
        [opLocalGet],
        encodeULEB128 0,
        [opI32Load, 0x02, 0x00],
        [opLocalSet],
        encodeULEB128 1,
        -- if (v == 255) result i32
        [opLocalGet],
        encodeULEB128 1,
        [opI32Const],
        encodeSLEB128 255,
        [opI32Eq],
        [opIf, blocktypeI32],
        -- then: Left OverflowError
        -- oe = __alloc(4); store tag 0
        [opI32Const],
        encodeSLEB128 4,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 2,
        [opLocalGet],
        encodeULEB128 2,
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store, 0x02, 0x00],
        -- cell = __alloc(8); store tag 0; store[offset=4] oe
        [opI32Const],
        encodeSLEB128 8,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 4,
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 2,
        [opI32Store, 0x02, 0x04],
        [opLocalGet],
        encodeULEB128 4,
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
        -- cell = __alloc(8); store tag 1; store[offset=4] box
        [opI32Const],
        encodeSLEB128 8,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 4,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 3,
        [opI32Store, 0x02, 0x04],
        [opLocalGet],
        encodeULEB128 4,
        [opEnd]
      ]

-- __eq_i32(a: i32, b: i32) -> i32
-- eqInt32 / eqUInt8: compare two boxed integers, return a Bool container.
--   Int32 and UInt8 both flow as pointers to i32 cells (UInt8 values are
--   stored masked to 0..255), so one helper handles both. True=0, False=1
--   matches declaration order in `type Bool = True | False`.
-- Locals: $cell(2) — single i32 local, in addition to the two params.
codeEqI32 :: WasmInfo -> [Word8]
codeEqI32 _info =
  encodeBody
    (encodeLocals 1)
    $ concat
      [ -- cell = __alloc(4)
        [opI32Const],
        encodeSLEB128 4,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 2,
        -- if (i32.load(a) == i32.load(b)) result i32
        [opLocalGet],
        encodeULEB128 0,
        [opI32Load, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 1,
        [opI32Load, 0x02, 0x00],
        [opI32Eq],
        [opIf, blocktypeI32],
        -- then: store tag 0 (True), return cell
        [opLocalGet],
        encodeULEB128 2,
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 2,
        [opElse],
        -- else: store tag 1 (False), return cell
        [opLocalGet],
        encodeULEB128 2,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 2,
        [opEnd]
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
codeAddI32 _info =
  encodeBody
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
        [opIf, blocktypeI32],
        -- then: Left (CRow rowTag (CCon 0 [])).
        -- inner = __alloc(4); store 0  (CCon UnderflowError/OverflowError, tag 0)
        [opI32Const],
        encodeSLEB128 4,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 5,
        [opLocalGet],
        encodeULEB128 5,
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store, 0x02, 0x00],
        -- row = __alloc(8); store rowTag(if a >= 0 then OverflowError else UnderflowError);
        --                   store inner at offset=4
        [opI32Const],
        encodeSLEB128 8,
        [opCall],
        encodeULEB128 idxAlloc,
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
        -- cell = __alloc(8); store tag 0 (Left); store row at offset=4
        [opI32Const],
        encodeSLEB128 8,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 8,
        [opLocalGet],
        encodeULEB128 8,
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 8,
        [opLocalGet],
        encodeULEB128 6,
        [opI32Store, 0x02, 0x04],
        [opLocalGet],
        encodeULEB128 8,
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
        -- cell = __alloc(8); store tag 1 (Right); store offset=4 box
        [opI32Const],
        encodeSLEB128 8,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 8,
        [opLocalGet],
        encodeULEB128 8,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 8,
        [opLocalGet],
        encodeULEB128 7,
        [opI32Store, 0x02, 0x04],
        [opLocalGet],
        encodeULEB128 8,
        [opEnd]
      ]

-- __addUInt8(pa: i32, pb: i32) -> i32
-- addUInt8: UInt8 -> UInt8 -> Either OverflowError UInt8. Sum is in
-- 0..510 so a single 'i32.gt_u 255' check picks the branch — no
-- widening, no mask on the ok path.
-- Locals: $s(2) $oe(3) $box(4) $cell(5).
codeAddU8 :: WasmInfo -> [Word8]
codeAddU8 _info =
  encodeBody
    (encodeLocals 4)
    $ concat
      [ -- s = i32.load(pa) + i32.load(pb)
        [opLocalGet],
        encodeULEB128 0,
        [opI32Load, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 1,
        [opI32Load, 0x02, 0x00],
        [opI32Add],
        [opLocalSet],
        encodeULEB128 2,
        -- if (s > 255) result i32
        [opLocalGet],
        encodeULEB128 2,
        [opI32Const],
        encodeSLEB128 255,
        [opI32GtU],
        [opIf, blocktypeI32],
        -- then: Left OverflowError
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
        [opI32Store, 0x02, 0x00],
        [opI32Const],
        encodeSLEB128 8,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 5,
        [opLocalGet],
        encodeULEB128 5,
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 5,
        [opLocalGet],
        encodeULEB128 3,
        [opI32Store, 0x02, 0x04],
        [opLocalGet],
        encodeULEB128 5,
        [opElse],
        -- else: Right s
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
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 5,
        [opLocalGet],
        encodeULEB128 5,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 5,
        [opLocalGet],
        encodeULEB128 4,
        [opI32Store, 0x02, 0x04],
        [opLocalGet],
        encodeULEB128 5,
        [opEnd]
      ]

-- __subInt32(pa: i32, pb: i32) -> i32
-- subInt32: Int32 -> Int32 -> Either ArithError Int32. Same XOR-based
-- signed-overflow detection as 'codeAddI32', with i32.sub replacing
-- i32.add and the second XOR comparing 'a' vs 'diff' (the standard
-- subtraction overflow check). Direction (over vs under) is read off
-- 'a >= 0', identical to 'codeAddI32'.
-- Locals: $a(2) $b(3) $d(4) $ae(5) $box(6) $cell(7).
codeSubI32 :: WasmInfo -> [Word8]
codeSubI32 _info =
  encodeBody
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
        -- d = a - b
        [opLocalGet],
        encodeULEB128 2,
        [opLocalGet],
        encodeULEB128 3,
        [opI32Sub],
        [opLocalSet],
        encodeULEB128 4,
        -- if (((a ^ b) & (a ^ d)) < 0)  result i32
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
        [opIf, blocktypeI32],
        -- then: Left (CRow rowTag (CCon 0 [])).
        -- inner = __alloc(4); store 0
        [opI32Const],
        encodeSLEB128 4,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 5,
        [opLocalGet],
        encodeULEB128 5,
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store, 0x02, 0x00],
        -- row = __alloc(8); store rowTag(if a >= 0 then OverflowError else UnderflowError);
        --                   store inner at offset=4
        [opI32Const],
        encodeSLEB128 8,
        [opCall],
        encodeULEB128 idxAlloc,
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
        -- cell = __alloc(8); store tag 0 (Left); store row at offset=4
        [opI32Const],
        encodeSLEB128 8,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 8,
        [opLocalGet],
        encodeULEB128 8,
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 8,
        [opLocalGet],
        encodeULEB128 6,
        [opI32Store, 0x02, 0x04],
        [opLocalGet],
        encodeULEB128 8,
        [opElse],
        -- else: Right d
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
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 8,
        [opLocalGet],
        encodeULEB128 8,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 8,
        [opLocalGet],
        encodeULEB128 7,
        [opI32Store, 0x02, 0x04],
        [opLocalGet],
        encodeULEB128 8,
        [opEnd]
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
codeMulI32 _info =
  encodeBody
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
        [opIf, blocktypeI32],
        -- then: Left (CRow rowTag(OverflowError) (CCon 0 [])).
        -- inner = __alloc(4); store 0
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
        [opI32Store, 0x02, 0x00],
        -- row = __alloc(8); store rowTag(OverflowError); store inner@offset=4
        [opI32Const],
        encodeSLEB128 8,
        [opCall],
        encodeULEB128 idxAlloc,
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
        -- cell = __alloc(8); store 0 (Left); store row@offset=4
        [opI32Const],
        encodeSLEB128 8,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 5,
        [opLocalGet],
        encodeULEB128 5,
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 5,
        [opLocalGet],
        encodeULEB128 6,
        [opI32Store, 0x02, 0x04],
        [opLocalGet],
        encodeULEB128 5,
        [opElse],
        -- if (p < minInt32 as i64)
        [opLocalGet],
        encodeULEB128 2,
        [opI64Const],
        encodeSLEB128 (-2147483648),
        [opI64LtS],
        [opIf, blocktypeI32],
        -- then: Left (CRow rowTag(UnderflowError) (CCon 0 [])).
        -- inner = __alloc(4); store 0
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
        [opI32Store, 0x02, 0x00],
        -- row = __alloc(8); store rowTag(UnderflowError); store inner@offset=4
        [opI32Const],
        encodeSLEB128 8,
        [opCall],
        encodeULEB128 idxAlloc,
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
        -- cell = __alloc(8); store 0 (Left); store row@offset=4
        [opI32Const],
        encodeSLEB128 8,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 5,
        [opLocalGet],
        encodeULEB128 5,
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 5,
        [opLocalGet],
        encodeULEB128 6,
        [opI32Store, 0x02, 0x04],
        [opLocalGet],
        encodeULEB128 5,
        [opElse],
        -- ok: Right (i32.wrap_i64 p)
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
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 5,
        [opLocalGet],
        encodeULEB128 5,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 5,
        [opLocalGet],
        encodeULEB128 4,
        [opI32Store, 0x02, 0x04],
        [opLocalGet],
        encodeULEB128 5,
        [opEnd], -- end inner if
        [opEnd] -- end outer if
      ]

-- __negInt32(p: i32) -> i32
-- negInt32: Int32 -> Either OverflowError Int32. Mirror of 'codeSuccI32'
-- with INT32_MIN as the boundary and 'i32.sub 0 v' for the ok branch.
-- Locals: $v(1) $oe(2) $box(3) $cell(4).
codeNegI32 :: WasmInfo -> [Word8]
codeNegI32 _info =
  encodeBody
    (encodeLocals 4)
    $ concat
      [ -- v = i32.load(p)
        [opLocalGet],
        encodeULEB128 0,
        [opI32Load, 0x02, 0x00],
        [opLocalSet],
        encodeULEB128 1,
        -- if (v == INT32_MIN) result i32
        [opLocalGet],
        encodeULEB128 1,
        [opI32Const],
        encodeSLEB128 (-2147483648),
        [opI32Eq],
        [opIf, blocktypeI32],
        -- then: Left OverflowError
        [opI32Const],
        encodeSLEB128 4,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 2,
        [opLocalGet],
        encodeULEB128 2,
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store, 0x02, 0x00],
        [opI32Const],
        encodeSLEB128 8,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 4,
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 2,
        [opI32Store, 0x02, 0x04],
        [opLocalGet],
        encodeULEB128 4,
        [opElse],
        -- else: Right (-v)
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
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 4,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 4,
        [opLocalGet],
        encodeULEB128 3,
        [opI32Store, 0x02, 0x04],
        [opLocalGet],
        encodeULEB128 4,
        [opEnd]
      ]

-- __subUInt8(pa: i32, pb: i32) -> i32
-- subUInt8: UInt8 -> UInt8 -> Either UnderflowError UInt8. The i32
-- difference is in -255..255; one 'i32.lt_s 0' check picks the underflow
-- branch — no widening or mask needed.
-- Locals: $d(2) $ue(3) $box(4) $cell(5).
codeSubU8 :: WasmInfo -> [Word8]
codeSubU8 _info =
  encodeBody
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
        -- if (d < 0) result i32
        [opLocalGet],
        encodeULEB128 2,
        [opI32Const],
        encodeSLEB128 0,
        [opI32LtS],
        [opIf, blocktypeI32],
        -- then: Left UnderflowError
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
        [opI32Store, 0x02, 0x00],
        [opI32Const],
        encodeSLEB128 8,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 5,
        [opLocalGet],
        encodeULEB128 5,
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 5,
        [opLocalGet],
        encodeULEB128 3,
        [opI32Store, 0x02, 0x04],
        [opLocalGet],
        encodeULEB128 5,
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
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 5,
        [opLocalGet],
        encodeULEB128 5,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 5,
        [opLocalGet],
        encodeULEB128 4,
        [opI32Store, 0x02, 0x04],
        [opLocalGet],
        encodeULEB128 5,
        [opEnd]
      ]

-- __mulUInt8(pa: i32, pb: i32) -> i32
-- mulUInt8: UInt8 -> UInt8 -> Either OverflowError UInt8. Inputs in
-- 0..255 give an i32 product in 0..65025 — well within i32 range. A
-- single 'i32.gt_u 255' check picks the branch.
-- Locals: $p(2) $oe(3) $box(4) $cell(5).
codeMulU8 :: WasmInfo -> [Word8]
codeMulU8 _info =
  encodeBody
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
        -- if (p > 255) result i32
        [opLocalGet],
        encodeULEB128 2,
        [opI32Const],
        encodeSLEB128 255,
        [opI32GtU],
        [opIf, blocktypeI32],
        -- then: Left OverflowError
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
        [opI32Store, 0x02, 0x00],
        [opI32Const],
        encodeSLEB128 8,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 5,
        [opLocalGet],
        encodeULEB128 5,
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 5,
        [opLocalGet],
        encodeULEB128 3,
        [opI32Store, 0x02, 0x04],
        [opLocalGet],
        encodeULEB128 5,
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
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 5,
        [opLocalGet],
        encodeULEB128 5,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 5,
        [opLocalGet],
        encodeULEB128 4,
        [opI32Store, 0x02, 0x04],
        [opLocalGet],
        encodeULEB128 5,
        [opEnd]
      ]

-- __splitOnFirst(sep: i32, str: i32) -> i32
-- splitOnFirst: String -> String -> Maybe (Tuple2 String String). Hand-
-- rolled byte scan since WASM has no built-in substring search. The
-- empty-separator and "separator longer than str" cases are handled
-- implicitly by the loop bounds — see the WAT version for the
-- annotated structure.
-- Locals (beyond the two params): $sep_len(2) $str_len(3) $i(4) $j(5)
-- pos(6) $match(7) $prefix(8) $suffix(9) $tuple(10) $cell(11) $suf_len(12).
codeSplitOnFirst :: WasmInfo -> [Word8]
codeSplitOnFirst _info =
  encodeBody
    (encodeLocals 11)
    $ concat
      [ -- sep_len = strlen($sep)
        [opLocalGet],
        encodeULEB128 0,
        [opCall],
        encodeULEB128 idxStrlen,
        [opLocalSet],
        encodeULEB128 2,
        -- str_len = strlen($str)
        [opLocalGet],
        encodeULEB128 1,
        [opCall],
        encodeULEB128 idxStrlen,
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
        --         if (str[i+j] != sep[j])
        [opLocalGet],
        encodeULEB128 1, -- str
        [opLocalGet],
        encodeULEB128 4, -- i
        [opI32Add],
        [opLocalGet],
        encodeULEB128 5, -- j
        [opI32Add],
        [opI32Load8U, 0x00, 0x00],
        [opLocalGet],
        encodeULEB128 0, -- sep
        [opLocalGet],
        encodeULEB128 5, -- j
        [opI32Add],
        [opI32Load8U, 0x00, 0x00],
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
        [opIf, blocktypeI32],
        --   Nothing: cell = alloc 4; store tag 0; return cell
        [opI32Const],
        encodeSLEB128 4,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 11,
        [opLocalGet],
        encodeULEB128 11,
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 11,
        [opElse],
        --   prefix = alloc(pos + 1); memcpy(prefix, str, pos); store8 0 at end
        [opLocalGet],
        encodeULEB128 6, -- pos
        [opI32Const],
        encodeSLEB128 1,
        [opI32Add],
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 8, -- prefix
        [opLocalGet],
        encodeULEB128 8,
        [opLocalGet],
        encodeULEB128 1, -- str
        [opLocalGet],
        encodeULEB128 6, -- pos
        [opCall],
        encodeULEB128 idxMemcpy,
        [opLocalGet],
        encodeULEB128 8,
        [opLocalGet],
        encodeULEB128 6,
        [opI32Add],
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store8, 0x00, 0x00],
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
        --   suffix = alloc(suf_len + 1); memcpy; store8 0 at end
        [opLocalGet],
        encodeULEB128 12,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Add],
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 9, -- suffix
        [opLocalGet],
        encodeULEB128 9,
        [opLocalGet],
        encodeULEB128 1, -- str
        [opLocalGet],
        encodeULEB128 6, -- pos
        [opLocalGet],
        encodeULEB128 2, -- sep_len
        [opI32Add],
        [opI32Add],
        [opLocalGet],
        encodeULEB128 12, -- suf_len
        [opCall],
        encodeULEB128 idxMemcpy,
        [opLocalGet],
        encodeULEB128 9,
        [opLocalGet],
        encodeULEB128 12,
        [opI32Add],
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store8, 0x00, 0x00],
        --   tuple = alloc 12; [tag=0, prefix, suffix]
        [opI32Const],
        encodeSLEB128 12,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 10, -- tuple
        [opLocalGet],
        encodeULEB128 10,
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store, 0x02, 0x00],
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
        --   cell = alloc 8; [tag=1, tuple]
        [opI32Const],
        encodeSLEB128 8,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 11, -- cell
        [opLocalGet],
        encodeULEB128 11,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 11,
        [opLocalGet],
        encodeULEB128 10,
        [opI32Store, 0x02, 0x04],
        [opLocalGet],
        encodeULEB128 11,
        [opEnd] -- end if (cell now on stack as result)
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
codeParseInt32 _info =
  let -- Two local groups: 8 i32, then 1 i64.
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
            -- len = strlen($s)
            [opLocalGet],
            encodeULEB128 0,
            [opCall],
            encodeULEB128 idxStrlen,
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
            --   if (load8_u $s == 45) { $neg = 1; $i = 1; if ($len == 1) { $failed = 1; br $exit } }
            [opLocalGet],
            encodeULEB128 0,
            [opI32Load8U, 0x00, 0x00],
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
            --       $c = i32.load8_u(s + i)
            [opLocalGet],
            encodeULEB128 0,
            [opLocalGet],
            encodeULEB128 2,
            [opI32Add],
            [opI32Load8U, 0x00, 0x00],
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
            [opIf, blocktypeI32],
            -- pe = alloc 4; store tag 0
            [opI32Const],
            encodeSLEB128 4,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 7,
            [opLocalGet],
            encodeULEB128 7,
            [opI32Const],
            encodeSLEB128 0,
            [opI32Store, 0x02, 0x00],
            -- cell = alloc 8; tag 0; offset 4 = pe
            [opI32Const],
            encodeSLEB128 8,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 6,
            [opLocalGet],
            encodeULEB128 6,
            [opI32Const],
            encodeSLEB128 0,
            [opI32Store, 0x02, 0x00],
            [opLocalGet],
            encodeULEB128 6,
            [opLocalGet],
            encodeULEB128 7,
            [opI32Store, 0x02, 0x04],
            [opLocalGet],
            encodeULEB128 6,
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
            -- cell = alloc 8; tag 1; offset 4 = box
            [opI32Const],
            encodeSLEB128 8,
            [opCall],
            encodeULEB128 idxAlloc,
            [opLocalSet],
            encodeULEB128 6,
            [opLocalGet],
            encodeULEB128 6,
            [opI32Const],
            encodeSLEB128 1,
            [opI32Store, 0x02, 0x00],
            [opLocalGet],
            encodeULEB128 6,
            [opLocalGet],
            encodeULEB128 5,
            [opI32Store, 0x02, 0x04],
            [opLocalGet],
            encodeULEB128 6,
            [opEnd] -- end if
          ]

-- __parseUInt8(s: i32) -> i32
-- Same shape as 'codeParseInt32' minus the sign handling, with an i32
-- accumulator (the running magnitude never exceeds 2559 before the
-- > 255 check fails the parse).
-- Locals: $len(1) $i(2) $acc(3) $c(4) $box(5) $cell(6) $pe(7) $failed(8).
codeParseUInt8 :: WasmInfo -> [Word8]
codeParseUInt8 _info =
  encodeBody (encodeLocals 8)
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
        -- len = strlen($s)
        [opLocalGet],
        encodeULEB128 0,
        [opCall],
        encodeULEB128 idxStrlen,
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
        [opLocalGet],
        encodeULEB128 0,
        [opLocalGet],
        encodeULEB128 2,
        [opI32Add],
        [opI32Load8U, 0x00, 0x00],
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
        [opIf, blocktypeI32],
        [opI32Const],
        encodeSLEB128 4,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 7,
        [opLocalGet],
        encodeULEB128 7,
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store, 0x02, 0x00],
        [opI32Const],
        encodeSLEB128 8,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 6,
        [opLocalGet],
        encodeULEB128 6,
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 6,
        [opLocalGet],
        encodeULEB128 7,
        [opI32Store, 0x02, 0x04],
        [opLocalGet],
        encodeULEB128 6,
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
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 6,
        [opLocalGet],
        encodeULEB128 6,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Store, 0x02, 0x00],
        [opLocalGet],
        encodeULEB128 6,
        [opLocalGet],
        encodeULEB128 5,
        [opI32Store, 0x02, 0x04],
        [opLocalGet],
        encodeULEB128 6,
        [opEnd]
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
    (encodeLocals 6)
    $ concat
      [ -- v = i32.load(p)
        [opLocalGet],
        encodeULEB128 0,
        [opI32Load, 0x02, 0x00],
        [opLocalSet],
        encodeULEB128 1,
        -- buf = __alloc(16)
        [opI32Const],
        encodeSLEB128 16,
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 2,
        -- store null at buf+15
        [opLocalGet],
        encodeULEB128 2,
        [opI32Const],
        encodeSLEB128 15,
        [opI32Add],
        [opI32Const],
        encodeSLEB128 0,
        [opI32Store8, 0x00, 0x00],
        -- pos = 14
        [opI32Const],
        encodeSLEB128 14,
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
        -- return buf + (pos + 1)
        [opLocalGet],
        encodeULEB128 2,
        [opLocalGet],
        encodeULEB128 3,
        [opI32Const],
        encodeSLEB128 1,
        [opI32Add],
        [opI32Add]
      ]

-- __get_arg() -> i32
-- locals: $argv_buf(0), $ptrs(1)
codeGetArg :: WasmInfo -> [Word8]
codeGetArg info =
  encodeBody
    (encodeLocals 2)
    $ concat
      [ -- drop(args_sizes_get(12, 16))
        [opI32Const],
        encodeSLEB128 12,
        [opI32Const],
        encodeSLEB128 16,
        [opCall],
        encodeULEB128 1, -- args_sizes_get (import index 1)
        [opDrop],
        -- if (i32.load(12) < 2)
        [opI32Const],
        encodeSLEB128 0,
        [opI32Load, 0x02, 0x0C], -- align=2, offset=12 (loads argc)
        [opI32Const],
        encodeSLEB128 2,
        [opI32LtU],
        [opIf, blocktypeI32],
        -- then: return empty string offset
        [opI32Const],
        encodeSLEB128 (fromIntegral info.wiEmptyOff),
        [opElse],
        -- else: alloc argv_buf, alloc ptrs, call args_get, return argv[1]
        -- argv_buf = __alloc(i32.load(16))  -- argv_buf_size
        [opI32Const],
        encodeSLEB128 0,
        [opI32Load, 0x02, 0x10], -- align=2, offset=16
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 0, -- argv_buf
        -- ptrs = __alloc(argc * 4)
        [opI32Const],
        encodeSLEB128 0,
        [opI32Load, 0x02, 0x0C], -- argc
        [opI32Const],
        encodeSLEB128 4,
        [opI32Mul],
        [opCall],
        encodeULEB128 idxAlloc,
        [opLocalSet],
        encodeULEB128 1, -- ptrs
        -- drop(args_get(ptrs, argv_buf))
        [opLocalGet],
        encodeULEB128 1,
        [opLocalGet],
        encodeULEB128 0,
        [opCall],
        encodeULEB128 2, -- args_get (import index 2)
        [opDrop],
        -- return i32.load(ptrs + 4)  -- argv[1]
        [opLocalGet],
        encodeULEB128 1,
        [opI32Load, 0x02, 0x04], -- align=2, offset=4
        [opEnd]
      ]

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
  _ -> 0

exprHasCCase :: CExpr -> Bool
exprHasCCase = \case
  CCase {} -> True
  CRowCase {} -> True
  CCall f xs -> exprHasCCase f || any exprHasCCase xs
  CLoop b -> exprHasCCase b
  CContinue xs -> any exprHasCCase xs
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
  _ -> 0

codeUserDecl :: WasmInfo -> Map FuncType Word32 -> CDecl -> [Word8]
codeUserDecl info typeMap = \case
  -- TCO-wrapped body. WASM params are already mutable locals, so we only
  -- need 'nParams' extra slots to stage 'CContinue' arguments (so a new
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
        totalSlots = tcoTempBase + nParams
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
              ecBoundBase = boundBase
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
        totalSlots = boundBase + fromIntegral maxBV
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
              ecBoundBase = boundBase
            }
     in encodeBody (encodeLocals nExtraLocals) (emitExpr ctx body)
  CValDef _nm rhs ->
    let conDepthNeeded = exprMaxConDepth rhs
        needsScrut = exprHasCCase rhs
        conBaseSlot = 0 :: Word32
        nextAfterCon = conBaseSlot + fromIntegral conDepthNeeded
        scrutSlot = nextAfterCon
        nextAfterScrut = if needsScrut then scrutSlot + 1 else scrutSlot
        boundBase = nextAfterScrut
        maxBV = exprMaxBoundVars rhs
        totalSlots = boundBase + fromIntegral maxBV
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
              ecBoundBase = boundBase
            }
     in encodeBody (encodeLocals nExtraLocals) (emitExpr ctx rhs)

-- _start: calls v_main(__get_arg()), drops result
codeStart :: WasmInfo -> [Word8]
codeStart info =
  let mainIdx = fromMaybe 0 (Map.lookup "main" info.wiFuncIdx)
   in encodeBody
        (encodeLocals 0)
        $ concat
          [ [opCall],
            encodeULEB128 idxGetArg,
            [opCall],
            encodeULEB128 mainIdx,
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
    ecBoundBase :: Word32 -- first local slot for case-bound variables
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
        conSlot = ctx.ecConBaseSlot + fromIntegral ctx.ecConDepth
        nestedCtx = ctx {ecConDepth = ctx.ecConDepth + 1}
        -- allocate (nSlots * 4) bytes, store pointer to conSlot
        allocCode =
          [opI32Const]
            <> encodeSLEB128 (fromIntegral (nSlots * 4))
            <> [opCall]
            <> encodeULEB128 idxAlloc
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
        -- store each field at offset (i+1)*4
        storeField (fld, i) =
          [opLocalGet]
            <> encodeULEB128 conSlot
            <> emitExpr nestedCtx fld
            <> [opI32Store]
            <> encodeULEB128 2
            <> encodeULEB128 (fromIntegral ((i + 1) * 4 :: Int))
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
      CBuiltIn "IO.Stdout.print"
        | [x] <- xs ->
            emitExpr ctx x
              <> [opCall]
              <> encodeULEB128 idxPrint
      CBuiltIn name
        | name == "showInt32" || name == "showUInt8",
          [x] <- xs ->
            emitExpr ctx x
              <> [opCall]
              <> encodeULEB128 idxShowI32
      CBuiltIn "predInt32"
        | [x] <- xs ->
            emitExpr ctx x
              <> [opCall]
              <> encodeULEB128 idxPredI32
      CBuiltIn "predUInt8"
        | [x] <- xs ->
            emitExpr ctx x
              <> [opCall]
              <> encodeULEB128 idxPredU8
      CBuiltIn "succInt32"
        | [x] <- xs ->
            emitExpr ctx x
              <> [opCall]
              <> encodeULEB128 idxSuccI32
      CBuiltIn "succUInt8"
        | [x] <- xs ->
            emitExpr ctx x
              <> [opCall]
              <> encodeULEB128 idxSuccU8
      CBuiltIn name
        | name == "eqInt32" || name == "eqUInt8",
          [a, b] <- xs ->
            emitExpr ctx a
              <> emitExpr ctx b
              <> [opCall]
              <> encodeULEB128 idxEqI32
      CBuiltIn name
        | name == "addInt32" || name == "addUInt8" || name == "subInt32" || name == "subUInt8" || name == "mulUInt8" || name == "mulInt32",
          [a, b] <- xs ->
            let idx = case name of
                  "addInt32" -> idxAddI32
                  "addUInt8" -> idxAddU8
                  "subInt32" -> idxSubI32
                  "subUInt8" -> idxSubU8
                  "mulInt32" -> idxMulI32
                  _ -> idxMulU8
             in emitExpr ctx a
                  <> emitExpr ctx b
                  <> [opCall]
                  <> encodeULEB128 idx
      CBuiltIn "negInt32"
        | [x] <- xs ->
            emitExpr ctx x
              <> [opCall]
              <> encodeULEB128 idxNegI32
      CBuiltIn "splitOnFirst"
        | [a, b] <- xs ->
            emitExpr ctx a
              <> emitExpr ctx b
              <> [opCall]
              <> encodeULEB128 idxSplitOnFirst
      CBuiltIn name
        | name == "parseInt32" || name == "parseUInt8",
          [x] <- xs ->
            let idx = if name == "parseInt32" then idxParseI32 else idxParseU8
             in emitExpr ctx x
                  <> [opCall]
                  <> encodeULEB128 idx
      CBuiltIn "concatString"
        | [a, b] <- xs ->
            emitExpr ctx a
              <> emitExpr ctx b
              <> [opCall]
              <> encodeULEB128 idxConcat
      CBuiltIn n ->
        error ("WASM codegen: unknown builtin '" <> n <> "' reached CCall (typecheck should have rejected it)")
      CVar n
        | n `Set.member` ctx.ecFunDefs ->
            let fIdx = fromMaybe 0 (Map.lookup n ctx.ecFuncIdx)
             in concatMap (emitExpr ctx) xs
                  <> [opCall]
                  <> encodeULEB128 fIdx
      _ ->
        let arity = length xs
            typeIdx = lookupType (FuncType arity True) ctx.ecTypeMap
         in concatMap (emitExpr ctx) xs
              <> emitExpr ctx f
              <> [opCallIndirect]
              <> encodeULEB128 typeIdx
              <> encodeULEB128 0 -- table index 0
  CLoop _ -> error "WASM Assemble: CLoop survived untcoProgram (pipeline bug)"
  CContinue _ -> error "WASM Assemble: CContinue survived untcoProgram (pipeline bug)"

-- | Emit a case expression as nested if/else in binary WASM.
-- Stores scrutinee pointer to $__scrut, loads tag, then chains if/else arms.
emitCaseChain :: ExprCtx -> CExpr -> [(Int, [Text], CExpr)] -> [Word8]
emitCaseChain _ctx _scrut [] = [opI32Const] <> encodeSLEB128 0 -- unreachable
emitCaseChain ctx scrut alts =
  let scrutSlot = ctx.ecScrutSlot
      -- evaluate scrutinee and store to scrut local
      storeCode =
        emitExpr ctx scrut
          <> [opLocalSet]
          <> encodeULEB128 scrutSlot
   in storeCode <> emitArmChain ctx alts

-- | Emit the if/else chain for case arms (scrutinee already in $__scrut).
emitArmChain :: ExprCtx -> [(Int, [Text], CExpr)] -> [Word8]
emitArmChain _ctx [] = [opI32Const] <> encodeSLEB128 0
emitArmChain ctx [(_, vars, body)] =
  -- Last arm: bind vars and emit body, no tag comparison needed
  let (bindCode, ctx') = bindArmVars ctx vars
   in bindCode <> emitExpr ctx' body
emitArmChain ctx ((tag, vars, body) : rest) =
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
   in loadTag
        <> cmpCode
        <> [opIf, blocktypeI32]
        <> bindCode
        <> emitExpr ctx' body
        <> [opElse]
        <> emitArmChain ctx rest
        <> [opEnd]

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
            bc =
              [opLocalGet]
                <> encodeULEB128 scrutSlot
                <> [opI32Load]
                <> encodeULEB128 2
                <> encodeULEB128 offset
                <> [opLocalSet]
                <> encodeULEB128 slot
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
-- stage 'CContinue' arguments, so a new value that reads a still-old
-- parameter sees the old binding rather than a half-updated one.
emitTailBin :: Word32 -> [Text] -> Word32 -> ExprCtx -> CExpr -> [Word8]
emitTailBin tcoTempBase params depth ctx = \case
  CContinue newArgs ->
    let evals =
          concat
            [ emitExpr ctx a
                <> [opLocalSet]
                <> encodeULEB128 (tcoTempBase + fromIntegral i)
            | (i, a) <- zip [0 :: Int ..] newArgs
            ]
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
     in evals <> copies <> [opBr] <> encodeULEB128 depth
  CCase scrut alts ->
    let sorted = sortWith (\(t, _, _) -> t) alts
        scrutCode =
          emitExpr ctx scrut
            <> [opLocalSet]
            <> encodeULEB128 ctx.ecScrutSlot
     in scrutCode <> emitTailArmChain tcoTempBase params depth ctx sorted
  other -> emitExpr ctx other

-- | Tail version of 'emitArmChain': each arm is emitted in tail form so
-- it either produces an @i32@ result or terminates with a @br@ back to
-- the loop. Nesting into an @opIf@ increases 'depth' by one for both the
-- then-body and the else-continuation.
emitTailArmChain :: Word32 -> [Text] -> Word32 -> ExprCtx -> [(Int, [Text], CExpr)] -> [Word8]
emitTailArmChain _ _ _ _ [] = [opI32Const] <> encodeSLEB128 0
emitTailArmChain tcoTempBase params depth ctx [(_, vars, body)] =
  let (bindCode, ctx') = bindArmVars ctx vars
   in bindCode <> emitTailBin tcoTempBase params depth ctx' body
emitTailArmChain tcoTempBase params depth ctx ((tag, vars, body) : rest) =
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
   in loadTag
        <> cmpCode
        <> [opIf, blocktypeI32]
        <> bindCode
        <> emitTailBin tcoTempBase params (depth + 1) ctx' body
        <> [opElse]
        <> emitTailArmChain tcoTempBase params (depth + 1) ctx rest
        <> [opEnd]

-- ════════════════════════════════════════════════════════════════════════════
-- Data section
-- ════════════════════════════════════════════════════════════════════════════

buildDataSection :: WasmInfo -> [Word8]
buildDataSection info =
  let pool = sortWith snd (Map.toList info.wiStringPool)
      mkSegment (s, off) =
        [0x00] -- active, memory 0
          <> [opI32Const]
          <> encodeSLEB128 (fromIntegral off)
          <> [opEnd]
          <> encodeBytes (BS.unpack (encodeUtf8 s) <> [0x00]) -- null-terminated
      content = encodeVec (map mkSegment pool)
   in buildSection 11 content

-- ════════════════════════════════════════════════════════════════════════════
-- Module assembly
-- ════════════════════════════════════════════════════════════════════════════

buildModule :: CoreProgram -> B.Builder
buildModule prog =
  let info = buildInfo prog
      (typeSec, typeMap) = buildTypeSection info prog
      importSec = buildImportSection typeMap
      funcSec = buildFunctionSection info typeMap prog
      tableSec = buildTableSection info
      memorySec = buildMemorySection
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
