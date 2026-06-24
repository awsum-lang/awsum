-- | Hspec tests for the per-target JVM class-file limit refusals
--   ('JvmLimitExceeded' in 'Awsum.Codegen.JVM.Assemble'). Several class-file
--   fields cannot represent an arbitrarily large program: a method's @Code@ is
--   capped at 65535 bytes (@code_length@, §4.7.3), and the u2 fields cap their
--   value at 65535 — @constant_pool_count@ (§4.1), a method's @max_stack@ /
--   @max_locals@ (§4.7.3), and each @CONSTANT_Utf8_info@ length (§4.4.7); a
--   method descriptor also encodes at most 255 parameters (§4.3.3). Past a limit
--   the field wraps (or the descriptor is rejected) and silently corrupts the
--   @.class@, which the JVM rejects at load; 'assembleJVM' refuses the program at
--   compile time instead.
--
--   These are per-target compile-time limits — see docs/targets.md. The other
--   four backends impose no such caps, so the refusal lives solely in
--   'assembleJVM' and a JVM 'Left' is the whole behaviour exercised here.
module Awsum.JvmClassFileLimitSpec (spec) where

import Awsum.Codegen.JVM.Assemble (JvmLimitExceeded (..), assembleJVM, methodLimitViolations, renderJvmLimitExceeded, selectLimit)
import Awsum.Core (CDecl (..), CExpr (..), CoreProgram (..))
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
--   The method @v_f@ carries @p@ @Object@ parameters, so @p > 255@ trips the
--   §4.3.3 descriptor-arity limit ('JvmTooManyParameters'). Recursive so Simplify
--   can't fold the all-literal call and tree-shake the many-parameter method.
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

-- | Assemble a trivial program with an extra top-level constant holding an
--   @n@-byte ASCII string, injected into its Core after elaboration. This is the
--   one way to exercise the over-long-string-constant cause of
--   'JvmConstantTooLong', which is distinct from descriptor arity: a source
--   literal is capped so a single one fits ('maxStringLitUtf16CodeUnits' = 21845
--   ⇒ ≤ 65535 bytes), and 'Awsum.Simplify' deliberately does not fold @++@ for
--   exactly this reason — so no source program produces one, but a folded
--   concatenation would, and this guard is the safety net that decision relies
--   on. 'doAssemble' assembles every declaration, so the constant's
--   @CONSTANT_Utf8_info@ reaches the pool.
assembleWithStringConstant :: Int -> Either JvmLimitExceeded ByteString
assembleWithStringConstant n =
  case parseProgram trivial of
    Left e -> error ("parse failed: " <> e)
    Right prog -> case elaborateLowerProgram ProgramCli (withPrelude prog) of
      Left err -> error ("elaborate failed: " <> show err)
      Right (_warns, ptags, CoreProgram decls) ->
        assembleJVM ptags (CoreProgram (decls <> [CValDef "bigConstant" (CString (T.replicate n "a"))]))
  where
    trivial = unlines ["import IO.Stdout", "", "main : IO Never Unit", "main = IO.Stdout.print \"hi\""]

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

  describe "method parameter count (descriptor arity, §4.3.3)" $ do
    it "assembles a function at the 255-parameter limit"
      $ case assembleProgram (mkManyParamProgram 255) of
        Right _bytes -> pass
        Left e -> expectationFailure ("unexpected JVM refusal: " <> toString (renderJvmLimitExceeded e))

    it "refuses a function with more than 255 parameters"
      $ case assembleProgram (mkManyParamProgram 256) of
        Left (JvmTooManyParameters name nparams) -> do
          name `shouldBe` "v_f"
          nparams `shouldBe` 256
        Left other -> expectationFailure ("expected JvmTooManyParameters, got: " <> toString (renderJvmLimitExceeded other))
        Right _bytes -> expectationFailure "expected a JVM refusal, got a class file"

  -- A cause independent of arity: a small program with one over-long string
  -- constant. Not producible from source today (see 'assembleWithStringConstant'),
  -- so the constant is injected into the Core after elaboration.
  describe "single Utf8 entry length (CONSTANT_Utf8_info length, §4.4.7)"
    $ it "refuses an over-long string constant (the cause a folded `++` would create)"
    $ case assembleWithStringConstant 70000 of
      Left (JvmConstantTooLong _preview nbytes) -> nbytes `shouldSatisfy` (> 65535)
      Left other -> expectationFailure ("expected JvmConstantTooLong, got: " <> toString (renderJvmLimitExceeded other))
      Right _bytes -> expectationFailure "expected a JVM refusal, got a class file"

  -- max_stack / max_locals over 65535 cannot be isolated through a real program:
  -- they are reached only alongside a code-length or descriptor overflow that
  -- bounds them. So these caps and the priority that orders co-occurring limits
  -- are tested directly on their pure functions.
  describe "per-method limit detection and reported-limit priority" $ do
    it "flags an over-255 parameter count, max_stack, and max_locals per method" $ do
      methodLimitViolations "m" 256 10 10 10 `shouldBe` [JvmTooManyParameters "m" 256]
      methodLimitViolations "m" 10 10 70000 10 `shouldBe` [JvmMaxStackTooLarge "m" 70000]
      methodLimitViolations "m" 10 10 10 70000 `shouldBe` [JvmMaxLocalsTooLarge "m" 70000]
      methodLimitViolations "m" 255 65535 65535 65535 `shouldBe` []

    it "reports the actionable cause ahead of a co-occurring symptom" $ do
      -- A high-arity method trips its parameter count and (past ~3640) its
      -- descriptor's Utf8 length; the parameter count is the actionable cause.
      selectLimit [JvmConstantTooLong "(L…)" 72000, JvmTooManyParameters "f" 4000]
        `shouldBe` Just (JvmTooManyParameters "f" 4000)
      selectLimit [JvmMaxLocalsTooLarge "f" 70000, JvmConstantTooLong "(L…)" 72000]
        `shouldBe` Just (JvmConstantTooLong "(L…)" 72000)
      selectLimit [JvmMaxStackTooLarge "f" 70000, JvmMethodTooLarge "f" 70000]
        `shouldBe` Just (JvmMethodTooLarge "f" 70000)
      selectLimit [] `shouldBe` Nothing

  -- The diagnostic distinguishes a user function from a compiler-synthesised
  -- method by the mangled `v_$…` name. Regression: the synthetic check must match
  -- the mangled name, not the raw `$scc$` Core prefix (which never matches a
  -- `v_`-prefixed method name, so the provenance hint was previously dead).
  describe "diagnostic phrasing" $ do
    it "names a user function plainly"
      $ renderJvmLimitExceeded (JvmTooManyParameters "v_f" 256)
      `shouldSatisfy` T.isInfixOf "function `v_f`"

    it "marks a synthesised method and explains its origin" $ do
      let scc = renderJvmLimitExceeded (JvmMethodTooLarge "v_$scc$f" 70000)
      scc `shouldSatisfy` T.isInfixOf "synthetic method"
      scc `shouldSatisfy` T.isInfixOf "mutual-recursion"
      renderJvmLimitExceeded (JvmTooManyParameters "v_$apply2" 300)
        `shouldSatisfy` T.isInfixOf "synthetic method"
