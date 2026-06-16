-- | One source of truth for the column units the compiler's position
--   consumers need. The /display width/ count matches Megaparsec's own
--   source-position tracking (it advances two columns per 'isWideChar'), so a
--   'Awsum.Syntax.SrcSpan' column equals the display width of the text before
--   it on its line. The formatter ('Awsum.Render') aligns by the same count so
--   a re-parse lands on the same columns; 'awsum check' carets read the same
--   span columns. The /UTF-16/ count is the unit LSP @Position@ columns use —
--   'Awsum.Lsp' converts span columns to it (and incoming positions back) at
--   the protocol boundary, since a column in one unit can't be turned into
--   another without walking the source.
module Awsum.Width
  ( isWideChar,
    displayWidth,
    utf16Width,
    displayColToUtf16,
    utf16ColToDisplay,
  )
where

import Data.Text qualified as T
import Relude
import Text.Megaparsec.Unicode (isWideChar)

-- | Display width in terminal columns: a wide East-Asian character is two
--   columns, everything else one — the same per-character increment Megaparsec
--   applies to source columns.
displayWidth :: Text -> Int
displayWidth = T.foldl' (\n c -> n + charDisplay c) 0

charDisplay :: Char -> Int
charDisplay c = if isWideChar c then 2 else 1

-- | Width in UTF-16 code units: a code point above the BMP is two units,
--   everything else one — the unit LSP @Position@ columns use.
utf16Width :: Text -> Int
utf16Width = T.foldl' (\n c -> n + charUtf16 c) 0

charUtf16 :: Char -> Int
charUtf16 c = if ord c > 0xFFFF then 2 else 1

-- | Translate a 1-based /display/ column on @line@ (an Awsum span column) to
--   the 0-based UTF-16 offset LSP expects. Walks the line, so the result is
--   exact for any mix of narrow, wide, and supplementary characters; a column
--   past the end of the line clamps to the line's UTF-16 length.
displayColToUtf16 :: Text -> Int -> Int
displayColToUtf16 line col = go (col - 1) 0 (toString line)
  where
    go remaining acc cs
      | remaining <= 0 = acc
      | otherwise = case cs of
          [] -> acc
          (c : rest) -> go (remaining - charDisplay c) (acc + charUtf16 c) rest

-- | Inverse of 'displayColToUtf16': a 0-based UTF-16 offset (an incoming LSP
--   column) to the 1-based display column the parser's spans are measured in.
utf16ColToDisplay :: Text -> Int -> Int
utf16ColToDisplay line u = go u 1 (toString line)
  where
    go remaining col cs
      | remaining <= 0 = col
      | otherwise = case cs of
          [] -> col
          (c : rest) -> go (remaining - charUtf16 c) (col + charDisplay c) rest
