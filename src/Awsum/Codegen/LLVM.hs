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
import Awsum.Syntax (Name)
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
      ctx = EmitCtx {params = Set.empty, valDefs = valDefNames, stringPool = pool, locals = Map.empty}
      userCode = evalState (T.intercalate "\n\n" <$> traverse (emitDecl ctx) decls) 0
      prims = usedPrims prog
      builtIns = usedBuiltIns prog
   in T.intercalate
        "\n"
        [ header,
          emitStringConstants pool,
          runtime prims builtIns,
          userCode,
          footer
        ]

-- ════════════════════════════════════════════════════════════════════════════
-- Context
-- ════════════════════════════════════════════════════════════════════════════

data EmitCtx = EmitCtx
  { params :: Set Text,
    valDefs :: Set Text,
    stringPool :: StringPool,
    locals :: Map Text Text -- case-bound variable name → SSA temp
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

freshLabel :: Text -> CodegenM Text
freshLabel prefix = do
  n <- get
  modify' (+ 1)
  pure (prefix <> "." <> show n)

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
  CIntLit _ _ -> []
  CPrim _ -> []
  CBuiltIn _ -> []
  CCon _ fields -> concatMap stringsInExpr fields
  CCase scrut alts -> stringsInExpr scrut <> concatMap (\(_, _, body) -> stringsInExpr body) alts
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
      "declare i32 @snprintf(ptr, i64, ptr, ...)",
      "",
      "@.fmt = private unnamed_addr constant [3 x i8] c\"%s\\00\"",
      "@.fmt_i32 = private unnamed_addr constant [3 x i8] c\"%d\\00\"",
      "@.fmt_u8 = private unnamed_addr constant [3 x i8] c\"%u\\00\"",
      "@.empty = private unnamed_addr constant [1 x i8] c\"\\00\""
    ]

-- ════════════════════════════════════════════════════════════════════════════
-- Runtime helpers
-- ════════════════════════════════════════════════════════════════════════════

-- | LLVM runtime helpers, tree-shaken: each @define@ is emitted only if
--   the corresponding 'Prim' or 'BuiltIn' is actually referenced in the
--   program's Core.
runtime :: Set Prim -> Set Name -> Text
runtime prims builtIns =
  T.intercalate "\n\n" (filter (not . T.null) parts) <> "\n"
  where
    parts =
      [ if Set.member PrimConcat prims then rtConcat else "",
        if Set.member PrimPrint prims then rtPrint else "",
        if any (`Set.member` prims) [PrimShowInt TInt32, PrimShowInt TUInt8] || Set.member "showInt32" builtIns
          then rtShowInt32
          else "",
        if any (`Set.member` prims) [PrimShowInt TInt32, PrimShowInt TUInt8] || Set.member "showUInt8" builtIns
          then rtShowUInt8
          else "",
        if Set.member "predInt32" builtIns then rtPredInt32 else ""
      ]
    rtConcat =
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
          "}"
        ]
    rtPrint =
      unlines
        [ "define ptr @__print(ptr %s) {",
          "  call i32 (ptr, ...) @printf(ptr @.fmt, ptr %s)",
          "  ret ptr null",
          "}"
        ]
    -- Integers are boxed: each CIntLit allocates a heap cell holding
    -- the native i32/i8 value and the Awsum-level 'ptr' points at it.
    -- Show reads the cell and snprintf's into a fresh 16-byte buffer
    -- (enough for @-2147483648@ / @255@ plus a null terminator).
    rtShowInt32 =
      unlines
        [ "define ptr @__showInt32(ptr %p) {",
          "  %v = load i32, ptr %p",
          "  %buf = call ptr @malloc(i64 16)",
          "  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_i32, i32 %v)",
          "  ret ptr %buf",
          "}"
        ]
    rtShowUInt8 =
      unlines
        [ "define ptr @__showUInt8(ptr %p) {",
          "  %b = load i8, ptr %p",
          "  %v = zext i8 %b to i32",
          "  %buf = call ptr @malloc(i64 16)",
          "  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_u8, i32 %v)",
          "  ret ptr %buf",
          "}"
        ]
    -- predInt32 : Int32 -> Either UnderflowError Int32
    --   On INT32_MIN, returns Left UnderflowError (tags: Left=0,
    --   UnderflowError=0). Otherwise returns Right (x - 1) (Right=1).
    --   Containers follow the uniform layout [tag_as_ptr, field, ...],
    --   same as user CCon emission.
    rtPredInt32 =
      unlines
        [ "define ptr @__predInt32(ptr %p) {",
          "  %v = load i32, ptr %p",
          "  %is_min = icmp eq i32 %v, -2147483648",
          "  br i1 %is_min, label %overflow, label %ok",
          "overflow:",
          "  %oe = call ptr @malloc(i64 8)",
          "  %oe_tag = inttoptr i64 0 to ptr",
          "  store ptr %oe_tag, ptr %oe",
          "  %left = call ptr @malloc(i64 16)",
          "  %left_tag = inttoptr i64 0 to ptr",
          "  store ptr %left_tag, ptr %left",
          "  %left_f = getelementptr ptr, ptr %left, i32 1",
          "  store ptr %oe, ptr %left_f",
          "  ret ptr %left",
          "ok:",
          "  %newv = sub i32 %v, 1",
          "  %box = call ptr @malloc(i64 4)",
          "  store i32 %newv, ptr %box",
          "  %right = call ptr @malloc(i64 16)",
          "  %right_tag = inttoptr i64 1 to ptr",
          "  store ptr %right_tag, ptr %right",
          "  %right_f = getelementptr ptr, ptr %right, i32 1",
          "  store ptr %box, ptr %right_f",
          "  ret ptr %right",
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
    | Just tmp <- Map.lookup n ctx.locals ->
        pure ("", tmp)
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
  CIntLit n it -> do
    -- Box the literal: malloc a cell of the right width, store the value,
    -- and return the pointer — integers share the uniform 'ptr' representation.
    buf <- freshTemp
    let (llvmTy, bytes, val) = case it of
          TInt32 -> ("i32" :: Text, 4 :: Int, show n :: Text)
          TUInt8 -> ("i8", 1, show n)
    pure
      ( "  "
          <> buf
          <> " = call ptr @malloc(i64 "
          <> show bytes
          <> ")\n"
          <> "  store "
          <> llvmTy
          <> " "
          <> val
          <> ", ptr "
          <> buf
          <> "\n",
        buf
      )
  CPrim _ ->
    pure ("", "null")
  CBuiltIn _ ->
    pure ("", "null") -- invariant: not a standalone term; dispatched from CCall
  CCon tag fields -> do
    -- Allocate container: [tag_as_ptr, field1, field2, ...]
    let nSlots = 1 + length fields
    arrTmp <- freshTemp
    let allocInstr = "  " <> arrTmp <> " = call ptr @malloc(i64 " <> show (nSlots * 8 :: Int) <> ")\n"
    -- Store tag at index 0
    tagPtr <- freshTemp
    tagSlot <- freshTemp
    let tagInstr =
          "  "
            <> tagPtr
            <> " = inttoptr i64 "
            <> show tag
            <> " to ptr\n"
            <> "  "
            <> tagSlot
            <> " = getelementptr ptr, ptr "
            <> arrTmp
            <> ", i32 0\n"
            <> "  store ptr "
            <> tagPtr
            <> ", ptr "
            <> tagSlot
            <> "\n"
    -- Store each field
    fieldInstrs <- forM (zip fields [1 :: Int ..]) $ \(fExpr, idx) -> do
      (instrF, resF) <- emitExpr ctx fExpr
      slotTmp <- freshTemp
      pure
        ( instrF
            <> "  "
            <> slotTmp
            <> " = getelementptr ptr, ptr "
            <> arrTmp
            <> ", i32 "
            <> show idx
            <> "\n"
            <> "  store ptr "
            <> resF
            <> ", ptr "
            <> slotTmp
            <> "\n"
        )
    pure
      ( allocInstr <> tagInstr <> T.concat fieldInstrs,
        arrTmp
      )
  CCase scrut alts -> do
    (instrS, resS) <- emitExpr ctx scrut
    -- Extract tag from container[0]
    tagSlot <- freshTemp
    tagLoaded <- freshTemp
    tagTmp <- freshTemp
    let tagInstr =
          "  "
            <> tagSlot
            <> " = getelementptr ptr, ptr "
            <> resS
            <> ", i32 0\n"
            <> "  "
            <> tagLoaded
            <> " = load ptr, ptr "
            <> tagSlot
            <> "\n"
            <> "  "
            <> tagTmp
            <> " = ptrtoint ptr "
            <> tagLoaded
            <> " to i64\n"
    -- Generate labels
    defLabel <- freshLabel "case.default"
    joinLabel <- freshLabel "case.join"
    altLabelsAndBodies <- forM alts $ \(tag, vars, body) -> do
      lbl <- freshLabel ("case.arm." <> show tag)
      endLbl <- freshLabel ("case.end." <> show tag)
      -- Extract bound variables from container fields
      varInstrs <- forM (zip vars [1 :: Int ..]) $ \(v, idx) -> do
        slotT <- freshTemp
        valT <- freshTemp
        pure
          ( "  "
              <> slotT
              <> " = getelementptr ptr, ptr "
              <> resS
              <> ", i32 "
              <> show idx
              <> "\n"
              <> "  "
              <> valT
              <> " = load ptr, ptr "
              <> slotT
              <> "\n",
            (v, valT)
          )
      let varInstrCode = T.concat (map fst varInstrs)
          varBindings = map snd varInstrs
      -- Emit body with bound variables in context
      let ctx' = foldl' (\c (v, tmp) -> c {locals = Map.insert v tmp (locals c)}) ctx varBindings
      (instrB, resB) <- emitExpr ctx' body
      pure (tag, lbl, endLbl, varInstrCode <> instrB, resB)
    -- switch instruction
    let switchCases = T.concat [" i64 " <> show tag <> ", label %" <> lbl | (tag, lbl, _, _, _) <- altLabelsAndBodies]
        switchInstr = "  switch i64 " <> tagTmp <> ", label %" <> defLabel <> " [" <> switchCases <> " ]\n"
    -- arm blocks (body may create new blocks; endLbl is always the direct predecessor of join)
    let armBlocks =
          T.concat
            [ lbl <> ":\n" <> instrB <> "  br label %" <> endLbl <> "\n" <> endLbl <> ":\n  br label %" <> joinLabel <> "\n"
            | (_, lbl, endLbl, instrB, _) <- altLabelsAndBodies
            ]
    -- default block (unreachable)
    let defBlock = defLabel <> ":\n  unreachable\n"
    -- phi at join (references endLbl, the actual predecessor)
    phiTmp <- freshTemp
    let phiIncoming = T.intercalate ", " ["[" <> resB <> ", %" <> endLbl <> "]" | (_, _, endLbl, _, resB) <- altLabelsAndBodies]
        joinBlock = joinLabel <> ":\n  " <> phiTmp <> " = phi ptr " <> phiIncoming <> "\n"
    pure
      ( instrS <> tagInstr <> switchInstr <> armBlocks <> defBlock <> joinBlock,
        phiTmp
      )
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
      CPrim (PrimShowInt it) ->
        case xs of
          [x] -> do
            (instrX, resX) <- emitExpr ctx x
            tmp <- freshTemp
            let fn = case it of
                  TInt32 -> "@__showInt32" :: Text
                  TUInt8 -> "@__showUInt8"
            pure
              ( instrX <> "  " <> tmp <> " = call ptr " <> fn <> "(ptr " <> resX <> ")\n",
                tmp
              )
          _ -> error "__showInt: arity mismatch"
      CBuiltIn name
        | name == "showInt32" || name == "showUInt8" ->
            case xs of
              [x] -> do
                (instrX, resX) <- emitExpr ctx x
                tmp <- freshTemp
                let fn :: Text
                    fn = case name of
                      "showUInt8" -> "@__showUInt8"
                      _ -> "@__showInt32"
                pure
                  ( instrX <> "  " <> tmp <> " = call ptr " <> fn <> "(ptr " <> resX <> ")\n",
                    tmp
                  )
              _ -> error ("BuiltIn." <> name <> ": arity mismatch")
      CBuiltIn "predInt32" ->
        case xs of
          [x] -> do
            (instrX, resX) <- emitExpr ctx x
            tmp <- freshTemp
            pure
              ( instrX <> "  " <> tmp <> " = call ptr @__predInt32(ptr " <> resX <> ")\n",
                tmp
              )
          _ -> error "BuiltIn.predInt32: arity mismatch"
      CBuiltIn n ->
        error ("LLVM codegen: unknown builtin '" <> n <> "' reached CCall (typecheck should have rejected it)")
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
