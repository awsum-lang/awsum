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
--   macOS-only at the moment (BSD @\/usr\/bin\/time@ output format,
--   @gtimeout@ from Homebrew @coreutils@). Linux would need a small
--   branch to call @\/usr\/bin\/time -v@ and parse a different shape;
--   not in scope here — see [management/tasks/2026-05-10__21-07.md].
module Main (main) where

import Awsum.Codegen.CLR.Assemble (assembleCLR)
import Awsum.Codegen.JS (codegenJS)
import Awsum.Codegen.JVM.Assemble (assembleJVM)
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
    optTimeoutSecs :: !Int
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
  runBench opts

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

runBench :: Options -> IO ()
runBench opts = do
  let path = "test/sources/benchmark" </> toString opts.optTest </> "code" </> "Main.aww"
  src <- readFileTextUtf8 path
  let ast = case parseProgram src of
        Left e -> error ("parse failed: " <> e)
        Right x -> x
      (ptags, core) = case elaborateLowerProgram ProgramCli (withPrelude ast) of
        Left err -> error ("elaborate failed: " <> show err)
        Right (_warns, pt, x) -> (pt, x)
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
      jvmBytes = assembleJVM ptags core
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
header = toText (printf "%-7s  %-12s  %9s  %14s  %s" ("backend" :: String) ("status" :: String) ("wall(s)" :: String) ("peakRss(MiB)" :: String) ("stdout" :: String) :: String)

separator :: Text
separator = T.replicate 90 "─"

formatRow :: Backend -> RunResult -> Text
formatRow b r =
  let st :: String
      st = case rrExit r of
        ExitSuccess -> "ok"
        ExitFailure 124 -> "timeout"
        ExitFailure n -> "fail(" <> show n <> ")"
      wall = printf "%9.2f" (rrWallSec r) :: String
      rss = case rrPeakRssBytes r of
        Just n -> printf "%14.1f" (fromIntegral n / mib :: Double) :: String
        Nothing -> printf "%14s" ("—" :: String) :: String
      stdoutShort = T.take 40 (T.replace "\n" "⏎" (T.strip (rrStdout r)))
      head_ = printf "%-7s  %-12s  %s  %s  " (show b :: String) st wall rss :: String
   in toText head_ <> stdoutShort
  where
    mib = 1024 * 1024 :: Double

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
