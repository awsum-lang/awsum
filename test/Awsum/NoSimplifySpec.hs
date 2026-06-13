-- | Differential output gate over the successful-program corpus: every
-- program is compiled a second time with the 'Awsum.Simplify' pass
-- disabled ('SimplifyOff') and run on all five backends, and each
-- backend's stdout must equal the committed output golden — the one
-- @just test@ records and asserts under 'SimplifyOn'. Together the two
-- suites pin @runtime(simplify(core)) == runtime(core)@ with the
-- runtime itself as the oracle: a wrong Core rewrite makes all five
-- backends agree on the same wrong answer, which neither the
-- per-backend snapshots nor the cross-backend equality checks can see —
-- this pair can.
--
-- This spec never writes a golden: a missing output snapshot fails with
-- an instruction to run @just test@ first. Creating goldens here would
-- record 'SimplifyOff' behaviour as the reference and invert the
-- differential.
--
-- Kept out of @just test@ \/ @just test-watch@ (the same gating as the
-- property suite) because it recompiles the whole corpus — one extra
-- @clang@ per program. @just test-no-simplify@ runs it; @just fix@ runs
-- all three suites.
module Awsum.NoSimplifySpec (spec) where

import Awsum.RunBackend (Backend, CompiledArtifacts, SimplifyMode (..), allBackends, compileFromFileWith, runOnAll)
import Common.File
import Control.Concurrent.MVar (modifyMVar)
import Matchers (snapshotsDir)
import Relude
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath ((</>))
import Test.Hspec
import TestSources (discoverTestDirs)

spec :: Spec
spec = describe "No-simplify differential" $ parallel $ do
  testNames <- runIO (discoverTestDirs sourcesDir)
  traverse_ testProgram testNames

sourcesDir :: FilePath
sourcesDir = "test/sources/successful"

-- | One program: compile once without Simplify (memoised across the
--   input groups, mirroring 'Awsum.ProgramSnapshotsSpec'), then one
--   group per input — the same @input/@ discovery and the same
--   'runOnAll' invocation the snapshot suite uses, so the outputs are
--   comparable to its goldens by construction.
testProgram :: FilePath -> Spec
testProgram testName = do
  inputFiles <- runIO discoverInputFiles
  compileOnce <- runIO $ do
    ref <- newMVar Nothing
    pure $ modifyMVar ref $ \case
      Just r -> pure (Just r, r)
      Nothing -> do
        r <- compileFromFileWith SimplifyOff (sourcesDir </> testName </> "code" </> "Main.aww")
        pure (Just r, r)
  describe testName $ case inputFiles of
    [] -> inputCase testName compileOnce Nothing
    files -> traverse_ (inputCase testName compileOnce . Just) files
  where
    discoverInputFiles :: IO [FilePath]
    discoverInputFiles = do
      let inputDir = sourcesDir </> testName </> "input"
      exists <- doesDirectoryExist inputDir
      if exists
        then sort <$> listDirectory inputDir
        else pure []

inputCase :: FilePath -> IO CompiledArtifacts -> Maybe FilePath -> Spec
inputCase testName compileOnce inputFile = do
  let goldenFile =
        snapshotsDir
          <> "successful/"
          <> testName
          <> "/output/"
          <> fromMaybe "no-input.txt" inputFile
      prepare :: IO (Text, [(Backend, Either Text Text)])
      prepare = do
        golden <- readGolden goldenFile
        input <- case inputFile of
          Nothing -> pure ""
          Just f -> readFileTextUtf8 (sourcesDir </> testName </> "input" </> f)
        artifacts <- compileOnce
        results <- runOnAll artifacts input
        pure (golden, results)
  beforeAll prepare
    $ describe (fromMaybe "no-input" inputFile)
    $ parallel
    $ forM_ allBackends
    $ \b ->
      it (show b <> " stdout without Simplify should match the golden") $ \(golden, results) ->
        case find ((== b) . fst) results of
          Just (_, Right out) -> out `shouldBe` golden
          Just (_, Left err) -> expectationFailure (toString (show b <> " failed:\n" <> err))
          Nothing -> expectationFailure (show b <> " missing from results")

-- | Read a committed output golden; a missing file is a hard,
--   explanatory failure rather than a fresh write — see the module
--   header.
readGolden :: FilePath -> IO Text
readGolden path = do
  exists <- doesFileExist path
  unless exists
    $ error
    $ "missing output golden "
    <> toText path
    <> " — run `just test` first; the no-simplify differential never writes goldens"
  readFileTextUtf8 path
