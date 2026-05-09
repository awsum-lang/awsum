-- | Awsum Language Server Protocol implementation.
--
-- Wraps the existing @Awsum.Diagnostic@ / @Awsum.Symbols@ / @Awsum.Format@
-- modules behind a stdio LSP server. The same compiler binary serves as
-- both the CLI (@awsum check@, @awsum format@, @awsum symbols@, …) and the
-- language server (@awsum lsp@): one parser, one typechecker, one fix
-- payload, no version-skew possible.
--
-- Feature parity with @awsum-vscode@ as of this commit:
--   * push diagnostics on open / save / change (debounced 500 ms);
--   * code actions for compiler-supplied @fixes@ payload;
--   * formatting via @Awsum.Format@;
--   * document symbols via @Awsum.Symbols@;
--   * workspace symbols by scanning @.aww@ files under @rootUri@.
module Awsum.Lsp (runLspServer) where

import Awsum.Diagnostic qualified as AD
import Awsum.ElaborateLower (elaborateLowerProgram)
import Awsum.Format (formatSource)
import Awsum.Parser (parseProgramDiagnostic)
import Awsum.Prelude (stripPreludeWarnings, withPrelude)
import Awsum.Program (ProgramType (..))
import Awsum.Symbols qualified as ASym
import Awsum.Syntax qualified as ASyn
import Common.File (readFileTextUtf8)
import Control.Concurrent (forkIO, threadDelay)
import Control.Exception (catch)
import Control.Lens ((^.))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as AesonKey
import Data.Aeson.KeyMap qualified as AesonKeyMap
import Data.Char (isDigit)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Language.LSP.Protocol.Lens qualified as L
import Language.LSP.Protocol.Message
import Language.LSP.Protocol.Types
import Language.LSP.Server
import Language.LSP.VFS (virtualFileText)
import Relude
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath (takeExtension, (</>))

-- ════════════════════════════════════════════════════════════════════════════
-- Server state
-- ════════════════════════════════════════════════════════════════════════════

-- | Per-server state, held behind 'IORef's so handlers can mutate from
--   either the main LSP thread or a forked debouncer thread.
data ServerState = ServerState
  { -- | Latest /pending/ check version per document. The debouncer fork
    --   compares against this to drop stale checks (a newer @didChange@
    --   bumps the counter, the older fork's wakeup sees the newer counter
    --   and silently exits).
    ssVersions :: IORef (Map NormalizedUri Word),
    -- | Compiler-supplied quick fixes per @(uri, range)@. Refilled on every
    --   successful check; consulted by the @textDocument/codeAction@
    --   handler.
    ssFixes :: IORef (Map (NormalizedUri, RangeKey) [AD.Fix]),
    -- | Workspace folders received during initialize. Used by
    --   @workspace/symbol@ as scan roots.
    ssWorkspaceRoots :: IORef [FilePath],
    -- | The compiler's own version, frozen at process start (passed into
    --   'runLspServer' from "Main"). The @SMethod_Initialized@ handler
    --   compares it against 'chExpectedAwsumVersion' and, on mismatch,
    --   surfaces a warning through the client.
    ssCompilerVersion :: Text,
    -- | Hints the client passed in @initializationOptions@: which
    --   @awsum@ version it expects, and how it would prefer a UX
    --   like the version-mismatch warning to be presented. Captured
    --   in 'doInitialize', consumed in the @Initialized@ handler.
    ssClientHints :: IORef ClientHints
  }

-- | Optional fields the client may set in @initialize.params.initializationOptions@.
--   Absent fields fall back to defaults that match the loosest
--   behaviour (no version warning, prefer-link UI).
data ClientHints = ClientHints
  { -- | The @awsum@ version the client was built against. The server
    --   compares with its own version on @initialized@ and warns on
    --   mismatch (unless either side is non-@A.B.C@).
    chExpectedAwsumVersion :: Maybe Text,
    -- | UX preference for the version-mismatch warning. @True@ ⇒
    --   @window/showMessageRequest@ with an action button (better for
    --   VS Code: it doesn't auto-linkify URLs in notifications, but
    --   reliably routes @window/showDocument@ to
    --   @vscode.env.openExternal@). @False@ ⇒ @window/showMessage@
    --   with the URL inline (better for Zed: it auto-linkifies
    --   notification URLs but currently doesn't open external https
    --   URLs from @window/showDocument@).
    chPreferButtonsOverLinks :: Bool
  }

defaultClientHints :: ClientHints
defaultClientHints =
  ClientHints
    { chExpectedAwsumVersion = Nothing,
      chPreferButtonsOverLinks = False
    }

-- | Stable @Ord@-able key for a 'Range' so we can index the fixes map.
type RangeKey = (UInt, UInt, UInt, UInt)

rangeKey :: Range -> RangeKey
rangeKey r =
  ( r ^. L.start . L.line,
    r ^. L.start . L.character,
    r ^. L.end . L.line,
    r ^. L.end . L.character
  )

newServerState :: Text -> IO ServerState
newServerState compilerVersion =
  ServerState
    <$> newIORef Map.empty
    <*> newIORef Map.empty
    <*> newIORef []
    <*> pure compilerVersion
    <*> newIORef defaultClientHints

-- ════════════════════════════════════════════════════════════════════════════
-- Awsum ↔ LSP type conversions
-- ════════════════════════════════════════════════════════════════════════════

-- | Awsum spans are 1-based @(line, col)@; LSP 'Range's are 0-based
--   @(line, character)@. The @-1@ shift is the only translation needed.
spanToRange :: ASyn.SrcSpan -> Range
spanToRange (ASyn.SrcSpan sl sc el ec) =
  Range
    (Position (toUInt (sl - 1)) (toUInt (sc - 1)))
    (Position (toUInt (el - 1)) (toUInt (ec - 1)))
  where
    toUInt :: Int -> UInt
    toUInt = fromIntegral . max 0

severityToLsp :: AD.Severity -> DiagnosticSeverity
severityToLsp = \case
  AD.SevError -> DiagnosticSeverity_Error
  AD.SevWarning -> DiagnosticSeverity_Warning

awsumDiagToLsp :: AD.Diagnostic -> Diagnostic
awsumDiagToLsp (AD.Diagnostic sev sp msg _fixes) =
  Diagnostic
    { _range = spanToRange sp,
      _severity = Just (severityToLsp sev),
      _code = Nothing,
      _codeDescription = Nothing,
      _source = Just "awsum",
      _message = msg,
      _tags = Nothing,
      _relatedInformation = Nothing,
      _data_ = Nothing
    }

awsumSymbolKindToLsp :: ASym.SymbolKind -> SymbolKind
awsumSymbolKindToLsp = \case
  ASym.SkFunction -> SymbolKind_Function
  ASym.SkConstant -> SymbolKind_Constant
  -- Mirrors awsum-vscode's mapping (SymbolKind.Enum) so the outline icons
  -- look the same in Zed and VS Code.
  ASym.SkType -> SymbolKind_Enum

-- | Recursive translation, depth-first.
awsumSymbolToLsp :: ASym.Symbol -> DocumentSymbol
awsumSymbolToLsp (ASym.Symbol k n r sr cs) =
  DocumentSymbol
    { _name = n,
      _detail = Nothing,
      _kind = awsumSymbolKindToLsp k,
      _tags = Nothing,
      _deprecated = Nothing,
      _range = spanToRange r,
      _selectionRange = spanToRange sr,
      _children = Just (map awsumSymbolToLsp cs)
    }

-- ════════════════════════════════════════════════════════════════════════════
-- Compile pipeline
-- ════════════════════════════════════════════════════════════════════════════

-- | Source text → Awsum diagnostics. Mirrors the @awsum check@ pipeline in
--   "Main.runCheck" — parse, elaborate (which runs typecheck + every
--   Core-to-Core pass), warn-or-error.
compileToDiagnostics :: Text -> [AD.Diagnostic]
compileToDiagnostics src =
  case parseProgramDiagnostic src of
    Left parseErrs -> map AD.parseErrorToDiagnostic parseErrs
    Right userProg ->
      case elaborateLowerProgram ProgramCli (withPrelude userProg) of
        Left typeErr -> [AD.typeErrorToDiagnostic typeErr]
        Right (warns, _ptags, _core) ->
          map AD.warningToDiagnostic (stripPreludeWarnings warns)

-- ════════════════════════════════════════════════════════════════════════════
-- Diagnostics + fix index update
-- ════════════════════════════════════════════════════════════════════════════

-- | Run the compile pipeline, push diagnostics to the client, and refresh
--   the fixes index for the document.
publishCheckResult ::
  ServerState ->
  NormalizedUri ->
  Maybe Int32 ->
  Text ->
  LspM () ()
publishCheckResult st uri mVersion src = do
  let diags = compileToDiagnostics src
      lspDiags = map awsumDiagToLsp diags
      newFixEntries =
        [ ((uri, rangeKey (spanToRange (AD.diagSpan d))), AD.diagFixes d)
        | d <- diags,
          not (null (AD.diagFixes d))
        ]
  -- Replace fixes for this URI atomically: drop stale ones, install new ones.
  liftIO $ atomicModifyIORef' (ssFixes st) $ \m ->
    let cleared = Map.filterWithKey (\(u, _) _ -> u /= uri) m
        updated = foldr (uncurry Map.insert) cleared newFixEntries
     in (updated, ())
  sendNotification
    SMethod_TextDocumentPublishDiagnostics
    PublishDiagnosticsParams
      { _uri = fromNormalizedUri uri,
        _version = mVersion,
        _diagnostics = lspDiags
      }

-- | Read current text from VFS. @Nothing@ when the document is not tracked
--   (e.g. closed before the handler ran).
readDocText :: NormalizedUri -> LspM () (Maybe Text)
readDocText uri = fmap virtualFileText <$> getVirtualFile uri

-- ════════════════════════════════════════════════════════════════════════════
-- Debounced check on didChange
-- ════════════════════════════════════════════════════════════════════════════

-- | Schedule a debounced check for a document. Each @didChange@ bumps a
--   per-URI counter; a fork sleeps 500 ms and only runs the check if it
--   still holds the latest counter. Newer changes silently invalidate
--   older forks — at most one published-diagnostics burst per quiet
--   period.
scheduleDebouncedCheck ::
  ServerState ->
  NormalizedUri ->
  Maybe Int32 ->
  LspM () ()
scheduleDebouncedCheck st uri mVersion = do
  myVer <- liftIO $ atomicModifyIORef' (ssVersions st) $ \m ->
    let v = Map.findWithDefault 0 uri m + 1
     in (Map.insert uri v m, v)
  env <- getLspEnv
  void $ liftIO $ forkIO $ do
    threadDelay 500_000 -- 500 ms
    currentVer <- Map.lookup uri <$> readIORef (ssVersions st)
    when (currentVer == Just myVer) $ runLspT env $ do
      mtxt <- readDocText uri
      whenJust mtxt $ \src -> publishCheckResult st uri mVersion src

-- ════════════════════════════════════════════════════════════════════════════
-- Handlers
-- ════════════════════════════════════════════════════════════════════════════

-- | Notifications the server is expected to receive but doesn't act on.
--
-- The 'lsp' framework logs every unhandled notification as a warning
-- ("LSP: no handler for: …"); registering an explicit no-op silences
-- the noise and documents the deliberate choice. Add a line here when
-- a new "yes, we receive this and intentionally ignore it" arrives.
stubNotifications :: Handlers (LspM ())
stubNotifications =
  mconcat
    [ -- Configuration change. The actual config update is handled by
      -- `parseConfig` / `onConfigChange` in the 'ServerDefinition'
      -- below; this handler only acknowledges the notification.
      notificationHandler SMethod_WorkspaceDidChangeConfiguration (const pass),
      -- Trace-level toggle from the client (`$/setTrace`). We don't
      -- emit LSP trace output, so silently accept and discard.
      notificationHandler SMethod_SetTrace (const pass),
      -- Request cancellation. Our handlers are short and synchronous —
      -- there's nothing meaningful to cancel mid-flight, the response
      -- arrives fast enough that the client discards it as stale.
      notificationHandler SMethod_CancelRequest (const pass)
    ]

-- | Lockstep version check, run once after the client sends
--   @initialized@. The client owns the decision /which/ awsum version
--   it expected (passed in
--   @initializationOptions.expectedAwsumVersion@ — extracted in
--   'doInitialize' and stashed in 'ssClientHints'); we just compare
--   against the running compiler's version and surface a warning when
--   they disagree. Pre-release / dirty versions (anything not
--   @A.B.C@) opt out — local dev sessions shouldn't spam the user.
--
--   The /how/ of the warning is also a client-supplied preference
--   ('chPreferButtonsOverLinks'): button-driven
--   @window/showMessageRequest@ + @window/showDocument@ for VS Code,
--   plain @window/showMessage@ with an inline URL for Zed. Different
--   clients render notifications differently; this lets each pick the
--   path that actually surfaces a clickable install link.
checkVersionOnInitialized :: ServerState -> LspM () ()
checkVersionOnInitialized st = do
  hints <- liftIO $ readIORef (ssClientHints st)
  let compiler = ssCompilerVersion st
  whenJust (chExpectedAwsumVersion hints) $ \expectedVer ->
    when
      ( looksLikeSemver expectedVer
          && looksLikeSemver compiler
          && expectedVer
          /= compiler
      )
      $ do
        -- Both branches use @window/showMessageRequest@, not
        -- @window/showMessage@: a /request/ stays visible until the
        -- user actively dismisses, while a /notification/ is
        -- transient and gets auto-cleared by clients like Zed within
        -- a few seconds — too short to read, let alone click. The
        -- two branches differ only in /how/ they surface the install
        -- URL (button vs inline).
        let installUrl :: Text
            installUrl = "https://awsum-lang.org/install"
            installLabel :: Text
            installLabel = "Open install page"
            preferButtons = chPreferButtonsOverLinks hints
            messageBody :: Text
            messageBody =
              "Awsum version mismatch: the client expected awsum "
                <> expectedVer
                <> ", but this server is awsum "
                <> compiler
                <> ". Update awsum"
                -- URL inline only when no working action button is
                -- on offer. Otherwise it's redundant noise next to
                -- the button.
                <> (if preferButtons then "" else " (" <> installUrl <> ")")
                <> " or install a matching client; behaviour may be unpredictable until they match."
            -- Button on clients that have a working
            -- @window/showDocument@ for external URLs (VS Code). For
            -- clients without that capability (Zed today), no button:
            -- a non-functional button is worse than none, and the
            -- inline URL above carries the same payload.
            actions = [MessageActionItem installLabel | preferButtons]
            params =
              ShowMessageRequestParams
                { _type_ = MessageType_Warning,
                  _message = messageBody,
                  _actions = Just actions
                }
        void $ sendRequest SMethod_WindowShowMessageRequest params $ \case
          Right (InL (MessageActionItem chosen))
            | chosen == installLabel ->
                -- Client picked the install action. Open the page in
                -- the user's browser via the standard LSP show-doc
                -- mechanism.
                void
                  $ sendRequest
                    SMethod_WindowShowDocument
                    ShowDocumentParams
                      { _uri = Uri installUrl,
                        _external = Just True,
                        _takeFocus = Nothing,
                        _selection = Nothing
                      }
                  $ const pass
          _ -> pass

-- | True iff the text is exactly an @A.B.C@ triple (digits only).
--   Anything richer (pre-release tag, dirty git suffix) opts out of the
--   strict-equality check — those are dev-mode versions, not lockstep
--   release versions.
looksLikeSemver :: Text -> Bool
looksLikeSemver t = case T.splitOn "." t of
  [a, b, c] -> not (any T.null [a, b, c]) && all (T.all isDigit) [a, b, c]
  _ -> False

-- | Pull every recognised hint field out of @initializationOptions@,
--   substituting defaults for absent / wrong-shape fields. Tolerant
--   parser by design — clients should be able to extend
--   @initializationOptions@ with private keys without breaking us, and
--   omitting our hints should leave the server in a working state.
extractClientHints :: Maybe Aeson.Value -> ClientHints
extractClientHints (Just (Aeson.Object o)) =
  ClientHints
    { chExpectedAwsumVersion =
        case AesonKeyMap.lookup (AesonKey.fromString "expectedAwsumVersion") o of
          Just (Aeson.String s) -> Just s
          _ -> Nothing,
      chPreferButtonsOverLinks =
        case AesonKeyMap.lookup (AesonKey.fromString "preferButtonsOverLinks") o of
          Just (Aeson.Bool b) -> b
          _ -> False
    }
extractClientHints _ = defaultClientHints

serverHandlers :: ServerState -> Handlers (LspM ())
serverHandlers st =
  mconcat
    [ stubNotifications,
      -- @initialized@ — sent once by the client when it's ready to
      -- receive notifications. Triggers the lockstep version check;
      -- see 'checkVersionOnInitialized' for the comparison logic.
      notificationHandler SMethod_Initialized $ \_ -> checkVersionOnInitialized st,
      -- New document: run check immediately so the user sees diagnostics
      -- without waiting for the first edit.
      notificationHandler SMethod_TextDocumentDidOpen $ \msg -> do
        let item = msg ^. L.params . L.textDocument
            uri = toNormalizedUri (item ^. L.uri)
            ver = item ^. L.version
            src = item ^. L.text
        publishCheckResult st uri (Just ver) src,
      -- Each keystroke: schedule a check via the 500 ms debouncer.
      notificationHandler SMethod_TextDocumentDidChange $ \msg -> do
        let uri = toNormalizedUri (msg ^. L.params . L.textDocument . L.uri)
            ver = msg ^. L.params . L.textDocument . L.version
        scheduleDebouncedCheck st uri (Just ver),
      -- Save: re-check with the on-disk content (which is what the VFS now
      -- reports — clients send didChange before didSave).
      notificationHandler SMethod_TextDocumentDidSave $ \msg -> do
        let uri = toNormalizedUri (msg ^. L.params . L.textDocument . L.uri)
        mtxt <- readDocText uri
        whenJust mtxt $ \src -> publishCheckResult st uri Nothing src,
      -- Close: drop tracking state and clear the squigglies.
      notificationHandler SMethod_TextDocumentDidClose $ \msg -> do
        let uri = toNormalizedUri (msg ^. L.params . L.textDocument . L.uri)
        liftIO $ atomicModifyIORef' (ssVersions st) $ \m -> (Map.delete uri m, ())
        liftIO $ atomicModifyIORef' (ssFixes st) $ \m ->
          (Map.filterWithKey (\(u, _) _ -> u /= uri) m, ())
        sendNotification
          SMethod_TextDocumentPublishDiagnostics
          PublishDiagnosticsParams
            { _uri = fromNormalizedUri uri,
              _version = Nothing,
              _diagnostics = []
            },
      -- Quick fixes: pull from the fix index by (uri, range), wrap as
      -- CodeAction(WorkspaceEdit).
      requestHandler SMethod_TextDocumentCodeAction $ \req responder -> do
        let uri = toNormalizedUri (req ^. L.params . L.textDocument . L.uri)
            ctxDiags = req ^. L.params . L.context . L.diagnostics
        fixesIdx <- liftIO $ readIORef (ssFixes st)
        let actions :: [Command |? CodeAction]
            actions =
              [ InR (fixToCodeAction uri d qf)
              | d <- ctxDiags,
                qf <- fromMaybe [] (Map.lookup (uri, rangeKey (d ^. L.range)) fixesIdx)
              ]
        responder (Right (InL actions)),
      -- Formatting: re-render via Awsum.Format. The whole-document edit
      -- replaces the entire buffer; the client is expected to merge.
      requestHandler SMethod_TextDocumentFormatting $ \req responder -> do
        let uri = toNormalizedUri (req ^. L.params . L.textDocument . L.uri)
        mtxt <- readDocText uri
        case mtxt of
          Nothing -> responder (Right (InR Null))
          Just src -> case formatSource src of
            -- Format failure (parse error) — return no edits rather than
            -- erroring out; diagnostics already surfaced the parse problem.
            Left _err -> responder (Right (InR Null))
            Right formatted ->
              responder
                ( Right
                    ( InL
                        [TextEdit (wholeDocumentRange src) formatted]
                    )
                ),
      -- Outline / breadcrumbs / symbol search inside a file.
      requestHandler SMethod_TextDocumentDocumentSymbol $ \req responder -> do
        let uri = toNormalizedUri (req ^. L.params . L.textDocument . L.uri)
        mtxt <- readDocText uri
        let syms :: [DocumentSymbol]
            syms = case mtxt of
              Nothing -> []
              Just src -> case parseProgramDiagnostic src of
                -- Parse error: outline is empty until the user fixes the
                -- syntax. The diagnostics path tells them what's wrong.
                Left _ -> []
                Right prog -> map awsumSymbolToLsp (ASym.symbolsOfProgram prog)
            -- lsp-types orders the union as `SymbolInformation[] | DocumentSymbol[] | null`
            -- (legacy alternative first, then DocumentSymbol[], then null).
            -- We always pick the DocumentSymbol[] branch.
            result :: [SymbolInformation] |? ([DocumentSymbol] |? Null)
            result = InR (InL syms)
        responder (Right result),
      -- Cross-file symbol search (Cmd+T / Ctrl+T). Scans every @.aww@ file
      -- under the workspace roots received at @initialize@. No incremental
      -- index — each request walks the disk. Acceptable for v0; if it
      -- becomes a bottleneck on large projects, add a cache + a
      -- @workspace/didChangeWatchedFiles@-driven invalidator.
      requestHandler SMethod_WorkspaceSymbol $ \req responder -> do
        let q = T.toLower (req ^. L.params . L.query)
        roots <- liftIO $ readIORef (ssWorkspaceRoots st)
        files <- liftIO $ concat <$> mapM findAwwFiles roots
        matches <- liftIO $ concat <$> mapM (workspaceSymbolsForFile q) files
        responder (Right (InL matches))
    ]

-- | Convert one Awsum 'AD.Fix' into an LSP 'CodeAction'. The diagnostic the
--   action came from is tucked into @diagnostics@ so VS Code shows it
--   inline next to the lightbulb.
fixToCodeAction :: NormalizedUri -> Diagnostic -> AD.Fix -> CodeAction
fixToCodeAction uri d (AD.Fix title edits) =
  CodeAction
    { _title = title,
      _kind = Just CodeActionKind_QuickFix,
      _diagnostics = Just [d],
      _isPreferred = Just True,
      _disabled = Nothing,
      _edit = Just (mkWorkspaceEdit uri edits),
      _command = Nothing,
      _data_ = Nothing
    }

mkWorkspaceEdit :: NormalizedUri -> [AD.Edit] -> WorkspaceEdit
mkWorkspaceEdit uri edits =
  WorkspaceEdit
    { _changes =
        Just
          ( Map.singleton
              (fromNormalizedUri uri)
              [TextEdit (spanToRange sp) newText | AD.Edit sp newText <- edits]
          ),
      _documentChanges = Nothing,
      _changeAnnotations = Nothing
    }

-- | A 'Range' covering the entire document text. Used by the formatter to
--   replace the buffer in one edit.
wholeDocumentRange :: Text -> Range
wholeDocumentRange src =
  let ls = T.splitOn "\n" src
      lastLineLen = maybe 0 T.length (viaNonEmpty last ls)
      lineCount = length ls
   in Range
        (Position 0 0)
        ( Position
            (fromIntegral (max 0 (lineCount - 1)))
            (fromIntegral lastLineLen)
        )

-- ════════════════════════════════════════════════════════════════════════════
-- Workspace symbol scan
-- ════════════════════════════════════════════════════════════════════════════

-- | Same exclude list as @awsum-vscode/src/extension.ts@ uses in its
--   @findFiles@ call, so workspace symbol search behaves consistently
--   across editors.
excludedDirs :: [FilePath]
excludedDirs = ["node_modules", ".stack-work", ".snapshots", "dist-newstyle", ".git"]

-- | Walk one workspace root, returning every @.aww@ file underneath.
--   Symlink-loops are not handled — we match the existing @awsum-vscode@
--   coverage, which relies on VS Code's @findFiles@ glob exclude.
findAwwFiles :: FilePath -> IO [FilePath]
findAwwFiles = walk
  where
    walk :: FilePath -> IO [FilePath]
    walk dir = do
      isDir <- doesDirectoryExist dir
      if not isDir
        then pure []
        else do
          es <- listDirectory dir
          fmap concat . forM es $ \e -> do
            let p = dir </> e
            isSubdir <- doesDirectoryExist p
            if isSubdir
              then
                if e `elem` excludedDirs
                  then pure []
                  else walk p
              else
                if takeExtension p == ".aww"
                  then pure [p]
                  else pure []

-- | Symbols from one file as flat 'SymbolInformation' entries (matching
--   the existing @awsum-vscode@ workspace-symbol shape — depth-first
--   flatten, no parent relation in v0).
workspaceSymbolsForFile :: Text -> FilePath -> IO [SymbolInformation]
workspaceSymbolsForFile q file = do
  -- File listed by 'findAwwFiles' may have disappeared by the time we
  -- read it (race with the user's editor / build / git). Treat any
  -- exception as "skip this file" rather than crashing the request.
  mSrc <-
    (Just <$> readFileTextUtf8 file)
      `catch` \(_ :: SomeException) -> pure Nothing
  pure $ case mSrc of
    Nothing -> []
    Just src -> case parseProgramDiagnostic src of
      Left _ -> []
      Right prog ->
        let syms = flattenSymbols (ASym.symbolsOfProgram prog)
            fileUri = filePathToUri file
         in [ SymbolInformation
                { _name = n,
                  _kind = awsumSymbolKindToLsp k,
                  _tags = Nothing,
                  _deprecated = Nothing,
                  _location = Location {_uri = fileUri, _range = spanToRange r},
                  _containerName = Nothing
                }
            | ASym.Symbol k n r _sr _cs <- syms,
              q == "" || T.isInfixOf q (T.toLower n)
            ]
  where
    flattenSymbols :: [ASym.Symbol] -> [ASym.Symbol]
    flattenSymbols = concatMap go
      where
        go s = s : concatMap go (ASym.symChildren s)

-- ════════════════════════════════════════════════════════════════════════════
-- Server entry point
-- ════════════════════════════════════════════════════════════════════════════

-- | Run the LSP server over stdio. Returns the protocol exit code: 0 on
--   clean shutdown, non-zero on protocol violation. Called from
--   @awsum lsp --stdio@ in "Main".
--
--   The compiler version is supplied by the caller (Main.hs reads it
--   from @Paths_awsum.version@) and threaded into the @initialize@
--   response's @serverInfo@ field. Editor extensions sync this against
--   their own version and warn the user on mismatch — the LSP-native
--   replacement for the previous CLI-based @awsum --version@ check.
runLspServer :: Text -> IO Int
runLspServer compilerVersion = do
  st <- newServerState compilerVersion
  runServer
    ServerDefinition
      { defaultConfig = (),
        configSection = "awsum",
        parseConfig = \_ _ -> Right (),
        onConfigChange = const pass,
        doInitialize = \env req -> do
          -- Capture workspace folders for workspace/symbol scans.
          let folders = case req ^. L.params . L.workspaceFolders of
                Just (InL fs) -> [uriToFilePathOrEmpty (f ^. L.uri) | f <- fs]
                _ -> case req ^. L.params . L.rootUri of
                  InL u -> maybeToList (uriToFilePath u)
                  _ -> case req ^. L.params . L.rootPath of
                    Just (InL p) -> [toString p]
                    _ -> []
          writeIORef (ssWorkspaceRoots st) folders
          -- Capture the client's hints (expected awsum version, UX
          -- preference for the mismatch warning). Deferred to the
          -- @initialized@ handler for the actual comparison — we
          -- can't push notifications from within @doInitialize@.
          writeIORef
            (ssClientHints st)
            (extractClientHints (req ^. L.params . L.initializationOptions))
          pure (Right env),
        staticHandlers = \_caps -> serverHandlers st,
        interpretHandler = \env -> Iso (runLspT env) liftIO,
        -- Explicitly advertise text-document synchronization. Without
        -- this, VS Code (and other strict LSP clients) skip sending
        -- didOpen / didChange / didSave / didClose entirely — the
        -- server starts, capabilities respond, the client confirms,
        -- and then no document ever arrives. Symbols/format/diagnostics
        -- silently never fire because there's nothing to fire on.
        options =
          defaultOptions
            { -- Advertise the compiler version. Editor extensions read
              -- this from the `initialize` response's `serverInfo` and
              -- warn the user when it doesn't match their own version
              -- (lockstep `awsum-vscode A.B.C` ↔ `awsum A.B.C`).
              optServerInfo = Just (ServerInfo "awsum" (Just compilerVersion)),
              optTextDocumentSync =
                Just
                  TextDocumentSyncOptions
                    { _openClose = Just True,
                      -- Full-document sync is more bandwidth than
                      -- Incremental on every keystroke, but our pipeline
                      -- typechecks the whole file regardless — there's
                      -- no incremental advantage server-side, and the
                      -- code path is simpler.
                      _change = Just TextDocumentSyncKind_Full,
                      _willSave = Nothing,
                      _willSaveWaitUntil = Nothing,
                      _save = Just (InR (SaveOptions {_includeText = Just False}))
                    }
            }
      }
  where
    uriToFilePathOrEmpty :: Uri -> FilePath
    uriToFilePathOrEmpty u = fromMaybe "" (uriToFilePath u)
