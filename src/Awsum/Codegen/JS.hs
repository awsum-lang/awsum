-- | JavaScript code generator for Awsum 'Core'.
--
-- Design goals:
--   • Emit small, readable JS that is easy to snapshot-test.
--   • Keep a tiny "runtime" in 'header' only for what we actually need.
--   • Preserve Core invariants: primitives only appear in callee position.
--
-- Semantics & assumptions:
--   • Strings: we rely on JS '+' to concatenate (both operands are statically 'String').
--   • Zero-arg surface defs are lowered to Core 'CValDef' and become JS 'const' values.
--     Functions remain 'function' declarations (hoisted), so call order is safe.
--   • Wrapping is selected by 'ProgramType':
--
--       - 'ProgramCli' → IIFE (@(function () { ... })()@). Inside a
--         function scope, top-level @function@ declarations don't
--         become @window.x@ and top-level @const@/@let@ are lexical,
--         so nothing leaks to the global object — whether loaded as a
--         classic @<script>@ or via Node's CommonJS wrapper. The Node
--         runner in the footer still sees @require@/@module@ via
--         closure.
--
--     No module-table indirection: function hoisting inside the IIFE
--     makes declaration order irrelevant.
--
--     Other program types (browser module, CommonJS, ESM) will pick
--     different wrappers without changing the name-emission rules below.
module Awsum.Codegen.JS (codegenJS) where

import Awsum.Core
import Awsum.HM (rowTag)
import Awsum.Program (ProgramType (..))
import Awsum.Syntax (Name, Type' (..), noSpan)
import Data.Char qualified as Char
import Data.Set qualified as Set
import Data.Text qualified as T
import Relude

-- | Produce a complete JS file. The wrapping strategy is selected by the
--   program type; the inner name-emission rules are shared.
codegenJS :: ProgramType -> CoreProgram -> Text
codegenJS = \case
  ProgramCli -> emitCliScript

-- | CLI script: IIFE-wrapped, with a Node runner inside. Nothing leaks
--   to the global object — neither function declarations (hoisted onto
--   @window@ only at /script/ top level, not inside an IIFE) nor
--   @const@/@let@ (lexically script-scoped).
emitCliScript :: CoreProgram -> Text
emitCliScript prog@(CoreProgram decls) =
  T.intercalate
    "\n"
    [ "\"use strict\";",
      "(function () {",
      header (usedBuiltIns prog),
      T.intercalate "\n\n" (map emitDecl decls),
      cliFooter,
      "})();"
    ]

-- | Minimal runtime, tree-shaken: only helpers whose primitive / built-in
--   is actually referenced from Core are emitted.
--   • '__print' writes without a newline (Awsum's 'IO.Stdout.print' is "print exactly").
--   • '__concat' is a tiny helper that wraps native '+' with the
--     language-fixed length cap (see 'BuiltIn.concatString'); inlining
--     '+' at each site would duplicate the cap check inline at every '++'.
--   Integer stringification doesn't need a helper; @String(x)@ is
--   inlined at each show call site.
header :: Set Name -> Text
header builtIns =
  let -- FNV-1a 32-bit row tags for the prelude's nominal labels used
      -- by the Int32 arithmetic builtins. Hard-wiring them via
      -- 'rowTag' here (instead of a magic number) keeps the encoding
      -- in lockstep with 'Awsum.HM.canonicalLabel' / 'Awsum.HM.fnv1a32'
      -- if either ever changes — the runtime helpers and the
      -- user-side row dispatch agree by construction, not by accident.
      underflowTag = rowTag (TyCon noSpan "UnderflowError")
      overflowTag = rowTag (TyCon noSpan "OverflowError")
      stringTooLongTag = rowTag (TyCon noSpan "StringTooLong")
      unpairedSurrogateTag = rowTag (TyCon noSpan "UnpairedUtf16Surrogate")
      lns =
        filter
          (not . T.null)
          [ -- '__print' writes a string to stdout (no newline) and
            -- returns the Unit constructor `[0]`. Driven by the
            -- prelude's `runIO` walking an 'IOStdoutPrint' arm via
            -- `BuiltIn.internalStdoutPrint`. Returning a real Unit
            -- value lets the prelude `case … of Unit -> next`
            -- dispatch through the standard CCase tag check.
            if Set.member "internalStdoutPrint" builtIns
              then "function __print(s){ process.stdout.write(String(s)); return [0]; }"
              else "",
            -- predInt32: returns Left UnderflowError on INT32_MIN, else Right (x - 1).
            -- Left=0, Right=1, UnderflowError=0 — matches user-code tag assignment
            -- for `type Either a b = Left a | Right b` and `type UnderflowError = UnderflowError`.
            if Set.member "predInt32" builtIns
              then "function __predInt32(x){ return x === -2147483648 ? [0, [0]] : [1, ((x - 1)|0)]; }"
              else "",
            -- predUInt8: returns Left UnderflowError on 0, else Right (x - 1).
            -- When x >= 1, (x - 1) is in 0..254, so no explicit mask is
            -- needed to stay in UInt8 range — but we keep '& 0xFF' for
            -- parallel structure with other UInt8 arithmetic helpers.
            if Set.member "predUInt8" builtIns
              then "function __predUInt8(x){ return x === 0 ? [0, [0]] : [1, ((x - 1) & 0xFF)]; }"
              else "",
            -- succInt32: returns Left OverflowError on INT32_MAX, else Right (x + 1).
            -- Left=0, Right=1, OverflowError=0 — tag assignment mirrors
            -- __predInt32 since both error types are single-constructor.
            if Set.member "succInt32" builtIns
              then "function __succInt32(x){ return x === 2147483647 ? [0, [0]] : [1, ((x + 1)|0)]; }"
              else "",
            -- succUInt8: returns Left OverflowError on 255, else Right (x + 1).
            -- '& 0xFF' kept for parallel structure with __predUInt8.
            if Set.member "succUInt8" builtIns
              then "function __succUInt8(x){ return x === 255 ? [0, [0]] : [1, ((x + 1) & 0xFF)]; }"
              else "",
            -- eqInt32 / eqUInt8: True=0, False=1 for `type Bool = True | False`.
            -- Both incoming values are already '|0' / '& 0xFF' coerced, so '===' on
            -- the JS Numbers gives the same answer as native i32/u8 equality.
            if Set.member "eqInt32" builtIns
              then "function __eqInt32(a, b){ return a === b ? [0] : [1]; }"
              else "",
            if Set.member "eqUInt8" builtIns
              then "function __eqUInt8(a, b){ return a === b ? [0] : [1]; }"
              else "",
            -- addInt32: Either (UnderflowError | OverflowError) Int32. JS
            -- numbers exactly represent the 33-bit sum of two i32s, so the
            -- range checks are direct without intermediate '|0' wrapping.
            -- The error side is a structural sum dispatched at runtime by
            -- FNV-1a row tags; the encoded shape is
            --   Left UnderflowError = [0, [tagU, [0]]]
            --   Left OverflowError  = [0, [tagO, [0]]]
            -- where the inner '[0]' is the nullary CCon for the
            -- single-constructor type and 'tagU' / 'tagO' are
            -- 'rowTag (TyCon "UnderflowError")' / 'rowTag (TyCon "OverflowError")'.
            if Set.member "addInt32" builtIns
              then "function __addInt32(a, b){ const s = a + b; if (s > 2147483647) return [0, [" <> show overflowTag <> ", [0]]]; if (s < -2147483648) return [0, [" <> show underflowTag <> ", [0]]]; return [1, s|0]; }"
              else "",
            -- subInt32: Either (UnderflowError | OverflowError) Int32. Same
            -- range-check shape as __addInt32 — the i32 difference fits in
            -- a JS Number exactly, so direct '> maxInt32' / '< minInt32'
            -- tests pick the branch. Same row-tagged error encoding.
            if Set.member "subInt32" builtIns
              then "function __subInt32(a, b){ const d = a - b; if (d > 2147483647) return [0, [" <> show overflowTag <> ", [0]]]; if (d < -2147483648) return [0, [" <> show underflowTag <> ", [0]]]; return [1, d|0]; }"
              else "",
            -- mulInt32: Either (UnderflowError | OverflowError) Int32. JS
            -- Numbers represent the product of two i32 values exactly (it
            -- fits in 53-bit mantissa precision, max product is ~2^62).
            -- Direct range check on the exact product picks the branch;
            -- '|0' coerces back to i32 on the ok path. Same row-tagged
            -- error encoding as add/sub.
            if Set.member "mulInt32" builtIns
              then "function __mulInt32(a, b){ const p = a * b; if (p > 2147483647) return [0, [" <> show overflowTag <> ", [0]]]; if (p < -2147483648) return [0, [" <> show underflowTag <> ", [0]]]; return [1, p|0]; }"
              else "",
            -- negInt32: Either OverflowError Int32. Only INT32_MIN overflows
            -- (negation would yield 2147483648, outside the signed range);
            -- every other value flips sign cleanly inside JS Number precision.
            if Set.member "negInt32" builtIns
              then "function __negInt32(x){ return x === -2147483648 ? [0, [0]] : [1, ((-x)|0)]; }"
              else "",
            -- addUInt8: Either OverflowError UInt8. Both inputs in 0..255,
            -- so the unmasked sum is in 0..510 and a single '> 255' check
            -- separates the branches.
            if Set.member "addUInt8" builtIns
              then "function __addUInt8(a, b){ const s = a + b; return s > 255 ? [0, [0]] : [1, s & 0xFF]; }"
              else "",
            -- subUInt8: Either UnderflowError UInt8. Both inputs in 0..255,
            -- so the difference is in -255..255; a single '< 0' check picks
            -- the underflow branch. The ok-path mask keeps parallel structure
            -- with __addUInt8 (the difference is already in 0..255 there).
            if Set.member "subUInt8" builtIns
              then "function __subUInt8(a, b){ const d = a - b; return d < 0 ? [0, [0]] : [1, d & 0xFF]; }"
              else "",
            -- mulUInt8: Either OverflowError UInt8. Both inputs in 0..255,
            -- so the unmasked product is in 0..65025 — well within JS Number
            -- precision and the i32 range that '|0' would coerce to. A
            -- single '> 255' check picks the overflow branch.
            if Set.member "mulUInt8" builtIns
              then "function __mulUInt8(a, b){ const p = a * b; return p > 255 ? [0, [0]] : [1, p & 0xFF]; }"
              else "",
            -- concatString: implements 'BuiltIn.concatString'. Pre-checks
            -- the combined UTF-16 length against the language-fixed cap
            -- (134217728 = 2^27, must stay in sync with
            -- 'maxStringLengthUtf16CodeUnits' in 'stdlib/Prelude.aww').
            -- JS String.length is UTF-16 code units exactly (matches the
            -- cap unit directly), so the check is one i32 comparison.
            -- Encoding: Left=0, Right=1, StringTooLong=0 (single ctor).
            if Set.member "concatString" builtIns
              then "function __concat(a, b){ return (a.length + b.length > 134217728) ? [0, [0]] : [1, a + b]; }"
              else "",
            -- splitOnFirst: 'indexOf("")' returns 0 in JS, so empty separator
            -- naturally yields ["", str]. 'substring' creates fresh strings
            -- (V8 sometimes shares storage internally — irrelevant at the
            -- semantic level we observe). Tags: Maybe Nothing=0, Just=1;
            -- Tuple2 has one constructor (tag 0).
            if Set.member "splitOnFirst" builtIns
              then "function __splitOnFirst(sep, str){ const i = str.indexOf(sep); if (i < 0) return [0]; return [1, [0, str.substring(0, i), str.substring(i + sep.length)]]; }"
              else "",
            -- parseInt32: strict decimal grammar mirroring the language
            -- literal — optional '-', one or more ASCII digits, nothing else.
            -- Regex full-match enforces it; Number() then range-checks. JS
            -- numbers are double-precision and represent every i32 (and the
            -- absolute minInt32 boundary 2147483648) exactly.
            if Set.member "parseInt32" builtIns
              then "function __parseInt32(s){ if (!/^-?[0-9]+$/.test(s)) return [0, [0]]; const n = Number(s); if (n < -2147483648 || n > 2147483647) return [0, [0]]; return [1, n | 0]; }"
              else "",
            -- parseUInt8: same shape but no sign accepted; range 0..255.
            if Set.member "parseUInt8" builtIns
              then "function __parseUInt8(s){ if (!/^[0-9]+$/.test(s)) return [0, [0]]; const n = Number(s); if (n > 255) return [0, [0]]; return [1, n & 0xFF]; }"
              else "",
            -- predUInt32: returns Left UnderflowError on 0, else Right (x - 1).
            -- '>>> 0' coerces to unsigned 32-bit (where '|0' would give signed).
            if Set.member "predUInt32" builtIns
              then "function __predUInt32(x){ return x === 0 ? [0, [0]] : [1, ((x - 1) >>> 0)]; }"
              else "",
            -- succUInt32: returns Left OverflowError on 4294967295, else Right (x + 1).
            if Set.member "succUInt32" builtIns
              then "function __succUInt32(x){ return x === 4294967295 ? [0, [0]] : [1, ((x + 1) >>> 0)]; }"
              else "",
            -- eqUInt32: identical shape to eqInt32 — both inputs are already
            -- '>>> 0' coerced so '===' on JS Numbers gives native u32 equality.
            if Set.member "eqUInt32" builtIns
              then "function __eqUInt32(a, b){ return a === b ? [0] : [1]; }"
              else "",
            -- addUInt32: Either OverflowError UInt32. JS Numbers exactly
            -- represent the unmasked sum of two u32s (max ~2^33), so a
            -- direct '> 4294967295' check separates the branches.
            if Set.member "addUInt32" builtIns
              then "function __addUInt32(a, b){ const s = a + b; return s > 4294967295 ? [0, [0]] : [1, (s >>> 0)]; }"
              else "",
            -- subUInt32: Either UnderflowError UInt32. Difference is in
            -- -4294967295..4294967295; '< 0' picks the underflow branch.
            if Set.member "subUInt32" builtIns
              then "function __subUInt32(a, b){ const d = a - b; return d < 0 ? [0, [0]] : [1, (d >>> 0)]; }"
              else "",
            -- mulUInt32: Either OverflowError UInt32. Product of two u32
            -- values is at most ~2^64; JS Numbers only have 53-bit
            -- precision so we use BigInt to compute the exact product,
            -- then range-check before coercing back.
            if Set.member "mulUInt32" builtIns
              then "function __mulUInt32(a, b){ const p = BigInt(a) * BigInt(b); return p > 4294967295n ? [0, [0]] : [1, (Number(p) >>> 0)]; }"
              else "",
            -- parseUInt32: same grammar as parseUInt8 — no sign, decimal
            -- digits only — range 0..4294967295. JS Numbers represent
            -- 4294967295 exactly, so direct '> 4294967295' is faithful.
            if Set.member "parseUInt32" builtIns
              then "function __parseUInt32(s){ if (!/^[0-9]+$/.test(s)) return [0, [0]]; const n = Number(s); if (n > 4294967295) return [0, [0]]; return [1, (n >>> 0)]; }"
              else "",
            -- lengthCodePoints: spread iteration walks the string by code
            -- point — the JS string iterator yields a surrogate pair as a
            -- single two-char element, so '[...s].length' gives the USV count.
            -- The cached UTF-16 'length' would over-count supplementary chars.
            if Set.member "lengthCodePoints" builtIns
              then "function __lengthCodePoints(s){ let n = 0; for (const _ of s) n++; return (n >>> 0); }"
              else "",
            -- lengthUtf16CodeUnits: native JS string length is the UTF-16
            -- code-unit count by spec — surrogate pairs contribute 2.
            if Set.member "lengthUtf16CodeUnits" builtIns
              then "function __lengthUtf16CodeUnits(s){ return (s.length >>> 0); }"
              else "",
            -- lengthUtf8Bytes: TextEncoder always uses standard (not
            -- modified) UTF-8 — 1 byte for ASCII, 2 for U+0080..U+07FF,
            -- 3 for U+0800..U+FFFF, 4 for U+10000..U+10FFFF.
            -- Allocating one encoder per call keeps the helper stateless;
            -- benchmarks haven't motivated hoisting it.
            if Set.member "lengthUtf8Bytes" builtIns
              then "function __lengthUtf8Bytes(s){ return (new TextEncoder().encode(s).length >>> 0); }"
              else "",
            -- __entryArgEither: wraps argv[1] in 'Either (StringTooLong |
            -- UnpairedUtf16Surrogate) String' for the user's 'main'. Two
            -- checks in one helper:
            --   1. Length cap: JS String.length is UTF-16 code units
            --      exactly; cap test is a single i32 compare.
            --   2. Surrogate pairing: walk code units, reject if any high
            --      surrogate (D800..DBFF) is not immediately followed by
            --      a low surrogate (DC00..DFFF), or any low surrogate has
            --      no preceding high. JS strings allow unpaired surrogates
            --      at the language level — Awsum 'String' is strict UTF-16,
            --      so the boundary validates.
            -- Cap value (134217728 = 2^27) and FNV-1a row tags for
            -- "StringTooLong" / "UnpairedUtf16Surrogate" must stay in sync
            -- with 'maxStringLengthUtf16CodeUnits' in 'stdlib/Prelude.aww'.
            -- Encoding mirrors the other backends: Right=[1, arg];
            -- Left=[0, [rowTag, [0]]] — three layers (inner CCon, row
            -- wrap, Left).
            "function __entryArgEither(arg){ if (arg.length > 134217728) return [0, [" <> show stringTooLongTag <> ", [0]]]; for (let i = 0; i < arg.length; i++) { const c = arg.charCodeAt(i); if (c >= 0xD800 && c <= 0xDBFF) { if (i + 1 >= arg.length) return [0, [" <> show unpairedSurrogateTag <> ", [0]]]; const next = arg.charCodeAt(i + 1); if (next < 0xDC00 || next > 0xDFFF) return [0, [" <> show unpairedSurrogateTag <> ", [0]]]; i++; } else if (c >= 0xDC00 && c <= 0xDFFF) return [0, [" <> show unpairedSurrogateTag <> ", [0]]]; } return [1, arg]; }"
          ]
   in T.intercalate "\n" lns <> "\n"

-- | Node-only convenience runner for CLI scripts:
--   when run as a script (not @require@-d), call @main@ with a single
--   command-line argument (or empty string). Works inside the IIFE
--   because @require@/@module@ are closed over from Node's module wrapper.
cliFooter :: Text
cliFooter =
  unlines
    [ "",
      "if (typeof require !== 'undefined' && require.main === module) {",
      "  const arg = process.argv[2] ?? \"\";",
      -- Wrap input in 'Either (StringTooLong | …) String' before handing to
      -- user's main. '__entryArgEither' compares 'arg.length' against the
      -- language-fixed cap and returns either 'Right arg' or row-tagged
      -- 'Left StringTooLong'. The IO tree from main is walked by 'runIO'
      -- (defined in the prelude as a regular Awsum function) which performs
      -- any effects via 'BuiltIn.internalStdoutPrint'.
      "  if (typeof main === 'function') v_runIO(main(__entryArgEither(arg)));",
      "}"
    ]

-- | Top-level declarations:
--   • 'CFunDef' with 'CLoop' body (output of the TCO pass) → 'while (true)'
--     loop whose body is emitted in statement form so 'CContinue' can
--     rebind the function's parameters and 'continue' the loop instead of
--     recursing. Rewriting a self-tail-call as a jump keeps the JS engine's
--     call stack bounded, which matters on Node/V8 because ES2015 PTC was
--     never shipped.
--   • 'CFunDef' without 'CLoop' → also statement form. A 'CCase' in tail
--     position becomes a 'switch' whose arms 'return' directly, instead of
--     an IIFE. That keeps deeply nested pattern matches (N nested 'case'
--     expressions in tail position) inside a single stack frame; the IIFE
--     form would burn one frame per level and overflow on platforms with
--     small default stacks (e.g. Windows Node ≈512 KB).
--   • 'CValDef' → 'const name = <expr>;'.
emitDecl :: CDecl -> Text
emitDecl = \case
  CFunDef nm args (CLoop body) ->
    "function "
      <> mangle nm
      <> "("
      <> T.intercalate ", " (map mangle args)
      <> "){\n"
      <> "  while (true) {\n"
      <> emitStmt args body
      <> "  }\n"
      <> "}"
  CFunDef nm args body ->
    "function "
      <> mangle nm
      <> "("
      <> T.intercalate ", " (map mangle args)
      <> "){\n"
      <> emitStmt args body
      <> "}"
  CValDef nm rhs ->
    "const " <> mangle nm <> " = " <> emitExpr rhs <> ";"

-- | Emit an expression in /statement form/ for use inside a 'while (true)'
-- loop introduced by 'CLoop':
--   • 'CContinue' rebinds the function's parameters and jumps back to the
--     loop head. Continue args are evaluated into temporaries first so a
--     new value that reads old params (e.g. @acc + "."@) sees the old
--     binding, not a half-updated one.
--   • 'CCase' dispatches through @switch@ and recurses into statement form
--     for each arm's body, because any arm might itself be a 'CContinue'.
--   • Anything else is a final value — we return it.
emitStmt :: [Name] -> CExpr -> Text
emitStmt params = go
  where
    go :: CExpr -> Text
    go = \case
      CContinue newArgs ->
        let temps = ["__t" <> show (i :: Int) | i <- [0 .. length newArgs - 1]]
            declLines =
              [ "    const " <> t <> " = " <> emitExpr a <> ";"
              | (t, a) <- zip temps newArgs
              ]
            assignLines =
              [ "    " <> mangle p <> " = " <> t <> ";"
              | (p, t) <- zip params temps
              ]
         in unlines (declLines <> assignLines <> ["    continue;"])
      CCase scrut alts ->
        "    {\n      const __s = "
          <> emitExpr scrut
          <> ";\n      switch (__s[0]) {\n"
          <> T.concat (map emitStmtAlt alts)
          <> "      }\n    }\n"
      CRowCase scrut alts ->
        "    {\n      const __s = "
          <> emitExpr scrut
          <> ";\n      switch (__s[0]) {\n"
          <> T.concat (map emitStmtRowAlt alts)
          <> "      }\n    }\n"
      e ->
        "    return " <> emitExpr e <> ";\n"

    emitStmtAlt :: (Int, [Name], CExpr) -> Text
    emitStmtAlt (tag, vars, body) =
      let bindings =
            T.concat
              [ "          const " <> mangle v <> " = __s[" <> show (i :: Int) <> "];\n"
              | (v, i) <- zip vars [1 ..]
              ]
       in "        case "
            <> show tag
            <> ": {\n"
            <> bindings
            <> reindentStmt (emitStmt params body)
            <> "        }\n"

    emitStmtRowAlt :: (Word32, Name, CExpr) -> Text
    emitStmtRowAlt (tag, var, body) =
      "        case "
        <> show tag
        <> ": {\n"
        <> "          const "
        <> mangle var
        <> " = __s[1];\n"
        <> reindentStmt (emitStmt params body)
        <> "        }\n"

    -- 'emitStmt' produces lines indented for @while (true)@ depth (4 spaces).
    -- Inside a @case@ we want them two levels deeper (10 spaces), so bump
    -- each non-empty line by 6 spaces without touching blank ones.
    reindentStmt :: Text -> Text
    reindentStmt = unlines . map bump . lines
      where
        bump l = if T.null (T.strip l) then l else "      " <> l

-- | Expressions:
--   • 'CBuiltIn' is never a standalone value — it only appears in the callee of 'CCall'.
--   • 'IO.Stdout.print' turns into '__print(x)'.
--   • 'BuiltIn.concatString' turns into '(a + b)'.
--   • Generic calls: '(callee)(args...)' — we parenthesize the callee to be safe.
emitExpr :: CExpr -> Text
emitExpr = \case
  CString s -> jsString s
  CVar n -> mangle n
  -- Int32: coerce to signed 32-bit via '|0' so later operations match semantics.
  -- UInt8: mask to 0..255 range so it behaves like the declared type, not a
  -- free-floating JS Number.
  CIntLit n TInt32 -> "(" <> show n <> "|0)"
  CIntLit n TUInt8 -> "(" <> show n <> " & 0xFF)"
  -- UInt32: '>>> 0' coerces to unsigned 32-bit so values up to
  -- 4294967295 are preserved (where '|0' would wrap them to signed).
  CIntLit n TUInt32 -> "(" <> show n <> " >>> 0)"
  CBuiltIn n -> "/*<builtin " <> n <> ">*/" -- invariant: not a standalone term
  CCon tag fields ->
    "[" <> T.intercalate ", " (show tag : map emitExpr fields) <> "]"
  -- Row-tagged value: same `[tag, value]` array layout as a one-field
  -- 'CCon', so a single 'switch (s[0])' shape serves both kinds of
  -- dispatch. Hash tags are 32-bit while constructor tags are small
  -- non-negative integers, so the two namespaces don't collide in
  -- practice.
  CRow tag v ->
    "[" <> show tag <> ", " <> emitExpr v <> "]"
  CCase scrut alts ->
    "((s) => { switch(s[0]) { "
      <> T.intercalate " " (map emitAlt alts)
      <> " } })("
      <> emitExpr scrut
      <> ")"
  CRowCase scrut alts ->
    "((s) => { switch(s[0]) { "
      <> T.intercalate " " (map emitRowAlt alts)
      <> " } })("
      <> emitExpr scrut
      <> ")"
  CCall f xs ->
    case f of
      -- Internal print primitive used by the prelude's `runIO`. Returns
      -- the Unit constructor `[0]` so the surrounding `case … of Unit ->
      -- next` arm dispatches through the standard tag check. Not exposed
      -- to user code (no prelude alias); this is a privileged channel
      -- between `runIO` and the host stdout.
      CBuiltIn "internalStdoutPrint" ->
        case xs of
          [x] -> "__print(" <> emitExpr x <> ")"
          _ -> error "__print: arity mismatch"
      CBuiltIn name
        | name == "showInt32" || name == "showUInt8" || name == "showUInt32" ->
            case xs of
              [x] -> "String(" <> emitExpr x <> ")"
              _ -> error ("BuiltIn." <> name <> ": arity mismatch")
      CBuiltIn "predInt32" ->
        case xs of
          [x] -> "__predInt32(" <> emitExpr x <> ")"
          _ -> error "BuiltIn.predInt32: arity mismatch"
      CBuiltIn "predUInt8" ->
        case xs of
          [x] -> "__predUInt8(" <> emitExpr x <> ")"
          _ -> error "BuiltIn.predUInt8: arity mismatch"
      CBuiltIn "predUInt32" ->
        case xs of
          [x] -> "__predUInt32(" <> emitExpr x <> ")"
          _ -> error "BuiltIn.predUInt32: arity mismatch"
      CBuiltIn "succInt32" ->
        case xs of
          [x] -> "__succInt32(" <> emitExpr x <> ")"
          _ -> error "BuiltIn.succInt32: arity mismatch"
      CBuiltIn "succUInt8" ->
        case xs of
          [x] -> "__succUInt8(" <> emitExpr x <> ")"
          _ -> error "BuiltIn.succUInt8: arity mismatch"
      CBuiltIn "succUInt32" ->
        case xs of
          [x] -> "__succUInt32(" <> emitExpr x <> ")"
          _ -> error "BuiltIn.succUInt32: arity mismatch"
      CBuiltIn name
        | name == "eqInt32" || name == "eqUInt8" || name == "eqUInt32" ->
            case xs of
              [a, b] ->
                let fn = case name of
                      "eqInt32" -> "__eqInt32"
                      "eqUInt8" -> "__eqUInt8"
                      _ -> "__eqUInt32"
                 in fn <> "(" <> emitExpr a <> ", " <> emitExpr b <> ")"
              _ -> error ("BuiltIn." <> name <> ": arity mismatch")
      CBuiltIn name
        | name == "addInt32" || name == "addUInt8" || name == "addUInt32" || name == "subInt32" || name == "subUInt8" || name == "subUInt32" || name == "mulUInt8" || name == "mulUInt32" || name == "mulInt32" ->
            case xs of
              [a, b] ->
                let fn = case name of
                      "addInt32" -> "__addInt32"
                      "addUInt8" -> "__addUInt8"
                      "addUInt32" -> "__addUInt32"
                      "subInt32" -> "__subInt32"
                      "subUInt8" -> "__subUInt8"
                      "subUInt32" -> "__subUInt32"
                      "mulInt32" -> "__mulInt32"
                      "mulUInt32" -> "__mulUInt32"
                      _ -> "__mulUInt8"
                 in fn <> "(" <> emitExpr a <> ", " <> emitExpr b <> ")"
              _ -> error ("BuiltIn." <> name <> ": arity mismatch")
      CBuiltIn "negInt32" ->
        case xs of
          [x] -> "__negInt32(" <> emitExpr x <> ")"
          _ -> error "BuiltIn.negInt32: arity mismatch"
      CBuiltIn "concatString" ->
        case xs of
          [a, b] -> "__concat(" <> emitExpr a <> ", " <> emitExpr b <> ")"
          _ -> error "BuiltIn.concatString: arity mismatch"
      CBuiltIn "splitOnFirst" ->
        case xs of
          [a, b] -> "__splitOnFirst(" <> emitExpr a <> ", " <> emitExpr b <> ")"
          _ -> error "BuiltIn.splitOnFirst: arity mismatch"
      CBuiltIn name
        | name == "parseInt32" || name == "parseUInt8" || name == "parseUInt32" ->
            case xs of
              [a] ->
                let fn = case name of
                      "parseInt32" -> "__parseInt32"
                      "parseUInt8" -> "__parseUInt8"
                      _ -> "__parseUInt32"
                 in fn <> "(" <> emitExpr a <> ")"
              _ -> error ("BuiltIn." <> name <> ": arity mismatch")
      CBuiltIn name
        | name == "lengthCodePoints" || name == "lengthUtf16CodeUnits" || name == "lengthUtf8Bytes" ->
            case xs of
              [a] ->
                let fn = case name of
                      "lengthCodePoints" -> "__lengthCodePoints"
                      "lengthUtf16CodeUnits" -> "__lengthUtf16CodeUnits"
                      _ -> "__lengthUtf8Bytes"
                 in fn <> "(" <> emitExpr a <> ")"
              _ -> error ("BuiltIn." <> name <> ": arity mismatch")
      CBuiltIn n ->
        error ("JS codegen: unknown builtin '" <> n <> "' reached CCall (typecheck should have rejected it)")
      _ ->
        "(" <> emitExpr f <> ")(" <> T.intercalate ", " (map emitExpr xs) <> ")"
  -- 'untcoProgram' strips these before emission. Reaching them signals a
  -- pipeline misorder (TCO ran but its inverse didn't), so crash loudly.
  CLoop _ -> error "JS codegen: CLoop survived untcoProgram (pipeline bug)"
  CContinue _ -> error "JS codegen: CContinue survived untcoProgram (pipeline bug)"
  where
    emitAlt (tag, vars, body) =
      let bindings = T.concat [" const " <> mangle v <> " = s[" <> show (i :: Int) <> "];" | (v, i) <- zip vars [1 ..]]
       in "case " <> show tag <> ": {" <> bindings <> " return " <> emitExpr body <> "; }"

    emitRowAlt :: (Word32, Name, CExpr) -> Text
    emitRowAlt (tag, var, body) =
      "case " <> show tag <> ": { const " <> mangle var <> " = s[1]; return " <> emitExpr body <> "; }"

-- | Encode a Haskell 'Text' as a JavaScript string literal with escapes.
--   Supported escapes mirror the parser/renderer: \n \t \r \" \\ \0
--   (If you ever embed scripts into HTML, consider also escaping U+2028/U+2029.)
jsString :: Text -> Text
jsString = \t -> "\"" <> T.concatMap esc t <> "\""
  where
    esc c = case c of
      '\n' -> "\\n"
      '\t' -> "\\t"
      '\r' -> "\\r"
      '\"' -> "\\\""
      '\\' -> "\\\\"
      '\0' -> "\\0"
      _ -> one c

-- | Simple name mangling:
--   • keep 'main' unchanged (needed by the runner),
--   • otherwise prefix with 'v_' and replace non [A-Za-z0-9_'] with '_'.
mangle :: Text -> Text
mangle t
  | t == "main" = "main"
  | otherwise =
      let ok c = Char.isAlphaNum c || c == '_' || c == '\''
          body = T.map (\c -> if ok c then c else '_') t
       in "v_" <> body
