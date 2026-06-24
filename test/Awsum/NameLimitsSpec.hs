-- | Tests for the two name-length limits:
--
--   * the parse-time cap on /source/ identifiers
--     ('Awsum.Parser.maxIdentifierChars'), and
--   * the lowering-time shortening of /synthesised/ top-level names
--     ('Awsum.ShortenNames.shortenSynthesizedNames').
--
--   Both keep emitted symbols inside every backend's limit — most sharply
--   JVM's 65535-byte @CONSTANT_Utf8@. A program that overflows it for real
--   needs thousands of fused functions, impractical as a fixture; these
--   exercise the bounding logic directly instead (cf. 'jsSyntaxSpec' for the
--   same synthetic-input approach to a codegen invariant).
module Awsum.NameLimitsSpec (spec) where

import Awsum.CallGraph (declName)
import Awsum.Core (CDecl (..), CExpr (..), CoreProgram (..), freeVars)
import Awsum.Parser (maxIdentifierChars, parseProgram)
import Awsum.ShortenNames (shortNameFor, shortenSynthesizedNames, synthNameThreshold)
import Awsum.Syntax (Name)
import Data.Text qualified as T
import Relude
import Test.Hspec

spec :: Spec
spec = do
  identifierCapSpec
  shorteningSpec

-- ── Source identifier cap (parse time) ───────────────────────────────────────

-- | A minimal program whose top-level name is @name@.
mkProgram :: Text -> Text
mkProgram name =
  unlines
    [ "import IO.Stdout",
      "",
      name <> " : String",
      name <> " = \"x\"",
      "",
      "main : IO Never Unit",
      "main = IO.Stdout.print " <> name
    ]

identifierCapSpec :: Spec
identifierCapSpec = describe "Source identifier length cap" $ do
  it "accepts an identifier at the cap"
    $ parseProgram (mkProgram (T.replicate maxIdentifierChars "a"))
    `shouldSatisfy` isRight

  it "rejects an identifier well past the cap, with a clear message"
    $ case parseProgram (mkProgram (T.replicate (maxIdentifierChars + 50) "a")) of
      Left msg -> msg `shouldSatisfy` T.isInfixOf "identifier too long"
      Right _ -> expectationFailure "expected the over-long identifier to be rejected"

-- ── Synthesised name shortening (lowering) ───────────────────────────────────

-- | A synthesised ($-prefixed) name past the threshold — must be rewritten.
longSynth :: Name
longSynth = "$scc$" <> T.replicate (synthNameThreshold + 100) "a"

-- | A user name (no $) past the threshold — must be left alone (it is the
--   parser's job to cap those; the pass must never touch a user name).
longUser :: Name
longUser = T.replicate (synthNameThreshold + 100) "b"

-- | Every name a program mentions: each declaration's own name plus the
--   free variables of its body (which include referenced top-level names).
allNames :: CoreProgram -> [Name]
allNames (CoreProgram ds) = concatMap names ds
  where
    names (CFunDef n _ b) = n : toList (freeVars b)
    names (CValDef n b) = n : toList (freeVars b)

sampleProgram :: CoreProgram
sampleProgram =
  CoreProgram
    [ CFunDef longSynth ["x"] (CCall (CVar "$cps$short") [CVar "x"]),
      CFunDef "$cps$short" ["y"] (CCall (CVar longSynth) [CVar "y"]),
      CFunDef longUser ["z"] (CVar "z"),
      CValDef "main" (CCall (CVar longSynth) [])
    ]

shorteningSpec :: Spec
shorteningSpec = describe "Synthesised name shortening" $ do
  let result = shortenSynthesizedNames sampleProgram
      resultNames = allNames result
      declNames = map declName (cdecls result)

  it "rewrites the over-long synthesised name everywhere (decl and references)"
    $ (longSynth `elem` resultNames)
    `shouldBe` False

  it "leaves the over-long USER name untouched"
    $ (longUser `elem` declNames)
    `shouldBe` True

  it "leaves a short synthesised name untouched"
    $ ("$cps$short" `elem` declNames)
    `shouldBe` True

  it "bounds every synthesised name at the threshold"
    $ filter (T.isPrefixOf "$") declNames
    `shouldSatisfy` all ((<= synthNameThreshold) . T.length)

  it "is idempotent"
    $ map declName (cdecls (shortenSynthesizedNames result))
    `shouldBe` declNames

  it "shortNameFor: bounded, $-tagged, deterministic" $ do
    let s = shortNameFor longSynth
    T.length s `shouldSatisfy` (<= synthNameThreshold)
    s `shouldSatisfy` T.isInfixOf "$x$"
    shortNameFor longSynth `shouldBe` s
