-- | Hspec tests for the compile-time string-literal length check
--   ('StringLiteralTooLong' in 'Awsum.Typing'). The cap is
--   'maxStringLitUtf16CodeUnits' = 21845 UTF-16 code units, derived
--   from JVM's 'CONSTANT_Utf8_info' u2 length field (65535 UTF-8
--   bytes / 3 bytes-per-code-unit worst-case) — see the comment on
--   the constant in 'Awsum.Typing'.
--
--   We pick BMP-3-byte CJK content for the literal so the test
--   exercises the worst-case UTF-8 encoding. At cap = 21845, the
--   literal serialises to exactly 65535 UTF-8 bytes — JVM's per-
--   literal boundary; the +1 case overflows by both metrics
--   simultaneously.
--
--   Each test takes a fraction of a second; cheap enough to keep in
--   the common 'just test'.
module Awsum.StringLiteralCapSpec (spec) where

import Awsum.ElaborateLower (elaborateLowerProgram)
import Awsum.Parser (parseProgram)
import Awsum.Prelude (withPrelude)
import Awsum.Program (ProgramType (..))
import Awsum.Typing (TypeError (..), maxStringLitUtf16CodeUnits)
import Common.File (readFileTextUtf8)
import Data.Text qualified as T
import Relude
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

-- | One BMP-3-byte CJK ideograph. 1 UTF-16 code unit, 3 UTF-8 bytes —
--   the worst-case ratio for "bytes per code unit", which is what
--   makes a code-unit-counted cap track JVM's byte-counted ceiling.
cjk :: Text
cjk = "中"

-- | A literal whose UTF-16 length is exactly 'maxStringLitUtf16CodeUnits'.
--   At the current cap of 21845, this is 21845 'cjk' characters —
--   65535 UTF-8 bytes, JVM's per-literal boundary.
literalAtCap :: Text
literalAtCap = T.replicate maxStringLitUtf16CodeUnits cjk

-- | One BMP-3-byte CJK over the cap (so cap+1 in code units, cap*3+3
--   in bytes — overflows both the typechecker cap and JVM's u2).
literalOverCap :: Text
literalOverCap = literalAtCap <> cjk

-- | A minimal 'main' program whose only string literal is 'literal'.
mkProgram :: Text -> Text
mkProgram literal =
  unlines
    [ "import IO.Stdout",
      "",
      "main : IO Never Unit",
      "main = IO.Stdout.print \"" <> literal <> "\""
    ]

-- | Compile a temp 'Main.aww' through the typechecker. Mirrors the
--   CLI's 'awsum check' path: file write → 'readFileTextUtf8' → parse
--   → elaborate.
compileTempFile :: Text -> IO (Either TypeError ())
compileTempFile src =
  withSystemTempDirectory "awsum-string-cap" $ \dir -> do
    let path = dir </> "Main.aww"
    writeFileText path src
    text <- readFileTextUtf8 path
    case parseProgram text of
      Left e -> error $ "parse failed: " <> e
      Right prog -> case elaborateLowerProgram ProgramCli (withPrelude prog) of
        Left err -> pure (Left err)
        Right (_warns, _ptags, _core) -> pure (Right ())

-- | Predicate: a 'TypeError' is 'StringLiteralTooLong' with the
--   expected reported length (UTF-16 code units) — checked exactly so
--   a bug in 'utf16CodeUnits' would surface as a wrong reported length.
isStringTooLong :: Int -> Either TypeError () -> Bool
isStringTooLong expectedLen = \case
  Left (StringLiteralTooLong _ n) -> n == expectedLen
  _ -> False

spec :: Spec
spec = describe "String literal length cap" $ do
  it "accepts a literal at exactly maxStringLitUtf16CodeUnits" $ do
    result <- compileTempFile (mkProgram literalAtCap)
    result `shouldBe` Right ()

  it "rejects a literal at maxStringLitUtf16CodeUnits + 1" $ do
    result <- compileTempFile (mkProgram literalOverCap)
    result `shouldSatisfy` isStringTooLong (maxStringLitUtf16CodeUnits + 1)
