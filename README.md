# Awsum

Correctness-first, cross-target functional language.

[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/12979/badge)](https://www.bestpractices.dev/projects/12979)

**Correctness-first:** No numeric overflow, underflow, or precision loss. No `NaN`, `null`, `nil`, or `undefined`. No `throw`, no `catch`, no `panic` — errors are values. No stack overflow on tail, non-tail, or even mutual recursion. This trade-off is deliberate: correctness comes ahead of runtime performance, compile speed, and syntactic convenience.

**Cross-target:** The same source compiles to Native (LLVM), JVM, CLR, WASM, or JS, and produces the same result on every one — independent of each target's quirks and built-in types. The compiler accepts only the effects supported by the chosen target and program type.

<video src="https://github.com/awsum-lang/awsum/raw/refs/heads/main/docs/awsum-preview.mp4" controls></video>

- [Home Page](https://awsum-lang.org)
- [Language docs](https://awsum-lang.org/docs)

## Design documents

- [Principles](docs/principles.md) — language guarantees + compiler trade-off priority.
- [Compilation pipeline](docs/pipeline.md) — phase-by-phase walkthrough of `awsum build`.
- [Type system](docs/type-system.md) — what the type system can express, with examples of programs that compile and programs that get rejected. Aimed at users; minimal implementation detail.
- [Prelude and built-in functions](docs/prelude.md) — how types and functions written in Awsum coexist with per-target compiler implementations.
- [Recursion](docs/recursion.md) — the three-pass pipeline (SCC merge, CPS defunctionalization, TCO) that turns any recursion shape into stack-safe code on every backend.
- [Memory management](docs/memory-management.md) — how heap allocations are reclaimed: host GC on JVM/CLR/JS, compiler-emitted reference counting on LLVM/WASM.
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

Commands that go through the typechecker (`build`, `run`, `check`, `core`, `asm`) take a mandatory `--program-type cli` flag (currently the only supported program type; see [docs/prelude.md](docs/prelude.md)). Purely syntactic commands (`ast`, `format`, `symbols`) don't.

- `awsum build --program-type cli -t llvm|jvm|clr|wasm|js [-o OUT] FILE` — compile to target and write to file (or stdout). For JVM, CLR, and WASM, outputs binary (`.class`/`.dll`/`.wasm`).
- `awsum run --program-type cli -t llvm|jvm|clr|wasm|js [--input TEXT | --stdin] FILE` — compile to a temp file and execute with the system runtime, passing input to main.
- `awsum check --program-type cli [--json] [--strict] FILE` — parse and typecheck; prints `OK`, warnings (yellow), or an error. With `--json`, outputs an array of diagnostics: `[{"severity":"error"|"warning","startLine":3,"startCol":5,"endLine":3,"endCol":12,"message":"...","fixes":[{"title":"…","edits":[{"startLine":…,"startCol":…,"endLine":…,"endCol":…,"newText":"…"}]}]}]`. With `--strict`, any warning causes a non-zero exit code (CI-friendly).
- `awsum format [-i|--in-place] FILE` — `render . parse` with stable formatting. Preserves comments (including trailing inline), keeps a blank line between top-level blocks, and ends the file with a trailing newline.
- `awsum ast FILE` — pretty-print the surface AST (for debugging).
- `awsum core --program-type cli FILE` — print elaborated/lowered Core (post type elaboration) (for debugging).
- `awsum asm --program-type cli -t jvm|clr|wasm FILE` — print target assembly text: Jasmin-like for JVM, CIL for CLR, WAT for WASM (for debugging).
- `awsum symbols [--json] FILE` — list top-level declarations. With `--json`, outputs an LSP-style `DocumentSymbol` array (kind, name, range, selectionRange, children) consumed by `awsum-vscode` to drive the Outline view.
- `awsum lsp --stdio` — run a Language Server Protocol server over stdio. Reuses the existing parser, typechecker, formatter, and quick-fix payload. Driven by `awsum-vscode` and `awsum-zed`.
- `awsum --version` — show version

Examples:

```sh
awsum build --program-type cli -t llvm -o out.ll          test/sources/successful/smoke_hello/code/Main.aww && clang out.ll -o program && ./program "world"
awsum build --program-type cli -t jvm  -o AwsumMain.class test/sources/successful/smoke_hello/code/Main.aww && java -Dsun.jnu.encoding=UTF-8 -Dfile.encoding=UTF-8 AwsumMain "world"
awsum build --program-type cli -t clr  -o AwsumMain.dll   test/sources/successful/smoke_hello/code/Main.aww && dotnet AwsumMain.dll "world"
awsum build --program-type cli -t wasm -o out.wasm        test/sources/successful/smoke_hello/code/Main.aww && wasmtime out.wasm "world"
awsum build --program-type cli -t js   -o out.js          test/sources/successful/smoke_hello/code/Main.aww && node out.js "world"

awsum asm --program-type cli -t jvm  test/sources/successful/smoke_hello/code/Main.aww   # Jasmin-like text (for inspection)
awsum asm --program-type cli -t clr  test/sources/successful/smoke_hello/code/Main.aww   # CIL text (for inspection)
awsum asm --program-type cli -t wasm test/sources/successful/smoke_hello/code/Main.aww   # WAT text (for inspection)

awsum run --program-type cli -t llvm --input "world" test/sources/successful/smoke_hello/code/Main.aww
awsum run --program-type cli -t jvm  --input "world" test/sources/successful/smoke_hello/code/Main.aww
awsum run --program-type cli -t clr  --input "world" test/sources/successful/smoke_hello/code/Main.aww
awsum run --program-type cli -t wasm --input "world" test/sources/successful/smoke_hello/code/Main.aww
awsum run --program-type cli -t js   --input "world" test/sources/successful/smoke_hello/code/Main.aww

echo "world" | awsum run --program-type cli -t llvm --stdin test/sources/successful/smoke_hello/code/Main.aww
echo "world" | awsum run --program-type cli -t jvm  --stdin test/sources/successful/smoke_hello/code/Main.aww
echo "world" | awsum run --program-type cli -t clr  --stdin test/sources/successful/smoke_hello/code/Main.aww
echo "world" | awsum run --program-type cli -t wasm --stdin test/sources/successful/smoke_hello/code/Main.aww
echo "world" | awsum run --program-type cli -t js   --stdin test/sources/successful/smoke_hello/code/Main.aww

awsum check --program-type cli         test/sources/successful/smoke_hello/code/Main.aww
awsum check --program-type cli  --json test/sources/successful/smoke_hello/code/Main.aww
awsum format -i                        test/sources/successful/smoke_hello/code/Main.aww
awsum ast                              test/sources/successful/smoke_hello/code/Main.aww
awsum core  --program-type cli         test/sources/successful/smoke_hello/code/Main.aww
awsum --version
```

## AI use

The Awsum compiler, its design documents, and test suite are developed with substantial usage of generative AI. Every generated change is reviewed, edited, and accepted by a human before it lands in the repository, and no output is shipped unedited.

## License

Apache 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).
