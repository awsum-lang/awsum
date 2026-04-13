module Awsum.ProgramSnapshotsSpec (spec) where

import Awsum.Codegen.JS (codegenJS)
import Awsum.Codegen.JVM (codegenJVM)
import Awsum.Codegen.JVM.Assemble (assembleJVM)
import Awsum.Codegen.LLVM (codegenLLVM)
import Awsum.Codegen.Lua (codegenLua)
import Awsum.Codegen.WASM (codegenWASM)
import Awsum.Codegen.WASM.Assemble (assembleWASM)
import Awsum.Core
import Awsum.ElaborateLower (elaborateLowerProgram)
import Awsum.Format (formatSource)
import Awsum.Parser (parseProgram)
import Awsum.Syntax
import Common.File
import Control.Exception (IOException, try)
import Data.ByteString qualified as BS
import Matchers
import Relude
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Test.Hspec

spec :: Spec
spec = describe "Program snapshots" $ do
  testProgram "hello.aww" ["hello.input1.txt", "hello.input2.txt", "hello.input3.txt"]
  testProgram "polymorphism.aww" ["polymorphism.input1.txt"]
  testProgram "comments.aww" []

sourcesDir :: Text
sourcesDir = "test/sources/"

data CompileResult = CompileResult
  { ast :: Program,
    core :: CoreProgram,
    formattedSource :: Text,
    jsCompiledCode :: Text,
    luaCompiledCode :: Text,
    llvmCompiledCode :: Text,
    jvmCompiledCode :: Text,
    jvmClassBytes :: ByteString,
    wasmCompiledCode :: Text,
    wasmBinary :: ByteString
  }

compileAll :: Text -> IO CompileResult
compileAll sourceFile = do
  src <- readFileTextUtf8 $ toString $ sourcesDir <> sourceFile
  ast <- case parseProgram src of
    Left e -> error $ "parse failed" <> e
    Right x -> pure x
  core <- case elaborateLowerProgram ast of
    Left err -> error $ "elaborate failed" <> show err
    Right x -> pure x
  formattedSource <- case formatSource src of
    Left err -> error $ "format failed" <> show err
    Right x -> pure x
  pure
    CompileResult
      { ast = ast,
        core = core,
        formattedSource = formattedSource,
        jsCompiledCode = codegenJS core,
        luaCompiledCode = codegenLua core,
        llvmCompiledCode = codegenLLVM core,
        jvmCompiledCode = codegenJVM core,
        jvmClassBytes = assembleJVM core,
        wasmCompiledCode = codegenWASM core,
        wasmBinary = assembleWASM core
      }

testProgram :: Text -> [Text] -> Spec
testProgram sourceFile inputFiles = do
  beforeAll (compileAll sourceFile) $ describe (toString sourceFile) $ do
    it "AST should match snapshot" $ \res -> do
      res.ast `shouldMatchShowSnapshot` (sourceFile <> "/ast.txt")
    it "Core should match snapshot" $ \res -> do
      res.core `shouldMatchShowSnapshot` (sourceFile <> "/core.txt")
    it "Formatted source should match snapshot" $ \res -> do
      res.formattedSource `shouldMatchTextSnapshot` (sourceFile <> "/formatted." <> sourceFile)
    it "JS code should match snapshot" $ \res -> do
      res.jsCompiledCode `shouldMatchTextSnapshot` (sourceFile <> "/compiled.js")
    it "Lua code should match snapshot" $ \res -> do
      res.luaCompiledCode `shouldMatchTextSnapshot` (sourceFile <> "/compiled.lua")
    it "LLVM code should match snapshot" $ \res -> do
      res.llvmCompiledCode `shouldMatchTextSnapshot` (sourceFile <> "/compiled.ll")
    it "JVM code should match snapshot" $ \res -> do
      res.jvmCompiledCode `shouldMatchTextSnapshot` (sourceFile <> "/compiled.j")
    it "WASM code should match snapshot" $ \res -> do
      res.wasmCompiledCode `shouldMatchTextSnapshot` (sourceFile <> "/compiled.wat")

  traverse_ (testProgramAgainstInput sourceFile) inputFiles

testProgramAgainstInput :: Text -> Text -> Spec
testProgramAgainstInput sourceFile inputFile = do
  let prepare :: IO (Text, Text, Text, Text, Text) = do
        input <- readFileTextUtf8 $ toString $ sourcesDir <> inputFile

        -- TODO: Make program compile and files be written exactly once per sourceFile
        res <- compileAll sourceFile

        jsRes <- runJs res.jsCompiledCode input
        jsOutput <- case jsRes of
          Left e -> error $ "JS failed" <> e
          Right x -> pure x
        luaRes <- runLua res.luaCompiledCode input
        luaOutput <- case luaRes of
          Left e -> error $ "Lua failed" <> e
          Right x -> pure x
        llvmRes <- runLLVM res.llvmCompiledCode input
        llvmOutput <- case llvmRes of
          Left e -> error $ "LLVM failed" <> e
          Right x -> pure x
        jvmRes <- runJVM res.jvmClassBytes input
        jvmOutput <- case jvmRes of
          Left e -> error $ "JVM failed" <> e
          Right x -> pure x
        wasmRes <- runWASM res.wasmBinary input
        wasmOutput <- case wasmRes of
          Left e -> error $ "WASM failed" <> e
          Right x -> pure x
        pure (jsOutput, luaOutput, llvmOutput, jvmOutput, wasmOutput)
  beforeAll prepare $ describe (toString $ inputFile) $ do
    it "JS stdout should match snapshot" $ \(jsOutput, _luaOutput, _llvmOutput, _jvmOutput, _wasmOutput) -> do
      jsOutput `shouldMatchTextSnapshot` (sourceFile <> "/output." <> inputFile)
    it "JS stdout and Lua stdout should be equivalent" $ \(jsOutput, luaOutput, _llvmOutput, _jvmOutput, _wasmOutput) -> do
      jsOutput `shouldBe` luaOutput
    it "JS stdout and LLVM stdout should be equivalent" $ \(jsOutput, _luaOutput, llvmOutput, _jvmOutput, _wasmOutput) -> do
      jsOutput `shouldBe` llvmOutput
    it "JS stdout and JVM stdout should be equivalent" $ \(jsOutput, _luaOutput, _llvmOutput, jvmOutput, _wasmOutput) -> do
      jsOutput `shouldBe` jvmOutput
    it "JS stdout and WASM stdout should be equivalent" $ \(jsOutput, _luaOutput, _llvmOutput, _jvmOutput, wasmOutput) -> do
      jsOutput `shouldBe` wasmOutput

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
  BS.writeFile classFile classBytes
  eRes <- try @IOException (readProcessWithExitCode "java" ["-cp", dir, "AwsumMain", toString input] "")
  case eRes of
    Left ex -> pure (Left ("failed to start java: " <> show ex))
    Right (ExitSuccess, out, _) -> pure (Right (toText out))
    Right (ExitFailure _, _out, err) ->
      pure (Left ("java exited with non-zero status:\n" <> toText err))

runWASM :: ByteString -> Text -> IO (Either Text Text)
runWASM wasmBytes input = withSystemTempDirectory "awsum" $ \dir -> do
  let wasmFile = dir </> "out.wasm"
  BS.writeFile wasmFile wasmBytes
  eRes <- try @IOException (readProcessWithExitCode "wasmtime" [wasmFile, toString input] "")
  case eRes of
    Left ex -> pure (Left ("failed to start wasmtime: " <> show ex))
    Right (ExitSuccess, out, _) -> pure (Right (toText out))
    Right (ExitFailure _, _out, err) ->
      pure (Left ("wasmtime exited with non-zero status:\n" <> toText err))
