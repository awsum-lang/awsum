# Roadmap

Design notes and future directions for the Awsum compiler.

## General directions

- More numeric types: `Int64`, `BigInt`, `Decimal`
- Type classes, monads, and `do`-notation.
- Modules and multi-file programs.
- Incremental recompilation.
- AI tooling: MCP server, grammar-constrained generation.
- Platform effects beyond CLI: browser, library.
- Mobile targets: iOS, Android.

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
