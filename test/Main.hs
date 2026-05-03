module Main (main) where

import Awsum.ArbitraryInstances ()
import Awsum.ElaborateLower (elaborateLowerProgram)
import Awsum.ErrorSnapshotsSpec qualified
import Awsum.FormattingSnapshotsSpec qualified
import Awsum.HMSpec qualified
import Awsum.Normalize (normalizeProgram)
import Awsum.Parser (parseProgram)
import Awsum.Prelude (preludeDefNames, preludeProgram, stripPreludeWarnings, verifyPrelude, withPrelude)
import Awsum.Program (ProgramType (..))
import Awsum.ProgramSnapshotsSpec qualified
import Awsum.PropertySpec qualified
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
  Awsum.HMSpec.spec
  Awsum.ProgramSnapshotsSpec.spec
  Awsum.FormattingSnapshotsSpec.spec
  Awsum.ErrorSnapshotsSpec.spec
  Awsum.PropertySpec.spec

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
              "main : Either (StringTooLong | UnpairedUtf16Surrogate) String -> IO Unit",
              "main _e = IO.Stdout.print \"hi\""
            ]
    case parseProgram src of
      Left e -> expectationFailure (toString e)
      Right userProg -> do
        let combined = withPrelude userProg
        -- 'stripPreludeWarnings' drops the expected \"showInt32 is unused\"
        -- warning that arises because this user program never calls into
        -- the prelude — same filter as the CLI / snapshot specs apply.
        fmap stripPreludeWarnings (typecheckProgram ProgramCli preludeDefNames combined) `shouldBe` Right []
        requireMain combined `shouldBe` Right ()

  it "withPrelude prepends prelude decls ahead of user decls" $ do
    let src =
          unlines
            [ "import IO.Stdout",
              "",
              "main : String -> IO Unit",
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
                "main : String -> IO Unit",
                "main input = IO.Stdout.print input"
              ]
          expected =
            Program
              { imports = [ImportDecl [] ("IO" :| ["Stdout"]) Nothing],
                decls =
                  Sig noSpan "main" (TyArrow noSpan (TyCon noSpan "String") (TyApp noSpan (TyCon noSpan "IO") (TyCon noSpan "Unit"))) Nothing
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
                "main : String -> IO Unit",
                "main input = IO.Stdout.print (input ++ input)"
              ]
          expected =
            Program
              { imports = [ImportDecl [] ("IO" :| ["Stdout"]) Nothing],
                decls =
                  Sig noSpan "main" (TyArrow noSpan (TyCon noSpan "String") (TyApp noSpan (TyCon noSpan "IO") (TyCon noSpan "Unit"))) Nothing
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

    it "parses: '|' has lower precedence than '->' (no parens)" $ do
      -- 'A | B -> C' must parse as 'A | (B -> C)' — the precedence choice
      -- spelled out in the structural-sums plan: '|' is the loosest binder,
      -- so the arrow on the right pulls in tighter than the union on the left.
      let src :: Text =
            unlines
              [ "f : Int32 | String -> String",
                "f _x = \"todo\""
              ]
          expectedSig =
            TyOr
              noSpan
              (TyCon noSpan "Int32")
              (TyArrow noSpan (TyCon noSpan "String") (TyCon noSpan "String"))
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right (Program _ (Sig _ _ ty _ :| _)) -> ty `shouldBe` expectedSig
        Right _ -> expectationFailure "expected first decl to be a Sig"

    it "parses: type-ascription pattern '(n : Int32)' inside a case arm" $ do
      -- '(x : T)' with parens around a binding and a type. Used to
      -- discriminate alternatives of a structural sum at the pattern
      -- level.
      let src :: Text =
            unlines
              [ "import IO.Stdout",
                "",
                "type T = T",
                "",
                "f : T -> String",
                "f x = case x of",
                "  (n : Int32) -> showInt32 n",
                "",
                "main : String -> IO Unit",
                "main _input = IO.Stdout.print (f T)"
              ]
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p ->
          let arm =
                listToMaybe
                  [ a
                  | FunDef _ "f" _ body _ <- toList (decls p),
                    ECase _ _ alts _ <- [body],
                    a <- toList alts
                  ]
              isAscribed (Just (CaseAlt _ (PAscribe _ (PVar _ "n") (TyCon _ "Int32")) _ _)) = True
              isAscribed _ = False
           in isAscribed arm `shouldBe` True

    it "renders a type-ascription pattern back into source" $ do
      -- Render produces the canonical '(p : T)' shape that the parser
      -- accepts; combined with the parser test above this nails down
      -- the parse / render roundtrip for the new pattern form.
      let pat = PAscribe noSpan (PVar noSpan "n") (TyCon noSpan "Int32")
          src :: Text =
            unlines
              [ "import IO.Stdout",
                "",
                "type T = T",
                "",
                "f : T -> String",
                "f x = case x of",
                "  (n : Int32) -> showInt32 n",
                "",
                "main : String -> IO Unit",
                "main _input = IO.Stdout.print (f T)"
              ]
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p -> do
          -- Parse → Render gives back the same source (modulo formatting
          -- the formatter would apply elsewhere).
          let rendered = renderProgram p
          rendered `shouldBe` src
          -- And the parsed pattern matches the constructed one
          -- (under derived 'Eq' that ignores spans).
          let parsedPat =
                listToMaybe
                  [ pp
                  | FunDef _ "f" _ body _ <- toList (decls p),
                    ECase _ _ alts _ <- [body],
                    CaseAlt _ pp _ _ <- toList alts
                  ]
          parsedPat `shouldBe` Just pat

    it "parses: parens force a structural sum onto the LHS of '->'" $ do
      -- '(A | B) -> C' is the only way to write a function that takes
      -- a union as input: without the parens, the arrow would absorb B
      -- into its own RHS (see the previous test).
      let src :: Text =
            unlines
              [ "f : (Int32 | String) -> String",
                "f _x = \"todo\""
              ]
          expectedSig =
            TyArrow
              noSpan
              (TyOr noSpan (TyCon noSpan "Int32") (TyCon noSpan "String"))
              (TyCon noSpan "String")
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right (Program _ (Sig _ _ ty _ :| _)) -> ty `shouldBe` expectedSig
        Right _ -> expectationFailure "expected first decl to be a Sig"

  describe "Render.renderProgram" $ do
    it "renders: print input" $ do
      let src :: Text =
            unlines
              [ "import IO.Stdout",
                "",
                "main : String -> IO Unit",
                "main input = IO.Stdout.print input"
              ]
          ast =
            Program
              { imports = [ImportDecl [] ("IO" :| ["Stdout"]) Nothing],
                decls =
                  Sig noSpan "main" (TyArrow noSpan (TyCon noSpan "String") (TyApp noSpan (TyCon noSpan "IO") (TyCon noSpan "Unit"))) Nothing
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
                "main : String -> IO Unit",
                "main input = IO.Stdout.print (input ++ input)"
              ]
          ast =
            Program
              { imports = [ImportDecl [] ("IO" :| ["Stdout"]) Nothing],
                decls =
                  Sig noSpan "main" (TyArrow noSpan (TyCon noSpan "String") (TyApp noSpan (TyCon noSpan "IO") (TyCon noSpan "Unit"))) Nothing
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
                "main : String -> IO Unit",
                "main input = IO.Stdout.print input"
              ]
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p -> fmap stripPreludeWarnings (typecheckProgram ProgramCli preludeDefNames (withPrelude p)) `shouldBe` Right []

    it "typechecks: print (input ++ input) via Right" $ do
      let src =
            unlines
              [ "import IO.Stdout",
                "",
                "main : Either (StringTooLong | UnpairedUtf16Surrogate) String -> IO Unit",
                "main e = case e of",
                "  Left _ -> IO.Stdout.print \"err\"",
                "  Right input -> case input ++ input of",
                "    Left _ -> IO.Stdout.print \"too long\"",
                "    Right s -> IO.Stdout.print s"
              ]
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p -> fmap stripPreludeWarnings (typecheckProgram ProgramCli preludeDefNames (withPrelude p)) `shouldBe` Right []

    it "typechecks a function with a structural-sum signature and PAscribe arms" $ do
      -- A closed structural sum '(Int32 | String)' is legal in a
      -- signature, and a 'case' arm-by-arm covering each label with
      -- '(x : T)' patterns satisfies the row-exhaustiveness check.
      -- Exercised here at the typechecker level only — runtime
      -- behaviour is covered by the cross-backend snapshot tests.
      let src =
            unlines
              [ "f : (Int32 | String) -> String",
                "f x = case x of",
                "  (n : Int32) -> showInt32 n",
                "  (s : String) -> s"
              ]
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p ->
          fmap stripPreludeWarnings (typecheckProgram ProgramCli preludeDefNames (withPrelude p))
            `shouldBe` Right []

    it "rejects a structural-sum case missing a label" $ do
      -- The String alternative is uncovered, so 'caseArmsRow' raises
      -- 'NonExhaustiveRow'.
      let src =
            unlines
              [ "f : (Int32 | String) -> String",
                "f x = case x of",
                "  (n : Int32) -> showInt32 n"
              ]
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p -> case typecheckProgram ProgramCli preludeDefNames (withPrelude p) of
          Left (NonExhaustiveRow {}) -> pass
          other -> expectationFailure ("expected NonExhaustiveRow, got: " <> show other)

    it "implicitly injects a string into a structural-sum argument" $ do
      -- 'f "hi"' with 'f : (Int32 | String) -> String' is accepted —
      -- the argument's actual type 'String' is one of the row's
      -- labels, so implicit injection kicks in.
      let src =
            unlines
              [ "import IO.Stdout",
                "",
                "f : (Int32 | String) -> String",
                "f x = case x of",
                "  (n : Int32) -> showInt32 n",
                "  (s : String) -> s",
                "",
                "main : String -> IO Unit",
                "main _input = IO.Stdout.print (f \"hi\")"
              ]
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p ->
          fmap stripPreludeWarnings (typecheckProgram ProgramCli preludeDefNames (withPrelude p))
            `shouldBe` Right []

    it "implicitly injects an integer literal into a structural-sum with a unique int label" $ do
      -- 'f 42' resolves to the row's only integer label (Int32) via D.1.
      let src =
            unlines
              [ "import IO.Stdout",
                "",
                "f : (Int32 | String) -> String",
                "f x = case x of",
                "  (n : Int32) -> showInt32 n",
                "  (s : String) -> s",
                "",
                "main : String -> IO Unit",
                "main _input = IO.Stdout.print (f 42)"
              ]
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p ->
          fmap stripPreludeWarnings (typecheckProgram ProgramCli preludeDefNames (withPrelude p))
            `shouldBe` Right []

    it "rejects a wildcard arm on a structural-sum scrutinee" $ do
      -- Catch-all on a row is forbidden by design.
      let src =
            unlines
              [ "f : (Int32 | String) -> String",
                "f x = case x of",
                "  (n : Int32) -> showInt32 n",
                "  _ -> \"oops\""
              ]
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p -> case typecheckProgram ProgramCli preludeDefNames (withPrelude p) of
          Left (RowCatchAllPattern _) -> pass
          other -> expectationFailure ("expected RowCatchAllPattern, got: " <> show other)

    it "typechecks a module with no 'main' (library mode)" $ do
      let src =
            unlines
              [ "greeting : String -> String",
                "greeting s = s"
              ]
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p -> typecheckProgram ProgramCli mempty p `shouldBe` Right []

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

    it "accepts a module with 'main : Either (StringTooLong | UnpairedUtf16Surrogate) String -> IO Unit'" $ do
      let src =
            unlines
              [ "import IO.Stdout",
                "",
                "main : Either (StringTooLong | UnpairedUtf16Surrogate) String -> IO Unit",
                "main _e = IO.Stdout.print \"hi\""
              ]
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p -> requireMain p `shouldBe` Right ()

elaborateSpec :: Spec
elaborateSpec = do
  it "elaborates: main _e = case \"a\" ++ \"b\" of ..." $ do
    -- Surface (++) lowers to `Right (concatString a b)` (a CCon 1
    -- wrapping the raw concat). The point of this golden is to lock
    -- in the `Right` wrapper at the lowering level — the same shape
    -- backends rely on for their CCase scrutinees.
    let src =
          unlines
            [ "import IO.Stdout",
              "",
              "main : Either (StringTooLong | UnpairedUtf16Surrogate) String -> IO Unit",
              "main _e = case \"a\" ++ \"b\" of",
              "  Left _ -> IO.Stdout.print \"err\"",
              "  Right s -> IO.Stdout.print s"
            ]
    case parseProgram src of
      Left e -> expectationFailure (toString e)
      Right p ->
        case elaborateLowerProgram ProgramCli (withPrelude p) of
          Left err -> expectationFailure ("expected Right, got: " <> show err)
          Right (_warns, _core) -> pass
