module Awsum.Format (formatSource) where

import Awsum.Parser
import Awsum.Render
import Relude

-- | Parse and re-render the source code to produce a formatted version.
formatSource :: Text -> Either Text Text
formatSource =
  fmap renderProgram . parseProgram
