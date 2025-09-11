module Matchers (shouldMatchTextSnapshot, shouldMatchShowSnapshot, snapshotsDir) where

import Common.File
import Relude
import Test.Hspec.Golden
import Text.Pretty.Simple

snapshotsDir :: FilePath
snapshotsDir = ".snapshots/"

-- |
-- Note: we could have set it up to be `Golden a`,
-- Which would be more idiomatic,
-- But we want to compare pretty-printed snapshots not only in the test output,
-- But also in the golden files themselves and compare via Git.
-- And also we don't really want to deal with `Read` instances for `a`.
shouldMatchShowSnapshot :: (Show a) => a -> Text -> Golden Text
shouldMatchShowSnapshot actualOutput snapshotName =
  Golden
    { output = toText $ pShowNoColor actualOutput,
      encodePretty = toString,
      writeToFile = writeFileText,
      readFromFile = readFileTextUtf8,
      goldenFile = snapshotsDir <> toString snapshotName,
      actualFile = Nothing,
      failFirstTime = False
    }

shouldMatchTextSnapshot :: Text -> Text -> Golden Text
shouldMatchTextSnapshot actualOutput snapshotName =
  Golden
    { output = actualOutput,
      encodePretty = toString,
      writeToFile = writeFileText,
      readFromFile = readFileTextUtf8,
      goldenFile = snapshotsDir <> toString snapshotName,
      actualFile = Nothing,
      failFirstTime = False
    }
