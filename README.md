# Awsum

A functional language with strong static typing, focused on reliability.

## Key features

- Friendly CLI (typecheck, build, run, format)
- The behavior is tested to be equivalent across targets.

## Targets

- **JS**
- **Lua**

## Editor support

### VSCode

- Install the `Awsum` extension to enable syntax highlight and code formatting
- Enable format on save

```json
{
  // settings.json
  "[awsum]": {
    "editor.formatOnSave": true,
    "editor.defaultFormatter": "awsum-lang.awsum-vscode"
  }
}
```

### Other editors

- [EBNF grammar](docs/spec/grammar.ebnf)
- [TextMate grammar](editors/textmate/awsum.tmLanguage.json)

## Examples

- [hello.aww](test/sources/hello.aww)
- [polymorphism.aww](test/sources/polymorphism.aww)

## Installation

- Install Stack via `ghcup`
- Install Node.js via NVM (for targeting JS)
- Install Lua via `brew install lua` (for targeting Lua)
- `stack build`
- `stack install`
- Make sure `~/.local/bin` is in `PATH`

## Usage

- `awsum build FILE [-t js] [-o OUT]` — compile to target and write to file (or stdout).
- `awsum run FILE [-t js] [--input TEXT | --stdin]` — compile to a temp file and execute with the system runtime, passing input to main.
- `awsum check FILE` — parse and typecheck; prints `OK` or a descriptive error.
- `awsum format FILE [-i|--in-place]` — `render . parse` with stable formatting. Preserves comments (including trailing inline), keeps a blank line between top-level blocks, and ends the file with a trailing newline.
- `awsum ast FILE` — pretty-print the surface AST (for debugging).
- `awsum core FILE` — print elaborated/lowered Core (post type elaboration) (for debugging).
- `awsum --version` — show version

Examples:

```sh
awsum build test/sources/hello.aww -t js  -o out.js  && node out.js "world"
awsum build test/sources/hello.aww -t lua -o out.lua && lua out.lua "world"

awsum run test/sources/hello.aww -t js  --input "world"
awsum run test/sources/hello.aww -t lua --input "world"

echo "world" | awsum run test/sources/hello.aww -t js  --stdin
echo "world" | awsum run test/sources/hello.aww -t lua --stdin

awsum check  test/sources/hello.aww
awsum format test/sources/hello.aww -i
awsum ast    test/sources/hello.aww
awsum core   test/sources/hello.aww
awsum --version
```

## Roadmap

- Equivalent behavior for numbers and strings across different runtimes.
- All arithmetic operations via Either. No silent underflow, overflow, precision loss. No NaN, Infinity, -0, etc.
- A compiler aware of dependency between application formats (cli, browser), targets (JS, Lua) and specific effects (Terminal, DOM, Ports) to allow compilation only for a specific set of effects.

## Notes

- The syntax and semantics is inspired by [Elm](https://elm-lang.org/).
- The name is inspired by the `AWSUM` keyword of the [LOLCODE](https://en.wikipedia.org/wiki/LOLCODE) language.
