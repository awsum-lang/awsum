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
      -- Read program command-line argument as an Awsum 'String'
      -- (strict UTF-16). The error-row carries the two decoding
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
        ioArgsDecodeStringTy
      )
    ]
  where
    stringTy = TyCon noSpan "String"
    stringTooLongTy = TyCon noSpan "StringTooLong"
    unpairedUtf16SurrogateTy = TyCon noSpan "UnpairedUtf16Surrogate"
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
    -- 'IO (StringTooLong | UnpairedUtf16Surrogate) String' for
    -- 'IO.Args.getArgs' — error row mirrors the same failure
    -- alphabet the entry-point validator and 'BuiltIn.internalGetArgs'
    -- already use.
    ioArgsDecodeStringTy =
      TyApp
        noSpan
        ( TyApp
            noSpan
            (TyCon noSpan "IO")
            (TyOr noSpan stringTooLongTy unpairedUtf16SurrogateTy)
        )
        stringTy
