{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeFamilies #-}

-- | A Megaparsec 'Stream' over 'Text' whose source-position columns are
--   counted in /Unicode code points/ — one column per character — instead of
--   the /display width/ Megaparsec's built-in 'Text' stream uses (a wide
--   East-Asian character there advances two columns). One column unit, code
--   points, so the parser's layout (the offside rule, via @indentLevel@) and
--   every 'Awsum.Syntax.SrcSpan' column agree with the @tree-sitter-awsum@
--   scanner (whose @get_column@ counts code points) and with the renderer's
--   code-point layout — @parse ∘ render@ stays the identity and the grammar
--   parses every formatter output, even when a wide character precedes a
--   layout anchor.
--
--   The 'Stream' and 'VisualStream' instances delegate tokenisation to 'Text';
--   only 'TraversableStream' differs. Its @reachOffset@ / @reachOffsetNoLine@
--   are Megaparsec's own @reachOffset'@ / @reachOffsetNoLine'@ (BSD-3-Clause,
--   github.com/mrkkrp/megaparsec) specialised to this stream, with the column
--   advance set to @+1@ per character in place of the display-width @charInc@.
--   Megaparsec 9.7.0 does not export those helpers with a pluggable column
--   increment, hence the inline copy.
module Awsum.SrcStream (SrcText (..)) where

import Data.Text qualified as T
import Relude
import Text.Megaparsec.Pos (Pos, SourcePos (..), mkPos, pos1, unPos)
import Text.Megaparsec.State (PosState (..))
import Text.Megaparsec.Stream
  ( Stream (..),
    TraversableStream (..),
    VisualStream (..),
  )

-- | 'Text' tagged so that Megaparsec counts columns in code points.
newtype SrcText = SrcText {unSrcText :: Text}
  deriving stock (Eq, Ord, Show)

instance Stream SrcText where
  type Token SrcText = Char
  type Tokens SrcText = Text
  tokenToChunk Proxy = T.singleton
  tokensToChunk Proxy = toText
  chunkToTokens Proxy = toString
  chunkLength Proxy = T.length
  chunkEmpty Proxy = T.null
  take1_ (SrcText s) = second SrcText <$> T.uncons s
  takeN_ n (SrcText s)
    | n <= 0 = Just (T.empty, SrcText s)
    | T.null s = Nothing
    | otherwise = Just (second SrcText (T.splitAt n s))
  takeWhile_ p (SrcText s) = second SrcText (T.span p s)

instance VisualStream SrcText where
  showTokens Proxy = showTokens (Proxy :: Proxy Text)
  tokensLength Proxy = tokensLength (Proxy :: Proxy Text)

instance TraversableStream SrcText where
  reachOffset o PosState {..} =
    ( Just $ case expandTab pstateTabWidth
        . addPrefix
        . f
        . toString
        . fst
        $ takeWhile_ (/= '\n') post of
        "" -> "<empty line>"
        xs -> xs,
      PosState
        { pstateInput = post,
          pstateOffset = max pstateOffset o,
          pstateSourcePos = spos,
          pstateTabWidth = pstateTabWidth,
          pstateLinePrefix =
            if sameLine then pstateLinePrefix ++ f "" else f ""
        }
    )
    where
      addPrefix xs = if sameLine then pstateLinePrefix ++ xs else xs
      sameLine = sourceLine spos == sourceLine pstateSourcePos
      (pre, post) = splitSrc (o - pstateOffset) pstateInput
      St spos f = T.foldl' go (St pstateSourcePos id) pre
      go (St apos g) ch =
        let SourcePos n l c = apos
            c' = unPos c
            w = unPos pstateTabWidth
         in if
              | ch == '\n' -> St (SourcePos n (l <> pos1) pos1) id
              | ch == '\t' ->
                  St (SourcePos n l (mkPos $ c' + w - ((c' - 1) `rem` w))) (g . (ch :))
              | otherwise -> St (SourcePos n l (c <> pos1)) (g . (ch :))

  reachOffsetNoLine o PosState {..} =
    PosState
      { pstateInput = post,
        pstateOffset = max pstateOffset o,
        pstateSourcePos = spos,
        pstateTabWidth = pstateTabWidth,
        pstateLinePrefix = pstateLinePrefix
      }
    where
      spos = T.foldl' go pstateSourcePos pre
      (pre, post) = splitSrc (o - pstateOffset) pstateInput
      go (SourcePos n l c) ch =
        let c' = unPos c
            w = unPos pstateTabWidth
         in if
              | ch == '\n' -> SourcePos n (l <> pos1) pos1
              | ch == '\t' -> SourcePos n l (mkPos $ c' + w - ((c' - 1) `rem` w))
              | otherwise -> SourcePos n l (c <> pos1)

-- | An accumulator threading the running 'SourcePos' and the line-so-far
--   builder, as in Megaparsec's @reachOffset'@.
data St = St !SourcePos (String -> String)

-- | 'T.splitAt' with the residual side re-tagged as 'SrcText'.
splitSrc :: Int -> SrcText -> (Text, SrcText)
splitSrc n (SrcText t) = second SrcText (T.splitAt n t)

-- | Megaparsec's @expandTab@ (BSD-3-Clause): replace tabs with spaces so the
--   single source line shown in a parse-error caret lines up. Counting columns
--   in code points leaves this per-line tab-stop arithmetic unchanged.
expandTab :: Pos -> String -> String
expandTab w' = go 0 0
  where
    go _ 0 [] = []
    go i 0 ('\t' : xs) = go i (w - (i `rem` w)) xs
    go i 0 (x : xs) = x : go (i + 1) 0 xs
    go i n xs = ' ' : go (i + 1) (n - 1) xs
    w = unPos w'
