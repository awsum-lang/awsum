# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Language**

  - Sum types (`type Color = Red | Green | Blue`) and exhaustive `case`/`of` pattern matching.
  - Underscore convention for intentionally-unused bindings at every level: values (`_x`), function params (`main _input = …`), pattern binders (`Box _v ->`), top-level defs (`_helper`), type parameters (`type Phantom _tag`), type names (`type _A`) and constructors (`type A = _B | C`). Referencing any `_`-prefixed name is a compile error (`ReferencingIgnored…` family) — the opt-out is enforced.
  - Bare `_` wildcards in pattern / function-param position — introduce no binding, so multiple `_` don't collide. Rejected as a nameable declaration (top-level, type, constructor, type-param).
  - Shadowing is now a compile error at every binding site (was a silent behaviour before).

- **Compiler**

  - Source positions (`SrcSpan`) tracked through the entire pipeline — error messages now include line and column numbers.
  - `awsum check --json` outputs structured diagnostics with `severity` (`"error"` | `"warning"`) and `fixes` (array of `{title, edits}`) fields. Parse-time, type-time, and warning diagnostics share one shape.
  - `awsum check --strict` escalates warnings to a non-zero exit code for CI.
  - Warnings with rename-to-`_name` quick-fixes: `UnusedParameter`, `UnusedTopLevel` (unreachable from `main`, reports only the source-SCC roots), `UnusedTypeParameter`.
  - New error family for the underscore convention: `ReferencingIgnored`, `ReferencingIgnoredTypeVar`, `ReferencingIgnoredConstructor`, `UnnamedType`, `UnnamedConstructor`, `UnnamedTypeParameter`, `DuplicateTypeParameter`.
  - Per-identifier source spans on function params, type parameters, constructor declarations, and constructor patterns — enables precise caret placement and minimal-edit quick-fixes.
  - New module `Awsum.Diagnostic` centralises severity/fix/edit types and JSON encoding.

- **Editor support**

  - VSCode extension shows inline error diagnostics (red) and warnings (yellow, theme-aware) on open, save, and as-you-type with debounce.
  - `AwsumCodeActionProvider` surfaces compiler-supplied quick-fixes as lightbulb actions. No language-aware logic in the extension — edits come straight from the diagnostic payload.
  - TextMate grammar updated to highlight `_`-prefixed identifiers in declaration sites (`_A`, `_B`, `_tag`, `_foo`, `_input`).

## [0.0.1] - 2025-09-11

### Added

- **Language**

  - Line and block comments as top-level items (preserved in round-trips).
  - Trailing inline comments (`-- …`) after signatures/definitions are preserved.
  - String literals with escapes: `\n \t \r \" \\ \0`.
  - Qualified names (`IO.Stdout.print`) and imports.
  - String concatenation
  - Function declaration
  - `String` arguments
  - `print` effect

- **Backends**

  - JS backend
  - Lua backend

- **CLI**

  - `--version` / `-V` prints compiler version.
  - Commands: `check`, `build`, `run`, `ast`, `core`, `format`.

- **Formatter**

  - Stable pretty-printer: separates top-level blocks with a blank line,
    keeps a signature attached to the following definition, ensures trailing newline.

- **Documentation**

  - EBNF grammar at `docs/spec/grammar.ebnf` (applies to current release).

- **Editor support**

  - TextMate grammar (`source.awsum`) for `*.aww` with robust string handling
    (non-escaped quote termination, escape highlighting).

[0.0.1]: https://github.com/awsum-lang/awsum/releases/tag/v0.0.1
