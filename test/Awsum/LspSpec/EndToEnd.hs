{-# LANGUAGE DataKinds #-}

-- | End-to-end tests for @awsum lsp@: a real server is started in-process
--   over a pair of pipes ('runLspServerWithHandles') and driven through
--   @lsp-test@. Where the unit layer in "Awsum.LspSpec" checks the
--   extracted request logic, this layer confirms the handlers are
--   actually registered and the JSON-RPC envelopes are shaped the way
--   every editor client depends on — initialize/didOpen, formatting,
--   document symbols, hover, code actions, and pushed diagnostics.
module Awsum.LspSpec.EndToEnd (spec) where

import Awsum.Format (formatSource)
import Awsum.Lsp (debounceMicros, runLspServerWithHandles)
import Control.Concurrent (forkIO, threadDelay)
import Control.Exception (catch)
import Data.Text qualified as T
import GHC.Clock (getMonotonicTime)
import Language.LSP.Protocol.Capabilities (fullLatestClientCaps)
import Language.LSP.Protocol.Message
  ( FromServerMessage,
    FromServerMessage' (..),
    LspId,
    Method (..),
    SMethod (..),
    TNotificationMessage (..),
    TResponseError,
    TResponseMessage (..),
  )
import Language.LSP.Protocol.Types
  ( CodeAction (..),
    CodeActionContext (..),
    CodeActionKind (..),
    CodeActionParams (..),
    Command,
    Diagnostic (..),
    DocumentSymbol (..),
    DocumentSymbolParams (..),
    FormattingOptions (..),
    Hover (..),
    MarkupContent (..),
    Null,
    Position (..),
    PublishDiagnosticsParams (..),
    Range (..),
    TextDocumentContentChangeEvent (..),
    TextDocumentContentChangeWholeDocument (..),
    TextDocumentIdentifier (..),
    VersionedTextDocumentIdentifier (..),
    toNormalizedUri,
    type (|?) (..),
  )
import Language.LSP.Test
  ( Session,
    anyMessage,
    changeDoc,
    createDoc,
    defaultConfig,
    documentContents,
    formatDoc,
    getCodeActions,
    getDocumentSymbols,
    getHover,
    getVersionedDoc,
    runSessionWithHandles,
    sendRequest,
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

  -- Timing bounds are relative to the slow document's own check, measured
  -- in the same session: a request that waited on that check takes about
  -- as long as it, an independent one a small fraction.
  describe "stays responsive while a document is being checked" $ do
    it "answers requests on other documents during a check" $ do
      (answer, check) <- withServer $ do
        small <- createDoc "Small.aww" "awsum" squareProg
        _ <- awaitMessage (diagnosticsOf small)
        t0 <- now
        slow <- createDoc "Slow.aww" "awsum" slowProg
        rid <- sendRequest SMethod_TextDocumentDocumentSymbol (symbolParams small)
        ((tAnswer, _), (tChecked, _)) <- arrivals (symbolsResponse rid) (diagnosticsOf slow)
        pure (tAnswer - t0, tChecked - t0)
      answer `shouldSatisfy` (< check / 4)

    it "publishes a new version without waiting for the check of the one it replaced" $ do
      (wait, check, published, expected, later) <- withServer $ do
        t0 <- now
        slow <- createDoc "Slow.aww" "awsum" slowProg
        _ <- awaitMessage (diagnosticsOf slow)
        check <- subtract t0 <$> now
        replaceText slow (slowProg <> "\n-- an edit\n")
        -- The edited version's check is about halfway through.
        liftIO (threadDelay (debounceMicros + round (check * 500_000)))
        tEdit <- now
        replaceText slow (slowProg <> "\nbroken = (\n")
        expected <- (._version) <$> getVersionedDoc slow
        published <- awaitMessage (diagnosticsOf slow)
        tPublished <- now
        -- Time for a check of the replaced version to finish and publish.
        liftIO (threadDelay (round (check * 1_000_000)))
        rid <- sendRequest SMethod_TextDocumentDocumentSymbol (symbolParams slow)
        later <- messagesUntil (symbolsResponse rid)
        pure (tPublished - tEdit, check, published, expected, mapMaybe (diagnosticsOf slow) later)
      published._version `shouldBe` Just expected
      length published._diagnostics `shouldBe` 1
      map (._version) later `shouldBe` []
      wait `shouldSatisfy` (< fromIntegral debounceMicros / 1_000_000 + check / 4)

    it "answers code actions while another document is being checked" $ do
      (answer, check, result) <- withServer $ do
        small <- createDoc "Small.aww" "awsum" unusedParamProg
        warnings <- (._diagnostics) <$> awaitMessage (diagnosticsOf small)
        t0 <- now
        slow <- createDoc "Slow.aww" "awsum" slowProg
        _ <- awaitMessage (diagnosticsOf slow)
        check <- subtract t0 <$> now
        replaceText slow (slowProg <> "\n-- an edit\n")
        -- The edited version's check is running.
        liftIO (threadDelay (debounceMicros + round (check * 250_000)))
        tAsk <- now
        rid <- sendRequest SMethod_TextDocumentCodeAction (codeActionParams small warnings)
        ((tAnswer, result), _) <- arrivals (codeActionResponse rid) (diagnosticsOf slow)
        pure (tAnswer - tAsk, check, result)
      case result of
        Right (InL actions) -> any isQuickFix actions `shouldBe` True
        _ -> expectationFailure "expected code actions"
      answer `shouldSatisfy` (< check / 4)

    it "serves hover from the document's last check instead of re-checking" $ do
      (hoverTime, check, mh) <- withServer $ do
        t0 <- now
        slow <- createDoc "Slow.aww" "awsum" slowProg
        _ <- awaitMessage (diagnosticsOf slow)
        check <- subtract t0 <$> now
        t1 <- now
        mh <- getHover slow (positionOf "res : " slowProg)
        t2 <- now
        pure (t2 - t1, check, mh)
      case mh of
        Just (Hover (InL (MarkupContent _ md)) _) -> md `shouldSatisfy` T.isInfixOf "Bool"
        _ -> expectationFailure "expected a markdown hover carrying the type"
      hoverTime `shouldSatisfy` (< check / 4)

    it "serves hover for the text just edited, not the last check" $ do
      mh <- withServer $ do
        doc <- openMain paramProg
        _ <- awaitMessage (diagnosticsOf doc)
        let edited = T.replace "Int32 -> Int32" "UInt8 -> UInt8" paramProg
        replaceText doc edited
        getHover doc (positionOf "n = n" edited) -- the parameter 'n'
      case mh of
        Just (Hover (InL (MarkupContent _ md)) _) -> md `shouldSatisfy` T.isInfixOf "UInt8"
        _ -> expectationFailure "expected a markdown hover carrying the type"
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

-- | Replace a document's whole text.
replaceText :: TextDocumentIdentifier -> Text -> Session ()
replaceText doc text =
  changeDoc doc [TextDocumentContentChangeEvent (InR (TextDocumentContentChangeWholeDocument text))]

-- | Seconds on a monotonic clock.
now :: Session Double
now = liftIO getMonotonicTime

-- | Read server messages until @pick@ accepts one.
awaitMessage :: (FromServerMessage -> Maybe a) -> Session a
awaitMessage pick = anyMessage >>= \msg -> maybe (awaitMessage pick) pure (pick msg)

-- | The server messages before the first one @stop@ accepts.
messagesUntil :: (FromServerMessage -> Maybe a) -> Session [FromServerMessage]
messagesUntil stop = do
  msg <- anyMessage
  if isJust (stop msg) then pure [] else (msg :) <$> messagesUntil stop

-- | Read server messages until each matcher has accepted one: when each
--   did, and what it accepted.
arrivals :: (FromServerMessage -> Maybe a) -> (FromServerMessage -> Maybe b) -> Session ((Double, a), (Double, b))
arrivals pickA pickB = go Nothing Nothing
  where
    go (Just a) (Just b) = pure (a, b)
    go ma mb = do
      msg <- anyMessage
      t <- now
      go (ma <|> ((t,) <$> pickA msg)) (mb <|> ((t,) <$> pickB msg))

-- | Diagnostics pushed for @doc@.
diagnosticsOf :: TextDocumentIdentifier -> FromServerMessage -> Maybe PublishDiagnosticsParams
diagnosticsOf doc = \case
  FromServerMess SMethod_TextDocumentPublishDiagnostics (TNotificationMessage _ _ params)
    | toNormalizedUri params._uri == toNormalizedUri doc._uri -> Just params
  _ -> Nothing

symbolsResponse :: LspId 'Method_TextDocumentDocumentSymbol -> FromServerMessage -> Maybe ()
symbolsResponse rid = \case
  FromServerRsp SMethod_TextDocumentDocumentSymbol (TResponseMessage _ (Just i) _) | i == rid -> Just ()
  _ -> Nothing

codeActionResponse ::
  LspId 'Method_TextDocumentCodeAction ->
  FromServerMessage ->
  Maybe (Either (TResponseError 'Method_TextDocumentCodeAction) ([Command |? CodeAction] |? Null))
codeActionResponse rid = \case
  FromServerRsp SMethod_TextDocumentCodeAction (TResponseMessage _ (Just i) result) | i == rid -> Just result
  _ -> Nothing

symbolParams :: TextDocumentIdentifier -> DocumentSymbolParams
symbolParams doc = DocumentSymbolParams {_workDoneToken = Nothing, _partialResultToken = Nothing, _textDocument = doc}

-- | Code actions for the given diagnostics, at the first one's range.
codeActionParams :: TextDocumentIdentifier -> [Diagnostic] -> CodeActionParams
codeActionParams doc diags =
  CodeActionParams
    { _workDoneToken = Nothing,
      _partialResultToken = Nothing,
      _textDocument = doc,
      _range = maybe (Range (Position 0 0) (Position 0 0)) (._range) (listToMaybe diags),
      _context = CodeActionContext {_diagnostics = diags, _only = Nothing, _triggerKind = Nothing}
    }

-- | The position of the first occurrence of @needle@ in @src@.
positionOf :: Text -> Text -> Position
positionOf needle src =
  case [(i, T.length prefix) | (i, l) <- zip [0 ..] (lines src), let (prefix, rest) = T.breakOn needle l, not (T.null rest)] of
    (i, col) : _ -> Position i (fromIntegral col)
    [] -> error ("fixture lacks " <> needle)

-- | A program whose check takes about a second: 1200 constructors over as
--   many type parameters, each used once — its typecheck grows as the
--   square of that count.
slowProg :: Text
slowProg =
  unlines
    $ ["import IO.Stdout", "", "type T " <> unwords (map param range), "  = T1 a1"]
    <> ["  | T" <> show i <> " " <> param i | i <- drop 1 range]
    <> ["", "un : T " <> unwords ("Bool" <$ range) <> " -> Bool", "un c = case c of"]
    <> ["  T" <> show i <> " x -> x" | i <- range]
    <> ["", "res : Bool", "res = " <> nestAnd ["(un (T" <> show i <> " True))" | i <- range]]
    <> ["", "main : IO Never Unit", "main = IO.Stdout.print (showBool res)"]
  where
    range = [1 .. 1200 :: Int]
    param i = "a" <> show i
    nestAnd :: [Text] -> Text
    nestAnd = \case
      [x] -> x
      x : xs -> "(and " <> x <> " " <> nestAnd xs <> ")"
      [] -> "True"

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

-- | A well-typed program whose parameter type an edit can change without
--   breaking it.
paramProg :: Text
paramProg =
  unlines
    [ "import IO.Stdout",
      "",
      "square : Int32 -> Int32",
      "square n = n",
      "",
      "main : IO Never Unit",
      "main = IO.Stdout.print \"x\""
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
