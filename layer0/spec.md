# Awsum layer0 Specification

## Introduction

### Purpose

`[spec.purpose]`

The Awsum layer0 language is the minimal language in which the first self-hosting Awsum compiler is written. This specification is normative for two implementations: the interpreter, written in C, and the compiler, written in Awsum layer0, together with its runtime. An implementation must behave exactly as described here. Anything this specification does not explicitly allow is forbidden. An implementation may deviate from it in one way only: a run may stop early when resources run out, [spec.resources].

### Terms

`[spec.terms]`

- A **static error** is detected before evaluation starts. The program does not run.
- A **dynamic error** occurs during evaluation and stops it immediately.
- A paragraph that starts with *Rationale* and a section named Example explain the text and add no requirements.
- Every section and every rule has an id, such as `[spec.locals.no-shadowing]`, written at its start. The implementations and the test cases refer to the rules by these ids.

### Notation

`[spec.notation]`

Grammars are written in the EBNF of ISO/IEC 14977 [[ISO 14977]], with juxtaposition instead of `,` for concatenation:

| Notation | Meaning |
| --- | --- |
| `A = … ;` | definition of rule `A` |
| `A B` | `A` followed by `B` |
| `A \| B` | `A` or `B` |
| `[ A ]` | `A` zero or one time |
| `{ A }` | `A` zero or more times |
| `( … )` | grouping |
| `"x"`, `'x'` | terminal; in single quotes when it is `"` |
| `? … ?` | described in words |

## Source Text

`[spec.source]`

### Bytes

`[spec.bytes]`

A program is a sequence of bytes. Outside string literals, [spec.string-literals], and comments, [spec.comments], only bytes 0x20–0x7E and line feed 0x0A are allowed. Any other byte in those places is a static error. In particular, tab and 0x0D are forbidden.

The bytes 0x20–0x7E are these characters, the first of them the space:

<!-- Each row starts at the code in its comment, and every column adds 1. -->

|   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |
| - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| <!-- 0x20 --> `␠` | `!` | `"` | `#` | `$` | `%` | `&` | `'` | `(` | `)` | `*` | `+` | `,` | `-` | `.` | `/` |
| <!-- 0x30 --> `0` | `1` | `2` | `3` | `4` | `5` | `6` | `7` | `8` | `9` | `:` | `;` | `<` | `=` | `>` | `?` |
| <!-- 0x40 --> `@` | `A` | `B` | `C` | `D` | `E` | `F` | `G` | `H` | `I` | `J` | `K` | `L` | `M` | `N` | `O` |
| <!-- 0x50 --> `P` | `Q` | `R` | `S` | `T` | `U` | `V` | `W` | `X` | `Y` | `Z` | `[` | `\` | `]` | `^` | `_` |
| <!-- 0x60 --> `` ` `` | `a` | `b` | `c` | `d` | `e` | `f` | `g` | `h` | `i` | `j` | `k` | `l` | `m` | `n` | `o` |
| <!-- 0x70 --> `p` | `q` | `r` | `s` | `t` | `u` | `v` | `w` | `x` | `y` | `z` | `{` | `\|` | `}` | `~` |   |

### Lines and Columns

`[spec.lines]`

Line feed 0x0A splits the text into lines, numbered from 1. A column is the index of a byte within its line, starting at 1. The position of a token is the line and column of its first byte. The first token on a line is called a **leading** token.

## Lexical Elements

`[spec.lexical]`

The text is split into tokens from left to right. At each step, the longest token that can be formed from the remaining text is taken. Spaces, line feeds and comments are not tokens.

### Comments

`[spec.comments]`

A comment is a `#` followed by a space, and extends up to, but not including, the next line feed. Any byte except 0x0A may appear in a comment after the space. A `#` immediately followed by a line feed or by the end of the text is an empty comment. A `#` followed by any other byte is a static error. There are no block comments. A `#` that is neither the first byte of its line nor follows a space is a static error, whatever byte follows it.

### Identifiers and Keywords

`[spec.identifiers]`

```
LowerIdent = lower { identTail } ;
UpperIdent = upper { identTail } ;
identTail  = lower | upper | digit | "_" | "'" ;
lower      = "a" | "b" | "c" | "d" | "e" | "f" | "g" | "h" | "i" | "j" | "k" | "l" | "m"
           | "n" | "o" | "p" | "q" | "r" | "s" | "t" | "u" | "v" | "w" | "x" | "y" | "z" ;
upper      = "A" | "B" | "C" | "D" | "E" | "F" | "G" | "H" | "I" | "J" | "K" | "L" | "M"
           | "N" | "O" | "P" | "Q" | "R" | "S" | "T" | "U" | "V" | "W" | "X" | "Y" | "Z" ;
digit      = "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" ;
```

The keywords `type`, `case`, `of`, `let` and `in` are not `LowerIdent`s.

In an identifier, an uppercase letter is never followed by another uppercase letter, so every uppercase letter begins a word: `HttpClient`, `Io`, `Uint8`, `Xaxis` and `parseJson`, not `HTTPClient`, `IO`, `UInt8`, `XAxis` and `parseJSON`. An identifier that breaks this rule is a static error.

*Rationale.* Uppercase letters that touch hide where a word begins: `HTTPServer` and `IOError` are read by guessing. When every uppercase letter begins a word, a name has one reading and a phrase one spelling.

### Integer Literals

`[spec.int-literals]`

```
Int = [ "-" ] digit { digit } ;
```

An integer literal is a number written in decimal. Its value is an `Int64`, [spec.values.int64], and must lie between −2^63 and 2^63 − 1 inclusive. Otherwise it is a static error. An integer literal whose first digit is `0` and has another digit after it is a static error, whatever its value, and so is `-0`.

*Rationale.* Every `Int64` has one spelling: `7`, not `007`, and `0`, not `-0`.

### Character Literals

`[spec.char-literals]`

```
Char     = "'" ( charByte | escape | "\'" ) "'" ;
charByte = ? a byte 0x20–0x7E other than "'" and "\" ? ;
escape   = "\" ( "n" | "t" | "r" | '"' | "\" | "0" ) ;
```

The value of a character literal is the code of its byte, an integer from 0 to 255. Escapes denote bytes: `\n` is 0x0A, `\t` is 0x09, `\r` is 0x0D, `\"` is 0x22, `\\` is 0x5C, `\0` is 0x00 and `\'` is 0x27.

### String Literals

`[spec.string-literals]`

```
String     = '"' { stringByte | escape } '"' ;
stringByte = ? a byte 0x20–0xFF other than '"' and "\" ? ;
```

The value of a string literal is the string of its bytes, with each escape replaced by the byte it denotes, [spec.char-literals]. Bytes 0x80–0xFF are taken as they are. UTF-8 validity is not checked.

### Symbols

`[spec.symbols]`

```
Symbol = "(" | ")" | "=" | "|" | "->" | ":" | "_" ;
```

A `_` immediately followed by an `identTail` byte is a static error. A `-` that does not start an `Int` or a `->` is a static error.

### Separation

`[spec.separation]`

A token that directly follows another token, with no space or line feed between them, is a static error, unless the token before it is `(` or the token itself is `)`. The error is detected at that token, once it has been read.

*Rationale.* Tokens set apart by spaces read more easily, and no text can be read in two ways.

## Layout

`[spec.layout]`

*Rationale.* The layout rule is taken from the offside rule of Landin [[Landin 1966]].

### Blocks

`[spec.blocks]`

A block is a sequence of items whose first tokens are aligned at one column, the **block column**.

- The whole program is a block with column 1. Its items are definitions, [spec.syntax].
- Each `case` expression opens a block of arms. The first arm must start with a leading token. The column of that token becomes the block column and must be greater than the column of the enclosing block. The block ends when the `case` expression ends.

### Leading Token Rule

`[spec.leading-token]`

Let B be the column of the innermost open block. A leading token at column c:

1. if c > B, continues the current item;
2. if c = B, starts the next item of the same block;
3. if c < B, closes the current block, and the rule is applied again to the enclosing block.

### End of an Expression

`[spec.expression-end]`

The sequence of atoms in an `App`, [spec.syntax], continues while the next token can start an `Atom` and is not a leading token at a column less than or equal to B. A token at which parsing cannot continue under these rules is a static error.

### Example

```
classify xs =
  case xs of
    Cons _ rest ->
      case rest of
        Nil -> "one"
        Cons _ _ -> "many"
    Nil -> "none"
```

The leading token `Nil` on the last line is at column 5, to the left of the arms of the inner `case` (column 9). It closes the inner block and, since it matches the column of the outer block, starts the next arm of the outer `case`.

## Syntax

`[spec.syntax]`

```
Program   = { Item } ;
Item      = TypeDecl | Signature | FunDef ;

TypeDecl  = "type" UpperIdent { LowerIdent } "=" ConDef { "|" ConDef } ;
ConDef    = UpperIdent { Field } ;
Field     = UpperIdent | LowerIdent | "(" Balanced ")" ;
Balanced  = ? any tokens in which parentheses are balanced ? ;
Signature = LowerIdent ":" Rest ;
Rest      = ? all tokens up to the end of the item, [spec.leading-token] ? ;
FunDef    = LowerIdent { Param } "=" Expr ;
Param     = LowerIdent | "_" ;

Expr      = Case | Let | App ;
Case      = "case" Expr "of" Arm { Arm } ;
Arm       = Pattern "->" Expr ;
Let       = "let" LowerIdent "=" Expr "in" Expr ;
App       = Atom { Atom } ;
Atom      = LowerIdent | UpperIdent | Int | Char | String | "(" Expr ")" ;

Pattern   = UpperIdent { PatAtom } | PatAtom ;
PatAtom   = "_" | LowerIdent | UpperIdent | Int | Char | String | "(" Pattern ")" ;
```

- `[spec.syntax.parentheses]` Parentheses only group: `( e )` means the same as `e`.
- `[spec.syntax.items]` An `Item` starts with a leading token at column 1. An `Arm` starts with a leading token at the block column of its `case`.

### Nesting Depth

`[spec.syntax.nesting]`

Expressions and patterns nest at most 1000 deep. The body of a `FunDef` is at depth 1, and an `Expr` or `Pattern` inside another one is one level deeper, including one in parentheses, in the body of a `Let` and in an `Arm`. Deeper nesting is a static error, detected at the first token of the first `Expr` or `Pattern` that is too deep.

*Rationale.* The limit on nesting lets an implementation parse and check a program by recursion within a 1 MiB stack, the default size of the main thread on Windows.

## Static Semantics

`[spec.static]`

Violating any rule in this section is a static error. When a program has several, [spec.check-order] says which one is reported.

### Namespaces

`[spec.namespaces]`

Function names (the `LowerIdent` of a `FunDef`) and builtin names, [spec.builtins], share one namespace. Constructor names form another. Type names and type parameter names have no effect.

### Definitions

`[spec.definitions]`

1. `[spec.definitions.functions]` A function name is defined at most once. Defining the name of a builtin is forbidden.
2. `[spec.definitions.constructors]` A constructor name is declared at most once in the whole program, counting the predeclared constructors, [spec.predeclared].
3. `[spec.definitions.skipped]` Of a `TypeDecl`, only the constructor names and their field counts matter. A `Signature` is skipped entirely.
4. `[spec.definitions.order]` Definition order does not matter: every function and every constructor is visible throughout the program.

### Local Names

`[spec.locals]`

1. `[spec.locals.scope]` Function parameters, pattern variables and `let` names are local names. The scope of a parameter is the function body, of a pattern variable the body of its arm, and of a `let` name the expression after `in`.
2. `[spec.locals.no-shadowing]` Shadowing is forbidden: a local name must differ from every name visible where it is declared, including functions and builtins.
3. `[spec.locals.distinct]` A name must not appear twice among the parameters of one function or within one pattern.
4. `[spec.locals.underscore]` `_` binds nothing and may appear any number of times.
5. `[spec.locals.known]` Every `LowerIdent` in an expression must denote a visible local name, a function or a builtin. Every `UpperIdent` in an expression or a pattern must denote a constructor.

### Argument Counts

`[spec.arity]`

1. `[spec.arity.constructors]` In a constructor application `C a1 … an` and in a pattern `C p1 … pn`, n equals the number of fields of `C`.
2. `[spec.arity.functions]` In an application `f a1 … an` of a function or builtin with k parameters, either n = k or n = 0.

### Entry Point

`[spec.entry]`

The program defines a function `main` with exactly one parameter.

## Values

`[spec.values]`

A value is one of:

1. `[spec.values.int64]` **An `Int64`:** a signed 64-bit integer, from −2^63 to 2^63 − 1, on every platform.
2. `[spec.values.string]` **A string:** a sequence of bytes of length 0 to 2^31 − 1.
3. `[spec.values.constructor]` **A value of a constructor:** the constructor name and the values of all its fields.
4. `[spec.values.function]` **A function value:** a reference to a top-level function that has parameters, or to a builtin.

`[spec.values.immutable]` All values are immutable.

*Rationale.* The limit on the length of a string comes from compiled code, which keeps the length in bytes in every string as a 32-bit number that shares one 8-byte word with the tag of the value, [compiler.cells].

### Predeclared Constructors

`[spec.predeclared]`

Every program behaves as if it contained these declarations:

```
type Bool = False | True
type List a = Nil | Cons a (List a)
```

A **list** is `Nil` or `Cons x xs`, where `xs` is a list. A **list of strings** is a list in which every `x` is a string.

## Dynamic Semantics

`[spec.eval]`

### Strictness and Order

`[spec.strictness]`

Evaluation is strict: the value of every subexpression is fully computed before it is used. Subexpressions are evaluated in the order described below and in no other order.

### Application

`[spec.application]`

An application `h a1 … an` is evaluated according to what `h` is:

1. `[spec.application.constructor]` **`h` is a constructor.** The arguments are evaluated left to right. The result is a value of constructor `h` whose fields are the values of the arguments.
2. `[spec.application.call]` **`h` is a function or a builtin, and n > 0.** The arguments are evaluated left to right, then the call is performed: the body of the function is evaluated with its parameters bound to the values of the arguments. For a builtin, [spec.builtins] defines the result.
3. `[spec.application.nullary]` **`h` is a function without parameters.** Its body is evaluated. Every reference evaluates the body anew.
4. `[spec.application.function-value]` **`h` is a function with parameters or a builtin, and n = 0.** The result is a function value referring to `h`.
5. `[spec.application.evaluated-head]` **`h` is anything else:** a local name, a literal, or an application, a `let` or a `case` in parentheses. First `h` is evaluated, then the arguments left to right. If n = 0, the result is the value of `h`. If n > 0, the value of `h` must be a function with exactly n parameters, otherwise it is a dynamic error. The call is then performed as in [spec.application.call].

### `let`

`[spec.let]`

`let x = e in body`: `e` is evaluated, `x` is bound to its value, then `body` is evaluated. The result is the value of `body`.

### `case`

`[spec.case]`

`case e of arm1 … armn`: `e` is evaluated. The arms are then matched against its value in order, [spec.patterns]. The result is the value of the body of the first matching arm, evaluated with the variables of its pattern bound. If no arm matches, it is a dynamic error.

### Pattern Matching

`[spec.patterns]`

A pattern matches a value v as follows:

1. `[spec.patterns.wildcard]` `_` matches any v.
2. `[spec.patterns.variable]` A variable matches any v and is bound to it.
3. `[spec.patterns.int]` An `Int` or a `Char` matches if v is an `Int64` equal to the value of the literal.
4. `[spec.patterns.string]` A `String` matches if v is a string whose bytes equal the bytes of the literal.
5. `[spec.patterns.constructor]` `C p1 … pn` matches if v is a value of constructor `C` and every field matches its pattern. Fields are checked left to right, and checking stops at the first field that does not match.

`[spec.patterns.mismatch]` Otherwise the pattern does not match. This is not an error, even when v could never match it: a string against `0`, an `Int64` against `Nil`.

### Resources

`[spec.resources]`

The language does not limit recursion depth or memory use. A run may stop early because the stack or the heap runs out: it then writes `stack overflow` or `out of memory`, [spec.messages], and exits with code 1. Where a run stops, and whether it stops at all, depends on the implementation and the machine; in every other respect the run follows this specification. In particular, a tail call is not promised constant stack: a loop written as tail recursion may run to its end or stop with `stack overflow`.

## Builtins

`[spec.builtins]`

In the table, a, b, i, from and to denote `Int64` values, except in `strEq`, where a and b denote strings. s and msg denote strings, and xs denotes a list of strings, [spec.predeclared]. An argument that does not match its denotation is a dynamic error. The arguments are checked from left to right, and the first that does not match is reported.

| Id | Builtin | Result | Dynamic error if |
| --- | --- | --- | --- |
| `[spec.builtins.add]` | `add a b` | a + b | the result is outside the range of `Int64` |
| `[spec.builtins.sub]` | `sub a b` | a − b | the result is outside the range of `Int64` |
| `[spec.builtins.mul]` | `mul a b` | a × b | the result is outside the range of `Int64` |
| `[spec.builtins.div]` | `div a b` | the quotient rounded toward zero | b = 0, or a = −2^63 and b = −1 |
| `[spec.builtins.rem]` | `rem a b` | a − b × q, where q is `div a b`; 0 when a = −2^63 and b = −1 | b = 0 |
| `[spec.builtins.eq]` | `eq a b` | `True` if a = b, otherwise `False` | — |
| `[spec.builtins.lt]` | `lt a b` | `True` if a < b, otherwise `False` | — |
| `[spec.builtins.str-len]` | `strLen s` | the length of s in bytes | — |
| `[spec.builtins.str-byte]` | `strByte s i` | the code of the byte of s at index i, an integer from 0 to 255 | i < 0 or i ≥ the length of s |
| `[spec.builtins.str-slice]` | `strSlice s from to` | the bytes of s at indices from to to − 1 | 0 ≤ from ≤ to ≤ the length of s does not hold |
| `[spec.builtins.str-eq]` | `strEq a b` | `True` if the bytes of a and b are equal, otherwise `False` | — |
| `[spec.builtins.str-join]` | `strJoin xs` | the strings of xs concatenated in order | the result is longer than 2^31 − 1 bytes |
| `[spec.builtins.str-from-byte]` | `strFromByte b` | a one-byte string containing b | b < 0 or b > 255 |
| `[spec.builtins.panic]` | `panic msg` | does not return | always, [spec.messages] |

*Rationale.* `div` and `rem` fail, as `add`, `sub` and `mul` do, exactly when the result does not exist or lies outside the range of `Int64`: the quotient of −2^63 by −1 is 2^63, while the remainder is 0.

## Running a Program

`[spec.run]`

### Running `main`

`[spec.run.main]` A program runs in these steps, whether the interpreter runs it or it is compiled:

1. All of stdin is read as one string s.
2. `main s` is evaluated.
3. The result must be a list of strings, otherwise it is a dynamic error.
4. The bytes of the strings of the result are written to stdout in order, without separators.

`[spec.run.io]` Input and output are binary: bytes are not re-encoded and line endings are not converted. Stdin is read to its end: when it has no data yet, as a pipe in non-blocking mode may, the run waits for the data. A program is a single file. If there are several source files, the build script concatenates them beforehand in a fixed order.

`[spec.run.length]` The program text and stdin are at most 2^31 − 1 bytes long each, the length of a string, [spec.values.string]. A longer program file or stdin is a failure to read it, [spec.exit-codes].

*Rationale.* A compiler written in Awsum reads the program text from stdin as a string, so it cannot take a longer text, and the interpreter is held to the same limit so that the two agree.

### Running the Interpreter

`[spec.run-interpreter]`

```
interpreter program.awsum < input > output
```

Here `interpreter` stands for any executable built from the interpreter's sources, such as `stage0-gcc`.

Source files have the extension `.awsum`. The interpreter does not check the extension.

`[spec.run-interpreter.steps]`

1. The interpreter reads the program from the file given as its only argument.
2. It checks the program for static errors, [spec.source] to [spec.static], as [spec.check-order] describes.
3. It runs the program, [spec.run.main].

### Order of Static Checks

`[spec.check-order]`

A program with several static errors reports one of them: the first that these checks find, made in this order.

1. The text is split into tokens, [spec.source], [spec.lexical], from left to right, up to the first error.
2. The tokens are parsed, [spec.layout], [spec.syntax], from left to right, up to the first error.
3. Constructor names, [spec.definitions.constructors]: the predeclared constructors, then those of the program in order. Each name is checked against the names before it.
4. Function names, [spec.definitions.functions], in program order. Each name is checked against the names of the functions before it, then against the builtins.
5. The entry point, [spec.entry].
6. The functions, in program order: the parameters of each from left to right, then its body. In an expression, the head of an application is checked before its arguments, which are checked from left to right; the value of a `let` before its name, and the name before the body; the scrutinee of a `case` before its arms, which are checked in order, each pattern before its body; the constructor of a pattern before its fields, which are checked from left to right.

*Rationale.* The value of a `let` is checked before its name, against the order of the text, because the name is not visible in the value, [spec.locals.scope].

### Exit Codes

`[spec.exit-codes]`

| Code | Cause |
| --- | --- |
| 0 | success |
| 1 | a dynamic error, including `panic`, or a run stopped early, [spec.resources] |
| 2 | a static error, wrong command-line arguments, or a failure to read the program file or stdin or to write stdout |

`[spec.exit-codes.empty-stdout]` When the exit code is not 0, stdout is empty, unless writing stdout itself failed.

### Error Messages

`[spec.messages]`

A message is written to stderr and ends with a line feed.

- `[spec.messages.static]` A static error message starts with the position of the token at which the error was detected, written as `line:column: `, [spec.lines].
- `[spec.messages.dynamic]` A dynamic error message starts with the position of the expression whose evaluation caused the error. When the result of `main` is not a list of strings, it is the position of the name in the definition of `main`.
- `[spec.messages.panic]` `panic msg` writes the bytes of msg without a prefix.
- `[spec.messages.plain]` Running out of memory or stack, wrong command-line arguments and failures to read or write are reported without a position.

### Compiled Programs

`[spec.compiled]`

`[spec.compiled.static-errors]` A compiler reports a static error, [spec.source] to [spec.static], itself: it writes the message of [spec.messages] for the error that [spec.check-order] picks, writes nothing to stdout and exits with code 1.

*Rationale.* A compiler written in Awsum layer0 can stop only through `panic`, which exits with code 1.

`[spec.compiled.run]` A compiled program runs as [spec.run.main] describes, and [spec.exit-codes] and [spec.messages] apply to it. Of the causes of exit code 2, only a failure to read stdin or to write stdout can occur.

## Implementation Requirements

`[spec.requirements]`

- `[spec.requirements.linear-checks]` Checking a program for static errors takes time linear in the size of the program.
- `[spec.requirements.portable]` What a program writes and its exit code depend neither on the platform it runs on nor on whether it is interpreted or compiled, and neither do the static errors a compiler reports. The one exception is a run stopped early, [spec.resources].
- `[spec.requirements.reproducible]` The code a compiler emits depends only on the program: not on the operating system, the processor, the C compiler, the LLVM version or the C library of the host, nor on the environment, the time or the run.

## Example

```
# Prints the length of the input in bytes.
main input = Cons (showNat (strLen input)) (Cons "\n" Nil)

showNat : Int64 -> String
showNat n =
  case lt n 10 of
    True -> digit n
    False -> strJoin (Cons (showNat (div n 10)) (Cons (digit (rem n 10)) Nil))

digit d = strFromByte (add '0' d)
```

## References

- [ISO 14977] ISO/IEC 14977:1996, *Information technology — Syntactic metalanguage — Extended BNF*.
- [Landin 1966] P. J. Landin, "The next 700 programming languages", *Communications of the ACM* 9(3), 157–166, 1966.

[ISO 14977]: https://standards.iso.org/ittf/PubliclyAvailableStandards/s026153_ISO_IEC_14977_1996(E).zip
[Landin 1966]: https://doi.org/10.1145/365230.365257
