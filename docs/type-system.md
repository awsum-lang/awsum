# Awsum type system

This document describes the type system from a user's perspective: what concepts the language has, how they fit together, and — for each concept — examples of programs that compile and programs that get rejected with a clear error. Implementation details (algorithms, AST shapes, internal data structures) are not the subject here; for those, see the source under `src/Awsum/`.

The reading order is layered: the early sections introduce foundational concepts every Awsum program uses, the later sections build on top.

---

## Quick map of concepts

| Concept                              | Status                                                        |
| ------------------------------------ | ------------------------------------------------------------- |
| Primitives (`String`, `Int32`, …)    | done                                                          |
| Nominal sum types (`type T = …`)     | done                                                          |
| Polymorphic type variables           | done                                                          |
| Function types `a -> b`              | done                                                          |
| Pattern matching on nominal sums     | done                                                          |
| Pattern matching with field bindings | done                                                          |
| Exhaustiveness checking              | done                                                          |
| Structural sums `(A \| B)`           | done                                                          |
| Type-ascription patterns `(x : T)`   | done                                                          |
| Mixed `PCon` + `PAscribe` arms       | done                                                          |
| Implicit injection into a row        | done                                                          |
| Distributive head subsumption        | done                                                          |
| `do`-notation for `Either`           | done                                                          |
| Lambda expressions `\x -> e`         | done for closed lambdas and for `do`-block continuations that capture only their own bind variable; lambdas that capture an outer parameter still hit a `saturate` restriction |
| Full row-polymorphic `bindEither`    | done                                                          |
| Open-row `(A \| r) ~ (A \| B \| r')` | partial — singleton tyvar / row only                          |
| Row-typed `let`-generalisation       | not yet — every top-level def needs a signature               |
| Type classes / dispatch              | not yet — `do` is hard-coded to `Either`                      |

---

## Foundations

### Primitives

`String`, `Int32`, `UInt8`, `IO a` are built-in. Everything else is defined in the prelude (see [docs/prelude.md](prelude.md)) on top of those primitives.

```awsum
greeting : String
greeting = "hello"

answer : Int32
answer = 42
```

There is **no defaulting**. An integer literal has no type unless the surrounding context fixes one — see [Integer literals](#integer-literals--no-defaulting) below.

### Type signatures are mandatory

Every top-level definition requires an explicit signature.

```awsum
-- ok
square : Int32 -> Int32
square n = n

-- error: Missing type signature for: badSquare
-- badSquare n = n
```

Type signatures are mandatory at top level **by design**. The compiler does have local type inference inside a definition's body — constructor instantiation, function application, polymorphic uses all go through unification — but stops at the boundary: it never picks a type for a top-level definition from its body.

The reason is **error locality**. With global type inference, a mistake in one place often surfaces as a type error elsewhere — the compiler solves a system of equations across the whole program, and the failure point is wherever that system becomes inconsistent, not where the user made the mistake.

Structural sums make the cost worse for Awsum specifically. The prelude's arithmetic, parsing, and lookup primitives all return `Either e a` with their own error type, and combining operations takes the set-semantic union of those rows. A missing `<-`, a swapped operation, or a refactor inside the body can widen or narrow the inferred error row silently — the result is still structurally valid, just no longer the row the user thought they were exporting.

Mandatory signatures cap the blast radius at one definition. A body wider than its signature, narrower than it, or a caller that expects a different shape — each fails locally, against the declared type.

The cost is one line per definition. The win is that type errors are local to where the contract was violated, and a function's public type is a property of the file you read.

---

## Nominal sum types

A `type` declaration introduces a sum (a type whose values come from a fixed list of constructors). Each constructor can carry zero or more typed fields.

```awsum
type Bool = True | False              -- two nullary constructors
type Maybe a = Nothing | Just a       -- parametric, one nullary + one unary
type Either a b = Left a | Right b    -- the canonical "result with error"
type Tree a = Leaf | Node (Tree a) a (Tree a)  -- recursive
```

A program that uses these types matches them with `case`:

```awsum
describe : Maybe Int32 -> String
describe x = case x of
  Nothing -> "nothing"
  Just n -> "just " ++ showInt32 n
```

### Exhaustiveness

`case` arms must cover every constructor of the scrutinee's type. Missing one is a compile error, never a warning.

```awsum
-- error: Non-exhaustive case on Maybe: missing ["Nothing"]
broken : Maybe Int32 -> String
broken x = case x of
  Just n -> showInt32 n
```

There is **no catch-all** (`_ -> …`). An unmatched constructor must be matched explicitly; the language refuses to let a missing case turn into a runtime error. The rule also covers what happens when a type gains a new constructor: with catch-all, the new alternative would be silently absorbed by every existing `_ -> …` arm and routed into whatever default that arm happened to pick — almost always the wrong choice. Without catch-all, every existing `case` over the extended type stops compiling until the new constructor is handled, and the change becomes visible everywhere it matters instead of turning into a silent logic bug.

### Uninhabited types

A type with zero constructors has no values. You can declare such a type and write a function that takes it (the function is well-typed but never callable, because there is no way to produce its argument), but you cannot construct one.

```awsum
type Never                            -- empty type — useful as a phantom

-- ok: signature is fine; the function is unreachable at runtime.
absurd : Never -> String
absurd _x = "unreachable"
```

A constructor whose field type is uninhabited is itself unreachable, and that's reflected in exhaustiveness: matching it isn't required.

```awsum
type Box a = Box a
type Container = Full (Box Never) | Empty

describe : Container -> String
describe x = case x of
  Empty -> "empty"   -- ok: 'Full' is unreachable because 'Box Never' is uninhabited
```

---

## Polymorphic type variables

Type signatures can introduce type variables (lowercase identifiers). Variables are universally quantified — the function works for every concrete type the caller picks.

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

At a call site, each variable is independently fixed to a concrete type (or to another variable if the caller is itself polymorphic).

```awsum
answer : Int32
answer = 42

fortyTwo : Int32
fortyTwo = identity answer    -- ok: 'a' fixed to 'Int32' here

hi : String
hi = identity "hello"         -- ok: a different 'identity' use, 'a' fixed to 'String'
```

A bare integer literal as the argument (`identity 42`) typechecks when the enclosing context pins the result. The bidirectional check walks the application's spine, unifies the function's generic result with the expected type to learn the binding for `a`, and pushes that substitution down to each argument position — so

```awsum
ten : Int32
ten = identity 10              -- ok: 'a' pins to 'Int32' via the return type
```

works without a typed-binding indirection. Lambda arguments contribute their own substitutions back through their bodies: `apply (\n -> n) 42 : Int32` typechecks because the lambda body's `n : a` unifies with the expected result type `Int32`, pinning `a := Int32` before the literal `42` is checked against `a`. Without a pinning context (a top-level signature, a constructor field type, an outer call's argument slot) the literal still has no type and the call is rejected — the rule is "no defaulting", not "no propagation".

### Variables only mean what the signature says

If a variable appears in a constructor field that the signature does not list, that's a compile error — Awsum does not silently introduce fresh variables.

```awsum
-- error: 'a' is not declared as a type parameter
type Phantom = Phantom a
```

---

## Functions

Function types are right-associative arrows. Curried application is the only application form.

```awsum
add : Int32 -> Int32 -> Int32   -- the same as Int32 -> (Int32 -> Int32)
add a b = a       -- placeholder body; real arithmetic is in the prelude

apply : (a -> b) -> a -> b
apply f x = f x
```

Constructors are first-class values: they can be passed to higher-order functions and partially applied like any other function.

```awsum
answer : Int32
answer = 42

makeJust : Maybe Int32
makeJust = apply Just answer   -- ok: 'Just' is a function `Int32 -> Maybe Int32` here
```

### Lambda expressions

Anonymous function literals parse as `\x y -> body`. The typechecker checks them bidirectionally against an expected arrow type from context, and lowering lifts each lambda to a fresh top-level helper.

```awsum
-- ok: '(\n -> n)' lifts to '$lam$0 n = n', and the call site
-- becomes 'apply $lam$0 42'. The literal '42' picks up its
-- 'Int32' type by propagation through the polymorphic call —
-- see "Polymorphic type variables" above.
inc42 : Int32
inc42 = apply (\n -> n) 42
```

Awsum has **no synthesis form for lambdas** — they only typecheck where the surrounding context fixes their type. A lambda at top level with no expected type is rejected:

```awsum
-- error: a lambda with no surrounding type cannot be checked.
-- noContext = \n -> n
```

**Today's restriction.** Lifting works for lambdas whose body references only the lambda's own parameters. A lambda that closes over an outer-function parameter (`\n -> outerK`) lifts fine, but the resulting partial application — passing the captured value at the call site — is rejected by the saturation pass with `partial application with local captures is not supported`. Restructure such code so the captured value flows through a parameter of a top-level helper, or so the body uses only the lambda's own argument:

```awsum
-- error in this iteration: 'k' is captured from outside the lambda.
-- captureFn : Int32 -> Int32
-- captureFn k = apply (\n -> k) answer
```

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

Validation is at compile time: literals out of the declared type's range are rejected.

```awsum
-- error: integer literal out of range for UInt8 (covers 0..255).
tooBig : UInt8
tooBig = 300
```

---

## No shadowing, ever

A new binding cannot reuse a name visible in any enclosing scope — not even from a different binding form.

```awsum
f : Int32 -> Int32
f x = x
--^ error: Shadowing is not allowed: 'x' is already bound in an enclosing scope.

x : Int32
x = 1
```

The rule applies uniformly to function parameters, pattern variables, top-level definitions, type parameters, and constructor names. The diagnostic always points at the _new_ binder.

The intent is to make every identifier reference unambiguous: the binding site is the lexically-earliest one, full stop. Explicit renames are how you express "I want a different value here", not implicit shadowing.

---

## Underscore convention

A leading `_` marks a binding as intentionally unused.

- `_n`, `_message` — values you bind and don't reference.
- `_a` — type parameter you don't use in any constructor.
- `_C` — constructor you don't expect anyone to construct.
- `_Foo` — type you keep around as a phantom.

Referencing any `_`-prefixed name _anywhere_ is a compile error: if you're using it, the underscore is wrong.

```awsum
-- ok: '_n' bound but ignored (loud at the call site, silent locally).
greeting : Int32 -> String
greeting _n = "hello"

-- error: '_n' is referenced; rename to 'n' or drop the prefix.
-- bad : Int32 -> Int32
-- bad _n = _n
```

A bare `_` is a wildcard pattern — it binds nothing. Using bare `_` where a name is required (top-level definitions, type names, constructor names, type parameter names) is rejected.

Binding a non-`_`-prefixed name and then never using it produces a warning, not an error, with a quick-fix to add the underscore. `awsum check --strict` escalates such warnings to errors for CI.

---

## Pattern matching

Patterns are a small language for taking apart constructed values.

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

A literal in a case-arm body picks up its type from the enclosing function's signature: the `Int32` return type pins `0` to `Int32` directly, so no separate `zero : Int32` binding is needed.

Inside a case arm, every value referenced must be in scope (either from outer bindings, the pattern itself, or top-level definitions).

---

## Structural sums (row types)

A type can be the union of two or more existing types, written with the `|` separator inside parentheses:

```awsum
ageOrName : (Int32 | String) -> String
ageOrName x = case x of
  (n : Int32) -> "age " ++ showInt32 n
  (s : String) -> "name " ++ s
```

The pipe binds **looser** than the arrow, so a row at the LHS of a function arrow needs explicit parens:

```awsum
fn : (Int32 | String) -> String   -- the row is the argument type
fn _ = "ok"

-- vs

-- 'A | B -> C' would parse as 'A | (B -> C)', a different (and
-- usually nonsensical) type. Always wrap unions in parens.
```

### Row equivalence

Two rows are equal if their alternatives are the same set: order doesn't matter, and duplicates collapse.

```
(A | B)         ~ (B | A)         -- commutative
(A | B | A)     ~ (A | B)         -- idempotent
((A | B) | C)   ~ (A | (B | C))   -- associative
```

This is what makes the `do`-notation example below assemble its error type bottom-up without you writing intermediate combined types.

### Type-ascription patterns

To match a row, use `(x : T)` — bind `x` and require the alternative to be `T`. The case must cover every alternative.

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

There is **no catch-all** (`_`) on a structural sum scrutinee. Either the case covers every alternative explicitly, or it's a compile error.

### Nominal alternatives in a row

A row can include a fully-applied nominal type as one of its alternatives. Constructor patterns are accepted _in the same case_ as type-ascription patterns:

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

Coverage is checked at two levels: every row alternative has to be covered, and for nominal alternatives every constructor has to appear; multiple `Just` arms together must in turn cover the inner row of `Maybe`'s argument.

### Implicit injection

A value of type `A` can flow into a position expecting `(A | B | …)` without an explicit wrapper. The compiler picks the matching alternative from the row.

```awsum
greet : (Int32 | String) -> String
greet x = case x of
  (n : Int32) -> "n=" ++ showInt32 n
  (s : String) -> "s=" ++ s

main : String -> IO Unit
main _input = IO.Stdout.print (greet "hello")  -- "hello" is a String, fits the row
```

Injection also works through nominal heads: a `Maybe Bool` value fits where `Maybe (Bool | Unit)` is expected, because the row sits inside `Maybe`'s argument position and `Bool` is one of its alternatives. The runtime carries a tag identifying the row label the value was constructed under (an FNV-1a hash of the label's canonical name), so the consumer's `case` dispatches correctly.

> **Row tag collision check.** Because the runtime tag is a 32-bit FNV-1a hash, two structurally distinct row labels could in principle hash to the same value and be confused at dispatch. The compiler enforces a *row tag collision check* during lowering: every row label in the program is hashed, and if two different labels share a tag the program is rejected with a `Row tag collision` diagnostic that names both labels. In hand-written code the chance of hitting a collision is vanishingly small (the hash is 32 bits wide); the check is a hard guard against adversarially-built names, not something you should expect to see in practice.

```awsum
-- ok: 'Just True' is constructed directly at the row-typed call
-- site, so the lowering wraps it with the matching row tags.
main : String -> IO Unit
main _input = IO.Stdout.print (whatsThat (Just True))
```

> **Caveat.** Implicit injection happens at the _construction site_. A value built in a non-row context (`Just True : Maybe Bool` bound as a top-level constant) cannot today flow into a row-expecting position later — the runtime representations differ. Construct directly where the row is expected, or use a small lift wrapper (`liftToRow x = case x of Nothing -> Nothing; Just b -> Just b`) whose return type is the row-typed `Maybe (Bool | Unit)` so the wrapping happens at lowering time. Cross-boundary normalisation is tracked as future work.

---

## Higher-order functions and `Either`

The prelude defines `Either a b = Left a | Right b` and a small set of helpers that use it as the error monad. Every `Either`-returning operation reports failure on the `Left` side; the success case is `Right`.

```awsum
predInt32 : Int32 -> Either UnderflowError Int32   -- in prelude

-- ok
example : Int32 -> String
example n = case predInt32 n of
  Left _e -> "underflow"
  Right m -> showInt32 m
```

### `bindEither` and row-polymorphic error types

The interesting trick is composing two `Either`-returning operations whose error types differ. The prelude provides:

```awsum
bindEither : Either e1 a -> (a -> Either e2 b) -> Either (e1 | e2) b
pureEither : a -> Either e a
mapRight : Either e a -> (a -> b) -> Either e b
mapLeft : Either e1 a -> (e1 -> e2) -> Either e2 a
```

`bindEither`'s result type unions the two error rows: chaining `op1` and `op2` produces `Either (e1 | e2) b`. Set-semantic union means duplicates collapse and order doesn't matter.

```awsum
type ErrorA = ErrorA
type ErrorB = ErrorB
type ErrorC = ErrorC

opA : Either ErrorA Int32
opA = Right 1

opB : Either (ErrorB | ErrorC) Int32
opB = Right 2

-- The composed error type is automatically '(ErrorA | ErrorB | ErrorC)'.
result : Either (ErrorA | ErrorB | ErrorC) Int32
result = bindEither opA (const opB)   -- 'const opB' ignores opA's success value
```

---

## `do`-notation

A `do` block is sugar for a chain of `bindEither` / `pureEither` calls. The desugaring is hard-coded to the `Either` shape — there is no type-class dispatch yet, and `do` only types against `Either e a`.

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

-- ok: each '<-' contributes its 'Left' type to the overall error
-- row; the final 'pureEither c' returns 'Right c'.
f : Either (ErrorA | ErrorB | ErrorC) Int32
f = do
  a <- op1
  b <- op2
  c <- op3
  pureEither c
```

### What's in scope inside a `do` block

- `<-` binds a name to the success value of an `Either`-returning expression. The right-hand side of `<-` must produce `Either e a`; any other type is rejected with `DoBindNonEither`.
- The block's final statement is an expression that produces the result. To return a plain value as `Right`, call `pureEither` from the prelude explicitly — there is no `pure` soft keyword in this iteration; once type classes land, `pure` will return as a polymorphic function rather than as a syntactic rewrite.
- Every block must end with an expression — a trailing `<-` or unfinished sentence is `DoBlockMissingResult`.

### Bound names threaded through subsequent statements

A bound name can be used by any later statement in the same `do`-block — the desugarer translates the dependency into a real lambda, which the lowering pass lifts to a top-level helper.

```awsum
op2WithA : Int32 -> Either ErrorB Int32
op2WithA n = Right n

-- ok: 'a' is used by 'op2WithA a' in the next statement; the
-- continuation lambda lifts to a fresh top-level helper.
g : Either (ErrorA | ErrorB) Int32
g = do
  a <- op1
  b <- op2WithA a
  pureEither b
```

### Today's restrictions

- `do` is hard-coded to `Either`. Other monad-like types are out of scope until type classes land.
- `let` inside `do` is reserved for a future iteration.
- Bind patterns are limited to `PVar` / `PWild` (a single name or `_`). Constructor and ascription patterns on the LHS of `<-` are not yet supported.

---

## What `do`-notation does _not_ yet do

Concretely, things planned for later iterations:

- Open-row tail variables `(A | B | r)` where `r` can be unioned with another open row at unification time. The current unifier handles the singleton case (a row variable absorbing a closed row), but not the symmetric "two open rows merge into one" case.
- `let` inside `do`. The parser accepts the `let` keyword for a future iteration; the typechecker rejects it.
- Lambdas that capture an outer-function parameter. The lifting pass produces a helper whose first arguments are the captured names, and the call site partial-applies the helper to those names — but the saturation pass does not yet support partial application with locally-captured arguments. A lambda whose body references only its own parameters (the typical do-block continuation shape) lifts cleanly.
- Type classes / dispatch. `pure`, `bindEither`, etc. are concrete prelude functions, not class methods. A `do` block over `Maybe` would need either a different desugar target or a real class system.

When a `do` block hits one of these, the diagnostic is the source of truth — it points at the offending construct and names the missing mechanism. Don't read this section as a list of bugs; read it as a list of decisions that haven't been made yet.

---

## How errors are reported

Every type error carries a span that points at the offending construct. The same diagnostic is shown by:

- `awsum check FILE` (human-readable, with carets);
- `awsum check --json FILE` (one JSON object per diagnostic, used by `awsum-vscode`);
- `awsum check --strict FILE` (escalates warnings to a non-zero exit status for CI).

There is no error suppression mechanism. The intent is that every error means something, and silencing it is always worse than fixing it.
