# Principles

The decisions behind Awsum's design, grouped by what the language guarantees vs how the compiler resolves trade-offs when those guarantees push against each other.

## What the language guarantees

1. **Identical results on every target.** The same program produces the same stdout whether compiled for LLVM, JVM, CLR, WASM, or JS — identical, verified by the test suite on every commit. A compiler invariant, not a best-effort goal; the rest of the design hangs off it.

2. **Stack safety belongs to the compiler, not the user.** Recursion — tail, non-tail, self, mutual — is normalised at Core level into a shape that runs in bounded stack on every backend, including JVM and JS where native cross-method tail calls do not exist. No manual CPS transforms, no `tailRecM`, no hand-unrolling. Write the recursion that expresses the algorithm; the compiler makes sure it doesn't fall over. See [recursion.md](recursion.md).

3. **Effects are platform-aware, and effects are values.** The compiler tracks which effects each target supports — a program using `Terminal` won't compile for a browser target; a program using `Window` won't compile for CLI. "Not supported" is a compile error, never a runtime surprise. Effects compose through `IO e a`: an `IO` value is **data** describing the effect, never a side effect performed during construction. Only the `IO` returned from `main` is run, by a small per-target runtime walker. The error row `e` is honest — failure modes appear in the type, not in invisible exceptions.

4. **Errors are values.** Arithmetic doesn't silently break. Division by zero, overflow, underflow, precision loss — all represented in the type system via `Either`. Effects too: `IO e a` carries its failure type explicitly through the same row mechanism. The programmer decides how to handle them; the compiler cannot "just return zero" or `NaN`.

5. **No invisible decisions.** When something has to be chosen, the programmer chooses — not the compiler. No defaulting of integer literals to a type the compiler guessed (ambiguity is rejected with an explicit hint); no silent shadowing of an outer name by an inner one (shadowing is a compile error); no quiet reference to something the programmer marked as unused (`_`-prefixed bindings cannot be read). The rules are small; the shared root is that nothing meaningful is decided behind the reader's back.

## How the compiler resolves trade-offs

When two of the language guarantees push in different directions, the compiler picks in this order:

1. **Correctness** — no runtime exceptions, no platform-behaviour differences, no surprising overflow / underflow / string corruption.
2. **Runtime performance** — generated programs should be fast.
3. **Compilation speed** — the compiler itself can be slower if it produces better output.
4. **Syntactic convenience** — the source can be more verbose if that's what it takes to keep the guarantees above visible.
