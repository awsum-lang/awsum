-- | Tests for the @awsum lsp@ server.
--
--   Two layers, both exercised here:
--
--     * /Unit/ — the request logic extracted from the handlers
--       ('formatEdits', 'compileToDiagnostics' + 'awsumDiagToLsp',
--       'documentSymbolsForSource', 'fixToCodeAction',
--       'workspaceSymbolsForFile', 'shouldWarnVersionMismatch',
--       'extractClientHints'), driven directly on small fixtures the
--       way 'Awsum.HoverSpec' drives 'hoverForPosition'.
--
--     * /End-to-end/ — a real server spun up in-process over a pipe pair
--       ('runLspServerWithHandles' + @lsp-test@), confirming the handlers
--       are actually registered and the JSON-RPC envelopes are shaped
--       right. Lives in "Awsum.LspSpec.EndToEnd", folded in below.
module Awsum.LspSpec (spec) where

import Awsum.Diagnostic qualified as AD
import Awsum.Format (formatSource)
import Awsum.Lsp
import Awsum.LspSpec.EndToEnd qualified as EndToEnd
import Awsum.Syntax (SrcSpan (..))
import Awsum.Width qualified as Width
import Data.Aeson ((.=))
import Data.Aeson qualified as Aeson
import Data.List (lookup)
import Data.Text qualified as T
import Language.LSP.Protocol.Types
  ( CodeAction (..),
    CodeActionKind (..),
    Diagnostic (..),
    DiagnosticSeverity (..),
    DocumentSymbol (..),
    Position (..),
    Range (..),
    SymbolInformation (..),
    SymbolKind (..),
    TextEdit (..),
    WorkspaceEdit (..),
    filePathToUri,
    toNormalizedUri,
  )
import Relude
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

spec :: Spec
spec = describe "Awsum.Lsp" $ do
  formatEditsSpec
  diagnosticsSpec
  columnConversionSpec
  documentSymbolsSpec
  codeActionSpec
  workspaceSymbolsSpec
  versionMismatchSpec
  clientHintsSpec
  EndToEnd.spec

-- ════════════════════════════════════════════════════════════════════════════
-- textDocument/formatting → formatEdits
-- ════════════════════════════════════════════════════════════════════════════

formatEditsSpec :: Spec
formatEditsSpec = describe "formatEdits" $ do
  it "returns no edits for an already-canonical document"
    $ formatEdits (fmt twoFns)
    `shouldBe` []

  it "returns no edits for a document that doesn't parse"
    $ formatEdits "@@@ not awsum @@@"
    `shouldBe` []

  it "round-trips: applying the edits reproduces the formatted source" $ do
    let messy = T.replace "foo n = n" "foo n =     n" (fmt twoFns)
    formatEdits messy `shouldNotBe` []
    applyEdits messy (formatEdits messy) `shouldBe` fmt messy

  it "round-trips a document with no final newline" $ do
    let noNL = T.dropWhileEnd (== '\n') (fmt twoFns) -- strip trailing '\n'
    applyEdits noNL (formatEdits noNL) `shouldBe` fmt noNL

  it "round-trips non-ASCII content (UTF-16 surrogate-pair columns)" $ do
    let messy = T.replace "main = " "main =    " (fmt emojiProg)
    formatEdits messy `shouldNotBe` []
    applyEdits messy (formatEdits messy) `shouldBe` fmt messy

  it "emits targeted edits, not a whole-document replace" $ do
    -- Only the LAST definition's body is perturbed; the single edit must
    -- start below line 0, proving the untouched prefix is left alone.
    let messy = T.replace "bar n = n" "bar n =   n" (fmt twoFns)
    case formatEdits messy of
      [TextEdit (Range (Position startLine _) _) _] ->
        startLine `shouldSatisfy` (> 0)
      es -> expectationFailure ("expected exactly one targeted edit, got " <> show (length es))

  it "emits one edit per changed hunk (multi-hunk)" $ do
    -- Two perturbations separated by unchanged lines → two edits.
    let messy =
          T.replace "bar n = n" "bar n =   n"
            $ T.replace "foo n = n" "foo n =   n" (fmt twoFns)
    length (formatEdits messy) `shouldBe` 2
    applyEdits messy (formatEdits messy) `shouldBe` fmt messy

-- ════════════════════════════════════════════════════════════════════════════
-- textDocument/publishDiagnostics → compileToDiagnostics + awsumDiagToLsp
-- ════════════════════════════════════════════════════════════════════════════

diagnosticsSpec :: Spec
diagnosticsSpec = describe "compileToDiagnostics / awsumDiagToLsp" $ do
  it "reports no diagnostics for a clean program"
    $ compileToDiagnostics (fmt twoFns)
    `shouldBe` []

  it "reports an error for an out-of-range integer literal" $ do
    let src =
          unlines
            [ "import IO.Stdout",
              "",
              "over : UInt8",
              "over = 300",
              "",
              "main : IO Never Unit",
              "main = IO.Stdout.print \"x\""
            ]
    case compileToDiagnostics src of
      (d : _) -> do
        AD.diagSeverity d `shouldBe` AD.SevError
        AD.diagMessage d `shouldSatisfy` T.isInfixOf "UInt8"
      [] -> expectationFailure "expected an out-of-range error"

  it "reports a warning (with a quick-fix) for an unused parameter"
    $ case find (not . null . AD.diagFixes) (compileToDiagnostics unusedParamProg) of
      Just d -> do
        AD.diagSeverity d `shouldBe` AD.SevWarning
        AD.diagMessage d `shouldSatisfy` T.isInfixOf "Unused parameter"
      Nothing -> expectationFailure "expected an unused-parameter warning carrying a fix"

  it "maps Awsum severity to the LSP severity field" $ do
    let lsp = awsumDiagToLsp [] (AD.Diagnostic AD.SevWarning (SrcSpan 1 1 1 2) "w" [])
    case lsp of
      Diagnostic {_severity = sev, _source = src} -> do
        sev `shouldBe` Just DiagnosticSeverity_Warning
        src `shouldBe` Just "awsum"

-- ════════════════════════════════════════════════════════════════════════════
-- Column units: Awsum span columns are display width (Megaparsec counts a wide
-- char as two); LSP Position columns are UTF-16 code units. The boundary
-- converts against the source line — these pin both directions.
-- ════════════════════════════════════════════════════════════════════════════

columnConversionSpec :: Spec
columnConversionSpec = describe "span (display width) ↔ LSP Position (UTF-16)" $ do
  -- A wide CJK char: two display columns, one UTF-16 unit.
  -- A math-bold letter: one display column, two UTF-16 units (supplementary).
  let wideThenX = toText [chr 0x732B, 'x']
      mathThenX = toText [chr 0x1D400, 'x']
      rangeOf src sc ec =
        case awsumDiagToLsp [src] (AD.Diagnostic AD.SevError (SrcSpan 1 sc 1 ec) "e" []) of
          Diagnostic {_range = Range (Position _ s) (Position _ e)} -> (s, e)

  it "emits UTF-16 columns after a wide char (2 cols, 1 unit)"
    -- 'x' is at display col 3 (the wide char spans cols 1..2) → UTF-16 offset 1.
    $ rangeOf wideThenX 3 4
    `shouldBe` (1, 2)

  it "emits UTF-16 columns after a supplementary char (1 col, 2 units)"
    -- 'x' is at display col 2 → UTF-16 offset 2 (the math char is a surrogate pair).
    $ rangeOf mathThenX 2 3
    `shouldBe` (2, 3)

  it "incoming UTF-16 columns invert to the display columns spans use" $ do
    -- Mixed line: wide, narrow, supplementary, narrow. Char-boundary display
    -- columns must survive display → UTF-16 → display unchanged (the hover
    -- handler converts the client's UTF-16 cursor back to a span column).
    let line = toText [chr 0x732B, 'x', chr 0x1D400, 'y']
        boundaries :: [Int]
        boundaries = [1, 3, 4, 5, 6]
    map (Width.utf16ColToDisplay line . Width.displayColToUtf16 line) boundaries
      `shouldBe` boundaries

-- ════════════════════════════════════════════════════════════════════════════
-- textDocument/documentSymbol → documentSymbolsForSource
-- ════════════════════════════════════════════════════════════════════════════

documentSymbolsSpec :: Spec
documentSymbolsSpec = describe "documentSymbolsForSource" $ do
  it "surfaces top-level type, function, and constant symbols" $ do
    let syms = documentSymbolsForSource outlineProg
        named = [(n, k) | DocumentSymbol {_name = n, _kind = k} <- syms]
    map fst named `shouldMatchList` ["Color", "greet", "answer"]
    lookup "Color" named `shouldBe` Just SymbolKind_Enum
    lookup "greet" named `shouldBe` Just SymbolKind_Function
    lookup "answer" named `shouldBe` Just SymbolKind_Constant

  it "returns no symbols when the source doesn't parse"
    $ documentSymbolsForSource "@@@ not awsum @@@"
    `shouldBe` []

-- ════════════════════════════════════════════════════════════════════════════
-- textDocument/codeAction → fixToCodeAction
-- ════════════════════════════════════════════════════════════════════════════

codeActionSpec :: Spec
codeActionSpec = describe "fixToCodeAction"
  $ it "wraps a compiler fix as a QuickFix CodeAction with the edit"
  $ case mapMaybe firstFix (compileToDiagnostics unusedParamProg) of
    ((d, qf) : _) -> do
      let uri = toNormalizedUri (filePathToUri "/x/Main.aww")
      case fixToCodeAction (lines unusedParamProg) uri (awsumDiagToLsp (lines unusedParamProg) d) qf of
        CodeAction {_kind = k, _edit = edit, _diagnostics = ds} -> do
          k `shouldBe` Just CodeActionKind_QuickFix
          (length <$> ds) `shouldBe` Just 1
          editTexts edit `shouldBe` ["_n"]
    [] -> expectationFailure "expected a diagnostic carrying a fix"
  where
    firstFix d = case AD.diagFixes d of
      (f : _) -> Just (d, f)
      [] -> Nothing
    editTexts = \case
      Just (WorkspaceEdit {_changes = Just changes}) ->
        [t | edits <- toList changes, TextEdit _ t <- edits]
      _ -> []

-- ════════════════════════════════════════════════════════════════════════════
-- workspace/symbol → workspaceSymbolsForFile
-- ════════════════════════════════════════════════════════════════════════════

workspaceSymbolsSpec :: Spec
workspaceSymbolsSpec = describe "workspaceSymbolsForFile" $ do
  it "returns every symbol for an empty query"
    $ withTempAww outlineProg
    $ \path -> do
      syms <- workspaceSymbolsForFile "" path
      map symName syms `shouldMatchList` ["Color", "greet", "answer"]

  it "filters by a case-insensitive substring query"
    $ withTempAww outlineProg
    $ \path -> do
      syms <- workspaceSymbolsForFile "gre" path
      map symName syms `shouldBe` ["greet"]

  it "returns nothing for a file that doesn't parse"
    $ withTempAww "@@@ not awsum @@@"
    $ \path -> do
      syms <- workspaceSymbolsForFile "" path
      syms `shouldBe` []
  where
    symName (SymbolInformation {_name = n}) = n
    withTempAww :: Text -> (FilePath -> IO a) -> IO a
    withTempAww contents act =
      withSystemTempDirectory "awsum-lsp" $ \dir -> do
        let path = dir </> "Main.aww"
        writeFileText path contents
        act path

-- ════════════════════════════════════════════════════════════════════════════
-- initialize version check → shouldWarnVersionMismatch / looksLikeSemver
-- ════════════════════════════════════════════════════════════════════════════

versionMismatchSpec :: Spec
versionMismatchSpec = describe "version mismatch check" $ do
  it "warns when two distinct A.B.C release versions disagree"
    $ shouldWarnVersionMismatch "1.2.3" "1.2.4"
    `shouldBe` True

  it "stays silent when the versions match"
    $ shouldWarnVersionMismatch "1.2.3" "1.2.3"
    `shouldBe` False

  it "stays silent when either side isn't a plain A.B.C version" $ do
    shouldWarnVersionMismatch "1.2.3-dirty" "1.2.4" `shouldBe` False
    shouldWarnVersionMismatch "1.2.3" "9.9.9-rc1" `shouldBe` False

  it "recognises A.B.C versions only" $ do
    looksLikeSemver "1.2.3" `shouldBe` True
    looksLikeSemver "1.2" `shouldBe` False
    looksLikeSemver "1.2.3.4" `shouldBe` False
    looksLikeSemver "a.b.c" `shouldBe` False

-- ════════════════════════════════════════════════════════════════════════════
-- initializationOptions parsing → extractClientHints
-- ════════════════════════════════════════════════════════════════════════════

clientHintsSpec :: Spec
clientHintsSpec = describe "extractClientHints" $ do
  it "defaults when no initializationOptions are present" $ do
    let h = extractClientHints Nothing
    chExpectedAwsumVersion h `shouldBe` Nothing
    chPreferButtonsOverLinks h `shouldBe` False

  it "reads the expected version and the buttons-over-links preference" $ do
    let h =
          extractClientHints
            . Just
            $ Aeson.object
              [ "expectedAwsumVersion" .= ("1.2.3" :: Text),
                "preferButtonsOverLinks" .= True
              ]
    chExpectedAwsumVersion h `shouldBe` Just "1.2.3"
    chPreferButtonsOverLinks h `shouldBe` True

  it "falls back to defaults for wrong-typed fields" $ do
    let h = extractClientHints . Just $ Aeson.object ["expectedAwsumVersion" .= (5 :: Int)]
    chExpectedAwsumVersion h `shouldBe` Nothing
    chPreferButtonsOverLinks h `shouldBe` False

-- ════════════════════════════════════════════════════════════════════════════
-- Fixtures + helpers
-- ════════════════════════════════════════════════════════════════════════════

-- | Format a source or fail loudly — fixtures must parse.
fmt :: Text -> Text
fmt s = case formatSource s of
  Right o -> o
  Left e -> error ("formatSource failed on fixture: " <> e)

twoFns :: Text
twoFns =
  unlines
    [ "import IO.Stdout",
      "",
      "foo : Int32 -> Int32",
      "foo n = n",
      "",
      "bar : Int32 -> Int32",
      "bar n = n",
      "",
      "main : IO Never Unit",
      "main = IO.Stdout.print (showInt32 (foo (bar 1)))"
    ]

emojiProg :: Text
emojiProg =
  unlines
    [ "import IO.Stdout",
      "",
      "main : IO Never Unit",
      "main = IO.Stdout.print \"\x1F525\x1F4A9\"" -- 🔥💩 (surrogate pairs in UTF-16)
    ]

unusedParamProg :: Text
unusedParamProg =
  unlines
    [ "import IO.Stdout",
      "",
      "greet : Int32 -> String",
      "greet n = \"hi\"",
      "",
      "main : IO Never Unit",
      "main = IO.Stdout.print (greet 1)"
    ]

outlineProg :: Text
outlineProg =
  unlines
    [ "type Color = Red | Green",
      "",
      "greet : Int32 -> String",
      "greet _n = \"hi\"",
      "",
      "answer : Int32",
      "answer = 42"
    ]

-- | Apply LSP 'TextEdit's to text, the way a client would. Edits are
--   non-overlapping; applying them from the highest start position
--   downward keeps earlier offsets valid. Positions are (line, UTF-16
--   code unit) per the LSP spec — this oracle counts code units
--   independently of 'Awsum.Lsp', so the round-trip checks above don't
--   merely re-test the server's own conversion.
applyEdits :: Text -> [TextEdit] -> Text
applyEdits src edits = foldl' apply1 src (sortOn (Down . editStart) edits)
  where
    editStart (TextEdit (Range (Position l c) _) _) = (l, c)
    apply1 t (TextEdit (Range startP endP) newText) =
      T.take (posToOffset t startP) t <> newText <> T.drop (posToOffset t endP) t

-- | LSP 'Position' (line, UTF-16 code unit) → code-point offset into the text.
posToOffset :: Text -> Position -> Int
posToOffset t (Position line ch) =
  let ls = T.splitOn "\n" t
      prefix = sum (map ((+ 1) . T.length) (take (fromIntegral line) ls))
      cur = fromMaybe "" (ls !!? fromIntegral line)
   in prefix + utf16ToCodePoints (fromIntegral ch) cur

-- | Code points consumed to reach @n@ UTF-16 code units into a line.
utf16ToCodePoints :: Int -> Text -> Int
utf16ToCodePoints n = go 0 0 . toString
  where
    go cp u (c : rest)
      | u >= n = cp
      | otherwise = go (cp + 1) (u + if ord c > 0xFFFF then 2 else 1) rest
    go cp _ [] = cp
