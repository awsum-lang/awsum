-- | Cell reuse à la Lean 4.
--
-- Recognises the canonical shape produced by 'Awsum.Lifetime.insertDrops'
-- (specifically by its 'addContinueDrops' step) under a linear case-scrutinee:
--
-- @
--   CCase (CVar n) [..., (tag_in, [v1..vk], CDrop n inner), ...]
-- @
--
-- where @inner@ contains a @CCon t fields@ with
-- @length fields == k@ (same arity as the matched constructor's
-- pattern binders). Such a 'CCon' is rewritten to
-- @CReuse n t fields@, and the outer @CDrop n@ is stripped: the
-- cell is not freed and re-allocated, it is mutated in place.
--
-- The pass is local — it does not propagate reuse opportunities
-- across function boundaries, and it does not perform alias
-- analysis. The only correctness predicate it relies on is the
-- @CDrop n inner@ wrap: 'addContinueDrops' only emits that drop
-- when @n@ is a function parameter that is not transferred via a
-- live use in @inner@, which is exactly the linear-use
-- precondition cell reuse needs.
--
-- Per-arm we rewrite at most /one/ @CCon@. Two independent
-- allocations of the same arity in the same arm would each
-- benefit from reusing the cell, but there is only one cell to
-- give — the second allocation stays as a normal 'CCon' (=
-- 'alloc'). 'rewriteFirstCCon' searches outermost-first and
-- descends into 'CCase' / 'CRowCase' arms in parallel (any single
-- arm that rewrites makes the whole sub-expression reused —
-- non-rewritten arms keep their original 'CCon').
module Awsum.Reuse (insertReuse) where

import Awsum.Core
import Awsum.Syntax (Name)
import Relude

-- | Run reuse-analysis over every declaration in the program.
insertReuse :: Int -> CoreProgram -> CoreProgram
insertReuse mintedFloor (CoreProgram ds) = CoreProgram (map (reuseDecl mintedFloor) ds)

reuseDecl :: Int -> CDecl -> CDecl
reuseDecl mintedFloor = \case
  CFunDef n ps body -> CFunDef n ps (reuseExpr mintedFloor body)
  CValDef n body -> CValDef n (reuseExpr mintedFloor body)

-- | Walk an expression, attempting the reuse rewrite at every
-- 'CCase' whose scrut is a 'CVar'. Recurses through every
-- constructor of 'CExpr' so opportunities nested inside arms /
-- loops / drops are also picked up.
reuseExpr :: Int -> CExpr -> CExpr
reuseExpr mintedFloor = goE
  where
    goE = \case
      CCase (CVar n) alts -> CCase (CVar n) (map (reuseArm mintedFloor n) alts)
      CCase scrut alts ->
        CCase (goE scrut) [(t, vs, goE b) | (t, vs, b) <- alts]
      CRowCase scrut alts ->
        CRowCase (goE scrut) [(t, v, goE b) | (t, v, b) <- alts]
      CCall f xs -> CCall (goE f) (map goE xs)
      CCon t fs -> CCon t (map goE fs)
      CRow t v -> CRow t (goE v)
      CLoop b -> CLoop (goE b)
      CContinue xs -> CContinue (map goE xs)
      CDrop m b -> CDrop m (goE b)
      CReuse m n t fs -> CReuse m n t (map goE fs)
      CLet x rhs body -> CLet x (goE rhs) (goE body)
      -- Self-contained patterns inside the join body and the inner expression
      -- are picked up independently; the scrut-drop search
      -- ('findAndReuseScrutDrop') stops at the node, so no reuse pattern ever
      -- spans the join boundary — the same separation the expansion adapter
      -- enforces by making the body a function.
      CJoin j ps body inner -> CJoin j ps (goE body) (goE inner)
      CJump j args -> CJump j (map goE args)
      e@(CProj _ _) -> e
      e@(CVar _) -> e
      e@(CString _) -> e
      e@(CIntLit _ _) -> e
      e@(CBuiltIn _) -> e

-- | Apply the reuse rewrite to one arm. Walks the arm body looking
-- for a 'CDrop scrut' wrap — possibly buried under arm-binder
-- 'CDrop's and inside nested 'CCase' / 'CRowCase' arms — and in any
-- such path strips the scrut drop and rewrites the first matching
-- 'CCon' to 'CReuse'. Distribution into nested 'CCase' arms is
-- independent: arms that have the pattern get rewritten, arms that
-- don't keep their original body (their scrut keeps flowing
-- normally — value-tail param dec or downstream 'CDrop' will free
-- it). Returns the arm unchanged if no path rewrote.
--
-- Recurses into the arm body with 'reuseExpr' first so nested
-- reuse opportunities (a 'case' inside a 'case' inside a 'case' …)
-- are picked up regardless of whether the outer rewrite fires.
--
-- Why the descent shape is safe. 'CDrop scrut' marks the last use
-- of the scrut cell in that path; rewriting an enclosed 'CCon' of
-- matching arity to 'CReuse' redirects the soon-to-be-freed cell
-- into the next allocation. Paths that don't drop the scrut
-- continue to own it. 'rewriteFirstCCon' stops at
-- 'CCall' / 'CVar' / 'CRow' / 'CLoop' / 'CReuse', so a value-tail
-- 'CCon t [..]' (returned as a non-CContinue leaf) is never
-- rewritten unless preceded by 'CDrop scrut' in that same path.
-- The matched arm's tag is the dying cell's tag, and it decides the
-- 'ReuseMode': a tag at or above the minted floor names an Scc pack or a
-- Cps continuation cell — loop-private by construction, 'ReuseUnique';
-- anything below is user-visible data the caller may retain,
-- 'ReuseGuarded'.
reuseArm :: Int -> Name -> (Int, [Name], CExpr) -> (Int, [Name], CExpr)
reuseArm mintedFloor scrutName (tag, vs, body) =
  let body' = reuseExpr mintedFloor body
      k = length vs
      mode = if tag >= mintedFloor then ReuseUnique else ReuseGuarded
   in case findAndReuseScrutDrop mode scrutName k body' of
        Just rewritten -> (tag, vs, rewritten)
        Nothing -> (tag, vs, body')

-- | Walk @body@ looking for paths containing 'CDrop scrut'. In each
-- such path, strip the scrut 'CDrop' and attempt to rewrite the
-- first 'CCon' of arity @k@ to 'CReuse'. Distributes into 'CCase' /
-- 'CRowCase' arms — each arm independently rewrites if its path has
-- the pattern; arms without the pattern keep their original body.
-- Returns 'Just' iff at least one path rewrote, 'Nothing' otherwise.
findAndReuseScrutDrop :: ReuseMode -> Name -> Int -> CExpr -> Maybe CExpr
findAndReuseScrutDrop mode scrut k = go
  where
    go :: CExpr -> Maybe CExpr
    go = \case
      -- Found scrut drop in this path. Strip it; the inner is the
      -- post-drop expression that 'rewriteFirstCCon' searches for a
      -- matching 'CCon' to redirect.
      CDrop n inner
        | n == scrut ->
            rewriteFirstCCon mode scrut k inner
      -- Other 'CDrop' (arm-binder, transient param). Preserve and
      -- recurse — the scrut drop may be further down.
      CDrop m inner ->
        CDrop m <$> go inner
      -- A 'CLet' (function inlining is the producer) is transparent for the
      -- search when its right-hand side does not touch the scrut: the body
      -- may hold the scrut drop. A right-hand side reading the scrut keeps
      -- the arm un-rewritten — maximally conservative, no read can end up
      -- relative to an in-place store it didn't expect.
      CLet x rhs b
        | not (binderUsedIn scrut rhs) -> CLet x rhs <$> go b
      -- Distribute into 'CCase' / 'CRowCase' arms; each arm decides
      -- independently whether it has a scrut drop to rewrite.
      CCase s alts -> CCase s <$> distributeAlts alts
      CRowCase s alts -> CRowCase s <$> distributeRowAlts alts
      -- Stop at every other constructor. 'CContinue' / 'CCon' /
      -- 'CCall' as the leaf are not reuse anchors on their own —
      -- they only matter once a 'CDrop scrut' has been crossed,
      -- after which 'rewriteFirstCCon' takes over.
      _ -> Nothing

    distributeAlts :: [(Int, [Name], CExpr)] -> Maybe [(Int, [Name], CExpr)]
    distributeAlts alts =
      let results = [(t, vs', go b, b) | (t, vs', b) <- alts]
          anyHit = any (\(_, _, mr, _) -> isJust mr) results
       in if anyHit
            then Just [(t, vs', fromMaybe b mr) | (t, vs', mr, b) <- results]
            else Nothing

    distributeRowAlts :: [(Word32, Name, CExpr)] -> Maybe [(Word32, Name, CExpr)]
    distributeRowAlts alts =
      let results = [(t, v, go b, b) | (t, v, b) <- alts]
          anyHit = any (\(_, _, mr, _) -> isJust mr) results
       in if anyHit
            then Just [(t, v, fromMaybe b mr) | (t, v, mr, b) <- results]
            else Nothing

-- | Find the first 'CCon' of arity @k@ reachable from @e@ and
-- rewrite it to 'CReuse'. Returns 'Just' the rewritten
-- expression iff a rewrite happened; 'Nothing' if no matching
-- 'CCon' was found anywhere.
--
-- Descends into:
--
--   * 'CContinue' arg list — recurses into args left-to-right,
--     stops after the first that rewrites.
--   * 'CCon' fields of a /non-matching/ constructor — the same
--     left-to-right walk with the same later-element gate. This is
--     where a sunk drop's cell hides: a CPS K-arm rebuilds the next
--     continuation /inside/ the cell its loop reuses
--     (@CCon 33 [l, CCon 31 […]]@ over a dropped 3-field @$k@), so
--     the matching-arity reconstruction is a field of a wider one.
--     The price of the descent: a rewrite whose /enclosing/ cell
--     ends up a plain allocation leaves a 'CReuse' whose target
--     still carries its extract-inc at evaluation time — on LLVM
--     the uniqueness check then routes it to the copy path every
--     run (behaviourally a 'CCon', plus one check); visible in the
--     IR snapshot, bounded, and absent from the CPS shapes that
--     motivate the descent.
--   * 'CCase' / 'CRowCase' arms — tries every arm; the whole
--     case rewrites if /any/ arm rewrites. Non-rewriting arms
--     keep their original body (the 'CCon' in those paths stays
--     a normal allocation).
--   * 'CDrop' — recurses into the wrapped body.
--   * 'CLet' — recurses into the body when the right-hand side
--     does not touch the scrut (the rhs evaluates before the
--     in-place store, but stay maximally conservative).
--
-- Stops at:
--
--   * Any 'CCon' of arity @k@ — rewrite to 'CReuse'.
--   * Any 'CCall' / 'CVar' / 'CString' / 'CIntLit' / 'CBuiltIn'
--     / 'CRow' / 'CLoop' / 'CReuse' — no rewrite (no further
--     descent; 'CLoop' is conservatively skipped because it
--     would jump back to a continue site that may not preserve
--     the reused-cell discipline).
--
-- Scrut-use gate ('binderUsedIn'): an in-place store overwrites the
-- scrut's slots (and on the reference-counted backends decs the old
-- values) /while/ the replacement fields evaluate, so any read of the
-- scrut at or after the store — a @CProj scrut@ reading a slot, a plain
-- @CVar scrut@ re-staging the cell (a 'CContinue' argument passing the
-- matched cell onward; the drop at the continue covers it because the
-- argument's inc fires first) — observes the mutation instead of the
-- value the source program read. Function inlining can move projections
-- into an arm (a callee projecting its parameter, the argument being this
-- scrut), and user code can re-stage the scrutinee it matched on, so any
-- candidate whose fields mention the scrut — or that is followed in
-- 'CContinue' argument order by an expression mentioning it — is skipped:
-- the allocation stays a plain 'CCon' rather than risking the
-- read-after-store.
rewriteFirstCCon :: ReuseMode -> Name -> Int -> CExpr -> Maybe CExpr
rewriteFirstCCon mode n k = go
  where
    go :: CExpr -> Maybe CExpr
    go = \case
      -- Fields before the node (innermost-first): nested scrutinees'
      -- passes run before their enclosing case's ('reuseArm' recurses
      -- first), so an inner cell must pair with the inner reconstruction
      -- and leave the enclosing one to the enclosing scrut — with equal
      -- arities (a 2-field pack carrying a 2-field list cell) the
      -- outermost-first order would let the inner pass steal the pack.
      CCon t fs ->
        (CCon t <$> goList fs)
          <|> ( if length fs == k && not (any (binderUsedIn n) fs)
                  then Just (CReuse mode n t fs)
                  else Nothing
              )
      CContinue xs -> CContinue <$> goList xs
      CCase scrut alts ->
        case goAlts alts of
          Just alts' -> Just (CCase scrut alts')
          Nothing -> Nothing
      CRowCase scrut alts ->
        case goRowAlts alts of
          Just alts' -> Just (CRowCase scrut alts')
          Nothing -> Nothing
      CDrop m b -> CDrop m <$> go b
      CLet x rhs b
        | not (binderUsedIn n rhs) -> CLet x rhs <$> go b
      _ -> Nothing

    -- Rewrite the first list element that contains a matching CCon —
    -- provided no later element mentions the scrut (later args evaluate
    -- after the in-place store; see the scrut-use gate above). Elements
    -- before the rewritten one evaluate before the store and may read
    -- freely.
    goList :: [CExpr] -> Maybe [CExpr]
    goList = \case
      [] -> Nothing
      x : xs -> case go x of
        Just x'
          | not (any (binderUsedIn n) xs) -> Just (x' : xs)
        _ -> (x :) <$> goList xs

    -- Rewrite arms that have a matching CCon; a sibling arm that does
    -- NOT rewrite re-acquires the scrut 'CDrop' ('fromMaybe (CDrop n b)').
    -- The caller ('findAndReuseScrutDrop') already stripped the single
    -- 'CDrop scrut' that wrapped this whole subtree, on the premise that an
    -- enclosed 'CCon' reuses the cell instead of freeing it — but that
    -- premise is per-path: a 'case' under the stripped drop splits into
    -- mutually exclusive arms, and an arm with no matching 'CCon' still has
    -- to free the scrut. Re-wrapping its body in 'CDrop n' restores exactly
    -- the drop the strip removed, giving it the same shape an all-non-reuse
    -- arm already carries; the reusing arm keeps the drop absorbed into its
    -- 'CReuse'. Omitting this leaks the scrut cell on every non-reuse path
    -- (e.g. the @Right@ success arm of an 'Either'-returning non-tail
    -- recursion's '$apply', whose CPS continuation cell is only reused on the
    -- @Left@ arm). The whole list "succeeds" iff at least one arm rewrote.
    goAlts :: [(Int, [Name], CExpr)] -> Maybe [(Int, [Name], CExpr)]
    goAlts alts =
      let results = [(t, vs, go b, b) | (t, vs, b) <- alts]
          anyChanged = any (\(_, _, mr, _) -> isJust mr) results
       in if anyChanged
            then Just [(t, vs, fromMaybe (CDrop n b) mb) | (t, vs, mb, b) <- results]
            else Nothing

    goRowAlts :: [(Word32, Name, CExpr)] -> Maybe [(Word32, Name, CExpr)]
    goRowAlts alts =
      let results = [(t, v, go b, b) | (t, v, b) <- alts]
          anyChanged = any (\(_, _, mr, _) -> isJust mr) results
       in if anyChanged
            then Just [(t, v, fromMaybe (CDrop n b) mb) | (t, v, mb, b) <- results]
            else Nothing
