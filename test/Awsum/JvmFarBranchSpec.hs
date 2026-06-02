-- | Hspec tests for JVM far-branch widening in 'Awsum.Codegen.JVM.Assemble'.
--   JVM @goto@ / @if*@ offsets are signed 16-bit (±32767); a method larger than
--   that has branches the assembler must widen — a @goto@ to @goto_w@, a
--   conditional to @if<¬cond> SKIP; goto_w TARGET; SKIP:@ with a synthesized
--   skip frame. Without widening the JVM rejects the class at load
--   (@VerifyError@), so each test asserts the program runs on @java@ and
--   computes the right value — i.e. the bytecode load-verifies.
--
--   Run JVM-only on purpose: the fix is JVM-specific, and 'compileFromText'
--   would eagerly invoke @clang@, which is slow on the multi-thousand-element
--   literal the far-conditional case needs. Going straight from 'assembleJVM'
--   to @java@ keeps these fast.
module Awsum.JvmFarBranchSpec (spec) where

import Awsum.Codegen.JVM.Assemble (assembleJVM, renderJvmLimitExceeded)
import Awsum.ElaborateLower (elaborateLowerProgram)
import Awsum.Parser (parseProgram)
import Awsum.Prelude (withPrelude)
import Awsum.Program (ProgramType (..))
import Awsum.RunBackend (runJVM, runJVMStdin)
import Relude
import Test.Hspec

-- | Parse → withPrelude → elaborate → assemble the JVM class bytes. Parse and
--   elaborate failures are test bugs (the source is generated), so they
--   'error'; a 'JvmLimitExceeded' (a method over the 65535-byte cap) means the
--   test sized something wrong and is surfaced as a failure by the caller.
assembleProgram :: Text -> Either Text ByteString
assembleProgram src =
  case parseProgram src of
    Left e -> error ("parse failed: " <> e)
    Right prog -> case elaborateLowerProgram ProgramCli (withPrelude prog) of
      Left err -> error ("elaborate failed: " <> show err)
      Right (_warns, ptags, core) -> first renderJvmLimitExceeded (assembleJVM ptags core)

-- | @n@ mutually recursive functions @f0 → f1 → … → f(n-1) → f0@, each
--   decrementing its argument and returning its own index when the argument
--   reaches zero. The stack-safety pipeline fuses the whole group into one
--   self-recursive @$scc$@ method; at @n@ this big enough, its TCO back-edge
--   (@CContinue@ → @goto@ to offset 0) overflows the 16-bit @goto@ offset and
--   must widen to @goto_w@. @f0 1000000@ returns @1000000 `mod` n@.
mkMutualRec :: Int -> Text
mkMutualRec n =
  unlines
    $ ["import IO.Stdout", ""]
    <> concatMap fdef [0 .. n - 1]
    <> ["main : IO Never Unit", "main = IO.Stdout.print (showInt32 (f0 1000000))"]
  where
    fdef i =
      let nxt = if i == n - 1 then 0 else i + 1
       in [ "f" <> show i <> " : Int32 -> Int32",
            "f" <> show i <> " n = case eqInt32 n 0 of",
            "  True -> " <> show i,
            "  False -> case predInt32 n of",
            "    Left _e -> " <> show i,
            "    Right m -> f" <> show nxt <> " m",
            ""
          ]

-- | A program whose @pick@ dispatches on a runtime-derived constructor (so the
--   case survives to codegen) with a middle arm built from a @depth@-deep list
--   literal. That arm's bytecode exceeds 32 KB, so the dispatch's @if_icmpne@
--   jumping over it is a far conditional the assembler must rewrite with
--   @goto_w@ and a synthesized skip frame. Feeding @"b"@ on stdin selects the
--   big arm; the result is @depth@.
mkHugeArmCase :: Int -> Text
mkHugeArmCase depth =
  let nested = foldr (\_ acc -> "(ICons 1 " <> acc <> ")") "INil" [1 .. depth]
   in unlines
        [ "import IO.Stdout",
          "import IO.Stdin",
          "",
          "type Three = A | B | C",
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
          "classify : String -> Three",
          "classify s = case eqString s \"b\" of",
          "  True -> B",
          "  False -> case eqString s \"c\" of",
          "    True -> C",
          "    False -> A",
          "",
          "pick : Three -> Int32",
          "pick t = case t of",
          "  A -> 1",
          "  B -> sumList " <> nested <> " 0",
          "  C -> 3",
          "",
          "handleErr : (StringTooLong | InvalidUtf8) -> IO Never Unit",
          "handleErr _e = IO.Stdout.print \"ERR\"",
          "",
          "run : String -> IO Never Unit",
          "run s = IO.Stdout.print (showInt32 (pick (classify s)))",
          "",
          "main : IO Never Unit",
          "main = IO.Stdin.readAllString |> andThenIO run |> handleErrorIO handleErr"
        ]

spec :: Spec
spec = describe "JVM far-branch widening" $ do
  it "runs a large fused mutual-recursion method (far goto → goto_w)"
    $ case assembleProgram (mkMutualRec 300) of
      Left e -> expectationFailure ("JVM assembly failed: " <> toString e)
      Right bytes -> do
        out <- runJVM bytes ""
        out `shouldBe` Right "100" -- 1000000 `mod` 300
  it "runs a method with a >32 KB case arm (far conditional → invert + goto_w + skip frame)"
    $ case assembleProgram (mkHugeArmCase 2000) of
      Left e -> expectationFailure ("JVM assembly failed: " <> toString e)
      Right bytes -> do
        out <- runJVMStdin bytes "b"
        out `shouldBe` Right "2000"
