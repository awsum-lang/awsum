# Awsum Compiler

Awsum is a functional programming language compiler written in Haskell. It compiles `.aww` source files to JavaScript, Lua, and LLVM IR with verified cross-backend equivalence.

## Quick Reference

```bash
just build          # Build with pedantic warnings
just test           # Run all tests
just test-watch     # TDD watch mode
just format-fix     # Autoformat Haskell with Ormolu
just precommit-fix  # Full precommit checks
```

## CLI Commands

```bash
awsum build FILE [-t js|lua|llvm] [-o OUT]   # Compile to file/stdout
awsum run FILE [-t js|lua|llvm] [--input X]  # Compile and execute
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
├── Codegen.hs        # Target enum (JS, Lua, LLVM)
├── Codegen/JS.hs     # JavaScript backend
├── Codegen/Lua.hs    # Lua backend
├── Codegen/LLVM.hs   # LLVM IR backend
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
Source (.aww) → Parser → AST → TypeChecker → ElaborateLower → Core → Codegen → JS/Lua/LLVM
```

## Language Features (v0.0.1)

- Types: `String`, `IOUnit`, polymorphic type variables
- Expressions: string literals, `++` concatenation, function application
- Declarations: type signatures required, function definitions
- Comments: `--` line, `{- -}` block (preserved through formatting)
- Built-in: `IO.Stdout.print : String -> IOUnit`

## Testing

Tests use Hspec with golden snapshots. Each test program generates snapshots for:
- AST, Core IR, formatted source, JS output, Lua output, LLVM output, runtime output

Cross-backend verification ensures JS, Lua, and LLVM produce identical stdout.

## Related Repositories

- Website: `awsum-lang.org` (../awsum-lang.org)
- VSCode extension: `awsum-vscode` (../awsum-vscode)
