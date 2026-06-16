-- | End-to-end tests for @awsum lsp@: a real server is started in-process
--   over a pair of pipes ('runLspServerWithHandles') and driven through
--   @lsp-test@. Where the unit layer in "Awsum.LspSpec" checks the
--   extracted request logic, this layer confirms the handlers are
--   actually registered and the JSON-RPC envelopes are shaped the way
--   every editor client depends on — initialize/didOpen, formatting,
--   document symbols, hover, code actions, and pushed diagnostics.
module Awsum.LspSpec.EndToEnd (spec) where

import Awsum.Format (formatSource)
import Awsum.Lsp (runLspServerWithHandles)
import Control.Concurrent (forkIO)
import Control.Exception (catch)
import Data.Text qualified as T
import Language.LSP.Protocol.Capabilities (fullLatestClientCaps)
import Language.LSP.Protocol.Types
  ( CodeAction (..),
    CodeActionKind (..),
    Diagnostic (..),
    DocumentSymbol (..),
    FormattingOptions (..),
    Hover (..),
    MarkupContent (..),
    Position (..),
    TextDocumentIdentifier,
    type (|?) (..),
  )
import Language.LSP.Test
  ( Session,
    createDoc,
    defaultConfig,
    documentContents,
    formatDoc,
    getCodeActions,
    getDocumentSymbols,
    getHover,
    runSessionWithHandles,
    waitForDiagnostics,
  )
import Relude
import System.Exit (ExitCode)
import System.Process (createPipe)
import Test.Hspec

spec :: Spec
spec = describe "Awsum.Lsp end-to-end (lsp-test over a real server)" $ do
  it "applies formatting edits, reproducing the formatted source" $ do
    let messy = T.replace "square n = n" "square n =    n" (fmt squareProg)
    result <- withServer $ do
      doc <- openMain messy
      formatDoc doc formattingOptions
      documentContents doc
    result `shouldBe` fmt messy

  it "leaves an already-canonical document untouched (no edits)" $ do
    let src = fmt squareProg
    result <- withServer $ do
      doc <- openMain src
      formatDoc doc formattingOptions
      documentContents doc
    result `shouldBe` src

  it "serves document symbols (outline)" $ do
    syms <- withServer $ openMain outlineProg >>= getDocumentSymbols
    case syms of
      Right ds -> [n | DocumentSymbol {_name = n} <- ds] `shouldMatchList` ["Color", "greet", "answer"]
      Left _ -> expectationFailure "expected DocumentSymbol[], got SymbolInformation[]"

  it "serves hover with the declaration's type" $ do
    mh <- withServer $ do
      doc <- openMain squareProg
      getHover doc (Position 2 0) -- 's' of 'square' in its signature
    case mh of
      Just (Hover (InL (MarkupContent _ md)) _) -> md `shouldSatisfy` T.isInfixOf "Int32"
      _ -> expectationFailure "expected a markdown hover carrying the type"

  it "offers a quick-fix code action for a warning" $ do
    actions <- withServer $ do
      doc <- openMain unusedParamProg
      diags <- waitForDiagnostics
      case diags of
        (Diagnostic {_range = r} : _) -> getCodeActions doc r
        [] -> pure []
    any isQuickFix actions `shouldBe` True

  it "pushes diagnostics for a type error on open" $ do
    diags <- withServer $ openMain outOfRangeProg >> waitForDiagnostics
    map diagMessage diags `shouldSatisfy` any (T.isInfixOf "UInt8")
  where
    isQuickFix (InR (CodeAction {_kind = Just CodeActionKind_QuickFix})) = True
    isQuickFix _ = False
    diagMessage (Diagnostic {_message = m}) = m

-- ════════════════════════════════════════════════════════════════════════════
-- Harness: a real server over an in-process pipe pair
-- ════════════════════════════════════════════════════════════════════════════

-- | Run a session against a server started in a forked thread, connected
--   by two pipes. @lsp-test@ performs the initialize/initialized
--   handshake; the body opens documents itself with 'openMain'.
withServer :: Session a -> IO a
withServer session = do
  (srvInR, srvInW) <- createPipe
  (srvOutR, srvOutW) <- createPipe
  -- The 'lsp' and 'lsp-test' transports each set NoBuffering + utf8 on
  -- their own handles, so there's nothing to configure here. On session
  -- end @lsp-test@ sends @exit@, which the 'lsp' framework turns into an
  -- 'ExitSuccess' thrown in this thread; swallow it so the forked
  -- shutdown is silent rather than a stray "uncaught exception" line.
  _ <- forkIO (void (runLspServerWithHandles srvInR srvOutW "9.9.9") `catch` \(_ :: ExitCode) -> pass)
  runSessionWithHandles srvInW srvOutR defaultConfig fullLatestClientCaps "." session

-- | Open a single @Main.aww@ document with the given contents.
openMain :: Text -> Session TextDocumentIdentifier
openMain = createDoc "Main.aww" "awsum"

-- | Formatting options the server ignores (it always reformats).
formattingOptions :: FormattingOptions
formattingOptions = FormattingOptions 2 True Nothing Nothing Nothing

-- | Format a fixture or fail loudly — fixtures must parse.
fmt :: Text -> Text
fmt s = case formatSource s of
  Right o -> o
  Left e -> error ("formatSource failed on fixture: " <> e)

squareProg :: Text
squareProg =
  unlines
    [ "import IO.Stdout",
      "",
      "square : Int32 -> Int32",
      "square n = n",
      "",
      "main : IO Never Unit",
      "main = IO.Stdout.print (showInt32 (square 1))"
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

outOfRangeProg :: Text
outOfRangeProg =
  unlines
    [ "import IO.Stdout",
      "",
      "over : UInt8",
      "over = 300",
      "",
      "main : IO Never Unit",
      "main = IO.Stdout.print \"x\""
    ]
