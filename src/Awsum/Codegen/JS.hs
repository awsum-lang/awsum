-- | JavaScript code generator for Awsum 'Core'.
--
-- Builds a 'Awsum.Codegen.JS.Syntax' AST from Core and renders it — the JS
-- analogue of how the byte backends build a spec ('JvmModule' \/ 'WasmFunc')
-- and project it. Everything in the emitted file flows through the AST:
-- the runtime helpers, the user\/prelude declarations, the @main@ value, the
-- Node runner, and the IIFE wrapper — there are no verbatim JS string blobs.
--
-- Semantics & assumptions:
--   • Strings: we rely on JS '+' to concatenate (both operands are statically 'String').
--   • Every top-level surface def is lowered to either Core 'CFunDef' or
--     'CValDef' and emitted as a JS @const@ binding — 'CFunDef' as an arrow
--     closure, 'CValDef' as a plain value.
--   • Wrapping is selected by 'ProgramType':
--
--       - 'ProgramCli' → IIFE (@(() => { … })()@). Inside a function scope,
--         top-level @const@\/@let@ are lexical, so nothing leaks to the global
--         object — whether loaded as a classic @<script>@ or via Node's
--         CommonJS wrapper. The Node runner in the footer still sees
--         @require@\/@module@ via closure.
--
--     Other program types (browser module, CommonJS, ESM) will pick
--     different wrappers without changing the name-emission rules below.
--
-- Declaration order: top-level decls are emitted in the reverse topological
-- order of the call graph ('Awsum.CallGraph.stronglyConnected' returns SCCs
-- sinks-first). Each SCC's members are emitted as one block; for
-- mutually-recursive 'CFunDef's, order within the block is arbitrary because
-- arrow-closure bodies defer name lookup to call time — by the time any
-- caller of the SCC runs, every member's @const@ has been initialized.
-- Mutually-recursive 'CValDef's have no fixed point in strict eval and are
-- rejected by 'Awsum.StackSafety', so any CyclicSCC encountered here contains
-- only 'CFunDef's. The result: no reliance on JS function-declaration
-- hoisting — every binding is an ordinary @const@ initialized at its line —
-- which also lets the runtime helpers be plain @const@ arrows like everything
-- else (the only inter-helper edge, @__getArgs@ → @__entryArgEither@, resolves
-- at call time, after every helper @const@ is initialized).
module Awsum.Codegen.JS (codegenJS) where

import Awsum.CallGraph (declName, stronglyConnected)
import Awsum.Codegen.JS.Syntax
import Awsum.Codegen.Mangle qualified as Mangle
import Awsum.Codegen.ReuseSchedule (ReuseStore (..), reuseSlotElided, scheduleReuse)
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
  ProgramCli -> \ptags prog -> renderProgram (cliModule ptags prog)

-- | CLI script: @"use strict";@ directive followed by an IIFE whose body is
--   the runtime helpers, the ordered declarations, and the Node runner.
cliModule :: PreludeTags -> CoreProgram -> [JsStmt]
cliModule ptags prog =
  [ SExpr (EStr "use strict"),
    SBlank,
    SExpr (ECall (EArrow [] iifeBody) [])
  ]
  where
    -- A blank line between each top-level unit (helper, declaration, footer)
    -- for legibility. A declaration is a group of statements — its hoisted
    -- @const@s plus the binding — kept together, so the blanks land only
    -- between units, never inside one.
    iifeBody =
      intercalate
        [SBlank]
        ( map (: []) (header ptags (usedBuiltIns prog))
            <> map declStmt (orderTopLevels prog)
            <> map (: []) cliFooter
        )

-- | Reorder top-level declarations so each name's @const@ binding is
--   initialized before any line that needs its value. See the module header
--   for why arbitrary order within a 'CyclicSCC' is safe.
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

-- ════════════════════════════════════════════════════════════════════════════
-- Runtime helpers
-- ════════════════════════════════════════════════════════════════════════════

-- | Minimal runtime, tree-shaken: only helpers whose primitive \/ built-in is
--   actually referenced from Core are emitted. Each helper is a @const@ arrow
--   so it obeys the same no-hoisting discipline as generated declarations.
--   The constructor\/row tags are looked up (not hardcoded) because globally
--   unique tags depend on declaration order — the runtime helpers, which build
--   these values out of band of the user's program, must agree with the
--   user-side dispatch by construction.
header :: PreludeTags -> Set Name -> [JsStmt]
header ptags builtIns =
  concat
    [ gate "internalStdoutPrint" printHelper,
      gate "predInt32" predInt32Helper,
      gate "predUInt8" predUInt8Helper,
      gate "succInt32" succInt32Helper,
      gate "succUInt8" succUInt8Helper,
      gate "eqInt32" (eqHelper "__eqInt32"),
      gate "eqUInt8" (eqHelper "__eqUInt8"),
      gate "eqString" (eqHelper "__eqString"),
      gate "addInt32" addInt32Helper,
      gate "subInt32" subInt32Helper,
      gate "mulInt32" mulInt32Helper,
      gate "negInt32" negInt32Helper,
      gate "addUInt8" addUInt8Helper,
      gate "subUInt8" subUInt8Helper,
      gate "mulUInt8" mulUInt8Helper,
      gate "concatString" concatHelper,
      gate "splitOnFirst" splitOnFirstHelper,
      gate "parseInt32" parseInt32Helper,
      gate "parseUInt8" parseUInt8Helper,
      gate "predUInt32" predUInt32Helper,
      gate "succUInt32" succUInt32Helper,
      gate "eqUInt32" (eqHelper "__eqUInt32"),
      gate "addUInt32" addUInt32Helper,
      gate "subUInt32" subUInt32Helper,
      gate "mulUInt32" mulUInt32Helper,
      gate "parseUInt32" parseUInt32Helper,
      gate "lengthCodePoints" lengthCodePointsHelper,
      gate "lengthUtf16CodeUnits" lengthUtf16Helper,
      gate "lengthUtf8Bytes" lengthUtf8Helper,
      -- '__entryArgEither' must precede '__getArgs' (its only caller); both
      -- gate on the argv built-in.
      gate "internalGetArgs" entryArgEitherHelper,
      gate "internalGetArgs" getArgsHelper,
      gate "internalStdinReadAllString" stdinReadAllStringHelper,
      gate "internalStdinReadAllBytes" stdinReadAllBytesHelper
    ]
  where
    gate :: Name -> JsStmt -> [JsStmt]
    gate name s = [s | Set.member name builtIns]

    -- Prelude constructor tags as JS number literals.
    ptL = ENum (toInteger (ptLeft ptags))
    ptR = ENum (toInteger (ptRight ptags))
    ptJ = ENum (toInteger (ptJust ptags))
    ptNothingTag = ENum (toInteger (ptNothing ptags))
    ptTrueTag = ENum (toInteger (ptTrue ptags))
    ptFalseTag = ENum (toInteger (ptFalse ptags))
    ptU = ENum (toInteger (ptUnit ptags))
    ptT2 = ENum (toInteger (ptTuple2 ptags))
    ptNilTag = ENum (toInteger (ptNil ptags))
    ptConsTag = ENum (toInteger (ptCons ptags))
    ptUE = ENum (toInteger (ptUnderflowError ptags))
    ptOE = ENum (toInteger (ptOverflowError ptags))
    ptPE = ENum (toInteger (ptParseError ptags))
    ptSTL = ENum (toInteger (ptStringTooLong ptags))
    ptUS = ENum (toInteger (ptUnpairedUtf16Surrogate ptags))
    ptIU = ENum (toInteger (ptInvalidUtf8 ptags))

    -- FNV-1a row tags for the row-wrapped 'Left' payloads of the Int32
    -- arithmetic helpers and the input decoders. Looked up via 'rowTag'
    -- (not magic numbers) so the encoding stays in lockstep with
    -- 'Awsum.HM.canonicalLabel'.
    overflowRow = ENum (toInteger (rowTag (TyCon noSpan "OverflowError")))
    underflowRow = ENum (toInteger (rowTag (TyCon noSpan "UnderflowError")))
    stringTooLongRow = ENum (toInteger (rowTag (TyCon noSpan "StringTooLong")))
    unpairedSurrogateRow = ENum (toInteger (rowTag (TyCon noSpan "UnpairedUtf16Surrogate")))
    invalidUtf8Row = ENum (toInteger (rowTag (TyCon noSpan "InvalidUtf8")))

    -- Encoded-value builders.
    leftV e = EArray [ptL, e] -- Left e  = [ptL, e]
    rightV e = EArray [ptR, e] -- Right e = [ptR, e]
    con0 t = EArray [t] -- nullary constructor [tag]
    rowOf rt inner = EArray [rt, inner] -- row-tagged [rowTag, inner]

    -- '__print' writes a string to stdout (no newline) and returns the Unit
    -- constructor. Driven by the prelude's `runIO` walking an 'IOStdoutPrint'
    -- arm; returning a real Unit value lets the `case … of Unit -> next`
    -- dispatch through the standard tag check.
    printHelper =
      SConst "__print"
        $ EArrow
          ["s"]
          [ SExpr (ECall (EMember (EMember (EVar "process") "stdout") "write") [ECall (EVar "String") [EVar "s"]]),
            SReturn (con0 ptU)
          ]

    -- predInt32: Left UnderflowError on INT32_MIN, else Right (x - 1).
    predInt32Helper =
      SConst "__predInt32"
        $ EArrow ["x"] [SReturn (ECond (EBin BEq (EVar "x") (ENum (-2147483648))) (leftV (con0 ptUE)) (rightV (i32 (EBin BSub (EVar "x") (ENum 1)))))]

    -- predUInt8: Left UnderflowError on 0, else Right (x - 1). The mask keeps
    -- parallel structure with the other UInt8 helpers (x - 1 is already 0..254).
    predUInt8Helper =
      SConst "__predUInt8"
        $ EArrow ["x"] [SReturn (ECond (EBin BEq (EVar "x") (ENum 0)) (leftV (con0 ptUE)) (rightV (u8 (EBin BSub (EVar "x") (ENum 1)))))]

    -- succInt32: Left OverflowError on INT32_MAX, else Right (x + 1).
    succInt32Helper =
      SConst "__succInt32"
        $ EArrow ["x"] [SReturn (ECond (EBin BEq (EVar "x") (ENum 2147483647)) (leftV (con0 ptOE)) (rightV (i32 (EBin BAdd (EVar "x") (ENum 1)))))]

    -- succUInt8: Left OverflowError on 255, else Right (x + 1).
    succUInt8Helper =
      SConst "__succUInt8"
        $ EArrow ["x"] [SReturn (ECond (EBin BEq (EVar "x") (ENum 255)) (leftV (con0 ptOE)) (rightV (u8 (EBin BAdd (EVar "x") (ENum 1)))))]

    -- predUInt32 / succUInt32: '>>> 0' coerces to unsigned 32-bit.
    predUInt32Helper =
      SConst "__predUInt32"
        $ EArrow ["x"] [SReturn (ECond (EBin BEq (EVar "x") (ENum 0)) (leftV (con0 ptUE)) (rightV (u32 (EBin BSub (EVar "x") (ENum 1)))))]

    succUInt32Helper =
      SConst "__succUInt32"
        $ EArrow ["x"] [SReturn (ECond (EBin BEq (EVar "x") (ENum 4294967295)) (leftV (con0 ptOE)) (rightV (u32 (EBin BAdd (EVar "x") (ENum 1)))))]

    -- negInt32: only INT32_MIN overflows; every other value flips sign cleanly.
    negInt32Helper =
      SConst "__negInt32"
        $ EArrow ["x"] [SReturn (ECond (EBin BEq (EVar "x") (ENum (-2147483648))) (leftV (con0 ptOE)) (rightV (i32 (EUnary UNeg (EVar "x")))))]

    -- eqInt32 / eqUInt8 / eqUInt32 / eqString: both operands are already
    -- range-coerced (or JS strings, where '===' is spec length-then-code-unit),
    -- so '===' matches the language-level equality.
    eqHelper :: Text -> JsStmt
    eqHelper fn =
      SConst fn
        $ EArrow ["a", "b"] [SReturn (ECond (EBin BEq (EVar "a") (EVar "b")) (con0 ptTrueTag) (con0 ptFalseTag))]

    -- addInt32 / subInt32 / mulInt32: Either (UnderflowError | OverflowError)
    -- Int32. JS Numbers exactly represent the 33-/62-bit intermediate, so the
    -- range checks are direct; the error side is the row-tagged structural sum.
    addInt32Helper = int32ArithHelper "__addInt32" BAdd
    subInt32Helper = int32ArithHelper "__subInt32" BSub
    mulInt32Helper = int32ArithHelper "__mulInt32" BMul

    int32ArithHelper :: Text -> BinOp -> JsStmt
    int32ArithHelper fn op =
      SConst fn
        $ EArrow
          ["a", "b"]
          [ SConst "r" (EBin op (EVar "a") (EVar "b")),
            SIf (EBin BGt (EVar "r") (ENum 2147483647)) [SReturn (leftV (rowOf overflowRow (con0 ptOE)))] [],
            SIf (EBin BLt (EVar "r") (ENum (-2147483648))) [SReturn (leftV (rowOf underflowRow (con0 ptUE)))] [],
            SReturn (rightV (i32 (EVar "r")))
          ]

    -- addUInt8 / subUInt8 / mulUInt8: single bound check then mask to 0..255.
    addUInt8Helper = u8OverflowHelper "__addUInt8" BAdd
    mulUInt8Helper = u8OverflowHelper "__mulUInt8" BMul

    u8OverflowHelper :: Text -> BinOp -> JsStmt
    u8OverflowHelper fn op =
      SConst fn
        $ EArrow
          ["a", "b"]
          [ SConst "r" (EBin op (EVar "a") (EVar "b")),
            SReturn (ECond (EBin BGt (EVar "r") (ENum 255)) (leftV (con0 ptOE)) (rightV (u8 (EVar "r"))))
          ]

    subUInt8Helper =
      SConst "__subUInt8"
        $ EArrow
          ["a", "b"]
          [ SConst "d" (EBin BSub (EVar "a") (EVar "b")),
            SReturn (ECond (EBin BLt (EVar "d") (ENum 0)) (leftV (con0 ptUE)) (rightV (u8 (EVar "d"))))
          ]

    -- addUInt32 / subUInt32: difference\/sum fits a JS Number exactly.
    addUInt32Helper =
      SConst "__addUInt32"
        $ EArrow
          ["a", "b"]
          [ SConst "s" (EBin BAdd (EVar "a") (EVar "b")),
            SReturn (ECond (EBin BGt (EVar "s") (ENum 4294967295)) (leftV (con0 ptOE)) (rightV (u32 (EVar "s"))))
          ]

    subUInt32Helper =
      SConst "__subUInt32"
        $ EArrow
          ["a", "b"]
          [ SConst "d" (EBin BSub (EVar "a") (EVar "b")),
            SReturn (ECond (EBin BLt (EVar "d") (ENum 0)) (leftV (con0 ptUE)) (rightV (u32 (EVar "d"))))
          ]

    -- mulUInt32: product can reach ~2^64, beyond Number precision, so compute
    -- it exactly with BigInt then range-check before coercing back.
    mulUInt32Helper =
      SConst "__mulUInt32"
        $ EArrow
          ["a", "b"]
          [ SConst "p" (EBin BMul (ECall (EVar "BigInt") [EVar "a"]) (ECall (EVar "BigInt") [EVar "b"])),
            SReturn (ECond (EBin BGt (EVar "p") (EBigInt 4294967295)) (leftV (con0 ptOE)) (rightV (u32 (ECall (EVar "Number") [EVar "p"]))))
          ]

    -- concatString: pre-check the combined UTF-16 length against the
    -- language-fixed cap (2^27); JS String.length is UTF-16 code units exactly.
    concatHelper =
      SConst "__concat"
        $ EArrow ["a", "b"] [SReturn (ECond (EBin BGt (EBin BAdd (EMember (EVar "a") "length") (EMember (EVar "b") "length")) (ENum 134217728)) (leftV (con0 ptSTL)) (rightV (EBin BAdd (EVar "a") (EVar "b"))))]

    -- splitOnFirst: 'indexOf("")' is 0 in JS, so an empty separator yields
    -- ["", str]. 'substring' creates fresh strings.
    splitOnFirstHelper =
      SConst "__splitOnFirst"
        $ EArrow
          ["sep", "str"]
          [ SConst "i" (ECall (EMember (EVar "str") "indexOf") [EVar "sep"]),
            SIf (EBin BLt (EVar "i") (ENum 0)) [SReturn (con0 ptNothingTag)] [],
            SReturn
              ( EArray
                  [ ptJ,
                    EArray
                      [ ptT2,
                        ECall (EMember (EVar "str") "substring") [ENum 0, EVar "i"],
                        ECall (EMember (EVar "str") "substring") [EBin BAdd (EVar "i") (EMember (EVar "sep") "length")]
                      ]
                  ]
              )
          ]

    -- parseInt32 / parseUInt8 / parseUInt32: strict decimal grammar mirroring
    -- the language literal (regex full-match), then Number() + range check.
    parseInt32Helper =
      SConst "__parseInt32"
        $ EArrow
          ["s"]
          [ SIf (EUnary UNot (ECall (EMember (ERegex "^-?[0-9]+$") "test") [EVar "s"])) [SReturn (leftV (con0 ptPE))] [],
            SConst "n" (ECall (EVar "Number") [EVar "s"]),
            SIf (EBin BOr (EBin BLt (EVar "n") (ENum (-2147483648))) (EBin BGt (EVar "n") (ENum 2147483647))) [SReturn (leftV (con0 ptPE))] [],
            SReturn (rightV (i32 (EVar "n")))
          ]

    parseUInt8Helper =
      SConst "__parseUInt8"
        $ EArrow
          ["s"]
          [ SIf (EUnary UNot (ECall (EMember (ERegex "^[0-9]+$") "test") [EVar "s"])) [SReturn (leftV (con0 ptPE))] [],
            SConst "n" (ECall (EVar "Number") [EVar "s"]),
            SIf (EBin BGt (EVar "n") (ENum 255)) [SReturn (leftV (con0 ptPE))] [],
            SReturn (rightV (u8 (EVar "n")))
          ]

    parseUInt32Helper =
      SConst "__parseUInt32"
        $ EArrow
          ["s"]
          [ SIf (EUnary UNot (ECall (EMember (ERegex "^[0-9]+$") "test") [EVar "s"])) [SReturn (leftV (con0 ptPE))] [],
            SConst "n" (ECall (EVar "Number") [EVar "s"]),
            SIf (EBin BGt (EVar "n") (ENum 4294967295)) [SReturn (leftV (con0 ptPE))] [],
            SReturn (rightV (u32 (EVar "n")))
          ]

    -- lengthCodePoints: 'Array.from' walks the string by its iterator, which
    -- yields one element per Unicode code point (a surrogate pair counts once)
    -- — the USV count, where the cached UTF-16 'length' would over-count.
    lengthCodePointsHelper =
      SConst "__lengthCodePoints"
        $ EArrow ["s"] [SReturn (u32 (EMember (ECall (EMember (EVar "Array") "from") [EVar "s"]) "length"))]

    -- lengthUtf16CodeUnits: native JS string length is the UTF-16 code-unit
    -- count by spec.
    lengthUtf16Helper =
      SConst "__lengthUtf16CodeUnits"
        $ EArrow ["s"] [SReturn (u32 (EMember (EVar "s") "length"))]

    -- lengthUtf8Bytes: TextEncoder always uses standard (not modified) UTF-8.
    lengthUtf8Helper =
      SConst "__lengthUtf8Bytes"
        $ EArrow ["s"] [SReturn (u32 (EMember (ECall (EMember (ENew (EVar "TextEncoder") []) "encode") [EVar "s"]) "length"))]

    -- __entryArgEither: wraps one host-decoded argv string in Either
    -- (StringTooLong | UnpairedUtf16Surrogate) String. Two checks: the length
    -- cap, then strict UTF-16 surrogate pairing (JS strings allow unpaired
    -- surrogates; Awsum 'String' is strict UTF-16, so the boundary validates).
    entryArgEitherHelper =
      SConst "__entryArgEither"
        $ EArrow
          ["arg"]
          [ SIf (EBin BGt (EMember (EVar "arg") "length") (ENum 134217728)) [SReturn (leftV (rowOf stringTooLongRow (con0 ptSTL)))] [],
            SFor
              "i"
              (ENum 0)
              (EBin BLt (EVar "i") (EMember (EVar "arg") "length"))
              (EUpdate UInc (EVar "i"))
              [ SConst "c" (ECall (EMember (EVar "arg") "charCodeAt") [EVar "i"]),
                SIf
                  (EBin BAnd (EBin BGe (EVar "c") (EHex 0xD800)) (EBin BLe (EVar "c") (EHex 0xDBFF)))
                  [ SIf (EBin BGe (EBin BAdd (EVar "i") (ENum 1)) (EMember (EVar "arg") "length")) [SReturn (leftV (rowOf unpairedSurrogateRow (con0 ptUS)))] [],
                    SConst "next" (ECall (EMember (EVar "arg") "charCodeAt") [EBin BAdd (EVar "i") (ENum 1)]),
                    SIf (EBin BOr (EBin BLt (EVar "next") (EHex 0xDC00)) (EBin BGt (EVar "next") (EHex 0xDFFF))) [SReturn (leftV (rowOf unpairedSurrogateRow (con0 ptUS)))] [],
                    SExpr (EUpdate UInc (EVar "i"))
                  ]
                  [SIf (EBin BAnd (EBin BGe (EVar "c") (EHex 0xDC00)) (EBin BLe (EVar "c") (EHex 0xDFFF))) [SReturn (leftV (rowOf unpairedSurrogateRow (con0 ptUS)))] []]
              ],
            SReturn (rightV (EVar "arg"))
          ]

    -- __getArgs: reads 'process.argv.slice(2)' and builds an Awsum 'List
    -- String', routing each element through '__entryArgEither' (all-or-nothing:
    -- the first failing element short-circuits with its Left). Walked
    -- right-to-left so the cons chain is built bottom-up without recursion.
    getArgsHelper =
      SConst "__getArgs"
        $ EArrow
          []
          [ SConst "args" (ECall (EMember (EMember (EVar "process") "argv") "slice") [ENum 2]),
            SLet "list" (Just (con0 ptNilTag)),
            SFor
              "i"
              (EBin BSub (EMember (EVar "args") "length") (ENum 1))
              (EBin BGe (EVar "i") (ENum 0))
              (EUpdate UDec (EVar "i"))
              [ SConst "v" (ECall (EVar "__entryArgEither") [EIndex (EVar "args") (EVar "i")]),
                SIf (EBin BNeq (EIndex (EVar "v") (ENum 0)) ptR) [SReturn (EVar "v")] [],
                SExpr (EAssign (EVar "list") (EArray [ptConsTag, EIndex (EVar "v") (ENum 1), EVar "list"]))
              ],
            SReturn (rightV (EVar "list"))
          ]

    -- __stdinReadAll: reads fd 0 to EOF and strict-UTF-8 decodes it via a fatal
    -- TextDecoder (any RFC-3629 malformation → Left InvalidUtf8). 'ignoreBOM:
    -- true' keeps a leading U+FEFF as data, matching the hand-written decoders.
    -- A successful decode is then length-capped.
    stdinReadAllStringHelper =
      SConst "__stdinReadAll"
        $ EArrow
          []
          [ SLet "s" Nothing,
            STry
              [SExpr (EAssign (EVar "s") (ECall (EMember (ENew (EVar "TextDecoder") [EStr "utf-8", EObject [("fatal", EBool True), ("ignoreBOM", EBool True)]]) "decode") [readStdin]))]
              "e"
              [SReturn (leftV (rowOf invalidUtf8Row (con0 ptIU)))],
            SIf (EBin BGt (EMember (EVar "s") "length") (ENum 134217728)) [SReturn (leftV (rowOf stringTooLongRow (con0 ptSTL)))] [],
            SReturn (rightV (EVar "s"))
          ]

    -- __stdinReadAllBytes: reads fd 0 to EOF and returns the raw bytes as a
    -- 'List UInt8', built right-to-left. No decode, no error row.
    stdinReadAllBytesHelper =
      SConst "__stdinReadAllBytes"
        $ EArrow
          []
          [ SConst "buf" readStdin,
            SLet "list" (Just (con0 ptNilTag)),
            SFor
              "i"
              (EBin BSub (EMember (EVar "buf") "length") (ENum 1))
              (EBin BGe (EVar "i") (ENum 0))
              (EUpdate UDec (EVar "i"))
              [SExpr (EAssign (EVar "list") (EArray [ptConsTag, EIndex (EVar "buf") (EVar "i"), EVar "list"]))],
            SReturn (EVar "list")
          ]

    -- require('fs').readFileSync(0) — blocking read of fd 0 to EOF.
    readStdin = ECall (EMember (ECall (EVar "require") [EStr "fs"]) "readFileSync") [ENum 0]

-- | Integer-range coercions, as the JS engines define them: signed 32-bit via
--   @| 0@, unsigned 8-bit via @& 0xFF@, unsigned 32-bit via @>>> 0@.
i32, u8, u32 :: JsExpr -> JsExpr
i32 e = EBin BBitOr e (ENum 0)
u8 e = EBin BBitAnd e (EHex 255)
u32 e = EBin BUShr e (ENum 0)

-- | Node-only runner for CLI scripts: when run as a script (not @require@-d),
--   walk @main@'s IO tree for effects. Works inside the IIFE because
--   @require@\/@module@ are closed over from Node's module wrapper.
cliFooter :: [JsStmt]
cliFooter =
  [ SIf
      (EBin BAnd (EBin BNeq (EUnary UTypeof (EVar "require")) (EStr "undefined")) (EBin BEq (EMember (EVar "require") "main") (EVar "module")))
      [SIf (EBin BNeq (EUnary UTypeof (EVar "main")) (EStr "undefined")) [SExpr (ECall (EVar "v_runIO") [EVar "main"])] []]
      []
  ]

-- ════════════════════════════════════════════════════════════════════════════
-- Declarations
-- ════════════════════════════════════════════════════════════════════════════

-- | A top-level declaration becomes a @const@ binding: a 'CFunDef' is an arrow
--   closure (its 'CLoop' body, the output of TCO, becomes a @while (true)@
--   loop whose 'CContinue's rebind the parameters and @continue@); a 'CValDef'
--   is a plain value. A 'CValDef' whose value hoists lets emits them as
--   preceding @const@s — hence a list of statements, kept together (the
--   caller blanks only between declarations, never inside one).
declStmt :: CDecl -> [JsStmt]
declStmt = \case
  CFunDef nm args (CLoop body) -> [SConst (mangle nm) (EArrow (map mangle args) [SWhileTrue (stmtBody Map.empty args body)])]
  CFunDef nm args body -> [SConst (mangle nm) (EArrow (map mangle args) (stmtBody Map.empty args body))]
  CValDef nm rhs -> let (ss, e) = flatE Map.empty rhs in ss <> [SConst (mangle nm) e]

-- ════════════════════════════════════════════════════════════════════════════
-- Statement-form bodies (tail position)
-- ════════════════════════════════════════════════════════════════════════════

-- | A 'CJoin' registered by the tail traversal: its JS label, its parameter
--   names (the assignment targets of every 'CJump' to it), and the @pending@
--   depth at the node — a jump nulls only what was dropped after that point;
--   the rest stays for the join body's own tails.
data JoinTarget = JoinTarget
  { jtLabel :: Text,
    jtParams :: [Name],
    jtPendingBase :: Int
  }

-- | Emit a function body in tail position as a list of statements. Threads a
--   @pending@ stack of 'CDrop'-named parameters, drained at every terminator:
--   a param dropped at a value tail is nulled after the value is captured (a
--   managed-GC early root snip — a JS variable is a GC root until reassigned);
--   a param a 'CContinue' rebinds needs no null (the rebind is the snip, and
--   nothing allocates between). 'CDrop' on a 'CCase' arm-binder is a no-op:
--   those are @const@, block-scoped, and collected when the arm closes.
--
--   A 'CJoin' declares one uninitialised @let@ slot per parameter (at the
--   node, not a prologue — a @let@ in a loop body is a fresh per-iteration
--   binding, not stack growth), wraps its inner expression in a labelled
--   block and lays the join body right after it. Inner value tails @return@
--   (and 'CContinue' arms @continue@) past the body; a 'CJump' assigns the
--   slots directly — the parameters are in scope only inside the body, so
--   a jump argument cannot read them and the 'CContinue' temp-snapshot
--   discipline is unnecessary — nulls the parameters dropped since the node
--   (the jumping arm's deaths; the body still runs inside this function, so
--   they would stay GC roots through it) and @break@s to the label. The
--   body is emitted without the join's own registration: a self-jump is
--   illegal in Core, and an unregistered jump fails loudly here rather than
--   as a SyntaxError from Node.
stmtBody :: Map Name [Name] -> [Name] -> CExpr -> [JsStmt]
stmtBody apv0 params = go apv0 Map.empty []
  where
    -- @apv@ — arm-pattern-by-scrut: the binders of the innermost enclosing
    -- case arm per scrutinee name, consulted by the 'CReuse' store
    -- schedule ('Awsum.Codegen.ReuseSchedule').
    go :: Map Name [Name] -> Map Name JoinTarget -> [Name] -> CExpr -> [JsStmt]
    go apv joins pending = \case
      -- Parallel assignment: every new value must read the /previous/
      -- iteration's parameters. The rebind is scheduled like a parallel
      -- copy. A parameter passed through unchanged needs no statement and
      -- never conflicts (its old and new value coincide). Of the rest,
      -- parameter k is assignable while no *remaining* argument reads it —
      -- picking the lowest assignable index each round keeps an
      -- already-valid parameter order untouched and otherwise reorders the
      -- direct assignments (an argument may read its own parameter: a JS
      -- assignment evaluates its right side before the store). The check
      -- also guarantees each argument is evaluated before any parameter it
      -- reads is overwritten: a parameter read by a remaining argument is
      -- not assignable. What survives is a genuine cycle — a swap — and
      -- only those parameters snapshot through @__t@ consts; their
      -- arguments read only still-unassigned parameters, so the direct
      -- prefix cannot have clobbered them. Reordering also reorders
      -- argument evaluation, which is sound only when no sibling argument
      -- can observe it. An effectful argument (not produced today — the
      -- platform primitives live only in @runIO@, whose rebind argument is
      -- a projection) falls back to the order-preserving full snapshot. A
      -- 'CReuse' is observable more narrowly — it overwrites the cell its
      -- binder names, so only a sibling mentioning that same binder can
      -- see the difference — and constrains exactly that pair: a
      -- cell-conflicting pair must keep its source evaluation order, an
      -- extra edge in the same greedy schedule. A pair the slot rule or
      -- this edge cannot order lands in the remainder together, and the
      -- temps evaluate in source order — which is how the @$apply@
      -- dispatchers' projection-then-reuse pair (the one shape where the
      -- reorder hands the next iteration a clobbered field) comes out
      -- snapshotted while an unrelated reuse stays a direct assignment.
      -- 'binderUsedIn' is the same read predicate binder elision uses.
      CContinue newArgs ->
        let paramAt k = fromMaybe (error "JS codegen: CContinue arity differs from the parameter list (Tco invariant)") (params !!? k)
            argAt k = fromMaybe (error "JS codegen: CContinue arity differs from the parameter list (Tco invariant)") (newArgs !!? k)
            selfPass k = argAt k == CVar (paramAt k)
            readsP j k = binderUsedIn (paramAt k) (argAt j)
            cellConflict j k =
              any (\n -> binderUsedIn n (argAt k)) (reusedBinders (argAt j))
                || any (\n -> binderUsedIn n (argAt j)) (reusedBinders (argAt k))
            schedule done remaining =
              case [k | k <- remaining, all (\j -> j == k || (not (readsP j k) && (j > k || not (cellConflict j k)))) remaining] of
                (k : _) -> schedule (done <> [k]) (filter (/= k) remaining)
                [] -> (done, remaining)
            (direct, cyclic) =
              if any effectfulIn newArgs
                then ([], [0 .. length newArgs - 1])
                else schedule [] [k | k <- [0 .. length newArgs - 1], not (selfPass k)]
            directAssigns = [SExpr (EAssign (EVar (mangle (paramAt k))) (exprE apv (argAt k))) | k <- direct]
            temps = [(k, "__t" <> show k) | k <- cyclic]
            decls = [SConst t (exprE apv (argAt k)) | (k, t) <- temps]
            assigns = [SExpr (EAssign (EVar (mangle (paramAt k))) (EVar t)) | (k, t) <- temps]
         in directAssigns <> decls <> assigns <> [SContinue]
      CCase scrut alts ->
        switchOn apv scrut (\scrutE -> map (stmtAlt apv (scrutName scrut) scrutE joins pending) alts)
      CRowCase scrut alts ->
        switchOn apv scrut (\scrutE -> map (stmtRowAlt apv scrutE joins pending) alts)
      CDrop n body -> go apv joins (n : pending) body
      -- A let in tail position binds a block-scoped @const@ and the body
      -- continues the statement spine (so arm-tail returns, continues and
      -- pending drops all flow through unchanged). The rhs flattens first, so
      -- its own nested lets land as @const@s just above this one.
      CLet x rhs body ->
        let (ss, re) = flatE apv rhs
         in ss <> (SConst (mangle x) re : go apv joins pending body)
      CJoin j ps body inner ->
        let target = JoinTarget {jtLabel = joinLabel j, jtParams = ps, jtPendingBase = length pending}
            slots = [SLet (mangle p) Nothing | p <- ps]
            -- A lone block (the usual case dispatch) splices into the
            -- labelled block — same scope, no doubled braces.
            innerStmts = case go apv (Map.insert j target joins) pending inner of
              [SBlock ss] -> ss
              ss -> ss
         in slots <> (SLabeled (jtLabel target) innerStmts : go apv joins pending body)
      CJump j args ->
        let JoinTarget label ps base =
              Map.findWithDefault
                (error "JS codegen: CJump to a join not registered by an enclosing CJoin (Core invariant: jumps appear only in the tail positions of their join's inner expression)")
                j
                joins
            (hoisted, argEs) = flatChildren apv args
            assigns = [SExpr (EAssign (EVar (mangle p)) e) | (p, e) <- zip ps argEs]
            dead = filter (`elem` params) (take (length pending - base) pending)
            nulls = [SExpr (EAssign (EVar (mangle n)) ENull) | n <- dead]
         in hoisted <> assigns <> nulls <> [SBreak label]
      e ->
        let (ss, ev) = flatE apv e
            paramPending = filter (`elem` params) pending
         in if null paramPending
              then ss <> [SReturn ev]
              else [SBlock (ss <> (SConst "__d" ev : [SExpr (EAssign (EVar (mangle n)) ENull) | n <- paramPending] <> [SReturn (EVar "__d")]))]

    -- Dispatch head of a statement-form case. The scrutinee must be
    -- evaluated exactly once, so in general it lands in a block-scoped
    -- @__s@ (the block exists solely to scope it). A scrutinee that is
    -- already a variable needs no alias: a JS binding is a reference, so
    -- @__s@ and the variable name the same cell at every read — dispatch
    -- and field reads go through the variable directly.
    scrutName :: CExpr -> Maybe Name
    scrutName = \case
      CVar n -> Just n
      _ -> Nothing

    switchOn :: Map Name [Name] -> CExpr -> (JsExpr -> [(Integer, [JsStmt])]) -> [JsStmt]
    switchOn _ (CVar n) mkCases = let scrutE = EVar (mangle n) in [SSwitch (EIndex scrutE (ENum 0)) (mkCases scrutE)]
    switchOn apv scrut mkCases =
      let (ss, se) = flatE apv scrut
       in [SBlock (ss <> (SConst "__s" se : [SSwitch (EIndex (EVar "__s") (ENum 0)) (mkCases (EVar "__s"))]))]

    stmtAlt :: Map Name [Name] -> Maybe Name -> JsExpr -> Map Name JoinTarget -> [Name] -> (Int, [Name], CExpr) -> (Integer, [JsStmt])
    stmtAlt apv mScrut scrutE joins pending (tag, vars, body) =
      let apv' = maybe apv (\n -> Map.insert n vars apv) mScrut
          elided = maybe Set.empty (\n -> reuseSlotElided (const True) n vars body) mScrut
          binds = [SConst (mangle v) (EIndex scrutE (ENum (toInteger i))) | (v, i) <- zip vars [1 :: Int ..], binderUsedIn v body, not (Set.member v elided)]
       in (toInteger tag, binds <> go apv' joins pending body)

    stmtRowAlt :: Map Name [Name] -> JsExpr -> Map Name JoinTarget -> [Name] -> (Word32, Name, CExpr) -> (Integer, [JsStmt])
    stmtRowAlt apv scrutE joins pending (tag, var, body) =
      let binds = [SConst (mangle var) (EIndex scrutE (ENum 1)) | binderUsedIn var body]
       in (toInteger tag, binds <> go apv joins pending body)

-- | A join point's JS label: the Core name itself — the minted @$join<k>@ is
--   a valid JS identifier (@$@ included), labels live in a namespace separate
--   from variables, and join names are globally unique, so two labels in one
--   function cannot collide. Sanitised like 'mangle' (sans prefix) so any
--   future name shape still renders as a valid label.
joinLabel :: Name -> Text
joinLabel = T.map (\c -> if Char.isAlphaNum c || c == '_' || c == '$' then c else '_')

-- ════════════════════════════════════════════════════════════════════════════
-- Expression-form
-- ════════════════════════════════════════════════════════════════════════════

-- | Lower an expression for a position with no statement spine, forcing any
--   hoistable let-bindings into a single zero-arg IIFE. Boundaries that /do/
--   have a spine call 'flatE' and splice its statements, so this wrapper
--   fires only where there is genuinely nowhere to put a statement: a 'CCon'
--   field or 'CCall' argument blocked behind a non-movable sibling, a
--   'CReuse' store operand, a 'CContinue' rebind argument. Even then it is one
--   closure for the whole expression's lets, never one per let.
exprE :: Map Name [Name] -> CExpr -> JsExpr
exprE apv e = case flatE apv e of
  ([], je) -> je
  (ss, je) -> ECall (EArrow [] (ss <> [SReturn je])) []

-- | Lower an expression, hoisting the let-bindings reachable along strict,
--   unconditional positions ('CCon' fields, 'CCall' callee\/arguments, 'CRow'
--   payload, 'CCase'\/'CRowCase' scrutinees) into preceding @const@ statements
--   returned alongside the residual expression. The statements run first;
--   together they evaluate exactly what the expression denotes, but a hoisted
--   @let@ becomes @const v = rhs;@ instead of the @((v) => …)(rhs)@ IIFE that
--   allocates a closure on every evaluation.
--
--   A hoisted binding keeps the @let@'s own binder — globally unique by the
--   inliner's mint and 'Awsum.UniquifyLocals' — so a bubbling region never
--   needs (or invents) a fresh temp name.
--
--   Conditional and loop nodes stay opaque: a 'CCase'\/'CRowCase'\/'CJoin'
--   renders with its own statement spine inside the dispatch arrow, and
--   'flatE' bubbles only its scrutinee, never through its arms — those are
--   conditional, so their bindings must stay inside them.
flatE :: Map Name [Name] -> CExpr -> ([JsStmt], JsExpr)
flatE apv = \case
  CString s -> noStmt (EStr s)
  CVar n -> noStmt (EVar (mangle n))
  CIntLit n TInt32 -> noStmt (i32 (ENum n))
  CIntLit n TUInt8 -> noStmt (u8 (ENum n))
  CIntLit n TUInt32 -> noStmt (u32 (ENum n))
  CBuiltIn n -> error ("JS codegen: CBuiltIn '" <> n <> "' in term position (invariant: only in CCall callee)")
  CCon tag fields ->
    let (ss, es) = flatChildren apv fields
     in (ss, EArray (ENum (toInteger tag) : es))
  -- A single payload: its residual is last in evaluation order, so its
  -- statements bubble with no sibling to reorder against.
  CRow tag v ->
    let (ss, e) = flatE apv v
     in (ss, EArray [ENum (toInteger tag), e])
  CDrop _ body -> flatE apv body
  -- A guarded reuse cannot mutate here: the cell may be shared (the caller
  -- can retain the structure) and there is no refcount header to check, so
  -- it lowers as the allocation it replaced — a 'CCon' for every purpose,
  -- its fields hoisting like any other. Only a 'ReuseUnique' cell — an Scc
  -- pack / Cps continuation, loop-private by construction — mutates.
  CReuse ReuseGuarded _ tag fields -> flatE apv (CCon tag fields)
  CReuse ReuseUnique n tag fields ->
    -- In-place stores in dependency order ('Awsum.Codegen.ReuseSchedule'):
    -- the acyclic permutation part reads the old slots straight off the
    -- cell, a cycle reads its one extracted binder, unrelated fields evaluate
    -- as ever. The arm extraction skips binders the schedule reads off the
    -- cell ('reuseSlotElided'), which is what returns the inline look. The
    -- node mutates @n@, so it is order-sensitive — opaque to hoisting.
    let v = mangle n
        tagStore = EAssign (EIndex (EVar v) (ENum 0)) (ENum (toInteger tag))
        (stores, _breakers) = scheduleReuse (Map.findWithDefault [] n apv) fields
        fieldAt i = fromMaybe (error "JS codegen: CReuse store schedule slot out of range") (fields !!? (i - 1))
        storeE = \case
          StoreFromSlot dst src -> EAssign (EIndex (EVar v) (ENum (toInteger dst))) (EIndex (EVar v) (ENum (toInteger src)))
          StoreFromBinder dst b -> EAssign (EIndex (EVar v) (ENum (toInteger dst))) (EVar (mangle b))
          StoreExtern dst -> EAssign (EIndex (EVar v) (ENum (toInteger dst))) (exprE apv (fieldAt dst))
     in noStmt (ESeq (tagStore : map storeE stores <> [EVar v]))
  CCase scrut alts ->
    let (ss, se) = flatE apv scrut
     in (ss, caseDispatch se (map (exprAlt (exprScrutName scrut)) alts))
  CRowCase scrut alts ->
    let (ss, se) = flatE apv scrut
     in (ss, caseDispatch se (map exprRowAlt alts))
  CCall f xs -> flatCall apv f xs
  CLoop _ -> error "JS codegen: CLoop in non-tail position (pipeline bug — should only appear at function-body-tail)"
  CContinue _ -> error "JS codegen: CContinue in non-tail position (pipeline bug — should only appear inside a CLoop)"
  -- A let in expression position: hoist @rhs@ to a @const@ in the bubbled
  -- spine, then continue with @body@ — no IIFE. @rhs@'s own sub-lets bubble
  -- first (it is fully evaluated before @body@), so order is preserved.
  CLet x rhs body ->
    let (rs, re) = flatE apv rhs
        (bs, be) = flatE apv body
     in (rs <> (SConst (mangle x) re : bs), be)
  CProj n slot -> noStmt (EIndex (EVar (mangle n)) (ENum (toInteger slot)))
  -- An expression-position join is self-contained (every jump inside targets
  -- a join registered inside — a jump out of a value position is ruled out in
  -- Core), so the statement-form lowering runs inside an immediately-invoked
  -- arrow: value tails @return@ past the join body, jumps @break@ to it.
  e@CJoin {} -> noStmt (ECall (EArrow [] (stmtBody apv [] e)) [])
  CJump {} -> error "JS codegen: CJump outside the tail positions of its join's inner expression (Core invariant)"
  where
    noStmt :: JsExpr -> ([JsStmt], JsExpr)
    noStmt e = ([], e)

    -- An expression-position case dispatches through an immediately-invoked
    -- arrow whose @switch@ arms @return@ directly: @((s) => { switch (s[0]) {
    -- … } })(scrut)@. The arms are the arrow's tail, so their bodies run
    -- through the statement walk ('stmtBody' with no parameters): a leaf
    -- value @return@s as before, while a nested case (or join) continues
    -- the statement spine inside the same arrow instead of opening another
    -- immediately-invoked one — one arrow per case /tree/, not per case.
    -- Bounding the syntactic depth is load-bearing, not cosmetic: V8
    -- recurses while parsing, and a 300-level dispatch chain at one more
    -- nesting step per level overflows its parser stack (@RangeError@
    -- before a single statement runs).
    caseDispatch :: JsExpr -> [(Integer, [JsStmt])] -> JsExpr
    caseDispatch se cases =
      ECall (EArrow ["s"] [SSwitch (EIndex (EVar "s") (ENum 0)) cases]) [se]

    exprScrutName :: CExpr -> Maybe Name
    exprScrutName = \case
      CVar n -> Just n
      _ -> Nothing

    exprAlt :: Maybe Name -> (Int, [Name], CExpr) -> (Integer, [JsStmt])
    exprAlt mScrut (tag, vars, body) =
      let apv' = maybe apv (\n -> Map.insert n vars apv) mScrut
          elided = maybe Set.empty (\n -> reuseSlotElided (const True) n vars body) mScrut
          binds = [SConst (mangle v) (EIndex (EVar "s") (ENum (toInteger i))) | (v, i) <- zip vars [1 :: Int ..], binderUsedIn v body, not (Set.member v elided)]
       in (toInteger tag, binds <> stmtBody apv' [] body)

    exprRowAlt :: (Word32, Name, CExpr) -> (Integer, [JsStmt])
    exprRowAlt (tag, var, body) =
      let binds = [SConst (mangle var) (EIndex (EVar "s") (ENum 1)) | binderUsedIn var body]
       in (toInteger tag, binds <> stmtBody apv [] body)

-- | Lower the children of a strict, left-to-right node ('CCon' fields, a
--   generic 'CCall' callee+arguments, builtin-call arguments), bubbling each
--   child's let-bindings into the returned statement list — but only while
--   every earlier sibling has a /movable/ residual ('movableE': a variable,
--   literal, or pure operator tree over those, immune to reordering). Past the
--   first non-movable sibling, later children keep their own IIFE ('exprE'),
--   so a hoist never floats a computation across an observable evaluation.
--   This is the conservative half of "hoist when it is free": no reordering
--   of observable work, and no synthetic temp names.
flatChildren :: Map Name [Name] -> [CExpr] -> ([JsStmt], [JsExpr])
flatChildren apv = go True
  where
    go _ [] = ([], [])
    go True (c : cs) =
      let (ss, e) = flatE apv c
          (ss', es) = go (movableE e) cs
       in (ss <> ss', e : es)
    go False (c : cs) =
      let (ss', es) = go False cs
       in (ss', exprE apv c : es)

-- | Is this residual safe to evaluate /after/ a later sibling's hoisted
--   statements — does it neither read mutable cell contents, nor mutate, nor
--   perform I/O? A variable read (the binding, not the cell behind it) and a
--   literal qualify, as does any pure operator tree over such operands; a call,
--   a field read ('EIndex'\/'EMember'), an in-place store ('EAssign'\/'ESeq'\/
--   'EUpdate'), a closure, or an allocation with a non-movable element does
--   not. Sufficient, not exact: when it holds, floating a later 'CLet' before
--   this residual cannot change any observation.
movableE :: JsExpr -> Bool
movableE = \case
  EVar _ -> True
  ENum _ -> True
  EHex _ -> True
  EBigInt _ -> True
  EStr _ -> True
  ERegex _ -> True
  EBool _ -> True
  ENull -> True
  EArray xs -> all movableE xs
  EObject kvs -> all (movableE . snd) kvs
  EBin _ a b -> movableE a && movableE b
  EUnary _ a -> movableE a
  ECond c t f -> movableE c && movableE t && movableE f
  EMember _ _ -> False
  EIndex _ _ -> False
  ECall _ _ -> False
  ENew _ _ -> False
  EArrow _ _ -> False
  EAssign _ _ -> False
  EUpdate _ _ -> False
  ESeq _ -> False

-- | A 'CCall'. The callee and arguments are lowered through 'flatChildren'
--   (so their let-bindings hoist along the movable-sibling gate), then a
--   'CBuiltIn' callee dispatches to its runtime-helper shape ('buildBuiltin')
--   over the lowered arguments; any other callee is an ordinary application.
flatCall :: Map Name [Name] -> CExpr -> [CExpr] -> ([JsStmt], JsExpr)
flatCall apv f xs = case f of
  CBuiltIn name ->
    let (ss, es) = flatChildren apv xs
     in (ss, buildBuiltin name es)
  _ ->
    let (ss, es) = flatChildren apv (f : xs)
     in case es of
          (fe : argEs) -> (ss, ECall fe argEs)
          [] -> error "JS codegen: flatCall produced no callee (impossible — f : xs is non-empty)"

-- | The JS shape of a built-in call over its already-lowered argument
--   expressions. A 'CBuiltIn' callee carries no hoistable lets itself, so this
--   is a pure mapping name + args → expression; 'flatCall' owns the argument
--   lowering.
buildBuiltin :: Name -> [JsExpr] -> JsExpr
buildBuiltin name es = case name of
  "internalStdoutPrint" -> unary "__print"
  "internalGetArgs" -> nullaryCall "__getArgs"
  "internalStdinReadAllString" -> nullaryCall "__stdinReadAll"
  "internalStdinReadAllBytes" -> nullaryCall "__stdinReadAllBytes"
  _
    | name `elem` ["showInt32", "showUInt8", "showUInt32"] -> case es of
        [x] -> ECall (EVar "String") [x]
        _ -> arityError name
  "byteToHexStringNoPrefix" -> case es of
    [x] -> ECall (EMember (ECall (EMember x "toString") [ENum 16]) "padStart") [ENum 2, EStr "0"]
    _ -> arityError "byteToHexStringNoPrefix"
  "predInt32" -> unary "__predInt32"
  "predUInt8" -> unary "__predUInt8"
  "predUInt32" -> unary "__predUInt32"
  "succInt32" -> unary "__succInt32"
  "succUInt8" -> unary "__succUInt8"
  "succUInt32" -> unary "__succUInt32"
  "negInt32" -> unary "__negInt32"
  _
    | name `elem` ["eqInt32", "eqUInt8", "eqUInt32", "eqString"] -> binary (helperFor name)
  _
    | name `elem` ["addInt32", "addUInt8", "addUInt32", "subInt32", "subUInt8", "subUInt32", "mulInt32", "mulUInt8", "mulUInt32"] -> binary (helperFor name)
  "concatString" -> binary "__concat"
  "splitOnFirst" -> binary "__splitOnFirst"
  _
    | name `elem` ["parseInt32", "parseUInt8", "parseUInt32"] -> unary (helperFor name)
  _
    | name `elem` ["lengthCodePoints", "lengthUtf16CodeUnits", "lengthUtf8Bytes"] -> unary (helperFor name)
  _ -> error ("JS codegen: unknown builtin '" <> name <> "' reached CCall (typecheck should have rejected it)")
  where
    -- Built-in name → its '__'-prefixed runtime helper.
    helperFor :: Text -> Text
    helperFor n = "__" <> n

    arityError :: Text -> a
    arityError n = error ("BuiltIn." <> n <> ": arity mismatch")

    nullaryCall :: Text -> JsExpr
    nullaryCall fn = case es of
      [] -> ECall (EVar fn) []
      _ -> error (fn <> ": arity mismatch")

    unary :: Text -> JsExpr
    unary fn = case es of
      [x] -> ECall (EVar fn) [x]
      _ -> error (fn <> ": arity mismatch")

    binary :: Text -> JsExpr
    binary fn = case es of
      [a, b] -> ECall (EVar fn) [a, b]
      _ -> error (fn <> ": arity mismatch")

-- | Name mangling: keep @main@ unchanged (the runner calls it by name); every
--   other identifier goes through the shared 'Mangle.mangle'.
mangle :: Name -> Text
mangle t
  | t == "main" = "main"
  | otherwise = Mangle.mangle t
