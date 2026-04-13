module Main (main) where

import Awsum.ArbitraryInstances ()
import Awsum.Core
import Awsum.ElaborateLower (elaborateLowerProgram)
import Awsum.Normalize (normalizeProgram)
import Awsum.Parser (parseProgram)
import Awsum.ProgramSnapshotsSpec qualified
import Awsum.Render (renderProgram)
import Awsum.Syntax
import Awsum.Typing (TypeError (..), typecheckProgram)
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
                  Sig noSpan "main" (TyArrow (TyCon "String") (TyCon "IOUnit")) Nothing
                    :| [ FunDef
                           noSpan
                           "main"
                           ["input"]
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
                  Sig noSpan "main" (TyArrow (TyCon "String") (TyCon "IOUnit")) Nothing
                    :| [ FunDef
                           noSpan
                           "main"
                           ["input"]
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
                  Sig noSpan "main" (TyArrow (TyCon "String") (TyCon "IOUnit")) Nothing
                    :| [ FunDef
                           noSpan
                           "main"
                           ["input"]
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
                  Sig noSpan "main" (TyArrow (TyCon "String") (TyCon "IOUnit")) Nothing
                    :| [ FunDef
                           noSpan
                           "main"
                           ["input"]
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
        Right p -> typecheckProgram p `shouldBe` Right ()

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
        Right p -> typecheckProgram p `shouldBe` Right ()

    it "fails when IO.Stdout not imported (NotImported)" $ do
      let src =
            unlines
              [ "main : String -> IOUnit",
                "main input = IO.Stdout.print input"
              ]
          expectedErr = NotImported noSpan (QName ["IO", "Stdout"] "print")
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p -> typecheckProgram p `shouldBe` Left expectedErr

    it "fails when main has wrong type (MainWrongType)" $ do
      let src =
            unlines
              [ "main : String -> String",
                "main input = input"
              ]
          expectedErr = MainWrongType (TyArrow (TyCon "String") (TyCon "String"))
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p -> typecheckProgram p `shouldBe` Left expectedErr

    it "fails on arity mismatch (ArityMismatch)" $ do
      let src =
            unlines
              [ "import IO.Stdout",
                "foo : String -> IOUnit",
                "foo = IO.Stdout.print",
                "",
                "main : String -> IOUnit",
                "main input = IO.Stdout.print input"
              ]
          expectedErr = ArityMismatch noSpan "foo" 1 0
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p -> typecheckProgram p `shouldBe` Left expectedErr

    it "fails on unknown variable (UnknownVar)" $ do
      let src =
            unlines
              [ "import IO.Stdout",
                "main : String -> IOUnit",
                "main input = IO.Stdout.print x"
              ]
          expectedErr = UnknownVar noSpan (QName [] "x")
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p -> typecheckProgram p `shouldBe` Left expectedErr

    it "fails on using non-function as a function (NotAFunction)" $ do
      let src =
            unlines
              [ "main : String -> IOUnit",
                "main input = input input"
              ]
          expectedErr = NotAFunction (EVar noSpan (QName [] "input")) (TyCon "String")
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p -> typecheckProgram p `shouldBe` Left expectedErr

    it "fails on bad (++) types (TypeMismatch)" $ do
      let src =
            unlines
              [ "import IO.Stdout",
                "main : String -> IOUnit",
                "main input = IO.Stdout.print ++ input"
              ]
          badExpr =
            EInfix
              noSpan
              OpConcat
              (EVar noSpan (QName ["IO", "Stdout"] "print"))
              (EVar noSpan (QName [] "input"))
          expectedErr =
            TypeMismatch
              (TyCon "String")
              (TyArrow (TyCon "String") (TyCon "IOUnit"))
              badExpr
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p -> typecheckProgram p `shouldBe` Left expectedErr

    it "fails on duplicate signature (DuplicateSignature)" $ do
      let src =
            unlines
              [ "foo : String -> IOUnit",
                "foo : String -> IOUnit",
                "",
                "main : String -> IOUnit",
                "main input = input"
              ]
          expectedErr = DuplicateSignature noSpan "foo"
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p -> typecheckProgram p `shouldBe` Left expectedErr

    it "fails on duplicate definition (DuplicateDefinition)" $ do
      let src =
            unlines
              [ "foo = foo",
                "foo = foo",
                "",
                "main : String -> IOUnit",
                "main input = input"
              ]
          expectedErr = DuplicateDefinition noSpan "foo"
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p -> typecheckProgram p `shouldBe` Left expectedErr

    it "fails on unknown type constructor in signature (UnknownTypeCon)" $ do
      let src =
            unlines
              [ "import IO.Stdout",
                "main : X -> IOUnit",
                "main x = IO.Stdout.print x"
              ]
          expectedErr = UnknownTypeCon noSpan "X"
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p -> typecheckProgram p `shouldBe` Left expectedErr

    it "fails on missing signature (MissingSignature)" $ do
      let src =
            unlines
              [ "foo x = x",
                "",
                "main : String -> IOUnit",
                "main input = input"
              ]
          expectedErr = MissingSignature noSpan "foo"
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p -> typecheckProgram p `shouldBe` Left expectedErr

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
            ( CoreProgram
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
