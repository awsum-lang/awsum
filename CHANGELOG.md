# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
