-- | Hspec tests for the compile-time string-literal length check
--   ('StringLiteralTooLong' in 'Awsum.Typing'). The cap is
--   'maxStringLengthUtf16CodeUnits' (= 2^27 = 134_217_728 UTF-16 code
--   units), the same value the runtime '__entryArgEither' / '__concat'
--   helpers enforce on each backend.
--
--   We can't commit a 134-MiB literal to the repo, so the tests build
--   the source 'Text' programmatically and write it to a temp file via
--   'withSystemTempDirectory' — exercising the file-read path the CLI
--   uses ('readFileTextUtf8' → strict UTF-8 decode). Each test takes a
--   couple of seconds; cheap enough to keep in the common 'just test'.
module Awsum.StringLiteralCapSpec (spec) where

import Awsum.ElaborateLower (elaborateLowerProgram)
import Awsum.Parser (parseProgram)
import Awsum.Prelude (withPrelude)
import Awsum.Program (ProgramType (..))
import Awsum.Typing (TypeError (..))
import Common.File (readFileTextUtf8)
import Data.Text qualified as T
import Relude
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

-- | Must stay in sync with 'maxStringLitUtf16CodeUnits' in
--   'Awsum.Typing' and 'maxStringLengthUtf16CodeUnits' in
--   'stdlib/Prelude.aww'. Asserting on the exact boundary, so a future
--   accidental drift in either direction surfaces as a test failure.
cap :: Int
cap = 134217728

-- | A minimal 'main' program whose only string literal is 'literal'.
--   Wrapping the literal in 'main' (rather than using a top-level
--   binding) keeps the pipeline going through the full
--   parse + elaborate + typecheck path that the CLI uses.
mkProgram :: Text -> Text
mkProgram literal =
  unlines
    [ "import IO.Stdout",
      "",
      "main : Either (StringTooLong | UnpairedUtf16Surrogate) String -> IO Never Unit",
      "main _e = IO.Stdout.print \"" <> literal <> "\""
    ]

-- | Compile a temp 'Main.aww' with the given source 'Text' and return
--   the elaborator's result. Mirrors what 'awsum check' does end-to-end:
--   write file → read via 'readFileTextUtf8' → parse → elaborate.
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
        Right (_warns, _core) -> pure (Right ())

-- | Predicate: a 'TypeError' is 'StringLiteralTooLong' with the
--   expected reported length (UTF-16 code units) — checked exactly so a
--   bug in 'utf16CodeUnits' would surface as a wrong reported length.
isStringTooLong :: Int -> Either TypeError () -> Bool
isStringTooLong expectedLen = \case
  Left (StringLiteralTooLong _ n) -> n == expectedLen
  _ -> False

spec :: Spec
spec = describe "String literal length cap" $ do
  it "accepts a literal at exactly maxStringLengthUtf16CodeUnits" $ do
    -- 'cap' ASCII bytes — each is 1 UTF-16 code unit, so
    -- 'utf16CodeUnits literal == cap' (the exact boundary).
    let literal = T.replicate cap "a"
        src = mkProgram literal
    result <- compileTempFile src
    result `shouldBe` Right ()

  it "rejects a literal at maxStringLengthUtf16CodeUnits + 1" $ do
    let literal = T.replicate (cap + 1) "a"
        src = mkProgram literal
    result <- compileTempFile src
    result `shouldSatisfy` isStringTooLong (cap + 1)

  it "counts a supplementary code point as 2 UTF-16 code units" $ do
    -- One 🔥 = 1 USV (U+1F525) = 2 UTF-16 code units (surrogate pair).
    -- 'cap / 2' supplementary code points hit the cap exactly; 'cap / 2 + 1'
    -- overflows by 2. Confirms 'utf16CodeUnits' counts surrogate pairs
    -- correctly rather than treating each emoji as 1.
    let literal = T.replicate (cap `div` 2 + 1) "🔥"
        src = mkProgram literal
    result <- compileTempFile src
    result `shouldSatisfy` isStringTooLong (cap + 2)
