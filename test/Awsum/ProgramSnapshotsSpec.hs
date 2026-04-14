module Awsum.ProgramSnapshotsSpec (spec) where

import Awsum.Codegen.CLR (codegenCLR)
import Awsum.Codegen.CLR.Assemble (assembleCLR)
import Awsum.Codegen.JS (codegenJS)
import Awsum.Codegen.JVM (codegenJVM)
import Awsum.Codegen.JVM.Assemble (assembleJVM)
import Awsum.Codegen.LLVM (codegenLLVM)
import Awsum.Codegen.Lua (codegenLua)
import Awsum.Codegen.WASM (codegenWASM)
import Awsum.Codegen.WASM.Assemble (assembleWASM)
import Awsum.Core
import Awsum.ElaborateLower (elaborateLowerProgram)
import Awsum.Parser (parseProgram)
import Awsum.Syntax
import Common.File
import Control.Concurrent.MVar (modifyMVar)
import Control.Exception (IOException, try)
import Matchers
import Relude
import System.Directory (doesDirectoryExist, listDirectory)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Test.Hspec

spec :: Spec
spec = describe "Program snapshots" $ do
  testNames <- runIO discoverTests
  traverse_ testProgram testNames

sourcesDir :: FilePath
sourcesDir = "test/sources/successful"

discoverTests :: IO [FilePath]
discoverTests = do
  entries <- listDirectory sourcesDir
  sort <$> filterM (\e -> doesDirectoryExist (sourcesDir </> e)) entries

data CompileResult = CompileResult
  { ast :: Program,
    core :: CoreProgram,
    llvmCompiledCode :: Text,
    jvmCompiledCode :: Text,
    jvmClassBytes :: ByteString,
    clrCompiledCode :: Text,
    clrBinary :: ByteString,
    wasmCompiledCode :: Text,
    wasmBinary :: ByteString,
    jsCompiledCode :: Text,
    luaCompiledCode :: Text
  }

compileAll :: FilePath -> IO CompileResult
compileAll testName = do
  src <- readFileTextUtf8 $ sourcesDir </> testName </> "code" </> "Main.aww"
  ast <- case parseProgram src of
    Left e -> error $ "parse failed" <> e
    Right x -> pure x
  core <- case elaborateLowerProgram ast of
    Left err -> error $ "elaborate failed" <> show err
    Right x -> pure x
  pure
    CompileResult
      { ast = ast,
        core = core,
        llvmCompiledCode = codegenLLVM core,
        jvmCompiledCode = codegenJVM core,
        jvmClassBytes = assembleJVM core,
        clrCompiledCode = codegenCLR core,
        clrBinary = assembleCLR core,
        wasmCompiledCode = codegenWASM core,
        wasmBinary = assembleWASM core,
        jsCompiledCode = codegenJS core,
        luaCompiledCode = codegenLua core
      }

testProgram :: FilePath -> Spec
testProgram testName = do
  stdinFiles <- runIO discoverStdinFiles
  compileOnce <- runIO $ do
    ref <- newMVar Nothing
    pure $ modifyMVar ref $ \case
      Just r -> pure (Just r, r)
      Nothing -> do
        r <- compileAll testName
        pure (Just r, r)
  let snap :: Text
      snap = "successful/" <> toText testName
  beforeAll compileOnce $ describe testName $ do
    it "AST should match snapshot" $ \res -> do
      res.ast `shouldMatchShowSnapshot` (snap <> "/compiler/ast.txt")
    it "Core should match snapshot" $ \res -> do
      res.core `shouldMatchShowSnapshot` (snap <> "/compiler/core.txt")
    it "LLVM code should match snapshot" $ \res -> do
      res.llvmCompiledCode `shouldMatchTextSnapshot` (snap <> "/compiler/compiled.ll")
    it "JVM code should match snapshot" $ \res -> do
      res.jvmCompiledCode `shouldMatchTextSnapshot` (snap <> "/compiler/compiled.j")
    it "CLR code should match snapshot" $ \res -> do
      res.clrCompiledCode `shouldMatchTextSnapshot` (snap <> "/compiler/compiled.il")
    it "WASM code should match snapshot" $ \res -> do
      res.wasmCompiledCode `shouldMatchTextSnapshot` (snap <> "/compiler/compiled.wat")
    it "JS code should match snapshot" $ \res -> do
      res.jsCompiledCode `shouldMatchTextSnapshot` (snap <> "/compiler/compiled.js")
    it "Lua code should match snapshot" $ \res -> do
      res.luaCompiledCode `shouldMatchTextSnapshot` (snap <> "/compiler/compiled.lua")

  case stdinFiles of
    [] -> testProgramNoInput testName compileOnce
    _ -> traverse_ (testProgramWithInput testName compileOnce) stdinFiles
  where
    discoverStdinFiles :: IO [FilePath]
    discoverStdinFiles = do
      let stdinDir :: FilePath
          stdinDir = sourcesDir </> testName </> "stdin"
      exists <- doesDirectoryExist stdinDir
      if exists
        then sort <$> listDirectory stdinDir
        else pure []

testProgramNoInput :: FilePath -> IO CompileResult -> Spec
testProgramNoInput testName compileOnce = do
  let prepare :: IO (Text, Text, Text, Text, Text, Text) = do
        res <- compileOnce
        runAllBackends res ""
  let snap :: Text
      snap = "successful/" <> toText testName <> "/output/no-stdin.txt"
  beforeAll prepare $ describe "no-stdin" $ do
    it "LLVM stdout should match snapshot" $ \(llvmOutput, _jvmOutput, _clrOutput, _wasmOutput, _jsOutput, _luaOutput) -> do
      llvmOutput `shouldMatchTextSnapshot` snap
    it "LLVM stdout and JVM stdout should be equivalent" $ \(llvmOutput, jvmOutput, _clrOutput, _wasmOutput, _jsOutput, _luaOutput) -> do
      llvmOutput `shouldBe` jvmOutput
    it "LLVM stdout and CLR stdout should be equivalent" $ \(llvmOutput, _jvmOutput, clrOutput, _wasmOutput, _jsOutput, _luaOutput) -> do
      llvmOutput `shouldBe` clrOutput
    it "LLVM stdout and WASM stdout should be equivalent" $ \(llvmOutput, _jvmOutput, _clrOutput, wasmOutput, _jsOutput, _luaOutput) -> do
      llvmOutput `shouldBe` wasmOutput
    it "LLVM stdout and JS stdout should be equivalent" $ \(llvmOutput, _jvmOutput, _clrOutput, _wasmOutput, jsOutput, _luaOutput) -> do
      llvmOutput `shouldBe` jsOutput
    it "LLVM stdout and Lua stdout should be equivalent" $ \(llvmOutput, _jvmOutput, _clrOutput, _wasmOutput, _jsOutput, luaOutput) -> do
      llvmOutput `shouldBe` luaOutput

testProgramWithInput :: FilePath -> IO CompileResult -> FilePath -> Spec
testProgramWithInput testName compileOnce inputFile = do
  let prepare :: IO (Text, Text, Text, Text, Text, Text) = do
        input <- readFileTextUtf8 $ sourcesDir </> testName </> "stdin" </> inputFile
        res <- compileOnce
        runAllBackends res input
  let snap :: Text
      snap = "successful/" <> toText testName <> "/output/" <> toText inputFile
  beforeAll prepare $ describe inputFile $ do
    it "LLVM stdout should match snapshot" $ \(llvmOutput, _jvmOutput, _clrOutput, _wasmOutput, _jsOutput, _luaOutput) -> do
      llvmOutput `shouldMatchTextSnapshot` snap
    it "LLVM stdout and JVM stdout should be equivalent" $ \(llvmOutput, jvmOutput, _clrOutput, _wasmOutput, _jsOutput, _luaOutput) -> do
      llvmOutput `shouldBe` jvmOutput
    it "LLVM stdout and CLR stdout should be equivalent" $ \(llvmOutput, _jvmOutput, clrOutput, _wasmOutput, _jsOutput, _luaOutput) -> do
      llvmOutput `shouldBe` clrOutput
    it "LLVM stdout and WASM stdout should be equivalent" $ \(llvmOutput, _jvmOutput, _clrOutput, wasmOutput, _jsOutput, _luaOutput) -> do
      llvmOutput `shouldBe` wasmOutput
    it "LLVM stdout and JS stdout should be equivalent" $ \(llvmOutput, _jvmOutput, _clrOutput, _wasmOutput, jsOutput, _luaOutput) -> do
      llvmOutput `shouldBe` jsOutput
    it "LLVM stdout and Lua stdout should be equivalent" $ \(llvmOutput, _jvmOutput, _clrOutput, _wasmOutput, _jsOutput, luaOutput) -> do
      llvmOutput `shouldBe` luaOutput

runAllBackends :: CompileResult -> Text -> IO (Text, Text, Text, Text, Text, Text)
runAllBackends res input = do
  llvmRes <- runLLVM res.llvmCompiledCode input
  llvmOutput <- case llvmRes of
    Left e -> error $ "LLVM failed" <> e
    Right x -> pure x
  jvmRes <- runJVM res.jvmClassBytes input
  jvmOutput <- case jvmRes of
    Left e -> error $ "JVM failed" <> e
    Right x -> pure x
  clrRes <- runCLR res.clrBinary input
  clrOutput <- case clrRes of
    Left e -> error $ "CLR failed" <> e
    Right x -> pure x
  wasmRes <- runWASM res.wasmBinary input
  wasmOutput <- case wasmRes of
    Left e -> error $ "WASM failed" <> e
    Right x -> pure x
  jsRes <- runJs res.jsCompiledCode input
  jsOutput <- case jsRes of
    Left e -> error $ "JS failed" <> e
    Right x -> pure x
  luaRes <- runLua res.luaCompiledCode input
  luaOutput <- case luaRes of
    Left e -> error $ "Lua failed" <> e
    Right x -> pure x
  pure (llvmOutput, jvmOutput, clrOutput, wasmOutput, jsOutput, luaOutput)

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

runLua :: Text -> Text -> IO (Either Text Text)
runLua code input = withSystemTempDirectory "awsum" $ \dir -> do
  let tempFile = dir </> "out.lua"
  writeFileText tempFile code
  eRes <- try @IOException (readProcessWithExitCode "lua" [toString tempFile, toString input] "")
  case eRes of
    Left ex -> pure (Left ("failed to start lua: " <> show ex))
    Right (ExitSuccess, out, _) -> pure (Right (toText out))
    Right (ExitFailure _, _out, err) ->
      pure (Left ("lua exited with non-zero status:\n" <> toText err))

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
