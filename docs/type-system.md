# Awsum type system

User-facing description of Awsum's type system — concepts and examples of programs that compile or get rejected. For implementation, see `src/Awsum/`.

---

## Quick map of concepts

| Concept                              | Status                                                        |
| ------------------------------------ | ------------------------------------------------------------- |
| Primitives (`String`, `Int32`, …)    | done                                                          |
| Nominal sum types (`type T = …`)     | done                                                          |
| Polymorphic type variables           | done                                                          |
| Function types `a -> b`              | done                                                          |
| Pattern matching, exhaustiveness     | done                                                          |
| Structural sums `(A \| B)`           | done                                                          |
| Type ascription `(e : T)` / `(p : T)` | done — expression-position pins the type; pattern-position also binds `p` |
| Implicit injection into a row        | done                                                          |
| `do`-notation for `Either`           | done                                                          |
| `IO e a` as lazy data + `bindIO`/`mapIO` | done                                                       |
| Lambda expressions `\x -> e`         | done — closed lambdas, `do`-block continuations, and closures over outer parameters |
| Open-row `(A \| r) ~ (A \| B \| r')` | partial — singleton tyvar / row only                          |
| Row-typed `let`-generalisation       | not yet — every top-level def needs a signature               |
| Type classes / dispatch              | not yet — `do` is hard-coded to `Either`                      |
| Comments and docstrings              | done — `--` line or `{- -}` block; adjacent to a decl = doc, blank line breaks the link |

---

## Foundations

### Primitives

`String`, `Int32`, `UInt8`, `UInt32` are built-in. `IO e a` is declared in the prelude (see [docs/prelude.md](prelude.md) and [IO](#io) below); everything else is in the prelude too.

`String` has two length caps, both expressed in **UTF-16 code units** so the spec stays in one unit regardless of content. They are derived from different backend constraints:

- **Runtime cap** — `maxStringLengthUtf16CodeUnits = 134_217_728` (`2^27`) UTF-16 code units. Applies to any string the running program builds — `(++)`, the program-entry argument, future `IO`-driven sources. Operations that would produce a longer string return `Left StringTooLong`. Pinned by the WASM-32 backend (not by the smallest UTF-16 runtime), so the worst-case UTF-8 expansion (`3 × 2^27 ≈ 384 MiB`), the `(++)` peak (`6×`), and other program data fit in WASM-32's 2–3 GiB practical budget — see [targets.md](targets.md).
- **Compile-time literal cap** — `maxStringLitUtf16CodeUnits = 21845` UTF-16 code units. Applies only to `LString` literals in `.aww` source. Pinned by JVM's `CONSTANT_Utf8_info` length field (`u2`, max 65535 UTF-8 bytes per single literal): with worst-case UTF-8 expansion `3 bytes/code unit` (BMP-3-byte content — CJK, hangul, most non-Latin scripts), `floor(65535 / 3) = 21845` is the largest UTF-16 code unit count whose worst-case Modified-UTF-8 encoding still fits the field. A literal over this cap is rejected by the typechecker as `StringLiteralTooLong` regardless of content. Runtime construction is bounded by the much higher runtime cap, so concatenations or input strings of any size up to `2^27` work normally — only the source-level shape is restricted.

```awsum
greeting : String
greeting = "hello"

answer : Int32
answer = 42
```

There is **no defaulting** — see [Integer literals](#integer-literals--no-defaulting).

### Type signatures are mandatory

Every top-level definition requires an explicit signature.

```awsum
-- ok
square : Int32 -> Int32
square n = n

-- error: Missing type signature for: badSquare
-- badSquare n = n
```

Local inference still runs inside a body — the compiler only refuses to pick a type for a top-level definition from its body.

The reason is **error locality**. With global inference a mistake surfaces wherever the system becomes inconsistent, not where it was made. Structural sums sharpen the cost: prelude arithmetic, parsing, and lookup all return `Either e a`, and combining operations takes the set-semantic union of error rows. A missing `<-` or a refactor inside the body silently widens or narrows the inferred row. Mandatory signatures cap the blast radius at one definition.

---

## Nominal sum types

A `type` declaration introduces a sum — a type whose values come from a fixed list of constructors, each carrying zero or more typed fields.

```awsum
type Bool = True | False              -- two nullary constructors
type Maybe a = Nothing | Just a       -- parametric, one nullary + one unary
type Either a b = Left a | Right b    -- the canonical "result with error"
type Tree a = Leaf | Node (Tree a) a (Tree a)  -- recursive
```

Use `case` to match:

```awsum
describe : Maybe Int32 -> String
describe x = case x of
  Nothing -> "nothing"
  Just n -> "just " ++ showInt32 n
```

### Exhaustiveness

`case` arms must cover every constructor. Missing one is a compile error, never a warning.

```awsum
-- error: Non-exhaustive case on Maybe: missing ["Nothing"]
broken : Maybe Int32 -> String
broken x = case x of
  Just n -> showInt32 n
```

There is **no catch-all** (`_ -> …`). When a type gains a new constructor, a catch-all would silently route it into whatever default the arm picked. Without one, every existing `case` over the extended type stops compiling until the new constructor is handled.

### Uninhabited types

A type with zero constructors has no values. You can declare one and write a function that takes it (well-typed but never callable), but you cannot construct one.

```awsum
type Never                            -- empty type — useful as a phantom

-- ok: signature is fine; the function is unreachable at runtime.
absurd : Never -> String
absurd _x = "unreachable"
```

A constructor whose field type is uninhabited is itself unreachable; exhaustiveness does not require matching it.

```awsum
type Box a = Box a
type Container = Full (Box Never) | Empty

describe : Container -> String
describe x = case x of
  Empty -> "empty"   -- ok: 'Full' is unreachable because 'Box Never' is uninhabited
```

---

## Polymorphic type variables

Lowercase identifiers in a signature are type variables, universally quantified — the function works for every concrete type the caller picks.

```awsum
identity : a -> a
identity x = x

const : a -> b -> a
const x _y = x

mapMaybe : Maybe a -> (a -> b) -> Maybe b
mapMaybe x f = case x of
  Nothing -> Nothing
  Just a -> Just (f a)
```

At a call site each variable is independently fixed.

```awsum
answer : Int32
answer = 42

fortyTwo : Int32
fortyTwo = identity answer    -- ok: 'a' fixed to 'Int32' here

hi : String
hi = identity "hello"         -- ok: a different 'identity' use, 'a' fixed to 'String'
```

A bare integer literal as an argument typechecks when the enclosing context pins the result — the bidirectional check propagates the substitution down:

```awsum
ten : Int32
ten = identity 10              -- ok: 'a' pins to 'Int32' via the return type
```

Lambda arguments contribute their own substitutions: in `apply (\n -> n) 42 : Int32` the lambda body pins `a := Int32` before `42` is checked. Without a pinning context the literal still has no type — the rule is "no defaulting", not "no propagation".

### Variables only mean what the signature says

A variable in a constructor field that the signature does not list is a compile error.

```awsum
-- error: 'a' is not declared as a type parameter
type Phantom = Phantom a
```

---

## Functions

Function types are right-associative arrows; application is curried.

```awsum
add : Int32 -> Int32 -> Int32   -- the same as Int32 -> (Int32 -> Int32)
add a b = a       -- placeholder body; real arithmetic is in the prelude

apply : (a -> b) -> a -> b
apply f x = f x
```

Constructors are first-class — passable to HOFs and partially applicable.

```awsum
answer : Int32
answer = 42

makeJust : Maybe Int32
makeJust = apply Just answer   -- ok: 'Just' is a function `Int32 -> Maybe Int32` here
```

### Destructuring patterns in parameters

A function parameter is either a name or a parens-wrapped destructuring pattern:

```awsum
sumTriple : Tuple3 Int32 Int32 Int32 -> Int32
sumTriple (Tuple3 a b c) = …                 -- destructures the tuple in place

addPair : Tuple2 Int32 Int32 -> Int32
addPair (Tuple2 a b) = …
```

The parens are required — without them `f Tuple3 a b c = …` would mean four bare parameters. The same shape works on lambda parameters: `\(Tuple2 a b) -> e`. Exhaustiveness applies: single-constructor types pass trivially; refutable patterns raise `NonExhaustiveCase`.

### Lambda expressions

Anonymous function literals parse as `\x y -> body` and typecheck bidirectionally against an expected arrow type from context (e.g. flowing into a HOF parameter):

```awsum
inc42 : Int32
inc42 = apply (\n -> n) 42
```

Without a top-down type, parameters get fresh tyvars and the body is inferred against the extended environment. A bare `let id = \x -> x in body` then works at multiple types — each use unifies the shared variable independently:

```awsum
both : Int32 -> String -> String
both n s =
  let id = \x -> x
   in showInt32 (id n) ++ " / " ++ id s
```

The same path covers a lambda as the head of an application (`(\x -> x) 5`). Top-level definitions still need an explicit signature — `noContext = \n -> n` is rejected for the missing signature, not the lambda.

**Closures.** A lambda may close over an outer-function parameter; the captured value follows the lambda wherever it flows.

```awsum
-- ok: 'k' is captured from outside the lambda.
captureFn : Int32 -> Int32
captureFn k = apply (\n -> k) answer
```

No backend has a closure runtime. The compiler /defunctionalises/ each HOF call site at lowering time: the static closure flowing into a fn-typed slot is replaced with a specialised first-order copy of the HOF whose parameter list adds the closure's captures up front. After this pass no first-class function value remains in any reachable position. Polymorphic HOFs become a family of monomorphic specialisations, one per distinct closure shape across call sites; pass-through HOFs (`applyTwice f x = applyOnce f (applyOnce f x)`) cascade naturally because each inner call resolves the same closure and reuses the memoised specialisation.

### Pipe operator `|>`

`x |> f` is **syntax** for `f x`. Left-associative, lowest precedence — `++` binds tighter (`a ++ b |> f` is `f (a ++ b)`); a chain `x |> f |> g` is `g (f x)`.

```awsum
-- Without |>
shoutLoud : String -> IO Never Unit
shoutLoud msg = bindIO (IO.Stdout.print msg) (\_u -> IO.Stdout.print "!")

-- With |>
shoutLoud : String -> IO Never Unit
shoutLoud msg = IO.Stdout.print msg |> bindIO (\_u -> IO.Stdout.print "!")
```

The rewrite happens before any Core-to-Core pass: after lowering, the IR for `x |> f` is the same IR you'd get for `f x`, so there is no residual call frame on any backend.

`(|>)` is **not** a referenceable name — there is no `(|>) x f = f x` definition in the prelude, and the parser rejects `(|>)` in any value position. `|>` is a syntactic operator, not a higher-order function. (When type classes and a supercompiler land, a first-class form may be added without losing the zero-cost guarantee; until then, the operator-only form is the only one available.)

---

## Integer literals — no defaulting

A bare integer literal has no type until the surrounding context gives it one.

```awsum
-- ok: signature fixes 'Int32', literal validates against the range.
answer : Int32
answer = 42

-- error: expression context isn't decided. There is no implicit
-- "default to Int32" behaviour.
-- ambiguous = 42
```

Literals out of the declared type's range are rejected at compile time.

```awsum
-- error: integer literal out of range for UInt8 (covers 0..255).
tooBig : UInt8
tooBig = 300
```

---

## No shadowing within a module

A new binding cannot reuse a name already visible in any enclosing scope of the **same module**.

```awsum
f : Int32 -> Int32
f x = x
--^ error: Shadowing is not allowed: 'x' is already bound in an enclosing scope.

x : Int32
x = 1
```

The rule covers function parameters, pattern variables, top-level definitions, type parameters, and constructor names. The diagnostic always points at the _new_ binder. Every reference in the module is unambiguous — the binding site is the lexically-earliest one.

Cross-module names are exempt. A parameter or pattern variable may shadow a top-level from another module — the prelude's `mapRight x f = …` parameter `f` does **not** clash with a user-program top-level `f`. Otherwise every prelude entry would need defensive parameter names. Today there are exactly two modules: the bundled prelude and the user program.

---

## Underscore convention

A leading `_` marks a binding as intentionally unused.

- `_n`, `_message` — values you bind and don't reference.
- `_a` — type parameter you don't use in any constructor.
- `_C` — constructor you don't expect anyone to construct.
- `_Foo` — type you keep around as a phantom.

Referencing any `_`-prefixed name _anywhere_ is a compile error: if you're using it, the underscore is wrong.

```awsum
-- ok: '_n' bound but ignored.
greeting : Int32 -> String
greeting _n = "hello"

-- error: '_n' is referenced; rename to 'n' or drop the prefix.
-- bad : Int32 -> Int32
-- bad _n = _n
```

A bare `_` is a wildcard — it binds nothing, and is rejected anywhere a name is required (top-level definitions, type names, constructor names, type parameters).

An unused non-`_` name is a warning with a quick-fix to add the underscore. `awsum check --strict` escalates warnings to a non-zero exit for CI.

---

## Pattern matching

| Pattern               | Matches                   | Notes                                         |
| --------------------- | ------------------------- | --------------------------------------------- |
| `True`, `Nothing`, …  | nullary constructors      | tag-equal at runtime                          |
| `Just x`, `Cons x xs` | constructor with bindings | binds each field to a name                    |
| `Just _`              | constructor, ignore field | wildcard — no binding                         |
| `(p : T)`             | type-ascription pattern   | see [Type ascription](#type-ascription) below; row-elimination form covered in [Structural sums](#structural-sums-row-types) |

Nested patterns work as expected.

```awsum
firstZero : Maybe (Maybe Int32) -> Int32
firstZero x = case x of
  Just (Just n) -> n
  Just Nothing -> 0
  Nothing -> 0
```

Literals inside an arm's body pick up their type from the enclosing function's signature.

---

## Type ascription

`(value : T)` everywhere means **"the value at this node has type `T`"**. The form appears in two syntactic positions:

- **Expression position** — `(e : T)` pins the type of an expression at the use site. Useful where bidirectional inference alone has too little context — most often a bare integer literal flowing into a polymorphic argument:

  ```awsum
  identity : a -> a
  identity x = x

  -- Without ascription: 'identity 42' has no synth form (the literal
  -- needs a numeric type pin), and 'a' is unresolved.
  pinned : Int32
  pinned = identity (42 : Int32)
  ```

  The ascription becomes the expected type for the inner expression. Integer literals validate against the ascribed range; polymorphic call sites resolve their `a` to the ascribed type; row-injection picks the right alternative.

- **Pattern position** — `(x : T)` matches the alternative `T` of a structural-sum scrutinee and binds `x` to that alternative. Covered in [Structural sums](#structural-sums-row-types) below.

The principle is identical in both positions; the difference is that patterns also bind names (because patterns introduce them), expressions do not.

The expression form requires parens — bare `e : T` would be ambiguous in positions like `let n = e : T in body`. The pattern form requires parens for the same reason.

```awsum
-- error: ascription doesn't fit the value
-- bad : String
-- bad = (42 : String)
--       ^^^^^^^^^^^^^
-- The integer literal 42 cannot have type String.
```

---

## Structural sums (row types)

A type can be the union of two or more types, written with `|` inside parens:

```awsum
ageOrName : (Int32 | String) -> String
ageOrName x = case x of
  (n : Int32) -> "age " ++ showInt32 n
  (s : String) -> "name " ++ s
```

The pipe binds **looser** than the arrow — `A | B -> C` parses as `A | (B -> C)`. Always wrap unions in parens.

### Row equivalence

Two rows are equal if their alternatives are the same set: order doesn't matter, duplicates collapse.

```
(A | B)         ~ (B | A)         -- commutative
(A | B | A)     ~ (A | B)         -- idempotent
((A | B) | C)   ~ (A | (B | C))   -- associative
```

### Type-ascription patterns

`(x : T)` matches the alternative `T` and binds `x`. The case must cover every alternative.

```awsum
-- ok
describe : (Int32 | String) -> String
describe x = case x of
  (n : Int32) -> showInt32 n
  (s : String) -> s

-- error: NonExhaustiveRow — 'String' is uncovered.
-- broken : (Int32 | String) -> String
-- broken x = case x of
--   (n : Int32) -> showInt32 n
```

There is **no catch-all** on a structural sum scrutinee — every alternative is covered explicitly or it's a compile error.

### Nominal alternatives in a row

A row alternative can be a fully-applied nominal type. Constructor patterns mix freely with type-ascription patterns in the same case:

```awsum
type ErrA = ErrA
type ErrB = ErrB

whatsThat : (Int32 | String | Maybe (Bool | Unit)) -> String
whatsThat x = case x of
  (n : Int32) -> "Int32 " ++ showInt32 n
  (s : String) -> "String " ++ s
  Nothing -> "Nothing"
  Just (b : Bool) -> case b of
    True -> "Just True"
    False -> "Just False"
  Just (u : Unit) -> "Just " ++ showUnit u
```

Coverage is checked at every level: every row alternative, every constructor of nominal alternatives, and inner rows like `Maybe`'s argument.

### Implicit injection

A value of type `A` flows into a position expecting `(A | B | …)` without an explicit wrapper.

```awsum
greet : (Int32 | String) -> String
greet x = case x of
  (n : Int32) -> "n=" ++ showInt32 n
  (s : String) -> "s=" ++ s

main : IO Never Unit
main = IO.Stdout.print (greet "hello")  -- "hello" is a String, fits the row
```

Injection works through nominal heads too: `Maybe Bool` fits where `Maybe (Bool | Unit)` is expected. Values built outside a row context are normalised at the boundary by a per-shape lifting helper, so a top-level `defaultJust : Maybe Bool` flows into a slot expecting `Maybe (Bool | Unit)` with no user-written wrapper.

```awsum
-- ok: 'Just True' is constructed directly at the row-typed call site.
main : IO Never Unit
main = IO.Stdout.print (whatsThat (Just True))
```

Row labels dispatch by FNV-1a hash; the lowering rejects programs with `Row tag collision` if two distinct labels hash to the same tag — vanishingly unlikely in hand-written code, but a hard guard against adversarial names.

---

## Higher-order functions and `Either`

The prelude defines `Either a b = Left a | Right b` and uses it as the error monad. Failure is `Left`, success is `Right`.

```awsum
predInt32 : Int32 -> Either UnderflowError Int32   -- in prelude

example : Int32 -> String
example n = case predInt32 n of
  Left _e -> "underflow"
  Right m -> showInt32 m
```

### `bindEither` and row-polymorphic error types

Composing two `Either`-returning operations whose error types differ:

```awsum
bindEither : Either e1 a -> (a -> Either e2 b) -> Either (e1 | e2) b
pureEither : a -> Either e a
mapRight : Either e a -> (a -> b) -> Either e b
mapLeft : Either e1 a -> (e1 -> e2) -> Either e2 a
```

`bindEither`'s result type unions the two error rows.

```awsum
type ErrorA = ErrorA
type ErrorB = ErrorB
type ErrorC = ErrorC

opA : Either ErrorA Int32
opA = Right 1

opB : Either (ErrorB | ErrorC) Int32
opB = Right 2

result : Either (ErrorA | ErrorB | ErrorC) Int32
result = bindEither opA (const opB)   -- 'const opB' ignores opA's success value
```

---

## `do`-notation

A `do` block desugars to a chain of `bindEither` / `pureEither`. The desugaring is hard-coded to `Either` — no type-class dispatch yet, and `do` only types against `Either e a`.

```awsum
type ErrorA = ErrorA
type ErrorB = ErrorB
type ErrorC = ErrorC

op1 : Either ErrorA Int32
op1 = Right 1

op2 : Either (ErrorB | ErrorC) Int32
op2 = Right 2

op3 : Either ErrorB Int32
op3 = Right 3

f : Either (ErrorA | ErrorB | ErrorC) Int32
f = do
  a <- op1
  b <- op2
  c <- op3
  pureEither c
```

### What's in scope inside a `do` block

- `<-` binds a name to the success value of an `Either`-returning expression. Anything else on the right is `DoBindNonEither`.
- The block's final statement is an expression. Return a plain value as `Right` by calling `pureEither` explicitly — there is no `pure` keyword today; once type classes land, `pure` will be a polymorphic function rather than a syntactic rewrite.
- A trailing `<-` or unfinished sentence is `DoBlockMissingResult`.

### Bound names threaded through subsequent statements

A bound name is visible to every later statement. The desugarer rewrites the chain into nested `case … of Left e -> Left e | Right p -> rest` before typechecking — continuations never appear as surface lambdas, and the synthesized `Left` arms feed the implicit-row-injection machinery to give the overall error type as the union of every `<-` step's `Left`.

```awsum
op2WithA : Int32 -> Either ErrorB Int32
op2WithA n = Right n

g : Either (ErrorA | ErrorB) Int32
g = do
  a <- op1
  b <- op2WithA a
  pureEither b
```

### `let` inside `do`

A `do` block can introduce a non-monadic binding with `let`:

```awsum
run : Int32 -> Either String String
run start = do
  a <- step1 start
  let prefix = "answer="
  b <- step2 a
  pureEither (prefix ++ showInt32 b)
```

The form is `let n = e` (no `in` — the rest of the block _is_ the body). Optional ascription `let n : T = e` applies when synthesis can't pin `e` — typically when the RHS is itself a `do`-block with mixed-row errors. The standalone `let n = e in body` (and ascribed variant) is also available outside `do` (see [`let` bindings](#let-bindings)); both desugar identically.

### Destructuring patterns on the LHS of `<-`

The LHS of `<-` accepts any pattern:

```awsum
do
  Tuple3 a b c <- parseInput raw
  property a b c
```

Desugars to `case parseInput raw of Left err -> Left err; Right (Tuple3 a b c) -> property a b c`. Exhaustiveness applies to the nested pattern: `Just x <- e` raises `NonExhaustiveCase` because `Right (Just x)` doesn't cover `Right Nothing`. Single-constructor types are exhaustive trivially.

---

## `let` bindings

`let n = e in body` binds `n` for the duration of `body`. It is an expression — usable wherever an expression is.

```awsum
pad : String -> String
pad s = let p = "[" ++ s in let q = p ++ "]" in q ++ q
```

- **No defaulting on the RHS.** `let n = 1 in body` is rejected — annotate (`let n : Int32 = 1`) or use an expression whose type is known.
- **Optional ascription.** `let n : T = e` checks `e` against `T`. Without ascription the typechecker synthesises `e`; failure raises `MissingLetAnnotation`. Common trigger: a `do`-block whose `<-` steps return `Either` with different error labels — the row-union can't be inferred bottom-up, but it can be checked top-down with an annotation.
- **Destructuring on the LHS.** `let (Tuple3 a b c) = e` binds three fields in one step (also inside `do`). Refutable patterns raise `NonExhaustiveCase`. Ascribing a destructuring let is rejected (`PatternLetAscription`) — ascribe the RHS instead.
- **No shadowing.** `let n = …` cannot reuse a name in scope at the let site.
- **The RHS is evaluated once.** Multiple references to `n` in `body` do not re-evaluate `e`.

The same form appears inside `do` blocks (see [`let` inside `do`](#let-inside-do)); both desugar identically.

---

## IO

`IO e a` is a sum type declared in the prelude:

```awsum
type IO e a
  = IOPure a
  | IOFail e
  | IOStdoutPrint String (IO e a)
  | IOGetArgs (Either (StringTooLong | UnpairedUtf16Surrogate) (List String) -> IO e a)
  | IOStdinReadAllString (Either (StringTooLong | InvalidUtf8) String -> IO e a)
  | IOStdinReadAllBytes (List UInt8 -> IO e a)
```

An `IO` value is **data**, not an effect. Constructing `IO.Stdout.print "x"` builds an `IOStdoutPrint` cell; the print does not happen at construction. The runtime walks the IO tree returned from `main` and performs the corresponding effects in order. Code that builds an `IO` value but never lets it reach the runtime walker produces no output:

```awsum
main : IO Never Unit
main =
  let unit = IO.Stdout.print "💩"
   in IO.Stdout.print "🔥"
-- prints `🔥`, not `💩🔥` — the first IO is constructed and discarded
```

The error row `e` works exactly like the error row of `Either`: each primitive declares its failure type explicitly. `main`'s required signature is `IO Never Unit`: any non-`Never` error row must be eliminated by the user before `main` returns it (handle the failure value, don't pretend it can't happen) — typically via `|> handleErrorIO h` at the tail of the chain.

### Reading command-line arguments

`IO.Args.getArgs : IO (StringTooLong | UnpairedUtf16Surrogate) (List String)` is a CLI platform built-in (registered when `--program-type cli` and `import IO.Args` are both present). The IO chain reads every command-line argument as a prelude `List String` rather than as a `main` parameter. Error semantics is all-or-nothing — if any one element fails to decode, the whole call returns `Left`:

```awsum
import IO.Stdout
import IO.Args

type NoArg = NoArg

greet : List String -> IO Never Unit
greet args =
  let res : Either (NoArg | StringTooLong) String = do
        first <- nothingAsLeft NoArg (headList args)
        "hi " ++ first
   in case res of
        Left (_n : NoArg) -> IO.Stdout.print "NO_ARG"
        Left (_l : StringTooLong) -> IO.Stdout.print "STRING_TOO_LONG"
        Right s -> IO.Stdout.print s

handleInputErr : (StringTooLong | UnpairedUtf16Surrogate) -> IO Never Unit
handleInputErr e = case e of
  (_l : StringTooLong) -> IO.Stdout.print "STRING_TOO_LONG"
  (_u : UnpairedUtf16Surrogate) -> IO.Stdout.print "UNPAIRED_UTF16_SURROGATE"

main : IO Never Unit
main =
  IO.Args.getArgs
    |> andThenIO greet
    |> handleErrorIO handleInputErr
```

`headList` and `nothingAsLeft` (both in the prelude) lift the typical "I want argument N" pattern out of the case-chain. The two decoding failures (length cap and unpaired UTF-16 surrogate) live in the IO error row, so they compose with `handleErrorIO` like any other IO failure. There is no entry-point parameter to pattern-match against.

### Reading stdin

Two stdin primitives, both CLI platform built-ins registered when `--program-type cli` and `import IO.Stdin` are both present. Each consumes the program's stdin to EOF; they differ in how they treat the bytes.

`IO.Stdin.readAllString : IO (StringTooLong | InvalidUtf8) String` decodes the bytes as **strict UTF-8** (RFC 3629). Because stdin is a raw byte stream the program owns end to end — unlike `argv`, which the host has already decoded — Awsum applies the full validity check itself rather than deferring to a host decoder. Any malformed sequence (overlong encoding, truncated multi-byte sequence, stray continuation byte, surrogate code point encoded in UTF-8, code point above U+10FFFF) is `Left InvalidUtf8`; a well-formed stream decodes to its `String`, or `Left StringTooLong` past the cap:

```awsum
import IO.Stdout
import IO.Stdin

handleInputErr : (StringTooLong | InvalidUtf8) -> IO Never Unit
handleInputErr e = case e of
  (_l : StringTooLong) -> IO.Stdout.print "STRING_TOO_LONG"
  (_i : InvalidUtf8) -> IO.Stdout.print "INVALID_UTF8"

main : IO Never Unit
main =
  IO.Stdin.readAllString
    |> andThenIO IO.Stdout.print
    |> handleErrorIO handleInputErr
```

`IO.Stdin.readAllBytes : IO Never (List UInt8)` returns the bytes verbatim — no decode, so no content-dependent failure (the error row is `Never`). Use it for input that isn't text, or for byte-exact round-tripping:

```awsum
import IO.Stdout
import IO.Stdin

main : IO Never Unit
main =
  IO.Stdin.readAllBytes
    |> andThenIO (\bytes -> case bytesToHexStringNoPrefix bytes of
        Left _e -> IO.Stdout.print "TOO_LONG"
        Right hex -> IO.Stdout.print hex)
```

`InvalidUtf8` (byte-level, from `readAllString`) and `UnpairedUtf16Surrogate` (UTF-16-level, from `IO.Args.getArgs`) are different failures — neither is a subset of the other. Argv is pre-decoded by the host into code units, so the only validity error left to detect is a lone surrogate; stdin is decoded from bytes by Awsum, so it owns the whole UTF-8 check.

Semantics are POSIX-honest: each call consumes whatever bytes remain on fd 0. A second call after EOF reads zero bytes — `readAllString` returns `Right ""`, `readAllBytes` returns `Nil`. Programs that need streaming reads will get a separate primitive when one is added; for now these two are "read everything in one go".

Both bypass every host's argv decoder — `sun.jnu.encoding` on the JVM, the OEM code page on Windows console, `CommandLineToArgvW` re-decoding on LLVM-MSVC. A program that needs to round-trip supplementary-plane characters, or any input the host's argv-encoding mangles, should read from stdin rather than argv.

### `bindIO` / `andThenIO` / `pureIO` / `failIO` / `mapIO` / `mapIOError` / `handleErrorIO`

Compose `IO` values through the prelude functions, exactly mirroring the `Either` family:

| Either                                           | IO                                            |
| ------------------------------------------------ | --------------------------------------------- |
| `bindEither : Either e1 a -> (a -> Either e2 b) -> Either (e1 \| e2) b` | `bindIO : IO e1 a -> (a -> IO e2 b) -> IO (e1 \| e2) b` |
| `andThenEither : (a -> Either e2 b) -> Either e1 a -> Either (e1 \| e2) b` | `andThenIO : (a -> IO e2 b) -> IO e1 a -> IO (e1 \| e2) b` |
| `pureEither : a -> Either e a`                   | `pureIO : a -> IO e a`                        |
| —                                                | `failIO : e -> IO e a`                        |
| `mapRight : Either e a -> (a -> b) -> Either e b` | `mapIO : IO e a -> (a -> b) -> IO e b`        |
| `mapLeft : Either e1 a -> (e1 -> e2) -> Either e2 a` | `mapIOError : IO e1 a -> (e1 -> e2) -> IO e2 a` |
| —                                                | `handleErrorIO : (e1 -> IO e2 a) -> IO e1 a -> IO e2 a` |

Sequencing two prints:

```awsum
main : IO Never Unit
main =
  IO.Stdout.print "a"
    |> andThenIO (\_u -> IO.Stdout.print "b")
-- prints `ab`
```

`do`-notation is hard-coded to `Either` and does not work for `IO`. Sequencing `IO` actions is explicit through `andThenIO` / `bindIO`. (When type classes land, `do` becomes polymorphic; until then, the lack of overloading is what keeps `do`'s desugaring purely syntactic.)

### Pattern-matching on `IO` constructors

Pattern-matching on `IOPure` / `IOFail` / `IOStdoutPrint` is technically allowed but **not part of the stable API**: new effects will add new constructors, breaking existing `case`-matches (no catch-all by language design). For ordinary composition, use `bindIO` / `mapIO` / `pureIO` / `mapIOError`. Direct matching is for first-party tooling (e.g. a future test framework's mock interpreter) that updates in lockstep with the compiler. When modules land, `IO`'s constructors will move into a privileged module inaccessible to user code.

---

## Comments and docstrings

Two comment forms: `--` to end-of-line, `{- ... -}` for a block. Block comments nest balanced — `{- outer {- inner -} more -}` is one comment, not three pieces.

### Adjacent comments are docstrings

A comment with **no blank line between it and the next top-level declaration** becomes that declaration's docstring:

```awsum
{- Square of an integer. -}
square : Int32 -> Either OverflowError Int32
square n = mulInt32 n n
```

Either form works; consecutive comments stack into one doc as long as no blank line breaks the chain:

```awsum
-- This stacks with the block below.
{- Both attach as one doc. -}
greet : String -> IO Never Unit
greet name = IO.Stdout.print name
```

A blank line is the escape hatch — the comment becomes a free-floating note that doesn't appear in `awsum docs` / LSP hover:

```awsum
{- Free-floating note — the blank line below detaches it from sumList. -}

sumList : List Int32 -> Either OverflowError Int32
sumList xs = ...
```

`awsum format` normalises every attached doc to a single `{- ... -}` block, regardless of how it was authored. Authorial line breaks inside the block are preserved — markdown lists and code blocks survive.

### Doc content is markdown

The compiler doesn't parse the content. It is shipped verbatim to LSP `textDocument/hover` as `MarkupContent { kind = "markdown", value = doc }`; every supported editor (`awsum-vscode`, `awsum-zed`, `awsum-intellij`, `awsum-nvim`, `awsum-emacs`) renders markdown by default. Multi-paragraph text, lists, inline code, links — all work as expected.

There is no Haddock-style prefix (`-- |`, `{-| -}`). A regular comment in the right position is the docstring.

### Two edge cases

1. **Module comment vs first-decl doc.** A `{- ... -}` at the very top of the file followed by a blank line, EOF, or an `import` is the module comment — stored separately, not surfaced in hover. The same block immediately followed by a top-level declaration is the doc of that declaration. The whitespace makes the choice visible.

2. **Unbalanced `-}` in doc content.** The doc text is parsed verbatim through `{- ... -}`, so a literal `-}` inside the content closes the block early. Either balance it with a matching `{-`, or use a line comment (`--`) for prose that needs to mention `-}` literally.

---

## How errors are reported

Every type error carries a span pointing at the offending construct, surfaced by:

- `awsum check FILE` — human-readable, with carets;
- `awsum check --json FILE` — one JSON object per diagnostic, used by `awsum-vscode`;
- `awsum check --strict FILE` — escalates warnings to a non-zero exit for CI.

There is no error suppression mechanism.
