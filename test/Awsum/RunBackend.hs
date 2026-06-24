-- | Cross-backend compile + run helpers shared between snapshot and
-- property test specs. Snapshot tests need ast / core / per-backend
-- text representations on top of these (for golden comparison) and
-- carry their own richer 'CompileResult'; this module only owns the
-- *runnable* artifacts (text or bytes that are fed to a host process)
-- and the per-backend runners themselves.
module Awsum.RunBackend
  ( Backend (..),
    allBackends,
    backendName,
    CompiledArtifacts (..),
    SimplifyMode (..),
    compileFromText,
    compileFromTextWith,
    compileFromFile,
    compileFromFileWith,
    runOn,
    runOnAll,
    runOnStdin,
    runOnAllStdin,
    runOnStdinBytes,
    runOnAllStdinBytes,
    runJVM,
    runJVMStdin,
  )
where

import Awsum.Codegen.CLR (codegenCLR)
import Awsum.Codegen.CLR.Assemble (assembleCLR)
import Awsum.Codegen.JS (codegenJS, codegenJsPretty)
import Awsum.Codegen.JVM (codegenJVM)
import Awsum.Codegen.JVM.Assemble (assembleJVM, renderJvmLimitExceeded)
import Awsum.Codegen.LLVM (LLVMHost, codegenLLVM, llvmHostFromSystem, llvmHostLinkerFlags, llvmLinkHostFromSystem)
import Awsum.Codegen.WASM (codegenWASM)
import Awsum.Codegen.WASM.Assemble (assembleWASM)
import Awsum.Core (CoreProgram)
import Awsum.ElaborateLower (SimplifyMode (..), elaborateLowerProgramWith)
import Awsum.Parser (parseProgram)
import Awsum.Prelude (withPrelude)
import Awsum.Program (ProgramType (..))
import Common.File
import Control.Concurrent.Async (async, concurrently, wait)
import Control.Exception (IOException, bracket, try)
import Data.ByteString qualified as BS
import Data.Text qualified as T
import Relude
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO (hClose, hSetBinaryMode)
import System.IO.Temp (createTempDirectory, getCanonicalTemporaryDirectory, withSystemTempDirectory)
import System.Process (CreateProcess (..), StdStream (..), cleanupProcess, createProcess, proc, readProcessWithExitCode, waitForProcess)
import System.Timeout (timeout)

-- ════════════════════════════════════════════════════════════════════════════
-- Backend enum
-- ════════════════════════════════════════════════════════════════════════════

data Backend = LLVM | JVM | CLR | WASM | JS
  deriving stock (Show, Eq, Ord, Enum, Bounded)

allBackends :: [Backend]
allBackends = universe

backendName :: Backend -> Text
backendName = show

-- ════════════════════════════════════════════════════════════════════════════
-- Time limit
-- ════════════════════════════════════════════════════════════════════════════

-- | Hard ceiling on one harness compile and on one backend process run.
--   Corpus programs are sized to finish in seconds even with the whole
--   suite loading the machine, so hitting it never means "slow test": it
--   means a diverging program (most often a miscompiled loop) or a
--   non-terminating compiler pass, and either must fail its item by name
--   instead of hanging the suite. An hspec-level per-item timeout could
--   not do this job — the compiles and runs happen inside 'beforeAll'
--   hooks shared by a whole group, and only this layer knows which
--   backend's process is stuck.
timeLimitMicros :: Int
timeLimitMicros = 60 * 1000 * 1000

-- | The limit as failure messages spell it.
timeLimitText :: Text
timeLimitText = show (timeLimitMicros `div` 1000000) <> "s"

-- ════════════════════════════════════════════════════════════════════════════
-- Compiled artifacts
-- ════════════════════════════════════════════════════════════════════════════

-- | The minimum each backend needs to actually run a compiled program.
--   Bytes for backends whose host opens its own input file (java reads
--   .class, dotnet reads .dll, wasmtime reads .wasm); text for JS,
--   which Node interprets. LLVM is the odd one — we directly @exec@
--   the native binary, so we keep it as a 'FilePath' to a file
--   produced by @clang@ rather than as bytes. Writing the bytes
--   ourselves and then @exec@-ing causes ETXTBSY ("Text file busy")
--   on Linux: while our 'writeFileBS' fd is open, a sibling thread's
--   @fork@ inherits it (no @O_CLOEXEC@) and the child holds the file
--   open for writing past our @exec@ attempt. Letting @clang@ write
--   the file in its own process avoids that race entirely. 'caLLVM'
--   is kept alongside the path because snapshot tests compare it to
--   a golden @.ll@ file — it isn't needed at run time. It is parameterised
--   on 'LLVMHost' so the snapshot layer asserts one IR per host on every
--   run, regardless of which host the test is running on.
data CompiledArtifacts = CompiledArtifacts
  { caLLVM :: LLVMHost -> Text,
    caLLVMBinPath :: FilePath,
    caJVMBytes :: ByteString,
    caCLRBytes :: ByteString,
    caWASMBytes :: ByteString,
    -- The compact, single-line JS that @awsum build@ / @run@ ship — what
    -- 'runOn' actually executes, so the cross-backend stdout check verifies
    -- the artifact users get. 'caJSPretty' is its indented projection (the
    -- @asm -t js@ form), read only by the snapshot golden — kept lazy so the
    -- property / no-simplify layers, which only run, never render it.
    caJS :: Text,
    caJSPretty :: Text,
    -- The elaborated Core and the JVM/CLR/WASM text, all derived from the
    -- SAME elaboration as the bytes above. The snapshot spec reads these
    -- instead of elaborating a second time, so a golden text snapshot is a
    -- faithful view of the bytes that actually run. Property tests ignore them.
    caCore :: CoreProgram,
    caJVMText :: Text,
    caCLRText :: Text,
    caWASMText :: Text
  }

-- | Run the compile pipeline (parse → withPrelude → elaborate → codegen)
--   on a piece of source and return the runnable artifacts. Crashes on
--   parse / elaborate failure — bad source is a test bug, not a runtime
--   concern. Lives in IO because LLVM's runnable artifact is the native
--   binary, which means shelling out to @clang@ once per source. Doing
--   it here (rather than inside 'runLLVM') means QuickCheck's N inputs
--   per property cost one @clang@, not N.
compileFromText :: Text -> IO CompiledArtifacts
compileFromText = compileFromTextWith SimplifyOn

-- | 'compileFromText' with the 'Awsum.Simplify' pass switchable. The
--   differential layers ('Awsum.NoSimplifySpec', the property suite's
--   no-simplify twin) compile through 'SimplifyOff' and assert the same
--   runtime stdout as the 'SimplifyOn' artifacts — the pass is an
--   optimisation, never a semantic step, and this switch is what keeps
--   that claim measured rather than assumed.
--
--   The body runs under 'timeLimitMicros', and every backend's artifact is
--   forced before the limit is lifted: the @clang@ step forces the
--   elaborated Core in full (the host IR is rendered from it), and the
--   'evaluateWHNF' below forces the four other codegens — the record
--   fields are lazy, and a diverging assembler walk would otherwise escape
--   the limit as a thunk and hang the suite at first use instead of
--   failing the compiling item by name.
compileFromTextWith :: SimplifyMode -> Text -> IO CompiledArtifacts
compileFromTextWith mode src = do
  mArtifacts <- timeout timeLimitMicros $ do
    let ast = case parseProgram src of
          Left e -> error $ "parse failed" <> e
          Right x -> x
        (ptags, core) = case elaborateLowerProgramWith mode ProgramCli (withPrelude ast) of
          Left err -> error $ "elaborate failed" <> show err
          Right (_warns, pt, x) -> (pt, x)
        -- A per-target JVM refusal (method over the 65535-byte ceiling) is a
        -- test bug here, like a parse/elaborate failure — the shared harness
        -- assumes all five backends compile. Programs that exercise the
        -- refusal call 'assembleJVM' directly in their own spec.
        jvmBytes = case assembleJVM ptags core of
          Left e -> error ("assembleJVM refused this program: " <> renderJvmLimitExceeded e)
          Right b -> b
        clrBytes = assembleCLR ptags core
        wasmBytes = assembleWASM ptags core
        jsText = codegenJS ProgramCli ptags core
        jvmText = codegenJVM ptags core
        clrText = codegenCLR ptags core
        wasmText = codegenWASM ptags core
    -- Binary built from the host-native variant — only that one can actually
    -- be linked and run by the host's clang. Snapshot tests pull text for
    -- other hosts via the 'caLLVM' field, which is a closure over 'core'.
    llvmBinPath <- compileLLVMBin (codegenLLVM llvmHostFromSystem ptags core)
    _ <-
      evaluateWHNF
        $ BS.length jvmBytes
        + BS.length clrBytes
        + BS.length wasmBytes
        + T.length jsText
        + T.length jvmText
        + T.length clrText
        + T.length wasmText
    pure
      CompiledArtifacts
        { caLLVM = \host -> codegenLLVM host ptags core,
          caLLVMBinPath = llvmBinPath,
          caJVMBytes = jvmBytes,
          caCLRBytes = clrBytes,
          caWASMBytes = wasmBytes,
          caJS = jsText,
          caJSPretty = codegenJsPretty ProgramCli ptags core,
          caCore = core,
          caJVMText = jvmText,
          caCLRText = clrText,
          caWASMText = wasmText
        }
  case mArtifacts of
    Just artifacts -> pure artifacts
    Nothing ->
      error
        $ "compile did not finish within "
        <> timeLimitText
        <> " — a compiler pass likely diverges on this program"

compileFromFile :: FilePath -> IO CompiledArtifacts
compileFromFile = compileFromFileWith SimplifyOn

compileFromFileWith :: SimplifyMode -> FilePath -> IO CompiledArtifacts
compileFromFileWith mode path = compileFromTextWith mode =<< readFileTextUtf8 path

-- | Compile LLVM IR text to a native binary via @clang -O2@ and return
--   the binary's path. The binary lives in a leaked temp dir under the
--   system temp root — the OS reaps it eventually. We deliberately do
--   not bracket the dir for cleanup: the file has to outlive
--   'compileLLVMBin' so 'runLLVM' can @exec@ it for every QuickCheck
--   input. It also avoids ETXTBSY: see the 'CompiledArtifacts' note —
--   keeping the binary written by @clang@ (an external process) rather
--   than by our test process means no fd in our address space ever
--   points at this file for writing.
compileLLVMBin :: Text -> IO FilePath
compileLLVMBin code = do
  base <- getCanonicalTemporaryDirectory
  dir <- createTempDirectory base "awsum-llvm"
  let llFile = dir </> "out.ll"
      binFile = dir </> "out"
  writeFileText llFile code
  -- AWSUM_CLANG lets CI (and users on hosts where 'clang' on PATH points
  -- at the wrong LLVM, e.g. Stack on Windows prepending GHC's bundled
  -- mingw clang) pin an absolute path. Empty/unset → fall back to PATH.
  clangPath <- fromMaybe "clang" . mfilter (not . null) <$> lookupEnv "AWSUM_CLANG"
  -- Linker flags come from the link-host axis ('LLVMLinkHost'),
  -- not the IR-shape axis ('LLVMHost'): macOS and Linux share
  -- the POSIX IR footer; Windows needs explicit shell32/kernel32
  -- links. See awsum/Main.hs for the same split on the CLI side.
  (ec, out, err) <- readProcessWithExitCode clangPath (["-O2", "-Wno-override-module", llFile, "-o", binFile] <> llvmHostLinkerFlags llvmLinkHostFromSystem) ""
  case ec of
    ExitFailure n ->
      error
        $ toText
        $ "clang failed during compile (exit "
        <> show n
        <> ")\nstderr:\n"
        <> err
        <> "\nstdout:\n"
        <> out
    ExitSuccess -> pure binFile

-- ════════════════════════════════════════════════════════════════════════════
-- Per-backend runners
-- ════════════════════════════════════════════════════════════════════════════

runOn :: Backend -> CompiledArtifacts -> Text -> IO (Either Text Text)
runOn LLVM ca = runLLVM ca.caLLVMBinPath
runOn JVM ca = runJVM ca.caJVMBytes
runOn CLR ca = runCLR ca.caCLRBytes
runOn WASM ca = runWASM ca.caWASMBytes
runOn JS ca = runJs ca.caJS

-- | Run the same input through every backend in parallel, returning the
--   results paired with their backend tag.
runOnAll :: CompiledArtifacts -> Text -> IO [(Backend, Either Text Text)]
runOnAll ca input = do
  ((llvmO, jvmO), ((clrO, wasmO), jsO)) <-
    concurrently
      ( concurrently
          (runOn LLVM ca input)
          (runOn JVM ca input)
      )
      ( concurrently
          ( concurrently
              (runOn CLR ca input)
              (runOn WASM ca input)
          )
          (runOn JS ca input)
      )
  pure
    [ (LLVM, llvmO),
      (JVM, jvmO),
      (CLR, clrO),
      (WASM, wasmO),
      (JS, jsO)
    ]

-- | Spawn @cmd args@ with an empty stdin and capture stdout. 'Left'
--   covers every way the run can fail to produce usable output: the
--   process not starting, exiting non-zero, or blowing 'timeLimitMicros'
--   — on expiry 'timeout' unwinds 'readProcessWithExitCode', whose
--   cleanup terminates the child, so the item fails with the backend's
--   process named and the suite moves on.
runProcArgv :: Text -> FilePath -> [String] -> IO (Either Text Text)
runProcArgv label cmd args = do
  eRes <- try @IOException (timeout timeLimitMicros (readProcessWithExitCode cmd args ""))
  pure $ case eRes of
    Left ex -> Left ("failed to start " <> label <> ": " <> show ex)
    Right Nothing -> Left (label <> " timed out after " <> timeLimitText <> " — the program likely diverges")
    Right (Just (ExitSuccess, out, _)) -> Right (toText out)
    Right (Just (ExitFailure _, _, err)) -> Left (label <> " exited with non-zero status:\n" <> toText err)

runLLVM :: FilePath -> Text -> IO (Either Text Text)
runLLVM binFile input = runProcArgv "binary" binFile [toString input]

runJVM :: ByteString -> Text -> IO (Either Text Text)
runJVM classBytes input = withSystemTempDirectory "awsum" $ \dir -> do
  let classFile = dir </> "AwsumMain.class"
  writeFileBS classFile classBytes
  -- Pin JVM I/O charsets to UTF-8 so 'argv[1]' survives the startup
  -- decode on hosts whose default charset isn't UTF-8 (Windows ANSI).
  -- Stdout side is handled by the 'System.setOut' prologue baked into
  -- emitted 'main'. Keep these flags in sync with awsum/Main.hs's
  -- 'awsum run -t jvm' so the test harness mirrors what users get.
  runProcArgv "java" "java" ["-Dsun.jnu.encoding=UTF-8", "-Dfile.encoding=UTF-8", "-cp", dir, "AwsumMain", toString input]

runCLR :: ByteString -> Text -> IO (Either Text Text)
runCLR dllBytes input = withSystemTempDirectory "awsum" $ \dir -> do
  let dllFile = dir </> "AwsumMain.dll"
      rcFile = dir </> "AwsumMain.runtimeconfig.json"
  writeFileBS dllFile dllBytes
  writeFileText rcFile runtimeConfigJson
  runProcArgv "dotnet" "dotnet" [dllFile, toString input]

runWASM :: ByteString -> Text -> IO (Either Text Text)
runWASM wasmBytes input = withSystemTempDirectory "awsum" $ \dir -> do
  let wasmFile = dir </> "out.wasm"
  writeFileBS wasmFile wasmBytes
  runProcArgv "wasmtime" "wasmtime" [wasmFile, toString input]

runJs :: Text -> Text -> IO (Either Text Text)
runJs code input = withSystemTempDirectory "awsum" $ \dir -> do
  let tempFile = dir </> "out.js"
  writeFileText tempFile code
  runProcArgv "node" "node" [toString tempFile, toString input]

-- ════════════════════════════════════════════════════════════════════════════
-- Per-backend runners — stdin input variant (property tests)
-- ════════════════════════════════════════════════════════════════════════════

-- | Run a child process feeding the input as **raw bytes** on its
--   stdin (rather than as a CLI arg). Used by property tests after the
--   migration to 'IO.Stdin.readAllString' — argv runs through the host's
--   startup decoder ('sun.jnu.encoding' on Windows JVM, ANSI codepage
--   for MSVCRT) and silently mangles supplementary-plane characters,
--   while stdin is delivered verbatim to the program.
--
--   The handles are forced to binary mode so the Haskell default
--   encoding (locale on POSIX, ANSI on Windows) doesn't re-encode
--   anything between us and the child. Stdout and stderr are read
--   concurrently with the write so a child that emits more than one
--   pipe-buffer's worth of bytes (64 KiB on Linux, often less on
--   other hosts) doesn't deadlock waiting for us to drain it before
--   we finish sending input.
--
--   The whole exchange runs under 'timeLimitMicros'; on expiry the
--   'bracket''s 'cleanupProcess' terminates the child and closes the
--   pipes (which also lets the reader threads finish), so a diverging
--   program becomes a named failure instead of a hang.
runProcStdinBytes :: FilePath -> [String] -> ByteString -> IO (Either Text Text)
runProcStdinBytes cmd args input = do
  eRes <-
    try @IOException
      $ timeout timeLimitMicros
      $ bracket
        ( createProcess
            (proc cmd args)
              { std_in = CreatePipe,
                std_out = CreatePipe,
                std_err = CreatePipe
              }
        )
        cleanupProcess
      $ \case
        (Just hin, Just hout, Just herr, ph) -> do
          hSetBinaryMode hin True
          hSetBinaryMode hout True
          hSetBinaryMode herr True
          writeAsync <- async $ do
            BS.hPut hin input
            hClose hin
          outAsync <- async (BS.hGetContents hout)
          errAsync <- async (BS.hGetContents herr)
          outBs <- wait outAsync
          errBs <- wait errAsync
          wait writeAsync
          ec <- waitForProcess ph
          pure (ec, outBs, errBs)
        _ -> error "runProcStdinBytes: CreatePipe produced no handle"
  pure $ case eRes of
    Left ex -> Left ("failed to start " <> toText cmd <> ": " <> show ex)
    Right Nothing -> Left (toText cmd <> " timed out after " <> timeLimitText <> " — the program likely diverges")
    Right (Just (ExitSuccess, out, _)) -> Right (decodeUtf8 out)
    Right (Just (ExitFailure _, _out, err)) -> Left (toText cmd <> " exited with non-zero status:\n" <> decodeUtf8 err)

-- | Feed the input as UTF-8 bytes; the 'ByteString' variant
--   'runOnStdinBytes' takes raw bytes for tests that need malformed input.
runOnStdin :: Backend -> CompiledArtifacts -> Text -> IO (Either Text Text)
runOnStdin be ca input = runOnStdinBytes be ca (encodeUtf8 input)

runOnStdinBytes :: Backend -> CompiledArtifacts -> ByteString -> IO (Either Text Text)
runOnStdinBytes LLVM ca = runProcStdinBytes ca.caLLVMBinPath []
runOnStdinBytes JVM ca = runJVMStdin ca.caJVMBytes
runOnStdinBytes CLR ca = runCLRStdin ca.caCLRBytes
runOnStdinBytes WASM ca = runWASMStdin ca.caWASMBytes
runOnStdinBytes JS ca = runJsStdin ca.caJS

-- | Stdin-input counterpart to 'runOnAll'. Used by property tests after
--   their 'main' was migrated from 'IO.Args.getArgs' to
--   'IO.Stdin.readAllString'.
runOnAllStdin :: CompiledArtifacts -> Text -> IO [(Backend, Either Text Text)]
runOnAllStdin ca input = runOnAllStdinBytes ca (encodeUtf8 input)

-- | Raw-bytes counterpart to 'runOnAllStdin' — feeds an arbitrary
--   'ByteString' (possibly malformed UTF-8) on stdin. Used by the
--   'IO.Stdin.readAllString' / 'IO.Stdin.readAllBytes' property tests,
--   whose generators produce byte sequences a 'Text' could not hold.
runOnAllStdinBytes :: CompiledArtifacts -> ByteString -> IO [(Backend, Either Text Text)]
runOnAllStdinBytes ca input = do
  ((llvmO, jvmO), ((clrO, wasmO), jsO)) <-
    concurrently
      ( concurrently
          (runOnStdinBytes LLVM ca input)
          (runOnStdinBytes JVM ca input)
      )
      ( concurrently
          ( concurrently
              (runOnStdinBytes CLR ca input)
              (runOnStdinBytes WASM ca input)
          )
          (runOnStdinBytes JS ca input)
      )
  pure
    [ (LLVM, llvmO),
      (JVM, jvmO),
      (CLR, clrO),
      (WASM, wasmO),
      (JS, jsO)
    ]

runJVMStdin :: ByteString -> ByteString -> IO (Either Text Text)
runJVMStdin classBytes input = withSystemTempDirectory "awsum" $ \dir -> do
  let classFile = dir </> "AwsumMain.class"
  writeFileBS classFile classBytes
  -- '-Dsun.jnu.encoding' only governs argv; stdin reads through
  -- 'System.in' which we wire to an explicit UTF-8 'StreamReader' on
  -- the program side. '-Dfile.encoding' still matters for stdout
  -- formatting in case other code paths reach the default charset.
  runProcStdinBytes "java" ["-Dsun.jnu.encoding=UTF-8", "-Dfile.encoding=UTF-8", "-cp", dir, "AwsumMain"] input

runCLRStdin :: ByteString -> ByteString -> IO (Either Text Text)
runCLRStdin dllBytes input = withSystemTempDirectory "awsum" $ \dir -> do
  let dllFile = dir </> "AwsumMain.dll"
      rcFile = dir </> "AwsumMain.runtimeconfig.json"
  writeFileBS dllFile dllBytes
  writeFileText rcFile runtimeConfigJson
  runProcStdinBytes "dotnet" [dllFile] input

runWASMStdin :: ByteString -> ByteString -> IO (Either Text Text)
runWASMStdin wasmBytes input = withSystemTempDirectory "awsum" $ \dir -> do
  let wasmFile = dir </> "out.wasm"
  writeFileBS wasmFile wasmBytes
  runProcStdinBytes "wasmtime" [wasmFile] input

runJsStdin :: Text -> ByteString -> IO (Either Text Text)
runJsStdin code input = withSystemTempDirectory "awsum" $ \dir -> do
  let tempFile = dir </> "out.js"
  writeFileText tempFile code
  runProcStdinBytes "node" [tempFile] input

-- | CLR runtime config for the test harness. Enables Server GC for the same
--   reason as the awsum/Main.hs and bench/Bench.hs copies it mirrors; keep all
--   three in sync.
runtimeConfigJson :: Text
runtimeConfigJson =
  "{\n\
  \  \"runtimeOptions\": {\n\
  \    \"tfm\": \"net9.0\",\n\
  \    \"framework\": {\n\
  \      \"name\": \"Microsoft.NETCore.App\",\n\
  \      \"version\": \"9.0.0\"\n\
  \    },\n\
  \    \"rollForward\": \"LatestMajor\",\n\
  \    \"configProperties\": {\n\
  \      \"System.GC.Server\": true\n\
  \    }\n\
  \  }\n\
  \}\n"
