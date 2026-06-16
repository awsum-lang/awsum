-- | Smoke tests for LSP @textDocument/hover@.
--
--   Drives 'Awsum.Lsp.hoverForPosition' on tiny in-memory programs and
--   asserts the rendered markdown payload contains the expected fenced
--   @```awsum``` type block. Full snapshot fixtures (per-position
--   markdown bodies, one file per scenario) are a clean follow-up;
--   this spec covers the load-bearing positions: head name, parameter,
--   top-level reference in body, monomorphic local binding.
module Awsum.HoverSpec (spec) where

import Awsum.Lsp (compileToTypedProgram, hoverForPosition)
import Awsum.Parser (parseProgram)
import Data.Text qualified as T
import Language.LSP.Protocol.Types
  ( Hover (..),
    MarkupContent (..),
    Position (..),
    type (|?) (..),
  )
import Relude
import Test.Hspec

-- | Single-line @awsum@ source position (1-based line, 1-based col) →
--   0-based LSP 'Position'.
pos :: Int -> Int -> Position
pos line col = Position (fromIntegral (line - 1)) (fromIntegral (col - 1))

-- | Compute hover for a program at a position. 'Nothing' on parse
--   failure or no hover.
hoverAt :: Text -> Position -> Maybe Text
hoverAt src position = do
  prog <- case parseProgram src of
    Left _ -> Nothing
    Right p -> Just p
  Hover (InL (MarkupContent _ md)) _ <- hoverForPosition (lines src) (compileToTypedProgram src) prog position
  pure md

spec :: Spec
spec = describe "Awsum.Lsp.hoverForPosition" $ do
  it "shows the type on a top-level head name (Sig)" $ do
    -- Cursor on the @s@ of @square@ in the signature line. Trace's
    -- head-name record maps that span to the signature's full arrow
    -- type, which is rendered in the @```awsum``` block.
    let src =
          unlines
            [ "import IO.Stdout",
              "",
              "square : Int32 -> Either (UnderflowError | OverflowError) Int32",
              "square n = mulInt32 n n",
              "",
              "main : IO Never Unit",
              "main = IO.Stdout.print \"42\""
            ]
    case hoverAt src (pos 3 1) of
      Just md -> md `shouldSatisfy` T.isInfixOf "Int32 -> Either"
      Nothing -> expectationFailure "expected hover on head name"

  it "shows the type on a function parameter" $ do
    let src =
          unlines
            [ "import IO.Stdout",
              "",
              "square : Int32 -> Either (UnderflowError | OverflowError) Int32",
              "square n = mulInt32 n n",
              "",
              "main : IO Never Unit",
              "main = IO.Stdout.print \"42\""
            ]
    -- Cursor on the parameter @n@ in @square n = …@.
    case hoverAt src (pos 4 8) of
      Just md -> md `shouldSatisfy` T.isInfixOf "Int32"
      Nothing -> expectationFailure "expected hover on parameter"

  it "shows the type on a top-level reference in a body" $ do
    let src =
          unlines
            [ "import IO.Stdout",
              "",
              "square : Int32 -> Either (UnderflowError | OverflowError) Int32",
              "square n = mulInt32 n n",
              "",
              "main : IO Never Unit",
              "main = IO.Stdout.print \"42\""
            ]
    -- Cursor on @mulInt32@ in the body. The trace records the prelude
    -- function's full type at this span.
    case hoverAt src (pos 4 12) of
      Just md -> md `shouldSatisfy` T.isInfixOf "Int32 -> Int32"
      Nothing -> expectationFailure "expected hover on reference"

  it "shows declared + instantiated for a polymorphic reference at a concrete call site" $ do
    -- 'bindEither : Either e1 a -> (a -> Either e2 b) -> Either (e1 | e2) b'
    -- in the prelude. At the call site below the row variables are
    -- resolved by 'unify', so hover should show both the declared
    -- scheme and the call-site-instantiated form.
    let src =
          unlines
            [ "import IO.Stdout",
              "",
              "type ErrA = ErrA",
              "type ErrB = ErrB",
              "",
              "opA : Either ErrA Int32",
              "opA = pureEither 1",
              "",
              "opB : Either ErrB Int32",
              "opB = pureEither 2",
              "",
              "combined : Either (ErrA | ErrB) Int32",
              "combined = bindEither opA (\\_ -> opB)",
              "",
              "main : IO Never Unit",
              "main = IO.Stdout.print \"42\""
            ]
    case hoverAt src (pos 13 12) of
      Just md -> do
        md `shouldSatisfy` T.isInfixOf "Instantiated here:"
        md `shouldSatisfy` T.isInfixOf "ErrA"
      Nothing -> expectationFailure "expected hover on bindEither"

  it "shows the type on an underscore-prefixed parameter" $ do
    -- '_n' is intentionally-unused (can't be referenced), but hover is
    -- read-only: a reader still wants the type the author chose to ignore.
    let src =
          unlines
            [ "import IO.Stdout",
              "",
              "greet : Int32 -> String",
              "greet _n = \"hi\"",
              "",
              "main : IO Never Unit",
              "main = IO.Stdout.print (greet 1)"
            ]
    -- Cursor on '_n' in 'greet _n = …'.
    case hoverAt src (pos 4 7) of
      Just md -> md `shouldSatisfy` T.isInfixOf "Int32"
      Nothing -> expectationFailure "expected hover on underscore-prefixed parameter"

  it "shows the matched type on a bare wildcard in a pattern" $ do
    -- '_' binds nothing, but it still has a type — the field a 'Just _'
    -- arm discards. Hover surfaces it.
    let src =
          unlines
            [ "import IO.Stdout",
              "",
              "describe : Maybe Int32 -> String",
              "describe m = case m of",
              "  Just _ -> \"j\"",
              "  Nothing -> \"n\"",
              "",
              "main : IO Never Unit",
              "main = IO.Stdout.print (describe Nothing)"
            ]
    -- Cursor on the '_' wildcard in 'Just _'.
    case hoverAt src (pos 5 8) of
      Just md -> md `shouldSatisfy` T.isInfixOf "Int32"
      Nothing -> expectationFailure "expected hover on wildcard"

  it "returns Nothing when the cursor is on a literal" $ do
    let src =
          unlines
            [ "import IO.Stdout",
              "",
              "answer : Int32",
              "answer = 42",
              "",
              "main : IO Never Unit",
              "main = IO.Stdout.print \"42\""
            ]
    -- Cursor on the @4@ of the integer literal — literals don't get
    -- hover (no 'TExpr' record, no AST-walk match).
    hoverAt src (pos 4 10) `shouldBe` Nothing
