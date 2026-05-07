-- | LLVM IR code generator for Awsum 'Core'.
--
-- Design goals:
--   * Emit textual LLVM IR (.ll) that can be compiled with @clang@.
--   * Keep a tiny C-based runtime (malloc/strlen/strcpy/strcat/printf).
--   * Mirror JS backend semantics for cross-backend equivalence.
--
-- Semantics & assumptions:
--   * All values are opaque pointers (@ptr@, LLVM 15+).
--   * Strings are null-terminated C strings (@ptr@ to @[N x i8]@).
--   * Concatenation: @strlen + malloc + strcpy + strcat@.
--   * Print: @printf("%s", s)@ — buffered, flushed on exit.
--   * Zero-arg surface defs ('CValDef') become zero-arg LLVM functions.
--     Pure expressions, so recomputation is safe.
--   * The C @main@ entry point reads @argv[1]@ and calls @v_main@.
module Awsum.Codegen.LLVM
  ( codegenLLVM,
    LLVMHost,
    allLLVMHosts,
    llvmHostName,
    llvmHostFromSystem,
    llvmHostLinkerFlags,
  )
where

import Awsum.Core
import Awsum.HM (rowTag)
import Awsum.Syntax (Name, Type' (..), noSpan)
import Data.ByteString qualified as BS
import Data.Char qualified as Char
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Relude
import System.Info qualified as Info

-- ════════════════════════════════════════════════════════════════════════════
-- Public API
-- ════════════════════════════════════════════════════════════════════════════

-- | The host environment the emitted IR is meant to be linked and run on.
--   Decides which @main@ entry point shape we generate (POSIX argv vs the
--   Windows GetCommandLineW path) and which extra @-l@ flags clang needs at
--   link time. The CLI derives this from 'System.Info.os' once via
--   'llvmHostFromSystem'; the snapshot test framework iterates all values
--   so per-host IR is asserted on every CI host.
data LLVMHost = LLVMPosix | LLVMWindows
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | Every supported host, used by snapshot tests to assert one IR file
--   per host on every test run regardless of which host is doing the run.
allLLVMHosts :: [LLVMHost]
allLLVMHosts = universe

-- | Stable lowercase name suitable for snapshot file paths
--   (@compiled.posix.ll@, @compiled.windows.ll@).
llvmHostName :: LLVMHost -> Text
llvmHostName = \case
  LLVMPosix -> "posix"
  LLVMWindows -> "windows"

-- | Detect the natural host for the awsum binary running this code.
--   GHC reports @"mingw32"@ for any Windows build regardless of which
--   external clang/linker the user has installed.
llvmHostFromSystem :: LLVMHost
llvmHostFromSystem
  | Info.os == "mingw32" = LLVMWindows
  | otherwise = LLVMPosix

-- | Extra clang flags required to actually link the IR for a given host.
--   Windows needs explicit @-lshell32 -lkernel32@ because @footerWindows@
--   calls 'CommandLineToArgvW' and friends — mingw-w64 auto-links those,
--   but MSVC's CRT only carries kernel32, so the explicit flag is what
--   closes @LNK2019: unresolved external symbol CommandLineToArgvW@.
--   Harmless on mingw-w64 (already in the auto-link line).
llvmHostLinkerFlags :: LLVMHost -> [String]
llvmHostLinkerFlags = \case
  LLVMPosix -> []
  LLVMWindows -> ["-lshell32", "-lkernel32"]

-- | Produce a complete LLVM IR module from a Core program for a given host.
codegenLLVM :: LLVMHost -> CoreProgram -> Text
codegenLLVM host prog@(CoreProgram decls) =
  let pool = collectStrings prog
      valDefNames = Set.fromList [n | CValDef n _ <- decls]
      ctx = EmitCtx {params = Set.empty, valDefs = valDefNames, stringPool = pool, locals = Map.empty, loopCtx = Nothing}
      userCode = evalState (T.intercalate "\n\n" <$> traverse (emitDecl ctx) decls) 0
      builtIns = usedBuiltIns prog
   in T.intercalate
        "\n"
        [ header builtIns,
          emitStringConstants pool,
          runtime builtIns,
          userCode,
          footer host
        ]

-- ════════════════════════════════════════════════════════════════════════════
-- Context
-- ════════════════════════════════════════════════════════════════════════════

data EmitCtx = EmitCtx
  { params :: Set Text,
    valDefs :: Set Text,
    stringPool :: StringPool,
    locals :: Map Text Text, -- case-bound variable name → SSA temp

    -- | @Just@ while we are emitting a 'CFunDef' body wrapped in 'CLoop'.
    -- Carries the label / alloca-slot names the TCO pass's 'CContinue'
    -- and the implicit @ret@ need. 'Nothing' outside a loop, so emitting
    -- a 'CContinue' there is a pipeline bug, not a code path.
    loopCtx :: Maybe LoopCtx
  }

-- | Scaffolding the 'CFunDef' prologue sets up so 'emitTail' can emit
-- either a jump back to the loop head (for 'CContinue') or a jump to a
-- single exit block that performs the one real @ret@.
data LoopCtx = LoopCtx
  { lcLoopLabel :: Text,
    lcExitLabel :: Text,
    lcRetSlot :: Text,
    -- | Parameter → alloca slot SSA name, one per original parameter.
    -- A 'CContinue' evaluates its arguments in order, then @store@s
    -- each into the matching slot before branching to the loop head.
    lcParamSlots :: [(Text, Text)]
  }

-- ════════════════════════════════════════════════════════════════════════════
-- SSA temp generation
-- ════════════════════════════════════════════════════════════════════════════

type CodegenM = State Int

freshTemp :: CodegenM Text
freshTemp = do
  n <- get
  modify' (+ 1)
  pure ("%t" <> show n)

freshLabel :: Text -> CodegenM Text
freshLabel prefix = do
  n <- get
  modify' (+ 1)
  pure (prefix <> "." <> show n)

-- ════════════════════════════════════════════════════════════════════════════
-- String constant pool
-- ════════════════════════════════════════════════════════════════════════════

type StringPool = Map Text Int

collectStrings :: CoreProgram -> StringPool
collectStrings (CoreProgram decls) =
  let strs = ordNub $ concatMap stringsInDecl decls
   in Map.fromList (zip strs [0 ..])

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

emitStringConstants :: StringPool -> Text
emitStringConstants pool
  | Map.null pool = ""
  | otherwise =
      T.intercalate "\n" (map emitOne (sortWith snd $ Map.toList pool)) <> "\n"
  where
    emitOne (s, i) =
      let escaped = llvmEscapeString s
          len = BS.length (encodeUtf8 s) + 1
       in "@.str."
            <> show i
            <> " = private unnamed_addr constant ["
            <> show len
            <> " x i8] c\""
            <> escaped
            <> "\\00\""

-- | Escape a string for LLVM IR constant syntax. ASCII printable bytes pass
--   through; everything else (including non-ASCII codepoints, which encode
--   to multi-byte UTF-8 sequences) becomes @\\XX@ hex pairs per byte.
llvmEscapeString :: Text -> Text
llvmEscapeString = T.concat . map escByte . BS.unpack . encodeUtf8
  where
    escByte b
      | b == 0x5C = "\\5C" -- backslash
      | b == 0x22 = "\\22" -- double quote
      | b == 0x0A = "\\0A" -- newline
      | b == 0x09 = "\\09" -- tab
      | b == 0x0D = "\\0D" -- carriage return
      | b == 0x00 = "\\00" -- nul
      | b >= 0x20 && b <= 0x7E = T.singleton (chr (fromIntegral b))
      | otherwise =
          let hi = b `div` 16
              lo = b `mod` 16
              hexChar x
                | x < 10 = chr (fromIntegral (0x30 + x))
                | otherwise = chr (fromIntegral (0x41 + x - 10))
           in "\\" <> toText [hexChar hi, hexChar lo]

-- ════════════════════════════════════════════════════════════════════════════
-- Header: external declarations + format strings
-- ════════════════════════════════════════════════════════════════════════════

header :: Set Name -> Text
header builtIns =
  unlines
    $ [ "; External C declarations",
        "declare ptr @malloc(i64)",
        "declare ptr @strcpy(ptr, ptr)",
        "declare ptr @strcat(ptr, ptr)",
        "declare i64 @strlen(ptr)",
        "declare i32 @printf(ptr, ...)",
        "declare i32 @snprintf(ptr, i64, ptr, ...)"
      ]
    <> [ "declare {i32, i1} @llvm.sadd.with.overflow.i32(i32, i32)"
       | Set.member "addInt32" builtIns
       ]
    <> [ "declare {i32, i1} @llvm.ssub.with.overflow.i32(i32, i32)"
       | Set.member "subInt32" builtIns
       ]
    <> [ "declare {i32, i1} @llvm.smul.with.overflow.i32(i32, i32)"
       | Set.member "mulInt32" builtIns
       ]
    <> [ "declare ptr @strstr(ptr, ptr)"
       | Set.member "splitOnFirst" builtIns
       ]
    <> [ "declare ptr @memcpy(ptr, ptr, i64)"
       | Set.member "splitOnFirst" builtIns
       ]
    <> [ "",
         "@.fmt = private unnamed_addr constant [3 x i8] c\"%s\\00\"",
         "@.fmt_i32 = private unnamed_addr constant [3 x i8] c\"%d\\00\"",
         "@.fmt_u8 = private unnamed_addr constant [3 x i8] c\"%u\\00\"",
         "@.empty = private unnamed_addr constant [1 x i8] c\"\\00\""
       ]

-- ════════════════════════════════════════════════════════════════════════════
-- Runtime helpers
-- ════════════════════════════════════════════════════════════════════════════

-- | LLVM runtime helpers, tree-shaken: each @define@ is emitted only
--   if the corresponding built-in is actually referenced in the
--   program's Core.
runtime :: Set Name -> Text
runtime builtIns =
  T.intercalate "\n\n" (filter (not . T.null) parts) <> "\n"
  where
    -- FNV-1a 32-bit row tags for the prelude's nominal labels used by
    -- the Int32 arithmetic builtins. Computed via 'rowTag' so the
    -- runtime helpers stay in lockstep with 'Awsum.HM.canonicalLabel'
    -- without hard-coded magic numbers.
    underflowTag :: Text
    underflowTag = show (rowTag (TyCon noSpan "UnderflowError"))
    overflowTag :: Text
    overflowTag = show (rowTag (TyCon noSpan "OverflowError"))
    -- StringTooLong row tag, used when the entry-point glue rejects a
    -- too-long argv[1] and hands user code 'Left StringTooLong' through
    -- the row '(StringTooLong | UnpairedUtf16Surrogate)'.
    stringTooLongTag :: Text
    stringTooLongTag = show (rowTag (TyCon noSpan "StringTooLong"))
    -- UnpairedUtf16Surrogate row tag, used when '__entryArgEither'
    -- detects an ill-formed surrogate-encoded UTF-8 byte triplet
    -- ('ED A0..BF 80..BF') in argv[1] — standard UTF-8 (RFC 3629)
    -- forbids these, but WTF-8 / CESU-8 / Java-modified-UTF-8 do not.
    unpairedSurrogateTag :: Text
    unpairedSurrogateTag = show (rowTag (TyCon noSpan "UnpairedUtf16Surrogate"))
    parts =
      [ if Set.member "concatString" builtIns then rtConcat else "",
        -- '__print' is the low-level platform primitive driven by the
        -- prelude's `runIO`, which walks the IO tree returned from
        -- `v_main` and calls `BuiltIn.internalStdoutPrint` on each
        -- 'IOStdoutPrint' arm. Returning a real Unit value
        -- (`malloc(8); store i64 0`) lets the surrounding
        -- `case … of Unit -> next` arm in `runIO` pattern-match
        -- through the standard CCase tag check.
        if Set.member "internalStdoutPrint" builtIns then rtPrint else "",
        if Set.member "showInt32" builtIns then rtShowInt32 else "",
        if Set.member "showUInt8" builtIns then rtShowUInt8 else "",
        if Set.member "predInt32" builtIns then rtPredInt32 else "",
        if Set.member "predUInt8" builtIns then rtPredUInt8 else "",
        if Set.member "succInt32" builtIns then rtSuccInt32 else "",
        if Set.member "succUInt8" builtIns then rtSuccUInt8 else "",
        if Set.member "eqInt32" builtIns then rtEqInt32 else "",
        if Set.member "eqUInt8" builtIns then rtEqUInt8 else "",
        if Set.member "addInt32" builtIns then rtAddInt32 else "",
        if Set.member "subInt32" builtIns then rtSubInt32 else "",
        if Set.member "mulInt32" builtIns then rtMulInt32 else "",
        if Set.member "negInt32" builtIns then rtNegInt32 else "",
        if Set.member "addUInt8" builtIns then rtAddUInt8 else "",
        if Set.member "subUInt8" builtIns then rtSubUInt8 else "",
        if Set.member "mulUInt8" builtIns then rtMulUInt8 else "",
        if Set.member "splitOnFirst" builtIns then rtSplitOnFirst else "",
        if Set.member "parseInt32" builtIns then rtParseInt32 else "",
        if Set.member "parseUInt8" builtIns then rtParseUInt8 else "",
        if Set.member "showUInt32" builtIns then rtShowUInt32 else "",
        if Set.member "predUInt32" builtIns then rtPredUInt32 else "",
        if Set.member "succUInt32" builtIns then rtSuccUInt32 else "",
        if Set.member "eqUInt32" builtIns then rtEqUInt32 else "",
        if Set.member "addUInt32" builtIns then rtAddUInt32 else "",
        if Set.member "subUInt32" builtIns then rtSubUInt32 else "",
        if Set.member "mulUInt32" builtIns then rtMulUInt32 else "",
        if Set.member "parseUInt32" builtIns then rtParseUInt32 else "",
        if Set.member "lengthCodePoints" builtIns then rtLengthCodePoints else "",
        -- '__concat' calls '__lengthUtf16CodeUnits' for the cap pre-check,
        -- so emit the helper whenever 'concatString' is referenced even if
        -- the user did not call 'lengthUtf16CodeUnits' directly.
        if Set.member "lengthUtf16CodeUnits" builtIns || Set.member "concatString" builtIns then rtLengthUtf16CodeUnits else "",
        if Set.member "lengthBytesAsUtf8" builtIns then rtLengthBytesAsUtf8 else "",
        -- '__entryArgEither' is always emitted: every program has a 'main',
        -- and 'footerPosix' / 'footerWindows' always call this helper to
        -- wrap argv[1] in 'Right' or in row-tagged 'Left StringTooLong'.
        rtEntryArgEither
      ]
    -- '__concat' implements 'BuiltIn.concatString'.
    -- Returns 'Either StringTooLong String' as a heap cell. Pre-checks
    -- the combined UTF-16 code unit length against the language-fixed
    -- cap and returns 'Left StringTooLong' with no buffer allocated when
    -- the result would overflow. The cap value (134217728) must stay in
    -- sync with 'maxStringLengthUtf16CodeUnits' in 'stdlib/Prelude.aww'.
    rtConcat =
      unlines
        [ "define internal ptr @__concat(ptr %a, ptr %b) {",
          -- UTF-16 length pre-check. Storage is UTF-8 bytes, but the cap
          -- is on UTF-16 code units (cross-runtime invariant), so we must
          -- count code units, not bytes.
          "  %la_box = call ptr @__lengthUtf16CodeUnits(ptr %a)",
          "  %la = load i32, ptr %la_box",
          "  %lb_box = call ptr @__lengthUtf16CodeUnits(ptr %b)",
          "  %lb = load i32, ptr %lb_box",
          -- Widen to i64 before summing. Awsum-internal strings respect
          -- the cap so the i32 sum can't overflow (max 2*134217728 fits
          -- in i32), but the widen costs nothing.
          "  %la64 = zext i32 %la to i64",
          "  %lb64 = zext i32 %lb to i64",
          "  %sum64 = add i64 %la64, %lb64",
          -- maxStringLengthUtf16CodeUnits = 134217728 (= 2^27).
          -- Keep in sync with 'maxStringLengthUtf16CodeUnits' in
          -- 'stdlib/Prelude.aww'.
          "  %over = icmp ugt i64 %sum64, 134217728",
          "  br i1 %over, label %too_long, label %ok",
          "too_long:",
          -- Build 'Left StringTooLong'. StringTooLong is a single-
          -- constructor type so its tag is 0; Either's Left tag is 0.
          "  %stl = call ptr @malloc(i64 8)",
          "  %stl_tag = inttoptr i64 0 to ptr",
          "  store ptr %stl_tag, ptr %stl",
          "  %left = call ptr @malloc(i64 16)",
          "  %left_tag = inttoptr i64 0 to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %stl, ptr %left_f",
          "  ret ptr %left",
          "ok:",
          -- Length fits — do the actual concat. UTF-8 byte count via
          -- 'strlen' is the right unit for the malloc/strcpy/strcat path.
          "  %ba = call i64 @strlen(ptr %a)",
          "  %bb = call i64 @strlen(ptr %b)",
          "  %bsum = add i64 %ba, %bb",
          "  %total = add i64 %bsum, 1",
          "  %buf = call ptr @malloc(i64 %total)",
          "  call ptr @strcpy(ptr %buf, ptr %a)",
          "  call ptr @strcat(ptr %buf, ptr %b)",
          -- Wrap in 'Right'. Either's Right tag is 1.
          "  %right = call ptr @malloc(i64 16)",
          "  %right_tag = inttoptr i64 1 to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %buf, ptr %right_f",
          "  ret ptr %right",
          "}"
        ]
    rtPrint =
      unlines
        [ "define internal ptr @__print(ptr %s) {",
          "  call i32 (ptr, ...) @printf(ptr @.fmt, ptr %s)",
          -- Allocate a Unit constructor cell: a single ptr slot holding
          -- the tag (`inttoptr 0`). Mirrors how every other CCon is
          -- emitted, so `runIO`'s `case … of Unit -> next` reads the
          -- tag through the same path.
          "  %unit = call ptr @malloc(i64 8)",
          "  %unit_tag_ptr = getelementptr ptr, ptr %unit, i32 0",
          "  %unit_tag = inttoptr i64 0 to ptr",
          "  store ptr %unit_tag, ptr %unit_tag_ptr",
          "  ret ptr %unit",
          "}"
        ]
    -- Integers are boxed: each CIntLit allocates a heap cell holding
    -- the native i32/i8 value and the Awsum-level 'ptr' points at it.
    -- Show reads the cell and snprintf's into a fresh 16-byte buffer
    -- (enough for @-2147483648@ / @255@ plus a null terminator).
    rtShowInt32 =
      unlines
        [ "define internal ptr @__showInt32(ptr %p) {",
          "  %v = load i32, ptr %p",
          "  %buf = call ptr @malloc(i64 16)",
          "  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_i32, i32 %v)",
          "  ret ptr %buf",
          "}"
        ]
    rtShowUInt8 =
      unlines
        [ "define internal ptr @__showUInt8(ptr %p) {",
          "  %b = load i8, ptr %p",
          "  %v = zext i8 %b to i32",
          "  %buf = call ptr @malloc(i64 16)",
          "  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_u8, i32 %v)",
          "  ret ptr %buf",
          "}"
        ]
    -- predInt32 : Int32 -> Either UnderflowError Int32
    --   On INT32_MIN, returns Left UnderflowError (tags: Left=0,
    --   UnderflowError=0). Otherwise returns Right (x - 1) (Right=1).
    --   Containers follow the uniform layout [tag_as_ptr, field, ...],
    --   same as user CCon emission.
    rtPredInt32 =
      unlines
        [ "define internal ptr @__predInt32(ptr %p) {",
          "  %v = load i32, ptr %p",
          "  %is_min = icmp eq i32 %v, -2147483648",
          "  br i1 %is_min, label %overflow, label %ok",
          "overflow:",
          "  %oe = call ptr @malloc(i64 8)",
          "  %oe_tag = inttoptr i64 0 to ptr",
          "  store ptr %oe_tag, ptr %oe",
          "  %left = call ptr @malloc(i64 16)",
          "  %left_tag = inttoptr i64 0 to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %oe, ptr %left_f",
          "  ret ptr %left",
          "ok:",
          "  %newv = sub i32 %v, 1",
          "  %box = call ptr @malloc(i64 4)",
          "  store i32 %newv, ptr %box",
          "  %right = call ptr @malloc(i64 16)",
          "  %right_tag = inttoptr i64 1 to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  ret ptr %right",
          "}"
        ]
    -- predUInt8 : UInt8 -> Either UnderflowError UInt8
    --   `Left UnderflowError` on 0, `Right (v - 1)` otherwise. Value is
    --   loaded as i8 (UInt8's storage width) and subtracted at i8 width;
    --   underflow is impossible on this path since v >= 1.
    rtPredUInt8 =
      unlines
        [ "define internal ptr @__predUInt8(ptr %p) {",
          "  %v = load i8, ptr %p",
          "  %is_zero = icmp eq i8 %v, 0",
          "  br i1 %is_zero, label %overflow, label %ok",
          "overflow:",
          "  %oe = call ptr @malloc(i64 8)",
          "  %oe_tag = inttoptr i64 0 to ptr",
          "  store ptr %oe_tag, ptr %oe",
          "  %left = call ptr @malloc(i64 16)",
          "  %left_tag = inttoptr i64 0 to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %oe, ptr %left_f",
          "  ret ptr %left",
          "ok:",
          "  %newv = sub i8 %v, 1",
          "  %box = call ptr @malloc(i64 1)",
          "  store i8 %newv, ptr %box",
          "  %right = call ptr @malloc(i64 16)",
          "  %right_tag = inttoptr i64 1 to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  ret ptr %right",
          "}"
        ]
    -- succInt32 : Int32 -> Either OverflowError Int32
    --   On INT32_MAX, returns Left OverflowError (tags: Left=0,
    --   OverflowError=0). Otherwise returns Right (x + 1) (Right=1). Mirrors
    --   'rtPredInt32' with the boundary flipped and 'sub' swapped for 'add'.
    rtSuccInt32 =
      unlines
        [ "define internal ptr @__succInt32(ptr %p) {",
          "  %v = load i32, ptr %p",
          "  %is_max = icmp eq i32 %v, 2147483647",
          "  br i1 %is_max, label %overflow, label %ok",
          "overflow:",
          "  %oe = call ptr @malloc(i64 8)",
          "  %oe_tag = inttoptr i64 0 to ptr",
          "  store ptr %oe_tag, ptr %oe",
          "  %left = call ptr @malloc(i64 16)",
          "  %left_tag = inttoptr i64 0 to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %oe, ptr %left_f",
          "  ret ptr %left",
          "ok:",
          "  %newv = add i32 %v, 1",
          "  %box = call ptr @malloc(i64 4)",
          "  store i32 %newv, ptr %box",
          "  %right = call ptr @malloc(i64 16)",
          "  %right_tag = inttoptr i64 1 to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  ret ptr %right",
          "}"
        ]
    -- succUInt8 : UInt8 -> Either OverflowError UInt8
    --   `Left OverflowError` on 255, `Right (v + 1)` otherwise. Value is
    --   loaded as i8 and added at i8 width; overflow is impossible on this
    --   path since v <= 254.
    rtSuccUInt8 =
      unlines
        [ "define internal ptr @__succUInt8(ptr %p) {",
          "  %v = load i8, ptr %p",
          "  %is_max = icmp eq i8 %v, 255",
          "  br i1 %is_max, label %overflow, label %ok",
          "overflow:",
          "  %oe = call ptr @malloc(i64 8)",
          "  %oe_tag = inttoptr i64 0 to ptr",
          "  store ptr %oe_tag, ptr %oe",
          "  %left = call ptr @malloc(i64 16)",
          "  %left_tag = inttoptr i64 0 to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %oe, ptr %left_f",
          "  ret ptr %left",
          "ok:",
          "  %newv = add i8 %v, 1",
          "  %box = call ptr @malloc(i64 1)",
          "  store i8 %newv, ptr %box",
          "  %right = call ptr @malloc(i64 16)",
          "  %right_tag = inttoptr i64 1 to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  ret ptr %right",
          "}"
        ]
    -- eqInt32 / eqUInt8: unbox both pointers, compare the native value, and
    -- return a one-slot Bool container ([tag]). True=0, False=1 matches
    -- declaration order in `type Bool = True | False`.
    rtEqInt32 =
      unlines
        [ "define internal ptr @__eqInt32(ptr %a, ptr %b) {",
          "  %va = load i32, ptr %a",
          "  %vb = load i32, ptr %b",
          "  %eq = icmp eq i32 %va, %vb",
          "  %tag = select i1 %eq, i64 0, i64 1",
          "  %box = call ptr @malloc(i64 8)",
          "  %tag_ptr = inttoptr i64 %tag to ptr",
          "  store ptr %tag_ptr, ptr %box",
          "  ret ptr %box",
          "}"
        ]
    rtEqUInt8 =
      unlines
        [ "define internal ptr @__eqUInt8(ptr %a, ptr %b) {",
          "  %va = load i8, ptr %a",
          "  %vb = load i8, ptr %b",
          "  %eq = icmp eq i8 %va, %vb",
          "  %tag = select i1 %eq, i64 0, i64 1",
          "  %box = call ptr @malloc(i64 8)",
          "  %tag_ptr = inttoptr i64 %tag to ptr",
          "  store ptr %tag_ptr, ptr %box",
          "  ret ptr %box",
          "}"
        ]
    -- addInt32 : Int32 -> Int32 -> Either (UnderflowError | OverflowError) Int32.
    --   Uses 'llvm.sadd.with.overflow' to detect signed overflow in one
    --   instruction. On overflow, signs of @a@ and @b@ must agree (else
    --   the sum stays in range), so a single @icmp sge i32 %a, 0@ separates
    --   positive overflow (OverflowError) from negative overflow
    --   (UnderflowError). The error side is a structural sum: the inner
    --   @CCon@ is the (single, 0-arg) constructor of UnderflowError or
    --   OverflowError, wrapped in a @CRow@ box keyed by the FNV-1a tag of
    --   the chosen label, then wrapped in a @Left@ Either box. Three
    --   nested boxes match what user-written @Left UnderflowError@ would
    --   lower to.
    rtAddInt32 =
      unlines
        [ "define internal ptr @__addInt32(ptr %pa, ptr %pb) {",
          "  %a = load i32, ptr %pa",
          "  %b = load i32, ptr %pb",
          "  %res = call {i32, i1} @llvm.sadd.with.overflow.i32(i32 %a, i32 %b)",
          "  %sum = extractvalue {i32, i1} %res, 0",
          "  %ovf = extractvalue {i32, i1} %res, 1",
          "  br i1 %ovf, label %err, label %ok",
          "err:",
          "  %is_pos = icmp sge i32 %a, 0",
          "  %row_tag_idx = select i1 %is_pos, i64 " <> overflowTag <> ", i64 " <> underflowTag,
          "  %inner = call ptr @malloc(i64 8)",
          "  %inner_tag = inttoptr i64 0 to ptr",
          "  store ptr %inner_tag, ptr %inner",
          "  %row = call ptr @malloc(i64 16)",
          "  %row_tag = inttoptr i64 %row_tag_idx to ptr",
          "  store ptr %row_tag, ptr %row",
          "  %row_f = getelementptr ptr, ptr %row, i32 1",
          "  store ptr %inner, ptr %row_f",
          "  %left = call ptr @malloc(i64 16)",
          "  %left_tag = inttoptr i64 0 to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %row, ptr %left_f",
          "  ret ptr %left",
          "ok:",
          "  %box = call ptr @malloc(i64 4)",
          "  store i32 %sum, ptr %box",
          "  %right = call ptr @malloc(i64 16)",
          "  %right_tag = inttoptr i64 1 to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  ret ptr %right",
          "}"
        ]
    -- subInt32 : Int32 -> Int32 -> Either (UnderflowError | OverflowError) Int32.
    --   Uses 'llvm.ssub.with.overflow' to detect signed overflow in one
    --   instruction. On overflow, signs of @a@ and @b@ must differ
    --   (otherwise the difference stays in range), so @icmp sge i32 %a, 0@
    --   separates positive overflow (@a >= 0, b < 0@ ⇒ OverflowError) from
    --   negative (@a < 0, b > 0@ ⇒ UnderflowError). The special case
    --   `b == minInt32` only overflows when `a >= 0`, which stays inside
    --   the @a >= 0 ⇒ OverflowError@ branch. Same row-tagged error
    --   encoding as 'rtAddInt32'.
    rtSubInt32 =
      unlines
        [ "define internal ptr @__subInt32(ptr %pa, ptr %pb) {",
          "  %a = load i32, ptr %pa",
          "  %b = load i32, ptr %pb",
          "  %res = call {i32, i1} @llvm.ssub.with.overflow.i32(i32 %a, i32 %b)",
          "  %diff = extractvalue {i32, i1} %res, 0",
          "  %ovf = extractvalue {i32, i1} %res, 1",
          "  br i1 %ovf, label %err, label %ok",
          "err:",
          "  %is_pos = icmp sge i32 %a, 0",
          "  %row_tag_idx = select i1 %is_pos, i64 " <> overflowTag <> ", i64 " <> underflowTag,
          "  %inner = call ptr @malloc(i64 8)",
          "  %inner_tag = inttoptr i64 0 to ptr",
          "  store ptr %inner_tag, ptr %inner",
          "  %row = call ptr @malloc(i64 16)",
          "  %row_tag = inttoptr i64 %row_tag_idx to ptr",
          "  store ptr %row_tag, ptr %row",
          "  %row_f = getelementptr ptr, ptr %row, i32 1",
          "  store ptr %inner, ptr %row_f",
          "  %left = call ptr @malloc(i64 16)",
          "  %left_tag = inttoptr i64 0 to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %row, ptr %left_f",
          "  ret ptr %left",
          "ok:",
          "  %box = call ptr @malloc(i64 4)",
          "  store i32 %diff, ptr %box",
          "  %right = call ptr @malloc(i64 16)",
          "  %right_tag = inttoptr i64 1 to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  ret ptr %right",
          "}"
        ]
    -- mulInt32 : Int32 -> Int32 -> Either (UnderflowError | OverflowError) Int32.
    --   Uses @llvm.smul.with.overflow.i32@ to detect signed overflow.
    --   Direction: same-sign overflow is OverflowError, opposite-sign is
    --   UnderflowError. We read sign agreement off @icmp sge i32 (a xor b), 0@:
    --   the xor's sign bit is 0 iff @a@ and @b@ have the same sign, so
    --   overflow on same-sign means positive overflow → OverflowError. The
    --   special case @minInt32 * -1@ = 2147483648 has same signs (both
    --   negative) and lands on OverflowError, which matches the math.
    --   Same row-tagged error encoding as 'rtAddInt32'.
    rtMulInt32 =
      unlines
        [ "define internal ptr @__mulInt32(ptr %pa, ptr %pb) {",
          "  %a = load i32, ptr %pa",
          "  %b = load i32, ptr %pb",
          "  %res = call {i32, i1} @llvm.smul.with.overflow.i32(i32 %a, i32 %b)",
          "  %prod = extractvalue {i32, i1} %res, 0",
          "  %ovf = extractvalue {i32, i1} %res, 1",
          "  br i1 %ovf, label %err, label %ok",
          "err:",
          "  %xor_ab = xor i32 %a, %b",
          "  %same_sign = icmp sge i32 %xor_ab, 0",
          "  %row_tag_idx = select i1 %same_sign, i64 " <> overflowTag <> ", i64 " <> underflowTag,
          "  %inner = call ptr @malloc(i64 8)",
          "  %inner_tag = inttoptr i64 0 to ptr",
          "  store ptr %inner_tag, ptr %inner",
          "  %row = call ptr @malloc(i64 16)",
          "  %row_tag = inttoptr i64 %row_tag_idx to ptr",
          "  store ptr %row_tag, ptr %row",
          "  %row_f = getelementptr ptr, ptr %row, i32 1",
          "  store ptr %inner, ptr %row_f",
          "  %left = call ptr @malloc(i64 16)",
          "  %left_tag = inttoptr i64 0 to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %row, ptr %left_f",
          "  ret ptr %left",
          "ok:",
          "  %box = call ptr @malloc(i64 4)",
          "  store i32 %prod, ptr %box",
          "  %right = call ptr @malloc(i64 16)",
          "  %right_tag = inttoptr i64 1 to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  ret ptr %right",
          "}"
        ]
    -- negInt32 : Int32 -> Either OverflowError Int32.
    --   Only @minInt32@ overflows on negation (its absolute value is one
    --   above maxInt32 in two's complement); every other input flips sign
    --   exactly. Same Left / Right encoding as 'rtSuccInt32', just with a
    --   different boundary and a 'sub 0, v' for the ok path.
    rtNegInt32 =
      unlines
        [ "define internal ptr @__negInt32(ptr %p) {",
          "  %v = load i32, ptr %p",
          "  %is_min = icmp eq i32 %v, -2147483648",
          "  br i1 %is_min, label %overflow, label %ok",
          "overflow:",
          "  %oe = call ptr @malloc(i64 8)",
          "  %oe_tag = inttoptr i64 0 to ptr",
          "  store ptr %oe_tag, ptr %oe",
          "  %left = call ptr @malloc(i64 16)",
          "  %left_tag = inttoptr i64 0 to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %oe, ptr %left_f",
          "  ret ptr %left",
          "ok:",
          "  %newv = sub i32 0, %v",
          "  %box = call ptr @malloc(i64 4)",
          "  store i32 %newv, ptr %box",
          "  %right = call ptr @malloc(i64 16)",
          "  %right_tag = inttoptr i64 1 to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  ret ptr %right",
          "}"
        ]
    -- addUInt8 : UInt8 -> UInt8 -> Either OverflowError UInt8.
    --   Both operands fit in i8, so widening to i32 first and comparing
    --   the sum against 255 gives a saturation-free overflow check
    --   (unsigned underflow is impossible for a + b on UInt8). On the ok
    --   path, the sum is in 0..510 — truncating to i8 keeps the low byte
    --   exactly when the comparison falls through.
    rtAddUInt8 =
      unlines
        [ "define internal ptr @__addUInt8(ptr %pa, ptr %pb) {",
          "  %a = load i8, ptr %pa",
          "  %b = load i8, ptr %pb",
          "  %a32 = zext i8 %a to i32",
          "  %b32 = zext i8 %b to i32",
          "  %sum32 = add i32 %a32, %b32",
          "  %ovf = icmp ugt i32 %sum32, 255",
          "  br i1 %ovf, label %err, label %ok",
          "err:",
          "  %oe = call ptr @malloc(i64 8)",
          "  %oe_tag = inttoptr i64 0 to ptr",
          "  store ptr %oe_tag, ptr %oe",
          "  %left = call ptr @malloc(i64 16)",
          "  %left_tag = inttoptr i64 0 to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %oe, ptr %left_f",
          "  ret ptr %left",
          "ok:",
          "  %newv = trunc i32 %sum32 to i8",
          "  %box = call ptr @malloc(i64 1)",
          "  store i8 %newv, ptr %box",
          "  %right = call ptr @malloc(i64 16)",
          "  %right_tag = inttoptr i64 1 to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  ret ptr %right",
          "}"
        ]
    -- mulUInt8 : UInt8 -> UInt8 -> Either OverflowError UInt8.
    --   Both operands fit in i8, so widening to i32 and multiplying gives
    --   a product in 0..65025 (= 255 * 255) — well inside the i32 range.
    --   A single @icmp ugt 255@ separates the branches; on the ok path
    --   the product is in 0..255, so truncating to i8 is faithful.
    rtMulUInt8 =
      unlines
        [ "define internal ptr @__mulUInt8(ptr %pa, ptr %pb) {",
          "  %a = load i8, ptr %pa",
          "  %b = load i8, ptr %pb",
          "  %a32 = zext i8 %a to i32",
          "  %b32 = zext i8 %b to i32",
          "  %prod32 = mul i32 %a32, %b32",
          "  %ovf = icmp ugt i32 %prod32, 255",
          "  br i1 %ovf, label %err, label %ok",
          "err:",
          "  %oe = call ptr @malloc(i64 8)",
          "  %oe_tag = inttoptr i64 0 to ptr",
          "  store ptr %oe_tag, ptr %oe",
          "  %left = call ptr @malloc(i64 16)",
          "  %left_tag = inttoptr i64 0 to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %oe, ptr %left_f",
          "  ret ptr %left",
          "ok:",
          "  %newv = trunc i32 %prod32 to i8",
          "  %box = call ptr @malloc(i64 1)",
          "  store i8 %newv, ptr %box",
          "  %right = call ptr @malloc(i64 16)",
          "  %right_tag = inttoptr i64 1 to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  ret ptr %right",
          "}"
        ]
    -- subUInt8 : UInt8 -> UInt8 -> Either UnderflowError UInt8.
    --   The signed-difference of two i8 values is in -128..127, but the
    --   *unsigned* interpretation of UInt8 says the difference is in
    --   -255..255. Widening to i32 first and comparing 'a < b' as unsigned
    --   picks the underflow branch. On the ok path the difference is
    --   already in 0..255, so truncating back to i8 is faithful.
    rtSubUInt8 =
      unlines
        [ "define internal ptr @__subUInt8(ptr %pa, ptr %pb) {",
          "  %a = load i8, ptr %pa",
          "  %b = load i8, ptr %pb",
          "  %a32 = zext i8 %a to i32",
          "  %b32 = zext i8 %b to i32",
          "  %unf = icmp ult i32 %a32, %b32",
          "  br i1 %unf, label %err, label %ok",
          "err:",
          "  %ue = call ptr @malloc(i64 8)",
          "  %ue_tag = inttoptr i64 0 to ptr",
          "  store ptr %ue_tag, ptr %ue",
          "  %left = call ptr @malloc(i64 16)",
          "  %left_tag = inttoptr i64 0 to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %ue, ptr %left_f",
          "  ret ptr %left",
          "ok:",
          "  %diff32 = sub i32 %a32, %b32",
          "  %newv = trunc i32 %diff32 to i8",
          "  %box = call ptr @malloc(i64 1)",
          "  store i8 %newv, ptr %box",
          "  %right = call ptr @malloc(i64 16)",
          "  %right_tag = inttoptr i64 1 to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  ret ptr %right",
          "}"
        ]
    -- splitOnFirst : String -> String -> Maybe (Tuple2 String String).
    --   Defers the substring search to libc 'strstr'; the empty-separator
    --   case is correct for free since 'strstr(s, "")' returns 's'. On
    --   miss returns a 1-slot Maybe container with tag 0 (Nothing). On
    --   hit allocates two fresh null-terminated buffers (prefix /
    --   suffix) — owning copies, never aliases into the input — and
    --   wraps them in `Tuple2 prefix suffix` (3-slot, tag 0) inside
    --   `Just` (2-slot, tag 1). Tags follow Prelude.aww declaration
    --   order: Maybe = Nothing | Just (0, 1); Tuple2 has one constructor
    --   (tag 0).
    rtSplitOnFirst =
      unlines
        [ "define internal ptr @__splitOnFirst(ptr %sep, ptr %str) {",
          "  %pos = call ptr @strstr(ptr %str, ptr %sep)",
          "  %is_null = icmp eq ptr %pos, null",
          "  br i1 %is_null, label %not_found, label %found",
          "not_found:",
          "  %nothing = call ptr @malloc(i64 8)",
          "  %nothing_tag = inttoptr i64 0 to ptr",
          "  store ptr %nothing_tag, ptr %nothing",
          "  ret ptr %nothing",
          "found:",
          "  %str_int = ptrtoint ptr %str to i64",
          "  %pos_int = ptrtoint ptr %pos to i64",
          "  %prefix_len = sub i64 %pos_int, %str_int",
          "  %sep_len = call i64 @strlen(ptr %sep)",
          "  %suffix_start = getelementptr i8, ptr %pos, i64 %sep_len",
          "  %suffix_len = call i64 @strlen(ptr %suffix_start)",
          "  %prefix_total = add i64 %prefix_len, 1",
          "  %prefix = call ptr @malloc(i64 %prefix_total)",
          "  call ptr @memcpy(ptr %prefix, ptr %str, i64 %prefix_len)",
          "  %prefix_term = getelementptr i8, ptr %prefix, i64 %prefix_len",
          "  store i8 0, ptr %prefix_term",
          "  %suffix_total = add i64 %suffix_len, 1",
          "  %suffix = call ptr @malloc(i64 %suffix_total)",
          "  call ptr @memcpy(ptr %suffix, ptr %suffix_start, i64 %suffix_len)",
          "  %suffix_term = getelementptr i8, ptr %suffix, i64 %suffix_len",
          "  store i8 0, ptr %suffix_term",
          "  %tuple = call ptr @malloc(i64 24)",
          "  %tuple_tag = inttoptr i64 0 to ptr",
          "  store ptr %tuple_tag, ptr %tuple",
          "  %tuple_a = getelementptr ptr, ptr %tuple, i32 1",
          "  store ptr %prefix, ptr %tuple_a",
          "  %tuple_b = getelementptr ptr, ptr %tuple, i32 2",
          "  store ptr %suffix, ptr %tuple_b",
          "  %just = call ptr @malloc(i64 16)",
          "  %just_tag = inttoptr i64 1 to ptr",
          "  store ptr %just_tag, ptr %just",
          "  %just_f = getelementptr ptr, ptr %just, i32 1",
          "  store ptr %tuple, ptr %just_f",
          "  ret ptr %just",
          "}"
        ]
    -- parseInt32 : String -> Either ParseError Int32.
    --   Strict decimal parser; grammar mirrors Awsum's literal — optional
    --   '-', one or more ASCII digits, nothing else. Accumulates into i64
    --   (so the maximum legal value 2147483648 — i.e. -minInt32 — fits)
    --   and fails fast as soon as the running magnitude exceeds 2147483648.
    --   Loop variables live in alloca slots; clang's mem2reg pass at -O2
    --   converts them to SSA phi nodes, so the emitted binary has no
    --   stack traffic.
    rtParseInt32 =
      unlines
        [ "define internal ptr @__parseInt32(ptr %s) {",
          "entry:",
          "  %neg_alloca = alloca i32, align 4",
          "  store i32 0, ptr %neg_alloca",
          "  %i_alloca = alloca i64, align 8",
          "  store i64 0, ptr %i_alloca",
          "  %acc_alloca = alloca i64, align 8",
          "  store i64 0, ptr %acc_alloca",
          "  %len = call i64 @strlen(ptr %s)",
          "  %is_empty = icmp eq i64 %len, 0",
          "  br i1 %is_empty, label %fail, label %check_sign",
          "check_sign:",
          "  %first = load i8, ptr %s",
          "  %first_i32 = zext i8 %first to i32",
          "  %is_neg = icmp eq i32 %first_i32, 45",
          "  br i1 %is_neg, label %sign_minus, label %loop_head",
          "sign_minus:",
          "  %is_lone = icmp eq i64 %len, 1",
          "  br i1 %is_lone, label %fail, label %sign_setup",
          "sign_setup:",
          "  store i32 1, ptr %neg_alloca",
          "  store i64 1, ptr %i_alloca",
          "  br label %loop_head",
          "loop_head:",
          "  %i = load i64, ptr %i_alloca",
          "  %acc = load i64, ptr %acc_alloca",
          "  %cond = icmp ult i64 %i, %len",
          "  br i1 %cond, label %body, label %after",
          "body:",
          "  %ptr_c = getelementptr i8, ptr %s, i64 %i",
          "  %c = load i8, ptr %ptr_c",
          "  %c_i32 = zext i8 %c to i32",
          "  %low = icmp ult i32 %c_i32, 48",
          "  %high = icmp ugt i32 %c_i32, 57",
          "  %bad = or i1 %low, %high",
          "  br i1 %bad, label %fail, label %parse",
          "parse:",
          "  %d = sub i32 %c_i32, 48",
          "  %d_i64 = zext i32 %d to i64",
          "  %x10 = mul i64 %acc, 10",
          "  %acc_next = add i64 %x10, %d_i64",
          "  %big = icmp ugt i64 %acc_next, 2147483648",
          "  br i1 %big, label %fail, label %body_end",
          "body_end:",
          "  store i64 %acc_next, ptr %acc_alloca",
          "  %i_next = add i64 %i, 1",
          "  store i64 %i_next, ptr %i_alloca",
          "  br label %loop_head",
          "after:",
          "  %neg_val = load i32, ptr %neg_alloca",
          "  %is_neg2 = icmp ne i32 %neg_val, 0",
          "  br i1 %is_neg2, label %finalize_neg, label %finalize_pos",
          "finalize_pos:",
          "  %big_pos = icmp ugt i64 %acc, 2147483647",
          "  br i1 %big_pos, label %fail, label %ok_pos",
          "finalize_neg:",
          "  %acc_neg = sub i64 0, %acc",
          "  br label %ok_neg",
          "ok_pos:",
          "  %result_pos = trunc i64 %acc to i32",
          "  br label %build_right",
          "ok_neg:",
          "  %result_neg = trunc i64 %acc_neg to i32",
          "  br label %build_right",
          "build_right:",
          "  %result = phi i32 [%result_pos, %ok_pos], [%result_neg, %ok_neg]",
          "  %box = call ptr @malloc(i64 4)",
          "  store i32 %result, ptr %box",
          "  %right = call ptr @malloc(i64 16)",
          "  %right_tag = inttoptr i64 1 to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  ret ptr %right",
          "fail:",
          "  %pe = call ptr @malloc(i64 8)",
          "  %pe_tag = inttoptr i64 0 to ptr",
          "  store ptr %pe_tag, ptr %pe",
          "  %left = call ptr @malloc(i64 16)",
          "  %left_tag = inttoptr i64 0 to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %pe, ptr %left_f",
          "  ret ptr %left",
          "}"
        ]
    -- parseUInt8 : String -> Either ParseError UInt8.
    --   No sign accepted; one or more ASCII digits, range 0..255. Same
    --   alloca-and-mem2reg pattern as 'rtParseInt32'; accumulator is i32
    --   since the running value never exceeds 2559 (255 * 10 + 9) before
    --   the '> 255' check fails the parse.
    rtParseUInt8 =
      unlines
        [ "define internal ptr @__parseUInt8(ptr %s) {",
          "entry:",
          "  %i_alloca = alloca i64, align 8",
          "  store i64 0, ptr %i_alloca",
          "  %acc_alloca = alloca i32, align 4",
          "  store i32 0, ptr %acc_alloca",
          "  %len = call i64 @strlen(ptr %s)",
          "  %is_empty = icmp eq i64 %len, 0",
          "  br i1 %is_empty, label %fail, label %loop_head",
          "loop_head:",
          "  %i = load i64, ptr %i_alloca",
          "  %acc = load i32, ptr %acc_alloca",
          "  %cond = icmp ult i64 %i, %len",
          "  br i1 %cond, label %body, label %ok",
          "body:",
          "  %ptr_c = getelementptr i8, ptr %s, i64 %i",
          "  %c = load i8, ptr %ptr_c",
          "  %c_i32 = zext i8 %c to i32",
          "  %low = icmp ult i32 %c_i32, 48",
          "  %high = icmp ugt i32 %c_i32, 57",
          "  %bad = or i1 %low, %high",
          "  br i1 %bad, label %fail, label %parse",
          "parse:",
          "  %d = sub i32 %c_i32, 48",
          "  %x10 = mul i32 %acc, 10",
          "  %acc_next = add i32 %x10, %d",
          "  %big = icmp ugt i32 %acc_next, 255",
          "  br i1 %big, label %fail, label %body_end",
          "body_end:",
          "  store i32 %acc_next, ptr %acc_alloca",
          "  %i_next = add i64 %i, 1",
          "  store i64 %i_next, ptr %i_alloca",
          "  br label %loop_head",
          "ok:",
          "  %result_i8 = trunc i32 %acc to i8",
          "  %box = call ptr @malloc(i64 1)",
          "  store i8 %result_i8, ptr %box",
          "  %right = call ptr @malloc(i64 16)",
          "  %right_tag = inttoptr i64 1 to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  ret ptr %right",
          "fail:",
          "  %pe = call ptr @malloc(i64 8)",
          "  %pe_tag = inttoptr i64 0 to ptr",
          "  store ptr %pe_tag, ptr %pe",
          "  %left = call ptr @malloc(i64 16)",
          "  %left_tag = inttoptr i64 0 to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %pe, ptr %left_f",
          "  ret ptr %left",
          "}"
        ]
    -- showUInt32: load i32, snprintf with the shared @.fmt_u8 ("%u")
    -- into a 16-byte buffer (max u32 "4294967295" is 10 digits + null).
    -- The format string is identical to UInt8's, so we don't introduce
    -- a separate constant — printf's "%u" with an i32 value already
    -- treats the 32-bit bit pattern as unsigned.
    rtShowUInt32 =
      unlines
        [ "define internal ptr @__showUInt32(ptr %p) {",
          "  %v = load i32, ptr %p",
          "  %buf = call ptr @malloc(i64 16)",
          "  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_u8, i32 %v)",
          "  ret ptr %buf",
          "}"
        ]
    -- predUInt32: Left UnderflowError on 0, else Right (v - 1). i32 storage
    -- with unsigned semantics — the subtract is purely on the ok path
    -- where v >= 1, so wrap-around is irrelevant.
    rtPredUInt32 =
      unlines
        [ "define internal ptr @__predUInt32(ptr %p) {",
          "  %v = load i32, ptr %p",
          "  %is_zero = icmp eq i32 %v, 0",
          "  br i1 %is_zero, label %overflow, label %ok",
          "overflow:",
          "  %ue = call ptr @malloc(i64 8)",
          "  %ue_tag = inttoptr i64 0 to ptr",
          "  store ptr %ue_tag, ptr %ue",
          "  %left = call ptr @malloc(i64 16)",
          "  %left_tag = inttoptr i64 0 to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %ue, ptr %left_f",
          "  ret ptr %left",
          "ok:",
          "  %newv = sub i32 %v, 1",
          "  %box = call ptr @malloc(i64 4)",
          "  store i32 %newv, ptr %box",
          "  %right = call ptr @malloc(i64 16)",
          "  %right_tag = inttoptr i64 1 to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  ret ptr %right",
          "}"
        ]
    -- succUInt32: Left OverflowError on 0xFFFFFFFF (-1 as signed i32),
    -- else Right (v + 1). The boundary literal is encoded as i32 -1 since
    -- LLVM accepts signed literals only for i32 immediates; the bit
    -- pattern is identical to 4294967295 unsigned.
    rtSuccUInt32 =
      unlines
        [ "define internal ptr @__succUInt32(ptr %p) {",
          "  %v = load i32, ptr %p",
          "  %is_max = icmp eq i32 %v, -1",
          "  br i1 %is_max, label %overflow, label %ok",
          "overflow:",
          "  %oe = call ptr @malloc(i64 8)",
          "  %oe_tag = inttoptr i64 0 to ptr",
          "  store ptr %oe_tag, ptr %oe",
          "  %left = call ptr @malloc(i64 16)",
          "  %left_tag = inttoptr i64 0 to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %oe, ptr %left_f",
          "  ret ptr %left",
          "ok:",
          "  %newv = add i32 %v, 1",
          "  %box = call ptr @malloc(i64 4)",
          "  store i32 %newv, ptr %box",
          "  %right = call ptr @malloc(i64 16)",
          "  %right_tag = inttoptr i64 1 to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  ret ptr %right",
          "}"
        ]
    -- eqUInt32: Mirrors rtEqInt32 since equality on i32 is sign-agnostic
    -- at the bit level.
    rtEqUInt32 =
      unlines
        [ "define internal ptr @__eqUInt32(ptr %a, ptr %b) {",
          "  %va = load i32, ptr %a",
          "  %vb = load i32, ptr %b",
          "  %eq = icmp eq i32 %va, %vb",
          "  %tag = select i1 %eq, i64 0, i64 1",
          "  %box = call ptr @malloc(i64 8)",
          "  %tag_ptr = inttoptr i64 %tag to ptr",
          "  store ptr %tag_ptr, ptr %box",
          "  ret ptr %box",
          "}"
        ]
    -- addUInt32: Either OverflowError UInt32. Widen both operands to i64
    -- (zext, unsigned) so the unmasked sum fits, then compare against
    -- 4294967295 with 'icmp ugt'. On the ok path the sum is in
    -- 0..4294967295 — truncating back to i32 keeps the low bits exactly.
    rtAddUInt32 =
      unlines
        [ "define internal ptr @__addUInt32(ptr %pa, ptr %pb) {",
          "  %a = load i32, ptr %pa",
          "  %b = load i32, ptr %pb",
          "  %a64 = zext i32 %a to i64",
          "  %b64 = zext i32 %b to i64",
          "  %sum64 = add i64 %a64, %b64",
          "  %ovf = icmp ugt i64 %sum64, 4294967295",
          "  br i1 %ovf, label %err, label %ok",
          "err:",
          "  %oe = call ptr @malloc(i64 8)",
          "  %oe_tag = inttoptr i64 0 to ptr",
          "  store ptr %oe_tag, ptr %oe",
          "  %left = call ptr @malloc(i64 16)",
          "  %left_tag = inttoptr i64 0 to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %oe, ptr %left_f",
          "  ret ptr %left",
          "ok:",
          "  %newv = trunc i64 %sum64 to i32",
          "  %box = call ptr @malloc(i64 4)",
          "  store i32 %newv, ptr %box",
          "  %right = call ptr @malloc(i64 16)",
          "  %right_tag = inttoptr i64 1 to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  ret ptr %right",
          "}"
        ]
    -- subUInt32: Either UnderflowError UInt32. Compare 'a < b' as
    -- unsigned at i32 width — overflow is unreachable for unsigned
    -- subtraction.
    rtSubUInt32 =
      unlines
        [ "define internal ptr @__subUInt32(ptr %pa, ptr %pb) {",
          "  %a = load i32, ptr %pa",
          "  %b = load i32, ptr %pb",
          "  %unf = icmp ult i32 %a, %b",
          "  br i1 %unf, label %err, label %ok",
          "err:",
          "  %ue = call ptr @malloc(i64 8)",
          "  %ue_tag = inttoptr i64 0 to ptr",
          "  store ptr %ue_tag, ptr %ue",
          "  %left = call ptr @malloc(i64 16)",
          "  %left_tag = inttoptr i64 0 to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %ue, ptr %left_f",
          "  ret ptr %left",
          "ok:",
          "  %newv = sub i32 %a, %b",
          "  %box = call ptr @malloc(i64 4)",
          "  store i32 %newv, ptr %box",
          "  %right = call ptr @malloc(i64 16)",
          "  %right_tag = inttoptr i64 1 to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  ret ptr %right",
          "}"
        ]
    -- mulUInt32: Either OverflowError UInt32. Widen both operands to i64
    -- (zext) so the unmasked product fits — max u32 * u32 is
    -- 0xFFFFFFFE00000001, well inside i64 range — then compare against
    -- 4294967295 with 'icmp ugt'. Same shape as 'rtAddUInt32' with 'mul'.
    rtMulUInt32 =
      unlines
        [ "define internal ptr @__mulUInt32(ptr %pa, ptr %pb) {",
          "  %a = load i32, ptr %pa",
          "  %b = load i32, ptr %pb",
          "  %a64 = zext i32 %a to i64",
          "  %b64 = zext i32 %b to i64",
          "  %prod64 = mul i64 %a64, %b64",
          "  %ovf = icmp ugt i64 %prod64, 4294967295",
          "  br i1 %ovf, label %err, label %ok",
          "err:",
          "  %oe = call ptr @malloc(i64 8)",
          "  %oe_tag = inttoptr i64 0 to ptr",
          "  store ptr %oe_tag, ptr %oe",
          "  %left = call ptr @malloc(i64 16)",
          "  %left_tag = inttoptr i64 0 to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %oe, ptr %left_f",
          "  ret ptr %left",
          "ok:",
          "  %newv = trunc i64 %prod64 to i32",
          "  %box = call ptr @malloc(i64 4)",
          "  store i32 %newv, ptr %box",
          "  %right = call ptr @malloc(i64 16)",
          "  %right_tag = inttoptr i64 1 to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  ret ptr %right",
          "}"
        ]
    -- parseUInt32: Same grammar as parseUInt8 — no sign accepted, decimal
    -- digits only — range 0..4294967295. Accumulator is i64 so the
    -- 'big' fast-fail check (acc > 4294967295) can fire as soon as
    -- accumulation overshoots; the running magnitude before failing is
    -- bounded by 4294967295 * 10 + 9 = 42949672959, which fits in i64.
    -- lengthBytesAsUtf8: strings are stored as null-terminated UTF-8
    -- byte buffers, so 'strlen' is exactly the answer. Truncated to i32
    -- because UInt32 boxes always 4 bytes wide.
    rtLengthBytesAsUtf8 =
      unlines
        [ "define internal ptr @__lengthBytesAsUtf8(ptr %s) {",
          "  %len64 = call i64 @strlen(ptr %s)",
          "  %len32 = trunc i64 %len64 to i32",
          "  %box = call ptr @malloc(i64 4)",
          "  store i32 %len32, ptr %box",
          "  ret ptr %box",
          "}"
        ]
    -- lengthCodePoints: walk UTF-8 bytes; every byte that is *not* a
    -- continuation byte (top two bits are 10) starts a fresh codepoint.
    -- Works for any well-formed UTF-8: 1/2/3/4-byte sequences each have
    -- exactly one start byte.
    rtLengthCodePoints =
      unlines
        [ "define internal ptr @__lengthCodePoints(ptr %s) {",
          "entry:",
          "  %i_p = alloca i64, align 8",
          "  store i64 0, ptr %i_p",
          "  %n_p = alloca i32, align 4",
          "  store i32 0, ptr %n_p",
          "  br label %head",
          "head:",
          "  %i = load i64, ptr %i_p",
          "  %bp = getelementptr i8, ptr %s, i64 %i",
          "  %b = load i8, ptr %bp",
          "  %is_nul = icmp eq i8 %b, 0",
          "  br i1 %is_nul, label %done, label %body",
          "body:",
          "  %bz = zext i8 %b to i32",
          "  %top2 = and i32 %bz, 192",
          "  %is_cont = icmp eq i32 %top2, 128",
          "  br i1 %is_cont, label %step, label %inc",
          "inc:",
          "  %n0 = load i32, ptr %n_p",
          "  %n1 = add i32 %n0, 1",
          "  store i32 %n1, ptr %n_p",
          "  br label %step",
          "step:",
          "  %i1 = add i64 %i, 1",
          "  store i64 %i1, ptr %i_p",
          "  br label %head",
          "done:",
          "  %nf = load i32, ptr %n_p",
          "  %box = call ptr @malloc(i64 4)",
          "  store i32 %nf, ptr %box",
          "  ret ptr %box",
          "}"
        ]
    -- lengthUtf16CodeUnits: walk codepoint starts; BMP codepoints
    -- (1-/2-/3-byte UTF-8 sequences) contribute 1 code unit, supplementary
    -- ones (4-byte UTF-8, 11110xxx start byte) contribute 2 (surrogate
    -- pair). Continuation bytes (10xxxxxx) are skipped.
    rtLengthUtf16CodeUnits =
      unlines
        [ "define internal ptr @__lengthUtf16CodeUnits(ptr %s) {",
          "entry:",
          "  %i_p = alloca i64, align 8",
          "  store i64 0, ptr %i_p",
          "  %n_p = alloca i32, align 4",
          "  store i32 0, ptr %n_p",
          "  br label %head",
          "head:",
          "  %i = load i64, ptr %i_p",
          "  %bp = getelementptr i8, ptr %s, i64 %i",
          "  %b = load i8, ptr %bp",
          "  %is_nul = icmp eq i8 %b, 0",
          "  br i1 %is_nul, label %done, label %body",
          "body:",
          "  %bz = zext i8 %b to i32",
          "  %top2 = and i32 %bz, 192",
          "  %is_cont = icmp eq i32 %top2, 128",
          "  br i1 %is_cont, label %step, label %check4",
          "check4:",
          "  %top5 = and i32 %bz, 248",
          "  %is_4 = icmp eq i32 %top5, 240",
          "  br i1 %is_4, label %add2, label %add1",
          "add2:",
          "  %n2_0 = load i32, ptr %n_p",
          "  %n2_1 = add i32 %n2_0, 2",
          "  store i32 %n2_1, ptr %n_p",
          "  br label %step",
          "add1:",
          "  %n1_0 = load i32, ptr %n_p",
          "  %n1_1 = add i32 %n1_0, 1",
          "  store i32 %n1_1, ptr %n_p",
          "  br label %step",
          "step:",
          "  %i1 = add i64 %i, 1",
          "  store i64 %i1, ptr %i_p",
          "  br label %head",
          "done:",
          "  %nf = load i32, ptr %n_p",
          "  %box = call ptr @malloc(i64 4)",
          "  store i32 %nf, ptr %box",
          "  ret ptr %box",
          "}"
        ]
    -- __entryArgEither: wraps argv[1] in 'Either (StringTooLong |
    -- UnpairedUtf16Surrogate) String' for the user's 'main'. Walks the
    -- UTF-8 bytes once and runs two checks:
    --   (1) UTF-16 code unit count vs cap (134217728), with short-circuit
    --       on overflow — adversarial input no longer drives an unbounded
    --       walk;
    --   (2) Surrogate-encoded byte triplets ('ED A0..BF 80..BF'), which
    --       standard UTF-8 (RFC 3629) forbids but WTF-8 / CESU-8 / Java
    --       modified UTF-8 do not. When detected, sets a sticky flag and
    --       continues scanning so a longer-than-cap input still reports
    --       'StringTooLong' (cap-check has priority).
    -- Returns:
    --   * Right(arg)               on fit + no surrogates
    --   * Left StringTooLong       on cap overflow (regardless of surrogates)
    --   * Left UnpairedUtf16Surrogate on surrogates with cap respected
    --
    -- Cap value (134217728 = 2^27) and FNV-1a row tags for "StringTooLong"
    -- / "UnpairedUtf16Surrogate" must stay in sync with
    -- 'maxStringLengthUtf16CodeUnits' in 'stdlib/Prelude.aww' and the
    -- matching constants in 'Awsum.Codegen.{JVM,CLR,WASM,JS}'.
    --
    -- Layout of the returned Either cell (identical for both Left arms,
    -- only the row tag differs):
    --   Right s     : malloc(16); [tag=1, ptr=s]
    --   Left  e     : malloc(16); [tag=0, ptr=row]
    --                 row = malloc(16); [rowTag, ptr=inner]   (CRow box)
    --                 inner = malloc(8); [tag=0]              (singleton CCon)
    rtEntryArgEither =
      unlines
        [ "define internal ptr @__entryArgEither(ptr %arg) {",
          "entry:",
          "  %i_p = alloca i64, align 8",
          "  store i64 0, ptr %i_p",
          "  %n_p = alloca i32, align 4",
          "  store i32 0, ptr %n_p",
          "  %surr_p = alloca i32, align 4",
          "  store i32 0, ptr %surr_p",
          "  br label %head",
          "head:",
          "  %i = load i64, ptr %i_p",
          "  %bp = getelementptr i8, ptr %arg, i64 %i",
          "  %b = load i8, ptr %bp",
          "  %is_nul = icmp eq i8 %b, 0",
          "  br i1 %is_nul, label %scan_done, label %body",
          "body:",
          "  %bz = zext i8 %b to i32",
          "  %top2 = and i32 %bz, 192",
          "  %is_cont = icmp eq i32 %top2, 128",
          "  br i1 %is_cont, label %step, label %surrogate_check",
          -- Surrogate-byte detection: a UTF-8 leading byte 0xED with the
          -- next byte in 0xA0..0xBF starts a 3-byte sequence encoding a
          -- code point in the surrogate range U+D800..U+DFFF. Standard
          -- UTF-8 forbids it; we treat it as 'UnpairedUtf16Surrogate'.
          -- Sticky flag, no early-exit (cap-check has priority).
          "surrogate_check:",
          "  %is_ED = icmp eq i32 %bz, 237",
          "  br i1 %is_ED, label %peek_next, label %check4",
          "peek_next:",
          "  %i_next = add i64 %i, 1",
          "  %bp_next = getelementptr i8, ptr %arg, i64 %i_next",
          "  %nxt = load i8, ptr %bp_next",
          "  %nxt_z = zext i8 %nxt to i32",
          "  %nxt_top3 = and i32 %nxt_z, 224",
          "  %is_surr = icmp eq i32 %nxt_top3, 160",
          "  br i1 %is_surr, label %set_surr, label %check4",
          "set_surr:",
          "  store i32 1, ptr %surr_p",
          "  br label %check4",
          "check4:",
          "  %top5 = and i32 %bz, 248",
          "  %is_4 = icmp eq i32 %top5, 240",
          "  br i1 %is_4, label %add2, label %add1",
          "add2:",
          "  %n2 = load i32, ptr %n_p",
          "  %n2_new = add i32 %n2, 2",
          "  store i32 %n2_new, ptr %n_p",
          -- maxStringLengthUtf16CodeUnits = 134217728. Short-circuit out
          -- of the scan as soon as the running count exceeds the cap.
          "  %over2 = icmp ugt i32 %n2_new, 134217728",
          "  br i1 %over2, label %scan_done, label %step",
          "add1:",
          "  %n1 = load i32, ptr %n_p",
          "  %n1_new = add i32 %n1, 1",
          "  store i32 %n1_new, ptr %n_p",
          "  %over1 = icmp ugt i32 %n1_new, 134217728",
          "  br i1 %over1, label %scan_done, label %step",
          "step:",
          "  %i1 = add i64 %i, 1",
          "  store i64 %i1, ptr %i_p",
          "  br label %head",
          "scan_done:",
          -- Cap-check has priority: if length exceeded the cap, return
          -- 'Left StringTooLong' regardless of the surrogate flag.
          "  %n_final = load i32, ptr %n_p",
          "  %over_final = icmp ugt i32 %n_final, 134217728",
          "  br i1 %over_final, label %too_long, label %check_surr",
          "check_surr:",
          "  %surr_final = load i32, ptr %surr_p",
          "  %is_surr_set = icmp ne i32 %surr_final, 0",
          "  br i1 %is_surr_set, label %unpaired, label %fits",
          "fits:",
          -- Right(arg): tag=1, payload=arg.
          "  %right = call ptr @malloc(i64 16)",
          "  %right_tag = inttoptr i64 1 to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %arg, ptr %right_f",
          "  ret ptr %right",
          "too_long:",
          -- inner: StringTooLong CCon (single ctor, tag 0).
          "  %tl_inner = call ptr @malloc(i64 8)",
          "  %tl_inner_tag = inttoptr i64 0 to ptr",
          "  store ptr %tl_inner_tag, ptr %tl_inner",
          -- row: CRow box keyed by FNV-1a hash of "StringTooLong".
          "  %tl_row = call ptr @malloc(i64 16)",
          "  %tl_row_tag = inttoptr i64 " <> stringTooLongTag <> " to ptr",
          "  store ptr %tl_row_tag, ptr %tl_row",
          "  %tl_row_f = getelementptr ptr, ptr %tl_row, i32 1",
          "  store ptr %tl_inner, ptr %tl_row_f",
          "  %tl_left = call ptr @malloc(i64 16)",
          "  %tl_left_tag = inttoptr i64 0 to ptr",
          "  store ptr %tl_left_tag, ptr %tl_left",
          "  %tl_left_f = getelementptr ptr, ptr %tl_left, i32 1",
          "  store ptr %tl_row, ptr %tl_left_f",
          "  ret ptr %tl_left",
          "unpaired:",
          -- inner: UnpairedUtf16Surrogate CCon (single ctor, tag 0).
          "  %us_inner = call ptr @malloc(i64 8)",
          "  %us_inner_tag = inttoptr i64 0 to ptr",
          "  store ptr %us_inner_tag, ptr %us_inner",
          -- row: CRow box keyed by FNV-1a hash of "UnpairedUtf16Surrogate".
          "  %us_row = call ptr @malloc(i64 16)",
          "  %us_row_tag = inttoptr i64 " <> unpairedSurrogateTag <> " to ptr",
          "  store ptr %us_row_tag, ptr %us_row",
          "  %us_row_f = getelementptr ptr, ptr %us_row, i32 1",
          "  store ptr %us_inner, ptr %us_row_f",
          "  %us_left = call ptr @malloc(i64 16)",
          "  %us_left_tag = inttoptr i64 0 to ptr",
          "  store ptr %us_left_tag, ptr %us_left",
          "  %us_left_f = getelementptr ptr, ptr %us_left, i32 1",
          "  store ptr %us_row, ptr %us_left_f",
          "  ret ptr %us_left",
          "}"
        ]
    rtParseUInt32 =
      unlines
        [ "define internal ptr @__parseUInt32(ptr %s) {",
          "entry:",
          "  %i_alloca = alloca i64, align 8",
          "  store i64 0, ptr %i_alloca",
          "  %acc_alloca = alloca i64, align 8",
          "  store i64 0, ptr %acc_alloca",
          "  %len = call i64 @strlen(ptr %s)",
          "  %is_empty = icmp eq i64 %len, 0",
          "  br i1 %is_empty, label %fail, label %loop_head",
          "loop_head:",
          "  %i = load i64, ptr %i_alloca",
          "  %acc = load i64, ptr %acc_alloca",
          "  %cond = icmp ult i64 %i, %len",
          "  br i1 %cond, label %body, label %ok",
          "body:",
          "  %ptr_c = getelementptr i8, ptr %s, i64 %i",
          "  %c = load i8, ptr %ptr_c",
          "  %c_i32 = zext i8 %c to i32",
          "  %low = icmp ult i32 %c_i32, 48",
          "  %high = icmp ugt i32 %c_i32, 57",
          "  %bad = or i1 %low, %high",
          "  br i1 %bad, label %fail, label %parse",
          "parse:",
          "  %d = sub i32 %c_i32, 48",
          "  %d_i64 = zext i32 %d to i64",
          "  %x10 = mul i64 %acc, 10",
          "  %acc_next = add i64 %x10, %d_i64",
          "  %big = icmp ugt i64 %acc_next, 4294967295",
          "  br i1 %big, label %fail, label %body_end",
          "body_end:",
          "  store i64 %acc_next, ptr %acc_alloca",
          "  %i_next = add i64 %i, 1",
          "  store i64 %i_next, ptr %i_alloca",
          "  br label %loop_head",
          "ok:",
          "  %result_i32 = trunc i64 %acc to i32",
          "  %box = call ptr @malloc(i64 4)",
          "  store i32 %result_i32, ptr %box",
          "  %right = call ptr @malloc(i64 16)",
          "  %right_tag = inttoptr i64 1 to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  ret ptr %right",
          "fail:",
          "  %pe = call ptr @malloc(i64 8)",
          "  %pe_tag = inttoptr i64 0 to ptr",
          "  store ptr %pe_tag, ptr %pe",
          "  %left = call ptr @malloc(i64 16)",
          "  %left_tag = inttoptr i64 0 to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %pe, ptr %left_f",
          "  ret ptr %left",
          "}"
        ]

-- ════════════════════════════════════════════════════════════════════════════
-- Footer: C main entry point
-- ════════════════════════════════════════════════════════════════════════════

-- | Choice of @main@ entry point per host. We don't yet support
--   cross-compilation, so the target triple of the emitted IR is whatever
--   clang infers from the host running the build. On Windows MSVCRT's
--   @argv@ goes through the ANSI code page and silently mangles
--   supplementary code points to @?@; the Windows entry replaces it with
--   a UTF-16-clean path that pulls the command line from shell32 and
--   converts to UTF-8 before handing off to @v_main@.
footer :: LLVMHost -> Text
footer = \case
  LLVMPosix -> footerPosix
  LLVMWindows -> footerWindows

footerPosix :: Text
footerPosix =
  unlines
    [ "",
      "define i32 @main(i32 %argc, ptr %argv) {",
      "  %has_arg = icmp sgt i32 %argc, 1",
      "  br i1 %has_arg, label %with_arg, label %no_arg",
      "with_arg:",
      "  %argptr = getelementptr ptr, ptr %argv, i64 1",
      "  %arg = load ptr, ptr %argptr",
      "  br label %call_main",
      "no_arg:",
      "  br label %call_main",
      "call_main:",
      "  %input = phi ptr [%arg, %with_arg], [@.empty, %no_arg]",
      -- '__entryArgEither' walks the UTF-8 input counting UTF-16 code
      -- units with short-circuit at cap+1, returning a fully-formed
      -- 'Either (StringTooLong | UnpairedUtf16Surrogate) String' cell
      -- (Right input on fit, row-tagged Left StringTooLong on overflow).
      "  %either = call ptr @__entryArgEither(ptr %input)",
      -- v_main returns an IO tree (lazy IO); the prelude's `runIO`
      -- walks it to execute any effects. `runIO` is a regular Awsum
      -- function emitted via the standard CFunDef path, so it goes
      -- through TCO and ends up as a bounded-stack loop. The IO
      -- value itself is a heap-allocated ptr-tagged ADT cell, same
      -- shape as user ADTs.
      "  %io = call ptr @v_main(ptr %either)",
      "  call ptr @v_runIO(ptr %io)",
      "  ret i32 0",
      "}"
    ]

-- | Windows entry: ignore the POSIX-shape @argc@/@argv@ that MSVCRT
--   hands us (those are ANSI-code-page-mangled), and re-fetch the
--   command line through @GetCommandLineW@ + @CommandLineToArgvW@,
--   then convert @argv[1]@ from UTF-16 to UTF-8 with
--   @WideCharToMultiByte (CP_UTF8)@. The UTF-8 buffer takes the place
--   the POSIX path's @%arg@ filled, so the rest of the entry (Right-box
--   wrap + call @v_main@) is identical.
--
--   The IR references symbols from kernel32 (GetCommandLineW,
--   WideCharToMultiByte) and shell32 (CommandLineToArgvW). The
--   mingw-w64 default link line auto-pulls both, but MSVC's linker
--   only auto-links what's in /DEFAULTLIB and CRT carries kernel32
--   only. The clang invocations in awsum/Main.hs and the test
--   harness pass @-lshell32 -lkernel32@ on a Windows host so
--   CommandLineToArgvW resolves under MSVC too (no-op on mingw-w64).
--
--   We skip @LocalFree@ on the argv array — main returns immediately
--   after, so the OS reclaims it.
footerWindows :: Text
footerWindows =
  unlines
    [ "",
      "declare ptr @GetCommandLineW()",
      "declare ptr @CommandLineToArgvW(ptr, ptr)",
      "declare i32 @WideCharToMultiByte(i32, i32, ptr, i32, ptr, i32, ptr, ptr)",
      "",
      "define i32 @main(i32 %argc_posix, ptr %argv_posix) {",
      "entry:",
      "  %cmdline = call ptr @GetCommandLineW()",
      "  %argc_slot = alloca i32",
      "  %argv_w = call ptr @CommandLineToArgvW(ptr %cmdline, ptr %argc_slot)",
      "  %argc_w = load i32, ptr %argc_slot",
      "  %has_arg = icmp sgt i32 %argc_w, 1",
      "  br i1 %has_arg, label %with_arg, label %no_arg",
      "with_arg:",
      "  %arg_w_slot = getelementptr ptr, ptr %argv_w, i64 1",
      "  %arg_w = load ptr, ptr %arg_w_slot",
      -- First call queries required UTF-8 byte count (incl. terminating NUL,
      -- because cchWideChar = -1 means "process the null-terminator too").
      -- 65001 = CP_UTF8.
      "  %needed = call i32 @WideCharToMultiByte(i32 65001, i32 0, ptr %arg_w, i32 -1, ptr null, i32 0, ptr null, ptr null)",
      "  %need_ok = icmp sgt i32 %needed, 0",
      "  br i1 %need_ok, label %do_convert, label %no_arg",
      "do_convert:",
      "  %needed64 = sext i32 %needed to i64",
      "  %buf = call ptr @malloc(i64 %needed64)",
      "  %written = call i32 @WideCharToMultiByte(i32 65001, i32 0, ptr %arg_w, i32 -1, ptr %buf, i32 %needed, ptr null, ptr null)",
      "  br label %call_main",
      "no_arg:",
      "  br label %call_main",
      "call_main:",
      "  %input = phi ptr [%buf, %do_convert], [@.empty, %no_arg]",
      -- Same '__entryArgEither' helper as the POSIX path; see footerPosix.
      "  %either = call ptr @__entryArgEither(ptr %input)",
      -- Same IO-tree handoff as the POSIX path; see footerPosix.
      "  %io = call ptr @v_main(ptr %either)",
      "  call ptr @v_runIO(ptr %io)",
      "  ret i32 0",
      "}"
    ]

-- ════════════════════════════════════════════════════════════════════════════
-- Declarations
-- ════════════════════════════════════════════════════════════════════════════

emitDecl :: EmitCtx -> CDecl -> CodegenM Text
emitDecl ctx = \case
  -- TCO-wrapped body. The SSA function can't mutate parameters, so we
  -- give each one an @alloca@ slot; the loop head loads the current
  -- values into fresh SSA names, the body sees those, and a 'CContinue'
  -- stores new values back before branching to the loop head. All real
  -- return paths write into @ret.slot@ and branch to a single exit block
  -- so the function still has exactly one @ret@ instruction.
  CFunDef nm args (CLoop body) -> do
    put 0
    loopLbl <- freshLabel "tco.loop"
    exitLbl <- freshLabel "tco.exit"
    retSlot <- freshTemp
    -- Allocate one slot per parameter and seed it with the incoming
    -- argument value. The allocas live in the entry block so they are
    -- visible across the loop back-edge.
    paramSlotPairs <- forM args $ \a -> do
      slot <- freshTemp
      pure (mangle a, slot)
    let entryAllocs =
          T.concat
            [ "  "
                <> slot
                <> " = alloca ptr\n"
                <> "  store ptr %"
                <> mangledName
                <> ", ptr "
                <> slot
                <> "\n"
            | (mangledName, slot) <- paramSlotPairs
            ]
        retAlloc = "  " <> retSlot <> " = alloca ptr\n"
    -- At the loop head, pull each parameter back into an SSA value. These
    -- are the names 'emitExpr' will resolve 'CVar' references to.
    loadPairs <- forM (zip args paramSlotPairs) $ \(origName, (_, slot)) -> do
      loaded <- freshTemp
      pure
        ( (origName, loaded),
          "  " <> loaded <> " = load ptr, ptr " <> slot <> "\n"
        )
    let loopLocals = Map.fromList (map fst loadPairs)
        loadCode = T.concat (map snd loadPairs)
        lctx =
          LoopCtx
            { lcLoopLabel = loopLbl,
              lcExitLabel = exitLbl,
              lcRetSlot = retSlot,
              lcParamSlots = paramSlotPairs
            }
        -- 'locals' shadows 'params' inside the loop body — the fresh
        -- loaded SSA names are what the body should read, not the raw
        -- function parameters (those are only used once, in @entry@).
        localCtx =
          ctx
            { params = Set.empty,
              locals = loopLocals,
              loopCtx = Just lctx
            }
    bodyInstrs <- emitTail localCtx body
    retLoaded <- freshTemp
    let llvmArgs = T.intercalate ", " (map (\a -> "ptr %" <> mangle a) args)
    pure
      $ "define internal ptr @"
      <> mangle nm
      <> "("
      <> llvmArgs
      <> ") {\n"
      <> "entry:\n"
      <> entryAllocs
      <> retAlloc
      <> "  br label %"
      <> loopLbl
      <> "\n"
      <> loopLbl
      <> ":\n"
      <> loadCode
      <> bodyInstrs
      <> exitLbl
      <> ":\n"
      <> "  "
      <> retLoaded
      <> " = load ptr, ptr "
      <> retSlot
      <> "\n"
      <> "  ret ptr "
      <> retLoaded
      <> "\n}"
  CFunDef nm args body -> do
    put 0
    let paramSet = Set.fromList args
        localCtx = ctx {params = paramSet}
        llvmArgs = T.intercalate ", " (map (\a -> "ptr %" <> mangle a) args)
    (instrs, result) <- emitExpr localCtx body
    pure
      $ "define internal ptr @"
      <> mangle nm
      <> "("
      <> llvmArgs
      <> ") {\n"
      <> instrs
      <> "  ret ptr "
      <> result
      <> "\n}"
  CValDef nm rhs -> do
    put 0
    let localCtx = ctx {params = Set.empty}
    (instrs, result) <- emitExpr localCtx rhs
    pure
      $ "define internal ptr @"
      <> mangle nm
      <> "() {\n"
      <> instrs
      <> "  ret ptr "
      <> result
      <> "\n}"

-- | Emit @body@ in tail position under a 'CLoop'. Guarantees the current
-- basic block is terminated (by @br@ to either the loop head or the exit
-- block), so the caller does not append its own terminator.
--
-- 'CContinue' evaluates its arguments (reading the pre-update parameters),
-- stores them into the loop's parameter slots, and jumps back to the loop
-- head. Every other tail shape computes a value through 'emitExpr', stows
-- it in the return slot, and jumps to the exit block — that way the
-- function has exactly one @ret@ regardless of control flow.
--
-- 'CCase' is traversed structurally: each arm is emitted in tail form and
-- self-terminating, so no @phi@ join is needed (the single @ret@ handles
-- the merge).
emitTail :: EmitCtx -> CExpr -> CodegenM Text
emitTail ctx expr = case ctx.loopCtx of
  Nothing -> error "LLVM codegen: emitTail called without LoopCtx (pipeline bug)"
  Just lctx -> go lctx expr
  where
    go :: LoopCtx -> CExpr -> CodegenM Text
    go lctx = \case
      CContinue newArgs -> do
        -- Evaluate all args before storing: a new value computed from the
        -- old parameter must read the old value, never a half-updated slot.
        argResults <- traverse (emitExpr ctx) newArgs
        let (argInstrsList, argNames) = unzip argResults
            stores =
              T.concat
                [ "  store ptr " <> r <> ", ptr " <> slot <> "\n"
                | (r, (_, slot)) <- zip argNames lctx.lcParamSlots
                ]
        pure
          $ T.concat argInstrsList
          <> stores
          <> "  br label %"
          <> lctx.lcLoopLabel
          <> "\n"
      CCase scrut alts -> do
        (instrS, resS) <- emitExpr ctx scrut
        tagSlot <- freshTemp
        tagLoaded <- freshTemp
        tagTmp <- freshTemp
        let tagInstr =
              "  "
                <> tagSlot
                <> " = getelementptr ptr, ptr "
                <> resS
                <> ", i32 0\n"
                <> "  "
                <> tagLoaded
                <> " = load ptr, ptr "
                <> tagSlot
                <> "\n"
                <> "  "
                <> tagTmp
                <> " = ptrtoint ptr "
                <> tagLoaded
                <> " to i64\n"
        defLabel <- freshLabel "tco.case.default"
        -- Each arm lives in its own labelled block and self-terminates
        -- (either to loop head or exit). No join / phi needed.
        armBlocks <- forM alts $ \(tag, vars, body) -> do
          lbl <- freshLabel ("tco.case.arm." <> show tag)
          varInstrs <- forM (zip vars [1 :: Int ..]) $ \(v, idx) -> do
            slotT <- freshTemp
            valT <- freshTemp
            pure
              ( "  "
                  <> slotT
                  <> " = getelementptr ptr, ptr "
                  <> resS
                  <> ", i32 "
                  <> show idx
                  <> "\n"
                  <> "  "
                  <> valT
                  <> " = load ptr, ptr "
                  <> slotT
                  <> "\n",
                (v, valT)
              )
          let varCode = T.concat (map fst varInstrs)
              varBindings = map snd varInstrs
              ctx' = foldl' (\c (v, tmp) -> c {locals = Map.insert v tmp (locals c)}) ctx varBindings
          bodyInstrs <- emitTail ctx' body
          pure (tag, lbl, varCode <> bodyInstrs)
        let switchCases = T.concat [" i64 " <> show tag <> ", label %" <> lbl | (tag, lbl, _) <- armBlocks]
            switchInstr = "  switch i64 " <> tagTmp <> ", label %" <> defLabel <> " [" <> switchCases <> " ]\n"
            armsEmitted = T.concat [lbl <> ":\n" <> blk | (_, lbl, blk) <- armBlocks]
            defBlock = defLabel <> ":\n  unreachable\n"
        pure
          $ instrS
          <> tagInstr
          <> switchInstr
          <> armsEmitted
          <> defBlock
      -- Row dispatch shares 'CCase''s ptr-tagged layout — delegate.
      CRowCase scrut alts ->
        emitTail ctx (CCase scrut [(fromIntegral t, [v], b) | (t, v, b) <- alts])
      other -> do
        (instrs, result) <- emitExpr ctx other
        pure
          $ instrs
          <> "  store ptr "
          <> result
          <> ", ptr "
          <> lctx.lcRetSlot
          <> "\n"
          <> "  br label %"
          <> lctx.lcExitLabel
          <> "\n"

-- ════════════════════════════════════════════════════════════════════════════
-- Expressions
-- ════════════════════════════════════════════════════════════════════════════

-- | Emit instructions for an expression.
--   Returns (accumulated instructions, SSA name holding the result).
emitExpr :: EmitCtx -> CExpr -> CodegenM (Text, Text)
emitExpr ctx = \case
  CString s -> do
    let idx = case Map.lookup s ctx.stringPool of
          Just i -> i
          Nothing -> error $ "string not in pool: " <> show s
        len = T.length s + 1
    tmp <- freshTemp
    pure
      ( "  " <> tmp <> " = getelementptr [" <> show len <> " x i8], ptr @.str." <> show idx <> ", i64 0, i64 0\n",
        tmp
      )
  CVar n
    | Just tmp <- Map.lookup n ctx.locals ->
        pure ("", tmp)
    | n `Set.member` ctx.params ->
        pure ("", "%" <> mangle n)
    | n `Set.member` ctx.valDefs -> do
        tmp <- freshTemp
        pure
          ( "  " <> tmp <> " = call ptr @" <> mangle n <> "()\n",
            tmp
          )
    | otherwise ->
        pure ("", "@" <> mangle n)
  CIntLit n it -> do
    -- Box the literal: malloc a cell of the right width, store the value,
    -- and return the pointer — integers share the uniform 'ptr' representation.
    buf <- freshTemp
    let (llvmTy, bytes, val) = case it of
          TInt32 -> ("i32" :: Text, 4 :: Int, show n :: Text)
          TUInt8 -> ("i8", 1, show n)
          -- LLVM i32 immediates are signed; values 2147483648..4294967295 must be
          -- written as their signed two's-complement equivalents (n - 2^32).
          TUInt32 -> ("i32", 4, show (if n >= 2147483648 then n - 4294967296 else n))
    pure
      ( "  "
          <> buf
          <> " = call ptr @malloc(i64 "
          <> show bytes
          <> ")\n"
          <> "  store "
          <> llvmTy
          <> " "
          <> val
          <> ", ptr "
          <> buf
          <> "\n",
        buf
      )
  CBuiltIn _ ->
    pure ("", "null") -- invariant: not a standalone term; dispatched from CCall
  CCon tag fields -> do
    -- Allocate container: [tag_as_ptr, field1, field2, ...]
    let nSlots = 1 + length fields
    arrTmp <- freshTemp
    let allocInstr = "  " <> arrTmp <> " = call ptr @malloc(i64 " <> show (nSlots * 8 :: Int) <> ")\n"
    -- Store tag at index 0
    tagPtr <- freshTemp
    tagSlot <- freshTemp
    let tagInstr =
          "  "
            <> tagPtr
            <> " = inttoptr i64 "
            <> show tag
            <> " to ptr\n"
            <> "  "
            <> tagSlot
            <> " = getelementptr ptr, ptr "
            <> arrTmp
            <> ", i32 0\n"
            <> "  store ptr "
            <> tagPtr
            <> ", ptr "
            <> tagSlot
            <> "\n"
    -- Store each field
    fieldInstrs <- forM (zip fields [1 :: Int ..]) $ \(fExpr, idx) -> do
      (instrF, resF) <- emitExpr ctx fExpr
      slotTmp <- freshTemp
      pure
        ( instrF
            <> "  "
            <> slotTmp
            <> " = getelementptr ptr, ptr "
            <> arrTmp
            <> ", i32 "
            <> show idx
            <> "\n"
            <> "  store ptr "
            <> resF
            <> ", ptr "
            <> slotTmp
            <> "\n"
        )
    pure
      ( allocInstr <> tagInstr <> T.concat fieldInstrs,
        arrTmp
      )
  -- Row injection / row dispatch: delegate to the same CCon / CCase
  -- emit machinery; the runtime layout (tag at offset 0, value at
  -- offset 1) is identical for one-field constructors.
  CRow tag v -> emitExpr ctx (CCon (fromIntegral tag) [v])
  CRowCase scrut alts ->
    emitExpr ctx (CCase scrut [(fromIntegral t, [v], b) | (t, v, b) <- alts])
  CCase scrut alts -> do
    (instrS, resS) <- emitExpr ctx scrut
    -- Extract tag from container[0]
    tagSlot <- freshTemp
    tagLoaded <- freshTemp
    tagTmp <- freshTemp
    let tagInstr =
          "  "
            <> tagSlot
            <> " = getelementptr ptr, ptr "
            <> resS
            <> ", i32 0\n"
            <> "  "
            <> tagLoaded
            <> " = load ptr, ptr "
            <> tagSlot
            <> "\n"
            <> "  "
            <> tagTmp
            <> " = ptrtoint ptr "
            <> tagLoaded
            <> " to i64\n"
    -- Generate labels
    defLabel <- freshLabel "case.default"
    joinLabel <- freshLabel "case.join"
    altLabelsAndBodies <- forM alts $ \(tag, vars, body) -> do
      lbl <- freshLabel ("case.arm." <> show tag)
      endLbl <- freshLabel ("case.end." <> show tag)
      -- Extract bound variables from container fields
      varInstrs <- forM (zip vars [1 :: Int ..]) $ \(v, idx) -> do
        slotT <- freshTemp
        valT <- freshTemp
        pure
          ( "  "
              <> slotT
              <> " = getelementptr ptr, ptr "
              <> resS
              <> ", i32 "
              <> show idx
              <> "\n"
              <> "  "
              <> valT
              <> " = load ptr, ptr "
              <> slotT
              <> "\n",
            (v, valT)
          )
      let varInstrCode = T.concat (map fst varInstrs)
          varBindings = map snd varInstrs
      -- Emit body with bound variables in context
      let ctx' = foldl' (\c (v, tmp) -> c {locals = Map.insert v tmp (locals c)}) ctx varBindings
      (instrB, resB) <- emitExpr ctx' body
      pure (tag, lbl, endLbl, varInstrCode <> instrB, resB)
    -- switch instruction
    let switchCases = T.concat [" i64 " <> show tag <> ", label %" <> lbl | (tag, lbl, _, _, _) <- altLabelsAndBodies]
        switchInstr = "  switch i64 " <> tagTmp <> ", label %" <> defLabel <> " [" <> switchCases <> " ]\n"
    -- arm blocks (body may create new blocks; endLbl is always the direct predecessor of join)
    let armBlocks =
          T.concat
            [ lbl <> ":\n" <> instrB <> "  br label %" <> endLbl <> "\n" <> endLbl <> ":\n  br label %" <> joinLabel <> "\n"
            | (_, lbl, endLbl, instrB, _) <- altLabelsAndBodies
            ]
    -- default block (unreachable)
    let defBlock = defLabel <> ":\n  unreachable\n"
    -- phi at join (references endLbl, the actual predecessor)
    phiTmp <- freshTemp
    let phiIncoming = T.intercalate ", " ["[" <> resB <> ", %" <> endLbl <> "]" | (_, _, endLbl, _, resB) <- altLabelsAndBodies]
        joinBlock = joinLabel <> ":\n  " <> phiTmp <> " = phi ptr " <> phiIncoming <> "\n"
    pure
      ( instrS <> tagInstr <> switchInstr <> armBlocks <> defBlock <> joinBlock,
        phiTmp
      )
  CCall f xs ->
    case f of
      -- Internal print primitive used by the prelude's `runIO`.
      -- Emits the same `__print` syscall the legacy `IO.Stdout.print`
      -- arm used to call directly; the difference is that this is now
      -- driven by the IO-tree walker rather than by user code.
      CBuiltIn "internalStdoutPrint" ->
        case xs of
          [x] -> do
            (instrX, resX) <- emitExpr ctx x
            tmp <- freshTemp
            pure
              ( instrX <> "  " <> tmp <> " = call ptr @__print(ptr " <> resX <> ")\n",
                tmp
              )
          _ -> error "__print: arity mismatch"
      CBuiltIn name
        | name == "showInt32" || name == "showUInt8" || name == "showUInt32" ->
            case xs of
              [x] -> do
                (instrX, resX) <- emitExpr ctx x
                tmp <- freshTemp
                let fn :: Text
                    fn = case name of
                      "showUInt8" -> "@__showUInt8"
                      "showUInt32" -> "@__showUInt32"
                      _ -> "@__showInt32"
                pure
                  ( instrX <> "  " <> tmp <> " = call ptr " <> fn <> "(ptr " <> resX <> ")\n",
                    tmp
                  )
              _ -> error ("BuiltIn." <> name <> ": arity mismatch")
      CBuiltIn "predInt32" ->
        case xs of
          [x] -> do
            (instrX, resX) <- emitExpr ctx x
            tmp <- freshTemp
            pure
              ( instrX <> "  " <> tmp <> " = call ptr @__predInt32(ptr " <> resX <> ")\n",
                tmp
              )
          _ -> error "BuiltIn.predInt32: arity mismatch"
      CBuiltIn "predUInt8" ->
        case xs of
          [x] -> do
            (instrX, resX) <- emitExpr ctx x
            tmp <- freshTemp
            pure
              ( instrX <> "  " <> tmp <> " = call ptr @__predUInt8(ptr " <> resX <> ")\n",
                tmp
              )
          _ -> error "BuiltIn.predUInt8: arity mismatch"
      CBuiltIn "predUInt32" ->
        case xs of
          [x] -> do
            (instrX, resX) <- emitExpr ctx x
            tmp <- freshTemp
            pure
              ( instrX <> "  " <> tmp <> " = call ptr @__predUInt32(ptr " <> resX <> ")\n",
                tmp
              )
          _ -> error "BuiltIn.predUInt32: arity mismatch"
      CBuiltIn "succInt32" ->
        case xs of
          [x] -> do
            (instrX, resX) <- emitExpr ctx x
            tmp <- freshTemp
            pure
              ( instrX <> "  " <> tmp <> " = call ptr @__succInt32(ptr " <> resX <> ")\n",
                tmp
              )
          _ -> error "BuiltIn.succInt32: arity mismatch"
      CBuiltIn "succUInt8" ->
        case xs of
          [x] -> do
            (instrX, resX) <- emitExpr ctx x
            tmp <- freshTemp
            pure
              ( instrX <> "  " <> tmp <> " = call ptr @__succUInt8(ptr " <> resX <> ")\n",
                tmp
              )
          _ -> error "BuiltIn.succUInt8: arity mismatch"
      CBuiltIn "succUInt32" ->
        case xs of
          [x] -> do
            (instrX, resX) <- emitExpr ctx x
            tmp <- freshTemp
            pure
              ( instrX <> "  " <> tmp <> " = call ptr @__succUInt32(ptr " <> resX <> ")\n",
                tmp
              )
          _ -> error "BuiltIn.succUInt32: arity mismatch"
      CBuiltIn name
        | name == "eqInt32" || name == "eqUInt8" || name == "eqUInt32" ->
            case xs of
              [a, b] -> do
                (instrA, resA) <- emitExpr ctx a
                (instrB, resB) <- emitExpr ctx b
                tmp <- freshTemp
                let fn :: Text
                    fn = case name of
                      "eqUInt8" -> "@__eqUInt8"
                      "eqUInt32" -> "@__eqUInt32"
                      _ -> "@__eqInt32"
                pure
                  ( instrA <> instrB <> "  " <> tmp <> " = call ptr " <> fn <> "(ptr " <> resA <> ", ptr " <> resB <> ")\n",
                    tmp
                  )
              _ -> error ("BuiltIn." <> name <> ": arity mismatch")
      CBuiltIn name
        | name == "addInt32" || name == "addUInt8" || name == "addUInt32" || name == "subInt32" || name == "subUInt8" || name == "subUInt32" || name == "mulUInt8" || name == "mulUInt32" || name == "mulInt32" ->
            case xs of
              [a, b] -> do
                (instrA, resA) <- emitExpr ctx a
                (instrB, resB) <- emitExpr ctx b
                tmp <- freshTemp
                let fn :: Text
                    fn = case name of
                      "addUInt8" -> "@__addUInt8"
                      "addUInt32" -> "@__addUInt32"
                      "subInt32" -> "@__subInt32"
                      "subUInt8" -> "@__subUInt8"
                      "subUInt32" -> "@__subUInt32"
                      "mulUInt8" -> "@__mulUInt8"
                      "mulUInt32" -> "@__mulUInt32"
                      "mulInt32" -> "@__mulInt32"
                      _ -> "@__addInt32"
                pure
                  ( instrA <> instrB <> "  " <> tmp <> " = call ptr " <> fn <> "(ptr " <> resA <> ", ptr " <> resB <> ")\n",
                    tmp
                  )
              _ -> error ("BuiltIn." <> name <> ": arity mismatch")
      CBuiltIn "negInt32" ->
        case xs of
          [x] -> do
            (instrX, resX) <- emitExpr ctx x
            tmp <- freshTemp
            pure
              ( instrX <> "  " <> tmp <> " = call ptr @__negInt32(ptr " <> resX <> ")\n",
                tmp
              )
          _ -> error "BuiltIn.negInt32: arity mismatch"
      CBuiltIn "concatString" ->
        case xs of
          [a, b] -> do
            (instrA, resA) <- emitExpr ctx a
            (instrB, resB) <- emitExpr ctx b
            tmp <- freshTemp
            pure
              ( instrA <> instrB <> "  " <> tmp <> " = call ptr @__concat(ptr " <> resA <> ", ptr " <> resB <> ")\n",
                tmp
              )
          _ -> error "BuiltIn.concatString: arity mismatch"
      CBuiltIn "splitOnFirst" ->
        case xs of
          [a, b] -> do
            (instrA, resA) <- emitExpr ctx a
            (instrB, resB) <- emitExpr ctx b
            tmp <- freshTemp
            pure
              ( instrA <> instrB <> "  " <> tmp <> " = call ptr @__splitOnFirst(ptr " <> resA <> ", ptr " <> resB <> ")\n",
                tmp
              )
          _ -> error "BuiltIn.splitOnFirst: arity mismatch"
      CBuiltIn name
        | name == "parseInt32" || name == "parseUInt8" || name == "parseUInt32" ->
            case xs of
              [a] -> do
                (instrA, resA) <- emitExpr ctx a
                tmp <- freshTemp
                let fn :: Text
                    fn = case name of
                      "parseInt32" -> "@__parseInt32"
                      "parseUInt32" -> "@__parseUInt32"
                      _ -> "@__parseUInt8"
                pure
                  ( instrA <> "  " <> tmp <> " = call ptr " <> fn <> "(ptr " <> resA <> ")\n",
                    tmp
                  )
              _ -> error ("BuiltIn." <> name <> ": arity mismatch")
      CBuiltIn name
        | name == "lengthCodePoints" || name == "lengthUtf16CodeUnits" || name == "lengthBytesAsUtf8" ->
            case xs of
              [a] -> do
                (instrA, resA) <- emitExpr ctx a
                tmp <- freshTemp
                let fn :: Text
                    fn = case name of
                      "lengthCodePoints" -> "@__lengthCodePoints"
                      "lengthUtf16CodeUnits" -> "@__lengthUtf16CodeUnits"
                      _ -> "@__lengthBytesAsUtf8"
                pure
                  ( instrA <> "  " <> tmp <> " = call ptr " <> fn <> "(ptr " <> resA <> ")\n",
                    tmp
                  )
              _ -> error ("BuiltIn." <> name <> ": arity mismatch")
      CBuiltIn n ->
        error ("LLVM codegen: unknown builtin '" <> n <> "' reached CCall (typecheck should have rejected it)")
      _ -> do
        (instrF, resF) <- emitExpr ctx f
        argsResults <- traverse (emitExpr ctx) xs
        let allInstrs = instrF <> mconcat (map fst argsResults)
            argList = T.intercalate ", " (map (\(_, r) -> "ptr " <> r) argsResults)
        tmp <- freshTemp
        pure
          ( allInstrs <> "  " <> tmp <> " = call ptr " <> resF <> "(" <> argList <> ")\n",
            tmp
          )
  CLoop _ -> error "LLVM codegen: CLoop survived untcoProgram (pipeline bug)"
  CContinue _ -> error "LLVM codegen: CContinue survived untcoProgram (pipeline bug)"

-- ════════════════════════════════════════════════════════════════════════════
-- Name mangling
-- ════════════════════════════════════════════════════════════════════════════

-- | All names get @v_@ prefix (including @main@ → @v_main@),
--   because @\@main@ is the C entry point.
mangle :: Text -> Text
mangle t =
  let ok c = Char.isAlphaNum c || c == '_' || c == '\''
      body = T.map (\c -> if ok c then c else '_') t
   in "v_" <> body
