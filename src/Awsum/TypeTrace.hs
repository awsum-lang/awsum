-- | Per-position type information collected during typechecking, surfaced
--   to editor hover via 'Awsum.Lsp'.
--
--   The trace is keyed by 'SrcSpan' of the name (or binder) the cursor
--   can land on. Two record shapes:
--
--     * 'TRReference' — a name reference (an 'EVar', 'ECon',
--       'EBuiltIn', 'TyCon', 'TyEmpty', 'PCon'). Carries two types:
--       the /declared/ scheme as written in source (constructor sig,
--       built-in registry entry, etc.) and the /instantiated/ type
--       at this exact occurrence, after the surrounding substitution
--       learned from unification is applied. For monomorphic
--       references the two coincide; for polymorphic ones the
--       instantiated form is the one resolved by the call-site
--       context.
--
--     * 'TRBinder' — a binder introduction site (function 'Param',
--       lambda 'Param', pattern 'PVar', 'DoBind' / 'DoLet' /
--       'ELet' binder, top-level head name). One monomorphic type
--       per binder (Awsum has no let-generalisation).
--
--   The trace is produced by 'Awsum.Typing.typecheckProgram' and
--   consumed by 'Awsum.Lsp.hoverForPosition'. It is /accumulative/:
--   on type-error the trace is dropped, on success the entire
--   program's records are returned alongside the warning list.
module Awsum.TypeTrace
  ( TypeTrace,
    TypeRecord (..),
    emptyTrace,
    insertReference,
    insertBinder,
    applySubstTo,
    lookupAtPosition,
    lookupAtSpan,
  )
where

import Awsum.HM (Subst, applySubst)
import Awsum.Syntax (SrcSpan (..), Type')
import Data.List (minimumBy)
import Data.Map.Strict qualified as M
import Relude

-- Internal map key. 'SrcSpan' itself has @instance Ord SrcSpan where
--   compare _ _ = EQ@ (so AST-level equality ignores positions),
--   which would collapse every record in a 'Map' onto a single slot.
--   Carrying the raw @(startLine, startCol, endLine, endCol)@ tuple
--   sidesteps that — entries stay distinct by source position.
type SpanKey = (Int, Int, Int, Int)

spanKey :: SrcSpan -> SpanKey
spanKey (SrcSpan sl sc el ec) = (sl, sc, el, ec)

-- | Per-span record of what type the typechecker assigned to the
--   identifier whose source span this is.
data TypeRecord
  = -- | Reference site (EVar, ECon, EBuiltIn, TyCon, TyEmpty, PCon).
    --   Fields: declared scheme as written / registered; instantiated
    --   type at this occurrence (after applying the call-site subst).
    --   On monomorphic references both fields equal.
    TRReference Type' Type'
  | -- | Binder introduction site (param, pattern variable, do-bind,
    --   let-bind, lambda parameter, top-level head name). One
    --   monomorphic type (Awsum does not generalise locally).
    TRBinder Type'
  deriving stock (Show, Eq)

-- | Span ↦ record. Spans are the *narrow* identifier spans (just the
--   name, not the enclosing form), so a positional lookup finds at
--   most one record per cursor point. Keys carry the raw position
--   tuple internally to dodge 'SrcSpan'\'s position-blind 'Ord'.
type TypeTrace = Map SpanKey (SrcSpan, TypeRecord)

emptyTrace :: TypeTrace
emptyTrace = M.empty

insertReference :: SrcSpan -> Type' -> Type' -> TypeTrace -> TypeTrace
insertReference sp declared instantiated =
  M.insert (spanKey sp) (sp, TRReference declared instantiated)

insertBinder :: SrcSpan -> Type' -> TypeTrace -> TypeTrace
insertBinder sp ty = M.insert (spanKey sp) (sp, TRBinder ty)

-- | Direct lookup by 'SrcSpan' (matches on position tuple, not on the
--   no-op 'Eq SrcSpan'). Used by the LSP hover handler when the AST
--   walker has already pinpointed the name span the cursor is on.
lookupAtSpan :: SrcSpan -> TypeTrace -> Maybe TypeRecord
lookupAtSpan sp = fmap snd . M.lookup (spanKey sp)

-- | Apply a substitution to every record's /instantiated/ slot
--   (and to the binder type). The /declared/ slot is left as is —
--   it represents the user-facing scheme, which should not change
--   with call-site context.
applySubstTo :: Subst -> TypeTrace -> TypeTrace
applySubstTo s = M.map (second applyOne)
  where
    applyOne (TRReference d i) = TRReference d (applySubst s i)
    applyOne (TRBinder t) = TRBinder (applySubst s t)

-- | Find the record whose span contains the given (line, column),
--   preferring the /narrowest/ span if several overlap. Returns
--   'Nothing' when no record covers the position.
lookupAtPosition :: Int -> Int -> TypeTrace -> Maybe (SrcSpan, TypeRecord)
lookupAtPosition line col tr =
  let hits =
        [ (sp, r)
        | (_, (sp, r)) <- M.toList tr,
          contains sp line col
        ]
      width (SrcSpan sl sc el ec) =
        ((el - sl) * 1000000) + (ec - sc)
   in case hits of
        [] -> Nothing
        _ -> Just (minimumBy (\(a, _) (b, _) -> compare (width a) (width b)) hits)
  where
    contains (SrcSpan sl sc el ec) l c =
      (l > sl || (l == sl && c >= sc))
        && (l < el || (l == el && c <= ec))
