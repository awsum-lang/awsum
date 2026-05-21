{-# LANGUAGE DeriveGeneric #-}

-- | Tests for the `awsum.tmLanguage.json` TextMate grammar shipped in
-- the `awsum-vscode` extension. Shell-out from Haskell to a small
-- Node script that tokenizes a file through `vscode-textmate` (the
-- same engine VSCode runs in production) and prints a JSON array of
-- per-line tokens. Two layers:
--
--   * `corpus` — every `.aww` under `test/sources/successful/`,
--     `test/sources/property/` and `test/sources/formatting/` is
--     tokenized and asserted to satisfy four invariants on the
--     resulting scope stacks. The same three roots used by the
--     tree-sitter spec; `formatting/` is included because the
--     malformed-but-recoverable inputs there are exactly where a
--     greedy regex rule is most likely to misbehave.
--
--   * `property` — for each QuickCheck-generated `Program`, render it
--     via `Awsum.Render.renderProgram` (the same path the formatter
--     uses) and apply the four corpus invariants plus one AST-aware
--     invariant: every `LString` in the AST is covered by a
--     `string.*`-scoped region in the tokenization.
--
-- The invariants (I1–I5) are documented at their assertion sites
-- below. They were chosen because they catch the regressions that
-- have historically slipped through code review on this grammar:
-- a keyword's regex stops matching after a punctuation change, the
-- string rule's `end` regex breaks and lets `string.*` leak into the
-- rest of the line, a comment regex starts consuming inside strings,
-- the numeric rule rejects an underscore-grouped literal, or a new
-- AST shape produces strings the grammar doesn't recognise.
--
-- Lives in the standalone `textmate-tests` test-suite (see
-- `package.yaml`) so CI's main suite never sees it. Discovery is
-- best-effort: if `node` isn't on PATH, or `../awsum-vscode/` isn't
-- in its conventional location (override with `AWSUM_VSCODE_DIR`),
-- or `node_modules/vscode-textmate` isn't installed inside it, the
-- spec emits a single `pendingWith`. Run via
-- `just test-textmate` (corpus only) or
-- `just test-textmate-property` (property only).
module Awsum.TextMateSpec (spec) where

import Awsum.ArbitraryInstances ()
import Awsum.Render (renderProgram)
import Awsum.Syntax
import Common.File (readFileTextUtf8)
import Data.Aeson (FromJSON, eitherDecodeStrict)
import Data.Char (isDigit)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Relude
import System.Directory (doesDirectoryExist, doesFileExist, findExecutable, getCurrentDirectory, listDirectory, makeAbsolute)
import System.FilePath ((</>))
import System.IO (hClose)
import System.IO.Temp (withSystemTempFile)
import System.Process (CreateProcess (cwd), proc, readCreateProcessWithExitCode)
import Test.Hspec
import Test.Hspec.QuickCheck (modifyMaxSuccess, prop)
import Test.QuickCheck (Property, counterexample, ioProperty)

spec :: Spec
spec = describe "Property tests" $ describe "awsum-vscode-textmate" $ do
  resources <- runIO discover
  case resources of
    Nothing ->
      it "awsum-vscode TextMate infrastructure available"
        $ pendingWith
          "Need an awsum-vscode checkout next to the compiler repo (or AWSUM_VSCODE_DIR set), with `npm install` already run inside it so node_modules/vscode-textmate exists, and `node` on PATH."
    Just res -> do
      corpusSpec res
      propertySpec res

-- ════════════════════════════════════════════════════════════════════
-- Token shape
-- ════════════════════════════════════════════════════════════════════

-- | A single TextMate token. @start@ and @end@ are UTF-16 code-unit
-- indices into the source line (vscode-textmate's native unit) — we
-- carry them for debugging but match against @text@, which the
-- script slices on the JS side because Haskell's `Data.Text`
-- indexes by code point and would mis-slice supplementary-plane
-- characters.
data Token = Token {start :: Int, end :: Int, text :: Text, scopes :: [Text]}
  deriving stock (Generic, Show)

instance FromJSON Token

data LineTokens = LineTokens {line :: Int, tokens :: [Token]}
  deriving stock (Generic, Show)

instance FromJSON LineTokens

-- ════════════════════════════════════════════════════════════════════
-- Corpus layer
-- ════════════════════════════════════════════════════════════════════

corpusSpec :: Resources -> Spec
corpusSpec res = describe "corpus" $ do
  files <- runIO discoverCorpus
  forM_ files $ \(label, path) ->
    it label $ do
      src <- readFileTextUtf8 path
      lns <- tokenizeFile res path
      assertSourceInvariants src lns

-- | Walk successful/, property/ AND formatting/ source roots. Same
-- shape as `TreeSitterSpec.discoverCorpus`; kept duplicated rather
-- than extracted because the two specs live in different test-suites
-- (cabal flags) and a shared module would force textmate-tests to
-- depend on tree-sitter-tests just for the helper.
discoverCorpus :: IO [(String, FilePath)]
discoverCorpus = do
  let roots :: [FilePath]
      roots =
        [ "test/sources/successful",
          "test/sources/property",
          "test/sources/formatting"
        ]
  concat <$> traverse collectFromRoot roots

collectFromRoot :: FilePath -> IO [(String, FilePath)]
collectFromRoot root = do
  exists <- doesDirectoryExist root
  if not exists
    then pure []
    else do
      entries <- sort <$> listDirectory root
      subDirs <- filterM (\e -> doesDirectoryExist (root </> e)) entries
      let candidates =
            [ (root </> e, (root </> e) </> "code" </> "Main.aww")
            | e <- subDirs
            ]
      filterM (\(_, p) -> doesFileExist p) candidates

-- ════════════════════════════════════════════════════════════════════
-- Property layer
-- ════════════════════════════════════════════════════════════════════

propertySpec :: Resources -> Spec
propertySpec res = describe "property"
  $ modifyMaxSuccess (const 100)
  $ prop "textmate tokenization satisfies every invariant on every renderProgram output"
  $ \prog -> ioProperty (runOne res prog)

runOne :: Resources -> Program -> IO Property
runOne res prog = do
  let src = renderProgram prog
  withSystemTempFile "tm-prop.aww" $ \path h -> do
    TIO.hPutStr h src
    hClose h
    lns <- tokenizeFile res path
    case checkAllInvariants src prog lns of
      Right () -> pure (counterexample "" True)
      Left msg -> pure (counterexample (formatFailure src lns msg) False)

-- ════════════════════════════════════════════════════════════════════
-- Discovery + spawn helpers
-- ════════════════════════════════════════════════════════════════════

data Resources = Resources {nodeBin :: FilePath, vscodeDir :: FilePath}

discover :: IO (Maybe Resources)
discover = do
  mNode <- findExecutable "node"
  mDir <- findVscodeDir
  case (mNode, mDir) of
    (Just nodeBin, Just vscodeDir) -> do
      hasTmEngine <- doesDirectoryExist (vscodeDir </> "node_modules" </> "vscode-textmate")
      hasOniguruma <- doesDirectoryExist (vscodeDir </> "node_modules" </> "vscode-oniguruma")
      hasScript <- doesFileExist (vscodeDir </> "scripts" </> "tokenize.mjs")
      pure
        $ if hasTmEngine && hasOniguruma && hasScript
          then Just Resources {nodeBin, vscodeDir}
          else Nothing
    _ -> pure Nothing

findVscodeDir :: IO (Maybe FilePath)
findVscodeDir = do
  override <- lookupEnv "AWSUM_VSCODE_DIR"
  case override of
    Just p -> existsAsExt p
    Nothing -> do
      cwdPath <- getCurrentDirectory
      existsAsExt (cwdPath </> ".." </> "awsum-vscode")
  where
    existsAsExt p = do
      e <- doesDirectoryExist p
      hasGrammar <- doesFileExist (p </> "syntaxes" </> "awsum.tmLanguage.json")
      pure $ if e && hasGrammar then Just p else Nothing

-- | Run the Node tokenizer against the given path, parse its JSON,
-- and return per-line token arrays. The script's `cwd` is the
-- `awsum-vscode/` directory so its relative resolves to the grammar
-- file work regardless of where the test was invoked from; the
-- input file path is canonicalised to absolute before passing so
-- the script doesn't try to resolve it against that `cwd`.
tokenizeFile :: Resources -> FilePath -> IO [LineTokens]
tokenizeFile res path = do
  absPath <- makeAbsolute path
  let cp = (proc (nodeBin res) ["scripts/tokenize.mjs", absPath]) {cwd = Just (vscodeDir res)}
  (_exit, sout, serr) <- readCreateProcessWithExitCode cp ""
  case eitherDecodeStrict (encodeUtf8 (toText sout)) of
    Right lns -> pure lns
    Left err ->
      fail
        $ "TextMate tokenizer JSON parse failed: "
        <> err
        <> "\nstdout (truncated to 2000 chars):\n"
        <> take 2000 sout
        <> "\nstderr:\n"
        <> serr

-- ════════════════════════════════════════════════════════════════════
-- Invariants
-- ════════════════════════════════════════════════════════════════════

-- | The four source-only invariants (I1–I4) checked on both layers.
-- Returns @Right ()@ on success or @Left explanation@ on the first
-- violation found.
assertSourceInvariants :: (HasCallStack) => Text -> [LineTokens] -> Expectation
assertSourceInvariants src lns =
  case checkSourceInvariants src lns of
    Right () -> pass
    Left msg -> expectationFailure (formatFailure src lns msg)

checkSourceInvariants :: Text -> [LineTokens] -> Either String ()
checkSourceInvariants _src lns = do
  checkI1Keywords lns
  checkI2StringBalance lns
  checkI3NoCommentInString lns
  checkI4Numeric lns

-- | All five — source-only plus I5 (AST-aware) — used in the
-- property layer where the AST is available.
checkAllInvariants :: Text -> Program -> [LineTokens] -> Either String ()
checkAllInvariants src prog lns = do
  checkSourceInvariants src lns
  checkI5StringCoverage prog lns

-- ─── I1: keyword identifiers receive `keyword.*` scope ─────────────
--
-- For every token whose textual content is exactly one of the
-- reserved keywords and which sits outside any `string.*`/`comment.*`
-- scope, its scope stack must contain at least one scope starting
-- with `keyword.`. Catches the failure mode where a keyword regex
-- stops matching (e.g. word-boundary change) and the keyword
-- silently downgrades to a plain identifier scope.
checkI1Keywords :: [LineTokens] -> Either String ()
checkI1Keywords lns =
  forEachToken lns $ \tok ->
    if text tok
      `elem` reservedKeywords
      && not (inStringOrComment tok)
      && not (hasKeywordScope tok)
      then
        Left
          $ "I1 (keyword scope): keyword `"
          <> toString (text tok)
          <> "` has scopes "
          <> show (scopes tok)
          <> " — none start with `keyword.`."
      else Right ()

reservedKeywords :: [Text]
reservedKeywords =
  ["do", "case", "of", "let", "in", "type", "empty", "import"]

hasKeywordScope :: Token -> Bool
hasKeywordScope = any ("keyword." `T.isPrefixOf`) . scopes

inStringOrComment :: Token -> Bool
inStringOrComment t =
  any (\s -> "string." `T.isPrefixOf` s || "comment." `T.isPrefixOf` s) (scopes t)

-- ─── I2: `string.*` scope is balanced per line ─────────────────────
--
-- A `string.*` scope must open and close on the same line. Awsum
-- strings cannot contain real newlines (the language requires `\n`
-- as an escape), so a multi-line `string.*` run is always a sign of
-- a missing closing quote in the grammar's end-regex. We detect it
-- by counting the per-line tokens that carry the grammar's
-- `punctuation.definition.string.begin.awsum` and `*.end.awsum`
-- scopes; on every line the two counts must be equal. Direct
-- check, no edge cases — the closing quote token is itself inside
-- the string region (so it carries `string.*` in its stack), which
-- ruled out simpler "last token must not be in string" formulations.
checkI2StringBalance :: [LineTokens] -> Either String ()
checkI2StringBalance lns =
  case mapMaybe lineImbalance lns of
    [] -> Right ()
    (n, begins, ends) : _ ->
      Left
        $ "I2 (string balance): line "
        <> show n
        <> " has "
        <> show begins
        <> " string opening(s) but "
        <> show ends
        <> " closing(s)."
  where
    lineImbalance :: LineTokens -> Maybe (Int, Int, Int)
    lineImbalance (LineTokens i ts) =
      let begins = countScope "punctuation.definition.string.begin.awsum" ts
          ends = countScope "punctuation.definition.string.end.awsum" ts
       in if begins == ends then Nothing else Just (i, begins, ends)

    countScope :: Text -> [Token] -> Int
    countScope name = length . filter (\t -> name `elem` scopes t)

-- ─── I3: no `comment.*` scope inside a `string.*` scope ────────────
--
-- The two scopes must not co-occur on any single token. If they do,
-- a comment rule is matching inside a string region — the exact bug
-- pattern reported in the doc as the `"--"` regression on tree-
-- sitter.
checkI3NoCommentInString :: [LineTokens] -> Either String ()
checkI3NoCommentInString lns =
  case firstViolation of
    Nothing -> Right ()
    Just (i, t) ->
      Left
        $ "I3 (no comment in string): line "
        <> show i
        <> " token ["
        <> show (start t)
        <> "-"
        <> show (end t)
        <> "] has both `string.*` and `comment.*`: "
        <> show (scopes t)
  where
    firstViolation =
      listToMaybe
        [ (i, t)
        | LineTokens i ts <- lns,
          t <- ts,
          any ("string." `T.isPrefixOf`) (scopes t),
          any ("comment." `T.isPrefixOf`) (scopes t)
        ]

-- ─── I4: integer literals receive `constant.numeric.*` scope ───────
--
-- For every token whose textual content matches the grammar's
-- numeric regex (`-?\d+(_\d+)*`) and which sits outside any
-- `string.*`/`comment.*` scope, its scope stack must contain
-- `constant.numeric.*`. Catches a broken numeric rule that fails to
-- match grouped-digit literals like `1_000_000`.
checkI4Numeric :: [LineTokens] -> Either String ()
checkI4Numeric lns =
  forEachToken lns $ \tok ->
    if isIntegerLiteral (text tok)
      && not (inStringOrComment tok)
      && not (hasNumericScope tok)
      then
        Left
          $ "I4 (numeric scope): integer literal `"
          <> toString (text tok)
          <> "` has scopes "
          <> show (scopes tok)
          <> " — none start with `constant.numeric.`."
      else Right ()

hasNumericScope :: Token -> Bool
hasNumericScope = any ("constant.numeric." `T.isPrefixOf`) . scopes

-- | True iff @txt@ is a bare integer literal in the surface syntax —
-- digit runs separated by single underscores, optionally prefixed by
-- @-@. Mirrors the regex in the grammar's `numeric_literal` rule but
-- expressed structurally so we can apply it to one token at a time.
isIntegerLiteral :: Text -> Bool
isIntegerLiteral t = case T.uncons t of
  Just ('-', rest) -> isDigitGroups rest
  _ -> isDigitGroups t
  where
    isDigitGroups s = case T.split (== '_') s of
      [] -> False
      parts -> all (\p -> not (T.null p) && T.all isDigit p) parts

-- ─── I5: every `LString` in AST is covered by a string region ─────
--
-- The number of `LString` literals in the AST must equal the number
-- of maximal contiguous regions of `string.*`-scoped tokens in the
-- tokenization. We count rather than position-match because the
-- string rule splits a `"..."` into begin-punct / content / end-
-- punct tokens — each is its own token but together one region.
checkI5StringCoverage :: Program -> [LineTokens] -> Either String ()
checkI5StringCoverage prog lns =
  if astCount == tokCount
    then Right ()
    else
      Left
        $ "I5 (string coverage): AST has "
        <> show astCount
        <> " LString literal(s) but tokenization has "
        <> show tokCount
        <> " string region(s)."
  where
    astCount = length (collectLStrings prog)
    tokCount = countStringRegions lns

countStringRegions :: [LineTokens] -> Int
countStringRegions = sum . map (lineRegions . tokens)
  where
    lineRegions :: [Token] -> Int
    lineRegions = go False 0
      where
        go _ acc [] = acc
        go inside acc (t : ts)
          | isString && not inside = go True (acc + 1) ts
          | isString = go True acc ts
          | otherwise = go False acc ts
          where
            isString = any ("string." `T.isPrefixOf`) (scopes t)

-- | Walk a `Program` and pull every `LString` literal out. Other
-- literal kinds (`LInt`) are ignored.
collectLStrings :: Program -> [Text]
collectLStrings prog =
  concatMap declStrings (toList (decls prog))
  where
    declStrings :: Decl -> [Text]
    declStrings = \case
      FunDef _ _ _ e _ _ -> exprStrings e
      Sig {} -> []
      TypeDecl {} -> []
      CommentDecl _ _ -> []

    exprStrings :: Expr -> [Text]
    exprStrings = \case
      ELit _ (LString s) -> [s]
      ELit _ _ -> []
      EVar {} -> []
      ECon {} -> []
      EBuiltIn {} -> []
      EApp _ f a -> exprStrings f <> exprStrings a
      EInfix _ _ a b -> exprStrings a <> exprStrings b
      EParens _ e -> exprStrings e
      ECase _ scrut alts _ -> exprStrings scrut <> concatMap altStrings (toList alts)
      EDo _ stmts -> concatMap stmtStrings stmts
      ELet _ _ _ rhs body -> exprStrings rhs <> exprStrings body
      ELam _ _ body -> exprStrings body
      EAscribe _ e _ -> exprStrings e

    altStrings :: CaseAlt -> [Text]
    altStrings = exprStrings . caseAltBody

    stmtStrings :: DoStmt -> [Text]
    stmtStrings = \case
      DoBind _ _ e -> exprStrings e
      DoLet _ _ _ e -> exprStrings e
      DoExpr _ e -> exprStrings e

-- ════════════════════════════════════════════════════════════════════
-- Token-walking helpers shared by I1 and I4
-- ════════════════════════════════════════════════════════════════════

-- | Apply a per-token predicate to every token in every line of the
-- tokenization, stopping at the first @Left@. The token's literal
-- source text is carried inside the token (sliced on the JS side to
-- avoid the UTF-16 / code-point indexing mismatch).
forEachToken :: [LineTokens] -> (Token -> Either String ()) -> Either String ()
forEachToken lns f =
  firstLeft [f t | LineTokens _ ts <- lns, t <- ts]

firstLeft :: [Either String ()] -> Either String ()
firstLeft = go
  where
    go [] = Right ()
    go (Left e : _) = Left e
    go (Right () : rest) = go rest

-- ════════════════════════════════════════════════════════════════════
-- Failure formatting
-- ════════════════════════════════════════════════════════════════════

formatFailure :: Text -> [LineTokens] -> String -> String
formatFailure src lns reason =
  toString
    $ unlines
      [ "TextMate invariant failed: " <> toText reason,
        "",
        "─── Source ───",
        src,
        "─── Tokens (truncated to 4000 chars) ───",
        T.take 4000 (show lns)
      ]
