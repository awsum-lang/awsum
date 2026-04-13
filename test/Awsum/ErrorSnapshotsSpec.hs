module Awsum.ErrorSnapshotsSpec (spec) where

import Awsum.Parser (parseProgramDiagnostic)
import Awsum.Syntax (SrcSpan (..))
import Awsum.Typing (prettyPrintTypeError, typeErrorSpan, typecheckProgram)
import Common.File
import Data.Text qualified as T
import Matchers
import Relude
import Test.Hspec

spec :: Spec
spec = describe "Error snapshots" $ do
  testError "unreachable-case-uninhabited.aww"
  testError "unreachable-case-uninhabited-nested.aww"

sourcesDir :: Text
sourcesDir = "test/sources/errors/"

testError :: Text -> Spec
testError sourceFile = do
  let prepare :: IO Text = do
        src <- readFileTextUtf8 $ toString $ sourcesDir <> sourceFile
        pure $ case parseProgramDiagnostic src of
          Left parseErrs ->
            diagnosticsToJson [(sp, msg) | (sp, msg) <- parseErrs]
          Right prog ->
            case typecheckProgram prog of
              Left typeErr ->
                let sp = fromMaybe (SrcSpan 1 1 1 1) (typeErrorSpan typeErr)
                 in diagnosticsToJson [(sp, prettyPrintTypeError typeErr)]
              Right () -> "[]"
  beforeAll prepare $ describe (toString sourceFile) $ do
    it "diagnostics should match snapshot" $ \json -> do
      json `shouldMatchTextSnapshot` ("errors/" <> sourceFile <> "/diagnostics.json")

-- ════════════════════════════════════════════════════════════════════════════
-- JSON diagnostics (mirrored from awsum/Main.hs, no aeson dependency)
-- ════════════════════════════════════════════════════════════════════════════

diagnosticsToJson :: [(SrcSpan, Text)] -> Text
diagnosticsToJson errs = "[" <> T.intercalate "," (map diagToJson errs) <> "]"

diagToJson :: (SrcSpan, Text) -> Text
diagToJson (SrcSpan sl sc el ec, msg) =
  "{\"startLine\":"
    <> show sl
    <> ",\"startCol\":"
    <> show sc
    <> ",\"endLine\":"
    <> show el
    <> ",\"endCol\":"
    <> show ec
    <> ",\"message\":"
    <> jsonString msg
    <> "}"

jsonString :: Text -> Text
jsonString t = "\"" <> T.concatMap escapeJsonChar t <> "\""

escapeJsonChar :: Char -> Text
escapeJsonChar = \case
  '"' -> "\\\""
  '\\' -> "\\\\"
  '\n' -> "\\n"
  '\r' -> "\\r"
  '\t' -> "\\t"
  c -> one c
