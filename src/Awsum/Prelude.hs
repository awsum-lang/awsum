{-# LANGUAGE TemplateHaskell #-}

-- | The Awsum standard prelude.
--
-- @stdlib/Prelude.aww@ is a regular Awsum module shipped with the compiler
-- and injected implicitly into every user compilation via 'withPrelude'.
-- It defines the prelude-visible types and the signatures that delegate to
-- the compiler's built-in table (see @docs/prelude.md@ for the
-- architectural rationale).
--
-- The source is embedded at compile time via @file-embed@ so the compiler
-- binary stays self-contained — no filesystem lookup at runtime, no risk
-- of a mismatched on-disk copy.
module Awsum.Prelude
  ( preludeSource,
    preludeProgram,
    preludeDefNames,
    verifyPrelude,
    withPrelude,
    stripPreludeWarnings,
  )
where

import Awsum.Parser (parseProgram)
import Awsum.Program (ProgramType)
import Awsum.Syntax (Decl (..), Name, Program (..))
import Awsum.Typing (TypeError, Warning (..), typecheckProgram)
import Data.FileEmbed (embedStringFile)
import Data.Set qualified as S
import Relude

-- | Raw source text of the bundled @Prelude.aww@.
preludeSource :: Text
preludeSource = toText ($(embedStringFile "stdlib/Prelude.aww") :: String)

-- | Parsed prelude. A parse failure here is an internal compiler error —
--   the prelude is part of the compiler distribution, not user input.
preludeProgram :: Program
preludeProgram = case parseProgram preludeSource of
  Right p -> p
  Left err ->
    error
      $ "Internal compiler error: stdlib/Prelude.aww failed to parse: "
      <> err

-- | Typecheck the bundled prelude. Exposed so CLI commands can surface
--   a clean diagnostic if the shipped prelude is broken. Result is
--   program-type-independent; the parameter is taken for uniform
--   plumbing with 'typecheckProgram'.
verifyPrelude :: ProgramType -> Either TypeError [Warning]
verifyPrelude progType = typecheckProgram progType S.empty preludeProgram

-- | Prepend the bundled prelude's imports and declarations to a user
--   program — the \"implicit @import Prelude@\". Downstream passes see
--   a single combined module.
--
--   Idempotent: when the incoming program /is/ the prelude (e.g.
--   @awsum check stdlib/Prelude.aww@ during compiler development), it
--   is returned unchanged. Otherwise a self-prepend would surface as
--   spurious duplicate-signature errors.
withPrelude :: Program -> Program
withPrelude userProg
  | userProg == preludeProgram = userProg
  | otherwise =
      Program
        { -- Keep the user's module comment; the prelude is an implicit
          -- prepend and its own header is an implementation detail.
          moduleComment = userProg.moduleComment,
          imports = preludeProgram.imports <> userProg.imports,
          decls = preludeProgram.decls <> userProg.decls
        }

-- | Top-level names defined in the bundled prelude. Used to strip
--   spurious \"unused top-level\" warnings — the prelude sits in scope
--   ready to be used, not every program uses every entry.
preludeDefNames :: Set Name
preludeDefNames =
  S.fromList
    [ n
    | decl <- toList preludeProgram.decls,
      n <- case decl of
        FunDef _ name _ _ _ -> [name]
        Sig _ name _ _ -> [name]
        _ -> []
    ]

-- | Drop warnings whose target is a prelude-defined name. Applied at the
--   boundary (CLI, LSP-facing test spec) so user-visible diagnostics are
--   about user code only, not about the prelude plumbing.
stripPreludeWarnings :: [Warning] -> [Warning]
stripPreludeWarnings = filter (not . aboutPrelude)
  where
    aboutPrelude = \case
      UnusedTopLevel _ _ n -> S.member n preludeDefNames
      UnusedParameter _ _ -> False
      UnusedTypeParameter _ _ -> False
