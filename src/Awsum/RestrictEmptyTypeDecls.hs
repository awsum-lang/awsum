-- | Reject user-code @empty type@ declarations.
--
-- @empty type X@ opts a type into the row-identity rule: it is uninhabited
-- and every two such declarations unify regardless of name (see
-- 'Awsum.HM.rowSubsume' and the @TyEmpty@ handling in 'Awsum.HM.unify').
-- The bundled prelude declares the one empty type the language needs —
-- @Never@ — and because all empty types are interchangeable, a
-- user-declared @empty type@ is only ever an alias of @Never@ that /looks/
-- like a distinct type but is not. To keep a single canonical row identity
-- (and avoid that hidden-alias trap), user code may not declare its own: it
-- reaches for @Never@ where it needs the row identity, or a plain
-- @type X@ (a distinct nominal label) otherwise.
--
-- Like "Awsum.RestrictPreludeRefs", this runs on the raw user 'Program'
-- /before/ 'Awsum.Prelude.withPrelude' splices the prelude in, and is a
-- no-op on the bundled prelude itself. When modules land the @empty@
-- keyword becomes prelude-private and this module is deleted.
module Awsum.RestrictEmptyTypeDecls
  ( EmptyTypeDeclViolation (..),
    restrictUserEmptyTypeDecls,
  )
where

import Awsum.Prelude (preludeProgram)
import Awsum.Syntax
import Relude

-- | One user-declared @empty type X@. The 'SrcSpan' covers the declaration
--   in user source; the 'Name' is the declared type name.
data EmptyTypeDeclViolation = EmptyTypeDeclViolation SrcSpan Name
  deriving stock (Show, Eq)

-- | Collect every @empty type@ declaration in the user program, in source
--   order. Returns @[]@ for the bundled prelude itself (so
--   @awsum check stdlib/Prelude.aww@ stays silent on its own
--   @empty type Never@ — the same idempotency trick
--   'Awsum.RestrictPreludeRefs.restrictPreludeRefs' uses).
restrictUserEmptyTypeDecls :: Program -> [EmptyTypeDeclViolation]
restrictUserEmptyTypeDecls userProg
  | userProg == preludeProgram = []
  | otherwise =
      [ EmptyTypeDeclViolation sp n
      | TypeDecl sp n _ _ _ Empty _ <- toList userProg.decls
      ]
