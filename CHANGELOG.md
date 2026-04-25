# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Tag-driven release workflow** — pushing a `v*` tag triggers `release.yml`, which reuses `check-and-build.yml` (new opt-in `upload-artifacts` input) to produce binaries for all four host platforms, packages them as `awsum-<version>-<target>.tar.gz` (Unix) / `awsum-<version>-<target>.zip` (Windows) plus a `SHA256SUMS` file, and publishes them as a GitHub Release pinned to the tagged commit. Asset names embed the version because the website always links to a specific release — the GitHub `latest/download/` redirect is deliberately not used. No `workflow_dispatch` — the tag is the only source of truth.

- **Cross-platform CI** — `check-and-build.yml` now runs on four OS / architecture combinations (was Linux x86_64 only): `ubuntu-24.04` (x86_64), `ubuntu-24.04-arm` (aarch64), `macos-15` (Apple Silicon), `windows-2025` (x86_64). `fail-fast: false`, per-arch cache keys, `STACK_ROOT` pinned to a workspace-relative path so caching works identically on every OS, runner OS versions pinned (no `*-latest`).

- **Toolchain versions pinned to the documented floor on every runner** — LLVM 15.0.7 (apt `clang-15` + `/usr/local/bin` symlink on Linux, `brew install llvm@15` with PATH prepend on macOS, official LLVM Windows installer silent-extracted into a pristine directory on Windows; verify-step fails CI loudly if `clang --version` doesn't report 15.x), Java 8 Zulu (lowest JDK installable on macOS ARM64 via `actions/setup-java`), Lua 5.1.5 (LuaBinaries direct download on Windows, `leafo/gh-actions-lua` elsewhere), Stack 3.9.1 (manual upgrades). On Windows the test harness's `clang` is routed via a project-root symlink to LLVM 15 — Stack would otherwise prepend GHC's bundled mingw clang (LLVM 14-era) to the child process PATH and shadow the install.

- **Supported host platforms documented in README** — a new table next to **Targets** lists OS / architecture / platform identifier / GitHub runner. Platform identifiers (`linux-x86_64-gnu`, `linux-aarch64-gnu`, `macos-aarch64`, `windows-x86_64`) double as the suffix in future release-asset filenames; Linux keeps `-gnu` to leave room for a future `-musl` build alongside, macOS / Windows have a single ABI per OS in our build pipeline so no suffix is needed.

- **`.gitattributes` forces LF on all text files** — Windows checkouts with default `core.autocrlf=true` were silently turning `.aww` sources, `stdlib/Prelude.aww` (embedded into the binary via `file-embed` at compile time), and `.snapshots/**` golden files into CRLF. That broke the parser's column tracker (Megaparsec counts `\r` as a column increment) and the byte-for-byte golden-snapshot matcher. Single rule `* text=auto eol=lf` covers every text extension uniformly.

## [0.0.2] - 2026-04-24

### Added

- **Language**
  - Sum types (`type Color = Red | Green | Blue`) and exhaustive `case`/`of` pattern matching.
  - Parametric sum types (`type Lookup a = Found a | NotFound`) with polymorphic type parameters.
  - Empty / uninhabited types (`type Never`) with uninhabited-type detection in the typechecker.
  - Integer types: `Int32` (signed 32-bit) and `UInt8` (unsigned 8-bit).
  - Integer literals with compile-time range validation against the declared type.
  - No-defaulting rule: the compiler never picks a type for the user — not for integer literals, not for any other ambiguous context. Ambiguous = compile error, fix with an explicit annotation.
  - Constructors are first-class — passable to HOFs via automatic eta-expansion into `$con$`-prefixed wrapper functions (tree-shaken if unused).
  - Underscore convention for intentionally-unused bindings at every level: values (`_x`), function params (`main _input = …`), pattern binders (`Box _v ->`), top-level defs (`_helper`), type parameters (`type Phantom _tag`), type names (`type _A`) and constructors (`type A = _B | C`). Referencing any `_`-prefixed name is a compile error (`ReferencingIgnored…` family) — the opt-out is enforced.
  - Bare `_` wildcards in pattern / function-param position — introduce no binding, so multiple `_` don't collide. Rejected as a nameable declaration (top-level, type, constructor, type-param).
  - Shadowing is now a compile error at every binding site (was a silent behaviour before).

- **Prelude** (implicitly imported — no `import` needed)
  - Bundled prelude compiled into the binary via `file-embed`; user programs see its declarations without an `import` line. Unused entries are dropped by reachability-based tree-shake from `main`.
  - Types: `Bool` (`True` | `False`), `Either a b` (`Left` | `Right`), `Maybe a` (`Just` | `Nothing`), `Unit`, `UnderflowError`, `OverflowError`.
  - Bool operators: `not`, `and`, `or`.
  - String concat: `(++) : String -> String -> String`.
  - Show functions: `showInt32`, `showUInt8`, `showUnderflowError`, `showOverflowError`.
  - Honest arithmetic: `predInt32` / `succInt32 : Int32 -> Either {Underflow,Overflow}Error Int32`; same shape for `UInt8`. The `Either` wrapping is mandatory — overflow/underflow cannot silently wrap.
  - Equality: `eqInt32 : Int32 -> Int32 -> Bool`, `eqUInt8 : UInt8 -> UInt8 -> Bool`.
  - `BuiltIn.foo` reserved syntax — per-target compiler implementation escape hatch behind prelude-visible names.

- **Backends** (four new targets)
  - **LLVM** — native binary via Clang (LLVM 15+ for opaque-pointer support).
  - **JVM** — Java 7+ bytecode generated directly (no Jasmin / javac dependency); ships a built-in `.class` assembler (`Awsum.Codegen.JVM.Assemble`).
  - **CLR** — .NET 9+ `.dll` generated directly as a PE file (no ilasm / csc).
  - **WASM** — WebAssembly with WASI preview 1 (tested against wasmtime); ships a WAT assembler for `.wasm` binaries.
  - Cross-backend equivalence is a compiler invariant: every successful test asserts byte-for-byte identical stdout across LLVM, JVM, CLR, WASM, JS, and Lua.

- **Stack-safe recursion**
  - Three-pass Core-to-Core pipeline that normalises every recursion shape into a loop on every backend:
    - `Awsum.Scc` — merges mutual recursion into self-recursion via Tarjan SCC + sum-tag dispatch.
    - `Awsum.Cps` — rewrites non-tail self-recursion into tail-self through a defunctionalised K chain.
    - `Awsum.Tco` — folds the remaining self-tail-calls into `CLoop` / `CContinue`.
  - Self, mutual, and non-tail recursion all run in bounded stack on all six backends — including JVM and JS, which have no native cross-method tail calls.
  - 1 000 000-iteration stress tests per recursion shape per backend.
  - `Awsum.StackSafety` rejects mutually-recursive top-level values (no fixed point) with a dedicated diagnostic before the merge pass runs.

- **Platform effects**
  - `--program-type cli` flag introduced; mandatory for any command that goes through the typechecker.
  - Qualified effect names (`IO.Stdout.print : String -> IOUnit`) — a CLI-program platform effect requiring both `--program-type cli` and `import IO.Stdout`.
  - `Awsum.Program.platformTable` dispatch ready to host `ProgramBrowser` / `ProgramModule` without touching existing modules.

- **Compiler**
  - Source positions (`SrcSpan`) tracked through the entire pipeline — error messages now include line and column numbers with clickable terminal links.
  - `awsum check --json` outputs structured diagnostics with `severity` (`"error"` | `"warning"`) and `fixes` (array of `{title, edits}`) fields. Parse-time, type-time, and warning diagnostics share one shape.
  - `awsum check --strict` escalates warnings to a non-zero exit code for CI.
  - Warnings with rename-to-`_name` quick-fixes: `UnusedParameter`, `UnusedTopLevel` (unreachable from `main`, reports only the source-SCC roots), `UnusedTypeParameter`.
  - New error family for the underscore convention: `ReferencingIgnored`, `ReferencingIgnoredTypeVar`, `ReferencingIgnoredConstructor`, `UnnamedType`, `UnnamedConstructor`, `UnnamedTypeParameter`, `DuplicateTypeParameter`.
  - Unreachable case arms produce an error (`UnreachableCase`).
  - Per-identifier source spans on function params, type parameters, constructor declarations, and constructor patterns — enables precise caret placement and minimal-edit quick-fixes.
  - New module `Awsum.Diagnostic` centralises severity/fix/edit types and JSON encoding.
  - Reachability-based tree-shake from `main` over all top-level Core decls (user, prelude, generated constructor wrappers) — unused prelude entries never reach codegen.

- **CLI**
  - `awsum core FILE --program-type cli` — print elaborated/lowered Core IR.
  - `awsum asm FILE -t {jvm|clr|wasm}` — print target assembly text (Jasmin-like / CIL / WAT).
  - `awsum symbols FILE --json` — emit an LSP-style `DocumentSymbol` array for Outline view and workspace symbol search.
  - `awsum run --input TEXT` / `awsum run --stdin` for passing input to `main`.

- **Documentation**
  - `docs/prelude.md` — Prelude + BuiltIn architecture design doc.
  - `docs/recursion.md` — stack-safe recursion pipeline walkthrough.
  - `docs/targets.md` — per-backend implementation details.
  - `docs/platform-version-policy.md` — which runtime versions each backend targets and why.

- **Testing**
  - Cross-backend equivalence tests: each `test/sources/successful/NAME/` is compiled to all six backends and asserted to produce identical stdout.
  - Golden snapshots per pipeline stage (AST, Core IR, formatted source, per-backend output text, runtime output).
  - Auto-detection of tests — adding a new test program in `test/sources/successful/` is enough; no registration required.
  - Error snapshot tests: `test/sources/errors/` with JSON diagnostics as the golden.

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

[0.0.1]: https://github.com/awsum-lang/awsum/releases/tag/v0.0.1
