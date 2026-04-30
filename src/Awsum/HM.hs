-- | Hindley-Milner-related infrastructure: substitutions, occurs check,
--   symmetric unification, and a type-checker monad with fresh-tyvar
--   generation.
--
--   This module is the seed for the upcoming HM-based type inference.
--   Its first user is internal to 'Awsum.Typing' — the existing one-way
--   matcher 'Awsum.Typing.match' reuses the substitution machinery from
--   here. Two-way 'unify' and 'UnifyError' are added alongside 'match'
--   for the upcoming bidirectional-checker stage; existing call sites
--   continue to use 'match' until that migration. Later stages introduce
--   bidirectional checking and let-generalisation on top.
module Awsum.HM
  ( -- * Substitutions
    Subst,
    singletonSubst,
    applySubst,
    composeSubst,

    -- * Occurs check
    occursIn,

    -- * Free type variables
    collectTypeVars,

    -- * Unification
    UnifyError (..),
    unify,
    flattenRow,
    rowSubsume,
    rowTag,
    canonicalLabel,

    -- * Schemes (polymorphic types)
    Scheme (..),
    generalize,
    instantiate,
    freshenType,

    -- * Type-checker monad
    TC,
    runTC,
    fresh,
  )
where

import Awsum.Syntax (Name, Type' (..), noSpan)
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import Data.Text qualified as T
import Relude

-- | A type substitution: a finite mapping from tyvar names to types.
--
--   The 'Semigroup' instance is /composition in mathematical-function
--   order/:
--
--   @applySubst (s2 \<\> s1) t == applySubst s2 (applySubst s1 t)@
--
--   so @s2 \<\> s1@ reads as "apply @s1@ first, then @s2@", just like
--   @(.)@ on functions. 'mempty' is the identity substitution.
--
--   The internal 'M.Map' representation is intentionally hidden; build
--   substitutions through 'mempty', 'singletonSubst', and '(<>)'.
newtype Subst = Subst (M.Map Name Type')
  deriving stock (Show, Eq)

instance Semigroup Subst where
  (<>) = composeSubst

instance Monoid Subst where
  mempty = Subst M.empty

-- | A single-binding substitution: @v ↦ t@.
singletonSubst :: Name -> Type' -> Subst
singletonSubst v t = Subst (M.singleton v t)

-- | Apply a substitution to a type, replacing every free 'TyVar'
--   whose name is in the substitution's domain. The replacement
--   inherits the spans of the substituted type, not of the original
--   variable — that mirrors how a unifier-driven rewrite would track
--   provenance.
applySubst :: Subst -> Type' -> Type'
applySubst (Subst s) = go
  where
    go = \case
      TyVar sp v -> fromMaybe (TyVar sp v) (M.lookup v s)
      TyCon sp c -> TyCon sp c
      TyApp sp f x -> TyApp sp (go f) (go x)
      TyArrow sp a b -> TyArrow sp (go a) (go b)
      TyOr sp a b -> TyOr sp (go a) (go b)

-- | Compose two substitutions in mathematical-function order:
--
--   @applySubst (composeSubst s2 s1) t == applySubst s2 (applySubst s1 t)@
--
--   so @composeSubst s2 s1@ reads as "@s2@ after @s1@" — @s1@
--   applied first, @s2@ second. This is what '(<>)' does as well;
--   'composeSubst' is exposed for call sites that prefer the
--   named form for clarity.
composeSubst :: Subst -> Subst -> Subst
composeSubst (Subst s2) (Subst s1) =
  Subst ((applySubst (Subst s2) <$> s1) `M.union` s2)

-- | Does the named type variable occur anywhere in the given type?
--
--   The classic /occurs check/ used by unification to reject
--   infinite types like @α ~ α -> Int32@. Currently a pure
--   structural traversal — no substitution is applied, so callers
--   must apply any pending substitution to the type first if they
--   want "occurs after substitution" semantics.
occursIn :: Name -> Type' -> Bool
occursIn n = go
  where
    go = \case
      TyVar _ v -> v == n
      TyCon _ _ -> False
      TyApp _ f x -> go f || go x
      TyArrow _ a b -> go a || go b
      TyOr _ a b -> go a || go b

-- | Why 'unify' rejected a pair of types.
--
--   Surfaced by 'unify' but kept as a separate type from
--   'Awsum.Typing.TypeError': the unifier is conceptually a primitive
--   operation, and the type checker's bidirectional layer translates
--   these low-level mismatches into user-facing diagnostics
--   ('TypeMismatch' when one side is the "expected" type, 'CannotUnify'
--   when both sides are independently inferred).
data UnifyError
  = -- | Two types could not be made equal — structural mismatch
    --   (different 'TyCon's, arrow vs non-arrow, different 'TyApp'
    --   heads, etc.). Carries the two offending types in their
    --   pre-substitution form, with their original spans intact, so
    --   diagnostics can point at the exact source positions.
    CannotUnify Type' Type'
  | -- | A variable would have to appear inside the type it is being
    --   unified against — the classic infinite-type case
    --   (@α ~ α -> Int32@). First field is the variable name, second
    --   is the type that referenced it.
    OccursCheckFailed Name Type'
  deriving stock (Show, Eq)

-- | Two-way unification: find the most general substitution @s@ such that
--   @applySubst s t1 == applySubst s t2@, or fail with 'UnifyError'.
--
--   Symmetric in argument order: for any inputs, @unify a b@ and
--   @unify b a@ either both succeed (with substitutions equivalent up
--   to renaming) or both fail with the same kind of error.
--
--   Compared to the one-way 'Awsum.Typing.match' (which only binds
--   variables on its first argument and returns 'Maybe'), 'unify':
--
--   * binds variables on /either/ side, so two unrelated
--     unification variables can be merged;
--   * runs the occurs check, rejecting infinite types like
--     @α ~ α -> Int32@;
--   * reports the cause of failure ('CannotUnify' / 'OccursCheckFailed')
--     instead of an opaque 'Nothing'.
--
--   Spans on the input types are preserved through to 'UnifyError'
--   payloads so the bidirectional-checker layer above can produce
--   diagnostics that point at exact source positions.
unify :: Type' -> Type' -> Either UnifyError Subst
unify t1 t2 = case (t1, t2) of
  -- Bind a free 'TyVar' to whatever sits on the other side, including
  -- a whole 'TyOr' row. The occurs guard keeps
  -- @unify (TyOr a a) (TyVar a)@ on the row path below: the
  -- duplicated label would trip 'bindVar' even though the row is
  -- semantically just @a@; 'unifyRows' flattens and dedupes before
  -- deciding, so it handles the dedup case correctly.
  (TyVar _ v, _) | not (occursIn v t2) -> bindVar v t2
  (_, TyVar _ v) | not (occursIn v t1) -> bindVar v t1
  -- Set-semantic unification for structural sums. Falls through to here
  -- when neither side is a free tyvar bindable to the other (e.g.
  -- @TyOr a a ~ TyVar a@): 'unifyRows' flattens and dedupes both sides
  -- first. Non-'TyOr' types are treated as singleton rows.
  (TyOr {}, _) -> unifyRows t1 t2
  (_, TyOr {}) -> unifyRows t1 t2
  (TyVar _ v, _) -> bindVar v t2
  (_, TyVar _ v) -> bindVar v t1
  (TyCon _ c1, TyCon _ c2)
    | c1 == c2 -> Right mempty
    | otherwise -> Left (CannotUnify t1 t2)
  (TyApp _ f1 x1, TyApp _ f2 x2) -> do
    s1 <- unify f1 f2
    s2 <- unify (applySubst s1 x1) (applySubst s1 x2)
    Right (s2 <> s1)
  (TyArrow _ a1 b1, TyArrow _ a2 b2) -> do
    s1 <- unify a1 a2
    s2 <- unify (applySubst s1 b1) (applySubst s1 b2)
    Right (s2 <> s1)
  _ -> Left (CannotUnify t1 t2)

-- | Flatten a (possibly deeply-nested) 'TyOr' into a deduplicated list
--   of alternatives. Non-'TyOr' types map to a singleton list. The
--   deduplication step is what gives 'unifyRows' its /idempotency/
--   property (@A | A ~ A@); the recursive flattening gives
--   /associativity/ (@(A | B) | C ~ A | (B | C)@); commutativity is
--   handled by 'unifyRows' itself when it tries to match each left
--   element against any right element.
flattenRow :: Type' -> [Type']
flattenRow = ordNub . go
  where
    go = \case
      TyOr _ a b -> go a <> go b
      t -> [t]

-- | One-way row subsumption: does a value of @actual@ fit where
--   @expected@ is required?
--
--   Like 'unify' but asymmetric — extra labels on the expected side
--   are accepted ('actual' is a sub-row), extra labels on the actual
--   side are rejected. The recursion through 'TyApp' assumes
--   covariance in every type-application position; 'TyArrow'
--   contravariance is encoded explicitly. Free 'TyVar's on either
--   side fit anything: the bidirectional checker calls this where the
--   actual type carries freshened tyvars from constructor instantiation
--   that the surrounding context's expected type pins down.
--
--   Used by 'Awsum.Typing.checkExpr' as the boundary acceptance
--   relation, replacing structural equality once 'TyOr' enters the
--   picture: expressions like @Left ErrA@ synthesise to
--   @Either ErrA r$@ but must flow into @Either (ErrA | ErrB) Int32@
--   without explicit injection — implicit injection extended through
--   nominal heads.
rowSubsume :: Type' -> Type' -> Bool
rowSubsume expected actual = case (expected, actual) of
  -- A free tyvar on either side accepts anything: the checker will
  -- have already pinned constraints in the synthesis path; here we
  -- just need a yes/no acceptance.
  (TyVar _ _, _) -> True
  (_, TyVar _ _) -> True
  -- Row on the expected side: every label of @actual@ must be
  -- subsumable by /some/ label of @expected@. Plain set membership
  -- (@elem@) is too strict — the test for membership is itself
  -- subsumption, so e.g. @Maybe Bool@ on the actual side is accepted
  -- by an expected row containing @Maybe (Bool | Unit)@: outer
  -- @Maybe ~ Maybe@ matches as TyApp, inner @Bool ⊆ (Bool | Unit)@
  -- via the recursive call into 'rowSubsume'.
  (TyOr {}, _) -> all (\al -> any (`rowSubsume` al) exLabels) (flattenRow actual)
    where
      exLabels = flattenRow expected
  -- Row on actual but not expected: a multi-label value cannot flow
  -- into a single-label position.
  (_, TyOr {}) -> False
  (TyApp _ f1 x1, TyApp _ f2 x2) -> rowSubsume f1 f2 && rowSubsume x1 x2
  (TyArrow _ a1 b1, TyArrow _ a2 b2) -> rowSubsume a2 a1 && rowSubsume b1 b2
  (TyCon _ c1, TyCon _ c2) -> c1 == c2
  _ -> False

-- | Set-semantic unification for structural sums. After flattening and
--   deduplication, the two sides must have equal-sized label sets and
--   each left-hand label must unify with /some/ right-hand label.
--
--   Matching is done by simple greedy search: each left label is paired
--   with the first right label it can unify with. Greedy can fail when
--   a non-deterministic choice would have worked — e.g. @(a | Int32) ~
--   (Int32 | String)@ should bind @a ↦ String@ but greedy commits
--   @a ↦ Int32@ first and then can't match the leftover @Int32@ against
--   @String@. For closed rows (no tail variable) the typical case is
--   mostly-concrete labels where greedy is unambiguous; full
--   backtracking is deferred to row polymorphism.
--
--   The 'CannotUnify' error reports the original (unflattened) types so
--   the user sees the surface form they wrote, not an internal
--   normalised list.
unifyRows :: Type' -> Type' -> Either UnifyError Subst
unifyRows lhs rhs =
  let ls = flattenRow lhs
      rs = flattenRow rhs
      mismatch = Left (CannotUnify lhs rhs)
   in if length ls /= length rs
        then mismatch
        else goMatch mismatch ls rs mempty

-- | Helper: pair every element of the first list with /some/ element of
--   the second, accumulating substitutions. Greedy from the left.
goMatch ::
  Either UnifyError Subst ->
  [Type'] ->
  [Type'] ->
  Subst ->
  Either UnifyError Subst
goMatch _ [] [] s = Right s
goMatch mismatch (l : ls') rs s = tryRs rs []
  where
    tryRs [] _ = mismatch
    tryRs (r : rs'') prev =
      case unify (applySubst s l) (applySubst s r) of
        Right s' -> goMatch mismatch ls' (reverse prev <> rs'') (s' <> s)
        Left _ -> tryRs rs'' (r : prev)
goMatch mismatch _ _ _ = mismatch

-- | Compute the row-tag for a label type: a 32-bit FNV-1a hash of the
--   label's canonical text representation. The same label always
--   produces the same tag regardless of source-position spans, so a
--   value injected at one site (`CRow tag v`) and a pattern matching
--   that label at another site (`CRowCase _ [(tag, …)]`) line up
--   bit-for-bit at runtime.
--
--   Spans are ignored by the canonical renderer, so the pre-existing
--   convention that 'Type'' equality ignores spans is preserved at the
--   hash level too. Inside a label, nested 'TyOr' alternatives are
--   sorted before hashing so set-equal rows produce equal tags
--   (relevant to labels like @(A | B) -> C@ where the inner @|@
--   could appear in either order in the source).
--
--   Used at lowering time only; codegens consume the resulting 'Word32'
--   without knowing what hash function produced it.
rowTag :: Type' -> Word32
rowTag = fnv1a32 . canonicalLabel

-- | Canonical text for a 'Type'' with TyOr alternatives sorted, used
--   only as input to 'fnv1a32' so the exact format doesn't have to be
--   pretty — just deterministic.
canonicalLabel :: Type' -> Text
canonicalLabel = \case
  TyVar _ n -> n
  TyCon _ n -> n
  TyApp _ f x -> "(" <> canonicalLabel f <> " " <> canonicalLabel x <> ")"
  TyArrow _ a b -> "(" <> canonicalLabel a <> "->" <> canonicalLabel b <> ")"
  ty@TyOr {} ->
    let alts = sort (map canonicalLabel (flattenRow ty))
     in "(" <> T.intercalate "|" alts <> ")"

-- | FNV-1a 32-bit on the UTF-8 byte sequence of a 'Text'. Deterministic
--   and stable across GHC versions (unlike 'Data.Hashable.hash').
fnv1a32 :: Text -> Word32
fnv1a32 = T.foldl' step fnvOffset
  where
    fnvOffset, fnvPrime :: Word32
    fnvOffset = 0x811c9dc5
    fnvPrime = 0x01000193
    step h c = (h `xor` fromIntegral (fromEnum c)) * fnvPrime

-- | Bind a tyvar to a type, with two early-outs:
--
--   * @v ↦ v@ is a no-op (returns the identity substitution): we never
--     need a binding that maps a variable to itself, and including it
--     would make composed substitutions accumulate trivial entries.
--
--   * @v@ occurring inside @t@ is the infinite-type case — return
--     'OccursCheckFailed' rather than producing a substitution that
--     would cause non-terminating 'applySubst' calls down the line.
bindVar :: Name -> Type' -> Either UnifyError Subst
bindVar v (TyVar _ v') | v' == v = Right mempty
bindVar v t
  | occursIn v t = Left (OccursCheckFailed v t)
  | otherwise = Right (singletonSubst v t)

-- | Collect every type-variable name occurring in a type.
--
--   Used by 'generalize' to compute the candidate set of quantifiable
--   variables, and as a small utility shared with the type checker.
collectTypeVars :: Type' -> S.Set Name
collectTypeVars = \case
  TyVar _ n -> S.singleton n
  TyCon _ _ -> S.empty
  TyApp _ f x -> collectTypeVars f <> collectTypeVars x
  TyArrow _ a b -> collectTypeVars a <> collectTypeVars b
  TyOr _ a b -> collectTypeVars a <> collectTypeVars b

-- | A polymorphic type scheme: a body type quantified over a list of
--   tyvar names. 'generalize' produces a scheme; 'instantiate' consumes
--   one to give a concrete 'Type'' with fresh tyvars at every use site.
--
--   The bound list is canonical (sorted) so two equal schemes have
--   structurally equal representations regardless of how they were built.
data Scheme = Forall [Name] Type'
  deriving stock (Show, Eq)

-- | Quantify every tyvar in @t@ that is /not/ already free in the
--   surrounding environment. The 'Set' parameter is the union of the
--   environment's free tyvars — the caller computes it by walking the
--   typing environment, so 'generalize' itself stays environment-agnostic
--   and easy to unit-test.
--
--   The bound list comes out of 'S.toList' (alphabetical), giving
--   deterministic schemes regardless of insertion order in the input
--   type.
generalize :: S.Set Name -> Type' -> Scheme
generalize envVars t =
  let bound = S.toList (collectTypeVars t `S.difference` envVars)
   in Forall bound t

-- | Use a 'Scheme' at a use site: replace every bound tyvar with a fresh
--   one drawn from the 'TC' counter, so distinct uses of the same scheme
--   get distinct tyvars and can be constrained independently. Returns
--   the body type with the substitution applied.
--
--   The fresh tyvars carry 'noSpan' — at this stage we don't track
--   provenance for instantiated tyvars; if a unifier-driven mismatch
--   later surfaces them, the surrounding diagnostic span still pins
--   the user's source location.
instantiate :: Scheme -> TC e Type'
instantiate (Forall vars t) = do
  freshNames <- traverse (const fresh) vars
  let subst =
        foldMap
          (\(v, fn) -> singletonSubst v (TyVar noSpan fn))
          (zip vars freshNames)
  pure (applySubst subst t)

-- | Position-based instantiate: rename every tyvar in @t@ by appending
--   the given suffix. The non-monadic counterpart of 'instantiate' —
--   useful where a 'TC' counter isn't threaded but a fresh polymorphic
--   instance is still needed (e.g. per-use-site freshening of a
--   constructor's type, where the suffix encodes the source position).
--
--   The result has the same /shape/ as the input but with disambiguated
--   tyvar names: @'a' -> Maybe 'a'@ becomes @'a$X' -> Maybe 'a$X'@. Two
--   call sites with different suffixes produce non-overlapping name sets.
freshenType :: Text -> Type' -> Type'
freshenType suffix ty = applySubst subst ty
  where
    subst =
      foldMap
        (\v -> singletonSubst v (TyVar noSpan (v <> suffix)))
        (collectTypeVars ty)

-- | Type-checker monad: 'StateT' over an 'Either'-based error channel.
--   Polymorphic in the error type so call sites can specialise to
--   their own diagnostic — typically @TC TypeError@ in 'Awsum.Typing'.
--   The 'Int' state is a fresh-tyvar counter consumed by 'fresh'.
type TC e a = StateT Int (Either e) a

-- | Run a 'TC' computation from a counter of 0, discarding the final
--   counter and surfacing only success or error.
runTC :: TC e a -> Either e a
runTC m = fst <$> runStateT m 0

-- | Generate a fresh tyvar name: @t0@, @t1@, @t2@, …
--
--   No leading underscore — that prefix is reserved in Awsum for
--   intentionally-unused user bindings, and reusing it for
--   compiler-generated names would conflate two unrelated meanings.
fresh :: TC e Name
fresh = do
  n <- get
  put (n + 1)
  pure ("t" <> show n)
