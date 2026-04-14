# Roadmap

Design notes and future directions for the Awsum compiler.

## Language

- Numbers and `Either`-based arithmetic with equivalent semantics across targets
- ~~Algebraic data types and pattern matching~~ ✓ (sum types + exhaustive `case`/`of`)
- Let-bindings and where-clauses
- Platform-aware effects: compile-time gating of `Terminal`, `DOM`, `Window`, `Ports`
- Application formats: CLI, browser, library

## AI Tooling

- MCP server exposing compiler intelligence to AI agents:
  - `awsum/typecheck` — typecheck a snippet without writing to disk
  - `awsum/typeof` — get the type of an expression or definition by name
  - `awsum/completions` — list valid completions at a given position
  - `awsum/signature` — look up a function signature by name
  - ~~`awsum/errors` — structured errors as JSON with source spans~~ ✓ (`awsum check --json`)
  - `awsum/available-effects` — list effects available for a given target
  - `awsum/project-index` — all definitions with types, without function bodies
- Grammar-constrained generation via EBNF for syntactically valid AI output

## Platform Version Policy

Awsum targets **the latest LTS versions of server and browser platforms**, and **the oldest manufacturer-supported versions of mobile platforms**.

The reasoning:

- **Server and browser platforms** (Node.js, JVM, .NET, Lua runtimes, browsers) are environments where end users can update software without replacing hardware. We target the latest LTS release — not bleeding edge, not legacy. There is no reason to support an outdated server runtime when updating is a configuration change.

- **Mobile platforms** (iOS, Android) are environments where the hardware manufacturer controls OS updates. A person with a 4-year-old phone may be stuck on the OS version it shipped with. Programs written in Awsum are built by companies whose customers are regular people, not developers — they have every right to use older devices for as long as those devices work. We target the oldest OS version still supported by the manufacturer.

The exact criteria for selecting minimum mobile OS versions are yet to be defined. The principle is clear: don't punish end users for not buying new hardware.

### Current targets

| Target     | Minimum version | Rationale                     |
| ---------- | --------------- | ----------------------------- |
| Node.js    | 22 (LTS)        | Latest LTS                    |
| Lua        | 5.1             | Oldest widely deployed        |
| LLVM/Clang | 15              | Opaque pointer support        |
| JVM        | 7               | CONSTANT_MethodHandle support |
| WASM/WASI  | wasmtime        | WASI preview 1                |
| .NET       | 9.0             | Latest LTS-adjacent release   |

## Mobile Targets: Platform Effects as Separate Targets

Mobile platforms (iOS, Android) should be treated as **separate compilation targets with separate effect namespaces**, not as one abstract "mobile" target with two implementations.

```
IOS.GetPhoto     -- compiles only under iOS target
Android.GetPhoto -- compiles only under Android target
```

### Rationale

1. **iOS and Android APIs diverge over time.** A unified abstraction (like React Native's `Platform.select`) pushes platform differences into runtime checks. Awsum should catch these at compile time, consistent with the existing effect model (`Window` unavailable in CLI target).

2. **Forces good architecture.** Shared business logic lives in pure functions (no platform effects, compiles to any target). Platform-specific UI/integration code is isolated per target. The type checker enforces this separation — not convention, not linting.

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
