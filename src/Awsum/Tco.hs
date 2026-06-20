-- | Self tail-call optimisation pass.
--
-- Rewrites every self-recursive call in tail position into a
-- 'CContinue' and wraps the body in a 'CLoop'.
--
-- Tail positions:
--
--   * The body of a 'CFunDef'.
--   * Each arm's body of a 'CCase' in tail position.
--
-- Everything else — call arguments, 'CCon' fields, 'CCase' scrutinees —
-- is non-tail, so self-recursive calls there stay as ordinary 'CCall's.
-- Non-self-recursive tail calls are also preserved: mutual recursion is
-- handled by 'Awsum.Scc'.
--
-- No-op on functions with no self-tail-call: the 'CLoop' wrapper is
-- only introduced when the body actually changed, keeping Core
-- snapshots stable for non-tail-recursive code.
module Awsum.Tco (tcoProgram) where

import Awsum.Core
import Awsum.Syntax (Name)
import Relude

-- | Run self-TCO over every declaration in the program.
tcoProgram :: CoreProgram -> CoreProgram
tcoProgram (CoreProgram ds) = CoreProgram (map tcoDecl ds)

tcoDecl :: CDecl -> CDecl
tcoDecl = \case
  CValDef n e -> CValDef n e
  CFunDef n ps body ->
    let (body', changed) = rewriteTail n body
     in if changed then CFunDef n ps (CLoop body') else CFunDef n ps body

-- | Rewrite self-recursive calls in tail positions of @body@ into
-- 'CContinue'. The 'Bool' reports whether anything changed — used to
-- decide whether the body needs a 'CLoop' wrapper.
rewriteTail :: Name -> CExpr -> (CExpr, Bool)
rewriteTail fn = go
  where
    go :: CExpr -> (CExpr, Bool)
    go = \case
      CCall (CVar n) args | n == fn -> (CContinue args, True)
      CCase scrut alts ->
        let results = [(tag, vs, go body) | (tag, vs, body) <- alts]
            alts' = [(tag, vs, body') | (tag, vs, (body', _)) <- results]
            anyChanged = any (\(_, _, (_, c)) -> c) results
         in (CCase scrut alts', anyChanged)
      CRowCase scrut alts ->
        let results = [(tag, v, go body) | (tag, v, body) <- alts]
            alts' = [(tag, v, body') | (tag, v, (body', _)) <- results]
            anyChanged = any (\(_, _, (_, c)) -> c) results
         in (CRowCase scrut alts', anyChanged)
      -- Tail leaves: a non-self 'CCall', a 'CCon' / 'CRow', or an atom is the
      -- function's result value, and its sub-expressions are non-tail (a
      -- self-call there stays a 'CCall'), so there is nothing to rewrite.
      e@(CCall _ _) -> (e, False)
      e@(CCon _ _) -> (e, False)
      e@(CRow _ _) -> (e, False)
      e@(CVar _) -> (e, False)
      e@(CString _) -> (e, False)
      e@(CIntLit _ _) -> (e, False)
      e@(CBuiltIn _) -> (e, False)
      -- Every node below is minted by a /later/ pass, so reaching it in Tco's
      -- input is a pipeline bug. Enumerated (no catch-all): a uniform policy
      -- with 'Awsum.Cps', and a guard that a future 'CExpr' node can't be
      -- silently leafed. The sharp case is 'CJoin' — a tail self-call in its
      -- body left un-rewritten would stay a 'CCall' past 'StackSafety', i.e.
      -- unbounded stack on JVM/JS.
      --
      -- 'CLoop' / 'CContinue' are produced by this pass; 'CDrop' / 'CReuse' by
      -- 'Awsum.Lifetime' / 'Awsum.Reuse' after it.
      CLoop _ -> error "Awsum.Tco: CLoop reached rewriteTail — Tco is its only producer"
      CContinue _ -> error "Awsum.Tco: CContinue reached rewriteTail — Tco is its only producer"
      CDrop {} -> error "Awsum.Tco: CDrop reached rewriteTail — Tco must run before insertDrops"
      CReuse {} -> error "Awsum.Tco: CReuse reached rewriteTail — Tco must run before insertReuse"
      -- 'CLet' / 'CProj' / 'CJoin' / 'CJump' are minted by 'Awsum.Simplify' after Tco.
      CLet {} -> error "Awsum.Tco: CLet reached rewriteTail — Tco must run before Simplify"
      CProj {} -> error "Awsum.Tco: CProj reached rewriteTail — Tco must run before Simplify"
      CJoin {} -> error "Awsum.Tco: CJoin reached rewriteTail — Tco must run before Simplify"
      CJump {} -> error "Awsum.Tco: CJump reached rewriteTail — Tco must run before Simplify"
