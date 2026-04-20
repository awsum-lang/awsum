module Main (main) where

import Awsum.ArbitraryInstances ()
import Awsum.Core
import Awsum.ElaborateLower (elaborateLowerProgram)
import Awsum.ErrorSnapshotsSpec qualified
import Awsum.FormattingSnapshotsSpec qualified
import Awsum.Normalize (normalizeProgram)
import Awsum.Parser (parseProgram)
import Awsum.ProgramSnapshotsSpec qualified
import Awsum.Render (renderProgram)
import Awsum.Syntax
import Awsum.Typing (typecheckProgram)
import Relude
import Test.Hspec
import Test.QuickCheck

main :: IO ()
main = hspec $ do
  parserSpec
  parserPropSpec
  typecheckerSpec
  elaborateSpec
  Awsum.ProgramSnapshotsSpec.spec
  Awsum.FormattingSnapshotsSpec.spec
  Awsum.ErrorSnapshotsSpec.spec

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
        Right p -> typecheckProgram p `shouldBe` Right []

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
        Right p -> typecheckProgram p `shouldBe` Right []

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
        elaborateLowerProgram p
          `shouldBe` Right
            ( [],
              CoreProgram
                [ CFunDef
                    "main"
                    ["input"]
                    ( CCall
                        (CPrim PrimPrint)
                        [ CCall
                            (CPrim PrimConcat)
                            [CVar "input", CVar "input"]
                        ]
                    )
                ]
            )
