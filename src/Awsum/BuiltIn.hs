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

-- | Surface type of every compiler-known built-in, keyed by the name
--   after @BuiltIn.@ in source.
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
      -- eqString : String -> String -> Bool
      -- Equality on UTF-16 code-unit sequences. JVM/CLR/JS delegate to
      -- the host's native String equality (UTF-16 by spec on all
      -- three); LLVM/WASM short-circuit on byte_count and then memcmp
      -- the UTF-8 payload (equivalent because strict UTF-16 gives a
      -- bijection between valid UTF-16 and valid UTF-8).
      ("eqString", TyArrow noSpan stringTy (TyArrow noSpan stringTy boolTy)),
      -- addInt32 : Int32 -> Int32 -> Either (UnderflowError | OverflowError) Int32
      -- `Left UnderflowError` if the true sum is below 'minInt32',
      -- `Left OverflowError` if above 'maxInt32', `Right (a + b)`
      -- otherwise. Both ends are reachable from one operation, so the
      -- error side is a structural sum of the two existing
      -- single-constructor error types — the row carries an FNV-1a tag
      -- per label so user-side @case e of (u : UnderflowError) -> …@
      -- dispatches the right way.
      ("addInt32", TyArrow noSpan int32Ty (TyArrow noSpan int32Ty (eitherTy arithRowTy int32Ty))),
      -- subInt32 : Int32 -> Int32 -> Either (UnderflowError | OverflowError) Int32
      -- `Left OverflowError` if `a - b > maxInt32`, `Left UnderflowError`
      -- if `a - b < minInt32`, `Right (a - b)` otherwise. Both ends are
      -- reachable (e.g. `maxInt32 - (-1)` overflows positively,
      -- `minInt32 - 1` underflows), so the error side mirrors
      -- 'addInt32'.
      ("subInt32", TyArrow noSpan int32Ty (TyArrow noSpan int32Ty (eitherTy arithRowTy int32Ty))),
      -- mulInt32 : Int32 -> Int32 -> Either (UnderflowError | OverflowError) Int32
      -- `Left OverflowError` if `a * b > maxInt32`, `Left UnderflowError`
      -- if `a * b < minInt32`, `Right (a * b)` otherwise. Both ends are
      -- reachable (e.g. `maxInt32 * 2`, `minInt32 * 2`), so the error
      -- side matches the additive operations.
      ("mulInt32", TyArrow noSpan int32Ty (TyArrow noSpan int32Ty (eitherTy arithRowTy int32Ty))),
      -- negInt32 : Int32 -> Either OverflowError Int32
      -- `Left OverflowError` on 'minInt32' (negation would yield 2147483648,
      -- which doesn't fit in Int32), `Right (-x)` otherwise. Single-error
      -- type because only positive overflow is reachable on negation.
      ("negInt32", TyArrow noSpan int32Ty (eitherTy overflowErrorTy int32Ty)),
      -- addUInt8 : UInt8 -> UInt8 -> Either OverflowError UInt8
      -- `Left OverflowError` if `a + b > 255`, `Right (a + b)` otherwise.
      -- Underflow is unreachable for unsigned addition, so the error type
      -- stays `OverflowError`, not `ArithError`.
      ("addUInt8", TyArrow noSpan uint8Ty (TyArrow noSpan uint8Ty (eitherTy overflowErrorTy uint8Ty))),
      -- subUInt8 : UInt8 -> UInt8 -> Either UnderflowError UInt8
      -- `Left UnderflowError` if `a < b`, `Right (a - b)` otherwise.
      -- Overflow is unreachable for unsigned subtraction (the difference
      -- of two UInt8 values is in -255..255 and stays in 0..255 when
      -- non-negative), so the error type is 'UnderflowError', symmetric
      -- to 'addUInt8' which uses 'OverflowError'.
      ("subUInt8", TyArrow noSpan uint8Ty (TyArrow noSpan uint8Ty (eitherTy underflowErrorTy uint8Ty))),
      -- mulUInt8 : UInt8 -> UInt8 -> Either OverflowError UInt8
      -- `Left OverflowError` if `a * b > 255`, `Right (a * b)` otherwise.
      -- Underflow is unreachable for unsigned multiplication (product of
      -- two non-negative values is non-negative). Symmetric to 'addUInt8'.
      ("mulUInt8", TyArrow noSpan uint8Ty (TyArrow noSpan uint8Ty (eitherTy overflowErrorTy uint8Ty))),
      -- concatString : String -> String -> Either StringTooLong String
      -- The '++' operator is parser sugar for a call to this built-in.
      -- Returns 'Right (a ++ b)' when the result would fit in
      -- 'maxStringLengthUtf16CodeUnits' (134_217_728) UTF-16 code units;
      -- otherwise 'Left StringTooLong' with no buffer allocated. Each
      -- backend's runtime helper performs the cap check before copying.
      ("concatString", TyArrow noSpan stringTy (TyArrow noSpan stringTy (eitherTy stringTooLongTy stringTy))),
      -- splitOnFirst : String -> String -> Maybe (Tuple2 String String)
      -- Splits 'str' at the first occurrence of 'separator'; see
      -- 'stdlib/Prelude.aww' for the full edge-case spec.
      ("splitOnFirst", TyArrow noSpan stringTy (TyArrow noSpan stringTy (maybeTy (tuple2Ty stringTy stringTy)))),
      -- parseInt32 : String -> Either ParseError Int32
      -- Strict decimal parser; grammar mirrors the language literal —
      -- optional '-', one or more digits, nothing else. See Prelude.aww
      -- for the full example list.
      ("parseInt32", TyArrow noSpan stringTy (eitherTy parseErrorTy int32Ty)),
      -- parseUInt8 : String -> Either ParseError UInt8
      -- Same grammar, no sign accepted (UInt8 is unsigned), range 0..255.
      ("parseUInt8", TyArrow noSpan stringTy (eitherTy parseErrorTy uint8Ty)),
      -- showUInt32 : UInt32 -> String
      ("showUInt32", TyArrow noSpan uint32Ty stringTy),
      -- predUInt32 : UInt32 -> Either UnderflowError UInt32
      -- Returns `Left UnderflowError` on 0, `Right (x - 1)` elsewhere.
      ("predUInt32", TyArrow noSpan uint32Ty (eitherTy underflowErrorTy uint32Ty)),
      -- succUInt32 : UInt32 -> Either OverflowError UInt32
      -- Returns `Left OverflowError` on 4294967295, `Right (x + 1)` elsewhere.
      ("succUInt32", TyArrow noSpan uint32Ty (eitherTy overflowErrorTy uint32Ty)),
      -- eqUInt32 : UInt32 -> UInt32 -> Bool
      ("eqUInt32", TyArrow noSpan uint32Ty (TyArrow noSpan uint32Ty boolTy)),
      -- addUInt32 : UInt32 -> UInt32 -> Either OverflowError UInt32
      -- `Left OverflowError` if `a + b > 4294967295`, `Right (a + b)`
      -- otherwise. Underflow is unreachable for unsigned addition,
      -- symmetric to 'addUInt8'.
      ("addUInt32", TyArrow noSpan uint32Ty (TyArrow noSpan uint32Ty (eitherTy overflowErrorTy uint32Ty))),
      -- subUInt32 : UInt32 -> UInt32 -> Either UnderflowError UInt32
      -- `Left UnderflowError` if `a < b`, `Right (a - b)` otherwise.
      -- Symmetric to 'subUInt8'.
      ("subUInt32", TyArrow noSpan uint32Ty (TyArrow noSpan uint32Ty (eitherTy underflowErrorTy uint32Ty))),
      -- mulUInt32 : UInt32 -> UInt32 -> Either OverflowError UInt32
      -- `Left OverflowError` if `a * b > 4294967295`, `Right (a * b)`
      -- otherwise. Symmetric to 'mulUInt8'.
      ("mulUInt32", TyArrow noSpan uint32Ty (TyArrow noSpan uint32Ty (eitherTy overflowErrorTy uint32Ty))),
      -- parseUInt32 : String -> Either ParseError UInt32
      -- No sign, decimal digits only, no whitespace, no trailing
      -- characters. Range 0..4294967295.
      ("parseUInt32", TyArrow noSpan stringTy (eitherTy parseErrorTy uint32Ty)),
      -- lengthCodePoints : String -> UInt32
      -- Counts Unicode code points (USVs) in the string. A surrogate
      -- pair counts once, never twice. The result is independent of how
      -- the backend stores the string (UTF-8 bytes vs UTF-16 code units).
      ("lengthCodePoints", TyArrow noSpan stringTy uint32Ty),
      -- lengthUtf16CodeUnits : String -> UInt32
      -- Number of 16-bit code units in the UTF-16 form of the string —
      -- BMP characters count as 1, supplementary characters count as 2
      -- (high + low surrogate). Matches 'String.length' on JVM/JS/CLR.
      ("lengthUtf16CodeUnits", TyArrow noSpan stringTy uint32Ty),
      -- lengthUtf8Bytes : String -> UInt32
      -- Number of bytes the string would occupy when serialised as
      -- (standard, not modified) UTF-8. ASCII characters count as 1,
      -- 2/3/4 bytes for the higher ranges per RFC 3629.
      ("lengthUtf8Bytes", TyArrow noSpan stringTy uint32Ty),
      -- internalStdoutPrint : String -> Unit
      -- Privileged low-level platform primitive: writes the argument to
      -- stdout (no newline), returns the Unit constructor. Used
      -- exclusively by the prelude's `runIO` to perform the effect of
      -- an `IOStdoutPrint` arm during IO-tree walking. Not exposed to
      -- user code via any prelude alias — there is no module/visibility
      -- system in Awsum yet, so the contract is convention only:
      -- user code uses `IO.Stdout.print` (a platform built-in that
      -- elaborates to an `IOStdoutPrint` constructor); only `runIO`
      -- reaches into `BuiltIn.internalStdoutPrint` directly. When
      -- modules land, this and the IO type's constructors move into a
      -- privileged module inaccessible to user code.
      ("internalStdoutPrint", TyArrow noSpan stringTy unitTy),
      -- internalGetArgs : Either (StringTooLong | UnpairedUtf16Surrogate) (List String)
      -- Privileged zero-arg low-level primitive: reads the platform's
      -- raw argv at runtime and decodes each element into Awsum's strict
      -- UTF-16 'String', returning the result as a prelude 'List String'.
      -- All-or-nothing error semantics: 'Left StringTooLong' if any
      -- element's decoded length would exceed
      -- 'maxStringLengthUtf16CodeUnits', 'Left UnpairedUtf16Surrogate'
      -- if any element contains an unpaired surrogate, 'Right xs' on
      -- success. Used exclusively by the prelude's 'runIO' to perform
      -- the effect of an 'IOGetArgs' arm during IO-tree walking. The
      -- user-facing wrapper is 'IO.Args.getArgs' (a CLI platform built-in
      -- that elaborates to an 'IOGetArgs' constructor whose continuation
      -- routes 'Left' to 'IOFail' and 'Right' to 'IOPure'). Per the
      -- no-memoisation decision, each call re-reads argv; deterministic
      -- because argv does not change during program execution.
      ("internalGetArgs", eitherTy inputDecodeRowTy listStringTy),
      -- internalStdinReadAllAsUtf16 : Either (StringTooLong | UnpairedUtf16Surrogate) String
      -- Privileged zero-arg low-level primitive: reads the platform's
      -- raw stdin to EOF and decodes it into Awsum's strict UTF-16
      -- 'String'; same error row and decoder as 'internalGetArgs', the
      -- byte source is the only difference. Used exclusively by the
      -- prelude's 'runIO' to perform the effect of an 'IOStdinReadAll'
      -- arm during IO-tree walking. The user-facing wrapper is
      -- 'IO.Stdin.readAll' (a CLI platform built-in that elaborates to
      -- an 'IOStdinReadAll' constructor whose continuation routes
      -- 'Left' to 'IOFail' and 'Right' to 'IOPure'). Each call reads
      -- whatever bytes remain on fd 0; a second call after EOF
      -- consequently returns 'Right ""'. No per-backend state — the
      -- OS-natural semantics of a consumed stream is exposed as-is.
      ("internalStdinReadAllAsUtf16", eitherTy inputDecodeRowTy stringTy)
    ]
  where
    int32Ty = TyCon noSpan "Int32"
    uint8Ty = TyCon noSpan "UInt8"
    uint32Ty = TyCon noSpan "UInt32"
    stringTy = TyCon noSpan "String"
    boolTy = TyCon noSpan "Bool"
    unitTy = TyCon noSpan "Unit"
    underflowErrorTy = TyCon noSpan "UnderflowError"
    overflowErrorTy = TyCon noSpan "OverflowError"
    -- Structural row of the two single-constructor error labels — the
    -- error side of the signed-integer arithmetic builtins.
    arithRowTy = TyOr noSpan underflowErrorTy overflowErrorTy
    parseErrorTy = TyCon noSpan "ParseError"
    stringTooLongTy = TyCon noSpan "StringTooLong"
    unpairedUtf16SurrogateTy = TyCon noSpan "UnpairedUtf16Surrogate"
    -- Structural row of the two decode-failure labels — the error side
    -- shared by every primitive that reads platform-encoded text and
    -- must report both length-cap and surrogate-validity violations
    -- ('internalGetArgs', 'internalStdinReadAllAsUtf16', and any future
    -- input-parsing primitive of the same shape).
    inputDecodeRowTy = TyOr noSpan stringTooLongTy unpairedUtf16SurrogateTy
    listStringTy = TyApp noSpan (TyCon noSpan "List") stringTy
    eitherTy a = TyApp noSpan (TyApp noSpan (TyCon noSpan "Either") a)
    maybeTy = TyApp noSpan (TyCon noSpan "Maybe")
    tuple2Ty a = TyApp noSpan (TyApp noSpan (TyCon noSpan "Tuple2") a)

-- | Look up a built-in by its surface name. 'Nothing' is an "unknown
--   builtin" error — the caller is responsible for surfacing it as a
--   diagnostic tied to the 'EBuiltIn' span.
lookupBuiltIn :: Name -> Maybe Type'
lookupBuiltIn n = M.lookup n builtIns
