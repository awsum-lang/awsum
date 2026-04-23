# Recursion in Awsum

How the compiler turns natural recursion (self, non-tail, mutual) into stack-safe code on all six backends, without asking the user to do anything differently.

## Guarantee to the user

A well-typed Awsum program **does not overflow the system stack on any backend**, regardless of recursion shape. This is a compiler invariant verified by the test suite at depths up to 1 000 000, cross-backend. The user writes whichever recursion expresses the algorithm most clearly; the compiler picks the shape that will not blow up.

Concretely:

- **Tail self-recursion** becomes a loop. (`countdown-int32-stress-tail` — 100 000 iterations across LLVM, JVM, CLR, WASM, JS, Lua.)
- **Non-tail self-recursion** moves its frames from the system stack into an ADT chain on the heap. (`countdown-int32-stress` — 100 000 iterations; `adt-list-map` — list `map` with the recursive call nested inside a constructor field.)
- **Mutual recursion** gets fused into a single self-recursive function; after that the same two mechanisms take over. (`even-odd-stress` — 1 000 000 iterations.)

None of these require user-facing annotations or special monadic combinators. The work happens in three Core-to-Core passes plugged into the existing compilation pipeline.

## Priority order behind the design

When a trade-off appears, the compiler follows this order:

1. **Correctness.** The program must not overflow on any target, and every backend must produce the same stdout.
2. **Runtime performance.** Generated code should be fast.
3. **Compilation speed.** The compiler itself can be slower if it produces better output.

"Heap frames instead of stack frames" costs a boxed allocation per non-tail recursive call. Heap is typically larger than the system stack and configurable; the allocation cost is the price of the correctness guarantee, and the priority order says that is acceptable.

## The three passes

```
Source (.aww) → Parser → AST → withPrelude → TypeChecker
                                     ↓
                              ElaborateLower
                                     ↓
                               tree-shake
                                     ↓
                                 saturate           (lambda-lifting for partial application)
                                     ↓
                              ┌─── Awsum.Scc ───┐   (mutual recursion → self-recursion)
                              │                 │
                              └─── Awsum.Cps ───┘   (non-tail self-recursion → tail-self via K chain)
                                     ↓
                                Awsum.Tco             (self-tail-call → CLoop/CContinue)
                                     ↓
                                   Codegen
                                     ↓
                        LLVM / JVM / CLR / WASM / JS / Lua
```

Between Cps and Tco, [`Awsum.StackSafety`](../src/Awsum/StackSafety.hs) verifies that none of those invariants slipped — see below.

Each pass is Core-to-Core. None of them add new Core IR constructs. None of them need backend-specific support beyond what the backend already does for ordinary ADTs and functions.

### 1. `Awsum.Scc` — mutual recursion → self-recursion

[Source](../src/Awsum/Scc.hs). Runs after saturate, before CPS. Input invariant: every call-graph edge is either a direct `CCall (CVar n)` or a first-class function reference `CVar n`. Output invariant: no call-graph cycle of size > 1 — every mutual cluster has been fused into one self-recursive function.

**Algorithm.**

1. Build the call graph from Core declarations: nodes are top-level names, edges are direct callees (`CCall (CVar n)` plus first-class `CVar n`), intersected with the set of top-level names so parameters and built-ins are not counted.
2. Run Tarjan (`Data.Graph.stronglyConnComp` from `containers`) to get SCCs in topological order.
3. For each **non-trivial** (cyclic, size > 1) SCC:
   - Check the MVP precondition: every member must be a `CFunDef` (not a `CValDef`) and all members must share the same arity. If either fails, skip the SCC and leave its members alone.
   - Sort members by name for a deterministic tag assignment (`0`, `1`, …).
   - Emit one merged function `$scc$<name_0>_<name_1>_...` with signature `(fn :: Int, arg_0, arg_1, …)`. Its body is a `case` on the tag parameter, each arm carrying one member's original body with:
     - original parameter names alpha-renamed to unified `$arg_0`, `$arg_1`, …;
     - every call `f_j(x, y, …)` to a fellow SCC member rewritten to `$scc$…(CCon j [], x, y, …)`.
   - Emit one wrapper per original name: `f_i(args) = $scc$…(CCon i [], args)`. The original public name stays callable from everywhere outside the SCC.

**Why this is enough.** After merge, every cross-call has become a self-call on the merged function. Tail cross-calls are tail self-calls and fall through to TCO below. Non-tail cross-calls are non-tail self-calls and fall through to CPS.

**Why this shape.** The tag `CCon i []` and its destructuring `case fn of 0 -> …; 1 -> …` reuse the uniform container layout every backend already has for ordinary ADTs. No new IR nodes, no runtime helpers.

**Why this belongs at this position in the pipeline.** SCC must run before CPS. If CPS ran first, each member would be individually CPS'd into a `$cps$f`/`$apply$f` pair, and merging those pairs after the fact would be both semantically awkward and pointless noise in the snapshots. The current order (saturate → **SCC** → **CPS** → TCO) produces the minimal, predictable output.

**Post-SCC tree-shake.** SCC rewrites every cross-call from `f_j(...)` to `$scc$...(CCon j [...])`, so the original member's public name (the wrapper) is no longer referenced by any sibling arm. Wrappers for members that were only ever called from /inside/ the SCC end up dead, and the `treeShakeFromMain` pass in `elaborateLowerProgram` prunes them immediately after merge. In the classic `handleA ⇄ handleB` test only `handleA` is reachable from `main`, so only its wrapper survives; `handleB`'s wrapper is dropped. Same for the three-member `stepA → stepB → stepC → stepA` cycle: only `stepA` survives if that is the sole public entry point.

**Sum-typed args.** Each member's arguments are packed into a `CCon` with a member-specific tag (the field count matches that member's arity), and the merged function's parameter is a single value destructured by `case`. This means members can have different arities or different parameter types — parser-combinator style (`parseExpr : Input -> Result`, `parseBinary : Input -> Int -> Result` calling each other) is handled out of the box. See `mutual-different-arity-stress` for the cross-backend 100 000-iteration proof.

**Current limitation.** SCCs containing a `CValDef` are passed through unchanged. Mutually recursive top-level values have no fixed point — `a = b; b = a` has no evaluable value — so this is really a user-level error that the compiler currently swallows silently; a future pass will reject it with a diagnostic.

### 2. `Awsum.Cps` — non-tail self-recursion → tail-self via K chain

[Source](../src/Awsum/Cps.hs). Runs after SCC, before TCO. Input invariant: no mutual recursion — every recursive edge is now a self-loop. Output invariant: every self-call, whether originally tail or non-tail, now sits in tail position.

**Algorithm.** For each `CFunDef f args body`:

1. Scan `body` for at least one non-tail self-call (scrutinee of a case, argument of a call, field of a constructor, or anywhere nested). If none, leave the function alone.
2. Otherwise emit a triple of declarations:
   - **Wrapper**: `f args = $cps$f args KTop`. Keeps the original public name reachable from every external caller.
   - **CPS'd function**: `$cps$f args $k`. Its body is `body` walked in evaluation order (left-to-right) with every non-tail self-call rewritten. Tail positions end with `$apply$f $k <value>`.
   - **Apply function**: `$apply$f $k $x`. A `case` on `$k` that dispatches over the ADT of `K` constructors built during step 2.

**Defunctionalization by Reynolds.** Each non-tail self-call site gets a fresh `K_i` constructor. `K_i`'s fields are:

- the parent continuation (always);
- every free name referenced by the post-call remainder of the expression (sorted alphabetically for snapshot determinism), minus top-level names, minus the received-value binder, minus `$k` itself.

The post-call remainder is stored as `K_i`'s apply-arm body. When `$apply$f` fires on a `K_i` value, it alpha-renames the received-value name to `$x` (the apply function's second parameter) and `$k` to `$pk_<tag>` (the arm-bound parent continuation), then evaluates the remainder in that scope.

**Worked example.** For

```aww
countDown : Int32 -> Either UnderflowError Int32
countDown n = case eqInt32 n zero of
  True  -> Right zero
  False -> case predInt32 n of
    Left e  -> Left e
    Right m -> case countDown m of         -- non-tail self-call
      Left e  -> Left e
      Right v -> Right v
```

the pass produces [this Core](../.snapshots/successful/countdown-int32-stress/compiler/core.txt) — a wrapper `countDown` that kicks off `$cps$countDown n KTop`, a tail-recursive `$cps$countDown` whose `Right m` branch emits a `CContinue` through a freshly-constructed `K_1 $k`, and a tail-recursive `$apply$countDown` that walks the K chain and reconstructs the final `Either` value.

**Why not add `CLet` and do A-normal form first.** Adding a let node to Core would require teaching all six backends to emit "evaluate, bind to local, continue". The current design keeps post-call remainders as ordinary Core sub-expressions (walked recursively by `goNonTail` with a continuation-callback) and reuses the existing arm-binding machinery in `case`. Net effect: zero backend changes.

**Why not closures + trampoline (path B).** An alternative reading of CPS keeps continuations as closures with captured environments, and a driver loop (trampoline) runs them. That approach requires first-class closures in Core, which every backend then has to represent: LLVM structs with function pointers, JVM `MethodHandle` with bound args, CLR `Func<>` delegates, WASM `funcref` tables plus heap-allocated environments, and so on. The ADT-based defunctionalization in use here reduces to plain `case` dispatch, which every JIT compiles to a native switch, and the implementation lives in one Core-to-Core module. The K-chain story and the SCC-tag story also share the same primitive, which is the main reason the two passes compose so cleanly.

**Why `$k → $pk_<tag>` in the apply arm.** The obvious-looking alternative is to rebind the arm-captured parent continuation to the name `$k` itself (Core-level shadowing of the apply function's parameter). This works everywhere except JavaScript: our JS codegen emits arm-bound names as `const`, and the subsequent TCO-driven re-assignment of the parameter slot at the bottom of the loop would then be a write to a `const`. The alpha-rename to `$pk_<tag>` sidesteps the clash without constraining codegen.

**Works on any non-tail position.** The transformer walks `goTail`, `goNonTail`, and `goArgs` in strict evaluation order. A non-tail self-call buried inside a constructor field (`Cons (f head) (map f tail)`), inside a call argument (`g (f x)`), or inside an arbitrary case scrutinee all generate their own `K_i` with the right captures. Multiple non-tail calls in one expression chain naturally: the apply-handler of the first `K_i` can itself emit a tail call to `$cps$f` with a later `K_j`, so a pair of sibling self-calls produces a pair of Ks that ping-pong through `$apply$f` as the first's result becomes the trigger for the second.

### 3. `Awsum.StackSafety` — post-pass verifier (guard rail)

[Source](../src/Awsum/StackSafety.hs). Runs between CPS and TCO. Input invariant: after SCC and CPS, the Core program should contain no non-trivial call-graph cycle and no non-tail self-call in any `CFunDef`. This module checks exactly that and refuses to lower the program (via a `TypeError`) on any violation.

Two classes of issues are caught:

- **`MutualCycleRemains [Name]`** — Tarjan still reports a size > 1 SCC in the post-CPS call graph. Today the only way to hit this is a mutually recursive `CValDef` cluster (which `Awsum.Scc` cannot merge because constants have no fixed point, and which represents a user-level ill-formed program anyway). Any other pattern would indicate an `Awsum.Scc` bug.
- **`NonTailSelfCallRemains Name`** — a `CFunDef` still has a non-tail self-call after `Awsum.Cps` had its chance. Today this cannot fire on any test because `Awsum.Cps` handles every non-tail self-call shape. It exists as a guard rail against future regressions in the CPS pass.

The verifier produces hard `TypeError`s, not warnings — there is no escape hatch. If you see one of these messages, either the program is genuinely stack-unsafe (mutually recursive `CValDef`s) or the compiler has a bug. The canonical failing program looks like:

```aww
foo : String
foo = bar

bar : String
bar = foo
```

which the compiler rejects with `Mutually recursive top-level declarations cannot be made stack-safe: bar, foo`. See [`test/sources/errors/mutually-recursive-values`](../test/sources/errors/mutually-recursive-values/code/Main.aww).

### 4. `Awsum.Tco` — self-tail-call → `CLoop` / `CContinue`

[Source](../src/Awsum/Tco.hs). Runs last in the Core pipeline. Input invariant: every self-call is in tail position (enforced by the two preceding passes plus whatever the user wrote). Output: the body is wrapped in a `CLoop`, and each self-tail-call is rewritten to `CContinue` carrying the new argument values.

Both `$cps$f` and `$apply$f` generated by CPS are self-tail-recursive, so this pass folds them into jump-and-rebind loops. The merged `$scc$…` function from SCC is also self-tail-recursive (for the tail branches) and gets the same treatment; its non-tail branches went through CPS first.

No transformation is applied to functions that lack a self-tail-call; their Core snapshots are unchanged.

Per-backend emission details (how `CLoop` / `CContinue` lower to a jump on each target) live in [targets.md — Recursion and tail calls](targets.md#recursion-and-tail-calls).

## Why these three passes compose

Each pass has a tightly-defined precondition and postcondition. The preconditions of the later pass match the postconditions of the earlier one:

| Pass          | Precondition (input)                                                   | Postcondition (output)                                   |
| ------------- | ---------------------------------------------------------------------- | -------------------------------------------------------- |
| `Scc`         | any Core program                                                       | no call-graph cycle of size > 1 among mergeable members  |
| `Cps`         | no mergeable call-graph cycle                                          | every self-call is in tail position                      |
| `StackSafety` | both of the above                                                      | `TypeError` on any violation; unchanged Core on success  |
| `Tco`         | every self-call is in tail position                                    | self-tail-calls are `CContinue` in a `CLoop`             |

This is what the earlier design document called "applying Reynolds' defunctionalization to two different objects": SCC defunctionalizes **which function is active**, CPS defunctionalizes **what to do after the current call returns**. Both produce ordinary ADTs dispatched by ordinary `case` expressions, which the backends already handle.

## Stack-safety test matrix

| Test                                                                                                      | Shape                                             | Depth     | What it verifies                                                                                                                                                     |
| --------------------------------------------------------------------------------------------------------- | ------------------------------------------------- | --------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`countdown-int32-stress-tail`](../test/sources/successful/countdown-int32-stress-tail/code/Main.aww)     | tail self                                         | 100 000   | TCO folds `Right m -> countDown m` into a loop on all six targets.                                                                                                   |
| [`countdown-int32-stress`](../test/sources/successful/countdown-int32-stress/code/Main.aww)               | non-tail self (case scrutinee)                    | 100 000   | CPS moves post-call `Left e -> Left e` / `Right v -> Right v` reconstruction into a K chain.                                                                         |
| [`countdown-uint8-tail`](../test/sources/successful/countdown-uint8-tail/code/Main.aww)                   | tail self with accumulator                        | 255       | Same as tail stress but exercises accumulator threading through `CContinue`.                                                                                         |
| [`countdown-uint8`](../test/sources/successful/countdown-uint8/code/Main.aww)                             | non-tail self, post-call captures outer parameter | 255       | `K_1` carries `n` from outer scope for use inside `Right (showUInt8 n ++ "," ++ s)`.                                                                                 |
| [`adt-list-map`](../test/sources/successful/adt-list-map/code/Main.aww)                                   | non-tail self in `CCon` field                     | 3         | Exercises the general CPS path: self-call in `Cons head (map f tail)`. Depth is small because the test is about the shape, not stack pressure.                       |
| [`mutual-recursion`](../test/sources/successful/mutual-recursion/code/Main.aww)                           | mutual, mixed tail + non-tail cross-calls         | 4         | SCC-merges `handleA` ⇄ `handleB` into `$scc$handleA_handleB`; the merged function's non-tail cross-calls (`"A" ++ handleB StepB`) go through CPS.                    |
| [`even-odd-stress`](../test/sources/successful/even-odd-stress/code/Main.aww)                             | mutual, all tail                                  | 1 000 000 | SCC turns `evenInt` ⇄ `oddInt` into self-recursion, TCO folds that into a loop. Classic "mutual tail recursion must not blow up."                                    |
| [`mutual-different-arity-smoke`](../test/sources/successful/mutual-different-arity-smoke/code/Main.aww)   | mutual, heterogeneous arity (1 arg ⇄ 2 args)      | small     | Shape regression anchor: SCC merges members of different arity via sum-typed args `CCon`.                                                                            |
| [`mutual-different-arity-stress`](../test/sources/successful/mutual-different-arity-stress/code/Main.aww) | mutual, heterogeneous arity, all tail             | 100 000   | `pingOne` (1 arg) ⇄ `pongTwo` (2 args) alternating — the sum-typed merge threads the right number of fields per iteration, TCO folds the fused function into a loop. |
| [`mutual-three-way-stress`](../test/sources/successful/mutual-three-way-stress/code/Main.aww)             | mutual, three-way cycle, all tail                 | 1 000 000 | `stepA → stepB → stepC → stepA`: SCC handles cycles of arbitrary length; the merged function dispatches over three tags but each iteration stays on the same frame.  |
| [`recursive-function-call`](../test/sources/successful/recursive-function-call/code/Main.aww)             | tail self via small ADT                           | small     | Smoke test for direct TCO through an enum-driven loop.                                                                                                               |

Every test in the table runs on all six backends with byte-identical stdout via `ProgramSnapshotsSpec`.

## The role of whole-program compilation

The designs above assume every callee is visible when the passes run. Awsum compiles whole-program from source (including the prelude, which is embedded into the binary via `file-embed`), so this assumption holds by construction. A separate-compilation language would either have to do the SCC / CPS passes at link time or give up and rely on whatever native TCO the target provides — and JVM and JS do not provide cross-method tail-call support, so the guarantees would not hold uniformly.

The whole-program story also makes the tree-shake honest. Generated `K_i` constructors, `$cps$f`, `$apply$f`, and `$scc$…` functions are reachable only from live user code; anything unused is dropped before codegen. A prelude entry that no program references costs nothing.

## Pre-existing bugs surfaced during this work

Non-tail self-recursion produces nested `case` expressions whose outer arm-bindings must stay live inside the inner case body — the captures of `K_i` come from exactly such bindings. That pattern had not appeared in any test before the CPS pass landed, and several backends had latent slot-allocation bugs that only surfaced once CPS started generating the shape. All fixed together:

- **CLR text ([`Codegen/CLR.hs`](../src/Awsum/Codegen/CLR.hs))** — `zip vars [0..]` in each `CCase` arm would overwrite outer bindings with inner ones. Fixed by computing the next free `ldloc` slot from the current `varMap`'s ldloc entries and allocating inner bindings beyond that.
- **CLR binary ([`Codegen/CLR/Assemble.hs`](../src/Awsum/Codegen/CLR/Assemble.hs))** — fixed `arrSlot = 0` and `bindSlotStart = 1` in each `CCase`. Fixed by `arrSlot = max(Map.elems eLocals) + 1`, which jumps past every live local including outer array scratch slots (those are not tracked in `eLocals` but stay live for the arm body). `exprLocalsNeeded` was already additive; the mismatch was in the emitter.
- **WASM binary ([`Codegen/WASM/Assemble.hs`](../src/Awsum/Codegen/WASM/Assemble.hs))** — fixed `ecBoundBase` across nested cases; inner `bindArmVars` overwrote outer slots. Fixed by bumping `ecBoundBase` by `length vars` in the returned context, and changing `exprMaxBoundVars` to sum along the deepest nesting path instead of taking max.
- **WASM text ([`Codegen/WASM.hs`](../src/Awsum/Codegen/WASM.hs))** — arm bindings were inline `i32.load offset=N (local.get $__scrut)` expressions sharing one `$__scrut` local. Inner cases overwrote `$__scrut`, turning outer bindings into garbage on next use. Fixed by pre-declaring one WASM local per unique arm-binding name (collected by `caseBoundVars` over the whole function body), materialising values on arm entry with `local.set`, and pointing `wLocalExprs` at `(local.get $v_<name>)`.
- **WASM allocator (both codegens)** — `memory.grow 1` fired once per `__alloc` when the heap exceeded the current page boundary. A single CPS-defunctionalized unwind on `countdown-uint8` overshot by more than one page in a single allocation and wrote into unmapped memory before the next alloc could grow. Fixed by looping `memory.grow 1` until the heap fits.

## Open extensions (deferred)

Still to do for a complete stack-safety story.

- **Monadic recursion.** Desugaring `do` into `>>=` calls in elaboration makes monadic code flow through the same SCC + CPS passes. Works transparently for "ordinary" monads (`IO`, `State`, `Reader`, `Writer`, `Either`, `Maybe`) whose `>>=` does not itself encode deep control flow; exotic monads (continuations, free monads with deep nesting, search with backtracking) will need an explicit `tailRecM` method à la PureScript. The prerequisites (type classes, monads, `do`-desugaring) are unimplemented today.

## References

- [`Awsum.Scc`](../src/Awsum/Scc.hs), [`Awsum.Cps`](../src/Awsum/Cps.hs), [`Awsum.Tco`](../src/Awsum/Tco.hs) — the three passes.
- [`Awsum.StackSafety`](../src/Awsum/StackSafety.hs) — post-pass verifier.
- [`Awsum.CallGraph`](../src/Awsum/CallGraph.hs) — shared call-graph + self-call analysis.
- [`Awsum.ElaborateLower`](../src/Awsum/ElaborateLower.hs) — pipeline wiring.
- [Per-backend emission of `CLoop` / `CContinue`](targets.md#recursion-and-tail-calls) in `targets.md`.
