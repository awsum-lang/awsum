# Awsum

A functional language where computation results are guaranteed equivalent across all compilation targets.

## Why Awsum

**Equivalent results everywhere.** When a program compiles for LLVM and JVM, both produce identical output — not by convention, but by design. Unlike Haskell/GHC vs GHCJS or PureScript's backends, Awsum treats cross-target equivalence as a compiler invariant, not a best-effort goal.

**Platform effects are compile-time gated.** Effects like `Window`, `Terminal`, or `DOM` are tied to compilation targets. If an effect isn't available on the platform, the program doesn't compile — no runtime surprises. The compiler knows what each target can do.

**Honest arithmetic.** All arithmetic operations return `Either` — no silent overflow, underflow, precision loss, `NaN`, `Infinity`, or `-0`. If a computation can fail, the type tells you. This is stricter than Elm (which inherits JS number semantics) and more explicit than Rust (where integer overflow is UB in release builds).

**Stack-safe recursion by default.** Write the recursion that expresses the algorithm — self-recursive, mutual, non-tail, whatever — and the compiler turns it into a loop without a stack frame per call on any backend, including JVM and JS where native cross-method tail calls do not exist. See [docs/recursion.md](docs/recursion.md).

## Targets

- **LLVM** — native binary via Clang (LLVM 15+)
- **JVM** — Java 7+ bytecode (generated directly, no Jasmin/javac)
- **CLR** — .NET 9+ DLL (generated directly, no ilasm/csc)
- **WASM** — WebAssembly via WASI (wasmtime)
- **JS** — Node.js 22+ (LTS), browser (planned)
- **Lua** — Lua 5.1+

See [Target Implementation Details](docs/targets.md) for how each backend works under the hood.

## Supported host platforms

The full test suite runs on every push to `main` and every PR across the following host OS / architecture combinations — these are the platforms the compiler is verified to build and run on:

| OS      | Architecture | Target triple              | GitHub runner      |
| ------- | ------------ | -------------------------- | ------------------ |
| Linux   | x86_64       | `x86_64-linux-gnu`         | `ubuntu-latest`    |
| Linux   | aarch64      | `aarch64-linux-gnu`        | `ubuntu-24.04-arm` |
| macOS   | aarch64      | `aarch64-apple-darwin`     | `macos-latest`     |
| Windows | x86_64       | `x86_64-pc-windows-msvc`   | `windows-latest`   |

Other host platforms may work but are not exercised in CI.

## Editor support

### VSCode

Install the `Awsum` extension to enable:

- Syntax highlighting (including integer literals)
- Formatting (on save or on demand)
- Inline error diagnostics (red squigglies) and warnings (yellow squigglies, theme-aware)
- Quick fixes (lightbulb) for unused bindings and matching ignored constructors
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

- [hello.aww](test/sources/successful/hello/code/Main.aww)
- [polymorphism.aww](test/sources/successful/polymorphism/code/Main.aww)

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
- `awsum check FILE [--json] [--strict]` — parse and typecheck; prints `OK`, warnings (yellow), or an error. With `--json`, outputs an array of diagnostics: `[{"severity":"error"|"warning","startLine":3,"startCol":5,"endLine":3,"endCol":12,"message":"...","fixes":[{"title":"…","edits":[{"startLine":…,"newText":"…"}]}]}]`. With `--strict`, any warning causes a non-zero exit code (CI-friendly).
- `awsum format FILE [-i|--in-place]` — `render . parse` with stable formatting. Preserves comments (including trailing inline), keeps a blank line between top-level blocks, and ends the file with a trailing newline.
- `awsum ast FILE` — pretty-print the surface AST (for debugging).
- `awsum core FILE` — print elaborated/lowered Core (post type elaboration) (for debugging).
- `awsum asm FILE [-t jvm|clr|wasm]` — print target assembly text: Jasmin-like for JVM, CIL for CLR, WAT for WASM (for debugging).
- `awsum symbols FILE [--json]` — list top-level declarations. With `--json`, outputs an LSP-style `DocumentSymbol` array (kind, name, range, selectionRange, children) consumed by the VSCode extension to drive the Outline view.
- `awsum --version` — show version

Examples:

```sh
awsum build test/sources/successful/hello/code/Main.aww -t llvm -o out.ll  && clang out.ll -o out && ./out "world"
awsum build test/sources/successful/hello/code/Main.aww -t jvm  -o AwsumMain.class && java AwsumMain "world"
awsum build test/sources/successful/hello/code/Main.aww -t clr  -o AwsumMain.dll   && dotnet AwsumMain.dll "world"
awsum build test/sources/successful/hello/code/Main.aww -t wasm -o out.wasm        && wasmtime out.wasm "world"
awsum build test/sources/successful/hello/code/Main.aww -t js   -o out.js  && node out.js "world"
awsum build test/sources/successful/hello/code/Main.aww -t lua  -o out.lua && lua out.lua "world"

awsum asm test/sources/successful/hello/code/Main.aww -t jvm   # Jasmin-like text (for inspection)
awsum asm test/sources/successful/hello/code/Main.aww -t clr   # CIL text (for inspection)
awsum asm test/sources/successful/hello/code/Main.aww -t wasm  # WAT text (for inspection)

awsum run test/sources/successful/hello/code/Main.aww -t llvm --input "world"
awsum run test/sources/successful/hello/code/Main.aww -t jvm  --input "world"
awsum run test/sources/successful/hello/code/Main.aww -t clr  --input "world"
awsum run test/sources/successful/hello/code/Main.aww -t wasm --input "world"
awsum run test/sources/successful/hello/code/Main.aww -t js   --input "world"
awsum run test/sources/successful/hello/code/Main.aww -t lua  --input "world"

echo "world" | awsum run test/sources/successful/hello/code/Main.aww -t llvm --stdin
echo "world" | awsum run test/sources/successful/hello/code/Main.aww -t jvm  --stdin
echo "world" | awsum run test/sources/successful/hello/code/Main.aww -t clr  --stdin
echo "world" | awsum run test/sources/successful/hello/code/Main.aww -t wasm --stdin
echo "world" | awsum run test/sources/successful/hello/code/Main.aww -t js   --stdin
echo "world" | awsum run test/sources/successful/hello/code/Main.aww -t lua  --stdin

awsum check  test/sources/successful/hello/code/Main.aww
awsum check  test/sources/successful/hello/code/Main.aww --json
awsum format test/sources/successful/hello/code/Main.aww -i
awsum ast    test/sources/successful/hello/code/Main.aww
awsum core   test/sources/successful/hello/code/Main.aww
awsum --version
```

## Design Principles

1. **Identical results on every target.** The same program produces the same stdout whether compiled for LLVM, JVM, CLR, WASM, JS, or Lua — byte-for-byte, verified by the test suite on every commit. This is a compiler invariant, not a best-effort goal; the rest of the design hangs off it.

2. **Stack safety belongs to the compiler, not the user.** Recursion — tail, non-tail, self, mutual — is normalised at Core level into a shape that runs in bounded stack on every backend, including JVM and JS where native cross-method tail calls do not exist. No manual CPS transforms, no `tailRecM`, no hand-unrolling. Write the recursion that expresses the algorithm; the compiler makes sure it doesn't fall over.

3. **Effects are platform-aware.** The compiler tracks which effects each target supports. A program using `Terminal` won't compile for a browser target; a program using `Window` won't compile for CLI. "Not supported" is a compile error, never a runtime surprise.

4. **Errors are values.** Arithmetic doesn't silently break. Division by zero, overflow, underflow, precision loss — all represented in the type system via `Either`. The programmer decides how to handle them; the compiler cannot "just return zero" or `NaN`.

5. **No invisible decisions.** When something has to be chosen, the programmer chooses — not the compiler. No defaulting of integer literals to a type the compiler guessed (ambiguity is rejected with an explicit hint); no silent shadowing of an outer name by an inner one (shadowing is a compile error); no quiet reference to something the programmer marked as unused (`_`-prefixed bindings cannot be read). The rules are small; the shared root is that nothing meaningful is decided behind the reader's back.

6. **Priority order when trade-offs appear:**
   1. **Correctness** — no runtime exceptions, no platform-behaviour differences, no surprising overflow / underflow / string corruption.
   2. **Runtime performance** — generated programs should be fast.
   3. **Compilation speed** — the compiler itself can be slower if it produces better output.

7. **The computer writes the compiler.** Implementation details would be chosen by hand, but choosing by hand got us JavaScript. So the computer chooses. It knows.

## Design documents

- [Prelude and built-in functions](docs/prelude.md) — how types and functions written in Awsum coexist with per-target compiler implementations.
- [Recursion](docs/recursion.md) — the three-pass pipeline (SCC merge, CPS defunctionalization, TCO) that turns any recursion shape into stack-safe code on every backend.
- [Target implementation details](docs/targets.md) — how each backend maps the same program to its native shape.
- [Platform version policy](docs/platform-version-policy.md) — which runtime versions each backend targets and why (latest LTS for server/browser, oldest manufacturer-supported for mobile).

## Roadmap

See [Roadmap](docs/roadmap.md) for planned features and design notes.

## Notes

- The syntax and semantics is inspired by [Elm](https://elm-lang.org/).
- The name is inspired by the `AWSUM` keyword of the [LOLCODE](https://en.wikipedia.org/wiki/LOLCODE) language.
