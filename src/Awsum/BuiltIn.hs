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
      ("predInt32", TyArrow noSpan int32Ty (eitherTy underflowErrorTy int32Ty)),
      -- predUInt8 : UInt8 -> Either UnderflowError UInt8
      -- Returns `Left UnderflowError` on 0, `Right (x - 1)` elsewhere.
      ("predUInt8", TyArrow noSpan uint8Ty (eitherTy underflowErrorTy uint8Ty)),
      -- succInt32 : Int32 -> Either OverflowError Int32
      -- Returns `Left OverflowError` on 'maxInt32', `Right (x + 1)` elsewhere.
      ("succInt32", TyArrow noSpan int32Ty (eitherTy overflowErrorTy int32Ty)),
      -- succUInt8 : UInt8 -> Either OverflowError UInt8
      -- Returns `Left OverflowError` on 255, `Right (x + 1)` elsewhere.
      ("succUInt8", TyArrow noSpan uint8Ty (eitherTy overflowErrorTy uint8Ty)),
      -- eqInt32 : Int32 -> Int32 -> Bool
      ("eqInt32", TyArrow noSpan int32Ty (TyArrow noSpan int32Ty boolTy)),
      -- eqUInt8 : UInt8 -> UInt8 -> Bool
      ("eqUInt8", TyArrow noSpan uint8Ty (TyArrow noSpan uint8Ty boolTy)),
      -- addInt32 : Int32 -> Int32 -> Either ArithError Int32
      -- `Left Underflow` if the true sum is below 'minInt32', `Left Overflow`
      -- if above 'maxInt32', `Right (a + b)` otherwise. Both ends are
      -- reachable from one operation, hence the two-constructor 'ArithError'.
      ("addInt32", TyArrow noSpan int32Ty (TyArrow noSpan int32Ty (eitherTy arithErrorTy int32Ty))),
      -- addUInt8 : UInt8 -> UInt8 -> Either OverflowError UInt8
      -- `Left OverflowError` if `a + b > 255`, `Right (a + b)` otherwise.
      -- Underflow is unreachable for unsigned addition, so the error type
      -- stays `OverflowError`, not `ArithError`.
      ("addUInt8", TyArrow noSpan uint8Ty (TyArrow noSpan uint8Ty (eitherTy overflowErrorTy uint8Ty))),
      -- concatString : String -> String -> String
      -- The '++' operator is parser sugar for a call to this built-in.
      ("concatString", TyArrow noSpan stringTy (TyArrow noSpan stringTy stringTy)),
      -- splitOnFirst : String -> String -> Maybe (Tuple2 String String)
      -- Splits 'str' at the first occurrence of 'separator'; see
      -- 'stdlib/Prelude.aww' for the full edge-case spec.
      ("splitOnFirst", TyArrow noSpan stringTy (TyArrow noSpan stringTy (maybeTy (tuple2Ty stringTy stringTy))))
    ]
  where
    int32Ty = TyCon noSpan "Int32"
    uint8Ty = TyCon noSpan "UInt8"
    stringTy = TyCon noSpan "String"
    boolTy = TyCon noSpan "Bool"
    underflowErrorTy = TyCon noSpan "UnderflowError"
    overflowErrorTy = TyCon noSpan "OverflowError"
    arithErrorTy = TyCon noSpan "ArithError"
    eitherTy a = TyApp noSpan (TyApp noSpan (TyCon noSpan "Either") a)
    maybeTy = TyApp noSpan (TyCon noSpan "Maybe")
    tuple2Ty a = TyApp noSpan (TyApp noSpan (TyCon noSpan "Tuple2") a)

-- | Look up a built-in by its surface name. 'Nothing' is an "unknown
--   builtin" error — the caller is responsible for surfacing it as a
--   diagnostic tied to the 'EBuiltIn' span.
lookupBuiltIn :: Name -> Maybe Type'
lookupBuiltIn n = M.lookup n builtIns
