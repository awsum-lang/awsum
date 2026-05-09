module Awsum.ProgramSnapshotsSpec (spec) where

import Awsum.Codegen.CLR (codegenCLR)
import Awsum.Codegen.JVM (codegenJVM)
import Awsum.Codegen.LLVM (allLLVMHosts, llvmHostName)
import Awsum.Codegen.WASM (codegenWASM)
import Awsum.Core
import Awsum.ElaborateLower (elaborateLowerProgram)
import Awsum.Parser (parseProgram)
import Awsum.Prelude (withPrelude)
import Awsum.Program (ProgramType (..))
import Awsum.RunBackend (Backend (..), CompiledArtifacts (..), runOn)
import Awsum.RunBackend qualified as RB
import Awsum.Symbols (symbolsOfProgram, symbolsToJson)
import Awsum.Syntax
import Common.File
import Control.Concurrent.Async (concurrently)
import Control.Concurrent.MVar (modifyMVar)
import Matchers
import Relude
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath ((</>))
import Test.Hspec

spec :: Spec
spec = describe "Program snapshots" $ parallel $ do
  -- 'parallel' here makes sibling programs run in parallel with each
  -- other; the inner 'parallel' inside 'testProgram' keeps the per-
  -- program tests parallelisable too. Each 'beforeAll' block scopes
  -- its own 'compileOnce', so parallel programs don't fight over a
  -- shared MVar.
  testNames <- runIO discoverTests
  traverse_ testProgram testNames

sourcesDir :: FilePath
sourcesDir = "test/sources/successful"

discoverTests :: IO [FilePath]
discoverTests = do
  entries <- listDirectory sourcesDir
  sort <$> filterM (\e -> doesDirectoryExist (sourcesDir </> e)) entries

-- | Snapshot tests need everything: ast / core / per-backend text for
-- golden comparison, plus the runnable artifacts to actually exercise
-- the program. Property tests, by contrast, only need 'CompiledArtifacts'.
data CompileResult = CompileResult
  { artifacts :: CompiledArtifacts,
    ast :: Program,
    core :: CoreProgram,
    symbolsJson :: Text,
    jvmText :: Text,
    clrText :: Text,
    wasmText :: Text
  }

compileAll :: FilePath -> IO CompileResult
compileAll testName = do
  src <- readFileTextUtf8 $ sourcesDir </> testName </> "code" </> "Main.aww"
  ast <- case parseProgram src of
    Left e -> error $ "parse failed" <> e
    Right x -> pure x
  (ptags, core) <- case elaborateLowerProgram ProgramCli (withPrelude ast) of
    Left err -> error $ "elaborate failed" <> show err
    Right (_warns, pt, x) -> pure (pt, x)
  artifacts <- RB.compileFromText src
  pure
    CompileResult
      { artifacts = artifacts,
        ast = ast,
        core = core,
        symbolsJson = symbolsToJson (symbolsOfProgram ast),
        jvmText = codegenJVM ptags core,
        clrText = codegenCLR ptags core,
        wasmText = codegenWASM ptags core
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
  beforeAll compileOnce $ describe testName $ parallel $ do
    it "AST should match snapshot" $ \res -> do
      res.ast `shouldMatchShowSnapshot` (snap <> "/compiler/ast.txt")
    it "Core should match snapshot" $ \res -> do
      res.core `shouldMatchShowSnapshot` (snap <> "/compiler/core.txt")
    it "Symbols JSON should match snapshot" $ \res -> do
      res.symbolsJson `shouldMatchTextSnapshot` (snap <> "/compiler/symbols.json")
    forM_ allLLVMHosts $ \host ->
      it ("LLVM code (" <> toString (llvmHostName host) <> ") should match snapshot") $ \res -> do
        res.artifacts.caLLVM host `shouldMatchTextSnapshot` (snap <> "/compiler/compiled." <> llvmHostName host <> ".ll")
    it "JVM code should match snapshot" $ \res -> do
      res.jvmText `shouldMatchTextSnapshot` (snap <> "/compiler/compiled.j")
    it "CLR code should match snapshot" $ \res -> do
      res.clrText `shouldMatchTextSnapshot` (snap <> "/compiler/compiled.il")
    it "WASM code should match snapshot" $ \res -> do
      res.wasmText `shouldMatchTextSnapshot` (snap <> "/compiler/compiled.wat")
    it "JS code should match snapshot" $ \res -> do
      res.artifacts.caJS `shouldMatchTextSnapshot` (snap <> "/compiler/compiled.js")

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
  let prepare :: IO (Text, Text, Text, Text, Text) = do
        res <- compileOnce
        runAllBackends res.artifacts ""
  let snap :: Text
      snap = "successful/" <> toText testName <> "/output/no-stdin.txt"
  beforeAll prepare $ describe "no-stdin" $ parallel $ do
    it "LLVM stdout should match snapshot" $ \(llvmOutput, _jvmOutput, _clrOutput, _wasmOutput, _jsOutput) -> do
      llvmOutput `shouldMatchTextSnapshot` snap
    it "LLVM stdout and JVM stdout should be equivalent" $ \(llvmOutput, jvmOutput, _clrOutput, _wasmOutput, _jsOutput) -> do
      llvmOutput `shouldBe` jvmOutput
    it "LLVM stdout and CLR stdout should be equivalent" $ \(llvmOutput, _jvmOutput, clrOutput, _wasmOutput, _jsOutput) -> do
      llvmOutput `shouldBe` clrOutput
    it "LLVM stdout and WASM stdout should be equivalent" $ \(llvmOutput, _jvmOutput, _clrOutput, wasmOutput, _jsOutput) -> do
      llvmOutput `shouldBe` wasmOutput
    it "LLVM stdout and JS stdout should be equivalent" $ \(llvmOutput, _jvmOutput, _clrOutput, _wasmOutput, jsOutput) -> do
      llvmOutput `shouldBe` jsOutput

testProgramWithInput :: FilePath -> IO CompileResult -> FilePath -> Spec
testProgramWithInput testName compileOnce inputFile = do
  let prepare :: IO (Text, Text, Text, Text, Text) = do
        input <- readFileTextUtf8 $ sourcesDir </> testName </> "stdin" </> inputFile
        res <- compileOnce
        runAllBackends res.artifacts input
  let snap :: Text
      snap = "successful/" <> toText testName <> "/output/" <> toText inputFile
  beforeAll prepare $ describe inputFile $ parallel $ do
    it "LLVM stdout should match snapshot" $ \(llvmOutput, _jvmOutput, _clrOutput, _wasmOutput, _jsOutput) -> do
      llvmOutput `shouldMatchTextSnapshot` snap
    it "LLVM stdout and JVM stdout should be equivalent" $ \(llvmOutput, jvmOutput, _clrOutput, _wasmOutput, _jsOutput) -> do
      llvmOutput `shouldBe` jvmOutput
    it "LLVM stdout and CLR stdout should be equivalent" $ \(llvmOutput, _jvmOutput, clrOutput, _wasmOutput, _jsOutput) -> do
      llvmOutput `shouldBe` clrOutput
    it "LLVM stdout and WASM stdout should be equivalent" $ \(llvmOutput, _jvmOutput, _clrOutput, wasmOutput, _jsOutput) -> do
      llvmOutput `shouldBe` wasmOutput
    it "LLVM stdout and JS stdout should be equivalent" $ \(llvmOutput, _jvmOutput, _clrOutput, _wasmOutput, jsOutput) -> do
      llvmOutput `shouldBe` jsOutput

runAllBackends :: CompiledArtifacts -> Text -> IO (Text, Text, Text, Text, Text)
runAllBackends ca input = do
  let unwrap name = either (\e -> error $ name <> " failed" <> e) pure
  ((llvmOutput, jvmOutput), ((clrOutput, wasmOutput), jsOutput)) <-
    concurrently
      ( concurrently
          (runOn LLVM ca input >>= unwrap "LLVM")
          (runOn JVM ca input >>= unwrap "JVM")
      )
      ( concurrently
          ( concurrently
              (runOn CLR ca input >>= unwrap "CLR")
              (runOn WASM ca input >>= unwrap "WASM")
          )
          (runOn JS ca input >>= unwrap "JS")
      )
  pure (llvmOutput, jvmOutput, clrOutput, wasmOutput, jsOutput)
