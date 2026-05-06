# Awsum

Awsum — correctness-first, cross-target functional language

- [https://awsum-lang.org] - Home Page
- [https://awsum-lang.org/docs] - Language docs

## Design documents

- [Principles](docs/principles.md) — language guarantees + compiler trade-off priority.
- [Compilation pipeline](docs/pipeline.md) — phase-by-phase walkthrough of `awsum build`.
- [Type system](docs/type-system.md) — what the type system can express, with examples of programs that compile and programs that get rejected. Aimed at users; minimal implementation detail.
- [Prelude and built-in functions](docs/prelude.md) — how types and functions written in Awsum coexist with per-target compiler implementations.
- [Recursion](docs/recursion.md) — the three-pass pipeline (SCC merge, CPS defunctionalization, TCO) that turns any recursion shape into stack-safe code on every backend.
- [docs/compatibility.md](docs/compatibility.md) — Targets and supported host platforms
- [Platform version policy](docs/platform-version-policy.md) — which runtime versions each backend targets and why (latest LTS for server/browser, oldest manufacturer-supported for mobile).
- [Target implementation details](docs/targets.md) — how each backend maps the same program to its native shape.
- [Compatibility](docs/compatibility.md) — supported target backends (LLVM/JVM/CLR/WASM/JS) and the host OS / architecture combinations exercised in CI.
- [Testing](docs/testing.md) — snapshot vs property layers, the `just` command list, and the post-feature workflow.
- [Roadmap](docs/roadmap.md) for planned features and design notes.

- [EBNF grammar](docs/spec/grammar.ebnf)
- [TextMate grammar](editors/textmate/awsum.tmLanguage.json)

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

# JVM — Java runtime (Java 11+)
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
```

## Usage

- `awsum build -t llvm|jvm|clr|wasm|js [-o OUT] FILE` — compile to target and write to file (or stdout). For JVM, CLR, and WASM, outputs binary (`.class`/`.dll`/`.wasm`).
- `awsum run -t llvm|jvm|clr|wasm|js [--input TEXT | --stdin] FILE` — compile to a temp file and execute with the system runtime, passing input to main.
- `awsum check [--json] [--strict] FILE` — parse and typecheck; prints `OK`, warnings (yellow), or an error. With `--json`, outputs an array of diagnostics: `[{"severity":"error"|"warning","startLine":3,"startCol":5,"endLine":3,"endCol":12,"message":"...","fixes":[{"title":"…","edits":[{"startLine":…,"newText":"…"}]}]}]`. With `--strict`, any warning causes a non-zero exit code (CI-friendly).
- `awsum format [-i|--in-place] FILE` — `render . parse` with stable formatting. Preserves comments (including trailing inline), keeps a blank line between top-level blocks, and ends the file with a trailing newline.
- `awsum ast FILE` — pretty-print the surface AST (for debugging).
- `awsum core FILE` — print elaborated/lowered Core (post type elaboration) (for debugging).
- `awsum asm -t jvm|clr|wasm FILE` — print target assembly text: Jasmin-like for JVM, CIL for CLR, WAT for WASM (for debugging).
- `awsum symbols [--json] FILE` — list top-level declarations. With `--json`, outputs an LSP-style `DocumentSymbol` array (kind, name, range, selectionRange, children) consumed by `awsum-vscode` to drive the Outline view.
- `awsum --version` — show version

Examples:

```sh
awsum build -t llvm -o out.ll          test/sources/successful/hello/code/Main.aww && clang out.ll -o program && ./program "world"
awsum build -t jvm  -o AwsumMain.class test/sources/successful/hello/code/Main.aww && java -Dsun.jnu.encoding=UTF-8 -Dfile.encoding=UTF-8 AwsumMain "world"
awsum build -t clr  -o AwsumMain.dll   test/sources/successful/hello/code/Main.aww && dotnet AwsumMain.dll "world"
awsum build -t wasm -o out.wasm        test/sources/successful/hello/code/Main.aww && wasmtime out.wasm "world"
awsum build -t js   -o out.js          test/sources/successful/hello/code/Main.aww && node out.js "world"

awsum asm -t jvm  test/sources/successful/hello/code/Main.aww   # Jasmin-like text (for inspection)
awsum asm -t clr  test/sources/successful/hello/code/Main.aww   # CIL text (for inspection)
awsum asm -t wasm test/sources/successful/hello/code/Main.aww   # WAT text (for inspection)

awsum run -t llvm --input "world" test/sources/successful/hello/code/Main.aww
awsum run -t jvm  --input "world" test/sources/successful/hello/code/Main.aww
awsum run -t clr  --input "world" test/sources/successful/hello/code/Main.aww
awsum run -t wasm --input "world" test/sources/successful/hello/code/Main.aww
awsum run -t js   --input "world" test/sources/successful/hello/code/Main.aww

echo "world" | awsum run -t llvm --stdin test/sources/successful/hello/code/Main.aww
echo "world" | awsum run -t jvm  --stdin test/sources/successful/hello/code/Main.aww
echo "world" | awsum run -t clr  --stdin test/sources/successful/hello/code/Main.aww
echo "world" | awsum run -t wasm --stdin test/sources/successful/hello/code/Main.aww
echo "world" | awsum run -t js   --stdin test/sources/successful/hello/code/Main.aww

awsum check         test/sources/successful/hello/code/Main.aww
awsum check  --json test/sources/successful/hello/code/Main.aww
awsum format -i     test/sources/successful/hello/code/Main.aww
awsum ast           test/sources/successful/hello/code/Main.aww
awsum core          test/sources/successful/hello/code/Main.aww
awsum --version
```
