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
module Awsum.Tco (tcoProgram, untcoProgram) where

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
      other -> (other, False)

-- | Inverse of 'tcoProgram': strips every 'CLoop' wrapper and turns
-- 'CContinue' back into a self-recursive 'CCall'. Used by backends
-- that haven't yet learned to emit real loop-and-jump — they get
-- correct (if stack-unsafe) semantics; newer backends skip this and
-- lower 'CLoop' / 'CContinue' natively.
untcoProgram :: CoreProgram -> CoreProgram
untcoProgram (CoreProgram ds) = CoreProgram (map untcoDecl ds)

untcoDecl :: CDecl -> CDecl
untcoDecl = \case
  CValDef n e -> CValDef n (stripLoop n e)
  CFunDef n ps body -> CFunDef n ps (stripLoop n body)
  where
    -- Strip the outer 'CLoop' and rewrite inner 'CContinue's into
    -- self-calls. No-op when the body doesn't start with 'CLoop'.
    stripLoop :: Name -> CExpr -> CExpr
    stripLoop fn = \case
      CLoop b -> unwind fn b
      other -> other

    unwind :: Name -> CExpr -> CExpr
    unwind fn = go
      where
        go = \case
          CContinue args -> CCall (CVar fn) (map go args)
          CCase scrut alts ->
            CCase (go scrut) [(tag, vs, go body) | (tag, vs, body) <- alts]
          CRowCase scrut alts ->
            CRowCase (go scrut) [(tag, v, go body) | (tag, v, body) <- alts]
          CRow tag v -> CRow tag (go v)
          CCall f xs -> CCall (go f) (map go xs)
          CCon tag fs -> CCon tag (map go fs)
          CLoop b -> CLoop (go b)
          e@(CVar _) -> e
          e@(CString _) -> e
          e@(CIntLit _ _) -> e
          e@(CBuiltIn _) -> e
