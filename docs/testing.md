# Testing

How the compiler test suite is structured, what each layer guarantees, and the workflow for finishing a feature. All commands below run from the compiler repo root (`awsum/`).

## Layers

The Hspec test suite has two complementary layers that share compile + run primitives via [test/Awsum/RunBackend.hs](../test/Awsum/RunBackend.hs) (`Backend`, `CompiledArtifacts`, `compileFromText`/`compileFromFile`, `runOn`, `runOnAll`).

### Snapshot tests — `just test`

Hspec + golden files. Each program in [test/sources/successful/](../test/sources/successful/)`<name>/code/Main.aww` generates snapshots for AST, Core IR, formatted source, per-backend codegen text (LLVM `.ll`, JVM `.j`, CLR `.il`, WASM `.wat`, JS), plus runtime stdout per stdin file. Cross-backend assertions guarantee LLVM/JVM/CLR/WASM/JS all produce **identical** stdout for the same input. To regenerate snapshots, delete the `.snapshots/` directory at the repo root and re-run `just test`.

Error-program snapshots live alongside under [test/sources/errors/](../test/sources/errors/) and `.snapshots/errors/`.

### Property tests — `just test-property` (~40s)

Same five backends, but instead of one fixed input per program, QuickCheck generates N constructively-valid inputs; each is fed through every backend and compared against a value computed independently in Haskell. Catches "all backends agree but the answer is wrong" — the failure mode snapshot tests cannot see. Lives in [test/sources/property/](../test/sources/property/) (Awsum sources) and [test/Awsum/PropertySpec.hs](../test/Awsum/PropertySpec.hs) (generators + expected-output functions). Slow because it spawns 5 backend processes per generated case, so it's gated out of `just test`.

## Commands

```bash
just build          # Build with pedantic warnings
just test           # Snapshot + error-program tests (excludes property tests)
just test-property  # Property tests across all 5 backends (~40s)
just test-watch     # TDD watch mode (snapshot tests, file-watch)
just build-watch    # Compiler-only watch mode
just format-fix     # Autoformat Haskell with Ormolu
just lint-check     # hlint (check only)
just lint-fix       # hlint with auto-fix
just clean          # Clean build artefacts (helps with weird HLS errors)
just fix            # Full precommit: cyrillic-detect → format → lint → clean → build → test → test-property
just release        # Tag and push the version currently in package.yaml (after the prep PR is merged)
```

## Workflow when finishing a feature

1. Run `just fix` — everything must pass (format, lint, build, snapshot tests, property tests).
2. Run `stack install` so the global `awsum` binary picks up the change (the VSCode extension shells out to it).
3. Add an entry under `## [Unreleased]` in [CHANGELOG.md](../CHANGELOG.md), grouped by Keep-a-Changelog section (`Added` / `Changed` / `Fixed` / `Removed`). One bullet per user-visible change. **If the changelog isn't updated, the feature isn't finished.** Infrastructure-only changes (CI, dev tooling, internal refactors) still get an entry so the next release notes are complete.

## CLI commands the tests exercise

Commands that go through the typechecker require `--program-type cli` (currently the only supported program type; see [prelude.md](prelude.md)). Purely syntactic commands (`ast`, `format`, `symbols`) don't take it.

```bash
awsum build --program-type cli -t llvm|jvm|clr|wasm|js [-o OUT] FILE     # Compile to file/stdout (binary for jvm/clr/wasm)
awsum run   --program-type cli -t llvm|jvm|clr|wasm|js [--input X] FILE  # Compile and execute
awsum check --program-type cli [--json] [--strict] FILE                  # Typecheck only
awsum core  --program-type cli FILE                                      # Print Core IR
awsum asm   --program-type cli -t jvm|clr|wasm FILE                      # Print target assembly text
awsum format [-i] FILE                                                   # Format source
awsum ast FILE                                                           # Print AST
awsum symbols [--json] FILE                                              # Top-level declarations (consumed by awsum-vscode)
```

## Iterating on one target at a time via `stack exec`

`just test` runs every program on all five backends and asserts identical stdout — that's its whole point. But during feature implementation the granularity is wrong: when wiring up a new prelude built-in, a new Core node, or a new codegen primitive, the natural workflow is to land it on one backend (typically LLVM first — its output is the easiest to read), then bring up the next, one at a time. Running the full suite forces all five to be plausible before any signal comes back. `stack exec awsum -- run` drives a single `.aww` file through whichever backend you're working on and prints the actual stdout — no snapshot comparison, no noise from the other four. (`stack exec` runs the local `stack build` output directly, so there's no need to `stack install` between iterations and no risk of invoking an older `awsum` from `PATH`.)

```bash
just build                                                                              # ensure the local binary is current

stack exec awsum -- run   --program-type cli -t jvm --input "world" path/to/Main.aww    # run on one backend, see real stdout (no snapshot comparison)
stack exec awsum -- check --program-type cli --json                 path/to/Main.aww    # diagnostics in the JSON shape awsum-vscode consumes
stack exec awsum -- core  --program-type cli                        path/to/Main.aww    # Core IR after typecheck + every Core-to-Core pass
stack exec awsum -- asm   --program-type cli -t jvm                 path/to/Main.aww    # text-form generated assembly (Jasmin-like for jvm, CIL for clr, WAT for wasm)
```

The `--` after `awsum` separates `stack`'s flags from the compiler's. The source path is arbitrary — `path/to/Main.aww` can be a file under [test/sources/](../test/sources/) or a scratch file outside the test tree for a minimal repro. For a tighter loop, run `just build-watch` in one terminal so the binary rebuilds on every save, and re-issue `stack exec` invocations in another to re-check.
