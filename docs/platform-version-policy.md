# Platform Version Policy

Which versions of other software Awsum requires, builds against and is tested on: the platforms compiled programs run on, the editors programs are written in, and every dependency of the toolchain.

## Why

Vulnerabilities are now found and exploited at machine speed: AI-assisted attackers turn a published fix or advisory into a working exploit within hours, and zero-days are exploited faster than ever. Running anything older than the newest release is a live risk. Update as soon as a release is eligible, without waiting for the news to say so. We see no reason to support anyone who, for whatever reason, stays on a version of any software older than its latest LTS release (or its latest stable release where there is no LTS).

The same speed cuts the other way: a release channel can itself be compromised, and a tampered release can reach thousands of users through automatic updates before anyone notices. Such releases are usually found and withdrawn within days.

Hence one rule with two halves: move to the newest release as soon as it has been public for 7 days, and never earlier.

## The rule

1. **Cooldown.** A release becomes eligible once it has been publicly available for at least 7 days. This applies to everything: target platforms, editors, libraries and tools in lockfiles, CI actions, and the runtimes CI installs. The one exception: if every release that has passed the window has a known vulnerability and a newer release fixes it, take the fixed release immediately.
2. **The minimum is the newest eligible release.** For target platforms, the latest LTS line; for software without LTS releases, the latest stable line. Build against the minimum. Testing against newer releases, including ones still inside the window, is welcome: the cooldown governs what we build against, ship and require, not what we test on.
3. **A wider range only when a distribution channel forces it.** If a marketplace, or a fork we support, needs an older minimum, the minimum becomes the oldest version it needs, and verification starts from that lower bound.
4. **Pin, don't float.** Every reference names an exact version or an immutable revision — lockfiles, CI actions pinned to commit SHAs, exact runtime versions in CI — so no release can arrive before its window has passed. Each release moves the pins forward.

## Target platforms

**Server and browser platforms** (Node.js, JVM, .NET, browsers) can be updated without replacing hardware, so the rule applies as written.

**Mobile platforms** (iOS, Android) are the exception: the hardware manufacturer controls OS updates, and a person with a 4-year-old phone may be stuck on the OS version it shipped with. Programs written in Awsum are built by companies whose customers are regular people, not developers — they have every right to use older devices for as long as those devices work. We target the oldest OS version still supported by the manufacturer. The exact criteria are yet to be defined; the principle is clear: don't punish end users for not buying new hardware.

| Target     | Minimum version | Rationale                     |
| ---------- | --------------- | ----------------------------- |
| Node.js    | 26 (LTS)        | Latest LTS                    |
| LLVM/Clang | 15              | Opaque pointer support        |
| JVM        | 25 (LTS)        | Latest LTS                    |
| WASM/WASI  | wasmtime        | WASI preview 1                |
| .NET       | 10 (LTS)        | Latest LTS                    |

## Editors

Editors have no LTS lines, so the minimum for each editor is its newest stable release that has passed the cooldown. The exact versions live with each plugin and move forward with every release.

VS Code is where the third clause applies: the forks we support (Cursor, Windsurf, VSCodium) lag behind VS Code itself, so the minimum is the newest version all three run. It must also have an `@types/vscode` release past the cooldown — the types describe the API we build against — and if that version has none, the minimum steps back to the newest version that does. Each fork's base version is read from its public data — release tags, update feeds, the `product.json` in its official download — without installing anything; `just check-forks` in `awsum-vscode` computes the result.
