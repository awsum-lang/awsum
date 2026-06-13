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
      -- A 'CLet' in tail position has @body@ as its tail; @rhs@ is non-tail
      -- (a self-call there must stay a 'CCall', not become a 'CContinue'),
      -- so only @body@ is rewritten. Matches the tail/non-tail split
      -- documented on 'CLet' in "Awsum.Core". (No pass emits 'CLet' before
      -- 'Awsum.Tco' today; this keeps the traversal honest for that step.)
      CLet x rhs body ->
        let (body', changed) = go body
         in (CLet x rhs body', changed)
      other -> (other, False)
