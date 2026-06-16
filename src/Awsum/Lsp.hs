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
--   * workspace symbols by scanning @.aww@ files under @rootUri@;
--   * hover with the doc comment attached to the declaration under the
--     cursor (markdown).
module Awsum.Lsp
  ( runLspServer,
    runLspServerWithHandles,
    -- Internals exported for testing. 'Awsum.HoverSpec' drives
    -- 'hoverForPosition' on small fixtures; 'Awsum.LspSpec' drives the
    -- rest of the request logic directly (formatting edits, diagnostics,
    -- symbols, code actions, version check, client hints) and the whole
    -- server end-to-end through 'runLspServerWithHandles'.
    compileToTypedProgram,
    hoverForPosition,
    formatEdits,
    compileToDiagnostics,
    awsumDiagToLsp,
    documentSymbolsForSource,
    fixToCodeAction,
    workspaceSymbolsForFile,
    looksLikeSemver,
    shouldWarnVersionMismatch,
    extractClientHints,
    ClientHints (..),
  )
where

import Awsum.Desugar (desugarProgram)
import Awsum.Diagnostic qualified as AD
import Awsum.ElaborateLower (elaborateLowerProgram)
import Awsum.Format (formatSource)
import Awsum.HM (stripSyntheticTyvarSuffix)
import Awsum.Parser (parseProgramDiagnostic)
import Awsum.Prelude (preludeDefNames, preludeProgram, stripPreludeWarnings, withPrelude)
import Awsum.Program (ProgramType (..))
import Awsum.Render (renderType)
import Awsum.RestrictPreludeRefs (restrictPreludeRefs)
import Awsum.Symbols qualified as ASym
import Awsum.Syntax qualified as ASyn
import Awsum.TExpr
  ( TAlt (..),
    TDecl (..),
    TExpr (..),
    TParam (..),
    TPattern (..),
    TRowAlt (..),
    TypedProgram (..),
    tdeclName,
  )
import Awsum.Typing (emptyTypeNamesInProgram, markEmptyTypesInDecl, typecheckProgram)
import Awsum.Width qualified as Width
import Common.File (readFileTextUtf8)
import Control.Concurrent (forkIO, threadDelay)
import Control.Exception (catch)
import Control.Lens ((^.))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as AesonKey
import Data.Aeson.KeyMap qualified as AesonKeyMap
import Data.Algorithm.Diff qualified as Diff
import Data.Char (isDigit)
import Data.List (minimumBy)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
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

-- | Document text split on newlines; 1-based span line numbers index into
--   it. Carried by every range producer because the column-unit conversion
--   below needs the source line.
type SrcLines = [Text]

docLines :: Text -> SrcLines
docLines = lines

-- | Awsum spans are 1-based @(line, col)@ with columns in /display width/
--   (Megaparsec advances two columns per wide character — see "Awsum.Width");
--   LSP 'Range's are 0-based @(line, character)@ with @character@ in /UTF-16
--   code units/. Lines just shift by one; columns convert through the source
--   line, because display width and UTF-16 width can't be turned into one
--   another without it (display width 2 is one wide char or two narrow ones).
spanToRange :: SrcLines -> ASyn.SrcSpan -> Range
spanToRange ls (ASyn.SrcSpan sl sc el ec) =
  Range
    (Position (line sl) (character sl sc))
    (Position (line el) (character el ec))
  where
    line :: Int -> UInt
    line n = fromIntegral (max 0 (n - 1))
    character :: Int -> Int -> UInt
    character ln col = fromIntegral (Width.displayColToUtf16 (lineAt ln) col)
    lineAt :: Int -> Text
    lineAt n = fromMaybe "" (ls !!? (n - 1))

-- ════════════════════════════════════════════════════════════════════════════
-- Hover type index
--
-- The typechecker elaborates each body into a typed 'TExpr'; hover reads
-- the cursor's type off that tree (plus top-level signatures for head
-- names) rather than from a separately-maintained trace. Records are
-- flattened into a position-keyed map so lookups stay O(log n) and the
-- narrowest-span tie-break is a single fold.
-- ════════════════════════════════════════════════════════════════════════════

-- | What the typechecker assigned at a hoverable source span.
data HoverRecord
  = -- | Reference site ('TVar' / 'TConRef' / 'TBuiltIn').
    --   Declared scheme as written / registered; instantiated type at
    --   this occurrence. On monomorphic references both coincide.
    HoverRef ASyn.Type' ASyn.Type'
  | -- | Binder introduction (parameter, pattern variable, let-bind) or
    --   top-level head name. One monomorphic type.
    HoverBinder ASyn.Type'

-- | Span ↦ record. Keys carry the raw position tuple because
--   'Ord SrcSpan' is position-blind (@compare _ _ = EQ@) and would
--   otherwise collapse every entry onto one slot.
type HoverRecords = Map SpanKey (ASyn.SrcSpan, HoverRecord)

type SpanKey = (Int, Int, Int, Int)

spanKey :: ASyn.SrcSpan -> SpanKey
spanKey (ASyn.SrcSpan sl sc el ec) = (sl, sc, el, ec)

-- | Direct lookup by exact span — used once the AST walk has pinpointed
--   the narrow name span the cursor is on.
lookupRecordAtSpan :: ASyn.SrcSpan -> HoverRecords -> Maybe HoverRecord
lookupRecordAtSpan sp = fmap snd . Map.lookup (spanKey sp)

-- | Find the record whose span contains @(line, col)@, preferring the
--   narrowest if several overlap. Used for local binders, which the AST
--   reference walk does not surface.
lookupRecordAtPosition :: Int -> Int -> HoverRecords -> Maybe (ASyn.SrcSpan, HoverRecord)
lookupRecordAtPosition line col recs =
  case [(sp, r) | (_, (sp, r)) <- Map.toList recs, contains sp] of
    [] -> Nothing
    hits -> Just (minimumBy (\(a, _) (b, _) -> compare (width a) (width b)) hits)
  where
    contains (ASyn.SrcSpan sl sc el ec) =
      (line > sl || (line == sl && col >= sc))
        && (line < el || (line == el && col <= ec))
    width (ASyn.SrcSpan sl sc el ec) = ((el - sl) * 1000000) + (ec - sc)

-- | The position-keyed type index for one hover request: top-level head
--   names from the user AST, plus every reference / binder node in the
--   elaborated bodies of user definitions. A 'Nothing' typed program
--   (ill-typed / not yet elaborated) yields a head-names-only index, so
--   hover still serves signatures and doc.
hoverRecords :: ASyn.Program -> Maybe TypedProgram -> HoverRecords
hoverRecords prog mtp =
  -- 'fromListWith' with a keep-existing combiner retains the FIRST
  -- record on a span collision. 'headRecords' come first, so a top-level
  -- head name (signature / type-decl) wins over a body node sharing the
  -- exact same span. The declared signature is what to show at a
  -- declaration name. No collision arises today (head spans are
  -- signature-name spans, body spans live in the RHS); this pins which
  -- side wins if one ever did, making it a named choice rather than an
  -- accident of '<>' order.
  Map.fromListWith
    (\_new old -> old)
    [ (spanKey sp, (sp, r))
    | (sp, r) <- headRecords (toList (ASyn.decls prog)) <> maybe [] bodyRecords mtp
    ]

-- | Head-name records from the /user/ AST: a 'Sig' contributes its
--   declared type, a 'TypeDecl' its return type. A 'FunDef' head carries
--   no type (its type lives on the sibling 'Sig'). The user 'Program'
--   has no prelude decls, so no filtering is needed.
headRecords :: [ASyn.Decl] -> [(ASyn.SrcSpan, HoverRecord)]
headRecords ds =
  [ (sp, HoverBinder ty)
  | d <- ds,
    Just sp <- [declHeadNameSpan d],
    Just ty <- [headDeclType d]
  ]
  where
    headDeclType = \case
      ASyn.Sig _ _ ty _ _ -> Just ty
      ASyn.TypeDecl _ n params _ _ _ _ -> Just (conReturnType n (map ASyn.paramName params))
      _ -> Nothing
    -- Mirrors 'Awsum.Typing.conReturnType': @Maybe a@ at the @Maybe@
    -- position. Spans are irrelevant — only the rendered type shows.
    conReturnType tName [] = ASyn.TyCon ASyn.noSpan tName
    conReturnType tName tvs =
      foldl' (ASyn.TyApp ASyn.noSpan) (ASyn.TyCon ASyn.noSpan tName) (map (ASyn.TyVar ASyn.noSpan) tvs)

-- | Reference + binder records from the elaborated bodies of /user/
--   definitions. Prelude defs are dropped — their spans come from the
--   bundled prelude and would collide with user spans by position.
bodyRecords :: TypedProgram -> [(ASyn.SrcSpan, HoverRecord)]
bodyRecords tp =
  concatMap declRecords [d | d <- tpDefs tp, tdeclName d `Set.notMember` preludeDefNames]
  where
    -- Every binder records its type — including @_@-prefixed names and
    -- the bare @_@ wildcard. Referencing such a name is a compile error,
    -- but hover is read-only inspection: seeing the type an author chose
    -- to ignore (a @_unused@ parameter, the field a @Just _@ discards) is
    -- exactly what helps when reading unfamiliar code.
    declRecords = \case
      TFunDef _ ps body -> map paramRec ps <> exprRecords body
      TValDef _ body -> exprRecords body
    paramRec (TParam sp t _) = (sp, HoverBinder t)

    exprRecords :: TExpr -> [(ASyn.SrcSpan, HoverRecord)]
    exprRecords = \case
      TVar sp decl inst _ -> [(sp, HoverRef decl inst)]
      TLit {} -> []
      TBuiltIn sp t _ -> [(sp, HoverRef t t)]
      TConRef sp decl inst _ -> [(sp, HoverRef decl inst)]
      TApp _ _ f args -> exprRecords f <> concatMap exprRecords args
      TLam _ _ ps body -> map paramRec ps <> exprRecords body
      TLet _ _ pat rhs body -> patRecords pat <> exprRecords rhs <> exprRecords body
      TCase _ _ scrut alts -> exprRecords scrut <> concatMap altRecords alts
      TRowCase _ _ scrut alts -> exprRecords scrut <> concatMap rowAltRecords alts
      TCoerce _ _ _ inner -> exprRecords inner

    altRecords (TAlt pat body) = patRecords pat <> exprRecords body
    rowAltRecords (TRowAlt _ pat body) = patRecords pat <> exprRecords body

    patRecords :: TPattern -> [(ASyn.SrcSpan, HoverRecord)]
    patRecords = \case
      TPVar sp t _ -> [(sp, HoverBinder t)]
      TPWild sp t -> [(sp, HoverBinder t)]
      TPCon _ _ _ ps -> concatMap patRecords ps
      TPAscribe _ _ p -> patRecords p

-- | Build a hover response for the cursor position.
--
--   Two payloads, both displayed in a single markdown popup:
--
--     1. /Type/ — read off the elaborated 'TExpr' tree (and top-level
--        signatures), indexed by the narrowest 'SrcSpan' that contains
--        the cursor. Reference sites ('TVar', 'TConRef',
--        'TBuiltIn') and binder introductions (parameters, let-bind,
--        case-arm pattern variables, top-level head names) carry types
--        here. Rendered as a fenced @```awsum``` code block at the top
--        of the popup. Polymorphic references surface both the
--        /declared/ scheme and the call-site-instantiated form,
--        separated by an \"Instantiated here:\" line; monomorphic refs
--        and locals collapse to one block. 'TyCon' references inside
--        type signatures and constructor references inside patterns do
--        /not/ carry types yet — they show doc only;
--
--     2. /Doc comment/ — the markdown-ish text attached to the
--        declaration this name resolves to, recovered by the AST walks
--        below ('headNameHover', 'referenceHover'). Searched across
--        user decls + the bundled prelude so a hover on @parseUInt32@
--        in user code surfaces the prelude's doc just as naturally as
--        a hover on a user-defined name.
--
--   Trigger forms:
--
--   /Form 1 — cursor on a user decl's head name./ E.g. @square@ in
--   @square : Int32 -> …@. Returns the signature's type plus the doc
--   attached to that decl (or — fallback — a sibling decl with the same
--   head name; handles the canonical @Sig + FunDef@ pair where only the
--   @Sig@ has a doc).
--
--   /Form 2 — cursor on a reference inside a user function body./
--   E.g. @mulInt32@ in @square n = mulInt32 n n@. Walks the expression
--   tree to find the innermost reference under the cursor and looks up
--   its name in the combined user+prelude decl list. The hover @range@
--   underlines just the reference, not the whole declaration.
--
--   References inside type signatures (@ParseError@ in
--   @parseUInt32 : String -> Either ParseError UInt32@), constructor
--   patterns (@Just@ in @case x of Just y -> …@), pattern-position
--   ascriptions (@Int32@ in @(n : Int32) ->@), and constructor field
--   types (the @Int32@ inside @type Box = Box Int32@) resolve through
--   the same name-lookup for doc. Type variables (lowercase, like
--   @a@ in @a -> a@) are bindings, not references — they intentionally
--   don't trigger.
--
--   /Form 3 — cursor on a local binder./ Function parameter, let-bind
--   variable, case-arm pattern variable — including intentionally-unused
--   @_name@ binders and the bare @_@ wildcard (referencing them is a
--   compile error, but hover is read-only and the discarded type is what
--   a reader wants). No doc here (binders don't have one), but the
--   'TExpr' carries the binder's monomorphic type, so the popup still
--   has content to show.
--
--   The type index is 'Nothing' when the program does not typecheck
--   (or hasn't been elaborated): hover then degrades to doc-only, which
--   the AST walks still serve.
hoverForPosition :: SrcLines -> Maybe TypedProgram -> ASyn.Program -> Position -> Maybe Hover
hoverForPosition ls mtp prog (Position l c) =
  let line = fromIntegral l + 1
      lineText = fromMaybe "" (ls !!? (line - 1))
      col = Width.utf16ColToDisplay lineText (fromIntegral c)
      userDecls = toList (ASyn.decls prog)
      -- User decls are listed first so that, when both the user
      -- program and the prelude define a name (e.g. the user
      -- redefines @const@), the user's doc is found first and wins.
      allDecls = userDecls <> toList (ASyn.decls preludeProgram)
      recs = hoverRecords prog mtp
   in headNameHover recs line col userDecls allDecls
        <|> referenceHover recs line col userDecls allDecls
        <|> binderHover recs line col
  where
    -- Cursor sits on a top-level decl's head name. Surfaces the
    -- decl's type (from the index) and its doc (with sibling fallback).
    headNameHover :: HoverRecords -> Int -> Int -> [ASyn.Decl] -> [ASyn.Decl] -> Maybe Hover
    headNameHover recs line col uds allDs =
      listToMaybe
        $ mapMaybe
          ( \d -> do
              headSp <- declHeadNameSpan d
              guard (positionInSpan line col headSp)
              buildHover recs headSp (docForDecl d allDs)
          )
          uds

    -- Cursor sits inside a user function body, on a reference. We can
    -- emit hover when either the index has a type at the reference
    -- span, or the AST search finds a documented declaration with
    -- that name (or both — preferred).
    referenceHover :: HoverRecords -> Int -> Int -> [ASyn.Decl] -> [ASyn.Decl] -> Maybe Hover
    referenceHover recs line col uds allDs =
      listToMaybe
        $ mapMaybe
          ( \d -> do
              (name, refSp) <- refUnderCursor line col d
              buildHover recs refSp (docByName name allDs)
          )
          uds

    -- Cursor on a local binder (parameter, let-bind, pattern
    -- variable). Locals don't have docs, but the index carries their
    -- type — that alone is enough payload to show a hover.
    binderHover :: HoverRecords -> Int -> Int -> Maybe Hover
    binderHover recs line col = case lookupRecordAtPosition line col recs of
      Just (sp, _) -> buildHover recs sp Nothing
      Nothing -> Nothing

    -- Compose the markdown payload from (optional) type and
    -- (optional) doc. Returns 'Nothing' iff both are absent — no
    -- empty hover popups.
    buildHover :: HoverRecords -> ASyn.SrcSpan -> Maybe Text -> Maybe Hover
    buildHover recs sp mDoc =
      let mTypeMd = renderRecordAt recs sp
          parts = catMaybes [mTypeMd, mDoc]
       in case parts of
            [] -> Nothing
            _ ->
              Just
                Hover
                  { _contents = InL (MarkupContent MarkupKind_Markdown (T.intercalate "\n\n" parts)),
                    _range = Just (spanToRange ls sp)
                  }

    -- Index lookup keyed by the AST span. The 'TExpr' reference nodes
    -- carry the same /narrow/ name span the AST walks return here, so
    -- equality matching suffices for 'TVar' / 'TConRef' /
    -- 'TBuiltIn' / head names. Local binders fall through to position
    -- search ('lookupRecordAtPosition' in 'binderHover').
    renderRecordAt :: HoverRecords -> ASyn.SrcSpan -> Maybe Text
    renderRecordAt recs sp = renderRecord <$> lookupRecordAtSpan sp recs

    -- 'HoverRef' carries both declared and instantiated slots —
    -- on monomorphic refs they coincide and we render one block; on
    -- polymorphic refs the call-site-substituted instantiated form
    -- differs from the declared scheme, and both blocks are
    -- rendered side by side with an "Instantiated here:" separator.
    --
    -- Comparison normalises freshener-suffixed tyvars
    -- ('stripSyntheticTyvarSuffix') so a `Just a -> Maybe a` that
    -- went through `freshenType "$N_M"` to `Just a$3_5 -> Maybe a$3_5`
    -- with no further substitution still compares equal to its
    -- declared form and renders one block, not two.
    renderRecord :: HoverRecord -> Text
    renderRecord = \case
      HoverRef declared instantiated
        | typesEquivalent declared instantiated -> codeBlock declared
        | otherwise ->
            codeBlock declared
              <> "\n\nInstantiated here:\n"
              <> codeBlock instantiated
      HoverBinder ty -> codeBlock ty

    codeBlock :: ASyn.Type' -> Text
    codeBlock ty = "```awsum\n" <> renderType (stripFreshenedSuffixes ty) <> "\n```"

    -- True iff two types are equal modulo synthetic freshener
    -- suffixes ('$3_5', '$check', etc.). Used to decide whether the
    -- instantiated slot adds information beyond the declared scheme.
    typesEquivalent :: ASyn.Type' -> ASyn.Type' -> Bool
    typesEquivalent a b = stripFreshenedSuffixes a == stripFreshenedSuffixes b

    -- Walk a type, stripping freshener suffixes from every 'TyVar'
    -- name. 'stripSyntheticTyvarSuffix' is the per-name helper from
    -- 'Awsum.HM'; we apply it everywhere a tyvar appears.
    stripFreshenedSuffixes :: ASyn.Type' -> ASyn.Type'
    stripFreshenedSuffixes = \case
      ASyn.TyVar sp n -> ASyn.TyVar sp (stripSyntheticTyvarSuffix n)
      ASyn.TyCon sp n -> ASyn.TyCon sp n
      ASyn.TyEmpty sp n -> ASyn.TyEmpty sp n
      ASyn.TyApp sp f x -> ASyn.TyApp sp (stripFreshenedSuffixes f) (stripFreshenedSuffixes x)
      ASyn.TyArrow sp a b -> ASyn.TyArrow sp (stripFreshenedSuffixes a) (stripFreshenedSuffixes b)
      ASyn.TyOr sp a b -> ASyn.TyOr sp (stripFreshenedSuffixes a) (stripFreshenedSuffixes b)

    positionInSpan :: Int -> Int -> ASyn.SrcSpan -> Bool
    positionInSpan line col (ASyn.SrcSpan sl sc el ec) =
      (line > sl || (line == sl && col >= sc))
        && (line < el || (line == el && col <= ec))

    -- Doc resolution from a /decl/ object (head-name path): own doc,
    -- or a sibling decl with the same name and a doc.
    docForDecl :: ASyn.Decl -> [ASyn.Decl] -> Maybe Text
    docForDecl d allDs =
      ASyn.declDocComment d <|> do
        n <- ASyn.declHeadName d
        docByName n allDs

    -- Doc resolution from a /name/ (reference path): first decl in
    -- the search list whose head name matches and that has a doc; if
    -- none, fall back to a 'TypeDecl' whose /constructor list/ contains
    -- the name (so hovering on @Just@ surfaces @Maybe@'s doc — the
    -- only place that constructor is documented today).
    docByName :: Text -> [ASyn.Decl] -> Maybe Text
    docByName name decls =
      listToMaybe
        [ doc
        | d <- decls,
          ASyn.declHeadName d == Just name,
          Just doc <- [ASyn.declDocComment d]
        ]
        <|> listToMaybe
          [ doc
          | ASyn.TypeDecl _ _ _ cons _ _ (Just doc) <- decls,
            ASyn.ConDef _ cname _ <- cons,
            cname == name
          ]

    -- Find the innermost name reference under the cursor inside this
    -- decl, if any. Sig walks the type, FunDef walks parameter
    -- patterns + body (which itself recurses into ELet/EAscribe/EDo
    -- patterns and types as it goes), TypeDecl walks each
    -- constructor's field types.
    refUnderCursor :: Int -> Int -> ASyn.Decl -> Maybe (Text, ASyn.SrcSpan)
    refUnderCursor line col = \case
      ASyn.Sig _ _ ty _ _ -> refInType line col ty
      ASyn.FunDef _ _ ps body _ _ ->
        firstJust (refInParam line col) ps
          <|> refInExpr line col body
      ASyn.TypeDecl _ _ _ cons _ _ _ ->
        firstJust (refInConDef line col) cons
      ASyn.CommentDecl _ _ -> Nothing

    refInParam :: Int -> Int -> ASyn.Param -> Maybe (Text, ASyn.SrcSpan)
    refInParam line col = \case
      ASyn.Param _ _ -> Nothing -- plain binder, not a reference
      ASyn.ParamPat _ pat -> refInPattern line col pat

    refInConDef :: Int -> Int -> ASyn.ConDef -> Maybe (Text, ASyn.SrcSpan)
    refInConDef line col (ASyn.ConDef _ _ flds) =
      firstJust (refInType line col) flds

    -- Walk an expression looking for the innermost name reference
    -- (EVar, ECon, EBuiltIn, plus references buried in pattern or
    -- type sub-nodes — case-alt patterns, let-ascriptions, do-binds,
    -- expression-level ascriptions). Pruning: subtrees whose own span
    -- doesn't contain the cursor are skipped, so the walk is O(depth)
    -- on a well-formed AST.
    refInExpr :: Int -> Int -> ASyn.Expr -> Maybe (Text, ASyn.SrcSpan)
    refInExpr line col e
      | not (positionInSpan line col (ASyn.exprSpan e)) = Nothing
      | otherwise = case e of
          ASyn.EVar sp (ASyn.QName _qual n) -> Just (n, sp)
          ASyn.ECon sp n -> Just (n, sp)
          ASyn.EBuiltIn sp n -> Just (n, sp)
          ASyn.ELit {} -> Nothing
          ASyn.EApp _ f x ->
            refInExpr line col f <|> refInExpr line col x
          ASyn.EInfix _ _ a b ->
            refInExpr line col a <|> refInExpr line col b
          ASyn.EParens _ inner -> refInExpr line col inner
          ASyn.ECase _ scrut alts _ ->
            refInExpr line col scrut
              <|> firstJust (refInCaseAlt line col) (toList alts)
          ASyn.ELam _ ps body ->
            firstJust (refInParam line col) ps
              <|> refInExpr line col body
          ASyn.EDo _ stmts -> firstJust (refInDoStmt line col) stmts
          ASyn.ELet _ pat mty rhs body ->
            refInPattern line col pat
              <|> (mty >>= refInType line col . fst)
              <|> refInExpr line col rhs
              <|> refInExpr line col body
          ASyn.EAscribe _ inner ty ->
            refInExpr line col inner <|> refInType line col ty

    refInCaseAlt :: Int -> Int -> ASyn.CaseAlt -> Maybe (Text, ASyn.SrcSpan)
    refInCaseAlt line col alt =
      refInPattern line col (ASyn.caseAltPattern alt)
        <|> refInExpr line col (ASyn.caseAltBody alt)

    refInDoStmt :: Int -> Int -> ASyn.DoStmt -> Maybe (Text, ASyn.SrcSpan)
    refInDoStmt line col = \case
      ASyn.DoBind _ pat e ->
        refInPattern line col pat <|> refInExpr line col e
      ASyn.DoLet _ pat mty e ->
        refInPattern line col pat
          <|> (mty >>= refInType line col . fst)
          <|> refInExpr line col e
      ASyn.DoExpr _ e -> refInExpr line col e

    -- Walk a pattern looking for constructor references (PCon names)
    -- and type references inside pattern-position ascriptions
    -- (@(n : Int32) -> …@). PVar / PWild bind locally — they're not
    -- references to anything resolvable.
    --
    -- PCon's own SrcSpan covers /just the constructor name/ in source
    -- (its inner patterns live in their own spans), so positional
    -- pruning on the outer pattern would skip a cursor that sits on
    -- a nested @PCon@. Recurse into inner sub-patterns first; only
    -- match the outer name when nothing inner does.
    refInPattern :: Int -> Int -> ASyn.Pattern -> Maybe (Text, ASyn.SrcSpan)
    refInPattern line col = \case
      ASyn.PCon sp n inner ->
        firstJust (refInPattern line col) inner
          <|> (if positionInSpan line col sp then Just (n, sp) else Nothing)
      ASyn.PVar _ _ -> Nothing
      ASyn.PWild _ -> Nothing
      ASyn.PAscribe _ inner ty ->
        refInPattern line col inner <|> refInType line col ty

    -- Walk a type looking for the innermost TyCon / TyEmpty under the
    -- cursor. TyVar is a bound lowercase name (e.g. @a@ in @a -> a@) —
    -- not resolvable to a declaration, so it's intentionally skipped.
    refInType :: Int -> Int -> ASyn.Type' -> Maybe (Text, ASyn.SrcSpan)
    refInType line col ty
      | not (positionInSpan line col (ASyn.typeSpan ty)) = Nothing
      | otherwise = case ty of
          ASyn.TyVar _ _ -> Nothing
          ASyn.TyCon sp n -> Just (n, sp)
          ASyn.TyEmpty sp n -> Just (n, sp)
          ASyn.TyApp _ f x -> refInType line col f <|> refInType line col x
          ASyn.TyArrow _ a b -> refInType line col a <|> refInType line col b
          ASyn.TyOr _ a b -> refInType line col a <|> refInType line col b

    firstJust :: (a -> Maybe b) -> [a] -> Maybe b
    firstJust f = listToMaybe . mapMaybe f

-- | Span of the head /name/ of a top-level declaration — the substring
--   the user clicks on to trigger hover. Approximations:
--
--     * 'Sig' / 'FunDef' — the name sits at the start of the decl span;
--       end column is start + 'T.length' of the name. For operator
--       decls spelled in source as @(++)@ the internal name is @"++"@
--       (length 2) so the returned span underestimates by the two
--       parens; a cursor inside @(++)@ at col 2..3 still triggers
--       (col 1 — the @(@ — and col 4 — the @)@ — do not).
--
--     * 'TypeDecl' (NotEmpty) — the @"type "@ prefix is 5 chars, so
--       the name starts at @startCol + 5@. Formatter normalises
--       whitespace, so this is reliable for any formatted source.
--
--     * 'TypeDecl' (Empty) — @"empty type "@ prefix is 11 chars.
--
--     * 'CommentDecl' — no head name; returns 'Nothing'.
declHeadNameSpan :: ASyn.Decl -> Maybe ASyn.SrcSpan
declHeadNameSpan = \case
  ASyn.Sig sp n _ _ _ -> Just (nameSpanAt sp n)
  ASyn.FunDef sp n _ _ _ _ -> Just (nameSpanAt sp n)
  ASyn.TypeDecl sp n _ _ _ ek _ ->
    let off = case ek of
          ASyn.NotEmpty -> T.length "type "
          ASyn.Empty -> T.length "empty type "
     in Just (nameSpanShifted sp off n)
  ASyn.CommentDecl _ _ -> Nothing
  where
    nameSpanAt :: ASyn.SrcSpan -> ASyn.Name -> ASyn.SrcSpan
    nameSpanAt (ASyn.SrcSpan sl sc _ _) n =
      ASyn.SrcSpan sl sc sl (sc + T.length n)
    nameSpanShifted :: ASyn.SrcSpan -> Int -> ASyn.Name -> ASyn.SrcSpan
    nameSpanShifted (ASyn.SrcSpan sl sc _ _) off n =
      ASyn.SrcSpan sl (sc + off) sl (sc + off + T.length n)

severityToLsp :: AD.Severity -> DiagnosticSeverity
severityToLsp = \case
  AD.SevError -> DiagnosticSeverity_Error
  AD.SevWarning -> DiagnosticSeverity_Warning

awsumDiagToLsp :: SrcLines -> AD.Diagnostic -> Diagnostic
awsumDiagToLsp ls (AD.Diagnostic sev sp msg _fixes) =
  Diagnostic
    { _range = spanToRange ls sp,
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
awsumSymbolToLsp :: SrcLines -> ASym.Symbol -> DocumentSymbol
awsumSymbolToLsp ls (ASym.Symbol k n r sr cs) =
  DocumentSymbol
    { _name = n,
      _detail = Nothing,
      _kind = awsumSymbolKindToLsp k,
      _tags = Nothing,
      _deprecated = Nothing,
      _range = spanToRange ls r,
      _selectionRange = spanToRange ls sr,
      _children = Just (map (awsumSymbolToLsp ls) cs)
    }

-- | Source text → document symbols (outline). Empty on parse error —
--   the same fallback the @textDocument/documentSymbol@ handler uses.
documentSymbolsForSource :: Text -> [DocumentSymbol]
documentSymbolsForSource src = case parseProgramDiagnostic src of
  Left _ -> []
  Right prog -> map (awsumSymbolToLsp (docLines src)) (ASym.symbolsOfProgram prog)

-- ════════════════════════════════════════════════════════════════════════════
-- Compile pipeline
-- ════════════════════════════════════════════════════════════════════════════

-- | Source text → elaborated 'TypedProgram'. Returns 'Nothing' on any
--   failure (parse error, prelude-reference violation, type error) so
--   hover gracefully degrades to doc-only — the AST-based doc walks
--   already work on the unmodified user program.
--
--   The pipeline here mirrors 'compileToDiagnostics' minus the Core
--   lowering steps: parsing and typechecking is all hover needs, and
--   skipping lowering keeps it responsive to partially-typed programs
--   (e.g. user is still typing).
compileToTypedProgram :: Text -> Maybe TypedProgram
compileToTypedProgram src =
  case parseProgramDiagnostic src of
    Left _ -> Nothing
    Right userProg -> case restrictPreludeRefs userProg of
      _ : _ -> Nothing
      [] ->
        -- Desugar before typechecking — mirrors 'elaborateLowerProgram'
        -- so the hover path and the lowering path see the same
        -- normalised AST (no 'EDo' / 'ParamPat' / non-'PVar' lets reach
        -- the typechecker). On desugar failure, degrade to doc-only hover.
        case desugarProgram (withPrelude userProg) of
          Left _ -> Nothing
          Right desugared ->
            let emptyNames = emptyTypeNamesInProgram desugared
                prog =
                  desugared
                    { ASyn.decls = fmap (markEmptyTypesInDecl emptyNames) (ASyn.decls desugared)
                    }
             in case typecheckProgram ProgramCli preludeDefNames prog of
                  Left _ -> Nothing
                  Right (typed, _) -> Just typed

-- | Source text → Awsum diagnostics. Mirrors the @awsum check@ pipeline in
--   "Main.runCheck" — parse, elaborate (which runs typecheck + every
--   Core-to-Core pass), warn-or-error.
compileToDiagnostics :: Text -> [AD.Diagnostic]
compileToDiagnostics src =
  case parseProgramDiagnostic src of
    Left parseErrs -> map AD.parseErrorToDiagnostic parseErrs
    Right userProg -> case restrictPreludeRefs userProg of
      vs@(_ : _) -> map AD.preludeRefViolationToDiagnostic vs
      [] ->
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
  let ls = docLines src
      diags = compileToDiagnostics src
      lspDiags = map (awsumDiagToLsp ls) diags
      newFixEntries =
        [ ((uri, rangeKey (spanToRange ls (AD.diagSpan d))), AD.diagFixes d)
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
    when (shouldWarnVersionMismatch expectedVer compiler) $ do
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

-- | Should the server warn about a client/compiler version mismatch?
--   Only when both sides are @A.B.C@ release versions and they differ;
--   a dev-mode (non-@A.B.C@) version on either side opts out.
shouldWarnVersionMismatch :: Text -> Text -> Bool
shouldWarnVersionMismatch expectedVer compiler =
  looksLikeSemver expectedVer
    && looksLikeSemver compiler
    && expectedVer
    /= compiler

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
        mtxt <- readDocText uri
        let ls = maybe [] docLines mtxt
            actions :: [Command |? CodeAction]
            actions =
              [ InR (fixToCodeAction ls uri d qf)
              | d <- ctxDiags,
                qf <- fromMaybe [] (Map.lookup (uri, rangeKey (d ^. L.range)) fixesIdx)
              ]
        responder (Right (InL actions)),
      -- Formatting: re-render via Awsum.Format and return the minimal
      -- list of line-range edits ('formatEdits') — never a whole-buffer
      -- replace. An already-canonical document yields no edits, so the
      -- client leaves the buffer (folds, cursor, undo) untouched, the
      -- same way 'awsum format -i' skips an unchanged write.
      requestHandler SMethod_TextDocumentFormatting $ \req responder -> do
        let uri = toNormalizedUri (req ^. L.params . L.textDocument . L.uri)
        mtxt <- readDocText uri
        case mtxt of
          Nothing -> responder (Right (InR Null))
          Just src -> responder (Right (InL (formatEdits src))),
      -- Outline / breadcrumbs / symbol search inside a file.
      requestHandler SMethod_TextDocumentDocumentSymbol $ \req responder -> do
        let uri = toNormalizedUri (req ^. L.params . L.textDocument . L.uri)
        mtxt <- readDocText uri
        let syms :: [DocumentSymbol]
            syms = maybe [] documentSymbolsForSource mtxt
            -- lsp-types orders the union as `SymbolInformation[] | DocumentSymbol[] | null`
            -- (legacy alternative first, then DocumentSymbol[], then null).
            -- We always pick the DocumentSymbol[] branch.
            result :: [SymbolInformation] |? ([DocumentSymbol] |? Null)
            result = InR (InL syms)
        responder (Right result),
      -- Hover: surface (a) the typechecker's type for whatever name /
      -- binder the cursor is on, and (b) the doc comment attached to
      -- the declaration it resolves to. Both pieces are shipped as a
      -- single markdown popup with a fenced @```awsum``` code block
      -- on top; every targeted editor (@awsum-vscode@, @awsum-intellij@,
      -- @awsum-zed@, @awsum-nvim@, @awsum-emacs@) renders both by default.
      --
      -- Function decls produce two AST nodes (Sig + FunDef); the parser's
      -- 'attachDocs' attaches the doc to whichever the comment textually
      -- precedes — almost always the Sig. Hover on either node resolves
      -- by name across the program, so a cursor on the function body's
      -- name still shows the signature's doc.
      requestHandler SMethod_TextDocumentHover $ \req responder -> do
        let uri = toNormalizedUri (req ^. L.params . L.textDocument . L.uri)
            pos = req ^. L.params . L.position
        mtxt <- readDocText uri
        let result :: Hover |? Null
            result = case mtxt of
              Nothing -> InR Null
              Just src -> case parseProgramDiagnostic src of
                Left _ -> InR Null
                Right prog ->
                  -- The typed program is elaborated afresh per hover
                  -- request. This duplicates work with the debounced
                  -- 'publishCheckResult' path but keeps the hover
                  -- handler synchronous; for typical hover frequency
                  -- (a few per second at most) the cost is invisible.
                  case hoverForPosition (docLines src) (compileToTypedProgram src) prog pos of
                    Nothing -> InR Null
                    Just h -> InL h
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
fixToCodeAction :: SrcLines -> NormalizedUri -> Diagnostic -> AD.Fix -> CodeAction
fixToCodeAction ls uri d (AD.Fix title edits) =
  CodeAction
    { _title = title,
      _kind = Just CodeActionKind_QuickFix,
      _diagnostics = Just [d],
      _isPreferred = Just True,
      _disabled = Nothing,
      _edit = Just (mkWorkspaceEdit ls uri edits),
      _command = Nothing,
      _data_ = Nothing
    }

mkWorkspaceEdit :: SrcLines -> NormalizedUri -> [AD.Edit] -> WorkspaceEdit
mkWorkspaceEdit ls uri edits =
  WorkspaceEdit
    { _changes =
        Just
          ( Map.singleton
              (fromNormalizedUri uri)
              [TextEdit (spanToRange ls sp) newText | AD.Edit sp newText <- edits]
          ),
      _documentChanges = Nothing,
      _changeAnnotations = Nothing
    }

-- ════════════════════════════════════════════════════════════════════════════
-- Formatting edits
-- ════════════════════════════════════════════════════════════════════════════

-- | Source text → the 'TextEdit's that turn it into its canonical form.
--   Empty list when the source is already canonical, or fails to parse
--   (diagnostics already report the parse error). Returning targeted
--   line-range edits rather than one whole-document replace lets the
--   client leave untouched regions — and their folds, cursor, and undo
--   history — alone, and gives an already-formatted buffer no edit at all
--   (the LSP analogue of 'awsum format -i' skipping an unchanged write).
formatEdits :: Text -> [TextEdit]
formatEdits src = case formatSource src of
  Left _err -> []
  Right formatted
    | formatted == src -> []
    | otherwise -> diffEdits src formatted

-- | Line-level diff of @src@ → @formatted@ as one 'TextEdit' per changed
--   hunk. Each line is modelled with its own trailing newline
--   ('linesWithNL') so a hunk's replacement is the plain concatenation of
--   the formatted lines it introduces and every range start is a line
--   start (@Position l 0@). The single non-line-start coordinate is the
--   end of a hunk reaching a @src@ with no final newline: there the range
--   ends just past the last character, counted in UTF-16 code units
--   ('utf16Len') — the unit LSP 'Position' columns use, not the code
--   points 'T.length' would give.
--
--   Invariant: applying the result to @src@ reproduces @formatted@.
diffEdits :: Text -> Text -> [TextEdit]
diffEdits src formatted = go 0 (Diff.getGroupedDiff srcLines fmtLines)
  where
    srcLines = linesWithNL src
    fmtLines = linesWithNL formatted
    srcCount = length srcLines
    srcEndsInNewline = "\n" `T.isSuffixOf` src

    -- End anchor for a hunk that consumed source lines up to index @j@
    -- (0-based, exclusive): the start of line @j@ when it exists, the
    -- end of the buffer otherwise.
    endAt :: Int -> Position
    endAt j
      | j < srcCount = Position (fromIntegral j) 0
      | srcEndsInNewline || srcCount == 0 = Position (fromIntegral srcCount) 0
      | otherwise =
          Position
            (fromIntegral (srcCount - 1))
            (utf16Len (fromMaybe "" (viaNonEmpty last srcLines)))

    go :: Int -> [Diff.Diff [Text]] -> [TextEdit]
    go _ [] = []
    go s (Diff.Both common _ : rest) = go (s + length common) rest
    go s groups =
      let (deleted, added, rest) = takeHunk groups
          end = s + length deleted
          edit = TextEdit (Range (Position (fromIntegral s) 0) (endAt end)) (T.concat added)
       in edit : go end rest

    -- Fold the maximal run of non-'Both' groups into one hunk: 'First'
    -- lines are deletions from @src@, 'Second' lines insertions from
    -- @formatted@.
    takeHunk :: [Diff.Diff [Text]] -> ([Text], [Text], [Diff.Diff [Text]])
    takeHunk (Diff.First xs : rest) = let (dels, adds, r) = takeHunk rest in (xs <> dels, adds, r)
    takeHunk (Diff.Second ys : rest) = let (dels, adds, r) = takeHunk rest in (dels, ys <> adds, r)
    takeHunk rest = ([], [], rest)

-- | Split text into lines that each keep their trailing newline, so
--   @T.concat (linesWithNL t) == t@. The last element lacks a newline
--   iff @t@ doesn't end in one; empty text yields no lines.
linesWithNL :: Text -> [Text]
linesWithNL t
  | T.null t = []
  | otherwise = case T.breakOn "\n" t of
      (before, rest) -> case T.stripPrefix "\n" rest of
        Just after -> (before <> "\n") : linesWithNL after
        Nothing -> [before]

-- | Length of a line in UTF-16 code units — the unit LSP 'Position'
--   columns are measured in. A code point above the BMP (e.g. an emoji)
--   is two code units; everything else is one.
utf16Len :: Text -> UInt
utf16Len = fromIntegral . T.foldl' (\n ch -> n + if ord ch > 0xFFFF then 2 else (1 :: Int)) 0

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
        let ls = docLines src
            syms = flattenSymbols (ASym.symbolsOfProgram prog)
            fileUri = filePathToUri file
         in [ SymbolInformation
                { _name = n,
                  _kind = awsumSymbolKindToLsp k,
                  _tags = Nothing,
                  _deprecated = Nothing,
                  _location = Location {_uri = fileUri, _range = spanToRange ls r},
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
  runServer (serverDefinition st compilerVersion)

-- | Run the server reading from @hin@ and writing to @hout@ instead of
--   stdio, with logging silenced. Lets 'Awsum.LspSpec' drive a real
--   server in-process over a pair of pipes ('lsp-test'), exercising the
--   actual handler registration and JSON-RPC envelopes rather than only
--   the extracted request logic.
runLspServerWithHandles :: Handle -> Handle -> Text -> IO Int
runLspServerWithHandles hin hout compilerVersion = do
  st <- newServerState compilerVersion
  runServerWithHandles mempty mempty hin hout (serverDefinition st compilerVersion)

-- | The 'ServerDefinition' shared by the stdio and handle-driven entry
--   points.
serverDefinition :: ServerState -> Text -> ServerDefinition ()
serverDefinition st compilerVersion =
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
