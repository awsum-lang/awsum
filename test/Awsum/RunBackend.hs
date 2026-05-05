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
    compileFromText,
    compileFromFile,
    runOn,
    runOnAll,
  )
where

import Awsum.Codegen.CLR.Assemble (assembleCLR)
import Awsum.Codegen.JS (codegenJS)
import Awsum.Codegen.JVM.Assemble (assembleJVM)
import Awsum.Codegen.LLVM (codegenLLVM)
import Awsum.Codegen.WASM.Assemble (assembleWASM)
import Awsum.ElaborateLower (elaborateLowerProgram)
import Awsum.Parser (parseProgram)
import Awsum.Prelude (withPrelude)
import Awsum.Program (ProgramType (..))
import Common.File
import Control.Concurrent.Async (concurrently)
import Control.Exception (IOException, try)
import Relude
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (createTempDirectory, getCanonicalTemporaryDirectory, withSystemTempDirectory)
import System.Process (readProcessWithExitCode)

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
--   a golden @.ll@ file — it isn't needed at run time.
data CompiledArtifacts = CompiledArtifacts
  { caLLVM :: Text,
    caLLVMBinPath :: FilePath,
    caJVMBytes :: ByteString,
    caCLRBytes :: ByteString,
    caWASMBytes :: ByteString,
    caJS :: Text
  }

-- | Run the compile pipeline (parse → withPrelude → elaborate → codegen)
--   on a piece of source and return the runnable artifacts. Crashes on
--   parse / elaborate failure — bad source is a test bug, not a runtime
--   concern. Lives in IO because LLVM's runnable artifact is the native
--   binary, which means shelling out to @clang@ once per source. Doing
--   it here (rather than inside 'runLLVM') means QuickCheck's N inputs
--   per property cost one @clang@, not N.
compileFromText :: Text -> IO CompiledArtifacts
compileFromText src = do
  let ast = case parseProgram src of
        Left e -> error $ "parse failed" <> e
        Right x -> x
      core = case elaborateLowerProgram ProgramCli (withPrelude ast) of
        Left err -> error $ "elaborate failed" <> show err
        Right (_warns, x) -> x
      llvmText = codegenLLVM core
  llvmBinPath <- compileLLVMBin llvmText
  pure
    CompiledArtifacts
      { caLLVM = llvmText,
        caLLVMBinPath = llvmBinPath,
        caJVMBytes = assembleJVM core,
        caCLRBytes = assembleCLR core,
        caWASMBytes = assembleWASM core,
        caJS = codegenJS ProgramCli core
      }

compileFromFile :: FilePath -> IO CompiledArtifacts
compileFromFile path = compileFromText =<< readFileTextUtf8 path

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
  (ec, out, err) <- readProcessWithExitCode clangPath ["-O2", "-Wno-override-module", llFile, "-o", binFile] ""
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

runLLVM :: FilePath -> Text -> IO (Either Text Text)
runLLVM binFile input = do
  eRun <- try @IOException (readProcessWithExitCode binFile [toString input] "")
  case eRun of
    Left ex -> pure (Left ("failed to run binary: " <> show ex))
    Right (ExitSuccess, out, _) -> pure (Right (toText out))
    Right (ExitFailure _, _, err) ->
      pure (Left ("binary exited with non-zero status:\n" <> toText err))

runJVM :: ByteString -> Text -> IO (Either Text Text)
runJVM classBytes input = withSystemTempDirectory "awsum" $ \dir -> do
  let classFile = dir </> "AwsumMain.class"
  writeFileBS classFile classBytes
  -- Pin JVM I/O charsets to UTF-8 so 'argv[1]' survives the startup
  -- decode on hosts whose default charset isn't UTF-8 (Windows ANSI).
  -- Stdout side is handled by the 'System.setOut' prologue baked into
  -- emitted 'main'. Keep these flags in sync with awsum/Main.hs's
  -- 'awsum run -t jvm' so the test harness mirrors what users get.
  eRes <- try @IOException (readProcessWithExitCode "java" ["-Dsun.jnu.encoding=UTF-8", "-Dfile.encoding=UTF-8", "-cp", dir, "AwsumMain", toString input] "")
  case eRes of
    Left ex -> pure (Left ("failed to start java: " <> show ex))
    Right (ExitSuccess, out, _) -> pure (Right (toText out))
    Right (ExitFailure _, _out, err) ->
      pure (Left ("java exited with non-zero status:\n" <> toText err))

runCLR :: ByteString -> Text -> IO (Either Text Text)
runCLR dllBytes input = withSystemTempDirectory "awsum" $ \dir -> do
  let dllFile = dir </> "AwsumMain.dll"
      rcFile = dir </> "AwsumMain.runtimeconfig.json"
  writeFileBS dllFile dllBytes
  writeFileText rcFile runtimeConfigJson
  eRes <- try @IOException (readProcessWithExitCode "dotnet" [dllFile, toString input] "")
  case eRes of
    Left ex -> pure (Left ("failed to start dotnet: " <> show ex))
    Right (ExitSuccess, out, _) -> pure (Right (toText out))
    Right (ExitFailure _, _out, err) ->
      pure (Left ("dotnet exited with non-zero status:\n" <> toText err))

runWASM :: ByteString -> Text -> IO (Either Text Text)
runWASM wasmBytes input = withSystemTempDirectory "awsum" $ \dir -> do
  let wasmFile = dir </> "out.wasm"
  writeFileBS wasmFile wasmBytes
  eRes <- try @IOException (readProcessWithExitCode "wasmtime" [wasmFile, toString input] "")
  case eRes of
    Left ex -> pure (Left ("failed to start wasmtime: " <> show ex))
    Right (ExitSuccess, out, _) -> pure (Right (toText out))
    Right (ExitFailure _, _out, err) ->
      pure (Left ("wasmtime exited with non-zero status:\n" <> toText err))

runJs :: Text -> Text -> IO (Either Text Text)
runJs code input = withSystemTempDirectory "awsum" $ \dir -> do
  let tempFile = dir </> "out.js"
  writeFileText tempFile code
  eRes <- try @IOException (readProcessWithExitCode "node" [toString tempFile, toString input] "")
  case eRes of
    Left ex -> pure (Left ("failed to start node: " <> show ex))
    Right (ExitSuccess, out, _) -> pure (Right (toText out))
    Right (ExitFailure _, _out, err) ->
      pure (Left ("node exited with non-zero status:\n" <> toText err))

runtimeConfigJson :: Text
runtimeConfigJson =
  "{\n\
  \  \"runtimeOptions\": {\n\
  \    \"tfm\": \"net9.0\",\n\
  \    \"framework\": {\n\
  \      \"name\": \"Microsoft.NETCore.App\",\n\
  \      \"version\": \"9.0.0\"\n\
  \    },\n\
  \    \"rollForward\": \"LatestMajor\"\n\
  \  }\n\
  \}\n"
