module Awsum.ErrorSnapshotsSpec (spec) where

import Awsum.Diagnostic
import Awsum.Parser (parseProgramDiagnostic)
import Awsum.Prelude (stripPreludeWarnings, withPrelude)
import Awsum.Program (ProgramType (..))
import Awsum.Typing (requireMain, typecheckProgram)
import Common.File
import Matchers
import Relude
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath ((</>))
import Test.Hspec

spec :: Spec
spec = describe "Error snapshots" $ do
  testNames <- runIO discoverTests
  traverse_ testError testNames

sourcesDir :: FilePath
sourcesDir = "test/sources/errors"

discoverTests :: IO [FilePath]
discoverTests = do
  entries <- listDirectory sourcesDir
  sort <$> filterM (\e -> doesDirectoryExist (sourcesDir </> e)) entries

-- | Snapshots here model what @awsum build@ reports: module-level
--   type-check diagnostics plus the entry-point check. LSP/@awsum check@
--   skip 'requireMain' — those are covered by unit tests.
testError :: FilePath -> Spec
testError testName = do
  let prepare :: IO Text = do
        src <- readFileTextUtf8 $ sourcesDir </> testName </> "code" </> "Main.aww"
        pure $ diagnosticsToJson $ case parseProgramDiagnostic src of
          Left parseErrs -> map parseErrorToDiagnostic parseErrs
          Right userProg ->
            let prog = withPrelude userProg
             in case typecheckProgram ProgramCli prog of
                  Left typeErr -> [typeErrorToDiagnostic typeErr]
                  Right warns ->
                    case requireMain prog of
                      Left typeErr -> [typeErrorToDiagnostic typeErr]
                      Right () -> map warningToDiagnostic (stripPreludeWarnings warns)
  beforeAll prepare $ describe testName $ parallel $ do
    it "diagnostics should match snapshot" $ \json -> do
      json `shouldMatchTextSnapshot` ("errors/" <> toText testName <> "/diagnostics.json")
