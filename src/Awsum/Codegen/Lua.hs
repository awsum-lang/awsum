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
import Awsum.Syntax (Name)
import Data.Char qualified as Char
import Data.Set qualified as Set
import Data.Text qualified as T
import Relude

-- | Produce a complete Lua chunk: header (runtime) + declarations + footer (runner).
codegenLua :: CoreProgram -> Text
codegenLua prog@(CoreProgram decls) =
  T.intercalate
    "\n"
    [ header (usedBuiltIns prog),
      T.intercalate "\n\n" (map emitDecl decls),
      footer
    ]

-- | Minimal runtime, tree-shaken — only helpers whose built-in is
--   referenced are emitted.
header :: Set Name -> Text
header builtIns =
  let lns =
        filter
          (not . T.null)
          [ if Set.member "IO.Stdout.print" builtIns
              then "local function __print(s) io.write(tostring(s)); return nil end"
              else "",
            -- predInt32: Lua tables are 1-indexed, so tag sits at [1] and field
            -- at [2]. Left/UnderflowError tags both 0; Right tag 1.
            if Set.member "predInt32" builtIns
              then "local function __predInt32(x) if x == -2147483648 then return {0, {0}} else return {1, x - 1} end end"
              else "",
            -- predUInt8: Left UnderflowError on 0, else Right (x - 1). Since
            -- x >= 1 implies (x - 1) is in 0..254, no mask is needed to
            -- keep the result inside UInt8 range.
            if Set.member "predUInt8" builtIns
              then "local function __predUInt8(x) if x == 0 then return {0, {0}} else return {1, x - 1} end end"
              else "",
            -- eqInt32 / eqUInt8: True=0, False=1 for `type Bool = True | False`.
            -- Nullary constructors are one-slot tables holding only the tag.
            if Set.member "eqInt32" builtIns
              then "local function __eqInt32(a, b) if a == b then return {0} else return {1} end end"
              else "",
            if Set.member "eqUInt8" builtIns
              then "local function __eqUInt8(a, b) if a == b then return {0} else return {1} end end"
              else ""
          ]
   in T.intercalate "\n" lns <> "\n"

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
--   • 'CFunDef' with a 'CLoop' body (product of the TCO pass) → a
--     @while true do ... end@ loop whose body is emitted in statement
--     form. 'CContinue' rebinds the function's parameters and lets
--     control fall through to the loop's next iteration; any other tail
--     position emits an explicit @return@. Lua 5.3+ already has proper
--     tail calls for @return f(...)@, but we rewrite uniformly so the
--     generated program is stack-safe on 5.1 too and consistent with the
--     other backends.
--   • 'CFunDef' without a 'CLoop' wrapper → plain @return <expr>@.
--   • 'CValDef' → /global/ assignment @name = <expr>@.
emitDecl :: CDecl -> Text
emitDecl = \case
  CFunDef nm args (CLoop body) ->
    "function "
      <> mangle nm
      <> "("
      <> T.intercalate ", " (map mangle args)
      <> ")\n"
      <> "  while true do\n"
      <> emitStmt args body
      <> "  end\n"
      <> "end"
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

-- | Statement-form emission for the body wrapped by 'CLoop'.
-- Lua has no @continue@ keyword (before 5.2's @goto@, and even then
-- with limits), but the structure of @while true do ... end@ lets us
-- emulate it: a 'CContinue' arm rebinds the function's parameters and
-- control falls through to the end of the while body, which iterates.
-- Other tail arms emit an explicit @return@.
--
-- New parameter values are stashed in temporaries first, so evaluating
-- a new value that reads a still-old parameter (e.g. @acc .. "."@) sees
-- the old binding rather than a half-updated one.
emitStmt :: [Name] -> CExpr -> Text
emitStmt params = go
  where
    go :: CExpr -> Text
    go = \case
      CContinue newArgs ->
        let temps = ["__t" <> show (i :: Int) | i <- [0 .. length newArgs - 1]]
            declLines =
              [ "    local " <> t <> " = " <> emitExpr a
              | (t, a) <- zip temps newArgs
              ]
            assignLines =
              [ "    " <> mangle p <> " = " <> t
              | (p, t) <- zip params temps
              ]
         in unlines (declLines <> assignLines)
      CCase scrut alts ->
        "    local __s = "
          <> emitExpr scrut
          <> "\n"
          <> emitStmtAlts alts
      e ->
        "    return " <> emitExpr e <> "\n"

    emitStmtAlts :: [(Int, [Name], CExpr)] -> Text
    emitStmtAlts [] = ""
    emitStmtAlts ((tag, vars, body) : rest) =
      let bindings =
            T.concat
              [ "      local " <> mangle v <> " = __s[" <> show (i :: Int) <> "]\n"
              | (v, i) <- zip vars [2 ..]
              ]
          headLine = "    if __s[1] == " <> show tag <> " then\n"
          tail' = case rest of
            [] -> "    end\n"
            _ -> emitElseAlts rest
       in headLine <> bindings <> reindentStmt (go body) <> tail'

    emitElseAlts :: [(Int, [Name], CExpr)] -> Text
    emitElseAlts [] = "    end\n"
    emitElseAlts ((tag, vars, body) : rest) =
      let bindings =
            T.concat
              [ "      local " <> mangle v <> " = __s[" <> show (i :: Int) <> "]\n"
              | (v, i) <- zip vars [2 ..]
              ]
          headLine = "    elseif __s[1] == " <> show tag <> " then\n"
       in headLine <> bindings <> reindentStmt (go body) <> emitElseAlts rest

    -- Bump non-empty lines by two spaces so statements inside a branch
    -- sit visibly deeper than the @if__ then@ header.
    reindentStmt :: Text -> Text
    reindentStmt = unlines . map bump . lines
      where
        bump l = if T.null (T.strip l) then l else "  " <> l

-- | Expressions:
--   • 'CBuiltIn' is never a standalone value — only appears as the callee of 'CCall'.
--   • 'IO.Stdout.print' → '__print(x)'.
--   • 'BuiltIn.concatString' → '(a .. b)' (or 'table.concat' for long chains).
--   • 'BuiltIn.showInt32' / 'BuiltIn.showUInt8' → 'tostring(x)'. Works
--     identically on Lua 5.1 and 5.3+. On 5.1 every number is an IEEE-754
--     double, but Int32 (max ~2e9) and UInt8 (max 255) fit well below 2^53,
--     so the double representation is exact. 'tostring' uses '%.14g' which
--     formats these values in normal (non-scientific) notation. When we
--     add Int64 (> 2^53) we'll lose precision on 5.1 — either restrict
--     to 5.3+ or emit integer operations via 'math.floor'/'math.fmod' to
--     stay uniform.
--   • Generic calls: '(callee)(args...)' with a safe parenthesized callee.
emitExpr :: CExpr -> Text
emitExpr = \case
  CString s -> luaString s
  CVar n -> mangle n
  CIntLit n _ -> show n
  CBuiltIn n -> "--<builtin " <> n <> ">" -- invariant: not a standalone term
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
      CBuiltIn "IO.Stdout.print" ->
        case xs of
          [x] -> "__print(" <> emitExpr x <> ")"
          _ -> error "__print: arity mismatch"
      CBuiltIn name
        | name == "showInt32" || name == "showUInt8" ->
            case xs of
              [x] -> "tostring(" <> emitExpr x <> ")"
              _ -> error ("BuiltIn." <> name <> ": arity mismatch")
      CBuiltIn "predInt32" ->
        case xs of
          [x] -> "__predInt32(" <> emitExpr x <> ")"
          _ -> error "BuiltIn.predInt32: arity mismatch"
      CBuiltIn "predUInt8" ->
        case xs of
          [x] -> "__predUInt8(" <> emitExpr x <> ")"
          _ -> error "BuiltIn.predUInt8: arity mismatch"
      CBuiltIn name
        | name == "eqInt32" || name == "eqUInt8" ->
            case xs of
              [a, b] ->
                let fn = if name == "eqInt32" then "__eqInt32" else "__eqUInt8"
                 in fn <> "(" <> emitExpr a <> ", " <> emitExpr b <> ")"
              _ -> error ("BuiltIn." <> name <> ": arity mismatch")
      CBuiltIn "concatString" ->
        case xs of
          [a, b] ->
            let parts = flattenConcat a ++ flattenConcat b
             in if length parts > 2
                  then "table.concat({" <> T.intercalate ", " (map emitExpr parts) <> "})"
                  else "(" <> emitExpr a <> " .. " <> emitExpr b <> ")"
          _ -> error "BuiltIn.concatString: arity mismatch"
      CBuiltIn n ->
        error ("Lua codegen: unknown builtin '" <> n <> "' reached CCall (typecheck should have rejected it)")
      _ ->
        "(" <> emitExpr f <> ")(" <> T.intercalate ", " (map emitExpr xs) <> ")"
  CLoop _ -> error "Lua codegen: CLoop survived untcoProgram (pipeline bug)"
  CContinue _ -> error "Lua codegen: CContinue survived untcoProgram (pipeline bug)"
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

-- | Flatten nested 'BuiltIn.concatString' calls into a flat list of operands.
--   This avoids deep Lua C-stack recursion for long '++' chains (e.g. 300 terms).
flattenConcat :: CExpr -> [CExpr]
flattenConcat (CCall (CBuiltIn "concatString") [a, b]) = flattenConcat a ++ flattenConcat b
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
