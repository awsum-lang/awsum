module Awsum.FormattingSnapshotsSpec (spec) where

import Awsum.Format (formatSource)
import Common.File
import Matchers
import Relude
import System.FilePath ((</>))
import Test.Hspec
import TestSources (discoverTestDirs)

spec :: Spec
spec = describe "Formatting snapshots" $ do
  testNames <- runIO (discoverTestDirs sourcesDir)
  traverse_ testFormatting testNames

sourcesDir :: FilePath
sourcesDir = "test/sources/formatting"

testFormatting :: FilePath -> Spec
testFormatting testName = do
  let prepare :: IO Text = do
        src <- readFileTextUtf8 $ sourcesDir </> testName </> "code" </> "Main.aww"
        case formatSource src of
          Left err -> error $ "format failed" <> show err
          Right x -> pure x
  beforeAll prepare $ describe testName $ do
    it "Formatted source should match snapshot" $ \formatted -> do
      formatted `shouldMatchTextSnapshot` ("formatting/" <> toText testName <> "/formatted.aww")
