# Platform Version Policy

Awsum targets **the latest LTS versions of server and browser platforms**, and **the oldest manufacturer-supported versions of mobile platforms**.

The reasoning:

- **Server and browser platforms** (Node.js, JVM, .NET runtimes, browsers) are environments where end users can update software without replacing hardware. We target the latest LTS release — not bleeding edge, not legacy. There is no reason to support an outdated server runtime when updating is a configuration change.

- **Mobile platforms** (iOS, Android) are environments where the hardware manufacturer controls OS updates. A person with a 4-year-old phone may be stuck on the OS version it shipped with. Programs written in Awsum are built by companies whose customers are regular people, not developers — they have every right to use older devices for as long as those devices work. We target the oldest OS version still supported by the manufacturer.

The exact criteria for selecting minimum mobile OS versions are yet to be defined. The principle is clear: don't punish end users for not buying new hardware.

## Current targets

| Target     | Minimum version | Rationale                     |
| ---------- | --------------- | ----------------------------- |
| Node.js    | 22 (LTS)        | Latest LTS                    |
| LLVM/Clang | 15              | Opaque pointer support        |
| JVM        | 7               | CONSTANT_MethodHandle support |
| WASM/WASI  | wasmtime        | WASI preview 1                |
| .NET       | 9.0             | Latest LTS-adjacent release   |
