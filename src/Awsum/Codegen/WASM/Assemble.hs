-- | WebAssembly binary (.wasm) assembler for Awsum 'Core'.
--
-- Generates a single @.wasm@ module with WASI imports for I\/O.
-- All values are @i32@ (pointers into linear memory). Strings are
-- null-terminated bytes. Bump allocator for dynamic memory.
-- @funcref@ table for higher-order functions.
module Awsum.Codegen.WASM.Assemble (assembleWASM) where

import Awsum.Core
import Data.Bits (shiftR, (.&.), (.|.))
import Data.ByteString qualified as BS
import Data.ByteString.Builder qualified as B
import Data.ByteString.Lazy qualified as BL
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Relude

-- ════════════════════════════════════════════════════════════════════════════
-- Public API
-- ════════════════════════════════════════════════════════════════════════════

-- | Produce a complete .wasm binary as a strict ByteString.
assembleWASM :: CoreProgram -> BS.ByteString
assembleWASM prog = BL.toStrict (B.toLazyByteString (buildModule prog))

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
  let bs = BS.unpack (TE.encodeUtf8 t)
   in encodeULEB128 (fromIntegral (length bs)) <> bs

-- ════════════════════════════════════════════════════════════════════════════
-- WASM opcodes
-- ════════════════════════════════════════════════════════════════════════════

op_block, op_loop, op_if, op_else, op_end :: Word8
op_block = 0x02
op_loop = 0x03
op_if = 0x04
op_else = 0x05
op_end = 0x0B

op_br, op_br_if, op_call, op_call_indirect, op_drop :: Word8
op_br = 0x0C
op_br_if = 0x0D
op_call = 0x10
op_call_indirect = 0x11
op_drop = 0x1A

op_local_get, op_local_set, op_global_get, op_global_set :: Word8
op_local_get = 0x20
op_local_set = 0x21
op_global_get = 0x23
op_global_set = 0x24

op_i32_load, op_i32_load8_u, op_i32_store, op_i32_store8 :: Word8
op_i32_load = 0x28
op_i32_load8_u = 0x2D
op_i32_store = 0x36
op_i32_store8 = 0x3A

op_i32_const :: Word8
op_i32_const = 0x41

op_i32_eqz, op_i32_add, op_i32_mul, op_i32_and, op_i32_lt_u, op_i32_ge_u :: Word8
op_i32_eqz = 0x45
op_i32_add = 0x6A
op_i32_mul = 0x6C
op_i32_and = 0x71
op_i32_lt_u = 0x49
op_i32_ge_u = 0x4F

-- WASM type encoding
valtype_i32 :: Word8
valtype_i32 = 0x7F

blocktype_void :: Word8
blocktype_void = 0x40

blocktype_i32 :: Word8
blocktype_i32 = valtype_i32

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

-- Runtime helper count: __strlen, __alloc, __memcpy, __concat, __print, __get_arg
runtimeCount :: Word32
runtimeCount = 6

-- Runtime helper function indices (after imports)
idxStrlen, idxAlloc, idxMemcpy, idxConcat, idxPrint, idxGetArg :: Word32
idxStrlen = importCount
idxAlloc = importCount + 1
idxMemcpy = importCount + 2
idxConcat = importCount + 3
idxPrint = importCount + 4
idxGetArg = importCount + 5

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
  CPrim _ -> []
  CCall f xs -> stringsInExpr f <> concatMap stringsInExpr xs

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
          $
          -- WASI imports
          [ FuncType 4 True, -- fd_write
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
          <> encodeVec (replicate nParams [valtype_i32])
          <> if hasResult
            then encodeVec [[valtype_i32]]
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
          [ [valtype_i32, 0x01] -- i32, mutable
              <> [op_i32_const]
              <> encodeSLEB128 (fromIntegral info.wiHeapStart)
              <> [op_end]
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
                  <> [op_i32_const]
                  <> encodeSLEB128 0
                  <> [op_end]
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
  let body = locals <> instrs <> [op_end]
   in encodeBytes body

-- | Encode local variable declarations.
encodeLocals :: Int -> [Word8]
encodeLocals n
  | n == 0 = encodeULEB128 0
  | otherwise = encodeVec [encodeULEB128 (fromIntegral n) <> [valtype_i32]]

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
        [op_i32_const],
        encodeSLEB128 0,
        [op_local_set],
        encodeULEB128 1,
        -- block $break
        [op_block, blocktype_void],
        -- loop $loop
        [op_loop, blocktype_void],
        -- br_if $break (i32.eqz (i32.load8_u (s + len)))
        [op_local_get],
        encodeULEB128 0, -- s
        [op_local_get],
        encodeULEB128 1, -- len
        [op_i32_add],
        [op_i32_load8_u, 0x00, 0x00], -- align=0, offset=0
        [op_i32_eqz],
        [op_br_if],
        encodeULEB128 1, -- break (label 1)
        -- len = len + 1
        [op_local_get],
        encodeULEB128 1,
        [op_i32_const],
        encodeSLEB128 1,
        [op_i32_add],
        [op_local_set],
        encodeULEB128 1,
        -- br $loop
        [op_br],
        encodeULEB128 0,
        -- end loop, end block
        [op_end],
        [op_end],
        -- return len
        [op_local_get],
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
        [op_global_get],
        encodeULEB128 0,
        [op_i32_const],
        encodeSLEB128 3,
        [op_i32_add],
        [op_i32_const],
        encodeSLEB128 (-4),
        [op_i32_and],
        [op_local_set],
        encodeULEB128 1,
        -- global.set $heap (ptr + size)
        [op_local_get],
        encodeULEB128 1, -- ptr
        [op_local_get],
        encodeULEB128 0, -- size
        [op_i32_add],
        [op_global_set],
        encodeULEB128 0,
        -- return ptr
        [op_local_get],
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
        [op_i32_const],
        encodeSLEB128 0,
        [op_local_set],
        encodeULEB128 3,
        -- block $break
        [op_block, blocktype_void],
        -- loop $loop
        [op_loop, blocktype_void],
        -- br_if $break (i >= len)
        [op_local_get],
        encodeULEB128 3, -- i
        [op_local_get],
        encodeULEB128 2, -- len
        [op_i32_ge_u],
        [op_br_if],
        encodeULEB128 1,
        -- i32.store8 (dst+i) (i32.load8_u (src+i))
        [op_local_get],
        encodeULEB128 0, -- dst
        [op_local_get],
        encodeULEB128 3, -- i
        [op_i32_add],
        [op_local_get],
        encodeULEB128 1, -- src
        [op_local_get],
        encodeULEB128 3, -- i
        [op_i32_add],
        [op_i32_load8_u, 0x00, 0x00],
        [op_i32_store8, 0x00, 0x00],
        -- i = i + 1
        [op_local_get],
        encodeULEB128 3,
        [op_i32_const],
        encodeSLEB128 1,
        [op_i32_add],
        [op_local_set],
        encodeULEB128 3,
        -- br $loop
        [op_br],
        encodeULEB128 0,
        [op_end],
        [op_end]
      ]

-- __concat(a: i32, b: i32) -> i32
-- locals: $la, $lb, $buf (slots 2,3,4)
codeConcat :: WasmInfo -> [Word8]
codeConcat _info =
  encodeBody
    (encodeLocals 3)
    $ concat
      [ -- la = __strlen(a)
        [op_local_get],
        encodeULEB128 0,
        [op_call],
        encodeULEB128 idxStrlen,
        [op_local_set],
        encodeULEB128 2,
        -- lb = __strlen(b)
        [op_local_get],
        encodeULEB128 1,
        [op_call],
        encodeULEB128 idxStrlen,
        [op_local_set],
        encodeULEB128 3,
        -- buf = __alloc(la + lb + 1)
        [op_local_get],
        encodeULEB128 2,
        [op_local_get],
        encodeULEB128 3,
        [op_i32_add],
        [op_i32_const],
        encodeSLEB128 1,
        [op_i32_add],
        [op_call],
        encodeULEB128 idxAlloc,
        [op_local_set],
        encodeULEB128 4,
        -- __memcpy(buf, a, la)
        [op_local_get],
        encodeULEB128 4,
        [op_local_get],
        encodeULEB128 0,
        [op_local_get],
        encodeULEB128 2,
        [op_call],
        encodeULEB128 idxMemcpy,
        -- __memcpy(buf+la, b, lb)
        [op_local_get],
        encodeULEB128 4,
        [op_local_get],
        encodeULEB128 2,
        [op_i32_add],
        [op_local_get],
        encodeULEB128 1,
        [op_local_get],
        encodeULEB128 3,
        [op_call],
        encodeULEB128 idxMemcpy,
        -- i32.store8 (buf+la+lb) 0
        [op_local_get],
        encodeULEB128 4,
        [op_local_get],
        encodeULEB128 2,
        [op_i32_add],
        [op_local_get],
        encodeULEB128 3,
        [op_i32_add],
        [op_i32_const],
        encodeSLEB128 0,
        [op_i32_store8, 0x00, 0x00],
        -- return buf
        [op_local_get],
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
        [op_local_get],
        encodeULEB128 0,
        [op_call],
        encodeULEB128 idxStrlen,
        [op_local_set],
        encodeULEB128 1,
        -- i32.store offset=0 (i32.const 0) s  -- iov_base
        [op_i32_const],
        encodeSLEB128 0,
        [op_local_get],
        encodeULEB128 0,
        [op_i32_store, 0x02, 0x00], -- align=2 (4-byte), offset=0
        -- i32.store offset=4 (i32.const 0) len  -- iov_len
        [op_i32_const],
        encodeSLEB128 0,
        [op_local_get],
        encodeULEB128 1,
        [op_i32_store, 0x02, 0x04], -- align=2, offset=4
        -- drop(fd_write(1, 0, 1, 8))
        [op_i32_const],
        encodeSLEB128 1, -- fd = stdout
        [op_i32_const],
        encodeSLEB128 0, -- iovs ptr
        [op_i32_const],
        encodeSLEB128 1, -- iovs_len
        [op_i32_const],
        encodeSLEB128 8, -- nwritten ptr
        [op_call],
        encodeULEB128 0, -- fd_write (import index 0)
        [op_drop],
        -- return 0
        [op_i32_const],
        encodeSLEB128 0
      ]

-- __get_arg() -> i32
-- locals: $argv_buf(0), $ptrs(1)
codeGetArg :: WasmInfo -> [Word8]
codeGetArg info =
  encodeBody
    (encodeLocals 2)
    $ concat
      [ -- drop(args_sizes_get(12, 16))
        [op_i32_const],
        encodeSLEB128 12,
        [op_i32_const],
        encodeSLEB128 16,
        [op_call],
        encodeULEB128 1, -- args_sizes_get (import index 1)
        [op_drop],
        -- if (i32.load(12) < 2)
        [op_i32_const],
        encodeSLEB128 0,
        [op_i32_load, 0x02, 0x0C], -- align=2, offset=12 (loads argc)
        [op_i32_const],
        encodeSLEB128 2,
        [op_i32_lt_u],
        [op_if, blocktype_i32],
        -- then: return empty string offset
        [op_i32_const],
        encodeSLEB128 (fromIntegral info.wiEmptyOff),
        [op_else],
        -- else: alloc argv_buf, alloc ptrs, call args_get, return argv[1]
        -- argv_buf = __alloc(i32.load(16))  -- argv_buf_size
        [op_i32_const],
        encodeSLEB128 0,
        [op_i32_load, 0x02, 0x10], -- align=2, offset=16
        [op_call],
        encodeULEB128 idxAlloc,
        [op_local_set],
        encodeULEB128 0, -- argv_buf
        -- ptrs = __alloc(argc * 4)
        [op_i32_const],
        encodeSLEB128 0,
        [op_i32_load, 0x02, 0x0C], -- argc
        [op_i32_const],
        encodeSLEB128 4,
        [op_i32_mul],
        [op_call],
        encodeULEB128 idxAlloc,
        [op_local_set],
        encodeULEB128 1, -- ptrs
        -- drop(args_get(ptrs, argv_buf))
        [op_local_get],
        encodeULEB128 1,
        [op_local_get],
        encodeULEB128 0,
        [op_call],
        encodeULEB128 2, -- args_get (import index 2)
        [op_drop],
        -- return i32.load(ptrs + 4)  -- argv[1]
        [op_local_get],
        encodeULEB128 1,
        [op_i32_load, 0x02, 0x04], -- align=2, offset=4
        [op_end]
      ]

-- ════════════════════════════════════════════════════════════════════════════
-- User declaration code
-- ════════════════════════════════════════════════════════════════════════════

codeUserDecl :: WasmInfo -> Map FuncType Word32 -> CDecl -> [Word8]
codeUserDecl info typeMap = \case
  CFunDef _nm args body ->
    let paramMap = Map.fromList (zip args [0 :: Word32 ..])
        ctx =
          ExprCtx
            { ecParams = paramMap,
              ecValDefs = info.wiValDefs,
              ecFunDefs = info.wiFunDefs,
              ecArities = info.wiArities,
              ecStringPool = info.wiStringPool,
              ecTableMap = info.wiTableMap,
              ecFuncIdx = info.wiFuncIdx,
              ecTypeMap = typeMap,
              ecIndirectArities = info.wiIndirectArities
            }
     in encodeBody (encodeLocals 0) (emitExpr ctx body)
  CValDef _nm rhs ->
    let ctx =
          ExprCtx
            { ecParams = Map.empty,
              ecValDefs = info.wiValDefs,
              ecFunDefs = info.wiFunDefs,
              ecArities = info.wiArities,
              ecStringPool = info.wiStringPool,
              ecTableMap = info.wiTableMap,
              ecFuncIdx = info.wiFuncIdx,
              ecTypeMap = typeMap,
              ecIndirectArities = info.wiIndirectArities
            }
     in encodeBody (encodeLocals 0) (emitExpr ctx rhs)

-- _start: calls v_main(__get_arg()), drops result
codeStart :: WasmInfo -> [Word8]
codeStart info =
  let mainIdx = fromMaybe 0 (Map.lookup "main" info.wiFuncIdx)
   in encodeBody
        (encodeLocals 0)
        $ concat
          [ [op_call],
            encodeULEB128 idxGetArg,
            [op_call],
            encodeULEB128 mainIdx,
            [op_drop]
          ]

-- ════════════════════════════════════════════════════════════════════════════
-- Expression code generation
-- ════════════════════════════════════════════════════════════════════════════

data ExprCtx = ExprCtx
  { ecParams :: Map Text Word32,
    ecValDefs :: Set Text,
    ecFunDefs :: Set Text,
    ecArities :: Map Text Int,
    ecStringPool :: Map Text Int,
    ecTableMap :: Map Text Int,
    ecFuncIdx :: Map Text Word32,
    ecTypeMap :: Map FuncType Word32,
    ecIndirectArities :: Set Int
  }

emitExpr :: ExprCtx -> CExpr -> [Word8]
emitExpr ctx = \case
  CString s ->
    let offset = fromMaybe (error $ "string not in pool: " <> show s) (Map.lookup s ctx.ecStringPool)
     in [op_i32_const] <> encodeSLEB128 (fromIntegral offset)
  CVar n
    | Just slot <- Map.lookup n ctx.ecParams ->
        [op_local_get] <> encodeULEB128 slot
    | n `Set.member` ctx.ecValDefs ->
        let fIdx = fromMaybe 0 (Map.lookup n ctx.ecFuncIdx)
         in [op_call] <> encodeULEB128 fIdx
    | n `Set.member` ctx.ecFunDefs ->
        let tblIdx = fromMaybe 0 (Map.lookup n ctx.ecTableMap)
         in [op_i32_const] <> encodeSLEB128 (fromIntegral tblIdx)
    | otherwise ->
        [op_i32_const] <> encodeSLEB128 0
  CPrim _ ->
    [op_i32_const] <> encodeSLEB128 0
  CCall f xs ->
    case f of
      CPrim PrimConcat
        | [a, b] <- xs ->
            emitExpr ctx a
              <> emitExpr ctx b
              <> [op_call]
              <> encodeULEB128 idxConcat
      CPrim PrimPrint
        | [x] <- xs ->
            emitExpr ctx x
              <> [op_call]
              <> encodeULEB128 idxPrint
      CVar n
        | n `Set.member` ctx.ecFunDefs ->
            let fIdx = fromMaybe 0 (Map.lookup n ctx.ecFuncIdx)
             in concatMap (emitExpr ctx) xs
                  <> [op_call]
                  <> encodeULEB128 fIdx
      _ ->
        let arity = length xs
            typeIdx = lookupType (FuncType arity True) ctx.ecTypeMap
         in concatMap (emitExpr ctx) xs
              <> emitExpr ctx f
              <> [op_call_indirect]
              <> encodeULEB128 typeIdx
              <> encodeULEB128 0 -- table index 0

-- ════════════════════════════════════════════════════════════════════════════
-- Data section
-- ════════════════════════════════════════════════════════════════════════════

buildDataSection :: WasmInfo -> [Word8]
buildDataSection info =
  let pool = sortOn snd (Map.toList info.wiStringPool)
      mkSegment (s, off) =
        [0x00] -- active, memory 0
          <> [op_i32_const]
          <> encodeSLEB128 (fromIntegral off)
          <> [op_end]
          <> encodeBytes (BS.unpack (TE.encodeUtf8 s) <> [0x00]) -- null-terminated
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
