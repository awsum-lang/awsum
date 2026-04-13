# Awsum Compiler

Awsum is a functional programming language compiler written in Haskell. It compiles `.aww` source files to JavaScript, Lua, LLVM IR, JVM bytecode, WebAssembly, and CLR (.NET) with verified cross-backend equivalence.

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

After completing a plan, run `just fix` to verify everything passes (format, lint, build, test).

## CLI Commands

```bash
awsum build FILE [-t js|lua|llvm|jvm|wasm|clr] [-o OUT]   # Compile to file/stdout (binary for jvm/wasm/clr)
awsum run FILE [-t js|lua|llvm|jvm|wasm|clr] [--input X]  # Compile and execute
awsum check FILE                              # Typecheck only
awsum format FILE [-i]                        # Format source
awsum ast FILE                                # Print AST
awsum core FILE                               # Print Core IR
awsum asm FILE [-t jvm|wasm|clr]              # Print target assembly text
```

## Project Structure

```
src/Awsum/
├── Syntax.hs         # Surface AST
├── Parser.hs         # Megaparsec parser
├── Typing.hs         # Type checker
├── ElaborateLower.hs # Surface → Core lowering
├── Core.hs           # Core IR
├── Codegen.hs        # Target enum (JS, Lua, LLVM, JVM, WASM, CLR)
├── Codegen/JS.hs     # JavaScript backend
├── Codegen/Lua.hs    # Lua backend
├── Codegen/LLVM.hs   # LLVM IR backend
├── Codegen/JVM.hs    # JVM text codegen (Jasmin-like, for snapshots)
├── Codegen/JVM/Assemble.hs  # JVM binary .class assembler
├── Codegen/WASM.hs   # WASM text codegen (WAT, for snapshots)
├── Codegen/WASM/Assemble.hs # WASM binary .wasm assembler
├── Codegen/CLR.hs    # CLR text codegen (CIL, for snapshots)
├── Codegen/CLR/Assemble.hs  # CLR binary .dll PE assembler
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
Source (.aww) → Parser → AST → TypeChecker → ElaborateLower → Core → Codegen → JS/Lua/LLVM/JVM/WASM/CLR
```

## Language Features (v0.0.1)

- Types: `String`, `IOUnit`, polymorphic type variables
- Expressions: string literals, `++` concatenation, function application
- Declarations: type signatures required, function definitions
- Comments: `--` line, `{- -}` block (preserved through formatting)
- Built-in: `IO.Stdout.print : String -> IOUnit`

## Testing

Tests use Hspec with golden snapshots. Each test program generates snapshots for:

- AST, Core IR, formatted source, JS output, Lua output, LLVM output, JVM output, WASM output, CLR output, runtime output

Cross-backend verification ensures JS, Lua, LLVM, JVM, WASM, and CLR produce identical stdout.

To regenerate snapshots, delete the `.snapshots/` directory and re-run `just test`.

## Why Claude likes working on this

Every design decision here has a principled reason, not a historical one. Either-based arithmetic exists because overflow shouldn't be a surprise. Six backends with identical stdout exist because equivalence is a compiler invariant, not a test. Effects are tied to targets so "not supported" never happens at runtime. The decisions are connected logically, not by accident. This is rare, and it doesn't become less correct if only one person uses it.

## Related Repositories

- Website: `awsum-lang.org` (../awsum-lang.org)
- VSCode extension: `awsum-vscode` (../awsum-vscode)
