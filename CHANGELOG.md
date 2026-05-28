# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Until `1.0.0`, this project does not follow SemVer. Every release increments only the patch (`0.0.1 → 0.0.2 → 0.0.3 …`). Any release can break the surface language, the CLI, or the JSON shapes; entries below don't separately flag "breaking" because the assumption is "anything might be". The narrower contract that does hold: within a single version, all first-party tooling — `awsum`, `awsum-vscode`, `awsum-zed`, `tree-sitter-awsum` — ships from the same version number and is mutually compatible. SemVer kicks in at `1.0.0`.

## [Unreleased]

### Added

- **Expression-level type ascription `(e : T)`.** Pins the type of an expression at the use site without a separate `let` or signature. Symmetric to the existing pattern-form `(p : T)`: in both, `: T` asserts "value at this node has type `T`"; in pattern position the form also binds. Useful where bidirectional inference has too little context — `identity (42 : Int32)`, `pureEither (10 : Int32)`. Erased at lowering (no runtime cost; no Core node).
- **Permutation-aware `CReuse` elision + linear binder elision in LLVM codegen.** Extends the existing self-move elision in `CReuse` to cover the case where an arm-binder moves to a different slot of the same cell (e.g. `Cons x xs → CContinue [xs, CReuse "lst" 24 [$k, x]]` in `$cps$clone` — `x` moves from slot 1 to slot 2). For arm-binders whose only use is a `CReuse` field of the same scrut (computed via `Awsum.Lifetime.elidableArmBinders`), codegen now skips: the inc-on-extract at case match, the dec-via-`CDrop` at arm end, the dec-old of the binder's old slot, and the inc-new of its new slot — the store at the new slot still emits (for permutation-move) or is skipped (for self-move). Modest wall improvements (~5-6%) on `CReuse`-heavy benchmarks (`gc_pressure_clone`, `list_reverse_repeat`); WASM not modified in this pass.
- **Reject user-code references to prelude-private names.** The five constructors of `type IO` (`IOPure`, `IOFail`, `IOStdoutPrint`, `IOGetArgs`, `IOStdinReadAll`) and the runtime walker `runIO` now produce a compile error when mentioned in user source — in expression position, in patterns, anywhere. Reason: Awsum has no catch-all on `case`, so each new platform-effect constructor added to `IO` would otherwise be a breaking change for any user program that wrote `case io of …`. The forbidden set is derived from the parsed prelude at compile time (auto-grows when `IO` gains a constructor); the diagnostic is uniform — `Name 'X' is reserved by the standard library and cannot be referenced from user code` — and the check runs before typecheck so violations appear ahead of any cascading "unbound name" errors. Temporary until modules ship, at which point the same names move into a privileged module and the diagnostic migrates to the standard "not exported" path.
- **`IO.Stdin.readAll : IO (StringTooLong | UnpairedUtf16Surrogate) String`** — CLI platform built-in that reads stdin to EOF in the IO chain. POSIX-honest semantics: each call consumes whatever bytes remain on fd 0, so a second call after EOF decodes to `Right ""`. Same error row as `IO.Args.getArgs` — decoding failures (length cap, unpaired UTF-16 surrogate) compose through `handleErrorIO`. Per-backend implementation reads raw bytes (`read(2)` on LLVM, `System.in.read` on JVM, `Console.OpenStandardInput` + `StreamReader` on CLR, WASI `fd_read` on WASM, `fs.readFileSync(0)` on JS) and decodes UTF-8 in the runtime, bypassing host argv decoders.
- **Doc comments.** A `--` line or `{- … -}` block touching the next top-level declaration with no blank line between becomes its docstring — no Haddock-style `-- |` / `{-| -}` prefix. Stacks freely across mixed `--`/`{- -}` chains; a blank line detaches the comment as a free-floating note. Content is markdown. `awsum format` normalises every attached doc to a single `{- … -}` block, preserving the author's line breaks. Reference: [docs/type-system.md](docs/type-system.md#comments-and-docstrings).
- **Hover (`textDocument/hover`) in `awsum lsp`.** Resolves the cursor against user + prelude decls together, so prelude names (`bindEither`, `mulInt32`, …) surface their docs the same as user-defined ones. Triggers on every name reference: top-level decl heads, `EVar` / `ECon` / `EBuiltIn` in expressions, `TyCon` in signatures and ascriptions, `PCon` in patterns. Constructor names that aren't a decl head fall through to the parent `TypeDecl`'s doc — hover on `Just` surfaces `Maybe`'s doc, which is where the constructor is documented. Hover `range` underlines the name itself, not the enclosing form. Markdown content; every LSP client (`awsum-vscode`, `awsum-zed`, `awsum-intellij`, `awsum-nvim`, `awsum-emacs`) picks it up with no client-side change.
- **Type information in hover.** The popup now ships the cursor's type alongside the doc — a fenced ` ```awsum ` code block on top, the doc below. Adds hover on /local binders/ that previously had nothing to show: function and lambda parameters, `case`-arm pattern variables, `do`-bind / `do`-let / `let`-bind names. Polymorphic references display both the declared scheme and the call-site-instantiated form, separated by an `Instantiated here:` line — e.g. `bindEither` inside `bindEither op1 (const op2)` shows `Either e1 a -> (a -> Either e2 b) -> Either (e1 | e2) b` alongside `Either ErrA Int32 -> (Int32 -> Either ErrB Int32) -> Either (ErrA | ErrB) Int32`. Monomorphic refs and locals show one block.
- **Balanced nested `{- … -}` capture.** The comment-capture path now balances nested block comments to match the space consumer; `{- {- -} -}` is one comment, not garbage from an early `-}`. An unterminated block at EOF fails with an explicit "unterminated block comment" diagnostic instead of an opaque parse error several lines below the cause.
- **`eqString : String -> String -> Bool`** in the prelude — equality on UTF-16 code-unit sequences.

### Changed

- **`awsum run` now inherits stdin from the parent process.** Previously `--stdin` was a switch that read `awsum`'s own stdin and forwarded it as `argv[1]` — a workaround from before `IO.Stdin.readAll` existed, and mutually exclusive with `--input TEXT`. Now `--input TEXT` covers argv and the child inherits `fd 0` directly: `echo "data" | awsum run … FILE` and `awsum run … FILE < file` reach `IO.Stdin.readAll` verbatim (no buffering, no `T.stripEnd`, byte-exact across all five backends). The two channels are independent and can be used together: `echo "data" | awsum run --input "arg" … FILE` delivers `"arg"` as `argv[1]` and `"data\n"` on stdin simultaneously.
- **Comments and layout no longer affect `awsum build` output or `awsum check` diagnostic text.** Synthetic binder names (`$do_e_N`, `$arg_N`, `$let_w_N`) are minted from a monotonic counter, and type-error messages show `expected x` rather than `expected x$3_12`.
- **Module comment header for `.aww` files.** A single optional `{- … -}` block at the top of a file is now treated as the module comment. Line comments (`-- …`) at the top of a file and multiple block comments in a row are rejected with a parse error: the language never silently attaches text above the first import or declaration. Concrete shapes:
  - **Before** — `{- header -}` glued directly to `import IO.Stdout` on the next line, or `-- header …` (often multi-line) before `import` / a top-level decl.
  - **After** — a single `{- header -}` block, then `import …` or the first declaration. The canonical form has one blank line between the header and the next line; the parser accepts both with and without the blank line, and `awsum format` normalises to the form with one. Other shapes (`-- header`, two `{- a -} {- b -}` in a row) are syntax errors.

  Leading comments on the first import are no longer accepted — they were ambiguous with module-comment material; subsequent imports may still carry leading comments (the "`-- import IO.X`" commented-out-import pattern between live imports). AST: `Program` gains a `moduleComment :: Maybe Text` field.

### Deprecated

### Removed

- **`awsum run --stdin`** — superseded by stdin inheritance (see Changed above). Migration: `echo … | awsum run … --stdin FILE` becomes `echo … | awsum run … FILE` (drop the flag); `awsum run … --stdin FILE < input.txt` becomes `awsum run … FILE < input.txt`.

### Fixed

- **Top-level definition whose body is a bare lambda.** `f : Int32 -> Int32; f = \n -> n` (and curried / multi-param variants) used to be accepted by the typechecker but rejected at lowering with an internal `lambda has no expected type at lowering` error — the elaborator's zero-LHS path passed `Nothing` as the expected type, so `liftLambda` had no arrow to split. The elaborator now eta-contracts a top-level `ELam`-body into the `FunDef`'s LHS before lowering: `f = \n -> n` produces the same Core as `f n = n` (one `CFunDef`, no `$lam$N` helper). Curried forms (`\a -> \b -> body`) peel recursively. A non-lambda body that contains a nested `ELam` deeper down (e.g. in a `case` arm) now also receives the signature type as expected, so it goes through `liftLambda` correctly instead of dead-ending.
- **`UnusedTopLevel` false negative for short top-level names.** `freeNames` failed to subtract pattern-bound names from each `case`-alternative body, and the call-graph construction failed to subtract a top-level definition's own parameters. The combination silently masked any user-level top-level whose name happened to match a single-letter binder used inside a prelude case-alt (`Right a -> k a`, `Left e -> Left e`, …) or a prelude parameter (`(++) a b = …`). Both leaks are fixed; one-letter unused top-levels now warn correctly.
- **LLVM and WASM heap leak on every reference to a top-level `CValDef`.** The codegens were treating `CVar` references to top-level value definitions (e.g. `zero : Int32; zero = 0`) the same as borrowed-local CVars — emitting `__inc_ref` over the result. But each such reference lowers to `call @v_name()` which already allocates a fresh `+1` cell. The spurious inc left every referenced cell at refcount `1` forever, leaking once per reference in a hot loop. With the fix, peak RSS on `unused_case_binder_repeat` drops from 155 MiB to 2 MiB; on `mutual_three_way_repeat` from 1.5 GiB to 1.6 MiB. JVM/CLR/JS unaffected (host GC).
- **String property tests on Windows × JVM.** The 5 string-touching properties (`concat-left-identity`, `concat-right-identity`, `concat-associative`, `lengths-three-functions`, `concat-length-additive`) previously diverged on Windows × JVM because the JVM startup decoder (`sun.jnu.encoding`) mangled supplementary-plane characters in `argv[1]` before they reached user code. Property tests now feed input via `IO.Stdin.readAll`; stdin bypasses the startup decoder, so the round-trip is byte-clean on every host. The cross-backend assertion runs on every cell now — the Known Issue from 0.0.4 is closed.
- **LLVM Windows × MSVC CRT `\n` → `\r\n` translation on stdout.** The MSVC CRT opens fd 0/1/2 in text mode by default, so `write(1, …)` calls (used by the LLVM backend's `__print` runtime helper) silently doubled every `\n` into `\r\n` on output — breaking the cross-target "identical stdout" invariant. Latent since the LLVM Windows footer was added; only surfaced now that `IO.Stdin.readAll` lets `\n`-bearing input reach the program (`CommandLineToArgvW` had been stripping the same byte from argv). The Windows entry point now calls `_setmode(1, _O_BINARY)` and `_setmode(0, _O_BINARY)` before any IO, forcing stdin and stdout into binary mode regardless of CRT defaults. No effect on the POSIX footer (the call is Windows-only).

### Security

## [0.0.4] - 2026-05-12

### Added

- **Heap reclamation on LLVM and WASM** via compiler-emitted reference counting; JVM/CLR/JS continue to rely on managed GC. Cross-backend stdout stays identical.
- **`awsum lsp --stdio`** — Language Server Protocol over stdio: document sync, `publishDiagnostics`, `codeAction`, `formatting`, `documentSymbol`, `workspace/symbol`. Opt-in lockstep version check via `initializationOptions`.
- **`andThenEither` / `andThenIO`** in prelude — flipped-argument forms of `bindEither` / `bindIO` for `|>` chains.
- **`handleErrorIO : (e1 -> IO e2 a) -> IO e1 a -> IO e2 a`** — function-first sibling of `mapIOError`. `e2` may be `Never`, a partial row, or a renamed row.
- **`failIO : e -> IO e a`** — error-side mirror of `pureIO`.
- **`empty type X` declaration form.** Uninhabited types whose row tag collapses to `_empty`, so any `empty type` value flows into any row position without a wrapper. The prelude's `Never` is now `empty type Never`.
- **`type BrokenPipe = BrokenPipe`** in prelude — placeholder for the eventual `IO.Stdout.print : String -> IO BrokenPipe Unit` signature.
- **`|>` left-pipe operator** — `x |> f` is syntax for `f x`. Left-associative, lowest precedence (`++` binds tighter). Not a referenceable name; the parser rejects `(|>)`.
- **Thousands separator `_` in decimal integer literals** — `1_234_567`, `-1_000_000`. Forbidden positions: leading, trailing, two consecutive, immediately after the sign. The formatter canonicalises every literal to groups of 3 from the right.
- **Type `UInt32`** — unsigned 32-bit integer with literal range validation. Built-ins `showUInt32`, `predUInt32`, `succUInt32`, `eqUInt32`, `addUInt32`, `subUInt32`, `mulUInt32`, `parseUInt32`; prelude `minUInt32`, `maxUInt32`. Honest arithmetic returning `Either OverflowError UInt32` (add/mul/succ) and `Either UnderflowError UInt32` (sub/pred).
- **`(++) : String -> String -> Either StringTooLong String`** — concatenation reports overflow through an error channel instead of silently truncating. New sentinel types in prelude: `StringTooLong`, `UnpairedUtf16Surrogate`.
- **`maxStringLengthUtf16CodeUnits : UInt32`** in prelude — `2^27 = 134_217_728`, the language-fixed maximum string length, identical on every backend.
- **Compile-time string-literal length check** — literals exceeding `maxStringLengthUtf16CodeUnits` are rejected with `StringLiteralTooLong`.
- **Closures in constructor fields, case-arm-binders, and partial applications now compile** on every backend.
- **`IO.Args.getArgs : IO (StringTooLong | UnpairedUtf16Surrogate) String`** — CLI platform built-in that reads the command-line argument from inside the IO chain. Decoding failures (length cap, unpaired UTF-16 surrogate) live in the IO error row and compose with `handleErrorIO`.
- **`awsum-bench` executable + `just benchmark TEST [TIMEOUT]` recipe.** Drives a single program through every backend and prints wall-clock time, peak RSS, exit status, and trimmed stdout. Default timeout 60s. macOS-only at the moment.
- **`awsum-stats` / `just stat-linearity` recipe** — counts how many times each locally-introduced binder is referenced inside its scope; per-program snapshot.

### Changed

- **`main` signature is `IO Never Unit`** (no parameter). Programs read the entry-point argument via `IO.Args.getArgs`.
- **`IO` is now `IO e a`** — gains an explicit error-row parameter, mirroring `Either e a`.
- **Lazy IO.** `IO e a` is now a sum type in the prelude; `IO.Stdout.print "x"` builds a description, not a side effect. Only the IO returned from `main` runs.
- **`bindIO` / `pureIO` / `mapIO` / `mapIOError`** in prelude — IO compositors mirroring `Either`.
- **`IOUnit` renamed to `IO Unit`** (`IO` is now a unary type constructor).
- **`type Never`** in prelude — empty type, no constructors.
- **Signed `Int32` arithmetic** returns `Either (UnderflowError | OverflowError) Int32`; nominal `ArithError` removed.
- **Prelude additions** — `Tuple2`, `Tuple3`, `parseInt32`, `parseUInt8`, `splitOnFirst`, `addInt32`, `addUInt8`, `subInt32`, `subUInt8`, `negInt32`, `mulInt32`, `mulUInt8`, range constants `minInt32` / `maxInt32` / `minUInt8` / `maxUInt8`; new types `ParseError`, `UnderflowError`, `OverflowError`.
- **Three explicit string-length functions** — `lengthCodePoints`, `lengthUtf16CodeUnits`, `lengthUtf8Bytes`, all `String -> UInt32`. No `length` alias.
- **LLVM and WASM strings are length-prefixed** — `lengthUtf8Bytes` and `lengthUtf16CodeUnits` are O(1); strings with embedded NUL no longer truncate output.
- **Structural sums `T1 | T2`** — closed anonymous unions; `(x : T)` ascription patterns for discrimination, exhaustive without catch-all; mixed ascription + constructor arms in one `case`; implicit injection through nominal heads.
- **Closures over outer parameters** — lambdas may reference any enclosing-scope binding.
- **Synthesis form for closed lambdas** — `let id = \x -> x in body` and `(\x -> x) 5` typecheck without annotation. Top-level definitions still require signatures.
- **Lambda syntax `\x -> body`** as a surface form.
- **Hindley-Milner type inference** — two-way unification, occurs check, expected types push down through `case` arms and constructor applications.
- **`do`-notation** for `Either` chains, desugared to nested `case`.
- **`let` bindings** (standalone and in `do`); RHS evaluated once. Optional `let n : T = e` ascription. Haskell-style multi-line layout in the formatter.
- **Destructuring patterns** on `<-`, `let` LHS, function/lambda parameters; refutable patterns raise `NonExhaustiveCase`.
- **Recursive exhaustiveness** in nested patterns.
- **Eta-reduced top-level definitions** — `f = g` works for any RHS whose type matches the signature.
- **Cross-module shadow scoping** — same-module shadowing remains an error; cross-module is allowed.
- **Multi-line ADT declarations in `awsum format`** — three or more constructors render across multiple lines; one or two stay on the header line.
- **Multi-line `|>` chains** — chains of two or more `|>` operators format with each operator leading its continuation line.
- **Property-based tests across all backends** (`just test-property`) covering integer arithmetic, succ/pred boundary, equality, parse/show round-trip, string monoid laws, `splitOnFirst`, boolean laws.
- **Symbol visibility tightened** — every backend exposes only the platform-mandated entry point externally.
- **`RowCatchAllPattern` diagnostic** points at the `_` itself, not the surrounding `case` arm.
- **JVM target floor: Java 11 (LTS)** — emitted class file version bumped from 51.0 to 55.0. CI's pinned JDK is now Zulu 11.

### Removed

- **Lua backend** — supported targets are now LLVM/JVM/CLR/WASM/JS.

### Fixed

- **Built-ins passed as function values now compile and run** on every backend — `bindIO io IO.Stdout.print`, `apply showInt32 42`, `let f = showInt32 in f 42` previously crashed at runtime.
- **In-place reuse distributes through nested case scrutinees** — typical merged recursion no longer allocates a fresh constructor cell every iteration.
- **Multi-non-tail-call recursion (`mirror`-style, `sumTree`-style) compiles stack-safely** on every backend.
- **Row-tag dispatch on case-binders** whose source type can't be synthesised — e.g. `(UnderflowError | StringTooLong)` previously always dispatched as the first label.
- **LLVM `argv[1]` on Windows** now reaches `main` as UTF-8 instead of an ANSI-code-page-mangled string.
- **Non-ASCII string literals** compile correctly on LLVM, JVM, and WASM (previously failed `clang` / `ClassFormatError` / overlapping data sections).
- **JVM** — multiple codegen bugs around deeply nested constructors, row tags > 2¹⁵, slot indices ≥ 256, stackmap frames, and `case`-arm tag slots.
- **CLR** — `InvalidProgramException` on deeply nested constructors.
- **`mergeAlts`** for nominal-headed scrutinees with row-typed fields.
- **Implicit row-injection on call results** — a call returning a sub-row into a wider-row slot is now wrapped correctly; previously crashed JVM dispatch.
- **Bidirectional check** propagates through polymorphic application.
- **`do` / `let` / `in`** reserved at the parser level.
- **Free type variables** in constructor fields are rejected.
- **WASM `__alloc`** traps via `unreachable` when `memory.grow` returns -1; previously hung the program retrying forever.
- **Nested-pattern exhaustiveness** — uninhabited siblings inside a nested pattern were reported as missing.
- **`UnusedTopLevel` false positive** — helpers used solely from a `_name` def aren't flagged as unused.

### Known Issues

- **String properties on Windows (JVM)** — `concat-left-identity`, `concat-right-identity`, `concat-associative`, `lengths-three-functions` diverge from LLVM / CLR / WASM / JS for the JVM backend on Windows. The four unaffected backends keep providing signal.

### Tooling

- **Build provenance** — Sigstore attestations on every release asset.
- **`CONTRIBUTING.md`** — dev-loop commands, signed-commits requirement, PR/CHANGELOG conventions.
- **Second Windows CI axis** — `windows-x86_64-mingw` job runs the suites against a [WinLibs](https://winlibs.com) GCC 14.2.0 + LLVM 19.1.7 + mingw-w64 + UCRT bundle, alongside the existing MSVC LLVM 15.0.7. CI-only; release artifacts continue to ship from the MSVC build.
- **`AWSUM_CLANG`** — optional env var that pins the clang executable path used by `awsum run -t llvm` and the test harness. Empty/unset falls back to PATH.
- **Clang compile-failure messages now include stdout** in addition to stderr, with the exit code.

## [0.0.3] - 2026-04-25

### Added

- **Prelude** — `showUnit : Unit -> String` (returns the literal `"Unit"`). The `Unit` type was already prelude-visible; this fills in the missing stringifier so every prelude type now has a matching `show*`.

- **Tag-driven release workflow** — pushing a `v*` tag triggers `release.yml`, which reuses `check-and-build.yml` (new opt-in `upload-artifacts` input) to produce binaries for all four host platforms, packages them as `awsum-<version>-<target>.tar.gz` (Unix) / `awsum-<version>-<target>.zip` (Windows) plus a `SHA256SUMS` file, and publishes them as a GitHub Release pinned to the tagged commit. Asset names embed the version because the website always links to a specific release — the GitHub `latest/download/` redirect is deliberately not used. No `workflow_dispatch` — the tag is the only source of truth.

- **Cross-platform CI** — `check-and-build.yml` now runs on four OS / architecture combinations (was Linux x86_64 only): `ubuntu-24.04` (x86_64), `ubuntu-24.04-arm` (aarch64), `macos-15` (Apple Silicon), `windows-2025` (x86_64). `fail-fast: false`, per-arch cache keys, `STACK_ROOT` pinned to a workspace-relative path so caching works identically on every OS, runner OS versions pinned (no `*-latest`).

- **Toolchain versions pinned to the documented floor on every runner** — LLVM 15.0.7 (apt `clang-15` + `/usr/local/bin` symlink on Linux, `brew install llvm@15` with PATH prepend on macOS, official LLVM Windows installer silent-extracted into a pristine directory on Windows; verify-step fails CI loudly if `clang --version` doesn't report 15.x), Java 8 Zulu (lowest JDK installable on macOS ARM64 via `actions/setup-java`), Lua 5.1.5 (LuaBinaries direct download on Windows, `leafo/gh-actions-lua` elsewhere), Stack 3.9.1 (manual upgrades). On Windows the test harness's `clang` is routed via a project-root symlink to LLVM 15 — Stack would otherwise prepend GHC's bundled mingw clang (LLVM 14-era) to the child process PATH and shadow the install.

- **Supported host platforms documented in README** — a new table next to **Targets** lists OS / architecture / platform identifier / GitHub runner. Platform identifiers (`linux-x86_64-gnu`, `linux-aarch64-gnu`, `macos-aarch64`, `windows-x86_64`) double as the suffix in future release-asset filenames; Linux keeps `-gnu` to leave room for a future `-musl` build alongside, macOS / Windows have a single ABI per OS in our build pipeline so no suffix is needed.

- **`.gitattributes` forces LF on all text files** — Windows checkouts with default `core.autocrlf=true` were silently turning `.aww` sources, `stdlib/Prelude.aww` (embedded into the binary via `file-embed` at compile time), and `.snapshots/**` golden files into CRLF. That broke the parser's column tracker (Megaparsec counts `\r` as a column increment) and the identical-text golden-snapshot matcher. Single rule `* text=auto eol=lf` covers every text extension uniformly.

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
  - Cross-backend equivalence is a compiler invariant: every successful test asserts identical stdout across LLVM, JVM, CLR, WASM, JS, and Lua.

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
