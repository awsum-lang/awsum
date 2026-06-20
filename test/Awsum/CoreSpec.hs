-- | Direct tests of the shared 'CExpr' traversals in 'Awsum.Core':
--   'children', 'freeVars', 'renameVar'. These resolve the @CDrop@/@CReuse@
--   reference-position convention once (see the @CDrop@ node doc), and the
--   convention only matters once a rename or a capture analysis runs over Core
--   that already carries drops — which today happens strictly /after/ the last
--   such pass, so no snapshot or property program can reach it. The functions
--   are therefore exercised on synthetic 'CExpr' here, the same way
--   'jsSyntaxSpec' exercises a renderer path the codegen builder never emits.
--
--   The load-bearing assertions are the @CDrop@ ones: the previous
--   'Awsum.Cps.alphaRename' treated @CDrop n@ as a /binder/ of @n@ (renaming
--   stopped, the name was deleted from the free set), which would have left a
--   post-'Awsum.Lifetime' rename pointing a drop at a renamed-away cell —
--   reclaiming the wrong (or a freed) cell on the reference-counted backends.
module Awsum.CoreSpec (spec) where

import Awsum.Core
import Data.Set qualified as Set
import Relude
import Test.Hspec

spec :: Spec
spec = do
  renameVarSpec
  freeVarsSpec
  childrenSpec

renameVarSpec :: Spec
renameVarSpec = describe "Awsum.Core.renameVar" $ do
  it "renames the dropped name of a CDrop and descends into its body"
    $
    -- The convention: CDrop's name is a reference, not a binder. (The old
    -- alpha-rename left this as 'CDrop "a" (CProj "a" 0)'.)
    renameVar "a" "b" (CDrop "a" (CProj "a" 0))
    `shouldBe` CDrop "b" (CProj "b" 0)

  it "descends through a CDrop of an unrelated name"
    $ renameVar "a" "b" (CDrop "c" (CVar "a"))
    `shouldBe` CDrop "c" (CVar "b")

  it "renames a CReuse cell name and its fields"
    $ renameVar "a" "b" (CReuse ReuseUnique "a" 3 [CVar "a", CVar "c"])
    `shouldBe` CReuse ReuseUnique "b" 3 [CVar "b", CVar "c"]

  it "stops at the case arm that rebinds the name, renames the others"
    $ renameVar "a" "b" (CCase (CVar "a") [(1, ["a"], CVar "a"), (2, [], CVar "a")])
    `shouldBe` CCase (CVar "b") [(1, ["a"], CVar "a"), (2, [], CVar "b")]

  it "is total over CJoin/CJump: param shadows in the body, inner is renamed"
    $
    -- The case the old alpha-rename errored on outright.
    renameVar "a" "b" (CJoin "$j" ["a"] (CVar "a") (CJump "$j" [CVar "a"]))
    `shouldBe` CJoin "$j" ["a"] (CVar "a") (CJump "$j" [CVar "b"])

freeVarsSpec :: Spec
freeVarsSpec = describe "Awsum.Core.freeVars" $ do
  it "counts the dropped name of a CDrop as free"
    $
    -- Reference position, like CReuse. (The old freeVars deleted it, giving
    -- {\"b\"}.)
    freeVars (CDrop "a" (CVar "b"))
    `shouldBe` Set.fromList ["a", "b"]

  it "counts a CReuse cell name as free"
    $ freeVars (CReuse ReuseUnique "a" 1 [CVar "b"])
    `shouldBe` Set.fromList ["a", "b"]

  it "subtracts case-arm binders from the arm body"
    $ freeVars (CCase (CVar "s") [(1, ["x"], CVar "x"), (2, ["y"], CVar "z")])
    `shouldBe` Set.fromList ["s", "z"]

  it "subtracts CJoin params from the join body, not from inner"
    $ freeVars (CJoin "$j" ["p"] (CVar "p") (CVar "q"))
    `shouldBe` Set.fromList ["q"]

  it "subtracts a CLet binder from its body but keeps the rhs free vars"
    $ freeVars (CLet "n" (CVar "r") (CCall (CVar "n") [CVar "m"]))
    `shouldBe` Set.fromList ["r", "m"]

childrenSpec :: Spec
childrenSpec = describe "Awsum.Core.children" $ do
  it "lists CCall children callee-first, then args in order"
    $ children (CCall (CVar "f") [CVar "x", CVar "y"])
    `shouldBe` [CVar "f", CVar "x", CVar "y"]

  it "lists a CCase scrutinee then each arm body"
    $ children (CCase (CVar "s") [(1, ["v"], CVar "a"), (2, [], CVar "b")])
    `shouldBe` [CVar "s", CVar "a", CVar "b"]

  it "gives a leaf node no children" $ do
    children (CProj "x" 0) `shouldBe` []
    children (CVar "x") `shouldBe` []

  it "feeds reusedBinders in source order (the JS scheduler's contract)"
    $
    -- 'reusedBinders' is list-valued and order-sensitive; it rides on
    -- 'children', so callee-before-args must survive the refactor.
    reusedBinders (CCall (CReuse ReuseUnique "a" 1 []) [CReuse ReuseUnique "b" 1 []])
    `shouldBe` ["a", "b"]
