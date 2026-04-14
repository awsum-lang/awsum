# Target Implementation Details

How the same Awsum program maps to each compilation target. All targets produce identical stdout for the same input — this is a compiler invariant, verified by the test suite.

## Overview

| | LLVM | JVM | CLR | WASM | JS | Lua |
|---|---|---|---|---|---|---|
| **Runtime** | Native binary (via Clang 15+) | Java 7+ | .NET 9+ (dotnet) | wasmtime (WASI) | Node.js 14+ | Lua 5.1+ |
| **String type** | `ptr` to null-terminated C string | `java.lang.String` (boxed as `Object`) | `System.String` (boxed as `object`) | `i32` pointer to null-terminated bytes in linear memory | Native JS string | Native Lua string |
| **Concat** | `strlen` + `malloc` + `strcpy` + `strcat` | `String.concat` | `System.String.Concat(object, object)` | `__concat`: strlen + bump alloc + memcpy | `+` | `..` |
| **Print** | `printf("%s", s)` | `System.out.print(s)` | `System.Console.Write(object)` | WASI `fd_write` via iovec | `process.stdout.write(s)` | `io.write(s)` |
| **Constants** | Zero-arg function, called on each use | Zero-arg static method, called on each use | Zero-arg static method, called on each use | Zero-arg function, called on each use | `const name = expr;` | `name = expr` (global) |
| **Functions** | `define ptr @name(ptr ...) { ... }` | `static Object v_name(Object...) { ... }` | `static object v_name(object ...) { ... }` | `(func $v_name (param i32 ...) (result i32) ...)` | `function` declaration (hoisted) | `function ... end` |
| **Higher-order** | Opaque `ptr` indirect call | `MethodHandle` (`ldc` + `invokevirtual invoke`) | `System.Func` delegates (`ldftn` + `newobj` + `callvirt Invoke`) | `funcref` table + `call_indirect` | First-class values | First-class values |
| **Constructors** | `malloc`'d `ptr` array: `[tag, fields...]` | `Object[]`: `[Integer(tag), fields...]` | `object[]`: `[box(tag), fields...]` | Linear memory: `[i32 tag, i32 fields...]` | Array: `[tag, fields...]` | Table: `{tag, fields...}` |
| **Pattern match** | `ptrtoint` tag → `icmp eq` → `br` | `aaload` tag → `intValue` → `ifeq` | `ldelem.ref` tag → `unbox.any` → `beq.s` | `i32.load` tag → `i32.eq` → `if`/`else` | `s[0] === N ? ...` | `s[1] == N and ...` |
| **Memory** | Manual (`malloc`, no `free`) | GC | GC | Bump allocator (no free) | GC | GC |
| **Name mangling** | `v_` prefix for all (including `main` → `v_main`) | `v_` prefix for all (including `main` → `v_main`) | `v_` prefix for all (including `main` → `v_main`) | `v_` prefix for all (`_start` is WASI entry) | `v_` prefix, `main` unchanged | `v_` prefix, `main` unchanged |

## String Concatenation

All six backends guarantee identical results because the type checker ensures both operands are `String`.

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

**CLR** — casts both operands to `object` and calls `System.String.Concat`:
```
call object AwsumMain::__concat(object, object)
// where __concat calls: string [System.Runtime]System.String::Concat(object, object)
```

**WASM** — runtime helper computes lengths, bump-allocates a new buffer, copies both strings, and null-terminates:
```wasm
(call $__concat (local.get $a) (local.get $b))
;; strlen(a) + strlen(b) → alloc(la+lb+1) → memcpy(buf,a,la) → memcpy(buf+la,b,lb) → store8 0
```

**JS** — uses native `+`, which is string concatenation when both sides are strings:
```javascript
("Hello" + ", " + name + "!")
```

**Lua** — uses native `..`, which is string concatenation:
```lua
("Hello" .. ", " .. name .. "!")
```

## Print

All backends print without a trailing newline — `IO.Stdout.print` outputs exactly what it receives.

**LLVM**: `printf("%s", s)` — C stdio buffering, implicit flush on `return 0` from `main`.

**JVM**: `System.out.print(s)` — buffered PrintStream, flushed on JVM exit.

**CLR**: `System.Console.Write(object)` — calls `ToString()` implicitly, buffered, flushed on exit.

**WASM**: WASI `fd_write` — stores an iovec (pointer + length) at scratch memory offset 0, calls `fd_write(1, iov, 1, nwritten)`.

**JS**: `process.stdout.write(String(s))` — unbuffered for TTY, buffered for pipes, flushed on exit.

**Lua**: `io.write(tostring(s))` — buffered, flushed on exit.

## Constants (CValDef)

Zero-argument definitions like `greeting = "Hello"` are compiled differently per target:

**LLVM**: Zero-arg function `define ptr @v_greeting() { ... }` — called each time the value is referenced. Safe because all expressions are pure (same result every time). Avoids the complexity of LLVM global initializers for non-constant expressions.

**JVM**: Zero-arg static method `static Object v_greeting() { ... }` — same approach as LLVM, called each time. The JVM JIT compiler can inline these.

**CLR**: Zero-arg static method `static object v_greeting() { ... }` — same approach as JVM. The .NET JIT can inline these.

**WASM**: Zero-arg function `(func $v_greeting (result i32) ...)` — same approach as LLVM and JVM.

**JS**: `const v_greeting = "Hello";` — evaluated once, hoisted by the runner.

**Lua**: `v_greeting = "Hello"` — global assignment, evaluated once before `main` runs.

## Higher-Order Functions

`compose g f x = g (f x)` — parameters `g` and `f` can be functions.

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

**CLR**: Function values are `System.Func<object,...,object>` delegates. When a function is used as a value, it is wrapped via `ldftn` + `newobj Func`. Indirect calls use `callvirt Invoke(...)`:
```
; compose g f x = g (f x)
.method public hidebysig static object v_compose(object, object, object) cil managed
  ldarg.1                          ; f (Func delegate)
  castclass Func`2<object, object>
  ldarg.2                          ; x
  callvirt instance object Func`2<object, object>::Invoke(object)
  ; g(result)
  ldarg.0                          ; g (Func delegate)
  castclass Func`2<object, object>
  swap
  callvirt instance object Func`2<object, object>::Invoke(object)
  ret
```

Direct calls to known functions use `call object AwsumMain::v_fn(...)` — no delegate overhead.

**WASM**: Function values are table indices (`i32`). All user `CFunDef`s are placed in a `funcref` table. When a function is used as a value, it becomes `(i32.const <table_index>)`. Indirect calls use `call_indirect` with a per-arity type signature:
```wasm
;; compose g f x = g (f x)
(func $v_compose (param $v_g i32) (param $v_f i32) (param $v_x i32) (result i32)
  (call_indirect (type $arity_1) (call_indirect (type $arity_1) (local.get $v_x) (local.get $v_f)) (local.get $v_g)))
```

Direct calls to known functions use `call $v_fn` — no table indirection.

**JS/Lua**: Functions are first-class values. Parameters that are functions are called with `(callee)(args...)`:
```javascript
function v_compose(v_g, v_f, v_x){ return (v_g)((v_f)(v_x)); }
```

## Sum Types & Pattern Matching

`type Lookup a = Found a | NotFound` — constructors with fields, matched via `case`/`of`.

All six backends use the same container representation: an array/block where index 0 is the constructor tag (integer) and subsequent indices hold constructor fields. Nullary constructors (no fields) also allocate a container with just a tag — this keeps the representation uniform and simplifies pattern matching.

**LLVM**: Container is a `malloc`'d array of `ptr`. Tag is stored as an `i64` cast to `ptr` at index 0. Fields are `ptr` values at indices 1, 2, ...:
```llvm
; Found "hello" → [tag=0, "hello"]
%t0 = call ptr @malloc(i64 16)           ; 2 slots × 8 bytes
%t1 = getelementptr ptr, ptr %t0, i64 0
store ptr inttoptr (i64 0 to ptr), ptr %t1  ; tag 0
%t2 = getelementptr ptr, ptr %t0, i64 1
store ptr @.str.0, ptr %t2                 ; field: "hello"
```

Pattern matching loads the tag and branches:
```llvm
%tag = load ptr, ptr %scrut
%tag_i = ptrtoint ptr %tag to i64
%is_0 = icmp eq i64 %tag_i, 0
br i1 %is_0, label %arm_0, label %next_0
```

**JVM**: Container is `Object[]`. Tag is a boxed `Integer` at index 0. Fields are `Object` at indices 1, 2, ...:
```
; Found "hello" → new Object[] { Integer(0), "hello" }
iconst_2
anewarray java/lang/Object
dup; iconst_0; iconst_0; invokestatic Integer.valueOf(int); aastore  ; tag 0
dup; iconst_1; ldc "hello"; aastore                                  ; field
```

Pattern matching casts to `Object[]`, extracts and unboxes the tag:
```
checkcast [Ljava/lang/Object;   ; verify array type for aaload
astore <arr>
aload <arr>; iconst_0; aaload; checkcast Integer; invokevirtual intValue()I; istore <tag>
iload <tag>; ifeq arm_0         ; if tag == 0, branch to arm_0
```

Field binding in matched arm: `aload <arr>; iconst_N; aaload` (loads field N from container).

**CLR**: Container is `object[]` via `newarr`. Tag is a boxed `Int32` at index 0. Fields are `object` at indices 1, 2, ...:
```
; Found "hello" → new object[] { box(0), "hello" }
ldc.i4.2
newarr [System.Runtime]System.Object
dup; ldc.i4.0; ldc.i4.0; box Int32; stelem.ref      ; tag 0
dup; ldc.i4.1; ldstr "hello"; stelem.ref             ; field
```

Pattern matching stores the container, extracts and unboxes the tag:
```
stloc.0                                              ; store container
ldloc.0; ldc.i4.0; ldelem.ref; unbox.any Int32       ; extract tag
ldc.i4.0; beq.s arm_0                                ; if tag == 0
```

Field binding: `ldloc.0; ldc.i4.N; ldelem.ref` (loads field N). Methods with locals require a `StandAloneSig` metadata entry and a fat method header with `InitLocals`.

**WASM**: Container is a linear memory block allocated via `$__alloc`. Tag is `i32` at byte offset 0. Fields are `i32` at byte offsets 4, 8, ...:
```wasm
;; Found "hello" → alloc 8 bytes, store tag=0 at +0, str ptr at +4
(i32.store offset=0 (local.tee $con (call $__alloc (i32.const 8))) (i32.const 0))
(i32.store offset=4 (local.get $con) (i32.const <str_ptr>))
```

Pattern matching loads the tag and uses an if/else chain:
```wasm
(local.set $scrut (... scrutinee ...))
(if (result i32) (i32.eq (i32.load offset=0 (local.get $scrut)) (i32.const 0))
  (then ... arm 0: (i32.load offset=4 (local.get $scrut)) for field binding ...)
  (else ... next arm ...))
```

**JS**: Container is an array literal. Tag is a number at index 0:
```javascript
const v_found = (a) => [0, a];     // Found a
const v_notFound = [1];            // NotFound
// case: s[0] === 0 ? s[1] : "not found"
```

**Lua**: Container is a table (1-indexed). Tag is at index 1:
```lua
function v_found(a) return {0, a} end
v_notFound = {1}
-- case: s[1] == 0 and s[2] or "not found"
```

## Entry Points

Each target has a runner that reads a command-line argument and passes it to `main`.

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

**CLR** (`.entrypoint` static `Main(string[])`):
```
.method public hidebysig static void Main(string[]) cil managed
{
  .entrypoint
  ldarg.0
  ldlen
  conv.i4
  ldc.i4.1
  bge.s has_arg
  ldstr ""
  br.s call_main
has_arg:
  ldarg.0
  ldc.i4.0
  ldelem.ref
call_main:
  call object AwsumMain::v_main(object)
  pop
  ret
}
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

## Name Mangling

All targets prefix user names with `v_` and replace non-alphanumeric characters (except `_` and `'`) with `_`.

The difference: LLVM, JVM, CLR, and WASM mangle `main` to `v_main` because `main`/`_start`/`Main` is reserved as the entry point in those targets. JS and Lua keep `main` unchanged because their runners call `main(arg)` by name.

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

**StackMapTable**: JVM 7+ requires `StackMapTable` attributes for methods with branches. The generated `main(String[])` has branches for argument handling. User-defined methods with `case`/`of` pattern matching also have branches (if/else chain over constructor tags) and require StackMapTable entries.

**Text codegen**: `Awsum.Codegen.JVM` produces a Jasmin-like textual representation of the bytecode. This is used for `awsum asm -t jvm` output and golden snapshot tests. The binary assembler (`assembleJVM`) is used for `awsum build -t jvm` (outputs `.class`) and `awsum run -t jvm`.

## CLR-Specific Details

**Binary format**: The `.dll` is a PE (Portable Executable) file generated directly in Haskell (`Awsum.Codegen.CLR.Assemble`), with no external tools — no `ilasm`, no `csc`. Only `dotnet` is needed to run. The assembler emits DOS header, PE/COFF headers, a `.text` section with CLR metadata and CIL method bodies.

**Metadata**: The PE file contains 9 CLR metadata tables (Module, TypeRef, TypeDef, MethodDef, Param, MemberRef, StandAloneSig, TypeSpec, Assembly, AssemblyRef) and 4 metadata heaps (#Strings, #US for user strings in UTF-16LE, #Blob for signatures, #GUID). The StandAloneSig table declares local variables for methods that use `stloc`/`ldloc` (e.g. pattern matching).

**Value representation**: All values are `object` (System.Object). Strings are `System.String`. Function references are `System.Func<object,...,object>` generic delegates. IOUnit is `null`.

**Func delegates for higher-order functions**: When a function is used as a value (passed as an argument), it is wrapped in a `System.Func` delegate via `ldftn` + `newobj`. The arity determines the generic instantiation: a 1-arg function becomes `Func<object, object>`, a 2-arg function becomes `Func<object, object, object>`, etc. Indirect calls use `callvirt Invoke(...)` on the delegate. Direct calls to known functions use `call` directly — no delegate overhead.

**Generic type variables in signatures**: MemberRef signatures for `Invoke` on generic Func TypeSpec instantiations use `ELEMENT_TYPE_VAR` (0x13) for type parameters, not concrete `object` types. This is required by the CLR metadata specification.

**Runtime configuration**: Running with `dotnet` requires an `AwsumMain.runtimeconfig.json` alongside the DLL. The compiler generates a fixed template targeting .NET 9.0 with `"rollForward": "LatestMajor"` for forward-compatibility with newer .NET versions.

**Text codegen**: `Awsum.Codegen.CLR` produces an ilasm-like textual representation of the CIL bytecode. This is used for `awsum asm -t clr` output and golden snapshot tests. The binary assembler (`assembleCLR`) is used for `awsum build -t clr` (outputs `.dll`) and `awsum run -t clr`.

**~25 CIL opcodes**: The assembler uses approximately 25 CIL opcodes — `ldarg.0`–`ldarg.3`, `ldstr`, `call`, `callvirt`, `ret`, `pop`, `ldnull`, `ldlen`, `ldelem.ref`, `ldc.i4.0`–`ldc.i4.8`/`ldc.i4.s`, `bge.s`, `br.s`, `beq.s`, `ldftn`, `newobj`, `castclass`, `conv.i4`, `newarr`, `stelem.ref`, `box`, `unbox.any`, `stloc.0`–`stloc.3`, `ldloc.0`–`ldloc.3`.

## WASM-Specific Details

**Binary format**: The `.wasm` binary is generated directly in Haskell (`Awsum.Codegen.WASM.Assemble`), with no external tools — no `wat2wasm`, no WABT. Only `wasmtime` is needed to run. Uses LEB128 encoding (unlike JVM's big-endian fixed-width integers).

**WASI imports**: Three WASI functions are imported from `wasi_snapshot_preview1`: `fd_write` (stdout), `args_sizes_get` and `args_get` (CLI arguments).

**Value representation**: All values are `i32` — pointers into linear memory. Strings are null-terminated byte sequences. Function references are table indices. IOUnit is `0`.

**Memory layout**: One page (64KB) of linear memory. Bytes 0-63 are scratch space for WASI iovec structs and argument buffers. String constants start at byte 64. A bump allocator (`$heap` global) grows from the end of the string pool. No deallocation — the OS reclaims memory on exit (same as LLVM).

**Runtime helpers**: Six helpers implemented in WASM itself: `__strlen` (null-byte scan), `__alloc` (4-byte-aligned bump allocator), `__memcpy` (byte-by-byte copy), `__concat` (strlen + alloc + memcpy + null-terminate), `__print` (iovec + fd_write), `__get_arg` (WASI args_sizes_get + args_get, returns argv[1] or empty string).

**Text codegen**: `Awsum.Codegen.WASM` produces WAT (WebAssembly Text Format) S-expressions. This is used for `awsum asm -t wasm` output and golden snapshot tests. The binary assembler (`assembleWASM`) is used for `awsum build -t wasm` (outputs `.wasm`) and `awsum run -t wasm`.

**~30 opcodes**: The assembler uses approximately 30 WASM opcodes — enough for string manipulation, control flow, memory access, and indirect calls.
