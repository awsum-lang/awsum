-- | The compiler's built-in table.
--
-- User code reaches built-ins through the reserved @BuiltIn.foo@ syntax
-- (see 'Awsum.Syntax.EBuiltIn'). Those references are checked against
-- this table at typecheck time: the name must exist and its declared
-- surface type must be exactly the one on the surrounding signature.
-- At codegen every backend also consults this table (indirectly, via
-- 'Awsum.Core.CBuiltIn') to emit its per-target implementation.
--
-- See @docs/prelude.md@ for the architectural rationale. New built-ins
-- are added here together with a matching signature in
-- @stdlib/Prelude.aww@ and per-target codegen branches in
-- @src/Awsum/Codegen/*@.
module Awsum.BuiltIn
  ( builtIns,
    lookupBuiltIn,
  )
where

import Awsum.Syntax (Name, Type' (..), noSpan)
import Data.Map.Strict qualified as M
import Relude

-- | Surface type of every compiler-known built-in, keyed by the name that
--   appears after @BuiltIn.@ in source. Grows as more prelude-visible
--   functions migrate off their hardcoded implementations; step 5 seeds
--   this with 'showInt32'.
builtIns :: Map Name Type'
builtIns =
  M.fromList
    [ ("showInt32", TyArrow noSpan int32Ty stringTy),
      ("showUInt8", TyArrow noSpan uint8Ty stringTy),
      -- predInt32 : Int32 -> Either UnderflowError Int32
      -- Returns `Left UnderflowError` on 'minInt32', `Right (x - 1)` elsewhere.
      ("predInt32", TyArrow noSpan int32Ty (eitherTy underflowErrorTy int32Ty))
    ]
  where
    int32Ty = TyCon noSpan "Int32"
    uint8Ty = TyCon noSpan "UInt8"
    stringTy = TyCon noSpan "String"
    underflowErrorTy = TyCon noSpan "UnderflowError"
    eitherTy a = TyApp noSpan (TyApp noSpan (TyCon noSpan "Either") a)

-- | Look up a built-in by its surface name. 'Nothing' is an "unknown
--   builtin" error — the caller is responsible for surfacing it as a
--   diagnostic tied to the 'EBuiltIn' span.
lookupBuiltIn :: Name -> Maybe Type'
lookupBuiltIn n = M.lookup n builtIns
