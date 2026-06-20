module Awsum.HMSpec (spec) where

import Awsum.ArbitraryInstances ()
import Awsum.HM
  ( Scheme (..),
    Subst,
    TC,
    UnifyError (..),
    applySubst,
    collectTypeVars,
    composeSubst,
    fresh,
    generalize,
    instantiate,
    occursIn,
    runTC,
    singletonSubst,
    unify,
  )
import Awsum.Syntax (Name, Type' (..), noSpan)
import Data.Set qualified as S
import Data.Text qualified as T
import Relude
import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck ((.&&.), (===))

-- | Concrete error type for 'TC' computations in this spec — 'TC' is
--   error-polymorphic, so call sites must pin it. Using 'Text' keeps
--   the test self-contained (no dependency on 'Awsum.Typing.TypeError').
type TCErr = Text

runTC' :: TC TCErr a -> Either TCErr a
runTC' = runTC

spec :: Spec
spec = do
  describe "Awsum.HM.applySubst" $ do
    it "leaves an unmapped tyvar alone" $ do
      let s = singletonSubst "a" (TyCon noSpan "Int32")
          t = TyVar noSpan "b"
      applySubst s t `shouldBe` t

    it "replaces a mapped tyvar" $ do
      let s = singletonSubst "a" (TyCon noSpan "Int32")
      applySubst s (TyVar noSpan "a") `shouldBe` TyCon noSpan "Int32"

    it "leaves a TyCon alone" $ do
      let s = singletonSubst "a" (TyCon noSpan "Int32")
      applySubst s (TyCon noSpan "String") `shouldBe` TyCon noSpan "String"

    it "recurses into TyApp" $ do
      let s = singletonSubst "a" (TyCon noSpan "Int32")
          t = TyApp noSpan (TyCon noSpan "Maybe") (TyVar noSpan "a")
      applySubst s t `shouldBe` TyApp noSpan (TyCon noSpan "Maybe") (TyCon noSpan "Int32")

    it "recurses into TyArrow on both sides" $ do
      let s = singletonSubst "a" (TyCon noSpan "Int32")
          t = TyArrow noSpan (TyVar noSpan "a") (TyVar noSpan "a")
      applySubst s t
        `shouldBe` TyArrow noSpan (TyCon noSpan "Int32") (TyCon noSpan "Int32")

    it "applies multiple bindings via Semigroup composition" $ do
      let s =
            singletonSubst "a" (TyCon noSpan "Int32")
              <> singletonSubst "b" (TyCon noSpan "String")
          t = TyArrow noSpan (TyVar noSpan "a") (TyVar noSpan "b")
      applySubst s t
        `shouldBe` TyArrow noSpan (TyCon noSpan "Int32") (TyCon noSpan "String")

    it "is identity under mempty" $ do
      let t =
            TyArrow
              noSpan
              (TyVar noSpan "a")
              (TyApp noSpan (TyCon noSpan "Maybe") (TyVar noSpan "b"))
      applySubst mempty t `shouldBe` t

  describe "Awsum.HM Subst Semigroup" $ do
    it "composes in mathematical order: apply (s2 <> s1) == apply s2 . apply s1" $ do
      -- s1 maps a → b; s2 maps b → Int32. Composition should map a → Int32.
      let s1 = singletonSubst "a" (TyVar noSpan "b")
          s2 = singletonSubst "b" (TyCon noSpan "Int32")
          t = TyVar noSpan "a"
      applySubst (s2 <> s1) t `shouldBe` applySubst s2 (applySubst s1 t)
      applySubst (s2 <> s1) t `shouldBe` TyCon noSpan "Int32"

    it "composeSubst is the same as (<>)" $ do
      let s1 = singletonSubst "a" (TyVar noSpan "b")
          s2 = singletonSubst "b" (TyCon noSpan "Int32")
          t = TyVar noSpan "a"
      applySubst (composeSubst s2 s1) t `shouldBe` applySubst (s2 <> s1) t

    it "associativity: (s3 <> s2) <> s1 == s3 <> (s2 <> s1)" $ do
      let s1 = singletonSubst "a" (TyVar noSpan "b")
          s2 = singletonSubst "b" (TyVar noSpan "c")
          s3 = singletonSubst "c" (TyCon noSpan "Int32")
          t = TyVar noSpan "a"
      applySubst ((s3 <> s2) <> s1) t `shouldBe` applySubst (s3 <> (s2 <> s1)) t

    it "earlier binding wins on overlapping keys (compose order)" $ do
      -- sLate <> sEarly: sEarly applied first (a → Int32), then sLate
      -- (no effect on Int32). Net: a → Int32, because sLate's a-binding
      -- never fires — by the time it would, 'a' is already gone.
      let sEarly = singletonSubst "a" (TyCon noSpan "Int32")
          sLate = singletonSubst "a" (TyCon noSpan "String")
      applySubst (sLate <> sEarly) (TyVar noSpan "a")
        `shouldBe` TyCon noSpan "Int32"

  describe "Awsum.HM.occursIn" $ do
    it "True when the type IS the tyvar"
      $ occursIn "a" (TyVar noSpan "a")
      `shouldBe` True

    it "False for a different tyvar"
      $ occursIn "a" (TyVar noSpan "b")
      `shouldBe` False

    it "False for a TyCon"
      $ occursIn "a" (TyCon noSpan "Int32")
      `shouldBe` False

    it "True if tyvar appears under TyApp"
      $ occursIn "a" (TyApp noSpan (TyCon noSpan "Maybe") (TyVar noSpan "a"))
      `shouldBe` True

    it "True if tyvar appears in TyArrow domain"
      $ occursIn "a" (TyArrow noSpan (TyVar noSpan "a") (TyCon noSpan "Int32"))
      `shouldBe` True

    it "True if tyvar appears in TyArrow codomain"
      $ occursIn "a" (TyArrow noSpan (TyCon noSpan "Int32") (TyVar noSpan "a"))
      `shouldBe` True

    it "False when tyvar is absent across nested arrows"
      $ occursIn
        "a"
        ( TyArrow
            noSpan
            (TyVar noSpan "b")
            (TyArrow noSpan (TyVar noSpan "c") (TyCon noSpan "Int32"))
        )
      `shouldBe` False

    it "True for the classic infinite-type shape α ~ α -> Int32"
      $ occursIn "a" (TyArrow noSpan (TyVar noSpan "a") (TyCon noSpan "Int32"))
      `shouldBe` True

  describe "Awsum.HM.unify" $ do
    it "unifies two equal TyCons with the identity substitution" $ do
      case unify (TyCon noSpan "Int32") (TyCon noSpan "Int32") of
        Right s -> applySubst s (TyCon noSpan "Int32") `shouldBe` TyCon noSpan "Int32"
        Left err -> expectationFailure ("unexpected " <> show err)

    it "rejects two different TyCons with CannotUnify" $ do
      let l = TyCon noSpan "Int32"
          r = TyCon noSpan "String"
      unify l r `shouldBe` Left (CannotUnify l r)

    it "binds a TyVar to a TyCon when on the left" $ do
      case unify (TyVar noSpan "a") (TyCon noSpan "Int32") of
        Right s -> applySubst s (TyVar noSpan "a") `shouldBe` TyCon noSpan "Int32"
        Left err -> expectationFailure ("unexpected " <> show err)

    it "binds a TyVar to a TyCon when on the right (symmetry)" $ do
      case unify (TyCon noSpan "Int32") (TyVar noSpan "a") of
        Right s -> applySubst s (TyVar noSpan "a") `shouldBe` TyCon noSpan "Int32"
        Left err -> expectationFailure ("unexpected " <> show err)

    it "unifies a tyvar with itself with the identity substitution" $ do
      case unify (TyVar noSpan "a") (TyVar noSpan "a") of
        Right s -> applySubst s (TyVar noSpan "a") `shouldBe` TyVar noSpan "a"
        Left err -> expectationFailure ("unexpected " <> show err)

    it "merges two distinct tyvars" $ do
      -- One direction: result substitution makes both sides equal under apply.
      case unify (TyVar noSpan "a") (TyVar noSpan "b") of
        Right s -> applySubst s (TyVar noSpan "a") `shouldBe` applySubst s (TyVar noSpan "b")
        Left err -> expectationFailure ("unexpected " <> show err)

    it "recurses through TyApp, binding both sides" $ do
      let l = TyApp noSpan (TyCon noSpan "Maybe") (TyVar noSpan "a")
          r = TyApp noSpan (TyCon noSpan "Maybe") (TyCon noSpan "Int32")
      case unify l r of
        Right s -> do
          applySubst s l `shouldBe` applySubst s r
          applySubst s (TyVar noSpan "a") `shouldBe` TyCon noSpan "Int32"
        Left err -> expectationFailure ("unexpected " <> show err)

    it "fails on different TyApp heads" $ do
      let l = TyApp noSpan (TyCon noSpan "Maybe") (TyVar noSpan "a")
          r = TyApp noSpan (TyCon noSpan "Either") (TyVar noSpan "a")
      case unify l r of
        Left (CannotUnify _ _) -> pass
        other -> expectationFailure ("expected CannotUnify on heads, got: " <> show other)

    it "fails when matched heads have non-unifiable arguments" $ do
      let l = TyApp noSpan (TyCon noSpan "Maybe") (TyCon noSpan "Int32")
          r = TyApp noSpan (TyCon noSpan "Maybe") (TyCon noSpan "String")
      case unify l r of
        Left (CannotUnify lt rt) -> do
          lt `shouldBe` TyCon noSpan "Int32"
          rt `shouldBe` TyCon noSpan "String"
        other -> expectationFailure ("expected CannotUnify on inner, got: " <> show other)

    it "recurses through TyArrow on both sides" $ do
      let l = TyArrow noSpan (TyVar noSpan "a") (TyVar noSpan "b")
          r = TyArrow noSpan (TyCon noSpan "Int32") (TyCon noSpan "String")
      case unify l r of
        Right s -> do
          applySubst s (TyVar noSpan "a") `shouldBe` TyCon noSpan "Int32"
          applySubst s (TyVar noSpan "b") `shouldBe` TyCon noSpan "String"
        Left err -> expectationFailure ("unexpected " <> show err)

    it "propagates a constraint across two occurrences of the same tyvar" $ do
      -- unify (a -> a) (Int32 -> b): a unifies with Int32 on the left,
      -- which forces b ~ Int32 on the right. Both bindings must come
      -- back in the resulting substitution.
      let l = TyArrow noSpan (TyVar noSpan "a") (TyVar noSpan "a")
          r = TyArrow noSpan (TyCon noSpan "Int32") (TyVar noSpan "b")
      case unify l r of
        Right s -> do
          applySubst s (TyVar noSpan "a") `shouldBe` TyCon noSpan "Int32"
          applySubst s (TyVar noSpan "b") `shouldBe` TyCon noSpan "Int32"
        Left err -> expectationFailure ("unexpected " <> show err)

    it "rejects arrow vs non-arrow" $ do
      let l = TyArrow noSpan (TyCon noSpan "Int32") (TyCon noSpan "Int32")
          r = TyCon noSpan "String"
      case unify l r of
        Left (CannotUnify _ _) -> pass
        other -> expectationFailure ("expected CannotUnify, got: " <> show other)

    it "fires the occurs check on α ~ α -> Int32" $ do
      -- The classic infinite-type shape: rejecting it is the whole
      -- point of having an occurs check.
      let l = TyVar noSpan "a"
          r = TyArrow noSpan (TyVar noSpan "a") (TyCon noSpan "Int32")
      case unify l r of
        Left (OccursCheckFailed v t) -> do
          v `shouldBe` "a"
          t `shouldBe` r
        other -> expectationFailure ("expected OccursCheckFailed, got: " <> show other)

    it "fires the occurs check symmetrically (α -> Int32 ~ α)" $ do
      let l = TyArrow noSpan (TyVar noSpan "a") (TyCon noSpan "Int32")
          r = TyVar noSpan "a"
      case unify l r of
        Left (OccursCheckFailed v _) -> v `shouldBe` "a"
        other -> expectationFailure ("expected OccursCheckFailed, got: " <> show other)

    it "result substitution is a unifier: applying it to both sides yields equal types" $ do
      -- General property exercised across a non-trivial pair: any
      -- successful unify must produce a substitution under which the
      -- two input types become structurally equal.
      let l =
            TyArrow
              noSpan
              (TyApp noSpan (TyCon noSpan "Maybe") (TyVar noSpan "a"))
              (TyVar noSpan "b")
          r =
            TyArrow
              noSpan
              (TyApp noSpan (TyCon noSpan "Maybe") (TyCon noSpan "Int32"))
              (TyVar noSpan "a")
      case unify l r of
        Right s -> applySubst s l `shouldBe` applySubst s r
        Left err -> expectationFailure ("unexpected " <> show err)

  describe "Awsum.HM.collectTypeVars" $ do
    it "empty for a TyCon"
      $ collectTypeVars (TyCon noSpan "Int32")
      `shouldBe` S.empty

    it "singleton for a bare TyVar"
      $ collectTypeVars (TyVar noSpan "a")
      `shouldBe` S.singleton "a"

    it "unions across TyApp"
      $ collectTypeVars
        (TyApp noSpan (TyVar noSpan "a") (TyVar noSpan "b"))
      `shouldBe` S.fromList ["a", "b"]

    it "unions across TyArrow, dedups repeated names"
      $ collectTypeVars
        (TyArrow noSpan (TyVar noSpan "a") (TyVar noSpan "a"))
      `shouldBe` S.singleton "a"

    it "walks nested structure"
      $ collectTypeVars
        ( TyArrow
            noSpan
            (TyApp noSpan (TyCon noSpan "Maybe") (TyVar noSpan "a"))
            (TyApp noSpan (TyCon noSpan "Maybe") (TyVar noSpan "b"))
        )
      `shouldBe` S.fromList ["a", "b"]

  describe "Awsum.HM.generalize" $ do
    it "concrete type generalises to an empty Forall"
      $ generalize S.empty (TyCon noSpan "Int32")
      `shouldBe` Forall [] (TyCon noSpan "Int32")

    it "binds every tyvar when env is empty"
      $ generalize
        S.empty
        (TyArrow noSpan (TyVar noSpan "a") (TyVar noSpan "a"))
      `shouldBe` Forall ["a"] (TyArrow noSpan (TyVar noSpan "a") (TyVar noSpan "a"))

    it "skips tyvars that are free in the environment"
      $ generalize
        (S.singleton "a")
        (TyArrow noSpan (TyVar noSpan "a") (TyVar noSpan "b"))
      `shouldBe` Forall ["b"] (TyArrow noSpan (TyVar noSpan "a") (TyVar noSpan "b"))

    it "binds nothing when every tyvar is in the env"
      $ generalize
        (S.fromList ["a", "b"])
        (TyArrow noSpan (TyVar noSpan "a") (TyVar noSpan "b"))
      `shouldBe` Forall [] (TyArrow noSpan (TyVar noSpan "a") (TyVar noSpan "b"))

    it "produces a sorted bound-list (deterministic)" $ do
      let scheme1 =
            generalize
              S.empty
              (TyArrow noSpan (TyVar noSpan "b") (TyVar noSpan "a"))
          scheme2 =
            generalize
              S.empty
              (TyArrow noSpan (TyVar noSpan "a") (TyVar noSpan "b"))
      case (scheme1, scheme2) of
        (Forall vs1 _, Forall vs2 _) -> vs1 `shouldBe` vs2

  describe "Awsum.HM.instantiate" $ do
    it "leaves a non-quantified scheme as its body" $ do
      let scheme = Forall [] (TyCon noSpan "Int32")
      runTC' (instantiate scheme) `shouldBe` Right (TyCon noSpan "Int32")

    it "replaces a single bound tyvar with a fresh one" $ do
      let scheme = Forall ["a"] (TyArrow noSpan (TyVar noSpan "a") (TyVar noSpan "a"))
      runTC' (instantiate scheme)
        `shouldBe` Right (TyArrow noSpan (TyVar noSpan "t0") (TyVar noSpan "t0"))

    it "replaces multiple bound tyvars with distinct fresh ones" $ do
      let scheme = Forall ["a", "b"] (TyArrow noSpan (TyVar noSpan "a") (TyVar noSpan "b"))
      runTC' (instantiate scheme)
        `shouldBe` Right (TyArrow noSpan (TyVar noSpan "t0") (TyVar noSpan "t1"))

    it "different uses of the same scheme produce disjoint fresh tyvars" $ do
      -- Run two instantiations back-to-back in the same TC computation;
      -- the counter must advance, so the second use can't collide with
      -- the first.
      let scheme = Forall ["a"] (TyVar noSpan "a")
          action :: TC TCErr (Type', Type')
          action = (,) <$> instantiate scheme <*> instantiate scheme
      runTC' action
        `shouldBe` Right (TyVar noSpan "t0", TyVar noSpan "t1")

    it "leaves free (unbound) tyvars in the body alone" $ do
      -- Body mentions @a@ and @b@; only @a@ is quantified. @b@ stays.
      let scheme = Forall ["a"] (TyArrow noSpan (TyVar noSpan "a") (TyVar noSpan "b"))
      runTC' (instantiate scheme)
        `shouldBe` Right (TyArrow noSpan (TyVar noSpan "t0") (TyVar noSpan "b"))

  describe "Awsum.HM generalize ↔ instantiate round-trip" $ do
    it "fresh tyvars from instantiate cover the structure of the original" $ do
      -- Take a polymorphic shape, generalise, instantiate, and check the
      -- shape (TyArrow over TyVar/TyVar) is preserved — only the names change.
      let original = TyArrow noSpan (TyVar noSpan "a") (TyVar noSpan "a")
          scheme = generalize S.empty original
      case runTC' (instantiate scheme) of
        Right (TyArrow _ (TyVar _ v1) (TyVar _ v2)) -> do
          v1 `shouldBe` v2 -- both copies of "a" map to the same fresh tyvar
          T.take 1 v1 `shouldBe` "t" -- it really is a fresh `tN`
        other -> expectationFailure ("unexpected shape: " <> show other)

  describe "Awsum.HM.unify (set-semantic on TyOr)" $ do
    -- Helper: assert two types unify with the identity substitution
    -- (no variable bindings needed). Used for the commutativity /
    -- idempotency / associativity laws, where the two rows are
    -- equivalent as label sets and unification finds matching pairs
    -- without needing to bind anything.
    let shouldUnifyAsIdentity a b =
          unify a b `shouldBe` (Right mempty :: Either UnifyError Subst)

    it "is commutative: (A | B) ~ (B | A)" $ do
      let l = TyOr noSpan (TyCon noSpan "Int32") (TyCon noSpan "String")
          r = TyOr noSpan (TyCon noSpan "String") (TyCon noSpan "Int32")
      shouldUnifyAsIdentity l r

    it "is idempotent: (A | A | B) ~ (A | B)" $ do
      let l =
            TyOr
              noSpan
              (TyCon noSpan "Int32")
              (TyOr noSpan (TyCon noSpan "Int32") (TyCon noSpan "String"))
          r = TyOr noSpan (TyCon noSpan "Int32") (TyCon noSpan "String")
      shouldUnifyAsIdentity l r

    it "is associative: ((A | B) | C) ~ (A | (B | C))" $ do
      let l =
            TyOr
              noSpan
              (TyOr noSpan (TyCon noSpan "Int32") (TyCon noSpan "String"))
              (TyCon noSpan "UInt8")
          r =
            TyOr
              noSpan
              (TyCon noSpan "Int32")
              (TyOr noSpan (TyCon noSpan "String") (TyCon noSpan "UInt8"))
      shouldUnifyAsIdentity l r

    it "rejects sets with a non-overlapping label: (A | B) !~ (A | C)" $ do
      let l = TyOr noSpan (TyCon noSpan "Int32") (TyCon noSpan "String")
          r = TyOr noSpan (TyCon noSpan "Int32") (TyCon noSpan "UInt8")
      case unify l r of
        Left (CannotUnify lt rt) -> do
          lt `shouldBe` l
          rt `shouldBe` r
        other ->
          expectationFailure ("expected CannotUnify on row mismatch, got: " <> show other)

    it "rejects sets of different sizes: (A | B | C) !~ (A | B)" $ do
      let l =
            TyOr
              noSpan
              (TyCon noSpan "Int32")
              (TyOr noSpan (TyCon noSpan "String") (TyCon noSpan "UInt8"))
          r = TyOr noSpan (TyCon noSpan "Int32") (TyCon noSpan "String")
      case unify l r of
        Left (CannotUnify _ _) -> pass
        other -> expectationFailure ("expected CannotUnify, got: " <> show other)

    it "binds a tyvar in a row: (a | Int32) ~ (String | Int32) ⇒ a ↦ String" $ do
      -- Greedy chooses the unambiguous match: 'a' tries the first
      -- right-hand label (String) and binds, then 'Int32' matches 'Int32'.
      let l = TyOr noSpan (TyVar noSpan "a") (TyCon noSpan "Int32")
          r = TyOr noSpan (TyCon noSpan "String") (TyCon noSpan "Int32")
      case unify l r of
        Right s ->
          applySubst s (TyVar noSpan "a") `shouldBe` TyCon noSpan "String"
        Left err -> expectationFailure ("unexpected " <> show err)

    it "treats a non-TyOr as a singleton row: (Int32 | Int32) ~ Int32" $ do
      -- After dedup the LHS reduces to '[Int32]', matching the RHS
      -- singleton row. Useful sanity check that the singleton wrapping
      -- happens uniformly.
      let l = TyOr noSpan (TyCon noSpan "Int32") (TyCon noSpan "Int32")
          r = TyCon noSpan "Int32"
      case unify l r of
        Right _ -> pass
        Left err -> expectationFailure ("unexpected " <> show err)

    it "rejects (A | B) against a single concrete: (Int32 | String) !~ Int32" $ do
      let l = TyOr noSpan (TyCon noSpan "Int32") (TyCon noSpan "String")
          r = TyCon noSpan "Int32"
      case unify l r of
        Left (CannotUnify _ _) -> pass
        other -> expectationFailure ("expected CannotUnify, got: " <> show other)

    it "recurses into label structure: (Maybe a | Int32) ~ (Maybe Int32 | Int32) ⇒ a ↦ Int32" $ do
      let l =
            TyOr
              noSpan
              (TyApp noSpan (TyCon noSpan "Maybe") (TyVar noSpan "a"))
              (TyCon noSpan "Int32")
          r =
            TyOr
              noSpan
              (TyApp noSpan (TyCon noSpan "Maybe") (TyCon noSpan "Int32"))
              (TyCon noSpan "Int32")
      case unify l r of
        Right s ->
          applySubst s (TyVar noSpan "a") `shouldBe` TyCon noSpan "Int32"
        Left err -> expectationFailure ("unexpected " <> show err)

  describe "Awsum.HM.unify (empty type is the row identity)" $ do
    -- 'Never' (and any empty type) is the row identity: it drops out of a
    -- row, so '(Never | A)' unifies with 'A'. Before the fix the
    -- differing-cardinality path counted 'Never' as an unabsorbable extra
    -- label and rejected the pair. These are not reachable from surface
    -- '.aww' (the typechecker's acceptance boundary is 'rowSubsume', which
    -- already handles empties), so the unifier-level law is pinned here.
    let never = TyEmpty noSpan "Never"
        a = TyCon noSpan "A"
        idSubst = Right mempty :: Either UnifyError Subst

    it "(Never | A) ~ A"
      $ unify (TyOr noSpan never a) a
      `shouldBe` idSubst

    it "A ~ (Never | A) (symmetry)"
      $ unify a (TyOr noSpan never a)
      `shouldBe` idSubst

    it "(Never | A) ~ (Never | A)"
      $ unify (TyOr noSpan never a) (TyOr noSpan never a)
      `shouldBe` idSubst

    it "folds two distinct empty names: (Never | Whatever | A) ~ (Never | A)" $ do
      let whatever = TyEmpty noSpan "Whatever"
      unify (TyOr noSpan never (TyOr noSpan whatever a)) (TyOr noSpan never a)
        `shouldBe` idSubst

    it "binds a tyvar past a dropped empty: (Never | a) ~ A ⇒ a ↦ A"
      $ case unify (TyOr noSpan never (TyVar noSpan "a")) a of
        Right s -> applySubst s (TyVar noSpan "a") `shouldBe` a
        Left err -> expectationFailure ("unexpected " <> show err)

    it "a lone empty is still not a populated type: Never !~ A"
      $ case unify never a of
        Left (CannotUnify _ _) -> pass
        other -> expectationFailure ("expected CannotUnify, got: " <> show other)

    it "differing non-empty labels still fail: (Never | A) !~ B"
      $ case unify (TyOr noSpan never a) (TyCon noSpan "B") of
        Left (CannotUnify _ _) -> pass
        other -> expectationFailure ("expected CannotUnify, got: " <> show other)

  describe "Awsum.HM.unify (set-semantic laws via QuickCheck)" $ do
    -- Property tests over arbitrary 'Type'' values (instance from
    -- 'Awsum.ArbitraryInstances'). They cover the laws that the
    -- example-based tests above only sample at fixed shapes.
    --
    -- Commutativity is intentionally /not/ tested as @unify a b ===
    -- unify b a@: greedy matching produces equivalent unifiers (ones
    -- that make both sides equal under 'applySubst') but not
    -- necessarily structurally identical substitutions when both rows
    -- contain tyvars — e.g. @unify (a | b) (b | a)@ commits to
    -- @{a ↦ b}@, while the flipped form commits to @{b ↦ a}@. Both
    -- are valid solutions; structural equality on 'Subst' would falsely
    -- reject one of them.
    let identitySubst :: Either UnifyError Subst
        identitySubst = Right mempty

    prop "reflexive: unify t t == Right mempty" $ \t ->
      unify (t :: Type') t === identitySubst

    prop "left dedup: unify (t | t) t == Right mempty" $ \t ->
      unify (TyOr noSpan (t :: Type') t) t === identitySubst

    prop "right dedup: unify t (t | t) == Right mempty" $ \t ->
      unify (t :: Type') (TyOr noSpan t t) === identitySubst

    prop "self-flatten reflexivity: unify (t | t | t) t == Right mempty" $ \t ->
      let triplicated = TyOr noSpan (t :: Type') (TyOr noSpan t t)
       in (unify triplicated t === identitySubst)
            .&&. (unify t triplicated === identitySubst)

  describe "Awsum.HM.fresh" $ do
    it "first call returns t0"
      $ runTC' fresh
      `shouldBe` Right ("t0" :: Name)

    it "successive calls produce a distinct, ordered sequence" $ do
      let action :: TC TCErr [Name]
          action = sequence [fresh, fresh, fresh, fresh]
      runTC' action `shouldBe` Right ["t0", "t1", "t2", "t3"]

    it "names start with 't' and never with leading underscore" $ do
      case runTC' fresh of
        Right name -> do
          T.take 1 name `shouldBe` "t"
          T.isPrefixOf "_" name `shouldBe` False
        Left err -> expectationFailure (toString err)
