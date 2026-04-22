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
      -- Node, io.write on Lua.
      ( QName ["IO", "Stdout"] "print",
        TyArrow noSpan stringTy ioUnitTy
      )
    ]
  where
    stringTy = TyCon noSpan "String"
    ioUnitTy = TyCon noSpan "IOUnit"
