-- | Platform-effect table for @--program-type cli@ programs.
--
-- Entries in this table are the qualified-name effects reachable from
-- a CLI program — things the user writes as @IO.Stdout.print@, not as
-- a prelude-visible @BuiltIn.foo@ alias. Module-level visibility still
-- applies (@import IO.Stdout@ must be present), so this table is the
-- /program-type/ gate, not the /module/ gate.
--
-- Adding a new CLI effect: append an entry here (surface name + type),
-- add a matching dispatch branch to every backend in
-- @src/Awsum/Codegen/*@, and — where a runtime helper is needed —
-- extend the @Set Name -> …@ gate in that backend's runtime emitter.
module Awsum.Program.Cli (cliPlatformTable) where

import Awsum.Syntax (QName (..), Type' (..), noSpan)
import Data.Map.Strict qualified as M
import Relude

-- | CLI-program platform-effect table.
cliPlatformTable :: Map QName Type'
cliPlatformTable =
  M.fromList
    [ -- Print to stdout (no newline). Compiled per-target:
      -- printf on LLVM, System.out.print on JVM, Console.Write
      -- on CLR, WASI fd_write on WASM, process.stdout.write on
      -- Node.
      ( QName ["IO", "Stdout"] "print",
        TyArrow noSpan stringTy ioNeverUnitTy
      ),
      -- Read every program command-line argument as a prelude
      -- 'List String' (each element strict UTF-16). All-or-nothing
      -- error semantics: if any element fails to decode, the whole
      -- call returns 'Left'. The error-row carries the two decoding
      -- failures the entry-point validator rejects: 'StringTooLong'
      -- (over 'maxStringLengthUtf16CodeUnits' = 2^27 UTF-16 code
      -- units) and 'UnpairedUtf16Surrogate' (any high surrogate
      -- not immediately followed by a low one, or any orphan low
      -- surrogate). Compiled per-target via 'BuiltIn.internalGetArgs':
      -- the lowering rewrites the platform call into an 'IOGetArgs'
      -- constructor whose continuation routes 'Left' to 'IOFail'
      -- and 'Right' to 'IOPure'; 'runIO' walks the cell and fires
      -- the cached argv read at that point.
      ( QName ["IO", "Args"] "getArgs",
        ioInputDecodeListStringTy
      ),
      -- Read stdin to EOF as an Awsum 'String', decoding the raw bytes
      -- as strict UTF-8 (RFC 3629). The error row carries the length
      -- cap ('StringTooLong') and byte-level malformation
      -- ('InvalidUtf8') — distinct from 'IO.Args.getArgs', whose
      -- host-decoded argv can only fail with 'UnpairedUtf16Surrogate'.
      -- Compiled per-target via 'BuiltIn.internalStdinReadAllString':
      -- the lowering rewrites the platform call into an
      -- 'IOStdinReadAllString' constructor whose continuation routes
      -- 'Left' to 'IOFail' and 'Right' to 'IOPure'; 'runIO' walks the
      -- cell and fires the read at that point. Per the no-memoisation
      -- decision (POSIX-honest), each call reads whatever bytes remain
      -- on fd 0; a second call after EOF decodes to 'Right ""'.
      ( QName ["IO", "Stdin"] "readAllString",
        ioStdinDecodeStringTy
      ),
      -- Read stdin to EOF as raw bytes ('List UInt8'), no decode. The
      -- result type carries no error row ('Never') because raw-byte
      -- capture cannot fail on content. Compiled per-target via
      -- 'BuiltIn.internalStdinReadAllBytes': the lowering rewrites the
      -- platform call into an 'IOStdinReadAllBytes' constructor whose
      -- continuation lifts the bytes straight to 'IOPure'. Same
      -- POSIX-honest no-memoisation semantics; a second call after EOF
      -- yields 'Nil'.
      ( QName ["IO", "Stdin"] "readAllBytes",
        ioNeverListUInt8Ty
      )
    ]
  where
    stringTy = TyCon noSpan "String"
    uint8Ty = TyCon noSpan "UInt8"
    stringTooLongTy = TyCon noSpan "StringTooLong"
    unpairedUtf16SurrogateTy = TyCon noSpan "UnpairedUtf16Surrogate"
    invalidUtf8Ty = TyCon noSpan "InvalidUtf8"
    -- 'Never' is declared as 'empty type Never' in 'Prelude.aww', so
    -- the row-identity slot here uses 'TyEmpty' rather than 'TyCon'.
    -- Without this, the typechecker would only know 'Never' as a
    -- regular nominal label, lose the row-identity rule, and reject
    -- @IO.Stdout.print "x"@ in any position expecting a wider error
    -- row (see 'Awsum.HM.rowSubsume').
    ioNeverUnitTy =
      TyApp
        noSpan
        (TyApp noSpan (TyCon noSpan "IO") (TyEmpty noSpan "Never"))
        (TyCon noSpan "Unit")
    -- 'IO (StringTooLong | InvalidUtf8) String' — used by
    -- 'IO.Stdin.readAllString'. Mirrors the 'stdinDecodeRowTy' in
    -- 'Awsum.BuiltIn' that types the matching low-level
    -- 'internalStdinReadAllString'.
    ioStdinDecodeStringTy =
      TyApp
        noSpan
        ( TyApp
            noSpan
            (TyCon noSpan "IO")
            (TyOr noSpan stringTooLongTy invalidUtf8Ty)
        )
        stringTy
    -- 'IO Never (List UInt8)' — used by 'IO.Stdin.readAllBytes'. The
    -- 'Never' error row uses 'TyEmpty' for the same row-identity reason
    -- as 'ioNeverUnitTy' above.
    listUInt8Ty = TyApp noSpan (TyCon noSpan "List") uint8Ty
    ioNeverListUInt8Ty =
      TyApp
        noSpan
        (TyApp noSpan (TyCon noSpan "IO") (TyEmpty noSpan "Never"))
        listUInt8Ty
    -- 'IO (StringTooLong | UnpairedUtf16Surrogate) (List String)' —
    -- used by 'IO.Args.getArgs'. Same error row as the singleton
    -- variant above; the result is the prelude 'List String' carrying
    -- every argv element. Mirrors the 'internalGetArgs' signature in
    -- 'Awsum.BuiltIn'.
    listStringTy = TyApp noSpan (TyCon noSpan "List") stringTy
    ioInputDecodeListStringTy =
      TyApp
        noSpan
        ( TyApp
            noSpan
            (TyCon noSpan "IO")
            (TyOr noSpan stringTooLongTy unpairedUtf16SurrogateTy)
        )
        listStringTy
