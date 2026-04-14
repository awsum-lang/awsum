module Awsum.FormattingSnapshotsSpec (spec) where

import Awsum.Format (formatSource)
import Common.File
import Matchers
import Relude
import Test.Hspec

spec :: Spec
spec = describe "Formatting snapshots" $ do
  testFormatting "improperly-formatted-source.aww"

sourcesDir :: Text
sourcesDir = "test/sources/formatting/"

testFormatting :: Text -> Spec
testFormatting sourceFile = do
  let prepare :: IO Text = do
        src <- readFileTextUtf8 $ toString $ sourcesDir <> sourceFile
        case formatSource src of
          Left err -> error $ "format failed" <> show err
          Right x -> pure x
  beforeAll prepare $ describe (toString sourceFile) $ do
    it "Formatted source should match snapshot" $ \formatted -> do
      formatted `shouldMatchTextSnapshot` ("formatting/" <> sourceFile <> "/formatted." <> sourceFile)
