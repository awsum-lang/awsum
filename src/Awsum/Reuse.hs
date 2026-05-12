-- | Cell reuse à la Lean 4.
--
-- Recognises the canonical shape produced by 'Awsum.Lifetime.insertDrops'
-- (specifically by its 'addContinueDrops' step) under a linear case-scrutinee:
--
-- @
--   CCase (CVar n) [..., (tag_in, [v1..vk], CDrop _ n inner), ...]
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
insertReuse :: CoreProgram -> CoreProgram
insertReuse (CoreProgram ds) = CoreProgram (map reuseDecl ds)

reuseDecl :: CDecl -> CDecl
reuseDecl = \case
  CFunDef n ps body -> CFunDef n ps (reuseExpr body)
  CValDef n body -> CValDef n (reuseExpr body)

-- | Walk an expression, attempting the reuse rewrite at every
-- 'CCase' whose scrut is a 'CVar'. Recurses through every
-- constructor of 'CExpr' so opportunities nested inside arms /
-- loops / drops are also picked up.
reuseExpr :: CExpr -> CExpr
reuseExpr = \case
  CCase (CVar n) alts -> CCase (CVar n) (map (reuseArm n) alts)
  CCase scrut alts ->
    CCase (reuseExpr scrut) [(t, vs, reuseExpr b) | (t, vs, b) <- alts]
  CRowCase scrut alts ->
    CRowCase (reuseExpr scrut) [(t, v, reuseExpr b) | (t, v, b) <- alts]
  CCall f xs -> CCall (reuseExpr f) (map reuseExpr xs)
  CCon t fs -> CCon t (map reuseExpr fs)
  CRow t v -> CRow t (reuseExpr v)
  CLoop b -> CLoop (reuseExpr b)
  CContinue xs -> CContinue (map reuseExpr xs)
  CDrop k m b -> CDrop k m (reuseExpr b)
  CReuse n t fs -> CReuse n t (map reuseExpr fs)
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
reuseArm :: Name -> (Int, [Name], CExpr) -> (Int, [Name], CExpr)
reuseArm scrutName (tag, vs, body) =
  let body' = reuseExpr body
      k = length vs
   in case findAndReuseScrutDrop scrutName k body' of
        Just rewritten -> (tag, vs, rewritten)
        Nothing -> (tag, vs, body')

-- | Walk @body@ looking for paths containing 'CDrop scrut'. In each
-- such path, strip the scrut 'CDrop' and attempt to rewrite the
-- first 'CCon' of arity @k@ to 'CReuse'. Distributes into 'CCase' /
-- 'CRowCase' arms — each arm independently rewrites if its path has
-- the pattern; arms without the pattern keep their original body.
-- Returns 'Just' iff at least one path rewrote, 'Nothing' otherwise.
findAndReuseScrutDrop :: Name -> Int -> CExpr -> Maybe CExpr
findAndReuseScrutDrop scrut k = go
  where
    go :: CExpr -> Maybe CExpr
    go = \case
      -- Found scrut drop in this path. Strip it; the inner is the
      -- post-drop expression that 'rewriteFirstCCon' searches for a
      -- matching 'CCon' to redirect.
      CDrop _ n inner
        | n == scrut ->
            rewriteFirstCCon scrut k inner
      -- Other 'CDrop' (arm-binder, transient param). Preserve and
      -- recurse — the scrut drop may be further down.
      CDrop dk m inner ->
        CDrop dk m <$> go inner
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
--   * 'CCase' / 'CRowCase' arms — tries every arm; the whole
--     case rewrites if /any/ arm rewrites. Non-rewriting arms
--     keep their original body (the 'CCon' in those paths stays
--     a normal allocation).
--   * 'CDrop' — recurses into the wrapped body.
--
-- Stops at:
--
--   * Any 'CCon' of arity @k@ — rewrite to 'CReuse'.
--   * Any 'CCall' / 'CVar' / 'CString' / 'CIntLit' / 'CBuiltIn'
--     / 'CRow' / 'CLoop' / 'CReuse' — no rewrite (no further
--     descent; 'CLoop' is conservatively skipped because it
--     would jump back to a continue site that may not preserve
--     the reused-cell discipline).
rewriteFirstCCon :: Name -> Int -> CExpr -> Maybe CExpr
rewriteFirstCCon n k = go
  where
    go :: CExpr -> Maybe CExpr
    go = \case
      CCon t fs | length fs == k -> Just (CReuse n t fs)
      CContinue xs -> CContinue <$> goList xs
      CCase scrut alts ->
        case goAlts alts of
          Just alts' -> Just (CCase scrut alts')
          Nothing -> Nothing
      CRowCase scrut alts ->
        case goRowAlts alts of
          Just alts' -> Just (CRowCase scrut alts')
          Nothing -> Nothing
      CDrop dk m b -> CDrop dk m <$> go b
      _ -> Nothing

    -- Rewrite the first list element that contains a matching CCon;
    -- subsequent elements stay unchanged.
    goList :: [CExpr] -> Maybe [CExpr]
    goList = \case
      [] -> Nothing
      x : xs -> case go x of
        Just x' -> Just (x' : xs)
        Nothing -> (x :) <$> goList xs

    -- Rewrite arms that have a matching CCon; arms that don't
    -- match keep their original body. The whole list "succeeds"
    -- iff at least one arm rewrote.
    goAlts :: [(Int, [Name], CExpr)] -> Maybe [(Int, [Name], CExpr)]
    goAlts alts =
      let results = [(t, vs, go b, b) | (t, vs, b) <- alts]
          anyChanged = any (\(_, _, mr, _) -> isJust mr) results
       in if anyChanged
            then Just [(t, vs, fromMaybe b mb) | (t, vs, mb, b) <- results]
            else Nothing

    goRowAlts :: [(Word32, Name, CExpr)] -> Maybe [(Word32, Name, CExpr)]
    goRowAlts alts =
      let results = [(t, v, go b, b) | (t, v, b) <- alts]
          anyChanged = any (\(_, _, mr, _) -> isJust mr) results
       in if anyChanged
            then Just [(t, v, fromMaybe b mb) | (t, v, mb, b) <- results]
            else Nothing
