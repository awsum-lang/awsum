-- | Discovery of test-source directories, shared by the snapshot and
-- property suites, with a built-in sweep of orphaned scaffolding.
--
-- Every test-source directory holds its program at @code/Main.aww@. A
-- subdirectory of a sources root that lacks that file is not a test —
-- it is an empty husk a branch switch or other git move left behind
-- (git records no empty directories, so removing the source can strand
-- the directories above it). Discovery deletes such husks rather than
-- stumble over them on every run — reading the absent @Main.aww@ would
-- abort the suite — or let them accumulate.
module TestSources (discoverTestDirs, pruneOrphanTestDirs) where

import Relude
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory, removeDirectoryRecursive)
import System.FilePath ((</>))

-- | Immediate subdirectories of @root@ that hold a @code/Main.aww@,
-- sorted. A subdirectory missing that file is removed (recursively)
-- and excluded from the result — see the module header.
discoverTestDirs :: FilePath -> IO [FilePath]
discoverTestDirs root = do
  entries <- listDirectory root
  subdirs <- filterM (\e -> doesDirectoryExist (root </> e)) entries
  sort <$> filterM keepOrPrune subdirs
  where
    keepOrPrune :: FilePath -> IO Bool
    keepOrPrune name = do
      hasCode <- doesFileExist (root </> name </> "code" </> "Main.aww")
      unless hasCode $ removeDirectoryRecursive (root </> name)
      pure hasCode

-- | Delete the orphaned directories under @root@ without collecting the
-- survivors. For a suite that enumerates its cases from a hard-coded
-- catalogue (the property suite) rather than from the directory listing,
-- yet should still not leave husks behind.
pruneOrphanTestDirs :: FilePath -> IO ()
pruneOrphanTestDirs = void . discoverTestDirs
