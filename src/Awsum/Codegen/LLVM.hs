-- | LLVM IR code generator for Awsum 'Core'.
--
-- Design goals:
--   * Emit textual LLVM IR (.ll) that can be compiled with @clang@.
--   * Keep a tiny C-based runtime: @malloc@/@free@/@write@ plus a
--     refcount-aware allocator layer ('__alloc_shaped',
--     '__inc_ref', '__free_recursive').
--   * Uphold cross-target equivalence — identical stdout to every other
--     backend.
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

import Awsum.Codegen.LLVM.Syntax
import Awsum.Core
import Awsum.HM (rowTag)
import Awsum.Lifetime (elidableArmBinders)
import Awsum.Syntax (Name, Type' (..), noSpan)
import Data.ByteString qualified as BS
import Data.Char qualified as Char
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Numeric (showHex)
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
--   Linux share the POSIX variant — the footer is identical for
--   both. The link-host axis (which linker flags @clang@ needs) is
--   tracked separately by 'LLVMLinkHost' because there macOS and Linux
--   diverge. The CLI derives this from 'System.Info.os' once via
--   'llvmHostFromSystem'; the snapshot test framework iterates all
--   values, covering every host's IR.
data LLVMHost = LLVMPosix | LLVMWindows
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | Every supported host, used by snapshot tests to assert one IR file
--   per host, regardless of which host is doing the run.
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
      ctx = EmitCtx {params = Set.empty, valDefs = valDefNames, stringPool = pool, locals = Map.empty, loopCtx = Nothing, armPatternByScrut = Map.empty, elidedBinders = Set.empty, joinTargets = Map.empty}
      userCode = T.intercalate "\n\n" (map renderFunc (evalState (traverse (emitDecl ctx) decls) 0))
      builtIns = usedBuiltIns prog
   in T.intercalate
        "\n"
        [ header host builtIns,
          emitStringConstants pool,
          runtime ptags builtIns,
          userCode,
          footer host builtIns
        ]

-- ════════════════════════════════════════════════════════════════════════════
-- Context
-- ════════════════════════════════════════════════════════════════════════════

data EmitCtx = EmitCtx
  { params :: Set Text,
    valDefs :: Set Text,
    stringPool :: StringPool,
    locals :: Map Text LVal, -- case- or let-bound variable name → bound value (SSA temp for case extracts; any 'LVal' for a 'CLet', e.g. a string-constant gep)

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
    elidedBinders :: Set Text,
    -- | In-scope join points: join name → branch target. Entered by the
    -- 'CJoin' emitters for the extent of the inner expression; a 'CJump'
    -- resolves its label, parameter slots, and — in the tail walks — the
    -- 'pending'\/fresh-scrutinee baselines recorded at the 'CJoin', so the
    -- jump releases exactly what accumulated since the node.
    joinTargets :: Map Text JoinTarget
  }

-- | Branch target of an in-scope 'CJoin'. The parameters live in
-- prologue-allocated slots ('joinSlotName'; mem2reg turns the
-- store\/load pairs into phis), so a jump needs no knowledge of its
-- own basic-block label.
data JoinTarget = JoinTarget
  { jtLabel :: Text,
    jtParams :: [Text],
    -- | Lengths of the tail walks' @pending@ / @freshScruts@ stacks at
    -- the 'CJoin' node. Binders and scrutinees accumulated past these
    -- baselines belong to the jumping path and are released at the jump
    -- (mirroring 'CContinue'); whatever was already pending at the node
    -- outlives it and is released at the join body's own terminals.
    jtPendingBase :: Int,
    jtScrutBase :: Int
  }

-- | The prologue-allocated slot carrying a join parameter's value across
-- the jump. Join parameter names are globally unique (one mint counter in
-- 'Awsum.Simplify'), so the name alone identifies the slot. Allocated in
-- the function prologue — an alloca at the 'CJoin' site would grow the
-- stack per iteration when the join sits inside a 'CLoop' body.
joinSlotName :: Name -> Text
joinSlotName p = "%" <> mangle p <> ".jslot"

-- | Every 'CJoin' parameter anywhere in a declaration body — the
-- prologue allocates one slot per entry.
joinParamsIn :: CExpr -> [Name]
joinParamsIn = go
  where
    go = \case
      CJoin _ ps body inner -> ps <> go body <> go inner
      CJump _ args -> concatMap go args
      CCall f xs -> go f <> concatMap go xs
      CCon _ fs -> concatMap go fs
      CRow _ v -> go v
      CCase s alts -> go s <> concatMap (\(_, _, b) -> go b) alts
      CRowCase s alts -> go s <> concatMap (\(_, _, b) -> go b) alts
      CLoop b -> go b
      CContinue xs -> concatMap go xs
      CLet _ rhs b -> go rhs <> go b
      CDrop _ _ b -> go b
      CReuse _ _ _ fs -> concatMap go fs
      CVar _ -> []
      CProj _ _ -> []
      CString _ -> []
      CIntLit _ _ -> []
      CBuiltIn _ -> []

-- | Strip the 'CDrop' wrappers 'Awsum.Lifetime' places around a jumping
-- arm body: the binders are released at the jump (after the argument
-- incs), and the bare 'CJump' underneath is what the arm dispatchers
-- detect.
peelDrops :: CExpr -> ([Name], CExpr)
peelDrops = \case
  CDrop _ n b -> first (n :) (peelDrops b)
  e -> ([], e)

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
  CLet _ rhs body -> stringsInExpr rhs <> stringsInExpr body
  CProj _ _ -> []
  CLoop b -> stringsInExpr b
  CContinue xs -> concatMap stringsInExpr xs
  CDrop _ _ body -> stringsInExpr body
  CReuse _ _ _ fs -> concatMap stringsInExpr fs
  CJoin _ _ body inner -> stringsInExpr body <> stringsInExpr inner
  CJump _ args -> concatMap stringsInExpr args

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
      T.intercalate "\n" (map (renderGlobal . strGlobal) (sortWith snd $ Map.toList pool)) <> "\n"
  where
    -- The literal's storage struct: @{flag, refcount, shape, byte_count,
    -- utf16_units, payload}@ — the first three fields are the 12-byte
    -- header 'emitStringConstants' documents above. A zero-length string
    -- carries a @[0 x i8] zeroinitializer@ payload ('GZero'); otherwise the
    -- escaped UTF-8 bytes ('GBytes').
    strGlobal (s, i) =
      let byteCount = BS.length (encodeUtf8 s)
          utf16Count = T.foldl' (\n c -> n + if Char.ord c > 0xFFFF then 2 else 1) (0 :: Int) s
          payloadTy = TArr byteCount I8
          payloadInit
            | byteCount == 0 = GZero
            | otherwise = GBytes (llvmEscapeString s)
       in LGlobal
            { lglName = "@.str." <> show i,
              lglLinkage = "private unnamed_addr",
              lglKind = "constant",
              lglType = TStruct [I32, I32, I32, I32, I32, payloadTy],
              lglInit =
                GStruct
                  [ (I32, GInt 0),
                    (I32, GInt 0),
                    (I32, GInt 0),
                    (I32, GInt (toInteger byteCount)),
                    (I32, GInt (toInteger utf16Count)),
                    (payloadTy, payloadInit)
                  ]
            }

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
      -- @\XX@: two uppercase hex digits, zero-padded (byte 0x0A -> @\0A@).
      | otherwise = "\\" <> T.toUpper (T.justifyRight 2 '0' (toText (showHex b "")))

-- ════════════════════════════════════════════════════════════════════════════
-- Header: external declarations + format strings
-- ════════════════════════════════════════════════════════════════════════════

header :: LLVMHost -> Set Name -> Text
header host builtIns =
  unlines
    $ [ "; External C declarations",
        decl Ptr "malloc" [I64],
        decl Ptr "realloc" [Ptr, I64],
        decl Void "free" [Ptr],
        decl Ptr "memcpy" [Ptr, Ptr, I64],
        -- 'write(2)' is used by '__print' to stream payload bytes to fd 1
        -- regardless of NUL bytes inside (which 'printf(\"%s\", …)' /
        -- 'printf(\"%.*s\", n, …)' would silently truncate at). On macOS
        -- and Linux libc the symbol is 'write'; mingw libc also exposes
        -- it. MSVC's CRT exposes '_write' instead — that variant is not
        -- yet wired through and is tracked as a Windows-host follow-up.
        decl I64 "write" [I32, Ptr, I64]
      ]
    <> [ -- 'strlen' is used only by 'rtGetArgs', at the boundary between
       -- OS argv[i] (NUL-terminated C-strings from libc) and our internal
       -- length-prefixed layout. Gated so programs without
       -- 'IO.Args.getArgs' don't pin libc 'strlen'.
       decl I64 "strlen" [Ptr]
       | Set.member "internalGetArgs" builtIns
       ]
    <> [ -- 'snprintf' formats Int32 / UInt8 / UInt32 into decimal in
       -- '__showInt32' / '__showUInt8' / '__showUInt32'. Gated so programs
       -- that show no integers don't pin it.
       renderDecl (LDecl I32 "snprintf" [Ptr, I64, Ptr] True)
       | Set.member "showInt32" builtIns
           || Set.member "showUInt8" builtIns
           || Set.member "showUInt32" builtIns
           || Set.member "byteToHexStringNoPrefix" builtIns
       ]
    <> [ -- 'read(2)' is used by '__readStdin' (shared by both stdin
       -- primitives) to consume fd 0 to EOF regardless of NUL bytes in
       -- the input. macOS / Linux / mingw libc all expose it as 'read';
       -- MSVC's CRT exposes '_read' instead — same Windows-host
       -- follow-up as 'write'. Gated so programs without a stdin reader
       -- don't pin libc 'read'.
       decl I64 "read" [I32, Ptr, I64]
       | Set.member "internalStdinReadAllString" builtIns
           || Set.member "internalStdinReadAllBytes" builtIns
       ]
    <> [ -- 'memcmp' is used only by '__eqString'. Gated so programs that
       -- don't reference 'eqString' don't pin libc 'memcmp'.
       decl I32 "memcmp" [Ptr, Ptr, I64]
       | Set.member "eqString" builtIns
       ]
    <> [ decl (TStruct [I32, I1]) "llvm.sadd.with.overflow.i32" [I32, I32]
       | Set.member "addInt32" builtIns
       ]
    <> [ decl (TStruct [I32, I1]) "llvm.ssub.with.overflow.i32" [I32, I32]
       | Set.member "subInt32" builtIns
       ]
    <> [ decl (TStruct [I32, I1]) "llvm.smul.with.overflow.i32" [I32, I32]
       | Set.member "mulInt32" builtIns
       ]
    -- 'strstr' / 'memcpy' from the splitOnFirst path are no longer
    -- needed: 'memcpy' is now in the always-on header (used by every
    -- string-allocating helper), and 'rtSplitOnFirst' walks the
    -- length-prefixed payload via i32 loads + index arithmetic instead
    -- of libc's null-aware 'strstr'.
    <> [""]
    -- '@.fmt_i32' / '@.fmt_u8' are the decimal format strings for the
    -- integer 'show' helpers, gated next to their sole readers
    -- ('__showInt32' / '__showUInt8' / '__showUInt32') so a program that
    -- shows no integers carries neither.
    <> [ constGlob "@.fmt_i32" (TArr 3 I8) (GBytes "%d\\00")
       | Set.member "showInt32" builtIns
       ]
    <> [ constGlob "@.fmt_u8" (TArr 3 I8) (GBytes "%u\\00")
       | Set.member "showUInt8" builtIns || Set.member "showUInt32" builtIns
       ]
    <> [ constGlob "@.fmt_hex" (TArr 5 I8) (GBytes "%02x\\00")
       | Set.member "byteToHexStringNoPrefix" builtIns
       ]
    -- '@.empty' is the language-fixed empty string in length-prefixed form
    -- (4-byte 'i32 flag = 0' literal prefix; the user pointer is
    -- '@.empty + 12'). Its only reader is the Windows entry's argv[0] slot
    -- in 'footerWindows', which itself only runs when the program reads
    -- argv — so it is gated on Windows ∧ 'internalGetArgs'.
    <> [ constGlob "@.empty" (TStruct [I32, I32, I32, I32, I32]) (GStruct (replicate 5 (I32, GInt 0)))
       | host == LLVMWindows && Set.member "internalGetArgs" builtIns
       ]
    -- '@.cli_argc' / '@.cli_argv' cache the entry-point's @argc@ and
    -- @argv@ (an array of NUL-terminated UTF-8 C-strings) so
    -- 'BuiltIn.internalGetArgs' can walk every element from the prelude's
    -- 'runIO' arm without threading @argc@/@argv@ through the IO tree.
    -- Read only by '__getArgs' and stored only by the entry footer, both
    -- gated on 'internalGetArgs' — so the globals are gated to match.
    <> ( if Set.member "internalGetArgs" builtIns
           then
             [ mutGlob "@.cli_argc" I64 (GInt 0),
               mutGlob "@.cli_argv" Ptr GNull
             ]
           else []
       )
    <> [ -- '__alloc' wraps libc 'malloc' with a
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
         -- shifts. 'CDrop' lowers to '__free_recursive' in emitExpr /
         -- emitTail so the refcount decrements and the shape-driven
         -- cascade fires; the cascade releases each dead block through
         -- libc 'free' directly. (The separate flag-guarded single-block
         -- '@__free' wrapper is emitted only for the argv path — see its
         -- gated definition below.)
         "",
         renderFunc allocFn
       ]
    -- '@__free' is the per-block libc-'free' wrapper. Its only caller is
    -- 'rtGetArgs' (releasing the 16-byte Either box per decoded argv
    -- element); '__free_recursive''s cascade ends in libc 'free' directly,
    -- not here. Gated on 'internalGetArgs'.
    <> ( if Set.member "internalGetArgs" builtIns
           then ["", renderFunc freeFn]
           else []
       )
    <> [ "",
         -- '@__inc_ref' increments the refcount of the cell
         -- at @user_ptr@. Literals (flag == 0) are unaffected — their
         -- refcount field stays at 0 and they never get freed.
         renderFunc incRefFn,
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
         mutGlob "@__free_worklist" Ptr GNull,
         mutGlob "@__free_worklist_top" I64 (GInt 0),
         mutGlob "@__free_worklist_cap" I64 (GInt 0),
         "",
         -- Push @%p@ onto '@__free_worklist'. Grows the buffer
         -- (initial 16 entries, doubles thereafter) when @top ==
         -- cap@; otherwise reuses the existing allocation. Each
         -- entry is a pointer (8 bytes on the only platform LLVM
         -- targets here).
         renderFunc worklistPushFn,
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
         renderFunc freeRecursiveFn
       ]
  where
    -- Render an external declaration / module global inline in the
    -- header's layout. The typed 'LDecl' / 'LGlobal' carry the shape;
    -- the @;@-comments and blank lines around them stay as text glue
    -- (the same split the trio's section assemblers use).
    decl ret nm ps = renderDecl (LDecl ret nm ps False)
    -- A @private unnamed_addr constant@ (format strings, '@.empty').
    constGlob nm ty ini = renderGlobal (LGlobal nm "private unnamed_addr" "constant" ty ini)
    -- An @internal global@ (mutable: argv cache, free worklist).
    mutGlob nm ty ini = renderGlobal (LGlobal nm "internal" "global" ty ini)
    -- '__alloc' wraps libc 'malloc' with the 12-byte header
    -- (flag | refcount | shape); user pointer is 12 bytes in.
    allocFn =
      LFunc
        { lfLinkage = "internal",
          lfRetType = Ptr,
          lfName = "__alloc",
          lfParams = [(I64, "%sz"), (I32, "%shape")],
          lfBody =
            [ IBin "%total" LAdd I64 (VReg "%sz") (VInt 12),
              ICall (Just "%raw") Ptr Nothing "@malloc" [(I64, VReg "%total")],
              IStore I32 (VInt 1) (VReg "%raw"),
              IGep "%rc_p" I8 (VReg "%raw") [(I64, VInt 4)],
              IStore I32 (VInt 1) (VReg "%rc_p"),
              IGep "%shape_p" I8 (VReg "%raw") [(I64, VInt 8)],
              IStore I32 (VReg "%shape") (VReg "%shape_p"),
              IGep "%user" I8 (VReg "%raw") [(I64, VInt 12)],
              IRet (Just (Ptr, VReg "%user"))
            ]
        }
    -- '__free' is the per-block libc-free wrapper (argv path only).
    freeFn =
      LFunc
        { lfLinkage = "internal",
          lfRetType = Void,
          lfName = "__free",
          lfParams = [(Ptr, "%p")],
          lfBody =
            [ IGep "%hdr_ptr" I8 (VReg "%p") [(I64, VInt (-12))],
              ILoad "%flag" I32 (VReg "%hdr_ptr"),
              IICmp "%is_heap" IEq I32 (VReg "%flag") (VInt 1),
              IBrCond (VReg "%is_heap") "do_free" "skip",
              ILabel "do_free",
              ICall Nothing Void Nothing "@free" [(Ptr, VReg "%hdr_ptr")],
              IBr "skip",
              ILabel "skip",
              IRet Nothing
            ]
        }
    -- '__inc_ref' bumps the refcount (literals, flag 0, are untouched).
    incRefFn =
      LFunc
        { lfLinkage = "internal",
          lfRetType = Void,
          lfName = "__inc_ref",
          lfParams = [(Ptr, "%p")],
          lfBody =
            [ IGep "%hdr_ptr" I8 (VReg "%p") [(I64, VInt (-12))],
              ILoad "%flag" I32 (VReg "%hdr_ptr"),
              IICmp "%is_heap" IEq I32 (VReg "%flag") (VInt 1),
              IBrCond (VReg "%is_heap") "do_inc" "skip_inc",
              ILabel "do_inc",
              IGep "%rc_p" I8 (VReg "%p") [(I64, VInt (-8))],
              ILoad "%rc_old" I32 (VReg "%rc_p"),
              IBin "%rc_new" LAdd I32 (VReg "%rc_old") (VInt 1),
              IStore I32 (VReg "%rc_new") (VReg "%rc_p"),
              IBr "skip_inc",
              ILabel "skip_inc",
              IRet Nothing
            ]
        }
    -- Push a child pointer onto the heap-backed free worklist (grows by
    -- doubling), keeping '__free_recursive''s C-stack footprint O(1).
    worklistPushFn =
      LFunc
        { lfLinkage = "internal",
          lfRetType = Void,
          lfName = "__free_worklist_push",
          lfParams = [(Ptr, "%p")],
          lfBody =
            [ ILabel "entry",
              ILoad "%top" I64 (VGlob "@__free_worklist_top"),
              ILoad "%cap" I64 (VGlob "@__free_worklist_cap"),
              IICmp "%is_full" IEq I64 (VReg "%top") (VReg "%cap"),
              IBrCond (VReg "%is_full") "grow" "store",
              ILabel "grow",
              IICmp "%cap_zero" IEq I64 (VReg "%cap") (VInt 0),
              IBin "%doubled" LShl I64 (VReg "%cap") (VInt 1),
              ISelect "%new_cap" (VReg "%cap_zero") I64 (VInt 16) (VReg "%doubled"),
              IBin "%bytes" LMul I64 (VReg "%new_cap") (VInt 8),
              ILoad "%old_buf" Ptr (VGlob "@__free_worklist"),
              ICall (Just "%new_buf") Ptr Nothing "@realloc" [(Ptr, VReg "%old_buf"), (I64, VReg "%bytes")],
              IStore Ptr (VReg "%new_buf") (VGlob "@__free_worklist"),
              IStore I64 (VReg "%new_cap") (VGlob "@__free_worklist_cap"),
              IBr "store",
              ILabel "store",
              ILoad "%buf" Ptr (VGlob "@__free_worklist"),
              IGep "%slot" Ptr (VReg "%buf") [(I64, VReg "%top")],
              IStore Ptr (VReg "%p") (VReg "%slot"),
              IBin "%top_new" LAdd I64 (VReg "%top") (VInt 1),
              IStore I64 (VReg "%top_new") (VGlob "@__free_worklist_top"),
              IRet Nothing
            ]
        }
    -- '__free_recursive' decrements the refcount and, at zero, cascades
    -- through the cell's ptr fields (last slot consumed iteratively, the
    -- rest pushed onto the worklist) — O(1) system stack regardless of shape.
    freeRecursiveFn =
      LFunc
        { lfLinkage = "internal",
          lfRetType = Void,
          lfName = "__free_recursive",
          lfParams = [(Ptr, "%p_arg")],
          lfBody =
            [ ILabel "entry",
              IBr "top",
              ILabel "top",
              IPhi "%p" Ptr [(VReg "%p_arg", "entry"), (VReg "%p_after", "continue")],
              IGep "%hdr_ptr" I8 (VReg "%p") [(I64, VInt (-12))],
              ILoad "%flag" I32 (VReg "%hdr_ptr"),
              IICmp "%is_heap" IEq I32 (VReg "%flag") (VInt 1),
              IBrCond (VReg "%is_heap") "do_dec" "try_pop",
              ILabel "do_dec",
              IGep "%rc_p" I8 (VReg "%p") [(I64, VInt (-8))],
              ILoad "%rc_old" I32 (VReg "%rc_p"),
              IBin "%rc_new" LSub I32 (VReg "%rc_old") (VInt 1),
              IStore I32 (VReg "%rc_new") (VReg "%rc_p"),
              IICmp "%is_zero" IEq I32 (VReg "%rc_new") (VInt 0),
              IBrCond (VReg "%is_zero") "do_cascade" "try_pop",
              ILabel "do_cascade",
              IGep "%shape_p" I8 (VReg "%p") [(I64, VInt (-4))],
              ILoad "%shape" I32 (VReg "%shape_p"),
              IICmp "%shape_zero" IEq I32 (VReg "%shape") (VInt 0),
              IBrCond (VReg "%shape_zero") "free_and_pop" "loop_check",
              ILabel "loop_check",
              IPhi "%i" I32 [(VInt 1, "do_cascade"), (VReg "%i_next", "loop_body")],
              IICmp "%cmp" IUlt I32 (VReg "%i") (VReg "%shape"),
              IBrCond (VReg "%cmp") "loop_body" "tail_jump_prep",
              ILabel "loop_body",
              IConv "%i64" Zext I32 (VReg "%i") I64,
              IGep "%slot_p" Ptr (VReg "%p") [(I64, VReg "%i64")],
              ILoad "%child" Ptr (VReg "%slot_p"),
              ICall Nothing Void Nothing "@__free_worklist_push" [(Ptr, VReg "%child")],
              IBin "%i_next" LAdd I32 (VReg "%i") (VInt 1),
              IBr "loop_check",
              ILabel "tail_jump_prep",
              IConv "%shape64" Zext I32 (VReg "%shape") I64,
              IGep "%last_slot_p" Ptr (VReg "%p") [(I64, VReg "%shape64")],
              ILoad "%p_next_tail" Ptr (VReg "%last_slot_p"),
              ICall Nothing Void Nothing "@free" [(Ptr, VReg "%hdr_ptr")],
              IBr "continue",
              ILabel "free_and_pop",
              ICall Nothing Void Nothing "@free" [(Ptr, VReg "%hdr_ptr")],
              IBr "try_pop",
              ILabel "try_pop",
              ILoad "%top_old" I64 (VGlob "@__free_worklist_top"),
              IICmp "%is_empty" IEq I64 (VReg "%top_old") (VInt 0),
              IBrCond (VReg "%is_empty") "done" "do_pop",
              ILabel "do_pop",
              IBin "%top_new" LSub I64 (VReg "%top_old") (VInt 1),
              IStore I64 (VReg "%top_new") (VGlob "@__free_worklist_top"),
              ILoad "%wl_buf" Ptr (VGlob "@__free_worklist"),
              IGep "%wl_slot" Ptr (VReg "%wl_buf") [(I64, VReg "%top_new")],
              ILoad "%p_popped" Ptr (VReg "%wl_slot"),
              IBr "continue",
              ILabel "continue",
              IPhi "%p_after" Ptr [(VReg "%p_next_tail", "tail_jump_prep"), (VReg "%p_popped", "do_pop")],
              IBr "top",
              ILabel "done",
              IRet Nothing
            ]
        }

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
    -- Typed-IR operand builders: 'tagOf' is the FNV-1a row tag of a label;
    -- 'ptI' is a globally-unique constructor tag from 'PreludeTags'.
    tagOf :: Text -> LVal
    tagOf lbl = VInt (toInteger (rowTag (TyCon noSpan lbl)))
    ptI :: (PreludeTags -> Int) -> LVal
    ptI f = VInt (toInteger (f ptags))
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
        if Set.member "byteToHexStringNoPrefix" builtIns then rtByteToHex else "",
        if Set.member "predInt32" builtIns then rtPredInt32 else "",
        if Set.member "predUInt8" builtIns then rtPredUInt8 else "",
        if Set.member "succInt32" builtIns then rtSuccInt32 else "",
        if Set.member "succUInt8" builtIns then rtSuccUInt8 else "",
        if Set.member "eqInt32" builtIns then rtEqInt32 else "",
        if Set.member "eqUInt8" builtIns then rtEqUInt8 else "",
        if Set.member "eqString" builtIns then rtEqString else "",
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
        -- '__entryArgEither' validates host-decoded argv strings only;
        -- stdin has its own strict byte decoder. Gated on the argv
        -- built-in so an argv-free program pays nothing for it.
        if Set.member "internalGetArgs" builtIns then rtEntryArgEither else "",
        if Set.member "internalGetArgs" builtIns then rtGetArgs else "",
        -- '__readStdin' is the shared fd-0-to-EOF reader; both stdin
        -- primitives call it. '__stdinDecodeStrict' is the strict UTF-8
        -- decoder used only by the string reader.
        if Set.member "internalStdinReadAllString" builtIns || Set.member "internalStdinReadAllBytes" builtIns then rtReadStdin else "",
        if Set.member "internalStdinReadAllString" builtIns then rtStdinDecodeStrict else "",
        if Set.member "internalStdinReadAllString" builtIns then rtStdinReadAll else "",
        if Set.member "internalStdinReadAllBytes" builtIns then rtStdinReadAllBytes else ""
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
    -- concat: cap-check on the UTF-16 sum → Left StringTooLong, else alloc
    -- a length-prefixed buffer and memcpy both payloads → Right.
    rtConcat =
      (<> "\n")
        $ renderFunc
          LFunc
            { lfLinkage = "internal",
              lfRetType = Ptr,
              lfName = "__concat",
              lfParams = [(Ptr, "%a"), (Ptr, "%b")],
              lfBody =
                [ ILoad "%ba" I32 (VReg "%a"),
                  IGep "%ua_p" I8 (VReg "%a") [(I64, VInt 4)],
                  ILoad "%ua" I32 (VReg "%ua_p"),
                  ILoad "%bb" I32 (VReg "%b"),
                  IGep "%ub_p" I8 (VReg "%b") [(I64, VInt 4)],
                  ILoad "%ub" I32 (VReg "%ub_p"),
                  IConv "%ua64" Zext I32 (VReg "%ua") I64,
                  IConv "%ub64" Zext I32 (VReg "%ub") I64,
                  IBin "%usum64" LAdd I64 (VReg "%ua64") (VReg "%ub64"),
                  -- maxStringLengthUtf16CodeUnits = 134217728 (2^27); keep in
                  -- sync with stdlib/Prelude.aww.
                  IICmp "%over" IUgt I64 (VReg "%usum64") (VInt 134217728),
                  IBrCond (VReg "%over") "too_long" "ok",
                  ILabel "too_long",
                  ICall (Just "%stl") Ptr Nothing "@__alloc" [(I64, VInt 8), (I32, VInt 0)],
                  IConv "%stl_tag" IntToPtr I64 (ptI ptStringTooLong) Ptr,
                  IStore Ptr (VReg "%stl_tag") (VReg "%stl"),
                  ICall (Just "%left") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%left_tag" IntToPtr I64 (ptI ptLeft) Ptr,
                  IStore Ptr (VReg "%left_tag") (VReg "%left"),
                  IGep "%left_f" Ptr (VReg "%left") [(I32, VInt 1)],
                  IStore Ptr (VReg "%stl") (VReg "%left_f"),
                  IBr "join",
                  ILabel "ok",
                  IConv "%ba64" Zext I32 (VReg "%ba") I64,
                  IConv "%bb64" Zext I32 (VReg "%bb") I64,
                  IBin "%bsum64" LAdd I64 (VReg "%ba64") (VReg "%bb64"),
                  IBin "%alloc64" LAdd I64 (VReg "%bsum64") (VInt 8),
                  ICall (Just "%buf") Ptr Nothing "@__alloc" [(I64, VReg "%alloc64"), (I32, VInt 0)],
                  IConv "%bsum32" Trunc I64 (VReg "%bsum64") I32,
                  IStore I32 (VReg "%bsum32") (VReg "%buf"),
                  IConv "%usum32" Trunc I64 (VReg "%usum64") I32,
                  IGep "%buf_u16p" I8 (VReg "%buf") [(I64, VInt 4)],
                  IStore I32 (VReg "%usum32") (VReg "%buf_u16p"),
                  IGep "%buf_payload" I8 (VReg "%buf") [(I64, VInt 8)],
                  IGep "%a_payload" I8 (VReg "%a") [(I64, VInt 8)],
                  ICall Nothing Ptr Nothing "@memcpy" [(Ptr, VReg "%buf_payload"), (Ptr, VReg "%a_payload"), (I64, VReg "%ba64")],
                  IGep "%buf_payload_b" I8 (VReg "%buf_payload") [(I64, VReg "%ba64")],
                  IGep "%b_payload" I8 (VReg "%b") [(I64, VInt 8)],
                  ICall Nothing Ptr Nothing "@memcpy" [(Ptr, VReg "%buf_payload_b"), (Ptr, VReg "%b_payload"), (I64, VReg "%bb64")],
                  ICall (Just "%right") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%right_tag" IntToPtr I64 (ptI ptRight) Ptr,
                  IStore Ptr (VReg "%right_tag") (VReg "%right"),
                  IGep "%right_f" Ptr (VReg "%right") [(I32, VInt 1)],
                  IStore Ptr (VReg "%buf") (VReg "%right_f"),
                  IBr "join",
                  ILabel "join",
                  IPhi "%result" Ptr [(VReg "%left", "too_long"), (VReg "%right", "ok")],
                  ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%a")],
                  ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%b")],
                  IRet (Just (Ptr, VReg "%result"))
                ]
            }
    -- '__print' uses 'write(2)' rather than 'printf("%s", …)' so a NUL
    -- byte inside the payload is preserved (printf-family stop at NUL
    -- regardless of '%.*s' precision per POSIX). Reads the byte count
    -- from the string header at offset 0 — O(1), no scan.
    rtPrint =
      (<> "\n")
        $ renderFunc
          LFunc
            { lfLinkage = "internal",
              lfRetType = Ptr,
              lfName = "__print",
              lfParams = [(Ptr, "%s")],
              lfBody =
                [ ILoad "%byte_count" I32 (VReg "%s"),
                  IConv "%byte_count_64" Zext I32 (VReg "%byte_count") I64,
                  IGep "%payload" I8 (VReg "%s") [(I64, VInt 8)],
                  ICall Nothing I64 Nothing "@write" [(I32, VInt 1), (Ptr, VReg "%payload"), (I64, VReg "%byte_count_64")],
                  -- Build Unit value (single ptr slot) — same shape as every
                  -- other nullary CCon, so 'runIO' reads it via the standard
                  -- CCase tag check.
                  ICall (Just "%unit") Ptr Nothing "@__alloc" [(I64, VInt 8), (I32, VInt 0)],
                  IGep "%unit_tag_ptr" Ptr (VReg "%unit") [(I32, VInt 0)],
                  IConv "%unit_tag" IntToPtr I64 (VInt (toInteger (ptUnit ptags))) Ptr,
                  IStore Ptr (VReg "%unit_tag") (VReg "%unit_tag_ptr"),
                  ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%s")],
                  IRet (Just (Ptr, VReg "%unit"))
                ]
            }
    -- Integers are boxed: each CIntLit allocates a heap cell holding
    -- the native i32/i8 value and the Awsum-level 'ptr' points at it.
    -- Show reads the cell and snprintf's the decimal form into the
    -- payload portion of a length-prefixed string buffer. snprintf
    -- returns the bytes-written count, which we use as both byte and
    -- UTF-16 length (decimal output is ASCII-only — 1 byte = 1 UTF-16
    -- code unit). Allocation is 8 (header) + 16 (max digits + sign +
    -- NUL); the trailing NUL written by snprintf is harmless because
    -- consumers read exactly 'byte_count' bytes from the payload.
    -- Show via snprintf: fixed buffer + format-string call → length-prefixed
    -- string. 'prologue' produces the i32 @%v@ to format (int32 loads it
    -- directly; the u8 forms zext from i8 first).
    showViaSnprintf :: Text -> Text -> [LInstr] -> LFunc
    showViaSnprintf name fmtGlobal prologue =
      LFunc
        { lfLinkage = "internal",
          lfRetType = Ptr,
          lfName = name,
          lfParams = [(Ptr, "%p")],
          lfBody =
            prologue
              <> [ ICall (Just "%buf") Ptr Nothing "@__alloc" [(I64, VInt 24), (I32, VInt 0)],
                   IGep "%payload" I8 (VReg "%buf") [(I64, VInt 8)],
                   ICall (Just "%n") I32 (Just ([Ptr, I64, Ptr], True)) "@snprintf" [(Ptr, VReg "%payload"), (I64, VInt 16), (Ptr, VGlob fmtGlobal), (I32, VReg "%v")],
                   IStore I32 (VReg "%n") (VReg "%buf"),
                   IGep "%u16p" I8 (VReg "%buf") [(I64, VInt 4)],
                   IStore I32 (VReg "%n") (VReg "%u16p"),
                   ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%p")],
                   IRet (Just (Ptr, VReg "%buf"))
                 ]
        }
    loadI32Direct :: [LInstr]
    loadI32Direct = [ILoad "%v" I32 (VReg "%p")]
    loadU8AsI32 :: [LInstr]
    loadU8AsI32 = [ILoad "%b" I8 (VReg "%p"), IConv "%v" Zext I8 (VReg "%b") I32]
    -- pred / succ: bounds-check, @Left <err>@ at the boundary else @Right (v ±
    -- 1)@. 'errTag' is UnderflowError (pred) or OverflowError (succ); 'cmpReg'
    -- is the (cosmetic) comparison-result name from the original IR.
    predSuccFn :: Text -> (PreludeTags -> Int) -> Text -> LType -> Text -> Integer -> LBinOp -> LFunc
    predSuccFn name errTag errReg ty cmpReg boundary op =
      LFunc
        { lfLinkage = "internal",
          lfRetType = Ptr,
          lfName = name,
          lfParams = [(Ptr, "%p")],
          lfBody =
            [ ILoad "%v" ty (VReg "%p"),
              IICmp cmpReg IEq ty (VReg "%v") (VInt boundary),
              IBrCond (VReg cmpReg) "overflow" "ok",
              ILabel "overflow",
              ICall (Just errReg) Ptr Nothing "@__alloc" [(I64, VInt 8), (I32, VInt 0)],
              IConv (errReg <> "_tag") IntToPtr I64 (ptI errTag) Ptr,
              IStore Ptr (VReg (errReg <> "_tag")) (VReg errReg),
              ICall (Just "%left") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
              IConv "%left_tag" IntToPtr I64 (ptI ptLeft) Ptr,
              IStore Ptr (VReg "%left_tag") (VReg "%left"),
              IGep "%left_f" Ptr (VReg "%left") [(I32, VInt 1)],
              IStore Ptr (VReg errReg) (VReg "%left_f"),
              ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%p")],
              IRet (Just (Ptr, VReg "%left")),
              ILabel "ok",
              IBin "%newv" op ty (VReg "%v") (VInt 1),
              ICall (Just "%box") Ptr Nothing "@__alloc" [(I64, VInt (typeBytes ty)), (I32, VInt 0)],
              IStore ty (VReg "%newv") (VReg "%box"),
              ICall (Just "%right") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
              IConv "%right_tag" IntToPtr I64 (ptI ptRight) Ptr,
              IStore Ptr (VReg "%right_tag") (VReg "%right"),
              IGep "%right_f" Ptr (VReg "%right") [(I32, VInt 1)],
              IStore Ptr (VReg "%box") (VReg "%right_f"),
              ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%p")],
              IRet (Just (Ptr, VReg "%right"))
            ]
        }
    -- Native-equality for boxed integers: unbox, compare, box a Bool tag.
    eqFn :: Text -> LType -> LFunc
    eqFn name ty =
      LFunc
        { lfLinkage = "internal",
          lfRetType = Ptr,
          lfName = name,
          lfParams = [(Ptr, "%a"), (Ptr, "%b")],
          lfBody =
            [ ILoad "%va" ty (VReg "%a"),
              ILoad "%vb" ty (VReg "%b"),
              IICmp "%eq" IEq ty (VReg "%va") (VReg "%vb"),
              ISelect "%tag" (VReg "%eq") I64 (ptI ptTrue) (ptI ptFalse),
              ICall (Just "%box") Ptr Nothing "@__alloc" [(I64, VInt 8), (I32, VInt 0)],
              IConv "%tag_ptr" IntToPtr I64 (VReg "%tag") Ptr,
              IStore Ptr (VReg "%tag_ptr") (VReg "%box"),
              ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%a")],
              ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%b")],
              IRet (Just (Ptr, VReg "%box"))
            ]
        }
    rtShowInt32 = (<> "\n") $ renderFunc (showViaSnprintf "__showInt32" "@.fmt_i32" loadI32Direct)
    rtShowUInt8 = (<> "\n") $ renderFunc (showViaSnprintf "__showUInt8" "@.fmt_u8" loadU8AsI32)
    -- byteToHexStringNoPrefix: same shape as '__showUInt8' but the '%02x'
    -- format — always two lowercase hex digits.
    rtByteToHex = (<> "\n") $ renderFunc (showViaSnprintf "__byteToHex" "@.fmt_hex" loadU8AsI32)
    -- predInt32 : Int32 -> Either UnderflowError Int32
    --   On INT32_MIN, returns Left UnderflowError (tags: Left=0,
    --   UnderflowError=0). Otherwise returns Right (x - 1) (Right=1).
    --   Containers follow the uniform layout [tag_as_ptr, field, ...],
    --   same as user CCon emission.
    rtPredInt32 = (<> "\n") $ renderFunc (predSuccFn "__predInt32" ptUnderflowError "%oe" I32 "%is_min" (-2147483648) LSub)
    -- predUInt8 : UInt8 -> Either UnderflowError UInt8
    --   `Left UnderflowError` on 0, `Right (v - 1)` otherwise. Value is
    --   loaded as i8 (UInt8's storage width) and subtracted at i8 width;
    --   underflow is impossible on this path since v >= 1.
    rtPredUInt8 = (<> "\n") $ renderFunc (predSuccFn "__predUInt8" ptUnderflowError "%oe" I8 "%is_zero" 0 LSub)
    -- succInt32 : Int32 -> Either OverflowError Int32
    --   On INT32_MAX, returns Left OverflowError (tags: Left=0,
    --   OverflowError=0). Otherwise returns Right (x + 1) (Right=1). Mirrors
    --   'rtPredInt32' with the boundary flipped and 'sub' swapped for 'add'.
    rtSuccInt32 = (<> "\n") $ renderFunc (predSuccFn "__succInt32" ptOverflowError "%oe" I32 "%is_max" 2147483647 LAdd)
    -- succUInt8 : UInt8 -> Either OverflowError UInt8
    --   `Left OverflowError` on 255, `Right (v + 1)` otherwise. Value is
    --   loaded as i8 and added at i8 width; overflow is impossible on this
    --   path since v <= 254.
    rtSuccUInt8 = (<> "\n") $ renderFunc (predSuccFn "__succUInt8" ptOverflowError "%oe" I8 "%is_max" 255 LAdd)
    -- eqInt32 / eqUInt8: unbox both pointers, compare the native value, and
    -- return a one-slot Bool container ([tag]). True=0, False=1 matches
    -- declaration order in `type Bool = True | False`.
    rtEqInt32 = (<> "\n") $ renderFunc (eqFn "__eqInt32" I32)
    rtEqUInt8 = (<> "\n") $ renderFunc (eqFn "__eqUInt8" I8)
    -- eqString : String -> String -> Bool.
    -- Strings carry an 8-byte header (i32 byte_count, i32 utf16_count)
    -- followed by the UTF-8 payload. Strict-UTF-16 invariant: equal
    -- UTF-16 code-unit sequences ⇔ equal UTF-8 byte sequences, so
    -- byte_count + memcmp suffices. byte_count check short-circuits
    -- on length mismatch without touching the payload.
    -- eqString: length check (header byte_count), then memcmp the payloads.
    rtEqString =
      (<> "\n")
        $ renderFunc
          LFunc
            { lfLinkage = "internal",
              lfRetType = Ptr,
              lfName = "__eqString",
              lfParams = [(Ptr, "%a"), (Ptr, "%b")],
              lfBody =
                [ ILoad "%ba" I32 (VReg "%a"),
                  ILoad "%bb" I32 (VReg "%b"),
                  IICmp "%len_eq" IEq I32 (VReg "%ba") (VReg "%bb"),
                  IBrCond (VReg "%len_eq") "cmp" "ne",
                  ILabel "cmp",
                  IGep "%a_payload" I8 (VReg "%a") [(I64, VInt 8)],
                  IGep "%b_payload" I8 (VReg "%b") [(I64, VInt 8)],
                  IConv "%ba64" Zext I32 (VReg "%ba") I64,
                  ICall (Just "%r") I32 Nothing "@memcmp" [(Ptr, VReg "%a_payload"), (Ptr, VReg "%b_payload"), (I64, VReg "%ba64")],
                  IICmp "%bytes_eq" IEq I32 (VReg "%r") (VInt 0),
                  IBrCond (VReg "%bytes_eq") "eq" "ne",
                  ILabel "eq",
                  IConv "%tag_t" IntToPtr I64 (ptI ptTrue) Ptr,
                  ICall (Just "%box_t") Ptr Nothing "@__alloc" [(I64, VInt 8), (I32, VInt 0)],
                  IStore Ptr (VReg "%tag_t") (VReg "%box_t"),
                  IBr "done",
                  ILabel "ne",
                  IConv "%tag_f" IntToPtr I64 (ptI ptFalse) Ptr,
                  ICall (Just "%box_f") Ptr Nothing "@__alloc" [(I64, VInt 8), (I32, VInt 0)],
                  IStore Ptr (VReg "%tag_f") (VReg "%box_f"),
                  IBr "done",
                  ILabel "done",
                  IPhi "%result" Ptr [(VReg "%box_t", "eq"), (VReg "%box_f", "ne")],
                  ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%a")],
                  ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%b")],
                  IRet (Just (Ptr, VReg "%result"))
                ]
            }
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
    -- add / sub Int32 share one shape: a @llvm.s{add,sub}.with.overflow@
    -- intrinsic, then on overflow @icmp sge i32 %a, 0@ picks OverflowError
    -- (a >= 0) vs UnderflowError, boxed inner-CCon → CRow → Left.
    int32OverflowFn :: Text -> Text -> Text -> LFunc
    int32OverflowFn name intrinsic valReg =
      LFunc
        { lfLinkage = "internal",
          lfRetType = Ptr,
          lfName = name,
          lfParams = [(Ptr, "%pa"), (Ptr, "%pb")],
          lfBody =
            [ ILoad "%a" I32 (VReg "%pa"),
              ILoad "%b" I32 (VReg "%pb"),
              ICall (Just "%res") (TStruct [I32, I1]) Nothing intrinsic [(I32, VReg "%a"), (I32, VReg "%b")],
              IExtractValue valReg (TStruct [I32, I1]) (VReg "%res") 0,
              IExtractValue "%ovf" (TStruct [I32, I1]) (VReg "%res") 1,
              IBrCond (VReg "%ovf") "err" "ok",
              ILabel "err",
              IICmp "%is_pos" ISge I32 (VReg "%a") (VInt 0),
              ISelect "%row_tag_idx" (VReg "%is_pos") I64 (tagOf "OverflowError") (tagOf "UnderflowError"),
              ISelect "%inner_tag_idx" (VReg "%is_pos") I64 (ptI ptOverflowError) (ptI ptUnderflowError),
              ICall (Just "%inner") Ptr Nothing "@__alloc" [(I64, VInt 8), (I32, VInt 0)],
              IConv "%inner_tag" IntToPtr I64 (VReg "%inner_tag_idx") Ptr,
              IStore Ptr (VReg "%inner_tag") (VReg "%inner"),
              ICall (Just "%row") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
              IConv "%row_tag" IntToPtr I64 (VReg "%row_tag_idx") Ptr,
              IStore Ptr (VReg "%row_tag") (VReg "%row"),
              IGep "%row_f" Ptr (VReg "%row") [(I32, VInt 1)],
              IStore Ptr (VReg "%inner") (VReg "%row_f"),
              ICall (Just "%left") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
              IConv "%left_tag" IntToPtr I64 (ptI ptLeft) Ptr,
              IStore Ptr (VReg "%left_tag") (VReg "%left"),
              IGep "%left_f" Ptr (VReg "%left") [(I32, VInt 1)],
              IStore Ptr (VReg "%row") (VReg "%left_f"),
              IBr "join",
              ILabel "ok",
              ICall (Just "%box") Ptr Nothing "@__alloc" [(I64, VInt 4), (I32, VInt 0)],
              IStore I32 (VReg valReg) (VReg "%box"),
              ICall (Just "%right") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
              IConv "%right_tag" IntToPtr I64 (ptI ptRight) Ptr,
              IStore Ptr (VReg "%right_tag") (VReg "%right"),
              IGep "%right_f" Ptr (VReg "%right") [(I32, VInt 1)],
              IStore Ptr (VReg "%box") (VReg "%right_f"),
              IBr "join",
              ILabel "join",
              IPhi "%result" Ptr [(VReg "%left", "err"), (VReg "%right", "ok")],
              ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%pa")],
              ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%pb")],
              IRet (Just (Ptr, VReg "%result"))
            ]
        }
    rtAddInt32 = (<> "\n") $ renderFunc (int32OverflowFn "__addInt32" "@llvm.sadd.with.overflow.i32" "%sum")
    -- subInt32 : Int32 -> Int32 -> Either (UnderflowError | OverflowError) Int32.
    --   Uses 'llvm.ssub.with.overflow' to detect signed overflow in one
    --   instruction. On overflow, signs of @a@ and @b@ must differ
    --   (otherwise the difference stays in range), so @icmp sge i32 %a, 0@
    --   separates positive overflow (@a >= 0, b < 0@ ⇒ OverflowError) from
    --   negative (@a < 0, b > 0@ ⇒ UnderflowError). The special case
    --   `b == minInt32` only overflows when `a >= 0`, which stays inside
    --   the @a >= 0 ⇒ OverflowError@ branch. Same row-tagged error
    --   encoding as 'rtAddInt32'.
    rtSubInt32 = (<> "\n") $ renderFunc (int32OverflowFn "__subInt32" "@llvm.ssub.with.overflow.i32" "%diff")
    -- mulInt32 : Int32 -> Int32 -> Either (UnderflowError | OverflowError) Int32.
    --   Uses @llvm.smul.with.overflow.i32@ to detect signed overflow.
    --   Direction: same-sign overflow is OverflowError, opposite-sign is
    --   UnderflowError. We read sign agreement off @icmp sge i32 (a xor b), 0@:
    --   the xor's sign bit is 0 iff @a@ and @b@ have the same sign, so
    --   overflow on same-sign means positive overflow → OverflowError. The
    --   special case @minInt32 * -1@ = 2147483648 has same signs (both
    --   negative) and lands on OverflowError, which matches the math.
    --   Same row-tagged error encoding as 'rtAddInt32'.
    -- mul Int32 differs from add/sub: overflow direction comes from sign
    -- agreement (@xor@'s sign bit) — same-sign overflow is OverflowError —
    -- and the inner CCon tag is a constant 0 rather than a selected
    -- 'oeLit'/'ueLit'; so it doesn't share 'int32OverflowFn'.
    rtMulInt32 =
      (<> "\n")
        $ renderFunc
          LFunc
            { lfLinkage = "internal",
              lfRetType = Ptr,
              lfName = "__mulInt32",
              lfParams = [(Ptr, "%pa"), (Ptr, "%pb")],
              lfBody =
                [ ILoad "%a" I32 (VReg "%pa"),
                  ILoad "%b" I32 (VReg "%pb"),
                  ICall (Just "%res") (TStruct [I32, I1]) Nothing "@llvm.smul.with.overflow.i32" [(I32, VReg "%a"), (I32, VReg "%b")],
                  IExtractValue "%prod" (TStruct [I32, I1]) (VReg "%res") 0,
                  IExtractValue "%ovf" (TStruct [I32, I1]) (VReg "%res") 1,
                  IBrCond (VReg "%ovf") "err" "ok",
                  ILabel "err",
                  IBin "%xor_ab" LXor I32 (VReg "%a") (VReg "%b"),
                  IICmp "%same_sign" ISge I32 (VReg "%xor_ab") (VInt 0),
                  ISelect "%row_tag_idx" (VReg "%same_sign") I64 (tagOf "OverflowError") (tagOf "UnderflowError"),
                  ICall (Just "%inner") Ptr Nothing "@__alloc" [(I64, VInt 8), (I32, VInt 0)],
                  IConv "%inner_tag" IntToPtr I64 (VInt 0) Ptr,
                  IStore Ptr (VReg "%inner_tag") (VReg "%inner"),
                  ICall (Just "%row") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%row_tag" IntToPtr I64 (VReg "%row_tag_idx") Ptr,
                  IStore Ptr (VReg "%row_tag") (VReg "%row"),
                  IGep "%row_f" Ptr (VReg "%row") [(I32, VInt 1)],
                  IStore Ptr (VReg "%inner") (VReg "%row_f"),
                  ICall (Just "%left") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%left_tag" IntToPtr I64 (ptI ptLeft) Ptr,
                  IStore Ptr (VReg "%left_tag") (VReg "%left"),
                  IGep "%left_f" Ptr (VReg "%left") [(I32, VInt 1)],
                  IStore Ptr (VReg "%row") (VReg "%left_f"),
                  IBr "join",
                  ILabel "ok",
                  ICall (Just "%box") Ptr Nothing "@__alloc" [(I64, VInt 4), (I32, VInt 0)],
                  IStore I32 (VReg "%prod") (VReg "%box"),
                  ICall (Just "%right") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%right_tag" IntToPtr I64 (ptI ptRight) Ptr,
                  IStore Ptr (VReg "%right_tag") (VReg "%right"),
                  IGep "%right_f" Ptr (VReg "%right") [(I32, VInt 1)],
                  IStore Ptr (VReg "%box") (VReg "%right_f"),
                  IBr "join",
                  ILabel "join",
                  IPhi "%result" Ptr [(VReg "%left", "err"), (VReg "%right", "ok")],
                  ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%pa")],
                  ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%pb")],
                  IRet (Just (Ptr, VReg "%result"))
                ]
            }
    -- negInt32 : Int32 -> Either OverflowError Int32.
    --   Only @minInt32@ overflows on negation (its absolute value is one
    --   above maxInt32 in two's complement); every other input flips sign
    --   exactly. Same Left / Right encoding as 'rtSuccInt32', just with a
    --   different boundary and a 'sub 0, v' for the ok path.
    rtNegInt32 =
      (<> "\n")
        $ renderFunc
          LFunc
            { lfLinkage = "internal",
              lfRetType = Ptr,
              lfName = "__negInt32",
              lfParams = [(Ptr, "%p")],
              lfBody =
                [ ILoad "%v" I32 (VReg "%p"),
                  IICmp "%is_min" IEq I32 (VReg "%v") (VInt (-2147483648)),
                  IBrCond (VReg "%is_min") "overflow" "ok",
                  ILabel "overflow",
                  ICall (Just "%oe") Ptr Nothing "@__alloc" [(I64, VInt 8), (I32, VInt 0)],
                  IConv "%oe_tag" IntToPtr I64 (ptI ptOverflowError) Ptr,
                  IStore Ptr (VReg "%oe_tag") (VReg "%oe"),
                  ICall (Just "%left") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%left_tag" IntToPtr I64 (ptI ptLeft) Ptr,
                  IStore Ptr (VReg "%left_tag") (VReg "%left"),
                  IGep "%left_f" Ptr (VReg "%left") [(I32, VInt 1)],
                  IStore Ptr (VReg "%oe") (VReg "%left_f"),
                  ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%p")],
                  IRet (Just (Ptr, VReg "%left")),
                  ILabel "ok",
                  IBin "%newv" LSub I32 (VInt 0) (VReg "%v"),
                  ICall (Just "%box") Ptr Nothing "@__alloc" [(I64, VInt 4), (I32, VInt 0)],
                  IStore I32 (VReg "%newv") (VReg "%box"),
                  ICall (Just "%right") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%right_tag" IntToPtr I64 (ptI ptRight) Ptr,
                  IStore Ptr (VReg "%right_tag") (VReg "%right"),
                  IGep "%right_f" Ptr (VReg "%right") [(I32, VInt 1)],
                  IStore Ptr (VReg "%box") (VReg "%right_f"),
                  ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%p")],
                  IRet (Just (Ptr, VReg "%right"))
                ]
            }
    -- addUInt8 : UInt8 -> UInt8 -> Either OverflowError UInt8.
    --   Both operands fit in i8, so widening to i32 first and comparing
    --   the sum against 255 gives a saturation-free overflow check
    --   (unsigned underflow is impossible for a + b on UInt8). On the ok
    --   path, the sum is in 0..510 — truncating to i8 keeps the low byte
    --   exactly when the comparison falls through.
    -- Unsigned add / mul: widen both operands (zext) so the result can't
    -- wrap, @icmp ugt@ against the type's max for OverflowError, else trunc
    -- back. Widened-register names take the wide type's bit width as suffix
    -- (@%a32@ for u8→i32, @%a64@ for u32→i64), matching the original IR.
    uintAddMulFn :: Text -> LBinOp -> Text -> LType -> LType -> Integer -> LFunc
    uintAddMulFn name op resPrefix loadTy wideTy bound =
      let w = show (typeBytes wideTy * 8)
          aReg = "%a" <> w
          bReg = "%b" <> w
          resReg = "%" <> resPrefix <> w
       in LFunc
            { lfLinkage = "internal",
              lfRetType = Ptr,
              lfName = name,
              lfParams = [(Ptr, "%pa"), (Ptr, "%pb")],
              lfBody =
                [ ILoad "%a" loadTy (VReg "%pa"),
                  ILoad "%b" loadTy (VReg "%pb"),
                  IConv aReg Zext loadTy (VReg "%a") wideTy,
                  IConv bReg Zext loadTy (VReg "%b") wideTy,
                  IBin resReg op wideTy (VReg aReg) (VReg bReg),
                  IICmp "%ovf" IUgt wideTy (VReg resReg) (VInt bound),
                  IBrCond (VReg "%ovf") "err" "ok",
                  ILabel "err",
                  ICall (Just "%oe") Ptr Nothing "@__alloc" [(I64, VInt 8), (I32, VInt 0)],
                  IConv "%oe_tag" IntToPtr I64 (ptI ptOverflowError) Ptr,
                  IStore Ptr (VReg "%oe_tag") (VReg "%oe"),
                  ICall (Just "%left") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%left_tag" IntToPtr I64 (ptI ptLeft) Ptr,
                  IStore Ptr (VReg "%left_tag") (VReg "%left"),
                  IGep "%left_f" Ptr (VReg "%left") [(I32, VInt 1)],
                  IStore Ptr (VReg "%oe") (VReg "%left_f"),
                  IBr "join",
                  ILabel "ok",
                  IConv "%newv" Trunc wideTy (VReg resReg) loadTy,
                  ICall (Just "%box") Ptr Nothing "@__alloc" [(I64, VInt (typeBytes loadTy)), (I32, VInt 0)],
                  IStore loadTy (VReg "%newv") (VReg "%box"),
                  ICall (Just "%right") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%right_tag" IntToPtr I64 (ptI ptRight) Ptr,
                  IStore Ptr (VReg "%right_tag") (VReg "%right"),
                  IGep "%right_f" Ptr (VReg "%right") [(I32, VInt 1)],
                  IStore Ptr (VReg "%box") (VReg "%right_f"),
                  IBr "join",
                  ILabel "join",
                  IPhi "%result" Ptr [(VReg "%left", "err"), (VReg "%right", "ok")],
                  ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%pa")],
                  ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%pb")],
                  IRet (Just (Ptr, VReg "%result"))
                ]
            }
    rtAddUInt8 = (<> "\n") $ renderFunc (uintAddMulFn "__addUInt8" LAdd "sum" I8 I32 255)
    -- mulUInt8 : UInt8 -> UInt8 -> Either OverflowError UInt8.
    --   Both operands fit in i8, so widening to i32 and multiplying gives
    --   a product in 0..65025 (= 255 * 255) — well inside the i32 range.
    --   A single @icmp ugt 255@ separates the branches; on the ok path
    --   the product is in 0..255, so truncating to i8 is faithful.
    rtMulUInt8 = (<> "\n") $ renderFunc (uintAddMulFn "__mulUInt8" LMul "prod" I8 I32 255)
    -- subUInt8 : UInt8 -> UInt8 -> Either UnderflowError UInt8.
    --   The signed-difference of two i8 values is in -128..127, but the
    --   *unsigned* interpretation of UInt8 says the difference is in
    --   -255..255. Widening to i32 first and comparing 'a < b' as unsigned
    --   picks the underflow branch. On the ok path the difference is
    --   already in 0..255, so truncating back to i8 is faithful.
    -- sub UInt8: widen to i32, @icmp ult@ for UnderflowError, else diff + trunc.
    rtSubUInt8 =
      (<> "\n")
        $ renderFunc
          LFunc
            { lfLinkage = "internal",
              lfRetType = Ptr,
              lfName = "__subUInt8",
              lfParams = [(Ptr, "%pa"), (Ptr, "%pb")],
              lfBody =
                [ ILoad "%a" I8 (VReg "%pa"),
                  ILoad "%b" I8 (VReg "%pb"),
                  IConv "%a32" Zext I8 (VReg "%a") I32,
                  IConv "%b32" Zext I8 (VReg "%b") I32,
                  IICmp "%unf" IUlt I32 (VReg "%a32") (VReg "%b32"),
                  IBrCond (VReg "%unf") "err" "ok",
                  ILabel "err",
                  ICall (Just "%ue") Ptr Nothing "@__alloc" [(I64, VInt 8), (I32, VInt 0)],
                  IConv "%ue_tag" IntToPtr I64 (ptI ptUnderflowError) Ptr,
                  IStore Ptr (VReg "%ue_tag") (VReg "%ue"),
                  ICall (Just "%left") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%left_tag" IntToPtr I64 (ptI ptLeft) Ptr,
                  IStore Ptr (VReg "%left_tag") (VReg "%left"),
                  IGep "%left_f" Ptr (VReg "%left") [(I32, VInt 1)],
                  IStore Ptr (VReg "%ue") (VReg "%left_f"),
                  IBr "join",
                  ILabel "ok",
                  IBin "%diff32" LSub I32 (VReg "%a32") (VReg "%b32"),
                  IConv "%newv" Trunc I32 (VReg "%diff32") I8,
                  ICall (Just "%box") Ptr Nothing "@__alloc" [(I64, VInt 1), (I32, VInt 0)],
                  IStore I8 (VReg "%newv") (VReg "%box"),
                  ICall (Just "%right") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%right_tag" IntToPtr I64 (ptI ptRight) Ptr,
                  IStore Ptr (VReg "%right_tag") (VReg "%right"),
                  IGep "%right_f" Ptr (VReg "%right") [(I32, VInt 1)],
                  IStore Ptr (VReg "%box") (VReg "%right_f"),
                  IBr "join",
                  ILabel "join",
                  IPhi "%result" Ptr [(VReg "%left", "err"), (VReg "%right", "ok")],
                  ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%pa")],
                  ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%pb")],
                  IRet (Just (Ptr, VReg "%result"))
                ]
            }
    -- splitOnFirst : String -> String -> Maybe (Tuple2 String String).
    --   Now operates on length-prefixed strings: byte counts come from
    --   the header (offset 0) directly, no 'strlen'. Empty separator
    --   matches at position 0 (prefix = "", suffix = str). Both halves
    --   are owning copies in length-prefixed format with their own
    --   computed UTF-16 counts via inline byte scans (BMP byte → 1 code
    --   unit, 4-byte UTF-8 → 2 surrogates).
    -- splitOnFirst defines two functions: the naive O(n·m) search, and an
    -- inline UTF-16-counting byte-walker '__utf16OfRange' it calls to give
    -- each half its own header. On a match it builds two owning
    -- length-prefixed copies, wraps them in Tuple2 → Just; else Nothing.
    rtSplitOnFirst =
      let splitFn =
            LFunc
              { lfLinkage = "internal",
                lfRetType = Ptr,
                lfName = "__splitOnFirst",
                lfParams = [(Ptr, "%sep"), (Ptr, "%str")],
                lfBody =
                  [ ILabel "entry",
                    ILoad "%sep_len32" I32 (VReg "%sep"),
                    ILoad "%str_len32" I32 (VReg "%str"),
                    IConv "%sep_len" Zext I32 (VReg "%sep_len32") I64,
                    IConv "%str_len" Zext I32 (VReg "%str_len32") I64,
                    IGep "%sep_payload" I8 (VReg "%sep") [(I64, VInt 8)],
                    IGep "%str_payload" I8 (VReg "%str") [(I64, VInt 8)],
                    IICmp "%too_long" IUgt I64 (VReg "%sep_len") (VReg "%str_len"),
                    IBrCond (VReg "%too_long") "not_found" "search_init",
                    ILabel "search_init",
                    IBin "%limit" LSub I64 (VReg "%str_len") (VReg "%sep_len"),
                    IAlloca "%i_p" I64 (Just 8),
                    IStore I64 (VInt 0) (VReg "%i_p"),
                    IBr "outer",
                    ILabel "outer",
                    ILoad "%i" I64 (VReg "%i_p"),
                    IICmp "%i_done" IUgt I64 (VReg "%i") (VReg "%limit"),
                    IBrCond (VReg "%i_done") "not_found" "inner_init",
                    ILabel "inner_init",
                    IAlloca "%j_p" I64 (Just 8),
                    IStore I64 (VInt 0) (VReg "%j_p"),
                    IBr "inner",
                    ILabel "inner",
                    ILoad "%j" I64 (VReg "%j_p"),
                    IICmp "%j_done" IUge I64 (VReg "%j") (VReg "%sep_len"),
                    IBrCond (VReg "%j_done") "match" "inner_step",
                    ILabel "inner_step",
                    IBin "%ij" LAdd I64 (VReg "%i") (VReg "%j"),
                    IGep "%sp" I8 (VReg "%str_payload") [(I64, VReg "%ij")],
                    ILoad "%sb" I8 (VReg "%sp"),
                    IGep "%sepp" I8 (VReg "%sep_payload") [(I64, VReg "%j")],
                    ILoad "%sepb" I8 (VReg "%sepp"),
                    IICmp "%eq" IEq I8 (VReg "%sb") (VReg "%sepb"),
                    IBrCond (VReg "%eq") "inner_advance" "outer_advance",
                    ILabel "inner_advance",
                    IBin "%j1" LAdd I64 (VReg "%j") (VInt 1),
                    IStore I64 (VReg "%j1") (VReg "%j_p"),
                    IBr "inner",
                    ILabel "outer_advance",
                    IBin "%i1" LAdd I64 (VReg "%i") (VInt 1),
                    IStore I64 (VReg "%i1") (VReg "%i_p"),
                    IBr "outer",
                    ILabel "match",
                    IPhi "%prefix_blen" I64 [(VReg "%i", "inner")],
                    IBin "%prefix_after" LAdd I64 (VReg "%i") (VReg "%sep_len"),
                    IBin "%suffix_blen" LSub I64 (VReg "%str_len") (VReg "%prefix_after"),
                    IGep "%suffix_start" I8 (VReg "%str_payload") [(I64, VReg "%prefix_after")],
                    ICall (Just "%prefix_u16") I32 Nothing "@__utf16OfRange" [(Ptr, VReg "%str_payload"), (I64, VReg "%prefix_blen")],
                    IBin "%prefix_alloc" LAdd I64 (VReg "%prefix_blen") (VInt 8),
                    ICall (Just "%prefix") Ptr Nothing "@__alloc" [(I64, VReg "%prefix_alloc"), (I32, VInt 0)],
                    IConv "%prefix_blen32" Trunc I64 (VReg "%prefix_blen") I32,
                    IStore I32 (VReg "%prefix_blen32") (VReg "%prefix"),
                    IGep "%prefix_u16p" I8 (VReg "%prefix") [(I64, VInt 4)],
                    IStore I32 (VReg "%prefix_u16") (VReg "%prefix_u16p"),
                    IGep "%prefix_payload" I8 (VReg "%prefix") [(I64, VInt 8)],
                    ICall Nothing Ptr Nothing "@memcpy" [(Ptr, VReg "%prefix_payload"), (Ptr, VReg "%str_payload"), (I64, VReg "%prefix_blen")],
                    ICall (Just "%suffix_u16") I32 Nothing "@__utf16OfRange" [(Ptr, VReg "%suffix_start"), (I64, VReg "%suffix_blen")],
                    IBin "%suffix_alloc" LAdd I64 (VReg "%suffix_blen") (VInt 8),
                    ICall (Just "%suffix") Ptr Nothing "@__alloc" [(I64, VReg "%suffix_alloc"), (I32, VInt 0)],
                    IConv "%suffix_blen32" Trunc I64 (VReg "%suffix_blen") I32,
                    IStore I32 (VReg "%suffix_blen32") (VReg "%suffix"),
                    IGep "%suffix_u16p" I8 (VReg "%suffix") [(I64, VInt 4)],
                    IStore I32 (VReg "%suffix_u16") (VReg "%suffix_u16p"),
                    IGep "%suffix_payload" I8 (VReg "%suffix") [(I64, VInt 8)],
                    ICall Nothing Ptr Nothing "@memcpy" [(Ptr, VReg "%suffix_payload"), (Ptr, VReg "%suffix_start"), (I64, VReg "%suffix_blen")],
                    ICall (Just "%tuple") Ptr Nothing "@__alloc" [(I64, VInt 24), (I32, VInt 2)],
                    IConv "%tuple_tag" IntToPtr I64 (ptI ptTuple2) Ptr,
                    IStore Ptr (VReg "%tuple_tag") (VReg "%tuple"),
                    IGep "%tuple_a" Ptr (VReg "%tuple") [(I32, VInt 1)],
                    IStore Ptr (VReg "%prefix") (VReg "%tuple_a"),
                    IGep "%tuple_b" Ptr (VReg "%tuple") [(I32, VInt 2)],
                    IStore Ptr (VReg "%suffix") (VReg "%tuple_b"),
                    ICall (Just "%just") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                    IConv "%just_tag" IntToPtr I64 (ptI ptJust) Ptr,
                    IStore Ptr (VReg "%just_tag") (VReg "%just"),
                    IGep "%just_f" Ptr (VReg "%just") [(I32, VInt 1)],
                    IStore Ptr (VReg "%tuple") (VReg "%just_f"),
                    IBr "join",
                    ILabel "not_found",
                    ICall (Just "%nothing") Ptr Nothing "@__alloc" [(I64, VInt 8), (I32, VInt 0)],
                    IConv "%nothing_tag" IntToPtr I64 (ptI ptNothing) Ptr,
                    IStore Ptr (VReg "%nothing_tag") (VReg "%nothing"),
                    IBr "join",
                    ILabel "join",
                    IPhi "%result" Ptr [(VReg "%just", "match"), (VReg "%nothing", "not_found")],
                    ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%sep")],
                    ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%str")],
                    IRet (Just (Ptr, VReg "%result"))
                  ]
              }
          utf16Fn =
            LFunc
              { lfLinkage = "internal",
                lfRetType = I32,
                lfName = "__utf16OfRange",
                lfParams = [(Ptr, "%p"), (I64, "%len")],
                lfBody =
                  [ ILabel "entry",
                    IAlloca "%i_p" I64 (Just 8),
                    IStore I64 (VInt 0) (VReg "%i_p"),
                    IAlloca "%n_p" I32 (Just 4),
                    IStore I32 (VInt 0) (VReg "%n_p"),
                    IBr "head",
                    ILabel "head",
                    ILoad "%i" I64 (VReg "%i_p"),
                    IICmp "%done" IUge I64 (VReg "%i") (VReg "%len"),
                    IBrCond (VReg "%done") "end" "body",
                    ILabel "body",
                    IGep "%bp" I8 (VReg "%p") [(I64, VReg "%i")],
                    ILoad "%b" I8 (VReg "%bp"),
                    IConv "%bz" Zext I8 (VReg "%b") I32,
                    IBin "%top2" LAnd I32 (VReg "%bz") (VInt 192),
                    IICmp "%is_cont" IEq I32 (VReg "%top2") (VInt 128),
                    IBrCond (VReg "%is_cont") "step" "check4",
                    ILabel "check4",
                    IBin "%top5" LAnd I32 (VReg "%bz") (VInt 248),
                    IICmp "%is_4" IEq I32 (VReg "%top5") (VInt 240),
                    IBrCond (VReg "%is_4") "add2" "add1",
                    ILabel "add2",
                    ILoad "%n2" I32 (VReg "%n_p"),
                    IBin "%n2_new" LAdd I32 (VReg "%n2") (VInt 2),
                    IStore I32 (VReg "%n2_new") (VReg "%n_p"),
                    IBr "step",
                    ILabel "add1",
                    ILoad "%n1" I32 (VReg "%n_p"),
                    IBin "%n1_new" LAdd I32 (VReg "%n1") (VInt 1),
                    IStore I32 (VReg "%n1_new") (VReg "%n_p"),
                    IBr "step",
                    ILabel "step",
                    IBin "%i1" LAdd I64 (VReg "%i") (VInt 1),
                    IStore I64 (VReg "%i1") (VReg "%i_p"),
                    IBr "head",
                    ILabel "end",
                    ILoad "%nf" I32 (VReg "%n_p"),
                    IRet (Just (I32, VReg "%nf"))
                  ]
              }
       in renderFunc splitFn <> "\n\n" <> renderFunc utf16Fn <> "\n"
    -- parseInt32 : String -> Either ParseError Int32.
    --   Strict decimal parser; grammar mirrors Awsum's literal — optional
    --   '-', one or more ASCII digits, nothing else. Accumulates into i64
    --   (so the maximum legal value 2147483648 — i.e. -minInt32 — fits)
    --   and fails fast as soon as the running magnitude exceeds 2147483648.
    --   Loop variables live in alloca slots; clang's mem2reg pass at -O2
    --   converts them to SSA phi nodes, so the emitted binary has no
    --   stack traffic.
    -- Strict decimal parser; grammar mirrors the Awsum literal (optional
    -- '-', one or more ASCII digits). Accumulates into i64 (so -minInt32 =
    -- 2147483648 fits) and fails fast past 2147483648; loop vars in allocas
    -- (clang's mem2reg promotes them to SSA at -O2).
    rtParseInt32 =
      (<> "\n")
        $ renderFunc
          LFunc
            { lfLinkage = "internal",
              lfRetType = Ptr,
              lfName = "__parseInt32",
              lfParams = [(Ptr, "%s")],
              lfBody =
                [ ILabel "entry",
                  IAlloca "%neg_alloca" I32 (Just 4),
                  IStore I32 (VInt 0) (VReg "%neg_alloca"),
                  IAlloca "%i_alloca" I64 (Just 8),
                  IStore I64 (VInt 0) (VReg "%i_alloca"),
                  IAlloca "%acc_alloca" I64 (Just 8),
                  IStore I64 (VInt 0) (VReg "%acc_alloca"),
                  ILoad "%len32" I32 (VReg "%s"),
                  IConv "%len" Zext I32 (VReg "%len32") I64,
                  IGep "%payload" I8 (VReg "%s") [(I64, VInt 8)],
                  IICmp "%is_empty" IEq I64 (VReg "%len") (VInt 0),
                  IBrCond (VReg "%is_empty") "fail" "check_sign",
                  ILabel "check_sign",
                  ILoad "%first" I8 (VReg "%payload"),
                  IConv "%first_i32" Zext I8 (VReg "%first") I32,
                  IICmp "%is_neg" IEq I32 (VReg "%first_i32") (VInt 45),
                  IBrCond (VReg "%is_neg") "sign_minus" "loop_head",
                  ILabel "sign_minus",
                  IICmp "%is_lone" IEq I64 (VReg "%len") (VInt 1),
                  IBrCond (VReg "%is_lone") "fail" "sign_setup",
                  ILabel "sign_setup",
                  IStore I32 (VInt 1) (VReg "%neg_alloca"),
                  IStore I64 (VInt 1) (VReg "%i_alloca"),
                  IBr "loop_head",
                  ILabel "loop_head",
                  ILoad "%i" I64 (VReg "%i_alloca"),
                  ILoad "%acc" I64 (VReg "%acc_alloca"),
                  IICmp "%cond" IUlt I64 (VReg "%i") (VReg "%len"),
                  IBrCond (VReg "%cond") "body" "after",
                  ILabel "body",
                  IGep "%ptr_c" I8 (VReg "%payload") [(I64, VReg "%i")],
                  ILoad "%c" I8 (VReg "%ptr_c"),
                  IConv "%c_i32" Zext I8 (VReg "%c") I32,
                  IICmp "%low" IUlt I32 (VReg "%c_i32") (VInt 48),
                  IICmp "%high" IUgt I32 (VReg "%c_i32") (VInt 57),
                  IBin "%bad" LOr I1 (VReg "%low") (VReg "%high"),
                  IBrCond (VReg "%bad") "fail" "parse",
                  ILabel "parse",
                  IBin "%d" LSub I32 (VReg "%c_i32") (VInt 48),
                  IConv "%d_i64" Zext I32 (VReg "%d") I64,
                  IBin "%x10" LMul I64 (VReg "%acc") (VInt 10),
                  IBin "%acc_next" LAdd I64 (VReg "%x10") (VReg "%d_i64"),
                  IICmp "%big" IUgt I64 (VReg "%acc_next") (VInt 2147483648),
                  IBrCond (VReg "%big") "fail" "body_end",
                  ILabel "body_end",
                  IStore I64 (VReg "%acc_next") (VReg "%acc_alloca"),
                  IBin "%i_next" LAdd I64 (VReg "%i") (VInt 1),
                  IStore I64 (VReg "%i_next") (VReg "%i_alloca"),
                  IBr "loop_head",
                  ILabel "after",
                  ILoad "%neg_val" I32 (VReg "%neg_alloca"),
                  IICmp "%is_neg2" INe I32 (VReg "%neg_val") (VInt 0),
                  IBrCond (VReg "%is_neg2") "finalize_neg" "finalize_pos",
                  ILabel "finalize_pos",
                  IICmp "%big_pos" IUgt I64 (VReg "%acc") (VInt 2147483647),
                  IBrCond (VReg "%big_pos") "fail" "ok_pos",
                  ILabel "finalize_neg",
                  IBin "%acc_neg" LSub I64 (VInt 0) (VReg "%acc"),
                  IBr "ok_neg",
                  ILabel "ok_pos",
                  IConv "%result_pos" Trunc I64 (VReg "%acc") I32,
                  IBr "build_right",
                  ILabel "ok_neg",
                  IConv "%result_neg" Trunc I64 (VReg "%acc_neg") I32,
                  IBr "build_right",
                  ILabel "build_right",
                  IPhi "%result" I32 [(VReg "%result_pos", "ok_pos"), (VReg "%result_neg", "ok_neg")],
                  ICall (Just "%box") Ptr Nothing "@__alloc" [(I64, VInt 4), (I32, VInt 0)],
                  IStore I32 (VReg "%result") (VReg "%box"),
                  ICall (Just "%right") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%right_tag" IntToPtr I64 (ptI ptRight) Ptr,
                  IStore Ptr (VReg "%right_tag") (VReg "%right"),
                  IGep "%right_f" Ptr (VReg "%right") [(I32, VInt 1)],
                  IStore Ptr (VReg "%box") (VReg "%right_f"),
                  IBr "join",
                  ILabel "fail",
                  ICall (Just "%pe") Ptr Nothing "@__alloc" [(I64, VInt 8), (I32, VInt 0)],
                  IConv "%pe_tag" IntToPtr I64 (ptI ptParseError) Ptr,
                  IStore Ptr (VReg "%pe_tag") (VReg "%pe"),
                  ICall (Just "%left") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%left_tag" IntToPtr I64 (ptI ptLeft) Ptr,
                  IStore Ptr (VReg "%left_tag") (VReg "%left"),
                  IGep "%left_f" Ptr (VReg "%left") [(I32, VInt 1)],
                  IStore Ptr (VReg "%pe") (VReg "%left_f"),
                  IBr "join",
                  ILabel "join",
                  IPhi "%res" Ptr [(VReg "%right", "build_right"), (VReg "%left", "fail")],
                  ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%s")],
                  IRet (Just (Ptr, VReg "%res"))
                ]
            }
    -- parseUInt8 : String -> Either ParseError UInt8.
    --   No sign accepted; one or more ASCII digits, range 0..255. Same
    --   alloca-and-mem2reg pattern as 'rtParseInt32'; accumulator is i32
    --   since the running value never exceeds 2559 (255 * 10 + 9) before
    --   the '> 255' check fails the parse.
    -- parseUInt8: no sign; i32 accumulator (never exceeds 2559 before the
    -- @> 255@ check); same alloca/mem2reg loop shape as parseInt32.
    rtParseUInt8 =
      (<> "\n")
        $ renderFunc
          LFunc
            { lfLinkage = "internal",
              lfRetType = Ptr,
              lfName = "__parseUInt8",
              lfParams = [(Ptr, "%s")],
              lfBody =
                [ ILabel "entry",
                  IAlloca "%i_alloca" I64 (Just 8),
                  IStore I64 (VInt 0) (VReg "%i_alloca"),
                  IAlloca "%acc_alloca" I32 (Just 4),
                  IStore I32 (VInt 0) (VReg "%acc_alloca"),
                  ILoad "%len32" I32 (VReg "%s"),
                  IConv "%len" Zext I32 (VReg "%len32") I64,
                  IGep "%payload" I8 (VReg "%s") [(I64, VInt 8)],
                  IICmp "%is_empty" IEq I64 (VReg "%len") (VInt 0),
                  IBrCond (VReg "%is_empty") "fail" "loop_head",
                  ILabel "loop_head",
                  ILoad "%i" I64 (VReg "%i_alloca"),
                  ILoad "%acc" I32 (VReg "%acc_alloca"),
                  IICmp "%cond" IUlt I64 (VReg "%i") (VReg "%len"),
                  IBrCond (VReg "%cond") "body" "ok",
                  ILabel "body",
                  IGep "%ptr_c" I8 (VReg "%payload") [(I64, VReg "%i")],
                  ILoad "%c" I8 (VReg "%ptr_c"),
                  IConv "%c_i32" Zext I8 (VReg "%c") I32,
                  IICmp "%low" IUlt I32 (VReg "%c_i32") (VInt 48),
                  IICmp "%high" IUgt I32 (VReg "%c_i32") (VInt 57),
                  IBin "%bad" LOr I1 (VReg "%low") (VReg "%high"),
                  IBrCond (VReg "%bad") "fail" "parse",
                  ILabel "parse",
                  IBin "%d" LSub I32 (VReg "%c_i32") (VInt 48),
                  IBin "%x10" LMul I32 (VReg "%acc") (VInt 10),
                  IBin "%acc_next" LAdd I32 (VReg "%x10") (VReg "%d"),
                  IICmp "%big" IUgt I32 (VReg "%acc_next") (VInt 255),
                  IBrCond (VReg "%big") "fail" "body_end",
                  ILabel "body_end",
                  IStore I32 (VReg "%acc_next") (VReg "%acc_alloca"),
                  IBin "%i_next" LAdd I64 (VReg "%i") (VInt 1),
                  IStore I64 (VReg "%i_next") (VReg "%i_alloca"),
                  IBr "loop_head",
                  ILabel "ok",
                  IConv "%result_i8" Trunc I32 (VReg "%acc") I8,
                  ICall (Just "%box") Ptr Nothing "@__alloc" [(I64, VInt 1), (I32, VInt 0)],
                  IStore I8 (VReg "%result_i8") (VReg "%box"),
                  ICall (Just "%right") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%right_tag" IntToPtr I64 (ptI ptRight) Ptr,
                  IStore Ptr (VReg "%right_tag") (VReg "%right"),
                  IGep "%right_f" Ptr (VReg "%right") [(I32, VInt 1)],
                  IStore Ptr (VReg "%box") (VReg "%right_f"),
                  IBr "join",
                  ILabel "fail",
                  ICall (Just "%pe") Ptr Nothing "@__alloc" [(I64, VInt 8), (I32, VInt 0)],
                  IConv "%pe_tag" IntToPtr I64 (ptI ptParseError) Ptr,
                  IStore Ptr (VReg "%pe_tag") (VReg "%pe"),
                  ICall (Just "%left") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%left_tag" IntToPtr I64 (ptI ptLeft) Ptr,
                  IStore Ptr (VReg "%left_tag") (VReg "%left"),
                  IGep "%left_f" Ptr (VReg "%left") [(I32, VInt 1)],
                  IStore Ptr (VReg "%pe") (VReg "%left_f"),
                  IBr "join",
                  ILabel "join",
                  IPhi "%res" Ptr [(VReg "%right", "ok"), (VReg "%left", "fail")],
                  ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%s")],
                  IRet (Just (Ptr, VReg "%res"))
                ]
            }
    -- showUInt32: load i32, snprintf with the shared @.fmt_u8 ("%u")
    -- into a 16-byte buffer (max u32 "4294967295" is 10 digits + null).
    -- The format string is identical to UInt8's, so we don't introduce
    -- a separate constant — printf's "%u" with an i32 value already
    -- treats the 32-bit bit pattern as unsigned.
    -- showUInt32 reuses the @%u@ format ('@.fmt_u8'): snprintf reads the i32
    -- arg as unsigned, so the 0..4294967295 range prints correctly.
    rtShowUInt32 = (<> "\n") $ renderFunc (showViaSnprintf "__showUInt32" "@.fmt_u8" loadI32Direct)
    -- predUInt32: Left UnderflowError on 0, else Right (v - 1). i32 storage
    -- with unsigned semantics — the subtract is purely on the ok path
    -- where v >= 1, so wrap-around is irrelevant.
    rtPredUInt32 = (<> "\n") $ renderFunc (predSuccFn "__predUInt32" ptUnderflowError "%ue" I32 "%is_zero" 0 LSub)
    -- succUInt32: boundary 0xFFFFFFFF is encoded as the i32 literal -1 (same
    -- bit pattern); LLVM takes signed literals for i32 immediates.
    rtSuccUInt32 = (<> "\n") $ renderFunc (predSuccFn "__succUInt32" ptOverflowError "%oe" I32 "%is_max" (-1) LAdd)
    rtEqUInt32 = (<> "\n") $ renderFunc (eqFn "__eqUInt32" I32)
    -- addUInt32: Either OverflowError UInt32. Widen both operands to i64
    -- (zext, unsigned) so the unmasked sum fits, then compare against
    -- 4294967295 with 'icmp ugt'. On the ok path the sum is in
    -- 0..4294967295 — truncating back to i32 keeps the low bits exactly.
    rtAddUInt32 = (<> "\n") $ renderFunc (uintAddMulFn "__addUInt32" LAdd "sum" I32 I64 4294967295)
    -- subUInt32: Either UnderflowError UInt32. Compare 'a < b' as
    -- unsigned at i32 width — overflow is unreachable for unsigned
    -- subtraction.
    -- sub UInt32: i32-width @icmp ult@ for UnderflowError, else plain sub
    -- (no widening needed — the difference fits i32 on the ok path).
    rtSubUInt32 =
      (<> "\n")
        $ renderFunc
          LFunc
            { lfLinkage = "internal",
              lfRetType = Ptr,
              lfName = "__subUInt32",
              lfParams = [(Ptr, "%pa"), (Ptr, "%pb")],
              lfBody =
                [ ILoad "%a" I32 (VReg "%pa"),
                  ILoad "%b" I32 (VReg "%pb"),
                  IICmp "%unf" IUlt I32 (VReg "%a") (VReg "%b"),
                  IBrCond (VReg "%unf") "err" "ok",
                  ILabel "err",
                  ICall (Just "%ue") Ptr Nothing "@__alloc" [(I64, VInt 8), (I32, VInt 0)],
                  IConv "%ue_tag" IntToPtr I64 (ptI ptUnderflowError) Ptr,
                  IStore Ptr (VReg "%ue_tag") (VReg "%ue"),
                  ICall (Just "%left") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%left_tag" IntToPtr I64 (ptI ptLeft) Ptr,
                  IStore Ptr (VReg "%left_tag") (VReg "%left"),
                  IGep "%left_f" Ptr (VReg "%left") [(I32, VInt 1)],
                  IStore Ptr (VReg "%ue") (VReg "%left_f"),
                  IBr "join",
                  ILabel "ok",
                  IBin "%newv" LSub I32 (VReg "%a") (VReg "%b"),
                  ICall (Just "%box") Ptr Nothing "@__alloc" [(I64, VInt 4), (I32, VInt 0)],
                  IStore I32 (VReg "%newv") (VReg "%box"),
                  ICall (Just "%right") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%right_tag" IntToPtr I64 (ptI ptRight) Ptr,
                  IStore Ptr (VReg "%right_tag") (VReg "%right"),
                  IGep "%right_f" Ptr (VReg "%right") [(I32, VInt 1)],
                  IStore Ptr (VReg "%box") (VReg "%right_f"),
                  IBr "join",
                  ILabel "join",
                  IPhi "%result" Ptr [(VReg "%left", "err"), (VReg "%right", "ok")],
                  ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%pa")],
                  ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%pb")],
                  IRet (Just (Ptr, VReg "%result"))
                ]
            }
    -- mulUInt32: Either OverflowError UInt32. Widen both operands to i64
    -- (zext) so the unmasked product fits — max u32 * u32 is
    -- 0xFFFFFFFE00000001, well inside i64 range — then compare against
    -- 4294967295 with 'icmp ugt'. Same shape as 'rtAddUInt32' with 'mul'.
    rtMulUInt32 = (<> "\n") $ renderFunc (uintAddMulFn "__mulUInt32" LMul "prod" I32 I64 4294967295)
    -- lengthUtf8Bytes: O(1) — load the byte count from the string's
    -- 8-byte header at offset 0. Was 'strlen' over a null-terminated
    -- payload; the new length-prefixed layout caches this directly.
    rtLengthBytesAsUtf8 =
      (<> "\n")
        $ renderFunc
          LFunc
            { lfLinkage = "internal",
              lfRetType = Ptr,
              lfName = "__lengthUtf8Bytes",
              lfParams = [(Ptr, "%s")],
              lfBody =
                [ ILoad "%len32" I32 (VReg "%s"),
                  ICall (Just "%box") Ptr Nothing "@__alloc" [(I64, VInt 4), (I32, VInt 0)],
                  IStore I32 (VReg "%len32") (VReg "%box"),
                  ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%s")],
                  IRet (Just (Ptr, VReg "%box"))
                ]
            }
    -- lengthCodePoints: still O(n) — code-point count requires walking
    -- the bytes (continuation bytes don't start a code point). The walk
    -- is now bounded by the byte_count from the header (offset 0)
    -- rather than terminated by a NUL, so a payload containing NUL is
    -- counted correctly.
    rtLengthCodePoints =
      (<> "\n")
        $ renderFunc
          LFunc
            { lfLinkage = "internal",
              lfRetType = Ptr,
              lfName = "__lengthCodePoints",
              lfParams = [(Ptr, "%s")],
              lfBody =
                [ ILabel "entry",
                  ILoad "%total_bytes" I32 (VReg "%s"),
                  IConv "%total_bytes_64" Zext I32 (VReg "%total_bytes") I64,
                  IGep "%payload" I8 (VReg "%s") [(I64, VInt 8)],
                  IAlloca "%i_p" I64 (Just 8),
                  IStore I64 (VInt 0) (VReg "%i_p"),
                  IAlloca "%n_p" I32 (Just 4),
                  IStore I32 (VInt 0) (VReg "%n_p"),
                  IBr "head",
                  ILabel "head",
                  ILoad "%i" I64 (VReg "%i_p"),
                  IICmp "%at_end" IUge I64 (VReg "%i") (VReg "%total_bytes_64"),
                  IBrCond (VReg "%at_end") "done" "body",
                  ILabel "body",
                  IGep "%bp" I8 (VReg "%payload") [(I64, VReg "%i")],
                  ILoad "%b" I8 (VReg "%bp"),
                  IConv "%bz" Zext I8 (VReg "%b") I32,
                  IBin "%top2" LAnd I32 (VReg "%bz") (VInt 192),
                  IICmp "%is_cont" IEq I32 (VReg "%top2") (VInt 128),
                  IBrCond (VReg "%is_cont") "step" "inc",
                  ILabel "inc",
                  ILoad "%n0" I32 (VReg "%n_p"),
                  IBin "%n1" LAdd I32 (VReg "%n0") (VInt 1),
                  IStore I32 (VReg "%n1") (VReg "%n_p"),
                  IBr "step",
                  ILabel "step",
                  IBin "%i1" LAdd I64 (VReg "%i") (VInt 1),
                  IStore I64 (VReg "%i1") (VReg "%i_p"),
                  IBr "head",
                  ILabel "done",
                  ILoad "%nf" I32 (VReg "%n_p"),
                  ICall (Just "%box") Ptr Nothing "@__alloc" [(I64, VInt 4), (I32, VInt 0)],
                  IStore I32 (VReg "%nf") (VReg "%box"),
                  ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%s")],
                  IRet (Just (Ptr, VReg "%box"))
                ]
            }
    -- lengthUtf16CodeUnits: walk codepoint starts; BMP codepoints
    -- (1-/2-/3-byte UTF-8 sequences) contribute 1 code unit, supplementary
    -- ones (4-byte UTF-8, 11110xxx start byte) contribute 2 (surrogate
    -- pair). Continuation bytes (10xxxxxx) are skipped.
    -- O(1) — UTF-16 code-unit count is cached in the string header at
    -- offset 4.
    rtLengthUtf16CodeUnits =
      (<> "\n")
        $ renderFunc
          LFunc
            { lfLinkage = "internal",
              lfRetType = Ptr,
              lfName = "__lengthUtf16CodeUnits",
              lfParams = [(Ptr, "%s")],
              lfBody =
                [ IGep "%u16p" I8 (VReg "%s") [(I64, VInt 4)],
                  ILoad "%u16" I32 (VReg "%u16p"),
                  ICall (Just "%box") Ptr Nothing "@__alloc" [(I64, VInt 4), (I32, VInt 0)],
                  IStore I32 (VReg "%u16") (VReg "%box"),
                  ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%s")],
                  IRet (Just (Ptr, VReg "%box"))
                ]
            }
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
    -- The cap value (134217728 = 2^27) and FNV-1a row tags for
    -- "StringTooLong" / "UnpairedUtf16Surrogate" must stay in sync with
    -- 'maxStringLengthUtf16CodeUnits' in 'stdlib/Prelude.aww'.
    --
    -- Layout of the returned Either cell (identical for both Left arms,
    -- only the row tag differs):
    --   Right s     : malloc(16); [tag=1, ptr=s]
    --   Left  e     : malloc(16); [tag=0, ptr=row]
    --                 row = malloc(16); [rowTag, ptr=inner]   (CRow box)
    --                 inner = malloc(8); [tag=0]              (singleton CCon)
    -- '__getArgs' is the zero-arg runtime helper for
    -- 'BuiltIn.internalGetArgs', called from 'runIO''s 'IOGetArgs' arm.
    -- Walks the cached @argv@ (from '@.cli_argv', length '@.cli_argc')
    -- from index @argc-1@ down to @1@ — index 0 is the program name and
    -- is skipped — validating each element via '__entryArgEither' and
    -- consing it onto a prelude 'List String'. All-or-nothing error
    -- semantics: the first element that fails to decode short-circuits
    -- the whole call with its 'Left'. On success the accumulated list is
    -- wrapped in 'Right'. Walked right-to-left so the cons chain is built
    -- bottom-up without recursion, preserving argv order at the head. An
    -- argv of just @[exe]@ (no user args) yields 'Right Nil'. Per the
    -- no-memoisation principle each call rebuilds the chain; argv is
    -- invariant during execution so repeat calls are deterministically
    -- equal. The loop carries @i@ and the list accumulator in 'alloca'
    -- slots (same idiom as the TCO-lowered user functions).
    -- getArgs: walk cached argv (from '@.cli_argv'/'@.cli_argc') right to
    -- left, skipping index 0 (program name), validating each via
    -- '__entryArgEither' (all-or-nothing — first Left short-circuits) and
    -- consing onto a prelude 'List String'; success → Right list.
    rtGetArgs =
      (<> "\n")
        $ renderFunc
          LFunc
            { lfLinkage = "internal",
              lfRetType = Ptr,
              lfName = "__getArgs",
              lfParams = [],
              lfBody =
                [ ILoad "%argc" I64 (VGlob "@.cli_argc"),
                  ILoad "%argv" Ptr (VGlob "@.cli_argv"),
                  IAlloca "%i.slot" I64 Nothing,
                  IAlloca "%acc.slot" Ptr Nothing,
                  ICall (Just "%nilC") Ptr Nothing "@__alloc" [(I64, VInt 8), (I32, VInt 0)],
                  IConv "%nilC_tag" IntToPtr I64 (ptI ptNil) Ptr,
                  IStore Ptr (VReg "%nilC_tag") (VReg "%nilC"),
                  IStore Ptr (VReg "%nilC") (VReg "%acc.slot"),
                  IStore I64 (VReg "%argc") (VReg "%i.slot"),
                  IBr "getargs_loop",
                  ILabel "getargs_loop",
                  ILoad "%i" I64 (VReg "%i.slot"),
                  IICmp "%at_end" ISle I64 (VReg "%i") (VInt 1),
                  IBrCond (VReg "%at_end") "getargs_done" "getargs_body",
                  ILabel "getargs_body",
                  IBin "%i.next" LSub I64 (VReg "%i") (VInt 1),
                  IStore I64 (VReg "%i.next") (VReg "%i.slot"),
                  IGep "%arg_slot" Ptr (VReg "%argv") [(I64, VReg "%i.next")],
                  ILoad "%arg" Ptr (VReg "%arg_slot"),
                  ICall (Just "%len") I64 Nothing "@strlen" [(Ptr, VReg "%arg")],
                  ICall (Just "%either") Ptr Nothing "@__entryArgEither" [(Ptr, VReg "%arg"), (I64, VReg "%len")],
                  ILoad "%either_tag_ptr" Ptr (VReg "%either"),
                  IConv "%either_tag" PtrToInt Ptr (VReg "%either_tag_ptr") I64,
                  IICmp "%is_left" IEq I64 (VReg "%either_tag") (ptI ptLeft),
                  IBrCond (VReg "%is_left") "getargs_left" "getargs_cons",
                  ILabel "getargs_cons",
                  IGep "%head_slot" Ptr (VReg "%either") [(I32, VInt 1)],
                  ILoad "%head" Ptr (VReg "%head_slot"),
                  ICall Nothing Void Nothing "@__free" [(Ptr, VReg "%either")],
                  ILoad "%acc" Ptr (VReg "%acc.slot"),
                  ICall (Just "%consC") Ptr Nothing "@__alloc" [(I64, VInt 24), (I32, VInt 2)],
                  IConv "%consC_tag" IntToPtr I64 (ptI ptCons) Ptr,
                  IStore Ptr (VReg "%consC_tag") (VReg "%consC"),
                  IGep "%consC_head_slot" Ptr (VReg "%consC") [(I32, VInt 1)],
                  IStore Ptr (VReg "%head") (VReg "%consC_head_slot"),
                  IGep "%consC_tail_slot" Ptr (VReg "%consC") [(I32, VInt 2)],
                  IStore Ptr (VReg "%acc") (VReg "%consC_tail_slot"),
                  IStore Ptr (VReg "%consC") (VReg "%acc.slot"),
                  IBr "getargs_loop",
                  ILabel "getargs_left",
                  IRet (Just (Ptr, VReg "%either")),
                  ILabel "getargs_done",
                  ILoad "%acc.final" Ptr (VReg "%acc.slot"),
                  ICall (Just "%rightC") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%rightC_tag" IntToPtr I64 (ptI ptRight) Ptr,
                  IStore Ptr (VReg "%rightC_tag") (VReg "%rightC"),
                  IGep "%rightC_field" Ptr (VReg "%rightC") [(I32, VInt 1)],
                  IStore Ptr (VReg "%acc.final") (VReg "%rightC_field"),
                  IRet (Just (Ptr, VReg "%rightC"))
                ]
            }
    -- '__readStdin(len_out)' reads fd 0 to EOF into a 'malloc'/'realloc'-
    -- grown buffer (start 4 KiB, double when full), writes the final byte
    -- length through 'len_out', and returns the buffer (caller frees).
    -- Shared by both stdin primitives. Per the POSIX-honest
    -- no-memoisation decision, each call consumes whatever bytes remain
    -- on fd 0; a second call after EOF reads zero bytes.
    -- readStdin(len_out): read fd 0 to EOF into a malloc/realloc-grown
    -- buffer (4 KiB start, double when <4 KiB free), write the byte length
    -- through len_out, return the buffer (caller frees). EOF or error both
    -- stop the loop.
    rtReadStdin =
      (<> "\n")
        $ renderFunc
          LFunc
            { lfLinkage = "internal",
              lfRetType = Ptr,
              lfName = "__readStdin",
              lfParams = [(Ptr, "%len_out")],
              lfBody =
                [ ILabel "entry",
                  IAlloca "%cap_p" I64 (Just 8),
                  IStore I64 (VInt 4096) (VReg "%cap_p"),
                  IAlloca "%len_p" I64 (Just 8),
                  IStore I64 (VInt 0) (VReg "%len_p"),
                  IAlloca "%buf_p" Ptr (Just 8),
                  ICall (Just "%buf0") Ptr Nothing "@malloc" [(I64, VInt 4096)],
                  IStore Ptr (VReg "%buf0") (VReg "%buf_p"),
                  IBr "read_head",
                  ILabel "read_head",
                  ILoad "%cap" I64 (VReg "%cap_p"),
                  ILoad "%len" I64 (VReg "%len_p"),
                  IBin "%remain" LSub I64 (VReg "%cap") (VReg "%len"),
                  IICmp "%need_grow" IUlt I64 (VReg "%remain") (VInt 4096),
                  IBrCond (VReg "%need_grow") "grow" "do_read",
                  ILabel "grow",
                  IBin "%new_cap" LMul I64 (VReg "%cap") (VInt 2),
                  ILoad "%old_buf" Ptr (VReg "%buf_p"),
                  ICall (Just "%new_buf") Ptr Nothing "@realloc" [(Ptr, VReg "%old_buf"), (I64, VReg "%new_cap")],
                  IStore Ptr (VReg "%new_buf") (VReg "%buf_p"),
                  IStore I64 (VReg "%new_cap") (VReg "%cap_p"),
                  IBr "do_read",
                  ILabel "do_read",
                  ILoad "%cap2" I64 (VReg "%cap_p"),
                  ILoad "%len2" I64 (VReg "%len_p"),
                  ILoad "%buf" Ptr (VReg "%buf_p"),
                  IGep "%off_ptr" I8 (VReg "%buf") [(I64, VReg "%len2")],
                  IBin "%remain2" LSub I64 (VReg "%cap2") (VReg "%len2"),
                  ICall (Just "%got") I64 Nothing "@read" [(I32, VInt 0), (Ptr, VReg "%off_ptr"), (I64, VReg "%remain2")],
                  IICmp "%eof" ISle I64 (VReg "%got") (VInt 0),
                  IBrCond (VReg "%eof") "read_done" "accumulate",
                  ILabel "accumulate",
                  ILoad "%len3" I64 (VReg "%len_p"),
                  IBin "%new_len" LAdd I64 (VReg "%len3") (VReg "%got"),
                  IStore I64 (VReg "%new_len") (VReg "%len_p"),
                  IBr "read_head",
                  ILabel "read_done",
                  ILoad "%final_len" I64 (VReg "%len_p"),
                  ILoad "%buf_final" Ptr (VReg "%buf_p"),
                  IStore I64 (VReg "%final_len") (VReg "%len_out"),
                  IRet (Just (Ptr, VReg "%buf_final"))
                ]
            }
    -- '__stdinReadAll' is the zero-arg runtime helper for
    -- 'BuiltIn.internalStdinReadAllString', called from 'runIO''s
    -- 'IOStdinReadAllString' arm. Reads stdin via '__readStdin', then
    -- strict-UTF-8 decodes the bytes via '__stdinDecodeStrict' (which
    -- copies any 'Right' payload into a fresh '__alloc'-ed cell), then
    -- frees the scratch buffer.
    rtStdinReadAll =
      (<> "\n")
        $ renderFunc
          LFunc
            { lfLinkage = "internal",
              lfRetType = Ptr,
              lfName = "__stdinReadAll",
              lfParams = [],
              lfBody =
                [ ILabel "entry",
                  IAlloca "%len_slot" I64 (Just 8),
                  ICall (Just "%buf") Ptr Nothing "@__readStdin" [(Ptr, VReg "%len_slot")],
                  ILoad "%len" I64 (VReg "%len_slot"),
                  ICall (Just "%either") Ptr Nothing "@__stdinDecodeStrict" [(Ptr, VReg "%buf"), (I64, VReg "%len")],
                  ICall Nothing Void Nothing "@free" [(Ptr, VReg "%buf")],
                  IRet (Just (Ptr, VReg "%either"))
                ]
            }
    -- '__stdinReadAllBytes' is the zero-arg runtime helper for
    -- 'BuiltIn.internalStdinReadAllBytes', called from 'runIO''s
    -- 'IOStdinReadAllBytes' arm. Reads stdin via '__readStdin' and builds
    -- an Awsum 'List UInt8' (each byte boxed as a 1-byte cell), folded
    -- right-to-left so the cons chain needs no recursion. No decode, no
    -- error row.
    rtStdinReadAllBytes =
      (<> "\n")
        $ renderFunc
          LFunc
            { lfLinkage = "internal",
              lfRetType = Ptr,
              lfName = "__stdinReadAllBytes",
              lfParams = [],
              lfBody =
                [ ILabel "entry",
                  IAlloca "%len_slot" I64 (Just 8),
                  ICall (Just "%buf") Ptr Nothing "@__readStdin" [(Ptr, VReg "%len_slot")],
                  ILoad "%len" I64 (VReg "%len_slot"),
                  IAlloca "%i_p" I64 (Just 8),
                  IAlloca "%acc_p" Ptr (Just 8),
                  ICall (Just "%nilC") Ptr Nothing "@__alloc" [(I64, VInt 8), (I32, VInt 0)],
                  IConv "%nilC_tag" IntToPtr I64 (ptI ptNil) Ptr,
                  IStore Ptr (VReg "%nilC_tag") (VReg "%nilC"),
                  IStore Ptr (VReg "%nilC") (VReg "%acc_p"),
                  IStore I64 (VReg "%len") (VReg "%i_p"),
                  IBr "bytes_loop",
                  ILabel "bytes_loop",
                  ILoad "%i" I64 (VReg "%i_p"),
                  IICmp "%at_start" IEq I64 (VReg "%i") (VInt 0),
                  IBrCond (VReg "%at_start") "bytes_done" "bytes_body",
                  ILabel "bytes_body",
                  IBin "%i_next" LSub I64 (VReg "%i") (VInt 1),
                  IStore I64 (VReg "%i_next") (VReg "%i_p"),
                  IGep "%byte_ptr" I8 (VReg "%buf") [(I64, VReg "%i_next")],
                  ILoad "%byte" I8 (VReg "%byte_ptr"),
                  ICall (Just "%u8") Ptr Nothing "@__alloc" [(I64, VInt 1), (I32, VInt 0)],
                  IStore I8 (VReg "%byte") (VReg "%u8"),
                  ILoad "%acc" Ptr (VReg "%acc_p"),
                  ICall (Just "%consC") Ptr Nothing "@__alloc" [(I64, VInt 24), (I32, VInt 2)],
                  IConv "%consC_tag" IntToPtr I64 (ptI ptCons) Ptr,
                  IStore Ptr (VReg "%consC_tag") (VReg "%consC"),
                  IGep "%consC_head" Ptr (VReg "%consC") [(I32, VInt 1)],
                  IStore Ptr (VReg "%u8") (VReg "%consC_head"),
                  IGep "%consC_tail" Ptr (VReg "%consC") [(I32, VInt 2)],
                  IStore Ptr (VReg "%acc") (VReg "%consC_tail"),
                  IStore Ptr (VReg "%consC") (VReg "%acc_p"),
                  IBr "bytes_loop",
                  ILabel "bytes_done",
                  ICall Nothing Void Nothing "@free" [(Ptr, VReg "%buf")],
                  ILoad "%acc_final" Ptr (VReg "%acc_p"),
                  IRet (Just (Ptr, VReg "%acc_final"))
                ]
            }
    -- '__stdinDecodeStrict(arg, len)' validates 'arg[0..len)' as
    -- well-formed UTF-8 (RFC 3629 / Unicode Table 3-7) and returns
    -- 'Either (StringTooLong | InvalidUtf8) String'. A single
    -- left-to-right pass: each leading byte selects a 1/2/3/4-byte
    -- sequence whose continuation bytes and overlong/surrogate/range
    -- constraints are all checked; the first malformation returns
    -- 'Left InvalidUtf8'. A fully-valid scan then length-caps on the
    -- UTF-16 code-unit count ('Left StringTooLong' over 2^27), else
    -- copies the bytes verbatim into a length-prefixed 'Right' cell.
    -- 'InvalidUtf8' takes priority over 'StringTooLong': the cap is only
    -- consulted after the whole input has been confirmed well-formed,
    -- matching the fatal host decoders the other backends use.
    -- Strict UTF-8 validator (RFC 3629 / Unicode Table 3-7): one
    -- left-to-right pass, each leading byte selecting a 1/2/3/4-byte
    -- sequence with its continuation/overlong/surrogate/range checks;
    -- first malformation → Left InvalidUtf8. A clean scan then caps the
    -- UTF-16 count (Left StringTooLong over 2^27) else copies the bytes
    -- into a length-prefixed Right cell. InvalidUtf8 takes priority.
    rtStdinDecodeStrict =
      (<> "\n")
        $ renderFunc
          LFunc
            { lfLinkage = "internal",
              lfRetType = Ptr,
              lfName = "__stdinDecodeStrict",
              lfParams = [(Ptr, "%arg"), (I64, "%len")],
              lfBody =
                [ ILabel "entry",
                  IAlloca "%i_p" I64 (Just 8),
                  IStore I64 (VInt 0) (VReg "%i_p"),
                  IAlloca "%n_p" I64 (Just 8),
                  IStore I64 (VInt 0) (VReg "%n_p"),
                  IBr "head",
                  ILabel "head",
                  ILoad "%i" I64 (VReg "%i_p"),
                  IICmp "%done" IUge I64 (VReg "%i") (VReg "%len"),
                  IBrCond (VReg "%done") "valid_end" "body",
                  ILabel "body",
                  IGep "%b0p" I8 (VReg "%arg") [(I64, VReg "%i")],
                  ILoad "%b0" I8 (VReg "%b0p"),
                  IConv "%b0z" Zext I8 (VReg "%b0") I32,
                  IICmp "%is_ascii" IUlt I32 (VReg "%b0z") (VInt 128),
                  IBrCond (VReg "%is_ascii") "one_byte" "chk_lead",
                  ILabel "one_byte",
                  ILoad "%n_o" I64 (VReg "%n_p"),
                  IBin "%n_o1" LAdd I64 (VReg "%n_o") (VInt 1),
                  IStore I64 (VReg "%n_o1") (VReg "%n_p"),
                  IBin "%i_o1" LAdd I64 (VReg "%i") (VInt 1),
                  IStore I64 (VReg "%i_o1") (VReg "%i_p"),
                  IBr "head",
                  ILabel "chk_lead",
                  IICmp "%ge_c2" IUge I32 (VReg "%b0z") (VInt 194),
                  IBrCond (VReg "%ge_c2") "chk2" "invalid",
                  ILabel "chk2",
                  IICmp "%lt_e0" IUlt I32 (VReg "%b0z") (VInt 224),
                  IBrCond (VReg "%lt_e0") "two_byte" "chk3",
                  ILabel "chk3",
                  IICmp "%lt_f0" IUlt I32 (VReg "%b0z") (VInt 240),
                  IBrCond (VReg "%lt_f0") "three_byte" "chk4",
                  ILabel "chk4",
                  IICmp "%lt_f5" IUlt I32 (VReg "%b0z") (VInt 245),
                  IBrCond (VReg "%lt_f5") "four_byte" "invalid",
                  ILabel "two_byte",
                  IBin "%i_2a" LAdd I64 (VReg "%i") (VInt 1),
                  IICmp "%trunc2" IUge I64 (VReg "%i_2a") (VReg "%len"),
                  IBrCond (VReg "%trunc2") "invalid" "two_cont",
                  ILabel "two_cont",
                  IGep "%b1_2p" I8 (VReg "%arg") [(I64, VReg "%i_2a")],
                  ILoad "%b1_2" I8 (VReg "%b1_2p"),
                  IConv "%b1_2z" Zext I8 (VReg "%b1_2") I32,
                  IBin "%b1_2m" LAnd I32 (VReg "%b1_2z") (VInt 192),
                  IICmp "%b1_2ok" IEq I32 (VReg "%b1_2m") (VInt 128),
                  IBrCond (VReg "%b1_2ok") "two_ok" "invalid",
                  ILabel "two_ok",
                  ILoad "%n_2" I64 (VReg "%n_p"),
                  IBin "%n_2a" LAdd I64 (VReg "%n_2") (VInt 1),
                  IStore I64 (VReg "%n_2a") (VReg "%n_p"),
                  IBin "%i_2b" LAdd I64 (VReg "%i") (VInt 2),
                  IStore I64 (VReg "%i_2b") (VReg "%i_p"),
                  IBr "head",
                  ILabel "three_byte",
                  IBin "%i_3c" LAdd I64 (VReg "%i") (VInt 2),
                  IICmp "%trunc3" IUge I64 (VReg "%i_3c") (VReg "%len"),
                  IBrCond (VReg "%trunc3") "invalid" "three_b1",
                  ILabel "three_b1",
                  IBin "%i_3b1" LAdd I64 (VReg "%i") (VInt 1),
                  IGep "%b1_3p" I8 (VReg "%arg") [(I64, VReg "%i_3b1")],
                  ILoad "%b1_3" I8 (VReg "%b1_3p"),
                  IConv "%b1_3z" Zext I8 (VReg "%b1_3") I32,
                  IBin "%b1_3m" LAnd I32 (VReg "%b1_3z") (VInt 192),
                  IICmp "%b1_3ok" IEq I32 (VReg "%b1_3m") (VInt 128),
                  IBrCond (VReg "%b1_3ok") "three_b2" "invalid",
                  ILabel "three_b2",
                  IGep "%b2_3p" I8 (VReg "%arg") [(I64, VReg "%i_3c")],
                  ILoad "%b2_3" I8 (VReg "%b2_3p"),
                  IConv "%b2_3z" Zext I8 (VReg "%b2_3") I32,
                  IBin "%b2_3m" LAnd I32 (VReg "%b2_3z") (VInt 192),
                  IICmp "%b2_3ok" IEq I32 (VReg "%b2_3m") (VInt 128),
                  IBrCond (VReg "%b2_3ok") "three_range" "invalid",
                  ILabel "three_range",
                  IICmp "%is_e0" IEq I32 (VReg "%b0z") (VInt 224),
                  IICmp "%b1_lt_a0" IUlt I32 (VReg "%b1_3z") (VInt 160),
                  IBin "%e0_overlong" LAnd I1 (VReg "%is_e0") (VReg "%b1_lt_a0"),
                  IBrCond (VReg "%e0_overlong") "invalid" "three_ed",
                  ILabel "three_ed",
                  IICmp "%is_ed" IEq I32 (VReg "%b0z") (VInt 237),
                  IICmp "%b1_ge_a0" IUge I32 (VReg "%b1_3z") (VInt 160),
                  IBin "%ed_surr" LAnd I1 (VReg "%is_ed") (VReg "%b1_ge_a0"),
                  IBrCond (VReg "%ed_surr") "invalid" "three_ok",
                  ILabel "three_ok",
                  ILoad "%n_3" I64 (VReg "%n_p"),
                  IBin "%n_3a" LAdd I64 (VReg "%n_3") (VInt 1),
                  IStore I64 (VReg "%n_3a") (VReg "%n_p"),
                  IBin "%i_3d" LAdd I64 (VReg "%i") (VInt 3),
                  IStore I64 (VReg "%i_3d") (VReg "%i_p"),
                  IBr "head",
                  ILabel "four_byte",
                  IBin "%i_4c" LAdd I64 (VReg "%i") (VInt 3),
                  IICmp "%trunc4" IUge I64 (VReg "%i_4c") (VReg "%len"),
                  IBrCond (VReg "%trunc4") "invalid" "four_b1",
                  ILabel "four_b1",
                  IBin "%i_4b1" LAdd I64 (VReg "%i") (VInt 1),
                  IGep "%b1_4p" I8 (VReg "%arg") [(I64, VReg "%i_4b1")],
                  ILoad "%b1_4" I8 (VReg "%b1_4p"),
                  IConv "%b1_4z" Zext I8 (VReg "%b1_4") I32,
                  IBin "%b1_4m" LAnd I32 (VReg "%b1_4z") (VInt 192),
                  IICmp "%b1_4ok" IEq I32 (VReg "%b1_4m") (VInt 128),
                  IBrCond (VReg "%b1_4ok") "four_b2" "invalid",
                  ILabel "four_b2",
                  IBin "%i_4b2" LAdd I64 (VReg "%i") (VInt 2),
                  IGep "%b2_4p" I8 (VReg "%arg") [(I64, VReg "%i_4b2")],
                  ILoad "%b2_4" I8 (VReg "%b2_4p"),
                  IConv "%b2_4z" Zext I8 (VReg "%b2_4") I32,
                  IBin "%b2_4m" LAnd I32 (VReg "%b2_4z") (VInt 192),
                  IICmp "%b2_4ok" IEq I32 (VReg "%b2_4m") (VInt 128),
                  IBrCond (VReg "%b2_4ok") "four_b3" "invalid",
                  ILabel "four_b3",
                  IGep "%b3_4p" I8 (VReg "%arg") [(I64, VReg "%i_4c")],
                  ILoad "%b3_4" I8 (VReg "%b3_4p"),
                  IConv "%b3_4z" Zext I8 (VReg "%b3_4") I32,
                  IBin "%b3_4m" LAnd I32 (VReg "%b3_4z") (VInt 192),
                  IICmp "%b3_4ok" IEq I32 (VReg "%b3_4m") (VInt 128),
                  IBrCond (VReg "%b3_4ok") "four_range" "invalid",
                  ILabel "four_range",
                  IICmp "%is_f0" IEq I32 (VReg "%b0z") (VInt 240),
                  IICmp "%b1_lt_90" IUlt I32 (VReg "%b1_4z") (VInt 144),
                  IBin "%f0_overlong" LAnd I1 (VReg "%is_f0") (VReg "%b1_lt_90"),
                  IBrCond (VReg "%f0_overlong") "invalid" "four_f4",
                  ILabel "four_f4",
                  IICmp "%is_f4" IEq I32 (VReg "%b0z") (VInt 244),
                  IICmp "%b1_ge_90" IUge I32 (VReg "%b1_4z") (VInt 144),
                  IBin "%f4_over" LAnd I1 (VReg "%is_f4") (VReg "%b1_ge_90"),
                  IBrCond (VReg "%f4_over") "invalid" "four_ok",
                  ILabel "four_ok",
                  ILoad "%n_4" I64 (VReg "%n_p"),
                  IBin "%n_4a" LAdd I64 (VReg "%n_4") (VInt 2),
                  IStore I64 (VReg "%n_4a") (VReg "%n_p"),
                  IBin "%i_4d" LAdd I64 (VReg "%i") (VInt 4),
                  IStore I64 (VReg "%i_4d") (VReg "%i_p"),
                  IBr "head",
                  ILabel "valid_end",
                  ILoad "%n_final" I64 (VReg "%n_p"),
                  IICmp "%over" IUgt I64 (VReg "%n_final") (VInt 134217728),
                  IBrCond (VReg "%over") "too_long" "fits",
                  ILabel "fits",
                  IConv "%byte_count" Trunc I64 (VReg "%len") I32,
                  IBin "%alloc_size" LAdd I64 (VReg "%len") (VInt 8),
                  ICall (Just "%wrapped") Ptr Nothing "@__alloc" [(I64, VReg "%alloc_size"), (I32, VInt 0)],
                  IStore I32 (VReg "%byte_count") (VReg "%wrapped"),
                  IConv "%n_final32" Trunc I64 (VReg "%n_final") I32,
                  IGep "%wrapped_u16p" I8 (VReg "%wrapped") [(I64, VInt 4)],
                  IStore I32 (VReg "%n_final32") (VReg "%wrapped_u16p"),
                  IGep "%wrapped_payload" I8 (VReg "%wrapped") [(I64, VInt 8)],
                  ICall Nothing Ptr Nothing "@memcpy" [(Ptr, VReg "%wrapped_payload"), (Ptr, VReg "%arg"), (I64, VReg "%len")],
                  ICall (Just "%right") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%right_tag" IntToPtr I64 (ptI ptRight) Ptr,
                  IStore Ptr (VReg "%right_tag") (VReg "%right"),
                  IGep "%right_f" Ptr (VReg "%right") [(I32, VInt 1)],
                  IStore Ptr (VReg "%wrapped") (VReg "%right_f"),
                  IRet (Just (Ptr, VReg "%right")),
                  ILabel "too_long",
                  ICall (Just "%tl_inner") Ptr Nothing "@__alloc" [(I64, VInt 8), (I32, VInt 0)],
                  IConv "%tl_inner_tag" IntToPtr I64 (ptI ptStringTooLong) Ptr,
                  IStore Ptr (VReg "%tl_inner_tag") (VReg "%tl_inner"),
                  ICall (Just "%tl_row") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%tl_row_tag" IntToPtr I64 (tagOf "StringTooLong") Ptr,
                  IStore Ptr (VReg "%tl_row_tag") (VReg "%tl_row"),
                  IGep "%tl_row_f" Ptr (VReg "%tl_row") [(I32, VInt 1)],
                  IStore Ptr (VReg "%tl_inner") (VReg "%tl_row_f"),
                  ICall (Just "%tl_left") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%tl_left_tag" IntToPtr I64 (ptI ptLeft) Ptr,
                  IStore Ptr (VReg "%tl_left_tag") (VReg "%tl_left"),
                  IGep "%tl_left_f" Ptr (VReg "%tl_left") [(I32, VInt 1)],
                  IStore Ptr (VReg "%tl_row") (VReg "%tl_left_f"),
                  IRet (Just (Ptr, VReg "%tl_left")),
                  ILabel "invalid",
                  ICall (Just "%iu_inner") Ptr Nothing "@__alloc" [(I64, VInt 8), (I32, VInt 0)],
                  IConv "%iu_inner_tag" IntToPtr I64 (ptI ptInvalidUtf8) Ptr,
                  IStore Ptr (VReg "%iu_inner_tag") (VReg "%iu_inner"),
                  ICall (Just "%iu_row") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%iu_row_tag" IntToPtr I64 (tagOf "InvalidUtf8") Ptr,
                  IStore Ptr (VReg "%iu_row_tag") (VReg "%iu_row"),
                  IGep "%iu_row_f" Ptr (VReg "%iu_row") [(I32, VInt 1)],
                  IStore Ptr (VReg "%iu_inner") (VReg "%iu_row_f"),
                  ICall (Just "%iu_left") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%iu_left_tag" IntToPtr I64 (ptI ptLeft) Ptr,
                  IStore Ptr (VReg "%iu_left_tag") (VReg "%iu_left"),
                  IGep "%iu_left_f" Ptr (VReg "%iu_left") [(I32, VInt 1)],
                  IStore Ptr (VReg "%iu_row") (VReg "%iu_left_f"),
                  IRet (Just (Ptr, VReg "%iu_left"))
                ]
            }
    -- entryArgEither: validate one host-decoded argv string. Single pass
    -- counting UTF-16 code units (with cap short-circuit) and stickily
    -- flagging any 0xED-led surrogate-encoded triplet (forbidden by RFC
    -- 3629). On exit, StringTooLong (cap has priority) → Left, else
    -- UnpairedUtf16Surrogate → Left, else copy to a Right length-prefixed
    -- string. Peeks @arg[i+1]@ — caller guarantees @arg[len]@ is readable.
    rtEntryArgEither =
      (<> "\n")
        $ renderFunc
          LFunc
            { lfLinkage = "internal",
              lfRetType = Ptr,
              lfName = "__entryArgEither",
              lfParams = [(Ptr, "%arg"), (I64, "%len")],
              lfBody =
                [ ILabel "entry",
                  IAlloca "%i_p" I64 (Just 8),
                  IStore I64 (VInt 0) (VReg "%i_p"),
                  IAlloca "%n_p" I32 (Just 4),
                  IStore I32 (VInt 0) (VReg "%n_p"),
                  IAlloca "%surr_p" I32 (Just 4),
                  IStore I32 (VInt 0) (VReg "%surr_p"),
                  IBr "head",
                  ILabel "head",
                  ILoad "%i" I64 (VReg "%i_p"),
                  IICmp "%done" IUge I64 (VReg "%i") (VReg "%len"),
                  IBrCond (VReg "%done") "scan_done" "body",
                  ILabel "body",
                  IGep "%bp" I8 (VReg "%arg") [(I64, VReg "%i")],
                  ILoad "%b" I8 (VReg "%bp"),
                  IConv "%bz" Zext I8 (VReg "%b") I32,
                  IBin "%top2" LAnd I32 (VReg "%bz") (VInt 192),
                  IICmp "%is_cont" IEq I32 (VReg "%top2") (VInt 128),
                  IBrCond (VReg "%is_cont") "step" "surrogate_check",
                  ILabel "surrogate_check",
                  IICmp "%is_ED" IEq I32 (VReg "%bz") (VInt 237),
                  IBrCond (VReg "%is_ED") "peek_next" "check4",
                  ILabel "peek_next",
                  IBin "%i_next" LAdd I64 (VReg "%i") (VInt 1),
                  IGep "%bp_next" I8 (VReg "%arg") [(I64, VReg "%i_next")],
                  ILoad "%nxt" I8 (VReg "%bp_next"),
                  IConv "%nxt_z" Zext I8 (VReg "%nxt") I32,
                  IBin "%nxt_top3" LAnd I32 (VReg "%nxt_z") (VInt 224),
                  IICmp "%is_surr" IEq I32 (VReg "%nxt_top3") (VInt 160),
                  IBrCond (VReg "%is_surr") "set_surr" "check4",
                  ILabel "set_surr",
                  IStore I32 (VInt 1) (VReg "%surr_p"),
                  IBr "check4",
                  ILabel "check4",
                  IBin "%top5" LAnd I32 (VReg "%bz") (VInt 248),
                  IICmp "%is_4" IEq I32 (VReg "%top5") (VInt 240),
                  IBrCond (VReg "%is_4") "add2" "add1",
                  ILabel "add2",
                  ILoad "%n2" I32 (VReg "%n_p"),
                  IBin "%n2_new" LAdd I32 (VReg "%n2") (VInt 2),
                  IStore I32 (VReg "%n2_new") (VReg "%n_p"),
                  IICmp "%over2" IUgt I32 (VReg "%n2_new") (VInt 134217728),
                  IBrCond (VReg "%over2") "scan_done" "step",
                  ILabel "add1",
                  ILoad "%n1" I32 (VReg "%n_p"),
                  IBin "%n1_new" LAdd I32 (VReg "%n1") (VInt 1),
                  IStore I32 (VReg "%n1_new") (VReg "%n_p"),
                  IICmp "%over1" IUgt I32 (VReg "%n1_new") (VInt 134217728),
                  IBrCond (VReg "%over1") "scan_done" "step",
                  ILabel "step",
                  IBin "%i1" LAdd I64 (VReg "%i") (VInt 1),
                  IStore I64 (VReg "%i1") (VReg "%i_p"),
                  IBr "head",
                  ILabel "scan_done",
                  ILoad "%n_final" I32 (VReg "%n_p"),
                  IICmp "%over_final" IUgt I32 (VReg "%n_final") (VInt 134217728),
                  IBrCond (VReg "%over_final") "too_long" "check_surr",
                  ILabel "check_surr",
                  ILoad "%surr_final" I32 (VReg "%surr_p"),
                  IICmp "%is_surr_set" INe I32 (VReg "%surr_final") (VInt 0),
                  IBrCond (VReg "%is_surr_set") "unpaired" "fits",
                  ILabel "fits",
                  ILoad "%byte_count_64" I64 (VReg "%i_p"),
                  IConv "%byte_count_32" Trunc I64 (VReg "%byte_count_64") I32,
                  IBin "%alloc_size_64" LAdd I64 (VReg "%byte_count_64") (VInt 8),
                  ICall (Just "%wrapped") Ptr Nothing "@__alloc" [(I64, VReg "%alloc_size_64"), (I32, VInt 0)],
                  IStore I32 (VReg "%byte_count_32") (VReg "%wrapped"),
                  IGep "%wrapped_u16p" I8 (VReg "%wrapped") [(I64, VInt 4)],
                  IStore I32 (VReg "%n_final") (VReg "%wrapped_u16p"),
                  IGep "%wrapped_payload" I8 (VReg "%wrapped") [(I64, VInt 8)],
                  ICall Nothing Ptr Nothing "@memcpy" [(Ptr, VReg "%wrapped_payload"), (Ptr, VReg "%arg"), (I64, VReg "%byte_count_64")],
                  ICall (Just "%right") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%right_tag" IntToPtr I64 (ptI ptRight) Ptr,
                  IStore Ptr (VReg "%right_tag") (VReg "%right"),
                  IGep "%right_f" Ptr (VReg "%right") [(I32, VInt 1)],
                  IStore Ptr (VReg "%wrapped") (VReg "%right_f"),
                  IRet (Just (Ptr, VReg "%right")),
                  ILabel "too_long",
                  ICall (Just "%tl_inner") Ptr Nothing "@__alloc" [(I64, VInt 8), (I32, VInt 0)],
                  IConv "%tl_inner_tag" IntToPtr I64 (ptI ptStringTooLong) Ptr,
                  IStore Ptr (VReg "%tl_inner_tag") (VReg "%tl_inner"),
                  ICall (Just "%tl_row") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%tl_row_tag" IntToPtr I64 (tagOf "StringTooLong") Ptr,
                  IStore Ptr (VReg "%tl_row_tag") (VReg "%tl_row"),
                  IGep "%tl_row_f" Ptr (VReg "%tl_row") [(I32, VInt 1)],
                  IStore Ptr (VReg "%tl_inner") (VReg "%tl_row_f"),
                  ICall (Just "%tl_left") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%tl_left_tag" IntToPtr I64 (ptI ptLeft) Ptr,
                  IStore Ptr (VReg "%tl_left_tag") (VReg "%tl_left"),
                  IGep "%tl_left_f" Ptr (VReg "%tl_left") [(I32, VInt 1)],
                  IStore Ptr (VReg "%tl_row") (VReg "%tl_left_f"),
                  IRet (Just (Ptr, VReg "%tl_left")),
                  ILabel "unpaired",
                  ICall (Just "%us_inner") Ptr Nothing "@__alloc" [(I64, VInt 8), (I32, VInt 0)],
                  IConv "%us_inner_tag" IntToPtr I64 (ptI ptUnpairedUtf16Surrogate) Ptr,
                  IStore Ptr (VReg "%us_inner_tag") (VReg "%us_inner"),
                  ICall (Just "%us_row") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%us_row_tag" IntToPtr I64 (tagOf "UnpairedUtf16Surrogate") Ptr,
                  IStore Ptr (VReg "%us_row_tag") (VReg "%us_row"),
                  IGep "%us_row_f" Ptr (VReg "%us_row") [(I32, VInt 1)],
                  IStore Ptr (VReg "%us_inner") (VReg "%us_row_f"),
                  ICall (Just "%us_left") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%us_left_tag" IntToPtr I64 (ptI ptLeft) Ptr,
                  IStore Ptr (VReg "%us_left_tag") (VReg "%us_left"),
                  IGep "%us_left_f" Ptr (VReg "%us_left") [(I32, VInt 1)],
                  IStore Ptr (VReg "%us_row") (VReg "%us_left_f"),
                  IRet (Just (Ptr, VReg "%us_left"))
                ]
            }
    -- parseUInt32: no sign; i64 accumulator (so the unmasked running value
    -- and the @> 4294967295@ check are exact), trunc to i32 on the ok path.
    rtParseUInt32 =
      (<> "\n")
        $ renderFunc
          LFunc
            { lfLinkage = "internal",
              lfRetType = Ptr,
              lfName = "__parseUInt32",
              lfParams = [(Ptr, "%s")],
              lfBody =
                [ ILabel "entry",
                  IAlloca "%i_alloca" I64 (Just 8),
                  IStore I64 (VInt 0) (VReg "%i_alloca"),
                  IAlloca "%acc_alloca" I64 (Just 8),
                  IStore I64 (VInt 0) (VReg "%acc_alloca"),
                  ILoad "%len32" I32 (VReg "%s"),
                  IConv "%len" Zext I32 (VReg "%len32") I64,
                  IGep "%payload" I8 (VReg "%s") [(I64, VInt 8)],
                  IICmp "%is_empty" IEq I64 (VReg "%len") (VInt 0),
                  IBrCond (VReg "%is_empty") "fail" "loop_head",
                  ILabel "loop_head",
                  ILoad "%i" I64 (VReg "%i_alloca"),
                  ILoad "%acc" I64 (VReg "%acc_alloca"),
                  IICmp "%cond" IUlt I64 (VReg "%i") (VReg "%len"),
                  IBrCond (VReg "%cond") "body" "ok",
                  ILabel "body",
                  IGep "%ptr_c" I8 (VReg "%payload") [(I64, VReg "%i")],
                  ILoad "%c" I8 (VReg "%ptr_c"),
                  IConv "%c_i32" Zext I8 (VReg "%c") I32,
                  IICmp "%low" IUlt I32 (VReg "%c_i32") (VInt 48),
                  IICmp "%high" IUgt I32 (VReg "%c_i32") (VInt 57),
                  IBin "%bad" LOr I1 (VReg "%low") (VReg "%high"),
                  IBrCond (VReg "%bad") "fail" "parse",
                  ILabel "parse",
                  IBin "%d" LSub I32 (VReg "%c_i32") (VInt 48),
                  IConv "%d_i64" Zext I32 (VReg "%d") I64,
                  IBin "%x10" LMul I64 (VReg "%acc") (VInt 10),
                  IBin "%acc_next" LAdd I64 (VReg "%x10") (VReg "%d_i64"),
                  IICmp "%big" IUgt I64 (VReg "%acc_next") (VInt 4294967295),
                  IBrCond (VReg "%big") "fail" "body_end",
                  ILabel "body_end",
                  IStore I64 (VReg "%acc_next") (VReg "%acc_alloca"),
                  IBin "%i_next" LAdd I64 (VReg "%i") (VInt 1),
                  IStore I64 (VReg "%i_next") (VReg "%i_alloca"),
                  IBr "loop_head",
                  ILabel "ok",
                  IConv "%result_i32" Trunc I64 (VReg "%acc") I32,
                  ICall (Just "%box") Ptr Nothing "@__alloc" [(I64, VInt 4), (I32, VInt 0)],
                  IStore I32 (VReg "%result_i32") (VReg "%box"),
                  ICall (Just "%right") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%right_tag" IntToPtr I64 (ptI ptRight) Ptr,
                  IStore Ptr (VReg "%right_tag") (VReg "%right"),
                  IGep "%right_f" Ptr (VReg "%right") [(I32, VInt 1)],
                  IStore Ptr (VReg "%box") (VReg "%right_f"),
                  IBr "join",
                  ILabel "fail",
                  ICall (Just "%pe") Ptr Nothing "@__alloc" [(I64, VInt 8), (I32, VInt 0)],
                  IConv "%pe_tag" IntToPtr I64 (ptI ptParseError) Ptr,
                  IStore Ptr (VReg "%pe_tag") (VReg "%pe"),
                  ICall (Just "%left") Ptr Nothing "@__alloc" [(I64, VInt 16), (I32, VInt 1)],
                  IConv "%left_tag" IntToPtr I64 (ptI ptLeft) Ptr,
                  IStore Ptr (VReg "%left_tag") (VReg "%left"),
                  IGep "%left_f" Ptr (VReg "%left") [(I32, VInt 1)],
                  IStore Ptr (VReg "%pe") (VReg "%left_f"),
                  IBr "join",
                  ILabel "join",
                  IPhi "%res" Ptr [(VReg "%right", "ok"), (VReg "%left", "fail")],
                  ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg "%s")],
                  IRet (Just (Ptr, VReg "%res"))
                ]
            }

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
footer :: LLVMHost -> Set Name -> Text
footer host builtIns = case host of
  LLVMPosix -> footerPosix builtIns
  LLVMWindows -> footerWindows builtIns

footerPosix :: Set Name -> Text
footerPosix builtIns =
  "\n" <> renderFunc mainFn <> "\n"
  where
    mainFn =
      LFunc
        { lfLinkage = "",
          lfRetType = I32,
          lfName = "main",
          lfParams = [(I32, "%argc"), (Ptr, "%argv")],
          lfBody = argvCache <> ioHandoff
        }
    -- Cache @argc@/@argv@ for 'BuiltIn.internalGetArgs' (called from
    -- 'runIO''s 'IOGetArgs' arm). 'main' itself takes no arguments (its
    -- signature is 'IO Never Unit'); user code that wants the argv reads
    -- it through 'IO.Args.getArgs', which lowers to the 'IOGetArgs'
    -- constructor and goes through '__getArgs' (which walks the cached
    -- array) when 'runIO' walks the IO tree. POSIX @argv@ is already an
    -- array of NUL-terminated UTF-8 C-strings, so no conversion is needed;
    -- argv is invariant for the lifetime of the process, so one store at
    -- entry is enough. Gated on 'internalGetArgs' — when the program never
    -- reads argv, the '@.cli_*' globals aren't declared and the stores
    -- would dangle.
    argvCache
      | Set.member "internalGetArgs" builtIns =
          [ IConv "%argc64" Sext I32 (VReg "%argc") I64,
            IStore I64 (VReg "%argc64") (VGlob "@.cli_argc"),
            IStore Ptr (VReg "%argv") (VGlob "@.cli_argv")
          ]
      | otherwise = []
    -- v_main is a zero-arg value (CValDef) that builds the IO tree;
    -- 'runIO' walks it to execute the effects. 'runIO' is a regular
    -- Awsum function emitted via the standard CFunDef path, so it
    -- goes through TCO and ends up as a bounded-stack loop. The IO
    -- value itself is a heap-allocated ptr-tagged ADT cell, same
    -- shape as user ADTs.
    ioHandoff =
      [ ICall (Just "%io") Ptr Nothing "@v_main" [],
        ICall Nothing Ptr Nothing "@v_runIO" [(Ptr, VReg "%io")],
        IRet (Just (I32, VInt 0))
      ]

-- | Windows entry: ignore the POSIX-shape @argc@/@argv@ that MSVCRT
--   hands us (those are ANSI-code-page-mangled), and re-fetch the
--   command line through @GetCommandLineW@ + @CommandLineToArgvW@,
--   then convert every @argv[i]@ from UTF-16 to UTF-8 with
--   @WideCharToMultiByte (CP_UTF8)@ into a fresh array of UTF-8
--   C-strings. That array takes the place the POSIX path's @argv@
--   fills, so '__getArgs' walks both hosts uniformly.
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
footerWindows :: Set Name -> Text
footerWindows builtIns =
  unlines $ declares <> ["", renderFunc mainFn]
  where
    usesArgs = Set.member "internalGetArgs" builtIns
    -- '_setmode' is always declared (the entry forces fd 0/1 into binary
    -- mode below). The argv-construction imports are only needed when the
    -- program reads argv (see the gated 'convBlock').
    declares =
      ["", renderDecl (LDecl I32 "_setmode" [I32, I32] False)]
        <> if usesArgs
          then
            [ renderDecl (LDecl Ptr "GetCommandLineW" [] False),
              renderDecl (LDecl Ptr "CommandLineToArgvW" [Ptr, Ptr] False),
              renderDecl (LDecl I32 "WideCharToMultiByte" [I32, I32, Ptr, I32, Ptr, I32, Ptr, Ptr] False)
            ]
          else []
    mainFn =
      LFunc
        { lfLinkage = "",
          lfRetType = I32,
          lfName = "main",
          lfParams = [(I32, "%argc_posix"), (Ptr, "%argv_posix")],
          lfBody = setmodeBody <> convBlock <> ioHandoff
        }
    setmodeBody =
      [ ILabel "entry",
        ICall Nothing I32 Nothing "@_setmode" [(I32, VInt 1), (I32, VInt 32768)],
        ICall Nothing I32 Nothing "@_setmode" [(I32, VInt 0), (I32, VInt 32768)]
      ]
    -- Re-fetch the command line and build a UTF-8 argv array for
    -- 'BuiltIn.internalGetArgs'; gated so a Windows program that never
    -- reads argv emits neither this block, the '@.cli_*' globals, nor
    -- '@.empty'. '_setmode' (above) and the 'v_main'/'runIO' handoff
    -- (below) stay unconditional.
    convBlock
      | usesArgs =
          [ ICall (Just "%cmdline") Ptr Nothing "@GetCommandLineW" [],
            IAlloca "%argc_slot" I32 Nothing,
            ICall (Just "%argv_w") Ptr Nothing "@CommandLineToArgvW" [(Ptr, VReg "%cmdline"), (Ptr, VReg "%argc_slot")],
            ILoad "%argc_w" I32 (VReg "%argc_slot"),
            IConv "%argc_w64" Sext I32 (VReg "%argc_w") I64,
            IStore I64 (VReg "%argc_w64") (VGlob "@.cli_argc"),
            -- Allocate a UTF-8 ptr array of length @argc_w@ (8 bytes/slot) and
            -- publish it as '@.cli_argv'. Index 0 (the program name) is left
            -- as the empty-string pointer — '__getArgs' never reads it — and
            -- indices 1.. are filled with per-arg UTF-8 conversions below.
            IBin "%arr_bytes" LMul I64 (VReg "%argc_w64") (VInt 8),
            ICall (Just "%u8arr") Ptr Nothing "@__alloc" [(I64, VReg "%arr_bytes"), (I32, VInt 0)],
            IStore Ptr (VReg "%u8arr") (VGlob "@.cli_argv"),
            IStore Ptr (VConstGep "@.empty" 12) (VReg "%u8arr"),
            IAlloca "%ci.slot" I64 Nothing,
            IStore I64 (VInt 1) (VReg "%ci.slot"),
            IBr "conv_loop",
            ILabel "conv_loop",
            ILoad "%ci" I64 (VReg "%ci.slot"),
            IICmp "%conv_done" ISge I64 (VReg "%ci") (VReg "%argc_w64"),
            IBrCond (VReg "%conv_done") "call_main" "conv_body",
            ILabel "conv_body",
            IGep "%argw_slot" Ptr (VReg "%argv_w") [(I64, VReg "%ci")],
            ILoad "%argw" Ptr (VReg "%argw_slot"),
            -- First call queries required UTF-8 byte count (incl. terminating NUL,
            -- because cchWideChar = -1 means "process the null-terminator too").
            -- 65001 = CP_UTF8.
            ICall (Just "%needed") I32 Nothing "@WideCharToMultiByte" [(I32, VInt 65001), (I32, VInt 0), (Ptr, VReg "%argw"), (I32, VInt (-1)), (Ptr, VNull), (I32, VInt 0), (Ptr, VNull), (Ptr, VNull)],
            IICmp "%need_ok" ISgt I32 (VReg "%needed") (VInt 0),
            IBrCond (VReg "%need_ok") "conv_do" "conv_empty",
            ILabel "conv_do",
            IConv "%needed64" Sext I32 (VReg "%needed") I64,
            ICall (Just "%buf") Ptr Nothing "@__alloc" [(I64, VReg "%needed64"), (I32, VInt 0)],
            ICall Nothing I32 Nothing "@WideCharToMultiByte" [(I32, VInt 65001), (I32, VInt 0), (Ptr, VReg "%argw"), (I32, VInt (-1)), (Ptr, VReg "%buf"), (I32, VReg "%needed"), (Ptr, VNull), (Ptr, VNull)],
            IGep "%dst_slot" Ptr (VReg "%u8arr") [(I64, VReg "%ci")],
            IStore Ptr (VReg "%buf") (VReg "%dst_slot"),
            IBin "%ci.next" LAdd I64 (VReg "%ci") (VInt 1),
            IStore I64 (VReg "%ci.next") (VReg "%ci.slot"),
            IBr "conv_loop",
            ILabel "conv_empty",
            -- Conversion reported 0 bytes (degenerate; keeps the array fully
            -- initialised so '__getArgs'/'strlen' stay well-defined).
            IGep "%dst_slot_e" Ptr (VReg "%u8arr") [(I64, VReg "%ci")],
            IStore Ptr (VConstGep "@.empty" 12) (VReg "%dst_slot_e"),
            IBin "%ci.next_e" LAdd I64 (VReg "%ci") (VInt 1),
            IStore I64 (VReg "%ci.next_e") (VReg "%ci.slot"),
            IBr "conv_loop",
            ILabel "call_main"
          ]
      | otherwise = []
    -- Same IO-tree handoff as the POSIX path; see footerPosix. With argv
    -- this runs at the loop exit ('call_main:'); without it the conv block
    -- is absent and these instructions run straight off 'entry:'.
    ioHandoff =
      [ ICall (Just "%io") Ptr Nothing "@v_main" [],
        ICall Nothing Ptr Nothing "@v_runIO" [(Ptr, VReg "%io")],
        IRet (Just (I32, VInt 0))
      ]

-- ════════════════════════════════════════════════════════════════════════════
-- Declarations
-- ════════════════════════════════════════════════════════════════════════════

emitDecl :: EmitCtx -> CDecl -> CodegenM LFunc
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
          concat
            [ [ IAlloca slot Ptr Nothing,
                IStore Ptr (VReg ("%" <> mangle origName)) (VReg slot)
              ]
            | (origName, slot) <- paramSlotPairs
            ]
            <> [IAlloca (joinSlotName p) Ptr Nothing | p <- joinParamsIn body]
    -- At the loop head, pull each parameter back into an SSA value. These
    -- are the names 'emitExpr' will resolve 'CVar' references to.
    loadPairs <- forM (zip args paramSlotPairs) $ \(origName, (_, slot)) -> do
      loaded <- freshTemp
      pure ((origName, loaded), ILoad loaded Ptr (VReg slot))
    let loopLocals = Map.fromList [(n, VReg t) | (n, t) <- map fst loadPairs]
        loadInstrs = map snd loadPairs
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
    pure
      LFunc
        { lfLinkage = "internal",
          lfRetType = Ptr,
          lfName = mangle nm,
          lfParams = [(Ptr, "%" <> mangle a) | a <- args],
          lfBody =
            [ILabel "entry"]
              <> entryAllocs
              <> [IAlloca retSlot Ptr Nothing, IBr loopLbl, ILabel loopLbl]
              <> loadInstrs
              <> bodyInstrs
              <> [ ILabel exitLbl,
                   ILoad retLoaded Ptr (VReg retSlot),
                   IRet (Just (Ptr, VReg retLoaded))
                 ]
        }
  CFunDef nm args body -> do
    put 0
    let paramSet = Set.fromList args
        localCtx = ctx {params = paramSet}
    -- Emit body via 'emitNonLoopBody' which walks the tail-form
    -- and emits the value-tail param decs at each terminal, with
    -- per-arm precision for 'CCase' / 'CRowCase' bodies so an arm
    -- returning a 'CVar' param is "moved" out without freeing the
    -- just-returned cell.
    bodyEmit <- emitNonLoopBody localCtx args body
    pure
      LFunc
        { lfLinkage = "internal",
          lfRetType = Ptr,
          lfName = mangle nm,
          lfParams = [(Ptr, "%" <> mangle a) | a <- args],
          lfBody = [IAlloca (joinSlotName p) Ptr Nothing | p <- joinParamsIn body] <> bodyEmit
        }
  CValDef nm rhs -> do
    put 0
    let localCtx = ctx {params = Set.empty}
    (instrs, result) <- emitExpr localCtx rhs
    pure
      LFunc
        { lfLinkage = "internal",
          lfRetType = Ptr,
          lfName = mangle nm,
          lfParams = [],
          lfBody =
            [IAlloca (joinSlotName p) Ptr Nothing | p <- joinParamsIn rhs]
              <> instrs
              <> [IRet (Just (Ptr, result))]
        }

-- | The inner expression of an expression-position 'CJoin': a case —
-- possibly under 'CLet' bindings floated out of its scrutinee and the
-- 'CDrop' wrappers 'Awsum.Lifetime' places around those binders — whose
-- arms either jump to the join (a 'CJump' at the arm root, possibly under
-- 'CDrop' wrappers — anything deeper would be a jump in non-tail
-- position, which the node's invariant excludes) or produce the join's
-- bypass values. Returns the emitted instructions plus the
-- @(value, end-label)@ pairs for the caller's phi. Releases accumulated
-- on the way down — a 'CDrop' crossed above the dispatch joins
-- @pendingDecs@, and the fresh inner scrutinee's dec is appended at the
-- case — fire once per path: value arms after their owned result, jump
-- arms before the branch (the jump path never reaches the after-block
-- where the vanilla case emitter would have released them) — the same
-- discipline the tail walks express through their @pending@ stacks. A
-- degenerate inner — the fusion's case later collapsed to a bare jump or
-- a plain value — takes the same two paths without the dispatch.
emitJoinInnerExpr :: EmitCtx -> Text -> [LInstr] -> CExpr -> CodegenM ([LInstr], [(LVal, Text)])
emitJoinInnerExpr ctx afterLbl pendingDecs = \case
  CRowCase scrut alts ->
    emitJoinInnerExpr ctx afterLbl pendingDecs (CCase scrut [(fromIntegral t, [v], b) | (t, v, b) <- alts])
  -- A let floated out of the inner case's scrutinee wraps the whole inner
  -- expression: bind it and continue.
  CLet x rhs body -> do
    (ri, rv) <- emitExpr ctx rhs
    let ctx' = ctx {locals = Map.insert x rv ctx.locals}
    (bi, ends) <- emitJoinInnerExpr ctx' afterLbl pendingDecs body
    pure (ri <> emitIncIfCVar ctx rhs rv <> bi, ends)
  -- A drop above the dispatch (a let binder whose scope is the whole
  -- inner expression): the dec joins the per-path releases below.
  CDrop _ n body ->
    emitJoinInnerExpr ctx afterLbl (pendingDecs <> emitFree ctx n) body
  CCase scrut alts -> do
    (instrS, resS) <- emitExpr ctx scrut
    tagSlot <- freshTemp
    tagLoaded <- freshTemp
    tagTmp <- freshTemp
    let tagInstrs =
          [ IGep tagSlot Ptr resS [(I32, VInt 0)],
            ILoad tagLoaded Ptr (VReg tagSlot),
            IConv tagTmp PtrToInt Ptr (VReg tagLoaded) I64
          ]
    defLabel <- freshLabel "join.case.default"
    let scrutDec =
          pendingDecs
            <> [ ICall Nothing Void Nothing "@__free_recursive" [(Ptr, resS)]
               | isNothing (borrowedSource ctx scrut)
               ]
    arms <- forM alts $ \(tag, vars, body) -> do
      lbl <- freshLabel ("join.case.arm." <> show tag)
      let armElidedSelfMove = case scrut of
            CVar n -> elidableArmBinders n vars body
            _ -> Set.empty
          armElided = armElidedSelfMove `Set.union` Set.fromList [v | v <- vars, not (binderUsedIn v body)]
      varInstrs <- forM [(v, idx) | (v, idx) <- zip vars [1 :: Int ..], binderUsedIn v body] $ \(v, idx) -> do
        slotT <- freshTemp
        valT <- freshTemp
        let incPart =
              ([ICall Nothing Void Nothing "@__inc_ref" [(Ptr, VReg valT)] | not (v `Set.member` armElided)])
        pure
          ( [ IGep slotT Ptr resS [(I32, VInt (toInteger idx))],
              ILoad valT Ptr (VReg slotT)
            ]
              <> incPart,
            (v, valT)
          )
      let varCode = concatMap fst varInstrs
          varBindings = map snd varInstrs
          ctx' =
            let withLocals = foldl' (\c (v, tmp) -> c {locals = Map.insert v (VReg tmp) (locals c)}) ctx varBindings
                withElided = withLocals {elidedBinders = elidedBinders withLocals `Set.union` armElided}
             in case scrut of
                  CVar n -> withElided {armPatternByScrut = Map.insert n vars (armPatternByScrut withElided)}
                  _ -> withElided
      (armCode, valueEnd) <- emitJoinArm ctx' afterLbl scrutDec body
      pure (tag, lbl, varCode <> armCode, valueEnd)
    let switchInstr = ISwitch I64 (VReg tagTmp) defLabel [(toInteger tag, lbl) | (tag, lbl, _, _) <- arms]
        armBlocks = concat [ILabel lbl : code | (_, lbl, code, _) <- arms]
        defBlock = [ILabel defLabel, IUnreachable]
    pure
      ( instrS <> tagInstrs <> [switchInstr] <> armBlocks <> defBlock,
        [ve | (_, _, _, Just ve) <- arms]
      )
  other -> do
    (code, valueEnd) <- emitJoinArm ctx afterLbl pendingDecs other
    pure (code, maybeToList valueEnd)

-- | One inner-arm body of an expression-position join. A jump (under its
-- drop wrappers) evaluates the arguments, incs the borrowed ones, releases
-- the wrapped binders and the fresh scrutinee, stores into the parameter
-- slots and branches — 'Nothing', no phi entry. Anything else is an
-- ordinary expression whose owned value (inc-if-borrow, the
-- expression-position invariant) trampolines to the after-block.
emitJoinArm :: EmitCtx -> Text -> [LInstr] -> CExpr -> CodegenM ([LInstr], Maybe (LVal, Text))
emitJoinArm ctx afterLbl scrutDec body0 =
  case peelDrops body0 of
    (dropped, CJump j args)
      | Just jt <- Map.lookup j ctx.joinTargets -> do
          argResults <- traverse (emitExpr ctx) args
          let (argInstrsList, argVals) = unzip argResults
              incs = concat [emitIncIfCVar ctx e r | (e, r) <- zip args argVals]
              dropDecs = concatMap (emitFree ctx) dropped
              stores = [IStore Ptr r (VReg (joinSlotName p)) | (r, p) <- zip argVals jt.jtParams]
          pure
            ( concat argInstrsList <> incs <> dropDecs <> scrutDec <> stores <> [IBr jt.jtLabel],
              Nothing
            )
    _ -> do
      (instrB, resB) <- emitExpr ctx body0
      endLbl <- freshLabel "join.val"
      let armInc = emitIncIfCVar ctx body0 resB
      pure
        ( instrB <> armInc <> scrutDec <> [IBr endLbl, ILabel endLbl, IBr afterLbl],
          Just (resB, endLbl)
        )

-- | Emit a non-CLoop 'CFunDef' body with proper value-tail
-- param decs. Walks the tail-form, emitting dec per terminal: for
-- 'CCase' / 'CRowCase' bodies each arm computes its own dec list
-- (so an arm returning a @CVar p@ doesn't free the cell the
-- function is about to return); for a bare @CVar n@ the matching
-- param is "moved" out; for any fresh source (CCon, CCall,
-- CIntLit, etc.) all params are dec'd.
emitNonLoopBody :: EmitCtx -> [Name] -> CExpr -> CodegenM [LInstr]
emitNonLoopBody ctx0 params = go ctx0 [] []
  where
    -- 'pending' accumulates 'CDrop'-bound binders during the tail
    -- walk; 'freshScruts' accumulates fresh case-scrutinee SSAs
    -- (no live binding-side owner once the case is over). Both
    -- get dec'd at every terminal, with move-semantics carve-out
    -- for the result-CVar on 'pending'/params (scruts have no
    -- name so they're dec'd unconditionally).
    go :: EmitCtx -> [Name] -> [LVal] -> CExpr -> CodegenM [LInstr]
    go ctx pending freshScruts = \case
      CCase scrut alts -> goCase ctx pending freshScruts scrut alts
      CRowCase scrut alts ->
        goCase ctx pending freshScruts scrut [(fromIntegral t, [v], b) | (t, v, b) <- alts]
      CDrop _ n body -> go ctx (n : pending) freshScruts body
      CLet x rhs body -> do
        (ri, rv) <- emitExpr ctx rhs
        let ctx' = ctx {locals = Map.insert x rv ctx.locals}
        bodyInstrs <- go ctx' pending freshScruts body
        pure (ri <> emitIncIfCVar ctx rhs rv <> bodyInstrs)
      -- Native join point: the inner expression continues the tail walk
      -- with the target registered; its jumps store into the prologue
      -- slots and branch to the labelled body block. The body is walked
      -- with the join parameters joined onto @pending@ — the value-tail
      -- release with the move carve-out is exactly the function-parameter
      -- discipline the parameters follow ('Awsum.Lifetime' wraps no drop
      -- around them). Whatever was pending at the node stays pending for
      -- the body: those binders wrap the whole join and die at its
      -- terminals, never between a jump and the body.
      CJoin j ps body inner -> do
        joinLbl <- freshLabel "join"
        let jt = JoinTarget joinLbl ps (length pending) (length freshScruts)
            ctxJ = ctx {joinTargets = Map.insert j jt ctx.joinTargets}
        innerInstrs <- go ctxJ pending freshScruts inner
        loads <- forM ps $ \p -> do
          t <- freshTemp
          pure ((p, VReg t), ILoad t Ptr (VReg (joinSlotName p)))
        let ctxB = ctx {locals = foldl' (\m (p, v) -> Map.insert p v m) ctx.locals (map fst loads)}
        bodyInstrs <- go ctxB (ps <> pending) freshScruts body
        pure (innerInstrs <> [ILabel joinLbl] <> map snd loads <> bodyInstrs)
      -- Mirror of 'CContinue': evaluate the arguments, inc the borrowed
      -- ones (the join parameter takes its own reference), release the
      -- scrutinees and pending binders accumulated /since/ the join node
      -- (the jumping path's own arms), store into the parameter slots,
      -- branch.
      CJump j args
        | Just jt <- Map.lookup j ctx.joinTargets -> do
            argResults <- traverse (emitExpr ctx) args
            let (argInstrsList, argVals) = unzip argResults
                incs = concat [emitIncIfCVar ctx e r | (e, r) <- zip args argVals]
                sincePending = take (length pending - jt.jtPendingBase) pending
                sinceScruts = take (length freshScruts - jt.jtScrutBase) freshScruts
                scrutDecs = [ICall Nothing Void Nothing "@__free_recursive" [(Ptr, s)] | s <- sinceScruts]
                frees = concatMap (emitFree ctx) sincePending
                stores = [IStore Ptr r (VReg (joinSlotName p)) | (r, p) <- zip argVals jt.jtParams]
            pure (concat argInstrsList <> incs <> scrutDecs <> frees <> stores <> [IBr jt.jtLabel])
      CJump j _ -> error ("LLVM codegen: CJump to unknown join " <> j <> " (pipeline bug)")
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
            scrutDecs = [ICall Nothing Void Nothing "@__free_recursive" [(Ptr, s)] | s <- freshScruts]
            frees =
              scrutDecs
                <> concatMap (emitFree ctx) pendingToDec
                <> concatMap (emitFree ctx) paramsToDec
        pure (instrs <> frees <> [IRet (Just (Ptr, result))])

    -- Per-arm dec: each arm body emits its own (potentially
    -- different) param decs based on its own tail-form. Each arm
    -- self-terminates with a @ret@, so no phi join is needed.
    goCase :: EmitCtx -> [Name] -> [LVal] -> CExpr -> [(Int, [Name], CExpr)] -> CodegenM [LInstr]
    goCase ctx pending freshScruts scrut alts = do
      (instrS, resS) <- emitExpr ctx scrut
      tagSlot <- freshTemp
      tagLoaded <- freshTemp
      tagTmp <- freshTemp
      let tagInstrs =
            [ IGep tagSlot Ptr resS [(I32, VInt 0)],
              ILoad tagLoaded Ptr (VReg tagSlot),
              IConv tagTmp PtrToInt Ptr (VReg tagLoaded) I64
            ]
      defLabel <- freshLabel "case.default"
      -- Thread fresh scrut SSA through each arm so its terminator
      -- dec's it.
      let freshScruts' = case borrowedSource ctx scrut of
            Just _ -> freshScruts
            Nothing -> resS : freshScruts
      arms <- forM alts $ \(tag, vars, body) -> do
        lbl <- freshLabel ("case.arm." <> show tag)
        let armElidedSelfMove = case scrut of
              CVar n -> elidableArmBinders n vars body
              _ -> Set.empty
            armElided = armElidedSelfMove `Set.union` Set.fromList [v | v <- vars, not (binderUsedIn v body)]
        varInstrs <- forM [(v, idx) | (v, idx) <- zip vars [1 :: Int ..], binderUsedIn v body] $ \(v, idx) -> do
          slotT <- freshTemp
          valT <- freshTemp
          let incPart =
                ([ICall Nothing Void Nothing "@__inc_ref" [(Ptr, VReg valT)] | not (v `Set.member` armElided)])
          pure
            ( [ IGep slotT Ptr resS [(I32, VInt (toInteger idx))],
                ILoad valT Ptr (VReg slotT)
              ]
                <> incPart,
              (v, valT)
            )
        let varCode = concatMap fst varInstrs
            varBindings = map snd varInstrs
            -- Linear-scrutinee elision: see 'emitExpr' 'CCase'.
            ctx' =
              let withLocals = foldl' (\c (v, tmp) -> c {locals = Map.insert v (VReg tmp) (locals c)}) ctx varBindings
                  withElided = withLocals {elidedBinders = elidedBinders withLocals `Set.union` armElided}
               in case scrut of
                    CVar n -> withElided {armPatternByScrut = Map.insert n vars (armPatternByScrut withElided)}
                    _ -> withElided
        armBody <- go ctx' pending freshScruts' body
        pure (tag, lbl, varCode <> armBody)
      let switchInstr = ISwitch I64 (VReg tagTmp) defLabel [(toInteger tag, lbl) | (tag, lbl, _) <- arms]
          armBlocks = concat [ILabel lbl : blk | (_, lbl, blk) <- arms]
          defBlock = [ILabel defLabel, IUnreachable]
      pure (instrS <> tagInstrs <> [switchInstr] <> armBlocks <> defBlock)

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
emitTail :: EmitCtx -> CExpr -> CodegenM [LInstr]
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
    go :: EmitCtx -> LoopCtx -> [Name] -> [LVal] -> CExpr -> CodegenM [LInstr]
    go ctx' lctx pending freshScruts = \case
      CContinue newArgs -> do
        argResults <- traverse (emitExpr ctx') newArgs
        let (argInstrsList, argNames) = unzip argResults
            -- Inc each ptr-arg whose source is a CVar (borrow →
            -- the next-iter slot takes its own ref). Fresh sources
            -- carry their @+1@ from @__alloc@.
            incs =
              concat
                [ emitIncIfCVar ctx' e r
                | (e, r) <- zip newArgs argNames
                ]
            scrutDecs = [ICall Nothing Void Nothing "@__free_recursive" [(Ptr, s)] | s <- freshScruts]
            frees = concatMap (emitFree ctx') pending
            stores =
              [ IStore Ptr r (VReg slot)
              | (r, (_, slot)) <- zip argNames lctx.lcParamSlots
              ]
        pure
          $ concat argInstrsList
          <> incs
          <> scrutDecs
          <> frees
          <> stores
          <> [IBr lctx.lcLoopLabel]
      CCase scrut alts -> do
        (instrS, resS) <- emitExpr ctx' scrut
        tagSlot <- freshTemp
        tagLoaded <- freshTemp
        tagTmp <- freshTemp
        let tagInstrs =
              [ IGep tagSlot Ptr resS [(I32, VInt 0)],
                ILoad tagLoaded Ptr (VReg tagSlot),
                IConv tagTmp PtrToInt Ptr (VReg tagLoaded) I64
              ]
        defLabel <- freshLabel "tco.case.default"
        -- If the scrut is fresh, thread its SSA through to each
        -- arm so the arm's terminator dec's it.
        let freshScruts' = case borrowedSource ctx' scrut of
              Just _ -> freshScruts
              Nothing -> resS : freshScruts
        armBlocks <- forM alts $ \(tag, vars, body) -> do
          lbl <- freshLabel ("tco.case.arm." <> show tag)
          let armElidedSelfMove = case scrut of
                CVar n -> elidableArmBinders n vars body
                _ -> Set.empty
              armElided = armElidedSelfMove `Set.union` Set.fromList [v | v <- vars, not (binderUsedIn v body)]
          -- Inc each extracted ptr-binder (see the non-tail
          -- 'CCase' in 'emitExpr' for the rationale). Skip the inc
          -- for binders in @armElided@ (move-armVars whose only
          -- use is a 'CReuse' field on the same scrut — their
          -- paired CDrop is also skipped via 'emitFree').
          varInstrs <- forM [(v, idx) | (v, idx) <- zip vars [1 :: Int ..], binderUsedIn v body] $ \(v, idx) -> do
            slotT <- freshTemp
            valT <- freshTemp
            let incPart =
                  ([ICall Nothing Void Nothing "@__inc_ref" [(Ptr, VReg valT)] | not (v `Set.member` armElided)])
            pure
              ( [ IGep slotT Ptr resS [(I32, VInt (toInteger idx))],
                  ILoad valT Ptr (VReg slotT)
                ]
                  <> incPart,
                (v, valT)
              )
          let varCode = concatMap fst varInstrs
              varBindings = map snd varInstrs
              -- Linear-scrutinee elision: see the matching comment
              -- in 'emitExpr' 'CCase' for the rationale.
              ctx'' =
                let withLocals = foldl' (\c (v, tmp) -> c {locals = Map.insert v (VReg tmp) (locals c)}) ctx' varBindings
                    withElided = withLocals {elidedBinders = elidedBinders withLocals `Set.union` armElided}
                 in case scrut of
                      CVar n -> withElided {armPatternByScrut = Map.insert n vars (armPatternByScrut withElided)}
                      _ -> withElided
          bodyInstrs <- go ctx'' lctx pending freshScruts' body
          pure (tag, lbl, varCode <> bodyInstrs)
        let switchInstr = ISwitch I64 (VReg tagTmp) defLabel [(toInteger tag, lbl) | (tag, lbl, _) <- armBlocks]
            armsEmitted = concat [ILabel lbl : blk | (_, lbl, blk) <- armBlocks]
            defBlock = [ILabel defLabel, IUnreachable]
        pure
          $ instrS
          <> tagInstrs
          <> [switchInstr]
          <> armsEmitted
          <> defBlock
      CRowCase scrut alts ->
        go ctx' lctx pending freshScruts (CCase scrut [(fromIntegral t, [v], b) | (t, v, b) <- alts])
      CDrop _ n body -> go ctx' lctx (n : pending) freshScruts body
      -- Bind, then the body continues in tail position (the binder's
      -- 'CDrop' joins the pending stack like any other).
      CLet x rhs body -> do
        (ri, rv) <- emitExpr ctx' rhs
        let ctx'' = ctx' {locals = Map.insert x rv ctx'.locals}
        bodyInstrs <- go ctx'' lctx pending freshScruts body
        pure (ri <> emitIncIfCVar ctx' rhs rv <> bodyInstrs)
      -- Native join point under a 'CLoop' — same shape as in
      -- 'emitNonLoopBody': inner walks with the target registered, the
      -- body walks at its label with the join parameters joined onto
      -- @pending@ (value-tail release, move carve-out). A 'CContinue'
      -- inside the body is still excluded by the fusion gate; arms of
      -- the inner case that continue the loop instead of jumping keep
      -- their ordinary 'CContinue' handling.
      CJoin j ps body inner -> do
        joinLbl <- freshLabel "join"
        let jt = JoinTarget joinLbl ps (length pending) (length freshScruts)
            ctxJ = ctx' {joinTargets = Map.insert j jt ctx'.joinTargets}
        innerInstrs <- go ctxJ lctx pending freshScruts inner
        loads <- forM ps $ \p -> do
          t <- freshTemp
          pure ((p, VReg t), ILoad t Ptr (VReg (joinSlotName p)))
        let ctxB = ctx' {locals = foldl' (\m (p, v) -> Map.insert p v m) ctx'.locals (map fst loads)}
        bodyInstrs <- go ctxB lctx (ps <> pending) freshScruts body
        pure (innerInstrs <> [ILabel joinLbl] <> map snd loads <> bodyInstrs)
      -- Mirror of 'CContinue' (see 'emitNonLoopBody' for the rationale).
      CJump j args
        | Just jt <- Map.lookup j ctx'.joinTargets -> do
            argResults <- traverse (emitExpr ctx') args
            let (argInstrsList, argVals) = unzip argResults
                incs = concat [emitIncIfCVar ctx' e r | (e, r) <- zip args argVals]
                sincePending = take (length pending - jt.jtPendingBase) pending
                sinceScruts = take (length freshScruts - jt.jtScrutBase) freshScruts
                scrutDecs = [ICall Nothing Void Nothing "@__free_recursive" [(Ptr, s)] | s <- sinceScruts]
                frees = concatMap (emitFree ctx') sincePending
                stores = [IStore Ptr r (VReg (joinSlotName p)) | (r, p) <- zip argVals jt.jtParams]
            pure (concat argInstrsList <> incs <> scrutDecs <> frees <> stores <> [IBr jt.jtLabel])
      CJump j _ -> error ("LLVM codegen: CJump to unknown join " <> j <> " (pipeline bug)")
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
            scrutDecs = [ICall Nothing Void Nothing "@__free_recursive" [(Ptr, s)] | s <- freshScruts]
            frees =
              scrutDecs
                <> concatMap (emitFree ctx') pendingToDec
                <> concatMap (emitFree ctx') paramsToDec
        pure
          $ instrs
          <> frees
          <> [ IStore Ptr result (VReg lctx.lcRetSlot),
               IBr lctx.lcExitLabel
             ]

lookupBinderSSA :: EmitCtx -> Name -> LVal
lookupBinderSSA ctx n
  | Just v <- Map.lookup n ctx.locals = v
  | n `Set.member` ctx.params = VReg ("%" <> mangle n)
  | otherwise = error $ "LLVM codegen: CDrop on unknown binder: " <> show n

-- | The textual name of a call target — the callee slot of 'ICall' is a
-- bare name, and a call always targets a register (indirect call) or a
-- global (@\@v_fn@). Any other operand reaching here is a pipeline bug.
lvalName :: LVal -> Text
lvalName = \case
  VReg r -> r
  VGlob g -> g
  v -> error $ "LLVM codegen: invalid call target: " <> show v

-- | Lower a 'CDrop' to a cascading-free dec. Reads the
-- cell's refcount, on hitting 0 walks @shape@ and dec's each ptr
-- field, then releases the block. Literals (flag == 0) short-circuit.
--
-- Returns @""@ for binders in @ctx.elidedBinders@ — those have had
-- their inc-on-extract skipped at the case match, so the paired
-- dec here must also vanish for refcount balance. See
-- 'Awsum.Lifetime.elidableArmBinders' for the precondition.
emitFree :: EmitCtx -> Name -> [LInstr]
emitFree ctx n
  | n `Set.member` ctx.elidedBinders = []
  | otherwise = [ICall Nothing Void Nothing "@__free_recursive" [(Ptr, lookupBinderSSA ctx n)]]

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
  -- A drop whose body returns the dropped binder itself is the move shape:
  -- the 'CDrop' emission inc'd the result before the dec, so the value
  -- leaves the drop /owned/ — a consumer must not inc it again. Any other
  -- tail passes through.
  CDrop _ n body -> case borrowedSource ctx body of
    Just m | m == n -> Nothing
    other -> other
  -- A let's value is its body's value.
  CLet _ _ body -> borrowedSource ctx body
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

-- | Does the expression contain a 'CReuse' anywhere? Such a field of an
-- enclosing 'CReuse' defers into the uniqueness branches — see the field
-- pre-evaluation note in the 'CReuse' emission.
containsCReuse :: CExpr -> Bool
containsCReuse = \case
  CReuse {} -> True
  CCon _ fs -> any containsCReuse fs
  CRow _ x -> containsCReuse x
  CCall f xs -> containsCReuse f || any containsCReuse xs
  CCase s alts -> containsCReuse s || any (\(_, _, b) -> containsCReuse b) alts
  CRowCase s alts -> containsCReuse s || any (\(_, _, b) -> containsCReuse b) alts
  CLet _ rhs b -> containsCReuse rhs || containsCReuse b
  CLoop b -> containsCReuse b
  CContinue xs -> any containsCReuse xs
  CDrop _ _ b -> containsCReuse b
  CJoin _ _ body inner -> containsCReuse body || containsCReuse inner
  CJump _ args -> any containsCReuse args
  CVar _ -> False
  CProj _ _ -> False
  CString _ -> False
  CIntLit _ _ -> False
  CBuiltIn _ -> False

-- | Emit a @__inc_ref@ call for the loaded SSA iff the source
-- expression is a borrowed @CVar@. See 'borrowedSource'.
emitIncIfCVar :: EmitCtx -> CExpr -> LVal -> [LInstr]
emitIncIfCVar ctx expr ssa = case borrowedSource ctx expr of
  Just _ -> [ICall Nothing Void Nothing "@__inc_ref" [(Ptr, ssa)]]
  Nothing -> []

-- | Emit an argument expression in a transfer position
-- (@CCall@ argument). Equivalent to 'emitExpr' followed by an
-- inc-on-CVar — keeps every CCall-arg evaluator inc'd consistently
-- without forcing each builtin's inline emit to remember the rule.
emitArgWithInc :: EmitCtx -> CExpr -> CodegenM ([LInstr], LVal)
emitArgWithInc ctx expr = do
  (instrs, ssa) <- emitExpr ctx expr
  pure (instrs <> emitIncIfCVar ctx expr ssa, ssa)

-- ════════════════════════════════════════════════════════════════════════════
-- Expressions
-- ════════════════════════════════════════════════════════════════════════════

-- | Emit instructions for an expression.
--   Returns (accumulated instructions, SSA name holding the result).
emitExpr :: EmitCtx -> CExpr -> CodegenM ([LInstr], LVal)
emitExpr ctx = \case
  -- Bind: the binder takes the rhs value. A borrowed 'CVar' rhs incs (the
  -- binding owns its own ref — same discipline as a stored cell field); a
  -- fresh source transfers its @+1@. The matching dec is the binder's
  -- 'CDrop' from 'Awsum.Lifetime'.
  CLet x rhs body -> do
    (ri, rv) <- emitExpr ctx rhs
    let ctx' = ctx {locals = Map.insert x rv ctx.locals}
    (bi, bv) <- emitExpr ctx' body
    pure (ri <> emitIncIfCVar ctx rhs rv <> bi, bv)
  -- Load slot @slot@ of the cell @n@ and take an owning reference. The
  -- inc is the cell-takes-ownership inc a 'CVar' field would otherwise get
  -- via 'emitIncIfCVar' at the construction site — but 'CProj' is not a
  -- 'CVar', so it inc's itself here. The matching binder is in
  -- 'ctx.elidedBinders' (its extract-inc and 'CDrop' are skipped), so the
  -- net refcount equals the un-inlined case.
  CProj n slot -> do
    (ni, nv) <- emitExpr ctx (CVar n)
    slotT <- freshTemp
    valT <- freshTemp
    pure
      ( ni
          <> [ IGep slotT Ptr nv [(I32, VInt (toInteger slot))],
               ILoad valT Ptr (VReg slotT),
               ICall Nothing Void Nothing "@__inc_ref" [(Ptr, VReg valT)]
             ],
        VReg valT
      )
  CString s -> do
    let idx = case Map.lookup s ctx.stringPool of
          Just i -> i
          Nothing -> error $ "string not in pool: " <> show s
    -- The literal's storage is '{i32 flag=0, i32 refcount, i32 shape,
    -- i32 byte_count, i32 utf16, [N x i8]}'; the user-facing pointer is
    -- '@.str.N + 12', skipping the 12-byte header so all existing readers
    -- work unchanged. See 'emitStringConstants'.
    pure ([], VConstGep ("@.str." <> show idx) 12)
  CVar n
    | Just v <- Map.lookup n ctx.locals ->
        pure ([], v)
    | n `Set.member` ctx.params ->
        pure ([], VReg ("%" <> mangle n))
    | n `Set.member` ctx.valDefs -> do
        tmp <- freshTemp
        pure
          ( [ICall (Just tmp) Ptr Nothing ("@" <> mangle n) []],
            VReg tmp
          )
    | otherwise ->
        pure ([], VGlob ("@" <> mangle n))
  CIntLit n it -> do
    -- Box the literal: malloc a cell of the right width, store the value,
    -- and return the pointer — integers share the uniform 'ptr' representation.
    buf <- freshTemp
    let (llvmTy, bytes, val) = case it of
          TInt32 -> (I32, 4 :: Int, n)
          TUInt8 -> (I8, 1, n)
          -- LLVM i32 immediates are signed; values 2147483648..4294967295 must be
          -- written as their signed two's-complement equivalents (n - 2^32).
          TUInt32 -> (I32, 4, if n >= 2147483648 then n - 4294967296 else n)
    pure
      ( [ ICall (Just buf) Ptr Nothing "@__alloc" [(I64, VInt (toInteger bytes)), (I32, VInt 0)],
          IStore llvmTy (VInt val) (VReg buf)
        ],
        VReg buf
      )
  CBuiltIn _ ->
    pure ([], VNull) -- invariant: not a standalone term; dispatched from CCall
  CCon tag fields -> do
    -- Allocate container: [tag_as_ptr, field1, field2, ...]. Shape
    -- = number of ptr fields starting at slot 1 (== arity), so
    -- '__free_recursive' cascades correctly. Nullary constructors
    -- bake @shape = 0@; everything else passes its arity.
    let nSlots = 1 + length fields
        nFields = length fields
    arrTmp <- freshTemp
    let allocInstr = ICall (Just arrTmp) Ptr Nothing "@__alloc" [(I64, VInt (toInteger (nSlots * 8))), (I32, VInt (toInteger nFields))]
    -- Store tag at index 0
    tagPtr <- freshTemp
    tagSlot <- freshTemp
    let tagInstrs =
          [ IConv tagPtr IntToPtr I64 (VInt (toInteger tag)) Ptr,
            IGep tagSlot Ptr (VReg arrTmp) [(I32, VInt 0)],
            IStore Ptr (VReg tagPtr) (VReg tagSlot)
          ]
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
            <> [ IGep slotTmp Ptr (VReg arrTmp) [(I32, VInt (toInteger idx))],
                 IStore Ptr resF (VReg slotTmp)
               ]
        )
    pure
      ( [allocInstr] <> tagInstrs <> concat fieldInstrs,
        VReg arrTmp
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
          Just m | m == n -> [ICall Nothing Void Nothing "@__inc_ref" [(Ptr, bodyResult)]]
          _ -> []
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
  CReuse mode n tag fields -> do
    -- Reuse-under-RC coexistence, split by 'ReuseMode'. A 'ReuseUnique'
    -- cell — an Scc argument pack or a Cps continuation, loop-private by
    -- construction — mutates in place unconditionally: no other holder
    -- can exist, so no refcount check and no copy leg (the same straight
    -- line the WASM assembler emits). A 'ReuseGuarded' cell — user data
    -- the caller may retain — is in-place mutation only when uniquely
    -- owned (refcount == 1); when shared, copy-on-write leaves the shared
    -- cell intact and produces a fresh one. The runtime branch is ~3
    -- cycles on the linear path (load refcount + compare + predicted
    -- branch).
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
    -- Pre-evaluate fields once — both branches reuse the same field SSAs
    -- to either store-in-place or store-into-fresh — except fields that
    -- themselves contain a 'CReuse' (a nested reuse: the next continuation
    -- cell rebuilt inside the cell this loop reuses). Those defer into the
    -- branches, and only that ordering makes the nested uniqueness check
    -- meaningful: on the in-place path this cell's old-slot decs have
    -- already released the parent's reference to the nested target, so its
    -- rc is 1 exactly when nothing else holds it; on the copy path no dec
    -- has happened, the target still carries the parent-slot reference on
    -- top of its extract-inc, the nested check fails, and the nested reuse
    -- copies too — leaving the shared original intact. Pre-evaluating such
    -- a field would mutate the target before this cell's branch decided.
    fieldResults <- forM fields $ \f ->
      if containsCReuse f
        then pure Nothing
        else Just <$> emitExpr ctx f
    let fieldInstrsCat = concat [i | Just (i, _) <- fieldResults]
        zippedFields = zip3 fields fieldResults [1 :: Int ..]
    -- In-place stores — the whole emission for 'ReuseUnique', the
    -- unique-ownership leg for 'ReuseGuarded'. Before overwriting
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
        then pure []
        else do
          oldSlotPtr <- freshTemp
          oldVal <- freshTemp
          pure
            [ IGep oldSlotPtr Ptr nPtr [(I32, VInt (toInteger idx))],
              ILoad oldVal Ptr (VReg oldSlotPtr),
              ICall Nothing Void Nothing "@__free_recursive" [(Ptr, VReg oldVal)]
            ]
    -- Self-move slots: skip store + inc-new entirely (the slot
    -- already has the right pointer, no new ref needed). A deferred
    -- field evaluates here, after the old-slot decs.
    inPlaceFieldStores <- forM zippedFields $ \(fExpr, mPre, idx) ->
      if isSelfMoveAt idx
        then pure []
        else do
          (evalI, resF) <- case mPre of
            Just (_, r) -> pure ([], r)
            Nothing -> emitExpr ctx fExpr
          slotTmp <- freshTemp
          pure
            ( evalI
                <> emitIncIfCVar ctx fExpr resF
                <> [ IGep slotTmp Ptr nPtr [(I32, VInt (toInteger idx))],
                     IStore Ptr resF (VReg slotTmp)
                   ]
            )
    inPlaceTag <- freshTemp
    inPlaceTagSlot <- freshTemp
    let inPlaceCore =
          concat inPlaceOldDecs
            <> [ IConv inPlaceTag IntToPtr I64 (VInt (toInteger tag)) Ptr,
                 IGep inPlaceTagSlot Ptr nPtr [(I32, VInt 0)],
                 IStore Ptr (VReg inPlaceTag) (VReg inPlaceTagSlot)
               ]
            <> concat inPlaceFieldStores
    case mode of
      -- Loop-private pack/continuation cell: in place, no branch — the
      -- old-slot decs still precede the (possibly deferred) field
      -- evaluation, so a nested guarded reuse's own check stays
      -- meaningful exactly as on the guarded leg below.
      ReuseUnique -> pure (fieldInstrsCat <> inPlaceCore, nPtr)
      ReuseGuarded -> do
        rcPtr <- freshTemp
        rcVal <- freshTemp
        isUnique <- freshTemp
        reuseLbl <- freshLabel "reuse.in_place"
        copyLbl <- freshLabel "reuse.copy"
        joinLbl <- freshLabel "reuse.join"
        -- A deferred field's nested reuse opens blocks of its own inside
        -- either branch, so the join phi cannot name the branch entry labels;
        -- each branch funnels through a dedicated end block — the case
        -- emitter's @case.end@ idiom.
        reuseEndLbl <- freshLabel "reuse.in_place.end"
        copyEndLbl <- freshLabel "reuse.copy.end"
        let rcCheck =
              [ IGep rcPtr I8 nPtr [(I64, VInt (-8))],
                ILoad rcVal I32 (VReg rcPtr),
                IICmp isUnique IEq I32 (VReg rcVal) (VInt 1),
                IBrCond (VReg isUnique) reuseLbl copyLbl
              ]
            inPlaceBlock =
              [ILabel reuseLbl]
                <> inPlaceCore
                <> [IBr reuseEndLbl, ILabel reuseEndLbl, IBr joinLbl]
        -- Copy path — allocate a fresh cell with proper shape, store
        -- tag + fields (with inc-on-CVar so the new cell takes its
        -- own refs), then dec @n@ to balance the missing reuse-path
        -- consumption.
        copyTmp <- freshTemp
        copyTagPtr <- freshTemp
        copyTagSlot <- freshTemp
        let copyAllocInstrs =
              [ ICall (Just copyTmp) Ptr Nothing "@__alloc" [(I64, VInt (toInteger ((1 + nFields) * 8))), (I32, VInt (toInteger nFields))],
                IConv copyTagPtr IntToPtr I64 (VInt (toInteger tag)) Ptr,
                IGep copyTagSlot Ptr (VReg copyTmp) [(I32, VInt 0)],
                IStore Ptr (VReg copyTagPtr) (VReg copyTagSlot)
              ]
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
                      [ICall Nothing Void Nothing "@__inc_ref" [(Ptr, resF)]]
                _ -> []
        -- A deferred field evaluates here too — with no preceding decs, so a
        -- nested reuse sees the undisturbed refcount and copies as well.
        copyFieldStores <- forM zippedFields $ \(fExpr, mPre, idx) -> do
          (evalI, resF) <- case mPre of
            Just (_, r) -> pure ([], r)
            Nothing -> emitExpr ctx fExpr
          slotTmp <- freshTemp
          pure
            ( evalI
                <> copyIncPart fExpr resF
                <> [ IGep slotTmp Ptr (VReg copyTmp) [(I32, VInt (toInteger idx))],
                     IStore Ptr resF (VReg slotTmp)
                   ]
            )
        let copyDecN = [ICall Nothing Void Nothing "@__free_recursive" [(Ptr, nPtr)]]
            copyBlock =
              [ILabel copyLbl]
                <> copyAllocInstrs
                <> concat copyFieldStores
                <> copyDecN
                <> [IBr copyEndLbl, ILabel copyEndLbl, IBr joinLbl]
        -- Join — phi the result pointer from both paths' end blocks.
        phiTmp <- freshTemp
        let joinBlock =
              [ ILabel joinLbl,
                IPhi phiTmp Ptr [(nPtr, reuseEndLbl), (VReg copyTmp, copyEndLbl)]
              ]
        pure
          ( fieldInstrsCat
              <> rcCheck
              <> inPlaceBlock
              <> copyBlock
              <> joinBlock,
            VReg phiTmp
          )
  CRowCase scrut alts ->
    emitExpr ctx (CCase scrut [(fromIntegral t, [v], b) | (t, v, b) <- alts])
  CCase scrut alts -> do
    (instrS, resS) <- emitExpr ctx scrut
    -- Extract tag from container[0]
    tagSlot <- freshTemp
    tagLoaded <- freshTemp
    tagTmp <- freshTemp
    let tagInstrs =
          [ IGep tagSlot Ptr resS [(I32, VInt 0)],
            ILoad tagLoaded Ptr (VReg tagSlot),
            IConv tagTmp PtrToInt Ptr (VReg tagLoaded) I64
          ]
    -- Generate labels
    defLabel <- freshLabel "case.default"
    joinLabel <- freshLabel "case.join"
    altLabelsAndBodies <- forM alts $ \(tag, vars, body) -> do
      lbl <- freshLabel ("case.arm." <> show tag)
      endLbl <- freshLabel ("case.end." <> show tag)
      let armElidedSelfMove = case scrut of
            CVar n -> elidableArmBinders n vars body
            _ -> Set.empty
          armElided = armElidedSelfMove `Set.union` Set.fromList [v | v <- vars, not (binderUsedIn v body)]
      -- Extract bound variables from container fields. Each
      -- ptr-binder is inc'd on extract so the local binding takes
      -- its own reference (the scrut cell's slot still holds a ref
      -- too). The matching dec fires at arm end via the 'CDrop'
      -- that 'Awsum.Lifetime' wraps around every arm.
      varInstrs <- forM [(v, idx) | (v, idx) <- zip vars [1 :: Int ..], binderUsedIn v body] $ \(v, idx) -> do
        slotT <- freshTemp
        valT <- freshTemp
        let incPart =
              ([ICall Nothing Void Nothing "@__inc_ref" [(Ptr, VReg valT)] | not (v `Set.member` armElided)])
        pure
          ( [ IGep slotT Ptr resS [(I32, VInt (toInteger idx))],
              ILoad valT Ptr (VReg slotT)
            ]
              <> incPart,
            (v, valT)
          )
      let varInstrCode = concatMap fst varInstrs
          varBindings = map snd varInstrs
      -- Emit body with bound variables in context. Linear-scrutinee
      -- elision: if the scrut is 'CVar n', record this arm's @vars@
      -- under @n@ so a nested 'CReuse n t fs' can detect self-move
      -- slots.
      let ctx' =
            let withLocals = foldl' (\c (v, tmp) -> c {locals = Map.insert v (VReg tmp) (locals c)}) ctx varBindings
                withElided = withLocals {elidedBinders = elidedBinders withLocals `Set.union` armElided}
             in case scrut of
                  CVar n -> withElided {armPatternByScrut = Map.insert n vars (armPatternByScrut withElided)}
                  _ -> withElided
      (instrB, resB) <- emitExpr ctx' body
      -- An expression-position case must yield an /owned/ value, whatever
      -- the consumer (a cell field, a call argument, a let binding, the
      -- scrutinee of an outer case): an arm whose tail is a borrowed
      -- 'CVar' incs it on the way out, exactly as a call boundary would
      -- have (function inlining replaces such calls with this shape).
      -- Fresh-source arms and move-inc'd drop tails pass through.
      let armInc = emitIncIfCVar ctx' body resB
      pure (tag, lbl, endLbl, varInstrCode <> instrB <> armInc, resB)
    let switchInstr = ISwitch I64 (VReg tagTmp) defLabel [(toInteger tag, lbl) | (tag, lbl, _, _, _) <- altLabelsAndBodies]
    -- arm blocks (body may create new blocks; endLbl is always the direct predecessor of join)
    let armBlocks =
          concat
            [ [ILabel lbl] <> instrB <> [IBr endLbl, ILabel endLbl, IBr joinLabel]
            | (_, lbl, endLbl, instrB, _) <- altLabelsAndBodies
            ]
    -- default block (unreachable)
    let defBlock = [ILabel defLabel, IUnreachable]
    -- phi at join (references endLbl, the actual predecessor)
    phiTmp <- freshTemp
    let joinBlock =
          [ ILabel joinLabel,
            IPhi phiTmp Ptr [(resB, endLbl) | (_, _, endLbl, _, resB) <- altLabelsAndBodies]
          ]
        -- If the scrut's tail isn't a 'CVar' it's a fresh
        -- allocation (CCon/CCall/…) whose @+1@ refcount has no
        -- other owner once the case is over — dec it after the
        -- phi so the cell is reclaimed. Case-binders inc'd at
        -- extract retain their own refs to the cell's slot
        -- values, so the cascade-free of those slots only drops
        -- back the slot-via-cell ref and the binders survive.
        scrutDec = case borrowedSource ctx scrut of
          Just _ -> []
          Nothing -> [ICall Nothing Void Nothing "@__free_recursive" [(Ptr, resS)]]
    pure
      ( instrS <> tagInstrs <> [switchInstr] <> armBlocks <> defBlock <> joinBlock <> scrutDec,
        VReg phiTmp
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
              ( instrX <> [ICall (Just tmp) Ptr Nothing "@__print" [(Ptr, resX)]],
                VReg tmp
              )
          _ -> error "__print: arity mismatch"
      -- Zero-arg primitive driving the prelude's `runIO` 'IOGetArgs'
      -- arm: walks the cached argv (@.cli_argv@ / @.cli_argc@, stashed
      -- at entry), validating each element via '__entryArgEither', and
      -- builds an 'Either (StringTooLong | UnpairedUtf16Surrogate)
      -- (List String)'. Per the no-memoisation decision each call
      -- rebuilds the list — argv is invariant, so repeat calls are
      -- deterministically equal.
      CBuiltIn "internalGetArgs" ->
        case xs of
          [] -> do
            tmp <- freshTemp
            pure ([ICall (Just tmp) Ptr Nothing "@__getArgs" []], VReg tmp)
          _ -> error "__getArgs: arity mismatch"
      -- Zero-arg primitive driving the prelude's 'runIO'
      -- 'IOStdinReadAllString' arm: consumes fd 0 to EOF and wraps the
      -- strict-UTF-8-decoded contents in 'Either (StringTooLong |
      -- InvalidUtf8) String' via '__stdinReadAll'. Per the POSIX-honest
      -- no-memoisation decision, a second call after EOF reads zero bytes
      -- and decodes to @Right ""@.
      CBuiltIn "internalStdinReadAllString" ->
        case xs of
          [] -> do
            tmp <- freshTemp
            pure ([ICall (Just tmp) Ptr Nothing "@__stdinReadAll" []], VReg tmp)
          _ -> error "__stdinReadAll: arity mismatch"
      -- Zero-arg primitive driving the prelude's 'runIO'
      -- 'IOStdinReadAllBytes' arm: consumes fd 0 to EOF and returns the
      -- raw bytes as 'List UInt8' via '__stdinReadAllBytes'.
      CBuiltIn "internalStdinReadAllBytes" ->
        case xs of
          [] -> do
            tmp <- freshTemp
            pure ([ICall (Just tmp) Ptr Nothing "@__stdinReadAllBytes" []], VReg tmp)
          _ -> error "__stdinReadAllBytes: arity mismatch"
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
                  ( instrX <> [ICall (Just tmp) Ptr Nothing fn [(Ptr, resX)]],
                    VReg tmp
                  )
              _ -> error ("BuiltIn." <> name <> ": arity mismatch")
      CBuiltIn "byteToHexStringNoPrefix" ->
        case xs of
          [x] -> do
            (instrX, resX) <- emitArgWithInc ctx x
            tmp <- freshTemp
            pure
              ( instrX <> [ICall (Just tmp) Ptr Nothing "@__byteToHex" [(Ptr, resX)]],
                VReg tmp
              )
          _ -> error "BuiltIn.byteToHexStringNoPrefix: arity mismatch"
      CBuiltIn "predInt32" ->
        case xs of
          [x] -> do
            (instrX, resX) <- emitArgWithInc ctx x
            tmp <- freshTemp
            pure
              ( instrX <> [ICall (Just tmp) Ptr Nothing "@__predInt32" [(Ptr, resX)]],
                VReg tmp
              )
          _ -> error "BuiltIn.predInt32: arity mismatch"
      CBuiltIn "predUInt8" ->
        case xs of
          [x] -> do
            (instrX, resX) <- emitArgWithInc ctx x
            tmp <- freshTemp
            pure
              ( instrX <> [ICall (Just tmp) Ptr Nothing "@__predUInt8" [(Ptr, resX)]],
                VReg tmp
              )
          _ -> error "BuiltIn.predUInt8: arity mismatch"
      CBuiltIn "predUInt32" ->
        case xs of
          [x] -> do
            (instrX, resX) <- emitArgWithInc ctx x
            tmp <- freshTemp
            pure
              ( instrX <> [ICall (Just tmp) Ptr Nothing "@__predUInt32" [(Ptr, resX)]],
                VReg tmp
              )
          _ -> error "BuiltIn.predUInt32: arity mismatch"
      CBuiltIn "succInt32" ->
        case xs of
          [x] -> do
            (instrX, resX) <- emitArgWithInc ctx x
            tmp <- freshTemp
            pure
              ( instrX <> [ICall (Just tmp) Ptr Nothing "@__succInt32" [(Ptr, resX)]],
                VReg tmp
              )
          _ -> error "BuiltIn.succInt32: arity mismatch"
      CBuiltIn "succUInt8" ->
        case xs of
          [x] -> do
            (instrX, resX) <- emitArgWithInc ctx x
            tmp <- freshTemp
            pure
              ( instrX <> [ICall (Just tmp) Ptr Nothing "@__succUInt8" [(Ptr, resX)]],
                VReg tmp
              )
          _ -> error "BuiltIn.succUInt8: arity mismatch"
      CBuiltIn "succUInt32" ->
        case xs of
          [x] -> do
            (instrX, resX) <- emitArgWithInc ctx x
            tmp <- freshTemp
            pure
              ( instrX <> [ICall (Just tmp) Ptr Nothing "@__succUInt32" [(Ptr, resX)]],
                VReg tmp
              )
          _ -> error "BuiltIn.succUInt32: arity mismatch"
      CBuiltIn name
        | name == "eqInt32" || name == "eqUInt8" || name == "eqUInt32" || name == "eqString" ->
            case xs of
              [a, b] -> do
                (instrA, resA) <- emitArgWithInc ctx a
                (instrB, resB) <- emitArgWithInc ctx b
                tmp <- freshTemp
                let fn :: Text
                    fn = case name of
                      "eqUInt8" -> "@__eqUInt8"
                      "eqUInt32" -> "@__eqUInt32"
                      "eqString" -> "@__eqString"
                      _ -> "@__eqInt32"
                pure
                  ( instrA <> instrB <> [ICall (Just tmp) Ptr Nothing fn [(Ptr, resA), (Ptr, resB)]],
                    VReg tmp
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
                  ( instrA <> instrB <> [ICall (Just tmp) Ptr Nothing fn [(Ptr, resA), (Ptr, resB)]],
                    VReg tmp
                  )
              _ -> error ("BuiltIn." <> name <> ": arity mismatch")
      CBuiltIn "negInt32" ->
        case xs of
          [x] -> do
            (instrX, resX) <- emitArgWithInc ctx x
            tmp <- freshTemp
            pure
              ( instrX <> [ICall (Just tmp) Ptr Nothing "@__negInt32" [(Ptr, resX)]],
                VReg tmp
              )
          _ -> error "BuiltIn.negInt32: arity mismatch"
      CBuiltIn "concatString" ->
        case xs of
          [a, b] -> do
            (instrA, resA) <- emitArgWithInc ctx a
            (instrB, resB) <- emitArgWithInc ctx b
            tmp <- freshTemp
            pure
              ( instrA <> instrB <> [ICall (Just tmp) Ptr Nothing "@__concat" [(Ptr, resA), (Ptr, resB)]],
                VReg tmp
              )
          _ -> error "BuiltIn.concatString: arity mismatch"
      CBuiltIn "splitOnFirst" ->
        case xs of
          [a, b] -> do
            (instrA, resA) <- emitArgWithInc ctx a
            (instrB, resB) <- emitArgWithInc ctx b
            tmp <- freshTemp
            pure
              ( instrA <> instrB <> [ICall (Just tmp) Ptr Nothing "@__splitOnFirst" [(Ptr, resA), (Ptr, resB)]],
                VReg tmp
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
                  ( instrA <> [ICall (Just tmp) Ptr Nothing fn [(Ptr, resA)]],
                    VReg tmp
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
                  ( instrA <> [ICall (Just tmp) Ptr Nothing fn [(Ptr, resA)]],
                    VReg tmp
                  )
              _ -> error ("BuiltIn." <> name <> ": arity mismatch")
      CBuiltIn n ->
        error ("LLVM codegen: unknown builtin '" <> n <> "' reached CCall (typecheck should have rejected it)")
      _ -> do
        (instrF, resF) <- emitExpr ctx f
        argsResults <- traverse (emitArgWithInc ctx) xs
        let allInstrs = instrF <> concatMap fst argsResults
            callArgs = [(Ptr, r) | (_, r) <- argsResults]
        tmp <- freshTemp
        pure
          ( allInstrs <> [ICall (Just tmp) Ptr Nothing (lvalName resF) callArgs],
            VReg tmp
          )
  CLoop _ -> error "LLVM codegen: CLoop in non-tail position (pipeline bug — should only appear at function-body-tail)"
  CContinue _ -> error "LLVM codegen: CContinue in non-tail position (pipeline bug — should only appear inside a CLoop)"
  -- Expression-position join point (a cell field, a call argument, a
  -- 'CLet' right-hand side — @main@'s fused IO chains are the dominant
  -- shape). The inner case's value arms trampoline their owned values to
  -- the after-block ('emitJoinInnerExpr'); its jump arms store into the
  -- prologue slots and branch to the body block. The body's value is
  -- owned like every expression-position arm's (inc-if-borrow), the join
  -- parameters are released right after — inc the new owner before the
  -- old one's dec; a body that /is/ a bare parameter moves it out
  -- instead (no inc, no dec) — and a phi merges the bypass values with
  -- the body's.
  CJoin j ps body inner -> do
    joinLbl <- freshLabel "join"
    afterLbl <- freshLabel "join.after"
    let jt = JoinTarget joinLbl ps 0 0
        ctxJ = ctx {joinTargets = Map.insert j jt ctx.joinTargets}
    (innerInstrs, valueEnds) <- emitJoinInnerExpr ctxJ afterLbl [] inner
    loads <- forM ps $ \p -> do
      t <- freshTemp
      pure ((p, VReg t), ILoad t Ptr (VReg (joinSlotName p)))
    let ctxB = ctx {locals = foldl' (\m (p, v) -> Map.insert p v m) ctx.locals (map fst loads)}
    (bodyInstrs, bodyRes) <- emitExpr ctxB body
    bodyEnd <- freshLabel "join.end"
    let psMoved = case borrowedSource ctxB body of
          Just m | m `elem` ps -> Just m
          _ -> Nothing
        bodyInc = case psMoved of
          Just _ -> []
          Nothing -> emitIncIfCVar ctxB body bodyRes
        psDecs = concat [emitFree ctxB p | p <- ps, Just p /= psMoved]
        bodyBlock =
          [ILabel joinLbl]
            <> map snd loads
            <> bodyInstrs
            <> bodyInc
            <> psDecs
            <> [IBr bodyEnd, ILabel bodyEnd, IBr afterLbl]
    phiTmp <- freshTemp
    let afterBlock =
          [ ILabel afterLbl,
            IPhi phiTmp Ptr (valueEnds <> [(bodyRes, bodyEnd)])
          ]
    pure (innerInstrs <> bodyBlock <> afterBlock, VReg phiTmp)
  CJump j _ -> error ("LLVM codegen: CJump to " <> j <> " in non-tail position — jumps live only in tail positions of their join's inner expression")

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
