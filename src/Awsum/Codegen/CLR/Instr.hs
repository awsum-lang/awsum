-- | Unified CIL instruction IR — the single source of truth behind both CLR
--   renderers. One 'CilMethod' value — a list of 'CilInstr' with operands
--   carried *symbolically* (type/member refs by name, branch labels never byte
--   offsets, string literals never @#US@ tokens) — feeds two total,
--   decision-free projections:
--
--     * 'renderCilMethod' here, which prints the CIL text.
--     * 'Awsum.Codegen.CLR.Assemble.assembleCilMethod', which resolves the
--       symbolic operands to metadata tokens and emits CIL bytes.
--
--   CIL carries no per-label stack-type metadata — the verifier infers stack
--   state — so there is no frame machinery here; @.maxstack@ is derived from
--   the instruction stream ('maxStackOf'). Every method — runtime helpers,
--   user declarations,
--   and the @Main@ entry — flows through one 'CilMethod', so the two
--   projections cannot diverge.
module Awsum.Codegen.CLR.Instr
  ( CilTypeRef (..),
    CilMemberRef (..),
    LabelId (..),
    SigElem (..),
    CilInstr (..),
    CilMethod (..),
    renderCilMethod,
    renderTypeRef,
    renderSigElem,
    maxStackOf,
    int32Ref,
    objectRef,
    showUInt32Spec,
    predInt32Spec,
    predUInt8Spec,
    predUInt32Spec,
    succInt32Spec,
    succUInt8Spec,
    succUInt32Spec,
    negInt32Spec,
    eqSpec,
    eqStringSpec,
    printSpec,
    addInt32Spec,
    subInt32Spec,
    mulInt32Spec,
    addUInt8Spec,
    subUInt8Spec,
    mulUInt8Spec,
    addUInt32Spec,
    subUInt32Spec,
    mulUInt32Spec,
    concatSpec,
    splitOnFirstSpec,
    lengthUtf16CodeUnitsSpec,
    lengthUtf8BytesSpec,
    lengthCodePointsSpec,
    parseInt32Spec,
    parseUInt8Spec,
    parseUInt32Spec,
    entryArgEitherSpec,
    getArgsSpec,
    stdinReadAllSpec,
    mainSpec,
  )
where

import Awsum.HM (rowTag)
import Awsum.Syntax (Type' (..), noSpan)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Relude

-- | A .NET @TypeRef@: the assembly it lives in (1 = @System.Runtime@,
--   2 = @System.Console@ — the two 'AssemblyRef' rows the assembler emits),
--   namespace, and name. Used as a @box@ / @unbox.any@ / @castclass@ /
--   @newarr@ operand and as a 'CilMemberRef' parent.
data CilTypeRef = CilTypeRef
  { ctrAsm :: Int,
    ctrNs :: Text,
    ctrName :: Text
  }
  deriving stock (Eq, Show)

-- | A signature element type — used for a method's own signature, a
--   'CilMemberRef' signature, and @.locals@ entries. (The handful of shapes
--   Awsum's codegen needs; extend when a helper needs a shape not here.)
data SigElem
  = SeObject -- @object@ / ELEMENT_TYPE_OBJECT (0x1C)
  | SeString -- @string@ / ELEMENT_TYPE_STRING (0x0E)
  | SeInt32 -- @int32@ / ELEMENT_TYPE_I4 (0x08)
  | SeInt64 -- @int64@ / ELEMENT_TYPE_I8 (0x0A)
  | SeChar -- @char@ / ELEMENT_TYPE_CHAR (0x03)
  | SeBool -- @bool@ / ELEMENT_TYPE_BOOLEAN (0x02)
  | SeVoid -- @void@ / ELEMENT_TYPE_VOID (0x01)
  | -- | @class T@ / ELEMENT_TYPE_CLASS (0x12) + TypeDefOrRef-coded token.
    --   Multi-byte and token-bearing, so the assembler resolves it monadically
    --   (see @sigElemBytes@); used for BCL reference-type returns like
    --   @System.Text.Encoding@.
    SeClass CilTypeRef
  | -- | @valuetype T@ / ELEMENT_TYPE_VALUETYPE (0x11) + TypeDefOrRef token;
    --   used for BCL enum/struct params like @System.StringComparison@.
    SeValueType CilTypeRef
  | -- | @T[]@ / ELEMENT_TYPE_SZARRAY (0x1D) + element type; used for the
    --   @object[]@ scratch local that holds a @CCon@ cell mid-build, and the
    --   @string[]@ / @object[]@ locals in the argv glue.
    SeSZArray SigElem
  deriving stock (Eq, Show)

-- | A @MemberRef@ to a method: its parent type, name, whether it is an
--   instance method (@HASTHIS@), its return element type, and its parameter
--   element types. The assembler interns this into a 'MemberRef' row; the text
--   renderer prints @[asm]Ns.Type::name(params)@ with an @instance@ prefix.
data CilMemberRef = CilMemberRef
  { cmrParent :: CilTypeRef,
    cmrName :: Text,
    cmrInstance :: Bool,
    cmrRet :: SigElem,
    cmrParams :: [SigElem]
  }
  deriving stock (Eq, Show)

-- | A symbolic branch label (the full @IL_…@ name). The assembler resolves it
--   to a relative byte offset; the text renderer prints it verbatim.
newtype LabelId = LabelId Text
  deriving stock (Eq, Ord, Show)

-- | One abstract CIL instruction. Operands are symbolic; branch targets are
--   labels, never byte offsets. Branches use the long (4-byte-offset) form
--   uniformly — correct at any method size, and the text/byte projections stay
--   trivially in step (no size-dependent form selection).
data CilInstr
  = Ldarg Int
  | Ldloc Int
  | Stloc Int
  | Starg Int
  | LdcI4 Int
  | Dup
  | Pop
  | Newarr CilTypeRef
  | StelemRef
  | LdelemRef
  | Box CilTypeRef
  | UnboxAny CilTypeRef
  | Castclass CilTypeRef
  | -- | @castclass object[]@ — to the @object[]@ TypeSpec (SZARRAY OBJECT). The
    --   @CReuse@ in-place store needs a statically-array-typed value on the
    --   stack, but param/local slots are typed plain @object@.
    CastObjArr
  | Call CilMemberRef
  | Callvirt CilMemberRef
  | -- | @newobj@ a constructor 'CilMemberRef' (pops the ctor's params, pushes
    --   the new instance — no @this@).
    Newobj CilMemberRef
  | Ldlen
  | -- | @ldstr@ a literal (interned into the @#US@ heap by the assembler).
    Ldstr Text
  | Ldnull
  | -- | @call object AwsumMain::<name>(object…)@ — a static call to a sibling
    --   method (a prelude/user @v_…@ or a @__…@ helper) of the module class,
    --   resolved to its MethodDef token via the assembler's name→token map. The
    --   'Int' is the arity (param count), needed only for text rendering; every
    --   such method takes/returns @object@.
    CallNamed Text Int
  | Add
  | Sub
  | Neg
  | Mul
  | Div
  | Xor
  | And
  | Shl
  | ConvI4
  | ConvI8
  | ConvU4
  | ConvU8
  | LdcI8 Int64
  | BneUn LabelId
  | Brfalse LabelId
  | Brtrue LabelId
  | Br LabelId
  | Beq LabelId
  | Bge LabelId
  | Blt LabelId
  | Ble LabelId
  | Bgt LabelId
  | BgtUn LabelId
  | BltUn LabelId
  | Label LabelId
  | Ret
  deriving stock (Eq, Show)

-- | A static method: name, return type, parameter types, @.locals@ element
--   types, and body. @.maxstack@ is not stored — it is /derived/ from the body
--   by 'maxStackOf', so both projections compute the identical value and the
--   @.maxstack@ directive can neither be hand-wrong nor diverge from the PE
--   method header.
data CilMethod = CilMethod
  { cmName :: Text,
    cmRet :: SigElem,
    cmParams :: [SigElem],
    cmLocals :: [SigElem],
    cmBody :: [CilInstr]
  }
  deriving stock (Eq, Show)

-- | The @.maxstack@ a method needs, derived from its body: the peak evaluation-
--   stack depth across every instruction. Flow-aware single forward pass that
--   tracks the running depth and, at every branch, records the depth its target
--   label is entered with (a branch's target and its fall-through share the
--   post-pop depth; an unconditional branch's target keeps the current depth).
--   A @Label@ takes its recorded entry depth (or the fall-through depth if it is
--   only fall-through-reached); after @Ret@ / @Br@ the path is dead until the
--   next label. This is exact regardless of base depth, so it handles values
--   left live across case-arm / join labels (depth 1+), not just depth-0 labels.
--   @Call@/@Callvirt@ deltas come from the member signature.
maxStackOf :: [CilInstr] -> Int
maxStackOf = go (Just 0) 0 mempty
  where
    cv :: Maybe Int -> Int
    cv = fromMaybe 0
    go _ mx _ [] = mx
    go cur mx ed (i : is) = case i of
      Label (LabelId l) ->
        let d = fromMaybe (cv cur) (Map.lookup l ed)
         in go (Just d) (max mx d) ed is
      Ret -> go Nothing mx ed is
      _ -> case branchTarget i of
        Just (LabelId l, conditional) ->
          let c' = cv cur + delta i
              ed' = if Map.member l ed then ed else Map.insert l c' ed
           in go (if conditional then Just c' else Nothing) (max mx (cv cur)) ed' is
        Nothing ->
          let c' = cv cur + delta i in go (Just c') (max mx c') ed is
    -- @Just (target, isConditional)@ for branch instructions.
    branchTarget :: CilInstr -> Maybe (LabelId, Bool)
    branchTarget = \case
      Br l -> Just (l, False)
      BneUn l -> Just (l, True)
      Brfalse l -> Just (l, True)
      Brtrue l -> Just (l, True)
      Beq l -> Just (l, True)
      Bge l -> Just (l, True)
      Blt l -> Just (l, True)
      Ble l -> Just (l, True)
      Bgt l -> Just (l, True)
      BgtUn l -> Just (l, True)
      BltUn l -> Just (l, True)
      _ -> Nothing
    delta :: CilInstr -> Int
    delta = \case
      Ldarg _ -> 1
      Ldloc _ -> 1
      LdcI4 _ -> 1
      LdcI8 _ -> 1
      Dup -> 1
      Pop -> -1
      Stloc _ -> -1
      Starg _ -> -1
      Newarr _ -> 0
      StelemRef -> -3
      LdelemRef -> -1
      Box _ -> 0
      UnboxAny _ -> 0
      Castclass _ -> 0
      CastObjArr -> 0
      Neg -> 0
      ConvI4 -> 0
      ConvI8 -> 0
      ConvU4 -> 0
      ConvU8 -> 0
      Add -> -1
      Sub -> -1
      Mul -> -1
      Div -> -1
      Xor -> -1
      And -> -1
      Shl -> -1
      Call mr -> callDelta mr
      Callvirt mr -> callDelta mr
      Newobj mr -> 1 - length (cmrParams mr) -- pops ctor params, pushes the new instance
      Ldlen -> 0 -- pops array, pushes length
      Ldstr _ -> 1
      Ldnull -> 1
      CallNamed _ arity -> 1 - arity -- pops the args, pushes one object result
      BneUn _ -> -2
      Beq _ -> -2
      Bge _ -> -2
      Blt _ -> -2
      Ble _ -> -2
      Bgt _ -> -2
      BgtUn _ -> -2
      BltUn _ -> -2
      Brfalse _ -> -1
      Brtrue _ -> -1
      Br _ -> 0
      Label _ -> 0
      Ret -> 0
    callDelta :: CilMemberRef -> Int
    callDelta mr =
      negate (length (cmrParams mr) + (if cmrInstance mr then 1 else 0))
        + (if cmrRet mr == SeVoid then 0 else 1)

-- | The assembly-qualified name of a 'CilTypeRef', e.g.
--   @[System.Runtime]System.Int32@.
renderTypeRef :: CilTypeRef -> Text
renderTypeRef (CilTypeRef asm ns name) =
  "[" <> asmName asm <> "]" <> ns <> "." <> name
  where
    asmName 2 = "System.Console"
    asmName _ = "System.Runtime"

-- | A signature element as it appears in CIL text.
renderSigElem :: SigElem -> Text
renderSigElem = \case
  SeObject -> "object"
  SeString -> "string"
  SeInt32 -> "int32"
  SeInt64 -> "int64"
  SeChar -> "char"
  SeBool -> "bool"
  SeVoid -> "void"
  SeClass tr -> "class " <> renderTypeRef tr
  SeValueType tr -> "valuetype " <> renderTypeRef tr
  SeSZArray e -> renderSigElem e <> "[]"

renderMemberRef :: CilMemberRef -> Text
renderMemberRef (CilMemberRef parent name isInstance ret params) =
  (if isInstance then "instance " else "")
    <> renderSigElem ret
    <> " "
    <> renderTypeRef parent
    <> "::"
    <> name
    <> "("
    <> T.intercalate "," (map renderSigElem params)
    <> ")"

-- | Total, decision-free text projection of a single instruction (4-space
--   body indent, matching the existing hand-written CIL).
renderCilInstr :: CilInstr -> Text
renderCilInstr = \case
  Ldarg n
    | n <= 3 -> "    ldarg." <> show n
    | otherwise -> "    ldarg.s " <> show n
  Ldloc n
    | n <= 3 -> "    ldloc." <> show n
    | n <= 255 -> "    ldloc.s " <> show n
    | otherwise -> "    ldloc " <> show n
  Stloc n
    | n <= 3 -> "    stloc." <> show n
    | n <= 255 -> "    stloc.s " <> show n
    | otherwise -> "    stloc " <> show n
  Starg n
    | n <= 255 -> "    starg.s " <> show n
    | otherwise -> "    starg " <> show n
  LdcI4 n
    | n >= 0 && n <= 8 -> "    ldc.i4." <> show n
    | n == -1 -> "    ldc.i4.m1"
    | n >= -128 && n <= 127 -> "    ldc.i4.s " <> show n
    | otherwise -> "    ldc.i4 " <> show n
  Dup -> "    dup"
  Pop -> "    pop"
  Newarr tr -> "    newarr " <> renderTypeRef tr
  StelemRef -> "    stelem.ref"
  LdelemRef -> "    ldelem.ref"
  Box tr -> "    box " <> renderTypeRef tr
  UnboxAny tr -> "    unbox.any " <> renderTypeRef tr
  Castclass tr -> "    castclass " <> renderTypeRef tr
  CastObjArr -> "    castclass object[]"
  Call mr -> "    call " <> renderMemberRef mr
  Callvirt mr -> "    callvirt " <> renderMemberRef mr
  Newobj mr -> "    newobj " <> renderMemberRef mr
  Ldlen -> "    ldlen"
  Ldstr s -> "    ldstr " <> show s
  Ldnull -> "    ldnull"
  CallNamed name arity ->
    "    call object AwsumMain::" <> name <> "(" <> T.intercalate ", " (replicate arity "object") <> ")"
  Add -> "    add"
  Sub -> "    sub"
  Neg -> "    neg"
  Mul -> "    mul"
  Div -> "    div"
  Xor -> "    xor"
  And -> "    and"
  Shl -> "    shl"
  ConvI4 -> "    conv.i4"
  ConvI8 -> "    conv.i8"
  ConvU4 -> "    conv.u4"
  ConvU8 -> "    conv.u8"
  LdcI8 n -> "    ldc.i8 " <> show n
  BneUn (LabelId l) -> "    bne.un " <> l
  Brfalse (LabelId l) -> "    brfalse " <> l
  Brtrue (LabelId l) -> "    brtrue " <> l
  Br (LabelId l) -> "    br " <> l
  Beq (LabelId l) -> "    beq " <> l
  Bge (LabelId l) -> "    bge " <> l
  Blt (LabelId l) -> "    blt " <> l
  Ble (LabelId l) -> "    ble " <> l
  Bgt (LabelId l) -> "    bgt " <> l
  BgtUn (LabelId l) -> "    bgt.un " <> l
  BltUn (LabelId l) -> "    blt.un " <> l
  Label (LabelId l) -> "  " <> l <> ":"
  Ret -> "    ret"

-- | Total, decision-free text projection of a method — the same ilasm-like
--   shape 'Awsum.Codegen.CLR' emitted by hand: a @.method@ header, @.maxstack@,
--   an optional @.locals init@, the body, and a closing brace.
renderCilMethod :: CilMethod -> Text
renderCilMethod m =
  unlines
    $ [ "  .method private hidebysig static "
          <> renderSigElem (cmRet m)
          <> " "
          <> cmName m
          <> "("
          <> T.intercalate "," (map renderSigElem (cmParams m))
          <> ") cil managed",
        "  {",
        "    .maxstack " <> show (maxStackOf (cmBody m))
      ]
    <> ( [ "    .locals init ("
             <> T.intercalate ", " [renderSigElem t <> " V_" <> show i | (t, i) <- zip (cmLocals m) [0 :: Int ..]]
             <> ")"
         | not (null (cmLocals m))
         ]
       )
    <> map renderCilInstr (cmBody m)
    <> ["  }"]

-- ════════════════════════════════════════════════════════════════════════════
-- Method specs
-- ════════════════════════════════════════════════════════════════════════════

-- | @__showUInt32@: unbox the @Int32@, re-box as @UInt32@, and @ToString()@ —
--   so the @2^31..2^32-1@ range prints unsigned, where a signed
--   @Int32.ToString@ would print negative. Branchless.
showUInt32Spec :: CilMethod
showUInt32Spec =
  CilMethod
    { cmName = "__showUInt32",
      cmRet = SeObject,
      cmParams = [SeObject],
      cmLocals = [],
      cmBody =
        [ Ldarg 0,
          UnboxAny (CilTypeRef 1 "System" "Int32"),
          Box (CilTypeRef 1 "System" "UInt32"),
          Callvirt (CilMemberRef (CilTypeRef 1 "System" "Object") "ToString" True SeString []),
          Ret
        ]
    }

-- | @[System.Runtime]System.Int32@ / @System.Object@ — the two type refs every
--   boxed-cell fragment needs.
int32Ref, objectRef, strRef :: CilTypeRef
int32Ref = CilTypeRef 1 "System" "Int32"
objectRef = CilTypeRef 1 "System" "Object"
strRef = CilTypeRef 1 "System" "String"

-- | A constructor cell: @Object[1 + n] = { Integer(tag), field0, … }@. Awsum's
--   runtime representation of a tagged value is an @object[]@ whose slot 0 is
--   the boxed FNV-1a row tag and whose remaining slots hold the fields. Each
--   field's instructions must net +1 on the stack.
cell :: Int -> [[CilInstr]] -> [CilInstr]
cell tag fields =
  [LdcI4 (1 + length fields), Newarr objectRef, Dup, LdcI4 0, LdcI4 tag, Box int32Ref, StelemRef]
    <> concat [[Dup, LdcI4 (i + 1)] <> f <> [StelemRef] | (i, f) <- zip [0 ..] fields]

-- | A nullary cell (no fields) — @cell tag []@.
nullaryCell :: Int -> [CilInstr]
nullaryCell tag = cell tag []

-- | A unary cell — @cell tag [valueInstrs]@.
unaryCell :: Int -> [CilInstr] -> [CilInstr]
unaryCell tag valueInstrs = cell tag [valueInstrs]

-- | The shared shape of @__predInt32@ / @__succInt32@ / @__negInt32@ and their
--   @UInt8@ / @UInt32@ siblings: unbox the argument to @int32@, compare against a
--   @boundary@ (the one input value that would overflow/underflow), and either
--   build @Left errTag@ (boundary hit) or @Right (arith applied)@ (otherwise).
--
--   @okArith@ is the body that, given the unboxed argument already on the stack,
--   produces the successful result: @[LdcI4 1, Sub]@ for pred, @[LdcI4 1, Add]@
--   for succ, @[Neg]@ for negate.
--
--   The boundary test is @bne.un@: when the argument differs from @boundary@ we
--   jump to the @ok@ label; otherwise we fall through to the @Left@ block. Slot
--   0 holds the unboxed @int32@ argument; slot 1 the boxed error tag.
predSuccSpec ::
  -- | method name (@__predInt32@, …)
  Text ->
  -- | boundary value that overflows/underflows
  Int ->
  -- | arithmetic applied on success (argument already on stack)
  [CilInstr] ->
  -- | inner error tag (Underflow / Overflow)
  Int ->
  -- | @Left@ row tag
  Int ->
  -- | @Right@ row tag
  Int ->
  -- | the @ok@ branch label (unique per method)
  Text ->
  CilMethod
predSuccSpec name boundary okArith errTag leftTag rightTag okLbl =
  CilMethod
    { cmName = name,
      cmRet = SeObject,
      cmParams = [SeObject],
      cmLocals = [SeInt32, SeObject],
      cmBody =
        [Ldarg 0, UnboxAny int32Ref, Stloc 0, Ldloc 0, LdcI4 boundary, BneUn (LabelId okLbl)]
          <> nullaryCell errTag
          <> [Stloc 1]
          <> unaryCell leftTag [Ldloc 1]
          <> [Ret]
          <> [Label (LabelId okLbl)]
          <> unaryCell rightTag (Ldloc 0 : okArith)
          <> [Ret]
    }

-- | The eight @pred@ / @succ@ / @negate@ helpers. Each takes the three runtime
--   row tags it needs — @(errTag, leftTag, rightTag)@ — from the caller's
--   'PreludeTags', so the spec literals (boundary, arithmetic, ok-label) live
--   here once and feed both the @.il@ text and the @.dll@ bytes. The successful
--   arithmetic boxes its @int32@ result back to @System.Int32@ (every numeric
--   value travels through the runtime as a boxed @Int32@, @UInt8@/@UInt32@
--   included).
predInt32Spec, predUInt8Spec, predUInt32Spec :: Int -> Int -> Int -> CilMethod
predInt32Spec e l r = predSuccSpec "__predInt32" (-2147483648) [LdcI4 1, Sub, Box int32Ref] e l r "IL_pred_ok"
predUInt8Spec e l r = predSuccSpec "__predUInt8" 0 [LdcI4 1, Sub, Box int32Ref] e l r "IL_predu8_ok"
predUInt32Spec e l r = predSuccSpec "__predUInt32" 0 [LdcI4 1, Sub, Box int32Ref] e l r "IL_predu32_ok"

succInt32Spec, succUInt8Spec, succUInt32Spec, negInt32Spec :: Int -> Int -> Int -> CilMethod
succInt32Spec e l r = predSuccSpec "__succInt32" 2147483647 [LdcI4 1, Add, Box int32Ref] e l r "IL_succ_ok"
succUInt8Spec e l r = predSuccSpec "__succUInt8" 255 [LdcI4 1, Add, Box int32Ref] e l r "IL_succu8_ok"
succUInt32Spec e l r = predSuccSpec "__succUInt32" (-1) [LdcI4 1, Add, Box int32Ref] e l r "IL_succu32_ok"
negInt32Spec e l r = predSuccSpec "__negInt32" (-2147483648) [Neg, Box int32Ref] e l r "IL_neg_ok"

-- | The three integer-equality helpers @__eqInt32@ / @__eqUInt8@ / @__eqUInt32@.
--   Unbox both arguments to @int32@ and compare with @bne.un@: equal falls
--   through to the @Right@-shaped @True@ cell, unequal jumps to the @_ne@ label
--   and builds the @False@ cell. @lbl@ is the label prefix the call site picks
--   (@IL_eq_i32@, …); the not-equal target is @lbl ++ "_ne"@.
eqSpec :: Text -> Text -> Int -> Int -> CilMethod
eqSpec name lbl trueTag falseTag =
  CilMethod
    { cmName = name,
      cmRet = SeObject,
      cmParams = [SeObject, SeObject],
      cmLocals = [],
      cmBody =
        [Ldarg 0, UnboxAny int32Ref, Ldarg 1, UnboxAny int32Ref, BneUn (LabelId (lbl <> "_ne"))]
          <> nullaryCell trueTag
          <> [Ret]
          <> [Label (LabelId (lbl <> "_ne"))]
          <> nullaryCell falseTag
          <> [Ret]
    }

-- | @__eqString@: UTF-16 code-unit string equality. Cast both arguments to
--   @string@ and call the static @System.String::op_Equality(string, string)@
--   (which returns @bool@ — hence 'SeBool', whose @0x02@ signature byte must
--   match the BCL method or runtime binding fails). @brfalse@ over the @True@
--   cell to the @False@ cell.
eqStringSpec :: Int -> Int -> CilMethod
eqStringSpec trueTag falseTag =
  CilMethod
    { cmName = "__eqString",
      cmRet = SeObject,
      cmParams = [SeObject, SeObject],
      cmLocals = [],
      cmBody =
        [ Ldarg 0,
          Castclass stringRef,
          Ldarg 1,
          Castclass stringRef,
          Call (CilMemberRef stringRef "op_Equality" False SeBool [SeString, SeString]),
          Brfalse (LabelId "IL_eq_str_ne")
        ]
          <> nullaryCell trueTag
          <> [Ret]
          <> [Label (LabelId "IL_eq_str_ne")]
          <> nullaryCell falseTag
          <> [Ret]
    }
  where
    stringRef = CilTypeRef 1 "System" "String"

-- | @__print@: the low-level stdout primitive the prelude's @runIO@ drives via
--   @BuiltIn.internalStdoutPrint@. Write the argument with the static
--   @System.Console::Write(object)@ and return a @Unit@ cell.
printSpec :: Int -> CilMethod
printSpec unitTag =
  CilMethod
    { cmName = "__print",
      cmRet = SeObject,
      cmParams = [SeObject],
      cmLocals = [],
      cmBody =
        [ Ldarg 0,
          Call (CilMemberRef (CilTypeRef 2 "System" "Console") "Write" False SeVoid [SeObject])
        ]
          <> nullaryCell unitTag
          <> [Ret]
    }

-- ── Arithmetic (add / sub / mul × Int32 / UInt8 / UInt32) ─────────────────────
--
-- Each is @(object, object) -> object@: unbox the two operands to @int32@,
-- compute, and return either @Right result@ or @Left err@ where the error is a
-- row-injected @OverflowError@ / @UnderflowError@ wrapped in a @Left@ cell.
-- Overflow detection differs by type: Int32 add/sub use the sign-bit XOR trick,
-- Int32 mul widens to @int64@ and range-checks, UInt8 range-checks against 255,
-- UInt32 widens to @uint64@ (@conv.u8@) and range-checks against @2^32-1@ then
-- narrows back with @conv.u4@.

-- | A binary-arithmetic helper skeleton: @(object, object) -> object@.
arithMethod :: Text -> [SigElem] -> [CilInstr] -> CilMethod
arithMethod name locals body =
  CilMethod {cmName = name, cmRet = SeObject, cmParams = [SeObject, SeObject], cmLocals = locals, cmBody = body}

-- | The error arm for a /single nominal/ error (no row): build a nullary
--   @innerTag@ cell, stash it to local @slot@, and wrap it as the unary field
--   of a @Left@ cell. Ends in @Ret@. Used by the UInt8 / UInt32 helpers, whose
--   error side is one fixed nominal type.
leftErr :: Int -> Int -> Int -> [CilInstr]
leftErr innerTag leftTag slot =
  nullaryCell innerTag <> [Stloc slot] <> unaryCell leftTag [Ldloc slot] <> [Ret]

-- | The error arm for a /row/ error @(UnderflowError | OverflowError)@: three
--   nested cells, matching the binary @mkAddInt32@'s @makeLeft@. (1) the nullary
--   nominal error cell tagged by its constructor index @nominalTag@; (2) the
--   row-injection cell tagged by the FNV row hash @rowTagVal@ wrapping (1);
--   (3) the @Left@ cell wrapping (2). Uses two object locals — @innerSlot@ for
--   (1), @rowSlot@ for (2). Ends in @Ret@.
leftRowErr :: Int -> Int -> Int -> Int -> Int -> [CilInstr]
leftRowErr nominalTag rowTagVal leftTag innerSlot rowSlot =
  nullaryCell nominalTag
    <> [Stloc innerSlot]
    <> unaryCell rowTagVal [Ldloc innerSlot]
    <> [Stloc rowSlot]
    <> unaryCell leftTag [Ldloc rowSlot]
    <> [Ret]

-- | FNV-1a 32-bit row tags for @OverflowError@ / @UnderflowError@ as row
--   alternatives — the tag user-side row dispatch (@v_render@) compares against,
--   distinct from the nominal constructor index ('PreludeTags'). Cast through
--   'Int32' so the bit pattern fits @ldc.i4@'s lower 32 bits.
overflowRowTag, underflowRowTag, stringTooLongRowTag, unpairedSurrogateRowTag :: Int
overflowRowTag = fromIntegral (fromIntegral (rowTag (TyCon noSpan "OverflowError")) :: Int32)
underflowRowTag = fromIntegral (fromIntegral (rowTag (TyCon noSpan "UnderflowError")) :: Int32)
stringTooLongRowTag = fromIntegral (fromIntegral (rowTag (TyCon noSpan "StringTooLong")) :: Int32)
unpairedSurrogateRowTag = fromIntegral (fromIntegral (rowTag (TyCon noSpan "UnpairedUtf16Surrogate")) :: Int32)

-- Tag arguments are passed positionally from the call site's 'PreludeTags':
-- @right@ = ptRight, @over@ = ptOverflowError, @under@ = ptUnderflowError,
-- @left@ = ptLeft. The Int32 helpers' error type is the row
-- @(UnderflowError | OverflowError)@, so their error arms use 'leftRowErr' with
-- the FNV row tags above; UInt8 / UInt32 errors are single nominal types and use
-- 'leftErr'.

addInt32Spec :: Int -> Int -> Int -> Int -> CilMethod
addInt32Spec right over under left =
  arithMethod "__addInt32" [SeInt32, SeInt32, SeInt32, SeObject, SeObject]
    $ [ Ldarg 0,
        UnboxAny int32Ref,
        Stloc 0,
        Ldarg 1,
        UnboxAny int32Ref,
        Stloc 1,
        Ldloc 0,
        Ldloc 1,
        Add,
        Stloc 2,
        Ldloc 0,
        Ldloc 2,
        Xor,
        Ldloc 1,
        Ldloc 2,
        Xor,
        And,
        LdcI4 0,
        Blt (LabelId "IL_addi32_over")
      ]
    <> unaryCell right [Ldloc 2, Box int32Ref]
    <> [Ret, Label (LabelId "IL_addi32_over"), Ldloc 0, LdcI4 0, Blt (LabelId "IL_addi32_under")]
    <> leftRowErr over overflowRowTag left 3 4
    <> [Label (LabelId "IL_addi32_under")]
    <> leftRowErr under underflowRowTag left 3 4

subInt32Spec :: Int -> Int -> Int -> Int -> CilMethod
subInt32Spec right over under left =
  arithMethod "__subInt32" [SeInt32, SeInt32, SeInt32, SeObject, SeObject]
    $ [ Ldarg 0,
        UnboxAny int32Ref,
        Stloc 0,
        Ldarg 1,
        UnboxAny int32Ref,
        Stloc 1,
        Ldloc 0,
        Ldloc 1,
        Sub,
        Stloc 2,
        Ldloc 0,
        Ldloc 1,
        Xor,
        Ldloc 0,
        Ldloc 2,
        Xor,
        And,
        LdcI4 0,
        Blt (LabelId "IL_subi32_over")
      ]
    <> unaryCell right [Ldloc 2, Box int32Ref]
    <> [Ret, Label (LabelId "IL_subi32_over"), Ldloc 0, LdcI4 0, Blt (LabelId "IL_subi32_under")]
    <> leftRowErr over overflowRowTag left 3 4
    <> [Label (LabelId "IL_subi32_under")]
    <> leftRowErr under underflowRowTag left 3 4

mulInt32Spec :: Int -> Int -> Int -> Int -> CilMethod
mulInt32Spec right over under left =
  arithMethod "__mulInt32" [SeInt32, SeInt32, SeInt64, SeObject, SeObject]
    $ [ Ldarg 0,
        UnboxAny int32Ref,
        Stloc 0,
        Ldarg 1,
        UnboxAny int32Ref,
        Stloc 1,
        Ldloc 0,
        ConvI8,
        Ldloc 1,
        ConvI8,
        Mul,
        Stloc 2,
        Ldloc 2,
        LdcI4 2147483647,
        ConvI8,
        Bgt (LabelId "IL_muli32_over"),
        Ldloc 2,
        LdcI4 (-2147483648),
        ConvI8,
        Blt (LabelId "IL_muli32_under")
      ]
    <> unaryCell right [Ldloc 2, ConvI4, Box int32Ref]
    <> [Ret, Label (LabelId "IL_muli32_over")]
    <> leftRowErr over overflowRowTag left 3 4
    <> [Label (LabelId "IL_muli32_under")]
    <> leftRowErr under underflowRowTag left 3 4

addUInt8Spec :: Int -> Int -> Int -> CilMethod
addUInt8Spec right over left =
  arithMethod "__addUInt8" [SeInt32, SeObject]
    $ [Ldarg 0, UnboxAny int32Ref, Ldarg 1, UnboxAny int32Ref, Add, Stloc 0, Ldloc 0, LdcI4 255, Ble (LabelId "IL_addu8_ok")]
    <> leftErr over left 1
    <> [Label (LabelId "IL_addu8_ok")]
    <> unaryCell right [Ldloc 0, Box int32Ref]
    <> [Ret]

subUInt8Spec :: Int -> Int -> Int -> CilMethod
subUInt8Spec right under left =
  arithMethod "__subUInt8" [SeInt32, SeObject]
    $ [Ldarg 0, UnboxAny int32Ref, Ldarg 1, UnboxAny int32Ref, Sub, Stloc 0, Ldloc 0, LdcI4 0, Blt (LabelId "IL_subu8_under")]
    <> unaryCell right [Ldloc 0, Box int32Ref]
    <> [Ret, Label (LabelId "IL_subu8_under")]
    <> leftErr under left 1

mulUInt8Spec :: Int -> Int -> Int -> CilMethod
mulUInt8Spec right over left =
  arithMethod "__mulUInt8" [SeInt32, SeObject]
    $ [Ldarg 0, UnboxAny int32Ref, Ldarg 1, UnboxAny int32Ref, Mul, Stloc 0, Ldloc 0, LdcI4 255, Ble (LabelId "IL_mulu8_ok")]
    <> leftErr over left 1
    <> [Label (LabelId "IL_mulu8_ok")]
    <> unaryCell right [Ldloc 0, Box int32Ref]
    <> [Ret]

addUInt32Spec :: Int -> Int -> Int -> CilMethod
addUInt32Spec right over left =
  arithMethod "__addUInt32" [SeInt64, SeObject]
    $ [Ldarg 0, UnboxAny int32Ref, ConvU8, Ldarg 1, UnboxAny int32Ref, ConvU8, Add, Stloc 0, Ldloc 0, LdcI8 4294967295, BgtUn (LabelId "IL_addu32_over")]
    <> unaryCell right [Ldloc 0, ConvU4, Box int32Ref]
    <> [Ret, Label (LabelId "IL_addu32_over")]
    <> leftErr over left 1

subUInt32Spec :: Int -> Int -> Int -> CilMethod
subUInt32Spec right under left =
  arithMethod "__subUInt32" [SeInt32, SeInt32, SeObject]
    $ [Ldarg 0, UnboxAny int32Ref, Stloc 0, Ldarg 1, UnboxAny int32Ref, Stloc 1, Ldloc 0, Ldloc 1, BltUn (LabelId "IL_subu32_under")]
    <> unaryCell right [Ldloc 0, Ldloc 1, Sub, Box int32Ref]
    <> [Ret, Label (LabelId "IL_subu32_under")]
    <> leftErr under left 2

mulUInt32Spec :: Int -> Int -> Int -> CilMethod
mulUInt32Spec right over left =
  arithMethod "__mulUInt32" [SeInt64, SeObject]
    $ [Ldarg 0, UnboxAny int32Ref, ConvU8, Ldarg 1, UnboxAny int32Ref, ConvU8, Mul, Stloc 0, Ldloc 0, LdcI8 4294967295, BgtUn (LabelId "IL_mulu32_over")]
    <> unaryCell right [Ldloc 0, ConvU4, Box int32Ref]
    <> [Ret, Label (LabelId "IL_mulu32_over")]
    <> leftErr over left 1

-- ── Strings ───────────────────────────────────────────────────────────────────

-- | @System.Text.Encoding@ — the BCL class whose static @UTF8@ / @UTF32@
--   properties the length helpers read. Lives in the @System.Runtime@ assembly.
encodingRef :: CilTypeRef
encodingRef = CilTypeRef 1 "System.Text" "Encoding"

-- | @String.get_Length@ — instance @int32@ property, no params.
getLengthRef :: CilMemberRef
getLengthRef = CilMemberRef strRef "get_Length" True SeInt32 []

-- | @String.get_Chars(int32)@ — instance @char@ indexer (the @char@ lands on the
--   stack as an int32, but the member signature is @char@ = 0x03).
getCharsRef :: CilMemberRef
getCharsRef = CilMemberRef strRef "get_Chars" True SeChar [SeInt32]

-- | @String.GetByteCount@ on an @Encoding@ — instance @int32@, one @string@ arg.
getByteCountRef :: CilMemberRef
getByteCountRef = CilMemberRef encodingRef "GetByteCount" True SeInt32 [SeString]

-- | @__concat@ (@BuiltIn.concatString@): @Right (a ++ b)@ when the combined
--   UTF-16 length fits @maxStringLengthUtf16CodeUnits@ = 2^27, else
--   @Left StringTooLong@. The two @get_Length@s are summed as @int64@ and
--   compared unsigned against the cap. The cap must stay in sync with
--   @maxStringLengthUtf16CodeUnits@ in @stdlib/Prelude.aww@ and the other
--   backends. @right@ = ptRight, @left@ = ptLeft, @stl@ = ptStringTooLong.
concatSpec :: Int -> Int -> Int -> CilMethod
concatSpec right left stl =
  CilMethod
    { cmName = "__concat",
      cmRet = SeObject,
      cmParams = [SeObject, SeObject],
      cmLocals = [SeObject],
      cmBody =
        [ Ldarg 0,
          Castclass strRef,
          Callvirt getLengthRef,
          ConvI8,
          Ldarg 1,
          Castclass strRef,
          Callvirt getLengthRef,
          ConvI8,
          Add,
          LdcI8 134217728,
          BgtUn (LabelId "IL_concat_toolong"),
          Ldarg 0,
          Ldarg 1,
          Call concatRef,
          Stloc 0
        ]
          <> unaryCell right [Ldloc 0]
          <> [Ret, Label (LabelId "IL_concat_toolong")]
          <> leftErr stl left 0
    }
  where
    concatRef = CilMemberRef strRef "Concat" False SeString [SeObject, SeObject]

-- | @__splitOnFirst@ (sep, haystack): @Just (Tuple2 before after)@ at the first
--   ordinal occurrence of @sep@ in @haystack@, else @Nothing@. @nothing@ =
--   ptNothing, @tuple2@ = ptTuple2, @just@ = ptJust.
splitOnFirstSpec :: Int -> Int -> Int -> CilMethod
splitOnFirstSpec nothing tuple2 just =
  CilMethod
    { cmName = "__splitOnFirst",
      cmRet = SeObject,
      cmParams = [SeObject, SeObject],
      cmLocals = [SeString, SeString, SeInt32, SeString, SeString, SeObject],
      cmBody =
        [ Ldarg 0,
          Castclass strRef,
          Stloc 0,
          Ldarg 1,
          Castclass strRef,
          Stloc 1,
          Ldloc 1,
          Ldloc 0,
          LdcI4 4,
          Callvirt indexOfRef,
          Stloc 2,
          Ldloc 2,
          LdcI4 (-1),
          BneUn (LabelId "IL_split_found")
        ]
          <> cell nothing []
          <> [ Ret,
               Label (LabelId "IL_split_found"),
               Ldloc 1,
               LdcI4 0,
               Ldloc 2,
               Callvirt substring2Ref,
               Stloc 3,
               Ldloc 1,
               Ldloc 2,
               Ldloc 0,
               Callvirt getLengthRef,
               Add,
               Callvirt substring1Ref,
               Stloc 4
             ]
          <> cell tuple2 [[Ldloc 3], [Ldloc 4]]
          <> [Stloc 5]
          <> cell just [[Ldloc 5]]
          <> [Ret]
    }
  where
    indexOfRef = CilMemberRef strRef "IndexOf" True SeInt32 [SeString, SeValueType (CilTypeRef 1 "System" "StringComparison")]
    substring2Ref = CilMemberRef strRef "Substring" True SeString [SeInt32, SeInt32]
    substring1Ref = CilMemberRef strRef "Substring" True SeString [SeInt32]

-- | @__lengthUtf16CodeUnits@: .NET strings are UTF-16, so @String.Length@ is the
--   code-unit count by definition.
lengthUtf16CodeUnitsSpec :: CilMethod
lengthUtf16CodeUnitsSpec =
  CilMethod
    { cmName = "__lengthUtf16CodeUnits",
      cmRet = SeObject,
      cmParams = [SeObject],
      cmLocals = [],
      cmBody = [Ldarg 0, Castclass strRef, Callvirt getLengthRef, Box int32Ref, Ret]
    }

-- | @__lengthUtf8Bytes@: @Encoding.UTF8.GetByteCount(s)@ — no bytes materialised.
lengthUtf8BytesSpec :: CilMethod
lengthUtf8BytesSpec =
  CilMethod
    { cmName = "__lengthUtf8Bytes",
      cmRet = SeObject,
      cmParams = [SeObject],
      cmLocals = [],
      cmBody =
        [ Call (CilMemberRef encodingRef "get_UTF8" False (SeClass encodingRef) []),
          Ldarg 0,
          Castclass strRef,
          Callvirt getByteCountRef,
          Box int32Ref,
          Ret
        ]
    }

-- | @__lengthCodePoints@: @Encoding.UTF32.GetByteCount(s) / 4@ — exact code-point
--   count (every UTF-32 unit is 4 bytes).
lengthCodePointsSpec :: CilMethod
lengthCodePointsSpec =
  CilMethod
    { cmName = "__lengthCodePoints",
      cmRet = SeObject,
      cmParams = [SeObject],
      cmLocals = [],
      cmBody =
        [ Call (CilMemberRef encodingRef "get_UTF32" False (SeClass encodingRef) []),
          Ldarg 0,
          Castclass strRef,
          Callvirt getByteCountRef,
          LdcI4 4,
          Div,
          Box int32Ref,
          Ret
        ]
    }

-- ── Parse (String -> Either ParseError <int>) ─────────────────────────────────
--
-- Each scans the string a char at a time, accumulating in an int (UInt8) or
-- int64 (Int32/UInt32) and failing on a non-digit, an empty string, or a
-- magnitude past the type's range. @right@ = ptRight, @parseErr@ = ptParseError,
-- @left@ = ptLeft. ParseError is a single nominal error (2-level 'leftErr').

-- | @__parseInt32@: optional leading @-@, int64 accumulator, magnitude capped at
--   @2^31@ (built as @1 << 31@), negated then range-checked against INT32_MAX.
--   Locals: s, len, i, neg, acc(int64), c, payload.
parseInt32Spec :: Int -> Int -> Int -> CilMethod
parseInt32Spec right parseErr left =
  CilMethod
    { cmName = "__parseInt32",
      cmRet = SeObject,
      cmParams = [SeObject],
      cmLocals = [SeString, SeInt32, SeInt32, SeInt32, SeInt64, SeInt32, SeObject],
      cmBody =
        [ Ldarg 0,
          Castclass strRef,
          Stloc 0,
          Ldloc 0,
          Callvirt getLengthRef,
          Stloc 1,
          Ldloc 1,
          Brfalse failL,
          LdcI4 0,
          Stloc 2,
          LdcI4 0,
          Stloc 3,
          Ldloc 0,
          LdcI4 0,
          Callvirt getCharsRef,
          LdcI4 45,
          BneUn initacc,
          LdcI4 1,
          Stloc 3,
          LdcI4 1,
          Stloc 2,
          Ldloc 1,
          LdcI4 1,
          Beq failL,
          Label initacc,
          LdcI4 0,
          ConvI8,
          Stloc 4,
          Label loop,
          Ldloc 2,
          Ldloc 1,
          Bge afterloop,
          Ldloc 0,
          Ldloc 2,
          Callvirt getCharsRef,
          Stloc 5,
          Ldloc 5,
          LdcI4 48,
          Blt failL,
          Ldloc 5,
          LdcI4 57,
          Bgt failL,
          Ldloc 4,
          LdcI4 10,
          ConvI8,
          Mul,
          Ldloc 5,
          LdcI4 48,
          Sub,
          ConvI8,
          Add,
          Stloc 4,
          Ldloc 4,
          LdcI4 1,
          ConvI8,
          LdcI4 31,
          Shl,
          Bgt failL,
          Ldloc 2,
          LdcI4 1,
          Add,
          Stloc 2,
          Br loop,
          Label afterloop,
          Ldloc 3,
          Brfalse poscheck,
          Ldloc 4,
          Neg,
          Stloc 4,
          Br buildright,
          Label poscheck,
          Ldloc 4,
          LdcI4 2147483647,
          ConvI8,
          Bgt failL,
          Label buildright
        ]
          <> unaryCell right [Ldloc 4, ConvI4, Box int32Ref]
          <> [Ret, Label failL]
          <> leftErr parseErr left 6
    }
  where
    failL = LabelId "IL_parsei32_fail"
    initacc = LabelId "IL_parsei32_initacc"
    loop = LabelId "IL_parsei32_loop"
    afterloop = LabelId "IL_parsei32_afterloop"
    poscheck = LabelId "IL_parsei32_poscheck"
    buildright = LabelId "IL_parsei32_buildright"

-- | @__parseUInt8@: no sign, int32 accumulator, fail when it exceeds 255.
--   Locals: s, len, i, acc, c, payload.
parseUInt8Spec :: Int -> Int -> Int -> CilMethod
parseUInt8Spec right parseErr left =
  CilMethod
    { cmName = "__parseUInt8",
      cmRet = SeObject,
      cmParams = [SeObject],
      cmLocals = [SeString, SeInt32, SeInt32, SeInt32, SeInt32, SeObject],
      cmBody =
        [ Ldarg 0,
          Castclass strRef,
          Stloc 0,
          Ldloc 0,
          Callvirt getLengthRef,
          Stloc 1,
          Ldloc 1,
          Brfalse failL,
          LdcI4 0,
          Stloc 2,
          LdcI4 0,
          Stloc 3,
          Label loop,
          Ldloc 2,
          Ldloc 1,
          Bge ok,
          Ldloc 0,
          Ldloc 2,
          Callvirt getCharsRef,
          Stloc 4,
          Ldloc 4,
          LdcI4 48,
          Blt failL,
          Ldloc 4,
          LdcI4 57,
          Bgt failL,
          Ldloc 3,
          LdcI4 10,
          Mul,
          Ldloc 4,
          LdcI4 48,
          Sub,
          Add,
          Stloc 3,
          Ldloc 3,
          LdcI4 255,
          Bgt failL,
          Ldloc 2,
          LdcI4 1,
          Add,
          Stloc 2,
          Br loop,
          Label ok
        ]
          <> unaryCell right [Ldloc 3, Box int32Ref]
          <> [Ret, Label failL]
          <> leftErr parseErr left 5
    }
  where
    failL = LabelId "IL_parseu8_fail"
    loop = LabelId "IL_parseu8_loop"
    ok = LabelId "IL_parseu8_ok"

-- | @__parseUInt32@: no sign, int64 accumulator, fail when it exceeds 2^32-1,
--   narrow back with @conv.u4@. Locals: s, len, i, acc(int64), c, payload.
parseUInt32Spec :: Int -> Int -> Int -> CilMethod
parseUInt32Spec right parseErr left =
  CilMethod
    { cmName = "__parseUInt32",
      cmRet = SeObject,
      cmParams = [SeObject],
      cmLocals = [SeString, SeInt32, SeInt32, SeInt64, SeInt32, SeObject],
      cmBody =
        [ Ldarg 0,
          Castclass strRef,
          Stloc 0,
          Ldloc 0,
          Callvirt getLengthRef,
          Stloc 1,
          Ldloc 1,
          Brfalse failL,
          LdcI4 0,
          Stloc 2,
          LdcI4 0,
          ConvI8,
          Stloc 3,
          Label loop,
          Ldloc 2,
          Ldloc 1,
          Bge ok,
          Ldloc 0,
          Ldloc 2,
          Callvirt getCharsRef,
          Stloc 4,
          Ldloc 4,
          LdcI4 48,
          Blt failL,
          Ldloc 4,
          LdcI4 57,
          Bgt failL,
          Ldloc 3,
          LdcI4 10,
          ConvI8,
          Mul,
          Ldloc 4,
          LdcI4 48,
          Sub,
          ConvI8,
          Add,
          Stloc 3,
          Ldloc 3,
          LdcI8 4294967295,
          Bgt failL,
          Ldloc 2,
          LdcI4 1,
          Add,
          Stloc 2,
          Br loop,
          Label ok
        ]
          <> unaryCell right [Ldloc 3, ConvU4, Box int32Ref]
          <> [Ret, Label failL]
          <> leftErr parseErr left 5
    }
  where
    failL = LabelId "IL_parseu32_fail"
    loop = LabelId "IL_parseu32_loop"
    ok = LabelId "IL_parseu32_ok"

-- ── Entry: argv/stdin UTF-16 validation ───────────────────────────────────────

-- | @__entryArgEither@: validate one decoded input string and return
--   @Right s@ or @Left e@ where @e : (StringTooLong | UnpairedUtf16Surrogate)@.
--   Rejects strings past the UTF-16 length cap, then scans for unpaired
--   surrogates (a high @0xD800–0xDBFF@ must be followed by a low
--   @0xDC00–0xDFFF@, and a low must be preceded by a high). The error side is a
--   row, so it uses the 3-level 'leftRowErr' with the FNV row tags. @right@ =
--   ptRight, @stl@ = ptStringTooLong, @unp@ = ptUnpairedUtf16Surrogate,
--   @left@ = ptLeft. Locals: s, len, i, expectingLow, maskedChar, two object
--   scratch slots for the row-error build.
entryArgEitherSpec :: Int -> Int -> Int -> Int -> CilMethod
entryArgEitherSpec right stl unp left =
  CilMethod
    { cmName = "__entryArgEither",
      cmRet = SeObject,
      cmParams = [SeObject],
      cmLocals = [SeString, SeInt32, SeInt32, SeInt32, SeInt32, SeObject, SeObject],
      cmBody =
        [ Ldarg 0,
          Castclass strRef,
          Stloc 0,
          Ldloc 0,
          Callvirt getLengthRef,
          Stloc 1,
          Ldloc 1,
          LdcI4 134217728,
          Bgt toolong,
          LdcI4 0,
          Stloc 2,
          LdcI4 0,
          Stloc 3,
          Label scan,
          Ldloc 2,
          Ldloc 1,
          Bge scandone,
          Ldloc 0,
          Ldloc 2,
          Callvirt getCharsRef,
          LdcI4 64512,
          And,
          Stloc 4,
          Ldloc 3,
          Brtrue checklow,
          Ldloc 4,
          LdcI4 56320,
          Beq unpaired,
          Ldloc 4,
          LdcI4 55296,
          BneUn inc,
          LdcI4 1,
          Stloc 3,
          Br inc,
          Label checklow,
          Ldloc 4,
          LdcI4 56320,
          BneUn unpaired,
          LdcI4 0,
          Stloc 3,
          Br inc,
          Label inc,
          Ldloc 2,
          LdcI4 1,
          Add,
          Stloc 2,
          Br scan,
          Label scandone,
          Ldloc 3,
          Brtrue unpaired
        ]
          <> unaryCell right [Ldarg 0]
          <> [Ret, Label toolong]
          <> leftRowErr stl stringTooLongRowTag left 5 6
          <> [Label unpaired]
          <> leftRowErr unp unpairedSurrogateRowTag left 5 6
    }
  where
    toolong = LabelId "IL_entryarg_toolong"
    scan = LabelId "IL_entryarg_scan"
    scandone = LabelId "IL_entryarg_scandone"
    checklow = LabelId "IL_entryarg_checklow"
    inc = LabelId "IL_entryarg_inc"
    unpaired = LabelId "IL_entryarg_unpaired"

-- ── Entry glue: getArgs / stdinReadAll / main ─────────────────────────────────

-- | @__getArgs@ (@BuiltIn.internalGetArgs@): read @Environment.GetCommandLineArgs()@
--   (a @string[]@ whose slot 0 is the exe path), then walk from the end down to
--   (but excluding) index 0, validate each element through @__entryArgEither@,
--   and cons it onto a prelude @List String@. All-or-nothing: the first failing
--   element short-circuits with its @Left@. @right@ = ptRight, @nil@ = ptNil,
--   @cons@ = ptCons. Locals: argv (string[]), i (int32), list (object[]),
--   validated (object[]).
getArgsSpec :: Int -> Int -> Int -> CilMethod
getArgsSpec right nil cons =
  CilMethod
    { cmName = "__getArgs",
      cmRet = SeObject,
      cmParams = [],
      cmLocals = [SeSZArray SeString, SeInt32, SeSZArray SeObject, SeSZArray SeObject],
      cmBody =
        [Call (CilMemberRef (CilTypeRef 1 "System" "Environment") "GetCommandLineArgs" False (SeSZArray SeString) []), Stloc 0]
          <> nullaryCell nil
          <> [Stloc 2, Ldloc 0, Ldlen, ConvI4, Stloc 1, Label loopLbl, Ldloc 1, LdcI4 1, Ble doneLbl]
          <> [ Ldloc 1,
               LdcI4 1,
               Sub,
               Stloc 1,
               Ldloc 0,
               Ldloc 1,
               LdelemRef,
               CallNamed "__entryArgEither" 1,
               Castclass objectRef,
               Stloc 3
             ]
          <> [Ldloc 3, LdcI4 0, LdelemRef, UnboxAny int32Ref, LdcI4 right, BneUn leftLbl]
          <> cell cons [[Ldloc 3, LdcI4 1, LdelemRef], [Ldloc 2]]
          <> [Stloc 2, Br loopLbl, Label leftLbl, Ldloc 3, Ret, Label doneLbl]
          <> unaryCell right [Ldloc 2]
          <> [Ret]
    }
  where
    loopLbl = LabelId "IL_args_loop"
    leftLbl = LabelId "IL_args_left"
    doneLbl = LabelId "IL_args_done"

-- | @__stdinReadAll@ (@BuiltIn.internalStdinReadAllAsUtf16@): wrap
--   @Console.OpenStandardInput()@ in a @StreamReader@ with explicit UTF-8
--   @Encoding@, read to EOF, and route the string through @__entryArgEither@
--   for the same strict-UTF-16 validation as argv.
stdinReadAllSpec :: CilMethod
stdinReadAllSpec =
  CilMethod
    { cmName = "__stdinReadAll",
      cmRet = SeObject,
      cmParams = [],
      cmLocals = [],
      cmBody =
        [ Call (CilMemberRef consoleRef "OpenStandardInput" False (SeClass streamRef) []),
          Call (CilMemberRef encodingRef "get_UTF8" False (SeClass encodingRef) []),
          Newobj (CilMemberRef streamReaderRef ".ctor" True SeVoid [SeClass streamRef, SeClass encodingRef]),
          Callvirt (CilMemberRef streamReaderRef "ReadToEnd" True SeString []),
          CallNamed "__entryArgEither" 1,
          Ret
        ]
    }
  where
    consoleRef = CilTypeRef 2 "System" "Console"
    streamRef = CilTypeRef 1 "System.IO" "Stream"
    streamReaderRef = CilTypeRef 1 "System.IO" "StreamReader"

-- | @Main(string[])@: force stdout to UTF-8 (so supplementary code points are
--   not mangled by a host ANSI fallback), build the IO tree (@v_main@), walk it
--   with @v_runIO@, discard the resulting @Unit@, and return.
mainSpec :: CilMethod
mainSpec =
  CilMethod
    { cmName = "Main",
      cmRet = SeVoid,
      cmParams = [SeSZArray SeString],
      cmLocals = [],
      cmBody =
        [ Call (CilMemberRef encodingRef "get_UTF8" False (SeClass encodingRef) []),
          Call (CilMemberRef (CilTypeRef 2 "System" "Console") "set_OutputEncoding" False SeVoid [SeClass encodingRef]),
          CallNamed "v_main" 0,
          CallNamed "v_runIO" 1,
          Pop,
          Ret
        ]
    }
