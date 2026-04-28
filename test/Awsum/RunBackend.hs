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
import System.IO.Temp (withSystemTempDirectory)
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

-- | The minimum each backend needs to actually run a compiled program:
--   text for backends whose host accepts source (LLVM IR is fed through
--   @clang@; JS is interpreted); bytes for backends whose host
--   takes a binary (.class / .dll / .wasm).
data CompiledArtifacts = CompiledArtifacts
  { caLLVM :: Text,
    caJVMBytes :: ByteString,
    caCLRBytes :: ByteString,
    caWASMBytes :: ByteString,
    caJS :: Text
  }

-- | Run the compile pipeline (parse → withPrelude → elaborate → codegen)
--   on a piece of source and return the runnable artifacts. Pure modulo
--   `error` on parse / elaborate failure (the test runner is happy to
--   crash here — bad source is a test bug, not a runtime concern).
compileFromText :: Text -> CompiledArtifacts
compileFromText src =
  let ast = case parseProgram src of
        Left e -> error $ "parse failed" <> e
        Right x -> x
      core = case elaborateLowerProgram ProgramCli (withPrelude ast) of
        Left err -> error $ "elaborate failed" <> show err
        Right (_warns, x) -> x
   in CompiledArtifacts
        { caLLVM = codegenLLVM core,
          caJVMBytes = assembleJVM core,
          caCLRBytes = assembleCLR core,
          caWASMBytes = assembleWASM core,
          caJS = codegenJS ProgramCli core
        }

compileFromFile :: FilePath -> IO CompiledArtifacts
compileFromFile path = compileFromText <$> readFileTextUtf8 path

-- ════════════════════════════════════════════════════════════════════════════
-- Per-backend runners
-- ════════════════════════════════════════════════════════════════════════════

runOn :: Backend -> CompiledArtifacts -> Text -> IO (Either Text Text)
runOn LLVM ca = runLLVM ca.caLLVM
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

runLLVM :: Text -> Text -> IO (Either Text Text)
runLLVM code input = withSystemTempDirectory "awsum" $ \dir -> do
  let llFile = dir </> "out.ll"
      binFile = dir </> "out"
  writeFileText llFile code
  eClang <- try @IOException (readProcessWithExitCode "clang" ["-O2", "-Wno-override-module", llFile, "-o", binFile] "")
  case eClang of
    Left ex -> pure (Left ("failed to start clang: " <> show ex))
    Right (ExitFailure _, _, err) ->
      pure (Left ("clang exited with non-zero status:\n" <> toText err))
    Right (ExitSuccess, _, _) -> do
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
  eRes <- try @IOException (readProcessWithExitCode "java" ["-cp", dir, "AwsumMain", toString input] "")
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
