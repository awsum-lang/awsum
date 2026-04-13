# Target Implementation Details

How the same Awsum program maps to each compilation target. All targets produce identical stdout for the same input — this is a compiler invariant, verified by the test suite.

## Overview

| | JS | Lua | LLVM | JVM | WASM |
|---|---|---|---|---|---|
| **Runtime** | Node.js 14+ | Lua 5.1+ | Native binary (via Clang 15+) | Java 7+ | wasmtime (WASI) |
| **String type** | Native JS string | Native Lua string | `ptr` to null-terminated C string | `java.lang.String` (boxed as `Object`) | `i32` pointer to null-terminated bytes in linear memory |
| **Concat** | `+` | `..` | `strlen` + `malloc` + `strcpy` + `strcat` | `String.concat` | `__concat`: strlen + bump alloc + memcpy |
| **Print** | `process.stdout.write(s)` | `io.write(s)` | `printf("%s", s)` | `System.out.print(s)` | WASI `fd_write` via iovec |
| **Constants** | `const name = expr;` | `name = expr` (global) | Zero-arg function, called on each use | Zero-arg static method, called on each use | Zero-arg function, called on each use |
| **Functions** | `function` declaration (hoisted) | `function ... end` | `define ptr @name(ptr ...) { ... }` | `static Object v_name(Object...) { ... }` | `(func $v_name (param i32 ...) (result i32) ...)` |
| **Higher-order** | First-class values | First-class values | Opaque `ptr` indirect call | `MethodHandle` (`ldc` + `invokevirtual invoke`) | `funcref` table + `call_indirect` |
| **Memory** | GC | GC | Manual (`malloc`, no `free`) | GC | Bump allocator (no free) |
| **Name mangling** | `v_` prefix, `main` unchanged | `v_` prefix, `main` unchanged | `v_` prefix for all (including `main` → `v_main`) | `v_` prefix for all (including `main` → `v_main`) | `v_` prefix for all (`_start` is WASI entry) |

## String Concatenation

All five backends guarantee identical results because the type checker ensures both operands are `String`.

**JS** — uses native `+`, which is string concatenation when both sides are strings:
```javascript
("Hello" + ", " + name + "!")
```

**Lua** — uses native `..`, which is string concatenation:
```lua
("Hello" .. ", " .. name .. "!")
```

**LLVM** — runtime helper allocates a new buffer and copies both strings:
```llvm
define ptr @__concat(ptr %a, ptr %b) {
  %la = call i64 @strlen(ptr %a)
  %lb = call i64 @strlen(ptr %b)
  %sum = add i64 %la, %lb
  %total = add i64 %sum, 1
  %buf = call ptr @malloc(i64 %total)
  call ptr @strcpy(ptr %buf, ptr %a)
  call ptr @strcat(ptr %buf, ptr %b)
  ret ptr %buf
}
```

**JVM** — casts both operands to `String` and uses `String.concat`:
```
invokestatic AwsumMain/__concat(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;
```

**WASM** — runtime helper computes lengths, bump-allocates a new buffer, copies both strings, and null-terminates:
```wasm
(call $__concat (local.get $a) (local.get $b))
;; strlen(a) + strlen(b) → alloc(la+lb+1) → memcpy(buf,a,la) → memcpy(buf+la,b,lb) → store8 0
```

## Print

All backends print without a trailing newline — `IO.Stdout.print` outputs exactly what it receives.

**JS**: `process.stdout.write(String(s))` — unbuffered for TTY, buffered for pipes, flushed on exit.

**Lua**: `io.write(tostring(s))` — buffered, flushed on exit.

**LLVM**: `printf("%s", s)` — C stdio buffering, implicit flush on `return 0` from `main`.

**JVM**: `System.out.print(s)` — buffered PrintStream, flushed on JVM exit.

**WASM**: WASI `fd_write` — stores an iovec (pointer + length) at scratch memory offset 0, calls `fd_write(1, iov, 1, nwritten)`.

## Constants (CValDef)

Zero-argument definitions like `greeting = "Hello"` are compiled differently per target:

**JS**: `const v_greeting = "Hello";` — evaluated once, hoisted by the runner.

**Lua**: `v_greeting = "Hello"` — global assignment, evaluated once before `main` runs.

**LLVM**: Zero-arg function `define ptr @v_greeting() { ... }` — called each time the value is referenced. Safe because all expressions are pure (same result every time). Avoids the complexity of LLVM global initializers for non-constant expressions.

**JVM**: Zero-arg static method `static Object v_greeting() { ... }` — same approach as LLVM, called each time. The JVM JIT compiler can inline these.

**WASM**: Zero-arg function `(func $v_greeting (result i32) ...)` — same approach as LLVM and JVM.

## Higher-Order Functions

`compose g f x = g (f x)` — parameters `g` and `f` can be functions.

**JS/Lua**: Functions are first-class values. Parameters that are functions are called with `(callee)(args...)`:
```javascript
function v_compose(v_g, v_f, v_x){ return (v_g)((v_f)(v_x)); }
```

**LLVM**: Functions are passed as opaque pointers (`ptr`). Indirect calls work because all user functions have the same shape — take `ptr` args, return `ptr`:
```llvm
define ptr @v_compose(ptr %v_g, ptr %v_f, ptr %v_x) {
  %t0 = call ptr %v_f(ptr %v_x)
  %t1 = call ptr %v_g(ptr %t0)
  ret ptr %t1
}
```

This uses LLVM 15+ opaque pointers — no `bitcast` or typed function pointer annotations needed.

**JVM**: Function values are `java.lang.invoke.MethodHandle` (available since Java 7, class version 51.0). When a function is used as a value (not called directly), it is loaded as a `CONSTANT_MethodHandle` from the constant pool via `ldc`. Indirect calls use `invokevirtual MethodHandle.invoke(...)`:
```
; compose g f x = g (f x)
.method public static v_compose(Object, Object, Object) → Object
  aload_1                          ; f (MethodHandle)
  checkcast java/lang/invoke/MethodHandle
  aload_2                          ; x
  invokevirtual MethodHandle.invoke(Object)Object
  ; g(result)
  aload_0                          ; g (MethodHandle)
  checkcast java/lang/invoke/MethodHandle
  swap
  invokevirtual MethodHandle.invoke(Object)Object
  areturn
```

Direct calls to known functions use `invokestatic` — no MethodHandle overhead.

**WASM**: Function values are table indices (`i32`). All user `CFunDef`s are placed in a `funcref` table. When a function is used as a value, it becomes `(i32.const <table_index>)`. Indirect calls use `call_indirect` with a per-arity type signature:
```wasm
;; compose g f x = g (f x)
(func $v_compose (param $v_g i32) (param $v_f i32) (param $v_x i32) (result i32)
  (call_indirect (type $arity_1) (call_indirect (type $arity_1) (local.get $v_x) (local.get $v_f)) (local.get $v_g)))
```

Direct calls to known functions use `call $v_fn` — no table indirection.

## Entry Points

Each target has a runner that reads a command-line argument and passes it to `main`.

**JS** (Node.js):
```javascript
if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}
```

**Lua** (best-effort main-chunk detection):
```lua
local ok, dbg = pcall(require, 'debug')
local should_run = false
if ok and dbg and dbg.getinfo then
  local info = dbg.getinfo(1, 'S')
  should_run = info and info.what == 'main'
else
  should_run = true
end
if should_run then
  local input = (_G and _G.arg and _G.arg[1]) or ""
  if type(main) == 'function' then main(input) end
end
```

**LLVM** (C `main`):
```llvm
define i32 @main(i32 %argc, ptr %argv) {
  %has_arg = icmp sgt i32 %argc, 1
  br i1 %has_arg, label %with_arg, label %no_arg
with_arg:
  %argptr = getelementptr ptr, ptr %argv, i64 1
  %arg = load ptr, ptr %argptr
  br label %call_main
no_arg:
  br label %call_main
call_main:
  %input = phi ptr [%arg, %with_arg], [@.empty, %no_arg]
  call ptr @v_main(ptr %input)
  ret i32 0
}
```

**JVM** (`main(String[])`):
```
.method public static main([Ljava/lang/String;)V
  aload_0
  arraylength
  iconst_1
  if_icmpge has_arg
  ldc ""
  goto call_main
has_arg:
  aload_0
  iconst_0
  aaload
call_main:
  invokestatic AwsumMain/v_main(Ljava/lang/Object;)Ljava/lang/Object;
  pop
  return
```

**WASM** (WASI `_start`):
```wasm
(func $__get_arg (result i32)  ;; returns argv[1] or ""
  (call $args_sizes_get ...)
  (if (i32.lt_u argc 2) (then (i32.const <empty_string_offset>))
    (else (call $args_get ...) (i32.load (i32.add ptrs 4)))))
(func $_start (export "_start")
  (drop (call $v_main (call $__get_arg))))
```

## Name Mangling

All targets prefix user names with `v_` and replace non-alphanumeric characters (except `_` and `'`) with `_`.

The difference: JS and Lua keep `main` unchanged because their runners call `main(arg)` by name. LLVM and JVM mangle `main` to `v_main` because `main` is reserved as the entry point in both targets.

## LLVM-Specific Details

**Opaque pointers**: The LLVM backend requires LLVM 15+ (opaque pointer support). All values — strings, function pointers, unit — are represented as `ptr`.

**String constant pool**: All string literals are collected in a pre-pass, deduplicated, and emitted as named LLVM constants (`@.str.0`, `@.str.1`, ...). Each constant is a null-terminated `[N x i8]` array.

**SSA form**: LLVM IR requires Static Single Assignment — each variable is assigned exactly once. The codegen uses a counter to generate unique temporaries (`%t0`, `%t1`, `%t2`, ...), reset per function.

**Memory management**: `__concat` allocates with `malloc` and never frees. For short-lived programs this is acceptable — the OS reclaims all memory on exit. A future GC or arena allocator would address this.

**Compilation**: The `awsum run -t llvm` command writes a `.ll` file, compiles it with `clang -O2`, and executes the resulting binary. We use `-O2` because runtime performance is prioritized over compilation speed (see [Design Principles](../README.md#priority-order)).

## Why LLVM IR, Not C

A natural question: why emit LLVM IR directly instead of generating C and compiling with a C compiler?

C is a *specification* with multiple implementations (GCC, Clang, MSVC, TCC, ...). These implementations don't try to produce equivalent output — and the C standard doesn't ask them to. The language has three categories of behavior that differ across compilers and platforms:

- **Undefined behavior** — the compiler may do anything (reorder, delete, or transform code). Example: signed integer overflow.
- **Implementation-defined behavior** — each compiler chooses a behavior and documents it, but different compilers choose differently. Example: right-shifting a negative integer.
- **Unspecified behavior** — the standard allows multiple outcomes and the compiler doesn't have to be consistent. Example: evaluation order of function arguments.

This is fundamentally incompatible with Awsum's core invariant: *if the same pure function compiles for two targets, the results are identical.* If we targeted C, we'd be promising equivalence on top of a language that was designed to allow divergence.

LLVM IR, by contrast, is *one implementation* with deterministic semantics. There's exactly one LLVM, and its behavior for any given IR is defined. When we emit LLVM IR and compile with Clang, the path from our IR to a binary is a single, known pipeline — not a specification interpreted differently by competing vendors.

There's also a practical argument: if we generated C and then mandated "use Clang", we'd be going through LLVM anyway — just with an extra layer of C semantics in between that we'd have to carefully navigate around.

## JVM-Specific Details

**Class file version**: 51.0 (Java 7). This is the minimum version that supports `CONSTANT_MethodHandle` (tag 15) in the constant pool, which we need for higher-order functions. Generated `.class` files run on any JVM 7+, including Android.

**Binary assembler**: The `.class` file is generated directly in Haskell (`Awsum.Codegen.JVM.Assemble`), with no external tools — no Jasmin, no javac. Only `java` is needed to run. The assembler emits a single `AwsumMain.class` with ~25 JVM instructions.

**Value representation**: All values are `java/lang/Object`. Strings are `java/lang/String` (a subtype of Object). Function references are `java/lang/invoke/MethodHandle`. IOUnit is `null`.

**MethodHandle for higher-order functions**: When a function is used as a value (passed as an argument), it is loaded via `ldc` with a `CONSTANT_MethodHandle` constant pool entry (kind `REF_invokeStatic = 6`). The callee uses `invokevirtual MethodHandle.invoke(...)` for the indirect call. Direct calls to known functions skip the MethodHandle and use `invokestatic` directly.

**StackMapTable**: JVM 7+ requires `StackMapTable` attributes for methods with branches. Currently only the generated `main(String[])` has branches (for argument handling). User-defined methods are branch-free (no `if`/`let` in the language yet).

**Text codegen**: `Awsum.Codegen.JVM` produces a Jasmin-like textual representation of the bytecode. This is used for `awsum asm -t jvm` output and golden snapshot tests. The binary assembler (`assembleJVM`) is used for `awsum build -t jvm` (outputs `.class`) and `awsum run -t jvm`.

## WASM-Specific Details

**Binary format**: The `.wasm` binary is generated directly in Haskell (`Awsum.Codegen.WASM.Assemble`), with no external tools — no `wat2wasm`, no WABT. Only `wasmtime` is needed to run. Uses LEB128 encoding (unlike JVM's big-endian fixed-width integers).

**WASI imports**: Three WASI functions are imported from `wasi_snapshot_preview1`: `fd_write` (stdout), `args_sizes_get` and `args_get` (CLI arguments).

**Value representation**: All values are `i32` — pointers into linear memory. Strings are null-terminated byte sequences. Function references are table indices. IOUnit is `0`.

**Memory layout**: One page (64KB) of linear memory. Bytes 0-63 are scratch space for WASI iovec structs and argument buffers. String constants start at byte 64. A bump allocator (`$heap` global) grows from the end of the string pool. No deallocation — the OS reclaims memory on exit (same as LLVM).

**Runtime helpers**: Six helpers implemented in WASM itself: `__strlen` (null-byte scan), `__alloc` (4-byte-aligned bump allocator), `__memcpy` (byte-by-byte copy), `__concat` (strlen + alloc + memcpy + null-terminate), `__print` (iovec + fd_write), `__get_arg` (WASI args_sizes_get + args_get, returns argv[1] or empty string).

**Text codegen**: `Awsum.Codegen.WASM` produces WAT (WebAssembly Text Format) S-expressions. This is used for `awsum asm -t wasm` output and golden snapshot tests. The binary assembler (`assembleWASM`) is used for `awsum build -t wasm` (outputs `.wasm`) and `awsum run -t wasm`.

**~30 opcodes**: The assembler uses approximately 30 WASM opcodes — enough for string manipulation, control flow, memory access, and indirect calls.
