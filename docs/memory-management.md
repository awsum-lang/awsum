# Memory management

How heap allocations are reclaimed on each backend. The user writes no annotations and sees no defaults — every reclaim point is computed from the Core IR.

## Guarantee to the user

Every heap-allocated cell — ADT constructor, boxed primitive, string — is reclaimed once it is no longer reachable, on every backend, with no manual `free`, no manual `Rc::clone`, no manual `null` assignment, no GC hint.

Identical reclaim semantics across all five backends. The mechanism differs by target:

| Backend | Reclaim mechanism                                                                 |
| ------- | --------------------------------------------------------------------------------- |
| JVM     | Host JVM garbage collector (G1/ZGC)                                               |
| CLR     | Host CLR generational garbage collector                                           |
| JS      | Host JS engine garbage collector (V8/JSC)                                         |
| LLVM    | Compiler-emitted reference counting over libc `malloc` / `free`                   |
| WASM    | Compiler-emitted reference counting over a per-size-bin freelist in linear memory |

## Why reference counting on LLVM and WASM

Tracing GC needs precise root identification, type information at every heap block, and (on WASM) a shadow stack. Reference counting needs only a header on each heap block and a balanced inc/dec discipline. Three language-level invariants make the latter sufficient:

1. **Immutability.** A field cannot be rewritten after construction, so the cell graph is acyclic. Reference counting is complete; no mark-sweep fallback is needed.
2. **Closed world after defunctionalization.** No first-class function value survives [Awsum.Defunctionalize](../src/Awsum/Defunctionalize.hs) and [Awsum.LowerClosures](../src/Awsum/LowerClosures.hs). Every pointer flow is visible in Core, so the compiler can place the right inc/dec at every transfer.
3. **Uniform heap-block shape.** Every heap block is one of: ADT cell (`CCon` lowering), structural-sum cell (`CRow` lowering, a 1-field constructor), boxed primitive, or string. All four are positional `[tag, field₀, …]`-style blocks reachable through a uniform header.

## Heap-block layout on LLVM and WASM

Each heap block carries a 12-byte header preceding the user-visible pointer:

```
  offset       field        size
  -12          flag         i32
   -8          refcount     i32
   -4          shape        i32
    0          user data    …
```

The user-facing pointer always points 12 bytes past the block start. Readers (string-length headers, ADT-tag at slot 0, constructor fields at slot 1+) operate on the user pointer and are unaware of the header.

- **`flag`** identifies the block class.
  - `flag == 0`: literal in static data (`@.str.N` on LLVM, `(data …)` on WASM). `__inc_ref` / `__free_recursive` / `__free` all short-circuit. The block is never reclaimed.
  - `flag == 1` on LLVM: heap block from `__alloc`, releasable via `free`.
  - `flag == <power-of-2>` on WASM (8, 16, 32, …, 4096): heap block whose size identifies which bin to push it onto on free.
- **`refcount`** is initialised to `1` by `__alloc` (the single owner returned to the caller). Adjusted by `__inc_ref` and `__free_recursive`.
- **`shape`** is the number of pointer fields starting at slot 1. Used by `__free_recursive` to recurse into children. A `shape == 0` block (boxed primitive, nullary constructor, string) has no child pointers; a `Cons`-shaped block has `shape == 2`; a `Tuple3` has `shape == 3`; and so on.

String literals carry the same header in static data with `flag = refcount = shape = 0`, so `CDrop` on a binder that may hold either a literal or a heap string is uniformly safe.

The header lives at `[Awsum.Codegen.LLVM](../src/Awsum/Codegen/LLVM.hs)` and `[Awsum.Codegen.WASM](../src/Awsum/Codegen/WASM.hs)`.

## Runtime helpers

Four helpers are emitted once per program (gated on whether the program references them):

- **`__alloc(size, shape)`** — allocate a block.
  - LLVM: `malloc(size + 12)`, write `flag=1, refcount=1, shape`, return `user_ptr = raw + 12`.
  - WASM: `__alloc_shaped(size, shape)` rounds `size` up to the next power of two (min 8), pops the matching bin if non-empty (reinitialising the header), otherwise bump-allocates and grows linear memory on demand. Bin head pointers live in linear memory at offsets `24 + (ctz(rounded) - 3) * 4` for size classes 8 through 4096. Bumping past `memory.grow == -1` traps via `unreachable`.
- **`__free(p)`** — return a block.
  - LLVM: if `flag == 1`, call libc `free(p - 12)`; otherwise no-op.
  - WASM: if `flag == 0`, no-op; if `flag > 4096`, leak (no matching bin); otherwise push the block onto `bin[flag]`, storing the previous head as the next-pointer at block offset 8 (`user_ptr - 4`).
- **`__inc_ref(p)`** — increment the refcount at `user_ptr - 8`. No-op on literals (`flag == 0`).
- **`__free_recursive(p)`** — decrement the refcount. On reaching zero, read `shape`, push slots `1..shape-1` onto the global worklist (see below), iterate the outer loop with `slot[shape]` as the new `p`, and return the current block via `__free`. When the current cell does no cascading work (literal, refcount > 0, shape == 0) the helper pops the next pending pointer from the worklist; on empty it returns. System-stack footprint is O(1) regardless of cascade shape. Immutability makes the cell graph acyclic, so the cascade terminates.

  The worklist lives off the system stack — a heap-allocated pointer buffer, doubled on overflow (initial 16 entries), single-threaded global state shared across all `__free_recursive` calls. On LLVM, three module-level globals (`@__free_worklist`, `@__free_worklist_top`, `@__free_worklist_cap`) plus a `@__free_worklist_push` helper backed by `realloc`. On WASM, three WASM globals (`$__wl_buf`, `$__wl_top`, `$__wl_cap`) plus a `$__free_worklist_push` helper backed by `__alloc_shaped` (old buffers ≤ 4096 bytes return to a bin via `__free`; larger ones leak with total leak ≤ 2× current capacity because doubling halves each predecessor). `top` is 0 between every top-level `__free_recursive` call — the helper drains its own pushes before returning — so no state leaks across calls. Awsum is single-threaded and runtime helpers never call user code, so the global buffer is non-reentrant by construction.

## The inc/dec discipline

Every cell follows a balanced `+1` / `-1` history:

- **Allocation** brings `+1` (the owner returned by `__alloc`).
- **Transfer** brings `+1` per new holder. A transfer position is any place a borrowed binder is stored into long-lived state — `CCall` arg, `CCon` field, `CRow` value, `CContinue` arg, `CReuse` field, `CCase` arm-binder extract. Codegen emits `__inc_ref` whenever the source expression resolves to a borrowed local or function parameter (see `borrowedSource` / `emitIncIfCVar` in [Awsum.Codegen.LLVM](../src/Awsum/Codegen/LLVM.hs)). Fresh-allocation sources need no inc — they bring their own `+1` from `__alloc`. This includes `CCon`, `CCall`, `CIntLit`, `CString`, and `CVar` references to top-level `CValDef`s (each such reference lowers to a `call @v_name()` whose body re-allocates a fresh cell).
- **Built-in `CCall`** uses callee-owns args: every built-in helper dec's its incoming pointers at the end via `__free_recursive`, and the caller adds the same inc-on-`CVar` rule that applies to user calls. The discipline is uniform between user and built-in calls.
- **Drop** brings `-1`. Drop placement is described next.

JVM, CLR, and JS do not participate in this discipline: the host GC tracks references and the codegen for those backends never emits inc.

## Drop insertion

[Awsum.Lifetime.insertDrops](../src/Awsum/Lifetime.hs) runs once after [Awsum.Tco](../src/Awsum/Tco.hs), annotating the Core IR with `CDrop k n body` nodes. The semantics is "evaluate `body`; after its value has been produced, dec `n`". Two classes of drop are emitted:

1. **Parameter drop at every `CContinue`.** Each parameter that is overwritten by the next loop iteration is wrapped in `CDrop` immediately before the `CContinue`. Codegen emits the dec after the next-iteration argument values are computed but before they are stored into the parameter slots, so the staged values are still readable when the dec fires.
2. **Arm-binder drop at every `CCase` / `CRowCase` arm.** Each pattern binder is wrapped in `CDrop` around the arm body. Codegen pairs this with an inc on the extracted slot at the binding site, so the matched cell's slots do not hold stale references after the dec cascade.

A third class of decs — for parameters that survive to a non-`CContinue` terminal in the function body — is handled directly by codegen rather than by inserting `CDrop` here. Outer-wrapping the whole body in a `CDrop` per parameter would shadow inner `CContinue` drops (the inner drop would see the parameter as already-dropped via `outerDropped` and skip emit). Codegen tracks parameters explicitly and dec's each one before the value-tail return, with a move-semantics carve-out: if the tail expression is a `CVar p` that names a parameter, `__inc_ref` is emitted on the result before the dec, so ownership is transferred to the caller instead of the cell being freed and the caller receiving a dangling pointer.

## Drop lowering per backend

- **LLVM**: `CDrop _ n body` lowers to `call void @__free_recursive(ptr %n)` after `body`'s value is produced. See [Awsum.Codegen.LLVM](../src/Awsum/Codegen/LLVM.hs).
- **WASM**: same shape, calling `$__free_recursive` in WAT and the corresponding function index in the binary assembler. See [Awsum.Codegen.WASM](../src/Awsum/Codegen/WASM.hs) and [Awsum.Codegen.WASM.Assemble](../src/Awsum/Codegen/WASM/Assemble.hs).
- **JVM**: parameter drop becomes `aconst_null; astore <slot>`. Arm-binder drops are no-ops — case-binders live in block-scoped slots that the host GC reclaims when the arm exits. Operand-stack net effect per pair is zero, so staged `CContinue` arguments stay in order. See [Awsum.Codegen.JVM](../src/Awsum/Codegen/JVM.hs).
- **CLR**: parameter drop becomes `ldnull; starg.s <i>`. Same shape and rationale as JVM. See [Awsum.Codegen.CLR](../src/Awsum/Codegen/CLR.hs).
- **JS**: parameter drop becomes `<param> = null;`. Arm-binders are declared with `const` and cannot be reassigned; their slots die with the lexical scope. See [Awsum.Codegen.JS](../src/Awsum/Codegen/JS.hs).

## Stack safety of the cascade

`__free_recursive` makes O(1) use of the system stack on every cascade shape: non-last children of cells with `shape > 1` are pushed onto the global worklist (see the `__free_recursive(p)` entry above) and processed in the helper's own outer loop, instead of recursed via `call __free_recursive`. The previous implementation tail-jumped only on the last slot and called recursively on the rest; that required a 256 MiB stack reservation (`-Wl,-stack_size,0x10000000` on POSIX, `-W max-wasm-stack=268435456` on wasmtime) sized to the *iteration count*, which is wrong — stack size should be a function of the program, not of how many times its loops run. With the worklist the reservation is gone; platform-default stacks (typically 8 MiB on POSIX, 1 MiB inside wasmtime) cover the residual user-call graph already bounded by [Awsum.StackSafety](../src/Awsum/StackSafety.hs).

The worklist itself grows on the heap with each cascade's max in-flight frontier — a function of data shape, not iteration count.

## Cell reuse

[Awsum.Reuse.insertReuse](../src/Awsum/Reuse.hs) runs after `insertDrops` and recognises the canonical Lean 4-style pattern of a scrut drop inside the arm of a linear case-scrutinee:

```
CCase (CVar n) [..., (tag_in, [v1..vk], CDrop _ n inner), ...]
```

where `inner` contains a `CCon t fields` with `length fields == k` (matching the arm's pattern arity). Such a `CCon` is rewritten to `CReuse n t fields`, and the outer `CDrop n` is stripped. The pass distributes into nested `CCase` / `CRowCase` arms — each arm independently rewrites if its path contains a scrut drop; arms without it keep their original allocation. Per arm at most one `CCon` is rewritten (there is only one cell to give back).

`insertDrops` produces the in-arm scrut drop in two places. A **parameter** is dropped at every `CContinue` (`addContinueDrops`) — the original producer, covering the TCO'd loop whose argument pack is rebuilt each iteration. A **binder whose sole use is the scrutinee of an inner case on its scope's spine** (a case every execution reaches — one only some paths reach keeps the scope wrap, or the bypassing paths would leak the binder) has its drop sunk into that case's arms instead of wrapping its scope (`soleScrutineeUse` / `sinkScrutDrop` — the dec still fires after the chosen arm's value, the same point the scope wrap expressed). The second producer is what makes the continuation cells of `$scc$`-merged CPS functions reusable: the merged loop's case on `$args` binds the K-cell `$k`, the inner case on `$k` rebuilds a same-arity K-cell inside the pack rebuild, and both cells die there.

The match is **innermost-first** (a constructor's fields are searched before the constructor itself): nested scrutinees' passes run before their enclosing case's, so an inner cell pairs with the inner reconstruction and leaves the enclosing cell to the enclosing scrut — with equal arities (a two-field pack carrying a two-field list cell, the `reverse` shape) the outermost-first order would let the inner pass steal the pack. The result is nested reuse, `CReuse n_outer t [", CReuse n_inner t' […]]`: a `mirror`/`reverse`-style hot loop rebuilds both its pack and its data cell in place and allocates nothing.

For a binder-target the refcount accounting balances with no new elisions: the binder enters the arm at `rc = 2` (the parent cell's slot plus its extract-inc); the enclosing reuse's dec-old of that slot releases the parent's reference; the stripped sunk drop never decs — its `+1` *becomes* the reference the new holder's slot stores (a `CReuse` result is a fresh source, stored without inc). Arms where the reuse does not fire keep the sunk drop and free the binder exactly where the scope wrap would have.

Every `CReuse` carries a `ReuseMode` — the uniqueness evidence the pass attaches by looking at the dying cell's constructor tag:

- **`ReuseUnique`** — the tag was minted at or above the pre-Scc `nextFreshConTag` floor, so the cell is an Scc argument pack or a Cps continuation: created and consumed entirely inside the compiler-generated loop, never stored into user data, never visible to user code. No other holder can exist; every backend mutates in place unconditionally.
- **`ReuseGuarded`** — a user-visible cell (a list node, a tree node, an IO step). The local drop only proves the *binder's* reference dies; the caller may retain the structure — Awsum is pure, so `let ys = reverse xs` keeps `xs` readable, and an unconditional in-place rewrite would corrupt it (observed: four backends printing `2e` against LLVM's `22` on an eight-line program, pinned by `memory_reuse-shared-retained`). LLVM and WASM mutate under a runtime uniqueness check with copy-on-write; the managed backends have no refcount header to check and lower the node as the allocation it replaced.

On LLVM and WASM, the guarded lowering of `CReuse n t fields` is in-place mutation under the refcount check (a `ReuseUnique` cell takes the in-place sequence with no branch):

- **`refcount == 1`** (uniquely owned): write `t` into slot 0 and the field values into slots 1..k of the existing cell at `n`. For each slot, dec the old value before overwriting; for each new `CVar` field source, inc; for each fresh source (`CCon`/`CCall`/`CIntLit`/`CString`) no inc (it brings its own `+1`). The cell's own refcount stays at 1. The pre-existing flag and shape header are left intact.

  Two refcount-bookkeeping elisions fire on this path:

  - **Self-move.** When a new field is `CVar v` and `v` is the arm-pattern binder at the same slot, the slot's stored pointer is already what we'd write — dec-old, inc-new, and store all cancel and are skipped.
  - **Permutation-move.** When a new field is `CVar v` where `v` is an arm-pattern binder at *some other* slot of the same scrut, the cell still owns `v` after the rewrite (just at a different slot). Codegen skips the dec-old of `v`'s old slot and the inc-new of its new slot; the store at the new slot is still emitted. The arm-binder's own inc-on-extract and CDrop also vanish when `v`'s only use is this one `CReuse` field (the linearity precondition is checked by [`Awsum.Lifetime.elidableArmBinders`](../src/Awsum/Lifetime.hs)).

- **`refcount > 1`** (shared with another live holder): copy-on-write. Allocate a fresh cell of the right shape, write `t` and the fields into it, `__free_recursive` on `n` (which dec's its refcount, leaving the other holders intact). Every `CVar` field gets its own `__inc_ref` here unconditionally — the fresh cell takes its own reference, and the old cell stays alive at `rc-1` still holding its own references; the elisions above apply only to the in-place path.

A field that itself contains a `CReuse` (the nested-reuse shape) is **not pre-evaluated** with the other fields on LLVM — it evaluates inside each branch, and only that ordering makes the nested uniqueness check meaningful. On the in-place path the enclosing cell's dec-old has already released the parent-slot reference to the nested target, so its `rc` is 1 exactly when nothing else holds it; on the copy path no dec has happened, the target still carries the parent-slot reference on top of its extract-inc, the nested check fails, and the nested reuse copies too — leaving the shared original intact. The nested target's `rc` is the same number in both worlds (the sharing lives one level up, on the enclosing cell), so pre-evaluating would mutate a cell the copy path still needs.

On JVM, CLR, and JS, a `ReuseUnique` cell lowers to plain field-overwrite of the existing array — `aastore` on JVM, `stelem.ref` on CLR, comma-expression `(n[0] = tag, n[1] = f₁, …, n)` on JS. There is no refcount header on managed-runtime heap blocks, so no runtime branch is possible — which is exactly why a `ReuseGuarded` cell lowers there as the plain allocation it replaced (the host GC reclaims the dead original).

## Pipeline placement

```
… → Awsum.Tco → Awsum.Lifetime.insertDrops → Awsum.Reuse.insertReuse → Codegen
```

Both passes run inside `elaborateLowerProgram` ([Awsum.ElaborateLower](../src/Awsum/ElaborateLower.hs)), after all stack-safety-shaping passes have stabilised the IR. Drop insertion runs first so cell reuse can rely on its drop placement as a proxy for the linear-use precondition.
