module Awsum.ErrorSnapshotsSpec (spec) where

import Awsum.Diagnostic
import Awsum.Parser (parseProgramDiagnostic)
import Awsum.Typing (typecheckProgram)
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

testError :: FilePath -> Spec
testError testName = do
  let prepare :: IO Text = do
        src <- readFileTextUtf8 $ sourcesDir </> testName </> "code" </> "Main.aww"
        pure $ diagnosticsToJson $ case parseProgramDiagnostic src of
          Left parseErrs -> map parseErrorToDiagnostic parseErrs
          Right prog ->
            case typecheckProgram prog of
              Left typeErr -> [typeErrorToDiagnostic typeErr]
              Right warns -> map warningToDiagnostic warns
  beforeAll prepare $ describe testName $ parallel $ do
    it "diagnostics should match snapshot" $ \json -> do
      json `shouldMatchTextSnapshot` ("errors/" <> toText testName <> "/diagnostics.json")
