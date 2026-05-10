-- | Tests for the `tree-sitter-awsum` grammar, run via the
-- `tree-sitter` CLI from inside the grammar repo. Three layers:
--
--   * `corpus` — every `.aww` under `test/sources/successful/`,
--     `test/sources/property/` and `test/sources/formatting/` is
--     parsed and asserted to produce no `(ERROR …)` / `(MISSING …)`
--     nodes. The first two are canonical surface-syntax fixtures the
--     compiler accepts; the third is malformed-but-recoverable input
--     used by the formatter's tests, which is exactly where the
--     scanner has historically regressed (the 22-GiB-runaway bug
--     surfaced on `formatting/improperly-formatted-source/`). Fast,
--     deterministic — the natural baseline for grammar work.
--
--   * `queries` — every `.scm` under `tree-sitter-awsum/queries/`
--     is run against every `.aww` in the corpus via
--     `tree-sitter query`. The output is scanned for `Query error` /
--     `Invalid node type` / `Query compilation failed`; any such
--     string fails the test. Catches grammar/queries drift — when a
--     grammar change renames a node type, the corresponding query
--     reference now has nowhere to bind, and the tree-sitter CLI
--     prints the error to stdout while exiting 0 (so neither
--     `tree-sitter generate` nor parse-only checks would notice).
--
--   * `property` — for each QuickCheck-generated `Program`, render
--     it via `Awsum.Render.renderProgram` (the same pipeline the
--     formatter uses) and apply BOTH checks above to it: parse must
--     produce no `(ERROR …)` / `(MISSING …)`, and every `.scm` query
--     must run without `Query error` / `Invalid node type` /
--     `Query compilation failed`. Drives the grammar past the corpus
--     into rare combinations that arbitrary generation hits.
--
-- Both layers share one discovery / spawn helper. Discovery is
-- best-effort: if `tree-sitter` isn't on PATH, or `tree-sitter-awsum/`
-- isn't in its conventional location next to the compiler repo
-- (override with `TREE_SITTER_AWSUM_DIR`), the spec emits a single
-- `pendingWith`.
--
-- Lives in the standalone `tree-sitter-tests` test-suite (see
-- `package.yaml`) so CI's main suite never sees it. Run via
-- `just test-tree-sitter` (corpus only) or
-- `just test-tree-sitter-property` (property only).
module Awsum.TreeSitterSpec (spec) where

import Awsum.ArbitraryInstances ()
import Awsum.Render (renderProgram)
import Awsum.Syntax (Program)
import Common.File (readFileTextUtf8)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Relude
import System.Directory (doesDirectoryExist, doesFileExist, findExecutable, getCurrentDirectory, listDirectory)
import System.FilePath ((</>))
import System.IO (hClose)
import System.IO.Temp (withSystemTempFile)
import System.Process (CreateProcess (cwd), proc, readCreateProcessWithExitCode)
import Test.Hspec
import Test.Hspec.QuickCheck (modifyMaxSuccess, prop)
import Test.QuickCheck (Property, counterexample, ioProperty)

spec :: Spec
spec = describe "Property tests" $ describe "tree-sitter-awsum" $ do
  resources <- runIO discover
  case resources of
    Nothing ->
      it "tree-sitter-awsum infrastructure available"
        $ pendingWith
          "Need `tree-sitter` on PATH and tree-sitter-awsum next to the compiler repo (or TREE_SITTER_AWSUM_DIR set)."
    Just (treeSitter, grammarDir) -> do
      corpusSpec treeSitter grammarDir
      queriesSpec treeSitter grammarDir
      propertySpec treeSitter grammarDir

-- ════════════════════════════════════════════════════════════════════
-- Corpus layer
-- ════════════════════════════════════════════════════════════════════

corpusSpec :: FilePath -> FilePath -> Spec
corpusSpec treeSitter grammarDir = describe "corpus" $ do
  files <- runIO discoverCorpus
  forM_ files $ \(label, path) ->
    it label $ do
      src <- readFileTextUtf8 path
      out <- runTreeSitterParse treeSitter grammarDir src
      unless (isAcceptable out) (expectationFailure (formatFailure src out))

-- | Walk successful/, property/ AND formatting/ source roots,
-- returning @(label, path)@ pairs for every test program's
-- @code/Main.aww@. Label is the relative path from the compiler-repo
-- root, which is what hspec prints for matching / debugging.
--
-- formatting/ is included because malformed-but-recoverable input
-- is exactly where the tree-sitter scanner is most likely to
-- regress (the original 22-GiB-runaway bug surfaced on
-- @formatting/improperly-formatted-source/code/Main.aww@). Tree-
-- sitter's grammar is intentionally lenient and must keep parsing
-- such files without runaway or stack corruption.
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
-- Queries layer
-- ════════════════════════════════════════════════════════════════════

-- | For every `.aww` in the corpus, run every query under
-- `tree-sitter-awsum/queries/` against it via `tree-sitter query`
-- and assert no error string appears in the output. One test per
-- `.aww` (queries fold inside) — keeps hspec output proportional to
-- which fixture broke, while still catching per-program issues a
-- single-file sanity check would miss.
queriesSpec :: FilePath -> FilePath -> Spec
queriesSpec treeSitter grammarDir = describe "queries" $ do
  awwFiles <- runIO discoverCorpus
  queryFiles <- runIO (discoverQueries grammarDir)
  if null queryFiles
    then it "queries directory present" $ pendingWith "tree-sitter-awsum/queries is missing"
    else forM_ awwFiles $ \(label, awwPath) ->
      it label $ forM_ queryFiles (validateQuery treeSitter grammarDir awwPath)

discoverQueries :: FilePath -> IO [(String, FilePath)]
discoverQueries grammarDir = do
  let queriesDir = grammarDir </> "queries"
  exists <- doesDirectoryExist queriesDir
  if not exists
    then pure []
    else do
      entries <- sort <$> listDirectory queriesDir
      pure
        [ ("queries/" <> e, queriesDir </> e)
        | e <- entries,
          ".scm" `T.isSuffixOf` toText e
        ]

validateQuery :: FilePath -> FilePath -> FilePath -> (String, FilePath) -> IO ()
validateQuery treeSitter grammarDir awwPath (queryLabel, queryPath) = do
  let cp = (proc treeSitter ["query", queryPath, awwPath]) {cwd = Just grammarDir}
  (_exit, sout, serr) <- readCreateProcessWithExitCode cp ""
  let combined = toText sout <> toText serr
      hasError =
        any
          (`T.isInfixOf` combined)
          ["Query error", "Invalid node type", "Query compilation failed"]
  when hasError
    $ expectationFailure
      ( toString
          $ unlines
            [ "tree-sitter query failed for " <> toText queryLabel <> " on " <> toText awwPath <> ":",
              combined
            ]
      )

-- ════════════════════════════════════════════════════════════════════
-- Property layer
-- ════════════════════════════════════════════════════════════════════
--
-- Mirrors corpus + queries on QuickCheck-generated programs: each
-- rendered program must parse without ERROR/MISSING AND every
-- query must run against it without a query error. Both checks
-- happen inside one property so the same generated source proves
-- the grammar AND the queries against it; a single counterexample
-- on shrink names which check failed.

propertySpec :: FilePath -> FilePath -> Spec
propertySpec treeSitter grammarDir = describe "property" $ do
  queryFiles <- runIO (discoverQueries grammarDir)
  modifyMaxSuccess (const 100)
    $ prop "tree-sitter accepts every renderProgram output (parse + queries)"
    $ \prog -> ioProperty (runOne treeSitter grammarDir queryFiles prog)

runOne :: FilePath -> FilePath -> [(String, FilePath)] -> Program -> IO Property
runOne treeSitter grammarDir queryFiles prog = do
  let src = renderProgram prog
  -- Persist the rendered source to a temp file just once; parse and
  -- every query share the same path so we don't re-write per check.
  withSystemTempFile "ts-prop.aww" $ \path h -> do
    TIO.hPutStr h src
    hClose h
    parseOut <- runTreeSitterParseOnPath treeSitter grammarDir path
    if not (isAcceptable parseOut)
      then pure (counterexample (formatParseFailure src parseOut) False)
      else do
        queryFailures <- runQueriesOnPath treeSitter grammarDir queryFiles path
        case queryFailures of
          [] -> pure (counterexample "" True)
          (queryLabel, combined) : _ ->
            pure (counterexample (formatQueryFailure src queryLabel combined) False)

-- | Run every query against the given parsed file. Returns
-- @(queryLabel, combinedOutput)@ for each query whose output
-- contains an error marker.
runQueriesOnPath :: FilePath -> FilePath -> [(String, FilePath)] -> FilePath -> IO [(String, Text)]
runQueriesOnPath treeSitter grammarDir queryFiles awwPath =
  fmap catMaybes $ forM queryFiles $ \(queryLabel, queryPath) -> do
    let cp = (proc treeSitter ["query", queryPath, awwPath]) {cwd = Just grammarDir}
    (_exit, sout, serr) <- readCreateProcessWithExitCode cp ""
    let combined = toText sout <> toText serr
        hasError =
          any
            (`T.isInfixOf` combined)
            ["Query error", "Invalid node type", "Query compilation failed"]
    pure $ if hasError then Just (queryLabel, combined) else Nothing

-- ════════════════════════════════════════════════════════════════════
-- Shared helpers
-- ════════════════════════════════════════════════════════════════════

discover :: IO (Maybe (FilePath, FilePath))
discover = do
  mTs <- findExecutable "tree-sitter"
  mDir <- findGrammarDir
  pure $ (,) <$> mTs <*> mDir

findGrammarDir :: IO (Maybe FilePath)
findGrammarDir = do
  override <- lookupEnv "TREE_SITTER_AWSUM_DIR"
  case override of
    Just p -> existsAsGrammar p
    Nothing -> do
      cwdPath <- getCurrentDirectory
      existsAsGrammar (cwdPath </> ".." </> "tree-sitter-awsum")
  where
    existsAsGrammar p = do
      e <- doesDirectoryExist p
      hasGrammar <- doesFileExist (p </> "grammar.js")
      pure $ if e && hasGrammar then Just p else Nothing

runTreeSitterParse :: FilePath -> FilePath -> Text -> IO Text
runTreeSitterParse ts grammarDir src =
  withSystemTempFile "ts-prop.aww" $ \path h -> do
    TIO.hPutStr h src
    hClose h
    runTreeSitterParseOnPath ts grammarDir path

runTreeSitterParseOnPath :: FilePath -> FilePath -> FilePath -> IO Text
runTreeSitterParseOnPath ts grammarDir path = do
  let cp = (proc ts ["parse", path]) {cwd = Just grammarDir}
  (_exit, sout, _serr) <- readCreateProcessWithExitCode cp ""
  pure (toText sout)

isAcceptable :: Text -> Bool
isAcceptable out = not (T.isInfixOf "(ERROR" out || T.isInfixOf "(MISSING" out)

-- | Used by the corpus layer (matches the original API).
formatFailure :: Text -> Text -> String
formatFailure = formatParseFailure

formatParseFailure :: Text -> Text -> String
formatParseFailure src out =
  toString
    $ unlines
      [ "tree-sitter parse produced ERROR or MISSING node(s).",
        "",
        "─── Source ───",
        src,
        "─── Parse tree (truncated to 4000 chars) ───",
        T.take 4000 out
      ]

formatQueryFailure :: Text -> String -> Text -> String
formatQueryFailure src queryLabel combined =
  toString
    $ unlines
      [ "tree-sitter query failed for " <> toText queryLabel <> ".",
        "",
        "─── Source ───",
        src,
        "─── Query output (truncated to 4000 chars) ───",
        T.take 4000 combined
      ]
