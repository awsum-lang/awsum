-- | Editor-facing diagnostic representation.
--
-- The unit of feedback the compiler emits to consumers (CLI @--json@,
-- @awsum-vscode@, future LSP). Mirrors 'vscode.Diagnostic' +
-- 'vscode.CodeAction' so producing JSON is the only translation needed.
-- Separates 'TypeError'/'Warning' producers (semantic) from JSON
-- rendering (here), so editors can evolve without touching the
-- typechecker.
module Awsum.Diagnostic
  ( Severity (..),
    Diagnostic (..),
    Fix (..),
    Edit (..),
    diagnosticsToJson,
    severityText,
    parseErrorToDiagnostic,
    typeErrorToDiagnostic,
    warningToDiagnostic,
  )
where

import Awsum.Syntax (SrcSpan (..))
import Awsum.Typing (TypeError (..), Warning (..), prettyPrintTypeError, typeErrorSpan)
import Data.Text qualified as T
import Relude

-- | How prominently the editor should render the diagnostic.
--   @SevError@ is red and (with @--strict@) blocks compilation;
--   @SevWarning@ is yellow / theme-dependent and informational.
data Severity = SevError | SevWarning
  deriving stock (Show, Eq)

-- | One source-located, severity-tagged message — possibly with quick-fixes.
data Diagnostic = Diagnostic
  { diagSeverity :: Severity,
    diagSpan :: SrcSpan,
    diagMessage :: Text,
    diagFixes :: [Fix]
  }
  deriving stock (Show, Eq)

-- | A named quick-fix. The editor presents @fixTitle@ in the lightbulb menu;
--   selecting it applies every edit in @fixEdits@ atomically.
data Fix = Fix
  { fixTitle :: Text,
    fixEdits :: [Edit]
  }
  deriving stock (Show, Eq)

-- | A single text replacement.
data Edit = Edit
  { editSpan :: SrcSpan,
    editNewText :: Text
  }
  deriving stock (Show, Eq)

-- | Render the textual tag for a severity (@"error"@ / @"warning"@).
severityText :: Severity -> Text
severityText = \case
  SevError -> "error"
  SevWarning -> "warning"

-- | Render diagnostics as a JSON array. Hand-written (no aeson dependency)
--   so the compiler stays free of heavyweight deps.
diagnosticsToJson :: [Diagnostic] -> Text
diagnosticsToJson ds = "[" <> T.intercalate "," (map diagToJson ds) <> "]"

diagToJson :: Diagnostic -> Text
diagToJson (Diagnostic sev sp msg fixes) =
  "{"
    <> T.intercalate
      ","
      [ "\"severity\":" <> jsonString (severityText sev),
        rangeFields sp,
        "\"message\":" <> jsonString msg,
        "\"fixes\":" <> fixesToJson fixes
      ]
    <> "}"

fixesToJson :: [Fix] -> Text
fixesToJson fs = "[" <> T.intercalate "," (map fixToJson fs) <> "]"

fixToJson :: Fix -> Text
fixToJson (Fix title edits) =
  "{"
    <> "\"title\":"
    <> jsonString title
    <> ",\"edits\":["
    <> T.intercalate "," (map editToJson edits)
    <> "]}"

editToJson :: Edit -> Text
editToJson (Edit sp newText) =
  "{" <> rangeFields sp <> ",\"newText\":" <> jsonString newText <> "}"

-- | The four position fields, formatted as a JSON object body (no braces).
--   Shared between top-level diagnostics and nested edits.
rangeFields :: SrcSpan -> Text
rangeFields (SrcSpan sl sc el ec) =
  "\"startLine\":"
    <> show sl
    <> ",\"startCol\":"
    <> show sc
    <> ",\"endLine\":"
    <> show el
    <> ",\"endCol\":"
    <> show ec

jsonString :: Text -> Text
jsonString t = "\"" <> T.concatMap escapeJsonChar t <> "\""

escapeJsonChar :: Char -> Text
escapeJsonChar = \case
  '"' -> "\\\""
  '\\' -> "\\\\"
  '\n' -> "\\n"
  '\r' -> "\\r"
  '\t' -> "\\t"
  c -> one c

-- ════════════════════════════════════════════════════════════════════════════
-- Lifters: TypeError / Warning / parse error → Diagnostic
-- ════════════════════════════════════════════════════════════════════════════

-- | Lift a Megaparsec-derived parse error tuple into a 'Diagnostic'.
parseErrorToDiagnostic :: (SrcSpan, Text) -> Diagnostic
parseErrorToDiagnostic (sp, msg) = Diagnostic SevError sp msg []

-- | Lift a typechecker error into a 'Diagnostic'. Some errors carry
--   the spans needed to compute a meaningful quick-fix (e.g. matching an
--   ignored constructor); the rest produce no fixes.
typeErrorToDiagnostic :: TypeError -> Diagnostic
typeErrorToDiagnostic = \case
  -- Special-case: matching '_C' in a pattern. The error carries both the
  -- pattern site (where '_C' was written) and the type-decl site (where
  -- '_C' was declared). The fix renames both to 'C' atomically so the
  -- file remains type-correct after the edit.
  ReferencingIgnoredConstructor patSp declSp n ->
    let stripped = T.drop 1 n
     in Diagnostic
          { diagSeverity = SevError,
            diagSpan = patSp,
            diagMessage = "Cannot match constructor '" <> n <> "': identifiers starting with '_' are marked as intentionally unused",
            diagFixes =
              [ Fix
                  { fixTitle = "Rename '" <> n <> "' to '" <> stripped <> "' (lift the intentional-unused mark)",
                    fixEdits = [Edit declSp stripped, Edit patSp stripped]
                  }
              ]
          }
  err ->
    let sp = fromMaybe (SrcSpan 1 1 1 1) (typeErrorSpan err)
     in Diagnostic SevError sp (prettyPrintTypeError err) []

-- | Lift a warning into a 'Diagnostic' with severity @warning@ and a
--   gentle rename quick-fix.
--
-- We intentionally offer /only/ the @_name@ rename (not a bare @_@
-- replacement). The rename is the most conservative edit possible — it
-- preserves the identifier so future renames-back are trivial, and never
-- loses information. That consistency lets a future "apply all
-- suggestions" action touch unused bindings without second-guessing.
warningToDiagnostic :: Warning -> Diagnostic
warningToDiagnostic = \case
  UnusedParameter sp n ->
    Diagnostic
      { diagSeverity = SevWarning,
        diagSpan = sp,
        diagMessage = "Unused parameter: '" <> n <> "'",
        diagFixes =
          [ Fix
              { fixTitle = "Rename '" <> n <> "' to '_" <> n <> "'",
                fixEdits = [Edit sp ("_" <> n)]
              }
          ]
      }
  UnusedTopLevel defSp mSigSp n ->
    Diagnostic
      { diagSeverity = SevWarning,
        diagSpan = defSp,
        diagMessage = "Unused top-level definition: '" <> n <> "'",
        diagFixes =
          [ Fix
              { fixTitle = "Rename '" <> n <> "' to '_" <> n <> "'",
                -- Rename both the signature and the definition so the
                -- file stays type-correct after the fix is applied.
                -- The sig span is optional because a FunDef without a
                -- matching Sig is already a (different) compile error,
                -- but if someone ever wires in orphan defs the fix still
                -- makes sense for just the def.
                fixEdits =
                  maybe [] (\sp -> [Edit sp ("_" <> n)]) mSigSp
                    <> [Edit defSp ("_" <> n)]
              }
          ]
      }
  UnusedTypeParameter sp n ->
    Diagnostic
      { diagSeverity = SevWarning,
        diagSpan = sp,
        diagMessage = "Unused type parameter: '" <> n <> "'",
        diagFixes =
          [ Fix
              { fixTitle = "Rename '" <> n <> "' to '_" <> n <> "'",
                -- Only the declaration site needs editing: if the
                -- parameter had been referenced anywhere, the warning
                -- wouldn't fire in the first place.
                fixEdits = [Edit sp ("_" <> n)]
              }
          ]
      }
