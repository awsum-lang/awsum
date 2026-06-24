module Main (main) where

import Awsum.ArbitraryInstances ()
import Awsum.ClrMetadataWidthSpec qualified
import Awsum.Codegen.JS.Syntax qualified as JS
import Awsum.CoreSpec qualified
import Awsum.ElaborateLower (elaborateLowerProgram)
import Awsum.ErrorSnapshotsSpec qualified
import Awsum.FormattingSnapshotsSpec qualified
import Awsum.HMSpec qualified
import Awsum.HoverSpec qualified
import Awsum.JvmClassFileLimitSpec qualified
import Awsum.JvmFarBranchSpec qualified
import Awsum.LspSpec qualified
import Awsum.NameLimitsSpec qualified
import Awsum.NoSimplifySpec qualified
import Awsum.Normalize (normalizeProgram)
import Awsum.Parser (parseProgram)
import Awsum.Prelude (preludeDefNames, preludeProgram, stripPreludeWarnings, verifyPrelude, withPrelude)
import Awsum.Program (ProgramType (..))
import Awsum.ProgramSnapshotsSpec qualified
import Awsum.PropertySpec qualified
import Awsum.Render (renderProgram)
import Awsum.StringLiteralCapSpec qualified
import Awsum.Syntax
import Awsum.Typing (TypeError (..), requireMain, typecheckProgram)
import GHC.IO.Encoding (setLocaleEncoding, utf8)
import Relude
import Test.Hspec
import Test.QuickCheck

main :: IO ()
main = do
  -- Test descriptions contain non-ASCII characters (arrows, set-theory
  -- glyphs). On Windows the default console code page is cp1252, so hspec's
  -- printer crashes mid-run on "commitBuffer: invalid argument (cannot
  -- encode character '\\8596')". Forcing UTF-8 on the locale encoding lets
  -- hspec write the bytes; the console renders unsupported glyphs as boxes
  -- rather than aborting the suite.
  setLocaleEncoding utf8
  hspec $ do
    parserSpec
    parserPropSpec
    typecheckerSpec
    preludeSpec
    elaborateSpec
    Awsum.HMSpec.spec
    Awsum.CoreSpec.spec
    Awsum.HoverSpec.spec
    Awsum.ProgramSnapshotsSpec.spec
    Awsum.FormattingSnapshotsSpec.spec
    Awsum.ErrorSnapshotsSpec.spec
    Awsum.PropertySpec.spec
    Awsum.NoSimplifySpec.spec
    Awsum.StringLiteralCapSpec.spec
    Awsum.NameLimitsSpec.spec
    Awsum.JvmClassFileLimitSpec.spec
    Awsum.ClrMetadataWidthSpec.spec
    Awsum.JvmFarBranchSpec.spec
    Awsum.LspSpec.spec
    jsSyntaxSpec

-- | Direct tests of the JS pretty-printer's two lexical guards (a nested unary
--   minus, a decimal-literal member receiver). The codegen builder never emits
--   either shape — integer literals are always wrapped in @| 0@ / @& 0xFF@ /
--   @>>> 0@, and unary minus only ever negates a bare variable — so a snapshot
--   can't reach them; the renderer is exercised on synthetic ASTs instead.
jsSyntaxSpec :: Spec
jsSyntaxSpec = describe "Awsum.Codegen.JS.Syntax renderer" $ do
  let render e = JS.renderProgram [JS.SExpr e]
  it "parenthesises a nested unary minus (no '--' merge)"
    $ render (JS.EUnary JS.UNeg (JS.EUnary JS.UNeg (JS.EVar "x")))
    `shouldBe` "-(-x);\n"
  it "parenthesises unary minus of a negative literal"
    $ render (JS.EUnary JS.UNeg (JS.ENum (-5)))
    `shouldBe` "-(-5);\n"
  it "leaves a plain unary minus unparenthesised"
    $ render (JS.EUnary JS.UNeg (JS.EVar "x"))
    `shouldBe` "-x;\n"
  it "parenthesises a decimal-literal member receiver (no '5.' merge)"
    $ render (JS.EMember (JS.ENum 5) "toString")
    `shouldBe` "(5).toString;\n"
  it "parenthesises a negative-literal member receiver"
    $ render (JS.EMember (JS.ENum (-5)) "toString")
    `shouldBe` "(-5).toString;\n"
  it "leaves a non-literal member receiver unparenthesised"
    $ render (JS.EMember (JS.EVar "x") "y")
    `shouldBe` "x.y;\n"
  it "renders a negative hex literal with a leading minus"
    $ render (JS.EHex (-255))
    `shouldBe` "-0xFF;\n"
  it "parenthesises a negative-hex member receiver (no '-0xFF.' merge)"
    $ render (JS.EMember (JS.EHex (-255)) "toString")
    `shouldBe` "(-0xFF).toString;\n"
  it "escapes NUL as a fixed-length \\u escape (not legacy octal)"
    $ render (JS.EStr "\0")
    `shouldBe` "\"\\u0000\";\n"
  it "escapes U+2028 (line separator) as a fixed-length \\u escape"
    $ render (JS.EStr "\x2028")
    `shouldBe` "\"\\u2028\";\n"
  it "escapes U+2029 (paragraph separator) as a fixed-length \\u escape"
    $ render (JS.EStr "\x2029")
    `shouldBe` "\"\\u2029\";\n"
  it "renders a left-associative '-' chain without parens"
    $ render (JS.EBin JS.BSub (JS.EBin JS.BSub (JS.EVar "a") (JS.EVar "b")) (JS.EVar "c"))
    `shouldBe` "a - b - c;\n"
  it "parenthesises the right operand of a left-associative '-'"
    $ render (JS.EBin JS.BSub (JS.EVar "a") (JS.EBin JS.BSub (JS.EVar "b") (JS.EVar "c")))
    `shouldBe` "a - (b - c);\n"
  -- The compact (artifact) renderer behind `awsum build` / `run`: the same
  -- tokens as 'renderProgram', dropped onto one line. Safe because every
  -- statement is ';'- or '}'-terminated, so removing newlines never fuses
  -- two tokens.
  it "renderProgramCompact joins statements on one line via their terminators"
    $ JS.renderProgramCompact [JS.SConst "a" (JS.ENum 1), JS.SReturn (JS.EVar "a")]
    `shouldBe` "const a = 1;return a;"
  it "renderProgramCompact collapses a block onto one line"
    $ JS.renderProgramCompact [JS.SIf (JS.EVar "c") [JS.SReturn (JS.ENum 1)] []]
    `shouldBe` "if (c) {return 1;}"
  it "renderProgramCompact emits no newline, even across nested blocks"
    $ ('\n' `elem` toString (JS.renderProgramCompact [JS.SIf (JS.EVar "c") [JS.SIf (JS.EVar "d") [JS.SReturn (JS.ENum 0)] []] []]))
    `shouldBe` False

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
              "main : IO Never Unit",
              "main = IO.Stdout.print \"hi\""
            ]
    case parseProgram src of
      Left e -> expectationFailure (toString e)
      Right userProg -> do
        let combined = withPrelude userProg
        -- 'stripPreludeWarnings' drops the expected \"showInt32 is unused\"
        -- warning that arises because this user program never calls into
        -- the prelude — same filter as the CLI / snapshot specs apply.
        fmap (stripPreludeWarnings . snd) (typecheckProgram ProgramCli preludeDefNames combined) `shouldBe` Right []
        requireMain combined `shouldBe` Right ()

  it "withPrelude prepends prelude decls ahead of user decls" $ do
    let src =
          unlines
            [ "import IO.Stdout",
              "",
              "main : String -> IO Never Unit",
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
                "main : String -> IO Never Unit",
                "main input = IO.Stdout.print input"
              ]
          expected =
            Program
              { moduleComment = Nothing,
                imports = [ImportDecl [] ("IO" :| ["Stdout"]) Nothing],
                decls =
                  Sig noSpan "main" (TyArrow noSpan (TyCon noSpan "String") (TyApp noSpan (TyApp noSpan (TyCon noSpan "IO") (TyCon noSpan "Never")) (TyCon noSpan "Unit"))) Nothing Nothing
                    : [ FunDef
                          noSpan
                          "main"
                          [Param noSpan "input"]
                          ( EApp
                              noSpan
                              (EVar noSpan (QName ["IO", "Stdout"] "print"))
                              (EVar noSpan (QName [] "input"))
                          )
                          Nothing
                          Nothing
                      ]
              }
      parseProgram src `shouldBe` Right expected

    it "parses: print (input ++ input)" $ do
      let src :: Text =
            unlines
              [ "import IO.Stdout",
                "",
                "main : String -> IO Never Unit",
                "main input = IO.Stdout.print (input ++ input)"
              ]
          expected =
            Program
              { moduleComment = Nothing,
                imports = [ImportDecl [] ("IO" :| ["Stdout"]) Nothing],
                decls =
                  Sig noSpan "main" (TyArrow noSpan (TyCon noSpan "String") (TyApp noSpan (TyApp noSpan (TyCon noSpan "IO") (TyCon noSpan "Never")) (TyCon noSpan "Unit"))) Nothing Nothing
                    : [ FunDef
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
        Right (Program _ _ (Sig _ _ ty _ _ : _)) -> ty `shouldBe` expectedSig
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
                "main : String -> IO Never Unit",
                "main _input = IO.Stdout.print (f T)"
              ]
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p ->
          let arm =
                listToMaybe
                  [ a
                  | FunDef _ "f" _ body _ _ <- toList (decls p),
                    ECase _ _ alts _ <- [body],
                    a <- toList alts
                  ]
              isAscribed (Just (CaseAltLeaf _ (PAscribe _ (PVar _ "n") (TyCon _ "Int32")) _ _)) = True
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
                "main : String -> IO Never Unit",
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
                  [ caseAltPattern alt
                  | FunDef _ "f" _ body _ _ <- toList (decls p),
                    ECase _ _ alts _ <- [body],
                    alt <- toList alts
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
        Right (Program _ _ (Sig _ _ ty _ _ : _)) -> ty `shouldBe` expectedSig
        Right _ -> expectationFailure "expected first decl to be a Sig"

  describe "Render.renderProgram" $ do
    it "renders: print input" $ do
      let src :: Text =
            unlines
              [ "import IO.Stdout",
                "",
                "main : String -> IO Never Unit",
                "main input = IO.Stdout.print input"
              ]
          ast =
            Program
              { moduleComment = Nothing,
                imports = [ImportDecl [] ("IO" :| ["Stdout"]) Nothing],
                decls =
                  Sig noSpan "main" (TyArrow noSpan (TyCon noSpan "String") (TyApp noSpan (TyApp noSpan (TyCon noSpan "IO") (TyCon noSpan "Never")) (TyCon noSpan "Unit"))) Nothing Nothing
                    : [ FunDef
                          noSpan
                          "main"
                          [Param noSpan "input"]
                          ( EApp
                              noSpan
                              (EVar noSpan (QName ["IO", "Stdout"] "print"))
                              (EVar noSpan (QName [] "input"))
                          )
                          Nothing
                          Nothing
                      ]
              }
      renderProgram ast `shouldBe` src

    it "renders: print (input ++ input)" $ do
      let src :: Text =
            unlines
              [ "import IO.Stdout",
                "",
                "main : String -> IO Never Unit",
                "main input = IO.Stdout.print (input ++ input)"
              ]
          ast =
            Program
              { moduleComment = Nothing,
                imports = [ImportDecl [] ("IO" :| ["Stdout"]) Nothing],
                decls =
                  Sig noSpan "main" (TyArrow noSpan (TyCon noSpan "String") (TyApp noSpan (TyApp noSpan (TyCon noSpan "IO") (TyCon noSpan "Never")) (TyCon noSpan "Unit"))) Nothing Nothing
                    : [ FunDef
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

  describe "format idempotency" $ do
    -- 'render . parse . render p == render p' for any 'p'. The
    -- 'parse . render == id' property above already ensures the AST
    -- round-trips; this one ensures the *text* produced by the
    -- formatter is itself in canonical form. Catches drift like
    -- comment placement that shifts on the second pass, or layout
    -- that isn't a fixed point of the formatter.
    it "render . parse . render == render"
      $ property
      $ \p ->
        let firstPass = renderProgram (p :: Program)
            secondPass = case parseProgram firstPass of
              Left e -> "<parse failed: " <> e <> ">"
              Right q -> renderProgram q
         in secondPass === firstPass

typecheckerSpec :: Spec
typecheckerSpec = do
  describe "Typing.typecheckProgram" $ do
    it "typechecks: print input" $ do
      let src =
            unlines
              [ "import IO.Stdout",
                "",
                "main : String -> IO Never Unit",
                "main input = IO.Stdout.print input"
              ]
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p -> fmap (stripPreludeWarnings . snd) (typecheckProgram ProgramCli preludeDefNames (withPrelude p)) `shouldBe` Right []

    it "typechecks: print (input ++ input) via Right" $ do
      let src =
            unlines
              [ "import IO.Stdout",
                "",
                "run : Either StringTooLong String -> IO Never Unit",
                "run e = case e of",
                "  Left _ -> IO.Stdout.print \"err\"",
                "  Right input -> case input ++ input of",
                "    Left _ -> IO.Stdout.print \"too long\"",
                "    Right s -> IO.Stdout.print s",
                "",
                "main : IO Never Unit",
                "main = run (Right \"hi\")"
              ]
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p -> fmap (stripPreludeWarnings . snd) (typecheckProgram ProgramCli preludeDefNames (withPrelude p)) `shouldBe` Right []

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
          fmap (stripPreludeWarnings . snd) (typecheckProgram ProgramCli preludeDefNames (withPrelude p))
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
                "main : String -> IO Never Unit",
                "main _input = IO.Stdout.print (f \"hi\")"
              ]
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p ->
          fmap (stripPreludeWarnings . snd) (typecheckProgram ProgramCli preludeDefNames (withPrelude p))
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
                "main : String -> IO Never Unit",
                "main _input = IO.Stdout.print (f 42)"
              ]
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p ->
          fmap (stripPreludeWarnings . snd) (typecheckProgram ProgramCli preludeDefNames (withPrelude p))
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
        Right p -> fmap snd (typecheckProgram ProgramCli mempty p) `shouldBe` Right []

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

    it "accepts a module with 'main : IO Never Unit'" $ do
      let src =
            unlines
              [ "import IO.Stdout",
                "",
                "main : IO Never Unit",
                "main = IO.Stdout.print \"hi\""
              ]
      case parseProgram src of
        Left e -> expectationFailure (toString e)
        Right p -> requireMain p `shouldBe` Right ()

    -- A file with no top-level declarations parses (the grammar allows
    -- zero); it is a valid empty module. The absent 'main' surfaces only
    -- when an executable is requested, via 'requireMain' — not as a parse
    -- error. This keeps the LSP "file is still being written" flow quiet.
    it "accepts an empty file as a valid module without 'main'" $ do
      case parseProgram "" of
        Left e -> expectationFailure (toString e)
        Right p -> do
          decls p `shouldBe` []
          requireMain p `shouldBe` Left MainMissing

    it "accepts an imports-only file as a valid module without 'main'" $ do
      case parseProgram (unlines ["import IO.Stdout"]) of
        Left e -> expectationFailure (toString e)
        Right p -> do
          decls p `shouldBe` []
          requireMain p `shouldBe` Left MainMissing

    it "accepts a module-comment-only file as a valid module without 'main'" $ do
      case parseProgram (unlines ["{- just a module comment -}", ""]) of
        Left e -> expectationFailure (toString e)
        Right p -> do
          moduleComment p `shouldBe` Just " just a module comment "
          decls p `shouldBe` []
          requireMain p `shouldBe` Left MainMissing

elaborateSpec :: Spec
elaborateSpec = do
  it "elaborates: main = case \"a\" ++ \"b\" of ..." $ do
    -- Surface (++) lowers to `Right (concatString a b)` (a CCon 1
    -- wrapping the raw concat). The point of this golden is to lock
    -- in the `Right` wrapper at the lowering level — the same shape
    -- backends rely on for their CCase scrutinees.
    let src =
          unlines
            [ "import IO.Stdout",
              "",
              "main : IO Never Unit",
              "main = case \"a\" ++ \"b\" of",
              "  Left _ -> IO.Stdout.print \"err\"",
              "  Right s -> IO.Stdout.print s"
            ]
    case parseProgram src of
      Left e -> expectationFailure (toString e)
      Right p ->
        case elaborateLowerProgram ProgramCli (withPrelude p) of
          Left err -> expectationFailure ("expected Right, got: " <> show err)
          Right (_warns, _ptags, _core) -> pass
