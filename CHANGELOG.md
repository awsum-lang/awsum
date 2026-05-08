# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **`andThenEither` / `andThenIO` in the prelude** — flipped-argument forms of `bindEither` / `bindIO` for use with `|>`: `value |> andThenEither k` chains `Either`-returning steps left-to-right in execution order without nested lambdas; `andThenIO` does the same for `IO`.
- **`handleErrorIO` in the prelude** — `(e1 -> IO e2 a) -> IO e1 a -> IO e2 a`, function-first sibling of `mapIOError`. Used at the tail of an IO chain (`io |> handleErrorIO h`); `e2` may be `Never` (full recovery), a partial row (re-throw via `failIO`), or a renamed row.
- **`failIO : e -> IO e a` in the prelude** — error-side mirror of `pureIO`. Used inside a `handleErrorIO` handler that closes part of an error row, and to construct failing IO actions in tests.
- **`empty type X` declaration form — explicit row identity.** New `empty` keyword for uninhabited types whose row tag collapses to `_empty`, so any `empty type` value flows into any row position without a wrapper. Plain `type X` stays a regular nominal with a distinct row label. Parser rejects constructors and parameters; typechecker rewrites `TyCon` references into a new `TyEmpty` AST node before unification. The prelude's `Never` is now `empty type Never`, so `IO.Stdout.print : String -> IO Never Unit` composes into any IO chain.
- **`type BrokenPipe = BrokenPipe` in the prelude** — placeholder for the eventual `IO.Stdout.print : String -> IO BrokenPipe Unit` signature. Print currently stays `IO Never Unit`; the type lands now so the signature flip is non-breaking.
- **`|>` left-pipe operator** — `x |> f` is pure syntax for `f x`, lowered in `Awsum.ElaborateLower` directly to `EApp` before any Core-to-Core pass; the resulting Core IR is identical to what the user would have written in the direct-application form, so there is no residual call frame on any of the five backends. Left-associative, lowest precedence — `++` binds tighter (`a ++ b |> f` is `f (a ++ b)`); chains like `x |> f |> g` mean `g (f x)`. The operator is **not** a referenceable name: there is no `(|>)` definition in the prelude and the parser rejects `(|>)` in any name position. A first-class form is deferred until type-class dispatch and a supercompiler can specialise away the wrapper call without runtime cost.
- **Thousands separator `_` in decimal integer literals** — parser accepts `_` between digits (`1_234_567`, `-1_000_000`, `12_34_5_6` all parse as the same integers as `1234567`, `-1000000`, `123456`). Forbidden positions: leading, trailing, two consecutive, immediately after the sign — rejected at parse time. The formatter canonicalises every literal to one shape: groups of 3 from the right, separator starting at 4 digits, sign on the outside (`1234567` → `1_234_567`, `-2000000000` → `-2_000_000_000`, values with 1–3 digits stay bare).
- **Type `UInt32`** — unsigned 32-bit integer with literal range validation (`0..4294967295`); built-ins `showUInt32`, `predUInt32`, `succUInt32`, `eqUInt32`, `addUInt32`, `subUInt32`, `mulUInt32`, `parseUInt32`; prelude entries `minUInt32`, `maxUInt32`. Honest arithmetic with `Either OverflowError UInt32` (add/mul/succ), `Either UnderflowError UInt32` (sub/pred). All five backends produce identical stdout, including high-bit values (≥ 2^31), boundary products `(2^32-1)^2`, and full round-trips via `parseUInt32` / `showUInt32`.
- **`(++) : String -> String -> Either StringTooLong String`** — string concatenation reports overflow through an error channel instead of silently truncating. Each backend's `__concat` runtime helper pre-checks the combined UTF-16 length against `maxStringLengthUtf16CodeUnits` (`2^27 = 134_217_728`) and returns `Left StringTooLong` (no buffer allocated on the rejection path) when the result would overflow. Cross-backend boundary behaviour verified end-to-end on the language-fixed cap by [test/sources/successful/strings_concat-cap-boundary](test/sources/successful/strings_concat-cap-boundary). New sentinel types in Prelude: `type StringTooLong = StringTooLong` and `type UnpairedUtf16Surrogate = UnpairedUtf16Surrogate`.
- **`maxStringLengthUtf16CodeUnits : UInt32`** in the prelude — `2^27 = 134_217_728` UTF-16 code units, the language-fixed maximum string length, identical on every backend. The cap is bounded by WASM-32's linear-memory budget, not by the smallest UTF-16 runtime (V8's `String::kMaxLength = 2^29 − 24` is ~4× higher), so that worst-case UTF-8 expansion (`3×` for BMP CJK content), `(++)` peak (`6×`), and room for multiple concurrent strings plus other program data all fit in 2–3 GiB practical WASM-32. See [docs/targets.md](docs/targets.md) § Maximum string length.
- **Compile-time string-literal length check** — a string literal in `.aww` source whose UTF-16 length exceeds `maxStringLengthUtf16CodeUnits` is rejected by the typechecker with `StringLiteralTooLong sp len`, parallel to `IntLiteralOutOfRange` for numeric literals. Source files always come from a path (CLI never reads them from stdin) and are decoded via strict UTF-8, so unpaired surrogates can't reach a literal — together with the limited escape syntax (`\n \t \r \" \\ \0`, no `\uXXXX`-style numeric escapes), this guarantees every compiled literal is strict UTF-16 by construction. The length check covers the full pipeline through the temp-file path (`readFileTextUtf8` → parse → typecheck), with three Hspec cases asserting the cap-exact ASCII boundary, cap+1 ASCII rejection, and a supplementary code point counting as 2 UTF-16 code units.
- **Snapshot test for string-literal escape sequences** — [test/sources/successful/strings_escapes](test/sources/successful/strings_escapes) prints a literal exercising all six supported escapes `\n \t \r \" \\ \0` and asserts identical bytes across all five backends (the 0x09 / 0x0A / 0x0D / 0x22 / 0x5C / 0x00 output bytes are pinned in the no-stdin golden). The `\0` case in particular verifies that strings are length-prefixed end-to-end on every backend — no NUL-terminator semantics anywhere.

### Changed

- **Multi-line `|>` chains.** A pipe chain of two or more `|>` operators is parsed and formatted with each operator leading its continuation line, indented relative to the first operand. A single-`|>` expression stays inline. The parser accepts both forms; the formatter normalises chains of 2+ operators to multi-line so pipelines read top-down in execution order. The continuation `|>` must be at column > 1 to keep top-level declaration boundaries unambiguous.
- **LLVM and WASM strings are now length-prefixed.** Layout: `{i32 utf8_bytes, i32 utf16_units, [N x i8] payload}` — 8-byte header (two little-endian i32s) followed by UTF-8 payload, no NUL terminator. Pointers into strings address the header start; runtime helpers load 32-bit ints at offsets 0 / 4 for byte / UTF-16 length and reach the payload at offset 8. `lengthUtf8Bytes` and `lengthUtf16CodeUnits` are now O(1) header loads on both backends (were O(n) byte scans). The `(++)` cap-check is also O(1) — two header loads, one add, one compare. `__print` writes exactly `byte_count` bytes via `write(2)` (LLVM) / `fd_write` (WASM) so a NUL inside a string no longer truncates the output, matching JVM / CLR / JS. `strlen` is now used only in the entry-point boundary glue, where the OS-supplied C-string for `argv[1]` is scanned once to build the length-prefixed wrap; LLVM keeps the libc declaration, WASM dropped its hand-rolled `__strlen` helper entirely (the entry-point scan is now inlined into `__entryArgEither`).
- **`main` signature** is now `main : Either (StringTooLong | UnpairedUtf16Surrogate) String -> IO Unit` — the runtime hands the entry-point input (`argv[1]` / stdin / FFI) to user code as `Right` on success or `Left StringTooLong` / `Left UnpairedUtf16Surrogate` on invalid input. Each backend's entry-point glue now calls a runtime helper (`__entryArgEither`) that runs two checks in a single pass:
  - **Length cap**: combined UTF-16 length compared against `maxStringLengthUtf16CodeUnits` (`2^27 = 134_217_728`); on overflow it constructs row-tagged `Left StringTooLong` without allocating a copy of the input. On UTF-8 backends (LLVM, WASM) the byte scan short-circuits as soon as the running UTF-16 count exceeds the cap, bounding the rejection-path cost on adversarial inputs at `O(min(len, 3 × cap))` bytes instead of an unbounded full walk.
  - **Strict UTF-16**: rejects unpaired surrogates. JVM, CLR, JS walk UTF-16 code units and verify each high surrogate (`U+D800..U+DBFF`) is immediately followed by a low surrogate (`U+DC00..U+DFFF`); standalone low or trailing high → `Left UnpairedUtf16Surrogate`. LLVM and WASM scan UTF-8 bytes and reject the surrogate-encoded triplet pattern (`ED A0..BF 80..BF`) which standard UTF-8 (RFC 3629) forbids — WTF-8, CESU-8, and Java modified UTF-8 inputs route to the same error label. Cap-check has priority: an input that is both too long and contains surrogates returns `Left StringTooLong`.
- **`CaseAlt` AST split into `CaseAltLeaf` / `CaseAltBlock`** — `CaseAltBlock` has no trailing-comment slot, encoding the parser invariant that a trailing `--` can't dock on an arm whose body ends inside a nested `ECase`/`EDo`. No user-visible change. Internally this unblocks nested `ECase`/`EDo` in `Arbitrary Expr` and surfaced renderer bugs (now fixed): multi-line subexpressions wrapped in nested position consistently close `)` on a fresh line in `EParens`/`ELam`/`ELet` and the precedence-driven wrap path.
- **Closures over outer parameters** — lambdas may reference any enclosing-scope binding. A new `Awsum.Defunctionalize` pass specialises each HOF call site for the closure flowing in: captures become first-order parameters and polymorphic HOFs split into monomorphic copies, so no backend grows a closure runtime.
- **Synthesis form for closed lambdas** — `let id = \x -> x in body` and `(\x -> x) 5` typecheck without annotation; per-use unification lets one local `\x -> x` flow at multiple types in one body. Top-level definitions still require signatures.
- **Structural sums `T1 | T2`** — closed anonymous unions; `(x : T)` ascription patterns for discrimination, exhaustive without catch-all; FNV-1a tag dispatch identical on all backends; mixed ascription + constructor arms in one `case`; implicit injection through nominal heads; cross-boundary row normalisation; row-tag collision check.
- **Hindley-Milner type inference** — two-way unification, occurs check, expected types push down through `case` arms and constructor applications.
- **`do`-notation** for `Either` chains, desugared directly to nested `case`.
- **`let` bindings** (standalone and in `do`); RHS evaluated once via a synthesised top-level helper. Optional `let n : T = e` ascription, required only on synth failure (`MissingLetAnnotation`). Haskell-style multi-line layout in the formatter.
- **Destructuring patterns** on `<-`, `let` LHS, function/lambda parameters; refutable patterns raise `NonExhaustiveCase`.
- **Recursive exhaustiveness** in nested patterns (closes pre-existing hole).
- **Lambda syntax `\x -> body`** as a surface form; lifted at lowering.
- **Eta-reduced top-level definitions** — `f = g` works for any RHS whose type matches the signature.
- **Property-based tests across all backends** (`just test-property`); 40 starter properties covering integer arithmetic (commutativity / associativity / identities / no-overflow agreement / distributivity), succ/pred (round-trip + boundary), equality, parse/show round-trip, string monoid laws, splitOnFirst, boolean laws.
- **Prelude** — `Tuple2`, `Tuple3`, `parseInt32`, `parseUInt8`, `splitOnFirst`, `addInt32`, `addUInt8`, `subInt32`, `subUInt8`, `negInt32`, `mulInt32`, `mulUInt8`, range constants `minInt32` / `maxInt32` / `minUInt8` / `maxUInt8`; new types `ParseError`, `UnderflowError`, `OverflowError`.
- **Three explicit string-length functions** — `lengthCodePoints`, `lengthUtf16CodeUnits`, `lengthUtf8Bytes`, all `String -> UInt32`. No `length` alias by design: the unit being counted is meaningful (a supplementary character is 1 code point, 2 UTF-16 code units, 4 UTF-8 bytes), and a call site that picked the wrong default would silently produce wrong answers.
- **`type Never`** in the prelude — empty type, no constructors. Used as the error row of `IO Never a` to declare an IO action that cannot fail; doubles as a phantom type and an unreachable-position marker.
- **Lazy IO.** `IO e a` is now a sum type in the prelude (`IOPure | IOFail | IOStdoutPrint`); `IO.Stdout.print "x"` builds an `IOStdoutPrint` cell instead of performing the print. Only the IO returned from `main` runs — `let _ = IO.Stdout.print "ignored" in IO.Stdout.print "real"` prints just `real`.
- **`bindIO` / `pureIO` / `mapIO` / `mapIOError`** in the prelude — IO compositors mirroring `bindEither` / `pureEither` / `mapRight` / `mapLeft`.

### Fixed

- **LLVM `argv[1]` on Windows** now reaches `v_main` as UTF-8 instead of an ANSI-code-page-mangled string. The footer used to emit POSIX `int main(int argc, char** argv)`, which on Windows had MSVCRT decode the command line through the host's ANSI code page — supplementary code points like `\u{C8E2D}` collapsed to `?` per UTF-16 unit before user code ran. On a `mingw32` host the codegen now emits a Windows-specific entry that re-fetches the command line via `GetCommandLineW` + `CommandLineToArgvW` and converts `argv[1]` to UTF-8 with `WideCharToMultiByte (CP_UTF8)`. The clang invocation in [awsum/Main.hs](awsum/Main.hs) and the test harness in [test/Awsum/RunBackend.hs](test/Awsum/RunBackend.hs) pass `-lshell32 -lkernel32` on a Windows host so `CommandLineToArgvW` resolves under both the mingw-w64 and MSVC linkers (mingw-w64 auto-links these; MSVC's CRT carries kernel32 only, so the explicit flag is what closes `LNK2019: unresolved external symbol CommandLineToArgvW`). The POSIX path is unchanged on non-Windows hosts.
- **Non-ASCII string literals** now compile correctly on the LLVM, JVM, and WASM backends. Previously LLVM declared `[N x i8]` based on Haskell `T.length` (code-point count) but emitted UTF-8 bytes (4 bytes for `🔥`, not 1), failing `clang` with a constant-expression type mismatch; JVM emitted standard UTF-8 into the constant pool where the verifier expects "modified UTF-8" (surrogate-pair-encoded), failing class load with `ClassFormatError`; WASM mis-sized the data-section offset for each pool entry, allowing later strings to overlap. CLR and JS were already correct because they store strings as UTF-16 natively.

### Changed

- **Signed Int32 arithmetic** returns `Either (UnderflowError | OverflowError) Int32`; nominal `ArithError` removed.
- **Cross-module shadow scoping** — same-module shadowing remains an error; cross-module is allowed.
- **Property tests** rewritten to a uniform `parseInput / property / main` skeleton with `let res : T = do { … }` directly in `main`; pattern do-bind inlines the previous `parsed <- … case parsed of …` envelopes.
- **`IOUnit` renamed to `IO Unit`** (`IO` is now a unary type constructor).
- **`IO` is now `IO e a`** — gains an explicit error-row parameter, mirroring `Either e a`. `main` now returns `IO Never Unit` and `IO.Stdout.print : String -> IO Never Unit` — `Never` declares "no errors possible at this site". When primitives later gain real errors (e.g. `BrokenPipe` for `print`), the type widens and forces every site to handle the new error explicitly. Signature-only change: IO actions are still executed eagerly at construction; lazy IO follows in a separate change.
- **Symbol visibility tightened** — every backend exposes only the platform-mandated entry point externally; user top-levels and runtime helpers are private.
- **`RowCatchAllPattern` diagnostic** points at the `_` itself, not the surrounding `case` arm.
- **JVM target floor: Java 11 (LTS)** — emitted class file version bumped from 51.0 (Java 7) to 55.0 (Java 11), aligning with the documented platform-version policy. CI's pinned JDK on all four matrix runners is now Zulu 11. Generated `.class` files run on any JVM ≥ 11.

### Removed

- **Lua backend** — supported targets are now LLVM/JVM/CLR/WASM/JS.

### Known Issues

- **String properties on Windows (JVM)** — `concat-left-identity`, `concat-right-identity`, `concat-associative`, and `lengths-three-functions` diverge from LLVM / CLR / WASM / JS on Windows for the JVM backend. The property test runner carries a `temporarilyBroken :: Set (OS, Backend, Text)` registry in [test/Awsum/PropertySpec.hs](test/Awsum/PropertySpec.hs) and excludes the listed (OS, backend, prop) cells from the cross-backend assertion, so the same properties keep providing signal on the four unaffected backends. Removing an entry once the bug is fixed re-enables assertion automatically.

### Fixed

- **JVM** — `caseSMT` slot 0 for `CValDef CCase`; `bcIconst` truncation of row tags > 2¹⁵; hardcoded `max_locals` / `max_stack` for deeply nested constructors; slot indices ≥ 256 (now uses `wide` prefix); `exprMaxStack` underestimate for first-class calls; inconsistent stackmap frames between sibling arms of a `case`; single-arm `case` tag slots tracked in SMT.
- **CLR** — `InvalidProgramException` on deeply nested constructors (hardcoded `MaxStack`, dup/stelem stack peak, `LocalVarSig` count truncation ≥ 128 locals).
- **`mergeAlts`** for nominal-headed scrutinees with row-typed fields.
- **Implicit row-injection on call results** — a call returning e.g. `Either ErrB Int32` into a `Either (ErrA | ErrB) Int32` slot is now wrapped with a `$lift$N` helper at lowering time. Previously the typechecker accepted it but codegen left the result unwrapped, crashing JVM dispatch on the bare-nominal payload.
- **Bidirectional check** propagates through polymorphic application.
- **`do` / `let` / `in`** reserved at the parser level.
- **Free type variables** in constructor fields are rejected.
- **WASM `__alloc`** traps via `unreachable` when `memory.grow` returns -1 (engine memory cap reached). Previously the bump allocator dropped the failure result and looped on retrying `memory.grow` forever, hanging the program; now OOM surfaces as an immediate `wasm trap: unreachable executed`.
- **Nested-pattern exhaustiveness** — `checkPatternColumnCovers` freshened type params with `"$exh"` while `isConInhabited` uses `"$scrut"`; the mismatched substitution no-op'd, so uninhabited siblings inside a nested pattern (e.g. `Right (Ok str)` on `Either e (Result _ (Box (Box (Box Never))))`) were reported as missing. Aligned both sites to `"$scrut"`.
- **`UnusedTopLevel` false positive** — reachability roots are now `main` plus every `_`-prefixed top-level, so helpers used solely from a `_name` def aren't flagged as unused.

### Tooling

- **Build provenance** — Sigstore attestations on every release asset.
- **`CONTRIBUTING.md`** — dev-loop commands, signed-commits requirement, PR/CHANGELOG conventions.
- **Second Windows CI axis** — `windows-x86_64-mingw` job runs the snapshot + property suites against a [WinLibs](https://winlibs.com) GCC 14.2.0 + LLVM 19.1.7 + mingw-w64 + UCRT bundle, in addition to the existing MSVC-flavored `LLVM-15.0.7-win64.exe`. The intentional version skew (15.0.7 vs 19.1.7) means both LLVM lines must accept our IR. The mingw job catches accidental toolchain-coupling in the LLVM codegen / clang invocation. The mingw job is CI-only — release artifacts continue to ship from the MSVC build, since the awsum.exe binary is GHC output and identical across the two runners.
- **`AWSUM_CLANG`** — optional environment variable that pins the clang executable path used by `awsum run -t llvm` and the test harness. Empty/unset falls back to PATH lookup (`clang`). Useful on hosts where PATH-resolved `clang` is the wrong LLVM — most prominently the Windows case, where Stack prepends GHC's bundled mingw clang (an older LLVM that predates opaque-pointers default) to child-process PATH.
- **Clang compile-failure messages now include stdout** in addition to stderr, with the exit code; previously a non-zero exit with empty stderr produced a content-free `clang failed during compile:` and hid the actual diagnostic. Applies to both the test harness and `awsum run -t llvm`.

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
