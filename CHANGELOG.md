# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Removed

- **Lua backend (`-t lua`).** The Lua target — `Awsum.Codegen.Lua`, the `TargetLua` enum case, the CLI flag, the runner, the per-test snapshot under every program in `.snapshots/successful/*/compiler/compiled.lua`, and the cross-backend equivalence assertion against `runLua` — has been removed end-to-end. The supported target list is now `llvm | jvm | clr | wasm | js`. CI no longer installs Lua 5.1 (`leafo/gh-actions-lua` step on Linux/macOS, the LuaBinaries direct download on Windows). Property tests and snapshot tests now spawn five backend processes per case instead of six. Docs (`README.md`, `CLAUDE.md`, `docs/targets.md`, `docs/recursion.md`, `docs/platform-version-policy.md`) updated to drop Lua-specific sections, code blocks, and runtime entries.

### Added

- **Eta-reduced (point-free) top-level definitions.** A definition with no parameters on the LHS is accepted whenever its signature has arrow shape and the RHS already has the full function type — e.g. `say : String -> IOUnit; say = IO.Stdout.print`, or aliasing another top-level. Previously this only worked for the `BuiltIn.foo` form (which keeps its zero-cost erasure path); the lowering eta-expands every other RHS into a regular first-order function so the invariant "`CBuiltIn` only appears in callee position of `CCall`" still holds and every backend handles the alias as a normal call. Defining with *more* parameters than the signature allows is still an `ArityMismatch` error.

- **Property-based tests across all backends** — new `awsum-test` group `Property tests` plus `just test-property` target. Each property has an Awsum source under [test/sources/property/](test/sources/property/), a QuickCheck generator and an expected-output function in [test/Awsum/PropertySpec.hs](test/Awsum/PropertySpec.hs); the framework compiles the source once per property, then feeds N constructively-generated inputs through every backend and asserts byte-for-byte equality with the Haskell-computed expected output. **29 starter properties** covering integer arithmetic (commutativity, associativity, zero identity on both sides, agreement with Haskell on no-overflow inputs), succ/pred (round-trip + boundary failure-iff-extreme), equality (reflexive, symmetric for Int32 / UInt8), parser/show round-trip for both numeric types, the string monoid laws (left + right identity, associativity), splitOnFirst round-trip in both positive (sep present) and negative (sep absent) branches, and boolean laws (involution of not, commutativity of and / or, De Morgan). All 29 green on every backend; full run is ~145 s. Also extracts compile + run helpers into [test/Awsum/RunBackend.hs](test/Awsum/RunBackend.hs) (`Backend`, `CompiledArtifacts`, `compileFromFile`, `runOn`, `runOnAll`) shared with snapshot tests.

- **`Tuple3 a b c` in Prelude** — three-positional-field single-constructor type alongside `Tuple2`. Same conventions: prefer a domain-specific single-constructor sum when the fields have meaningful names; reach for `Tuple3` only when they honestly don't. Used by the new associativity-of-addition properties (`addInt32-associative`, `addUInt8-associative`) and by the refactored `concat-associative` to thread three positional arguments out of one `argv[1]` (`"a:b:c"` → two `splitOnFirst ":"` → `Tuple3 a b c`). Tree-shake drops it from any program that doesn't reference it, so adding it is zero-cost for existing code.

- **Associativity properties for integer addition** — `addInt32-associative` and `addUInt8-associative` join the property catalogue. Both use a constructive no-overflow triple generator that picks `(a, b, c)` so that `a+b`, `b+c` and `(a+b)+c` all stay in range — the intersection of those intervals always contains 0, so the generator never has to retry.

- **Integer subtraction and negation primitives.** Three new prelude built-ins, all five backends, with case-based snapshot tests:
  - `subInt32 : Int32 -> Int32 -> Either ArithError Int32`. Honest signed subtraction. Detects overflow with the XOR trick `(a ^ b) & (a ^ diff) < 0` (matches the LLVM/JVM/CLR/WASM `addInt32` shape, with `i32.sub` in place of `i32.add`); LLVM uses the `llvm.ssub.with.overflow.i32` intrinsic. Direction is read off `a >= 0`: when subtraction overflows, signs of `a` and `b` differ, so `a >= 0` ⇒ `b < 0` ⇒ Overflow, otherwise Underflow. Test under [test/sources/successful/int32-sub/](test/sources/successful/int32-sub/) covers the five reachable cases — ordinary positive, ordinary mixed-sign, `maxInt32 - (-1)` (Overflow), `minInt32 - 1` (Underflow), and `0 - minInt32` (Overflow, the negation-of-minInt32 corner).
  - `negInt32 : Int32 -> Either OverflowError Int32`. Only `minInt32` overflows on negation (its absolute value is one above `maxInt32` in two's complement); every other input flips sign cleanly. Single-error type because only positive overflow is reachable. Test under [test/sources/successful/int32-neg/](test/sources/successful/int32-neg/) covers positive, negative non-min, zero, `maxInt32`, and the `minInt32` overflow case.
  - `subUInt8 : UInt8 -> UInt8 -> Either UnderflowError UInt8`. Honest unsigned subtraction; underflow is reachable when `a < b`. The i32 difference is in -255..255, so a single signed-`< 0` check picks the underflow branch — no widening needed beyond the already-i32-typed cells. Symmetric to `addUInt8` with `UnderflowError` instead of `OverflowError`. Test under [test/sources/successful/uint8-sub/](test/sources/successful/uint8-sub/) covers the boundary `5 - 5 = 0`, the largest non-underflow `255 - 0 = 255`, and the smallest / largest underflows `0 - 1` and `0 - 255`.

- **Cross-operation properties for `subInt32` / `negInt32`** — two new entries in the property catalogue, pinning the algebraic relationship between subtraction, negation, and addition:
  - `subInt32-equals-add-neg`: `subInt32 a b == addInt32 a (negInt32 b)`. New constructive generator `NoOverflowSubInt32NonMinB` picks `(a, b)` so that `b ≠ minInt32` (otherwise `negInt32 b` would fail) and `a - b` stays in Int32 range, so both sides land on the same `Right`.
  - `addInt32-neg-cancels`: `addInt32 (negInt32 x) x == Right 0`. Reuses the existing `NonMinInt32` generator — the only constraint is `x ≠ minInt32`; the sum `-x + x = 0` is always in range.

- **Integer multiplication primitives.** Two new prelude built-ins, all five backends, with case-based snapshot tests:
  - `mulUInt8 : UInt8 -> UInt8 -> Either OverflowError UInt8`. Honest unsigned multiplication; both operands are in 0..255 so the i32 product is in 0..65025 (well within native range), and a single `> 255` check picks the overflow branch. Symmetric to `addUInt8`. Test under [test/sources/successful/uint8-mul/](test/sources/successful/uint8-mul/) covers the boundary `15 * 17 = 255`, the smallest overflow `16 * 16`, the maximum overflow `255 * 255`, the zero-annihilator `0 * 200`, and the one-identity `1 * 200`.
  - `mulInt32 : Int32 -> Int32 -> Either ArithError Int32`. Honest signed multiplication. LLVM uses `llvm.smul.with.overflow.i32` with direction read off `(a xor b) >= 0` (same-sign overflow → Overflow, opposite-sign → Underflow). JVM/CLR/WASM widen both operands to 64 bits, multiply at long width, then range-check against `[INT32_MIN, INT32_MAX]` — direction comes directly from `lcmp`/`bgt`/`blt` on the long product. JVM binary materialises the long bounds via `ldc N; i2l` since the assembler has no CPLong slot; CLR uses `ldc.i4 N; conv.i8`; WASM uses `i64.const`. Test under [test/sources/successful/int32-mul/](test/sources/successful/int32-mul/) covers ordinary positive/mixed-sign products, positive/negative overflow, the special `minInt32 * (-1)` corner (math result `2147483648` overflows positively), and the `minInt32 * 1` identity case where the result is itself `minInt32`.

- **Multiplication properties for `mulUInt8` / `mulInt32`** — nine new entries in the property catalogue (now 40 total), exercising the distributivity gap that's been in the backlog since the property infrastructure was first set up:
  - `mulUInt8-commutative` / `mulUInt8-one-identity-left` / `mulUInt8-one-identity-right` / `mulUInt8-associative`. Constructive generators `NoOverflowMulUInt8` and `NoOverflowMulUInt8Triple` pick `(a, b)` and `(a, b, c)` so every intermediate product stays in `0..255`. The triple generator bounds all three of `a*b`, `b*c` and `a*b*c` (not just the left grouping) — under overflow-checked arithmetic the two associativity groupings `(a*b)*c` and `a*(b*c)` are not interchangeable, so e.g. `(0, 216, 99)` has product `0` but `b*c = 21384` overflows on the right grouping. `c` is drawn from the intersection `[0, min(255/b, 255/(a*b))]`, with zero denominators widening to `0..255` (a vacuous constraint when the product is forced to `0`).
  - `mulInt32-commutative` / `mulInt32-one-identity-left` / `mulInt32-one-identity-right` / `mulInt32-associative`. Generators `NoOverflowMulInt32` and `NoOverflowMulInt32Triple` mirror the UInt8 shape on signed bounds: `b ∈ [-maxInt32 / |a|, maxInt32 / |a|]` for the pair, and the triple bounds `c` by the intersection of the `b*c` and `a*b*c` no-overflow intervals. `a == minInt32` (where `|a| > maxInt32` forces the bounds to `0`) degenerates to `b = c = 0`, which keeps every product zero.
  - `mulInt32-distributive-over-addInt32`: `mulInt32 a (addInt32 b c) == addInt32 (mulInt32 a b) (mulInt32 a c)` — the distributivity law, the original backlog entry that motivated `mulInt32`. Generator `NoOverflowMulDistribInt32` picks `b, c ∈ [-bound/2, bound/2]` where `bound = maxInt32 / max(|a|, 1)`. The half-amplitude makes every intermediate (`b+c`, `a*b`, `a*c`, `a*(b+c)`) stay in Int32 range simultaneously by construction — no rejection sampling.

### Changed

- **Symbol visibility tightened across LLVM, JVM, CLR, WASM.** A compiled CLI program now exposes only the platform-mandated entry point externally — everything else (user `top-level`s, generated constructor wrappers, runtime helpers like `__concat` / `__print`) becomes an implementation detail. WASM emits `(export ...)` only for `_start` and `memory` (was: every user function plus `memory`); LLVM marks user / helper functions `internal` linkage (was: implicit `external`); JVM drops `public` from user methods, runtime helpers, and `<init>` — only `main([Ljava/lang/String;)V` keeps it (was: `public static` everywhere); CLR emits `private hidebysig` on user methods, helpers, `Main`, and `.ctor` — `Main` is found by the runtime via `.entrypoint` metadata token regardless of access. Cross-backend stdout equivalence is unchanged. Renaming any non-entry top-level is no longer a breaking change for any consumer.

### Fixed

- **JVM `ClassFormatError` / `VerifyError` / `Operand stack overflow` on deeply nested constructors.** Same family of "headers say a generous-but-fixed number, real shape can exceed it" bugs as the CLR fix below — surfaced together by `either-nested-right-300` / `either-nested-right-case-300`. Four independent issues in [src/Awsum/Codegen/JVM/Assemble.hs](src/Awsum/Codegen/JVM/Assemble.hs):
  - **`max_locals` and `max_stack` were both hardcoded to 256** in the Code attribute. JVM Spec §4.7.3 requires both to be the actual peak — verifier rejects any frame whose `number_of_locals` exceeds `max_locals` (`bad type array size`) and any path whose stack peaks above `max_stack` (`Operand stack overflow`). Now computed per method via two new helpers `exprMaxLocals` / `exprMaxStack` that walk the Core IR mirroring the emit shape: `CCase` is additive (2 slots arr+tag plus widest binding set, recursing into arms); `CCon` uses the dup/aastore chain so each level pins 3 slots on the stack across the next field's evaluation. Static helpers (`__concat`, `__predInt32`, `__addInt32`, `__parseInt32`, …) keep the previous 256/256 since their hand-written bytecode bodies are bounded by inspection.
  - **`bcAload` / `bcAstore` / `bcIload` / `bcIstore` / `bcLload` / `bcLstore` silently truncated slot indices ≥ 256 to one byte.** JVM Spec §6.5 specifies these instructions take an unsigned 8-bit operand; for slots ≥ 256 the `wide` prefix (0xC4) extends the operand to two bytes. Without it, `astore 256` encoded as `astore 0`, overwriting the method parameter and producing `ClassCastException: String cannot be cast to [Ljava/lang/Object;` at the first reuse. Bites any program whose `CCase` nesting pushes `cNextLocal` past 255 — for the unwrap test that's around depth 86 (1 param + 84 levels × 3 slots).
  - **`exprMaxStack` for `CCall` underestimated by one slot when the callee was a parameter.** First-class calls (callee not in `cFunDefs`) push the callee onto the stack before evaluating args (it stays pinned across arg emission). The original formula treated every `CVar` callee as a direct call. Reproducer: `compose g f x = g (f x)` peaked at 3 slots but was declared `max_stack = 2`, so the verifier rejected it with `Operand stack overflow @4: aload_1`. Now the helper unconditionally assumes the first-class shape (one extra slot for the callee) — overestimates direct-call methods by one slot, which is harmless and keeps the helper context-free.
  - Reproducer (no longer reproduces): `awsum run -t jvm test/sources/successful/either-nested-right-300/code/Main.aww`.

- **CLR `InvalidProgramException` on deeply nested constructors.** Surfaced by the new `either-nested-right-300` / `either-nested-right-case-300` snapshot tests. Three independent bugs in [src/Awsum/Codegen/CLR/Assemble.hs](src/Awsum/Codegen/CLR/Assemble.hs), all triggered together at depths around `Right (Right (Right ...))` ≥ 5–10:
  - **`MaxStack` was hardcoded to 16 in every fat method header.** Per ECMA-335 §II.25.4.3 `MaxStack` is the maximum operand-stack depth a method ever reaches, and the verifier rejects any method that exceeds the declared value with `InvalidProgramException`. Now computed per method via a new `exprStackDepth :: CExpr -> Int` that mirrors the `emitExpr` shape construct-by-construct; static helpers (`__concat`, `__predInt32`, `__addInt32`, `__parseInt32`, …) keep the previous `MaxStack = 16` since their hand-written CIL bodies have known shallow stacks.
  - **`CCon` left the partially built array on the operand stack across each field's evaluation** via the dup/stelem pattern, peaking at ~2N for a depth-N constructor chain. Replaced with a temp-local strategy: `newarr` → `stloc tmpSlot`, then for each tag/field `ldloc tmpSlot; ldc index; <field>; stelem.ref` (stack returns to 0 between fields). Per-`CCon` tmp-slot allocation is threaded through a new `eNextScratch :: Int` field on `ECtx`, since the slot is not user-visible and so isn't tracked in `eLocals` — without that counter, two nested `CCon`s would alias the same slot. `CCase` was migrated to the same counter to keep slot allocation uniform. `exprLocalsNeeded` now adds 1 for each `CCon` level, additive with the field's own demand. Peak stack depth becomes O(field) per level instead of O(depth).
  - **`addLocalSig` truncated the LocalVarSig `Count` field to 1 byte** via `fromIntegral nLocals :: Word8`, producing malformed signatures for any method with ≥ 128 locals — exactly what the new CCon tmp-slot accounting can request. The Count is a *compressed* unsigned integer per ECMA-335 §II.23.2; switched to the existing `compressU` helper, which handles 1-, 2-, and 4-byte forms uniformly with the rest of the assembler.
  - Design note at `awsum-management/clr-maxstack-and-ccon-stack-depth.md`. Reproducer (no longer reproduces): `awsum run -t clr test/sources/successful/either-nested-right-300/code/Main.aww`.

- **Free type variables in constructor fields now rejected.** A type declaration like `type X = X a` previously passed `awsum check` because the typechecker silently treated `a` as a fresh per-constructor tyvar disconnected from `X`'s parameter list — the type then broke at first use with a confusing `Type mismatch: expected a$N_M` error. New diagnostic `Unknown type variable: 'a' is not declared as a type parameter`, raised by `validateTypeParams` when a `TyVar` in any constructor field is not in the declaration's parameter list. The `_`-prefixed case keeps its more specific `ReferencingIgnoredTypeVar` error.

- **JVM `VerifyError: Inconsistent stackmap frames` for deeply nested `case`s.** Surfaced by the new property tests on the first run. Two distinct issues, both around slot reuse between sibling arms of a `case`:
  - Non-tail `emitExpr` for `CCase` set `cNextLocal = bindSlotStart + length vars` for each arm body — so an arm with 1 binding and an arm with 2 bindings opened nested cases at *different* slot indices, and a slot that was an inner-case tag (int) on one path was an outer binding (Object) on another. The verifier merge of int + Object is `Top`, but our SMT wrote `Object`. Tail-position `emitTailCase` had always used `maxBindingsCount` for the same reason; non-tail now matches.
  - SMT slot-type resolution in `caseSMT` only knew about tag slots from cases that produced a `BranchTarget` (i.e. multi-arm cases that emit `if_icmpne`). Single-arm `case`s (e.g. `case t of Tuple2 a b -> ...`) emit no branch instruction and so left their tag slot off the radar, which the verifier saw as `int` while outer SMT frames declared it `Object`. `CodeWithMeta` now carries a `cwIntSlots` field that propagates through every emitter and feeds `caseSMT` so single-arm tag slots are tracked too.
  - Reproducer (no longer reproduces): `awsum run -t jvm test/sources/property/addInt32-commutative/code/Main.aww --input "1:2"`.

- **Prelude** — `parseInt32 : String -> Either ParseError Int32` and `parseUInt8 : String -> Either ParseError UInt8`, plus a new prelude type `type ParseError = ParseError` with `showParseError`. Strict decimal grammar mirroring the language's integer literal: optional `-` (Int32 only), one or more ASCII digits, nothing else — no `+`, no whitespace, no trailing characters. The docstring on each parser lists every accepted and rejected input form. Each backend handrolls a byte-scan parser with the same algorithm: i64 (or equivalent) accumulator capped at `|minInt32|` for Int32, i32 capped at 255 for UInt8 — no native parser is used (`Integer.parseInt` accepts `+`, `tonumber` accepts hex/exponent, `Number()` is permissive about whitespace, etc.).

- **Prelude** — `splitOnFirst : String -> String -> Maybe (Tuple2 String String)` and a new `type Tuple2 a b = Tuple2 a b`. Splits at the first occurrence of `separator`; the docstring lists eight worked examples (multiple occurrences, multi-char separator, empty separator, separator at start / end / equal to string, separator longer than string, miss). Backends defer to native substring search where available — `strstr` (LLVM, libc), `String.indexOf` (JVM), `String.IndexOf` (CLR), `String.indexOf` (JS), `string.find` plain-text mode (Lua) — and a handrolled byte-scan in WASM (no native search there). Matching is byte-level, not codepoint-level; UTF-8-aware splitting will be a separate API.

- **Prelude** — `addInt32 : Int32 -> Int32 -> Either ArithError Int32` and `addUInt8 : UInt8 -> UInt8 -> Either OverflowError UInt8`, joining `predInt32` / `succInt32` / `predUInt8` / `succUInt8` as honest-arithmetic primitives. `addInt32` introduces a new prelude type `type ArithError = Underflow | Overflow` (with `showArithError`) because signed addition can fail at *both* ends from a single operation — `maxInt32 + 1` is `Overflow`, `minInt32 + (-1)` is `Underflow`. `addUInt8` keeps the existing `OverflowError` since unsigned addition can only overflow.

- **Build provenance** — `release.yml` calls `actions/attest-build-provenance@v4` on each `awsum-<version>-<target>.{tar.gz,zip}` archive after packaging; the release job now declares `id-token: write` + `attestations: write`. Every published asset gets a Sigstore-signed attestation tying it to a specific workflow run and commit. Users verify with `gh attestation verify <file> --repo awsum-lang/awsum`. Closes the gap where a stolen maintainer token could replace a release asset without the workflow's OIDC identity.

- **`CONTRIBUTING.md`** — covers the dev-loop commands, the signed-commits requirement on `main` (with a working `~/.gitconfig` example for SSH signing), and the PR / CHANGELOG conventions.

## [0.0.3] - 2026-04-25

### Added

- **Prelude** — `showUnit : Unit -> String` (returns the literal `"Unit"`). The `Unit` type was already prelude-visible; this fills in the missing stringifier so every prelude type now has a matching `show*`.

- **Tag-driven release workflow** — pushing a `v*` tag triggers `release.yml`, which reuses `check-and-build.yml` (new opt-in `upload-artifacts` input) to produce binaries for all four host platforms, packages them as `awsum-<version>-<target>.tar.gz` (Unix) / `awsum-<version>-<target>.zip` (Windows) plus a `SHA256SUMS` file, and publishes them as a GitHub Release pinned to the tagged commit. Asset names embed the version because the website always links to a specific release — the GitHub `latest/download/` redirect is deliberately not used. No `workflow_dispatch` — the tag is the only source of truth.

- **Cross-platform CI** — `check-and-build.yml` now runs on four OS / architecture combinations (was Linux x86_64 only): `ubuntu-24.04` (x86_64), `ubuntu-24.04-arm` (aarch64), `macos-15` (Apple Silicon), `windows-2025` (x86_64). `fail-fast: false`, per-arch cache keys, `STACK_ROOT` pinned to a workspace-relative path so caching works identically on every OS, runner OS versions pinned (no `*-latest`).

- **Toolchain versions pinned to the documented floor on every runner** — LLVM 15.0.7 (apt `clang-15` + `/usr/local/bin` symlink on Linux, `brew install llvm@15` with PATH prepend on macOS, official LLVM Windows installer silent-extracted into a pristine directory on Windows; verify-step fails CI loudly if `clang --version` doesn't report 15.x), Java 8 Zulu (lowest JDK installable on macOS ARM64 via `actions/setup-java`), Lua 5.1.5 (LuaBinaries direct download on Windows, `leafo/gh-actions-lua` elsewhere), Stack 3.9.1 (manual upgrades). On Windows the test harness's `clang` is routed via a project-root symlink to LLVM 15 — Stack would otherwise prepend GHC's bundled mingw clang (LLVM 14-era) to the child process PATH and shadow the install.

- **Supported host platforms documented in README** — a new table next to **Targets** lists OS / architecture / platform identifier / GitHub runner. Platform identifiers (`linux-x86_64-gnu`, `linux-aarch64-gnu`, `macos-aarch64`, `windows-x86_64`) double as the suffix in future release-asset filenames; Linux keeps `-gnu` to leave room for a future `-musl` build alongside, macOS / Windows have a single ABI per OS in our build pipeline so no suffix is needed.

- **`.gitattributes` forces LF on all text files** — Windows checkouts with default `core.autocrlf=true` were silently turning `.aww` sources, `stdlib/Prelude.aww` (embedded into the binary via `file-embed` at compile time), and `.snapshots/**` golden files into CRLF. That broke the parser's column tracker (Megaparsec counts `\r` as a column increment) and the byte-for-byte golden-snapshot matcher. Single rule `* text=auto eol=lf` covers every text extension uniformly.

## [0.0.2] - 2026-04-24

### Added

- **Language**
  - Sum types (`type Color = Red | Green | Blue`) and exhaustive `case`/`of` pattern matching.
  - Parametric sum types (`type Lookup a = Found a | NotFound`) with polymorphic type parameters.
  - Empty / uninhabited types (`type Never`) with uninhabited-type detection in the typechecker.
  - Integer types: `Int32` (signed 32-bit) and `UInt8` (unsigned 8-bit).
  - Integer literals with compile-time range validation against the declared type.
  - No-defaulting rule: the compiler never picks a type for the user — not for integer literals, not for any other ambiguous context. Ambiguous = compile error, fix with an explicit annotation.
  - Constructors are first-class — passable to HOFs via automatic eta-expansion into `$con$`-prefixed wrapper functions (tree-shaken if unused).
  - Underscore convention for intentionally-unused bindings at every level: values (`_x`), function params (`main _input = …`), pattern binders (`Box _v ->`), top-level defs (`_helper`), type parameters (`type Phantom _tag`), type names (`type _A`) and constructors (`type A = _B | C`). Referencing any `_`-prefixed name is a compile error (`ReferencingIgnored…` family) — the opt-out is enforced.
  - Bare `_` wildcards in pattern / function-param position — introduce no binding, so multiple `_` don't collide. Rejected as a nameable declaration (top-level, type, constructor, type-param).
  - Shadowing is now a compile error at every binding site (was a silent behaviour before).

- **Prelude** (implicitly imported — no `import` needed)
  - Bundled prelude compiled into the binary via `file-embed`; user programs see its declarations without an `import` line. Unused entries are dropped by reachability-based tree-shake from `main`.
  - Types: `Bool` (`True` | `False`), `Either a b` (`Left` | `Right`), `Maybe a` (`Just` | `Nothing`), `Unit`, `UnderflowError`, `OverflowError`.
  - Bool operators: `not`, `and`, `or`.
  - String concat: `(++) : String -> String -> String`.
  - Show functions: `showInt32`, `showUInt8`, `showUnderflowError`, `showOverflowError`.
  - Honest arithmetic: `predInt32` / `succInt32 : Int32 -> Either {Underflow,Overflow}Error Int32`; same shape for `UInt8`. The `Either` wrapping is mandatory — overflow/underflow cannot silently wrap.
  - Equality: `eqInt32 : Int32 -> Int32 -> Bool`, `eqUInt8 : UInt8 -> UInt8 -> Bool`.
  - `BuiltIn.foo` reserved syntax — per-target compiler implementation escape hatch behind prelude-visible names.

- **Backends** (four new targets)
  - **LLVM** — native binary via Clang (LLVM 15+ for opaque-pointer support).
  - **JVM** — Java 7+ bytecode generated directly (no Jasmin / javac dependency); ships a built-in `.class` assembler (`Awsum.Codegen.JVM.Assemble`).
  - **CLR** — .NET 9+ `.dll` generated directly as a PE file (no ilasm / csc).
  - **WASM** — WebAssembly with WASI preview 1 (tested against wasmtime); ships a WAT assembler for `.wasm` binaries.
  - Cross-backend equivalence is a compiler invariant: every successful test asserts byte-for-byte identical stdout across LLVM, JVM, CLR, WASM, JS, and Lua.

- **Stack-safe recursion**
  - Three-pass Core-to-Core pipeline that normalises every recursion shape into a loop on every backend:
    - `Awsum.Scc` — merges mutual recursion into self-recursion via Tarjan SCC + sum-tag dispatch.
    - `Awsum.Cps` — rewrites non-tail self-recursion into tail-self through a defunctionalised K chain.
    - `Awsum.Tco` — folds the remaining self-tail-calls into `CLoop` / `CContinue`.
  - Self, mutual, and non-tail recursion all run in bounded stack on all six backends — including JVM and JS, which have no native cross-method tail calls.
  - 1 000 000-iteration stress tests per recursion shape per backend.
  - `Awsum.StackSafety` rejects mutually-recursive top-level values (no fixed point) with a dedicated diagnostic before the merge pass runs.

- **Platform effects**
  - `--program-type cli` flag introduced; mandatory for any command that goes through the typechecker.
  - Qualified effect names (`IO.Stdout.print : String -> IOUnit`) — a CLI-program platform effect requiring both `--program-type cli` and `import IO.Stdout`.
  - `Awsum.Program.platformTable` dispatch ready to host `ProgramBrowser` / `ProgramModule` without touching existing modules.

- **Compiler**
  - Source positions (`SrcSpan`) tracked through the entire pipeline — error messages now include line and column numbers with clickable terminal links.
  - `awsum check --json` outputs structured diagnostics with `severity` (`"error"` | `"warning"`) and `fixes` (array of `{title, edits}`) fields. Parse-time, type-time, and warning diagnostics share one shape.
  - `awsum check --strict` escalates warnings to a non-zero exit code for CI.
  - Warnings with rename-to-`_name` quick-fixes: `UnusedParameter`, `UnusedTopLevel` (unreachable from `main`, reports only the source-SCC roots), `UnusedTypeParameter`.
  - New error family for the underscore convention: `ReferencingIgnored`, `ReferencingIgnoredTypeVar`, `ReferencingIgnoredConstructor`, `UnnamedType`, `UnnamedConstructor`, `UnnamedTypeParameter`, `DuplicateTypeParameter`.
  - Unreachable case arms produce an error (`UnreachableCase`).
  - Per-identifier source spans on function params, type parameters, constructor declarations, and constructor patterns — enables precise caret placement and minimal-edit quick-fixes.
  - New module `Awsum.Diagnostic` centralises severity/fix/edit types and JSON encoding.
  - Reachability-based tree-shake from `main` over all top-level Core decls (user, prelude, generated constructor wrappers) — unused prelude entries never reach codegen.

- **CLI**
  - `awsum core FILE --program-type cli` — print elaborated/lowered Core IR.
  - `awsum asm FILE -t {jvm|clr|wasm}` — print target assembly text (Jasmin-like / CIL / WAT).
  - `awsum symbols FILE --json` — emit an LSP-style `DocumentSymbol` array for Outline view and workspace symbol search.
  - `awsum run --input TEXT` / `awsum run --stdin` for passing input to `main`.

- **Documentation**
  - `docs/prelude.md` — Prelude + BuiltIn architecture design doc.
  - `docs/recursion.md` — stack-safe recursion pipeline walkthrough.
  - `docs/targets.md` — per-backend implementation details.
  - `docs/platform-version-policy.md` — which runtime versions each backend targets and why.

- **Testing**
  - Cross-backend equivalence tests: each `test/sources/successful/NAME/` is compiled to all six backends and asserted to produce identical stdout.
  - Golden snapshots per pipeline stage (AST, Core IR, formatted source, per-backend output text, runtime output).
  - Auto-detection of tests — adding a new test program in `test/sources/successful/` is enough; no registration required.
  - Error snapshot tests: `test/sources/errors/` with JSON diagnostics as the golden.

## [0.0.1] - 2025-09-11

### Added

- **Language**
  - Line and block comments as top-level items (preserved in round-trips).
  - Trailing inline comments (`-- …`) after signatures/definitions are preserved.
  - String literals with escapes: `\n \t \r \" \\ \0`.
  - Qualified names (`IO.Stdout.print`) and imports.
  - String concatenation
  - Function declaration
  - `String` arguments
  - `print` effect

- **Backends**
  - JS backend
  - Lua backend

- **CLI**
  - `--version` / `-V` prints compiler version.
  - Commands: `check`, `build`, `run`, `ast`, `core`, `format`.

- **Formatter**
  - Stable pretty-printer: separates top-level blocks with a blank line,
    keeps a signature attached to the following definition, ensures trailing newline.

- **Documentation**
  - EBNF grammar at `docs/spec/grammar.ebnf` (applies to current release).

[0.0.1]: https://github.com/awsum-lang/awsum/releases/tag/v0.0.1
