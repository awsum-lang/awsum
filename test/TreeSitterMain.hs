-- | Entrypoint for the `tree-sitter-tests` test-suite — runs the
-- `tree-sitter-awsum` integration spec and nothing else. Built only
-- when the cabal flag `tree-sitter-tests` is enabled (see
-- `package.yaml`); the default-off ensures CI's `just test` /
-- `just test-property` don't pull this suite or its `tree-sitter`
-- CLI dependency.
module TreeSitterMain (main) where

import Awsum.ArbitraryInstances ()
import Awsum.TreeSitterSpec qualified
import GHC.IO.Encoding (setLocaleEncoding, utf8)
import Relude
import Test.Hspec

main :: IO ()
main = do
  -- Same UTF-8 encoding fix as the main test suite — hspec's
  -- printer crashes on non-ASCII glyphs without it on Windows
  -- consoles.
  setLocaleEncoding utf8
  hspec Awsum.TreeSitterSpec.spec
