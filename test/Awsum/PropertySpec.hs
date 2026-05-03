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

import Awsum.RunBackend (Backend, CompiledArtifacts, compileFromFile, runOnAll)
import Data.ByteString qualified as BS
import Data.Text qualified as T
import Relude
import System.FilePath ((</>))
import Test.Hspec
import Test.Hspec.QuickCheck (modifyMaxSuccess, prop)
import Test.QuickCheck (Arbitrary (..), Gen, chooseBoundedIntegral, chooseInteger, counterexample, elements, forAll, frequency, ioProperty, listOf, listOf1)
import Test.QuickCheck qualified as QC

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

propertySourceFile :: FilePath -> FilePath
propertySourceFile dir = "test/sources/property" </> dir </> "code" </> "Main.aww"

spec :: Spec
spec = describe "Property tests"
  $ modifyMaxSuccess (const 100)
  $ forM_ properties
  $ \(SomeProperty p) ->
    describe (toString p.propName) $ do
      artifacts <- runIO (compileFromFile (propertySourceFile p.propSourceDir))
      prop "holds on every backend" (runProperty artifacts p)

runProperty :: (Show a) => CompiledArtifacts -> Property a -> QC.Property
runProperty artifacts p =
  forAll p.propGen $ \a -> ioProperty $ do
    let input = p.propEncode a
        expected = p.propExpectedOutput a
    results <- runOnAll artifacts input
    pure
      $ counterexample (toString (formatFailure input expected results))
      $ allMatch expected results

allMatch :: Text -> [(Backend, Either Text Text)] -> Bool
allMatch expected = all $ \(_, r) -> case r of
  Right out -> out == expected
  Left _ -> False

formatFailure :: Text -> Text -> [(Backend, Either Text Text)] -> Text
formatFailure input expected results =
  unlines
    $ ["input:    " <> show input, "expected: " <> show expected, "results:"]
    <> ["  " <> show b <> ": " <> formatOne expected r | (b, r) <- results]
  where
    formatOne :: Text -> Either Text Text -> Text
    formatOne e (Right o)
      | o == e = "OK"
      | otherwise = "GOT " <> show o
    formatOne _ (Left e) = "ERROR " <> show e

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
--   Constructed in three stages: a uniform, b uniform from the
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
--   Same shape as 'NoOverflowMulUInt8Triple' on the full u32 range —
--   bound every intermediate product, not just the left-grouping ones.
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
lengthBytesAsUtf8Hs :: Text -> Word32
lengthBytesAsUtf8Hs = fromIntegral . BS.length . encodeUtf8

-- ════════════════════════════════════════════════════════════════════════════
-- Property catalogue
-- ════════════════════════════════════════════════════════════════════════════

properties :: [SomeProperty]
properties =
  [ -- ── Integer arithmetic (commutativity, identity, agreement) ──
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
          <> show (lengthBytesAsUtf8Hs s)
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
