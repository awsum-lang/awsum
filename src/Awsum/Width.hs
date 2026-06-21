-- | Column-unit conversion at the LSP boundary. The compiler tracks source
--   positions in /code points/ — one column per character, the unit
--   "Awsum.SrcStream" makes the parser count and the formatter ('Awsum.Render')
--   aligns by, so an 'Awsum.Syntax.SrcSpan' column equals the number of
--   characters before it on its line, and 'awsum check' carets read the same
--   span columns. LSP @Position@ columns are /UTF-16 code units/; 'Awsum.Lsp'
--   converts span columns to that unit (and incoming positions back) at the
--   protocol boundary, since a column in one unit can't be turned into another
--   without walking the source line.
module Awsum.Width
  ( codePointColToUtf16,
    utf16ColToCodePoint,
  )
where

import Relude

-- | UTF-16 code units a single code point occupies: two above the BMP
--   (a surrogate pair), one otherwise.
charUtf16 :: Char -> Int
charUtf16 c = if ord c > 0xFFFF then 2 else 1

-- | Translate a 1-based /code-point/ column on @line@ (an Awsum span column) to
--   the 0-based UTF-16 offset LSP expects. Walks the line, so the result is
--   exact for any mix of BMP and supplementary characters; a column past the
--   end of the line clamps to the line's UTF-16 length.
codePointColToUtf16 :: Text -> Int -> Int
codePointColToUtf16 line col = go (col - 1) 0 (toString line)
  where
    go remaining acc cs
      | remaining <= 0 = acc
      | otherwise = case cs of
          [] -> acc
          (c : rest) -> go (remaining - 1) (acc + charUtf16 c) rest

-- | Inverse of 'codePointColToUtf16': a 0-based UTF-16 offset (an incoming LSP
--   column) to the 1-based code-point column the parser's spans are measured in.
utf16ColToCodePoint :: Text -> Int -> Int
utf16ColToCodePoint line u = go u 1 (toString line)
  where
    go remaining col cs
      | remaining <= 0 = col
      | otherwise = case cs of
          [] -> col
          (c : rest) -> go (remaining - charUtf16 c) (col + 1) rest
