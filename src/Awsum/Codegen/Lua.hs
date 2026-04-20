-- | Lua code generator for Awsum 'Core'.
--
-- Design goals:
--   • Emit tiny, readable Lua with a minimal runtime in 'header'.
--   • Keep output stable for snapshot tests (no formatting noise).
--   • Mirror JS backend semantics where possible (concat, print).
--
-- Semantics & assumptions:
--   • Strings: we concatenate with Lua's "..". The typechecker guarantees both
--     operands are 'String' in Awsum, so no coercion surprises here.
--   • Zero-arg surface defs are lowered to Core 'CValDef' and become /globals/
--     (see 'emitDecl'): this keeps them visible from any function regardless of
--     declaration order. Functions ('CFunDef') are top-level too.
--     By the time the footer calls 'main', all top-level assignments have run,
--     so globals (constants) are initialized.
--   • The footer tries to run the chunk only when executed as a script, not when
--     loaded via 'require'. Lua lacks a perfect "main module" check, so we use
--     a best-effort 'debug.getinfo' probe (guarded by pcall).
module Awsum.Codegen.Lua (codegenLua) where

import Awsum.Core
import Data.Char qualified as Char
import Data.Text qualified as T
import Relude

-- | Produce a complete Lua chunk: header (runtime) + declarations + footer (runner).
codegenLua :: CoreProgram -> Text
codegenLua (CoreProgram decls) =
  T.intercalate
    "\n"
    [ header,
      T.intercalate "\n\n" (map emitDecl decls),
      footer
    ]

-- | Minimal runtime:
--   • '__print' writes without a newline (Awsum's IO.Stdout.print is "print exactly").
header :: Text
header =
  unlines
    [ "local function __print(s) io.write(tostring(s)); return nil end"
    ]

-- | Best-effort "run if this is the main chunk":
--   • If 'debug' is available, check current chunk's 'what' == 'main'.
--   • Otherwise assume it's a script (common for embedded Lua).
--   Then call 'main' with a single argument (or empty string) if it exists.
footer :: Text
footer =
  unlines
    [ "",
      "local ok, dbg = pcall(require, 'debug')",
      "local should_run = false",
      "if ok and dbg and dbg.getinfo then",
      "  local info = dbg.getinfo(1, 'S')",
      "  should_run = info and info.what == 'main'",
      "else",
      "  should_run = true",
      "end",
      "if should_run then",
      "  local input = (_G and _G.arg and _G.arg[1]) or \"\"",
      "  if type(main) == 'function' then main(input) end",
      "end"
    ]

-- | Top-level declarations:
--   • 'CFunDef' → 'function name(args) ... end'
--   • 'CValDef' → /global/ assignment 'name = <expr>' (see module notes above).
emitDecl :: CDecl -> Text
emitDecl = \case
  CFunDef nm args body ->
    "function "
      <> mangle nm
      <> "("
      <> T.intercalate ", " (map mangle args)
      <> ")\n"
      <> "  return "
      <> emitExpr body
      <> "\n"
      <> "end"
  CValDef nm rhs ->
    mangle nm <> " = " <> emitExpr rhs

-- | Expressions:
--   • 'CPrim' is never a standalone value — only appears as the callee of 'CCall'.
--   • 'PrimConcat' → '(a .. b)'.
--   • 'PrimPrint'  → '__print(x)'.
--   • 'PrimShowInt _' → 'tostring(x)'. Works identically on Lua 5.1 and 5.3+.
--     On 5.1 every number is an IEEE-754 double, but Int32 (max ~2e9) and
--     UInt8 (max 255) fit well below 2^53, so the double representation is
--     exact. 'tostring' uses '%.14g' which formats these values in normal
--     (non-scientific) notation. When we add Int64 (> 2^53) we'll lose
--     precision on 5.1 — either restrict to 5.3+ or emit integer operations
--     via 'math.floor'/'math.fmod' to stay uniform.
--   • Generic calls: '(callee)(args...)' with a safe parenthesized callee.
emitExpr :: CExpr -> Text
emitExpr = \case
  CString s -> luaString s
  CVar n -> mangle n
  CIntLit n _ -> show n
  CPrim PrimConcat -> "--<prim concat>"
  CPrim PrimPrint -> "--<prim print>"
  CPrim (PrimShowInt _) -> "--<prim showInt>"
  CCon tag fields ->
    "{" <> T.intercalate ", " (show tag : map emitExpr fields) <> "}"
  CCase scrut alts ->
    "(function(s) "
      <> emitAlts alts
      <> " end)("
      <> emitExpr scrut
      <> ")"
  CCall f xs ->
    case f of
      CPrim PrimConcat ->
        case xs of
          [a, b] ->
            let parts = flattenConcat a ++ flattenConcat b
             in if length parts > 2
                  then "table.concat({" <> T.intercalate ", " (map emitExpr parts) <> "})"
                  else "(" <> emitExpr a <> " .. " <> emitExpr b <> ")"
          _ -> error "__concat: arity mismatch"
      CPrim PrimPrint ->
        case xs of
          [x] -> "__print(" <> emitExpr x <> ")"
          _ -> error "__print: arity mismatch"
      CPrim (PrimShowInt _) ->
        case xs of
          [x] -> "tostring(" <> emitExpr x <> ")"
          _ -> error "__showInt: arity mismatch"
      _ ->
        "(" <> emitExpr f <> ")(" <> T.intercalate ", " (map emitExpr xs) <> ")"
  where
    emitAlts [] = ""
    emitAlts ((tag, vars, body) : rest) =
      let bindings = T.concat [" local " <> mangle v <> " = s[" <> show (i :: Int) <> "];" | (v, i) <- zip vars [2 ..]]
       in "if s[1] == "
            <> show tag
            <> " then"
            <> bindings
            <> " return "
            <> emitExpr body
            <> case rest of
              [] -> " end"
              _ -> " else" <> emitAlts rest

-- | Flatten nested 'PrimConcat' calls into a flat list of operands.
--   This avoids deep Lua C-stack recursion for long '++' chains (e.g. 300 terms).
flattenConcat :: CExpr -> [CExpr]
flattenConcat (CCall (CPrim PrimConcat) [a, b]) = flattenConcat a ++ flattenConcat b
flattenConcat e = [e]

-- | Encode a Haskell 'Text' as a Lua string literal with escapes.
--   Supported escapes mirror the parser/renderer: \n \t \r \" \\ \0
luaString :: Text -> Text
luaString = \t -> "\"" <> T.concatMap esc t <> "\""
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
