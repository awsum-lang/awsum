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
| Type-ascription patterns `(x : T)`   | done                                                          |
| Implicit injection into a row        | done                                                          |
| `do`-notation for `Either`           | done                                                          |
| Lambda expressions `\x -> e`         | closed lambdas and `do`-block continuations; outer-parameter capture hits a `saturate` restriction |
| Open-row `(A \| r) ~ (A \| B \| r')` | partial — singleton tyvar / row only                          |
| Row-typed `let`-generalisation       | not yet — every top-level def needs a signature               |
| Type classes / dispatch              | not yet — `do` is hard-coded to `Either`                      |

---

## Foundations

### Primitives

`String`, `Int32`, `UInt8`, `IO a` are built-in. Everything else is in the prelude (see [docs/prelude.md](prelude.md)).

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

The reason is **error locality**. With global inference a mistake surfaces wherever the system becomes inconsistent, not where it was made. Structural sums sharpen the cost: prelude arithmetic, parsing, and lookup all return `Either e a`, and combining operations takes the set-semantic union of error rows. A missing `<-` or a refactor inside the body silently widens or narrows the inferred row — still well-formed, just no longer the row the user thought they were exporting. Mandatory signatures cap the blast radius at one definition.

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

There is **no catch-all** (`_ -> …`). When a type gains a new constructor, a catch-all would silently route it into whatever default the arm picked. Without one, every existing `case` over the extended type stops compiling until the new constructor is handled — the change becomes visible everywhere it matters instead of turning into a silent logic bug.

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

Anonymous function literals parse as `\x y -> body` and typecheck bidirectionally against an expected arrow type from context.

```awsum
inc42 : Int32
inc42 = apply (\n -> n) 42
```

Awsum has **no synthesis form for lambdas** — they only typecheck where the surrounding context fixes their type:

```awsum
-- error: a lambda with no surrounding type cannot be checked.
-- noContext = \n -> n
```

**Today's restriction.** A lambda that closes over an outer-function parameter is rejected by the saturation pass with `partial application with local captures is not supported`. Restructure so the captured value flows through a parameter of a top-level helper:

```awsum
-- error in this iteration: 'k' is captured from outside the lambda.
-- captureFn : Int32 -> Int32
-- captureFn k = apply (\n -> k) answer
```

`do`-notation bypasses this — the desugar inlines bind into a nested `case`, so multi-bind blocks with later-step references compile without first-class closures. Free-standing closures-with-captures are tracked as future work.

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

Cross-module names are exempt. A parameter or pattern variable may shadow a top-level from another module — the prelude's `mapRight x f = …` parameter `f` does **not** clash with a user-program top-level `f`. Otherwise every prelude entry would need defensive parameter names. In the current iteration there are exactly two modules: the bundled prelude and the user program.

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
| `(p : T)`             | type-ascription pattern   | only valid against a structural-sum scrutinee |

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

main : String -> IO Unit
main _input = IO.Stdout.print (greet "hello")  -- "hello" is a String, fits the row
```

Injection works through nominal heads too: `Maybe Bool` fits where `Maybe (Bool | Unit)` is expected. Values built outside a row context are normalised at the boundary by a per-shape lifting helper, so a top-level `defaultJust : Maybe Bool` flows into a slot expecting `Maybe (Bool | Unit)` without a user-written wrapper.

```awsum
-- ok: 'Just True' is constructed directly at the row-typed call site.
main : String -> IO Unit
main _input = IO.Stdout.print (whatsThat (Just True))
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
- The block's final statement is an expression. Return a plain value as `Right` by calling `pureEither` explicitly — there is no `pure` keyword in this iteration; once type classes land, `pure` will be a polymorphic function rather than a syntactic rewrite.
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

## How errors are reported

Every type error carries a span pointing at the offending construct, surfaced by:

- `awsum check FILE` — human-readable, with carets;
- `awsum check --json FILE` — one JSON object per diagnostic, used by `awsum-vscode`;
- `awsum check --strict FILE` — escalates warnings to a non-zero exit for CI.

There is no error suppression mechanism.
