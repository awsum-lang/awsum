# Awsum Compiler

Awsum is a functional programming language compiler written in Haskell. It compiles `.aww` source files to LLVM IR, JVM bytecode, CLR (.NET), WebAssembly, and JavaScript with verified cross-backend equivalence.

## Quick Reference

```bash
just build          # Build with pedantic warnings
just test           # Run snapshot tests (excludes property tests)
just test-property  # Run property-based tests across all 5 backends (~40s)
just test-watch     # TDD watch mode
just format-fix     # Autoformat Haskell with Ormolu
just lint-check     # Run hlint (check only)
just lint-fix       # Run hlint with auto-fix
just fix            # Full precommit checks (format, lint, build, test)
```

After completing a plan, run `just fix` to verify everything passes (format, lint, build, test), then `stack install` to update the global `awsum` binary.

When a feature is done, add an entry for it under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md) — one bullet per user-visible change, grouped by the Keep-a-Changelog section (`Added` / `Changed` / `Fixed` / `Removed`). Do this as part of finishing the feature, not later — if the changelog isn't updated, the feature isn't finished. Infrastructure-only changes (CI, dev tooling, internal refactors) still get an entry so the next release notes are complete.

## CLI Commands

Commands that go through the typechecker require `--program-type cli`
(currently the only supported program type; see [docs/prelude.md](docs/prelude.md)).
Purely syntactic commands (`ast`, `format`, `symbols`) don't take it.

```bash
awsum build --program-type cli -t llvm|jvm|clr|wasm|js [-o OUT] FILE   # Compile to file/stdout (binary for jvm/clr/wasm)
awsum run --program-type cli -t llvm|jvm|clr|wasm|js [--input X] FILE  # Compile and execute
awsum check --program-type cli [--json] [--strict] FILE  # Typecheck only
awsum core --program-type cli FILE            # Print Core IR
awsum asm --program-type cli -t jvm|clr|wasm FILE  # Print target assembly text
awsum format [-i] FILE                        # Format source
awsum ast FILE                                # Print AST
awsum symbols [--json] FILE                   # List top-level declarations (outline)
awsum lsp --stdio                             # Run Language Server Protocol (transport mandatory)
```

## Project Structure

```
src/Awsum/
├── Syntax.hs         # Surface AST
├── Parser.hs         # Megaparsec parser
├── Typing.hs         # Type checker
├── ElaborateLower.hs # Surface → Core lowering (incl. unused-conWrapper tree-shake)
├── Defunctionalize.hs# Eliminate first-class function values via per-call-site HOF specialisation
├── LowerClosures.hs  # Reynolds defunctionalization for residual fn values (ctor fields, case-arm-binders) → tagged CCon + per-arity $applyN dispatcher
├── Core.hs           # Core IR
├── Prelude.hs        # Bundles stdlib/Prelude.aww (file-embed); withPrelude; warning filter
├── BuiltIn.hs        # Registered prelude built-ins: surface name → surface type (see docs/prelude.md)
├── Program.hs        # ProgramType enum + platformTable dispatch (CLI/Browser/…)
├── Program/Cli.hs    # CLI-program platform-effect table (IO.Stdout.print, …)
├── Scc.hs            # Mutual recursion → self-recursion (Tarjan + SCC merge); see docs/recursion.md
├── Cps.hs            # Non-tail self-recursion → tail-self via K chain (CPS + defunctionalization)
├── Tco.hs            # Self-tail-call → CLoop / CContinue (loop + jump)
├── Codegen.hs        # Target enum (LLVM, JVM, CLR, WASM, JS)
├── Codegen/LLVM.hs   # LLVM IR backend
├── Codegen/JVM.hs    # JVM text codegen (Jasmin-like, for snapshots)
├── Codegen/JVM/Assemble.hs  # JVM binary .class assembler
├── Codegen/CLR.hs    # CLR text codegen (CIL, for snapshots)
├── Codegen/CLR/Assemble.hs  # CLR binary .dll PE assembler
├── Codegen/WASM.hs   # WASM text codegen (WAT, for snapshots)
├── Codegen/WASM/Assemble.hs # WASM binary .wasm assembler
├── Codegen/JS.hs     # JavaScript backend
├── Format.hs         # Formatter entry point
├── Render.hs         # Pretty printer
├── Normalize.hs      # Normalization pass
├── Symbols.hs        # Top-level symbol extraction (outline, IDE integration)
├── Diagnostic.hs     # Editor-facing diagnostic shape (severity, fixes) + JSON encoder
└── Lsp.hs            # `awsum lsp` Language Server Protocol over stdio

awsum/Main.hs         # CLI entry point
stdlib/Prelude.aww    # Implicitly-imported prelude (embedded into the binary)
test/Awsum/RunBackend.hs        # Shared compile + run helpers (Backend, CompiledArtifacts, runOn, runOnAll)
test/Awsum/ProgramSnapshotsSpec.hs  # Snapshot tests
test/Awsum/PropertySpec.hs      # Property tests (gated by '--match "Property tests"')
test/sources/
├── successful/       # Programs that compile and run (cross-backend snapshot verification)
├── errors/           # Programs that should fail (JSON diagnostics snapshots)
└── property/         # Programs whose stdout is asserted against a Haskell-computed expectation
.snapshots/
├── successful/       # Golden outputs for successful programs
└── errors/           # Golden diagnostics for error programs
docs/type-system.md             # Type system from a user's perspective: concepts + examples (passes / fails)
docs/prelude.md                 # Prelude + BuiltIn architecture (design doc)
docs/recursion.md               # Stack-safe recursion pipeline: Scc + Cps + Tco passes
docs/targets.md                 # Target implementation details
docs/platform-version-policy.md # Which runtime versions each backend targets and why
docs/compatibility.md           # Supported target backends + host OS/arch matrix exercised in CI
docs/spec/grammar.ebnf          # Formal grammar
```

## Compilation Pipeline

Phase-by-phase walkthrough (Frontend → Lowering → Core-to-Core → Backend) lives in [docs/pipeline.md](docs/pipeline.md):

@docs/pipeline.md

## Language Features

For the user-facing description of the type system — concepts and examples of programs that pass / fail typechecking — see [docs/type-system.md](docs/type-system.md). The bullets below are the implementation-side index.

- Types: `String`, `IO a`, `Int32` (signed 32-bit), `UInt8` (unsigned 8-bit), `Either a b` and `UnderflowError` (prelude-visible), polymorphic type variables, sum types (`type Bool = True | False`), parametric sum types (`type Lookup a = Found a | NotFound`), empty types (`type Never`), structural sums `(A | B)` with type-ascription patterns and row-tag-based runtime dispatch, `do`-notation hard-coded to `Either`
- No defaulting, ever: the compiler never picks a type for the user — not for integer literals, not for a monadic context, not for anything else added later. Ambiguous = compile error, fix with an explicit annotation.
- No shadowing, ever: a fresh binder must not reuse any name already visible in its scope at any level (function params, pattern binders, and every future binding form we add). Shadowing is a compile error, not a warning.
- Underscore convention: a leading `_` marks a binding as intentionally unused. Applies to values (`_foo`), top-level defs (`_foo`), type params (`_a`), type names (`_A`) and constructors (`_C`). Referencing any `_`-prefixed name anywhere is a compile error. Bare `_` is a wildcard in pattern / function-param position (no binding); forbidden as a nameable declaration (top-level, type, constructor, type-param).
- Unused bindings: produce warnings with rename-to-`_name` quick-fixes, not errors. `awsum check --strict` escalates warnings to a non-zero exit code for CI. Current warnings: `UnusedParameter`, `UnusedTopLevel`, `UnusedTypeParameter`.
- Integer literals: compile-time range validation against the declared type (follows directly from no-defaulting).
- Expressions: string literals, integer literals, `++` concatenation, function application, constructors (first-class — passable to HOFs), `case`/`of` pattern matching with field bindings
- Declarations: type signatures required, function definitions, type declarations with exhaustiveness checking, constructor fields, uninhabited type detection
- Comments: `--` line, `{- -}` block (preserved through formatting)
- Built-ins: `IO.Stdout.print : String -> IO Unit` is a CLI-program platform effect — requires both `--program-type cli` at compile time and `import IO.Stdout` in the source (see `Awsum.Program.Cli`). Prelude-visible (no import) via the Prelude + BuiltIn mechanism: `showInt32 : Int32 -> String`, `showUInt8 : UInt8 -> String`, `showUnderflowError : UnderflowError -> String`, `predInt32 : Int32 -> Either UnderflowError Int32` (honest arithmetic — `Left UnderflowError` on `minInt32`). Reserved `BuiltIn.foo` syntax forwards to the compiler's per-target implementation — see [docs/prelude.md](docs/prelude.md).
- Tree-shake: `elaborateLowerProgram` runs reachability analysis from `main` over all top-level Core declarations (user decls, prelude helpers, generated constructor wrappers) and drops anything unreachable before codegen. Prelude can grow without cost to programs that don't use the new entries.

## Testing

See [docs/testing.md](docs/testing.md) for the full reference: snapshot vs property layers, the `just` command list, the post-feature workflow (`just fix` → `stack install` → CHANGELOG), and the CLI commands the tests exercise.

Two layers in one sentence each: **snapshot tests** (`just test`) compile every program in [test/sources/successful/](test/sources/successful/) on all five backends and assert the stdouts are identical and match golden files; **property tests** (`just test-property`, ~40s) feed QuickCheck-generated inputs through every backend and assert the stdouts match a Haskell-computed expectation. Both share primitives via [test/Awsum/RunBackend.hs](test/Awsum/RunBackend.hs).

## Related Repositories

- Website: `awsum-lang.org` (../awsum-lang.org)
- VSCode extension: `awsum-vscode` (../awsum-vscode)
