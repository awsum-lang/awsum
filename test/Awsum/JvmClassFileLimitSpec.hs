-- | Hspec tests for the per-target JVM class-file limit refusals
--   ('JvmLimitExceeded' in 'Awsum.Codegen.JVM.Assemble'). Several class-file
--   fields cannot represent an arbitrarily large program: a method's @Code@ is
--   capped at 65535 bytes (@code_length@, §4.7.3), and the u2 fields cap their
--   value at 65535 — @constant_pool_count@ (§4.1), a method's @max_stack@ /
--   @max_locals@ (§4.7.3), and each @CONSTANT_Utf8_info@ length (§4.4.7). Past
--   the limit the field wraps and silently corrupts the @.class@, which the JVM
--   rejects at load; 'assembleJVM' refuses the program at compile time instead.
--
--   These are per-target compile-time limits — see docs/targets.md. The other
--   four backends impose no such caps, so the refusal lives solely in
--   'assembleJVM' and a JVM 'Left' is the whole behaviour exercised here.
module Awsum.JvmClassFileLimitSpec (spec) where

import Awsum.Codegen.JVM.Assemble (JvmLimitExceeded (..), assembleJVM, methodLimitViolations, renderJvmLimitExceeded, selectLimit)
import Awsum.ElaborateLower (elaborateLowerProgram)
import Awsum.Parser (parseProgram)
import Awsum.Prelude (withPrelude)
import Awsum.Program (ProgramType (..))
import Data.Text qualified as T
import Relude
import Test.Hspec

-- | A program whose @main@ sums a list literal of the given nesting depth.
--   The literal lowers into a single straight-line @v_main@ method, so its
--   bytecode size grows linearly with @depth@ — the @code_length@ trigger.
mkDeepListProgram :: Int -> Text
mkDeepListProgram depth =
  let nested = foldr (\_ acc -> "(ICons 1 " <> acc <> ")") "INil" [1 .. depth]
   in unlines
        [ "import IO.Stdout",
          "",
          "type IntList = INil | ICons Int32 IntList",
          "",
          "sumList : IntList -> Int32 -> Int32",
          "sumList lst acc = case lst of",
          "  INil -> acc",
          "  ICons x xs -> case addInt32 acc x of",
          "    Left _e -> acc",
          "    Right n -> sumList xs n",
          "",
          "main : IO Never Unit",
          "main = IO.Stdout.print (showInt32 (sumList " <> nested <> " 0))"
        ]

-- | A chain of @n@ recursive single-argument functions, @f1@ … @fn@, each with
--   its own three string literals. Recursion keeps each function a separate
--   method (Simplify never inlines a 'CLoop'), so the constant pool accumulates
--   ~6.4 distinct entries per function — the @constant_pool_count@ trigger.
mkConstantPoolProgram :: Int -> Text
mkConstantPoolProgram n =
  unlines
    $ ["import IO.Stdout", ""]
    <> concatMap fn [1 .. n]
    <> ["main : IO Never Unit", "main = IO.Stdout.print (f1 0)"]
  where
    fn i =
      [ "f" <> show i <> " : Int32 -> String",
        "f" <> show i <> " n = case eqInt32 n 0 of",
        if i < n
          then "  True -> f" <> show (i + 1) <> " 0"
          else "  True -> \"end-" <> show n <> "\"",
        "  False -> case predInt32 n of",
        "    Left _e -> \"litA-" <> show i <> "\"",
        "    Right m -> case eqInt32 m 999 of",
        "      True -> \"litB-" <> show i <> "\"",
        "      False -> \"litC-" <> show i <> "\"",
        ""
      ]

-- | One recursive function of @p@ parameters; @main@ applies it to @p@ zeros.
--   The method descriptor is @(Ljava\/lang\/Object;…)Ljava\/lang\/Object;@ —
--   one @CONSTANT_Utf8_info@ of @18·p + 21@ bytes — so a large @p@ overflows a
--   single Utf8 entry. Recursive so Simplify can't fold the all-literal call and
--   tree-shake the method whose descriptor is the over-long string. Identifiers
--   (≤ 1024 chars) and string literals (≤ 21845 code units ⇒ ≤ 65535 bytes) are
--   capped below the u2 limit, so an extreme arity is the only way to reach it.
mkManyParamProgram :: Int -> Text
mkManyParamProgram p =
  let params = ["p" <> show i | i <- [0 .. p - 1]]
      sig = "f : " <> T.intercalate " -> " (replicate (p + 1) "Int32")
      recCall = unwords ("m" : drop 1 params) -- p0 := m, rest passed through
      args = unwords (replicate p "0")
   in unlines
        [ "import IO.Stdout",
          "",
          sig,
          "f " <> unwords params <> " = case eqInt32 p0 0 of",
          "  True -> p0",
          "  False -> case predInt32 p0 of",
          "    Left _e -> p0",
          "    Right m -> f " <> recCall,
          "",
          "main : IO Never Unit",
          "main = IO.Stdout.print (showInt32 (f " <> args <> "))"
        ]

-- | Parse → withPrelude → elaborate → assemble the JVM class bytes. Parse and
--   elaborate failures are test bugs (the source is generated), so they
--   'error'; the result is whatever 'assembleJVM' decides.
assembleProgram :: Text -> Either JvmLimitExceeded ByteString
assembleProgram src =
  case parseProgram src of
    Left e -> error ("parse failed: " <> e)
    Right prog -> case elaborateLowerProgram ProgramCli (withPrelude prog) of
      Left err -> error ("elaborate failed: " <> show err)
      Right (_warns, ptags, core) -> assembleJVM ptags core

spec :: Spec
spec = describe "JVM class-file limits" $ do
  describe "per-method bytecode size (code_length, §4.7.3)" $ do
    it "assembles a small program (method well under the 65535-byte cap)"
      $ case assembleProgram (mkDeepListProgram 100) of
        Right _bytes -> pass
        Left e -> expectationFailure ("unexpected JVM refusal: " <> toString (renderJvmLimitExceeded e))

    -- depth 3500 leaves margin over the cap against minor codegen drift; if a
    -- change shrinks the body under it, bump the depth (the assertion pins the
    -- refusal and reported size, not the depth).
    it "refuses a program whose `v_main` method exceeds the 65535-byte cap"
      $ case assembleProgram (mkDeepListProgram 3500) of
        Left (JvmMethodTooLarge name nbytes) -> do
          name `shouldBe` "v_main"
          nbytes `shouldSatisfy` (> 65535)
        Left other -> expectationFailure ("expected JvmMethodTooLarge, got: " <> toString (renderJvmLimitExceeded other))
        Right _bytes -> expectationFailure "expected a JVM refusal, got a class file"

  -- ~11000 recursive functions accumulate ~70k pool entries; the threshold is
  -- ~10200, so the margin is ~5k entries. If a codegen change drops the
  -- per-function entry count enough to fall under, this goes Right — bump n.
  describe "constant-pool count (constant_pool_count, §4.1)"
    $ it "refuses a program needing more than 65535 constant-pool entries"
    $ case assembleProgram (mkConstantPoolProgram 11000) of
      Left (JvmConstantPoolOverflow count) -> count `shouldSatisfy` (> 65535)
      Left other -> expectationFailure ("expected JvmConstantPoolOverflow, got: " <> toString (renderJvmLimitExceeded other))
      Right _bytes -> expectationFailure "expected a JVM refusal, got a class file"

  -- 4000 parameters ⇒ a ~72k-byte descriptor (threshold ~3640); one over-long
  -- Utf8 entry, no other limit crossed (max_locals = 4000).
  describe "single Utf8 entry length (CONSTANT_Utf8_info length, §4.4.7)"
    $ it "refuses a function whose method descriptor exceeds 65535 bytes"
    $ case assembleProgram (mkManyParamProgram 4000) of
      Left (JvmConstantTooLong _preview nbytes) -> nbytes `shouldSatisfy` (> 65535)
      Left other -> expectationFailure ("expected JvmConstantTooLong, got: " <> toString (renderJvmLimitExceeded other))
      Right _bytes -> expectationFailure "expected a JVM refusal, got a class file"

  -- max_stack / max_locals cannot be isolated through a real program: an
  -- over-65535 value is always reached alongside a code-length or descriptor
  -- overflow (both bound it), which 'selectLimit' surfaces first. So the
  -- per-method check and the priority that orders co-occurring limits are tested
  -- directly on their pure functions.
  describe "max_stack / max_locals (§4.7.3) and reported-limit priority" $ do
    it "flags max_stack and max_locals over 65535 per method" $ do
      methodLimitViolations "m" 10 70000 10 `shouldBe` [JvmMaxStackTooLarge "m" 70000]
      methodLimitViolations "m" 10 10 70000 `shouldBe` [JvmMaxLocalsTooLarge "m" 70000]
      methodLimitViolations "m" 65535 65535 65535 `shouldBe` []

    it "reports the actionable cause ahead of a co-occurring max_stack / max_locals" $ do
      selectLimit [JvmMaxLocalsTooLarge "f" 70000, JvmConstantTooLong "(L…)" 72000]
        `shouldBe` Just (JvmConstantTooLong "(L…)" 72000)
      selectLimit [JvmMaxStackTooLarge "f" 70000, JvmMethodTooLarge "f" 70000]
        `shouldBe` Just (JvmMethodTooLarge "f" 70000)
      selectLimit [] `shouldBe` Nothing
