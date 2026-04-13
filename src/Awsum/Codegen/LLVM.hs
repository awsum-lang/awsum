-- | LLVM IR code generator for Awsum 'Core'.
--
-- Design goals:
--   * Emit textual LLVM IR (.ll) that can be compiled with @clang@.
--   * Keep a tiny C-based runtime (malloc/strlen/strcpy/strcat/printf).
--   * Mirror JS/Lua backend semantics for cross-backend equivalence.
--
-- Semantics & assumptions:
--   * All values are opaque pointers (@ptr@, LLVM 15+).
--   * Strings are null-terminated C strings (@ptr@ to @[N x i8]@).
--   * Concatenation: @strlen + malloc + strcpy + strcat@.
--   * Print: @printf("%s", s)@ — buffered, flushed on exit.
--   * Zero-arg surface defs ('CValDef') become zero-arg LLVM functions.
--     Pure expressions, so recomputation is safe.
--   * The C @main@ entry point reads @argv[1]@ and calls @v_main@.
module Awsum.Codegen.LLVM (codegenLLVM) where

import Awsum.Core
import Data.Char qualified as Char
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Relude

-- ════════════════════════════════════════════════════════════════════════════
-- Public API
-- ════════════════════════════════════════════════════════════════════════════

-- | Produce a complete LLVM IR module from a Core program.
codegenLLVM :: CoreProgram -> Text
codegenLLVM prog@(CoreProgram decls) =
  let pool = collectStrings prog
      valDefNames = Set.fromList [n | CValDef n _ <- decls]
      ctx = EmitCtx {params = Set.empty, valDefs = valDefNames, stringPool = pool}
      userCode = evalState (T.intercalate "\n\n" <$> traverse (emitDecl ctx) decls) 0
   in T.intercalate
        "\n"
        [ header,
          emitStringConstants pool,
          runtime,
          userCode,
          footer
        ]

-- ════════════════════════════════════════════════════════════════════════════
-- Context
-- ════════════════════════════════════════════════════════════════════════════

data EmitCtx = EmitCtx
  { params :: Set Text,
    valDefs :: Set Text,
    stringPool :: StringPool
  }

-- ════════════════════════════════════════════════════════════════════════════
-- SSA temp generation
-- ════════════════════════════════════════════════════════════════════════════

type CodegenM = State Int

freshTemp :: CodegenM Text
freshTemp = do
  n <- get
  modify' (+ 1)
  pure ("%t" <> show n)

-- ════════════════════════════════════════════════════════════════════════════
-- String constant pool
-- ════════════════════════════════════════════════════════════════════════════

type StringPool = Map Text Int

collectStrings :: CoreProgram -> StringPool
collectStrings (CoreProgram decls) =
  let strs = ordNub $ concatMap stringsInDecl decls
   in Map.fromList (zip strs [0 ..])

stringsInDecl :: CDecl -> [Text]
stringsInDecl = \case
  CFunDef _ _ body -> stringsInExpr body
  CValDef _ rhs -> stringsInExpr rhs

stringsInExpr :: CExpr -> [Text]
stringsInExpr = \case
  CString s -> [s]
  CVar _ -> []
  CPrim _ -> []
  CCall f xs -> stringsInExpr f <> concatMap stringsInExpr xs

emitStringConstants :: StringPool -> Text
emitStringConstants pool
  | Map.null pool = ""
  | otherwise =
      T.intercalate "\n" (map emitOne (sortWith snd $ Map.toList pool)) <> "\n"
  where
    emitOne (s, i) =
      let escaped = llvmEscapeString s
          len = T.length s + 1
       in "@.str."
            <> show i
            <> " = private unnamed_addr constant ["
            <> show len
            <> " x i8] c\""
            <> escaped
            <> "\\00\""

-- | Escape a string for LLVM IR constant syntax.
--   Non-printable and special chars become @\\XX@ hex pairs.
llvmEscapeString :: Text -> Text
llvmEscapeString = T.concatMap escChar
  where
    escChar c
      | c == '\\' = "\\5C"
      | c == '"' = "\\22"
      | c == '\n' = "\\0A"
      | c == '\t' = "\\09"
      | c == '\r' = "\\0D"
      | c == '\0' = "\\00"
      | Char.isPrint c = one c
      | otherwise =
          let n = Char.ord c
              hi = n `div` 16
              lo = n `mod` 16
              hexChar x
                | x < 10 = chr (Char.ord '0' + x)
                | otherwise = chr (Char.ord 'A' + x - 10)
           in "\\" <> toText [hexChar hi, hexChar lo]

-- ════════════════════════════════════════════════════════════════════════════
-- Header: external declarations + format strings
-- ════════════════════════════════════════════════════════════════════════════

header :: Text
header =
  unlines
    [ "; External C declarations",
      "declare ptr @malloc(i64)",
      "declare ptr @strcpy(ptr, ptr)",
      "declare ptr @strcat(ptr, ptr)",
      "declare i64 @strlen(ptr)",
      "declare i32 @printf(ptr, ...)",
      "",
      "@.fmt = private unnamed_addr constant [3 x i8] c\"%s\\00\"",
      "@.empty = private unnamed_addr constant [1 x i8] c\"\\00\""
    ]

-- ════════════════════════════════════════════════════════════════════════════
-- Runtime helpers
-- ════════════════════════════════════════════════════════════════════════════

runtime :: Text
runtime =
  unlines
    [ "define ptr @__concat(ptr %a, ptr %b) {",
      "  %la = call i64 @strlen(ptr %a)",
      "  %lb = call i64 @strlen(ptr %b)",
      "  %sum = add i64 %la, %lb",
      "  %total = add i64 %sum, 1",
      "  %buf = call ptr @malloc(i64 %total)",
      "  call ptr @strcpy(ptr %buf, ptr %a)",
      "  call ptr @strcat(ptr %buf, ptr %b)",
      "  ret ptr %buf",
      "}",
      "",
      "define ptr @__print(ptr %s) {",
      "  call i32 (ptr, ...) @printf(ptr @.fmt, ptr %s)",
      "  ret ptr null",
      "}"
    ]

-- ════════════════════════════════════════════════════════════════════════════
-- Footer: C main entry point
-- ════════════════════════════════════════════════════════════════════════════

footer :: Text
footer =
  unlines
    [ "",
      "define i32 @main(i32 %argc, ptr %argv) {",
      "  %has_arg = icmp sgt i32 %argc, 1",
      "  br i1 %has_arg, label %with_arg, label %no_arg",
      "with_arg:",
      "  %argptr = getelementptr ptr, ptr %argv, i64 1",
      "  %arg = load ptr, ptr %argptr",
      "  br label %call_main",
      "no_arg:",
      "  br label %call_main",
      "call_main:",
      "  %input = phi ptr [%arg, %with_arg], [@.empty, %no_arg]",
      "  call ptr @v_main(ptr %input)",
      "  ret i32 0",
      "}"
    ]

-- ════════════════════════════════════════════════════════════════════════════
-- Declarations
-- ════════════════════════════════════════════════════════════════════════════

emitDecl :: EmitCtx -> CDecl -> CodegenM Text
emitDecl ctx = \case
  CFunDef nm args body -> do
    put 0
    let paramSet = Set.fromList args
        localCtx = ctx {params = paramSet}
        llvmArgs = T.intercalate ", " (map (\a -> "ptr %" <> mangle a) args)
    (instrs, result) <- emitExpr localCtx body
    pure
      $ "define ptr @"
      <> mangle nm
      <> "("
      <> llvmArgs
      <> ") {\n"
      <> instrs
      <> "  ret ptr "
      <> result
      <> "\n}"
  CValDef nm rhs -> do
    put 0
    let localCtx = ctx {params = Set.empty}
    (instrs, result) <- emitExpr localCtx rhs
    pure
      $ "define ptr @"
      <> mangle nm
      <> "() {\n"
      <> instrs
      <> "  ret ptr "
      <> result
      <> "\n}"

-- ════════════════════════════════════════════════════════════════════════════
-- Expressions
-- ════════════════════════════════════════════════════════════════════════════

-- | Emit instructions for an expression.
--   Returns (accumulated instructions, SSA name holding the result).
emitExpr :: EmitCtx -> CExpr -> CodegenM (Text, Text)
emitExpr ctx = \case
  CString s -> do
    let idx = case Map.lookup s ctx.stringPool of
          Just i -> i
          Nothing -> error $ "string not in pool: " <> show s
        len = T.length s + 1
    tmp <- freshTemp
    pure
      ( "  " <> tmp <> " = getelementptr [" <> show len <> " x i8], ptr @.str." <> show idx <> ", i64 0, i64 0\n",
        tmp
      )
  CVar n
    | n `Set.member` ctx.params ->
        pure ("", "%" <> mangle n)
    | n `Set.member` ctx.valDefs -> do
        tmp <- freshTemp
        pure
          ( "  " <> tmp <> " = call ptr @" <> mangle n <> "()\n",
            tmp
          )
    | otherwise ->
        pure ("", "@" <> mangle n)
  CPrim _ ->
    pure ("", "null")
  CCall f xs ->
    case f of
      CPrim PrimConcat ->
        case xs of
          [a, b] -> do
            (instrA, resA) <- emitExpr ctx a
            (instrB, resB) <- emitExpr ctx b
            tmp <- freshTemp
            pure
              ( instrA <> instrB <> "  " <> tmp <> " = call ptr @__concat(ptr " <> resA <> ", ptr " <> resB <> ")\n",
                tmp
              )
          _ -> error "__concat: arity mismatch"
      CPrim PrimPrint ->
        case xs of
          [x] -> do
            (instrX, resX) <- emitExpr ctx x
            tmp <- freshTemp
            pure
              ( instrX <> "  " <> tmp <> " = call ptr @__print(ptr " <> resX <> ")\n",
                tmp
              )
          _ -> error "__print: arity mismatch"
      _ -> do
        (instrF, resF) <- emitExpr ctx f
        argsResults <- traverse (emitExpr ctx) xs
        let allInstrs = instrF <> mconcat (map fst argsResults)
            argList = T.intercalate ", " (map (\(_, r) -> "ptr " <> r) argsResults)
        tmp <- freshTemp
        pure
          ( allInstrs <> "  " <> tmp <> " = call ptr " <> resF <> "(" <> argList <> ")\n",
            tmp
          )

-- ════════════════════════════════════════════════════════════════════════════
-- Name mangling
-- ════════════════════════════════════════════════════════════════════════════

-- | All names get @v_@ prefix (including @main@ → @v_main@),
--   because @\@main@ is the C entry point.
mangle :: Text -> Text
mangle t =
  let ok c = Char.isAlphaNum c || c == '_' || c == '\''
      body = T.map (\c -> if ok c then c else '_') t
   in "v_" <> body
