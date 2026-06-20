-- | Direct tests of the shared 'CExpr' traversals in 'Awsum.Core':
--   'children', 'freeVars', 'renameVar'. These resolve the @CDrop@/@CReuse@
--   reference-position convention once (see the @CDrop@ node doc), and the
--   convention only matters once a rename or a capture analysis runs over Core
--   that already carries drops — which today happens strictly /after/ the last
--   such pass, so no snapshot or property program can reach it. The functions
--   are therefore exercised on synthetic 'CExpr' here, the same way
--   'jsSyntaxSpec' exercises a renderer path the codegen builder never emits.
--   'effectfulIn' is exercised here too, for the distinct latent reason
--   spelled out on 'effectfulInSpec' below. The 'pipelineNodeGuardSpec'
--   assertions ride the same rationale — that 'Awsum.Cps' / 'Awsum.Tco'
--   /raise/ on a node 'Awsum.Simplify' mints, unreachable from any .aww
--   program.
--
--   The load-bearing assertions are the @CDrop@ ones: the previous
--   'Awsum.Cps.alphaRename' treated @CDrop n@ as a /binder/ of @n@ (renaming
--   stopped, the name was deleted from the free set), which would have left a
--   post-'Awsum.Lifetime' rename pointing a drop at a renamed-away cell —
--   reclaiming the wrong (or a freed) cell on the reference-counted backends.
module Awsum.CoreSpec (spec) where

import Awsum.BuiltIn (builtIns, effectfulBuiltIns)
import Awsum.Core
import Awsum.Cps (cpsProgram)
import Awsum.Syntax (Name)
import Awsum.Tco (tcoProgram)
import Control.Exception (ErrorCall (..))
import Data.Map.Strict qualified as M
import Data.Set qualified as Set
import Data.Text qualified as T
import Relude
import Test.Hspec

spec :: Spec
spec = do
  renameVarSpec
  freeVarsSpec
  childrenSpec
  effectfulInSpec
  pipelineNodeGuardSpec

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

-- | 'effectfulIn' must flag exactly the built-ins the 'Awsum.BuiltIn'
--   registry marks 'Effectful', and nothing else — the property that keeps
--   'Awsum.Simplify' from deleting a platform effect it mistook for pure.
--   The defect is latent: today the effectful primitives are precisely the
--   four @internal*@ built-ins, so the old hardcoded list in 'effectfulIn' and
--   the registry happened to agree. A fifth platform effect added only to the
--   registry would, under that hardcoded list, slip past 'effectfulIn' and be
--   dropped with every backend's stdout still identical — invisible to the
--   snapshot and property suites. Deriving the set from the registry
--   ('effectfulBuiltIns') closes the hole; this spec is the tripwire if
--   'effectfulIn' ever regrows a parallel list. Synthetic 'CExpr', because no
--   .aww program reaches the divergence (the fifth effect doesn't exist yet).
effectfulInSpec :: Spec
effectfulInSpec = describe "Awsum.Core.effectfulIn" $ do
  -- A bare CBuiltIn only ever appears in CCall function position (the CExpr
  -- invariants), so feed well-formed calls.
  let callOf n = CCall (CBuiltIn n) []
      pureBuiltInNames = Set.toList (M.keysSet builtIns `Set.difference` effectfulBuiltIns)

  it "flags every built-in the registry marks Effectful"
    $ for_ (Set.toList effectfulBuiltIns) (\n -> effectfulIn (callOf n) `shouldBe` True)

  it "flags no built-in the registry marks Pure"
    $ for_ pureBuiltInNames (\n -> effectfulIn (callOf n) `shouldBe` False)

  it "has a non-empty effectful set anchored at a known I/O primitive" $ do
    -- Catches a catastrophic "everything marked Pure" regression and ties the
    -- derived set to a concrete real effect.
    Set.null effectfulBuiltIns `shouldBe` False
    Set.member "internalStdoutPrint" effectfulBuiltIns `shouldBe` True

  it "finds an effectful call nested inside a case arm"
    $ effectfulIn (CCase (CVar "s") [(1, [], callOf "internalStdoutPrint"), (2, [], CVar "x")])
    `shouldBe` True

  it "is False for a pure expression with no built-in call"
    $ effectfulIn (CCase (CVar "s") [(1, ["v"], CVar "v"), (2, [], CIntLit 0 TInt32)])
    `shouldBe` False

-- | Force a Core program deep enough to raise a buried pipeline-bug 'error':
--   'show' walks the whole tree, 'length' forces every character of it.
forceProgram :: CoreProgram -> IO Int
forceProgram p = evaluateWHNF (length (show p :: String))

-- | A 'shouldThrow' selector matching an 'ErrorCall' whose message contains
--   @needle@ — enough to pin which arm fired, without nailing the full wording.
errorContaining :: Text -> Selector ErrorCall
errorContaining needle (ErrorCall msg) = needle `T.isInfixOf` toText msg

-- | 'Awsum.Cps' and 'Awsum.Tco' run before 'Awsum.Simplify', so their input
--   never carries the nodes Simplify mints ('CLet' / 'CProj' / 'CJoin' /
--   'CJump'). Both passes enumerate every 'CExpr' constructor and reject those
--   four loudly instead of leafing them through a catch-all. The hazard this
--   guards is concrete: were 'Awsum.Tco' ever reordered after Simplify, a tail
--   self-call inside a 'CJoin' body left un-rewritten would stay a 'CCall' past
--   'Awsum.StackSafety' and blow the stack on JVM/JS. Compile-time
--   exhaustiveness already forces every constructor to be /handled/; these
--   assertions add what it cannot see — that the arm /raises/ rather than
--   quietly returning a value, the exact regression the original defect was.
--   Synthetic 'CExpr', because no .aww program can route a post-Simplify node
--   into a pre-Simplify pass.
pipelineNodeGuardSpec :: Spec
pipelineNodeGuardSpec = do
  describe "Awsum.Tco.tcoProgram rejects post-Simplify nodes (CJoin the sharp one)"
    $ for_ minted
    $ \(label, node) ->
      it ("raises on " <> label <> " in tail position")
        $ forceProgram (tcoProgram (oneFn [] node))
        `shouldThrow` errorContaining (toText label <> " reached rewriteTail")

  describe "Awsum.Cps.cpsProgram rejects post-Simplify nodes" $ do
    for_ minted $ \(label, node) ->
      it ("raises on " <> label <> " in non-tail position (goNonTail)")
        $ forceProgram (cpsProgram (oneFn ["x"] (besideNonTailSelfCall node)))
        `shouldThrow` errorContaining (toText label <> " reached goNonTail")

    it "raises on a CJoin reached in tail position (goTail)"
      $ forceProgram (cpsProgram (oneFn ["x"] (tailArmBesideSelfCall (CJoin "$j" [] (CVar "y") (CVar "z")))))
      `shouldThrow` errorContaining "CJoin reached goTail"
  where
    -- The four nodes 'Awsum.Simplify' mints, each a minimal instance — only the
    -- constructor reaches the rejecting arm, so well-formedness is irrelevant.
    minted :: [(String, CExpr)]
    minted =
      [ ("CLet", CLet "v" (CIntLit 0 TInt32) (CVar "v")),
        ("CProj", CProj "x" 0),
        ("CJoin", CJoin "$j" [] (CVar "y") (CVar "z")),
        ("CJump", CJump "$j" [CVar "y"])
      ]

    oneFn :: [Name] -> CExpr -> CoreProgram
    oneFn ps body = CoreProgram [CFunDef "f" ps body]

    -- A non-tail self-call (so 'cpsProgram' transforms the body at all) sitting
    -- in a 'CCon' field beside the node; both fields are non-tail, so the node
    -- reaches 'goNonTail'.
    besideNonTailSelfCall :: CExpr -> CExpr
    besideNonTailSelfCall node = CCon 0 [CCall (CVar "f") [CVar "x"], node]

    -- A non-tail self-call in one case arm forces CPS; the node sits in the
    -- sibling arm's tail position, where 'goTail' walks it.
    tailArmBesideSelfCall :: CExpr -> CExpr
    tailArmBesideSelfCall node =
      CCase
        (CVar "x")
        [ (0, [], CCon 0 [CCall (CVar "f") [CVar "x"]]),
          (1, [], node)
        ]
