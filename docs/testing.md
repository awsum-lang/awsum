# Testing

How the compiler test suite is structured, what each layer guarantees, and the workflow for finishing a feature. All commands below run from the compiler repo root (`awsum/`).

## Layers

The Hspec test suite has three complementary layers that share compile + run primitives via [test/Awsum/RunBackend.hs](../test/Awsum/RunBackend.hs) (`Backend`, `CompiledArtifacts`, `compileFromText`/`compileFromFile`, `runOn`, `runOnAll`). Every harness compile and every backend process run is capped at 60 s (`timeLimitMicros` there): a diverging program or a non-terminating compiler pass fails its item by name instead of hanging the suite.

### Snapshot tests — `just test`

Hspec + golden files. Each program in [test/sources/successful/](../test/sources/successful/)`<name>/code/Main.aww` generates snapshots for AST, Core IR, formatted source, per-backend codegen text (LLVM `.ll`, JVM `.j`, CLR `.il`, WASM `.wat`, JS), plus runtime stdout per input file (`<name>/input/*.txt` — today each is delivered to the program as its single CLI argument; a program with no `input/` directory runs once, against `output/no-input.txt`). Cross-backend assertions guarantee LLVM/JVM/CLR/WASM/JS all produce **identical** stdout for the same input. To regenerate snapshots, delete the `.snapshots/` directory at the repo root and re-run `just test`.

Error-program snapshots live alongside under [test/sources/errors/](../test/sources/errors/) and `.snapshots/errors/`.

### Property tests — `just test-property` (~2 min)

Same five backends, but instead of one fixed input per program, QuickCheck generates N constructively-valid inputs; each is fed through every backend — in both pipeline modes, with and without the `Simplify` pass — and compared against a value computed independently in Haskell. Catches "all backends agree but the answer is wrong" — the failure mode snapshot tests cannot see. Lives in [test/sources/property/](../test/sources/property/) (Awsum sources) and [test/Awsum/PropertySpec.hs](../test/Awsum/PropertySpec.hs) (generators + expected-output functions). Slow because it spawns 10 backend processes per generated case (5 backends × 2 modes), so it's gated out of `just test`.

### No-simplify differential — `just test-no-simplify`

Every successful-corpus program compiled a second time with the `Simplify` pass disabled — a library-level, test-only switch; the `awsum` CLI has no such flag — and run on all five backends; each stdout must equal the committed output golden that `just test` records under the normal pipeline. The pair of suites asserts `runtime(simplify(core)) == runtime(core)` with the runtime itself as the oracle (a wrong Core rewrite makes all five backends agree on the same wrong answer, invisible to both snapshot layers), and keeps every codegen exercised on raw, unsimplified Core shapes. Never writes goldens — a missing golden means `just test` hasn't recorded the reference yet. Gated out of `just test` for the same reason the property layer is: one extra `clang` per program. Lives in [test/Awsum/NoSimplifySpec.hs](../test/Awsum/NoSimplifySpec.hs).

### Benchmark snapshots — `just benchmark-snapshot`

Performance golden files, one per program under [test/sources/benchmark/](../test/sources/benchmark/): `.benchmarks/<name>/bench.txt` records a per-backend `median (min–max)` of wall time and peak RSS (run count and timeout in the header), plus a stdout anchor cross-checked against every backend and run while measuring — a backend whose stdout deviates renders `mismatch` and the run exits non-zero. Snapshot mode also compiles the program without the `Simplify` pass and runs it once per backend (unmeasured) against the same anchor: `bench.txt` records only the normal pipeline, a no-simplify deviation goes to stderr and the exit code. The numbers are machine-local, so they are **not** asserted by `just test` or CI; the workflow is manual: snapshot, make the change, snapshot again, read the `git diff` — the (min–max) band separates run-to-run noise from a real shift. Compiler artifacts for the same programs (`.snapshots/benchmark/<name>/compiler/` — AST, Core, per-backend codegen text, lifetime analysis) **are** golden-tested by `just test`, so a bench delta is diagnosable from the committed IR diff. The split is physical: `.snapshots/` holds what `just test` regenerates and can be reset wholesale; `.benchmarks/` is written only by benchmark runs, so a snapshot reset cannot take the medians with it. macOS-only (BSD `/usr/bin/time -l`, `gtimeout` from coreutils).

## Test source conventions

Snapshot sources under [test/sources/successful/](../test/sources/successful/) are worked examples — read and copied by people and by the language models that assist them — so they hold to one house style. A program that produces output by threading an `Either` to stdout uses this shape:

```awsum
main : IO Never Unit
main = eitherToIO res
  |> andThenIO IO.Stdout.print
  |> handleErrorIO onError

onError : <error row> -> IO Never Unit
onError e = case e of
  StringTooLong -> IO.Stdout.print "STRING_TOO_LONG"
  …
```

1. **Bridge `Either` to `IO` with `eitherToIO`** — never a hand-written `case res of Left … ; Right …` to print the result.
2. **Sequence `IO` with `andThenIO`** (or `bindIO` where a value is threaded into the continuation), composed left-to-right with `|>`.
3. **One error handler, named `onError`** — not an inline `\_e -> …` lambda, not a differently-named helper.
4. **`onError` enumerates the error row by constructor** — one arm per alternative, no `_` wildcard that discards the structure. Bare constructor pattern (`StringTooLong ->`) where the alternative is a single-constructor nominal type; type-ascription pattern (`(s : String) ->`) where it is a primitive or a multi-constructor type; a distinct message per arm.
5. **The doc comment is behaviour-only** — one short `{- … -}` saying what language shape the program exercises and what it should print. Self-contained: no reference to other test programs, to `docs/`, to compiler modules or passes, or to the property / no-simplify / benchmark layers. Regression history lives in git, not in the comment.

The exception is a test whose *subject* is one of these mechanisms — a program exercising `bindIO`, `handleErrorIO` partial recovery, the row-collapse matrix, a `Simplify` Core shape, the `|>` operator itself, and so on. There the construct under test stays as written; the conventions apply to everything incidental around it.

## Commands

```bash
just build          # Build with pedantic warnings
just test           # Snapshot + error-program tests (excludes the property and no-simplify suites)
just test-property  # Property tests across all 5 backends, both pipeline modes (~2 min)
just test-no-simplify    # Whole corpus without the Simplify pass vs committed stdout goldens
just benchmark NAME      # One benchmark through every backend with timing + peak RSS (macOS)
just benchmark-all       # Every benchmark in sequence, summary at the end
just benchmark-snapshot  # Overwrite the per-benchmark median golden files
just test-watch     # TDD watch mode (snapshot tests, file-watch)
just build-watch    # Compiler-only watch mode
just format-fix     # Autoformat Haskell with Ormolu
just lint-check     # hlint (check only)
just lint-fix       # hlint with auto-fix
just clean          # Clean build artefacts (helps with weird HLS errors)
just fix            # Full precommit: cyrillic-detect → format → lint → clean → build → test → test-property → test-no-simplify
just release        # Tag and push the version currently in package.yaml (after the prep PR is merged)
```

## Workflow when finishing a feature

Any new functionality lands together with the tests that exercise it — snapshot tests for new language features or compiler passes, property tests for behaviour that has a generator-friendly input space.

1. Run `just fix` — everything must pass (format, lint, build, snapshot tests, property tests, no-simplify differential).
2. Run `stack install` so the global `awsum` binary picks up the change (the VSCode extension shells out to it).
3. Add an entry under `## [Unreleased]` in [CHANGELOG.md](../CHANGELOG.md), grouped by Keep-a-Changelog section (`Added` / `Changed` / `Fixed` / `Removed`). One bullet per user-visible change. **If the changelog isn't updated, the feature isn't finished.** Infrastructure-only changes (CI, dev tooling, internal refactors) still get an entry so the next release notes are complete.

## CLI commands the tests exercise

Commands that go through the typechecker require `--program-type cli` (currently the only supported program type; see [prelude.md](prelude.md)). Purely syntactic commands (`ast`, `format`, `symbols`) don't take it.

```bash
awsum build --program-type cli -t llvm|jvm|clr|wasm|js [-o OUT] FILE     # Compile to file/stdout (binary for jvm/clr/wasm)
awsum run   --program-type cli -t llvm|jvm|clr|wasm|js FILE [-- ARG …]   # Compile and execute (argv after --, read via IO.Args.getArgs as List String; stdin inherits — pipe or < file to feed IO.Stdin.readAllString/readAllBytes)
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

stack exec awsum -- run   --program-type cli -t jvm path/to/Main.aww -- "world"         # argv path: run on one backend, see real stdout (no snapshot comparison)
printf '1:1' | stack exec awsum -- run --program-type cli -t jvm    path/to/Main.aww    # stdin path: byte-exact input via pipe reaches IO.Stdin.readAllString/readAllBytes
stack exec awsum -- check --program-type cli --json                 path/to/Main.aww    # diagnostics in the JSON shape awsum-vscode consumes
stack exec awsum -- core  --program-type cli                        path/to/Main.aww    # Core IR after typecheck + every Core-to-Core pass
stack exec awsum -- asm   --program-type cli -t jvm                 path/to/Main.aww    # text-form generated assembly (Jasmin-like for jvm, CIL for clr, WAT for wasm)
```

The `--` after `awsum` separates `stack`'s flags from the compiler's. The source path is arbitrary — `path/to/Main.aww` can be a file under [test/sources/](../test/sources/) or a scratch file outside the test tree for a minimal repro. For a tighter loop, run `just build-watch` in one terminal so the binary rebuilds on every save, and re-issue `stack exec` invocations in another to re-check.
