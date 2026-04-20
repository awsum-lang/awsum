# Awsum

A functional language where computation results are guaranteed equivalent across all compilation targets.

## Why Awsum

**Equivalent results everywhere.** When a program compiles for LLVM and JVM, both produce identical output — not by convention, but by design. Unlike Haskell/GHC vs GHCJS or PureScript's backends, Awsum treats cross-target equivalence as a compiler invariant, not a best-effort goal.

**Platform effects are compile-time gated.** Effects like `Window`, `Terminal`, or `DOM` are tied to compilation targets. If an effect isn't available on the platform, the program doesn't compile — no runtime surprises. The compiler knows what each target can do.

**Honest arithmetic.** All arithmetic operations return `Either` — no silent overflow, underflow, precision loss, `NaN`, `Infinity`, or `-0`. If a computation can fail, the type tells you. This is stricter than Elm (which inherits JS number semantics) and more explicit than Rust (where integer overflow is UB in release builds).

## Targets

- **LLVM** — native binary via Clang (LLVM 15+)
- **JVM** — Java 7+ bytecode (generated directly, no Jasmin/javac)
- **CLR** — .NET 9+ DLL (generated directly, no ilasm/csc)
- **WASM** — WebAssembly via WASI (wasmtime)
- **JS** — Node.js 14+, browser (planned)
- **Lua** — Lua 5.1+

See [Target Implementation Details](docs/targets.md) for how each backend works under the hood.

## Editor support

### VSCode

Install the `Awsum` extension to enable:

- Syntax highlighting (including integer literals)
- Formatting (on save or on demand)
- Inline error diagnostics (on open / save / edit)
- Outline view, breadcrumbs, and in-file symbol navigation (`Ctrl+Shift+O` / `@`)
- Workspace-wide symbol search (`Ctrl+T`)

Recommended settings:

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
# LLVM — native binary compiler (opaque pointer support requires 15+)
brew install llvm@15

# JVM — Java runtime (Java 7+)
# https://get-coursier.io/

# CLR — .NET runtime (.NET 9+)
# https://dotnet.microsoft.com/download
brew install dotnet

# WASM — WebAssembly runtime with WASI support
brew install wasmtime

# WABT — WebAssembly Binary Toolkit (optional, for validating generated .wasm)
brew install wabt

# JS — Node.js interpreter
# https://www.nvmnode.com/

# Lua — Lua interpreter
brew install lua
```

## Usage

- `awsum build FILE [-t llvm] [-o OUT]` — compile to target and write to file (or stdout). For JVM, CLR, and WASM, outputs binary (`.class`/`.dll`/`.wasm`).
- `awsum run FILE [-t llvm] [--input TEXT | --stdin]` — compile to a temp file and execute with the system runtime, passing input to main.
- `awsum check FILE [--json]` — parse and typecheck; prints `OK` or a descriptive error. With `--json`, outputs a JSON array of diagnostics with source positions: `[{"startLine":3,"startCol":5,"endLine":3,"endCol":12,"message":"..."}]`.
- `awsum format FILE [-i|--in-place]` — `render . parse` with stable formatting. Preserves comments (including trailing inline), keeps a blank line between top-level blocks, and ends the file with a trailing newline.
- `awsum ast FILE` — pretty-print the surface AST (for debugging).
- `awsum core FILE` — print elaborated/lowered Core (post type elaboration) (for debugging).
- `awsum asm FILE [-t jvm|clr|wasm]` — print target assembly text: Jasmin-like for JVM, CIL for CLR, WAT for WASM (for debugging).
- `awsum symbols FILE [--json]` — list top-level declarations. With `--json`, outputs an LSP-style `DocumentSymbol` array (kind, name, range, selectionRange, children) consumed by the VSCode extension to drive the Outline view.
- `awsum --version` — show version

Examples:

```sh
awsum build test/sources/hello.aww -t llvm -o out.ll  && clang out.ll -o out && ./out "world"
awsum build test/sources/hello.aww -t jvm  -o AwsumMain.class && java AwsumMain "world"
awsum build test/sources/hello.aww -t clr  -o AwsumMain.dll   && dotnet AwsumMain.dll "world"
awsum build test/sources/hello.aww -t wasm -o out.wasm        && wasmtime out.wasm "world"
awsum build test/sources/hello.aww -t js   -o out.js  && node out.js "world"
awsum build test/sources/hello.aww -t lua  -o out.lua && lua out.lua "world"

awsum asm test/sources/hello.aww -t jvm   # Jasmin-like text (for inspection)
awsum asm test/sources/hello.aww -t clr   # CIL text (for inspection)
awsum asm test/sources/hello.aww -t wasm  # WAT text (for inspection)

awsum run test/sources/hello.aww -t llvm --input "world"
awsum run test/sources/hello.aww -t jvm  --input "world"
awsum run test/sources/hello.aww -t clr  --input "world"
awsum run test/sources/hello.aww -t wasm --input "world"
awsum run test/sources/hello.aww -t js   --input "world"
awsum run test/sources/hello.aww -t lua  --input "world"

echo "world" | awsum run test/sources/hello.aww -t llvm --stdin
echo "world" | awsum run test/sources/hello.aww -t jvm  --stdin
echo "world" | awsum run test/sources/hello.aww -t clr  --stdin
echo "world" | awsum run test/sources/hello.aww -t wasm --stdin
echo "world" | awsum run test/sources/hello.aww -t js   --stdin
echo "world" | awsum run test/sources/hello.aww -t lua  --stdin

awsum check  test/sources/hello.aww
awsum check  test/sources/hello.aww --json
awsum format test/sources/hello.aww -i
awsum ast    test/sources/hello.aww
awsum core   test/sources/hello.aww
awsum --version
```

## Design Principles

1. **Equivalence is a guarantee, not a test.** If the same pure function compiles for two targets, the results are identical. The compiler and the test suite enforce this as an invariant.
2. **Effects are platform-aware.** The compiler tracks which effects each target supports. A program using `Terminal` won't compile for a browser target; a program using `Window` won't compile for CLI. No runtime "not supported" errors.
3. **Errors are values.** Arithmetic doesn't silently break. Division by zero, overflow, precision loss — all represented in the type system via `Either`. The programmer decides how to handle them.
4. **The computer writes the compiler.** Implementation details would be chosen by hand, but choosing by hand got us JavaScript. So the computer chooses. It knows.

### Priority order

When making trade-offs, the compiler follows this priority:

1. **Correctness** — no runtime exceptions, no platform behavior differences, no non-obvious behavior (overflow, underflow, string data corruption)
2. **Runtime performance** — generated programs should be fast
3. **Compilation speed** — the compiler itself can be slower if it produces better output

## Roadmap

See [Roadmap](docs/roadmap.md) for planned features and design notes.

## Notes

- The syntax and semantics is inspired by [Elm](https://elm-lang.org/).
- The name is inspired by the `AWSUM` keyword of the [LOLCODE](https://en.wikipedia.org/wiki/LOLCODE) language.
