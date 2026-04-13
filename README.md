# Awsum

A functional language where computation results are guaranteed equivalent across all compilation targets.

## Why Awsum

**Equivalent results everywhere.** When a program compiles for JS and Lua, both produce identical output — not by convention, but by design. Unlike Haskell/GHC vs GHCJS or PureScript's backends, Awsum treats cross-target equivalence as a compiler invariant, not a best-effort goal.

**Platform effects are compile-time gated.** Effects like `Window`, `Terminal`, or `DOM` are tied to compilation targets. If an effect isn't available on the platform, the program doesn't compile — no runtime surprises. The compiler knows what each target can do.

**Honest arithmetic.** All arithmetic operations return `Either` — no silent overflow, underflow, precision loss, `NaN`, `Infinity`, or `-0`. If a computation can fail, the type tells you. This is stricter than Elm (which inherits JS number semantics) and more explicit than Rust (where integer overflow is UB in release builds).

## Targets

- **JS** — Node.js 14+, browser (planned)
- **Lua** — Lua 5.1+
- **LLVM** — native binary via Clang (LLVM 15+)
- **JVM** — Java 7+ bytecode (generated directly, no Jasmin/javac)
- **WASM** — WebAssembly via WASI (wasmtime)

See [Target Implementation Details](docs/targets.md) for how each backend works under the hood.

## Editor support

### VSCode

- Install the `Awsum` extension to enable syntax highlight and code formatting
- Enable format on save

```json
{
  // settings.json
  "[awsum]": {
    "editor.formatOnSave": true,
    "editor.defaultFormatter": "awsum-lang.awsum-vscode"
  }
}
```

### Other editors

- [EBNF grammar](docs/spec/grammar.ebnf)
- [TextMate grammar](editors/textmate/awsum.tmLanguage.json)

## Examples

- [hello.aww](test/sources/hello.aww)
- [polymorphism.aww](test/sources/polymorphism.aww)

## Installation

### Compiler

```sh
# Install Stack (Haskell build tool)
ghcup install stack

# Build and install the compiler
stack build
stack install

# Make sure ~/.local/bin is in PATH
```

### Target runtimes

Install only the runtimes for the targets you need:

```sh
# JS — Node.js interpreter
nvm install 22

# Lua — Lua interpreter
brew install lua

# LLVM — native binary compiler (opaque pointer support requires 15+)
brew install llvm@15

# JVM — Java runtime (class version 51.0 requires 7+)
brew install openjdk

# WASM — WebAssembly runtime with WASI support
brew install wasmtime

# WABT — WebAssembly Binary Toolkit (optional, for validating generated .wasm)
brew install wabt
```

## Usage

- `awsum build FILE [-t js] [-o OUT]` — compile to target and write to file (or stdout). For JVM and WASM, outputs binary (`.class`/`.wasm`).
- `awsum run FILE [-t js] [--input TEXT | --stdin]` — compile to a temp file and execute with the system runtime, passing input to main.
- `awsum check FILE` — parse and typecheck; prints `OK` or a descriptive error.
- `awsum format FILE [-i|--in-place]` — `render . parse` with stable formatting. Preserves comments (including trailing inline), keeps a blank line between top-level blocks, and ends the file with a trailing newline.
- `awsum ast FILE` — pretty-print the surface AST (for debugging).
- `awsum core FILE` — print elaborated/lowered Core (post type elaboration) (for debugging).
- `awsum asm FILE [-t jvm|wasm]` — print target assembly text: Jasmin-like for JVM, WAT for WASM (for debugging).
- `awsum --version` — show version

Examples:

```sh
awsum build test/sources/hello.aww -t js   -o out.js  && node out.js "world"
awsum build test/sources/hello.aww -t lua  -o out.lua && lua out.lua "world"
awsum build test/sources/hello.aww -t llvm -o out.ll  && clang out.ll -o out && ./out "world"
awsum build test/sources/hello.aww -t jvm  -o AwsumMain.class && java AwsumMain "world"
awsum build test/sources/hello.aww -t wasm -o out.wasm        && wasmtime out.wasm "world"

awsum asm test/sources/hello.aww -t jvm   # Jasmin-like text (for inspection)
awsum asm test/sources/hello.aww -t wasm  # WAT text (for inspection)

awsum run test/sources/hello.aww -t js   --input "world"
awsum run test/sources/hello.aww -t lua  --input "world"
awsum run test/sources/hello.aww -t llvm --input "world"
awsum run test/sources/hello.aww -t jvm  --input "world"
awsum run test/sources/hello.aww -t wasm --input "world"

echo "world" | awsum run test/sources/hello.aww -t js   --stdin
echo "world" | awsum run test/sources/hello.aww -t lua  --stdin
echo "world" | awsum run test/sources/hello.aww -t llvm --stdin
echo "world" | awsum run test/sources/hello.aww -t jvm  --stdin
echo "world" | awsum run test/sources/hello.aww -t wasm --stdin

awsum check  test/sources/hello.aww
awsum format test/sources/hello.aww -i
awsum ast    test/sources/hello.aww
awsum core   test/sources/hello.aww
awsum --version
```

## Design Principles

1. **Equivalence is a guarantee, not a test.** If the same pure function compiles for two targets, the results are identical. The compiler and the test suite enforce this as an invariant.
2. **Effects are platform-aware.** The compiler tracks which effects each target supports. A program using `Terminal` won't compile for a browser target; a program using `Window` won't compile for CLI. No runtime "not supported" errors.
3. **Errors are values.** Arithmetic doesn't silently break. Division by zero, overflow, precision loss — all represented in the type system via `Either`. The programmer decides how to handle them.

### Priority order

When making trade-offs, the compiler follows this priority:

1. **Correctness** — no runtime exceptions, no platform behavior differences, no non-obvious behavior (overflow, underflow, string data corruption)
2. **Runtime performance** — generated programs should be fast
3. **Compilation speed** — the compiler itself can be slower if it produces better output

## Roadmap

### Language

- Numbers and `Either`-based arithmetic with equivalent semantics across targets
- Algebraic data types and pattern matching
- Let-bindings and where-clauses
- Platform-aware effects: compile-time gating of `Terminal`, `DOM`, `Window`, `Ports`
- Application formats: CLI, browser, library

### AI tooling

- MCP server exposing compiler intelligence to AI agents:
  - `awsum/typecheck` — typecheck a snippet without writing to disk
  - `awsum/typeof` — get the type of an expression or definition by name
  - `awsum/completions` — list valid completions at a given position
  - `awsum/signature` — look up a function signature by name
  - `awsum/errors` — structured errors as JSON with source spans
  - `awsum/available-effects` — list effects available for a given target
  - `awsum/project-index` — all definitions with types, without function bodies
- Grammar-constrained generation via EBNF for syntactically valid AI output

## Notes

- The syntax and semantics is inspired by [Elm](https://elm-lang.org/).
- The name is inspired by the `AWSUM` keyword of the [LOLCODE](https://en.wikipedia.org/wiki/LOLCODE) language.
