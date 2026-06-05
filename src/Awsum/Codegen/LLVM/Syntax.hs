-- | Typed LLVM IR (a textual subset) + renderer for 'Awsum.Codegen.LLVM'.
--
-- The LLVM backend builds values of this IR from Core and renders them to
-- @.ll@ text here — the same "typed spec, then project" shape the byte
-- backends use, and the JS backend's 'Awsum.Codegen.JS.Syntax'. LLVM has a
-- single projection (text consumed by @clang@), so there is one renderer.
--
-- Unlike the JS AST (a nested expression tree), LLVM IR is flat SSA: a
-- function is a list of instructions in basic blocks, each value-producing
-- instruction naming its result register. So 'LInstr' is a flat instruction
-- (closer to the trio's @WasmInstr@), and a label is just an 'ILabel' marker
-- in the stream — matching how the imperative codegen emits.
--
-- The subset is exactly what the backend uses — no @div@/@rem@/@or@/@bitcast@,
-- overflow via the @llvm.*.with.overflow@ intrinsics rather than @nsw@/@nuw@.
-- Register and global names are stored with their sigil (@%t0@, @\@malloc@);
-- label names are stored bare and gain @:@ / @%@ at render.
module Awsum.Codegen.LLVM.Syntax
  ( LType (..),
    LVal (..),
    ICmpPred (..),
    ConvOp (..),
    LBinOp (..),
    LInstr (..),
    LFunc (..),
    LDecl (..),
    LGlobal (..),
    LGInit (..),
    typeBytes,
    renderType,
    renderTypedVal,
    renderInstr,
    renderInstrs,
    renderFunc,
    renderDecl,
    renderGlobal,
  )
where

import Data.Text qualified as T
import Relude

-- ════════════════════════════════════════════════════════════════════════════
-- IR
-- ════════════════════════════════════════════════════════════════════════════

-- | The LLVM types this backend uses. @TArr@ backs string / format-string
--   constants; @TStruct@ backs the @{i32, i1}@ result of the overflow
--   intrinsics.
data LType
  = I1
  | I8
  | I32
  | I64
  | Ptr
  | Void
  | TArr Int LType
  | TStruct [LType]
  deriving stock (Eq, Show)

-- | An operand. Registers and globals carry their sigil verbatim
--   (@%name@ / @\@name@); 'VInt' is a bare integer literal; 'VNull' is the
--   @ptr@ @null@. 'VConstGep' is a constant-expression
--   @getelementptr inbounds (i8, ptr \@g, i64 off)@ — the user-facing
--   pointer for a string literal (@\@.str.N@ + 12) or the empty string
--   (@\@.empty@ + 12), which is an operand rather than an instruction.
data LVal
  = VReg Text
  | VGlob Text
  | VInt Integer
  | VNull
  | VConstGep Text Integer
  deriving stock (Eq, Show)

data ICmpPred = IEq | INe | ISgt | ISge | ISlt | ISle | IUgt | IUge | IUlt | IUle
  deriving stock (Eq, Show)

-- | Conversions, all rendered @<op> <fromTy> <val> to <toTy>@.
data ConvOp = Zext | Sext | Trunc | IntToPtr | PtrToInt
  deriving stock (Eq, Show)

data LBinOp = LAdd | LSub | LMul | LAnd | LOr | LXor | LShl
  deriving stock (Eq, Show)

-- | A single LLVM instruction. Value-producing instructions carry their
--   result register name (with @%@). 'ILabel' is a basic-block label marker
--   in the flat instruction stream.
data LInstr
  = -- | @label:@
    ILabel Text
  | -- | @%r = <op> <ty> <a>, <b>@
    IBin Text LBinOp LType LVal LVal
  | -- | @%r = icmp <pred> <ty> <a>, <b>@
    IICmp Text ICmpPred LType LVal LVal
  | -- | @%r = select i1 <c>, <ty> <t>, <ty> <f>@ (both arms share @ty@)
    ISelect Text LVal LType LVal LVal
  | -- | @%r = <conv> <fromTy> <v> to <toTy>@
    IConv Text ConvOp LType LVal LType
  | -- | @%r = getelementptr <elemTy>, ptr <base>, <idxTy> <idx>…@
    IGep Text LType LVal [(LType, LVal)]
  | -- | @%r = load <ty>, ptr <p>@
    ILoad Text LType LVal
  | -- | @store <ty> <v>, ptr <p>@
    IStore LType LVal LVal
  | -- | @%r = alloca <ty>[, align <n>]@
    IAlloca Text LType (Maybe Int)
  | -- | @[%r = ]call <retTy>[ <fnTy>] <callee>(<args>)@. 'Nothing' result
    --   discards the value (still typed); @fnTy@ (param types + vararg) is
    --   present only for a varargs callee (@snprintf@).
    ICall (Maybe Text) LType (Maybe ([LType], Bool)) Text [(LType, LVal)]
  | -- | @%r = extractvalue <structTy> <v>, <idx>@
    IExtractValue Text LType LVal Int
  | -- | @%r = phi <ty> [ <v>, %<lbl> ]…@
    IPhi Text LType [(LVal, Text)]
  | -- | @br label %<lbl>@
    IBr Text
  | -- | @br i1 <c>, label %<t>, label %<f>@
    IBrCond LVal Text Text
  | -- | @ret <ty> <v>@ / @ret void@
    IRet (Maybe (LType, LVal))
  | -- | @switch <ty> <v>, label %<def> [ <ty> <n>, label %<lbl>… ]@
    ISwitch LType LVal Text [(Integer, Text)]
  | -- | @unreachable@
    IUnreachable
  deriving stock (Eq, Show)

-- | A function definition: @define [linkage ]<retTy> \@<name>(<params>) { <body> }@.
--   @lfLinkage@ is e.g. @"internal"@, or @""@ for an external definition
--   (the C @main@). Params carry their sigil'd name (@"%s"@).
data LFunc = LFunc
  { lfLinkage :: Text,
    lfRetType :: LType,
    lfName :: Text,
    lfParams :: [(LType, Text)],
    lfBody :: [LInstr]
  }
  deriving stock (Eq, Show)

-- | An external declaration: @declare <retTy> \@<name>(<paramTys>[, ...])@.
data LDecl = LDecl LType Text [LType] Bool
  deriving stock (Eq, Show)

-- | A module-level global: @\@name = <linkage> <kind> <type> <init>@.
--   @lglLinkage@ is e.g. @"internal"@ or @"private unnamed_addr"@; @lglKind@
--   is @"global"@ (mutable) or @"constant"@.
data LGlobal = LGlobal
  { lglName :: Text,
    lglLinkage :: Text,
    lglKind :: Text,
    lglType :: LType,
    lglInit :: LGInit
  }
  deriving stock (Eq, Show)

-- | A global initialiser. 'GBytes' is a @c"…"@ byte string (content already
--   escaped); 'GStruct' an aggregate @{ ty v, … }@; 'GZero' is
--   @zeroinitializer@ (used for an empty @[0 x i8]@ string payload).
data LGInit = GInt Integer | GNull | GBytes Text | GStruct [(LType, LGInit)] | GZero
  deriving stock (Eq, Show)

-- ════════════════════════════════════════════════════════════════════════════
-- Renderer
-- ════════════════════════════════════════════════════════════════════════════

renderType :: LType -> Text
renderType = \case
  I1 -> "i1"
  I8 -> "i8"
  I32 -> "i32"
  I64 -> "i64"
  Ptr -> "ptr"
  Void -> "void"
  TArr n t -> "[" <> show n <> " x " <> renderType t <> "]"
  TStruct ts -> "{" <> T.intercalate ", " (map renderType ts) <> "}"

-- | Size in bytes of a type's in-memory representation (pointers are 64-bit;
--   this backend's LLVM targets are all LP64/LLP64). Used to size heap boxes.
typeBytes :: LType -> Integer
typeBytes = \case
  I1 -> 1
  I8 -> 1
  I32 -> 4
  I64 -> 8
  Ptr -> 8
  Void -> 0
  TArr n t -> toInteger n * typeBytes t
  TStruct ts -> sum (map typeBytes ts)

renderVal :: LVal -> Text
renderVal = \case
  VReg r -> r
  VGlob g -> g
  VInt n -> show n
  VNull -> "null"
  VConstGep g off -> "getelementptr inbounds (i8, ptr " <> g <> ", i64 " <> show off <> ")"

-- | @<ty> <val>@ — the form operands take where LLVM states their type.
renderTypedVal :: LType -> LVal -> Text
renderTypedVal t v = renderType t <> " " <> renderVal v

icmpPred :: ICmpPred -> Text
icmpPred = \case
  IEq -> "eq"
  INe -> "ne"
  ISgt -> "sgt"
  ISge -> "sge"
  ISlt -> "slt"
  ISle -> "sle"
  IUgt -> "ugt"
  IUge -> "uge"
  IUlt -> "ult"
  IUle -> "ule"

convOp :: ConvOp -> Text
convOp = \case
  Zext -> "zext"
  Sext -> "sext"
  Trunc -> "trunc"
  IntToPtr -> "inttoptr"
  PtrToInt -> "ptrtoint"

binOp :: LBinOp -> Text
binOp = \case
  LAdd -> "add"
  LSub -> "sub"
  LMul -> "mul"
  LAnd -> "and"
  LOr -> "or"
  LXor -> "xor"
  LShl -> "shl"

-- | The explicit function-type a varargs call needs: @(ty, …, ...)@.
fnTy :: ([LType], Bool) -> Text
fnTy (ts, vararg) =
  "(" <> T.intercalate ", " (map renderType ts <> (["..." | vararg])) <> ")"

-- | Render one instruction as a single line — a label flush-left, every
--   other instruction indented two spaces. No trailing newline.
renderInstr :: LInstr -> Text
renderInstr = \case
  ILabel l -> l <> ":"
  IBin r op ty a b ->
    ind r <> binOp op <> " " <> renderType ty <> " " <> renderVal a <> ", " <> renderVal b
  IICmp r p ty a b ->
    ind r <> "icmp " <> icmpPred p <> " " <> renderType ty <> " " <> renderVal a <> ", " <> renderVal b
  ISelect r c ty t f ->
    ind r <> "select i1 " <> renderVal c <> ", " <> renderTypedVal ty t <> ", " <> renderTypedVal ty f
  IConv r op fromTy v toTy ->
    ind r <> convOp op <> " " <> renderType fromTy <> " " <> renderVal v <> " to " <> renderType toTy
  IGep r elemTy base idxs ->
    ind r
      <> "getelementptr "
      <> renderType elemTy
      <> ", ptr "
      <> renderVal base
      <> T.concat [", " <> renderTypedVal it iv | (it, iv) <- idxs]
  ILoad r ty p ->
    ind r <> "load " <> renderType ty <> ", ptr " <> renderVal p
  IStore ty v p ->
    "  store " <> renderTypedVal ty v <> ", ptr " <> renderVal p
  IAlloca r ty mAlign ->
    ind r <> "alloca " <> renderType ty <> maybe "" (\n -> ", align " <> show n) mAlign
  ICall mRes retTy mFnTy callee args ->
    "  "
      <> maybe "" (<> " = ") mRes
      <> "call "
      <> renderType retTy
      <> maybe "" (\ft -> " " <> fnTy ft) mFnTy
      <> " "
      <> callee
      <> "("
      <> T.intercalate ", " [renderTypedVal t v | (t, v) <- args]
      <> ")"
  IExtractValue r structTy v idx ->
    ind r <> "extractvalue " <> renderType structTy <> " " <> renderVal v <> ", " <> show idx
  IPhi r ty incomings ->
    ind r
      <> "phi "
      <> renderType ty
      <> " "
      <> T.intercalate ", " ["[ " <> renderVal v <> ", %" <> l <> " ]" | (v, l) <- incomings]
  IBr l -> "  br label %" <> l
  IBrCond c t f -> "  br i1 " <> renderVal c <> ", label %" <> t <> ", label %" <> f
  IRet Nothing -> "  ret void"
  IRet (Just (ty, v)) -> "  ret " <> renderTypedVal ty v
  ISwitch ty v def cases ->
    "  switch "
      <> renderTypedVal ty v
      <> ", label %"
      <> def
      <> " ["
      <> T.concat [" " <> renderType ty <> " " <> show n <> ", label %" <> l | (n, l) <- cases]
      <> " ]"
  IUnreachable -> "  unreachable"
  where
    -- "  %r = " — the indented result-assignment prefix.
    ind r = "  " <> r <> " = "

-- | Render a block of instructions, one per line.
renderInstrs :: [LInstr] -> Text
renderInstrs = T.intercalate "\n" . map renderInstr

-- | Render a function definition. No trailing newline (callers join
--   functions with a blank line).
renderFunc :: LFunc -> Text
renderFunc f =
  "define "
    <> (if T.null f.lfLinkage then "" else f.lfLinkage <> " ")
    <> renderType f.lfRetType
    <> " @"
    <> f.lfName
    <> "("
    <> T.intercalate ", " [renderType t <> " " <> nm | (t, nm) <- f.lfParams]
    <> ") {\n"
    <> renderInstrs f.lfBody
    <> "\n}"

-- | Render an external declaration.
renderDecl :: LDecl -> Text
renderDecl (LDecl retTy name paramTys vararg) =
  "declare "
    <> renderType retTy
    <> " @"
    <> name
    <> "("
    <> T.intercalate ", " (map renderType paramTys <> (["..." | vararg]))
    <> ")"

renderGlobal :: LGlobal -> Text
renderGlobal g =
  g.lglName
    <> " = "
    <> g.lglLinkage
    <> " "
    <> g.lglKind
    <> " "
    <> renderType g.lglType
    <> " "
    <> renderGInit g.lglInit

renderGInit :: LGInit -> Text
renderGInit = \case
  GInt n -> show n
  GNull -> "null"
  GZero -> "zeroinitializer"
  GBytes s -> "c\"" <> s <> "\""
  GStruct fields -> "{ " <> T.intercalate ", " [renderTypedVal' t v | (t, v) <- fields] <> " }"
  where
    renderTypedVal' t v = renderType t <> " " <> renderGInit v
