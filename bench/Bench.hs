-- | @awsum-bench@ — driver for benchmark programs under
--   @test/sources/benchmark/<NAME>/code/Main.aww@.
--
--   For each backend it compiles the program once, then runs the
--   produced artifact wrapped in @/usr/bin/time -l gtimeout TIMEOUT@
--   and reports wall-clock time + peak RSS + exit status. The wrap
--   order matters: @time@ is outermost so it observes the whole
--   subtree's @RUSAGE_CHILDREN@ even when @gtimeout@ kills the
--   runner; @gtimeout@ guarantees a hung backend doesn't tie up the
--   benchmark indefinitely.
--
--   With @--snapshot@ it instead runs each backend @--runs@ times and
--   overwrites @.benchmarks\/<NAME>\/bench.txt@ with the
--   per-backend @median (min–max)@ of wall time + peak RSS — no
--   threshold on the numbers. Every successful run's stdout is also
--   compared against a cross-backend anchor: a deviation marks the
--   row @mismatch@ and the process exits non-zero, so a backend whose
--   behaviour changed can't hide in plausible-looking numbers. The
--   measurement workflow is local and hardware-independent: snapshot
--   before a change, snapshot again after, read the @git diff@ — the
--   (min–max) band tells run-to-run noise from signal.
--
--   macOS-only at the moment (BSD @\/usr\/bin\/time@ output format,
--   @gtimeout@ from Homebrew @coreutils@). Linux would need a small
--   branch to call @\/usr\/bin\/time -v@ and parse a different shape.
module Main (main) where

import Awsum.Codegen.CLR.Assemble (assembleCLR)
import Awsum.Codegen.JS (codegenJS)
import Awsum.Codegen.JVM.Assemble (assembleJVM, renderJvmLimitExceeded)
import Awsum.Codegen.LLVM (codegenLLVM, llvmHostFromSystem, llvmHostLinkerFlags, llvmLinkHostFromSystem)
import Awsum.Codegen.WASM.Assemble (assembleWASM)
import Awsum.Core (CoreProgram, PreludeTags)
import Awsum.ElaborateLower (SimplifyMode (..), elaborateLowerProgramWith)
import Awsum.Parser (parseProgram)
import Awsum.Prelude (withPrelude)
import Awsum.Program (ProgramType (..))
import Common.File (readFileTextUtf8)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time.Clock (diffUTCTime, getCurrentTime)
import Options.Applicative qualified as OA
import Relude
import System.Directory (createDirectoryIfMissing)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Info (os)
import System.Process (readProcessWithExitCode)
import Text.Printf (printf)

-- ════════════════════════════════════════════════════════════════════════════
-- CLI
-- ════════════════════════════════════════════════════════════════════════════

data Options = Options
  { optTest :: !Text,
    optTimeoutSecs :: !Int,
    optSnapshot :: !Bool,
    optRuns :: !Int
  }

optionsParser :: OA.ParserInfo Options
optionsParser =
  OA.info
    ( ( Options
          <$> OA.strArgument
            ( OA.metavar "TEST"
                <> OA.help "Subdirectory under test/sources/benchmark/ holding code/Main.aww"
            )
          <*> OA.option
            OA.auto
            ( OA.long "timeout"
                <> OA.metavar "SECS"
                <> OA.value 60
                <> OA.showDefault
                <> OA.help "Per-backend timeout (passed to gtimeout)"
            )
          <*> OA.switch
            ( OA.long "snapshot"
                <> OA.help "Write the per-backend median to .benchmarks/<TEST>/bench.txt (overwrite, no threshold)"
            )
          <*> OA.option
            OA.auto
            ( OA.long "runs"
                <> OA.metavar "N"
                <> OA.value 5
                <> OA.showDefault
                <> OA.help "Runs per backend for the median (snapshot mode; odd N gives a true median)"
            )
      )
        <**> OA.helper
    )
    ( OA.fullDesc
        <> OA.progDesc "Run a single benchmark program through every backend with timing + peak-RSS"
    )

main :: IO ()
main = do
  when (os /= "darwin") $ do
    TIO.hPutStrLn stderr "awsum-bench currently supports macOS only (BSD /usr/bin/time -l + gtimeout from coreutils)."
    exitFailure
  opts <- OA.execParser optionsParser
  if opts.optSnapshot then runSnapshot opts else runBench opts

-- ════════════════════════════════════════════════════════════════════════════
-- Compile + run
-- ════════════════════════════════════════════════════════════════════════════

data Backend = LLVM | JVM | CLR | WASM | JS
  deriving stock (Show, Eq, Ord, Enum, Bounded)

allBackends :: [Backend]
allBackends = universe

data RunResult = RunResult
  { rrExit :: !ExitCode,
    rrWallSec :: !Double,
    rrPeakRssBytes :: !(Maybe Integer),
    rrStdout :: !Text,
    rrStderr :: !Text
  }

-- | Parse + lower a benchmark program to Core. Shared by the print and
--   snapshot drivers; the snapshot driver additionally loads a
--   'SimplifyOff' variant for its differential stdout check.
loadCore :: SimplifyMode -> Text -> IO (PreludeTags, CoreProgram)
loadCore mode test = do
  let path = "test/sources/benchmark" </> toString test </> "code" </> "Main.aww"
  src <- readFileTextUtf8 path
  case parseProgram src of
    Left e -> error ("parse failed: " <> e)
    Right ast -> case elaborateLowerProgramWith mode ProgramCli (withPrelude ast) of
      Left err -> error ("elaborate failed: " <> show err)
      Right (_warns, pt, core) -> pure (pt, core)

runBench :: Options -> IO ()
runBench opts = do
  (ptags, core) <- loadCore SimplifyOn opts.optTest
  putTextLn $ "Benchmark: " <> opts.optTest
  putTextLn $ "Timeout:   " <> show opts.optTimeoutSecs <> "s"
  putTextLn ""
  putTextLn header
  putTextLn separator
  withSystemTempDirectory "awsum-bench" $ \dir -> do
    artifacts <- buildAllArtifacts dir ptags core
    rows <- forM allBackends $ \b -> do
      r <- runOne opts.optTimeoutSecs dir artifacts b
      putTextLn (formatRow b r)
      pure (b, r)
    putTextLn ""
    forM_ rows $ \(b, r) -> when (rrExit r /= ExitSuccess) (printFailureDetail b r)

-- ────────────────────────────────────────────────────────────────────────────
-- Snapshot mode: median over N runs per backend, overwritten to a golden file
-- ────────────────────────────────────────────────────────────────────────────

-- | Aggregated per-backend result over the N runs: a status, the
--   median \/ min \/ max wall time and peak RSS of the successful runs,
--   and the first deviation from the cross-backend stdout anchor
--   (run index + stdout) when there is one.
data Agg = Agg
  { aggStatus :: !Text,
    aggWall :: !(Maybe (Stats Double)),
    aggRss :: !(Maybe (Stats Integer)),
    aggMismatch :: !(Maybe (Int, Text))
  }

aggOk :: Agg -> Bool
aggOk agg = aggStatus agg == "ok"

-- | Run every backend @--runs@ times, aggregate per backend, and
--   overwrite @.benchmarks/<TEST>/bench.txt@. No threshold on
--   the numbers — the file is read through @git diff@ before/after a
--   change — but behaviour is checked: any failed run, and any
--   successful run whose stdout deviates from the cross-backend
--   anchor, leaves a non-@ok@ status in the file and exits non-zero,
--   so @just benchmark-snapshot@ stops loud instead of recording a
--   plausible-looking lie.
runSnapshot :: Options -> IO ()
runSnapshot opts = do
  (ptags, core) <- loadCore SimplifyOn opts.optTest
  putTextLn $ "Snapshot: " <> opts.optTest <> "  (median of " <> show opts.optRuns <> " runs/backend, timeout " <> show opts.optTimeoutSecs <> "s)"
  withSystemTempDirectory "awsum-bench" $ \dir -> do
    artifacts <- buildAllArtifacts dir ptags core
    let go anchor acc = \case
          [] -> pure (reverse acc, anchor)
          b : bs -> do
            results <- replicateM opts.optRuns (runOne opts.optTimeoutSecs dir artifacts b)
            let anchor' = anchor <|> (rrStdout <$> find ((== ExitSuccess) . rrExit) results)
                agg = aggregate anchor' results
            putTextLn ("  " <> toText (printf "%-7s  %s" (show b :: String) (toString (aggStatus agg)) :: String))
            go anchor' ((b, agg) : acc) bs
    (rows, anchor) <- go Nothing [] allBackends
    -- Outside .snapshots/ deliberately: .snapshots holds what `just test`
    -- regenerates, so a full reset there must not take the medians with
    -- it. This tree is written only here, by explicit benchmark runs.
    let outDir = ".benchmarks" </> toString opts.optTest
    createDirectoryIfMissing True outDir
    let outFile = outDir </> "bench.txt"
    writeFileText outFile (renderSnapshot opts anchor rows)
    putTextLn $ "  wrote " <> toText outFile
    -- Differential check: the same program compiled without the Simplify
    -- pass must print the same stdout. One unmeasured run per backend
    -- against the same cross-backend anchor; nothing of it is recorded —
    -- bench.txt stays a SimplifyOn measurement, a deviation goes to
    -- stderr and the exit code. Skipped when no anchor exists (every
    -- measured run failed, so the rows above are already non-ok).
    offBad <- case anchor of
      Nothing -> pure []
      Just a -> do
        putTextLn "  no-simplify differential (one unmeasured run per backend):"
        withSystemTempDirectory "awsum-bench-no-simplify" $ \offDir -> do
          (ptagsOff, coreOff) <- loadCore SimplifyOff opts.optTest
          artifactsOff <- buildAllArtifacts offDir ptagsOff coreOff
          fmap catMaybes $ forM allBackends $ \b -> do
            r <- runOne opts.optTimeoutSecs offDir artifactsOff b
            let deviation = case rrExit r of
                  ExitSuccess -> if rrStdout r == a then Nothing else Just (b, "stdout mismatch")
                  ec -> Just (b, statusText ec)
            putTextLn ("  " <> toText (printf "%-7s  %s" (show b :: String) (toString (maybe "ok" snd deviation)) :: String))
            pure deviation
    let bad = [b | (b, agg) <- rows, not (aggOk agg)]
    unless (null bad && null offBad) $ do
      unless (null bad)
        $ TIO.hPutStrLn stderr
        $ "  non-ok rows ("
        <> T.intercalate ", " (map show bad)
        <> ") — see "
        <> toText outFile
      unless (null offBad)
        $ TIO.hPutStrLn stderr
        $ "  no-simplify deviations: "
        <> T.intercalate ", " [show b <> " (" <> d <> ")" | (b, d) <- offBad]
      exitFailure

-- | Collapse the N runs of one backend into a status plus per-metric
--   @median \/ min \/ max@ over the successful runs. A failed run
--   (timeout, non-zero exit) sets the status to its kind with a
--   @(failed\/total)@ count; otherwise a successful run whose stdout
--   differs from the anchor sets @mismatch(deviating\/total)@ — the
--   per-run cross-backend identical-stdout check. The anchor is the
--   first successful run's stdout of the first backend that produced
--   one, so the anchor backend's own later runs are checked against it
--   too: cross-run nondeterminism surfaces the same way.
aggregate :: Maybe Text -> [RunResult] -> Agg
aggregate anchor rs =
  let oks = filter ((== ExitSuccess) . rrExit) rs
      failures = filter ((/= ExitSuccess) . rrExit) rs
      deviations =
        [ (i, rrStdout r)
        | a <- maybeToList anchor,
          (i, r) <- zip [1 :: Int ..] rs,
          rrExit r == ExitSuccess,
          rrStdout r /= a
        ]
      count k = "(" <> show k <> "/" <> show (length rs) <> ")"
      status = case (failures, deviations) of
        (f : _, _) -> statusText (rrExit f) <> count (length failures)
        ([], _ : _) -> "mismatch" <> count (length deviations)
        ([], []) -> "ok"
   in Agg
        { aggStatus = status,
          aggWall = stats (map rrWallSec oks),
          aggRss = stats (mapMaybe rrPeakRssBytes oks),
          aggMismatch = listToMaybe deviations
        }

-- | Per-metric aggregate over the successful runs: median by sorting
--   and taking the middle element (an odd @--runs@ — the default 5 —
--   gives the true median; an even count the upper-middle), plus the
--   min and max bounding the run-to-run noise band.
data Stats a = Stats
  { stMed :: !a,
    stMin :: !a,
    stMax :: !a
  }

type role Stats representational

stats :: (Ord a) => [a] -> Maybe (Stats a)
stats xs = case sortOn identity xs of
  [] -> Nothing
  sorted@(lo : _) ->
    Stats
      <$> sorted
      !!? (length sorted `div` 2)
      <*> Just lo
      <*> viaNonEmpty last sorted

-- | The golden file: a per-backend table of @median (min–max)@ cells
--   plus a short stdout anchor. Behaviour is checked right here: every
--   successful run of every backend is compared against the anchor,
--   and a deviating backend renders a @mismatch@ status plus its own
--   @stdout[…]@ line under the anchor. Compiler-side artifacts of
--   benchmark programs are snapshotted by the Hspec suite
--   (@.snapshots\/benchmark\/<NAME>\/compiler\/@); this file owns the
--   runtime side. Only the numbers vary between healthy runs — no
--   hostname \/ CPU — so a before\/after @git diff@ reads as pure
--   deltas, and the (min–max) band separates run-to-run noise from a
--   real shift.
renderSnapshot :: Options -> Maybe Text -> [(Backend, Agg)] -> Text
renderSnapshot opts anchor rows =
  unlines
    $ [ "benchmark: " <> opts.optTest,
        "median (min–max) over " <> show opts.optRuns <> " runs per backend (wall time, peak RSS); timeout " <> show opts.optTimeoutSecs <> "s; macOS",
        "",
        toText snapHeader
      ]
    <> map (uncurry snapRow) rows
    <> ["", "stdout: " <> anchorShown]
    <> mismatchLines
  where
    anchorShown = case shortStdout <$> anchor of
      Just s | not (T.null s) -> s
      _ -> "—"
    mismatchLines =
      [ "stdout[" <> show b <> runSuffix i <> "]: " <> shortStdout s
      | (b, agg) <- rows,
        (i, s) <- maybeToList (aggMismatch agg)
      ]
    runSuffix i = if i == 1 then ("" :: Text) else ", run " <> show i

snapHeader :: String
snapHeader = printf "%-7s  %-13s  %20s  %23s" ("target" :: String) ("status" :: String) ("time(s)" :: String) ("peakMem(MiB)" :: String)

snapRow :: Backend -> Agg -> Text
snapRow b agg =
  let wall = case agg.aggWall of
        Just s -> printf "%20s" (printf "%.2f (%.2f–%.2f)" s.stMed s.stMin s.stMax :: String) :: String
        Nothing -> printf "%20s" ("—" :: String) :: String
      rss = case agg.aggRss of
        Just s -> printf "%23s" (printf "%.1f (%.1f–%.1f)" (toMiB s.stMed) (toMiB s.stMin) (toMiB s.stMax) :: String) :: String
        Nothing -> printf "%23s" ("—" :: String) :: String
   in toText (printf "%-7s  %-13s  %s  %s" (show b :: String) (toString (aggStatus agg)) wall rss :: String)

-- ────────────────────────────────────────────────────────────────────────────
-- Shared formatting helpers
-- ────────────────────────────────────────────────────────────────────────────

-- | Exit code → short human status, shared by the print table and the snapshot.
statusText :: ExitCode -> Text
statusText = \case
  ExitSuccess -> "ok"
  ExitFailure 124 -> "timeout"
  ExitFailure n -> "fail(" <> show n <> ")"

-- | First line (≤40 chars) of stdout, newlines flattened — a compact anchor.
shortStdout :: Text -> Text
shortStdout = T.take 40 . T.replace "\n" "⏎" . T.strip

-- | Bytes → MiB divisor, shared by both formatters.
mib :: Double
mib = 1024 * 1024

-- | Bytes → MiB, shared by both formatters.
toMiB :: Integer -> Double
toMiB n = fromIntegral n / mib

-- ────────────────────────────────────────────────────────────────────────────
-- Artifact production
-- ────────────────────────────────────────────────────────────────────────────

data Artifacts = Artifacts
  { aLLVMBin :: !FilePath,
    aJVMDir :: !FilePath,
    aCLRDll :: !FilePath,
    aWASM :: !FilePath,
    aJS :: !FilePath
  }

buildAllArtifacts :: FilePath -> PreludeTags -> CoreProgram -> IO Artifacts
buildAllArtifacts dir ptags core = do
  let ll = codegenLLVM llvmHostFromSystem ptags core
      jvmBytes = case assembleJVM ptags core of
        Left e -> error ("assembleJVM refused a benchmark program: " <> renderJvmLimitExceeded e)
        Right b -> b
      clrBytes = assembleCLR ptags core
      wasmBytes = assembleWASM ptags core
      jsCode = codegenJS ProgramCli ptags core
  llvmBin <- buildLLVMBin dir ll
  let jvmClass = dir </> "AwsumMain.class"
      clrDll = dir </> "AwsumMain.dll"
      clrCfg = dir </> "AwsumMain.runtimeconfig.json"
      wasmFile = dir </> "out.wasm"
      jsFile = dir </> "out.js"
  writeFileBS jvmClass jvmBytes
  writeFileBS clrDll clrBytes
  writeFileText clrCfg runtimeConfigJson
  writeFileBS wasmFile wasmBytes
  writeFileText jsFile jsCode
  pure
    Artifacts
      { aLLVMBin = llvmBin,
        aJVMDir = dir,
        aCLRDll = clrDll,
        aWASM = wasmFile,
        aJS = jsFile
      }

-- | Compile LLVM IR to a native binary via @clang -O2@. Same path as
--   the test harness in @test/Awsum/RunBackend.hs@.
buildLLVMBin :: FilePath -> Text -> IO FilePath
buildLLVMBin dir ll = do
  let llFile = dir </> "out.ll"
      binFile = dir </> "out"
  writeFileText llFile ll
  clangPath <- fromMaybe "clang" . mfilter (not . null) <$> lookupEnv "AWSUM_CLANG"
  (ec, out, err) <-
    readProcessWithExitCode
      clangPath
      ( ["-O2", "-Wno-override-module", llFile, "-o", binFile]
          <> llvmHostLinkerFlags llvmLinkHostFromSystem
      )
      ""
  case ec of
    ExitSuccess -> pure binFile
    ExitFailure n ->
      error
        . toText
        $ "clang failed during compile (exit "
        <> show n
        <> ")\nstderr:\n"
        <> err
        <> "\nstdout:\n"
        <> out

-- ────────────────────────────────────────────────────────────────────────────
-- Per-backend invocation
-- ────────────────────────────────────────────────────────────────────────────

runOne :: Int -> FilePath -> Artifacts -> Backend -> IO RunResult
runOne t _dir a LLVM = runWithStats t a.aLLVMBin []
runOne t _dir a JVM = runWithStats t "java" ["-Dsun.jnu.encoding=UTF-8", "-Dfile.encoding=UTF-8", "-cp", a.aJVMDir, "AwsumMain"]
runOne t _dir a CLR = runWithStats t "dotnet" [a.aCLRDll]
runOne t _dir a WASM = runWithStats t "wasmtime" [a.aWASM]
runOne t _dir a JS = runWithStats t "node" [a.aJS]

-- | Wrap a command with @\/usr\/bin\/time -l gtimeout TIMEOUT@ and
--   capture wall time, exit status, peak RSS, stdout, stderr.
--
--   Wrap order: @time@ is outermost, @gtimeout@ inside it. This way
--   @time@'s @RUSAGE_CHILDREN@ accumulates across @gtimeout@'s exit
--   so the rusage line is always written, regardless of whether the
--   inner runner finished naturally or was killed.
runWithStats :: Int -> FilePath -> [String] -> IO RunResult
runWithStats timeoutSecs cmd args = do
  let fullArgs = ["-l", "gtimeout", show timeoutSecs, cmd] <> args
  start <- getCurrentTime
  (ec, sout, serr) <- readProcessWithExitCode "/usr/bin/time" fullArgs ""
  end <- getCurrentTime
  let serrT = toText serr
  pure
    RunResult
      { rrExit = ec,
        rrWallSec = realToFrac (diffUTCTime end start),
        rrPeakRssBytes = parsePeakRss serrT,
        rrStdout = toText sout,
        rrStderr = serrT
      }

-- | Parse "N  maximum resident set size" line out of BSD time -l
--   output. The numeric value is in bytes on macOS.
parsePeakRss :: Text -> Maybe Integer
parsePeakRss txt = listToMaybe $ do
  line <- lines txt
  let trimmed = T.strip line
  guard ("maximum resident set size" `T.isInfixOf` trimmed)
  let num = T.takeWhile (/= ' ') trimmed
  maybe [] pure (readMaybe (toString num))

-- ────────────────────────────────────────────────────────────────────────────
-- Output formatting
-- ────────────────────────────────────────────────────────────────────────────

header :: Text
header = toText (printf "%-7s  %-12s  %9s  %14s  %s" ("target" :: String) ("status" :: String) ("time(s)" :: String) ("peakMem(MiB)" :: String) ("stdout" :: String) :: String)

separator :: Text
separator = T.replicate 90 "─"

formatRow :: Backend -> RunResult -> Text
formatRow b r =
  let st = toString (statusText (rrExit r)) :: String
      wall = printf "%9.2f" (rrWallSec r) :: String
      rss = case rrPeakRssBytes r of
        Just n -> printf "%14.1f" (toMiB n) :: String
        Nothing -> printf "%14s" ("—" :: String) :: String
      head_ = printf "%-7s  %-12s  %s  %s  " (show b :: String) st wall rss :: String
   in toText head_ <> shortStdout (rrStdout r)

printFailureDetail :: Backend -> RunResult -> IO ()
printFailureDetail b r = do
  putTextLn $ "── " <> show b <> " stderr ──────────────────────────────────────────────────"
  putText (rrStderr r)
  putTextLn ""

-- ────────────────────────────────────────────────────────────────────────────
-- CLR runtime config (kept in sync with test/Awsum/RunBackend.hs).
-- ────────────────────────────────────────────────────────────────────────────

runtimeConfigJson :: Text
runtimeConfigJson =
  "{\n\
  \  \"runtimeOptions\": {\n\
  \    \"tfm\": \"net9.0\",\n\
  \    \"framework\": {\n\
  \      \"name\": \"Microsoft.NETCore.App\",\n\
  \      \"version\": \"9.0.0\"\n\
  \    },\n\
  \    \"rollForward\": \"LatestMajor\"\n\
  \  }\n\
  \}\n"
