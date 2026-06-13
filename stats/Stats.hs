-- | @awsum-stats@ — aggregate linearity statistics across every
--   program under @test/sources/successful/@.
--
--   For each program: parse → withPrelude → elaborateLowerProgram →
--   'Awsum.Lifetime.analyzeProgram'. Tally every binder by kind
--   ('Param' / 'CasePattern' / 'RowCaseBinder') and by use count
--   bucket (unused / linear / multi). Print one summary table at the
--   end. The number to read first is the 'linear' percentage at the
--   bottom of the @overall@ row — it gauges how much of the program
--   space is amenable to in-place reuse.
--
--   No timeouts, no parallelism — analysis is pure and fast.
module Main (main) where

import Awsum.ElaborateLower (elaborateLowerProgram)
import Awsum.Lifetime (BindingKind (..), BindingUsage (..), DeclLifetime (..), LifetimeEntry (..), analyzeProgram)
import Awsum.Parser (parseProgram)
import Awsum.Prelude (withPrelude)
import Awsum.Program (ProgramType (..))
import Common.File (readFileTextUtf8)
import Control.Exception (try)
import Data.Text qualified as T
import Relude
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath ((</>))
import Text.Printf (printf)

sourcesDir :: FilePath
sourcesDir = "test/sources/successful"

-- ════════════════════════════════════════════════════════════════════════════
-- Per-bucket counts
-- ════════════════════════════════════════════════════════════════════════════

-- | One row of the summary: how many binders of a given kind fall
--   into each use-count bucket.
data Bucket = Bucket
  { bUnused :: !Int,
    bLinear :: !Int,
    bMulti :: !Int
  }
  deriving stock (Show)

instance Semigroup Bucket where
  Bucket a b c <> Bucket d e f = Bucket (a + d) (b + e) (c + f)

instance Monoid Bucket where
  mempty = Bucket 0 0 0

bucketTotal :: Bucket -> Int
bucketTotal (Bucket u l m) = u + l + m

classify :: BindingUsage -> Bucket
classify (BindingUsage 0) = Bucket 1 0 0
classify (BindingUsage 1) = Bucket 0 1 0
classify (BindingUsage _) = Bucket 0 0 1

-- | One summary row per kind.
data Summary = Summary
  { sParam :: !Bucket,
    sCasePattern :: !Bucket,
    sRowCaseBinder :: !Bucket,
    sLetBinder :: !Bucket,
    sJoinParam :: !Bucket
  }
  deriving stock (Show)

instance Semigroup Summary where
  Summary a b c d j <> Summary e f g h k = Summary (a <> e) (b <> f) (c <> g) (d <> h) (j <> k)

instance Monoid Summary where
  mempty = Summary mempty mempty mempty mempty mempty

summarize :: [DeclLifetime] -> Summary
summarize = foldMap (foldMap entrySummary . dlEntries)
  where
    entrySummary (LifetimeEntry _ k u) =
      let b = classify u
       in case k of
            Param -> mempty {sParam = b}
            CasePattern -> mempty {sCasePattern = b}
            RowCaseBinder -> mempty {sRowCaseBinder = b}
            LetBinder -> mempty {sLetBinder = b}
            JoinParam -> mempty {sJoinParam = b}

summaryOverall :: Summary -> Bucket
summaryOverall s = s.sParam <> s.sCasePattern <> s.sRowCaseBinder <> s.sLetBinder <> s.sJoinParam

-- ════════════════════════════════════════════════════════════════════════════
-- Driver
-- ════════════════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  testNames <- discoverTests
  results <- forM testNames $ \name -> do
    s <- analyzeOne name
    pure (name, s)
  let agg = foldMap snd results
  putTextLn $ "Programs analysed: " <> show (length results)
  putTextLn ""
  putTextLn header
  putTextLn separator
  putTextLn (formatRow "Param" agg.sParam)
  putTextLn (formatRow "CasePattern" agg.sCasePattern)
  putTextLn (formatRow "RowCaseBinder" agg.sRowCaseBinder)
  putTextLn (formatRow "LetBinder" agg.sLetBinder)
  putTextLn (formatRow "JoinParam" agg.sJoinParam)
  putTextLn separator
  putTextLn (formatRow "overall" (summaryOverall agg))

discoverTests :: IO [FilePath]
discoverTests = do
  entries <- listDirectory sourcesDir
  sort <$> filterM (\e -> doesDirectoryExist (sourcesDir </> e)) entries

analyzeOne :: FilePath -> IO Summary
analyzeOne name = do
  let path = sourcesDir </> name </> "code" </> "Main.aww"
  esrc <- try @SomeException (readFileTextUtf8 path)
  case esrc of
    Left ex -> do
      putTextLn $ "  skip " <> toText name <> ": " <> show ex
      pure mempty
    Right src -> case parseProgram src of
      Left e -> do
        putTextLn $ "  skip " <> toText name <> ": parse failed " <> toText e
        pure mempty
      Right ast -> case elaborateLowerProgram ProgramCli (withPrelude ast) of
        Left err -> do
          putTextLn $ "  skip " <> toText name <> ": elaborate failed " <> show err
          pure mempty
        Right (_warns, _ptags, core) ->
          pure (summarize (analyzeProgram core))

-- ════════════════════════════════════════════════════════════════════════════
-- Formatting
-- ════════════════════════════════════════════════════════════════════════════

header :: Text
header =
  toText
    ( printf
        "%-15s %8s %8s %8s %8s %8s %8s"
        ("kind" :: String)
        ("total" :: String)
        ("unused" :: String)
        ("%" :: String)
        ("linear" :: String)
        ("%" :: String)
        ("multi%" :: String) ::
        String
    )

separator :: Text
separator = T.replicate 64 "─"

formatRow :: Text -> Bucket -> Text
formatRow label b =
  let total = bucketTotal b
      pct n
        | total == 0 = 0 :: Double
        | otherwise = 100 * fromIntegral n / fromIntegral total
   in toText
        ( printf
            "%-15s %8d %8d %7.1f%% %8d %7.1f%% %7.1f%%"
            (toString label)
            total
            b.bUnused
            (pct b.bUnused)
            b.bLinear
            (pct b.bLinear)
            (pct b.bMulti) ::
            String
        )
