# Compilation pipeline

What happens when you run `awsum build`. Phases live in `src/Awsum/`; cross-cutting topics each have their own design doc — links inline below.

```
Source (.aww)
  │
  ▼  Frontend
[ Parse  →  withPrelude  →  desugar do-blocks  →  Typecheck ]
  │
  ▼  Lowering
[ MonomorphizeRows  →  Typed AST → Core IR  (+ row-tag collision check)  →  lazy-IO lowering  →  tree-shake from main, runIO ]
  │
  ▼  Core-to-Core passes
[ Defunctionalize → tree-shake
  LowerClosures → tree-shake
  Saturate
  Scc-merge → tree-shake
  Cps
  Scc-merge → tree-shake (multi-non-tail-call cycle between $cps$f and $apply$f)
  StackSafety            (any leftover non-tail recursion → compile error)
  Tco
  Lifetime.insertDrops   (places CDrop annotations at scope-correct points)
  Reuse.insertReuse      (rewrites linear-scrutinee CCon into in-place CReuse) ]
  │
  ▼  Backend
[ Codegen  →  LLVM | JVM | CLR | WASM | JS ]
  │
  ▼
 .ll   .class   .dll   .wasm   .js
```

Every phase below is orchestrated by `elaborateLowerProgram` in [../src/Awsum/ElaborateLower.hs](../src/Awsum/ElaborateLower.hs) — one Haskell function that runs the whole desugar-typecheck-lower-and-flatten sequence and returns a flattened `CoreProgram` or a `TypeError`.

## Frontend

- **Parse** (`Awsum.Parser`) — Megaparsec turns `.aww` text into a surface AST. Comments are preserved so `awsum format` round-trips. Grammar: [spec/grammar.ebnf](spec/grammar.ebnf).
- **withPrelude** (`Awsum.Prelude`) — The bundled [../stdlib/Prelude.aww](../stdlib/Prelude.aww) is prepended to the user's AST. Every program gets `Maybe`, `Either`, `Bool`, `bindEither`, `showInt32`, etc. without an import. Some prelude functions are aliases to compiler-supplied built-ins (`BuiltIn.foo`) that codegen substitutes per target. See [prelude.md](prelude.md).
- **Desugar `do`-blocks** — A pre-typecheck rewrite turns each `do`-block into nested `bindEither` calls with surface lambda continuations. Lambdas themselves stay as surface nodes; the typechecker handles them bidirectionally and lambda-lifting happens later, during lowering.
- **Typecheck** (`Awsum.Typing`) — Bidirectional. Mandatory top-level signatures, no defaulting, no shadowing, exhaustive `case`, structural sums with implicit injection. Produces a typed AST (`Awsum.TExpr`) — every node carries its resolved type, with an explicit coercion node at each row injection — which the lowering passes below consume instead of re-inferring types. Diagnostics carry source spans (and quick-fixes where applicable) — consumed by `awsum-vscode` via `awsum check --json`. The platform-effect gate (`IO.Stdout.print`, etc.) lives here too: `--program-type cli` plus a matching `import` is what makes those names resolvable. Full reference: [type-system.md](type-system.md).

## Lowering

- **MonomorphizeRows** (`Awsum.MonomorphizeRows`) — A typed-AST → typed-AST pass, run after typechecking and before Core lowering: it specialises each row-polymorphic combinator (`bindEither`, `bindIO`, `andThenEither`, …) at every concrete row instantiation. A polymorphic combinator's body injects its `Left` / `failIO` payload into the result row via a coercion whose label is still an abstract type variable — which has no statically-known row tag — so lowering the generic body once would emit the wrong tag, and the row-`case` at the call site (dispatching on the concrete label's tag) would never line up. At each call site whose instantiation widens an abstract row into a concrete multi-alternative one, the pass emits a specialised copy of the callee with the call-site substitution applied to its body (turning the abstract label into the concrete one) and repoints the call. The trigger is the authoritative `(declared, instantiated)` pair the typechecker recorded on the call head. See [type-system.md](type-system.md) (structural sums).
- **Lower to Core** (`Awsum.ElaborateLower`) — Drops signatures, converts the typed defs and exprs into the smaller Core IR (`Awsum.Core`), generates constructor wrappers, lambda-lifts capturing lambdas. A row-tag collision check rejects programs whose structural-sum labels would canonicalise to the same FNV-1a 32-bit hash at runtime.
- **Lower IO platform built-ins** (`Awsum.ElaborateLower.lowerIOPlatformBuiltinsDecl`) — Rewrites `CCall (CBuiltIn "IO.Stdout.print") [arg]` into the constructor expression `CCon ioStdoutPrintTag [arg, IOPure Unit]`. After this pass the platform built-in's call site is gone from Core; in its place is a heap-allocated description that the prelude's `runIO` walks at runtime. This is what makes IO lazy. See [prelude.md](prelude.md) for the full story.
- **Tree-shake from `main` and `runIO`** — Reachability analysis over every top-level declaration (user code, prelude helpers, generated constructor wrappers). Roots are `main` (the user entry point) plus `runIO` (the prelude's IO-tree walker, which the codegen entry-point glue calls on `main`'s result through a string template — not a Core call edge). Anything unreachable from those two roots is dropped — the prelude can grow without inflating program size. Tree-shake re-runs after every later pass that can produce new dead code.

## Core-to-Core passes

These run in order inside `Awsum.ElaborateLower` after the initial tree-shake. Their job is to flatten everything that any backend would otherwise need a runtime feature to handle (closures, mutual recursion, non-tail recursion, partial application).

- **Defunctionalize** (`Awsum.Defunctionalize`) — No backend has a closure runtime. Each HOF call site that statically resolves to a known closure has its `fn`-typed slot replaced with a first-order specialisation whose parameter list adds the closure's captures up front. *(Tree-shake re-runs — original polymorphic HOFs whose calls were all replaced by specialisations fall out as dead code.)*
- **LowerClosures** (`Awsum.LowerClosures`) — Reynolds defunctionalization for residual function values: closures that survived the previous pass because they flow through positions Defunctionalize cannot specialise (stored in a constructor field, passed through a case-arm-binder, captured into a partial application inside a non-statically-resolvable HOF). Each such closure is encoded as a tagged `CCon` and every residual call routed through a per-arity `$applyN` dispatcher. After this pass no first-class function value remains in any reachable position; every `CCall` callee is either a top-level fn name or one of the synthetic `$applyN` helpers. *(Tree-shake re-runs.)*
- **Saturate** — Lambda-lift under-applied direct calls so codegen sees only full-arity calls. Also asserts the post-Defunctionalize/LowerClosures invariant that no partial application with local captures survives — both passes cooperate to maintain it.
- **Scc-merge** (`Awsum.Scc`) — Every mutually recursive call-graph cluster (Tarjan SCC, size > 1) is fused into a single self-recursive `$scc$…` function whose argument is a sum-typed `CCon` tagged by "which member is active". Each original public name becomes a one-line wrapper that packs its args into the right tag. After this, mutual recursion has become self-recursion. *(Tree-shake re-runs — wrappers for SCC members only called from inside the cluster fall out.)*
- **Cps** (`Awsum.Cps`) — Non-tail self-recursion is moved off the system stack into a heap-allocated continuation chain (defunctionalisation-by-Reynolds applied to the continuation type). Each function with at least one non-tail self-call is emitted as a wrapper + `$cps$f` + `$apply$f` trio; both `$cps$f` and `$apply$f` are self-tail-recursive so they fall through to TCO below.
- **Scc-merge again** (`Awsum.Scc`) — When the original body has two or more non-tail self-calls in one expression (`Node (mirror r) v (mirror l)`-style), Cps allocates one K_i per call and an earlier K_i's apply arm tail-calls `$cps$f` to start the next call — so `$cps$f` and `$apply$f` end up mutually recursive. Re-running Scc-merge fuses any such pair into one self-recursive `$scc$` function tagged by which of the two is active. Single-non-tail-call functions stay unchanged (the apply body never references `$cps$f`, so no cycle exists), and Scc-merge is a no-op on them. *(Tree-shake re-runs.)*
- **StackSafety verifier** (`Awsum.StackSafety`) — A standalone post-condition check: after Scc-merge and Cps there must be no non-trivial call-graph cycle and no `CFunDef` with a non-tail self-call. Any remainder is a compile error, no escape hatch — the program is either user-level ill-formed (e.g. mutually recursive `CValDef`s, which have no fixed point) or a compiler bug.
- **Tco** (`Awsum.Tco`) — Remaining self-tail-calls fold into `CContinue` jumps inside a `CLoop` body; backends emit a loop + jump rather than a recursive call. Final Core-level invariant: every remaining recursion is a self-tail-call wrapped in `CLoop`. Full reference: [recursion.md](recursion.md).
- **Lifetime.insertDrops** (`Awsum.Lifetime`) — Annotates each locally-introduced binder with a `CDrop n inner` node at the latest scope-correct point where it stops being referenced: scope start when unused, the start of `CCase`/`CRowCase` arms that don't mention it, the next sibling after its last use in `CCall`/`CCon`/`CContinue` sequences, and the function epilogue for tail-leaf parameters. JVM/CLR/JS treat `CDrop` as transparent (managed GC handles block-scoped slot collection); LLVM/WASM lower it to `__free_recursive`. Full reference: [memory-management.md](memory-management.md).
- **Reuse.insertReuse** (`Awsum.Reuse`) — Detects the canonical linear-scrutinee pattern `case x of (..., CDrop x (CCon t [..])) -> ...` and rewrites the inner `CCon` to a `CReuse` Core node — in-place stores on the existing cell rather than `alloc`-then-store. The transformation distributes into nested `CCase`/`CRowCase` arms so each arm independently picks up the rewrite when its scrut-drop is present. Backends lower `CReuse` as in-place writes on LLVM/WASM and (still) as `anewarray`/`newarr`/array-literal on JVM/CLR/JS, which managed GCs then promote to stack via escape analysis once the hot loop is alloc-free.

## Backend

- **Codegen** (`Awsum.Codegen.{LLVM,JVM,CLR,WASM,JS}`) — The same Core IR is lowered to one of five targets. JVM/CLR/WASM each go through a text codegen module + a binary assembler (`.j` → `.class`, `.il` → `.dll`, `.wat` → `.wasm`); LLVM emits `.ll` for `clang`; JS emits `.js`. Every target produces **identical** stdout for the same input — a compiler invariant verified on every commit (see [testing.md](testing.md)). Per-target details: [targets.md](targets.md).
