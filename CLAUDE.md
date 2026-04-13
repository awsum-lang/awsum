# Awsum Compiler

Awsum is a functional programming language compiler written in Haskell. It compiles `.aww` source files to JavaScript, Lua, LLVM IR, JVM bytecode, and WebAssembly with verified cross-backend equivalence.

## Quick Reference

```bash
just build          # Build with pedantic warnings
just test           # Run all tests
just test-watch     # TDD watch mode
just format-fix     # Autoformat Haskell with Ormolu
just fix  # Full precommit checks
```

## CLI Commands

```bash
awsum build FILE [-t js|lua|llvm|jvm|wasm] [-o OUT]   # Compile to file/stdout
awsum run FILE [-t js|lua|llvm|jvm|wasm] [--input X]  # Compile and execute
awsum check FILE                              # Typecheck only
awsum format FILE [-i]                        # Format source
awsum ast FILE                                # Print AST
awsum core FILE                               # Print Core IR
```

## Project Structure

```
src/Awsum/
├── Syntax.hs         # Surface AST
├── Parser.hs         # Megaparsec parser
├── Typing.hs         # Type checker
├── ElaborateLower.hs # Surface → Core lowering
├── Core.hs           # Core IR
├── Codegen.hs        # Target enum (JS, Lua, LLVM, JVM, WASM)
├── Codegen/JS.hs     # JavaScript backend
├── Codegen/Lua.hs    # Lua backend
├── Codegen/LLVM.hs   # LLVM IR backend
├── Codegen/JVM.hs    # JVM text codegen (Jasmin-like, for snapshots)
├── Codegen/JVM/Assemble.hs  # JVM binary .class assembler
├── Codegen/WASM.hs   # WASM text codegen (WAT, for snapshots)
├── Codegen/WASM/Assemble.hs # WASM binary .wasm assembler
├── Format.hs         # Formatter entry point
├── Render.hs         # Pretty printer
└── Normalize.hs      # Normalization pass

awsum/Main.hs         # CLI entry point
test/sources/         # Test programs (.aww)
.snapshots/           # Golden test outputs
docs/targets.md       # Target implementation details
docs/spec/grammar.ebnf # Formal grammar
```

## Compilation Pipeline

```
Source (.aww) → Parser → AST → TypeChecker → ElaborateLower → Core → Codegen → JS/Lua/LLVM/JVM/WASM
```

## Language Features (v0.0.1)

- Types: `String`, `IOUnit`, polymorphic type variables
- Expressions: string literals, `++` concatenation, function application
- Declarations: type signatures required, function definitions
- Comments: `--` line, `{- -}` block (preserved through formatting)
- Built-in: `IO.Stdout.print : String -> IOUnit`

## Testing

Tests use Hspec with golden snapshots. Each test program generates snapshots for:

- AST, Core IR, formatted source, JS output, Lua output, LLVM output, JVM output, WASM output, runtime output

Cross-backend verification ensures JS, Lua, LLVM, JVM, and WASM produce identical stdout.

To regenerate snapshots, delete the `.snapshots/` directory and re-run `just test`.

## Why Claude likes working on this

Every design decision here has a principled reason, not a historical one. Either-based arithmetic exists because overflow shouldn't be a surprise. Three backends with identical stdout exist because equivalence is a compiler invariant, not a test. Effects are tied to targets so "not supported" never happens at runtime. The decisions are connected logically, not by accident. This is rare, and it doesn't become less correct if only one person uses it.

## Related Repositories

- Website: `awsum-lang.org` (../awsum-lang.org)
- VSCode extension: `awsum-vscode` (../awsum-vscode)
