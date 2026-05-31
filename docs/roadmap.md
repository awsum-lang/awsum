# Roadmap

Design notes and future directions for the Awsum compiler.

## Development Tracks

### Soundness Track

#### S1. Compiler fuzzing

A generator of well-typed Awsum programs that compiles each across all five backends and checks for output divergence, surfacing cross-target equivalence bugs the fixed test corpus cannot reach.

#### S2. Effects expressed in the type system

A granular effect system that replaces the single catch-all IO type: every effect a function performs is named in its type, rather than collapsed into one IO.

#### S3. Type classes

Type classes, with do-notation generalised beyond its current hard-coding to Either.

#### S4. Concurrency and parallelism

Primitives for concurrent and parallel execution, exposed through the effect system.

#### S5. Specification, accessibility, trustworthy delivery, and 1.0 release

Language reference specification (machine-checkable EBNF grammar and semantic specification, published under CC-BY-4.0); WCAG 2.2 AA accessibility audit and remediation across the five editor integrations; a trustworthy delivery pipeline (SLSA provenance, Sigstore signing, reproducible builds, SBOMs); and the coordinated Awsum 1.0 release.

### Practicality Track

#### P1. AI tooling

An MCP server exposing the compiler's typecheck, build, diagnostics, and symbol queries to AI assistants — the same capabilities the LSP server already serves to editors; and a set of packaged agent skills — instructions plus worked examples that teach an assistant the language's idioms — so an assistant writes idiomatic Awsum instead of rediscovering the rules from compile errors.

#### P2. Module system and project tooling

Modules; private and public declarations, with a mechanism for testing private declarations; partial incremental compilation (compilation stays whole-program, but intermediate results are cached so unchanged inputs are not recompiled); multiple source directories; a project configuration file; and dependencies fetched from arbitrary git repositories with integrity pinned to the commit hash.

#### P3. Test and benchmark tooling

A test runner (unit testing, property-based testing, effect testing and integration testing); and awsum benchmark, reporting compile time and program run time as separate measurements.

#### P4. Numeric types and collections.

Remaining operations on the existing Int32 / UInt8 / UInt32; unbounded integers; exact unbounded rationals; literal syntax for sequence collections; Set (unbounded) and Map (both a bounded Int-keyed form and an unbounded form).

#### P5. Networking

TCP connections and an HTTP server, exposed as platform effects gated to the appropriate program type.

#### P6. Browser-application program type

A browser-application program type modelled on The Elm Architecture, with Elm-style ports for typed interop with JavaScript.

#### P7. Mobile targets

iOS and Android as separate compilation targets with separate effect namespaces (`IOS.*` / `Android.*`), gated at compile time — Android via the existing JVM target (Kotlin/Java interop), iOS via the existing LLVM target (Swift interop over the C ABI). Detailed below.

## Mobile Targets: Platform Effects as Separate Targets

Mobile platforms (iOS, Android) should be treated as **separate compilation targets with separate effect namespaces**, not as one abstract "mobile" target with two implementations.

```
IOS.GetPhoto     -- compiles only under iOS target
Android.GetPhoto -- compiles only under Android target
```

### Rationale

1. **iOS and Android APIs diverge over time.** A unified abstraction (like React Native's `Platform.select`) pushes platform differences into runtime checks. Awsum should catch these at compile time, consistent with the existing effect model (`Window` unavailable in CLI target).

2. **Forces good architecture.** Shared business logic lives in pure functions (no platform effects, compiles to any target). Platform-specific UI/integration code is isolated per target. The type checker enforces the separation — not convention, not linting.

3. **Avoids maintaining a lowest-common-denominator abstraction.** Two platforms requesting "a photo" return different result types, have different permission models, and follow different lifecycle rules. Pretending they're the same creates leaky abstractions.

### Practical implications

- **Android** is covered by the existing JVM target (Kotlin/Java interop is natural).
- **iOS** is covered by the existing LLVM target (Swift interop via C ABI).
- **No need for a Dart/Flutter target.** Flutter's value proposition is "one codebase, both platforms" — the opposite of what Awsum enforces. Dart adds no new habitat that JVM + LLVM don't already cover.

### Code structure this enables

```
src/
  Core.aww          -- pure functions, compiles to any target
  ios/App.aww        -- uses IOS.* effects, iOS target only
  android/App.aww    -- uses Android.* effects, Android target only
```

The compiler rejects `IOS.GetPhoto` in an Android build and `Android.GetPhoto` in an iOS build — at type-checking time, not runtime.
