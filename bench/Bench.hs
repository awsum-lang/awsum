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
--   overwrites the per-backend median wall time + peak RSS to
--   @.snapshots\/benchmark\/<NAME>\/bench.txt@ — no threshold, no
--   pass\/fail. The measurement workflow is local and hardware-independent:
--   snapshot before a change, snapshot again after, read the @git diff@.
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
import Awsum.ElaborateLower (elaborateLowerProgram)
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
                <> OA.help "Write the per-backend median to .snapshots/benchmark/<TEST>/bench.txt (overwrite, no threshold)"
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
--   snapshot drivers.
loadCore :: Text -> IO (PreludeTags, CoreProgram)
loadCore test = do
  let path = "test/sources/benchmark" </> toString test </> "code" </> "Main.aww"
  src <- readFileTextUtf8 path
  case parseProgram src of
    Left e -> error ("parse failed: " <> e)
    Right ast -> case elaborateLowerProgram ProgramCli (withPrelude ast) of
      Left err -> error ("elaborate failed: " <> show err)
      Right (_warns, pt, core) -> pure (pt, core)

runBench :: Options -> IO ()
runBench opts = do
  (ptags, core) <- loadCore opts.optTest
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

-- | Aggregated per-backend result over the N runs: a status plus the median
--   wall time and median peak RSS of the successful runs, and one captured
--   stdout for the behavioural anchor.
data Agg = Agg
  { aggStatus :: !Text,
    aggMedWallSec :: !(Maybe Double),
    aggMedRssBytes :: !(Maybe Integer),
    aggStdout :: !Text
  }

-- | Run every backend @--runs@ times, take the per-backend median, and
--   overwrite @.snapshots/benchmark/<TEST>/bench.txt@. No threshold, no
--   pass/fail — the file is read through @git diff@ before/after a change.
runSnapshot :: Options -> IO ()
runSnapshot opts = do
  (ptags, core) <- loadCore opts.optTest
  putTextLn $ "Snapshot: " <> opts.optTest <> "  (median of " <> show opts.optRuns <> " runs/backend, timeout " <> show opts.optTimeoutSecs <> "s)"
  withSystemTempDirectory "awsum-bench" $ \dir -> do
    artifacts <- buildAllArtifacts dir ptags core
    rows <- forM allBackends $ \b -> do
      results <- replicateM opts.optRuns (runOne opts.optTimeoutSecs dir artifacts b)
      let agg = aggregate results
      putTextLn ("  " <> toText (printf "%-7s  %s" (show b :: String) (toString (aggStatus agg)) :: String))
      pure (b, agg)
    let outDir = ".snapshots" </> "benchmark" </> toString opts.optTest
    createDirectoryIfMissing True outDir
    let outFile = outDir </> "bench.txt"
    writeFileText outFile (renderSnapshot opts.optTest rows)
    putTextLn $ "  wrote " <> toText outFile

-- | Collapse the N runs of one backend into a status + medians. The median
--   uses only the successful runs; the status is the first non-success exit
--   (or @ok@ when every run succeeded).
aggregate :: [RunResult] -> Agg
aggregate rs =
  let oks = filter ((== ExitSuccess) . rrExit) rs
   in Agg
        { aggStatus = maybe "ok" (statusText . rrExit) (find ((/= ExitSuccess) . rrExit) rs),
          aggMedWallSec = median (map rrWallSec oks),
          aggMedRssBytes = median (mapMaybe rrPeakRssBytes oks),
          aggStdout = maybe "" rrStdout (listToMaybe oks)
        }

-- | Median by sorting and taking the middle element. With an odd sample count
--   (the default @--runs@ is 5) this is the true median; with an even count it
--   is the upper-middle element.
median :: (Ord a) => [a] -> Maybe a
median xs = sortOn identity xs !!? (length xs `div` 2)

-- | The golden file: a per-backend table of medians plus a short stdout anchor.
--   Benchmark programs are not in the Hspec suite, so the anchor is the only
--   guard that a change didn't alter their behaviour. Only the numbers vary
--   between runs — no hostname / CPU — so a before/after @git diff@ reads as
--   pure deltas.
renderSnapshot :: Text -> [(Backend, Agg)] -> Text
renderSnapshot test rows =
  unlines $
    [ "benchmark: " <> test,
      "medians over several runs per backend (wall time, peak RSS); macOS",
      "",
      toText snapHeader
    ]
      <> map (uncurry snapRow) rows
      <> ["", "stdout: " <> stdoutAnchor]
  where
    stdoutAnchor = case mapMaybe (nonEmpty' . shortStdout . aggStdout . snd) rows of
      (s : _) -> s
      [] -> "—"
    nonEmpty' s = if T.null s then Nothing else Just s

snapHeader :: String
snapHeader = printf "%-7s  %-10s  %9s  %14s" ("target" :: String) ("status" :: String) ("time(s)" :: String) ("peakMem(MiB)" :: String)

snapRow :: Backend -> Agg -> Text
snapRow b agg =
  let wall = case aggMedWallSec agg of
        Just t -> printf "%9.2f" t :: String
        Nothing -> printf "%9s" ("—" :: String) :: String
      rss = case aggMedRssBytes agg of
        Just n -> printf "%14.1f" (fromIntegral n / mib :: Double) :: String
        Nothing -> printf "%14s" ("—" :: String) :: String
   in toText (printf "%-7s  %-10s  %s  %s" (show b :: String) (toString (aggStatus agg)) wall rss :: String)

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
        Just n -> printf "%14.1f" (fromIntegral n / mib :: Double) :: String
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
