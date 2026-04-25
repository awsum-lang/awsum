-- | Program-type concept: what /kind/ of program the user is compiling.
--
-- This is orthogonal to the target (LLVM, JVM, …) and to module
-- imports. The program type decides which platform-specific effect
-- tables are visible to the compiler. A CLI program can reach
-- @IO.Stdout.print@ / @Process.exit@; a browser program (when that
-- type exists) would reach @Window.focus@ / @Document.querySelector@
-- and so on.
--
-- Today the only program type is 'ProgramCli'. See @docs/prelude.md@
-- for how program types interact with the prelude + built-in mechanism.
module Awsum.Program
  ( ProgramType (..),
    parseProgramType,
    programTypeName,
    platformTable,
  )
where

import Awsum.Program.Cli (cliPlatformTable)
import Awsum.Syntax (QName, Type')
import Relude

-- | Kind of program being compiled. The compiler ships one entry per
--   supported program type; each has its own platform-effect table.
data ProgramType = ProgramCli
  deriving stock (Show, Eq, Ord)

-- | Parse a user-supplied program-type token (as passed to the
--   @--program-type@ CLI flag). Returns the canonical value or the
--   offending input text so the caller can surface a diagnostic.
parseProgramType :: Text -> Either Text ProgramType
parseProgramType = \case
  "cli" -> Right ProgramCli
  other -> Left other

-- | Canonical surface name of a program type — the round-trip inverse
--   of 'parseProgramType'. Used in error messages and (when it lands)
--   in @awsum.json@.
programTypeName :: ProgramType -> Text
programTypeName = \case
  ProgramCli -> "cli"

-- | Platform-gated effect table visible for the given program type.
--   Key: the fully qualified surface name the user writes in source
--   (e.g. @IO.Stdout.print@); value: the surface type the typechecker
--   installs for that name. Empty for program types that have no
--   platform effects of their own.
platformTable :: ProgramType -> Map QName Type'
platformTable = \case
  ProgramCli -> cliPlatformTable
