-- | JavaScript code generator for Awsum 'Core'.
--
-- Design goals:
--   • Emit small, readable JS that is easy to snapshot-test.
--   • Keep a tiny “runtime” in 'header' only for what we actually need.
--   • Preserve Core invariants: primitives only appear in callee position.
--
-- Semantics & assumptions:
--   • Strings: we rely on JS '+' to concatenate (both operands are statically 'String').
--   • Zero-arg surface defs are lowered to Core 'CValDef' and become JS 'const' values.
--     Functions remain 'function' declarations (hoisted), so call order is safe.
--   • The footer includes a tiny Node runner: `node out.js <input>`.
module Awsum.Codegen.JS (codegenJS) where

import Awsum.Core
import Data.Char qualified as Char
import Data.Text qualified as T
import Relude

-- | Produce a complete JS file: header (runtime) + declarations + footer (runner).
codegenJS :: CoreProgram -> Text
codegenJS (CoreProgram decls) =
  T.intercalate
    "\n"
    [ header,
      T.intercalate "\n\n" (map emitDecl decls),
      footer
    ]

-- | Minimal runtime:
--   • '__print' writes without a newline (Awsum's 'IO.Stdout.print' is "print exactly").
--   Note: we intentionally skip a '__concat' helper — '+' is fine because both operands
--   are statically strings under our typechecker.
header :: Text
header =
  T.unlines
    [ "\"use strict\";",
      "function __print(s){ process.stdout.write(String(s)); return undefined; }"
    ]

-- | Node-only convenience runner:
--   when run as a script, call 'main' with a single command-line argument (or empty).
footer :: Text
footer =
  T.unlines
    [ "",
      "if (typeof require !== 'undefined' && require.main === module) {",
      "  const arg = process.argv[2] ?? \"\";",
      "  if (typeof main === 'function') main(arg);",
      "}"
    ]

-- | Top-level declarations:
--   • 'CFunDef' → function declaration returning the rendered body.
--   • 'CValDef' → 'const name = <expr>;' (zero-arg defs are constants).
emitDecl :: CDecl -> Text
emitDecl = \case
  CFunDef nm args body ->
    "function "
      <> mangle nm
      <> "("
      <> T.intercalate ", " (map mangle args)
      <> "){\n"
      <> "  return "
      <> emitExpr body
      <> ";\n"
      <> "}"
  CValDef nm rhs ->
    "const " <> mangle nm <> " = " <> emitExpr rhs <> ";"

-- | Expressions:
--   • 'CPrim' is never a standalone value — it only appears in the callee of 'CCall'.
--   • 'PrimConcat' turns into '(a + b)'.
--   • 'PrimPrint' turns into '__print(x)'.
--   • Generic calls: '(callee)(args...)' — we parenthesize the callee to be safe.
emitExpr :: CExpr -> Text
emitExpr = \case
  CString s -> jsString s
  CVar n -> mangle n
  CPrim PrimConcat -> "/*<prim concat>*/" -- invariant: not a standalone term
  CPrim PrimPrint -> "/*<prim print>*/" -- invariant: not a standalone term
  CCall f xs ->
    case f of
      CPrim PrimConcat ->
        case xs of
          [a, b] -> "(" <> emitExpr a <> " + " <> emitExpr b <> ")"
          _ -> error "__concat: arity mismatch"
      CPrim PrimPrint ->
        case xs of
          [x] -> "__print(" <> emitExpr x <> ")"
          _ -> error "__print: arity mismatch"
      _ ->
        "(" <> emitExpr f <> ")(" <> T.intercalate ", " (map emitExpr xs) <> ")"

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
      _ -> T.singleton c

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
