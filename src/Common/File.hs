module Common.File (readFileTextUtf8) where

import Relude

{-# INLINE readFileTextUtf8 #-}
readFileTextUtf8 :: (MonadIO m, MonadFail m, ConvertUtf8 c ByteString) => FilePath -> m c
readFileTextUtf8 = readFileBS >=> (either (fail . show) pure . decodeUtf8Strict)
