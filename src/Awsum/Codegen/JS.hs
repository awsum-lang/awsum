-- | JavaScript code generator for Awsum 'Core'.
--
-- Design goals:
--   • Emit small, readable JS that is easy to snapshot-test.
--   • Keep a tiny "runtime" in 'header' only for what we actually need.
--   • Preserve Core invariants: primitives only appear in callee position.
--
-- Semantics & assumptions:
--   • Strings: we rely on JS '+' to concatenate (both operands are statically 'String').
--   • Every top-level surface def is lowered to either Core 'CFunDef' or
--     'CValDef' and emitted as a JS @const@ binding — 'CFunDef' as an
--     arrow closure @const name = (args) => { … };@, 'CValDef' as a
--     plain value @const name = <expr>;@.
--   • Wrapping is selected by 'ProgramType':
--
--       - 'ProgramCli' → IIFE (@(function () { ... })()@). Inside a
--         function scope, top-level @const@/@let@ are lexical, so
--         nothing leaks to the global object — whether loaded as a
--         classic @<script>@ or via Node's CommonJS wrapper. The Node
--         runner in the footer still sees @require@/@module@ via
--         closure.
--
--     Other program types (browser module, CommonJS, ESM) will pick
--     different wrappers without changing the name-emission rules below.
--
-- Declaration order: top-level decls are emitted in the reverse
-- topological order of the call graph ('Awsum.CallGraph.stronglyConnected'
-- already returns SCCs sinks-first). Each SCC's members are emitted as
-- one block; for mutually-recursive 'CFunDef's, order within the block
-- is arbitrary because arrow-closure bodies defer name lookup to call
-- time — by the time any caller of the SCC runs, every member's @const@
-- has been initialized. Mutually-recursive 'CValDef's have no fixed
-- point in strict eval and are rejected by 'Awsum.StackSafety', so any
-- CyclicSCC encountered here contains only 'CFunDef's.
--
-- The result: no reliance on JS function-declaration hoisting; the
-- compiler explicitly enforces an evaluation-safe order. This matters
-- both for correctness inside the IIFE and for future program types
-- (ESM module top level, where 'function' decls behave differently).
module Awsum.Codegen.JS (codegenJS) where

import Awsum.CallGraph (declName, stronglyConnected)
import Awsum.Core
import Awsum.HM (rowTag)
import Awsum.Program (ProgramType (..))
import Awsum.Syntax (Name, Type' (..), noSpan)
import Data.Char qualified as Char
import Data.Graph qualified as G
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Relude

-- | Produce a complete JS file. The wrapping strategy is selected by the
--   program type; the inner name-emission rules are shared.
codegenJS :: ProgramType -> PreludeTags -> CoreProgram -> Text
codegenJS = \case
  ProgramCli -> emitCliScript

-- | CLI script: IIFE-wrapped, with a Node runner inside. Nothing leaks
--   to the global object — neither function declarations (hoisted onto
--   @window@ only at /script/ top level, not inside an IIFE) nor
--   @const@/@let@ (lexically script-scoped).
emitCliScript :: PreludeTags -> CoreProgram -> Text
emitCliScript ptags prog =
  T.intercalate
    "\n"
    [ "\"use strict\";",
      "(function () {",
      header ptags (usedBuiltIns prog),
      T.intercalate "\n\n" (map emitDecl (orderTopLevels prog)),
      cliFooter,
      "})();"
    ]

-- | Reorder top-level declarations so each name's @const@ binding is
-- initialized before any line that needs its value. Uses the call
-- graph's strongly-connected components (sinks first) — each SCC's
-- members emit as one block in arbitrary internal order. Mutual
-- recursion among 'CFunDef's tolerates any order because arrow-closure
-- bodies defer name lookup to call time; mutually-recursive 'CValDef's
-- would be ill-formed in strict eval and are rejected upstream by
-- 'Awsum.StackSafety', so any 'CyclicSCC' encountered here contains
-- only 'CFunDef's.
orderTopLevels :: CoreProgram -> [CDecl]
orderTopLevels prog@(CoreProgram decls) =
  let declMap = Map.fromList [(declName d, d) | d <- decls]
      pickDecl n =
        Map.findWithDefault
          (error "JS codegen: SCC name not found in CoreProgram")
          n
          declMap
      flatten = \case
        G.AcyclicSCC v -> [pickDecl v]
        G.CyclicSCC vs -> map pickDecl vs
   in concatMap flatten (stronglyConnected prog)

-- | Minimal runtime, tree-shaken: only helpers whose primitive / built-in
--   is actually referenced from Core are emitted.
--   • '__print' writes without a newline (Awsum's 'IO.Stdout.print' is "print exactly").
--   • '__concat' is a tiny helper that wraps native '+' with the
--     language-fixed length cap (see 'BuiltIn.concatString'); inlining
--     '+' at each site would duplicate the cap check inline at every '++'.
--   Integer stringification doesn't need a helper; @String(x)@ is
--   inlined at each show call site.
header :: PreludeTags -> Set Name -> Text
header ptags builtIns =
  let -- FNV-1a 32-bit row tags for the prelude's nominal labels used
      -- by the Int32 arithmetic builtins. Hard-wiring them via
      -- 'rowTag' here (instead of a magic number) keeps the encoding
      -- in lockstep with 'Awsum.HM.canonicalLabel' / 'Awsum.HM.fnv1a32'
      -- if either ever changes — the runtime helpers and the
      -- user-side row dispatch agree by construction, not by accident.
      underflowTag = rowTag (TyCon noSpan "UnderflowError")
      overflowTag = rowTag (TyCon noSpan "OverflowError")
      stringTooLongRowTag = rowTag (TyCon noSpan "StringTooLong")
      unpairedSurrogateRowTag = rowTag (TyCon noSpan "UnpairedUtf16Surrogate")
      -- Constructor tags fed in from 'PreludeTags'. Under globally
      -- unique tags every constructor's tag depends on declaration
      -- order, so the runtime helpers — which build these values out
      -- of band of the user's program — must look the tags up rather
      -- than hardcode them.
      ptL = show (ptLeft ptags)
      ptR = show (ptRight ptags)
      ptU = show (ptUnit ptags)
      ptT = show (ptTrue ptags)
      ptF = show (ptFalse ptags)
      ptN = show (ptNothing ptags)
      ptJ = show (ptJust ptags)
      ptT2 = show (ptTuple2 ptags)
      ptUE = show (ptUnderflowError ptags)
      ptOE = show (ptOverflowError ptags)
      ptPE = show (ptParseError ptags)
      ptSTL = show (ptStringTooLong ptags)
      ptUS = show (ptUnpairedUtf16Surrogate ptags)
      lns =
        filter
          (not . T.null)
          [ -- '__print' writes a string to stdout (no newline) and
            -- returns the Unit constructor. Driven by the prelude's
            -- `runIO` walking an 'IOStdoutPrint' arm via
            -- `BuiltIn.internalStdoutPrint`. Returning a real Unit
            -- value lets the prelude `case … of Unit -> next`
            -- dispatch through the standard CCase tag check.
            if Set.member "internalStdoutPrint" builtIns
              then "function __print(s){ process.stdout.write(String(s)); return [" <> ptU <> "]; }"
              else "",
            -- predInt32: returns Left UnderflowError on INT32_MIN, else Right (x - 1).
            if Set.member "predInt32" builtIns
              then "function __predInt32(x){ return x === -2147483648 ? [" <> ptL <> ", [" <> ptUE <> "]] : [" <> ptR <> ", ((x - 1)|0)]; }"
              else "",
            -- predUInt8: returns Left UnderflowError on 0, else Right (x - 1).
            -- When x >= 1, (x - 1) is in 0..254, so no explicit mask is
            -- needed to stay in UInt8 range — but we keep '& 0xFF' for
            -- parallel structure with other UInt8 arithmetic helpers.
            if Set.member "predUInt8" builtIns
              then "function __predUInt8(x){ return x === 0 ? [" <> ptL <> ", [" <> ptUE <> "]] : [" <> ptR <> ", ((x - 1) & 0xFF)]; }"
              else "",
            -- succInt32: returns Left OverflowError on INT32_MAX, else Right (x + 1).
            if Set.member "succInt32" builtIns
              then "function __succInt32(x){ return x === 2147483647 ? [" <> ptL <> ", [" <> ptOE <> "]] : [" <> ptR <> ", ((x + 1)|0)]; }"
              else "",
            -- succUInt8: returns Left OverflowError on 255, else Right (x + 1).
            -- '& 0xFF' kept for parallel structure with __predUInt8.
            if Set.member "succUInt8" builtIns
              then "function __succUInt8(x){ return x === 255 ? [" <> ptL <> ", [" <> ptOE <> "]] : [" <> ptR <> ", ((x + 1) & 0xFF)]; }"
              else "",
            -- eqInt32 / eqUInt8: returns Bool. Both incoming values are
            -- already '|0' / '& 0xFF' coerced, so '===' on JS Numbers
            -- gives the same answer as native i32/u8 equality.
            if Set.member "eqInt32" builtIns
              then "function __eqInt32(a, b){ return a === b ? [" <> ptT <> "] : [" <> ptF <> "]; }"
              else "",
            if Set.member "eqUInt8" builtIns
              then "function __eqUInt8(a, b){ return a === b ? [" <> ptT <> "] : [" <> ptF <> "]; }"
              else "",
            -- eqString: returns Bool. JS strings are UTF-16 internally and
            -- '===' on strings is defined by spec as length-then-code-unit
            -- comparison — exactly the language-level semantics of
            -- 'BuiltIn.eqString'.
            if Set.member "eqString" builtIns
              then "function __eqString(a, b){ return a === b ? [" <> ptT <> "] : [" <> ptF <> "]; }"
              else "",
            -- addInt32: Either (UnderflowError | OverflowError) Int32. JS
            -- numbers exactly represent the 33-bit sum of two i32s, so the
            -- range checks are direct without intermediate '|0' wrapping.
            -- The error side is a structural sum dispatched at runtime by
            -- FNV-1a row tags; the encoded shape is
            --   Left UnderflowError = [ptL, [tagU, [ptUE]]]
            --   Left OverflowError  = [ptL, [tagO, [ptOE]]]
            -- where the inner [ptUE]/[ptOE] is the nullary CCon for the
            -- single-constructor type and 'tagU'/'tagO' are
            -- 'rowTag (TyCon "UnderflowError")'/'rowTag (TyCon "OverflowError")'.
            if Set.member "addInt32" builtIns
              then "function __addInt32(a, b){ const s = a + b; if (s > 2147483647) return [" <> ptL <> ", [" <> show overflowTag <> ", [" <> ptOE <> "]]]; if (s < -2147483648) return [" <> ptL <> ", [" <> show underflowTag <> ", [" <> ptUE <> "]]]; return [" <> ptR <> ", s|0]; }"
              else "",
            -- subInt32: Either (UnderflowError | OverflowError) Int32. Same
            -- range-check shape as __addInt32 — the i32 difference fits in
            -- a JS Number exactly, so direct '> maxInt32' / '< minInt32'
            -- tests pick the branch. Same row-tagged error encoding.
            if Set.member "subInt32" builtIns
              then "function __subInt32(a, b){ const d = a - b; if (d > 2147483647) return [" <> ptL <> ", [" <> show overflowTag <> ", [" <> ptOE <> "]]]; if (d < -2147483648) return [" <> ptL <> ", [" <> show underflowTag <> ", [" <> ptUE <> "]]]; return [" <> ptR <> ", d|0]; }"
              else "",
            -- mulInt32: Either (UnderflowError | OverflowError) Int32. JS
            -- Numbers represent the product of two i32 values exactly (it
            -- fits in 53-bit mantissa precision, max product is ~2^62).
            -- Direct range check on the exact product picks the branch;
            -- '|0' coerces back to i32 on the ok path. Same row-tagged
            -- error encoding as add/sub.
            if Set.member "mulInt32" builtIns
              then "function __mulInt32(a, b){ const p = a * b; if (p > 2147483647) return [" <> ptL <> ", [" <> show overflowTag <> ", [" <> ptOE <> "]]]; if (p < -2147483648) return [" <> ptL <> ", [" <> show underflowTag <> ", [" <> ptUE <> "]]]; return [" <> ptR <> ", p|0]; }"
              else "",
            -- negInt32: Either OverflowError Int32. Only INT32_MIN overflows
            -- (negation would yield 2147483648, outside the signed range);
            -- every other value flips sign cleanly inside JS Number precision.
            if Set.member "negInt32" builtIns
              then "function __negInt32(x){ return x === -2147483648 ? [" <> ptL <> ", [" <> ptOE <> "]] : [" <> ptR <> ", ((-x)|0)]; }"
              else "",
            -- addUInt8: Either OverflowError UInt8. Both inputs in 0..255,
            -- so the unmasked sum is in 0..510 and a single '> 255' check
            -- separates the branches.
            if Set.member "addUInt8" builtIns
              then "function __addUInt8(a, b){ const s = a + b; return s > 255 ? [" <> ptL <> ", [" <> ptOE <> "]] : [" <> ptR <> ", s & 0xFF]; }"
              else "",
            -- subUInt8: Either UnderflowError UInt8. Both inputs in 0..255,
            -- so the difference is in -255..255; a single '< 0' check picks
            -- the underflow branch. The ok-path mask keeps parallel structure
            -- with __addUInt8 (the difference is already in 0..255 there).
            if Set.member "subUInt8" builtIns
              then "function __subUInt8(a, b){ const d = a - b; return d < 0 ? [" <> ptL <> ", [" <> ptUE <> "]] : [" <> ptR <> ", d & 0xFF]; }"
              else "",
            -- mulUInt8: Either OverflowError UInt8. Both inputs in 0..255,
            -- so the unmasked product is in 0..65025 — well within JS Number
            -- precision and the i32 range that '|0' would coerce to. A
            -- single '> 255' check picks the overflow branch.
            if Set.member "mulUInt8" builtIns
              then "function __mulUInt8(a, b){ const p = a * b; return p > 255 ? [" <> ptL <> ", [" <> ptOE <> "]] : [" <> ptR <> ", p & 0xFF]; }"
              else "",
            -- concatString: implements 'BuiltIn.concatString'. Pre-checks
            -- the combined UTF-16 length against the language-fixed cap
            -- (134217728 = 2^27, must stay in sync with
            -- 'maxStringLengthUtf16CodeUnits' in 'stdlib/Prelude.aww').
            -- JS String.length is UTF-16 code units exactly (matches the
            -- cap unit directly), so the check is one i32 comparison.
            if Set.member "concatString" builtIns
              then "function __concat(a, b){ return (a.length + b.length > 134217728) ? [" <> ptL <> ", [" <> ptSTL <> "]] : [" <> ptR <> ", a + b]; }"
              else "",
            -- splitOnFirst: 'indexOf("")' returns 0 in JS, so empty separator
            -- naturally yields ["", str]. 'substring' creates fresh strings
            -- (V8 sometimes shares storage internally — irrelevant at the
            -- semantic level we observe).
            if Set.member "splitOnFirst" builtIns
              then "function __splitOnFirst(sep, str){ const i = str.indexOf(sep); if (i < 0) return [" <> ptN <> "]; return [" <> ptJ <> ", [" <> ptT2 <> ", str.substring(0, i), str.substring(i + sep.length)]]; }"
              else "",
            -- parseInt32: strict decimal grammar mirroring the language
            -- literal — optional '-', one or more ASCII digits, nothing else.
            -- Regex full-match enforces it; Number() then range-checks. JS
            -- numbers are double-precision and represent every i32 (and the
            -- absolute minInt32 boundary 2147483648) exactly.
            if Set.member "parseInt32" builtIns
              then "function __parseInt32(s){ if (!/^-?[0-9]+$/.test(s)) return [" <> ptL <> ", [" <> ptPE <> "]]; const n = Number(s); if (n < -2147483648 || n > 2147483647) return [" <> ptL <> ", [" <> ptPE <> "]]; return [" <> ptR <> ", n | 0]; }"
              else "",
            -- parseUInt8: same shape but no sign accepted; range 0..255.
            if Set.member "parseUInt8" builtIns
              then "function __parseUInt8(s){ if (!/^[0-9]+$/.test(s)) return [" <> ptL <> ", [" <> ptPE <> "]]; const n = Number(s); if (n > 255) return [" <> ptL <> ", [" <> ptPE <> "]]; return [" <> ptR <> ", n & 0xFF]; }"
              else "",
            -- predUInt32: returns Left UnderflowError on 0, else Right (x - 1).
            -- '>>> 0' coerces to unsigned 32-bit (where '|0' would give signed).
            if Set.member "predUInt32" builtIns
              then "function __predUInt32(x){ return x === 0 ? [" <> ptL <> ", [" <> ptUE <> "]] : [" <> ptR <> ", ((x - 1) >>> 0)]; }"
              else "",
            -- succUInt32: returns Left OverflowError on 4294967295, else Right (x + 1).
            if Set.member "succUInt32" builtIns
              then "function __succUInt32(x){ return x === 4294967295 ? [" <> ptL <> ", [" <> ptOE <> "]] : [" <> ptR <> ", ((x + 1) >>> 0)]; }"
              else "",
            -- eqUInt32: identical shape to eqInt32 — both inputs are already
            -- '>>> 0' coerced so '===' on JS Numbers gives native u32 equality.
            if Set.member "eqUInt32" builtIns
              then "function __eqUInt32(a, b){ return a === b ? [" <> ptT <> "] : [" <> ptF <> "]; }"
              else "",
            -- addUInt32: Either OverflowError UInt32. JS Numbers exactly
            -- represent the unmasked sum of two u32s (max ~2^33), so a
            -- direct '> 4294967295' check separates the branches.
            if Set.member "addUInt32" builtIns
              then "function __addUInt32(a, b){ const s = a + b; return s > 4294967295 ? [" <> ptL <> ", [" <> ptOE <> "]] : [" <> ptR <> ", (s >>> 0)]; }"
              else "",
            -- subUInt32: Either UnderflowError UInt32. Difference is in
            -- -4294967295..4294967295; '< 0' picks the underflow branch.
            if Set.member "subUInt32" builtIns
              then "function __subUInt32(a, b){ const d = a - b; return d < 0 ? [" <> ptL <> ", [" <> ptUE <> "]] : [" <> ptR <> ", (d >>> 0)]; }"
              else "",
            -- mulUInt32: Either OverflowError UInt32. Product of two u32
            -- values is at most ~2^64; JS Numbers only have 53-bit
            -- precision so we use BigInt to compute the exact product,
            -- then range-check before coercing back.
            if Set.member "mulUInt32" builtIns
              then "function __mulUInt32(a, b){ const p = BigInt(a) * BigInt(b); return p > 4294967295n ? [" <> ptL <> ", [" <> ptOE <> "]] : [" <> ptR <> ", (Number(p) >>> 0)]; }"
              else "",
            -- parseUInt32: same grammar as parseUInt8 — no sign, decimal
            -- digits only — range 0..4294967295. JS Numbers represent
            -- 4294967295 exactly, so direct '> 4294967295' is faithful.
            if Set.member "parseUInt32" builtIns
              then "function __parseUInt32(s){ if (!/^[0-9]+$/.test(s)) return [" <> ptL <> ", [" <> ptPE <> "]]; const n = Number(s); if (n > 4294967295) return [" <> ptL <> ", [" <> ptPE <> "]]; return [" <> ptR <> ", (n >>> 0)]; }"
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
            -- '__entryArgEither' is shared by '__getArgs' (argv source)
            -- and '__stdinReadAll' (stdin source). Gate on either
            -- builtin's presence so a program that needs neither pays
            -- nothing for the validator.
            if Set.member "internalGetArgs" builtIns || Set.member "internalStdinReadAllAsUtf16" builtIns
              then "function __entryArgEither(arg){ if (arg.length > 134217728) return [" <> ptL <> ", [" <> show stringTooLongRowTag <> ", [" <> ptSTL <> "]]]; for (let i = 0; i < arg.length; i++) { const c = arg.charCodeAt(i); if (c >= 0xD800 && c <= 0xDBFF) { if (i + 1 >= arg.length) return [" <> ptL <> ", [" <> show unpairedSurrogateRowTag <> ", [" <> ptUS <> "]]]; const next = arg.charCodeAt(i + 1); if (next < 0xDC00 || next > 0xDFFF) return [" <> ptL <> ", [" <> show unpairedSurrogateRowTag <> ", [" <> ptUS <> "]]]; i++; } else if (c >= 0xDC00 && c <= 0xDFFF) return [" <> ptL <> ", [" <> show unpairedSurrogateRowTag <> ", [" <> ptUS <> "]]]; } return [" <> ptR <> ", arg]; }"
              else "",
            -- __getArgs: zero-arg helper called by 'runIO''s 'IOGetArgs'
            -- arm via 'BuiltIn.internalGetArgs'. Reads 'process.argv[2]'
            -- (same slot as the entry-point glue) and routes through
            -- '__entryArgEither' for the strict-UTF-16 validation. Per
            -- the no-memoisation decision each call re-reads argv;
            -- argv is invariant during execution, so repeat calls
            -- return the same value deterministically.
            if Set.member "internalGetArgs" builtIns
              then "function __getArgs(){ return __entryArgEither(process.argv[2] ?? \"\"); }"
              else "",
            -- __stdinReadAll: zero-arg helper for
            -- 'BuiltIn.internalStdinReadAllAsUtf16', called from
            -- 'runIO''s 'IOStdinReadAll' arm. Reads fd 0 to EOF via
            -- 'fs.readFileSync(0)' (which works on POSIX and Windows,
            -- handles binary input correctly, and blocks until EOF),
            -- then UTF-8 decodes the resulting Buffer and routes the
            -- string through '__entryArgEither'. Per the POSIX-honest
            -- no-memoisation decision, each call reads whatever bytes
            -- remain on stdin; a second call after EOF reads zero
            -- bytes and decodes to @Right ""@.
            if Set.member "internalStdinReadAllAsUtf16" builtIns
              then "function __stdinReadAll(){ return __entryArgEither(require('fs').readFileSync(0).toString('utf-8')); }"
              else ""
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
      -- v_main is a zero-arg value (CValDef in Core) that the JS
      -- codegen emits as a top-level 'const main = …' — i.e. the IO
      -- tree is the value of that binding, not a function. 'v_runIO'
      -- walks the tree for effects. User code reads argv through
      -- 'IO.Args.getArgs' inside the chain; that lowers to an
      -- 'IOGetArgs' constructor whose runIO arm calls '__getArgs'
      -- (which reads 'process.argv[2]' lazily on each call).
      "  if (typeof main !== 'undefined') v_runIO(main);",
      "}"
    ]

-- | Top-level declarations:
--   • 'CFunDef' with 'CLoop' body (output of the TCO pass) → arrow
--     closure containing a 'while (true)' loop whose body is emitted in
--     statement form so 'CContinue' can rebind the function's parameters
--     and 'continue' the loop instead of recursing. Rewriting a
--     self-tail-call as a jump keeps the JS engine's call stack bounded,
--     which matters on Node/V8 because ES2015 PTC was never shipped.
--   • 'CFunDef' without 'CLoop' → arrow closure, statement form body.
--     A 'CCase' in tail position becomes a 'switch' whose arms 'return'
--     directly, instead of an IIFE. That keeps deeply nested pattern
--     matches (N nested 'case' expressions in tail position) inside a
--     single stack frame; the IIFE form would burn one frame per level
--     and overflow on platforms with small default stacks (e.g. Windows
--     Node ≈512 KB).
--   • 'CValDef' → 'const name = <expr>;'.
--
-- Arrow closures (rather than @function@ declarations) so the codegen
-- doesn't rely on function-declaration hoisting — 'orderTopLevels'
-- arranges decls in evaluation-safe order, and each binding is an
-- ordinary @const@ that's initialized exactly at its line.
emitDecl :: CDecl -> Text
emitDecl = \case
  CFunDef nm args (CLoop body) ->
    "const "
      <> mangle nm
      <> " = ("
      <> T.intercalate ", " (map mangle args)
      <> ") => {\n"
      <> "  while (true) {\n"
      <> emitStmt args body
      <> "  }\n"
      <> "};"
  CFunDef nm args body ->
    "const "
      <> mangle nm
      <> " = ("
      <> T.intercalate ", " (map mangle args)
      <> ") => {\n"
      <> emitStmt args body
      <> "};"
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
-- | Emit @body@ in tail position. Threads a 'pending' stack of
-- 'CDrop'-named parameters; the stack drains at every terminator.
-- For 'CContinue' the drains land between the buffered
-- arg-evaluations and the param updates, so each dropped parameter's
-- old reference is overwritten with @null@ before the next iteration
-- reads the buffered value. (JS variables are GC roots until
-- reassigned; nulling the slot lets V8 collect the old graph one
-- iteration sooner.) For a value-producing tail, the drains fire
-- after the value is captured, then @return@.
emitStmt :: [Name] -> CExpr -> Text
emitStmt params = go []
  where
    -- 'CDrop' on a function parameter assigns @null@ to the
    -- (mutable) param slot — managed-GC early root snip.
    -- 'CDrop' on a 'CCase' arm-binder is a no-op: case-binders
    -- are declared with @const@ (V8 can't reassign), and the
    -- block-scoped slot dies as soon as the arm closes, so GC
    -- collects naturally.
    isParam :: Name -> Bool
    isParam n = n `elem` params

    go :: [Name] -> CExpr -> Text
    go pending = \case
      CContinue newArgs ->
        let temps = ["__t" <> show (i :: Int) | i <- [0 .. length newArgs - 1]]
            declLines =
              [ "    const " <> t <> " = " <> emitExpr a <> ";"
              | (t, a) <- zip temps newArgs
              ]
            freeLines =
              [ "    " <> mangle n <> " = null;"
              | n <- pending,
                isParam n
              ]
            assignLines =
              [ "    " <> mangle p <> " = " <> t <> ";"
              | (p, t) <- zip params temps
              ]
         in unlines (declLines <> freeLines <> assignLines <> ["    continue;"])
      CCase scrut alts ->
        "    {\n      const __s = "
          <> emitExpr scrut
          <> ";\n      switch (__s[0]) {\n"
          <> T.concat (map (emitStmtAlt pending) alts)
          <> "      }\n    }\n"
      CRowCase scrut alts ->
        "    {\n      const __s = "
          <> emitExpr scrut
          <> ";\n      switch (__s[0]) {\n"
          <> T.concat (map (emitStmtRowAlt pending) alts)
          <> "      }\n    }\n"
      -- Push the drop onto 'pending'; drain at the next terminator.
      CDrop _ n body -> go (n : pending) body
      e ->
        let valExpr = emitExpr e
            paramPending = filter isParam pending
         in if null paramPending
              then "    return " <> valExpr <> ";\n"
              else
                "    {\n"
                  <> "      const __d = "
                  <> valExpr
                  <> ";\n"
                  <> T.concat ["      " <> mangle n <> " = null;\n" | n <- paramPending]
                  <> "      return __d;\n"
                  <> "    }\n"

    emitStmtAlt :: [Name] -> (Int, [Name], CExpr) -> Text
    emitStmtAlt pending (tag, vars, body) =
      let bindings =
            T.concat
              [ "          const " <> mangle v <> " = __s[" <> show (i :: Int) <> "];\n"
              | (v, i) <- zip vars [1 ..]
              ]
       in "        case "
            <> show tag
            <> ": {\n"
            <> bindings
            <> reindentStmt (go pending body)
            <> "        }\n"

    emitStmtRowAlt :: [Name] -> (Word32, Name, CExpr) -> Text
    emitStmtRowAlt pending (tag, var, body) =
      "        case "
        <> show tag
        <> ": {\n"
        <> "          const "
        <> mangle var
        <> " = __s[1];\n"
        <> reindentStmt (go pending body)
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
  -- Liveness annotation; backends treat as a transparent wrapper
  -- since the managed GC handles reclaim.
  CDrop _ _ body -> emitExpr body
  -- Cell reuse. In-place mutation of the JS array at
  -- @n@: assign each slot then return the array. Emitted as a
  -- single comma expression so the whole construct is still a
  -- value-producing JS expression usable in any argument position.
  --
  -- Invariant from 'Awsum.Reuse.rewriteFirstCCon': @length fields@
  -- equals the matched arm's pattern arity, so the array has at
  -- least @1 + length fields@ slots.
  CReuse n tag fields ->
    let v = mangle n
        tagStore = v <> "[0] = " <> show tag
        fieldStores =
          [v <> "[" <> show (i :: Int) <> "] = " <> emitExpr fld | (fld, i) <- zip fields [1 ..]]
     in "(" <> T.intercalate ", " (tagStore : fieldStores <> [v]) <> ")"
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
      CBuiltIn "internalGetArgs" ->
        case xs of
          [] -> "__getArgs()"
          _ -> error "__getArgs: arity mismatch"
      -- Zero-arg primitive driving 'runIO''s 'IOStdinReadAll' arm:
      -- consumes stdin via 'fs.readFileSync(0)' and routes the decoded
      -- UTF-8 through '__entryArgEither'.
      CBuiltIn "internalStdinReadAllAsUtf16" ->
        case xs of
          [] -> "__stdinReadAll()"
          _ -> error "__stdinReadAll: arity mismatch"
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
        | name == "eqInt32" || name == "eqUInt8" || name == "eqUInt32" || name == "eqString" ->
            case xs of
              [a, b] ->
                let fn = case name of
                      "eqInt32" -> "__eqInt32"
                      "eqUInt8" -> "__eqUInt8"
                      "eqUInt32" -> "__eqUInt32"
                      _ -> "__eqString"
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
  -- 'CLoop' / 'CContinue' should only appear at function-body-tail and
  -- inside a 'CLoop' body respectively; the tail walker in 'emitFun'
  -- handles those positions directly. Hitting either here signals a
  -- pipeline bug, so crash loudly.
  CLoop _ -> error "JS codegen: CLoop in non-tail position (pipeline bug — should only appear at function-body-tail)"
  CContinue _ -> error "JS codegen: CContinue in non-tail position (pipeline bug — should only appear inside a CLoop)"
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
