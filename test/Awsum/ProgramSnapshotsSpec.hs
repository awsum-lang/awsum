module Awsum.ProgramSnapshotsSpec (spec) where

import Awsum.Codegen.LLVM (allLLVMHosts, llvmHostName)
import Awsum.Core
import Awsum.Lifetime (analyzeProgram, renderLifetime)
import Awsum.Parser (parseProgram)
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
import TestSources (discoverTestDirs)

spec :: Spec
spec = do
  describe "Program snapshots" $ parallel $ do
    -- 'parallel' here makes sibling programs run in parallel with each
    -- other; the inner 'parallel' inside 'testProgram' keeps the per-
    -- program tests parallelisable too. Each 'beforeAll' block scopes
    -- its own 'compileOnce', so parallel programs don't fight over a
    -- shared MVar.
    testNames <- runIO (discoverTestDirs sourcesDir)
    traverse_ testProgram testNames
  describe "Benchmark program snapshots" $ parallel $ do
    -- Compiler artifacts only. Benchmark programs run for minutes by
    -- design, so the runtime side (timings, peak RSS, cross-backend
    -- stdout) stays with 'awsum-bench'; the committed IR is what makes
    -- a bench.txt delta diagnosable from a 'git diff' instead of an
    -- archaeology session against an old compiler build.
    benchNames <- runIO (discoverTestDirs benchmarkDir)
    traverse_ benchmarkProgram benchNames

sourcesDir :: FilePath
sourcesDir = "test/sources/successful"

benchmarkDir :: FilePath
benchmarkDir = "test/sources/benchmark"

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
    wasmText :: Text,
    lifetimeText :: Text
  }

compileAll :: FilePath -> FilePath -> IO CompileResult
compileAll root testName = do
  src <- readFileTextUtf8 $ root </> testName </> "code" </> "Main.aww"
  ast <- case parseProgram src of
    Left e -> error $ "parse failed" <> e
    Right x -> pure x
  -- One elaboration, inside 'compileFromText': the golden text snapshots
  -- ('caJVMText' …) and the runnable bytes are both derived from its 'caCore',
  -- so a text snapshot is a faithful view of what the bytes run.
  artifacts <- RB.compileFromText src
  pure
    CompileResult
      { artifacts = artifacts,
        ast = ast,
        core = artifacts.caCore,
        symbolsJson = symbolsToJson (symbolsOfProgram ast),
        jvmText = artifacts.caJVMText,
        clrText = artifacts.caCLRText,
        wasmText = artifacts.caWASMText,
        lifetimeText = renderLifetime (analyzeProgram artifacts.caCore)
      }

testProgram :: FilePath -> Spec
testProgram testName = do
  inputFiles <- runIO discoverInputFiles
  compileOnce <- runIO $ do
    ref <- newMVar Nothing
    pure $ modifyMVar ref $ \case
      Just r -> pure (Just r, r)
      Nothing -> do
        r <- compileAll sourcesDir testName
        pure (Just r, r)
  let snap :: Text
      snap = "successful/" <> toText testName
  -- One named group per program, the runtime groups nested inside it. A
  -- runtime group used to be an anonymous sibling (`describe "no-stdin"`
  -- at the top level), which made a failure there unattributable in the
  -- formatter output and unreachable by `--match <program>`.
  describe testName $ do
    beforeAll compileOnce $ parallel $ compilerSnapshotItems snap
    case inputFiles of
      [] -> testProgramNoInput testName compileOnce
      _ -> traverse_ (testProgramWithInput testName compileOnce) inputFiles
  where
    -- Files under @input/@ — today each is delivered to the program as its
    -- single CLI argument (no test reads stdin yet); how an input reaches
    -- the program is meant to become per-test configuration later.
    discoverInputFiles :: IO [FilePath]
    discoverInputFiles = do
      let inputDir :: FilePath
          inputDir = sourcesDir </> testName </> "input"
      exists <- doesDirectoryExist inputDir
      if exists
        then sort <$> listDirectory inputDir
        else pure []

-- | The per-program compiler-artifact golden tests, shared by the
--   successful and benchmark trees. 'snap' is the snapshot path prefix
--   under '.snapshots/' (@successful/<name>@, @benchmark/<name>@).
compilerSnapshotItems :: Text -> SpecWith CompileResult
compilerSnapshotItems snap = do
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
  it "Lifetime should match snapshot" $ \res -> do
    res.lifetimeText `shouldMatchTextSnapshot` (snap <> "/compiler/lifetime.txt")

-- | Benchmark programs: compiler snapshots only — no output groups.
--   One 'beforeAll' group means the compile runs once with no second
--   consumer, so no memoising MVar is needed.
benchmarkProgram :: FilePath -> Spec
benchmarkProgram testName =
  beforeAll (compileAll benchmarkDir testName)
    $ describe testName
    $ parallel
    $ compilerSnapshotItems ("benchmark/" <> toText testName)

testProgramNoInput :: FilePath -> IO CompileResult -> Spec
testProgramNoInput testName compileOnce = do
  let prepare :: IO (Text, Text, Text, Text, Text) = do
        res <- compileOnce
        runAllBackends res.artifacts ""
  let snap :: Text
      snap = "successful/" <> toText testName <> "/output/no-input.txt"
  beforeAll prepare $ describe "no-input" $ parallel $ do
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
        input <- readFileTextUtf8 $ sourcesDir </> testName </> "input" </> inputFile
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
  let unwrap name = either (\e -> error $ name <> " failed: " <> e) pure
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
