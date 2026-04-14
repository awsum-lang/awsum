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

```bash
awsum build FILE [-t llvm|jvm|clr|wasm|js|lua] [-o OUT]   # Compile to file/stdout (binary for jvm/clr/wasm)
awsum run FILE [-t llvm|jvm|clr|wasm|js|lua] [--input X]  # Compile and execute
awsum check FILE [--json]                      # Typecheck only (--json for structured diagnostics)
awsum format FILE [-i]                        # Format source
awsum ast FILE                                # Print AST
awsum core FILE                               # Print Core IR
awsum asm FILE [-t jvm|clr|wasm]              # Print target assembly text
```

## Project Structure

```
src/Awsum/
├── Syntax.hs         # Surface AST
├── Parser.hs         # Megaparsec parser
├── Typing.hs         # Type checker
├── ElaborateLower.hs # Surface → Core lowering
├── Core.hs           # Core IR
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
└── Normalize.hs      # Normalization pass

awsum/Main.hs         # CLI entry point
test/sources/
├── successful/       # Programs that compile and run (cross-backend verification)
└── errors/           # Programs that should fail (JSON diagnostics snapshots)
.snapshots/
├── successful/       # Golden outputs for successful programs
└── errors/           # Golden diagnostics for error programs
docs/targets.md       # Target implementation details
docs/spec/grammar.ebnf # Formal grammar
```

## Compilation Pipeline

```
Source (.aww) → Parser → AST → TypeChecker → ElaborateLower → Core → Codegen → LLVM/JVM/CLR/WASM/JS/Lua
```

## Language Features

- Types: `String`, `IOUnit`, polymorphic type variables, sum types (`type Bool = True | False`), parametric sum types (`type Lookup a = Found a | NotFound`), empty types (`type Never`)
- Expressions: string literals, `++` concatenation, function application, constructors, `case`/`of` pattern matching with field bindings
- Declarations: type signatures required, function definitions, type declarations with exhaustiveness checking, constructor fields, uninhabited type detection
- Comments: `--` line, `{- -}` block (preserved through formatting)
- Built-in: `IO.Stdout.print : String -> IOUnit`

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
