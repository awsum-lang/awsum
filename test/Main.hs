module Main (main) where

import Awsum.ArbitraryInstances ()
import Awsum.Core
import Awsum.ElaborateLower (elaborateLowerProgram)
import Awsum.ErrorSnapshotsSpec qualified
import Awsum.FormattingSnapshotsSpec qualified
import Awsum.Normalize (normalizeProgram)
import Awsum.Parser (parseProgram)
import Awsum.Prelude (preludeProgram, stripPreludeWarnings, verifyPrelude, withPrelude)
import Awsum.Program (ProgramType (..))
import Awsum.ProgramSnapshotsSpec qualified
import Awsum.Render (renderProgram)
import Awsum.Syntax
import Awsum.Typing (TypeError (..), requireMain, typecheckProgram)
import Relude
import Test.Hspec
import Test.QuickCheck

main :: IO ()
main = hspec $ do
  parserSpec
  parserPropSpec
  typecheckerSpec
  preludeSpec
  elaborateSpec
  Awsum.ProgramSnapshotsSpec.spec
  Awsum.FormattingSnapshotsSpec.spec
  Awsum.ErrorSnapshotsSpec.spec

preludeSpec :: Spec
preludeSpec = describe "Awsum.Prelude" $ do
  it "bundled prelude parses and typechecks"
    $ case verifyPrelude ProgramCli of
      Right _warns -> pass
      Left err -> expectationFailure (show err)

  it "withPrelude keeps a user program typecheckable and main-eligible" $ do
    let src =
          unlines
            [ "import IO.Stdout",
              "",
              "main : String -> IOUnit",
              "main input = IO.Stdout.print input"
            ]
    case parseProgram src of
      Left e -> expectationFailure (toString e)
      Right userProg -> do
        let combined = withPrelude userProg
        -- 'stripPreludeWarnings' drops the expected \"showInt32 is unused\"
        -- warning that arises because this user program never calls into
        -- the prelude — same filter as the CLI / snapshot specs apply.
        fmap stripPreludeWarnings (typecheckProgram ProgramCli combined) `shouldBe` Right []
        requireMain combined `shouldBe` Right ()

  it "withPrelude prepends prelude decls ahead of user decls" $ do
    let src =
          unlines
            [ "import IO.Stdout",
              "",
              "main : String -> IOUnit",
              "main input = IO.Stdout.print input"
            ]
    case parseProgram src of
      Left e -> expectationFailure (toString e)
      Right userProg -> do
        let combined = withPrelude userProg
            pLen = length (decls preludeProgram)
            uLen = length (decls userProg)
            cLen = length (decls combined)
        cLen `shouldBe` pLen + uLen

parserSpec :: Spec
parserSpec = do
  describe "Parser.parseProgram" $ do
    it "parses: print input" $ do
      let src :: Text =
            unlines
              [ "import IO.Stdout",
                "",
                "main : String -> IOUnit",
                "main input = IO.Stdout.print input"
              ]
          expected =
            Program
              { imports = [ImportDecl [] ("IO" :| ["Stdout"]) Nothing],
                decls =
                  Sig noSpan "main" (TyArrow noSpan (TyCon noSpan "String") (TyCon noSpan "IOUnit")) Nothing
                    :| [ FunDef
                           noSpan
                           "main"
                           [Param noSpan "input"]
                           ( EApp
                               noSpan
                               (EVar noSpan (QName ["IO", "Stdout"] "print"))
                               (EVar noSpan (QName [] "input"))
                           )
                           Nothing
                       ]
              }
      parseProgram src `shouldBe` Right expected

    it "parses: print (input ++ input)" $ do
      let src :: Text =
            unlines
              [ "import IO.Stdout",
                "",
                "main : String -> IOUnit",
                "main input = IO.Stdout.print (input ++ input)"
              ]
          expected =
            Program
              { imports = [ImportDecl [] ("IO" :| ["Stdout"]) Nothing],
                decls =
                  Sig noSpan "main" (TyArrow noSpan (TyCon noSpan "String") (TyCon noSpan "IOUnit")) Nothing
                    :| [ FunDef
                           noSpan
                           "main"
                           [Param noSpan "input"]
                           ( EApp
                               noSpan
                               (EVar noSpan (QName ["IO", "Stdout"] "print"))
                               ( EParens
                                   noSpan
                                   ( EInfix
                                       noSpan
                                       OpConcat
                                       (EVar noSpan (QName [] "input"))
                                       (EVar noSpan (QName [] "input"))
                                   )
                               )
                           )
                           Nothing
                       ]
              }
      parseProgram src `shouldBe` Right expected

  describe "Render.renderProgram" $ do
    it "renders: print input" $ do
      let src :: Text =
            unlines
              [ "import IO.Stdout",
                "",
                "main : String -> IOUnit",
                "main input = IO.Stdout.print input"
              ]
          ast =
            Program
              { imports = [ImportDecl [] ("IO" :| ["Stdout"]) Nothing],
                decls =
                  Sig noSpan "main" (TyArrow noSpan (TyCon noSpan "String") (TyCon noSpan "IOUnit")) Nothing
                    :| [ FunDef
                           noSpan
                           "main"
                           [Param noSpan "input"]
                           ( EApp
                               noSpan
                               (EVar noSpan (QName ["IO", "Stdout"] "print"))
                               (EVar noSpan (QName [] "input"))
                           )
                           Nothing
                       ]
              }
      renderProgram ast `shouldBe` src

    it "renders: print (input ++ input)" $ do
      let src :: Text =
            unlines
              [ "import IO.Stdout",
                "",
                "main : String -> IOUnit",
                "main input = IO.Stdout.print (input ++ input)"
              ]
          ast =
            Program
              { imports = [ImportDecl [] ("IO" :| ["Stdout"]) Nothing],
                decls =
                  Sig noSpan "main" (TyArrow noSpan (TyCon noSpan "String") (TyCon noSpan "IOUnit")) Nothing
                    :| [ FunDef
                           noSpan
                           "main"
                           [Param noSpan "input"]
                           ( EApp
                               noSpan
                               (EVar noSpan (QName ["IO", "Stdout"] "print"))
                               ( EParens
                                   noSpan
                                   ( EInfix
                                       noSpan
                                       OpConcat
                                       (EVar noSpan (QName [] "input"))
                                       (EVar noSpan (QName [] "input"))
                                   )
                               )
                           )
                           Nothing
                       ]
              }
      renderProgram ast `shouldBe` src

parserPropSpec :: Spec
parserPropSpec = do
  describe "render ∘ parse roundtrip" $ do
    it "parse . render == id for Program"
      $ property
      $ \p ->
        fmap normalizeProgram (parseProgram (renderProgram p))
          === Right (normalizeProgram (p :: Program))

typecheckerSpec :: Spec
typecheckerSpec = do
  describe "Typing.typecheckProgram" $ do
    it "typechecks: print input" $ do
      let src =
            unlines
              [ "import IO.Stdout",
                "",
                "main : String -> IOUnit",
                "main input = IO.Stdout.print input"
              ]
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p -> typecheckProgram ProgramCli p `shouldBe` Right []

    it "typechecks: print (input ++ input)" $ do
      let src =
            unlines
              [ "import IO.Stdout",
                "",
                "main : String -> IOUnit",
                "main input = IO.Stdout.print (input ++ input)"
              ]
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p -> typecheckProgram ProgramCli p `shouldBe` Right []

    it "typechecks a module with no 'main' (library mode)" $ do
      let src =
            unlines
              [ "greeting : String -> String",
                "greeting s = \"hi \" ++ s"
              ]
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p -> typecheckProgram ProgramCli p `shouldBe` Right []

  describe "Typing.requireMain" $ do
    it "rejects a module without 'main'" $ do
      let src =
            unlines
              [ "greeting : String -> String",
                "greeting s = \"hi \" ++ s"
              ]
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p -> requireMain p `shouldBe` Left MainMissing

    it "rejects a module with 'main' of the wrong type" $ do
      let src =
            unlines
              [ "main : String -> String",
                "main input = input"
              ]
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p -> case requireMain p of
          Left (MainWrongType _) -> pass
          other -> expectationFailure ("expected MainWrongType, got: " <> show other)

    it "accepts a module with 'main : String -> IOUnit'" $ do
      let src =
            unlines
              [ "import IO.Stdout",
                "",
                "main : String -> IOUnit",
                "main input = IO.Stdout.print input"
              ]
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p -> requireMain p `shouldBe` Right ()

elaborateSpec :: Spec
elaborateSpec = do
  it "elaborates: main input = IO.Stdout.print (input ++ input)" $ do
    let src =
          unlines
            [ "import IO.Stdout",
              "",
              "main : String -> IOUnit",
              "main input = IO.Stdout.print (input ++ input)"
            ]
    case parseProgram src of
      Left e -> expectationFailure (toString e)
      Right p ->
        elaborateLowerProgram ProgramCli p
          `shouldBe` Right
            ( [],
              CoreProgram
                [ CFunDef
                    "main"
                    ["input"]
                    ( CCall
                        (CBuiltIn "IO.Stdout.print")
                        [ CCall
                            (CBuiltIn "concatString")
                            [CVar "input", CVar "input"]
                        ]
                    )
                ]
            )
