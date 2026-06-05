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
    -- A blank line between each top-level statement (helper, declaration,
    -- footer) for legibility.
    iifeBody =
      intersperse
        SBlank
        ( header ptags (usedBuiltIns prog)
            <> map declStmt (orderTopLevels prog)
            <> cliFooter
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
        $ EArrow ["a", "b"] [SReturn (ECond (EBin BGt (EBin op (EVar "a") (EVar "b")) (ENum 255)) (leftV (con0 ptOE)) (rightV (u8 (EBin op (EVar "a") (EVar "b")))))]

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
--   is a plain value.
declStmt :: CDecl -> JsStmt
declStmt = \case
  CFunDef nm args (CLoop body) -> SConst (mangle nm) (EArrow (map mangle args) [SWhileTrue (stmtBody args body)])
  CFunDef nm args body -> SConst (mangle nm) (EArrow (map mangle args) (stmtBody args body))
  CValDef nm rhs -> SConst (mangle nm) (exprE rhs)

-- ════════════════════════════════════════════════════════════════════════════
-- Statement-form bodies (tail position)
-- ════════════════════════════════════════════════════════════════════════════

-- | Emit a function body in tail position as a list of statements. Threads a
--   @pending@ stack of 'CDrop'-named parameters, drained at every terminator:
--   a param dropped at a value tail is nulled after the value is captured (a
--   managed-GC early root snip — a JS variable is a GC root until reassigned);
--   a param a 'CContinue' rebinds needs no null (the rebind is the snip, and
--   nothing allocates between). 'CDrop' on a 'CCase' arm-binder is a no-op:
--   those are @const@, block-scoped, and collected when the arm closes.
stmtBody :: [Name] -> CExpr -> [JsStmt]
stmtBody params = go []
  where
    go :: [Name] -> CExpr -> [JsStmt]
    go pending = \case
      CContinue newArgs ->
        let temps = ["__t" <> show (i :: Int) | i <- [0 .. length newArgs - 1]]
            decls = [SConst t (exprE a) | (t, a) <- zip temps newArgs]
            assigns = [SExpr (EAssign (EVar (mangle p)) (EVar t)) | (p, t) <- zip params temps]
         in decls <> assigns <> [SContinue]
      CCase scrut alts ->
        [SBlock (SConst "__s" (exprE scrut) : [SSwitch (EIndex (EVar "__s") (ENum 0)) (map (stmtAlt pending) alts)])]
      CRowCase scrut alts ->
        [SBlock (SConst "__s" (exprE scrut) : [SSwitch (EIndex (EVar "__s") (ENum 0)) (map (stmtRowAlt pending) alts)])]
      CDrop _ n body -> go (n : pending) body
      e ->
        let paramPending = filter (`elem` params) pending
         in if null paramPending
              then [SReturn (exprE e)]
              else [SBlock (SConst "__d" (exprE e) : [SExpr (EAssign (EVar (mangle n)) ENull) | n <- paramPending] <> [SReturn (EVar "__d")])]

    stmtAlt :: [Name] -> (Int, [Name], CExpr) -> (Integer, [JsStmt])
    stmtAlt pending (tag, vars, body) =
      let binds = [SConst (mangle v) (EIndex (EVar "__s") (ENum (toInteger i))) | (v, i) <- zip vars [1 :: Int ..]]
       in (toInteger tag, binds <> go pending body)

    stmtRowAlt :: [Name] -> (Word32, Name, CExpr) -> (Integer, [JsStmt])
    stmtRowAlt pending (tag, var, body) =
      (toInteger tag, SConst (mangle var) (EIndex (EVar "__s") (ENum 1)) : go pending body)

-- ════════════════════════════════════════════════════════════════════════════
-- Expression-form
-- ════════════════════════════════════════════════════════════════════════════

exprE :: CExpr -> JsExpr
exprE = \case
  CString s -> EStr s
  CVar n -> EVar (mangle n)
  CIntLit n TInt32 -> i32 (ENum n)
  CIntLit n TUInt8 -> u8 (ENum n)
  CIntLit n TUInt32 -> u32 (ENum n)
  CBuiltIn n -> error ("JS codegen: CBuiltIn '" <> n <> "' in term position (invariant: only in CCall callee)")
  CCon tag fields -> EArray (ENum (toInteger tag) : map exprE fields)
  CRow tag v -> EArray [ENum (toInteger tag), exprE v]
  CDrop _ _ body -> exprE body
  CReuse n tag fields ->
    let v = mangle n
        tagStore = EAssign (EIndex (EVar v) (ENum 0)) (ENum (toInteger tag))
        fieldStores = [EAssign (EIndex (EVar v) (ENum (toInteger i))) (exprE fld) | (fld, i) <- zip fields [1 :: Int ..]]
     in ESeq (tagStore : fieldStores <> [EVar v])
  CCase scrut alts -> exprCall (map exprAlt alts) scrut
  CRowCase scrut alts -> exprCall (map exprRowAlt alts) scrut
  CCall f xs -> callExpr f xs
  CLoop _ -> error "JS codegen: CLoop in non-tail position (pipeline bug — should only appear at function-body-tail)"
  CContinue _ -> error "JS codegen: CContinue in non-tail position (pipeline bug — should only appear inside a CLoop)"
  where
    -- An expression-position case dispatches through an immediately-invoked
    -- arrow whose @switch@ arms @return@ directly: @((s) => { switch (s[0]) {
    -- … } })(scrut)@.
    exprCall :: [(Integer, [JsStmt])] -> CExpr -> JsExpr
    exprCall cases scrut =
      ECall (EArrow ["s"] [SSwitch (EIndex (EVar "s") (ENum 0)) cases]) [exprE scrut]

    exprAlt :: (Int, [Name], CExpr) -> (Integer, [JsStmt])
    exprAlt (tag, vars, body) =
      let binds = [SConst (mangle v) (EIndex (EVar "s") (ENum (toInteger i))) | (v, i) <- zip vars [1 :: Int ..]]
       in (toInteger tag, binds <> [SReturn (exprE body)])

    exprRowAlt :: (Word32, Name, CExpr) -> (Integer, [JsStmt])
    exprRowAlt (tag, var, body) =
      (toInteger tag, [SConst (mangle var) (EIndex (EVar "s") (ENum 1)), SReturn (exprE body)])

-- | A 'CCall'. A 'CBuiltIn' callee dispatches to its runtime helper (or an
--   inlined form); any other callee is an ordinary application.
callExpr :: CExpr -> [CExpr] -> JsExpr
callExpr f xs = case f of
  CBuiltIn "internalStdoutPrint" -> unary "__print"
  CBuiltIn "internalGetArgs" -> nullaryCall "__getArgs"
  CBuiltIn "internalStdinReadAllString" -> nullaryCall "__stdinReadAll"
  CBuiltIn "internalStdinReadAllBytes" -> nullaryCall "__stdinReadAllBytes"
  CBuiltIn name
    | name `elem` ["showInt32", "showUInt8", "showUInt32"] -> case xs of
        [x] -> ECall (EVar "String") [exprE x]
        _ -> arityError name
  CBuiltIn "byteToHexStringNoPrefix" -> case xs of
    [x] -> ECall (EMember (ECall (EMember (exprE x) "toString") [ENum 16]) "padStart") [ENum 2, EStr "0"]
    _ -> arityError "byteToHexStringNoPrefix"
  CBuiltIn "predInt32" -> unary "__predInt32"
  CBuiltIn "predUInt8" -> unary "__predUInt8"
  CBuiltIn "predUInt32" -> unary "__predUInt32"
  CBuiltIn "succInt32" -> unary "__succInt32"
  CBuiltIn "succUInt8" -> unary "__succUInt8"
  CBuiltIn "succUInt32" -> unary "__succUInt32"
  CBuiltIn "negInt32" -> unary "__negInt32"
  CBuiltIn name
    | name `elem` ["eqInt32", "eqUInt8", "eqUInt32", "eqString"] -> binary (helperFor name)
  CBuiltIn name
    | name `elem` ["addInt32", "addUInt8", "addUInt32", "subInt32", "subUInt8", "subUInt32", "mulInt32", "mulUInt8", "mulUInt32"] -> binary (helperFor name)
  CBuiltIn "concatString" -> binary "__concat"
  CBuiltIn "splitOnFirst" -> binary "__splitOnFirst"
  CBuiltIn name
    | name `elem` ["parseInt32", "parseUInt8", "parseUInt32"] -> unary (helperFor name)
  CBuiltIn name
    | name `elem` ["lengthCodePoints", "lengthUtf16CodeUnits", "lengthUtf8Bytes"] -> unary (helperFor name)
  CBuiltIn n -> error ("JS codegen: unknown builtin '" <> n <> "' reached CCall (typecheck should have rejected it)")
  _ -> ECall (exprE f) (map exprE xs)
  where
    -- 'CBuiltIn' name → its '__'-prefixed runtime helper.
    helperFor :: Text -> Text
    helperFor n = "__" <> n

    arityError :: Text -> a
    arityError n = error ("BuiltIn." <> n <> ": arity mismatch")

    nullaryCall :: Text -> JsExpr
    nullaryCall fn = case xs of
      [] -> ECall (EVar fn) []
      _ -> error (fn <> ": arity mismatch")

    unary :: Text -> JsExpr
    unary fn = case xs of
      [x] -> ECall (EVar fn) [exprE x]
      _ -> error (fn <> ": arity mismatch")

    binary :: Text -> JsExpr
    binary fn = case xs of
      [a, b] -> ECall (EVar fn) [exprE a, exprE b]
      _ -> error (fn <> ": arity mismatch")

-- | Name mangling: keep @main@ unchanged (needed by the runner); otherwise
--   prefix with @v_@ and replace any non @[A-Za-z0-9_']@ character with @_@.
mangle :: Name -> Text
mangle t
  | t == "main" = "main"
  | otherwise = "v_" <> T.map (\c -> if ok c then c else '_') t
  where
    ok c = Char.isAlphaNum c || c == '_' || c == '\''
