{-# LANGUAGE TemplateHaskell #-}

-- | Compile-time-baked package version, read from the top-level @VERSION@ file
-- via Template Haskell. Replaces the auto-generated @Paths_awsum@ so absolute
-- build-directory paths don't leak into the binary. @just check-version-sync@
-- keeps @package.yaml@'s @version:@ aligned with @VERSION@.
module Awsum.Version (version) where

import Data.Char (isDigit)
import Data.Version (Version, makeVersion)
import Language.Haskell.TH (runIO)
import Language.Haskell.TH.Syntax (lift, qAddDependentFile)
import Prelude

version :: Version
version =
  makeVersion
    $( do
         qAddDependentFile "VERSION"
         contents <- runIO (readFile "VERSION")
         let digits = filter (\c -> isDigit c || c == '.') contents
             splitOn c s = case break (== c) s of
               (chunk, []) -> [chunk]
               (chunk, _ : rest) -> chunk : splitOn c rest
         lift (map read (splitOn '.' digits) :: [Int])
     )
