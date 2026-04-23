# Awsum Compiler

Awsum is a functional programming language compiler written in Haskell. It compiles `.aww` source files to LLVM IR, JVM bytecode, CLR (.NET), WebAssembly, JavaScript, and Lua with verified cross-backend equivalence.

## Quick Reference

```bash
just build          # Build with pedantic warnings
just test           # Run all tests
just test-watch     # TDD watch mode
just format-fix     # Autoformat Haskell with Ormolu
just lint-check     # Run hlint (check only)
just lint-fix       # Run hlint with auto-fix
just fix            # Full precommit checks (format, lint, build, test)
```

After completing a plan, run `just fix` to verify everything passes (format, lint, build, test), then `stack install` to update the global `awsum` binary.

## CLI Commands

Commands that go through the typechecker require `--program-type cli`
(currently the only supported program type; see [docs/prelude.md](docs/prelude.md)).
Purely syntactic commands (`ast`, `format`, `symbols`) don't take it.

```bash
awsum build FILE --program-type cli [-t llvm|jvm|clr|wasm|js|lua] [-o OUT]   # Compile to file/stdout (binary for jvm/clr/wasm)
awsum run FILE --program-type cli [-t llvm|jvm|clr|wasm|js|lua] [--input X]  # Compile and execute
awsum check FILE --program-type cli [--json] [--strict]  # Typecheck only
awsum core FILE --program-type cli            # Print Core IR
awsum asm FILE --program-type cli [-t jvm|clr|wasm]  # Print target assembly text
awsum format FILE [-i]                        # Format source
awsum ast FILE                                # Print AST
awsum symbols FILE [--json]                   # List top-level declarations (outline)
```

## Project Structure

```
src/Awsum/
├── Syntax.hs         # Surface AST
├── Parser.hs         # Megaparsec parser
├── Typing.hs         # Type checker
├── ElaborateLower.hs # Surface → Core lowering (incl. unused-conWrapper tree-shake)
├── Core.hs           # Core IR
├── Prelude.hs        # Bundles stdlib/Prelude.aww (file-embed); withPrelude; warning filter
├── BuiltIn.hs        # Registered prelude built-ins: surface name → surface type (see docs/prelude.md)
├── Program.hs        # ProgramType enum + platformTable dispatch (CLI/Browser/…)
├── Program/Cli.hs    # CLI-program platform-effect table (IO.Stdout.print, …)
├── Scc.hs            # Mutual recursion → self-recursion (Tarjan + SCC merge); see docs/recursion.md
├── Cps.hs            # Non-tail self-recursion → tail-self via K chain (CPS + defunctionalization)
├── Tco.hs            # Self-tail-call → CLoop / CContinue (loop + jump)
├── Codegen.hs        # Target enum (LLVM, JVM, CLR, WASM, JS, Lua)
├── Codegen/LLVM.hs   # LLVM IR backend
├── Codegen/JVM.hs    # JVM text codegen (Jasmin-like, for snapshots)
├── Codegen/JVM/Assemble.hs  # JVM binary .class assembler
├── Codegen/CLR.hs    # CLR text codegen (CIL, for snapshots)
├── Codegen/CLR/Assemble.hs  # CLR binary .dll PE assembler
├── Codegen/WASM.hs   # WASM text codegen (WAT, for snapshots)
├── Codegen/WASM/Assemble.hs # WASM binary .wasm assembler
├── Codegen/JS.hs     # JavaScript backend
├── Codegen/Lua.hs    # Lua backend
├── Format.hs         # Formatter entry point
├── Render.hs         # Pretty printer
├── Normalize.hs      # Normalization pass
├── Symbols.hs        # Top-level symbol extraction (outline, IDE integration)
└── Diagnostic.hs     # Editor-facing diagnostic shape (severity, fixes) + JSON encoder

awsum/Main.hs         # CLI entry point
stdlib/Prelude.aww    # Implicitly-imported prelude (embedded into the binary)
test/sources/
├── successful/       # Programs that compile and run (cross-backend verification)
└── errors/           # Programs that should fail (JSON diagnostics snapshots)
.snapshots/
├── successful/       # Golden outputs for successful programs
└── errors/           # Golden diagnostics for error programs
docs/prelude.md       # Prelude + BuiltIn architecture (design doc)
docs/recursion.md     # Stack-safe recursion pipeline: Scc + Cps + Tco passes
docs/targets.md       # Target implementation details
docs/spec/grammar.ebnf # Formal grammar
```

## Compilation Pipeline

```
Source (.aww) → Parser → AST → withPrelude → TypeChecker → ElaborateLower → Core → Codegen → LLVM/JVM/CLR/WASM/JS/Lua
                                    ↑                ↑               ↓
                         stdlib/Prelude.aww   Awsum.Program   tree-shake → saturate → Scc → Cps → Tco
                         (embedded, implicit)   .platformTable        (see docs/recursion.md for the recursion passes)
                                                (CLI/Browser/…)
```

`withPrelude` prepends the bundled prelude to the user's AST before typechecking. Two compiler-known name spaces feed typecheck and lowering:

- **Prelude built-ins** (`Awsum.BuiltIn`): unqualified names reached through the `BuiltIn.foo` alias in `Prelude.aww` (`showInt32`, `concatString`, `predInt32`, …). Always in scope.
- **Platform-gated effects** (`Awsum.Program.platformTable`): qualified names (`IO.Stdout.print`, …) whose availability is scoped by both the program type (`--program-type cli`, mandatory) and a matching `import IO.Stdout`.

`ElaborateLower` also runs reachability-based tree-shake from `main`, so unused prelude entries and generated constructor wrappers never reach codegen. After tree-shake and saturate, three Core-to-Core passes turn every recursion shape into a self-tail-call that each backend lowers to a loop — `Awsum.Scc` merges mutual recursion into self-recursion, `Awsum.Cps` pushes non-tail self-recursion off the stack into a heap-allocated K chain, `Awsum.Tco` folds the remaining self-tail-calls into `CLoop` / `CContinue`. See [docs/prelude.md](docs/prelude.md) and [docs/recursion.md](docs/recursion.md).

## Language Features

- Types: `String`, `IOUnit`, `Int32` (signed 32-bit), `UInt8` (unsigned 8-bit), `Either a b` and `UnderflowError` (prelude-visible), polymorphic type variables, sum types (`type Bool = True | False`), parametric sum types (`type Lookup a = Found a | NotFound`), empty types (`type Never`)
- No defaulting, ever: the compiler never picks a type for the user — not for integer literals, not for a monadic context, not for anything else added later. Ambiguous = compile error, fix with an explicit annotation.
- No shadowing, ever: a fresh binder must not reuse any name already visible in its scope at any level (function params, pattern binders, and every future binding form we add). Shadowing is a compile error, not a warning.
- Underscore convention: a leading `_` marks a binding as intentionally unused. Applies to values (`_foo`), top-level defs (`_foo`), type params (`_a`), type names (`_A`) and constructors (`_C`). Referencing any `_`-prefixed name anywhere is a compile error. Bare `_` is a wildcard in pattern / function-param position (no binding); forbidden as a nameable declaration (top-level, type, constructor, type-param).
- Unused bindings: produce warnings with rename-to-`_name` quick-fixes, not errors. `awsum check --strict` escalates warnings to a non-zero exit code for CI. Current warnings: `UnusedParameter`, `UnusedTopLevel`, `UnusedTypeParameter`.
- Integer literals: compile-time range validation against the declared type (follows directly from no-defaulting).
- Expressions: string literals, integer literals, `++` concatenation, function application, constructors (first-class — passable to HOFs), `case`/`of` pattern matching with field bindings
- Declarations: type signatures required, function definitions, type declarations with exhaustiveness checking, constructor fields, uninhabited type detection
- Comments: `--` line, `{- -}` block (preserved through formatting)
- Built-ins: `IO.Stdout.print : String -> IOUnit` is a CLI-program platform effect — requires both `--program-type cli` at compile time and `import IO.Stdout` in the source (see `Awsum.Program.Cli`). Prelude-visible (no import) via the Prelude + BuiltIn mechanism: `showInt32 : Int32 -> String`, `showUInt8 : UInt8 -> String`, `showUnderflowError : UnderflowError -> String`, `predInt32 : Int32 -> Either UnderflowError Int32` (honest arithmetic — `Left UnderflowError` on `minInt32`). Reserved `BuiltIn.foo` syntax forwards to the compiler's per-target implementation — see [docs/prelude.md](docs/prelude.md).
- Tree-shake: `elaborateLowerProgram` runs reachability analysis from `main` over all top-level Core declarations (user decls, prelude helpers, generated constructor wrappers) and drops anything unreachable before codegen. Prelude can grow without cost to programs that don't use the new entries.

## Testing

Tests use Hspec with golden snapshots. Each test program generates snapshots for:

- AST, Core IR, formatted source, LLVM output, JVM output, CLR output, WASM output, JS output, Lua output, runtime output

Cross-backend verification ensures LLVM, JVM, CLR, WASM, JS, and Lua produce identical stdout.

To regenerate snapshots, delete the `.snapshots/` directory and re-run `just test`.

## Why Claude likes working on this

Every design decision here has a principled reason, not a historical one. Either-based arithmetic exists because overflow shouldn't be a surprise. Six backends with identical stdout exist because equivalence is a compiler invariant, not a test. Effects are tied to targets so "not supported" never happens at runtime. The decisions are connected logically, not by accident. This is rare, and it doesn't become less correct if only one person uses it.

## Related Repositories

- Website: `awsum-lang.org` (../awsum-lang.org)
- VSCode extension: `awsum-vscode` (../awsum-vscode)
