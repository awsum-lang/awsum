# Memory management

How heap allocations are reclaimed on each backend. The user writes no annotations and sees no defaults — every reclaim point is computed from the Core IR.

## Guarantee to the user

Every heap-allocated cell — ADT constructor, boxed primitive, string — is reclaimed once it is no longer reachable, on every backend, with no manual `free`, no manual `Rc::clone`, no manual `null` assignment, no GC hint.

Identical reclaim semantics across all five backends. The mechanism differs by target:

| Backend | Reclaim mechanism |
| ------- | ----------------- |
| JVM     | Host JVM garbage collector (G1/ZGC) |
| CLR     | Host CLR generational garbage collector |
| JS      | Host JS engine garbage collector (V8/JSC) |
| LLVM    | Compiler-emitted reference counting over libc `malloc` / `free` |
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
- **`__free_recursive(p)`** — decrement the refcount. On reaching zero, read `shape`, recurse on slots `1..shape-1`, then return the block via `__free`. For linear chains (lists, continuation chains) the last pointer slot is tail-jumped iteratively in the helper itself so the system stack does not grow with chain depth. Immutability makes the cell graph acyclic, so the recursion terminates.

## The inc/dec discipline

Every cell follows a balanced `+1` / `-1` history:

- **Allocation** brings `+1` (the owner returned by `__alloc`).
- **Transfer** brings `+1` per new holder. A transfer position is any place a borrowed binder is stored into long-lived state — `CCall` arg, `CCon` field, `CRow` value, `CContinue` arg, `CReuse` field, `CCase` arm-binder extract. Codegen emits `__inc_ref` whenever the source expression is a `CVar` (see `sourceCVar` / `emitIncIfCVar` in [Awsum.Codegen.LLVM](../src/Awsum/Codegen/LLVM.hs)). Fresh-allocation sources (`CCon`, `CCall` to an alloc-producing helper, `CIntLit`, `CString`) already carry their `+1` from `__alloc` and need no inc.
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

`__free_recursive` walks linear chains iteratively (tail-jumping on the last pointer slot) and recurses on earlier slots. To absorb the residual recursion on cells with more than one pointer field at deep nesting, both targets reserve a large reclamation stack:

- LLVM links with `-Wl,-stack_size,0x10000000` on POSIX (256 MiB).
- The test runner and `awsum run -t wasm` invoke `wasmtime` with `-W max-wasm-stack=268435456` (256 MiB).

## Cell reuse

[Awsum.Reuse.insertReuse](../src/Awsum/Reuse.hs) runs after `insertDrops` and recognises the canonical Lean 4-style pattern produced by `addContinueDrops` under a linear case-scrutinee:

```
CCase (CVar n) [..., (tag_in, [v1..vk], CDrop _ n inner), ...]
```

where `inner` contains a `CCon t fields` with `length fields == k` (matching the arm's pattern arity). Such a `CCon` is rewritten to `CReuse n t fields`, and the outer `CDrop n` is stripped. The pass distributes into nested `CCase` / `CRowCase` arms — each arm independently rewrites if its path contains a scrut drop; arms without it keep their original allocation. Per arm at most one `CCon` is rewritten (there is only one cell to give back).

Backend lowering of `CReuse n t fields` is in-place mutation guarded by a runtime refcount check:

- **`refcount == 1`** (uniquely owned): write `t` into slot 0 and the field values into slots 1..k of the existing cell at `n`. For each slot, dec the old value before overwriting; for each new `CVar` field source, inc; for each fresh source (`CCon`/`CCall`/`CIntLit`/`CString`) no inc (it brings its own `+1`). A self-move (new value equals the arm-pattern binder at the same slot) skips the dec / inc / store entirely. The cell's own refcount stays at 1. The pre-existing flag and shape header are left intact.
- **`refcount > 1`** (shared with another live holder): copy-on-write. Allocate a fresh cell of the right shape, write `t` and the fields into it (same inc-on-`CVar` rule), then `__free_recursive` on `n` (which dec's its refcount, leaving the other holders intact).

On JVM, CLR, and JS, `CReuse` lowers to plain field-overwrite of the existing array — `aastore` on JVM, `stelem.ref` on CLR, comma-expression `(n[0] = tag, n[1] = f₁, …, n)` on JS. There is no refcount header on managed-runtime heap blocks, so the runtime branch on uniqueness is absent.

## Pipeline placement

```
… → Awsum.Tco → Awsum.Lifetime.insertDrops → Awsum.Reuse.insertReuse → Codegen
```

Both passes run inside `elaborateLowerProgram` ([Awsum.ElaborateLower](../src/Awsum/ElaborateLower.hs)), after all stack-safety-shaping passes have stabilised the IR. Drop insertion runs first so cell reuse can rely on its drop placement as a proxy for the linear-use precondition.
