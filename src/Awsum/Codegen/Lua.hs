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
--   • Top-level decls ('CFunDef' and 'CValDef') are emitted as fields of a
--     single module-like local table @M@ (@M.main = function(...)@, @M.foo =
--     ...@). References to top-level names compile to @M.foo@; function
--     parameters and pattern binders remain plain locals.
--
--     Why a table instead of one @local a, b, c@ forward-declaration:
--     Lua's reference compiler caps /active locals per function/ at 200
--     (@MAXVARS@ in @lparser.c@; LuaJIT inherits the limit). A top-level
--     chunk counts as one function, so a program with >200 top-level decls
--     would fail to compile with "too many local variables". The table has
--     no such ceiling — we pay one hash lookup per top-level reference (vs.
--     a register-style local read), which is fine for scripting-tier Lua
--     and lets the backend scale arbitrarily. No-shadowing in Awsum source
--     (see CLAUDE.md) means pattern/param binders never collide with
--     top-level names, so the "is this a top-level?" check is safe.
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

-- | Produce a complete Lua chunk: module table + runtime helpers (as fields
--   of @M@) + top-level declarations (as fields of @M@) + footer (runner).
--
--   The layout puts @local M = {}@ first so both the runtime helpers and the
--   user decls can refer to it uniformly.
codegenLua :: CoreProgram -> Text
codegenLua prog@(CoreProgram decls) =
  let topNames = Set.fromList (map declName decls)
   in T.intercalate
        "\n"
        [ "local M = {}\n",
          header (usedBuiltIns prog),
          T.intercalate "\n\n" (map (emitDecl topNames) decls),
          footer
        ]

-- | Name of the declaration (for the top-level-name set passed to 'emitExpr').
declName :: CDecl -> Name
declName (CFunDef nm _ _) = nm
declName (CValDef nm _) = nm

-- | Minimal runtime, tree-shaken — only helpers whose built-in is
--   referenced are emitted. Each helper is a field of @M@ so the
--   generated chunk has exactly one top-level binding (see 'codegenLua').
header :: Set Name -> Text
header builtIns =
  let lns =
        filter
          (not . T.null)
          [ if Set.member "IO.Stdout.print" builtIns
              then "function M.__print(s) io.write(tostring(s)); return nil end"
              else "",
            -- predInt32: Lua tables are 1-indexed, so tag sits at [1] and field
            -- at [2]. Left/UnderflowError tags both 0; Right tag 1.
            if Set.member "predInt32" builtIns
              then "function M.__predInt32(x) if x == -2147483648 then return {0, {0}} else return {1, x - 1} end end"
              else "",
            -- predUInt8: Left UnderflowError on 0, else Right (x - 1). Since
            -- x >= 1 implies (x - 1) is in 0..254, no mask is needed to
            -- keep the result inside UInt8 range.
            if Set.member "predUInt8" builtIns
              then "function M.__predUInt8(x) if x == 0 then return {0, {0}} else return {1, x - 1} end end"
              else "",
            -- succInt32: Left OverflowError on INT32_MAX, else Right (x + 1).
            -- Tag assignment mirrors __predInt32 (OverflowError=0 like
            -- UnderflowError — both single-constructor types).
            if Set.member "succInt32" builtIns
              then "function M.__succInt32(x) if x == 2147483647 then return {0, {0}} else return {1, x + 1} end end"
              else "",
            -- succUInt8: Left OverflowError on 255, else Right (x + 1). Since
            -- x <= 254 implies (x + 1) is in 1..255, no mask is needed.
            if Set.member "succUInt8" builtIns
              then "function M.__succUInt8(x) if x == 255 then return {0, {0}} else return {1, x + 1} end end"
              else "",
            -- eqInt32 / eqUInt8: True=0, False=1 for `type Bool = True | False`.
            -- Nullary constructors are one-slot tables holding only the tag.
            if Set.member "eqInt32" builtIns
              then "function M.__eqInt32(a, b) if a == b then return {0} else return {1} end end"
              else "",
            if Set.member "eqUInt8" builtIns
              then "function M.__eqUInt8(a, b) if a == b then return {0} else return {1} end end"
              else "",
            -- addInt32: Either ArithError Int32. Lua 5.1+ stores numbers as
            -- double, so the 33-bit sum is exact and the range checks
            -- evaluate before any precision loss. ArithError tags follow
            -- declaration order: Underflow=0, Overflow=1.
            if Set.member "addInt32" builtIns
              then "function M.__addInt32(a, b) local s = a + b if s > 2147483647 then return {0, {1}} elseif s < -2147483648 then return {0, {0}} else return {1, s} end end"
              else "",
            -- addUInt8: Either OverflowError UInt8. Sum ranges 0..510, a
            -- single '> 255' check separates the branches.
            if Set.member "addUInt8" builtIns
              then "function M.__addUInt8(a, b) local s = a + b if s > 255 then return {0, {0}} else return {1, s} end end"
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
      "  if type(M.main) == 'function' then M.main(input) end",
      "end"
    ]

-- | Top-level declarations. All names become fields of the module table @M@.
--   • 'CFunDef' with a 'CLoop' body (product of the TCO pass) → a
--     @while true do ... end@ loop whose body is emitted in statement
--     form. 'CContinue' rebinds the function's parameters and lets
--     control fall through to the loop's next iteration; any other tail
--     position emits an explicit @return@. Lua 5.3+ already has proper
--     tail calls for @return f(...)@, but we rewrite uniformly so the
--     generated program is stack-safe on 5.1 too and consistent with the
--     other backends.
--   • 'CFunDef' without a 'CLoop' wrapper → plain @return <expr>@.
--   • 'CValDef' → assignment @M.name = <expr>@.
emitDecl :: Set Name -> CDecl -> Text
emitDecl topNames = \case
  CFunDef nm args (CLoop body) ->
    "function M."
      <> mangle nm
      <> "("
      <> T.intercalate ", " (map mangle args)
      <> ")\n"
      <> "  while true do\n"
      <> emitStmt topNames args body
      <> "  end\n"
      <> "end"
  CFunDef nm args body ->
    "function M."
      <> mangle nm
      <> "("
      <> T.intercalate ", " (map mangle args)
      <> ")\n"
      <> "  return "
      <> emitExpr topNames body
      <> "\n"
      <> "end"
  CValDef nm rhs ->
    "M." <> mangle nm <> " = " <> emitExpr topNames rhs

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
emitStmt :: Set Name -> [Name] -> CExpr -> Text
emitStmt topNames params = go
  where
    go :: CExpr -> Text
    go = \case
      CContinue newArgs ->
        let temps = ["__t" <> show (i :: Int) | i <- [0 .. length newArgs - 1]]
            declLines =
              [ "    local " <> t <> " = " <> emitExpr topNames a
              | (t, a) <- zip temps newArgs
              ]
            assignLines =
              [ "    " <> mangle p <> " = " <> t
              | (p, t) <- zip params temps
              ]
         in unlines (declLines <> assignLines)
      CCase scrut alts ->
        "    local __s = "
          <> emitExpr topNames scrut
          <> "\n"
          <> emitStmtAlts alts
      e ->
        "    return " <> emitExpr topNames e <> "\n"

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
emitExpr :: Set Name -> CExpr -> Text
emitExpr topNames = go
  where
    go :: CExpr -> Text
    go = \case
      CString s -> luaString s
      -- Top-level names live in the module table @M@; parameters and
      -- pattern binders remain plain locals. No-shadowing in Awsum
      -- guarantees the sets don't overlap.
      CVar n
        | Set.member n topNames -> "M." <> mangle n
        | otherwise -> mangle n
      CIntLit n _ -> show n
      CBuiltIn n -> "--<builtin " <> n <> ">" -- invariant: not a standalone term
      CCon tag fields ->
        "{" <> T.intercalate ", " (show tag : map go fields) <> "}"
      CCase scrut alts ->
        "(function(s) "
          <> emitAlts alts
          <> " end)("
          <> go scrut
          <> ")"
      CCall f xs ->
        case f of
          CBuiltIn "IO.Stdout.print" ->
            case xs of
              [x] -> "M.__print(" <> go x <> ")"
              _ -> error "M.__print: arity mismatch"
          CBuiltIn name
            | name == "showInt32" || name == "showUInt8" ->
                case xs of
                  [x] -> "tostring(" <> go x <> ")"
                  _ -> error ("BuiltIn." <> name <> ": arity mismatch")
          CBuiltIn "predInt32" ->
            case xs of
              [x] -> "M.__predInt32(" <> go x <> ")"
              _ -> error "BuiltIn.predInt32: arity mismatch"
          CBuiltIn "predUInt8" ->
            case xs of
              [x] -> "M.__predUInt8(" <> go x <> ")"
              _ -> error "BuiltIn.predUInt8: arity mismatch"
          CBuiltIn "succInt32" ->
            case xs of
              [x] -> "M.__succInt32(" <> go x <> ")"
              _ -> error "BuiltIn.succInt32: arity mismatch"
          CBuiltIn "succUInt8" ->
            case xs of
              [x] -> "M.__succUInt8(" <> go x <> ")"
              _ -> error "BuiltIn.succUInt8: arity mismatch"
          CBuiltIn name
            | name == "eqInt32" || name == "eqUInt8" ->
                case xs of
                  [a, b] ->
                    let fn = if name == "eqInt32" then "M.__eqInt32" else "M.__eqUInt8"
                     in fn <> "(" <> go a <> ", " <> go b <> ")"
                  _ -> error ("BuiltIn." <> name <> ": arity mismatch")
          CBuiltIn name
            | name == "addInt32" || name == "addUInt8" ->
                case xs of
                  [a, b] ->
                    let fn = if name == "addInt32" then "M.__addInt32" else "M.__addUInt8"
                     in fn <> "(" <> go a <> ", " <> go b <> ")"
                  _ -> error ("BuiltIn." <> name <> ": arity mismatch")
          CBuiltIn "concatString" ->
            case xs of
              [a, b] ->
                let parts = flattenConcat a ++ flattenConcat b
                 in if length parts > 2
                      then "table.concat({" <> T.intercalate ", " (map go parts) <> "})"
                      else "(" <> go a <> " .. " <> go b <> ")"
              _ -> error "BuiltIn.concatString: arity mismatch"
          CBuiltIn n ->
            error ("Lua codegen: unknown builtin '" <> n <> "' reached CCall (typecheck should have rejected it)")
          _ ->
            "(" <> go f <> ")(" <> T.intercalate ", " (map go xs) <> ")"
      CLoop _ -> error "Lua codegen: CLoop survived untcoProgram (pipeline bug)"
      CContinue _ -> error "Lua codegen: CContinue survived untcoProgram (pipeline bug)"

    emitAlts [] = ""
    emitAlts ((tag, vars, body) : rest) =
      let bindings = T.concat [" local " <> mangle v <> " = s[" <> show (i :: Int) <> "];" | (v, i) <- zip vars [2 ..]]
       in "if s[1] == "
            <> show tag
            <> " then"
            <> bindings
            <> " return "
            <> go body
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
