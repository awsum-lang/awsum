-- | LLVM IR code generator for Awsum 'Core'.
--
-- Design goals:
--   * Emit textual LLVM IR (.ll) that can be compiled with @clang@.
--   * Keep a tiny C-based runtime: @malloc@/@free@/@write@ plus a
--     refcount-aware allocator layer ('__alloc_shaped',
--     '__inc_ref', '__free_recursive').
--   * Mirror JS / JVM / CLR / WASM backend semantics for cross-backend
--     equivalence; identical stdout is verified on every commit.
--
-- Semantics & assumptions:
--   * All values are opaque pointers (@ptr@, LLVM 15+).
--   * Strings are length-prefixed: 12-byte refcount header
--     ([flag | refcount | shape]) + 8-byte length header
--     (utf8_bytes : i32 LE, utf16_units : i32 LE) + UTF-8 payload, no
--     NUL terminator. Pointers address the refcount header start.
--   * Concatenation pre-checks the combined UTF-16 length against
--     'maxStringLengthUtf16CodeUnits' and returns @Left StringTooLong@
--     on overflow; otherwise allocates a fresh cell and copies bytes.
--   * Print: @write(STDOUT_FILENO, payload, byte_count)@ — exact-length,
--     so embedded NULs don't truncate.
--   * Zero-arg surface defs ('CValDef') become zero-arg LLVM functions.
--     Pure expressions, so recomputation is safe.
--   * The C @main@ entry point calls @v_runIO(v_main())@. Argv is read
--     lazily via 'IOGetArgs' during 'runIO' if and only if the program
--     uses @IO.Args.getArgs@.
module Awsum.Codegen.LLVM
  ( codegenLLVM,
    LLVMHost,
    allLLVMHosts,
    llvmHostName,
    llvmHostFromSystem,
    LLVMLinkHost,
    llvmLinkHostFromSystem,
    llvmHostLinkerFlags,
  )
where

import Awsum.Core
import Awsum.HM (rowTag)
import Awsum.Lifetime (elidableArmBinders)
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

-- | The IR shape variant — which @main@ entry point we emit.
--   POSIX uses the standard @int main(int argc, char** argv)@; Windows
--   ignores that argv (MSVCRT mangles it through the ANSI code page)
--   and re-fetches the UTF-16 command line through @GetCommandLineW@ /
--   @CommandLineToArgvW@ before handing off to @v_main@. macOS and
--   Linux share the POSIX variant — the footer is byte-identical for
--   both. The link-host axis (which linker flags @clang@ needs) is
--   tracked separately by 'LLVMLinkHost' because there macOS and Linux
--   diverge. The CLI derives this from 'System.Info.os' once via
--   'llvmHostFromSystem'; the snapshot test framework iterates all
--   values so per-host IR is asserted on every CI host.
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

-- | The linker flavour @clang@ will hand the IR off to. This is a
--   separate axis from 'LLVMHost' because macOS and Linux share the
--   POSIX IR footer but use completely different linkers with
--   incompatible flag spellings: macOS goes through ld64 (or its LLD
--   port @ld64.lld@), Linux through GNU @ld@ or @ld.lld@. Detected
--   independently via 'llvmLinkHostFromSystem'.
data LLVMLinkHost = LinkMacOS | LinkLinux | LinkWindows
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | Detect the link host for the awsum binary running this code.
--   GHC reports @"darwin"@ for macOS, @"mingw32"@ for any Windows
--   build; everything else (Linux/FreeBSD/…) falls through to the
--   ELF/GNU-ld branch.
llvmLinkHostFromSystem :: LLVMLinkHost
llvmLinkHostFromSystem
  | Info.os == "darwin" = LinkMacOS
  | Info.os == "mingw32" = LinkWindows
  | otherwise = LinkLinux

-- | Extra clang flags required to actually link the IR on each host.
--   On macOS, ld64 accepts @-stack_size@ as a single-dash separate
--   argument; on Linux, both GNU @ld@ and @ld.lld@ instead express
--   the same setting through the ELF-specific @-z stack-size=N@.
--   Windows needs explicit @-lshell32 -lkernel32@ because
--   'footerWindows' calls 'CommandLineToArgvW' and friends —
--   mingw-w64 auto-links those, but MSVC's CRT only carries kernel32,
--   so the explicit flag is what closes
--   @LNK2019: unresolved external symbol CommandLineToArgvW@.
--   Harmless on mingw-w64 (already in the auto-link line).
llvmHostLinkerFlags :: LLVMLinkHost -> [String]
llvmHostLinkerFlags = \case
  -- POSIX hosts need nothing beyond the toolchain default: the
  -- runtime helper '@__free_recursive' uses a global heap-backed
  -- worklist for non-last cascade children, so its C-stack
  -- footprint is O(1) regardless of data shape or iteration
  -- count. The platform-default 8 MiB thread stack is enough for
  -- the remaining user call graph (already shaped to bounded
  -- depth by 'Awsum.StackSafety').
  LinkMacOS -> []
  LinkLinux -> []
  -- Windows needs explicit @-lshell32 -lkernel32@ because
  -- 'footerWindows' calls 'CommandLineToArgvW' and friends —
  -- mingw-w64 auto-links those, but MSVC's CRT only carries kernel32,
  -- so the explicit flag is what closes
  -- @LNK2019: unresolved external symbol CommandLineToArgvW@.
  -- Harmless on mingw-w64 (already in the auto-link line).
  LinkWindows -> ["-lshell32", "-lkernel32"]

-- | Produce a complete LLVM IR module from a Core program for a given host.
codegenLLVM :: LLVMHost -> PreludeTags -> CoreProgram -> Text
codegenLLVM host ptags prog@(CoreProgram decls) =
  let pool = collectStrings prog
      valDefNames = Set.fromList [n | CValDef n _ <- decls]
      ctx = EmitCtx {params = Set.empty, valDefs = valDefNames, stringPool = pool, locals = Map.empty, loopCtx = Nothing, armPatternByScrut = Map.empty, elidedBinders = Set.empty}
      userCode = evalState (T.intercalate "\n\n" <$> traverse (emitDecl ctx) decls) 0
      builtIns = usedBuiltIns prog
   in T.intercalate
        "\n"
        [ header builtIns,
          emitStringConstants pool,
          runtime ptags builtIns,
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
    loopCtx :: Maybe LoopCtx,
    -- | Linear-scrutinee elision: for each in-scope 'CCase' / 'CRowCase'
    -- whose scrutinee is a 'CVar n', records the arm's pattern
    -- variables. 'CReuse n t fs' inside the arm body checks
    -- @armPatternByScrut[n]@ to detect self-move slots (@fs[i] ==
    -- CVar vs[i]@) and skip their dec-old + inc-new + store entirely
    -- — the slot's pointer is already what we wanted.
    armPatternByScrut :: Map Text [Text],
    -- | Permutation-aware elision: arm-binder names whose only use
    -- in the arm body is as a 'CVar' field of a 'CReuse' on the
    -- same scrut (self-move or permutation-move, either way the
    -- cell still owns the value through the rewrite). For such
    -- binders, codegen skips: (a) the inc-on-extract at case match;
    -- (b) the dec-via-CDrop at arm end; (c) inside the matching
    -- 'CReuse', the dec-old of the binder's old slot and the
    -- inc-new of its new slot. The store at the new slot is still
    -- emitted for permutation moves; self-move skips the store too
    -- via 'isSelfMoveAt'. Empty for any binder that flows anywhere
    -- other than that one 'CReuse' field (CContinue arg, CCall arg,
    -- multiple uses, etc.) — those keep the full inc/dec dance.
    elidedBinders :: Set Text
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
  CDrop _ _ body -> stringsInExpr body
  CReuse _ _ fs -> concatMap stringsInExpr fs

-- | Emit string-pool constants in the language-fixed length-prefixed
--   layout, prefixed by a 12-byte @{i32 flag = 0, i32 refcount = 0,
--   i32 shape = 0}@ header so '@__free' /
--   '@__free_recursive' recognise the literal (flag == 0 short-
--   circuits both) and no-op on it. Refcount stays 0 across the run
--   — inc/dec on literals is also flag-gated. Shape == 0 means
--   '__free_recursive' will not descend into the string payload as
--   if it were pointer fields.
--
--   The user-facing pointer is @getelementptr i8, ptr @.str.N, i64
--   12@ — runtime helpers then @load i32@ at user_ptr+0 / +4 for
--   byte / UTF-16 length, and @gep i8, ptr s, i64 8@ for the payload
--   start, with no offset shift relative to the pre-header layout.
--   See 'stringLiteralUserPtr' for the constexpr that produces the
--   user pointer at every reference site.
emitStringConstants :: StringPool -> Text
emitStringConstants pool
  | Map.null pool = ""
  | otherwise =
      T.intercalate "\n" (map emitOne (sortWith snd $ Map.toList pool)) <> "\n"
  where
    emitOne (s, i) =
      let bs = encodeUtf8 s
          byteCount = BS.length bs
          utf16Count = T.foldl' (\n c -> n + if Char.ord c > 0xFFFF then 2 else 1) (0 :: Int) s
          escaped = llvmEscapeString s
          payloadType = "[" <> show byteCount <> " x i8]"
          payloadInit
            | byteCount == 0 = "[0 x i8] zeroinitializer"
            | otherwise = payloadType <> " c\"" <> escaped <> "\""
       in "@.str."
            <> show i
            <> " = private unnamed_addr constant {i32, i32, i32, i32, i32, "
            <> payloadType
            <> "} { i32 0, i32 0, i32 0, i32 "
            <> show byteCount
            <> ", i32 "
            <> show utf16Count
            <> ", "
            <> payloadInit
            <> " }"

-- | Constexpr that yields the user-pointer for a string literal.
--   Adds 12 to skip the literal's flag/refcount/shape header,
--   matching the layout produced by 'emitStringConstants'.
stringLiteralUserPtr :: Int -> Text
stringLiteralUserPtr i =
  "getelementptr inbounds (i8, ptr @.str." <> show i <> ", i64 12)"

-- | Constexpr for the '@.empty' user-pointer. Same shape as
--   'stringLiteralUserPtr' but for the language-fixed empty literal.
emptyStringUserPtr :: Text
emptyStringUserPtr = "getelementptr inbounds (i8, ptr @.empty, i64 12)"

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
        "declare ptr @realloc(ptr, i64)",
        "declare void @free(ptr)",
        "declare ptr @memcpy(ptr, ptr, i64)",
        -- 'strlen' is used only at the boundary between OS argv[1]
        -- (a C-string from libc) and our internal length-prefixed layout
        -- — see 'rtEntryArgEither'. None of the regular runtime helpers
        -- depend on null termination anymore; they read length from the
        -- string's 8-byte header.
        "declare i64 @strlen(ptr)",
        -- 'write(2)' is used by '__print' to stream payload bytes to fd 1
        -- regardless of NUL bytes inside (which 'printf(\"%s\", …)' /
        -- 'printf(\"%.*s\", n, …)' would silently truncate at). On macOS
        -- and Linux libc the symbol is 'write'; mingw libc also exposes
        -- it. MSVC's CRT exposes '_write' instead — that variant is not
        -- yet wired through and is tracked as a Windows-host follow-up.
        "declare i64 @write(i32, ptr, i64)",
        "declare i32 @printf(ptr, ...)",
        "declare i32 @snprintf(ptr, i64, ptr, ...)"
      ]
    <> [ -- 'read(2)' is used by '__stdinReadAll' to consume fd 0 to EOF
       -- regardless of NUL bytes in the input. macOS / Linux / mingw
       -- libc all expose it as 'read'; MSVC's CRT exposes '_read'
       -- instead — same Windows-host follow-up as 'write'. Gated so
       -- programs without 'IO.Stdin.readAll' don't pin libc 'read'.
       "declare i64 @read(i32, ptr, i64)"
       | Set.member "internalStdinReadAllAsUtf16" builtIns
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
    -- 'strstr' / 'memcpy' from the splitOnFirst path are no longer
    -- needed: 'memcpy' is now in the always-on header (used by every
    -- string-allocating helper), and 'rtSplitOnFirst' walks the
    -- length-prefixed payload via i32 loads + index arithmetic instead
    -- of libc's null-aware 'strstr'.
    <> [ "",
         "@.fmt_i32 = private unnamed_addr constant [3 x i8] c\"%d\\00\"",
         "@.fmt_u8 = private unnamed_addr constant [3 x i8] c\"%u\\00\"",
         -- '@.empty' is the language-fixed empty string in length-prefixed
         -- form. The 4-byte 'i32 flag = 0' prefix
         -- tells '@__free' this is a literal — passing the user-pointer
         -- through 'CDrop' is safe and no-ops. The user pointer is
         -- '@.empty + 4'; existing readers see byte_count at user_ptr+0
         -- and utf16 at user_ptr+4 unchanged.
         "@.empty = private unnamed_addr constant {i32, i32, i32, i32, i32} { i32 0, i32 0, i32 0, i32 0, i32 0 }",
         -- '@.cli_arg' caches the entry-point's @argv[1]@ pointer (or
         -- @.empty@ when absent) so 'BuiltIn.internalGetArgs' can re-
         -- read it from the prelude's 'runIO' arm without threading
         -- @argc@/@argv@ through the IO tree. Argv is invariant during
         -- program execution, so a single store at entry is enough —
         -- the no-memoisation principle is on the Awsum side (each
         -- 'IO.Args.getArgs' call yields a fresh 'Either' cell), not
         -- the C-level argv read.
         "@.cli_arg = internal global ptr null",
         -- '__alloc' / '__free' wrap libc 'malloc' / 'free' with a
         -- 12-byte header: each block is prefixed
         -- with @flag@ (4 bytes: 1 for heap, 0 for string literals
         -- which carry the same prefix in their global layout — see
         -- 'emitStringConstants'), @refcount@ (4 bytes, initial 1 = the
         -- single owner returned by 'alloc'), and @shape@ (4 bytes:
         -- number of ptr fields starting at slot 1, used by
         -- '__free_recursive' to recurse into ADT cells; 0 = no ptr
         -- fields, so strings/boxed scalars/nullary constructors get
         -- the default without explicit override). The user-facing
         -- pointer always points 12 bytes past the malloc'd block, so
         -- existing readers (string headers at user_ptr+0/+4, ADT
         -- cells at user_ptr+0 for tag, …) keep working without offset
         -- shifts. '__free' reads the flag and only releases when it
         -- is 1, making @call __free@ safe on literal pointers (no-op)
         -- as well as heap pointers. 'CDrop' lowers to
         -- '__free_recursive' in emitExpr / emitTail so the refcount
         -- decrements and the shape-driven cascade fires; '__free'
         -- itself is the per-block release the cascade ends in.
         "",
         "define internal ptr @__alloc(i64 %sz, i32 %shape) {",
         "  %total = add i64 %sz, 12",
         "  %raw = call ptr @malloc(i64 %total)",
         "  store i32 1, ptr %raw",
         "  %rc_p = getelementptr i8, ptr %raw, i64 4",
         "  store i32 1, ptr %rc_p",
         "  %shape_p = getelementptr i8, ptr %raw, i64 8",
         "  store i32 %shape, ptr %shape_p",
         "  %user = getelementptr i8, ptr %raw, i64 12",
         "  ret ptr %user",
         "}",
         "",
         "define internal void @__free(ptr %p) {",
         "  %hdr_ptr = getelementptr i8, ptr %p, i64 -12",
         "  %flag = load i32, ptr %hdr_ptr",
         "  %is_heap = icmp eq i32 %flag, 1",
         "  br i1 %is_heap, label %do_free, label %skip",
         "do_free:",
         "  call void @free(ptr %hdr_ptr)",
         "  br label %skip",
         "skip:",
         "  ret void",
         "}",
         "",
         -- '@__inc_ref' increments the refcount of the cell
         -- at @user_ptr@. Literals (flag == 0) are unaffected — their
         -- refcount field stays at 0 and they never get freed.
         "define internal void @__inc_ref(ptr %p) {",
         "  %hdr_ptr = getelementptr i8, ptr %p, i64 -12",
         "  %flag = load i32, ptr %hdr_ptr",
         "  %is_heap = icmp eq i32 %flag, 1",
         "  br i1 %is_heap, label %do_inc, label %skip_inc",
         "do_inc:",
         "  %rc_p = getelementptr i8, ptr %p, i64 -8",
         "  %rc_old = load i32, ptr %rc_p",
         "  %rc_new = add i32 %rc_old, 1",
         "  store i32 %rc_new, ptr %rc_p",
         "  br label %skip_inc",
         "skip_inc:",
         "  ret void",
         "}",
         "",
         -- '@__free_worklist' / '@__free_worklist_top' /
         -- '@__free_worklist_cap' back '@__free_recursive''s
         -- cascade. Non-last children of cells with shape > 1 go
         -- onto this heap-backed buffer instead of the C stack;
         -- the helper drains the buffer in its own outer loop, so
         -- system-stack usage is O(1) independent of cascade
         -- shape. Storage is single-threaded (Awsum is
         -- single-threaded; the helper never calls user code) and
         -- reused across every '@__free_recursive' invocation;
         -- 'top' returns to 0 by the time the helper returns, so
         -- no state leaks between top-level calls. Buffer doubles
         -- on overflow ('realloc'); it is never shrunk because
         -- past peak depth is a good predictor of future peak
         -- depth.
         "@__free_worklist = internal global ptr null",
         "@__free_worklist_top = internal global i64 0",
         "@__free_worklist_cap = internal global i64 0",
         "",
         -- Push @%p@ onto '@__free_worklist'. Grows the buffer
         -- (initial 16 entries, doubles thereafter) when @top ==
         -- cap@; otherwise reuses the existing allocation. Each
         -- entry is a pointer (8 bytes on the only platform LLVM
         -- targets here).
         "define internal void @__free_worklist_push(ptr %p) {",
         "entry:",
         "  %top = load i64, ptr @__free_worklist_top",
         "  %cap = load i64, ptr @__free_worklist_cap",
         "  %is_full = icmp eq i64 %top, %cap",
         "  br i1 %is_full, label %grow, label %store",
         "grow:",
         "  %cap_zero = icmp eq i64 %cap, 0",
         "  %doubled = shl i64 %cap, 1",
         "  %new_cap = select i1 %cap_zero, i64 16, i64 %doubled",
         "  %bytes = mul i64 %new_cap, 8",
         "  %old_buf = load ptr, ptr @__free_worklist",
         "  %new_buf = call ptr @realloc(ptr %old_buf, i64 %bytes)",
         "  store ptr %new_buf, ptr @__free_worklist",
         "  store i64 %new_cap, ptr @__free_worklist_cap",
         "  br label %store",
         "store:",
         "  %buf = load ptr, ptr @__free_worklist",
         "  %slot = getelementptr ptr, ptr %buf, i64 %top",
         "  store ptr %p, ptr %slot",
         "  %top_new = add i64 %top, 1",
         "  store i64 %top_new, ptr @__free_worklist_top",
         "  ret void",
         "}",
         "",
         -- '@__free_recursive' decrements the refcount of
         -- @user_ptr@. When the refcount reaches 0 it reads
         -- @shape@ (number of ptr fields starting at slot 1) and
         -- cascades: non-last children go onto the global
         -- worklist, the last slot is consumed iteratively as the
         -- next @p@ in the outer loop, the current block is
         -- freed via libc 'free'. When the local cell is done
         -- (cleared, or its refcount stayed > 0, or shape == 0),
         -- the helper pops the next pointer from the worklist
         -- and continues; when the worklist is empty, it
         -- returns. This makes the C-stack footprint O(1)
         -- regardless of how deep the cascade goes — large
         -- frontiers grow the worklist (heap) instead of the
         -- stack. Literals (flag == 0) and live cells (rc > 0)
         -- pop the next pending without touching the cell
         -- further. The cascade is safe under Awsum's
         -- immutability invariant: a cell can only reference
         -- cells allocated before it, so the graph is acyclic.
         "define internal void @__free_recursive(ptr %p_arg) {",
         "entry:",
         "  br label %top",
         "top:",
         "  %p = phi ptr [ %p_arg, %entry ], [ %p_after, %continue ]",
         "  %hdr_ptr = getelementptr i8, ptr %p, i64 -12",
         "  %flag = load i32, ptr %hdr_ptr",
         "  %is_heap = icmp eq i32 %flag, 1",
         "  br i1 %is_heap, label %do_dec, label %try_pop",
         "do_dec:",
         "  %rc_p = getelementptr i8, ptr %p, i64 -8",
         "  %rc_old = load i32, ptr %rc_p",
         "  %rc_new = sub i32 %rc_old, 1",
         "  store i32 %rc_new, ptr %rc_p",
         "  %is_zero = icmp eq i32 %rc_new, 0",
         "  br i1 %is_zero, label %do_cascade, label %try_pop",
         "do_cascade:",
         "  %shape_p = getelementptr i8, ptr %p, i64 -4",
         "  %shape = load i32, ptr %shape_p",
         "  %shape_zero = icmp eq i32 %shape, 0",
         "  br i1 %shape_zero, label %free_and_pop, label %loop_check",
         "loop_check:",
         "  %i = phi i32 [ 1, %do_cascade ], [ %i_next, %loop_body ]",
         "  %cmp = icmp ult i32 %i, %shape",
         "  br i1 %cmp, label %loop_body, label %tail_jump_prep",
         "loop_body:",
         "  %i64 = zext i32 %i to i64",
         "  %slot_p = getelementptr ptr, ptr %p, i64 %i64",
         "  %child = load ptr, ptr %slot_p",
         "  call void @__free_worklist_push(ptr %child)",
         "  %i_next = add i32 %i, 1",
         "  br label %loop_check",
         "tail_jump_prep:",
         -- Load the last ptr slot, free the current block, then
         -- iterate the outer loop with the child as the new @p@.
         -- This consumes one cell of any linear chain (lists,
         -- continuation chains) per outer iteration without
         -- pushing onto the worklist.
         "  %shape64 = zext i32 %shape to i64",
         "  %last_slot_p = getelementptr ptr, ptr %p, i64 %shape64",
         "  %p_next_tail = load ptr, ptr %last_slot_p",
         "  call void @free(ptr %hdr_ptr)",
         "  br label %continue",
         "free_and_pop:",
         "  call void @free(ptr %hdr_ptr)",
         "  br label %try_pop",
         "try_pop:",
         "  %top_old = load i64, ptr @__free_worklist_top",
         "  %is_empty = icmp eq i64 %top_old, 0",
         "  br i1 %is_empty, label %done, label %do_pop",
         "do_pop:",
         "  %top_new = sub i64 %top_old, 1",
         "  store i64 %top_new, ptr @__free_worklist_top",
         "  %wl_buf = load ptr, ptr @__free_worklist",
         "  %wl_slot = getelementptr ptr, ptr %wl_buf, i64 %top_new",
         "  %p_popped = load ptr, ptr %wl_slot",
         "  br label %continue",
         "continue:",
         "  %p_after = phi ptr [ %p_next_tail, %tail_jump_prep ], [ %p_popped, %do_pop ]",
         "  br label %top",
         "done:",
         "  ret void",
         "}"
       ]

-- ════════════════════════════════════════════════════════════════════════════
-- Runtime helpers
-- ════════════════════════════════════════════════════════════════════════════

-- | LLVM runtime helpers, tree-shaken: each @define@ is emitted only
--   if the corresponding built-in is actually referenced in the
--   program's Core.
runtime :: PreludeTags -> Set Name -> Text
runtime ptags builtIns =
  T.intercalate "\n\n" (filter (not . T.null) parts) <> "\n"
  where
    -- FNV-1a 32-bit row tags for the prelude's nominal labels used by
    -- the Int32 arithmetic builtins. Computed via 'rowTag' so the
    -- runtime helpers stay in lockstep with 'Awsum.HM.canonicalLabel'
    -- without hard-coded magic numbers.
    underflowRowTag :: Text
    underflowRowTag = show (rowTag (TyCon noSpan "UnderflowError"))
    overflowRowTag :: Text
    overflowRowTag = show (rowTag (TyCon noSpan "OverflowError"))
    -- StringTooLong row tag, used when the entry-point glue rejects a
    -- too-long argv[1] and hands user code 'Left StringTooLong' through
    -- the row '(StringTooLong | UnpairedUtf16Surrogate)'.
    stringTooLongRowTag :: Text
    stringTooLongRowTag = show (rowTag (TyCon noSpan "StringTooLong"))
    -- UnpairedUtf16Surrogate row tag, used when '__entryArgEither'
    -- detects an ill-formed surrogate-encoded UTF-8 byte triplet
    -- ('ED A0..BF 80..BF') in argv[1] — standard UTF-8 (RFC 3629)
    -- forbids these, but WTF-8 / CESU-8 / Java-modified-UTF-8 do not.
    unpairedSurrogateRowTag :: Text
    unpairedSurrogateRowTag = show (rowTag (TyCon noSpan "UnpairedUtf16Surrogate"))
    -- Globally-unique constructor tags fed in via 'PreludeTags'. These
    -- show up at every user 'CCon' / 'CCase' arm; runtime helpers
    -- construct values of these types out of band so they need to
    -- match the same numbering.
    leftLit, rightLit, unitLit, trueLit, falseLit, nothingLit, justLit, tuple2Lit, ueLit, oeLit, peLit, stlLit, usLit :: Text
    leftLit = show (ptLeft ptags)
    rightLit = show (ptRight ptags)
    unitLit = show (ptUnit ptags)
    trueLit = show (ptTrue ptags)
    falseLit = show (ptFalse ptags)
    nothingLit = show (ptNothing ptags)
    justLit = show (ptJust ptags)
    tuple2Lit = show (ptTuple2 ptags)
    ueLit = show (ptUnderflowError ptags)
    oeLit = show (ptOverflowError ptags)
    peLit = show (ptParseError ptags)
    stlLit = show (ptStringTooLong ptags)
    usLit = show (ptUnpairedUtf16Surrogate ptags)
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
        if Set.member "lengthUtf16CodeUnits" builtIns then rtLengthUtf16CodeUnits else "",
        if Set.member "lengthUtf8Bytes" builtIns then rtLengthBytesAsUtf8 else "",
        -- '__entryArgEither' is the shared length-aware UTF-8 → UTF-16
        -- decoder used by '__getArgs' (argv source) and '__stdinReadAll'
        -- (stdin source). Gated on either built-in's presence so a
        -- program that needs neither pays nothing for the helper.
        if Set.member "internalGetArgs" builtIns || Set.member "internalStdinReadAllAsUtf16" builtIns then rtEntryArgEither else "",
        if Set.member "internalGetArgs" builtIns then rtGetArgs else "",
        if Set.member "internalStdinReadAllAsUtf16" builtIns then rtStdinReadAll else ""
      ]
    -- '__concat' implements 'BuiltIn.concatString' on the length-
    -- prefixed string layout. Returns 'Either StringTooLong String' as
    -- a heap cell. Cap-check is now O(1) (load both UTF-16 lengths
    -- from headers, add, compare) — no byte-scan, no short-circuit
    -- needed. The cap value (134217728) must stay in sync with
    -- 'maxStringLengthUtf16CodeUnits' in 'stdlib/Prelude.aww'.
    --
    -- Output layout: malloc(8 + ba + bb), write {byte_count, utf16_count}
    -- in the header, memcpy a's payload then b's payload to offset 8.
    rtConcat =
      unlines
        [ "define internal ptr @__concat(ptr %a, ptr %b) {",
          -- Load lengths from a / b headers.
          "  %ba = load i32, ptr %a",
          "  %ua_p = getelementptr i8, ptr %a, i64 4",
          "  %ua = load i32, ptr %ua_p",
          "  %bb = load i32, ptr %b",
          "  %ub_p = getelementptr i8, ptr %b, i64 4",
          "  %ub = load i32, ptr %ub_p",
          -- Cap check on UTF-16 sum (the language-level metric).
          "  %ua64 = zext i32 %ua to i64",
          "  %ub64 = zext i32 %ub to i64",
          "  %usum64 = add i64 %ua64, %ub64",
          -- maxStringLengthUtf16CodeUnits = 134217728 (= 2^27).
          -- Keep in sync with 'maxStringLengthUtf16CodeUnits' in
          -- 'stdlib/Prelude.aww'.
          "  %over = icmp ugt i64 %usum64, 134217728",
          "  br i1 %over, label %too_long, label %ok",
          "too_long:",
          -- Build 'Left StringTooLong'. StringTooLong is a single-ctor
          -- type so its tag is 0; Either's Left tag is 0.
          "  %stl = call ptr @__alloc(i64 8, i32 0)",
          "  %stl_tag = inttoptr i64 " <> stlLit <> " to ptr",
          "  store ptr %stl_tag, ptr %stl",
          "  %left = call ptr @__alloc(i64 16, i32 1)",
          "  %left_tag = inttoptr i64 " <> leftLit <> " to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %stl, ptr %left_f",
          "  br label %join",
          "ok:",
          -- Allocate header (8 bytes) + ba + bb byte payload.
          "  %ba64 = zext i32 %ba to i64",
          "  %bb64 = zext i32 %bb to i64",
          "  %bsum64 = add i64 %ba64, %bb64",
          "  %alloc64 = add i64 %bsum64, 8",
          "  %buf = call ptr @__alloc(i64 %alloc64, i32 0)",
          -- Write header: byte count at offset 0, utf16 count at offset 4.
          "  %bsum32 = trunc i64 %bsum64 to i32",
          "  store i32 %bsum32, ptr %buf",
          "  %usum32 = trunc i64 %usum64 to i32",
          "  %buf_u16p = getelementptr i8, ptr %buf, i64 4",
          "  store i32 %usum32, ptr %buf_u16p",
          -- Copy a.payload, then b.payload, into the new payload slot.
          "  %buf_payload = getelementptr i8, ptr %buf, i64 8",
          "  %a_payload = getelementptr i8, ptr %a, i64 8",
          "  call ptr @memcpy(ptr %buf_payload, ptr %a_payload, i64 %ba64)",
          "  %buf_payload_b = getelementptr i8, ptr %buf_payload, i64 %ba64",
          "  %b_payload = getelementptr i8, ptr %b, i64 8",
          "  call ptr @memcpy(ptr %buf_payload_b, ptr %b_payload, i64 %bb64)",
          -- Wrap in 'Right'. Either's Right tag is 1.
          "  %right = call ptr @__alloc(i64 16, i32 1)",
          "  %right_tag = inttoptr i64 " <> rightLit <> " to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %buf, ptr %right_f",
          "  br label %join",
          "join:",
          "  %result = phi ptr [%left, %too_long], [%right, %ok]",
          "  call void @__free_recursive(ptr %a)",
          "  call void @__free_recursive(ptr %b)",
          "  ret ptr %result",
          "}"
        ]
    -- '__print' uses 'write(2)' rather than 'printf("%s", …)' so a NUL
    -- byte inside the payload is preserved (printf-family stop at NUL
    -- regardless of '%.*s' precision per POSIX). Reads the byte count
    -- from the string header at offset 0 — O(1), no scan.
    rtPrint =
      unlines
        [ "define internal ptr @__print(ptr %s) {",
          "  %byte_count = load i32, ptr %s",
          "  %byte_count_64 = zext i32 %byte_count to i64",
          "  %payload = getelementptr i8, ptr %s, i64 8",
          "  call i64 @write(i32 1, ptr %payload, i64 %byte_count_64)",
          -- Build Unit value (single ptr slot, tag 0) — same shape as
          -- every other nullary CCon, so 'runIO' reads it via the
          -- standard CCase tag check.
          "  %unit = call ptr @__alloc(i64 8, i32 0)",
          "  %unit_tag_ptr = getelementptr ptr, ptr %unit, i32 0",
          "  %unit_tag = inttoptr i64 " <> unitLit <> " to ptr",
          "  store ptr %unit_tag, ptr %unit_tag_ptr",
          "  call void @__free_recursive(ptr %s)",
          "  ret ptr %unit",
          "}"
        ]
    -- Integers are boxed: each CIntLit allocates a heap cell holding
    -- the native i32/i8 value and the Awsum-level 'ptr' points at it.
    -- Show reads the cell and snprintf's the decimal form into the
    -- payload portion of a length-prefixed string buffer. snprintf
    -- returns the bytes-written count, which we use as both byte and
    -- UTF-16 length (decimal output is ASCII-only — 1 byte = 1 UTF-16
    -- code unit). Allocation is 8 (header) + 16 (max digits + sign +
    -- NUL); the trailing NUL written by snprintf is harmless because
    -- consumers read exactly 'byte_count' bytes from the payload.
    rtShowInt32 =
      unlines
        [ "define internal ptr @__showInt32(ptr %p) {",
          "  %v = load i32, ptr %p",
          "  %buf = call ptr @__alloc(i64 24, i32 0)",
          "  %payload = getelementptr i8, ptr %buf, i64 8",
          "  %n = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %payload, i64 16, ptr @.fmt_i32, i32 %v)",
          "  store i32 %n, ptr %buf",
          "  %u16p = getelementptr i8, ptr %buf, i64 4",
          "  store i32 %n, ptr %u16p",
          "  call void @__free_recursive(ptr %p)",
          "  ret ptr %buf",
          "}"
        ]
    rtShowUInt8 =
      unlines
        [ "define internal ptr @__showUInt8(ptr %p) {",
          "  %b = load i8, ptr %p",
          "  %v = zext i8 %b to i32",
          "  %buf = call ptr @__alloc(i64 24, i32 0)",
          "  %payload = getelementptr i8, ptr %buf, i64 8",
          "  %n = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %payload, i64 16, ptr @.fmt_u8, i32 %v)",
          "  store i32 %n, ptr %buf",
          "  %u16p = getelementptr i8, ptr %buf, i64 4",
          "  store i32 %n, ptr %u16p",
          "  call void @__free_recursive(ptr %p)",
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
          "  %oe = call ptr @__alloc(i64 8, i32 0)",
          "  %oe_tag = inttoptr i64 " <> ueLit <> " to ptr",
          "  store ptr %oe_tag, ptr %oe",
          "  %left = call ptr @__alloc(i64 16, i32 1)",
          "  %left_tag = inttoptr i64 " <> leftLit <> " to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %oe, ptr %left_f",
          "  call void @__free_recursive(ptr %p)",
          "  ret ptr %left",
          "ok:",
          "  %newv = sub i32 %v, 1",
          "  %box = call ptr @__alloc(i64 4, i32 0)",
          "  store i32 %newv, ptr %box",
          "  %right = call ptr @__alloc(i64 16, i32 1)",
          "  %right_tag = inttoptr i64 " <> rightLit <> " to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  call void @__free_recursive(ptr %p)",
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
          "  %oe = call ptr @__alloc(i64 8, i32 0)",
          "  %oe_tag = inttoptr i64 " <> ueLit <> " to ptr",
          "  store ptr %oe_tag, ptr %oe",
          "  %left = call ptr @__alloc(i64 16, i32 1)",
          "  %left_tag = inttoptr i64 " <> leftLit <> " to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %oe, ptr %left_f",
          "  call void @__free_recursive(ptr %p)",
          "  ret ptr %left",
          "ok:",
          "  %newv = sub i8 %v, 1",
          "  %box = call ptr @__alloc(i64 1, i32 0)",
          "  store i8 %newv, ptr %box",
          "  %right = call ptr @__alloc(i64 16, i32 1)",
          "  %right_tag = inttoptr i64 " <> rightLit <> " to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  call void @__free_recursive(ptr %p)",
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
          "  %oe = call ptr @__alloc(i64 8, i32 0)",
          "  %oe_tag = inttoptr i64 " <> oeLit <> " to ptr",
          "  store ptr %oe_tag, ptr %oe",
          "  %left = call ptr @__alloc(i64 16, i32 1)",
          "  %left_tag = inttoptr i64 " <> leftLit <> " to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %oe, ptr %left_f",
          "  call void @__free_recursive(ptr %p)",
          "  ret ptr %left",
          "ok:",
          "  %newv = add i32 %v, 1",
          "  %box = call ptr @__alloc(i64 4, i32 0)",
          "  store i32 %newv, ptr %box",
          "  %right = call ptr @__alloc(i64 16, i32 1)",
          "  %right_tag = inttoptr i64 " <> rightLit <> " to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  call void @__free_recursive(ptr %p)",
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
          "  %oe = call ptr @__alloc(i64 8, i32 0)",
          "  %oe_tag = inttoptr i64 " <> oeLit <> " to ptr",
          "  store ptr %oe_tag, ptr %oe",
          "  %left = call ptr @__alloc(i64 16, i32 1)",
          "  %left_tag = inttoptr i64 " <> leftLit <> " to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %oe, ptr %left_f",
          "  call void @__free_recursive(ptr %p)",
          "  ret ptr %left",
          "ok:",
          "  %newv = add i8 %v, 1",
          "  %box = call ptr @__alloc(i64 1, i32 0)",
          "  store i8 %newv, ptr %box",
          "  %right = call ptr @__alloc(i64 16, i32 1)",
          "  %right_tag = inttoptr i64 " <> rightLit <> " to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  call void @__free_recursive(ptr %p)",
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
          "  %tag = select i1 %eq, i64 " <> trueLit <> ", i64 " <> falseLit <> "",
          "  %box = call ptr @__alloc(i64 8, i32 0)",
          "  %tag_ptr = inttoptr i64 %tag to ptr",
          "  store ptr %tag_ptr, ptr %box",
          "  call void @__free_recursive(ptr %a)",
          "  call void @__free_recursive(ptr %b)",
          "  ret ptr %box",
          "}"
        ]
    rtEqUInt8 =
      unlines
        [ "define internal ptr @__eqUInt8(ptr %a, ptr %b) {",
          "  %va = load i8, ptr %a",
          "  %vb = load i8, ptr %b",
          "  %eq = icmp eq i8 %va, %vb",
          "  %tag = select i1 %eq, i64 " <> trueLit <> ", i64 " <> falseLit <> "",
          "  %box = call ptr @__alloc(i64 8, i32 0)",
          "  %tag_ptr = inttoptr i64 %tag to ptr",
          "  store ptr %tag_ptr, ptr %box",
          "  call void @__free_recursive(ptr %a)",
          "  call void @__free_recursive(ptr %b)",
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
          "  %row_tag_idx = select i1 %is_pos, i64 " <> overflowRowTag <> ", i64 " <> underflowRowTag,
          "  %inner_tag_idx = select i1 %is_pos, i64 " <> oeLit <> ", i64 " <> ueLit,
          "  %inner = call ptr @__alloc(i64 8, i32 0)",
          "  %inner_tag = inttoptr i64 %inner_tag_idx to ptr",
          "  store ptr %inner_tag, ptr %inner",
          "  %row = call ptr @__alloc(i64 16, i32 1)",
          "  %row_tag = inttoptr i64 %row_tag_idx to ptr",
          "  store ptr %row_tag, ptr %row",
          "  %row_f = getelementptr ptr, ptr %row, i32 1",
          "  store ptr %inner, ptr %row_f",
          "  %left = call ptr @__alloc(i64 16, i32 1)",
          "  %left_tag = inttoptr i64 " <> leftLit <> " to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %row, ptr %left_f",
          "  br label %join",
          "ok:",
          "  %box = call ptr @__alloc(i64 4, i32 0)",
          "  store i32 %sum, ptr %box",
          "  %right = call ptr @__alloc(i64 16, i32 1)",
          "  %right_tag = inttoptr i64 " <> rightLit <> " to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  br label %join",
          "join:",
          "  %result = phi ptr [%left, %err], [%right, %ok]",
          "  call void @__free_recursive(ptr %pa)",
          "  call void @__free_recursive(ptr %pb)",
          "  ret ptr %result",
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
          "  %row_tag_idx = select i1 %is_pos, i64 " <> overflowRowTag <> ", i64 " <> underflowRowTag,
          "  %inner_tag_idx = select i1 %is_pos, i64 " <> oeLit <> ", i64 " <> ueLit,
          "  %inner = call ptr @__alloc(i64 8, i32 0)",
          "  %inner_tag = inttoptr i64 %inner_tag_idx to ptr",
          "  store ptr %inner_tag, ptr %inner",
          "  %row = call ptr @__alloc(i64 16, i32 1)",
          "  %row_tag = inttoptr i64 %row_tag_idx to ptr",
          "  store ptr %row_tag, ptr %row",
          "  %row_f = getelementptr ptr, ptr %row, i32 1",
          "  store ptr %inner, ptr %row_f",
          "  %left = call ptr @__alloc(i64 16, i32 1)",
          "  %left_tag = inttoptr i64 " <> leftLit <> " to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %row, ptr %left_f",
          "  br label %join",
          "ok:",
          "  %box = call ptr @__alloc(i64 4, i32 0)",
          "  store i32 %diff, ptr %box",
          "  %right = call ptr @__alloc(i64 16, i32 1)",
          "  %right_tag = inttoptr i64 " <> rightLit <> " to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  br label %join",
          "join:",
          "  %result = phi ptr [%left, %err], [%right, %ok]",
          "  call void @__free_recursive(ptr %pa)",
          "  call void @__free_recursive(ptr %pb)",
          "  ret ptr %result",
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
          "  %row_tag_idx = select i1 %same_sign, i64 " <> overflowRowTag <> ", i64 " <> underflowRowTag,
          "  %inner = call ptr @__alloc(i64 8, i32 0)",
          "  %inner_tag = inttoptr i64 0 to ptr",
          "  store ptr %inner_tag, ptr %inner",
          "  %row = call ptr @__alloc(i64 16, i32 1)",
          "  %row_tag = inttoptr i64 %row_tag_idx to ptr",
          "  store ptr %row_tag, ptr %row",
          "  %row_f = getelementptr ptr, ptr %row, i32 1",
          "  store ptr %inner, ptr %row_f",
          "  %left = call ptr @__alloc(i64 16, i32 1)",
          "  %left_tag = inttoptr i64 " <> leftLit <> " to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %row, ptr %left_f",
          "  br label %join",
          "ok:",
          "  %box = call ptr @__alloc(i64 4, i32 0)",
          "  store i32 %prod, ptr %box",
          "  %right = call ptr @__alloc(i64 16, i32 1)",
          "  %right_tag = inttoptr i64 " <> rightLit <> " to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  br label %join",
          "join:",
          "  %result = phi ptr [%left, %err], [%right, %ok]",
          "  call void @__free_recursive(ptr %pa)",
          "  call void @__free_recursive(ptr %pb)",
          "  ret ptr %result",
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
          "  %oe = call ptr @__alloc(i64 8, i32 0)",
          "  %oe_tag = inttoptr i64 " <> oeLit <> " to ptr",
          "  store ptr %oe_tag, ptr %oe",
          "  %left = call ptr @__alloc(i64 16, i32 1)",
          "  %left_tag = inttoptr i64 " <> leftLit <> " to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %oe, ptr %left_f",
          "  call void @__free_recursive(ptr %p)",
          "  ret ptr %left",
          "ok:",
          "  %newv = sub i32 0, %v",
          "  %box = call ptr @__alloc(i64 4, i32 0)",
          "  store i32 %newv, ptr %box",
          "  %right = call ptr @__alloc(i64 16, i32 1)",
          "  %right_tag = inttoptr i64 " <> rightLit <> " to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  call void @__free_recursive(ptr %p)",
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
          "  %oe = call ptr @__alloc(i64 8, i32 0)",
          "  %oe_tag = inttoptr i64 " <> oeLit <> " to ptr",
          "  store ptr %oe_tag, ptr %oe",
          "  %left = call ptr @__alloc(i64 16, i32 1)",
          "  %left_tag = inttoptr i64 " <> leftLit <> " to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %oe, ptr %left_f",
          "  br label %join",
          "ok:",
          "  %newv = trunc i32 %sum32 to i8",
          "  %box = call ptr @__alloc(i64 1, i32 0)",
          "  store i8 %newv, ptr %box",
          "  %right = call ptr @__alloc(i64 16, i32 1)",
          "  %right_tag = inttoptr i64 " <> rightLit <> " to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  br label %join",
          "join:",
          "  %result = phi ptr [%left, %err], [%right, %ok]",
          "  call void @__free_recursive(ptr %pa)",
          "  call void @__free_recursive(ptr %pb)",
          "  ret ptr %result",
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
          "  %oe = call ptr @__alloc(i64 8, i32 0)",
          "  %oe_tag = inttoptr i64 " <> oeLit <> " to ptr",
          "  store ptr %oe_tag, ptr %oe",
          "  %left = call ptr @__alloc(i64 16, i32 1)",
          "  %left_tag = inttoptr i64 " <> leftLit <> " to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %oe, ptr %left_f",
          "  br label %join",
          "ok:",
          "  %newv = trunc i32 %prod32 to i8",
          "  %box = call ptr @__alloc(i64 1, i32 0)",
          "  store i8 %newv, ptr %box",
          "  %right = call ptr @__alloc(i64 16, i32 1)",
          "  %right_tag = inttoptr i64 " <> rightLit <> " to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  br label %join",
          "join:",
          "  %result = phi ptr [%left, %err], [%right, %ok]",
          "  call void @__free_recursive(ptr %pa)",
          "  call void @__free_recursive(ptr %pb)",
          "  ret ptr %result",
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
          "  %ue = call ptr @__alloc(i64 8, i32 0)",
          "  %ue_tag = inttoptr i64 " <> ueLit <> " to ptr",
          "  store ptr %ue_tag, ptr %ue",
          "  %left = call ptr @__alloc(i64 16, i32 1)",
          "  %left_tag = inttoptr i64 " <> leftLit <> " to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %ue, ptr %left_f",
          "  br label %join",
          "ok:",
          "  %diff32 = sub i32 %a32, %b32",
          "  %newv = trunc i32 %diff32 to i8",
          "  %box = call ptr @__alloc(i64 1, i32 0)",
          "  store i8 %newv, ptr %box",
          "  %right = call ptr @__alloc(i64 16, i32 1)",
          "  %right_tag = inttoptr i64 " <> rightLit <> " to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  br label %join",
          "join:",
          "  %result = phi ptr [%left, %err], [%right, %ok]",
          "  call void @__free_recursive(ptr %pa)",
          "  call void @__free_recursive(ptr %pb)",
          "  ret ptr %result",
          "}"
        ]
    -- splitOnFirst : String -> String -> Maybe (Tuple2 String String).
    --   Now operates on length-prefixed strings: byte counts come from
    --   the header (offset 0) directly, no 'strlen'. Empty separator
    --   matches at position 0 (prefix = "", suffix = str). Both halves
    --   are owning copies in length-prefixed format with their own
    --   computed UTF-16 counts via inline byte scans (BMP byte → 1 code
    --   unit, 4-byte UTF-8 → 2 surrogates).
    rtSplitOnFirst =
      unlines
        [ "define internal ptr @__splitOnFirst(ptr %sep, ptr %str) {",
          "entry:",
          "  %sep_len32 = load i32, ptr %sep",
          "  %str_len32 = load i32, ptr %str",
          "  %sep_len = zext i32 %sep_len32 to i64",
          "  %str_len = zext i32 %str_len32 to i64",
          "  %sep_payload = getelementptr i8, ptr %sep, i64 8",
          "  %str_payload = getelementptr i8, ptr %str, i64 8",
          -- A separator longer than the input can't match.
          "  %too_long = icmp ugt i64 %sep_len, %str_len",
          "  br i1 %too_long, label %not_found, label %search_init",
          "search_init:",
          -- Last possible start position: str_len - sep_len. The empty
          -- separator case slips through with %limit = %str_len.
          "  %limit = sub i64 %str_len, %sep_len",
          "  %i_p = alloca i64, align 8",
          "  store i64 0, ptr %i_p",
          "  br label %outer",
          "outer:",
          "  %i = load i64, ptr %i_p",
          "  %i_done = icmp ugt i64 %i, %limit",
          "  br i1 %i_done, label %not_found, label %inner_init",
          "inner_init:",
          "  %j_p = alloca i64, align 8",
          "  store i64 0, ptr %j_p",
          "  br label %inner",
          "inner:",
          "  %j = load i64, ptr %j_p",
          "  %j_done = icmp uge i64 %j, %sep_len",
          "  br i1 %j_done, label %match, label %inner_step",
          "inner_step:",
          "  %ij = add i64 %i, %j",
          "  %sp = getelementptr i8, ptr %str_payload, i64 %ij",
          "  %sb = load i8, ptr %sp",
          "  %sepp = getelementptr i8, ptr %sep_payload, i64 %j",
          "  %sepb = load i8, ptr %sepp",
          "  %eq = icmp eq i8 %sb, %sepb",
          "  br i1 %eq, label %inner_advance, label %outer_advance",
          "inner_advance:",
          "  %j1 = add i64 %j, 1",
          "  store i64 %j1, ptr %j_p",
          "  br label %inner",
          "outer_advance:",
          "  %i1 = add i64 %i, 1",
          "  store i64 %i1, ptr %i_p",
          "  br label %outer",
          "match:",
          -- Split position = %i. prefix bytes = str[0..i], suffix bytes
          -- = str[i+sep_len..str_len].
          "  %prefix_blen = phi i64 [%i, %inner]",
          "  %prefix_after = add i64 %i, %sep_len",
          "  %suffix_blen = sub i64 %str_len, %prefix_after",
          "  %suffix_start = getelementptr i8, ptr %str_payload, i64 %prefix_after",
          -- Build prefix string with its own UTF-16 count.
          "  %prefix_u16 = call i32 @__utf16OfRange(ptr %str_payload, i64 %prefix_blen)",
          "  %prefix_alloc = add i64 %prefix_blen, 8",
          "  %prefix = call ptr @__alloc(i64 %prefix_alloc, i32 0)",
          "  %prefix_blen32 = trunc i64 %prefix_blen to i32",
          "  store i32 %prefix_blen32, ptr %prefix",
          "  %prefix_u16p = getelementptr i8, ptr %prefix, i64 4",
          "  store i32 %prefix_u16, ptr %prefix_u16p",
          "  %prefix_payload = getelementptr i8, ptr %prefix, i64 8",
          "  call ptr @memcpy(ptr %prefix_payload, ptr %str_payload, i64 %prefix_blen)",
          -- Build suffix string with its own UTF-16 count.
          "  %suffix_u16 = call i32 @__utf16OfRange(ptr %suffix_start, i64 %suffix_blen)",
          "  %suffix_alloc = add i64 %suffix_blen, 8",
          "  %suffix = call ptr @__alloc(i64 %suffix_alloc, i32 0)",
          "  %suffix_blen32 = trunc i64 %suffix_blen to i32",
          "  store i32 %suffix_blen32, ptr %suffix",
          "  %suffix_u16p = getelementptr i8, ptr %suffix, i64 4",
          "  store i32 %suffix_u16, ptr %suffix_u16p",
          "  %suffix_payload = getelementptr i8, ptr %suffix, i64 8",
          "  call ptr @memcpy(ptr %suffix_payload, ptr %suffix_start, i64 %suffix_blen)",
          -- Tuple2 prefix suffix → Just (Tuple2 prefix suffix).
          "  %tuple = call ptr @__alloc(i64 24, i32 2)",
          "  %tuple_tag = inttoptr i64 " <> tuple2Lit <> " to ptr",
          "  store ptr %tuple_tag, ptr %tuple",
          "  %tuple_a = getelementptr ptr, ptr %tuple, i32 1",
          "  store ptr %prefix, ptr %tuple_a",
          "  %tuple_b = getelementptr ptr, ptr %tuple, i32 2",
          "  store ptr %suffix, ptr %tuple_b",
          "  %just = call ptr @__alloc(i64 16, i32 1)",
          "  %just_tag = inttoptr i64 " <> justLit <> " to ptr",
          "  store ptr %just_tag, ptr %just",
          "  %just_f = getelementptr ptr, ptr %just, i32 1",
          "  store ptr %tuple, ptr %just_f",
          "  br label %join",
          "not_found:",
          "  %nothing = call ptr @__alloc(i64 8, i32 0)",
          "  %nothing_tag = inttoptr i64 " <> nothingLit <> " to ptr",
          "  store ptr %nothing_tag, ptr %nothing",
          "  br label %join",
          "join:",
          "  %result = phi ptr [%just, %match], [%nothing, %not_found]",
          "  call void @__free_recursive(ptr %sep)",
          "  call void @__free_recursive(ptr %str)",
          "  ret ptr %result",
          "}",
          "",
          -- Inline byte-walker: count UTF-16 code units in [%p, %p+%len).
          -- BMP code points (1/2/3-byte UTF-8 sequences) contribute 1;
          -- supplementary (4-byte, leading 11110xxx) contribute 2.
          -- Continuation bytes (10xxxxxx) skipped.
          "define internal i32 @__utf16OfRange(ptr %p, i64 %len) {",
          "entry:",
          "  %i_p = alloca i64, align 8",
          "  store i64 0, ptr %i_p",
          "  %n_p = alloca i32, align 4",
          "  store i32 0, ptr %n_p",
          "  br label %head",
          "head:",
          "  %i = load i64, ptr %i_p",
          "  %done = icmp uge i64 %i, %len",
          "  br i1 %done, label %end, label %body",
          "body:",
          "  %bp = getelementptr i8, ptr %p, i64 %i",
          "  %b = load i8, ptr %bp",
          "  %bz = zext i8 %b to i32",
          "  %top2 = and i32 %bz, 192",
          "  %is_cont = icmp eq i32 %top2, 128",
          "  br i1 %is_cont, label %step, label %check4",
          "check4:",
          "  %top5 = and i32 %bz, 248",
          "  %is_4 = icmp eq i32 %top5, 240",
          "  br i1 %is_4, label %add2, label %add1",
          "add2:",
          "  %n2 = load i32, ptr %n_p",
          "  %n2_new = add i32 %n2, 2",
          "  store i32 %n2_new, ptr %n_p",
          "  br label %step",
          "add1:",
          "  %n1 = load i32, ptr %n_p",
          "  %n1_new = add i32 %n1, 1",
          "  store i32 %n1_new, ptr %n_p",
          "  br label %step",
          "step:",
          "  %i1 = add i64 %i, 1",
          "  store i64 %i1, ptr %i_p",
          "  br label %head",
          "end:",
          "  %nf = load i32, ptr %n_p",
          "  ret i32 %nf",
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
          -- O(1) length from header; payload starts at offset 8.
          "  %len32 = load i32, ptr %s",
          "  %len = zext i32 %len32 to i64",
          "  %payload = getelementptr i8, ptr %s, i64 8",
          "  %is_empty = icmp eq i64 %len, 0",
          "  br i1 %is_empty, label %fail, label %check_sign",
          "check_sign:",
          "  %first = load i8, ptr %payload",
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
          "  %ptr_c = getelementptr i8, ptr %payload, i64 %i",
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
          "  %box = call ptr @__alloc(i64 4, i32 0)",
          "  store i32 %result, ptr %box",
          "  %right = call ptr @__alloc(i64 16, i32 1)",
          "  %right_tag = inttoptr i64 " <> rightLit <> " to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  br label %join",
          "fail:",
          "  %pe = call ptr @__alloc(i64 8, i32 0)",
          "  %pe_tag = inttoptr i64 " <> peLit <> " to ptr",
          "  store ptr %pe_tag, ptr %pe",
          "  %left = call ptr @__alloc(i64 16, i32 1)",
          "  %left_tag = inttoptr i64 " <> leftLit <> " to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %pe, ptr %left_f",
          "  br label %join",
          "join:",
          "  %res = phi ptr [%right, %build_right], [%left, %fail]",
          "  call void @__free_recursive(ptr %s)",
          "  ret ptr %res",
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
          -- O(1) length from header; payload at offset 8.
          "  %len32 = load i32, ptr %s",
          "  %len = zext i32 %len32 to i64",
          "  %payload = getelementptr i8, ptr %s, i64 8",
          "  %is_empty = icmp eq i64 %len, 0",
          "  br i1 %is_empty, label %fail, label %loop_head",
          "loop_head:",
          "  %i = load i64, ptr %i_alloca",
          "  %acc = load i32, ptr %acc_alloca",
          "  %cond = icmp ult i64 %i, %len",
          "  br i1 %cond, label %body, label %ok",
          "body:",
          "  %ptr_c = getelementptr i8, ptr %payload, i64 %i",
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
          "  %box = call ptr @__alloc(i64 1, i32 0)",
          "  store i8 %result_i8, ptr %box",
          "  %right = call ptr @__alloc(i64 16, i32 1)",
          "  %right_tag = inttoptr i64 " <> rightLit <> " to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  br label %join",
          "fail:",
          "  %pe = call ptr @__alloc(i64 8, i32 0)",
          "  %pe_tag = inttoptr i64 " <> peLit <> " to ptr",
          "  store ptr %pe_tag, ptr %pe",
          "  %left = call ptr @__alloc(i64 16, i32 1)",
          "  %left_tag = inttoptr i64 " <> leftLit <> " to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %pe, ptr %left_f",
          "  br label %join",
          "join:",
          "  %res = phi ptr [%right, %ok], [%left, %fail]",
          "  call void @__free_recursive(ptr %s)",
          "  ret ptr %res",
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
          "  %buf = call ptr @__alloc(i64 24, i32 0)",
          "  %payload = getelementptr i8, ptr %buf, i64 8",
          "  %n = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %payload, i64 16, ptr @.fmt_u8, i32 %v)",
          "  store i32 %n, ptr %buf",
          "  %u16p = getelementptr i8, ptr %buf, i64 4",
          "  store i32 %n, ptr %u16p",
          "  call void @__free_recursive(ptr %p)",
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
          "  %ue = call ptr @__alloc(i64 8, i32 0)",
          "  %ue_tag = inttoptr i64 " <> ueLit <> " to ptr",
          "  store ptr %ue_tag, ptr %ue",
          "  %left = call ptr @__alloc(i64 16, i32 1)",
          "  %left_tag = inttoptr i64 " <> leftLit <> " to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %ue, ptr %left_f",
          "  call void @__free_recursive(ptr %p)",
          "  ret ptr %left",
          "ok:",
          "  %newv = sub i32 %v, 1",
          "  %box = call ptr @__alloc(i64 4, i32 0)",
          "  store i32 %newv, ptr %box",
          "  %right = call ptr @__alloc(i64 16, i32 1)",
          "  %right_tag = inttoptr i64 " <> rightLit <> " to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  call void @__free_recursive(ptr %p)",
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
          "  %oe = call ptr @__alloc(i64 8, i32 0)",
          "  %oe_tag = inttoptr i64 " <> oeLit <> " to ptr",
          "  store ptr %oe_tag, ptr %oe",
          "  %left = call ptr @__alloc(i64 16, i32 1)",
          "  %left_tag = inttoptr i64 " <> leftLit <> " to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %oe, ptr %left_f",
          "  call void @__free_recursive(ptr %p)",
          "  ret ptr %left",
          "ok:",
          "  %newv = add i32 %v, 1",
          "  %box = call ptr @__alloc(i64 4, i32 0)",
          "  store i32 %newv, ptr %box",
          "  %right = call ptr @__alloc(i64 16, i32 1)",
          "  %right_tag = inttoptr i64 " <> rightLit <> " to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  call void @__free_recursive(ptr %p)",
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
          "  %tag = select i1 %eq, i64 " <> trueLit <> ", i64 " <> falseLit <> "",
          "  %box = call ptr @__alloc(i64 8, i32 0)",
          "  %tag_ptr = inttoptr i64 %tag to ptr",
          "  store ptr %tag_ptr, ptr %box",
          "  call void @__free_recursive(ptr %a)",
          "  call void @__free_recursive(ptr %b)",
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
          "  %oe = call ptr @__alloc(i64 8, i32 0)",
          "  %oe_tag = inttoptr i64 " <> oeLit <> " to ptr",
          "  store ptr %oe_tag, ptr %oe",
          "  %left = call ptr @__alloc(i64 16, i32 1)",
          "  %left_tag = inttoptr i64 " <> leftLit <> " to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %oe, ptr %left_f",
          "  br label %join",
          "ok:",
          "  %newv = trunc i64 %sum64 to i32",
          "  %box = call ptr @__alloc(i64 4, i32 0)",
          "  store i32 %newv, ptr %box",
          "  %right = call ptr @__alloc(i64 16, i32 1)",
          "  %right_tag = inttoptr i64 " <> rightLit <> " to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  br label %join",
          "join:",
          "  %result = phi ptr [%left, %err], [%right, %ok]",
          "  call void @__free_recursive(ptr %pa)",
          "  call void @__free_recursive(ptr %pb)",
          "  ret ptr %result",
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
          "  %ue = call ptr @__alloc(i64 8, i32 0)",
          "  %ue_tag = inttoptr i64 " <> ueLit <> " to ptr",
          "  store ptr %ue_tag, ptr %ue",
          "  %left = call ptr @__alloc(i64 16, i32 1)",
          "  %left_tag = inttoptr i64 " <> leftLit <> " to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %ue, ptr %left_f",
          "  br label %join",
          "ok:",
          "  %newv = sub i32 %a, %b",
          "  %box = call ptr @__alloc(i64 4, i32 0)",
          "  store i32 %newv, ptr %box",
          "  %right = call ptr @__alloc(i64 16, i32 1)",
          "  %right_tag = inttoptr i64 " <> rightLit <> " to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  br label %join",
          "join:",
          "  %result = phi ptr [%left, %err], [%right, %ok]",
          "  call void @__free_recursive(ptr %pa)",
          "  call void @__free_recursive(ptr %pb)",
          "  ret ptr %result",
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
          "  %oe = call ptr @__alloc(i64 8, i32 0)",
          "  %oe_tag = inttoptr i64 " <> oeLit <> " to ptr",
          "  store ptr %oe_tag, ptr %oe",
          "  %left = call ptr @__alloc(i64 16, i32 1)",
          "  %left_tag = inttoptr i64 " <> leftLit <> " to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %oe, ptr %left_f",
          "  br label %join",
          "ok:",
          "  %newv = trunc i64 %prod64 to i32",
          "  %box = call ptr @__alloc(i64 4, i32 0)",
          "  store i32 %newv, ptr %box",
          "  %right = call ptr @__alloc(i64 16, i32 1)",
          "  %right_tag = inttoptr i64 " <> rightLit <> " to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  br label %join",
          "join:",
          "  %result = phi ptr [%left, %err], [%right, %ok]",
          "  call void @__free_recursive(ptr %pa)",
          "  call void @__free_recursive(ptr %pb)",
          "  ret ptr %result",
          "}"
        ]
    -- lengthUtf8Bytes: O(1) — load the byte count from the string's
    -- 8-byte header at offset 0. Was 'strlen' over a null-terminated
    -- payload; the new length-prefixed layout caches this directly.
    rtLengthBytesAsUtf8 =
      unlines
        [ "define internal ptr @__lengthUtf8Bytes(ptr %s) {",
          "  %len32 = load i32, ptr %s",
          "  %box = call ptr @__alloc(i64 4, i32 0)",
          "  store i32 %len32, ptr %box",
          "  call void @__free_recursive(ptr %s)",
          "  ret ptr %box",
          "}"
        ]
    -- lengthCodePoints: still O(n) — code-point count requires walking
    -- the bytes (continuation bytes don't start a code point). The walk
    -- is now bounded by the byte_count from the header (offset 0)
    -- rather than terminated by a NUL, so a payload containing NUL is
    -- counted correctly.
    rtLengthCodePoints =
      unlines
        [ "define internal ptr @__lengthCodePoints(ptr %s) {",
          "entry:",
          "  %total_bytes = load i32, ptr %s",
          "  %total_bytes_64 = zext i32 %total_bytes to i64",
          "  %payload = getelementptr i8, ptr %s, i64 8",
          "  %i_p = alloca i64, align 8",
          "  store i64 0, ptr %i_p",
          "  %n_p = alloca i32, align 4",
          "  store i32 0, ptr %n_p",
          "  br label %head",
          "head:",
          "  %i = load i64, ptr %i_p",
          "  %at_end = icmp uge i64 %i, %total_bytes_64",
          "  br i1 %at_end, label %done, label %body",
          "body:",
          "  %bp = getelementptr i8, ptr %payload, i64 %i",
          "  %b = load i8, ptr %bp",
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
          "  %box = call ptr @__alloc(i64 4, i32 0)",
          "  store i32 %nf, ptr %box",
          "  call void @__free_recursive(ptr %s)",
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
          -- O(1) — load UTF-16 code unit count from the string header at
          -- offset 4. Was an O(n) byte scan over the null-terminated
          -- payload; the new length-prefixed layout caches this directly.
          "  %u16p = getelementptr i8, ptr %s, i64 4",
          "  %u16 = load i32, ptr %u16p",
          "  %box = call ptr @__alloc(i64 4, i32 0)",
          "  store i32 %u16, ptr %box",
          "  call void @__free_recursive(ptr %s)",
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
    -- '__getArgs' is the zero-arg runtime helper for
    -- 'BuiltIn.internalGetArgs', called from 'runIO''s 'IOGetArgs' arm.
    -- Reads the cached argv[1] from '@.cli_arg' and routes it through
    -- '__entryArgEither' for the strict-UTF-16 validation. Each call
    -- returns a fresh 'Either' cell — argv is invariant during
    -- execution, so repeat calls are deterministically equal.
    rtGetArgs =
      unlines
        [ "define internal ptr @__getArgs() {",
          "  %arg = load ptr, ptr @.cli_arg",
          -- argv[1] is a NUL-terminated C-string from libc (POSIX path)
          -- or a NUL-terminated UTF-8 buffer produced by
          -- 'WideCharToMultiByte(... -1 ...)' (Windows path); 'strlen'
          -- gives the byte count, and the NUL byte at @arg[strlen]@
          -- is the readable byte the length-aware '__entryArgEither'
          -- relies on for its one-past-end surrogate peek.
          "  %len = call i64 @strlen(ptr %arg)",
          "  %either = call ptr @__entryArgEither(ptr %arg, i64 %len)",
          "  ret ptr %either",
          "}"
        ]
    -- '__stdinReadAll' is the zero-arg runtime helper for
    -- 'BuiltIn.internalStdinReadAllAsUtf16', called from 'runIO''s
    -- 'IOStdinReadAll' arm. Reads fd 0 to EOF into a 'malloc'/'realloc'-
    -- grown scratch buffer (start 4 KiB, double when full), then routes
    -- the captured bytes through the same '__entryArgEither' decoder
    -- 'getArgs' uses. After the decode, the scratch buffer is 'free'd
    -- — '__entryArgEither' has already copied any 'Right' payload into
    -- a freshly '__alloc'-ed length-prefixed cell. Per the
    -- POSIX-honest no-memoisation decision, each call consumes whatever
    -- bytes remain on fd 0; a second call after EOF reads zero bytes
    -- and decodes to @Right ""@.
    rtStdinReadAll =
      unlines
        [ "define internal ptr @__stdinReadAll() {",
          "entry:",
          "  %cap_p = alloca i64, align 8",
          "  store i64 4096, ptr %cap_p",
          "  %len_p = alloca i64, align 8",
          "  store i64 0, ptr %len_p",
          "  %buf_p = alloca ptr, align 8",
          "  %buf0 = call ptr @malloc(i64 4096)",
          "  store ptr %buf0, ptr %buf_p",
          "  br label %read_head",
          "read_head:",
          -- Ensure at least 4 KiB of free space at the tail before issuing
          -- the next 'read'. If short, double the buffer.
          "  %cap = load i64, ptr %cap_p",
          "  %len = load i64, ptr %len_p",
          "  %remain = sub i64 %cap, %len",
          "  %need_grow = icmp ult i64 %remain, 4096",
          "  br i1 %need_grow, label %grow, label %do_read",
          "grow:",
          "  %new_cap = mul i64 %cap, 2",
          "  %old_buf = load ptr, ptr %buf_p",
          "  %new_buf = call ptr @realloc(ptr %old_buf, i64 %new_cap)",
          "  store ptr %new_buf, ptr %buf_p",
          "  store i64 %new_cap, ptr %cap_p",
          "  br label %do_read",
          "do_read:",
          "  %cap2 = load i64, ptr %cap_p",
          "  %len2 = load i64, ptr %len_p",
          "  %buf = load ptr, ptr %buf_p",
          "  %off_ptr = getelementptr i8, ptr %buf, i64 %len2",
          "  %remain2 = sub i64 %cap2, %len2",
          "  %got = call i64 @read(i32 0, ptr %off_ptr, i64 %remain2)",
          -- EOF (got == 0) or read error (got < 0) both terminate the
          -- loop; an error is treated as 'whatever we have so far'. Real
          -- I/O errors on stdin are extremely rare for piped input, and
          -- carrying a new row variant for them would mean every program
          -- using 'IO.Stdin.readAll' would have to handle it. Conscious
          -- trade-off — see [stdin-read-all.md] (in management/) for the
          -- one-pager.
          "  %eof = icmp sle i64 %got, 0",
          "  br i1 %eof, label %read_done, label %accumulate",
          "accumulate:",
          "  %len3 = load i64, ptr %len_p",
          "  %new_len = add i64 %len3, %got",
          "  store i64 %new_len, ptr %len_p",
          "  br label %read_head",
          "read_done:",
          -- Guarantee a readable byte at @buf[len]@ for '__entryArgEither's
          -- one-past-end surrogate peek. Grow by one if the buffer is
          -- exactly full, then store a 0 sentinel.
          "  %final_cap = load i64, ptr %cap_p",
          "  %final_len = load i64, ptr %len_p",
          "  %is_full = icmp eq i64 %final_cap, %final_len",
          "  br i1 %is_full, label %pad_grow, label %pad_write",
          "pad_grow:",
          "  %pad_old = load ptr, ptr %buf_p",
          "  %pad_cap = add i64 %final_cap, 1",
          "  %pad_new = call ptr @realloc(ptr %pad_old, i64 %pad_cap)",
          "  store ptr %pad_new, ptr %buf_p",
          "  br label %pad_write",
          "pad_write:",
          "  %buf_final = load ptr, ptr %buf_p",
          "  %past_end = getelementptr i8, ptr %buf_final, i64 %final_len",
          "  store i8 0, ptr %past_end",
          "  %either = call ptr @__entryArgEither(ptr %buf_final, i64 %final_len)",
          -- Scratch buffer is no longer needed: '__entryArgEither' has
          -- copied any 'Right' payload into a '__alloc'-managed cell.
          "  call void @free(ptr %buf_final)",
          "  ret ptr %either",
          "}"
        ]
    rtEntryArgEither =
      unlines
        [ "define internal ptr @__entryArgEither(ptr %arg, i64 %len) {",
          "entry:",
          "  %i_p = alloca i64, align 8",
          "  store i64 0, ptr %i_p",
          "  %n_p = alloca i32, align 4",
          "  store i32 0, ptr %n_p",
          "  %surr_p = alloca i32, align 4",
          "  store i32 0, ptr %surr_p",
          "  br label %head",
          "head:",
          -- Length-aware termination. The surrogate-detection branch in
          -- 'body' peeks one byte past the current position; the caller
          -- guarantees @arg[len]@ is a readable byte (NUL terminator for
          -- argv, a zero we write past the end of the stdin buffer).
          "  %i = load i64, ptr %i_p",
          "  %done = icmp uge i64 %i, %len",
          "  br i1 %done, label %scan_done, label %body",
          "body:",
          "  %bp = getelementptr i8, ptr %arg, i64 %i",
          "  %b = load i8, ptr %bp",
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
          -- argv[1] is a C-string from libc; convert it to length-prefixed
          -- form before handing to user code. 'i' at scan exit is the byte
          -- count (position of NUL). 'n_final' is the cached UTF-16 count.
          "  %byte_count_64 = load i64, ptr %i_p",
          "  %byte_count_32 = trunc i64 %byte_count_64 to i32",
          "  %alloc_size_64 = add i64 %byte_count_64, 8",
          "  %wrapped = call ptr @__alloc(i64 %alloc_size_64, i32 0)",
          "  store i32 %byte_count_32, ptr %wrapped",
          "  %wrapped_u16p = getelementptr i8, ptr %wrapped, i64 4",
          "  store i32 %n_final, ptr %wrapped_u16p",
          "  %wrapped_payload = getelementptr i8, ptr %wrapped, i64 8",
          "  call ptr @memcpy(ptr %wrapped_payload, ptr %arg, i64 %byte_count_64)",
          -- Right(wrapped): tag=1, payload=wrapped length-prefixed string.
          "  %right = call ptr @__alloc(i64 16, i32 1)",
          "  %right_tag = inttoptr i64 " <> rightLit <> " to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %wrapped, ptr %right_f",
          "  ret ptr %right",
          "too_long:",
          -- inner: StringTooLong CCon (single ctor, tag 0).
          "  %tl_inner = call ptr @__alloc(i64 8, i32 0)",
          "  %tl_inner_tag = inttoptr i64 " <> stlLit <> " to ptr",
          "  store ptr %tl_inner_tag, ptr %tl_inner",
          -- row: CRow box keyed by FNV-1a hash of "StringTooLong".
          "  %tl_row = call ptr @__alloc(i64 16, i32 1)",
          "  %tl_row_tag = inttoptr i64 " <> stringTooLongRowTag <> " to ptr",
          "  store ptr %tl_row_tag, ptr %tl_row",
          "  %tl_row_f = getelementptr ptr, ptr %tl_row, i32 1",
          "  store ptr %tl_inner, ptr %tl_row_f",
          "  %tl_left = call ptr @__alloc(i64 16, i32 1)",
          "  %tl_left_tag = inttoptr i64 " <> leftLit <> " to ptr",
          "  store ptr %tl_left_tag, ptr %tl_left",
          "  %tl_left_f = getelementptr ptr, ptr %tl_left, i32 1",
          "  store ptr %tl_row, ptr %tl_left_f",
          "  ret ptr %tl_left",
          "unpaired:",
          -- inner: UnpairedUtf16Surrogate CCon (single ctor, tag 0).
          "  %us_inner = call ptr @__alloc(i64 8, i32 0)",
          "  %us_inner_tag = inttoptr i64 " <> usLit <> " to ptr",
          "  store ptr %us_inner_tag, ptr %us_inner",
          -- row: CRow box keyed by FNV-1a hash of "UnpairedUtf16Surrogate".
          "  %us_row = call ptr @__alloc(i64 16, i32 1)",
          "  %us_row_tag = inttoptr i64 " <> unpairedSurrogateRowTag <> " to ptr",
          "  store ptr %us_row_tag, ptr %us_row",
          "  %us_row_f = getelementptr ptr, ptr %us_row, i32 1",
          "  store ptr %us_inner, ptr %us_row_f",
          "  %us_left = call ptr @__alloc(i64 16, i32 1)",
          "  %us_left_tag = inttoptr i64 " <> leftLit <> " to ptr",
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
          -- O(1) length from header; payload at offset 8.
          "  %len32 = load i32, ptr %s",
          "  %len = zext i32 %len32 to i64",
          "  %payload = getelementptr i8, ptr %s, i64 8",
          "  %is_empty = icmp eq i64 %len, 0",
          "  br i1 %is_empty, label %fail, label %loop_head",
          "loop_head:",
          "  %i = load i64, ptr %i_alloca",
          "  %acc = load i64, ptr %acc_alloca",
          "  %cond = icmp ult i64 %i, %len",
          "  br i1 %cond, label %body, label %ok",
          "body:",
          "  %ptr_c = getelementptr i8, ptr %payload, i64 %i",
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
          "  %box = call ptr @__alloc(i64 4, i32 0)",
          "  store i32 %result_i32, ptr %box",
          "  %right = call ptr @__alloc(i64 16, i32 1)",
          "  %right_tag = inttoptr i64 " <> rightLit <> " to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  br label %join",
          "fail:",
          "  %pe = call ptr @__alloc(i64 8, i32 0)",
          "  %pe_tag = inttoptr i64 " <> peLit <> " to ptr",
          "  store ptr %pe_tag, ptr %pe",
          "  %left = call ptr @__alloc(i64 16, i32 1)",
          "  %left_tag = inttoptr i64 " <> leftLit <> " to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %pe, ptr %left_f",
          "  br label %join",
          "join:",
          "  %res = phi ptr [%right, %ok], [%left, %fail]",
          "  call void @__free_recursive(ptr %s)",
          "  ret ptr %res",
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
      "  %input = phi ptr [%arg, %with_arg], [" <> emptyStringUserPtr <> ", %no_arg]",
      -- Cache argv[1] for 'BuiltIn.internalGetArgs' (called from
      -- 'runIO''s 'IOGetArgs' arm). 'main' itself takes no arguments
      -- (its signature is 'IO Never Unit'); user code that wants the
      -- argv reads it through 'IO.Args.getArgs', which lowers to the
      -- 'IOGetArgs' constructor and goes through this cached pointer
      -- when 'runIO' walks the IO tree. Argv is invariant for the
      -- lifetime of the process, so one store at entry is enough.
      "  store ptr %input, ptr @.cli_arg",
      -- v_main is a zero-arg value (CValDef) that builds the IO tree;
      -- `runIO` walks it to execute the effects. `runIO` is a regular
      -- Awsum function emitted via the standard CFunDef path, so it
      -- goes through TCO and ends up as a bounded-stack loop. The IO
      -- value itself is a heap-allocated ptr-tagged ADT cell, same
      -- shape as user ADTs.
      "  %io = call ptr @v_main()",
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
--
--   Before any IO, force fd 0 and fd 1 into binary mode through
--   @_setmode@. MSVC CRT opens stdio in text mode by default, which
--   translates @\\n@ ↔ @\\r\\n@ on read/write and treats @^Z@ as EOF
--   on input. The @write(1, …)@ path the @__print@ helper uses goes
--   through MSVC's @_write@, so any program that emits a @\\n@ would
--   silently get a @\\r\\n@ on stdout — breaking the cross-target
--   "identical stdout" invariant. The @_O_BINARY@ flag is @0x8000@.
--   Returns the previous mode; we discard it. Idempotent on backends
--   whose CRT already opens stdio in binary mode (e.g. some mingw-w64
--   link configurations).
footerWindows :: Text
footerWindows =
  unlines
    [ "",
      "declare i32 @_setmode(i32, i32)",
      "declare ptr @GetCommandLineW()",
      "declare ptr @CommandLineToArgvW(ptr, ptr)",
      "declare i32 @WideCharToMultiByte(i32, i32, ptr, i32, ptr, i32, ptr, ptr)",
      "",
      "define i32 @main(i32 %argc_posix, ptr %argv_posix) {",
      "entry:",
      "  call i32 @_setmode(i32 1, i32 32768)",
      "  call i32 @_setmode(i32 0, i32 32768)",
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
      "  %buf = call ptr @__alloc(i64 %needed64, i32 0)",
      "  %written = call i32 @WideCharToMultiByte(i32 65001, i32 0, ptr %arg_w, i32 -1, ptr %buf, i32 %needed, ptr null, ptr null)",
      "  br label %call_main",
      "no_arg:",
      "  br label %call_main",
      "call_main:",
      "  %input = phi ptr [%buf, %do_convert], [" <> emptyStringUserPtr <> ", %no_arg]",
      -- Cache argv[1] for 'BuiltIn.internalGetArgs'; see footerPosix.
      "  store ptr %input, ptr @.cli_arg",
      -- Same IO-tree handoff as the POSIX path; see footerPosix.
      "  %io = call ptr @v_main()",
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
      -- Keep the original (unmangled) name so 'lcParamSlots' can
      -- be used as a name source for 'emitTail' value-tail param
      -- decs — 'lookupBinderSSA' resolves names against 'locals'
      -- which is keyed by the original name.
      pure (a, slot)
    let entryAllocs =
          T.concat
            [ "  "
                <> slot
                <> " = alloca ptr\n"
                <> "  store ptr %"
                <> mangle origName
                <> ", ptr "
                <> slot
                <> "\n"
            | (origName, slot) <- paramSlotPairs
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
    -- Emit body via 'emitNonLoopBody' which walks the tail-form
    -- and emits the value-tail param decs at each terminal, with
    -- per-arm precision for 'CCase' / 'CRowCase' bodies so an arm
    -- returning a 'CVar' param is "moved" out without freeing the
    -- just-returned cell.
    bodyEmit <- emitNonLoopBody localCtx args body
    pure
      $ "define internal ptr @"
      <> mangle nm
      <> "("
      <> llvmArgs
      <> ") {\n"
      <> bodyEmit
      <> "}"
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

-- | Emit a non-CLoop 'CFunDef' body with proper value-tail
-- param decs. Walks the tail-form, emitting dec per terminal: for
-- 'CCase' / 'CRowCase' bodies each arm computes its own dec list
-- (so an arm returning a @CVar p@ doesn't free the cell the
-- function is about to return); for a bare @CVar n@ the matching
-- param is "moved" out; for any fresh source (CCon, CCall,
-- CIntLit, etc.) all params are dec'd.
emitNonLoopBody :: EmitCtx -> [Name] -> CExpr -> CodegenM Text
emitNonLoopBody ctx0 params = go ctx0 [] []
  where
    -- 'pending' accumulates 'CDrop'-bound binders during the tail
    -- walk; 'freshScruts' accumulates fresh case-scrutinee SSAs
    -- (no live binding-side owner once the case is over). Both
    -- get dec'd at every terminal, with move-semantics carve-out
    -- for the result-CVar on 'pending'/params (scruts have no
    -- name so they're dec'd unconditionally).
    go :: EmitCtx -> [Name] -> [Text] -> CExpr -> CodegenM Text
    go ctx pending freshScruts = \case
      CCase scrut alts -> goCase ctx pending freshScruts scrut alts
      CRowCase scrut alts ->
        goCase ctx pending freshScruts scrut [(fromIntegral t, [v], b) | (t, v, b) <- alts]
      CDrop _ n body -> go ctx (n : pending) freshScruts body
      other -> do
        (instrs, result) <- emitExpr ctx other
        let resultName = borrowedSource ctx other
            inResult m = Just m == resultName
            pendingToDec = filter (not . inResult) pending
            paramsToDec =
              [ p
              | p <- params,
                not (inResult p),
                p `notElem` pending
              ]
            scrutDecs = T.concat ["  call void @__free_recursive(ptr " <> s <> ")\n" | s <- freshScruts]
            frees =
              scrutDecs
                <> T.concat [emitFree ctx n | n <- pendingToDec]
                <> T.concat [emitFree ctx p | p <- paramsToDec]
        pure (instrs <> frees <> "  ret ptr " <> result <> "\n")

    -- Per-arm dec: each arm body emits its own (potentially
    -- different) param decs based on its own tail-form. Each arm
    -- self-terminates with a @ret@, so no phi join is needed.
    goCase :: EmitCtx -> [Name] -> [Text] -> CExpr -> [(Int, [Name], CExpr)] -> CodegenM Text
    goCase ctx pending freshScruts scrut alts = do
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
      defLabel <- freshLabel "case.default"
      -- Thread fresh scrut SSA through each arm so its terminator
      -- dec's it.
      let freshScruts' = case borrowedSource ctx scrut of
            Just _ -> freshScruts
            Nothing -> resS : freshScruts
      arms <- forM alts $ \(tag, vars, body) -> do
        lbl <- freshLabel ("case.arm." <> show tag)
        let armElided = case scrut of
              CVar n -> elidableArmBinders n vars body
              _ -> Set.empty
        varInstrs <- forM (zip vars [1 :: Int ..]) $ \(v, idx) -> do
          slotT <- freshTemp
          valT <- freshTemp
          let incPart =
                if v `Set.member` armElided
                  then ""
                  else "  call void @__inc_ref(ptr " <> valT <> ")\n"
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
                <> "\n"
                <> incPart,
              (v, valT)
            )
        let varCode = T.concat (map fst varInstrs)
            varBindings = map snd varInstrs
            -- Linear-scrutinee elision: see 'emitExpr' 'CCase'.
            ctx' =
              let withLocals = foldl' (\c (v, tmp) -> c {locals = Map.insert v tmp (locals c)}) ctx varBindings
                  withElided = withLocals {elidedBinders = elidedBinders withLocals `Set.union` armElided}
               in case scrut of
                    CVar n -> withElided {armPatternByScrut = Map.insert n vars (armPatternByScrut withElided)}
                    _ -> withElided
        armBody <- go ctx' pending freshScruts' body
        pure (tag, lbl, varCode <> armBody)
      let switchCases =
            T.concat [" i64 " <> show tag <> ", label %" <> lbl | (tag, lbl, _) <- arms]
          switchInstr = "  switch i64 " <> tagTmp <> ", label %" <> defLabel <> " [" <> switchCases <> " ]\n"
          armBlocks =
            T.concat [lbl <> ":\n" <> blk | (_, lbl, blk) <- arms]
          defBlock = defLabel <> ":\n  unreachable\n"
      pure (instrS <> tagInstr <> switchInstr <> armBlocks <> defBlock)

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
  Just lctx -> go ctx lctx [] [] expr
  where
    -- 'freshScruts' accumulates SSA names of fresh case-scrutinees
    -- (those whose source isn't a 'CVar', so they have no live
    -- binding-side owner once the case is over). Each terminator
    -- (CContinue, value-tail) dec's them after the inc-on-CVar
    -- pass for new args/result so cascade-free of slot values
    -- happens after the new owners have bumped their refcount.
    go :: EmitCtx -> LoopCtx -> [Name] -> [Text] -> CExpr -> CodegenM Text
    go ctx' lctx pending freshScruts = \case
      CContinue newArgs -> do
        argResults <- traverse (emitExpr ctx') newArgs
        let (argInstrsList, argNames) = unzip argResults
            -- Inc each ptr-arg whose source is a CVar (borrow →
            -- the next-iter slot takes its own ref). Fresh sources
            -- carry their @+1@ from @__alloc@.
            incs =
              T.concat
                [ emitIncIfCVar ctx' e r
                | (e, r) <- zip newArgs argNames
                ]
            scrutDecs = T.concat ["  call void @__free_recursive(ptr " <> s <> ")\n" | s <- freshScruts]
            frees = T.concat [emitFree ctx' n | n <- pending]
            stores =
              T.concat
                [ "  store ptr " <> r <> ", ptr " <> slot <> "\n"
                | (r, (_, slot)) <- zip argNames lctx.lcParamSlots
                ]
        pure
          $ T.concat argInstrsList
          <> incs
          <> scrutDecs
          <> frees
          <> stores
          <> "  br label %"
          <> lctx.lcLoopLabel
          <> "\n"
      CCase scrut alts -> do
        (instrS, resS) <- emitExpr ctx' scrut
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
        -- If the scrut is fresh, thread its SSA through to each
        -- arm so the arm's terminator dec's it.
        let freshScruts' = case borrowedSource ctx' scrut of
              Just _ -> freshScruts
              Nothing -> resS : freshScruts
        armBlocks <- forM alts $ \(tag, vars, body) -> do
          lbl <- freshLabel ("tco.case.arm." <> show tag)
          let armElided = case scrut of
                CVar n -> elidableArmBinders n vars body
                _ -> Set.empty
          -- Inc each extracted ptr-binder (see the non-tail
          -- 'CCase' in 'emitExpr' for the rationale). Skip the inc
          -- for binders in @armElided@ (move-armVars whose only
          -- use is a 'CReuse' field on the same scrut — their
          -- paired CDrop is also skipped via 'emitFree').
          varInstrs <- forM (zip vars [1 :: Int ..]) $ \(v, idx) -> do
            slotT <- freshTemp
            valT <- freshTemp
            let incPart =
                  if v `Set.member` armElided
                    then ""
                    else "  call void @__inc_ref(ptr " <> valT <> ")\n"
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
                  <> "\n"
                  <> incPart,
                (v, valT)
              )
          let varCode = T.concat (map fst varInstrs)
              varBindings = map snd varInstrs
              -- Linear-scrutinee elision: see the matching comment
              -- in 'emitExpr' 'CCase' for the rationale.
              ctx'' =
                let withLocals = foldl' (\c (v, tmp) -> c {locals = Map.insert v tmp (locals c)}) ctx' varBindings
                    withElided = withLocals {elidedBinders = elidedBinders withLocals `Set.union` armElided}
                 in case scrut of
                      CVar n -> withElided {armPatternByScrut = Map.insert n vars (armPatternByScrut withElided)}
                      _ -> withElided
          bodyInstrs <- go ctx'' lctx pending freshScruts' body
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
      CRowCase scrut alts ->
        go ctx' lctx pending freshScruts (CCase scrut [(fromIntegral t, [v], b) | (t, v, b) <- alts])
      CDrop _ n body -> go ctx' lctx (n : pending) freshScruts body
      other -> do
        (instrs, result) <- emitExpr ctx' other
        -- Value-tail decs.
        --
        --   * If the result is a 'CVar m', exclude @m@ from the dec
        --     list — the function transfers ownership to the caller
        --     (move-semantics). Without this, the dec of @m@ would
        --     drop the cell we just returned, leaving the caller
        --     with a dangling pointer.
        --   * 'freshScruts' SSAs are dec'd unconditionally (they
        --     have no name to match for move-semantics).
        --   * Pending (the binders accumulated from outer 'CDrop's
        --     during tail recursion) are dec'd with the same
        --     move-semantics carve-out.
        --   * Function params are dec'd here too — 'addContinueDrops'
        --     only emits param drops at 'CContinue' paths, so the
        --     value-tail path needs an explicit pass.
        let resultName = borrowedSource ctx' other
            inResult n = Just n == resultName
            pendingToDec = filter (not . inResult) pending
            paramNames = [p | (p, _) <- lctx.lcParamSlots]
            paramsToDec =
              [ p
              | p <- paramNames,
                not (inResult p),
                p `notElem` pending
              ]
            scrutDecs = T.concat ["  call void @__free_recursive(ptr " <> s <> ")\n" | s <- freshScruts]
            frees =
              scrutDecs
                <> T.concat [emitFree ctx' n | n <- pendingToDec]
                <> T.concat [emitFree ctx' p | p <- paramsToDec]
        pure
          $ instrs
          <> frees
          <> "  store ptr "
          <> result
          <> ", ptr "
          <> lctx.lcRetSlot
          <> "\n"
          <> "  br label %"
          <> lctx.lcExitLabel
          <> "\n"

lookupBinderSSA :: EmitCtx -> Name -> Text
lookupBinderSSA ctx n
  | Just t <- Map.lookup n ctx.locals = t
  | n `Set.member` ctx.params = "%" <> mangle n
  | otherwise = error $ "LLVM codegen: CDrop on unknown binder: " <> show n

-- | Lower a 'CDrop' to a cascading-free dec. Reads the
-- cell's refcount, on hitting 0 walks @shape@ and dec's each ptr
-- field, then releases the block. Literals (flag == 0) short-circuit.
--
-- Returns @""@ for binders in @ctx.elidedBinders@ — those have had
-- their inc-on-extract skipped at the case match, so the paired
-- dec here must also vanish for refcount balance. See
-- 'Awsum.Lifetime.elidableArmBinders' for the precondition.
emitFree :: EmitCtx -> Name -> Text
emitFree ctx n
  | n `Set.member` ctx.elidedBinders = ""
  | otherwise = "  call void @__free_recursive(ptr " <> lookupBinderSSA ctx n <> ")\n"

-- | If an expression's value flows through to a long-lived store
-- position (a cell slot, a 'CContinue' phi, a 'CCall' arg, a
-- 'CRow' wrap, a 'CReuse' field) and its source is a /borrowed/
-- @CVar@ (a local binder or function parameter, possibly under
-- @CDrop@ wrappers), return that binder's name. The caller emits
-- a @__inc_ref@ on the loaded SSA so the store position takes its
-- own reference and the borrowing owner keeps its.
--
-- Returns 'Nothing' for fresh-allocation sources (@CCon@, @CCall@,
-- @CIntLit@, @CString@) whose @+1@ from @__alloc@ is already the
-- new ref the receiving position needs, and for @CVar@s referring
-- to top-level @CValDef@s — those lower to @call ptr \@v_n()@,
-- which produces a fresh @+1@ allocation per reference (the body
-- runs and @__alloc@s its result every call). Treating those as
-- borrowed would emit a spurious @__inc_ref@ over the fresh @+1@;
-- with no second owner the cell never reaches @refcount == 0@ and
-- leaks on every reference in a hot loop.
borrowedSource :: EmitCtx -> CExpr -> Maybe Name
borrowedSource ctx = \case
  CVar n
    | n `Set.member` ctx.valDefs -> Nothing
    | n `Set.member` ctx.elidedBinders -> Nothing
    | otherwise -> Just n
  CDrop _ _ body -> borrowedSource ctx body
  _ -> Nothing

-- | Return the binder name at the tail of @expr@ when @expr@ is a
-- 'CVar' (possibly under 'CDrop' wrappers), regardless of whether
-- that binder is borrowed-vs-fresh or elided. Used by the CReuse
-- copy path, which needs to inc every CVar field unconditionally
-- (the fresh cell takes its own ref no matter what the in-place
-- elision rules say). Differs from 'borrowedSource' in that it
-- does not exclude valDefs or elided binders.
sourceCVarStripDrops :: CExpr -> Maybe Name
sourceCVarStripDrops = \case
  CVar n -> Just n
  CDrop _ _ body -> sourceCVarStripDrops body
  _ -> Nothing

-- | Emit a @__inc_ref@ call for the loaded SSA iff the source
-- expression is a borrowed @CVar@. See 'borrowedSource'.
emitIncIfCVar :: EmitCtx -> CExpr -> Text -> Text
emitIncIfCVar ctx expr ssa = case borrowedSource ctx expr of
  Just _ -> "  call void @__inc_ref(ptr " <> ssa <> ")\n"
  Nothing -> ""

-- | Emit an argument expression in a transfer position
-- (@CCall@ argument). Equivalent to 'emitExpr' followed by an
-- inc-on-CVar — keeps every CCall-arg evaluator inc'd consistently
-- without forcing each builtin's inline emit to remember the rule.
emitArgWithInc :: EmitCtx -> CExpr -> CodegenM (Text, Text)
emitArgWithInc ctx expr = do
  (instrs, ssa) <- emitExpr ctx expr
  pure (instrs <> emitIncIfCVar ctx expr ssa, ssa)

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
    -- The literal's storage is '{i32 flag=0, i32 byte_count, i32 utf16,
    -- [N x i8]}'; the user-facing pointer is '@.str.N + 4', i.e. it
    -- points at byte_count so all existing readers work unchanged.
    -- See 'emitStringConstants' / 'stringLiteralUserPtr'.
    pure ("", stringLiteralUserPtr idx)
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
          <> " = call ptr @__alloc(i64 "
          <> show bytes
          <> ", i32 0)\n"
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
    -- Allocate container: [tag_as_ptr, field1, field2, ...]. Shape
    -- = number of ptr fields starting at slot 1 (== arity), so
    -- '__free_recursive' cascades correctly. Nullary constructors
    -- bake @shape = 0@; everything else passes its arity.
    let nSlots = 1 + length fields
        nFields = length fields
    arrTmp <- freshTemp
    let allocInstr =
          "  "
            <> arrTmp
            <> " = call ptr @__alloc(i64 "
            <> show (nSlots * 8 :: Int)
            <> ", i32 "
            <> show nFields
            <> ")\n"
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
    -- Store each field. Inc-on-store: if the field source is a
    -- CVar (borrow), inc its refcount — the new cell's slot
    -- takes its own reference. Fresh sources (CCon/CCall/CIntLit/
    -- CString) bring their @+1@ from @__alloc@ and need no inc.
    fieldInstrs <- forM (zip fields [1 :: Int ..]) $ \(fExpr, idx) -> do
      (instrF, resF) <- emitExpr ctx fExpr
      slotTmp <- freshTemp
      pure
        ( instrF
            <> emitIncIfCVar ctx fExpr resF
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
  -- Lower CDrop: evaluate body, then dec the dropped binder.
  -- If the body's tail value is the dropped binder itself, inc the
  -- result first so the dec balances out (move-semantics on
  -- single-binder shadowing). This matches the @emitTail@ value-tail
  -- carve-out and prevents a cascade-free of the just-returned cell.
  CDrop _ n body -> do
    (bodyInstrs, bodyResult) <- emitExpr ctx body
    let incInstr = case borrowedSource ctx body of
          Just m | m == n -> "  call void @__inc_ref(ptr " <> bodyResult <> ")\n"
          _ -> ""
    pure (bodyInstrs <> incInstr <> emitFree ctx n, bodyResult)
  -- Cell reuse. In-place mutation: write tag at slot 0
  -- and each field at slot i+1 of the existing user-pointer at @n@.
  -- No '__alloc', no '__free' — the matched-out cell is recycled.
  -- The flag header at @user_ptr - 4@ stays intact (still flag=1
  -- heap), so a later 'CDrop' on this binder's flow still
  -- correctly recognises the cell as heap-allocated.
  --
  -- Invariant from 'Awsum.Reuse.rewriteFirstCCon': @length fields@
  -- equals the matched arm's pattern arity, so the cell has at
  -- least @1 + length fields@ slots — every store stays in bounds.
  CReuse n tag fields -> do
    -- Reuse-under-RC coexistence: CReuse is in-place mutation,
    -- which is safe only if the cell is uniquely owned (refcount
    -- == 1). Under RC the cell may be shared (refcount > 1) when
    -- the matched binder aliases another live binding; in that
    -- case we copy-on-write instead, leaving the shared cell
    -- intact and producing a fresh one. The runtime branch is
    -- ~3 cycles on the linear path (load refcount + compare +
    -- predicted branch).
    --
    -- Linear-scrutinee elision (self-move + permutation): if a
    -- field is @CVar v@ where @v@ is one of the arm-pattern binders
    -- of the scrut, the cell still owns @v@ through the rewrite —
    -- just at a different slot. Two cases:
    --
    --   * Self-move: @v@ is the binder at the same slot. Skip the
    --     whole dec-old/inc-new/store triple — the slot already
    --     holds @v@.
    --   * Permutation: @v@ is a binder of some other slot. Skip
    --     dec-old at @v@'s old slot (the dec would consume the
    --     extract-inc that was also elided for @v@); skip inc-new
    --     at the new slot (via 'borrowedSource' returning Nothing
    --     for elided binders); emit the store at the new slot.
    --
    -- The matching binder-level elision (skip extract-inc on @v@,
    -- skip CDrop @v@) is driven by 'ctx.elidedBinders', populated
    -- at arm entry via 'Awsum.Lifetime.elidableArmBinders'. The
    -- arm-pattern lookup here goes through 'ctx.armPatternByScrut[n]'.
    let nPtr = lookupBinderSSA ctx n
        nFields = length fields
        armVars = Map.findWithDefault [] n ctx.armPatternByScrut
        nthMaybe :: Int -> [a] -> Maybe a
        nthMaybe i xs = listToMaybe (drop i xs)
        isSelfMoveAt :: Int -> Bool
        isSelfMoveAt slotIdx =
          case (nthMaybe (slotIdx - 1) fields, nthMaybe (slotIdx - 1) armVars) of
            (Just (CVar v), Just w) -> v == w
            _ -> False
        -- Skip dec-old at slot @slotIdx@ iff its old occupant
        -- (@armVars[slotIdx-1]@) is one of the elided binders —
        -- those have had their extract-inc skipped, so the dec-old
        -- here would over-dec the cell.
        skipDecOldAt :: Int -> Bool
        skipDecOldAt slotIdx =
          isSelfMoveAt slotIdx
            || case nthMaybe (slotIdx - 1) armVars of
              Just w -> w `Set.member` ctx.elidedBinders
              Nothing -> False
    -- Pre-evaluate fields once — both branches need the same
    -- field SSAs to either store-in-place or store-into-fresh.
    fieldResults <- forM fields (emitExpr ctx)
    let (fieldInstrsList, fieldNames) = unzip fieldResults
        fieldInstrsCat = T.concat fieldInstrsList
        zippedFields = zip3 fields fieldNames [1 :: Int ..]
    rcPtr <- freshTemp
    rcVal <- freshTemp
    isUnique <- freshTemp
    reuseLbl <- freshLabel "reuse.in_place"
    copyLbl <- freshLabel "reuse.copy"
    joinLbl <- freshLabel "reuse.join"
    let rcCheck =
          "  "
            <> rcPtr
            <> " = getelementptr i8, ptr "
            <> nPtr
            <> ", i64 -8\n"
            <> "  "
            <> rcVal
            <> " = load i32, ptr "
            <> rcPtr
            <> "\n"
            <> "  "
            <> isUnique
            <> " = icmp eq i32 "
            <> rcVal
            <> ", 1\n"
            <> "  br i1 "
            <> isUnique
            <> ", label %"
            <> reuseLbl
            <> ", label %"
            <> copyLbl
            <> "\n"
    -- In-place reuse path — uniquely owned cell. Before overwriting
    -- slots we dec each old slot value (the cell's existing
    -- references-via-slot dies); then inc each new CVar source
    -- (the cell's new slot takes its own reference). Fresh
    -- sources (CCon/CCall/CIntLit/CString) bring their @+1@ from
    -- @__alloc@ and need no inc — same rule as the CCon-store
    -- discipline. The cell's own refcount stays at 1.
    -- Self-move slots: skip dec-old entirely (the slot value is
    -- preserved across the CReuse).
    inPlaceOldDecs <- forM [1 .. nFields] $ \idx ->
      if skipDecOldAt idx
        then pure ""
        else do
          oldSlotPtr <- freshTemp
          oldVal <- freshTemp
          pure
            ( "  "
                <> oldSlotPtr
                <> " = getelementptr ptr, ptr "
                <> nPtr
                <> ", i32 "
                <> show idx
                <> "\n"
                <> "  "
                <> oldVal
                <> " = load ptr, ptr "
                <> oldSlotPtr
                <> "\n"
                <> "  call void @__free_recursive(ptr "
                <> oldVal
                <> ")\n"
            )
    -- Self-move slots: skip store + inc-new entirely (the slot
    -- already has the right pointer, no new ref needed).
    inPlaceFieldStores <- forM zippedFields $ \(fExpr, resF, idx) ->
      if isSelfMoveAt idx
        then pure ""
        else do
          slotTmp <- freshTemp
          pure
            ( emitIncIfCVar ctx fExpr resF
                <> "  "
                <> slotTmp
                <> " = getelementptr ptr, ptr "
                <> nPtr
                <> ", i32 "
                <> show idx
                <> "\n"
                <> "  store ptr "
                <> resF
                <> ", ptr "
                <> slotTmp
                <> "\n"
            )
    inPlaceTag <- freshTemp
    inPlaceTagSlot <- freshTemp
    let inPlaceBlock =
          reuseLbl
            <> ":\n"
            <> T.concat inPlaceOldDecs
            <> "  "
            <> inPlaceTag
            <> " = inttoptr i64 "
            <> show tag
            <> " to ptr\n"
            <> "  "
            <> inPlaceTagSlot
            <> " = getelementptr ptr, ptr "
            <> nPtr
            <> ", i32 0\n"
            <> "  store ptr "
            <> inPlaceTag
            <> ", ptr "
            <> inPlaceTagSlot
            <> "\n"
            <> T.concat inPlaceFieldStores
            <> "  br label %"
            <> joinLbl
            <> "\n"
    -- Copy path — allocate a fresh cell with proper shape, store
    -- tag + fields (with inc-on-CVar so the new cell takes its
    -- own refs), then dec @n@ to balance the missing reuse-path
    -- consumption.
    copyTmp <- freshTemp
    copyTagPtr <- freshTemp
    copyTagSlot <- freshTemp
    let copyAlloc =
          "  "
            <> copyTmp
            <> " = call ptr @__alloc(i64 "
            <> show ((1 + nFields) * 8 :: Int)
            <> ", i32 "
            <> show nFields
            <> ")\n"
        copyTag =
          "  "
            <> copyTagPtr
            <> " = inttoptr i64 "
            <> show tag
            <> " to ptr\n"
            <> "  "
            <> copyTagSlot
            <> " = getelementptr ptr, ptr "
            <> copyTmp
            <> ", i32 0\n"
            <> "  store ptr "
            <> copyTagPtr
            <> ", ptr "
            <> copyTagSlot
            <> "\n"
    -- In the copy path, the fresh cell takes its own ownership of
    -- each ptr field AND the old cell @n@ stays alive at @rc - 1@
    -- still holding its references, so every borrowed CVar source
    -- needs an inc here. The 'elidedBinders' carve-out applies only
    -- to the in-place path (cell stays, slot just shifts); in the
    -- copy path we bypass 'emitIncIfCVar' (which would skip incs on
    -- elided binders) and emit the inc unconditionally for any CVar
    -- that isn't a top-level 'CValDef' fresh source.
    let copyIncPart fExpr resF =
          case sourceCVarStripDrops fExpr of
            Just src
              | src `Set.notMember` ctx.valDefs ->
                  "  call void @__inc_ref(ptr " <> resF <> ")\n"
            _ -> ""
    copyFieldStores <- forM zippedFields $ \(fExpr, resF, idx) -> do
      slotTmp <- freshTemp
      pure
        ( copyIncPart fExpr resF
            <> "  "
            <> slotTmp
            <> " = getelementptr ptr, ptr "
            <> copyTmp
            <> ", i32 "
            <> show idx
            <> "\n"
            <> "  store ptr "
            <> resF
            <> ", ptr "
            <> slotTmp
            <> "\n"
        )
    let copyDecN = "  call void @__free_recursive(ptr " <> nPtr <> ")\n"
        copyBlock =
          copyLbl
            <> ":\n"
            <> copyAlloc
            <> copyTag
            <> T.concat copyFieldStores
            <> copyDecN
            <> "  br label %"
            <> joinLbl
            <> "\n"
    -- Join — phi the result pointer from both paths.
    phiTmp <- freshTemp
    let joinBlock =
          joinLbl
            <> ":\n"
            <> "  "
            <> phiTmp
            <> " = phi ptr [ "
            <> nPtr
            <> ", %"
            <> reuseLbl
            <> " ], [ "
            <> copyTmp
            <> ", %"
            <> copyLbl
            <> " ]\n"
    pure
      ( fieldInstrsCat
          <> rcCheck
          <> inPlaceBlock
          <> copyBlock
          <> joinBlock,
        phiTmp
      )
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
      let armElided = case scrut of
            CVar n -> elidableArmBinders n vars body
            _ -> Set.empty
      -- Extract bound variables from container fields. Each
      -- ptr-binder is inc'd on extract so the local binding takes
      -- its own reference (the scrut cell's slot still holds a ref
      -- too). The matching dec fires at arm end via the 'CDrop'
      -- that 'Awsum.Lifetime' wraps around every arm.
      varInstrs <- forM (zip vars [1 :: Int ..]) $ \(v, idx) -> do
        slotT <- freshTemp
        valT <- freshTemp
        let incPart =
              if v `Set.member` armElided
                then ""
                else "  call void @__inc_ref(ptr " <> valT <> ")\n"
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
              <> "\n"
              <> incPart,
            (v, valT)
          )
      let varInstrCode = T.concat (map fst varInstrs)
          varBindings = map snd varInstrs
      -- Emit body with bound variables in context. Linear-scrutinee
      -- elision: if the scrut is 'CVar n', record this arm's @vars@
      -- under @n@ so a nested 'CReuse n t fs' can detect self-move
      -- slots.
      let ctx' =
            let withLocals = foldl' (\c (v, tmp) -> c {locals = Map.insert v tmp (locals c)}) ctx varBindings
                withElided = withLocals {elidedBinders = elidedBinders withLocals `Set.union` armElided}
             in case scrut of
                  CVar n -> withElided {armPatternByScrut = Map.insert n vars (armPatternByScrut withElided)}
                  _ -> withElided
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
        -- If the scrut's tail isn't a 'CVar' it's a fresh
        -- allocation (CCon/CCall/…) whose @+1@ refcount has no
        -- other owner once the case is over — dec it after the
        -- phi so the cell is reclaimed. Case-binders inc'd at
        -- extract retain their own refs to the cell's slot
        -- values, so the cascade-free of those slots only drops
        -- back the slot-via-cell ref and the binders survive.
        scrutDec = case borrowedSource ctx scrut of
          Just _ -> ""
          Nothing -> "  call void @__free_recursive(ptr " <> resS <> ")\n"
    pure
      ( instrS <> tagInstr <> switchInstr <> armBlocks <> defBlock <> joinBlock <> scrutDec,
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
            (instrX, resX) <- emitArgWithInc ctx x
            tmp <- freshTemp
            pure
              ( instrX <> "  " <> tmp <> " = call ptr @__print(ptr " <> resX <> ")\n",
                tmp
              )
          _ -> error "__print: arity mismatch"
      -- Zero-arg primitive driving the prelude's `runIO` 'IOGetArgs'
      -- arm: re-reads argv[1] (cached at entry in @.cli_arg) and wraps
      -- it in 'Either (StringTooLong | UnpairedUtf16Surrogate) String'
      -- via '__entryArgEither'. Per the no-memoisation decision each
      -- call yields a fresh cell — argv is invariant, so repeat calls
      -- are deterministically equal.
      CBuiltIn "internalGetArgs" ->
        case xs of
          [] -> do
            tmp <- freshTemp
            pure ("  " <> tmp <> " = call ptr @__getArgs()\n", tmp)
          _ -> error "__getArgs: arity mismatch"
      -- Zero-arg primitive driving the prelude's 'runIO' 'IOStdinReadAll'
      -- arm: consumes fd 0 to EOF and wraps the decoded contents in
      -- 'Either (StringTooLong | UnpairedUtf16Surrogate) String' via
      -- '__stdinReadAll'. Per the POSIX-honest no-memoisation decision,
      -- a second call after EOF reads zero bytes and decodes to
      -- @Right ""@.
      CBuiltIn "internalStdinReadAllAsUtf16" ->
        case xs of
          [] -> do
            tmp <- freshTemp
            pure ("  " <> tmp <> " = call ptr @__stdinReadAll()\n", tmp)
          _ -> error "__stdinReadAll: arity mismatch"
      CBuiltIn name
        | name == "showInt32" || name == "showUInt8" || name == "showUInt32" ->
            case xs of
              [x] -> do
                (instrX, resX) <- emitArgWithInc ctx x
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
            (instrX, resX) <- emitArgWithInc ctx x
            tmp <- freshTemp
            pure
              ( instrX <> "  " <> tmp <> " = call ptr @__predInt32(ptr " <> resX <> ")\n",
                tmp
              )
          _ -> error "BuiltIn.predInt32: arity mismatch"
      CBuiltIn "predUInt8" ->
        case xs of
          [x] -> do
            (instrX, resX) <- emitArgWithInc ctx x
            tmp <- freshTemp
            pure
              ( instrX <> "  " <> tmp <> " = call ptr @__predUInt8(ptr " <> resX <> ")\n",
                tmp
              )
          _ -> error "BuiltIn.predUInt8: arity mismatch"
      CBuiltIn "predUInt32" ->
        case xs of
          [x] -> do
            (instrX, resX) <- emitArgWithInc ctx x
            tmp <- freshTemp
            pure
              ( instrX <> "  " <> tmp <> " = call ptr @__predUInt32(ptr " <> resX <> ")\n",
                tmp
              )
          _ -> error "BuiltIn.predUInt32: arity mismatch"
      CBuiltIn "succInt32" ->
        case xs of
          [x] -> do
            (instrX, resX) <- emitArgWithInc ctx x
            tmp <- freshTemp
            pure
              ( instrX <> "  " <> tmp <> " = call ptr @__succInt32(ptr " <> resX <> ")\n",
                tmp
              )
          _ -> error "BuiltIn.succInt32: arity mismatch"
      CBuiltIn "succUInt8" ->
        case xs of
          [x] -> do
            (instrX, resX) <- emitArgWithInc ctx x
            tmp <- freshTemp
            pure
              ( instrX <> "  " <> tmp <> " = call ptr @__succUInt8(ptr " <> resX <> ")\n",
                tmp
              )
          _ -> error "BuiltIn.succUInt8: arity mismatch"
      CBuiltIn "succUInt32" ->
        case xs of
          [x] -> do
            (instrX, resX) <- emitArgWithInc ctx x
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
                (instrA, resA) <- emitArgWithInc ctx a
                (instrB, resB) <- emitArgWithInc ctx b
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
                (instrA, resA) <- emitArgWithInc ctx a
                (instrB, resB) <- emitArgWithInc ctx b
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
            (instrX, resX) <- emitArgWithInc ctx x
            tmp <- freshTemp
            pure
              ( instrX <> "  " <> tmp <> " = call ptr @__negInt32(ptr " <> resX <> ")\n",
                tmp
              )
          _ -> error "BuiltIn.negInt32: arity mismatch"
      CBuiltIn "concatString" ->
        case xs of
          [a, b] -> do
            (instrA, resA) <- emitArgWithInc ctx a
            (instrB, resB) <- emitArgWithInc ctx b
            tmp <- freshTemp
            pure
              ( instrA <> instrB <> "  " <> tmp <> " = call ptr @__concat(ptr " <> resA <> ", ptr " <> resB <> ")\n",
                tmp
              )
          _ -> error "BuiltIn.concatString: arity mismatch"
      CBuiltIn "splitOnFirst" ->
        case xs of
          [a, b] -> do
            (instrA, resA) <- emitArgWithInc ctx a
            (instrB, resB) <- emitArgWithInc ctx b
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
                (instrA, resA) <- emitArgWithInc ctx a
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
        | name == "lengthCodePoints" || name == "lengthUtf16CodeUnits" || name == "lengthUtf8Bytes" ->
            case xs of
              [a] -> do
                (instrA, resA) <- emitArgWithInc ctx a
                tmp <- freshTemp
                let fn :: Text
                    fn = case name of
                      "lengthCodePoints" -> "@__lengthCodePoints"
                      "lengthUtf16CodeUnits" -> "@__lengthUtf16CodeUnits"
                      _ -> "@__lengthUtf8Bytes"
                pure
                  ( instrA <> "  " <> tmp <> " = call ptr " <> fn <> "(ptr " <> resA <> ")\n",
                    tmp
                  )
              _ -> error ("BuiltIn." <> name <> ": arity mismatch")
      CBuiltIn n ->
        error ("LLVM codegen: unknown builtin '" <> n <> "' reached CCall (typecheck should have rejected it)")
      _ -> do
        (instrF, resF) <- emitExpr ctx f
        argsResults <- traverse (emitArgWithInc ctx) xs
        let allInstrs = instrF <> mconcat (map fst argsResults)
            argList = T.intercalate ", " (map (\(_, r) -> "ptr " <> r) argsResults)
        tmp <- freshTemp
        pure
          ( allInstrs <> "  " <> tmp <> " = call ptr " <> resF <> "(" <> argList <> ")\n",
            tmp
          )
  CLoop _ -> error "LLVM codegen: CLoop in non-tail position (pipeline bug — should only appear at function-body-tail)"
  CContinue _ -> error "LLVM codegen: CContinue in non-tail position (pipeline bug — should only appear inside a CLoop)"

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
