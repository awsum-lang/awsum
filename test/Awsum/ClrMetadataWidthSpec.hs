-- | Tests for ECMA-335 metadata index widths in the CLR assembler
--   ('clrMetaWidths' + the @#~@ HeapSizes byte in 'Awsum.Codegen.CLR.Assemble').
--
--   The @.dll@ metadata indexes heaps (#Strings / #GUID / #Blob) and tables
--   with either 2- or 4-byte fields; the width is not free-form but derived per
--   §II.24.2.6 from the final heap sizes and row counts, and recorded (for the
--   heaps) in the @#~@ HeapSizes byte. Emitting every index as 2 bytes — the
--   former behaviour — silently corrupts any @.dll@ whose #Strings heap (all the
--   method / type names) outgrows 16-bit offsets: the loader reads a wrapped
--   name index and throws @TypeLoadException@, while the other four backends run
--   the same program. The boundary is a per-target detail of a format that
--   *supports* the wider encoding, so the fix widens rather than refuses (unlike
--   the JVM's hard u2 caps — see 'Awsum.JvmClassFileLimitSpec').
--
--   Two layers: the width logic on its boundary values (cheap, exhaustive), and
--   one ~64KB-#Strings program assembled and run on all five backends — the
--   #Strings stream is asserted past 0xFFFF and the HeapSizes bit set (so the
--   fixture genuinely exercises the 4-byte path), then identical stdout proves
--   the widened metadata loads.
module Awsum.ClrMetadataWidthSpec (spec) where

import Awsum.Codegen.CLR.Assemble (MetaWidths (..), assembleCLR, clrMetaWidths)
import Awsum.ElaborateLower (elaborateLowerProgram)
import Awsum.Parser (parseProgram)
import Awsum.Prelude (withPrelude)
import Awsum.Program (ProgramType (..))
import Awsum.RunBackend (backendName, compileFromText, runOnAll)
import Data.Bits (complement, shiftL, (.&.))
import Data.ByteString qualified as BS
import Data.Text qualified as T
import Relude
import Test.Hspec

spec :: Spec
spec = do
  widthBoundarySpec
  heapWideningSpec

-- ── Index-width boundary logic (pure) ────────────────────────────────────────

-- | 'clrMetaWidths' with every heap tiny and every table one row — the shape of
--   an ordinary program, where all widths are 2 bytes.
small :: MetaWidths
small = clrMetaWidths 1 16 1 1 1 1 1

widthBoundarySpec :: Spec
widthBoundarySpec = describe "clrMetaWidths (ECMA-335 §II.24.2.6 index widths)" $ do
  it "is all-2-byte, HeapSizes 0, for a small program" $ do
    [mwStr small, mwGuid small, mwBlob small] `shouldBe` [2, 2, 2]
    [mwField small, mwMethodDef small, mwParam small] `shouldBe` [2, 2, 2]
    [mwResScope small, mwTdor small, mwMrp small] `shouldBe` [2, 2, 2]
    mwHeapSizes small `shouldBe` 0

  describe "heap indices widen once the heap exceeds 0xFFFF bytes" $ do
    it "#Strings (HeapSizes bit 0x01)" $ do
      let lo = clrMetaWidths 0xFFFF 16 1 1 1 1 1
          hi = clrMetaWidths 0x10000 16 1 1 1 1 1
      (mwStr lo, mwHeapSizes lo .&. 0x01) `shouldBe` (2, 0)
      (mwStr hi, mwHeapSizes hi .&. 0x01) `shouldBe` (4, 0x01)

    it "#GUID (HeapSizes bit 0x02)" $ do
      let lo = clrMetaWidths 1 0xFFFF 1 1 1 1 1
          hi = clrMetaWidths 1 0x10000 1 1 1 1 1
      (mwGuid lo, mwHeapSizes lo .&. 0x02) `shouldBe` (2, 0)
      (mwGuid hi, mwHeapSizes hi .&. 0x02) `shouldBe` (4, 0x02)

    it "#Blob (HeapSizes bit 0x04)" $ do
      let lo = clrMetaWidths 1 16 0xFFFF 1 1 1 1
          hi = clrMetaWidths 1 16 0x10000 1 1 1 1
      (mwBlob lo, mwHeapSizes lo .&. 0x04) `shouldBe` (2, 0)
      (mwBlob hi, mwHeapSizes hi .&. 0x04) `shouldBe` (4, 0x04)

  describe "simple table indices widen once the table reaches 2^16 rows" $ do
    it "MethodDef (TypeDef.MethodList)" $ do
      mwMethodDef (clrMetaWidths 1 16 1 1 0xFFFF 1 1) `shouldBe` 2
      mwMethodDef (clrMetaWidths 1 16 1 1 0x10000 1 1) `shouldBe` 4

    it "Param (MethodDef.ParamList)" $ do
      mwParam (clrMetaWidths 1 16 1 1 1 0xFFFF 1) `shouldBe` 2
      mwParam (clrMetaWidths 1 16 1 1 1 0x10000 1) `shouldBe` 4

  describe "coded indices widen at 2^(16 - tagBits) rows of their largest table" $ do
    it "MemberRefParent (3 tag bits → 0x2000) tracks the MethodDef row count" $ do
      mwMrp (clrMetaWidths 1 16 1 1 0x1FFF 1 1) `shouldBe` 2
      mwMrp (clrMetaWidths 1 16 1 1 0x2000 1 1) `shouldBe` 4

    it "TypeDefOrRef (2 tag bits → 0x4000) tracks the TypeSpec row count" $ do
      mwTdor (clrMetaWidths 1 16 1 1 1 1 0x3FFF) `shouldBe` 2
      mwTdor (clrMetaWidths 1 16 1 1 1 1 0x4000) `shouldBe` 4

    it "ResolutionScope (2 tag bits → 0x4000) tracks the TypeRef row count" $ do
      mwResScope (clrMetaWidths 1 16 1 0x3FFF 1 1 1) `shouldBe` 2
      mwResScope (clrMetaWidths 1 16 1 0x4000 1 1 1) `shouldBe` 4

-- ── #Strings heap past 64KB (integration + behaviour) ─────────────────────────

-- | Function count for the over-64KB-#Strings fixture. Each function's ~123-byte
--   name costs ~128 #Strings bytes, so 600 lands the heap near ~76KB — clear of
--   the 65536-byte boundary with margin against codegen drift. The assertions
--   below pin that the heap really crosses it, so if drift ever shrinks it below,
--   the test fails loudly (bump this) rather than silently skipping the path.
bigProgramFnCount :: Int
bigProgramFnCount = 600

-- | @n@ recursive single-argument functions @f1 … fn@ with long names, chained
--   @fi 0 = f(i+1) 0@ down to @fn 0 = "end"@; recursion (the @Right m -> fi m@
--   arm) keeps each a separate method (Simplify never inlines a 'CLoop' and the
--   recursive call blocks const-folding the chain), so all @n@ names land in the
--   #Strings heap. @main@ prints @f1 0@, i.e. @"end"@.
mkBigProgram :: Int -> Text
mkBigProgram n =
  unlines
    $ ["import IO.Stdout", ""]
    <> concatMap fn [1 .. n]
    <> ["main : IO Never Unit", "main = IO.Stdout.print (" <> nm 1 <> " 0)"]
  where
    nm :: Int -> Text
    nm i = "fn" <> T.replicate 120 "X" <> show i
    fn i =
      [ nm i <> " : Int32 -> String",
        nm i <> " n = case eqInt32 n 0 of",
        if i < n then "  True -> " <> nm (i + 1) <> " 0" else "  True -> \"end\"",
        "  False -> case predInt32 n of",
        "    Left _e -> \"L\"",
        "    Right m -> " <> nm i <> " m",
        ""
      ]

-- | Parse → withPrelude → elaborate → assemble CLR bytes. Failures are test bugs
--   (the source is generated), so they 'error'.
assembleProgram :: Text -> ByteString
assembleProgram src =
  case parseProgram src of
    Left e -> error ("parse failed: " <> e)
    Right prog -> case elaborateLowerProgram ProgramCli (withPrelude prog) of
      Left err -> error ("elaborate failed: " <> show err)
      Right (_warns, ptags, core) -> assembleCLR ptags core

-- | The @#~@ HeapSizes byte and the #Strings stream size, read from a @.dll@'s
--   metadata root (§II.24.2.1): locate the @BSJB@ signature, skip the padded
--   version string to the stream-header list, then walk the headers.
parseMeta :: ByteString -> (Word8, Int)
parseMeta dll =
  let root = BS.length (fst (BS.breakSubstring (BS.pack [0x42, 0x53, 0x4A, 0x42]) dll))
      le16 off = fromIntegral (BS.index dll off) + (fromIntegral (BS.index dll (off + 1)) `shiftL` 8)
      le32 off = sum [fromIntegral (BS.index dll (off + i)) `shiftL` (8 * i) | i <- [0 .. 3]]
      align4 x = (x + 3) .&. complement 3
      versionLen = le32 (root + 12)
      streamCountOff = root + 16 + versionLen + 2
      nStreams = le16 streamCountOff
      collect 0 _ = []
      collect k p =
        let nameStart = p + 8
            nameLen = BS.length (BS.takeWhile (/= 0) (BS.drop nameStart dll))
            name = decodeUtf8 (BS.take nameLen (BS.drop nameStart dll)) :: Text
         in (name, le32 p, le32 (p + 4)) : collect (k - 1 :: Int) (align4 (nameStart + nameLen + 1))
      streams = collect nStreams (streamCountOff + 2)
      streamOf nm = listToMaybe [(o, s) | (n, o, s) <- streams, n == nm]
      tildeOff = maybe (error "parseMeta: no #~ stream") fst (streamOf "#~")
      strSize = maybe (error "parseMeta: no #Strings stream") snd (streamOf "#Strings")
   in (BS.index dll (root + tildeOff + 6), strSize)

heapWideningSpec :: Spec
heapWideningSpec = describe "#~ HeapSizes widens to 4-byte indices past the 64KB #Strings boundary" $ do
  it "records the #Strings 4-byte bit in the metadata it emits" $ do
    let (heapSizes, strSize) = parseMeta (assembleProgram (mkBigProgram bigProgramFnCount))
    strSize `shouldSatisfy` (> 0xFFFF) -- fixture really crosses the boundary
    (heapSizes .&. 0x01) `shouldBe` 0x01 -- and #Strings indices are emitted 4-byte
  it "runs identically on all five backends (CLR no longer corrupts the .dll)" $ do
    arts <- compileFromText (mkBigProgram bigProgramFnCount)
    results <- runOnAll arts ""
    let failures = [(backendName b, err) | (b, Left err) <- results]
    failures `shouldBe` []
    forM_ results $ \(b, r) -> case r of
      Left _ -> pass -- already reported above
      Right out -> (backendName b, T.strip out) `shouldBe` (backendName b, "end")
