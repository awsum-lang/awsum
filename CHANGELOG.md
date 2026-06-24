# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Until `1.0.0`, this project does not follow SemVer. Every release increments only the patch (`0.0.1 → 0.0.2 → 0.0.3 …`). Any release can break the surface language, the CLI, or the JSON shapes; entries below don't separately flag "breaking" because the assumption is "anything might be". The narrower contract that does hold: within a single version, all first-party tooling — `awsum`, `awsum-vscode`, `awsum-zed`, `tree-sitter-awsum` — ships from the same version number and is mutually compatible. SemVer kicks in at `1.0.0`.

## [Unreleased]

### Fixed

- **Identifiers with an apostrophe (`xs'`, `f'`) now compile identically on all five backends.** They previously passed through to the generated LLVM IR and JavaScript verbatim — an artifact `clang` / `node` rejected, while JVM/CLR/WASM accepted it, with `build` still exiting 0. The codegen name-mangler — now a single `Awsum.Codegen.Mangle` shared by every backend, replacing six divergent copies — escapes the apostrophe injectively into ASCII on every target.
- **Non-ASCII characters in an identifier are rejected at parse time with a diagnostic pointing at the offending character**, instead of silently miscompiling on LLVM. Identifiers are ASCII `[A-Za-z0-9_']` starting with a letter or `_`; comments and string literals keep full Unicode.
- **Polymorphic recursion over a non-regular (nested) datatype now runs correctly on all five backends.** A hand-written `map`/`fold` over a type like `type Nest a = Deeper (Nest (Maybe a)) | Base a` compiled without error but crashed at runtime (JS `ReferenceError`, JVM/CLR index-out-of-bounds, WASM/LLVM trap), because the pipeline's second `Scc` merge reused the fixed pack-parameter name `$args` that a first-merge member already carried — the merged `case` shadowed its own parameter and codegen emitted a self-referential field read. The merge now picks a pack-parameter name fresh with respect to its members (`$args` when free, else `$args$N`); output is unchanged for every program that didn't hit the collision.

## [0.0.7] - 2026-06-22

### Added

- **`awsum lsp` now has an automated test suite (`Awsum.LspSpec`).** Unit tests over the request logic (formatting, diagnostics, document/workspace symbols, code actions, version-mismatch, `initializationOptions`), plus an in-process end-to-end layer driving a real server over a pipe via `lsp-test`.
- **The `Simplify` pass is switchable off for the compiler's own tests.** A library-level switch (no CLI flag) backs `just test-no-simplify`, the property suite's two pipeline modes, and `awsum-bench --snapshot`, asserting `runtime(simplify(core)) == runtime(core)` with the runtime as oracle.
- **`awsum-bench --snapshot` / `just benchmark-snapshot`: per-backend median benchmark goldens** — `median (min–max)` wall time + peak RSS under `.benchmarks/`, each run cross-checked against a stdout anchor. Manual, macOS-only, not part of `just test`/CI.
- **Benchmark programs now have committed compiler snapshots** (AST, Core, symbols, codegen text, lifetime), so a `bench.txt` delta is diagnosable from the IR diff.
- **Test harness: a 60-second ceiling on every backend run and harness compile** — a diverging program or non-terminating pass fails by name instead of hanging the suite.
- **Lambda parameters accept a type annotation: `\(n : T) -> …`.** It supplies the parameter type in synthesis position (a `let`-bound lambda, or one passed to a polymorphic higher-order function) and is verified against the known type in check position. Top-level parameters still take their type from the mandatory signature.
- **`let` bindings accept the type signature on its own line** (`n : T` then `n = e`), alongside inline `let n : T = e`, in both `let … in` and `do`-block `let`; `awsum format` preserves whichever was written.

### Changed

- **LLVM/WASM: a binder forwarded through a self-tail-call is moved into the next iteration, not copied-then-dropped** — the redundant `__inc_ref` / `__free_recursive` pair is gone from every hot loop. Output unchanged; the managed backends (JVM/CLR/JS) are untouched.
- **JS: a `let` in expression position lowers to a hoisted `const`, not a per-evaluation IIFE** (502 across the corpus → 0), with evaluation order preserved. Output unchanged.
- **JVM/CLR/WASM verifier limits (`max_stack` / `max_locals`, `.locals`) are derived from the emitted instruction stream**, not a parallel sizing traversal that could silently under-declare on an untested program shape. Output unchanged; limits only tighten toward the exact peak.
- **Internal hardening, output unchanged:** `Awsum.Cps` / `Awsum.Tco` reject later-pass Core nodes uniformly instead of via a silent catch-all; `effectfulIn`'s effectful-built-in set is derived from the `Awsum.BuiltIn` registry; the `CExpr` traversals (`freeVars`, renames, folds) are consolidated in `Awsum.Core` under one `CDrop`-as-reference convention; and the same-arity reuse carve-out is one named predicate with an arity-safety regression test.
- **Structural-row matching in the typechecker is no longer quadratic on ground rows** — `O(N²)` → `O(N log N)` via multiset / `Set` comparison when no row variable is free (the structural scan stays only for a genuinely-subsumed inner row that grew). Inferred types, acceptance, and diagnostics are identical.
- **`docs/spec/grammar.ebnf` documents the lambda / parameter binders accurately** — the `Lambda` / `ParamBinder` productions now admit the `(p : T)` ascription form the parser has accepted since lambda-parameter annotations landed.
- **`awsum format -i` leaves an already-canonical file untouched** — the write is skipped, so mtime is preserved and editors / watchers see no change.
- **`awsum lsp` formatting returns minimal per-hunk text edits** (one `TextEdit` per changed line range, none when already canonical) instead of a whole-document replace — the LSP counterpart to the `awsum format -i` skip above.
- **New `Awsum.Simplify` Core-to-Core pass** (after `Tco`, before `Lifetime`): case-of-known-constructor and case-over-constant collapse, case-of-case fusion via join points, single-arm / identical-arms collapse, single-use binder inlining, non-recursive function inlining with a `let` cleanup family, and integer const-folding over literals. Output unchanged; smaller, faster generated code.
- **Cell reuse now reaches inner cells (nested `CReuse`)** — a `mirror` / `reverse`-style loop rewrites both its argument pack and its data cell in place and allocates nothing on LLVM/WASM. Output unchanged.
- **Smaller, more legible generated code on every backend, output unchanged** — a `case` over a bare variable dispatches in place (no scrutinee-alias copy), JS expression-position case-trees share one arrow, reuse / tail rebinds are scheduled like a parallel copy, and the JVM stops null-storing into unused binder slots.
- **`docs/pipeline.md` matches the memory passes** — `CReuse` as in-place stores (with the LLVM/WASM copy-on-write fallback), JVM `CDrop` slot-nulling at rebinds / returns, and the `Simplify` same-arity carve-out boundary.
- **Test fixtures: per-program runtime inputs renamed `stdin/` → `input/`, the default output golden `no-stdin.txt` → `no-input.txt`** — they are delivered as the program's single CLI argument, not over stdin (218 goldens renamed, content intact).
- **JS renders a single-`return` arrow as an expression body** (`x => e` rather than `(x) => { return e; }`), dropping the parens around a lone parameter. Output unchanged; more legible JS.
- **Dead `case` arms whose tag is never constructed on any reachable path are pruned flow-sensitively** — chiefly the IO combinators' `IO.Args` / `IO.Stdin` arms in programs that import neither, which had dragged the argv / stdin decoders into the output. Output unchanged; smaller code (even hello-world shrinks).
- **A row-widening coercion that is the identity on the runtime representation no longer emits a structural deep-copy helper** — chiefly the `IO Never X → IO (e | Never) X` widening the IO combinators insert. Output unchanged; smaller code. A genuine re-tag (a shared label whose inner row grew) still emits its helper.
- **Lowering consumes a typed AST (`Awsum.TExpr`) from the typechecker** instead of re-inferring types, with a new `Awsum.MonomorphizeRows` pass specialising row-polymorphic combinators before lowering — closing the residual class of row-injection bugs at the source (~1000 lines of re-inference deleted).
- **The surface formatter and the LLVM, WAT, and JS code generators are now built from a typed IR rendered with `prettyprinter`** (matching the JVM/CLR byte backends), instead of hand-rolled string concatenation. Output unchanged — only legibility / indentation improves (the lone `.ll` text change: `phi` operands render `[ %v, %lbl ]`).
- **The CLR target now runs under Server GC** (`"System.GC.Server": true` in the generated `runtimeconfig.json`). Output unchanged; only GC throughput changes.
- **Snapshot test sources normalised to one house style, recorded in `docs/testing.md`** — the `eitherToIO … |> andThenIO IO.Stdout.print |> handleErrorIO onError` shape with behaviour-only doc comments; `just format-fix` now also formats the Awsum test sources and `stdlib/Prelude.aww`.
- **Pattern shapes are validated at nested field positions, not just at the top of a `case`** — a partial catch-all (`Just A | Just _`), an ascription on a non-row field, a constructor on a primitive or polymorphic field, and a constructor naming a different type are now rejected at the offending pattern instead of crashing or miscompiling in lowering.
- **Typechecker / Core cleanup, output unchanged:** the recursive-type set is computed once per `case` (not rebuilt per constructor), the pattern-matrix helpers are deduplicated, and the unused `CDropKind` / `BinderKindMap` drop-classification is removed from the Core `CDrop` node.

### Removed

- **`empty type` may no longer be declared in user code.** The standard library declares the one empty type the language needs — `Never`, the row identity — and a user-declared one was only ever an alias of it. The error points at `Never` (row identity) or a plain `type X` (a distinct uninhabited type).

### Fixed

- **The bundled TextMate grammar no longer mis-highlights an identifier containing an apostrophe.** `\b` word boundaries split a trailing `'`, so `in'` mis-tokenised as the `in` keyword; every identifier and keyword boundary now uses `(?<![\w'])` / `(?![\w'])` lookarounds. The `awsum-vscode` / `awsum-intellij` copies stay byte-identical.
- **A single-inhabited structural sum — `(Never | T)`, including nested in a head (`Maybe (Never | T)`, …) — no longer miscompiles when matched with a used binder.** Such a row is the same type as `T` and flows with no coercion, but some producers tagged it while every consumer read a tag; it is now bare everywhere, matching `unify`. (A `type Void` or `Box Never` stays a genuine tagged label.)
- **A row combinator whose result row carries a concrete error label is no longer accepted into `Either Never` / `IO Never`.** `bindEither op1 (\_n -> pureEither 0)` ascribed `Either Never Int32` typechecked though `op1 : Either ErrA Int32`, dropping the live `Left ErrA` and misdispatching at runtime; a boundary guard now re-checks the threaded result against the expected row.
- **A binding can no longer declare a type more polymorphic than its body — closing a general `unsafeCoerce`.** `val : a` with `val = (42 : Int32)`, used at `String`, fed an `Int32` into a `String`. Each body is now additionally checked against its signature with the signature's type variables replaced by rigid skolems (`SignatureTooPolymorphic`); legitimate polymorphism is untouched and accepted programs compile byte-identically.
- **A `case` on a structural sum with a free-type-variable label (an open row tail, `(Int32 | r)`) is now rejected (`MatchOnOpenRow`) instead of miscompiling.** The caller can inject any type into the tail, which then hit an arm-less dispatch; matching an open row can't be exhaustive without a catch-all, which the language forbids. Building through an open tail (injection) is unchanged.
- **A non-tail recursion whose post-call work returns a multi-constructor type no longer leaks its CPS continuation chain on LLVM/WASM.** When the matched-cell scope held a splitting `case`, only the rebuilding arm reinstated the freeing drop, so the forwarding arm never freed its continuation cell — one leak per step, accumulating across repeats. A sibling arm that doesn't reuse now re-acquires the drop.
- **A type constructor named in a data-constructor field is now resolved against the program's type names, exactly as a signature is** (`UnknownTypeCon`), and a `_`-prefixed one is rejected. Relatedly, a type parameter named `_T` (uppercase) is rejected, since it lexes as a constructor in use position.
- **`check --json`: an undeclared `_`-prefixed constructor in a pattern no longer emits a quick-fix with two overlapping edits** (which strict LSP clients rejected). The diagnostic now carries the declaration span as `Maybe SrcSpan` and offers no fix when the constructor is undeclared.
- **A type constructor is now applied to exactly its declared number of arguments, everywhere a type is written** (`TypeConArityMismatch`). `Maybe Int32 Int32`, `Either Int32`, a bare `Maybe`, `IO Int32` were all previously accepted (and the row-alternative form ran to completion). A type-variable head is still left to unification.
- **A constructor pattern that binds the wrong number of fields is now rejected at every pattern position** (`PatternArityMismatch`), before any binder is created — previously the `zip`-based walks truncated, so surplus binders vanished and a short pattern surfaced as a confusing non-exhaustiveness witness.
- **An empty type (`Never`) named in a type annotation inside a function body now resolves to the row identity, like the same name in a signature** — the `Never`-rewrite now descends into body annotations, fixing a baffling `expected IO Never Unit, got IO Never Unit`.
- **The unifier treats an empty type (`Never`) as the row identity when two rows of different width meet.** `unify (Never | A) A` now succeeds (empties dropped from the width comparison) while `Never ~ (e1 | e2)` still binds both to `Never`. Pinned at the `Awsum.HM` level (not reachable from surface `.aww`).
- **Injecting a value into a structural sum with two same-head alternatives (`(Maybe T | Maybe U)`) no longer routes it to the wrong one.** Check-mode now pushes the pinning substitution into the value, and a genuinely-ambiguous injection with no pin (a bare `Nothing`) is rejected (`AmbiguousRowInjection`) instead of silently taking the first alternative.
- **A `case` over a multi-field constructor no longer accepts an uncovered combination of fields.** Per-column coverage isn't cartesian coverage for ≥2 fields (`Tuple2 A A | Tuple2 B B` left `Tuple2 A B` uncovered, silently falling through); exhaustiveness is now matrix-based (Maranget), reporting one concrete uncovered value.
- **A non-constructor pattern in a `case` on a nominal type now points at the pattern, not at line 1**, and explains that nominal types are matched by constructors while `(x : T)` discriminates a structural sum.
- **`awsum format`: no trailing blank line to stdout** (byte-identical to what `-i` writes), and a run of adjacent top-level comments is grouped into one block instead of wedging a blank line between every line.
- **A nested chain of the same row-polymorphic combinator no longer rejects a well-typed destructuring continuation** — the bidirectional spine now freshens the polymorphic head's instantiated type per call site, so a destructuring step's result is no longer checked against its input type.
- **In-place cell reuse no longer mutates a cell a later sibling still reads** — a `CContinue` re-staging the matched cell beside a same-arity rebuild clobbered it; the gate now blocks the rewrite when any later-evaluated sibling mentions the scrutinee.
- **Cell reuse no longer corrupts a structure the caller retains — `CReuse` carries uniqueness evidence (`ReuseMode`).** Compiler-minted cells (`ReuseUnique`) mutate unconditionally; user-visible data (`ReuseGuarded`) mutates on LLVM/WASM only under an `rc == 1` check with copy-on-write (a plain allocation on the managed backends).
- **LLVM/WASM: an expression-position `case` whose arms return bare variables no longer triggers a use-after-free** — both backends now increment at every expression-position arm tail whose value is a borrow (move-aware, looking through `let`).
- **JVM/CLR/WASM: a `case` in an awkward position no longer crashes the compiler or fails bytecode verification** — a constructor-cell field, a tail-call argument, or a deep scrutinee position now evaluate into save locals first, slot sizing accounts for the scrutinee, frame typing is contextual, and a tail-recursive parameter-swap rebind no longer overflows `max_stack`.
- **A local binder sharing a bare name with a top-level declaration no longer miscompiles.** Naming a `bindIO` continuation `cont` (a name the prelude also binds) made defunctionalisation resolve to the user's top-level and drop the closure's captures; a new lowering pass renames any colliding local before the closure passes run.
- **Over-applying a higher-order function now compiles on every backend instead of crashing the compiler** — `identity applyOnce inc 5` (surplus arguments applied to the result) routes through the closure-apply dispatcher, generalised to also grow an under-applied closure into a larger one at runtime.
- **JS: a NUL byte followed by a decimal digit in a string literal no longer emits invalid JavaScript** — the pair formed a legacy octal escape, a strict-mode `SyntaxError`. NUL (and U+2028 / U+2029) is now emitted as a fixed-length Unicode escape.
- **Widening a structural sum where a shared label's inner row grows now re-tags correctly** (`Maybe Bool` → `Maybe (Bool | Unit)`) — the coercion dispatches on the label and re-tags any whose structure changed; pure widening stays a no-op.
- **Row-combinator error-row tagging hardened across its partial / aliased / named shapes.** A platform-effect `bindIO` with a failing continuation, an alias whose body is a partial application (`greet = const "hi"`), and a row combinator partially applied and bound to a named value with a concrete continuation row — each previously left the continuation's error untagged (a crash or wrong arm) — now recover the concrete row from the surrounding signature and specialise.
- **A row combinator whose continuation is inline, or reached through an argument position or a nested named continuation, now resolves its error row from the surrounding signature** — the injection that previously reached lowering untagged (mis-dispatching on every backend) is now tagged and the call head specialises, independent of the order labels appear in the signature.
- **A lambda that applies a captured function-typed parameter now compiles on every backend** — `poly k = applyOnce (\n -> k n) 5` dropped `k` when `poly` was defunctionalised; a captured function-typed parameter is now resolved to its closure representation and reaches the dispatcher like any other.
- **A partially-concrete output tail widening by two-or-more labels now compiles, and an unannotated `let` over a partial row combinator is rejected with a clear diagnostic** instead of miscompiling — `zeroOr : Int32 -> Either (EZ | e) Int32` used at a wider row now keeps its tag, and `let pb = bindEither oa` is reported with a pointer to the annotation that fixes it.
- **Source layout and `SrcSpan` positions are counted in Unicode code points — one column per character — not display width.** A wide character before a multi-line `let` had shifted the apparent indentation, leaving `awsum format` output unparseable by `tree-sitter-awsum`; a new `Awsum.SrcStream` makes the offside rule and every span count code points (the layout convention of Haskell / Elm). ASCII spans are byte-identical.
- **`awsum lsp` reports positions in UTF-16 code units, as LSP mandates** — `Awsum.Lsp` converts the compiler's code-point columns to UTF-16 at the protocol boundary (and incoming client positions back).
- **`case` arm-merge and row-field-descent lowering bugs fixed** on well-typed programs: a multi-field constructor matched by field combination (a dropped second-field dispatch, or differently-named shared binders), a constructor descending into a row-typed field's label, and a duplicate arm ascribing a field to the same row alternative — previously miscompiled or raised a line-1 internal error — now lower correctly or report the precise diagnostic.
- **A non-regular (nested) recursive type no longer hangs the compiler (and `awsum lsp`).** `type Nest a = NestCons a (Nest (Tuple2 a a)) | NestNil` drove the inhabitedness check into unbounded recursion; its cycle guard now keys on the head type-constructor name, restricted to genuinely recursive constructors.
- **`awsum-bench --snapshot`: the no-simplify differential leg runs under its own wider timeout** (3× the measured one), so a program near the boundary no longer fails the snapshot spuriously while leaving an all-`ok` `bench.txt`.
- **Partial application and point-free aliasing of a compiler built-in now compile on every backend** (`mulInt32 5`, `f = BuiltIn.showInt32`) instead of crashing or silently writing an invalid artifact — both route through the `$bi$`-wrapper / alias-eta path the closure passes already lower.
- **A file with no top-level declarations now parses, matching the grammar** — an empty, imports-only, or module-comment-only file is a valid empty module (`awsum check` and the LSP accept it); the absent entry point surfaces only when `build` / `run` requests one (`Missing 'main' function`).

## [0.0.6] - 2026-06-03

### Added

- **`IO.Stdin.readAllBytes : IO Never (List UInt8)`** — CLI platform built-in that reads stdin to EOF as raw bytes, with no decode and no content-dependent failure (the result carries no error row). The companion to `readAllString` for input that isn't text, or text the host's argv decoder would mangle: stdin bytes reach the program verbatim on every backend. The per-target reader builds the prelude `List UInt8` directly from the captured bytes.
- **`byteToHexStringNoPrefix : UInt8 -> String`** (a per-target built-in) and **`bytesToHexStringNoPrefix : List UInt8 -> Either StringTooLong String`** (pure Awsum — a non-tail fold over `(++)`) in the prelude. Render a byte / byte list as lowercase, zero-padded, no-prefix hexadecimal (`0 → "00"`, `255 → "ff"`); the list form returns `Left StringTooLong` only if the joined result would exceed the string cap.
- **`InvalidUtf8`** type + **`showInvalidUtf8`** in the prelude — the byte-level decode failure `readAllString` reports for stdin bytes that are not well-formed UTF-8. Distinct from `UnpairedUtf16Surrogate` (a UTF-16-level failure of host-decoded argv): neither is a subset of the other.

### Changed

- **`IO.Stdin.readAll` is renamed `IO.Stdin.readAllString` and now decodes stdin as strict UTF-8 (RFC 3629); its error row changes from `(StringTooLong | UnpairedUtf16Surrogate)` to `(StringTooLong | InvalidUtf8)`.** Stdin is a raw byte stream the program owns end to end, so Awsum applies the full UTF-8 validity check itself rather than deferring to a host decoder. Any malformed sequence — overlong encoding, truncated multi-byte sequence, stray continuation byte, surrogate code point encoded in UTF-8, code point above U+10FFFF — is `Left InvalidUtf8`; a well-formed stream decodes to its `String` (`Left StringTooLong` past the 2^27 UTF-16 code-unit cap), and a leading UTF-8 BOM is kept verbatim as the ordinary scalar U+FEFF on every backend rather than silently stripped. `IO.Args.getArgs` is unchanged: argv is pre-decoded by the host, so its only failures remain `StringTooLong` and `UnpairedUtf16Surrogate`.

### Fixed

- **A string literal flowing into a structural sum is now injected (`CRow`), and a value already typed at a narrower row widens into a wider one correctly.** A string literal in a non-argument position whose type is a row — `val : (Int32 | String); val = "hi"`, or in a `let` RHS / `case`-arm / def body — lowered to a bare string (only the integer-literal arm injected), so the row-`case` mis-read it: crash on LLVM/JVM/CLR/WASM, `undefined` on JS. String literals now route through the same injection path the integer arm uses. This also closes the sub-row→wider-row case (`("x" : (String | Int32))` flowing into `(String | Int32 | Bool)`): row tags are per-label (FNV of the label name), so the widening is a pass-through once the leaf is injected — no separate coercion needed.
- **A row-unioning combinator applied to a continuation whose type can't be synthesised now injects the concrete error label.** `bindEither opA (const opB)` / `andThenEither (\_n -> opB) opA` — where the continuation is a partial application or a lambda — left one alternative of the result error row abstract, so the body-specialisation that injects the row tag was skipped and the `Left` payload reached the row-`case` un-tagged (crash on four backends, garbage on JS). The leftover labels are now recovered from the caller's expected result type before the body is re-lowered at concrete types; the argument-derived path the nested-combinator chains rely on is unchanged.
- **The Defunctionalize pass no longer hangs when a named top-level function is passed to a row-specialised combinator.** When the combinator's function-typed slot parameter shared a name with the passed function (e.g. a user `k` into a combinator whose continuation parameter is also `k`), `transformCall` re-resolved the same name through the closure environment forever — the compiler hung at the Core-to-Core stage with no diagnostic (typecheck passed). It now drops the name from the environment and dispatches the call as the top-level function it is.
- **Malformed UTF-8 on stdin now decodes — or is rejected — identically on every backend.** `IO.Stdin.readAll` previously routed stdin through whatever decode each host gave for free: a lenient U+FFFD-replacing decoder on JS / JVM / CLR, a byte-counting pass that copied invalid bytes verbatim on LLVM / WASM. Well-formed input agreed, but a malformed byte sequence diverged — one backend replaced, another truncated, another copied the bad bytes through. The renamed `readAllString` applies one strict decoder per target (hand-rolled RFC-3629 state machines on LLVM / WASM, the platform's fatal UTF-8 decoder on JVM / JS, a re-encode round-trip check on CLR), all pinned to the same well-formed-UTF-8 definition by a property test that compares all five against a Haskell oracle over arbitrary byte sequences.
- **A row-typed list built from literals mixing integer and string elements now compiles.** `Cons 1 (Cons 2 (Cons "x" Nil)) : List (Int32 | String)` was rejected with "integer literal without a known numeric type": `synthLabelType` under-approximated the element type as `String` — bare int literals contribute nothing to the synthesis, so a later string element alone fixed the element variable, and the ints were then lowered against a `String` element type. An argument that can't be synthesised but whose slot reaches the result now fails synthesis, so the declared element type propagates to every element.
- **Non-tail self-recursion under a structural-sum (row) case — or a tail row-injection — now compiles, in bounded stack on every backend.** A non-tail self-call inside a `(n : Int32)` row arm (`addInt32 n (sumRow t)`), or one whose result is injected into a row-typed return, was rejected by the stack-safety verifier (`UnsupportedRecursionShape`) even though the identical fold over a nominal type compiled and ran. `Awsum.Cps.goTail` now descends into `CRowCase` arms and tail `CRow` injections the way it already did for `CCase`/`CCon`, and the WASM tail emitter got the matching `CRowCase` arm. Closes a hole in "stack safety for any recursion shape".
- **An integer literal flowing into a structural sum is now injected (`CRow`) at lowering, closing a silent cross-target divergence.** A literal in a non-argument position whose type is a row — `(0 : Int32)` or bare `0` in an `(Int32 | String)` `case` arm, `let`, or function body — lowered to a bare integer: the typechecker accepted the implicit injection but lowering dropped the row tag, so a row-consumer misread the cell (LLVM/JVM/CLR crash, JS `undefined`). `EAscribe` now re-injects into the ambient row type, and a bare literal resolves against the row's unique int label — matching what argument position already did.
- **JVM methods larger than 32 KB now assemble correctly.** A branch spanning more than 32767 bytes — a large fused mutual-recursion loop's tail back-edge, or a `case` dispatch jumping over a >32 KB arm — had its signed-16-bit offset silently truncated, so the JVM rejected the class at load (`VerifyError`) even though the method was valid and well under the 64 KB ceiling; it ran on the other four backends and crashed only on the JVM. The assembler now widens far branches — `goto` → `goto_w`, conditionals via invert-and-`goto_w` with a synthesized skip frame. Methods under 32 KB are byte-identical to before; other backends are unaffected.
- **A function whose JVM bytecode would exceed the 65535-byte per-method limit (`code_length`, JVM Spec §4.7.3) is now refused at compile time instead of emitted as an invalid `.class`** that the JVM rejected only at load (`ClassFormatError`) — a program that built but crashed on the JVM while running fine on the other four backends. The build now fails with a diagnostic naming the method and its size. This is a per-target compile-time limit; capable backends aren't capped to match (see [docs/targets.md](docs/targets.md#per-target-compile-time-limits)). Reaching it takes a pathologically large single function; ordinary code is nowhere near it.
- **Implicit row injection now fires when a value reaches a wider structural-sum error type through a value-flow boundary, not only at a construction site.** Previously the row tag (`CRow`) was inserted only where a constructor was written directly at the row type (`Left ErrA : Either (String | ErrA) Int32`). A value that arrived already built — a `let`/def-body/`case`-arm variable, or the result of a row-unioning combinator (`bindEither`, `andThenEither`, `bindIO`, `andThenIO`) — kept its narrower representation, which the row-`case` then mis-read: wrong alternative on JS (the constructor tag surfaced as an `Int32`), out-of-bounds access on LLVM/JVM/CLR/WASM. Two parts: (1) an `EVar` used where a row is expected now routes through the existing injection (`let x : Either ErrA Int32 = … in x` at `Either (String | ErrA) Int32`); (2) a fully-applied call that widens an abstract error row `(e1 | e2)` into a concrete multi-alternative row is dispatched to a per-instantiation specialisation of the combinator, whose body is re-lowered at the concrete error types — the polymorphic original cannot inject, because its error types are still type variables when its body is lowered. Covers `Never` collapse, the primitive `String` as an alternative, one- and two-constructor nominal alternatives, idempotent `(e | e) ~ e` collapse, and multi-step chains. Programs that didn't hit the bug are unchanged — output stays identical on every backend.

## [0.0.5] - 2026-05-31

### Added

- **`type List a = Nil | Cons a (List a)`** in the prelude.
- **`headList : List a -> Maybe a`** and **`tailList : List a -> Maybe (List a)`** in the prelude.
- **`nothingAsLeft : e -> Maybe a -> Either e a`** in the prelude — `Just a → Right a`, `Nothing → Left e`.
- **Expression-level type ascription `(e : T)`.** Pins the type of an expression at the use site without a separate `let` or signature. Symmetric to the existing pattern-form `(p : T)`: in both, `: T` asserts "value at this node has type `T`"; in pattern position the form also binds. Useful where bidirectional inference has too little context — `identity (42 : Int32)`, `pureEither (10 : Int32)`. Erased at lowering (no runtime cost; no Core node).
- **Permutation-aware `CReuse` elision + linear binder elision in LLVM codegen.** Extends the existing self-move elision in `CReuse` to cover the case where an arm-binder moves to a different slot of the same cell (e.g. `Cons x xs → CContinue [xs, CReuse "lst" 24 [$k, x]]` in `$cps$clone` — `x` moves from slot 1 to slot 2). For arm-binders whose only use is a `CReuse` field of the same scrut (computed via `Awsum.Lifetime.elidableArmBinders`), codegen now skips: the inc-on-extract at case match, the dec-via-`CDrop` at arm end, the dec-old of the binder's old slot, and the inc-new of its new slot — the store at the new slot still emits (for permutation-move) or is skipped (for self-move). Modest wall improvements (~5-6%) on `CReuse`-heavy benchmarks (`gc_pressure_clone`, `list_reverse_repeat`); WASM not modified in this pass.
- **Reject user-code references to prelude-private names.** The five constructors of `type IO` (`IOPure`, `IOFail`, `IOStdoutPrint`, `IOGetArgs`, `IOStdinReadAll`) and the runtime walker `runIO` now produce a compile error when mentioned in user source — in expression position, in patterns, anywhere. Reason: Awsum has no catch-all on `case`, so each new platform-effect constructor added to `IO` would otherwise be a breaking change for any user program that wrote `case io of …`. The forbidden set is derived from the parsed prelude at compile time (auto-grows when `IO` gains a constructor); the diagnostic is uniform — `Name 'X' is reserved by the standard library and cannot be referenced from user code` — and the check runs before typecheck so violations appear ahead of any cascading "unbound name" errors. Temporary until modules ship, at which point the same names move into a privileged module and the diagnostic migrates to the standard "not exported" path.
- **`IO.Stdin.readAll : IO (StringTooLong | UnpairedUtf16Surrogate) String`** — CLI platform built-in that reads stdin to EOF in the IO chain. POSIX-honest semantics: each call consumes whatever bytes remain on fd 0, so a second call after EOF decodes to `Right ""`. Same error row as `IO.Args.getArgs` — decoding failures (length cap, unpaired UTF-16 surrogate) compose through `handleErrorIO`. Per-backend implementation reads raw bytes (`read(2)` on LLVM, `System.in.read` on JVM, `Console.OpenStandardInput` + `StreamReader` on CLR, WASI `fd_read` on WASM, `fs.readFileSync(0)` on JS) and decodes UTF-8 in the runtime, bypassing host argv decoders.
- **Doc comments.** A `--` line or `{- … -}` block touching the next top-level declaration with no blank line between becomes its docstring — no Haddock-style `-- |` / `{-| -}` prefix. Stacks freely across mixed `--`/`{- -}` chains; a blank line detaches the comment as a free-floating note. Content is markdown. `awsum format` normalises every attached doc to a single `{- … -}` block, preserving the author's line breaks. Reference: [docs/type-system.md](docs/type-system.md#comments-and-docstrings).
- **Hover (`textDocument/hover`) in `awsum lsp`.** Resolves the cursor against user + prelude decls together, so prelude names (`bindEither`, `mulInt32`, …) surface their docs the same as user-defined ones. Triggers on every name reference: top-level decl heads, `EVar` / `ECon` / `EBuiltIn` in expressions, `TyCon` in signatures and ascriptions, `PCon` in patterns. Constructor names that aren't a decl head fall through to the parent `TypeDecl`'s doc — hover on `Just` surfaces `Maybe`'s doc, which is where the constructor is documented. Hover `range` underlines the name itself, not the enclosing form. Markdown content; every LSP client (`awsum-vscode`, `awsum-zed`, `awsum-intellij`, `awsum-nvim`, `awsum-emacs`) picks it up with no client-side change.
- **Type information in hover.** The popup now ships the cursor's type alongside the doc — a fenced ` ```awsum ` code block on top, the doc below. Adds hover on /local binders/ that previously had nothing to show: function and lambda parameters, `case`-arm pattern variables, `do`-bind / `do`-let / `let`-bind names. Polymorphic references display both the declared scheme and the call-site-instantiated form, separated by an `Instantiated here:` line — e.g. `bindEither` inside `bindEither op1 (const op2)` shows `Either e1 a -> (a -> Either e2 b) -> Either (e1 | e2) b` alongside `Either ErrA Int32 -> (Int32 -> Either ErrB Int32) -> Either (ErrA | ErrB) Int32`. Monomorphic refs and locals show one block.
- **Balanced nested `{- … -}` capture.** The comment-capture path now balances nested block comments to match the space consumer; `{- {- -} -}` is one comment, not garbage from an early `-}`. An unterminated block at EOF fails with an explicit "unterminated block comment" diagnostic instead of an opaque parse error several lines below the cause.
- **`eqString : String -> String -> Bool`** in the prelude — equality on UTF-16 code-unit sequences.

### Changed

- **JS / JVM / CLR codegen: no redundant slot-null before a rebound loop parameter.** In a TCO'd self-tail-call (`CContinue`), a parameter whose old value is dropped and that the same continue immediately rebinds used to emit a slot null-out (`x = null` on JS, `aconst_null; astore` on JVM, `ldnull; starg` on CLR) right before the rebinding store. The store itself drops the old reference and nothing allocates between the two writes, so the null gained the GC nothing — it is now omitted on the three managed backends whenever the dropped parameter is rebound in that same continue. Drops on binders the continue does not rebind, and every drop at a value-producing tail, still null the slot; LLVM/WASM are untouched (their drop is a real free). No behaviour change — output stays identical on every backend.
- **JVM, CLR, and WASM codegen: text and binary output now share one instruction-IR.** Each of these backends used to lower Core to its target twice — once for the readable dump (`.j` / `.il` / `.wat`) and once for the shipped binary (`.class` / `.dll` / `.wasm`) — two independent passes that could silently disagree. Each now lowers Core once into a per-backend abstract instruction IR (`JvmInstr` / `CilInstr` / `WasmInstr`) whose operands are _symbolic_ — names and labels, never constant-pool indices, metadata tokens, or byte offsets — and the text renderer and the binary assembler are both total, decision-free projections of that single value; the assembler alone resolves the symbolic operands into concrete indices, tokens, branch offsets, and stack maps. So the text shown by `awsum asm` is a faithful view of the bytes that actually run, and the two cannot drift apart. Generated programs are unchanged — output stays identical on all five backends.
- **WASM codegen emits only the runtime helpers the program reaches.** The `.wasm` binary (and the `awsum asm -t wasm` dump) previously carried all ~42 runtime helpers at fixed indices regardless of use. They are now gated to the set reachable from the program — user code plus `_start`, closed over helper-to-helper calls — with every function index derived from that gated list. The user-code emitter calls helpers by name rather than by hardcoded index, so the gated text and the gated bytes resolve through one shared name→index map and cannot disagree on which helpers exist. No behaviour change — output stays identical on every backend; the `.wasm` is just smaller (a hello-world drops from 42 helpers to the handful it actually touches).
- **LLVM codegen emits only the runtime preamble the program uses.** External `declare`s and global constants that were previously always present are now gated next to their sole readers: `@snprintf` / `@.fmt_i32` / `@.fmt_u8` on the integer-`show` helpers, and `@strlen` / `@__free` / `@.cli_argc` / `@.cli_argv` — plus, on Windows, the whole argv-construction block (`GetCommandLineW` / `CommandLineToArgvW` / `WideCharToMultiByte` + `@.empty`) — on `IO.Args.getArgs`. `declare @printf` is dropped entirely (it had no call site). `_setmode` and the `v_main`/`runIO` handoff stay unconditional, as do `@__alloc` / `@__inc_ref` / `@__free_recursive` / `@memcpy`. No behaviour change — generated programs produce identical output on every backend; only dead preamble is removed (≈10.6k fewer lines across the snapshot `.ll` set).
- **`IO.Args.getArgs : IO (StringTooLong | UnpairedUtf16Surrogate) (List String)`.** Was `IO _ String` (a single argv[1]); now returns every command-line argument as a prelude `List String`. All-or-nothing error semantics: if any element fails to decode, the call returns `Left`. All five backends walk argv in full and agree element-for-element, including the empty-argv case (`Right Nil`) — LLVM stashes `argc`/`argv` at entry (converting the wide command line to UTF-8 on Windows) and WASM reads WASI `args_get` directly, both looping from `argc-1` down to 1.
- **`awsum run` argv via POSIX `--` separator; stdin inherits from the parent.** Was two mutually-exclusive flags — `--input TEXT` (singleton argv) and `--stdin` (read `awsum`'s own stdin, `T.stripEnd`, forward as `argv[1]`); both are gone. Now everything after `--` is forwarded as command-line arguments and read with `IO.Args.getArgs` as `List String` (no `--` → `Right Nil`); the child inherits `fd 0` directly, so `echo "data" | awsum run … FILE` and `awsum run … FILE < file` reach `IO.Stdin.readAll` verbatim (no buffering, no `T.stripEnd`, byte-exact across all five backends). The two channels are independent and can be used together: `echo "data" | awsum run … FILE -- arg1 arg2` delivers `["arg1", "arg2"]` to `getArgs` and `"data\n"` on stdin simultaneously.
- **Comments and layout no longer affect `awsum build` output or `awsum check` diagnostic text.** Synthetic binder names (`$do_e_N`, `$arg_N`, `$let_w_N`) are minted from a monotonic counter, and type-error messages show `expected x` rather than `expected x$3_12`.
- **Module comment header for `.aww` files.** A single optional `{- … -}` block at the top of a file is now treated as the module comment. Line comments (`-- …`) at the top of a file and multiple block comments in a row are rejected with a parse error: the language never silently attaches text above the first import or declaration. Concrete shapes:
  - **Before** — `{- header -}` glued directly to `import IO.Stdout` on the next line, or `-- header …` (often multi-line) before `import` / a top-level decl.
  - **After** — a single `{- header -}` block, then `import …` or the first declaration. The canonical form has one blank line between the header and the next line; the parser accepts both with and without the blank line, and `awsum format` normalises to the form with one. Other shapes (`-- header`, two `{- a -} {- b -}` in a row) are syntax errors.

  Leading comments on the first import are no longer accepted — they were ambiguous with module-comment material; subsequent imports may still carry leading comments (the "`-- import IO.X`" commented-out-import pattern between live imports). AST: `Program` gains a `moduleComment :: Maybe Text` field.

### Deprecated

### Removed

- **`awsum run --stdin` and `awsum run --input TEXT`** — superseded by stdin inheritance and the POSIX `--` separator (see Changed above). Migration: `echo … | awsum run … --stdin FILE` becomes `echo … | awsum run … FILE`; `awsum run … --stdin FILE < input.txt` becomes `awsum run … FILE < input.txt`; `awsum run --input "arg" … FILE` becomes `awsum run … FILE -- "arg"` — and multiple positional args after `--` are now possible (`-- arg1 arg2 …` → `List String`).

### Fixed

- **JVM verifier rejected a `CCase` in `CCall` argument position.** Two issues: branch-target offsets weren't shifted by the byte length of preceding sub-metas (StackMapTable frames landed before the actual targets), and the case declared an empty operand stack at its `if_icmpne` while the prior args still sat there. `CCall` now routes args through fresh locals when any arg contains a case, with the reserved save slots declared as `top` in the case's frame. Surface trigger: a `let` whose RHS is a `do`-block. LLVM/CLR/WASM/JS unaffected.
- **Top-level definition whose body is a bare lambda.** `f : Int32 -> Int32; f = \n -> n` (and curried / multi-param variants) used to be accepted by the typechecker but rejected at lowering with an internal `lambda has no expected type at lowering` error — the elaborator's zero-LHS path passed `Nothing` as the expected type, so `liftLambda` had no arrow to split. The elaborator now eta-contracts a top-level `ELam`-body into the `FunDef`'s LHS before lowering: `f = \n -> n` produces the same Core as `f n = n` (one `CFunDef`, no `$lam$N` helper). Curried forms (`\a -> \b -> body`) peel recursively. A non-lambda body that contains a nested `ELam` deeper down (e.g. in a `case` arm) now also receives the signature type as expected, so it goes through `liftLambda` correctly instead of dead-ending.
- **`UnusedTopLevel` false negative for short top-level names.** `freeNames` failed to subtract pattern-bound names from each `case`-alternative body, and the call-graph construction failed to subtract a top-level definition's own parameters. The combination silently masked any user-level top-level whose name happened to match a single-letter binder used inside a prelude case-alt (`Right a -> k a`, `Left e -> Left e`, …) or a prelude parameter (`(++) a b = …`). Both leaks are fixed; one-letter unused top-levels now warn correctly.
- **LLVM and WASM heap leak on every reference to a top-level `CValDef`.** The codegens were treating `CVar` references to top-level value definitions (e.g. `zero : Int32; zero = 0`) the same as borrowed-local CVars — emitting `__inc_ref` over the result. But each such reference lowers to `call @v_name()` which already allocates a fresh `+1` cell. The spurious inc left every referenced cell at refcount `1` forever, leaking once per reference in a hot loop. With the fix, peak RSS on `unused_case_binder_repeat` drops from 155 MiB to 2 MiB; on `mutual_three_way_repeat` from 1.5 GiB to 1.6 MiB. JVM/CLR/JS unaffected (host GC).
- **String property tests on Windows × JVM.** The 5 string-touching properties (`concat-left-identity`, `concat-right-identity`, `concat-associative`, `lengths-three-functions`, `concat-length-additive`) previously diverged on Windows × JVM because the JVM startup decoder (`sun.jnu.encoding`) mangled supplementary-plane characters in `argv[1]` before they reached user code. Property tests now feed input via `IO.Stdin.readAll`; stdin bypasses the startup decoder, so the round-trip is byte-clean on every host. The cross-backend assertion runs on every cell now — the Known Issue from 0.0.4 is closed.
- **LLVM Windows × MSVC CRT `\n` → `\r\n` translation on stdout.** The MSVC CRT opens fd 0/1/2 in text mode by default, so `write(1, …)` calls (used by the LLVM backend's `__print` runtime helper) silently doubled every `\n` into `\r\n` on output — breaking the cross-target "identical stdout" invariant. Latent since the LLVM Windows footer was added; only surfaced now that `IO.Stdin.readAll` lets `\n`-bearing input reach the program (`CommandLineToArgvW` had been stripping the same byte from argv). The Windows entry point now calls `_setmode(1, _O_BINARY)` and `_setmode(0, _O_BINARY)` before any IO, forcing stdin and stdout into binary mode regardless of CRT defaults. No effect on the POSIX footer (the call is Windows-only).
- **JVM/CLR binary assemblers emitted `__entryArgEither` unconditionally.** The text codegens (`Awsum.Codegen.{JVM,CLR}`) gate the `__entryArgEither` helper on `IO.Args.getArgs` ∨ `IO.Stdin.readAll`, but the binary assemblers (`JVM/Assemble.hs`, `CLR/Assemble.hs`) always emitted the method — so the `.class` / `.dll` carried a method the `.j` / `.il` snapshot omitted (its only callers, `__getArgs` / `__stdinReadAll`, are themselves gated; `Main` never calls it). The binary assemblers now gate it on the same predicate. On CLR the gate is applied in lockstep to both the method table and `allNames` (which assigns `MethodDef` tokens), so user/`Main` tokens stay aligned. No behaviour change — the method was dead when absent; runtime output is identical on every backend, and the text snapshots are unchanged.

### Security

## [0.0.4] - 2026-05-12

### Added

- **Heap reclamation on LLVM and WASM** via compiler-emitted reference counting; JVM/CLR/JS continue to rely on managed GC. Cross-backend stdout stays identical.
- **`awsum lsp --stdio`** — Language Server Protocol over stdio: document sync, `publishDiagnostics`, `codeAction`, `formatting`, `documentSymbol`, `workspace/symbol`. Opt-in lockstep version check via `initializationOptions`.
- **`andThenEither` / `andThenIO`** in prelude — flipped-argument forms of `bindEither` / `bindIO` for `|>` chains.
- **`handleErrorIO : (e1 -> IO e2 a) -> IO e1 a -> IO e2 a`** — function-first sibling of `mapIOError`. `e2` may be `Never`, a partial row, or a renamed row.
- **`failIO : e -> IO e a`** — error-side mirror of `pureIO`.
- **`empty type X` declaration form.** Uninhabited types whose row tag collapses to `_empty`, so any `empty type` value flows into any row position without a wrapper. The prelude's `Never` is now `empty type Never`.
- **`type BrokenPipe = BrokenPipe`** in prelude — placeholder for the eventual `IO.Stdout.print : String -> IO BrokenPipe Unit` signature.
- **`|>` left-pipe operator** — `x |> f` is syntax for `f x`. Left-associative, lowest precedence (`++` binds tighter). Not a referenceable name; the parser rejects `(|>)`.
- **Thousands separator `_` in decimal integer literals** — `1_234_567`, `-1_000_000`. Forbidden positions: leading, trailing, two consecutive, immediately after the sign. The formatter canonicalises every literal to groups of 3 from the right.
- **Type `UInt32`** — unsigned 32-bit integer with literal range validation. Built-ins `showUInt32`, `predUInt32`, `succUInt32`, `eqUInt32`, `addUInt32`, `subUInt32`, `mulUInt32`, `parseUInt32`; prelude `minUInt32`, `maxUInt32`. Honest arithmetic returning `Either OverflowError UInt32` (add/mul/succ) and `Either UnderflowError UInt32` (sub/pred).
- **`(++) : String -> String -> Either StringTooLong String`** — concatenation reports overflow through an error channel instead of silently truncating. New sentinel types in prelude: `StringTooLong`, `UnpairedUtf16Surrogate`.
- **`maxStringLengthUtf16CodeUnits : UInt32`** in prelude — `2^27 = 134_217_728`, the language-fixed maximum string length, identical on every backend.
- **Compile-time string-literal length check** — literals exceeding `maxStringLengthUtf16CodeUnits` are rejected with `StringLiteralTooLong`.
- **Closures in constructor fields, case-arm-binders, and partial applications now compile** on every backend.
- **`IO.Args.getArgs : IO (StringTooLong | UnpairedUtf16Surrogate) String`** — CLI platform built-in that reads the command-line argument from inside the IO chain. Decoding failures (length cap, unpaired UTF-16 surrogate) live in the IO error row and compose with `handleErrorIO`.
- **`awsum-bench` executable + `just benchmark TEST [TIMEOUT]` recipe.** Drives a single program through every backend and prints wall-clock time, peak RSS, exit status, and trimmed stdout. Default timeout 60s. macOS-only at the moment.
- **`awsum-stats` / `just stat-linearity` recipe** — counts how many times each locally-introduced binder is referenced inside its scope; per-program snapshot.

### Changed

- **`main` signature is `IO Never Unit`** (no parameter). Programs read the entry-point argument via `IO.Args.getArgs`.
- **`IO` is now `IO e a`** — gains an explicit error-row parameter, mirroring `Either e a`.
- **Lazy IO.** `IO e a` is now a sum type in the prelude; `IO.Stdout.print "x"` builds a description, not a side effect. Only the IO returned from `main` runs.
- **`bindIO` / `pureIO` / `mapIO` / `mapIOError`** in prelude — IO compositors mirroring `Either`.
- **`IOUnit` renamed to `IO Unit`** (`IO` is now a unary type constructor).
- **`type Never`** in prelude — empty type, no constructors.
- **Signed `Int32` arithmetic** returns `Either (UnderflowError | OverflowError) Int32`; nominal `ArithError` removed.
- **Prelude additions** — `Tuple2`, `Tuple3`, `parseInt32`, `parseUInt8`, `splitOnFirst`, `addInt32`, `addUInt8`, `subInt32`, `subUInt8`, `negInt32`, `mulInt32`, `mulUInt8`, range constants `minInt32` / `maxInt32` / `minUInt8` / `maxUInt8`; new types `ParseError`, `UnderflowError`, `OverflowError`.
- **Three explicit string-length functions** — `lengthCodePoints`, `lengthUtf16CodeUnits`, `lengthUtf8Bytes`, all `String -> UInt32`. No `length` alias.
- **LLVM and WASM strings are length-prefixed** — `lengthUtf8Bytes` and `lengthUtf16CodeUnits` are O(1); strings with embedded NUL no longer truncate output.
- **Structural sums `T1 | T2`** — closed anonymous unions; `(x : T)` ascription patterns for discrimination, exhaustive without catch-all; mixed ascription + constructor arms in one `case`; implicit injection through nominal heads.
- **Closures over outer parameters** — lambdas may reference any enclosing-scope binding.
- **Synthesis form for closed lambdas** — `let id = \x -> x in body` and `(\x -> x) 5` typecheck without annotation. Top-level definitions still require signatures.
- **Lambda syntax `\x -> body`** as a surface form.
- **Hindley-Milner type inference** — two-way unification, occurs check, expected types push down through `case` arms and constructor applications.
- **`do`-notation** for `Either` chains, desugared to nested `case`.
- **`let` bindings** (standalone and in `do`); RHS evaluated once. Optional `let n : T = e` ascription. Haskell-style multi-line layout in the formatter.
- **Destructuring patterns** on `<-`, `let` LHS, function/lambda parameters; refutable patterns raise `NonExhaustiveCase`.
- **Recursive exhaustiveness** in nested patterns.
- **Eta-reduced top-level definitions** — `f = g` works for any RHS whose type matches the signature.
- **Cross-module shadow scoping** — same-module shadowing remains an error; cross-module is allowed.
- **Multi-line ADT declarations in `awsum format`** — three or more constructors render across multiple lines; one or two stay on the header line.
- **Multi-line `|>` chains** — chains of two or more `|>` operators format with each operator leading its continuation line.
- **Property-based tests across all backends** (`just test-property`) covering integer arithmetic, succ/pred boundary, equality, parse/show round-trip, string monoid laws, `splitOnFirst`, boolean laws.
- **Symbol visibility tightened** — every backend exposes only the platform-mandated entry point externally.
- **`RowCatchAllPattern` diagnostic** points at the `_` itself, not the surrounding `case` arm.
- **JVM target floor: Java 11 (LTS)** — emitted class file version bumped from 51.0 to 55.0. CI's pinned JDK is now Zulu 11.

### Removed

- **Lua backend** — supported targets are now LLVM/JVM/CLR/WASM/JS.

### Fixed

- **Built-ins passed as function values now compile and run** on every backend — `bindIO io IO.Stdout.print`, `apply showInt32 42`, `let f = showInt32 in f 42` previously crashed at runtime.
- **In-place reuse distributes through nested case scrutinees** — typical merged recursion no longer allocates a fresh constructor cell every iteration.
- **Multi-non-tail-call recursion (`mirror`-style, `sumTree`-style) compiles stack-safely** on every backend.
- **Row-tag dispatch on case-binders** whose source type can't be synthesised — e.g. `(UnderflowError | StringTooLong)` previously always dispatched as the first label.
- **LLVM `argv[1]` on Windows** now reaches `main` as UTF-8 instead of an ANSI-code-page-mangled string.
- **Non-ASCII string literals** compile correctly on LLVM, JVM, and WASM (previously failed `clang` / `ClassFormatError` / overlapping data sections).
- **JVM** — multiple codegen bugs around deeply nested constructors, row tags > 2¹⁵, slot indices ≥ 256, stackmap frames, and `case`-arm tag slots.
- **CLR** — `InvalidProgramException` on deeply nested constructors.
- **`mergeAlts`** for nominal-headed scrutinees with row-typed fields.
- **Implicit row-injection on call results** — a call returning a sub-row into a wider-row slot is now wrapped correctly; previously crashed JVM dispatch.
- **Bidirectional check** propagates through polymorphic application.
- **`do` / `let` / `in`** reserved at the parser level.
- **Free type variables** in constructor fields are rejected.
- **WASM `__alloc`** traps via `unreachable` when `memory.grow` returns -1; previously hung the program retrying forever.
- **Nested-pattern exhaustiveness** — uninhabited siblings inside a nested pattern were reported as missing.
- **`UnusedTopLevel` false positive** — helpers used solely from a `_name` def aren't flagged as unused.

### Known Issues

- **String properties on Windows (JVM)** — `concat-left-identity`, `concat-right-identity`, `concat-associative`, `lengths-three-functions` diverge from LLVM / CLR / WASM / JS for the JVM backend on Windows. The four unaffected backends keep providing signal.

### Tooling

- **Build provenance** — Sigstore attestations on every release asset.
- **`CONTRIBUTING.md`** — dev-loop commands, signed-commits requirement, PR/CHANGELOG conventions.
- **Second Windows CI axis** — `windows-x86_64-mingw` job runs the suites against a [WinLibs](https://winlibs.com) GCC 14.2.0 + LLVM 19.1.7 + mingw-w64 + UCRT bundle, alongside the existing MSVC LLVM 15.0.7. CI-only; release artifacts continue to ship from the MSVC build.
- **`AWSUM_CLANG`** — optional env var that pins the clang executable path used by `awsum run -t llvm` and the test harness. Empty/unset falls back to PATH.
- **Clang compile-failure messages now include stdout** in addition to stderr, with the exit code.

## [0.0.3] - 2026-04-25

### Added

- **Prelude** — `showUnit : Unit -> String` (returns the literal `"Unit"`). The `Unit` type was already prelude-visible; this fills in the missing stringifier so every prelude type now has a matching `show*`.

- **Tag-driven release workflow** — pushing a `v*` tag triggers `release.yml`, which reuses `check-and-build.yml` (new opt-in `upload-artifacts` input) to produce binaries for all four host platforms, packages them as `awsum-<version>-<target>.tar.gz` (Unix) / `awsum-<version>-<target>.zip` (Windows) plus a `SHA256SUMS` file, and publishes them as a GitHub Release pinned to the tagged commit. Asset names embed the version because the website always links to a specific release — the GitHub `latest/download/` redirect is deliberately not used. No `workflow_dispatch` — the tag is the only source of truth.

- **Cross-platform CI** — `check-and-build.yml` now runs on four OS / architecture combinations (was Linux x86_64 only): `ubuntu-24.04` (x86_64), `ubuntu-24.04-arm` (aarch64), `macos-15` (Apple Silicon), `windows-2025` (x86_64). `fail-fast: false`, per-arch cache keys, `STACK_ROOT` pinned to a workspace-relative path so caching works identically on every OS, runner OS versions pinned (no `*-latest`).

- **Toolchain versions pinned to the documented floor on every runner** — LLVM 15.0.7 (apt `clang-15` + `/usr/local/bin` symlink on Linux, `brew install llvm@15` with PATH prepend on macOS, official LLVM Windows installer silent-extracted into a pristine directory on Windows; verify-step fails CI loudly if `clang --version` doesn't report 15.x), Java 8 Zulu (lowest JDK installable on macOS ARM64 via `actions/setup-java`), Lua 5.1.5 (LuaBinaries direct download on Windows, `leafo/gh-actions-lua` elsewhere), Stack 3.9.1 (manual upgrades). On Windows the test harness's `clang` is routed via a project-root symlink to LLVM 15 — Stack would otherwise prepend GHC's bundled mingw clang (LLVM 14-era) to the child process PATH and shadow the install.

- **Supported host platforms documented in README** — a new table next to **Targets** lists OS / architecture / platform identifier / GitHub runner. Platform identifiers (`linux-x86_64-gnu`, `linux-aarch64-gnu`, `macos-aarch64`, `windows-x86_64`) double as the suffix in future release-asset filenames; Linux keeps `-gnu` to leave room for a future `-musl` build alongside, macOS / Windows have a single ABI per OS in our build pipeline so no suffix is needed.

- **`.gitattributes` forces LF on all text files** — Windows checkouts with default `core.autocrlf=true` were silently turning `.aww` sources, `stdlib/Prelude.aww` (embedded into the binary via `file-embed` at compile time), and `.snapshots/**` golden files into CRLF. That broke the parser's column tracker (Megaparsec counts `\r` as a column increment) and the identical-text golden-snapshot matcher. Single rule `* text=auto eol=lf` covers every text extension uniformly.

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
  - Cross-backend equivalence is a compiler invariant: every successful test asserts identical stdout across LLVM, JVM, CLR, WASM, JS, and Lua.

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
