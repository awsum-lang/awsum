-- | 'jvmLaunchFlags' keep the JVM's own output off stdout. By default the JVM
--   prints to stdout through two channels, unified logging and its VM output
--   stream, so a JVM warning lands in the program's output and the JVM leg
--   differs from the other four backends. The test forces one line out of
--   each channel and requires stdout to be the program's output alone, and
--   stderr to carry both lines (so a JDK that stops printing them fails the
--   test instead of passing it vacuously).
module Awsum.JvmLaunchSpec (spec) where

import Awsum.Codegen.JVM.Assemble (jvmLaunchFlags)
import Awsum.RunBackend (CompiledArtifacts (..), compileFromText, timeLimitMicros)
import Relude
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import System.Timeout (timeout)
import Test.Hspec

spec :: Spec
spec = describe "JVM launch flags"
  $ it "keep the JVM's own output off stdout"
  $ do
    artifacts <- compileFromText "import IO.Stdout\n\nmain : IO Never Unit\nmain = IO.Stdout.print \"ok\"\n"
    withSystemTempDirectory "awsum" $ \dir -> do
      writeFileBS (dir </> "AwsumMain.class") (caJVMBytes artifacts)
      let provoke =
            [ -- unified logging: a missing CDS archive logs a cds error
              "-XX:SharedArchiveFile=" <> (dir </> "missing.jsa"),
              -- VM output stream: the final value of every VM flag
              "-XX:+PrintFlagsFinal"
            ]
      result <- timeout timeLimitMicros (readProcessWithExitCode "java" (jvmLaunchFlags <> provoke <> ["-cp", dir, "AwsumMain"]) "")
      case result of
        Nothing -> expectationFailure "java timed out"
        Just (code, out, err) -> do
          code `shouldBe` ExitSuccess
          out `shouldBe` "ok"
          err `shouldContain` "[cds]"
          err `shouldContain` "UsePerfData"
