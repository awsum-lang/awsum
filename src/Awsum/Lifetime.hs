-- | Two complementary services over Core IR.
--
--   /Linearity analysis/ — 'analyzeProgram' counts how many times each
--   locally-introduced binder (function parameter, 'CCase' pattern-binder,
--   'CRowCase' arm-binder) is referenced inside its scope. Read-only;
--   consumed by 'awsum-stats' for cross-program coverage reports.
--
--   /Drop insertion/ — 'insertDrops' annotates the Core IR with 'CDrop'
--   nodes that pair with the codegen's inc-on-store discipline to give
--   every heap cell a balanced inc/dec history.
--
--     @CDrop k n body@   means   "evaluate @body@; after @body@'s
--                                 value is produced, dec @n@'s
--                                 refcount (cascading-free on 0)".
--
--   This is the linear "let-end" / Lean 4 / Koka semantics: the
--   reclaim point is /after/ the wrapped sub-expression finishes
--   producing its value, so any read /through/ @n@'s pointer that
--   the body or its inner calls performs has already happened by the
--   time the dec fires.
--
--   Two classes of 'CDrop' are emitted here:
--
--   1. /Param dec at every @CContinue@/ — at every loop step each
--      parameter is dec'd before the next iteration's stores
--      overwrite its slot. No transferred-skip — under pure RC
--      every caller-side @inc@ on @CCall@/@CCon@/@CContinue@ args
--      makes the dec mandatory: skipping it leaks the caller's
--      binding forever.
--
--   2. /Arm-binder dec at every @CCase@/@CRowCase@ arm/ — each
--      pattern-binder is wrapped in 'CDrop' /around/ the arm body,
--      paired with codegen's inc-on-case-extract that keeps the
--      matched cell's slots from holding stale references after
--      the dec/cascade fires.
--
--   The third source of decs — value-tail decs for every parameter
--   that survives to a non-@CContinue@ terminal — is /not/ emitted
--   as 'CDrop' here. Outer-wrapping the whole body in
--   @CDrop k p body@ for each param would pollute 'outerDropped'
--   and silently suppress the inner @CContinue@ param drops.
--   Codegen handles value-tail param decs directly, with an
--   explicit move-semantics carve-out for the case where the
--   result expression is a @CVar p@ matching a param/binder (so
--   the function transfers ownership to the caller instead of
--   freeing its own return value).
--
--   The 'CDropKind' attached to every emitted 'CDrop' is set
--   conservatively to 'DropFreeUnchecked' at this layer; backends
--   read the cell's runtime header at dec time to short-circuit
--   on literals (flag==0) and to drive cascading via @shape@.
module Awsum.Lifetime
  ( BindingUsage (..),
    BindingKind (..),
    LifetimeEntry (..),
    DeclLifetime (..),
    analyzeProgram,
    renderLifetime,
    insertDrops,
    freeVars,
    elidableArmBinders,
    scrutReuseEligible,
    soleScrutineeUse,
  )
where

import Awsum.Core
import Awsum.Syntax (Name)
import Data.Set qualified as Set
import Data.Text qualified as T
import Relude

-- | How many times a binder is referenced inside its scope.
newtype BindingUsage = BindingUsage {buCount :: Int}
  deriving stock (Show, Eq)

-- | Where a binder came from. Kept separate from 'BindingUsage' so
--   future fields on either type don't conflate concerns.
data BindingKind
  = Param
  | CasePattern
  | RowCaseBinder
  | LetBinder
  | JoinParam
  deriving stock (Show, Eq)

-- | One binder + its kind + its use count, ordered as the binder
--   appears during a left-to-right walk of the declaration.
data LifetimeEntry = LifetimeEntry
  { leBinder :: !Name,
    leKind :: !BindingKind,
    leUsage :: !BindingUsage
  }
  deriving stock (Show, Eq)

-- | Per-declaration usage report. 'CFunDef's always show up;
--   'CValDef's only show up if their body actually introduces
--   binders (i.e. contains a 'CCase' / 'CRowCase').
data DeclLifetime = DeclLifetime
  { dlName :: !Name,
    dlEntries :: ![LifetimeEntry]
  }
  deriving stock (Show, Eq)

-- ════════════════════════════════════════════════════════════════════════════
-- Linearity analysis (read-only)
-- ════════════════════════════════════════════════════════════════════════════

-- | Walk every top-level declaration in declaration order. Skip
--   'CValDef's whose body contains no binders so the report only
--   carries information that is interesting for linearity statistics.
analyzeProgram :: CoreProgram -> [DeclLifetime]
analyzeProgram (CoreProgram ds) = mapMaybe analyzeDecl ds

analyzeDecl :: CDecl -> Maybe DeclLifetime
analyzeDecl = \case
  CFunDef n params body ->
    let paramEntries = [LifetimeEntry p Param (BindingUsage (countUses p body)) | p <- params]
        innerEntries = collectInnerBinders body
     in Just (DeclLifetime n (paramEntries <> innerEntries))
  CValDef n body ->
    case collectInnerBinders body of
      [] -> Nothing
      es -> Just (DeclLifetime n es)

-- | Pattern-binders introduced anywhere inside an expression.
collectInnerBinders :: CExpr -> [LifetimeEntry]
collectInnerBinders = go
  where
    go = \case
      CCase scrut alts ->
        go scrut <> concatMap goAlt alts
      CRowCase scrut alts ->
        go scrut <> concatMap goRowAlt alts
      CCall f xs -> go f <> concatMap go xs
      CCon _ fs -> concatMap go fs
      CRow _ v -> go v
      CLoop b -> go b
      CContinue xs -> concatMap go xs
      CDrop _ _ b -> go b
      CReuse _ _ _ fs -> concatMap go fs
      CLet x rhs body ->
        go rhs <> (LifetimeEntry x LetBinder (BindingUsage (countUses x body)) : go body)
      CJoin _ ps body inner ->
        [LifetimeEntry p JoinParam (BindingUsage (countUses p body)) | p <- ps]
          <> go body
          <> go inner
      CJump _ args -> concatMap go args
      CProj _ _ -> []
      CVar _ -> []
      CString _ -> []
      CIntLit _ _ -> []
      CBuiltIn _ -> []

    goAlt (_, names, body) =
      [LifetimeEntry n CasePattern (BindingUsage (countUses n body)) | n <- names]
        <> go body

    goRowAlt (_, name, body) =
      LifetimeEntry name RowCaseBinder (BindingUsage (countUses name body))
        : go body

-- | Count occurrences of @CVar n@ inside @e@ that aren't shadowed by
--   a tighter 'CCase'/'CRowCase' arm-binder of the same name.
countUses :: Name -> CExpr -> Int
countUses target = go
  where
    go = \case
      CVar n
        | n == target -> 1
        | otherwise -> 0
      CCall f xs -> go f + sum (fmap go xs)
      CCon _ fs -> sum (fmap go fs)
      CCase s alts ->
        go s
          + sum
            [ if target `elem` ns then 0 else go b
            | (_, ns, b) <- alts
            ]
      CRowCase s alts ->
        go s
          + sum
            [ if target == m then 0 else go b
            | (_, m, b) <- alts
            ]
      CRow _ v -> go v
      CLoop b -> go b
      CContinue xs -> sum (fmap go xs)
      CDrop _ n b
        | n == target -> 0
        | otherwise -> go b
      CReuse _ n _ fs ->
        -- 'CReuse n tag fs' uses the binder @n@ (the cell being
        -- reused) plus every field expression. The 'Int' tag is a
        -- constant, not a name.
        (if n == target then 1 else 0) + sum (fmap go fs)
      CLet x rhs body -> go rhs + (if x == target then 0 else go body)
      CProj n _ -> if n == target then 1 else 0
      CJoin _ ps body inner -> (if target `elem` ps then 0 else go body) + go inner
      CJump _ args -> sum (fmap go args)
      CString _ -> 0
      CIntLit _ _ -> 0
      CBuiltIn _ -> 0

-- ════════════════════════════════════════════════════════════════════════════
-- Snapshot rendering
-- ════════════════════════════════════════════════════════════════════════════

renderLifetime :: [DeclLifetime] -> Text
renderLifetime decls =
  T.intercalate "\n" (fmap renderDecl decls) <> "\n"

renderDecl :: DeclLifetime -> Text
renderDecl (DeclLifetime n es) =
  n <> ":\n" <> T.intercalate "\n" (fmap renderEntry es) <> "\n"

renderEntry :: LifetimeEntry -> Text
renderEntry (LifetimeEntry n k u) =
  "  " <> padRight 16 (renderKind k) <> padRight 32 n <> "count=" <> show u.buCount

renderKind :: BindingKind -> Text
renderKind = \case
  Param -> "param"
  CasePattern -> "case-pattern"
  RowCaseBinder -> "row-case"
  LetBinder -> "let"
  JoinParam -> "join-param"

padRight :: Int -> Text -> Text
padRight n t = t <> T.replicate (max 0 (n - T.length t)) " "

-- ════════════════════════════════════════════════════════════════════════════
-- Drop insertion ("drop after body" semantics + ownership-aware LCA placement)
-- ════════════════════════════════════════════════════════════════════════════

-- | Free variables of a Core expression. 'CCase' / 'CRowCase' arm
--   binders subtract from the body's free vars; 'CDrop' subtracts
--   the dropped binder (after the drop, downstream code does not
--   refer to it).
freeVars :: CExpr -> Set Name
freeVars = \case
  CVar n -> Set.singleton n
  CString _ -> mempty
  CIntLit _ _ -> mempty
  CBuiltIn _ -> mempty
  CCall f xs -> freeVars f <> foldMap freeVars xs
  CCon _ fs -> foldMap freeVars fs
  CCase s alts ->
    freeVars s
      <> foldMap (\(_, ns, b) -> freeVars b `Set.difference` Set.fromList ns) alts
  CRow _ v -> freeVars v
  CRowCase s alts ->
    freeVars s
      <> foldMap (\(_, n, b) -> Set.delete n (freeVars b)) alts
  CLoop b -> freeVars b
  CContinue xs -> foldMap freeVars xs
  CDrop _ n b -> Set.delete n (freeVars b)
  CReuse _ n _ fs -> Set.insert n (foldMap freeVars fs)
  CLet n rhs body -> freeVars rhs <> Set.delete n (freeVars body)
  CProj n _ -> Set.singleton n
  -- The join name is a label, not a reference; the parameters scope over
  -- the body only.
  CJoin _ ps body inner -> (freeVars body `Set.difference` Set.fromList ps) <> freeVars inner
  CJump _ args -> foldMap freeVars args

defaultKind :: CDropKind
defaultKind = DropFreeUnchecked

-- | Pure-RC drop placement.
--
--   For each 'CFunDef' the pass inserts 'CDrop' nodes that, together
--   with the codegen's inc-on-store / dec-on-scope-end discipline,
--   give every heap-allocated cell a balanced inc/dec history.
--
--   Three classes of 'CDrop' are emitted here:
--
--   1. /Param drops at every @CContinue@/ — at every loop step every
--      parameter is dec'd before the next iteration's stores take
--      its slot. No transferred-skip — under pure RC the caller-side
--      @inc@ on each @CCall@/@CCon@/@CContinue@ arg makes the dec
--      mandatory: skipping it leaks the caller's binding forever.
--
--   2. /Arm-binder drops at every @CCase@/@CRowCase@ arm/ — each
--      pattern-binder is wrapped in 'CDrop' /around/ the arm body
--      so codegen's flatten-to-pending lowering decs each binder
--      before either the value-tail return or the inner @CContinue@.
--      Codegen pairs this with an inc-on-case-extract that keeps
--      the matched cell's slots from holding stale references after
--      the cascade.
--
--   The third class — /value-tail param drops at every non-@CContinue@
--   terminal/ — is /not/ emitted as 'CDrop' here. Outer-wrapping the
--   whole body would pollute 'outerDropped' and silently suppress the
--   inner @CContinue@ param drops. Codegen handles value-tail param
--   decs directly, with an explicit move-semantics carve-out for the
--   case where the result expression is a @CVar p@ matching a param
--   (so the function transfers ownership to the caller instead of
--   freeing its own return value).
insertDrops :: CoreProgram -> CoreProgram
insertDrops (CoreProgram ds) = CoreProgram (map dropDecl ds)

dropDecl :: CDecl -> CDecl
dropDecl = \case
  CFunDef n params body -> CFunDef n params (addContinueDrops params body)
  -- A value definition's own body gets no drops (the managed backends
  -- compute it once into a static slot; the LLVM/WASM getter has its own
  -- codegen-side discipline) — but a join body inside it is ordinary
  -- branch-and-bind code the backends execute inline, and executed code
  -- without its arm-binder drops leaks on the reference-counted backends.
  -- A 'CLet' binder anywhere in the body needs its drop for the same
  -- reason: the right-hand side evaluates per getter call and the
  -- binding owns its value. So the drop-needing scopes inside a
  -- 'CValDef' are the join bodies (treated exactly like function bodies)
  -- and every let binder ('wrapLetBinderDrop').
  CValDef n body -> CValDef n (joinBodyDrops body)

-- | Locate every 'CJoin' inside a value definition's body and give its
--   body the function-body drop treatment ('addContinueDrops' with no
--   parameters — join parameters follow the function-parameter discipline,
--   and a 'CContinue' cannot occur under a join until the fusion gate
--   lifts) — and give every 'CLet' binder its drop ('wrapLetBinderDrop'):
--   a let's right-hand side evaluates per getter call on the
--   reference-counted backends and the binding owns its value, so a
--   value definition whose simplified body holds a let (the inliner is
--   the producer) leaked one cell per reference without it. Case-arm
--   binders outside join bodies keep the value-definition convention: no
--   drops.
joinBodyDrops :: CExpr -> CExpr
joinBodyDrops = go
  where
    go = \case
      CJoin j ps body inner -> CJoin j ps (addContinueDrops [] body) (go inner)
      CJump j args -> CJump j (map go args)
      CCall f xs -> CCall (go f) (map go xs)
      CCon t fs -> CCon t (map go fs)
      CRow t v -> CRow t (go v)
      CCase s alts -> CCase (go s) [(t, vs, go b) | (t, vs, b) <- alts]
      CRowCase s alts -> CRowCase (go s) [(t, v, go b) | (t, v, b) <- alts]
      CLoop b -> CLoop (go b)
      CContinue xs -> CContinue (map go xs)
      CLet x rhs b -> CLet x (go rhs) (wrapLetBinderDrop x (go b))
      CDrop k x b -> CDrop k x (go b)
      CReuse rm x t fs -> CReuse rm x t (map go fs)
      e@(CVar _) -> e
      e@(CProj _ _) -> e
      e@(CString _) -> e
      e@(CIntLit _ _) -> e
      e@(CBuiltIn _) -> e

-- | The drop discipline of a 'CLet' binder, shared by the function-body
--   walk ('addContinueDrops') and the value-definition walk
--   ('joinBodyDrops'): a binder whose sole use is a spine dispatch sinks
--   its drop into that case's arms; everyone else — the /unused/ binder
--   included — gets the scope wrap. Unlike an unused arm binder (never
--   extracted, so no reference exists to dec), an unused let binder's
--   right-hand side always evaluates and the binding owns its value; such
--   a 'CLet' survives Simplify's dead-let rule only when the right-hand
--   side is effectful, and that value still has to be released — the
--   print helper's fresh @Unit@ cell leaked once per executed print on
--   the reference-counted backends when this drop was skipped.
wrapLetBinderDrop :: Name -> CExpr -> CExpr
wrapLetBinderDrop x body
  | soleScrutineeUse x body, Just sunk <- sinkScrutDrop x body = sunk
  | otherwise = CDrop defaultKind x body

addContinueDrops :: [Name] -> CExpr -> CExpr
addContinueDrops params = goExpr Set.empty
  where
    goExpr :: Set Name -> CExpr -> CExpr
    goExpr outerDropped = \case
      CContinue args ->
        let argsRecursed = map (goExpr outerDropped) args
            droppedParams =
              filter (`Set.notMember` outerDropped) params
         in foldr
              (CDrop defaultKind)
              (CContinue argsRecursed)
              droppedParams
      CCase scrut alts ->
        CCase
          (goExpr outerDropped scrut)
          [ (t, ns, wrapBinderDrops ns (goExpr (outerDropped <> Set.fromList ns) b))
          | (t, ns, b) <- alts
          ]
      CRowCase scrut alts ->
        CRowCase
          (goExpr outerDropped scrut)
          [ (t, n, wrapBinderDrops [n] (goExpr (Set.insert n outerDropped) b))
          | (t, n, b) <- alts
          ]
      CCall f xs -> CCall (goExpr outerDropped f) (map (goExpr outerDropped) xs)
      CCon t fs -> CCon t (map (goExpr outerDropped) fs)
      CRow t v -> CRow t (goExpr outerDropped v)
      CLoop b -> CLoop (goExpr outerDropped b)
      CDrop k n b -> CDrop k n (goExpr (Set.insert n outerDropped) b)
      CReuse rm n tag fs -> CReuse rm n tag (map (goExpr outerDropped) fs)
      -- A let binder is dropped like a case-arm binder — 'CDrop' around
      -- the body it scopes over (or sunk into its sole consuming
      -- dispatch), paired with the codegen's inc-on-bind for a borrowed
      -- 'CVar' right-hand side (a fresh source transfers its own @+1@).
      -- The value-tail move carve-out in codegen covers a body that
      -- returns the binder itself; 'wrapLetBinderDrop' covers why the
      -- unused binder is wrapped too.
      CLet x rhs body ->
        CLet x (goExpr outerDropped rhs) (wrapLetBinderDrop x (goExpr (Set.insert x outerDropped) body))
      -- Join parameters follow the /function-parameter/ discipline, not the
      -- arm-binder one: no 'CDrop' wrap here. Every backend's native
      -- lowering emits the value-tail param decs itself, exactly as for
      -- function parameters — a wrap would double the dec. Binders bound
      -- outside the join keep their usual wraps around scopes that contain
      -- the whole 'CJoin', so no drop ever sits between a jump and the body
      -- it transfers to.
      CJoin j ps body inner ->
        CJoin j ps (goExpr (outerDropped <> Set.fromList ps) body) (goExpr outerDropped inner)
      CJump j args -> CJump j (map (goExpr outerDropped) args)
      e@(CProj _ _) -> e
      e@(CVar _) -> e
      e@(CString _) -> e
      e@(CIntLit _ _) -> e
      e@(CBuiltIn _) -> e

    -- Outermost-binder first so codegen's pending stack lists
    -- binders in any order — the dec is uniform. A binder unused in the
    -- arm body gets no drop: 'Awsum.Simplify' inlines a single-use binder
    -- into a 'CProj' of the scrutinee, leaving the binder unused, and
    -- codegen also skips extracting/inc'ing it — so there is no reference
    -- to dec. (Pre-Simplify every listed binder is used, so this is a
    -- no-op there.)
    wrapBinderDrops :: [Name] -> CExpr -> CExpr
    wrapBinderDrops bs body = foldr wrapOne body (filter (`binderUsedIn` body) bs)
      where
        -- A binder consumed by a single dispatch dies with it: sink the
        -- drop into that case's arms ('sinkScrutDrop') so 'Awsum.Reuse'
        -- can match the cell as an in-place reuse target. Everyone else
        -- keeps the scope wrap.
        wrapOne v acc
          | soleScrutineeUse v acc, Just sunk <- sinkScrutDrop v acc = sunk
          | otherwise = CDrop defaultKind v acc

-- | Can 'Awsum.Reuse' ever rewrite a reconstruction inside an arm of a case
--   on this scrutinee into an in-place 'CReuse'? Reuse matches a
--   @CDrop scrut@ /inside/ the arm, and that shape has exactly two
--   producers: 'addContinueDrops' drops params (and nothing else) at each
--   'CContinue', and 'wrapBinderDrops' sinks the drop of a binder whose
--   sole use is the scrutinee of a nominal case into that case's arms
--   ('soleScrutineeUse' \/ 'sinkScrutDrop'). Other binders get their drops
--   around the scope they bind — never inside a nested arm. Row cells are
--   out entirely: 'Awsum.Reuse' descends through 'CRowCase' without
--   matching, so a row scrutinee is never eligible regardless of its name.
--
--   Consumed by 'Awsum.Simplify': the same-arity carve-outs (single-use
--   binder inline, identical-arms collapse) preserve the linear-scrutinee
--   shape Reuse rewrites — only worth paying where a reuse is actually
--   reachable. This function covers the parameter producer; Simplify
--   checks the sink producer with the same exported 'soleScrutineeUse'.
--   Extending where 'insertDrops' places in-arm scrut drops must extend
--   that eligibility in the same change.
scrutReuseEligible :: [Name] -> Name -> Bool
scrutReuseEligible params scrut = scrut `elem` params

-- | Is @v@'s only occurrence in @e@ the scrutinee of a nominal case that
--   /every/ execution of the scope reaches — exactly one 'CVar' use,
--   sitting as @CCase (CVar v)@ on the scope's spine, no 'CProj'\/'CReuse'
--   name-use, and no rebinding of @v@ anywhere in @e@ (lowering's
--   deterministic pattern names repeat across nesting levels; a drop sunk
--   into a shadowing arm would dec the inner cell)? Such a binder dies
--   with the dispatch that consumes it, so its drop can ride into the arms
--   ('sinkScrutDrop'), where 'Awsum.Reuse' looks for it.
--
--   The spine requirement is load-bearing: a consuming case that only some
--   paths reach (under another dispatch's arm, inside a join body) would
--   take the sunk drop with it, and every bypassing path would release the
--   binder nowhere — a per-call leak on the reference-counted backends
--   that no stdout suite can see. Off-spine consumers keep the scope wrap.
--
--   'Awsum.Simplify' consults the same predicate on its own (pre-drop)
--   Core to keep such arms' binders extracted. The two sides may disagree
--   when a simplifier rewrite changes the use count mid-fixpoint — that
--   degrades to a missed reuse, never a miscompile: a premature inline
--   leaves a 'CProj' name-use that makes this predicate false (no sink, no
--   reuse), and Reuse's own scrut-use gate ('binderUsedIn') refuses to rewrite beside a
--   projection of the target.
soleScrutineeUse :: Name -> CExpr -> Bool
soleScrutineeUse v e0 = not (reboundIn e0) && counts True e0 == (1, 0, 1)
  where
    reboundIn = \case
      CCase s alts -> reboundIn s || any (\(_, vs, b) -> v `elem` vs || reboundIn b) alts
      CRowCase s alts -> reboundIn s || any (\(_, w, b) -> w == v || reboundIn b) alts
      CLet x rhs b -> x == v || reboundIn rhs || reboundIn b
      CJoin _ ps body inner -> v `elem` ps || reboundIn body || reboundIn inner
      CCall f xs -> reboundIn f || any reboundIn xs
      CCon _ fs -> any reboundIn fs
      CRow _ x -> reboundIn x
      CLoop b -> reboundIn b
      CContinue xs -> any reboundIn xs
      CDrop _ _ b -> reboundIn b
      CReuse _ _ _ fs -> any reboundIn fs
      CJump _ args -> any reboundIn args
      CVar _ -> False
      CProj _ _ -> False
      CString _ -> False
      CIntLit _ _ -> False
      CBuiltIn _ -> False
    -- (CVar uses, CProj/CReuse name-uses, of which /spine/ scrutinee-position
    -- uses). The spine is the unconditionally-evaluated part of the scope:
    -- case arms and join bodies run only on some paths, so descending into
    -- them clears the flag; scrutinees, let rhs/body, argument lists and a
    -- join's inner expression evaluate whenever their parent does and keep
    -- it.
    counts spine = \case
      CCase (CVar s) alts
        | s == v -> foldl' addC (1, 0 :: Int, if spine then 1 else 0) [counts False b | (_, _, b) <- alts]
      CCase s alts -> foldl' addC (counts spine s) [counts False b | (_, _, b) <- alts]
      CRowCase s alts -> foldl' addC (counts spine s) [counts False b | (_, _, b) <- alts]
      CLet _ rhs b -> addC (counts spine rhs) (counts spine b)
      CJoin _ _ body inner -> addC (counts False body) (counts spine inner)
      CCall f xs -> foldl' addC (counts spine f) (map (counts spine) xs)
      CCon _ fs -> foldl' addC zeroC (map (counts spine) fs)
      CRow _ x -> counts spine x
      CLoop b -> counts False b
      CContinue xs -> foldl' addC zeroC (map (counts spine) xs)
      CDrop _ _ b -> counts spine b
      CReuse _ n _ fs -> foldl' addC (0, if n == v then 1 else 0, 0) (map (counts spine) fs)
      CJump _ args -> foldl' addC zeroC (map (counts spine) args)
      CVar n -> (if n == v then 1 else 0, 0, 0)
      CProj n _ -> (0, if n == v then 1 else 0, 0)
      CString _ -> zeroC
      CIntLit _ _ -> zeroC
      CBuiltIn _ -> zeroC
    zeroC = (0, 0, 0) :: (Int, Int, Int)
    addC (a, b, c) (a', b', c') = (a + a', b + b', c + c')

-- | Rewrite the unique @CCase (CVar v) alts@ inside @e@ so each arm body
--   is wrapped in @CDrop v@ — the drop rides into the dispatch that
--   consumes @v@, which is where 'Awsum.Reuse' searches for it. The dec
--   still fires after the chosen arm's value, the same point the scope
--   wrap expressed (a case's value /is/ its arm's value), so backends
--   lower it unchanged. Precondition: 'soleScrutineeUse'.
sinkScrutDrop :: Name -> CExpr -> Maybe CExpr
sinkScrutDrop v = go
  where
    go = \case
      CCase (CVar s) alts
        | s == v ->
            Just (CCase (CVar s) [(t, vs, CDrop defaultKind v b) | (t, vs, b) <- alts])
      CCase s alts ->
        (CCase <$> go s <*> pure alts)
          <|> (CCase s <$> goAlts alts)
      CRowCase s alts ->
        (CRowCase <$> go s <*> pure alts)
          <|> (CRowCase s <$> goRowAlts alts)
      CLet x rhs b ->
        ((\rhs' -> CLet x rhs' b) <$> go rhs)
          <|> (CLet x rhs <$> go b)
      CJoin j ps body inner ->
        ((\body' -> CJoin j ps body' inner) <$> go body)
          <|> (CJoin j ps body <$> go inner)
      CCall f xs ->
        ((`CCall` xs) <$> go f)
          <|> (CCall f <$> goFirst xs)
      CCon t fs -> CCon t <$> goFirst fs
      CRow t x -> CRow t <$> go x
      CLoop b -> CLoop <$> go b
      CContinue xs -> CContinue <$> goFirst xs
      CDrop k n b -> CDrop k n <$> go b
      CReuse rm n t fs -> CReuse rm n t <$> goFirst fs
      CJump j args -> CJump j <$> goFirst args
      CVar _ -> Nothing
      CProj _ _ -> Nothing
      CString _ -> Nothing
      CIntLit _ _ -> Nothing
      CBuiltIn _ -> Nothing
    goFirst :: [CExpr] -> Maybe [CExpr]
    goFirst = \case
      [] -> Nothing
      x : xs -> ((: xs) <$> go x) <|> ((x :) <$> goFirst xs)
    goAlts :: [(Int, [Name], CExpr)] -> Maybe [(Int, [Name], CExpr)]
    goAlts = \case
      [] -> Nothing
      a@(t, vs, b) : rest ->
        ((\b' -> (t, vs, b') : rest) <$> go b) <|> ((a :) <$> goAlts rest)
    goRowAlts :: [(Word32, Name, CExpr)] -> Maybe [(Word32, Name, CExpr)]
    goRowAlts = \case
      [] -> Nothing
      a@(t, w, b) : rest ->
        ((\b' -> (t, w, b') : rest) <$> go b) <|> ((a :) <$> goRowAlts rest)

-- ════════════════════════════════════════════════════════════════════════════
-- Permutation-aware CReuse elision support
-- ════════════════════════════════════════════════════════════════════════════

-- | Given a 'CCase'/'CRowCase' arm matching a scrut named @scrut@
-- with pattern binders @vs@ and arm body @body@, returns the subset
-- of @vs@ whose only use in @body@ is as a @CVar@ field of a
-- @CReuse scrut _ fs@ expression. Codegen uses this to elide:
--
--   * the inc-on-extract that pairs with the binder's CDrop, and
--   * inside the matching @CReuse@, the dec-old of the binder's
--     old slot together with the inc-new of its new slot.
--
-- Whether the move is self-move (binder stays in the same slot) or
-- permutation-move (binder shifts to a different slot of the same
-- cell), the cell still owns the value through the rewrite, so all
-- four ops are bookkeeping that cancels to a net-zero refcount
-- change. The single-use precondition guarantees the binder doesn't
-- escape to another consumer that would need the inc.
--
-- Note on @CDrop@: this analysis runs on post-'insertDrops' IR
-- where every arm-binder is wrapped in a @CDrop k v armBody@. The
-- walk descends through @CDrop@ unconditionally — the binder is
-- still in scope inside @body@ (the CDrop fires after @body@'s
-- value is produced). This differs from 'countUses' which
-- short-circuits on @CDrop _ n b | n == target -> 0@ for the
-- stat-linearity report's own scoping convention.
elidableArmBinders :: Name -> [Name] -> CExpr -> Set Name
elidableArmBinders scrut vs body =
  Set.fromList [v | v <- vs, isElidable v]
  where
    isElidable v =
      countAllUses v body
        == 1
        && countReuseFieldUses scrut v body
        == 1

-- | Count every @CVar target@ occurrence inside @e@. Unlike
-- 'countUses', this does not short-circuit at @CDrop _ target _@ —
-- the binder is still in scope inside the @CDrop@'s body.
countAllUses :: Name -> CExpr -> Int
countAllUses target = go
  where
    go = \case
      CVar n
        | n == target -> 1
        | otherwise -> 0
      CString _ -> 0
      CIntLit _ _ -> 0
      CBuiltIn _ -> 0
      CCall f xs -> go f + sum (fmap go xs)
      CCon _ fs -> sum (fmap go fs)
      CCase s alts ->
        go s
          + sum
            [ if target `elem` ns then 0 else go b
            | (_, ns, b) <- alts
            ]
      CRowCase s alts ->
        go s
          + sum
            [ if target == m then 0 else go b
            | (_, m, b) <- alts
            ]
      CRow _ v -> go v
      CLoop b -> go b
      CContinue xs -> sum (fmap go xs)
      CDrop _ _ b -> go b
      CReuse _ n _ fs ->
        (if n == target then 1 else 0) + sum (fmap go fs)
      CLet x rhs body -> go rhs + (if x == target then 0 else go body)
      CProj n _ -> if n == target then 1 else 0
      CJoin _ ps body inner -> (if target `elem` ps then 0 else go body) + go inner
      CJump _ args -> sum (fmap go args)

-- | Count @CVar target@ occurrences that appear as immediate fields
-- of a @CReuse scrut _ fs@ expression (i.e. one of @fs@). Recurses
-- through every constructor so a nested CReuse on the same scrut
-- is also counted.
countReuseFieldUses :: Name -> Name -> CExpr -> Int
countReuseFieldUses scrut target = go
  where
    go = \case
      CVar _ -> 0
      CString _ -> 0
      CIntLit _ _ -> 0
      CBuiltIn _ -> 0
      CCall f xs -> go f + sum (fmap go xs)
      CCon _ fs -> sum (fmap go fs)
      CCase s alts ->
        go s
          + sum
            [ if target `elem` ns then 0 else go b
            | (_, ns, b) <- alts
            ]
      CRowCase s alts ->
        go s
          + sum
            [ if target == m then 0 else go b
            | (_, m, b) <- alts
            ]
      CRow _ v -> go v
      CLoop b -> go b
      CContinue xs -> sum (fmap go xs)
      CDrop _ _ b -> go b
      CReuse _ n _ fs
        | n == scrut ->
            sum [1 | CVar w <- fs, w == target] + sum (fmap go fs)
        | otherwise -> sum (fmap go fs)
      CLet x rhs body -> go rhs + (if x == target then 0 else go body)
      CProj _ _ -> 0
      CJoin _ ps body inner -> (if target `elem` ps then 0 else go body) + go inner
      CJump _ args -> sum (fmap go args)
