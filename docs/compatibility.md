# Compatibility

What Awsum compiles to (target backends + minimum runtime versions) and what it's verified to compile *on* (host OS / architecture combinations exercised in CI).

## Targets

The same Awsum program lowers to any of five backends; cross-backend equivalence is checked on every commit (see [testing.md](testing.md)). Per-backend implementation details: [targets.md](targets.md). Minimum-runtime rationale: [platform-version-policy.md](platform-version-policy.md).

- **LLVM** — native binary via Clang (LLVM 15+)
- **JVM** — Java 11+ bytecode (generated directly, no Jasmin/javac)
- **CLR** — .NET 9+ DLL (generated directly, no ilasm/csc)
- **WASM** — WebAssembly via WASI (wasmtime)
- **JS** — Node.js 22+ (LTS), browser (planned)

## Supported host platforms

The full test suite runs on every push to `main` and every PR across the following host OS / architecture combinations — these are the platforms the compiler is verified to build and run on:

| OS      | Architecture | Platform identifier | GitHub runners              |
| ------- | ------------ | ------------------- | --------------------------- |
| Linux   | x86_64       | `linux-x86_64-gnu`  | `ubuntu-24.04`              |
| Linux   | aarch64      | `linux-aarch64-gnu` | `ubuntu-24.04-arm`          |
| macOS   | aarch64      | `macos-aarch64`     | `macos-15`                  |
| Windows | x86_64       | `windows-x86_64`    | `windows-2025` (LLVM MSVC)  |
| Windows | x86_64       | `windows-x86_64`    | `windows-2025` (WinLibs)    |

The platform identifiers double as the suffix in release-asset filenames (e.g. `awsum-<version>-linux-x86_64-gnu.tar.gz`). Linux entries keep the `-gnu` suffix to leave room for a future `-musl` build alongside; macOS and Windows have a single ABI per OS in our build pipeline, so no suffix is needed.

Windows is exercised on two LLVM toolchains in parallel — the MSVC-flavored `LLVM-15.0.7-win64.exe` from llvm-project, and a mingw-w64-flavored [WinLibs](https://winlibs.com) bundle (LLVM 19.1.7, default triple `x86_64-w64-mingw32`, UCRT runtime) — to catch accidental coupling to one toolchain's link line or default triple. The version skew (15.0.7 vs 19.1.7) is intentional: our documented floor is "LLVM 15+", and the mingw job pins the most recent UCRT bundle WinLibs publishes so the codegen has to keep working as upstream LLVM moves. Both jobs must pass. Only the MSVC job uploads a release artifact; `awsum.exe` itself is GHC output and identical across the two runners, so there's one canonical Windows binary per release.

Other host platforms may work but are not exercised in CI.
