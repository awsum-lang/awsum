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
      CReuse _ _ fs -> concatMap go fs
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
      CReuse n _ fs ->
        -- 'CReuse n tag fs' uses the binder @n@ (the cell being
        -- reused) plus every field expression. The 'Int' tag is a
        -- constant, not a name.
        (if n == target then 1 else 0) + sum (fmap go fs)
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
  CReuse n _ fs -> Set.insert n (foldMap freeVars fs)

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
  CValDef n body -> CValDef n body

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
      CReuse n tag fs -> CReuse n tag (map (goExpr outerDropped) fs)
      e@(CVar _) -> e
      e@(CString _) -> e
      e@(CIntLit _ _) -> e
      e@(CBuiltIn _) -> e

    -- Outermost-binder first so codegen's pending stack lists
    -- binders in any order — the dec is uniform.
    wrapBinderDrops :: [Name] -> CExpr -> CExpr
    wrapBinderDrops bs body = foldr (CDrop defaultKind) body bs

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
      countAllUses v body == 1
        && countReuseFieldUses scrut v body == 1

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
      CReuse n _ fs ->
        (if n == target then 1 else 0) + sum (fmap go fs)

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
      CReuse n _ fs
        | n == scrut ->
            sum [1 | CVar w <- fs, w == target] + sum (fmap go fs)
        | otherwise -> sum (fmap go fs)
