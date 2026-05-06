# Prelude and built-in functions

How Awsum lets types and functions written in the language itself (the prelude) coexist with per-target implementations the compiler substitutes at codegen (built-ins). Design doc — covers how the mechanism works, what it enables, and which alternatives were rejected.

## The problem

The language has three categories of public functions and types:

1. **Fully expressible in Awsum.** Things like `map : (a -> b) -> List a -> List b`. We want to write them in Awsum and hide nothing from the reader.
2. **Expressible in Awsum in terms of lower-level operations.** Things like `not : Bool -> Bool`. Technically buildable with `case`, and we still want the Awsum source visible.
3. **Not expressible in the current language.** Things like `predInt32 : Int32 -> Either UnderflowError Int32`. The implementation needs target-specific primitives (range check + tagged-sum construction at codegen time). Adding `Int64` or `Int128` adds more target-specific workarounds, not fewer.

The design goals:

- There is **one entry point** the user sees — `Prelude.aww` — where every prelude-visible signature and every prelude-level type lives.
- Hover and go-to-definition in the IDE land there, not inside the compiler's Haskell.
- For category-3 functions, the per-target implementation lives in the compiler's built-in table and is substituted at codegen.
- A category-1 function can later migrate to category 3 (e.g. for a target-specific optimisation) without any visible change on the user side.

## Design

`Prelude.aww` is a regular Awsum file that ships inside the compiler and is parsed and type-checked the same way user code is. In it:

- Prelude-visible types are declared (`Either`, `Maybe`, `Bool`, `Unit`, etc).
- Every prelude-visible function has a signature.
- Category-3 function bodies are a reference to the compiler-provided implementation:

  ```
  showInt32 : Int32 -> String
  showInt32 = BuiltIn.showInt32

  predInt32 : Int32 -> Either UnderflowError Int32
  predInt32 = BuiltIn.predInt32
  ```

Category-1 and category-2 bodies are ordinary Awsum — `BuiltIn` does not appear there.

### `BuiltIn` is a syntactic primitive, not a module

`BuiltIn.foo` is **not** a qualified module reference. The parser recognises this form directly and lowers it to a Core `CBuiltIn "foo"`. There is no `BuiltIn.aww` file, `awsum ast BuiltIn.aww` is meaningless, and the user cannot declare their own `BuiltIn.bar`. The `BuiltIn` namespace is reserved.

Making `BuiltIn` a real module would have required either shipping a physical file with placeholder bodies or generating one at build time, plus explaining to the user why that module is special. A separate syntactic category (like `case`/`of`) is simpler than a name in scope.

### Type checking

When the type-checker meets `= BuiltIn.foo` in the alias form `foo = BuiltIn.bar` at top level, it checks:

1. The compiler's built-in table has an entry named `bar`.
2. The entry's type **equals** the type declared on the left. No coercion, no unification slack — equality only. Any difference is a compile error.
3. If the table has no entry for `bar`, compilation fails with `UnknownBuiltIn` pointing at `BuiltIn.bar`.

This keeps the compiler's table and `Prelude.aww` in lock-step: any drift between them is a compile error — either when the compiler type-checks the bundled prelude itself at startup (surfaced as "Internal compiler error"), or on the first user compilation that resolves the name.

The alias form — zero parameters on the left of `=`, a bare `BuiltIn.bar` on the right — is the only place the type-checker waives its usual arity rule. For every other zero-parameter definition the RHS is checked against the _result_ type of the signature, so a user who writes `foo = someFunction` with a function-typed signature still gets an arity-mismatch error. Aliasing a built-in is the one case where the RHS carries the whole arrow type.

### Bootstrap order and the apparent cycle

There is an order-of-operations puzzle: the signature of `predInt32` in `Prelude.aww` mentions `Either`, which is _also_ declared in `Prelude.aww`; the compiler's built-in table wants to cross-check the `predInt32` entry against a type that mentions `Either` too.

The cycle is on values, not on types. The sequence is:

1. The parser reads `Prelude.aww`.
2. The type-checker processes type declarations (`type Either a b = Left a | Right b`). The environment now has `Either`.
3. The type-checker processes function signatures. The environment now has `predInt32 : Int32 -> Either UnderflowError Int32`.
4. The type-checker processes function bodies. When it hits `= BuiltIn.bar`, it looks up `bar` in the compiler's table and compares types.
5. The table's entry for `predInt32` also refers to `Either` — and resolves through the same environment that step 2 populated. There is no second copy of `Either` hiding in the compiler's Haskell.

The built-in table stores types as `Core.Type` values, not Haskell types. Name resolution for `Either` in the table goes through the same `TypeEnv` `Prelude.aww` just populated. One environment, visited twice — not two pretending to be the same.

### What the user sees

```
import IO.Stdout

main : String -> IO Unit
main _input = IO.Stdout.print (showInt32 42)
```

`showInt32` is in scope without an explicit import because the prelude is injected implicitly. Go-to-definition on `showInt32` opens `Prelude.aww` at the line:

```
showInt32 : Int32 -> String
showInt32 = BuiltIn.showInt32
```

and stops there — `BuiltIn.showInt32` has no Awsum definition to open. This is the same transparency boundary as `foreign import` in GHC or `@external` in Elm.

### Enabling future migration

Suppose `not : Bool -> Bool` is written in Awsum via `case`. Later, on one target, native XOR turns out to be faster. The migration is a one-line edit in `Prelude.aww`:

```
-- before:
not : Bool -> Bool
not True = False
not False = True

-- after:
not : Bool -> Bool
not = BuiltIn.not
```

The user sees no change — signature identical, go-to-definition lands in the same place. The compiler's table grows a `not` entry with per-target implementations. Migrating back is symmetric.

## Program type and platform-gated effects

`BuiltIn.foo` covers one class of compiler-known name: prelude-visible functions that behave the same on every target (`showInt32`, `predInt32`, `concatString`, …). A second class exists: effects whose availability depends on the _kind of program_ the user is writing — `IO.Stdout.print` for a CLI program, `Window.focus` for a browser program, and so on. Mixing these into `BuiltIn` would lose the gating.

The design distinguishes them at the key shape:

- `CBuiltIn "showInt32"` — flat unqualified key, resolved through `Awsum.BuiltIn`.
- `CBuiltIn "IO.Stdout.print"` — dotted qualified key, resolved through `Awsum.Program.platformTable`.

Two independent gates decide whether a platform name is usable in a given file:

1. **Program type** (`--program-type cli`, mandatory on typecheck-bearing commands) picks which platform table the typechecker and `ElaborateLower` see. Today only `ProgramCli` is implemented in `Awsum.Program.Cli`.
2. **Module import** (`import IO.Stdout`) is the per-file visibility gate. It's independent of the program type — a CLI program that omits the import still cannot call `IO.Stdout.print`.

Both gates are enforced in `Awsum.Typing.builtinEnvFromImports` — it computes the intersection of the current program type's table and the file's imports.

The CLI flag is mandatory to force an explicit choice rather than a silent default that could typecheck a program against the wrong effect set.

Core-level uniformity is deliberate: both classes collapse to `CBuiltIn`. Backends don't care which table a name came from — they dispatch on the key string alone. The distinction is a typing / availability concern, not an IR concern. Migrations are symmetric: a function can move between `BuiltIn` and a program's platform table, or between program types, without touching any backend.

## Tradeoffs

- **One extra pipeline stage**: every compilation parses and type-checks `Prelude.aww`. Whole-program tree-shaking runs between lowering and codegen (reachability from `main` across every `CDecl`, including prelude entries and generated constructor wrappers), so unused prelude functions never reach any backend. Adding new prelude entries has zero cost on programs that don't use them.
- **Mismatch errors need care**: the diagnostic "signature in `Prelude.aww` disagrees with the built-in table" is aimed at a compiler developer adding a new built-in, not at a regular user. The wording and span placement of `BuiltInTypeMismatch` matter.
- **Strict type equality** instead of subtyping or coercion is a deliberate choice. `BuiltIn.foo` is not a polymorphic variable — it is a hole typed from the outside. Any flexibility here turns into silent drift between declaration and implementation.

## Rejected alternatives

1. **Hard-coded entries in `TypeEnv`**, as for `showInt32` / `showUInt8` before this design. Fine for two or three entries. Doesn't scale to dozens: the prelude disappears into Haskell, hover has nothing to show, and the user has no single entry point to read.
2. **`Prelude.aww` without `BuiltIn`, primitives as bodiless signatures** (`showInt32 : Int32 -> String` and nothing more). The parser would have to accept "signature only" as a valid top-level form, and a user typo ("I forgot to write the body") would become indistinguishable from "this is a built-in". An explicit marker is clearer.
3. **FFI-style syntax** (`foreign import showInt32 : Int32 -> String`). Brings lexical and syntactic changes plus C-FFI connotations that don't apply. `= BuiltIn.foo` fits the existing "function definition" shape with no new grammar.

## Where this lives in the code

- `stdlib/Prelude.aww` — the prelude source, embedded into the compiler binary via `file-embed`.
- `src/Awsum/Prelude.hs` — loading, `withPrelude`, prelude-warning filtering.
- `src/Awsum/BuiltIn.hs` — the prelude built-in table (flat keys) and `lookupBuiltIn`.
- `src/Awsum/Program.hs` — `ProgramType` enum + `platformTable` dispatch.
- `src/Awsum/Program/Cli.hs` — the CLI platform-effect table (dotted qualified keys: `IO.Stdout.print`, …). Future `Awsum/Program/Browser.hs` etc. will follow the same shape.
- `src/Awsum/Syntax.hs` — `EBuiltIn` surface node.
- `src/Awsum/Core.hs` — `CBuiltIn` core node (the one node for both built-in kinds — dispatch is on the key string).
- `src/Awsum/Parser.hs` — recognising `BuiltIn.foo` as a syntactic primitive.
- `src/Awsum/Typing.hs` — alias-form arity rule, `UnknownBuiltIn`, `BuiltInTypeMismatch`, and `builtinEnvFromImports` (intersects the program type's platform table with the file's imports).
- `src/Awsum/ElaborateLower.hs` — lowering `EBuiltIn` to `CBuiltIn` (flat key), qualified names to `CBuiltIn` (dotted key) via the program's platform table, skipping alias `FunDef`s, reachability-based tree-shake (`reachableCore`) that drops any top-level Core declaration not reachable from `main`, including prelude helpers and constructor wrappers.
- Each backend in `src/Awsum/Codegen/*` — per-target dispatch on `CCall (CBuiltIn name) args` keyed by the name string, e.g. `@__showInt32`, `@__predInt32`, `@__print` for `IO.Stdout.print`.
