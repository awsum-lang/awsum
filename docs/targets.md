# Target Implementation Details

How the same Awsum program maps to each compilation target. All targets produce identical stdout for the same input — this is a compiler invariant, verified by the test suite.

## Overview

|                   | LLVM                                              | JVM                                               | CLR                                                              | WASM                                                    | JS                                            |
| ----------------- | ------------------------------------------------- | ------------------------------------------------- | ---------------------------------------------------------------- | ------------------------------------------------------- | --------------------------------------------- |
| **Runtime**       | Native binary (via Clang 15+)                     | Java 7+                                           | .NET 9+ (dotnet)                                                 | wasmtime (WASI)                                         | Node.js 22+                                   |
| **String type**   | `ptr` to null-terminated C string                 | `java.lang.String` (boxed as `Object`)            | `System.String` (boxed as `object`)                              | `i32` pointer to null-terminated bytes in linear memory | Native JS string                              |
| **Concat**        | `strlen` + `malloc` + `strcpy` + `strcat`         | `String.concat`                                   | `System.String.Concat(object, object)`                           | `__concat`: strlen + bump alloc + memcpy                | `+`                                           |
| **Print**         | `printf("%s", s)`                                 | `System.out.print(s)`                             | `System.Console.Write(object)`                                   | WASI `fd_write` via iovec                               | `process.stdout.write(s)`                     |
| **Constants**     | Zero-arg function, called on each use             | Zero-arg static method, called on each use        | Zero-arg static method, called on each use                       | Zero-arg function, called on each use                   | `const name = expr;`                          |
| **Functions**     | `define ptr @name(ptr ...) { ... }`               | `static Object v_name(Object...) { ... }`         | `static object v_name(object ...) { ... }`                       | `(func $v_name (param i32 ...) (result i32) ...)`       | `function` declaration (hoisted)              |
| **Higher-order**  | Opaque `ptr` indirect call                        | `MethodHandle` (`ldc` + `invokevirtual invoke`)   | `System.Func` delegates (`ldftn` + `newobj` + `callvirt Invoke`) | `funcref` table + `call_indirect`                       | First-class values                            |
| **Constructors**  | `malloc`'d `ptr` array: `[tag, fields...]`        | `Object[]`: `[Integer(tag), fields...]`           | `object[]`: `[box(tag), fields...]`                              | Linear memory: `[i32 tag, i32 fields...]`               | Array: `[tag, fields...]`                     |
| **Pattern match** | `ptrtoint` tag → `icmp eq` → `br`                 | `aaload` tag → `intValue` → `ifeq`                | `ldelem.ref` tag → `unbox.any` → `beq.s`                         | `i32.load` tag → `i32.eq` → `if`/`else`                 | `s[0] === N ? ...`                            |
| **Int32 / UInt8** | Heap cell: `ptr` to `i32` / `i8`                  | Boxed `java.lang.Integer`                         | Boxed `System.Int32`                                             | Heap cell: `i32` in linear memory                       | `(N\|0)` / `(N & 0xFF)` — unboxed JS `number` |
| **show\***        | Runtime helpers using `snprintf`                  | `Integer.toString()`                              | `callvirt Object::ToString()`                                    | Hand-rolled itoa in linear memory                       | `String(x)`                                   |
| **Memory**        | Manual (`malloc`, no `free`)                      | GC                                                | GC                                                               | Bump allocator (no free)                                | GC                                            |
| **Name mangling** | `v_` prefix for all (including `main` → `v_main`) | `v_` prefix for all (including `main` → `v_main`) | `v_` prefix for all (including `main` → `v_main`)                | `v_` prefix for all (`_start` is WASI entry)            | `v_` prefix, `main` unchanged                 |

## String Concatenation

All five backends guarantee identical results because the type checker ensures both operands are `String`.

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
"Hello" + ", " + name + "!";
```

## Splitting at the first separator

`splitOnFirst sep str` returns `Just (Tuple2 prefix suffix)` for the first occurrence of `sep` in `str`, or `Nothing` if it does not appear. Full edge-case spec — including the empty separator, separator at start / end / equal to string, separator longer than string — is on the function's docstring in [stdlib/Prelude.aww](../stdlib/Prelude.aww).

Four of five backends defer to a native substring search; WASM hand-rolls a byte scan because no such primitive is available there.

**LLVM** — `strstr` from libc returns a pointer to the first match (or `NULL`); the helper then `memcpy`s into two freshly `malloc`'d buffers (owning copies, not aliases). `strstr(s, "")` returns `s` per POSIX, so the empty-separator case is correct without special handling.

**JVM** — `String.indexOf(String)I` (returns `-1` on miss, `0` on empty separator) plus the two `String.substring` overloads:

```
invokevirtual java/lang/String/indexOf(Ljava/lang/String;)I
invokevirtual java/lang/String/substring(II)Ljava/lang/String;
invokevirtual java/lang/String/substring(I)Ljava/lang/String;
```

**CLR** — same shape with the System.String members:

```
callvirt instance int32 [System.Runtime]System.String::IndexOf(string)
callvirt instance string [System.Runtime]System.String::Substring(int32, int32)
callvirt instance string [System.Runtime]System.String::Substring(int32)
```

**WASM** — outer loop over candidate positions `i ∈ 0..str_len - sep_len`, inner loop compares `str[i+j]` against `sep[j]` byte by byte; on match, `__memcpy` builds two fresh null-terminated buffers (the same allocator the rest of the runtime uses). Empty separator and separator-longer-than-`str` are handled implicitly by the loop bounds — no special cases in code.

**JS** — `String.prototype.indexOf` plus `substring`:

```javascript
const i = str.indexOf(sep);
return i < 0 ? [0] : [1, [0, str.substring(0, i), str.substring(i + sep.length)]];
```

Matching is byte-level on every backend — a multi-byte UTF-8 sequence can be split inside a codepoint. UTF-8-aware splitting is a separate, future API.

## Parsing decimals

`parseInt32 : String -> Either ParseError Int32` and `parseUInt8 : String -> Either ParseError UInt8` follow a strict grammar that mirrors Awsum's own integer literal: optional `-` (Int32 only), one or more ASCII digits, nothing else — no `+`, no whitespace, no trailing characters. See the docstrings in [stdlib/Prelude.aww](../stdlib/Prelude.aww) for the worked example list.

**Every backend hand-rolls the parser**; native parsers are not used:

- JVM `Integer.parseInt` accepts a leading `+`.
- CLR `Int32.TryParse` (with default `NumberStyles`) accepts whitespace and signs.
- JS `Number(s)` accepts whitespace, scientific notation, and the empty string (silently → `0`).

Stripping these affordances reliably across five runtimes is the same amount of code as just doing the parse byte-by-byte. The hand-rolled algorithm is identical on every target:

```
parseInt32(s):
  if len == 0: fail
  i = 0; neg = false
  if s[0] == '-':
    neg = true; i = 1
    if i == len: fail              -- lone '-'
  acc : i64 = 0
  while i < len:
    c = s[i]
    if c < '0' || c > '9': fail
    acc = acc * 10 + (c - '0')
    if acc > 2147483648: fail      -- early termination on magnitude overshoot
    i += 1
  if neg:
    return Right (i32) (-acc)      -- acc <= 2147483648 ⇒ -acc >= minInt32
  else:
    if acc > 2147483647: fail
    return Right (i32) acc
```

`parseUInt8` is the same shape with no sign branch and an i32 accumulator (the running magnitude never exceeds 2559 before the `> 255` check fails the parse).

The `2147483648L` constant (= `|minInt32|`) does not fit in an i32, so each backend builds it differently:

- **LLVM** — direct `2147483648` integer literal, used at i64 width.
- **JVM** — `ldc2_w 2147483648` in the text codegen; the binary assembler does not carry a `CONSTANT_Long_info` slot, so it builds the constant with the shift trick `iconst_1; i2l; bipush 31; lshl`.
- **CLR** — same shift trick (`ldc.i4.1; conv.i8; ldc.i4.s 31; shl`) in both text and binary, for symmetry with JVM.
- **WASM** — `i64.shl (i64.const 1) (i64.const 31)` everywhere — there's no native i64 literal limit but the shift form keeps the source aligned with JVM/CLR.
- **JS** — IEEE-754 double represents `2147483648` exactly, so the literal is written directly.

The grammar is byte-level (ASCII digits 0x30..0x39 only); other Unicode digit forms are rejected. UTF-8-aware parsing is a separate, future API.

## Print

All backends print without a trailing newline — `IO.Stdout.print` outputs exactly what it receives.

**LLVM**: `printf("%s", s)` — C stdio buffering, implicit flush on `return 0` from `main`.

**JVM**: `System.out.print(s)` — buffered PrintStream, flushed on JVM exit.

**CLR**: `System.Console.Write(object)` — calls `ToString()` implicitly, buffered, flushed on exit.

**WASM**: WASI `fd_write` — stores an iovec (pointer + length) at scratch memory offset 0, calls `fd_write(1, iov, 1, nwritten)`.

**JS**: `process.stdout.write(String(s))` — unbuffered for TTY, buffered for pipes, flushed on exit.

## Constants (CValDef)

Zero-argument definitions like `greeting = "Hello"` are compiled differently per target:

**LLVM**: Zero-arg function `define ptr @v_greeting() { ... }` — called each time the value is referenced. Safe because all expressions are pure (same result every time). Avoids the complexity of LLVM global initializers for non-constant expressions.

**JVM**: Zero-arg static method `static Object v_greeting() { ... }` — same approach as LLVM, called each time. The JVM JIT compiler can inline these.

**CLR**: Zero-arg static method `static object v_greeting() { ... }` — same approach as JVM. The .NET JIT can inline these.

**WASM**: Zero-arg function `(func $v_greeting (result i32) ...)` — same approach as LLVM and JVM.

**JS**: `const v_greeting = "Hello";` — evaluated once, hoisted by the runner.

## Integers

Awsum currently has two integer types: `Int32` (signed 32-bit) and `UInt8` (unsigned 8-bit). Integer literals have no runtime default type — context fixes the type, and the type checker validates the literal against its range at compile time.

Two builtins render integers as strings:

- `showInt32 : Int32 -> String`
- `showUInt8 : UInt8 -> String`

These are unqualified top-level names (no `import` required), because the types themselves are prelude-visible and a faked `Int32.show` quote would imply a module that does not exist. When polymorphic `show` arrives (type classes), these two specialised helpers go away in favour of it.

All five backends produce identical decimal output for the same value — this is verified by the cross-backend tests `int32-show` and `uint8-show`, which render the full range (min, negatives, zero, positives, max) as a comma-separated list.

### Representation

**LLVM**: Integers are boxed — each `CIntLit` allocates a heap cell (`i32` or `i8`) and the Awsum-level `ptr` points at it. Show helpers load the value and format it with `snprintf`:

```llvm
declare i32 @snprintf(ptr, i64, ptr, ...)
@.fmt_i32 = private unnamed_addr constant [3 x i8] c"%d\00"
@.fmt_u8  = private unnamed_addr constant [3 x i8] c"%u\00"

define ptr @__showInt32(ptr %p) {
  %v   = load i32, ptr %p
  %buf = call ptr @malloc(i64 16)
  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_i32, i32 %v)
  ret ptr %buf
}
```

`__showUInt8` is the same with `load i8` + `zext i8 to i32` + `@.fmt_u8`. 16 bytes is enough for `-2147483648` (11 chars) plus null terminator.

**JVM**: Both `Int32` and `UInt8` are boxed as `java.lang.Integer` (not `java.lang.Byte`, because `byte` is signed on the JVM — `Integer` preserves the 0..255 value space without masking headaches for later arithmetic). Literals are pushed with `iconst`/`bipush`/`sipush`, or loaded from a `CONSTANT_Integer` pool entry via `ldc` for values outside the short range:

```
; showInt32 42 → boxed Integer(42) → "42"
bipush 42
invokestatic java/lang/Integer.valueOf(I)Ljava/lang/Integer;
checkcast java/lang/Integer
invokevirtual java/lang/Integer.toString()Ljava/lang/String;
```

**CLR**: Both types are boxed as `System.Int32` (same rationale as JVM — avoiding `System.Byte`'s unsigned primitive path keeps the representation uniform). `ldc.i4` pushes the value, `box` turns it into an `object`, and show is a virtual call to `Object::ToString()` — boxed `Int32` dispatches to `System.Int32.ToString()`:

```
; showInt32 42 → boxed Int32 → "42"
ldc.i4 42
box [System.Runtime]System.Int32
callvirt instance string [System.Runtime]System.Object::ToString()
```

**WASM**: Integers are boxed in linear memory — `__box_i32(v)` allocates 4 bytes via `__alloc`, stores `v`, and returns the pointer. Show is implemented by hand because WASM has no stdlib: `__show_i32` reads the value, writes digits into a 16-byte buffer from the end, and prepends `-` if the value is negative. The same routine handles `UInt8`: values 0..255 are always positive in the signed interpretation, so `i32.lt_s (x) 0` is false and no `-` is written.

`i32.div_u` / `i32.rem_u` are used on the magnitude — this sidesteps the `INT_MIN` corner case where `0 - INT_MIN` is `INT_MIN` again in two's complement: the unsigned reading of `0x80000000` is `2147483648`, which is the correct magnitude.

**JS**: Integers are unboxed JS `number`s, coerced to match the declared type's value space at the literal site:

```javascript
// Int32 N → (N|0)    forces signed 32-bit semantics
// UInt8 N → (N & 0xFF)   masks to 0..255
// showInt32 / showUInt8 → String(x)
```

`String(x)` produces the decimal form with no locale-specific separators. JS numbers hold `Int32` and `UInt8` ranges exactly, so no precision loss.

Signedness and width are not visible at the show layer because both backends widen to a representation big enough to hold the full UInt8 / Int32 range (JVM `Integer`, JS `number`). Where they *do* matter is in arithmetic — see the next subsection.

### Honest arithmetic

Every numeric primitive that can produce a value outside its declared type's range returns `Either <error> <result>` rather than wrapping or trapping at runtime. Currently:

- `predInt32` / `succInt32` — `Left UnderflowError` / `Left OverflowError` at the boundaries; otherwise `Right (x ± 1)`.
- `predUInt8` / `succUInt8` — same shape, with the boundaries at 0 and 255.
- `addInt32 : Int32 -> Int32 -> Either ArithError Int32` — `Left Underflow` / `Left Overflow` (`type ArithError = Underflow | Overflow`), since signed addition can fail at *both* ends from a single operation.
- `addUInt8 : UInt8 -> UInt8 -> Either OverflowError UInt8` — only overflow is reachable for unsigned addition, so the closed `OverflowError` suffices.

`eqInt32` / `eqUInt8` are also in this layer but cannot fail; they return `Bool` directly.

Because the error type is part of the surface signature, tests pin both branches at the language level. Per-backend the detection methods do differ:

**LLVM** — `addInt32` uses the `llvm.sadd.with.overflow.i32` intrinsic, which returns `{i32, i1}` with the wrapped sum and an overflow flag in one instruction. Direction (Underflow vs Overflow) is recovered from the sign of `a` — when overflow happens, `a` and `b` necessarily have the same sign, so `icmp sge i32 %a, 0` distinguishes the two `ArithError` constructors.

**JVM / CLR / WASM** — none of these expose a "did the last add overflow" flag at the bytecode level, so all three use the classical XOR trick:

```
overflow = ((a ^ s) & (b ^ s)) < 0    -- where s = a + b (wraps mod 2^32)
```

`(a ^ s)` flips its sign bit iff the sign of `s` differs from `a`; the bitwise AND with `(b ^ s)` is true on the sign bit iff *both* sources disagree with the sum, which is exactly the same-sign-overflow condition. As on LLVM, `a >= 0` then picks Overflow (positive direction) vs Underflow. The CLR text emits `blt.s` / `ble.s`, the JVM uses `iflt`, WASM uses `i32.lt_s` against zero — three encodings of the same Boolean.

**JS** — JS `number` is an IEEE-754 double, which exactly represents every i32 sum (the result is at most 33 bits). The check is the most direct of the five:

```
const s = a + b;
if (s > 2147483647) return Left Overflow;
if (s < -2147483648) return Left Underflow;
return Right (s | 0);
```

For `addUInt8` the picture is uniform: every backend widens both operands into a representation that holds at least 9 bits (i32 / Integer / number), sums, compares against 255, and either returns `Left OverflowError` or boxes the truncated low byte as `Right`. No native u8 add is used anywhere — even where the platform has one (LLVM `i8`), promoting first sidesteps the wrap-on-overflow that the Either-returning signature is designed to forbid.

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

**JS**: Functions are first-class values. Parameters that are functions are called with `(callee)(args...)`:

```javascript
function v_compose(v_g, v_f, v_x) {
  return v_g(v_f(v_x));
}
```

## Sum Types & Pattern Matching

`type Lookup a = Found a | NotFound` — constructors with fields, matched via `case`/`of`.

All five backends use the same container representation: an array/block where index 0 is the constructor tag (integer) and subsequent indices hold constructor fields. Nullary constructors (no fields) also allocate a container with just a tag — this keeps the representation uniform and simplifies pattern matching.

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
const v_found = (a) => [0, a]; // Found a
const v_notFound = [1]; // NotFound
// case: s[0] === 0 ? s[1] : "not found"
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
if (typeof require !== "undefined" && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === "function") main(arg);
}
```

## Name Mangling

All targets prefix user names with `v_` and replace non-alphanumeric characters (except `_` and `'`) with `_`.

The difference: LLVM, JVM, CLR, and WASM mangle `main` to `v_main` because `main`/`_start`/`Main` is reserved as the entry point in those targets. JS keeps `main` unchanged because its runner calls `main(arg)` by name.

## Recursion and tail calls

Every recursion shape in Awsum is normalized at Core level into self-tail-calls, which the backends lower as a jump to the top of the enclosing method / function / loop. The normalization itself (SCC merge for mutual recursion, CPS + defunctionalization for non-tail recursion) is backend-agnostic and lives in [`Awsum.Scc`](../src/Awsum/Scc.hs) and [`Awsum.Cps`](../src/Awsum/Cps.hs); the last pass, [`Awsum.Tco`](../src/Awsum/Tco.hs), wraps the body in a `CLoop` and turns each surviving self-call into a `CContinue`. See [`docs/recursion.md`](recursion.md) for the full pipeline story.

This section is about the last step — how each backend maps `CLoop` + `CContinue` to native code. The shape is the same everywhere: allocate the loop label once at the top of the method, evaluate each `CContinue`'s new arguments into temporaries so mid-update reads of the old parameters aren't corrupted, then overwrite the parameter slots and jump back.

**LLVM** — `%tco.loop` block; parameters live in `alloca` slots, `CContinue` stores new values and `br`s to `%tco.loop`. A trailing `%tco.exit` block owns the single `ret` via another `alloca`. `mem2reg` at `-O2` erases every `alloca` into real SSA `phi` nodes, so the final binary is indistinguishable from one written with phi by hand.

**JVM** — label `L_tco_loop:` at offset 0; `CContinue` evaluates new args onto the operand stack, `astore`s them into the argument slots in reverse (JVM stack is LIFO), then `goto 0`. JVM 7+ verifier requires a `StackMapTable` entry when offset 0 is a branch target — `buildFrames` emits the explicit initial frame (the implicit one describes the same state, but the verifier needs the explicit form once the offset is reachable by a jump).

**CLR** — label `IL_tco_loop:` at offset 0; `CContinue` uses `starg.s` to rewrite argument slots in reverse, then `br` (4-byte offset — the 1-byte form is too short for stress tests). `exprLocalsNeeded` walks nested `CCase`s additively so a method with pattern matching has enough `stloc` slots; the JIT uses the `tail.` prefix opportunistically but we do not emit it — the Core-level loop rewrite is the guarantee.

**WASM** — the whole function body sits inside `(loop $tco_top (result i32) …)`; `CContinue` writes new values into `$__k0`, `$__k1`, … temps (one per parameter), copies them into the parameter slots, then `br $tco_top`. Depth counting tracks how many nested `if`/`block` scopes sit between `CContinue` and the loop header so the `br` label depth is correct.

**JavaScript** — `while (true) { … }` wrapper; `CContinue` computes new values into `__t0`, `__t1`, … `const`s, assigns them to the parameter `let`s, and `continue`s. The two-step is deliberate: computing new args can still reference the old parameter values, which the `const` temps preserve.

Mutual recursion and non-tail recursion never reach the backend — by the time the codegen runs, the Core IR has only self-recursion, and only in tail position. The test matrix in [`docs/recursion.md`](recursion.md#stack-safety-test-matrix) runs the stress programs on all five backends at depths up to 1 000 000 with byte-identical stdout.

## LLVM-Specific Details

**Opaque pointers**: The LLVM backend requires LLVM 15+ (opaque pointer support). All values — strings, function pointers, unit — are represented as `ptr`.

**String constant pool**: All string literals are collected in a pre-pass, deduplicated, and emitted as named LLVM constants (`@.str.0`, `@.str.1`, ...). Each constant is a null-terminated `[N x i8]` array.

**SSA form**: LLVM IR requires Static Single Assignment — each variable is assigned exactly once. The codegen uses a counter to generate unique temporaries (`%t0`, `%t1`, `%t2`, ...), reset per function.

**Memory management**: `__concat`, integer box cells, and `__showInt32` / `__showUInt8` buffers all allocate with `malloc` and never free. For short-lived programs this is acceptable — the OS reclaims all memory on exit. A future GC or arena allocator would address this.

**Compilation**: The `awsum run -t llvm` command writes a `.ll` file, compiles it with `clang -O2`, and executes the resulting binary. We use `-O2` because runtime performance is prioritized over compilation speed (see [Design Principles](../README.md#priority-order)).

## Why LLVM IR, Not C

A natural question: why emit LLVM IR directly instead of generating C and compiling with a C compiler?

C is a _specification_ with multiple implementations (GCC, Clang, MSVC, TCC, ...). These implementations don't try to produce equivalent output — and the C standard doesn't ask them to. The language has three categories of behavior that differ across compilers and platforms:

- **Undefined behavior** — the compiler may do anything (reorder, delete, or transform code). Example: signed integer overflow.
- **Implementation-defined behavior** — each compiler chooses a behavior and documents it, but different compilers choose differently. Example: right-shifting a negative integer.
- **Unspecified behavior** — the standard allows multiple outcomes and the compiler doesn't have to be consistent. Example: evaluation order of function arguments.

This is fundamentally incompatible with Awsum's core invariant: _if the same pure function compiles for two targets, the results are identical._ If we targeted C, we'd be promising equivalence on top of a language that was designed to allow divergence.

LLVM IR, by contrast, is _one implementation_ with deterministic semantics. There's exactly one LLVM, and its behavior for any given IR is defined. When we emit LLVM IR and compile with Clang, the path from our IR to a binary is a single, known pipeline — not a specification interpreted differently by competing vendors.

There's also a practical argument: if we generated C and then mandated "use Clang", we'd be going through LLVM anyway — just with an extra layer of C semantics in between that we'd have to carefully navigate around.

## JVM-Specific Details

**Class file version**: 51.0 (Java 7). This is the minimum version that supports `CONSTANT_MethodHandle` (tag 15) in the constant pool, which we need for higher-order functions. Generated `.class` files run on any JVM 7+, including Android.

**Binary assembler**: The `.class` file is generated directly in Haskell (`Awsum.Codegen.JVM.Assemble`), with no external tools — no Jasmin, no javac. Only `java` is needed to run. The assembler emits a single `AwsumMain.class` with ~25 JVM instructions.

**Value representation**: All values are `java/lang/Object`. Strings are `java/lang/String` (a subtype of Object). Function references are `java/lang/invoke/MethodHandle`. Integers (`Int32`, `UInt8`) are boxed `java/lang/Integer`. `IO Unit` is `null`.

**MethodHandle for higher-order functions**: When a function is used as a value (passed as an argument), it is loaded via `ldc` with a `CONSTANT_MethodHandle` constant pool entry (kind `REF_invokeStatic = 6`). The callee uses `invokevirtual MethodHandle.invoke(...)` for the indirect call. Direct calls to known functions skip the MethodHandle and use `invokestatic` directly.

**StackMapTable**: JVM 7+ requires `StackMapTable` attributes for methods with branches. The generated `main(String[])` has branches for argument handling. User-defined methods with `case`/`of` pattern matching also have branches (if/else chain over constructor tags) and require StackMapTable entries.

**Text codegen**: `Awsum.Codegen.JVM` produces a Jasmin-like textual representation of the bytecode. This is used for `awsum asm -t jvm` output and golden snapshot tests. The binary assembler (`assembleJVM`) is used for `awsum build -t jvm` (outputs `.class`) and `awsum run -t jvm`.

## CLR-Specific Details

**Binary format**: The `.dll` is a PE (Portable Executable) file generated directly in Haskell (`Awsum.Codegen.CLR.Assemble`), with no external tools — no `ilasm`, no `csc`. Only `dotnet` is needed to run. The assembler emits DOS header, PE/COFF headers, a `.text` section with CLR metadata and CIL method bodies.

**Metadata**: The PE file contains 9 CLR metadata tables (Module, TypeRef, TypeDef, MethodDef, Param, MemberRef, StandAloneSig, TypeSpec, Assembly, AssemblyRef) and 4 metadata heaps (#Strings, #US for user strings in UTF-16LE, #Blob for signatures, #GUID). The StandAloneSig table declares local variables for methods that use `stloc`/`ldloc` (e.g. pattern matching).

**Value representation**: All values are `object` (System.Object). Strings are `System.String`. Function references are `System.Func<object,...,object>` generic delegates. Integers (`Int32`, `UInt8`) are boxed `System.Int32`. `IO Unit` is `null`.

**Func delegates for higher-order functions**: When a function is used as a value (passed as an argument), it is wrapped in a `System.Func` delegate via `ldftn` + `newobj`. The arity determines the generic instantiation: a 1-arg function becomes `Func<object, object>`, a 2-arg function becomes `Func<object, object, object>`, etc. Indirect calls use `callvirt Invoke(...)` on the delegate. Direct calls to known functions use `call` directly — no delegate overhead.

**Generic type variables in signatures**: MemberRef signatures for `Invoke` on generic Func TypeSpec instantiations use `ELEMENT_TYPE_VAR` (0x13) for type parameters, not concrete `object` types. This is required by the CLR metadata specification.

**Runtime configuration**: Running with `dotnet` requires an `AwsumMain.runtimeconfig.json` alongside the DLL. The compiler generates a fixed template targeting .NET 9.0 with `"rollForward": "LatestMajor"` for forward-compatibility with newer .NET versions.

**Text codegen**: `Awsum.Codegen.CLR` produces an ilasm-like textual representation of the CIL bytecode. This is used for `awsum asm -t clr` output and golden snapshot tests. The binary assembler (`assembleCLR`) is used for `awsum build -t clr` (outputs `.dll`) and `awsum run -t clr`.

## WASM-Specific Details

**Binary format**: The `.wasm` binary is generated directly in Haskell (`Awsum.Codegen.WASM.Assemble`), with no external tools — no `wat2wasm`, no WABT. Only `wasmtime` is needed to run. Uses LEB128 encoding (unlike JVM's big-endian fixed-width integers).

**WASI imports**: Three WASI functions are imported from `wasi_snapshot_preview1`: `fd_write` (stdout), `args_sizes_get` and `args_get` (CLI arguments).

**Value representation**: All values are `i32` — pointers into linear memory. Strings are null-terminated byte sequences. Function references are table indices. Integers (`Int32`, `UInt8`) are pointers to 4-byte heap cells holding the value. `IO Unit` is `0`.

**Memory layout**: One page (64KB) of linear memory. Bytes 0-63 are scratch space for WASI iovec structs and argument buffers. String constants start at byte 64. A bump allocator (`$heap` global) grows from the end of the string pool. No deallocation — the OS reclaims memory on exit (same as LLVM).

**Runtime helpers**: Implemented in WASM itself, no host imports beyond WASI. Three structural: `__strlen` (null-byte scan), `__alloc` (4-byte-aligned bump allocator), `__memcpy` (byte-by-byte copy). Two I/O: `__concat` (strlen + alloc + memcpy + null-terminate) and `__print` (iovec + `fd_write`). Two boxing/show: `__box_i32` (allocate 4 bytes, store value, return pointer) and `__show_i32` (render decimal into a 16-byte buffer — handles sign, zero, and the `INT_MIN` corner case via unsigned division on the magnitude). One argv: `__get_arg` (WASI args_sizes_get + args_get, returns argv[1] or empty string). One string-manipulation: `__splitOnFirst` (hand-rolled byte scan because WASM has no native substring search). The remainder are honest-arithmetic and parse primitives — `__predInt32`, `__predUInt8`, `__succInt32`, `__succUInt8`, `__eq_i32` (shared by both equality builtins since both types flow as i32 cells), `__addInt32`, `__addUInt8`, `__parseInt32`, `__parseUInt8` — each returning a pointer to a freshly allocated `Either` container in the same `[i32 tag, i32 fields…]` layout that user constructors use. `__parseInt32` is the only helper that needs an i64 local (the accumulator), and the only one whose `locals` declaration uses two run-length groups (`8 i32`, then `1 i64`) instead of one.

**Text codegen**: `Awsum.Codegen.WASM` produces WAT (WebAssembly Text Format) S-expressions. This is used for `awsum asm -t wasm` output and golden snapshot tests. The binary assembler (`assembleWASM`) is used for `awsum build -t wasm` (outputs `.wasm`) and `awsum run -t wasm`.
