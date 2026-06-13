-- | Property-based tests across all five runtimes. Compiles each
-- property's Awsum source once, then feeds N constructively-generated
-- inputs through every backend, asserting that stdout is identical
-- to a value the Haskell side computes independently.
--
-- Two interaction styles are supported by the same framework:
--   * `OK` / `FAIL` — Awsum verifies the property internally and prints
--     a fixed marker; `propExpectedOutput = const "OK"`. Used for
--     integer arithmetic / equality properties where Awsum can decide
--     equality on its own.
--   * round-trip / direct compute — Awsum computes a value and prints
--     it; `propExpectedOutput` recomputes the same value Haskell-side
--     and asserts the two stdouts are identical. Used for string
--     properties where Awsum has no `eqString` builtin yet.
--
-- The generators are constructive (no-overflow on integer ops,
-- disjoint alphabets where uniqueness matters) so the inputs that
-- reach each backend are valid for the property under test by
-- construction.
module Awsum.PropertySpec (spec) where

import Awsum.RunBackend (Backend, CompiledArtifacts, SimplifyMode (..), compileFromFile, compileFromFileWith, compileFromText, compileFromTextWith, runOnAllStdinBytes)
import Data.ByteString qualified as BS
import Data.Text qualified as T
import Numeric (showHex)
import Relude
import System.FilePath ((</>))
import Test.Hspec
import Test.Hspec.QuickCheck (modifyMaxSuccess, prop)
import Test.QuickCheck (Arbitrary (..), Gen, chooseBoundedIntegral, chooseInteger, counterexample, elements, forAll, frequency, ioProperty, listOf, listOf1)
import Test.QuickCheck qualified as QC
import TestSources (pruneOrphanTestDirs)

-- ════════════════════════════════════════════════════════════════════════════
-- Framework
-- ════════════════════════════════════════════════════════════════════════════

type role Property representational

data Property a = Property
  { propName :: Text,
    -- | Subdirectory under @test/sources/property/@ that holds @code/Main.aww@.
    propSourceDir :: FilePath,
    propGen :: Gen a,
    -- | Render the generated value as the @argv[1]@ Awsum will receive.
    propEncode :: a -> Text,
    -- | Compute, on the Haskell side, the stdout the Awsum program is
    --   expected to produce for this exact input. The comparison
    --   requires the two strings to be identical.
    propExpectedOutput :: a -> Text
  }

data SomeProperty = forall a. (Show a) => SomeProperty (Property a)

propertyRoot :: FilePath
propertyRoot = "test/sources/property"

propertySourceFile :: FilePath -> FilePath
propertySourceFile dir = propertyRoot </> dir </> "code" </> "Main.aww"

spec :: Spec
spec = describe "Property tests"
  -- Sibling property descriptions run in parallel — with N properties
  -- and M hspec workers (default = number of cores) up to M run at
  -- once. Compiles still happen at spec-build time via 'runIO', which
  -- is sequential, but that's a small overhead (one @clang@ per
  -- property at ~100ms) compared to 100 input runs × 5 backends each.
  $ parallel
  $ modifyMaxSuccess (const 100)
  $ do
    -- Sweep orphaned husks (a directory with no code/Main.aww, stranded by
    -- a git move) before compiling. This suite drives itself from the
    -- hard-coded 'properties' catalogue, so an orphan is never referenced —
    -- but it shouldn't linger either.
    runIO (pruneOrphanTestDirs propertyRoot)
    forM_ properties $ \(SomeProperty p) ->
      describe (toString p.propName) $ do
        arts <- runIO (compileBothModes (propertySourceFile p.propSourceDir))
        prop "holds on every backend" (runProperty arts p)
    -- Byte-level stdin properties — these feed arbitrary 'ByteString's a
    -- 'Text' could not hold, so they sit outside the 'Property a' record.
    byteStdinProperty "readAllBytes-roundtrip" "readallbytes-roundtrip" hexOf
    byteStdinProperty "readAllString-strict-decode" "readallstring-strict-decode" expectedStrictDecode
    -- Fixed-input guard: 'genStdinBytes' almost never begins with the exact
    -- 3-byte UTF-8 BOM, so the leading-BOM divergence stays invisible to the
    -- random property above. This pins it deterministically.
    leadingBomPreserved
    -- The random stdin inputs stay under the 4096-byte initial read buffer, so
    -- the grow path (and the buffer free on grow) is otherwise unexercised.
    stdinGrowPathReclaimed
    -- Const-fold differential: literals live in the generated *source*, so
    -- 'Awsum.Simplify' evaluates them at compile time — unlike every property
    -- above, whose inputs arrive at runtime and never fold.
    constFoldDifferentialSpec
    -- Function-inlining differential: generated helper chains exercising
    -- every argument-binding shape of the inliner, seeded with a runtime
    -- value so the inlined code actually executes on the SimplifyOn leg.
    fnInlineDifferentialSpec
    -- Case-of-case differential: generated boolean towers over a runtime
    -- seed — fusion collapses them (and mints joins on the mixed-arm legs)
    -- on the SimplifyOn leg, while the Off leg dispatches every level at
    -- runtime; both must match the Haskell oracle.
    caseOfCaseDifferentialSpec
    -- Reuse-sharing differential: generated sharing topologies (retained /
    -- linear / same-cell-twice / top-level-definition / diamond) fed
    -- through a reuse-shaped consuming loop, with the retained parts read
    -- back *after* the loop — the probe that makes an in-place overwrite
    -- of a still-reachable cell visible in stdout. Both Simplify modes ×
    -- five backends against the Haskell oracle ('Awsum.Lifetime' and
    -- 'Awsum.Reuse' run on the Off leg too, so raw shapes are covered).
    reuseSharingDifferentialSpec

-- | A property whose input is raw stdin bytes (possibly malformed UTF-8):
--   generate a byte sequence, feed it to every backend, and assert all five
--   emit the @oracle@'s stdout. The generator mixes valid UTF-8 (encoded
--   from valid Unicode text) with arbitrary bytes so both the decode-success
--   and decode-failure paths are exercised.
byteStdinProperty :: Text -> FilePath -> (ByteString -> Text) -> Spec
byteStdinProperty name dir oracle =
  describe (toString name) $ do
    arts <- runIO (compileBothModes (propertySourceFile dir))
    prop "holds on every backend"
      $ forAll genStdinBytes
      $ \bs -> ioProperty $ do
        results <- runBothStdinBytes arts bs
        let expected = oracle bs
        pure
          $ counterexample (toString (formatFailure (hexOf bs) expected results))
          $ allMatch expected results

-- | Fixed regression for 'readAllString': a leading UTF-8 BOM (@EF BB BF@,
--   U+FEFF) is a valid scalar that every backend must echo verbatim. The
--   strict oracle ('decodeUtf8'') keeps it and so do the four hand-written
--   decoders; Node's 'TextDecoder' keeps it only with @ignoreBOM: true@,
--   without which a leading BOM is silently dropped — an identical-stdout
--   break the random 'genStdinBytes' arms never surface (they essentially
--   never start with the exact 3-byte BOM).
leadingBomPreserved :: Spec
leadingBomPreserved =
  describe "readAllString-leading-BOM" $ do
    arts <- runIO (compileBothModes (propertySourceFile "readallstring-strict-decode"))
    it "keeps a leading UTF-8 BOM on every backend" $ do
      let input = BS.pack [0xEF, 0xBB, 0xBF] <> encodeUtf8 ("hi" :: Text)
          expected = expectedStrictDecode input
      results <- runBothStdinBytes arts input
      unless (T.isPrefixOf "\xFEFF" expected)
        $ expectationFailure "strict oracle dropped the BOM — regression test is mis-set-up"
      unless (allMatch expected results)
        $ expectationFailure (toString (formatFailure (hexOf input) expected results))

-- | Fixed regression for the stdin read-buffer grow path. The small random
--   'genStdinBytes' inputs stay under the 4096-byte initial buffer, so the
--   doubling-and-copy path — and the buffer free added alongside it — is
--   otherwise never run. A >8 KiB input forces two grows; the read/grow/free
--   logic is shared by both readers, so 'readAllString' exercises it cheaply
--   (no O(n^2) hex). The decoded echo must be byte-exact on every backend.
stdinGrowPathReclaimed :: Spec
stdinGrowPathReclaimed =
  describe "readAllString-grow-path" $ do
    arts <- runIO (compileBothModes (propertySourceFile "readallstring-strict-decode"))
    it "decodes a >8 KiB stream (forces buffer growth) on every backend" $ do
      let input = BS.replicate 9000 0x61 -- 9000 'a': valid UTF-8, two grows (4096 -> 8192 -> 16384)
          expected = expectedStrictDecode input
      results <- runBothStdinBytes arts input
      unless (allMatch expected results)
        $ expectationFailure (toString (formatFailure "9000 x 0x61" expected results))

-- | Stdin byte generator: a mix of valid UTF-8 (so the decode-success path
--   runs) and arbitrary bytes (so the malformed path runs).
genStdinBytes :: Gen ByteString
genStdinBytes =
  frequency
    [ (2, encodeUtf8 <$> genUtf16Str),
      (2, BS.pack <$> listOf (chooseBoundedIntegral (0, 255))),
      (1, (BS.append . encodeUtf8 <$> genUtf16Str) <*> (BS.pack <$> listOf (chooseBoundedIntegral (0, 255))))
    ]

-- | Lowercase, zero-padded, no-prefix hex of a byte string — the oracle for
--   the @readAllBytes@ round-trip (matches @bytesToHexStringNoPrefix@).
hexOf :: ByteString -> Text
hexOf bs = T.concat [T.justifyRight 2 '0' (toText (showHex b "")) | b <- BS.unpack bs]

-- | Strict-UTF-8 oracle for @readAllString@: a well-formed byte sequence
--   decodes to its 'Text' (echoed verbatim); a malformed one yields the
--   @INVALID_UTF8@ marker. The length cap is unreachable for test-sized
--   inputs, so @STRING_TOO_LONG@ never appears here.
expectedStrictDecode :: ByteString -> Text
expectedStrictDecode bs = case decodeUtf8' bs of
  Right t -> t
  Left _ -> "INVALID_UTF8"

-- | Compile one property source in both pipeline modes: the shipped
--   'SimplifyOn' artifacts plus a 'SimplifyOff' twin. Every property runs
--   each generated input through both (see 'runBothStdinBytes'), so an
--   'Awsum.Simplify' rewrite that bends behaviour uniformly across the
--   five backends still has to disagree with the Haskell oracle.
compileBothModes :: FilePath -> IO (CompiledArtifacts, CompiledArtifacts)
compileBothModes path =
  (,) <$> compileFromFile path <*> compileFromFileWith SimplifyOff path

-- | Feed one input to all five backends in both pipeline modes — ten
--   results, labelled @Backend@ / @Backend [no-simplify]@.
runBothStdinBytes :: (CompiledArtifacts, CompiledArtifacts) -> ByteString -> IO [(Text, Either Text Text)]
runBothStdinBytes (artsOn, artsOff) input = do
  rOn <- runOnAllStdinBytes artsOn input
  rOff <- runOnAllStdinBytes artsOff input
  pure (labelled "" rOn <> labelled " [no-simplify]" rOff)
  where
    labelled :: Text -> [(Backend, Either Text Text)] -> [(Text, Either Text Text)]
    labelled suffix = map (\(b, r) -> (show b <> suffix, r))

runProperty :: (Show a) => (CompiledArtifacts, CompiledArtifacts) -> Property a -> QC.Property
runProperty arts p =
  forAll p.propGen $ \a -> ioProperty $ do
    let input = p.propEncode a
        expected = p.propExpectedOutput a
    results <- runBothStdinBytes arts (encodeUtf8 input)
    pure
      $ counterexample (toString (formatFailure input expected results))
      $ allMatch expected results

allMatch :: Text -> [(Text, Either Text Text)] -> Bool
allMatch expected = all $ \(_, r) -> case r of
  Right out -> out == expected
  Left _ -> False

formatFailure :: Text -> Text -> [(Text, Either Text Text)] -> Text
formatFailure input expected results =
  unlines
    $ ["input:    " <> show input, "expected: " <> show expected, "results:"]
    <> ["  " <> b <> ": " <> formatRaw r | (b, r) <- results]
  where
    formatRaw :: Either Text Text -> Text
    formatRaw (Right o)
      | o == expected = "OK"
      | otherwise = "GOT " <> show o
    formatRaw (Left e) = "ERROR " <> show e

-- ════════════════════════════════════════════════════════════════════════════
-- Generators
-- ════════════════════════════════════════════════════════════════════════════

-- ── Integer ──

newtype NoOverflowAddInt32 = NoOverflowAddInt32 (Int32, Int32) deriving stock (Show)

instance Arbitrary NoOverflowAddInt32 where
  arbitrary = do
    a <- chooseBoundedIntegral (minBound :: Int32, maxBound :: Int32)
    let aI = toInteger a
        loI = max (toInteger (minBound :: Int32)) (toInteger (minBound :: Int32) - aI)
        hiI = min (toInteger (maxBound :: Int32)) (toInteger (maxBound :: Int32) - aI)
    bI <- chooseInteger (loI, hiI)
    pure (NoOverflowAddInt32 (a, fromInteger bI))

newtype Int32V = Int32V Int32 deriving stock (Show)

instance Arbitrary Int32V where
  arbitrary = Int32V <$> chooseBoundedIntegral (minBound, maxBound)

newtype NonMinInt32 = NonMinInt32 Int32 deriving stock (Show)

instance Arbitrary NonMinInt32 where
  arbitrary = NonMinInt32 <$> chooseBoundedIntegral (minBound + 1, maxBound)

newtype NonMaxInt32 = NonMaxInt32 Int32 deriving stock (Show)

instance Arbitrary NonMaxInt32 where
  arbitrary = NonMaxInt32 <$> chooseBoundedIntegral (minBound, maxBound - 1)

newtype Word8V = Word8V Word8 deriving stock (Show)

instance Arbitrary Word8V where
  arbitrary = Word8V <$> chooseBoundedIntegral (0, 255)

newtype Word32V = Word32V Word32 deriving stock (Show)

instance Arbitrary Word32V where
  arbitrary = Word32V <$> chooseBoundedIntegral (minBound, maxBound)

-- | (a, b) where @a * b@ stays in Int32 range. Pick @a@ uniformly,
--   then @b@ from the no-overflow interval — for @a == 0@ the
--   product is always 0 so the full range is OK; otherwise the
--   bounds are @floor(maxInt32 / |a|)@ on each side, with the lower
--   side flipped sign-wise. The @|a| == 1@ corner is also fine since
--   any b fits then. Constructive — no rejection sampling.
newtype NoOverflowMulInt32 = NoOverflowMulInt32 (Int32, Int32) deriving stock (Show)

instance Arbitrary NoOverflowMulInt32 where
  arbitrary = do
    a <- chooseBoundedIntegral (minBound :: Int32, maxBound :: Int32)
    let aI = toInteger a
        minI = toInteger (minBound :: Int32)
        maxI = toInteger (maxBound :: Int32)
        -- The set of valid b values is { b ∈ Int32 | minInt32 ≤ a*b ≤ maxInt32 }.
        -- For a == 0, every b qualifies. For a > 0:
        --   a*b ≤ maxInt32 ⇒ b ≤ floor(maxInt32 / a)
        --   a*b ≥ minInt32 ⇒ b ≥ ceil(minInt32 / a) = -floor(maxInt32 / a) - 1
        --     wait: minInt32 / a where a > 0 may not divide evenly; use
        --     -((|minInt32|) `div` a) which equals -((maxInt32+1) / a) but
        --     since we only need a *valid* lower bound (not the tightest),
        --     -(maxInt32 `div` a) is safe and the interval still contains 0.
        --   So: b ∈ [-floor(maxInt32/a), floor(maxInt32/a)].
        -- For a < 0: symmetric — same bounds in absolute value.
        absA = abs aI
        bound = if absA == 0 then maxI else maxI `div` absA
        loI = max minI (negate bound)
        hiI = min maxI bound
    bI <- chooseInteger (loI, hiI)
    pure (NoOverflowMulInt32 (a, fromInteger bI))

-- | (a, b, c) such that @a*b@, @b*c@ and @a*b*c@ all fit in Int32.
--   Mirrors 'NoOverflowMulUInt8Triple' on signed bounds: same lesson —
--   under overflow-checked arithmetic the two associativity groupings
--   @(a*b)*c@ and @a*(b*c)@ are not interchangeable, so the generator
--   has to bound every intermediate product.
--
--   Pick @a@ uniformly. Then @b@ from @[-bA, bA]@ with
--   @bA = maxI / max(1, |a|)@, ensuring @|a*b| ≤ maxI@. Then @c@ from
--   the intersection of:
--     * @|b*c| ≤ maxI@: @c ∈ [-bB, bB]@ with @bB = maxI / max(1, |b|)@
--     * @|a*b*c| ≤ maxI@: @c ∈ [-bAB, bAB]@ with @bAB = maxI / max(1, |a*b|)@
--   Each interval contains 0 (and 1), so the intersection is non-empty
--   — no rejection sampling. @a == minInt32@ degenerates to
--   @b = c = 0@ since @|a| > maxI@ forces @bA = 0@.
newtype NoOverflowMulInt32Triple = NoOverflowMulInt32Triple (Int32, Int32, Int32) deriving stock (Show)

instance Arbitrary NoOverflowMulInt32Triple where
  arbitrary = do
    a <- chooseBoundedIntegral (minBound :: Int32, maxBound :: Int32)
    let aI = toInteger a
        maxI = toInteger (maxBound :: Int32)
        bA = maxI `div` max 1 (abs aI)
    bI <- chooseInteger (negate bA, bA)
    let abI = aI * bI
        bB = maxI `div` max 1 (abs bI)
        bAB = maxI `div` max 1 (abs abI)
        cBound = min bB bAB
    cI <- chooseInteger (negate cBound, cBound)
    pure (NoOverflowMulInt32Triple (a, fromInteger bI, fromInteger cI))

-- | (a, b, c) such that @b + c@, @a * b@, @a * c@ and @a * (b + c)@
--   are all in Int32 range. This is the joint domain on which the
--   distributivity law @a * (b + c) == a * b + a * c@ is well-
--   defined under honest arithmetic.
--
--   The construction picks @a@ uniformly, then conservatively bounds
--   @b@ and @c@ to half the per-multiplication budget so that
--   @b + c@ also stays in the no-overflow product range. With
--   @bound = maxInt32 / max(|a|, 1)@ and @b, c ∈ [-bound/2, bound/2]@,
--   we have @|b + c| ≤ bound@ ⇒ @|a * (b + c)| ≤ maxInt32@, plus
--   each individual @|a * b|, |a * c| ≤ maxInt32 / 2 ≤ maxInt32@.
--   Each interval contains 0, so no rejection sampling is needed.
newtype NoOverflowMulDistribInt32 = NoOverflowMulDistribInt32 (Int32, Int32, Int32) deriving stock (Show)

instance Arbitrary NoOverflowMulDistribInt32 where
  arbitrary = do
    a <- chooseBoundedIntegral (minBound :: Int32, maxBound :: Int32)
    let aI = toInteger a
        maxI = toInteger (maxBound :: Int32)
        absA = max 1 (abs aI)
        bound = maxI `div` absA
        half = bound `div` 2
    bI <- chooseInteger (negate half, half)
    cI <- chooseInteger (negate half, half)
    pure (NoOverflowMulDistribInt32 (a, fromInteger bI, fromInteger cI))

-- | (a, b) where roughly 20 % of the time b == a, the rest random. Used
--   for symmetry / reflexivity properties where the @True@ branch of
--   equality would never be exercised by uniform sampling alone.
newtype Int32MaybeEqualPair = Int32MaybeEqualPair (Int32, Int32) deriving stock (Show)

instance Arbitrary Int32MaybeEqualPair where
  arbitrary = do
    a <- chooseBoundedIntegral (minBound, maxBound)
    b <-
      frequency
        [ (1, pure a),
          (4, chooseBoundedIntegral (minBound, maxBound))
        ]
    pure (Int32MaybeEqualPair (a, b))

newtype Word8MaybeEqualPair = Word8MaybeEqualPair (Word8, Word8) deriving stock (Show)

instance Arbitrary Word8MaybeEqualPair where
  arbitrary = do
    a <- chooseBoundedIntegral (0, 255)
    b <-
      frequency
        [ (1, pure a),
          (4, chooseBoundedIntegral (0, 255))
        ]
    pure (Word8MaybeEqualPair (a, b))

newtype Word32MaybeEqualPair = Word32MaybeEqualPair (Word32, Word32) deriving stock (Show)

instance Arbitrary Word32MaybeEqualPair where
  arbitrary = do
    a <- chooseBoundedIntegral (minBound, maxBound)
    b <-
      frequency
        [ (1, pure a),
          (4, chooseBoundedIntegral (minBound, maxBound))
        ]
    pure (Word32MaybeEqualPair (a, b))

-- | Int32 with @maxBound@ favoured (~9 %). Used for boundary tests
--   where the failure case (succ at max) would otherwise never be hit
--   by a uniform sample.
newtype Int32WithMaxFavored = Int32WithMaxFavored Int32 deriving stock (Show)

instance Arbitrary Int32WithMaxFavored where
  arbitrary =
    Int32WithMaxFavored
      <$> frequency
        [ (1, pure maxBound),
          (10, chooseBoundedIntegral (minBound, maxBound))
        ]

newtype Int32WithMinFavored = Int32WithMinFavored Int32 deriving stock (Show)

instance Arbitrary Int32WithMinFavored where
  arbitrary =
    Int32WithMinFavored
      <$> frequency
        [ (1, pure minBound),
          (10, chooseBoundedIntegral (minBound, maxBound))
        ]

newtype Word8WithMaxFavored = Word8WithMaxFavored Word8 deriving stock (Show)

instance Arbitrary Word8WithMaxFavored where
  arbitrary =
    Word8WithMaxFavored
      <$> frequency
        [ (1, pure 255),
          (10, chooseBoundedIntegral (0, 255))
        ]

newtype Word8WithMinFavored = Word8WithMinFavored Word8 deriving stock (Show)

instance Arbitrary Word8WithMinFavored where
  arbitrary =
    Word8WithMinFavored
      <$> frequency
        [ (1, pure 0),
          (10, chooseBoundedIntegral (0, 255))
        ]

newtype Word32WithMaxFavored = Word32WithMaxFavored Word32 deriving stock (Show)

instance Arbitrary Word32WithMaxFavored where
  arbitrary =
    Word32WithMaxFavored
      <$> frequency
        [ (1, pure maxBound),
          (10, chooseBoundedIntegral (minBound, maxBound))
        ]

newtype Word32WithMinFavored = Word32WithMinFavored Word32 deriving stock (Show)

instance Arbitrary Word32WithMinFavored where
  arbitrary =
    Word32WithMinFavored
      <$> frequency
        [ (1, pure 0),
          (10, chooseBoundedIntegral (minBound, maxBound))
        ]

newtype NoOverflowAddUInt8 = NoOverflowAddUInt8 (Word8, Word8) deriving stock (Show)

instance Arbitrary NoOverflowAddUInt8 where
  arbitrary = do
    a <- chooseBoundedIntegral (0 :: Word8, 255)
    b <- chooseBoundedIntegral (0, 255 - a)
    pure (NoOverflowAddUInt8 (a, b))

-- | (a, b) where @a - b@ stays in Int32 range AND @b ≠ minInt32@. The
--   second constraint is necessary for properties that evaluate
--   @negInt32 b@ — that call fails on @minInt32@. Constructive sampling:
--   pick @a@ uniformly, then @b@ from the intersection of the
--   no-overflow interval @[a - maxInt32, a - minInt32]@ and the
--   non-minBound interval @[minInt32 + 1, maxInt32]@. The intersection
--   always contains 0 for any @a@, so it is non-empty.
newtype NoOverflowSubInt32NonMinB = NoOverflowSubInt32NonMinB (Int32, Int32) deriving stock (Show)

instance Arbitrary NoOverflowSubInt32NonMinB where
  arbitrary = do
    a <- chooseBoundedIntegral (minBound :: Int32, maxBound :: Int32)
    let aI = toInteger a
        minI = toInteger (minBound :: Int32)
        maxI = toInteger (maxBound :: Int32)
        loI = max (minI + 1) (aI - maxI)
        hiI = min maxI (aI - minI)
    bI <- chooseInteger (loI, hiI)
    pure (NoOverflowSubInt32NonMinB (a, fromInteger bI))

-- | (a, b, c) such that a+b, b+c and a+b+c are all in Int32 range.
--   Constructed in three steps: a uniform, b uniform from the
--   shrunken interval that keeps a+b in range, c uniform from the
--   intersection of intervals that keep both b+c and (a+b)+c in range.
--   Both intervals contain 0, so the intersection is non-empty.
newtype NoOverflowAddInt32Triple = NoOverflowAddInt32Triple (Int32, Int32, Int32) deriving stock (Show)

instance Arbitrary NoOverflowAddInt32Triple where
  arbitrary = do
    a <- chooseBoundedIntegral (minBound :: Int32, maxBound :: Int32)
    let aI = toInteger a
        minI = toInteger (minBound :: Int32)
        maxI = toInteger (maxBound :: Int32)
        loB = max minI (minI - aI)
        hiB = min maxI (maxI - aI)
    bI <- chooseInteger (loB, hiB)
    let abI = aI + bI
        loC = max minI (max (minI - bI) (minI - abI))
        hiC = min maxI (min (maxI - bI) (maxI - abI))
    cI <- chooseInteger (loC, hiC)
    pure (NoOverflowAddInt32Triple (a, fromInteger bI, fromInteger cI))

-- | (a, b, c) such that a+b ≤ 255 and a+b+c ≤ 255 (which subsumes
--   b+c ≤ 255 since c ≤ 255 - (a+b) ≤ 255 - b).
newtype NoOverflowAddUInt8Triple = NoOverflowAddUInt8Triple (Word8, Word8, Word8) deriving stock (Show)

instance Arbitrary NoOverflowAddUInt8Triple where
  arbitrary = do
    a <- chooseBoundedIntegral (0 :: Word8, 255)
    b <- chooseBoundedIntegral (0, 255 - a)
    c <- chooseBoundedIntegral (0, 255 - (a + b))
    pure (NoOverflowAddUInt8Triple (a, b, c))

-- | (a, b) such that a*b ≤ 255 in unsigned arithmetic. Pick @a@
--   uniformly, then @b@ from @[0..255 / a]@ (or the full range when
--   @a == 0@, since @0 * anything = 0@). Constructive — no
--   rejection-sampling.
newtype NoOverflowMulUInt8 = NoOverflowMulUInt8 (Word8, Word8) deriving stock (Show)

instance Arbitrary NoOverflowMulUInt8 where
  arbitrary = do
    a <- chooseBoundedIntegral (0 :: Word8, 255)
    let bMax = if a == 0 then 255 else 255 `div` a
    b <- chooseBoundedIntegral (0, bMax)
    pure (NoOverflowMulUInt8 (a, b))

-- ── UInt32 ──

-- | (a, b) where @a + b@ stays in UInt32 range. Pick @a@ uniformly in
--   the full u32 domain, then @b@ from the remaining capacity
--   @0..maxBound - a@. Constructive — no rejection sampling.
newtype NoOverflowAddUInt32 = NoOverflowAddUInt32 (Word32, Word32) deriving stock (Show)

instance Arbitrary NoOverflowAddUInt32 where
  arbitrary = do
    a <- chooseBoundedIntegral (minBound :: Word32, maxBound)
    b <- chooseBoundedIntegral (0, maxBound - a)
    pure (NoOverflowAddUInt32 (a, b))

-- | (a, b, c) such that @a + b@, @a + b + c@ both stay in UInt32 range
--   (which subsumes @b + c@ since @c <= maxBound - (a+b) <= maxBound - b@).
newtype NoOverflowAddUInt32Triple = NoOverflowAddUInt32Triple (Word32, Word32, Word32) deriving stock (Show)

instance Arbitrary NoOverflowAddUInt32Triple where
  arbitrary = do
    a <- chooseBoundedIntegral (minBound :: Word32, maxBound)
    b <- chooseBoundedIntegral (0, maxBound - a)
    c <- chooseBoundedIntegral (0, maxBound - (a + b))
    pure (NoOverflowAddUInt32Triple (a, b, c))

-- | (a, b) such that @a * b <= maxUInt32@. Pick @a@ uniformly, then
--   @b@ from @[0..maxBound \`div\` a]@ (or the full range when
--   @a == 0@, since @0 * anything = 0@). Constructive — no
--   rejection-sampling.
newtype NoOverflowMulUInt32 = NoOverflowMulUInt32 (Word32, Word32) deriving stock (Show)

instance Arbitrary NoOverflowMulUInt32 where
  arbitrary = do
    a <- chooseBoundedIntegral (minBound :: Word32, maxBound)
    let bMax = if a == 0 then maxBound else maxBound `div` a
    b <- chooseBoundedIntegral (0, bMax)
    pure (NoOverflowMulUInt32 (a, b))

-- | (a, b, c) such that @a*b@, @b*c@ and @a*b*c@ all fit in UInt32.
--   All three intermediate products are bounded, not only the
--   left-grouping ones — see 'NoOverflowMulUInt8Triple' below for the
--   rationale (groupings differ under overflow-checked arithmetic).
newtype NoOverflowMulUInt32Triple = NoOverflowMulUInt32Triple (Word32, Word32, Word32) deriving stock (Show)

instance Arbitrary NoOverflowMulUInt32Triple where
  arbitrary = do
    a <- chooseBoundedIntegral (minBound :: Word32, maxBound)
    let bMax = if a == 0 then maxBound else maxBound `div` a
    b <- chooseBoundedIntegral (0, bMax)
    let ab = a * b
        cMaxBC = if b == 0 then maxBound else maxBound `div` b
        cMaxABC = if ab == 0 then maxBound else maxBound `div` ab
        cMax = min cMaxBC cMaxABC
    c <- chooseBoundedIntegral (0, cMax)
    pure (NoOverflowMulUInt32Triple (a, b, c))

-- | (a, b, c) such that @a*b@, @b*c@ and @a*b*c@ all fit in UInt8.
--   Under overflow-checked arithmetic the two groupings @(a*b)*c@ and
--   @a*(b*c)@ are *not* interchangeable: a final product of 0 is no
--   excuse for the intermediate @b*c@ overflowing on the right-hand
--   grouping (e.g. @(0, 216, 99)@: @0*216*99 == 0@ but @216*99 == 21384@
--   overflows). So we bound every intermediate product, not just the
--   left-grouping ones.
--
--   Pick @a@ uniformly, then @b@ from the @a*b ≤ 255@ interval, then
--   @c@ from the intersection of @b*c ≤ 255@ and @a*b*c ≤ 255@. Each
--   interval contains 0 (and 1), so the construction never has to retry;
--   a zero denominator widens its bound to 255 (the constraint is
--   vacuous when the product is forced to 0).
newtype NoOverflowMulUInt8Triple = NoOverflowMulUInt8Triple (Word8, Word8, Word8) deriving stock (Show)

instance Arbitrary NoOverflowMulUInt8Triple where
  arbitrary = do
    a <- chooseBoundedIntegral (0 :: Word8, 255)
    let bMax = if a == 0 then 255 else 255 `div` a
    b <- chooseBoundedIntegral (0, bMax)
    let ab = a * b
        cMaxBC = if b == 0 then 255 else 255 `div` b
        cMaxABC = if ab == 0 then 255 else 255 `div` ab
        cMax = min cMaxBC cMaxABC
    c <- chooseBoundedIntegral (0, cMax)
    pure (NoOverflowMulUInt8Triple (a, b, c))

-- ── Bool ──

-- | Encoded into Awsum's @argv[1]@ as "0" / "1" since there's no
--   parseBool yet — Awsum reads via 'parseUInt8' and converts.
boolEncodeBit :: Bool -> Text
boolEncodeBit True = "1"
boolEncodeBit False = "0"

-- | Awsum prints booleans back as "T" / "F" so the comparison
--   with this Haskell-side rendering is on identical strings.
boolPrint :: Bool -> Text
boolPrint True = "T"
boolPrint False = "F"

newtype BoolV = BoolV Bool deriving stock (Show)

instance Arbitrary BoolV where
  arbitrary = BoolV <$> arbitrary

newtype BoolPair = BoolPair (Bool, Bool) deriving stock (Show)

instance Arbitrary BoolPair where
  arbitrary = BoolPair <$> ((,) <$> arbitrary <*> arbitrary)

-- ── String ──

genLowerStr :: Gen Text
genLowerStr = toText <$> listOf (elements ['a' .. 'z'])

genUpperNonemptyStr :: Gen Text
genUpperNonemptyStr = toText <$> listOf1 (elements ['A' .. 'Z'])

-- | Any valid-UTF-16 Unicode scalar value: U+0001..U+10FFFF excluding
--   the surrogate range U+D800..U+DFFF. The two exclusions correspond
--   to:
--
--   * **U+0000.** Strings reach the program through @argv[1]@, which is
--     a NUL-terminated byte sequence on every backend's host (POSIX,
--     Node's @process.argv@, the JVM and CLR's argv decoders, WASI's
--     @args_get@). A NUL inside the string would truncate the argument
--     before it ever reaches user code.
--   * **U+D800..U+DFFF.** These code units are valid in WTF-16 but not
--     in UTF-16; Awsum strings are strict UTF-16 (see @docs/prelude.md@
--     and the @UnpairedUtf16Surrogate@ entry-point error). A surrogate
--     half generated here would have nothing meaningful to round-trip.
--
--   Newlines and other ASCII control characters are kept — the test
--   compares stdout as raw bytes through @readProcessWithExitCode@, no
--   shell or terminal layer in between. CJK / supplementary-plane code
--   points (which encode as 2 UTF-16 code units / 4 UTF-8 bytes) are
--   the most interesting cases the generator will reach: they're the
--   ones where a backend that fumbled UTF-16/UTF-8 round-tripping
--   would diverge from the others.
genValidUtf16Char :: Gen Char
genValidUtf16Char = do
  n <- chooseInteger (1, 0x10FFFF)
  if n >= 0xD800 && n <= 0xDFFF
    then genValidUtf16Char
    else pure (chr (fromInteger n))

genUtf16Str :: Gen Text
genUtf16Str = toText <$> listOf genValidUtf16Char

newtype LowerStr = LowerStr Text deriving stock (Show)

instance Arbitrary LowerStr where
  arbitrary = LowerStr <$> genLowerStr

-- | Any-valid-UTF-16 string used by the concatenation properties.
--   Distinct from 'LowerStr' (which the splitOnFirst properties keep
--   using) because those rely on a disjoint alphabet between separator
--   and operands.
newtype Utf16Str = Utf16Str Text deriving stock (Show)

instance Arbitrary Utf16Str where
  arbitrary = Utf16Str <$> genUtf16Str

-- | Triple of any-valid-UTF-16 strings, with one extra exclusion: the
--   colon ':'. The associativity property encodes the triple as
--   @"a:b:c"@ in @argv[1]@ and splits on ':' inside Awsum, so a colon
--   inside any operand would corrupt the parse and turn a true
--   property failure into a noise failure.
newtype Utf16TripleNoColon = Utf16TripleNoColon (Text, Text, Text) deriving stock (Show)

instance Arbitrary Utf16TripleNoColon where
  arbitrary = do
    a <- genUtf16NoColon
    b <- genUtf16NoColon
    c <- genUtf16NoColon
    pure (Utf16TripleNoColon (a, b, c))
    where
      genUtf16NoColon = toText <$> listOf (genValidUtf16Char `QC.suchThat` (/= ':'))

-- | Pair of any-valid-UTF-16 strings, colon-excluded for the same
--   reason as 'Utf16TripleNoColon': the additive-length property
--   encodes the pair as @"a:b"@ in @argv[1]@ and splits on ':' inside
--   Awsum.
newtype Utf16PairNoColon = Utf16PairNoColon (Text, Text) deriving stock (Show)

instance Arbitrary Utf16PairNoColon where
  arbitrary = do
    a <- genUtf16NoColon
    b <- genUtf16NoColon
    pure (Utf16PairNoColon (a, b))
    where
      genUtf16NoColon = toText <$> listOf (genValidUtf16Char `QC.suchThat` (/= ':'))

-- | Same shape as 'Utf16PairNoColon' but with the second component
--   sometimes (~20%) reusing the first verbatim. Used by the
--   'eqString'-symmetric property where uniform sampling would never
--   hit the @a == b@ branch, leaving the @True@ arm of the @case@
--   uncovered. Parallel to 'Int32MaybeEqualPair' / 'Word8MaybeEqualPair'.
newtype Utf16MaybeEqualPairNoColon = Utf16MaybeEqualPairNoColon (Text, Text) deriving stock (Show)

instance Arbitrary Utf16MaybeEqualPairNoColon where
  arbitrary = do
    a <- genUtf16NoColon
    b <-
      frequency
        [ (1, pure a),
          (4, genUtf16NoColon)
        ]
    pure (Utf16MaybeEqualPairNoColon (a, b))
    where
      genUtf16NoColon = toText <$> listOf (genValidUtf16Char `QC.suchThat` (/= ':'))

-- | (sep, a, b): sep ∈ [A-Z]+, a, b ∈ [a-z]*.
--   Disjoint alphabets ⇒ neither a nor b can contain sep as a substring.
newtype SplitRoundtripCase = SplitRoundtripCase (Text, Text, Text) deriving stock (Show)

instance Arbitrary SplitRoundtripCase where
  arbitrary = do
    sep <- genUpperNonemptyStr
    a <- genLowerStr
    b <- genLowerStr
    pure (SplitRoundtripCase (sep, a, b))

-- | (sep, s) with the same disjoint-alphabet trick — except here we
--   want @sep@ to be guaranteed *absent* from @s@, so no extra
--   construction is needed: @sep@ is uppercase, @s@ is lowercase, the
--   negative branch of splitOnFirst is the only correct outcome.
newtype SplitNegativeCase = SplitNegativeCase (Text, Text) deriving stock (Show)

instance Arbitrary SplitNegativeCase where
  arbitrary = do
    sep <- genUpperNonemptyStr
    s <- genLowerStr
    pure (SplitNegativeCase (sep, s))

-- ── String-length helpers (Haskell-side oracle) ──

-- | Code-point count: 'T.length' on 'Text' returns the number of
--   'Char's, i.e. Unicode scalar values, regardless of the internal
--   storage (text-2.x is UTF-8, text-1.x was UTF-16; 'T.length' is
--   defined to be the scalar count in both).
lengthCodePointsHs :: Text -> Word32
lengthCodePointsHs = fromIntegral . T.length

-- | UTF-16 code-unit count: every BMP scalar is one unit, every
--   supplementary scalar (>= U+10000) needs a high+low surrogate
--   pair so it counts as two. The fold walks each 'Char' once.
lengthUtf16CodeUnitsHs :: Text -> Word32
lengthUtf16CodeUnitsHs = T.foldl' step 0
  where
    step acc c = acc + if ord c >= 0x10000 then 2 else 1

-- | UTF-8 byte count: encode and ask the bytestring its length.
--   Allocates the encoded bytes; for a property test that's fine.
lengthUtf8BytesHs :: Text -> Word32
lengthUtf8BytesHs = fromIntegral . BS.length . encodeUtf8

-- ════════════════════════════════════════════════════════════════════════════
-- Property catalogue
-- ════════════════════════════════════════════════════════════════════════════

-- | A generated Int32 round-tripped through a '(Int32 | String)' row:
--   injected as the int and as a string, dispatched in both label orders
--   (commutativity). Self-verifying — the program prints OK iff every path
--   recovers 'showInt32 a'. The first property test exercising rows, so the
--   injection/dispatch machinery is fuzzed cross-backend.
rowInjectionRoundtripProp :: Property Int32V
rowInjectionRoundtripProp =
  Property
    { propName = "row-injection-roundtrip",
      propSourceDir = "row-injection-roundtrip",
      propGen = arbitrary,
      propEncode = \(Int32V a) -> show a,
      propExpectedOutput = const "OK"
    }

properties :: [SomeProperty]
properties =
  [ -- ── Structural unions (rows) ──
    SomeProperty rowInjectionRoundtripProp,
    -- ── Integer arithmetic (commutativity, identity, agreement) ──
    SomeProperty addInt32CommutativeProp,
    SomeProperty addInt32ZeroIdentityLeftProp,
    SomeProperty addInt32ZeroIdentityRightProp,
    SomeProperty addUInt8CommutativeProp,
    SomeProperty addUInt8ZeroIdentityLeftProp,
    SomeProperty addUInt8ZeroIdentityRightProp,
    SomeProperty addInt32AssociativeProp,
    SomeProperty addUInt8AssociativeProp,
    SomeProperty addInt32MatchesHaskellProp,
    SomeProperty subInt32EqualsAddNegProp,
    SomeProperty addInt32NegCancelsProp,
    SomeProperty mulUInt8CommutativeProp,
    SomeProperty mulUInt8OneIdentityLeftProp,
    SomeProperty mulUInt8OneIdentityRightProp,
    SomeProperty mulUInt8AssociativeProp,
    SomeProperty addUInt32CommutativeProp,
    SomeProperty addUInt32AssociativeProp,
    SomeProperty addUInt32ZeroIdentityLeftProp,
    SomeProperty addUInt32ZeroIdentityRightProp,
    SomeProperty mulUInt32CommutativeProp,
    SomeProperty mulUInt32AssociativeProp,
    SomeProperty mulUInt32OneIdentityLeftProp,
    SomeProperty mulUInt32OneIdentityRightProp,
    SomeProperty mulInt32CommutativeProp,
    SomeProperty mulInt32OneIdentityLeftProp,
    SomeProperty mulInt32OneIdentityRightProp,
    SomeProperty mulInt32AssociativeProp,
    SomeProperty mulInt32DistributiveProp,
    -- ── Successor / predecessor (round-trip + boundary) ──
    SomeProperty succPredRoundtripInt32Prop,
    SomeProperty predSuccRoundtripInt32Prop,
    SomeProperty succInt32FailsIffMaxProp,
    SomeProperty predInt32FailsIffMinProp,
    SomeProperty succUInt8FailsIff255Prop,
    SomeProperty predUInt8FailsIffZeroProp,
    SomeProperty succUInt32FailsIffMaxProp,
    SomeProperty predUInt32FailsIffZeroProp,
    -- ── Equality ──
    SomeProperty eqInt32ReflexiveProp,
    SomeProperty eqInt32SymmetricProp,
    SomeProperty eqUInt8SymmetricProp,
    SomeProperty eqUInt32SymmetricProp,
    SomeProperty eqStringReflexiveProp,
    SomeProperty eqStringSymmetricProp,
    -- ── Parser / show round-trip ──
    SomeProperty parseInt32ShowRoundtripProp,
    SomeProperty parseUInt8ShowRoundtripProp,
    SomeProperty parseUInt32ShowRoundtripProp,
    -- ── String monoid + split ──
    SomeProperty concatLeftIdentityProp,
    SomeProperty concatRightIdentityProp,
    SomeProperty concatAssociativeProp,
    SomeProperty splitOnFirstRoundtripPositiveProp,
    SomeProperty splitOnFirstRoundtripNegativeProp,
    -- ── String length (three explicit functions) ──
    SomeProperty lengthsThreeFunctionsProp,
    SomeProperty concatLengthAdditiveProp,
    -- ── Boolean laws ──
    SomeProperty notInvolutiveProp,
    SomeProperty andCommutativeProp,
    SomeProperty orCommutativeProp,
    SomeProperty deMorganProp
  ]

-- ── Integer arithmetic ──

addInt32CommutativeProp :: Property NoOverflowAddInt32
addInt32CommutativeProp =
  Property
    { propName = "addInt32-commutative",
      propSourceDir = "addInt32-commutative",
      propGen = arbitrary,
      propEncode = \(NoOverflowAddInt32 (a, b)) -> show a <> ":" <> show b,
      propExpectedOutput = const "OK"
    }

addInt32ZeroIdentityLeftProp :: Property Int32V
addInt32ZeroIdentityLeftProp =
  Property
    { propName = "addInt32-zero-identity-left",
      propSourceDir = "addInt32-zero-identity-left",
      propGen = arbitrary,
      propEncode = \(Int32V a) -> show a,
      propExpectedOutput = const "OK"
    }

addInt32ZeroIdentityRightProp :: Property Int32V
addInt32ZeroIdentityRightProp =
  Property
    { propName = "addInt32-zero-identity-right",
      propSourceDir = "addInt32-zero-identity-right",
      propGen = arbitrary,
      propEncode = \(Int32V a) -> show a,
      propExpectedOutput = const "OK"
    }

addUInt8ZeroIdentityLeftProp :: Property Word8V
addUInt8ZeroIdentityLeftProp =
  Property
    { propName = "addUInt8-zero-identity-left",
      propSourceDir = "addUInt8-zero-identity-left",
      propGen = arbitrary,
      propEncode = \(Word8V a) -> show a,
      propExpectedOutput = const "OK"
    }

addUInt8ZeroIdentityRightProp :: Property Word8V
addUInt8ZeroIdentityRightProp =
  Property
    { propName = "addUInt8-zero-identity-right",
      propSourceDir = "addUInt8-zero-identity-right",
      propGen = arbitrary,
      propEncode = \(Word8V a) -> show a,
      propExpectedOutput = const "OK"
    }

-- | Stronger than the commutativity / identity properties: pins down
--   the exact numeric result Awsum produces against an independently
--   computed Haskell @Int32@ sum. Closes the gap where every backend
--   could agree on the wrong value (e.g. an off-by-one in addInt32
--   that all five backends share would be invisible to commutativity
--   alone).
addInt32MatchesHaskellProp :: Property NoOverflowAddInt32
addInt32MatchesHaskellProp =
  Property
    { propName = "addInt32-matches-haskell-no-overflow",
      propSourceDir = "addInt32-matches-haskell-no-overflow",
      propGen = arbitrary,
      propEncode = \(NoOverflowAddInt32 (a, b)) -> show a <> ":" <> show b,
      propExpectedOutput = \(NoOverflowAddInt32 (a, b)) -> show ((a + b) :: Int32)
    }

-- | @subInt32 a b == addInt32 a (negInt32 b)@ — links subtraction,
--   negation and addition. Generator excludes @b == minInt32@ (so
--   @negInt32 b@ succeeds) and keeps @a - b@ in range, so both sides
--   land on the same @Right@.
subInt32EqualsAddNegProp :: Property NoOverflowSubInt32NonMinB
subInt32EqualsAddNegProp =
  Property
    { propName = "subInt32-equals-add-neg",
      propSourceDir = "subInt32-equals-add-neg",
      propGen = arbitrary,
      propEncode = \(NoOverflowSubInt32NonMinB (a, b)) -> show a <> ":" <> show b,
      propExpectedOutput = const "OK"
    }

-- | @addInt32 (negInt32 x) x == Right 0@ — negation cancels addition.
--   Excludes @x == minInt32@ (so @negInt32 x@ succeeds); the sum
--   @-x + x = 0@ is always in range, so the property is well-defined
--   on the rest of Int32.
addInt32NegCancelsProp :: Property NonMinInt32
addInt32NegCancelsProp =
  Property
    { propName = "addInt32-neg-cancels",
      propSourceDir = "addInt32-neg-cancels",
      propGen = arbitrary,
      propEncode = \(NonMinInt32 x) -> show x,
      propExpectedOutput = const "OK"
    }

predSuccRoundtripInt32Prop :: Property NonMaxInt32
predSuccRoundtripInt32Prop =
  Property
    { propName = "predSucc-roundtrip-int32",
      propSourceDir = "predSucc-roundtrip-int32",
      propGen = arbitrary,
      propEncode = \(NonMaxInt32 x) -> show x,
      propExpectedOutput = const "OK"
    }

succInt32FailsIffMaxProp :: Property Int32WithMaxFavored
succInt32FailsIffMaxProp =
  Property
    { propName = "succInt32-fails-iff-max",
      propSourceDir = "succInt32-fails-iff-max",
      propGen = arbitrary,
      propEncode = \(Int32WithMaxFavored x) -> show x,
      propExpectedOutput = const "OK"
    }

predInt32FailsIffMinProp :: Property Int32WithMinFavored
predInt32FailsIffMinProp =
  Property
    { propName = "predInt32-fails-iff-min",
      propSourceDir = "predInt32-fails-iff-min",
      propGen = arbitrary,
      propEncode = \(Int32WithMinFavored x) -> show x,
      propExpectedOutput = const "OK"
    }

succUInt8FailsIff255Prop :: Property Word8WithMaxFavored
succUInt8FailsIff255Prop =
  Property
    { propName = "succUInt8-fails-iff-255",
      propSourceDir = "succUInt8-fails-iff-255",
      propGen = arbitrary,
      propEncode = \(Word8WithMaxFavored x) -> show x,
      propExpectedOutput = const "OK"
    }

predUInt8FailsIffZeroProp :: Property Word8WithMinFavored
predUInt8FailsIffZeroProp =
  Property
    { propName = "predUInt8-fails-iff-zero",
      propSourceDir = "predUInt8-fails-iff-zero",
      propGen = arbitrary,
      propEncode = \(Word8WithMinFavored x) -> show x,
      propExpectedOutput = const "OK"
    }

eqInt32SymmetricProp :: Property Int32MaybeEqualPair
eqInt32SymmetricProp =
  Property
    { propName = "eqInt32-symmetric",
      propSourceDir = "eqInt32-symmetric",
      propGen = arbitrary,
      propEncode = \(Int32MaybeEqualPair (a, b)) -> show a <> ":" <> show b,
      propExpectedOutput = const "OK"
    }

eqUInt8SymmetricProp :: Property Word8MaybeEqualPair
eqUInt8SymmetricProp =
  Property
    { propName = "eqUInt8-symmetric",
      propSourceDir = "eqUInt8-symmetric",
      propGen = arbitrary,
      propEncode = \(Word8MaybeEqualPair (a, b)) -> show a <> ":" <> show b,
      propExpectedOutput = const "OK"
    }

eqStringReflexiveProp :: Property Utf16Str
eqStringReflexiveProp =
  Property
    { propName = "eqString-reflexive",
      propSourceDir = "eqString-reflexive",
      propGen = arbitrary,
      propEncode = \(Utf16Str s) -> s,
      propExpectedOutput = const "OK"
    }

eqStringSymmetricProp :: Property Utf16MaybeEqualPairNoColon
eqStringSymmetricProp =
  Property
    { propName = "eqString-symmetric",
      propSourceDir = "eqString-symmetric",
      propGen = arbitrary,
      propEncode = \(Utf16MaybeEqualPairNoColon (a, b)) -> a <> ":" <> b,
      propExpectedOutput = const "OK"
    }

parseInt32ShowRoundtripProp :: Property Int32V
parseInt32ShowRoundtripProp =
  Property
    { propName = "parseInt32-show-roundtrip",
      propSourceDir = "parseInt32-show-roundtrip",
      propGen = arbitrary,
      propEncode = \(Int32V x) -> show x,
      -- 'show' on Int32 in Haskell gives the same decimal grammar
      -- Awsum's showInt32 produces (no sign for non-negative, leading
      -- '-' for negative, no padding), so the input is also the
      -- expected output.
      propExpectedOutput = \(Int32V x) -> show x
    }

parseUInt8ShowRoundtripProp :: Property Word8V
parseUInt8ShowRoundtripProp =
  Property
    { propName = "parseUInt8-show-roundtrip",
      propSourceDir = "parseUInt8-show-roundtrip",
      propGen = arbitrary,
      propEncode = \(Word8V x) -> show x,
      propExpectedOutput = \(Word8V x) -> show x
    }

addUInt8CommutativeProp :: Property NoOverflowAddUInt8
addUInt8CommutativeProp =
  Property
    { propName = "addUInt8-commutative",
      propSourceDir = "addUInt8-commutative",
      propGen = arbitrary,
      propEncode = \(NoOverflowAddUInt8 (a, b)) -> show a <> ":" <> show b,
      propExpectedOutput = const "OK"
    }

addInt32AssociativeProp :: Property NoOverflowAddInt32Triple
addInt32AssociativeProp =
  Property
    { propName = "addInt32-associative",
      propSourceDir = "addInt32-associative",
      propGen = arbitrary,
      propEncode = \(NoOverflowAddInt32Triple (a, b, c)) ->
        show a <> ":" <> show b <> ":" <> show c,
      propExpectedOutput = const "OK"
    }

addUInt8AssociativeProp :: Property NoOverflowAddUInt8Triple
addUInt8AssociativeProp =
  Property
    { propName = "addUInt8-associative",
      propSourceDir = "addUInt8-associative",
      propGen = arbitrary,
      propEncode = \(NoOverflowAddUInt8Triple (a, b, c)) ->
        show a <> ":" <> show b <> ":" <> show c,
      propExpectedOutput = const "OK"
    }

mulUInt8CommutativeProp :: Property NoOverflowMulUInt8
mulUInt8CommutativeProp =
  Property
    { propName = "mulUInt8-commutative",
      propSourceDir = "mulUInt8-commutative",
      propGen = arbitrary,
      propEncode = \(NoOverflowMulUInt8 (a, b)) -> show a <> ":" <> show b,
      propExpectedOutput = const "OK"
    }

mulUInt8OneIdentityLeftProp :: Property Word8V
mulUInt8OneIdentityLeftProp =
  Property
    { propName = "mulUInt8-one-identity-left",
      propSourceDir = "mulUInt8-one-identity-left",
      propGen = arbitrary,
      propEncode = \(Word8V a) -> show a,
      propExpectedOutput = const "OK"
    }

mulUInt8OneIdentityRightProp :: Property Word8V
mulUInt8OneIdentityRightProp =
  Property
    { propName = "mulUInt8-one-identity-right",
      propSourceDir = "mulUInt8-one-identity-right",
      propGen = arbitrary,
      propEncode = \(Word8V a) -> show a,
      propExpectedOutput = const "OK"
    }

mulUInt8AssociativeProp :: Property NoOverflowMulUInt8Triple
mulUInt8AssociativeProp =
  Property
    { propName = "mulUInt8-associative",
      propSourceDir = "mulUInt8-associative",
      propGen = arbitrary,
      propEncode = \(NoOverflowMulUInt8Triple (a, b, c)) ->
        show a <> ":" <> show b <> ":" <> show c,
      propExpectedOutput = const "OK"
    }

-- ── UInt32 ──

addUInt32CommutativeProp :: Property NoOverflowAddUInt32
addUInt32CommutativeProp =
  Property
    { propName = "addUInt32-commutative",
      propSourceDir = "addUInt32-commutative",
      propGen = arbitrary,
      propEncode = \(NoOverflowAddUInt32 (a, b)) -> show a <> ":" <> show b,
      propExpectedOutput = const "OK"
    }

addUInt32AssociativeProp :: Property NoOverflowAddUInt32Triple
addUInt32AssociativeProp =
  Property
    { propName = "addUInt32-associative",
      propSourceDir = "addUInt32-associative",
      propGen = arbitrary,
      propEncode = \(NoOverflowAddUInt32Triple (a, b, c)) ->
        show a <> ":" <> show b <> ":" <> show c,
      propExpectedOutput = const "OK"
    }

addUInt32ZeroIdentityLeftProp :: Property Word32V
addUInt32ZeroIdentityLeftProp =
  Property
    { propName = "addUInt32-zero-identity-left",
      propSourceDir = "addUInt32-zero-identity-left",
      propGen = arbitrary,
      propEncode = \(Word32V a) -> show a,
      propExpectedOutput = const "OK"
    }

addUInt32ZeroIdentityRightProp :: Property Word32V
addUInt32ZeroIdentityRightProp =
  Property
    { propName = "addUInt32-zero-identity-right",
      propSourceDir = "addUInt32-zero-identity-right",
      propGen = arbitrary,
      propEncode = \(Word32V a) -> show a,
      propExpectedOutput = const "OK"
    }

mulUInt32CommutativeProp :: Property NoOverflowMulUInt32
mulUInt32CommutativeProp =
  Property
    { propName = "mulUInt32-commutative",
      propSourceDir = "mulUInt32-commutative",
      propGen = arbitrary,
      propEncode = \(NoOverflowMulUInt32 (a, b)) -> show a <> ":" <> show b,
      propExpectedOutput = const "OK"
    }

mulUInt32OneIdentityLeftProp :: Property Word32V
mulUInt32OneIdentityLeftProp =
  Property
    { propName = "mulUInt32-one-identity-left",
      propSourceDir = "mulUInt32-one-identity-left",
      propGen = arbitrary,
      propEncode = \(Word32V a) -> show a,
      propExpectedOutput = const "OK"
    }

mulUInt32OneIdentityRightProp :: Property Word32V
mulUInt32OneIdentityRightProp =
  Property
    { propName = "mulUInt32-one-identity-right",
      propSourceDir = "mulUInt32-one-identity-right",
      propGen = arbitrary,
      propEncode = \(Word32V a) -> show a,
      propExpectedOutput = const "OK"
    }

mulUInt32AssociativeProp :: Property NoOverflowMulUInt32Triple
mulUInt32AssociativeProp =
  Property
    { propName = "mulUInt32-associative",
      propSourceDir = "mulUInt32-associative",
      propGen = arbitrary,
      propEncode = \(NoOverflowMulUInt32Triple (a, b, c)) ->
        show a <> ":" <> show b <> ":" <> show c,
      propExpectedOutput = const "OK"
    }

succUInt32FailsIffMaxProp :: Property Word32WithMaxFavored
succUInt32FailsIffMaxProp =
  Property
    { propName = "succUInt32-fails-iff-max",
      propSourceDir = "succUInt32-fails-iff-max",
      propGen = arbitrary,
      propEncode = \(Word32WithMaxFavored x) -> show x,
      propExpectedOutput = const "OK"
    }

predUInt32FailsIffZeroProp :: Property Word32WithMinFavored
predUInt32FailsIffZeroProp =
  Property
    { propName = "predUInt32-fails-iff-zero",
      propSourceDir = "predUInt32-fails-iff-zero",
      propGen = arbitrary,
      propEncode = \(Word32WithMinFavored x) -> show x,
      propExpectedOutput = const "OK"
    }

eqUInt32SymmetricProp :: Property Word32MaybeEqualPair
eqUInt32SymmetricProp =
  Property
    { propName = "eqUInt32-symmetric",
      propSourceDir = "eqUInt32-symmetric",
      propGen = arbitrary,
      propEncode = \(Word32MaybeEqualPair (a, b)) -> show a <> ":" <> show b,
      propExpectedOutput = const "OK"
    }

parseUInt32ShowRoundtripProp :: Property Word32V
parseUInt32ShowRoundtripProp =
  Property
    { propName = "parseUInt32-show-roundtrip",
      propSourceDir = "parseUInt32-show-roundtrip",
      propGen = arbitrary,
      propEncode = \(Word32V x) -> show x,
      propExpectedOutput = \(Word32V x) -> show x
    }

-- ── Int32 ──

mulInt32CommutativeProp :: Property NoOverflowMulInt32
mulInt32CommutativeProp =
  Property
    { propName = "mulInt32-commutative",
      propSourceDir = "mulInt32-commutative",
      propGen = arbitrary,
      propEncode = \(NoOverflowMulInt32 (a, b)) -> show a <> ":" <> show b,
      propExpectedOutput = const "OK"
    }

mulInt32OneIdentityLeftProp :: Property Int32V
mulInt32OneIdentityLeftProp =
  Property
    { propName = "mulInt32-one-identity-left",
      propSourceDir = "mulInt32-one-identity-left",
      propGen = arbitrary,
      propEncode = \(Int32V a) -> show a,
      propExpectedOutput = const "OK"
    }

mulInt32OneIdentityRightProp :: Property Int32V
mulInt32OneIdentityRightProp =
  Property
    { propName = "mulInt32-one-identity-right",
      propSourceDir = "mulInt32-one-identity-right",
      propGen = arbitrary,
      propEncode = \(Int32V a) -> show a,
      propExpectedOutput = const "OK"
    }

mulInt32AssociativeProp :: Property NoOverflowMulInt32Triple
mulInt32AssociativeProp =
  Property
    { propName = "mulInt32-associative",
      propSourceDir = "mulInt32-associative",
      propGen = arbitrary,
      propEncode = \(NoOverflowMulInt32Triple (a, b, c)) ->
        show a <> ":" <> show b <> ":" <> show c,
      propExpectedOutput = const "OK"
    }

mulInt32DistributiveProp :: Property NoOverflowMulDistribInt32
mulInt32DistributiveProp =
  Property
    { propName = "mulInt32-distributive-over-addInt32",
      propSourceDir = "mulInt32-distributive-over-addInt32",
      propGen = arbitrary,
      propEncode = \(NoOverflowMulDistribInt32 (a, b, c)) ->
        show a <> ":" <> show b <> ":" <> show c,
      propExpectedOutput = const "OK"
    }

succPredRoundtripInt32Prop :: Property NonMinInt32
succPredRoundtripInt32Prop =
  Property
    { propName = "succPred-roundtrip-int32",
      propSourceDir = "succPred-roundtrip-int32",
      propGen = arbitrary,
      propEncode = \(NonMinInt32 x) -> show x,
      propExpectedOutput = const "OK"
    }

eqInt32ReflexiveProp :: Property Int32V
eqInt32ReflexiveProp =
  Property
    { propName = "eqInt32-reflexive",
      propSourceDir = "eqInt32-reflexive",
      propGen = arbitrary,
      propEncode = \(Int32V a) -> show a,
      propExpectedOutput = const "OK"
    }

-- ── String monoid + split ──

concatLeftIdentityProp :: Property Utf16Str
concatLeftIdentityProp =
  Property
    { propName = "concat-left-identity",
      propSourceDir = "concat-left-identity",
      propGen = arbitrary,
      propEncode = \(Utf16Str s) -> s,
      propExpectedOutput = \(Utf16Str s) -> s
    }

concatRightIdentityProp :: Property Utf16Str
concatRightIdentityProp =
  Property
    { propName = "concat-right-identity",
      propSourceDir = "concat-right-identity",
      propGen = arbitrary,
      propEncode = \(Utf16Str s) -> s,
      propExpectedOutput = \(Utf16Str s) -> s
    }

concatAssociativeProp :: Property Utf16TripleNoColon
concatAssociativeProp =
  Property
    { propName = "concat-associative",
      propSourceDir = "concat-associative",
      propGen = arbitrary,
      propEncode = \(Utf16TripleNoColon (a, b, c)) -> a <> ":" <> b <> ":" <> c,
      propExpectedOutput = \(Utf16TripleNoColon (a, b, c)) ->
        let s = a <> b <> c in s <> ":" <> s
    }

splitOnFirstRoundtripPositiveProp :: Property SplitRoundtripCase
splitOnFirstRoundtripPositiveProp =
  Property
    { propName = "splitOnFirst-roundtrip-positive",
      propSourceDir = "splitOnFirst-roundtrip-positive",
      propGen = arbitrary,
      -- Awsum receives "sep:s" where s = a <> sep <> b, i.e. sep is
      -- guaranteed to occur. The disjoint alphabets ensure 'a' itself
      -- contains no occurrence of sep, so splitOnFirst hits exactly the
      -- inserted boundary — round-trip is `a ++ sep ++ b == s`.
      propEncode = \(SplitRoundtripCase (sep, a, b)) ->
        sep <> ":" <> a <> sep <> b,
      propExpectedOutput = \(SplitRoundtripCase (sep, a, b)) -> a <> sep <> b
    }

splitOnFirstRoundtripNegativeProp :: Property SplitNegativeCase
splitOnFirstRoundtripNegativeProp =
  Property
    { propName = "splitOnFirst-roundtrip-negative",
      propSourceDir = "splitOnFirst-roundtrip-negative",
      propGen = arbitrary,
      propEncode = \(SplitNegativeCase (sep, s)) -> sep <> ":" <> s,
      propExpectedOutput = const "OK"
    }

-- ── String length (three explicit functions) ──

-- | For any valid-UTF-16 input, the three string-length functions must
--   agree across all five backends and match the Haskell oracle.
--   Awsum prints @cp:cu:b@; Haskell computes the same triple from
--   'Text' independently. Two-sided check: a backend that miscounts
--   surrogate pairs, undercounts a 4-byte UTF-8 sequence, or treats
--   the storage buffer as raw bytes would diverge from at least one
--   peer and from the oracle.
lengthsThreeFunctionsProp :: Property Utf16Str
lengthsThreeFunctionsProp =
  Property
    { propName = "lengths-three-functions",
      propSourceDir = "lengths-three-functions",
      propGen = arbitrary,
      propEncode = \(Utf16Str s) -> s,
      propExpectedOutput = \(Utf16Str s) ->
        show (lengthCodePointsHs s)
          <> ":"
          <> show (lengthUtf16CodeUnitsHs s)
          <> ":"
          <> show (lengthUtf8BytesHs s)
    }

-- | All three string-length functions are additive under @(++)@: the
--   length of @a ++ b@ equals the sum of the individual lengths, in
--   each of the three units. Awsum prints @cp:cu:b@ computed from
--   @a ++ b@ on the @Right@ path; Haskell computes the same triple
--   from @T.append a b@. A backend whose @__concat@ produced a buffer
--   of wrong size, or which miscounted at the join when one operand
--   ends in a high surrogate and the other starts in a low surrogate,
--   would diverge from at least one peer and from the oracle.
concatLengthAdditiveProp :: Property Utf16PairNoColon
concatLengthAdditiveProp =
  Property
    { propName = "concat-length-additive",
      propSourceDir = "concat-length-additive",
      propGen = arbitrary,
      propEncode = \(Utf16PairNoColon (a, b)) -> a <> ":" <> b,
      propExpectedOutput = \(Utf16PairNoColon (a, b)) ->
        let ab = a <> b
         in show (lengthCodePointsHs ab)
              <> ":"
              <> show (lengthUtf16CodeUnitsHs ab)
              <> ":"
              <> show (lengthUtf8BytesHs ab)
    }

-- ── Boolean laws ──

notInvolutiveProp :: Property BoolV
notInvolutiveProp =
  Property
    { propName = "not-involutive",
      propSourceDir = "not-involutive",
      propGen = arbitrary,
      propEncode = \(BoolV b) -> boolEncodeBit b,
      propExpectedOutput = \(BoolV b) -> boolPrint b
    }

andCommutativeProp :: Property BoolPair
andCommutativeProp =
  Property
    { propName = "and-commutative",
      propSourceDir = "and-commutative",
      propGen = arbitrary,
      propEncode = \(BoolPair (a, b)) -> boolEncodeBit a <> ":" <> boolEncodeBit b,
      propExpectedOutput = \(BoolPair (a, b)) -> boolPrint (a && b) <> boolPrint (b && a)
    }

orCommutativeProp :: Property BoolPair
orCommutativeProp =
  Property
    { propName = "or-commutative",
      propSourceDir = "or-commutative",
      propGen = arbitrary,
      propEncode = \(BoolPair (a, b)) -> boolEncodeBit a <> ":" <> boolEncodeBit b,
      propExpectedOutput = \(BoolPair (a, b)) -> boolPrint (a || b) <> boolPrint (b || a)
    }

deMorganProp :: Property BoolPair
deMorganProp =
  Property
    { propName = "de-morgan",
      propSourceDir = "de-morgan",
      propGen = arbitrary,
      propEncode = \(BoolPair (a, b)) -> boolEncodeBit a <> ":" <> boolEncodeBit b,
      propExpectedOutput = \(BoolPair (a, b)) ->
        boolPrint (not (a && b)) <> boolPrint (not a || not b)
    }

-- ════════════════════════════════════════════════════════════════════════════
-- Const-fold differential (fold == runtime)
-- ════════════════════════════════════════════════════════════════════════════

-- Every property above feeds its operands through argv/stdin, so they reach
-- the runtime helpers as runtime values and 'Awsum.Simplify' has nothing to
-- fold. This one generates the *program*: the operands are source literals,
-- which the 'SimplifyOn' compile evaluates at compile time ('constFold' +
-- case-of-known-constructor) while the 'SimplifyOff' twin routes the very
-- same literals to the runtime helpers. Both runs, on all five backends,
-- must print the marker string the Haskell oracle computes — so
-- @fold == haskell@ and @runtime == haskell@, hence @fold == runtime@,
-- including the exact overflow/underflow outcome of every operation.
--
-- One generated program carries one instance of every (operation, outcome)
-- pair — overflow, underflow and in-range operands are each constructed
-- directly (no rejection sampling), so every helper's every branch is
-- exercised in every QuickCheck iteration, with random magnitudes.

-- | One case of the generated program: a built-in applied to literal
--   operands, the arm shape the program scrutinises its result with, and
--   the stdout marker the Haskell oracle expects.
data FoldCaseV = FoldCaseV
  { fcvOp :: Text,
    fcvArgs :: [Integer],
    fcvArm :: FoldArmStyle,
    fcvExpected :: Text
  }
  deriving stock (Show)

-- | How the generated program scrutinises one result.
data FoldArmStyle
  = -- | @Either@ whose @Left@ carries the @(UnderflowError | OverflowError)@
    --   row (signed add\/sub\/mul): the arm row-cases into \"U\" \/ \"O\";
    --   @Right v@ prints the named show function of @v@.
    FoldArmRow Text
  | -- | @Either@ whose @Left@ is a bare single-error constructor: the arm
    --   prints the given marker; @Right v@ prints the named show function.
    FoldArmLeft Text Text
  | -- | @Bool@ result: \"T\" \/ \"F\".
    FoldArmBool
  deriving stock (Show)

i32Lo, i32Hi, u8Hi, u32Hi :: Integer
i32Lo = -2147483648
i32Hi = 2147483647
u8Hi = 255
u32Hi = 4294967295

-- | All cases of one generated program: one instance per (operation,
--   outcome). 41 cases — 3 outcomes × 3 signed ops, 2 × 12 unsigned-op
--   directions, boundary + random for the seven unary ops, forced-equal +
--   random pair for the three equalities.
genFoldCases :: Gen [FoldCaseV]
genFoldCases =
  concat
    <$> sequence
      [ int32ArithCases "addInt32" (+) genAddOk,
        int32ArithCases "subInt32" (-) genSubOk,
        int32ArithCases "mulInt32" (*) genMulOk,
        unsignedAdd "addUInt8" "showUInt8" u8Hi,
        unsignedSub "subUInt8" "showUInt8" u8Hi,
        unsignedMul "mulUInt8" "showUInt8" u8Hi,
        unsignedAdd "addUInt32" "showUInt32" u32Hi,
        unsignedSub "subUInt32" "showUInt32" u32Hi,
        unsignedMul "mulUInt32" "showUInt32" u32Hi,
        unaryCases "negInt32" "showInt32" "O" i32Lo (i32Lo, i32Hi) (\a -> if a == i32Lo then "O" else show (negate a)),
        unaryCases "succInt32" "showInt32" "O" i32Hi (i32Lo, i32Hi) (\a -> if a == i32Hi then "O" else show (a + 1)),
        unaryCases "predInt32" "showInt32" "U" i32Lo (i32Lo, i32Hi) (\a -> if a == i32Lo then "U" else show (a - 1)),
        unaryCases "succUInt8" "showUInt8" "O" u8Hi (0, u8Hi) (\a -> if a == u8Hi then "O" else show (a + 1)),
        unaryCases "predUInt8" "showUInt8" "U" 0 (0, u8Hi) (\a -> if a == 0 then "U" else show (a - 1)),
        unaryCases "succUInt32" "showUInt32" "O" u32Hi (0, u32Hi) (\a -> if a == u32Hi then "O" else show (a + 1)),
        unaryCases "predUInt32" "showUInt32" "U" 0 (0, u32Hi) (\a -> if a == 0 then "U" else show (a - 1)),
        eqCases "eqInt32" (i32Lo, i32Hi),
        eqCases "eqUInt8" (0, u8Hi),
        eqCases "eqUInt32" (0, u32Hi)
      ]
  where
    -- Signed Int32 add/sub/mul: three outcomes each. Overflow/underflow
    -- operands are constructed per operation; the in-range generator is the
    -- operation's NoOverflow* construction.
    int32ArithCases name f genOk = do
      ovf <- case name of
        "subInt32" -> do
          a <- chooseInteger (0, i32Hi)
          b <- chooseInteger (i32Lo, a - i32Hi - 1)
          pure (a, b)
        "mulInt32" -> do
          a <- chooseInteger (2, i32Hi)
          b <- chooseInteger (i32Hi `div` a + 1, i32Hi)
          pure (a, b)
        _ -> do
          a <- chooseInteger (1, i32Hi)
          b <- chooseInteger (i32Hi - a + 1, i32Hi)
          pure (a, b)
      unf <- case name of
        "subInt32" -> do
          a <- chooseInteger (i32Lo, -2)
          b <- chooseInteger (a - i32Lo + 1, i32Hi)
          pure (a, b)
        "mulInt32" -> do
          a <- chooseInteger (2, i32Hi)
          b <- chooseInteger (i32Lo, i32Lo `div` a - 1)
          pure (a, b)
        _ -> do
          a <- chooseInteger (i32Lo, -1)
          b <- chooseInteger (i32Lo, i32Lo - a - 1)
          pure (a, b)
      ok <- genOk
      pure [mk name f ab | ab <- [ovf, unf, ok]]
      where
        mk n g (a, b) = FoldCaseV n [a, b] (FoldArmRow "showInt32") (oracle (g a b))
        oracle r
          | r > i32Hi = "O"
          | r < i32Lo = "U"
          | otherwise = show r
    genAddOk = do
      a <- chooseInteger (i32Lo, i32Hi)
      b <- chooseInteger (max i32Lo (i32Lo - a), min i32Hi (i32Hi - a))
      pure (a, b)
    genSubOk = do
      a <- chooseInteger (i32Lo, i32Hi)
      b <- chooseInteger (max i32Lo (a - i32Hi), min i32Hi (a - i32Lo))
      pure (a, b)
    genMulOk = do
      a <- chooseInteger (i32Lo, i32Hi)
      let bound = if a == 0 then i32Hi else i32Hi `div` abs a
      b <- chooseInteger (negate bound, bound)
      pure (a, b)
    -- Unsigned add / mul: two outcomes each (overflow is the only failure).
    unsignedAdd name showFn hi = do
      ovf <- do
        a <- chooseInteger (1, hi)
        b <- chooseInteger (hi - a + 1, hi)
        pure (a, b)
      ok <- do
        a <- chooseInteger (0, hi)
        b <- chooseInteger (0, hi - a)
        pure (a, b)
      pure [mkOverflowing name showFn hi (+) ab | ab <- [ovf, ok]]
    unsignedMul name showFn hi = do
      ovf <- do
        a <- chooseInteger (2, hi)
        b <- chooseInteger (hi `div` a + 1, hi)
        pure (a, b)
      ok <- do
        a <- chooseInteger (0, hi)
        b <- chooseInteger (0, if a == 0 then hi else hi `div` a)
        pure (a, b)
      pure [mkOverflowing name showFn hi (*) ab | ab <- [ovf, ok]]
    mkOverflowing name showFn hi f (a, b) =
      FoldCaseV name [a, b] (FoldArmLeft "O" showFn) (if f a b > hi then "O" else show (f a b))
    -- Unsigned sub: two outcomes (underflow is the only failure).
    unsignedSub name showFn hi = do
      unf <- do
        a <- chooseInteger (0, hi - 1)
        b <- chooseInteger (a + 1, hi)
        pure (a, b)
      ok <- do
        a <- chooseInteger (0, hi)
        b <- chooseInteger (0, a)
        pure (a, b)
      pure [mk ab | ab <- [unf, ok]]
      where
        mk (a, b) = FoldCaseV name [a, b] (FoldArmLeft "U" showFn) (if a < b then "U" else show (a - b))
    -- Unary succ/pred/neg: the boundary value (the op's only failure) plus a
    -- uniform draw from the full domain.
    unaryCases name showFn marker boundary (lo, hi) oracle = do
      x <- chooseInteger (lo, hi)
      pure [mk boundary, mk x]
      where
        mk a = FoldCaseV name [a] (FoldArmLeft marker showFn) (oracle a)
    -- Equality: a forced-equal pair (uniform sampling almost never produces
    -- one) plus an independent pair.
    eqCases name (lo, hi) = do
      a1 <- chooseInteger (lo, hi)
      a2 <- chooseInteger (lo, hi)
      b2 <- chooseInteger (lo, hi)
      pure
        [ FoldCaseV name [a1, a1] FoldArmBool "T",
          FoldCaseV name [a2, b2] FoldArmBool (if a2 == b2 then "T" else "F")
        ]

-- | Render the generated cases as one Awsum program: a @String@ definition
--   per case plus a @main@ chain printing them \";\"-separated. Every binder
--   name carries the case index — the module-wide no-shadowing rule demands
--   distinct names across all definitions.
renderFoldProgram :: [FoldCaseV] -> Text
renderFoldProgram cs =
  unlines
    ( ["import IO.Stdout", ""]
        <> concatMap defLines (zip [(0 :: Int) ..] cs)
        <> mainLines
    )
  where
    defLines (i, FoldCaseV op args arm _) =
      [ "c" <> show i <> " : String",
        "c" <> show i <> " = case " <> op <> " " <> unwords (map lit args) <> " of"
      ]
        <> armLines i arm
        <> [""]
    lit n = if n < 0 then "(" <> show n <> ")" else show n
    armLines i = \case
      FoldArmRow showFn ->
        [ "  Left e" <> show i <> " -> case e" <> show i <> " of",
          "    (_u" <> show i <> " : UnderflowError) -> \"U\"",
          "    (_o" <> show i <> " : OverflowError) -> \"O\"",
          "  Right v" <> show i <> " -> " <> showFn <> " v" <> show i
        ]
      FoldArmLeft marker showFn ->
        [ "  Left _e" <> show i <> " -> \"" <> marker <> "\"",
          "  Right v" <> show i <> " -> " <> showFn <> " v" <> show i
        ]
      FoldArmBool ->
        [ "  True -> \"T\"",
          "  False -> \"F\""
        ]
    mainLines =
      [ "main : IO Never Unit",
        "main = IO.Stdout.print c0"
      ]
        <> concat
          [ [ "  |> andThenIO (\\_s" <> show i <> " -> IO.Stdout.print \";\")",
              "  |> andThenIO (\\_p" <> show i <> " -> IO.Stdout.print c" <> show i <> ")"
            ]
          | i <- [1 .. length cs - 1]
          ]

constFoldDifferentialSpec :: Spec
constFoldDifferentialSpec =
  describe "constFold-differential"
    -- Each iteration compiles the generated program twice (On + Off, five
    -- backends each) — far costlier than the run-only properties above, and
    -- one iteration already exercises every (operation, outcome) pair.
    $ modifyMaxSuccess (const 10)
    $ prop "folded literal arithmetic matches the runtime helpers on every backend"
    $ forAll genFoldCases
    $ \cs -> ioProperty $ do
      let src = renderFoldProgram cs
          expected = T.intercalate ";" (map fcvExpected cs)
      arts <- (,) <$> compileFromText src <*> compileFromTextWith SimplifyOff src
      results <- runBothStdinBytes arts ""
      pure
        $ counterexample (toString (formatFailure src expected results))
        $ allMatch expected results

-- ════════════════════════════════════════════════════════════════════════════
-- Function-inlining differential
-- ════════════════════════════════════════════════════════════════════════════

-- | One step of a generated helper chain, each exercising one
--   argument-binding shape of the inliner ('Awsum.Simplify'):
--
--     * 'InlPick' — a constructor wrapped and immediately projected
--       (known-projection + case-of-known-constructor cascade); fst keeps
--       the running value, snd replaces it with the step constant — a slot
--       swap in the projection is observable either way;
--     * 'InlDup' — a parameter used twice (binder occurrence counting);
--     * 'InlDrop' — a parameter never used (its argument is dropped
--       unevaluated);
--     * 'InlShare' — a multi-use parameter whose argument is a non-variable
--       expression (an inlined helper call), which the inliner must share
--       through a 'CLet' — the node's only producer, so this leg also runs
--       the 'CLet' lowering on every backend.
--
--   The chain seed is @lengthUtf8Bytes (showInt32 k)@ — string built-ins
--   never const-fold, so the value is a runtime one and the inlined code
--   path actually executes on the SimplifyOn leg (literal seeds would fold
--   the whole chain into a string constant). Constants stay ≤ 1000 and the
--   seed ≤ 11, so no checked add can overflow and the Haskell oracle is the
--   plain formula.
data InlStep
  = InlPick Bool Integer
  | InlDup Integer
  | InlDrop Integer
  | InlShare Integer Integer
  deriving stock (Show)

genInlChain :: Gen (Integer, [InlStep])
genInlChain = do
  seedK <- chooseInteger (-2147483648, 2147483647)
  n <- QC.chooseInt (3, 6)
  steps <- replicateM n step
  pure (seedK, steps)
  where
    smallK = chooseInteger (0, 1000)
    step =
      QC.oneof
        [ InlPick <$> arbitrary <*> smallK,
          InlDup <$> smallK,
          InlDrop <$> smallK,
          InlShare <$> smallK <*> smallK
        ]

-- | The chain's value, computed independently of the compiler.
inlOracle :: Integer -> [InlStep] -> Integer
inlOracle seedK = foldl' apply (toInteger (T.length (show seedK)))
  where
    apply x = \case
      InlPick keepFst c -> if keepFst then x else c
      InlDup c -> x + x + c
      InlDrop _ -> x
      InlShare c c2 -> let y = x + c in y + y + c2

-- | Render the chain as one Awsum program: helpers per step (names carry
--   the step index — module-wide no-shadowing), a @let@-chain threading the
--   running value, and a @main@ printing the final @showUInt32@.
renderInlProgram :: Integer -> [InlStep] -> Text
renderInlProgram seedK steps =
  unlines
    ( [ "import IO.Stdout",
        "",
        "seed : UInt32",
        "seed = lengthUtf8Bytes (showInt32 " <> lit seedK <> ")",
        ""
      ]
        <> concatMap helperLines (zip [(1 :: Int) ..] steps)
        <> resultLines
        <> [ "",
             "main : IO Never Unit",
             "main = IO.Stdout.print result"
           ]
    )
  where
    lit n = if n < 0 then "(" <> show n <> ")" else show n
    sVar i = "s" <> show (i :: Int)
    checkedAddBody fnIx a b kTail tailVar =
      [ "  case addUInt32 " <> a <> " " <> b <> " of",
        "    Left _l" <> fnIx <> " -> 0",
        "    Right r" <> fnIx <> " -> case addUInt32 r" <> fnIx <> " " <> kTail <> " of",
        "      Left _m" <> fnIx <> " -> 0",
        "      Right " <> tailVar <> fnIx <> " -> " <> tailVar <> fnIx
      ]
    helperLines (i, st) = case st of
      InlPick keepFst k ->
        let ix = show i
            (px, py, ret) = if keepFst then ("x" <> ix, "_y" <> ix, "x" <> ix) else ("_x" <> ix, "y" <> ix, "y" <> ix)
         in [ "mk" <> ix <> " : UInt32 -> Tuple2 UInt32 UInt32",
              "mk" <> ix <> " a" <> ix <> " = Tuple2 a" <> ix <> " " <> lit k,
              "",
              "get" <> ix <> " : Tuple2 UInt32 UInt32 -> UInt32",
              "get" <> ix <> " p" <> ix <> " = case p" <> ix <> " of",
              "  Tuple2 " <> px <> " " <> py <> " -> " <> ret,
              ""
            ]
      InlDup k ->
        let ix = show i
         in ["dup" <> ix <> " : UInt32 -> UInt32", "dup" <> ix <> " n" <> ix <> " ="]
              <> checkedAddBody ix ("n" <> ix) ("n" <> ix) (lit k) "t"
              <> [""]
      InlDrop _ ->
        let ix = show i
         in [ "gate" <> ix <> " : UInt32 -> UInt32 -> UInt32",
              "gate" <> ix <> " _g" <> ix <> " w" <> ix <> " = w" <> ix,
              ""
            ]
      InlShare k k2 ->
        let ix = show i
         in ["shr" <> ix <> " : UInt32 -> UInt32", "shr" <> ix <> " n" <> ix <> " ="]
              <> checkedAddBody ix ("n" <> ix) ("n" <> ix) (lit k2) "t"
              <> [ "",
                   "bump" <> ix <> " : UInt32 -> UInt32",
                   "bump" <> ix <> " q" <> ix <> " = case addUInt32 q" <> ix <> " " <> lit k <> " of",
                   "  Left _b" <> ix <> " -> 0",
                   "  Right u" <> ix <> " -> u" <> ix,
                   ""
                 ]
    stepExpr i st prev = case st of
      InlPick _ _ -> "get" <> show i <> " (mk" <> show i <> " " <> prev <> ")"
      InlDup _ -> "dup" <> show i <> " " <> prev
      InlDrop k -> "gate" <> show i <> " " <> lit k <> " " <> prev
      InlShare _ _ -> "shr" <> show i <> " (bump" <> show i <> " " <> prev <> ")"
    resultLines =
      [ "result : String",
        "result =",
        "  let " <> sVar 0 <> " = seed"
      ]
        <> [ "   in let " <> sVar i <> " = " <> stepExpr i st (sVar (i - 1))
           | (i, st) <- zip [1 ..] steps
           ]
        <> ["   in showUInt32 " <> sVar (length steps)]

fnInlineDifferentialSpec :: Spec
fnInlineDifferentialSpec =
  describe "fnInline-differential"
    -- Two compiles per iteration (On + Off, five backends each), like the
    -- const-fold differential; one iteration runs every step shape drawn.
    $ modifyMaxSuccess (const 10)
    $ prop "inlined helper chains match the call-boundary semantics on every backend"
    $ forAll genInlChain
    $ \(seedK, steps) -> ioProperty $ do
      let src = renderInlProgram seedK steps
          expected = show (inlOracle seedK steps)
      arts <- (,) <$> compileFromText src <*> compileFromTextWith SimplifyOff src
      results <- runBothStdinBytes arts ""
      pure
        $ counterexample (toString (formatFailure src expected results))
        $ allMatch expected results

-- | One step of the case-of-case differential's boolean tower. 'CocAnd' /
--   'CocOr' / 'CocNot' compose the prelude combinators — after inlining,
--   each is one more case layered over the previous result, which the
--   fusion re-collapses level by level ('CocOr True' is the shared-arm
--   shape: both inner arms select the same outer arm). 'CocMix' routes the
--   value through a helper whose @True@ arm carries a runtime computation —
--   the inner case then has one literal and one computation arm, so the
--   fusion mints a join point and the lifted @$join@ path runs on every
--   backend.
--
--   The seed is @eqUInt32 (lengthUtf8Bytes (showInt32 k)) 2@ — a runtime
--   'Bool' (string built-ins never const-fold), so the fused dispatch
--   actually executes on the SimplifyOn leg instead of folding away.
data CocStep
  = CocAnd Bool
  | CocOr Bool
  | CocNot
  | CocMix Integer
  deriving stock (Show)

-- | How the tower's value reaches @main@. 'CocPlain' prints it from the
--   value chain directly — residual joins sit in expression position.
--   'CocLoop' threads it through a TCO'd countdown loop whose dispatch is
--   itself a case-of-case with a loop-back outer arm — the minted join's
--   body carries a 'CContinue' and runs once per iteration, the shape the
--   fusion gate excluded until every backend lowered the node natively.
data CocForm = CocPlain | CocLoop
  deriving stock (Show)

genCocChain :: Gen (Integer, [CocStep], CocForm)
genCocChain = do
  seedK <- chooseInteger (-2147483648, 2147483647)
  n <- QC.chooseInt (3, 7)
  steps <- replicateM n step
  form <- QC.elements [CocPlain, CocLoop]
  pure (seedK, steps, form)
  where
    step =
      QC.oneof
        [ CocAnd <$> arbitrary,
          CocOr <$> arbitrary,
          pure CocNot,
          CocMix <$> chooseInteger (-2147483648, 2147483647)
        ]

-- | The tower's value, computed independently of the compiler.
cocOracle :: Integer -> [CocStep] -> Bool
cocOracle seedK = foldl' apply (lenOf seedK == 2)
  where
    lenOf :: Integer -> Int
    lenOf n = T.length (show n)
    apply x = \case
      CocAnd l -> x && l
      CocOr l -> x || l
      CocNot -> not x
      CocMix k -> x && (lenOf k == 3)

-- | Render the tower as one Awsum program: a @mix@ helper per 'CocMix'
--   step (names carry the step index — module-wide no-shadowing) and a
--   @let@-chain threading the running 'Bool'. 'CocPlain' ends the chain
--   in a case printing @"T"@ / @"F"@; 'CocLoop' binds the chain as a
--   @tower@ value, pre-renders the answer, and reaches it through a
--   countdown loop whose dispatch fuses into a join with a loop-back arm
--   in its body (the inner @True@ resolves statically against the small
--   case-free @answer@, the comparison arm jumps, and the outer @False@
--   arm's recursion — a 'CContinue' after TCO — rides along in the body).
renderCocProgram :: Integer -> [CocStep] -> CocForm -> Text
renderCocProgram seedK steps form =
  unlines
    ( [ "import IO.Stdout",
        "",
        "seed : Bool",
        "seed = eqUInt32 (lengthUtf8Bytes (showInt32 " <> lit seedK <> ")) 2",
        ""
      ]
        <> concatMap helperLines (zip [(1 :: Int) ..] steps)
        <> formLines
    )
  where
    lit n = if n < 0 then "(" <> show n <> ")" else show n
    boolLit b = if b then "True" else "False"
    sVar i = "s" <> show (i :: Int)
    helperLines (i, st) = case st of
      CocMix k ->
        let ix = show (i :: Int)
         in [ "mix" <> ix <> " : Bool -> Bool",
              "mix" <> ix <> " b" <> ix <> " = case b" <> ix <> " of",
              "  True -> eqUInt32 (lengthUtf8Bytes (showInt32 " <> lit k <> ")) 3",
              "  False -> False",
              ""
            ]
      _ -> []
    stepExpr i st prev = case st of
      CocAnd l -> "and " <> prev <> " " <> boolLit l
      CocOr l -> "or " <> prev <> " " <> boolLit l
      CocNot -> "not " <> prev
      CocMix _ -> "and (mix" <> show (i :: Int) <> " " <> prev <> ") True"
    chainLines name final =
      [ name <> " =",
        "  let " <> sVar 0 <> " = seed"
      ]
        <> [ "   in let " <> sVar i <> " = " <> stepExpr i st (sVar (i - 1))
           | (i, st) <- zip [1 ..] steps
           ]
        <> ["   in " <> final]
    formLines = case form of
      CocPlain ->
        ("result : String" : chainLines "result" caseTF)
          <> [ "",
               "main : IO Never Unit",
               "main = IO.Stdout.print result"
             ]
        where
          caseTF =
            "case "
              <> sVar (length steps)
              <> " of\n        True -> \"T\"\n        False -> \"F\""
      CocLoop ->
        ("tower : Bool" : chainLines "tower" (sVar (length steps)))
          <> [ "",
               "answer : String",
               "answer = case tower of",
               "  True -> \"T\"",
               "  False -> \"F\"",
               "",
               "spin : UInt32 -> String",
               "spin n = case (case eqUInt32 n 0 of",
               "    True -> True",
               "    False -> eqUInt32 n 1) of",
               "  True -> answer",
               "  False -> (case subUInt32 n 1 of",
               "    Left _e -> \"E\"",
               "    Right m -> spin m)",
               "",
               "main : IO Never Unit",
               "main = IO.Stdout.print (spin 1000)"
             ]

caseOfCaseDifferentialSpec :: Spec
caseOfCaseDifferentialSpec =
  describe "caseOfCase-differential"
    -- Two compiles per iteration (On + Off, five backends each), like the
    -- inlining differential; the tower shapes vary per draw.
    $ modifyMaxSuccess (const 10)
    $ prop "fused boolean towers match the per-level dispatch on every backend"
    $ forAll genCocChain
    $ \(seedK, steps, form) -> ioProperty $ do
      let src = renderCocProgram seedK steps form
          expected = if cocOracle seedK steps then "T" else "F"
      arts <- (,) <$> compileFromText src <*> compileFromTextWith SimplifyOff src
      results <- runBothStdinBytes arts ""
      pure
        $ counterexample (toString (formatFailure src expected results))
        $ allMatch expected results

-- ════════════════════════════════════════════════════════════════════════════
-- Reuse-sharing differential
-- ════════════════════════════════════════════════════════════════════════════

-- | One generated sharing topology. Every shape feeds a structure through
--   a consuming, reuse-shaped loop and (except 'RsLinear') reads a
--   retained part *after* the loop, fusing both reads into stdout — the
--   probe that makes an in-place overwrite of a still-reachable cell
--   visible. The cells are user data ('ReuseGuarded'), so the loop may
--   mutate only what the runtime uniqueness check proves unshared
--   (LLVM/WASM) and nothing at all on the managed backends.
--
--     * 'RsRetained' — the classic caller-retained alias: @let xs@ is
--       reversed, then read again.
--     * 'RsLinear' — no retention: the only soundness obligation is the
--       reversed value itself (and the reuse is free to fire).
--     * 'RsArgTwice' — the same cell reaches one call through both
--       parameters; the first is consumed, the second read after.
--     * 'RsValDef' — a top-level definition (computed once at startup on
--       the managed backends, a fresh getter cell per reference on
--       LLVM/WASM) flows into the consuming loop and is read again.
--     * 'RsDiamond' — both children of every tree node are the same
--       subtree; a consuming left-spine walk runs while the right arms
--       still reach every shared cell.
data RsShape = RsRetained | RsLinear | RsArgTwice | RsValDef | RsDiamond
  deriving stock (Show)

genRsCase :: Gen (RsShape, Int, Int)
genRsCase = do
  shape <- QC.elements [RsRetained, RsLinear, RsArgTwice, RsValDef, RsDiamond]
  len <- QC.chooseInt (1, 4)
  probeIx <- QC.chooseInt (1, 2)
  pure (shape, len, probeIx)

-- | The list the generated @mk@ builds: @mk n Empty@ pushes
--   @showInt32 n@ first, so the final head is @"1"@.
rsMkList :: Int -> [Text]
rsMkList n = map show [1 .. n]

-- | The generated probe: element 1 (head) or element 2, with the same
--   miss markers the rendered helper prints.
rsProbe :: Int -> [Text] -> Text
rsProbe 1 = \case
  [] -> "E"
  (x : _) -> x
rsProbe _ = \case
  [] -> "E"
  [_] -> "e"
  (_ : y : _) -> y

-- | Haskell mirror of the diamond program's tree functions.
data RsTree = RsLeaf | RsNode RsTree Text RsTree

rsMkTree :: Int -> RsTree -> RsTree
rsMkTree n acc
  | n <= 0 = acc
  | otherwise = rsMkTree (n - 1) (RsNode acc (show n) acc)

rsSumLeft :: RsTree -> RsTree -> RsTree
rsSumLeft RsLeaf acc = acc
rsSumLeft (RsNode l v _) acc = rsSumLeft l (RsNode acc v RsLeaf)

rsTopV :: RsTree -> Text
rsTopV RsLeaf = "L"
rsTopV (RsNode _ v _) = v

rsRightV :: RsTree -> Text
rsRightV RsLeaf = "L"
rsRightV (RsNode _ _ r) = rsTopV r

rsOracle :: RsShape -> Int -> Int -> Text
rsOracle shape len probeIx =
  let l = rsMkList len
      p = rsProbe probeIx
   in case shape of
        RsRetained -> p (reverse l) <> p l
        RsLinear -> p (reverse l)
        RsArgTwice -> p (reverse l) <> p l
        RsValDef -> p (reverse l) <> p l
        RsDiamond ->
          let s = rsMkTree len RsLeaf
           in rsTopV (rsSumLeft s RsLeaf) <> rsRightV s

-- | Render the topology as one Awsum program. The list/tree contents
--   come from @showInt32@ of the loop counter — runtime values, so
--   nothing folds at compile time; the loops themselves are recursive
--   and never inline.
renderRsProgram :: RsShape -> Int -> Int -> Text
renderRsProgram shape len probeIx =
  unlines (["import IO.Stdout", ""] <> body)
  where
    lenT = show len
    probeLines =
      case probeIx of
        1 ->
          [ "probe : Stack -> String",
            "probe st = case st of",
            "  Empty -> \"E\"",
            "  Push s2 _r -> s2",
            ""
          ]
        _ ->
          [ "probe : Stack -> String",
            "probe st = case st of",
            "  Empty -> \"E\"",
            "  Push _s2 r -> case r of",
            "    Empty -> \"e\"",
            "    Push s3 _r2 -> s3",
            ""
          ]
    stackLines =
      [ "type Stack = Empty | Push String Stack",
        "",
        "mk : Int32 -> Stack -> Stack",
        "mk n acc = case eqInt32 n 0 of",
        "  True -> acc",
        "  False -> case predInt32 n of",
        "    Left _u -> acc",
        "    Right m -> mk m (Push (showInt32 n) acc)",
        "",
        "revInto2 : Stack -> Stack -> Stack",
        "revInto2 lst acc2 = case lst of",
        "  Empty -> acc2",
        "  Push s rest -> revInto2 rest (Push s acc2)",
        ""
      ]
        <> probeLines
    body = case shape of
      RsRetained ->
        stackLines
          <> [ "main : IO Never Unit",
               "main =",
               "  let xs = mk " <> lenT <> " Empty",
               "   in IO.Stdout.print (probe (revInto2 xs Empty))",
               "        |> andThenIO (\\_u2 -> IO.Stdout.print (probe xs))"
             ]
      RsLinear ->
        stackLines
          <> [ "main : IO Never Unit",
               "main = IO.Stdout.print (probe (revInto2 (mk " <> lenT <> " Empty) Empty))"
             ]
      RsArgTwice ->
        stackLines
          <> [ "both : Stack -> Stack -> String",
               "both a b =",
               "  let x = probe (revInto2 a Empty)",
               "   in let y = probe b",
               "       in case x ++ y of",
               "            Left _e -> \"L\"",
               "            Right z -> z",
               "",
               "main : IO Never Unit",
               "main =",
               "  let xs = mk " <> lenT <> " Empty",
               "   in IO.Stdout.print (both xs xs)"
             ]
      RsValDef ->
        stackLines
          <> [ "topDef : Stack",
               "topDef = mk " <> lenT <> " Empty",
               "",
               "main : IO Never Unit",
               "main =",
               "  IO.Stdout.print (probe (revInto2 topDef Empty))",
               "    |> andThenIO (\\_u2 -> IO.Stdout.print (probe topDef))"
             ]
      RsDiamond ->
        [ "type Tree = Leaf | Node Tree String Tree",
          "",
          "mk2 : Int32 -> Tree -> Tree",
          "mk2 n acc = case eqInt32 n 0 of",
          "  True -> acc",
          "  False -> case predInt32 n of",
          "    Left _u -> acc",
          "    Right m -> mk2 m (Node acc (showInt32 n) acc)",
          "",
          "sumLeft : Tree -> Tree -> Tree",
          "sumLeft t acc = case t of",
          "  Leaf -> acc",
          "  Node l v r -> sumLeft l (Node acc v Leaf)",
          "",
          "topV : Tree -> String",
          "topV t2 = case t2 of",
          "  Leaf -> \"L\"",
          "  Node _l3 v3 _r3 -> v3",
          "",
          "rightV : Tree -> String",
          "rightV t4 = case t4 of",
          "  Leaf -> \"L\"",
          "  Node _l5 _v5 r5 -> topV r5",
          "",
          "main : IO Never Unit",
          "main =",
          "  let s = mk2 " <> lenT <> " Leaf",
          "   in IO.Stdout.print (topV (sumLeft s Leaf))",
          "        |> andThenIO (\\_u2 -> IO.Stdout.print (rightV s))"
        ]

reuseSharingDifferentialSpec :: Spec
reuseSharingDifferentialSpec =
  describe "reuseSharing-differential"
    -- Two compiles per iteration (On + Off, five backends each), like the
    -- inlining differential.
    $ modifyMaxSuccess (const 10)
    $ prop "consuming loops never mutate a still-reachable cell on any backend"
    $ forAll genRsCase
    $ \(shape, len, probeIx) -> ioProperty $ do
      let src = renderRsProgram shape len probeIx
          expected = rsOracle shape len probeIx
      arts <- (,) <$> compileFromText src <*> compileFromTextWith SimplifyOff src
      results <- runBothStdinBytes arts ""
      pure
        $ counterexample (toString (formatFailure src expected results))
        $ allMatch expected results
