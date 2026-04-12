# Target Implementation Details

How the same Awsum program maps to each compilation target. All targets produce identical stdout for the same input — this is a compiler invariant, verified by the test suite.

## Overview

| | JS | Lua | LLVM |
|---|---|---|---|
| **Runtime** | Node.js | Lua 5.1+ | Native binary (via clang) |
| **String type** | Native JS string | Native Lua string | `ptr` to null-terminated C string |
| **Concat** | `+` | `..` | `strlen` + `malloc` + `strcpy` + `strcat` |
| **Print** | `process.stdout.write(s)` | `io.write(s)` | `printf("%s", s)` |
| **Constants** | `const name = expr;` | `name = expr` (global) | Zero-arg function, called on each use |
| **Functions** | `function` declaration (hoisted) | `function ... end` | `define ptr @name(ptr ...) { ... }` |
| **Memory** | GC | GC | Manual (`malloc`, no `free`) |
| **Name mangling** | `v_` prefix, `main` unchanged | `v_` prefix, `main` unchanged | `v_` prefix for all (including `main` → `v_main`) |

## String Concatenation

All three backends guarantee identical results because the type checker ensures both operands are `String`.

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

## Print

All backends print without a trailing newline — `IO.Stdout.print` outputs exactly what it receives.

**JS**: `process.stdout.write(String(s))` — unbuffered for TTY, buffered for pipes, flushed on exit.

**Lua**: `io.write(tostring(s))` — buffered, flushed on exit.

**LLVM**: `printf("%s", s)` — C stdio buffering, implicit flush on `return 0` from `main`.

## Constants (CValDef)

Zero-argument definitions like `greeting = "Hello"` are compiled differently per target:

**JS**: `const v_greeting = "Hello";` — evaluated once, hoisted by the runner.

**Lua**: `v_greeting = "Hello"` — global assignment, evaluated once before `main` runs.

**LLVM**: Zero-arg function `define ptr @v_greeting() { ... }` — called each time the value is referenced. Safe because all expressions are pure (same result every time). Avoids the complexity of LLVM global initializers for non-constant expressions.

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

## Name Mangling

All targets prefix user names with `v_` and replace non-alphanumeric characters (except `_` and `'`) with `_`.

The difference: JS and Lua keep `main` unchanged because their runners call `main(arg)` by name. LLVM mangles `main` to `v_main` because `@main` is reserved as the C entry point.

## LLVM-Specific Details

**Opaque pointers**: The LLVM backend requires LLVM 15+ (opaque pointer support). All values — strings, function pointers, unit — are represented as `ptr`.

**String constant pool**: All string literals are collected in a pre-pass, deduplicated, and emitted as named LLVM constants (`@.str.0`, `@.str.1`, ...). Each constant is a null-terminated `[N x i8]` array.

**SSA form**: LLVM IR requires Static Single Assignment — each variable is assigned exactly once. The codegen uses a counter to generate unique temporaries (`%t0`, `%t1`, `%t2`, ...), reset per function.

**Memory management**: `__concat` allocates with `malloc` and never frees. For short-lived programs this is acceptable — the OS reclaims all memory on exit. A future GC or arena allocator would address this.

**Compilation**: The `awsum run -t llvm` command writes a `.ll` file, compiles it with `clang -O2`, and executes the resulting binary. We use `-O2` because runtime performance is prioritized over compilation speed (see [Design Principles](../README.md#priority-order)).
