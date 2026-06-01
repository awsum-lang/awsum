-- | Hspec test for the per-target JVM method-size refusal
--   ('JvmMethodTooLarge' in 'Awsum.Codegen.JVM.Assemble'). The JVM caps a
--   method's @Code@ at 65535 bytes (@code_length@, JVM Spec §4.7.3); a larger
--   method yields a class the JVM rejects at load. 'assembleJVM' now refuses
--   such a program at compile time instead of emitting the invalid @.class@.
--
--   This is a per-target compile-time limit — see docs/targets.md. The other
--   four backends impose no such cap and are not exercised here: the refusal
--   lives solely in 'assembleJVM', so a JVM 'Left' is the whole behaviour.
--
--   The trigger is a deeply nested list literal, which lowers into one
--   straight-line @v_main@ body (no loops, so no far branches — this is a
--   genuine code_length overflow, distinct from the goto-offset story). At
--   depth 3000 the body is 66069 bytes; depth 3500 is used here for margin
--   against minor codegen drift. If a future JVM-codegen change shrinks the
--   body under the cap at this depth, bump the depth — the assertion pins the
--   refusal and its reported size, not a particular depth.
module Awsum.JvmMethodLimitSpec (spec) where

import Awsum.Codegen.JVM.Assemble (JvmLimitExceeded (..), assembleJVM)
import Awsum.ElaborateLower (elaborateLowerProgram)
import Awsum.Parser (parseProgram)
import Awsum.Prelude (withPrelude)
import Awsum.Program (ProgramType (..))
import Relude
import Test.Hspec

-- | A program whose @main@ sums a list literal of the given nesting depth.
--   The literal lowers into a single straight-line @v_main@ method, so its
--   bytecode size grows linearly with @depth@.
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
spec = describe "JVM per-method bytecode limit" $ do
  it "assembles a small program (method well under the 65535-byte cap)"
    $ case assembleProgram (mkDeepListProgram 100) of
      Right _bytes -> pass
      Left e -> expectationFailure ("unexpected JVM refusal of `" <> toString (jleMethod e) <> "`")

  it "refuses a program whose `v_main` method exceeds the 65535-byte cap"
    $ case assembleProgram (mkDeepListProgram 3500) of
      Left (JvmMethodTooLarge name n) -> do
        name `shouldBe` "v_main"
        n `shouldSatisfy` (> 65535)
      Right _bytes -> expectationFailure "expected a JVM refusal, got a class file"
