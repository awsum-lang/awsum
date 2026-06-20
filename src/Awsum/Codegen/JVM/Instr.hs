-- | Unified JVM instruction IR — the single source of truth behind both JVM
--   renderers. One 'JvmMethod' value — a list of abstract 'JvmInstr' with
--   operands carried *symbolically* (class names, method refs, branch *labels*
--   never byte offsets) — feeds two total, decision-free renderers:
--
--     * 'renderMethod' here, which prints the Jasmin text.
--     * 'Awsum.Codegen.JVM.Assemble.assembleMethod', which resolves the
--       symbolic operands (constant-pool refs, label → byte offset, the
--       StackMapTable from the labels' frames) and emits bytes.
--
--   A method's body is lowered to a 'JvmMethod' once: within a method neither
--   renderer makes a Core-derived decision — which instruction, which slot,
--   which @max_stack@, which branch target — all of it is fixed when the
--   'JvmMethod' is built, so changing one projection's body is impossible
--   without changing the 'JvmMethod' (and thus the other). The text snapshot is
--   a faithful view of the shipped @.class@.
module Awsum.Codegen.JVM.Instr
  ( ClassRef (..),
    MethodRef (..),
    FieldRef (..),
    LabelId (..),
    VType (..),
    Frame (..),
    JvmInstr (..),
    JvmMethod (..),
    renderMethod,
    renderInstr,
    maxStackOf,
    maxLocalsOf,
    methodMaxStack,
    methodMaxLocals,
    showUInt32Spec,
    eqSpec,
    eqStringSpec,
    printSpec,
    concatSpec,
    splitOnFirstSpec,
    predUInt8Spec,
    succUInt8Spec,
    predInt32Spec,
    succInt32Spec,
    negInt32Spec,
    addInt32Spec,
    subInt32Spec,
    mulInt32Spec,
    addUInt8Spec,
    subUInt8Spec,
    mulUInt8Spec,
    addUInt32Spec,
    subUInt32Spec,
    mulUInt32Spec,
    parseUInt8Spec,
    parseUInt32Spec,
    parseInt32Spec,
    entryArgEitherSpec,
    getArgsSpec,
    stdinReadAllSpec,
    stdinDecodeStrictSpec,
    stdinReadAllBytesSpec,
    mainSpec,
    lengthCodePointsSpec,
    lengthUtf16CodeUnitsSpec,
    lengthUtf8BytesSpec,
    predUInt32Spec,
    succUInt32Spec,
  )
where

import Data.Map.Strict qualified as Map
import Relude

-- | A JVM class, by its internal binary name (e.g. @"java/lang/Integer"@).
newtype ClassRef = ClassRef Text
  deriving stock (Eq, Show)

-- | A JVM method reference: owner class, method name, descriptor
--   (e.g. @MethodRef "java/lang/Integer" "intValue" "()I"@).
data MethodRef = MethodRef Text Text Text
  deriving stock (Eq, Show)

-- | A JVM field reference: owner class, field name, descriptor (e.g.
--   @FieldRef "java/nio/charset/StandardCharsets" "UTF_8" "Ljava/nio/charset/Charset;"@).
data FieldRef = FieldRef Text Text Text
  deriving stock (Eq, Show)

-- | A symbolic branch label (the full Jasmin label text, e.g.
--   @"L_predu32_ok"@). The byte assembler resolves it to an offset; the
--   text renderer prints it verbatim.
newtype LabelId = LabelId Text
  deriving stock (Eq, Ord, Show)

-- | StackMapTable verification type for a local/stack slot.
--   @VLong@ is one /entry/ though it occupies two local slots.
data VType
  = VInteger -- ITEM_Integer (1)
  | VLong -- ITEM_Long (4)
  | VObject ClassRef -- ITEM_Object (7) + a CONSTANT_Class index, resolved in the assembler
  | VTop -- ITEM_Top (0) — a reserved-but-unwritten slot
  deriving stock (Eq, Show)

-- | The StackMapTable frame a 'Label' carries (binary-only — the text has no
--   SMT). An /absolute/ snapshot of the verifier state at the label: the full
--   local list (long = one entry) and the operand stack. The assembler diffs
--   it against the previous frame to choose same / append / chop / full —
--   so the frame /kind/ is a derived output, never an IR property.
data Frame = Frame
  { frLocals :: [VType],
    frStack :: [VType]
  }
  deriving stock (Eq, Show)

-- | One abstract JVM instruction. Operands are symbolic; branch targets are
--   labels, never byte offsets.
data JvmInstr
  = Aload Int
  | Astore Int
  | Iload Int
  | Istore Int
  | Lload Int
  | Lstore Int
  | PushInt Int
  | -- | Like 'PushInt' but mirrors @bcLoadInt32@ (no @iconst_m1@) — used for
    -- constructor / row tags so a tag of -1 or a large FNV hash matches the
    -- binary's @bcLoadInt32@ exactly.
    LoadInt32 Int32
  | CheckCast ClassRef
  | ANewArray ClassRef
  | -- | @new <class>@ — allocate an uninitialised object (paired with a later
    --   @invokespecial <init>@).
    New ClassRef
  | -- | @newarray byte@ — a fresh @byte[]@ (the only primitive array Awsum's
    --   codegen builds — the stdin read buffer).
    NewArrayByte
  | AconstNull
  | Dup
  | Dup2
  | Pop2
  | AAStore
  | Aaload
  | Baload
  | IAdd
  | ISub
  | IMul
  | INeg
  | IXor
  | IAnd
  | I2L
  | L2I
  | LConst0
  | LConst1
  | LAdd
  | LSub
  | LMul
  | LNeg
  | LShl
  | LCmp
  | InvokeVirtual MethodRef
  | InvokeStatic MethodRef
  | InvokeSpecial MethodRef
  | GetStatic FieldRef
  | PutStatic FieldRef
  | -- | @ldc "<text>"@ — load a @CONSTANT_String@ (only @main@'s @"UTF-8"@).
    LdcString Text
  | Pop
  | ArrayLength
  | Ifeq LabelId
  | Ifne LabelId
  | Iflt LabelId
  | Ifle LabelId
  | Ifgt LabelId
  | IfICmpEq LabelId
  | IfICmpNe LabelId
  | IfICmpLe LabelId
  | IfICmpLt LabelId
  | IfICmpGt LabelId
  | IfICmpGe LabelId
  | Goto LabelId
  | Iinc Int Int
  | -- | A branch target. The optional 'Frame' is its StackMapTable entry
    -- (binary-only); 'Nothing' for a label that is not a verifier frame.
    Label LabelId (Maybe Frame)
  | AReturn
  | -- | @return@ — void return (only @main@).
    Return
  deriving stock (Eq, Show)

-- | A method: name, descriptor, and body. The verifier limits @max_stack@ /
--   @max_locals@ are not stored — both projections derive them from 'jmBody'
--   ('methodMaxStack' / 'methodMaxLocals'), so the @.limit@ directives and the
--   classfile Code attribute cannot disagree and no figure is hand-maintained.
--   @jmPublic@ is @True@ only for the entry point @main@ (@public static@,
--   access flags @0x0009@); every other helper is package-private @static@
--   (@0x0008@).
data JvmMethod = JvmMethod
  { jmName :: Text,
    jmDesc :: Text,
    jmPublic :: Bool,
    jmBody :: [JvmInstr]
  }
  deriving stock (Eq, Show)

-- | Total, decision-free text projection of a method (Jasmin-like, the same
--   shape 'Awsum.Codegen.JVM' emitted by hand).
renderMethod :: JvmMethod -> Text
renderMethod m =
  unlines
    $ [ ".method " <> (if jmPublic m then "public static " else "static ") <> jmName m <> jmDesc m,
        "  .limit stack " <> show (methodMaxStack m),
        "  .limit locals " <> show (methodMaxLocals m)
      ]
    <> map renderInstr (jmBody m)
    <> [".end method"]

-- | Total, decision-free text projection of a single instruction. Labels
--   render at column 0; everything else is indented two spaces.
renderInstr :: JvmInstr -> Text
renderInstr = \case
  Aload n -> "  aload" <> slotSuffix n
  Astore n -> "  astore" <> slotSuffix n
  Iload n -> "  iload" <> slotSuffix n
  Istore n -> "  istore" <> slotSuffix n
  Lload n -> "  lload" <> slotSuffix n
  Lstore n -> "  lstore" <> slotSuffix n
  PushInt n -> renderPushInt n
  LoadInt32 n -> renderLoadInt32 n
  CheckCast (ClassRef c) -> "  checkcast " <> c
  ANewArray (ClassRef c) -> "  anewarray " <> c
  New (ClassRef c) -> "  new " <> c
  NewArrayByte -> "  newarray byte"
  AconstNull -> "  aconst_null"
  Return -> "  return"
  Dup -> "  dup"
  Dup2 -> "  dup2"
  Pop2 -> "  pop2"
  AAStore -> "  aastore"
  Aaload -> "  aaload"
  Baload -> "  baload"
  IAdd -> "  iadd"
  ISub -> "  isub"
  IMul -> "  imul"
  INeg -> "  ineg"
  IXor -> "  ixor"
  IAnd -> "  iand"
  I2L -> "  i2l"
  L2I -> "  l2i"
  LConst0 -> "  lconst_0"
  LConst1 -> "  lconst_1"
  LAdd -> "  ladd"
  LSub -> "  lsub"
  LMul -> "  lmul"
  LNeg -> "  lneg"
  LShl -> "  lshl"
  LCmp -> "  lcmp"
  InvokeVirtual mref -> "  invokevirtual " <> renderMethodRef mref
  InvokeStatic mref -> "  invokestatic " <> renderMethodRef mref
  InvokeSpecial mref -> "  invokespecial " <> renderMethodRef mref
  PutStatic (FieldRef owner name desc) -> "  putstatic " <> owner <> "/" <> name <> " " <> desc
  LdcString s -> "  ldc \"" <> s <> "\""
  Pop -> "  pop"
  GetStatic (FieldRef owner name desc) -> "  getstatic " <> owner <> "/" <> name <> " " <> desc
  ArrayLength -> "  arraylength"
  Ifeq (LabelId l) -> "  ifeq " <> l
  Ifne (LabelId l) -> "  ifne " <> l
  Iflt (LabelId l) -> "  iflt " <> l
  Ifle (LabelId l) -> "  ifle " <> l
  Ifgt (LabelId l) -> "  ifgt " <> l
  IfICmpEq (LabelId l) -> "  if_icmpeq " <> l
  IfICmpNe (LabelId l) -> "  if_icmpne " <> l
  IfICmpLe (LabelId l) -> "  if_icmple " <> l
  IfICmpLt (LabelId l) -> "  if_icmplt " <> l
  IfICmpGt (LabelId l) -> "  if_icmpgt " <> l
  IfICmpGe (LabelId l) -> "  if_icmpge " <> l
  Goto (LabelId l) -> "  goto " <> l
  Iinc slot delta -> "  iinc " <> show slot <> " " <> show delta
  Label (LabelId l) _ -> l <> ":"
  AReturn -> "  areturn"

renderMethodRef :: MethodRef -> Text
renderMethodRef (MethodRef owner name desc) = owner <> "/" <> name <> desc

-- | Tightest int-push mnemonic: @iconst_<n>@ for @[-1,5]@, @bipush@ / @sipush@
--   for one/two signed bytes, else @ldc@. The byte renderer encodes the same
--   choice, so text and bytes agree on the mnemonic.
renderPushInt :: Int -> Text
renderPushInt n
  | n >= -1 && n <= 5 = "  iconst_" <> if n == -1 then "m1" else show n
  | n >= -128 && n <= 127 = "  bipush " <> show n
  | n >= -32768 && n <= 32767 = "  sipush " <> show n
  | otherwise = "  ldc " <> show n

-- | Mirror of @bcLoadInt32@ (the tag-push path): @iconst_0@..@iconst_5@ /
--   @bipush@ / @sipush@ / @ldc@ — but NO @iconst_m1@, so a tag of -1 renders
--   as @bipush -1@ exactly as the binary does.
renderLoadInt32 :: Int32 -> Text
renderLoadInt32 n
  | n >= 0 && n <= 5 = "  iconst_" <> show n
  | n >= -128 && n <= 127 = "  bipush " <> show n
  | n >= -32768 && n <= 32767 = "  sipush " <> show n
  | otherwise = "  ldc " <> show n

-- | @aload_0@..@aload_3@ (and @i/astore_<n>@) have dedicated short opcodes;
--   @… n@ for @n > 3@. Mirrors 'Awsum.Codegen.JVM.aloadSuffix'.
slotSuffix :: Int -> Text
slotSuffix n
  | n <= 3 = "_" <> show n
  | otherwise = " " <> show n

-- ── Verifier limits, derived from the emitted instruction stream ─────────────

-- | @max_stack@ (JVM Spec §4.7.3): the deepest the operand stack gets, in
--   /slots/ (a @long@ occupies two). Abstract interpretation over the body —
--   sum each instruction's fixed stack delta, remember the depth at every
--   branch target so a label reached by a jump resumes at the right height, and
--   treat code after an unconditional @goto@ / @areturn@ / @return@ as dead
--   until the next label. Because it reads the instructions the method actually
--   emits, it cannot under-declare the way a second traversal over the source
--   IR could: every @aconst_null@ a drop-drain pushes over parked continue args,
--   every loop-tail drain, is already in the stream and counted here.
maxStackOf :: [JvmInstr] -> Int
maxStackOf = go (Just 0) 0 mempty
  where
    cv :: Maybe Int -> Int
    cv = fromMaybe 0
    go :: Maybe Int -> Int -> Map LabelId Int -> [JvmInstr] -> Int
    go _ mx _ [] = mx
    go cur mx ed (i : is) = case i of
      Label l _ ->
        let d = fromMaybe (cv cur) (Map.lookup l ed)
         in go (Just d) (max mx d) ed is
      AReturn -> go Nothing mx ed is
      Return -> go Nothing mx ed is
      _ -> case branchTarget i of
        Just (l, conditional) ->
          let c' = cv cur + delta i
              ed' = if Map.member l ed then ed else Map.insert l c' ed
           in go (if conditional then Just c' else Nothing) (max mx (cv cur)) ed' is
        Nothing ->
          let c' = cv cur + delta i in go (Just c') (max mx c') ed is
    -- @Just (target, isConditional)@ for the branch instructions; an
    -- unconditional @goto@ is @False@ (control does not fall through).
    branchTarget :: JvmInstr -> Maybe (LabelId, Bool)
    branchTarget = \case
      Goto l -> Just (l, False)
      Ifeq l -> Just (l, True)
      Ifne l -> Just (l, True)
      Iflt l -> Just (l, True)
      Ifle l -> Just (l, True)
      Ifgt l -> Just (l, True)
      IfICmpEq l -> Just (l, True)
      IfICmpNe l -> Just (l, True)
      IfICmpLe l -> Just (l, True)
      IfICmpLt l -> Just (l, True)
      IfICmpGt l -> Just (l, True)
      IfICmpGe l -> Just (l, True)
      _ -> Nothing
    delta :: JvmInstr -> Int
    delta = \case
      Aload _ -> 1
      Iload _ -> 1
      Lload _ -> 2
      Astore _ -> -1
      Istore _ -> -1
      Lstore _ -> -2
      PushInt _ -> 1
      LoadInt32 _ -> 1
      AconstNull -> 1
      LdcString _ -> 1
      LConst0 -> 2
      LConst1 -> 2
      CheckCast _ -> 0
      ANewArray _ -> 0 -- pops count, pushes the array ref
      New _ -> 1
      NewArrayByte -> 0 -- pops count, pushes the array ref
      Dup -> 1
      Dup2 -> 2
      Pop -> -1
      Pop2 -> -2
      AAStore -> -3
      Aaload -> -1
      Baload -> -1
      IAdd -> -1
      ISub -> -1
      IMul -> -1
      INeg -> 0
      IXor -> -1
      IAnd -> -1
      I2L -> 1 -- int (1) → long (2)
      L2I -> -1 -- long (2) → int (1)
      LAdd -> -2
      LSub -> -2
      LMul -> -2
      LNeg -> 0
      LShl -> -1 -- long (2) + int (1) → long (2)
      LCmp -> -3 -- long (2) + long (2) → int (1)
      ArrayLength -> 0
      Iinc _ _ -> 0
      InvokeVirtual mr -> callDelta True mr
      InvokeSpecial mr -> callDelta True mr
      InvokeStatic mr -> callDelta False mr
      GetStatic (FieldRef _ _ d) -> fieldSlots d
      PutStatic (FieldRef _ _ d) -> negate (fieldSlots d)
      Ifeq _ -> -1
      Ifne _ -> -1
      Iflt _ -> -1
      Ifle _ -> -1
      Ifgt _ -> -1
      IfICmpEq _ -> -2
      IfICmpNe _ -> -2
      IfICmpLe _ -> -2
      IfICmpLt _ -> -2
      IfICmpGt _ -> -2
      IfICmpGe _ -> -2
      Goto _ -> 0
      -- Handled in 'go' before 'delta' is reached; listed for totality.
      Label _ _ -> 0
      AReturn -> -1
      Return -> 0
    callDelta :: Bool -> MethodRef -> Int
    callDelta isInstance (MethodRef _ _ d) =
      descRetSlots d - descArgSlots d - (if isInstance then 1 else 0)

-- | Slot width of a single field descriptor (@J@/@D@ are two, everything
--   else — object refs, arrays, @int@-family — is one).
fieldSlots :: Text -> Int
fieldSlots d = case toString d of
  'J' : _ -> 2
  'D' : _ -> 2
  _ -> 1

-- | Total slot width of a method descriptor's parameters.
descArgSlots :: Text -> Int
descArgSlots d = sumSlots (takeWhile (/= ')') (drop 1 (dropWhile (/= '(') (toString d))))

-- | Slot width of a method descriptor's return type (@V@ is zero).
descRetSlots :: Text -> Int
descRetSlots d = case drop 1 (dropWhile (/= ')') (toString d)) of
  'V' : _ -> 0
  'J' : _ -> 2
  'D' : _ -> 2
  _ -> 1

sumSlots :: String -> Int
sumSlots [] = 0
sumSlots s = let (w, r) = oneType s in w + sumSlots r

-- | One field descriptor at the head: its slot width and the rest. An array
--   (@[…@) is one ref slot regardless of its element type.
oneType :: String -> (Int, String)
oneType = \case
  '[' : r -> let (_, r') = oneType r in (1, r')
  'L' : r -> (1, drop 1 (dropWhile (/= ';') r))
  'J' : r -> (2, r)
  'D' : r -> (2, r)
  _ : r -> (1, r)
  [] -> (0, [])

-- | @max_locals@ (JVM Spec §4.7.3): the number of local slots the method
--   reserves, read off the emitted stream as the max of two demands — one past
--   the highest slot any instruction loads or stores (slot width counted: a
--   @long@ at slot @n@ reaches @n + 2@), and the breadth of every StackMapTable
--   frame. A frame describes locals @0..k@ and may name a slot that no
--   load/store instruction reaches — a reserved 'VTop', or a 'VLong' whose
--   reads sit in another method — so @max_locals@ must cover it too, or the
--   verifier rejects the frame's locals array as @bad type array size@. The
--   caller floors the result at the parameter count — arguments occupy slots
--   @0..nParams-1@ on entry whether or not the body reads them back.
maxLocalsOf :: [JvmInstr] -> Int
maxLocalsOf = foldl' (\acc i -> max acc (slotsOf i)) 0
  where
    slotsOf :: JvmInstr -> Int
    slotsOf = \case
      Aload n -> n + 1
      Astore n -> n + 1
      Iload n -> n + 1
      Istore n -> n + 1
      Iinc n _ -> n + 1
      Lload n -> n + 2
      Lstore n -> n + 2
      Label _ (Just (Frame locals _)) -> foldl' (\a vt -> a + vtypeSlots vt) 0 locals
      _ -> 0
    vtypeSlots :: VType -> Int
    vtypeSlots VLong = 2
    vtypeSlots _ = 1

-- | The @max_stack@ a method declares: the peak its own body reaches. Both
--   projections ('renderMethod', 'Awsum.Codegen.JVM.Assemble.assembleMethod')
--   derive it from 'jmBody' here, so the @.limit@ directive and the classfile
--   Code attribute cannot disagree, and no hand-written figure can drift from
--   the instructions — every method, user-lowered or hand-written helper,
--   shares the one derivation.
methodMaxStack :: JvmMethod -> Int
methodMaxStack = maxStackOf . jmBody

-- | The @max_locals@ a method declares: the slots its body touches
--   ('maxLocalsOf'), floored at the parameter count — the arguments occupy
--   slots @0..nParams-1@ on entry whether or not the body reads them. All
--   parameters here are one slot (no @long@/@double@ parameter in any emitted
--   or hand-written method), so the descriptor's parameter width is the floor.
methodMaxLocals :: JvmMethod -> Int
methodMaxLocals m = max (descArgSlots (jmDesc m)) (maxLocalsOf (jmBody m))

-- ── Shared operand/fragment vocabulary ──────────────────────────────────────

objectToObjectDesc :: Text
objectToObjectDesc = "(Ljava/lang/Object;)Ljava/lang/Object;"

integerClass :: ClassRef
integerClass = ClassRef "java/lang/Integer"

objectClass :: ClassRef
objectClass = ClassRef "java/lang/Object"

integerIntValue :: MethodRef
integerIntValue = MethodRef "java/lang/Integer" "intValue" "()I"

integerValueOf :: MethodRef
integerValueOf = MethodRef "java/lang/Integer" "valueOf" "(I)Ljava/lang/Integer;"

-- | Push tag @n@ then box it as @java.lang.Integer@. (Was @boxedTagLines@.)
boxedTag :: Int -> [JvmInstr]
boxedTag n = [PushInt n, InvokeStatic integerValueOf]

-- | Build @Object[1] = [Integer(tag)]@ (a nullary @CCon@) on the stack.
--   (Was @makeNullaryCellLines@.)
makeNullaryCell :: Int -> [JvmInstr]
makeNullaryCell tag =
  [PushInt 1, ANewArray objectClass, Dup, PushInt 0] <> boxedTag tag <> [AAStore]

-- | Build @Object[2] = [Integer(tag), <loadInstr>]@ (a one-field @CCon@) on
--   the stack. (Was @makeUnaryCellFromLocalLines@.)
makeUnaryCellFromLocal :: Int -> JvmInstr -> [JvmInstr]
makeUnaryCellFromLocal tag loadInstr =
  [PushInt 2, ANewArray objectClass, Dup, PushInt 0]
    <> boxedTag tag
    <> [AAStore, Dup, PushInt 1, loadInstr, AAStore]

-- ── Helper method specs ─────────────────────────────────────────────────────

-- | @__showUInt32@: unbox the 'Integer' arg, format unsigned. Branchless.
showUInt32Spec :: JvmMethod
showUInt32Spec =
  JvmMethod
    { jmName = "__showUInt32",
      jmPublic = False,
      jmDesc = objectToObjectDesc,
      jmBody =
        [ Aload 0,
          CheckCast integerClass,
          InvokeVirtual integerIntValue,
          InvokeStatic (MethodRef "java/lang/Integer" "toUnsignedString" "(I)Ljava/lang/String;"),
          AReturn
        ]
    }

-- | @__eqInt32@ / @__eqUInt8@ / @__eqUInt32@ — equality on boxed @Integer@s
--   (all three are the same body; Int32 and both UInt are boxed @Integer@).
--   Unbox both args, @if_icmpne@ to the not-equal label, return @True@ /
--   @False@ as a nullary @CCon@. The not-equal label's frame is a
--   @same_frame@ (locals unchanged @[Object, Object]@, stack empty) — the
--   diff-classifier derives that from the absolute 'Frame'. @labelBase@ keeps
--   the per-method label name (@L_eq_i32@ …) so the text matches; the tags
--   (@True@/@False@) come from 'Awsum.Core.PreludeTags'.
eqSpec :: Text -> Text -> (Int, Int) -> JvmMethod
eqSpec name labelBase (trueTag, falseTag) =
  let ne = LabelId (labelBase <> "_ne")
   in JvmMethod
        { jmName = name,
          jmPublic = False,
          jmDesc = "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
          jmBody =
            [ Aload 0,
              CheckCast integerClass,
              InvokeVirtual integerIntValue,
              Aload 1,
              CheckCast integerClass,
              InvokeVirtual integerIntValue,
              IfICmpNe ne
            ]
              <> makeNullaryCell trueTag
              <> [AReturn, Label ne (Just (Frame [VObject objectClass, VObject objectClass] []))]
              <> makeNullaryCell falseTag
              <> [AReturn]
        }

-- | @__eqString@ — same True/False cell shape as 'eqSpec', but the two
--   operands are compared with @String.equals@ (an object comparison) rather
--   than unboxed and compared as @int@. The miss label is a @same_frame@ with
--   the two @Object@ params still in locals.
eqStringSpec :: (Int, Int) -> JvmMethod
eqStringSpec (trueTag, falseTag) =
  let ne = LabelId "L_eq_str_ne"
      strCls = ClassRef "java/lang/String"
   in JvmMethod
        { jmName = "__eqString",
          jmPublic = False,
          jmDesc = "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
          jmBody =
            [ Aload 0,
              CheckCast strCls,
              Aload 1,
              CheckCast strCls,
              InvokeVirtual (MethodRef "java/lang/String" "equals" "(Ljava/lang/Object;)Z"),
              Ifeq ne
            ]
              <> makeNullaryCell trueTag
              <> [AReturn, Label ne (Just (Frame [VObject objectClass, VObject objectClass] []))]
              <> makeNullaryCell falseTag
              <> [AReturn]
        }

-- | Shared shape of the six @pred@/@succ@ bound helpers (Int32 / UInt8 /
--   UInt32): unbox to slot 1, compare against the boundary, on hit return
--   @Left err@, else return @Right (v ± 1)@. The lower-bound-0 case checks
--   @v == 0@ with a bare 'Ifne' (empty @boundaryCheck@); every other case
--   pushes the boundary (@sipush 255@, @ldc ±2147483648@) and uses
--   'IfICmpNe'. The tags (@err@/@Left@/@Right@) come from
--   'Awsum.Core.PreludeTags', passed in so this module stays prelude-free.
predSuccSpec ::
  -- | method name, e.g. @"__predUInt32"@
  Text ->
  -- | ok-path label, e.g. @"L_predu32_ok"@
  Text ->
  -- | instrs between @iload_1@ and the branch (@[]@ for pred, @[PushInt -1]@ for succ-u32)
  [JvmInstr] ->
  -- | the branch to the ok path (e.g. @Ifne@ / @IfICmpNe@)
  (LabelId -> JvmInstr) ->
  -- | error tag (Underflow / Overflow), Left tag, Right tag
  (Int, Int, Int) ->
  -- | ok-path arithmetic after @iload_1@: @[PushInt 1, ISub]@ (pred),
  --   @[PushInt 1, IAdd]@ (succ), @[INeg]@ (neg)
  [JvmInstr] ->
  JvmMethod
predSuccSpec name okLabelText boundaryCheck branch (errTag, leftTag, rightTag) okArith =
  let ok = LabelId okLabelText
   in JvmMethod
        { jmName = name,
          jmPublic = False,
          jmDesc = objectToObjectDesc,
          jmBody =
            [Aload 0, CheckCast integerClass, InvokeVirtual integerIntValue, Istore 1, Iload 1]
              <> boundaryCheck
              <> [branch ok]
              <> makeNullaryCell errTag
              <> [Astore 2]
              <> makeUnaryCellFromLocal leftTag (Aload 2)
              <> [AReturn, Label ok (Just (Frame [VObject objectClass, VInteger] []))]
              <> [PushInt 2, ANewArray objectClass, Dup, PushInt 0]
              <> boxedTag rightTag
              <> [AAStore, Dup, PushInt 1, Iload 1]
              <> okArith
              <> [InvokeStatic integerValueOf, AAStore, AReturn]
        }

-- | @Left err@ cell for the UInt8 helpers (single error type, /no/ row
--   wrap): @[err]@ inner, saved to slot 2, wrapped in @Left@.
uint8LeftErr :: Int -> Int -> [JvmInstr]
uint8LeftErr errTag leftTag =
  makeNullaryCell errTag <> [Astore 2] <> makeUnaryCellFromLocal leftTag (Aload 2) <> [AReturn]

-- | @Right (Integer v)@ cell, where @v@ is pushed by @valInstr@ (e.g. @Iload 2@).
uint8RightVal :: Int -> JvmInstr -> [JvmInstr]
uint8RightVal rightTag valInstr =
  [PushInt 2, ANewArray objectClass, Dup, PushInt 0]
    <> boxedTag rightTag
    <> [AAStore, Dup, PushInt 1, valInstr, InvokeStatic integerValueOf, AAStore, AReturn]

-- | @__addUInt8@ / @__mulUInt8@ — @a ⊕ b@ in @int@ (no wrap: both in 0..255),
--   range-checked @<= 255@ via @if_icmple@ to the ok label; over the bound is
--   @Left OverflowError@. Slot 2 = the int result / error scratch. One
--   @append [int]@ frame at the ok label.
uint8OverflowSpec :: Text -> Text -> JvmInstr -> (Int, Int, Int) -> JvmMethod
uint8OverflowSpec name okLabel arithOp (errTag, leftTag, rightTag) =
  let ok = LabelId okLabel
   in JvmMethod
        { jmName = name,
          jmPublic = False,
          jmDesc = "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
          jmBody =
            [Aload 0, CheckCast integerClass, InvokeVirtual integerIntValue, Aload 1, CheckCast integerClass, InvokeVirtual integerIntValue, arithOp, Istore 2, Iload 2, PushInt 255, IfICmpLe ok]
              <> uint8LeftErr errTag leftTag
              <> [Label ok (Just (Frame [VObject objectClass, VObject objectClass, VInteger] []))]
              <> uint8RightVal rightTag (Iload 2)
        }

-- | @__addUInt8@: @sum > 255@ → @Left OverflowError@, else @Right sum@.
addUInt8Spec :: (Int, Int, Int) -> JvmMethod
addUInt8Spec = uint8OverflowSpec "__addUInt8" "L_addu8_ok" IAdd

-- | @__mulUInt8@: @product > 255@ → @Left OverflowError@, else @Right product@.
mulUInt8Spec :: (Int, Int, Int) -> JvmMethod
mulUInt8Spec = uint8OverflowSpec "__mulUInt8" "L_mulu8_ok" IMul

-- | @__subUInt8@: @diff < 0@ → @Left UnderflowError@, else @Right diff@. Ok is
--   the fall-through; the @iflt@ branch leads to the error label.
subUInt8Spec :: (Int, Int, Int) -> JvmMethod
subUInt8Spec (errTag, leftTag, rightTag) =
  let under = LabelId "L_subu8_under"
   in JvmMethod
        { jmName = "__subUInt8",
          jmPublic = False,
          jmDesc = "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
          jmBody =
            [Aload 0, CheckCast integerClass, InvokeVirtual integerIntValue, Aload 1, CheckCast integerClass, InvokeVirtual integerIntValue, ISub, Istore 2, Iload 2, Iflt under]
              <> uint8RightVal rightTag (Iload 2)
              <> [Label under (Just (Frame [VObject objectClass, VObject objectClass, VInteger] []))]
              <> uint8LeftErr errTag leftTag
        }

-- | Push @4294967295L@ (the UInt32 max) without a @CONSTANT_Long@:
--   @(1L << 32) - 1@. Mirrors @bcU32MaxAsLong@.
u32MaxAsLong :: [JvmInstr]
u32MaxAsLong = [LConst1, PushInt 32, LShl, LConst1, LSub]

integerToUnsignedLong :: MethodRef
integerToUnsignedLong = MethodRef "java/lang/Integer" "toUnsignedLong" "(I)J"

longCompareUnsigned :: MethodRef
longCompareUnsigned = MethodRef "java/lang/Long" "compareUnsigned" "(JJ)I"

integerCompareUnsigned :: MethodRef
integerCompareUnsigned = MethodRef "java/lang/Integer" "compareUnsigned" "(II)I"

-- | @Left err@ cell building from scratch slot @s@ (single error type, no row).
left1Err :: Int -> Int -> Int -> [JvmInstr]
left1Err errTag leftTag s =
  [PushInt 1, ANewArray objectClass, Dup, PushInt 0]
    <> boxedTag errTag
    <> [AAStore, Astore s, PushInt 2, ANewArray objectClass, Dup, PushInt 0]
    <> boxedTag leftTag
    <> [AAStore, Dup, PushInt 1, Aload s, AAStore, AReturn]

-- | @__addUInt32@ / @__mulUInt32@ — widen both args via @toUnsignedLong@,
--   @ladd@/@lmul@, store the @long@ in slot 2, compare unsigned against the
--   u32 max; over ⇒ @Left OverflowError@ (single type, no row), else
--   @Right (l2i result)@. The error label carries @append [long]@.
--   @scratch@ is the boxed-cell slot (4 for add — the long occupies 2/3; 2
--   for mul — it overwrites the dead long).
uint32LongSpec :: Text -> Text -> JvmInstr -> Int -> (Int, Int, Int) -> JvmMethod
uint32LongSpec name overLabel longArith scratch (errTag, leftTag, rightTag) =
  let over = LabelId overLabel
   in JvmMethod
        { jmName = name,
          jmPublic = False,
          jmDesc = "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
          jmBody =
            [Aload 0, CheckCast integerClass, InvokeVirtual integerIntValue, InvokeStatic integerToUnsignedLong, Aload 1, CheckCast integerClass, InvokeVirtual integerIntValue, InvokeStatic integerToUnsignedLong, longArith, Lstore 2, Lload 2]
              <> u32MaxAsLong
              <> [InvokeStatic longCompareUnsigned, Ifgt over]
              <> [Lload 2, L2I, InvokeStatic integerValueOf, Astore scratch, PushInt 2, ANewArray objectClass, Dup, PushInt 0]
              <> boxedTag rightTag
              <> [AAStore, Dup, PushInt 1, Aload scratch, AAStore, AReturn]
              <> [Label over (Just (Frame [VObject objectClass, VObject objectClass, VLong] []))]
              <> left1Err errTag leftTag scratch
        }

-- | @__addUInt32@: @sum > u32max@ → @Left OverflowError@, else @Right sum@.
addUInt32Spec :: (Int, Int, Int) -> JvmMethod
addUInt32Spec = uint32LongSpec "__addUInt32" "L_addu32_over" LAdd 4

-- | @__mulUInt32@: @product > u32max@ → @Left OverflowError@, else @Right product@.
mulUInt32Spec :: (Int, Int, Int) -> JvmMethod
mulUInt32Spec = uint32LongSpec "__mulUInt32" "L_mulu32_over" LMul 2

-- | @__subUInt32@: unsigned @a < b@ (via @Integer.compareUnsigned@) →
--   @Left UnderflowError@, else @Right (a - b)@ (int @isub@ is bit-correct for
--   u32 when @a >= b@). Slots 2/3 = int @a@/@b@, slot 4 = scratch; the
--   error label carries @append [int, int]@.
subUInt32Spec :: (Int, Int, Int) -> JvmMethod
subUInt32Spec (errTag, leftTag, rightTag) =
  let under = LabelId "L_subu32_under"
   in JvmMethod
        { jmName = "__subUInt32",
          jmPublic = False,
          jmDesc = "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
          jmBody =
            [Aload 0, CheckCast integerClass, InvokeVirtual integerIntValue, Istore 2, Aload 1, CheckCast integerClass, InvokeVirtual integerIntValue, Istore 3, Iload 2, Iload 3, InvokeStatic integerCompareUnsigned, Iflt under]
              <> [Iload 2, Iload 3, ISub, InvokeStatic integerValueOf, Astore 4, PushInt 2, ANewArray objectClass, Dup, PushInt 0]
              <> boxedTag rightTag
              <> [AAStore, Dup, PushInt 1, Aload 4, AAStore, AReturn]
              <> [Label under (Just (Frame [VObject objectClass, VObject objectClass, VInteger, VInteger] []))]
              <> left1Err errTag leftTag 4
        }

-- | @__parseUInt8@ — parse a decimal @String@ to @Either ParseError UInt8@.
--   A digit loop accumulating in @int@: empty / non-digit / @acc > 255@ all
--   jump to the fail label (@Left ParseError@, single type — no row). Three
--   frames: @L_loop@ (full_frame [Object, String, int, int, int] — append-4
--   from the entry's single Object exceeds the +3 append cap), @L_ok@
--   (same_frame), @L_fail@ (chop to [Object, String, int] — the common locals
--   of the empty-string and in-loop edges). The diff-classifier derives all
--   three. Slots: 1 = String, 2 = len, 3 = i, 4 = acc / error scratch, 5 = char.
parseUInt8Spec :: (Int, Int, Int) -> JvmMethod
parseUInt8Spec (parseErrTag, leftTag, rightTag) =
  let loop = LabelId "L_parseUInt8_loop"
      ok = LabelId "L_parseUInt8_ok"
      fl = LabelId "L_parseUInt8_fail"
      strCls = ClassRef "java/lang/String"
      lengthRef = MethodRef "java/lang/String" "length" "()I"
      charAtRef = MethodRef "java/lang/String" "charAt" "(I)C"
      loopFrame = Frame [VObject objectClass, VObject strCls, VInteger, VInteger, VInteger] []
   in JvmMethod
        { jmName = "__parseUInt8",
          jmPublic = False,
          jmDesc = "(Ljava/lang/Object;)Ljava/lang/Object;",
          jmBody =
            [ Aload 0,
              CheckCast strCls,
              Astore 1,
              Aload 1,
              InvokeVirtual lengthRef,
              Istore 2,
              Iload 2,
              Ifeq fl,
              PushInt 0,
              Istore 3,
              PushInt 0,
              Istore 4,
              Label loop (Just loopFrame),
              Iload 3,
              Iload 2,
              IfICmpGe ok,
              Aload 1,
              Iload 3,
              InvokeVirtual charAtRef,
              Istore 5,
              Iload 5,
              PushInt 48,
              IfICmpLt fl,
              Iload 5,
              PushInt 57,
              IfICmpGt fl,
              Iload 4,
              PushInt 10,
              IMul,
              Iload 5,
              PushInt 48,
              ISub,
              IAdd,
              Istore 4,
              Iload 4,
              PushInt 255,
              IfICmpGt fl,
              Iinc 3 1,
              Goto loop,
              Label ok (Just loopFrame)
            ]
              <> [PushInt 2, ANewArray objectClass, Dup, PushInt 0]
              <> boxedTag rightTag
              <> [AAStore, Dup, PushInt 1, Iload 4, InvokeStatic integerValueOf, AAStore, AReturn]
              <> [Label fl (Just (Frame [VObject objectClass, VObject strCls, VInteger] []))]
              <> left1Err parseErrTag leftTag 4
        }

-- | @__parseUInt32@ — like 'parseUInt8Spec' but the accumulator is a @long@
--   (slots 4-5) so @acc*10 + digit@ can exceed u32 before the @> u32max@
--   check (unsigned via @lcmp@ against @(1L<<32)-1@; the running magnitude
--   stays below @Long.MAX@). Char is slot 6. The bound @(1L<<32)-1@ is built
--   with the shift form (no @CONSTANT_Long@). Frames: @L_loop@ full_frame
--   @[Object, String, int, int, long]@, @L_ok@ same_frame, @L_fail@ chop to
--   @[Object, String]@.
parseUInt32Spec :: (Int, Int, Int) -> JvmMethod
parseUInt32Spec (parseErrTag, leftTag, rightTag) =
  let loop = LabelId "L_parseUInt32_loop"
      ok = LabelId "L_parseUInt32_ok"
      fl = LabelId "L_parseUInt32_fail"
      strCls = ClassRef "java/lang/String"
      lengthRef = MethodRef "java/lang/String" "length" "()I"
      charAtRef = MethodRef "java/lang/String" "charAt" "(I)C"
      loopFrame = Frame [VObject objectClass, VObject strCls, VInteger, VInteger, VLong] []
   in JvmMethod
        { jmName = "__parseUInt32",
          jmPublic = False,
          jmDesc = "(Ljava/lang/Object;)Ljava/lang/Object;",
          jmBody =
            [ Aload 0,
              CheckCast strCls,
              Astore 1,
              Aload 1,
              InvokeVirtual lengthRef,
              Istore 2,
              Iload 2,
              Ifeq fl,
              PushInt 0,
              Istore 3,
              LConst0,
              Lstore 4,
              Label loop (Just loopFrame),
              Iload 3,
              Iload 2,
              IfICmpGe ok,
              Aload 1,
              Iload 3,
              InvokeVirtual charAtRef,
              Istore 6,
              Iload 6,
              PushInt 48,
              IfICmpLt fl,
              Iload 6,
              PushInt 57,
              IfICmpGt fl,
              Lload 4,
              PushInt 10,
              I2L,
              LMul,
              Iload 6,
              PushInt 48,
              ISub,
              I2L,
              LAdd,
              Lstore 4,
              Lload 4
            ]
              <> u32MaxAsLong
              <> [LCmp, Ifgt fl, Iinc 3 1, Goto loop, Label ok (Just loopFrame)]
              <> [PushInt 2, ANewArray objectClass, Dup, PushInt 0]
              <> boxedTag rightTag
              <> [AAStore, Dup, PushInt 1, Lload 4, L2I, InvokeStatic integerValueOf, AAStore, AReturn]
              <> [Label fl (Just (Frame [VObject objectClass, VObject strCls] []))]
              <> left1Err parseErrTag leftTag 4
        }

-- | @__parseInt32@ — the full signed parse, hardest of the family. A leading
--   @-@ sets a sign flag (slot 4) and starts the digit index at 1; the
--   accumulator is a @long@ (slots 5-6) so the in-loop bound is the magnitude
--   @2147483648L = 1L<<31@ (built @iconst_1; i2l; bipush 31; lshl@ — no
--   @CONSTANT_Long@). After the loop a negative negates the magnitude
--   (@lneg@, which makes @-2147483648@ representable); a positive is bounded
--   by @2147483647@ (INT32_MAX, an @ldc; i2l@ compare). Six StackMapTable
--   frames: @L_init_acc@ full_frame @[Object,String,int,int,int]@ (sign slots
--   present, accumulator not yet), @L_loop@ append @[long]@, @L_after_loop@ /
--   @L_pos_check@ / @L_build_right@ same_frame, @L_fail@ chop to
--   @[Object,String,int]@ — all derived by the assembler's frame classifier.
parseInt32Spec :: (Int, Int, Int) -> JvmMethod
parseInt32Spec (parseErrTag, leftTag, rightTag) =
  let initAcc = LabelId "L_parseInt32_init_acc"
      loop = LabelId "L_parseInt32_loop"
      afterLoop = LabelId "L_parseInt32_after_loop"
      posCheck = LabelId "L_parseInt32_pos_check"
      buildRight = LabelId "L_parseInt32_build_right"
      fl = LabelId "L_parseInt32_fail"
      strCls = ClassRef "java/lang/String"
      lengthRef = MethodRef "java/lang/String" "length" "()I"
      charAtRef = MethodRef "java/lang/String" "charAt" "(I)C"
      noAcc = Frame [VObject objectClass, VObject strCls, VInteger, VInteger, VInteger] []
      withAcc = Frame [VObject objectClass, VObject strCls, VInteger, VInteger, VInteger, VLong] []
   in JvmMethod
        { jmName = "__parseInt32",
          jmPublic = False,
          jmDesc = "(Ljava/lang/Object;)Ljava/lang/Object;",
          jmBody =
            [ Aload 0,
              CheckCast strCls,
              Astore 1,
              Aload 1,
              InvokeVirtual lengthRef,
              Istore 2,
              Iload 2,
              Ifeq fl,
              PushInt 0,
              Istore 3,
              PushInt 0,
              Istore 4,
              Aload 1,
              PushInt 0,
              InvokeVirtual charAtRef,
              PushInt 45,
              IfICmpNe initAcc,
              PushInt 1,
              Istore 4,
              PushInt 1,
              Istore 3,
              Iload 2,
              PushInt 1,
              IfICmpEq fl,
              Label initAcc (Just noAcc),
              LConst0,
              Lstore 5,
              Label loop (Just withAcc),
              Iload 3,
              Iload 2,
              IfICmpGe afterLoop,
              Aload 1,
              Iload 3,
              InvokeVirtual charAtRef,
              Istore 7,
              Iload 7,
              PushInt 48,
              IfICmpLt fl,
              Iload 7,
              PushInt 57,
              IfICmpGt fl,
              Lload 5,
              PushInt 10,
              I2L,
              LMul,
              Iload 7,
              PushInt 48,
              ISub,
              I2L,
              LAdd,
              Lstore 5,
              Lload 5,
              PushInt 1,
              I2L,
              PushInt 31,
              LShl,
              LCmp,
              Ifgt fl,
              Iinc 3 1,
              Goto loop,
              Label afterLoop (Just withAcc),
              Iload 4,
              Ifeq posCheck,
              Lload 5,
              LNeg,
              Lstore 5,
              Goto buildRight,
              Label posCheck (Just withAcc),
              Lload 5,
              LoadInt32 2147483647,
              I2L,
              LCmp,
              Ifgt fl,
              Label buildRight (Just withAcc),
              PushInt 2,
              ANewArray objectClass,
              Dup,
              PushInt 0
            ]
              <> boxedTag rightTag
              <> [AAStore, Dup, PushInt 1, Lload 5, L2I, InvokeStatic integerValueOf, AAStore, AReturn]
              <> [Label fl (Just (Frame [VObject objectClass, VObject strCls, VInteger] []))]
              <> left1Err parseErrTag leftTag 4
        }

-- | @__print@ — the low-level stdout primitive driven by the prelude's
--   @runIO@. @System.out.print(arg)@, then return a @Unit@ cell so the
--   surrounding @case … of Unit -> next@ in @runIO@ dispatches normally.
--   Honest limits: @stack 4@ / @locals 1@.
printSpec :: Int -> JvmMethod
printSpec unitTag =
  JvmMethod
    { jmName = "__print",
      jmPublic = False,
      jmDesc = "(Ljava/lang/Object;)Ljava/lang/Object;",
      jmBody =
        [ GetStatic (FieldRef "java/lang/System" "out" "Ljava/io/PrintStream;"),
          Aload 0,
          InvokeVirtual (MethodRef "java/io/PrintStream" "print" "(Ljava/lang/Object;)V"),
          PushInt 1,
          ANewArray objectClass,
          Dup,
          PushInt 0
        ]
          <> boxedTag unitTag
          <> [AAStore, AReturn]
    }

-- | @(++)@ / @__concat@ — UTF-16 cap check then @String.concat@. Sum the two
--   inputs' @length()@ (UTF-16 code units on the JVM) as @long@ and compare
--   against @maxStringLengthUtf16CodeUnits = 2^27@, built @lconst_1; bipush 27;
--   lshl@ (no @CONSTANT_Long@). Over ⇒ @Left StringTooLong@; otherwise
--   @Right (a.concat(b))@. One @same_frame@ at the too-long label (slot 2 — the
--   result — is set only inside each branch, so locals there are still the two
--   @Object@ params).
concatSpec :: (Int, Int, Int) -> JvmMethod
concatSpec (rightTag, leftTag, stlTag) =
  let tooLong = LabelId "L_concat_too_long"
      strCls = ClassRef "java/lang/String"
      unboxLen =
        [ CheckCast strCls,
          InvokeVirtual (MethodRef "java/lang/String" "length" "()I"),
          I2L
        ]
   in JvmMethod
        { jmName = "__concat",
          jmPublic = False,
          jmDesc = "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
          jmBody =
            [Aload 0]
              <> unboxLen
              <> [Aload 1]
              <> unboxLen
              <> [LAdd, LConst1, PushInt 27, LShl, LCmp, Ifgt tooLong]
              <> [ Aload 0,
                   CheckCast strCls,
                   Aload 1,
                   CheckCast strCls,
                   InvokeVirtual (MethodRef "java/lang/String" "concat" "(Ljava/lang/String;)Ljava/lang/String;"),
                   Astore 2,
                   PushInt 2,
                   ANewArray objectClass,
                   Dup,
                   PushInt 0
                 ]
              <> boxedTag rightTag
              <> [AAStore, Dup, PushInt 1, Aload 2, AAStore, AReturn]
              <> [Label tooLong (Just (Frame [VObject objectClass, VObject objectClass] []))]
              <> [PushInt 1, ANewArray objectClass, Dup, PushInt 0]
              <> boxedTag stlTag
              <> [AAStore, Astore 2, PushInt 2, ANewArray objectClass, Dup, PushInt 0]
              <> boxedTag leftTag
              <> [AAStore, Dup, PushInt 1, Aload 2, AAStore, AReturn]
        }

-- | @splitOnFirst@ / @__splitOnFirst@ — @str.indexOf(sep)@; on miss
--   (@-1@) return @Nothing@, else split with two @substring@ calls and wrap
--   the halves in @Just (Tuple2 prefix suffix)@. One @append [int]@ frame at
--   the found label (slot 2 holds the index, set before the branch). Slots are
--   reused honestly: slot 2 (index → suffix), slot 3 (prefix → tuple).
splitOnFirstSpec :: (Int, Int, Int) -> JvmMethod
splitOnFirstSpec (nothingTag, tuple2Tag, justTag) =
  let found = LabelId "L_split_found"
      strCls = ClassRef "java/lang/String"
      indexOfRef = MethodRef "java/lang/String" "indexOf" "(Ljava/lang/String;)I"
      substring2Ref = MethodRef "java/lang/String" "substring" "(II)Ljava/lang/String;"
      substring1Ref = MethodRef "java/lang/String" "substring" "(I)Ljava/lang/String;"
      lengthRef = MethodRef "java/lang/String" "length" "()I"
   in JvmMethod
        { jmName = "__splitOnFirst",
          jmPublic = False,
          jmDesc = "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
          jmBody =
            [ Aload 1,
              CheckCast strCls,
              Aload 0,
              CheckCast strCls,
              InvokeVirtual indexOfRef,
              Istore 2,
              Iload 2,
              PushInt (-1),
              IfICmpNe found
            ]
              <> [PushInt 1, ANewArray objectClass, Dup, PushInt 0]
              <> boxedTag nothingTag
              <> [AAStore, AReturn]
              <> [Label found (Just (Frame [VObject objectClass, VObject objectClass, VInteger] []))]
              <> [ Aload 1,
                   CheckCast strCls,
                   PushInt 0,
                   Iload 2,
                   InvokeVirtual substring2Ref,
                   Astore 3,
                   Aload 1,
                   CheckCast strCls,
                   Iload 2,
                   Aload 0,
                   CheckCast strCls,
                   InvokeVirtual lengthRef,
                   IAdd,
                   InvokeVirtual substring1Ref,
                   Astore 2,
                   PushInt 3,
                   ANewArray objectClass,
                   Dup,
                   PushInt 0
                 ]
              <> boxedTag tuple2Tag
              <> [AAStore, Dup, PushInt 1, Aload 3, AAStore, Dup, PushInt 2, Aload 2, AAStore, Astore 3, PushInt 2, ANewArray objectClass, Dup, PushInt 0]
              <> boxedTag justTag
              <> [AAStore, Dup, PushInt 1, Aload 3, AAStore, AReturn]
        }

-- | @__entryArgEither@ — strict-UTF-16 validation of one input string,
--   shared by @getArgs@ and @stdinReadAll@. Cap-check (@2^27@) then a single
--   surrogate-pairing scan (slot 4 = expecting-low flag, slot 5 = the masked
--   code unit). On success @Right input@; on overflow @Left StringTooLong@; on
--   a bad surrogate @Left UnpairedUtf16Surrogate@. The two error paths wrap the
--   nullary @CCon@ in a row cell (the @row@ tag is a large FNV-1a hash, so it
--   loads via 'LoadInt32', mirroring the binary's @bcLoadInt32@) then in @Left@.
--   Six frames: scan/scan_done/unpaired @[obj,str,int,int,int]@, check_low/inc
--   add the mask slot @[…,int]@, too_long @[obj,str,int]@ — the frame /kind/
--   (same/append/chop/full) at each is derived by the assembler's classifier
--   from the deltas, never set here.
entryArgEitherSpec :: (Int, Int, Int, Int, Int32, Int32) -> JvmMethod
entryArgEitherSpec (rightTag, leftTag, stlTag, usTag, stlRowTag, usRowTag) =
  let scan = LabelId "L_entry_scan"
      checkLow = LabelId "L_entry_check_low"
      inc = LabelId "L_entry_inc"
      scanDone = LabelId "L_entry_scan_done"
      tooLong = LabelId "L_entry_too_long"
      unpaired = LabelId "L_entry_unpaired"
      strCls = ClassRef "java/lang/String"
      lengthRef = MethodRef "java/lang/String" "length" "()I"
      charAtRef = MethodRef "java/lang/String" "charAt" "(I)C"
      -- absolute frames (long counts as one; here all locals are int/obj)
      f5 = Frame [VObject objectClass, VObject strCls, VInteger, VInteger, VInteger] []
      f6 = Frame [VObject objectClass, VObject strCls, VInteger, VInteger, VInteger, VInteger] []
      f3 = Frame [VObject objectClass, VObject strCls, VInteger] []
      -- inner CCon cell (slot 6) → row cell (slot 7) → Left cell; mirrors the
      -- binary's buildLeftBlock exactly.
      buildLeft innerTag rowTag =
        [PushInt 1, ANewArray objectClass, Dup, PushInt 0]
          <> boxedTag innerTag
          <> [AAStore, Astore 6, PushInt 2, ANewArray objectClass, Dup, PushInt 0, LoadInt32 rowTag, InvokeStatic integerValueOf, AAStore, Dup, PushInt 1, Aload 6, AAStore, Astore 7, PushInt 2, ANewArray objectClass, Dup, PushInt 0]
          <> boxedTag leftTag
          <> [AAStore, Dup, PushInt 1, Aload 7, AAStore, AReturn]
   in JvmMethod
        { jmName = "__entryArgEither",
          jmPublic = False,
          jmDesc = "(Ljava/lang/Object;)Ljava/lang/Object;",
          jmBody =
            [ Aload 0,
              CheckCast strCls,
              Astore 1,
              Aload 1,
              InvokeVirtual lengthRef,
              Istore 2,
              Iload 2,
              LoadInt32 134217728,
              IfICmpGt tooLong,
              PushInt 0,
              Istore 3,
              PushInt 0,
              Istore 4,
              Label scan (Just f5),
              Iload 3,
              Iload 2,
              IfICmpGe scanDone,
              Aload 1,
              Iload 3,
              InvokeVirtual charAtRef,
              LoadInt32 64512,
              IAnd,
              Istore 5,
              Iload 4,
              Ifne checkLow,
              Iload 5,
              LoadInt32 56320,
              IfICmpEq unpaired,
              Iload 5,
              LoadInt32 55296,
              IfICmpNe inc,
              PushInt 1,
              Istore 4,
              Goto inc,
              Label checkLow (Just f6),
              Iload 5,
              LoadInt32 56320,
              IfICmpNe unpaired,
              PushInt 0,
              Istore 4,
              Goto inc,
              Label inc (Just f6),
              Iinc 3 1,
              Goto scan,
              Label scanDone (Just f5),
              Iload 4,
              Ifne unpaired,
              PushInt 2,
              ANewArray objectClass,
              Dup,
              PushInt 0
            ]
              <> boxedTag rightTag
              <> [AAStore, Dup, PushInt 1, Aload 0, AAStore, AReturn, Label tooLong (Just f3)]
              <> buildLeft stlTag stlRowTag
              <> [Label unpaired (Just f5)]
              <> buildLeft usTag usRowTag
        }

-- | @__getArgs@ — reads the @AwsumMain.__argv@ @String[]@, walks it
--   right-to-left, routes each element through @__entryArgEither@, and
--   accumulates a prelude @List String@ (Cons cells, slot 2). First failing
--   element short-circuits with its @Left@. @__entryArgEither@ is declared to
--   return @Object@ but always yields the @Object[]@ of an Either cell, so the
--   result is narrowed with @checkcast [Ljava/lang/Object;@ before slot 3 is
--   @aaload@-ed (the verifier requires the cast). Three frames at loop / left /
--   done; @argv@ is typed @Object[]@ (a @String[]@ widens into it).
getArgsSpec :: (Int, Int, Int) -> JvmMethod
getArgsSpec (nilTag, consTag, rightTag) =
  let loop = LabelId "L_args_loop"
      left = LabelId "L_args_left"
      done = LabelId "L_args_done"
      argvField = FieldRef "AwsumMain" "__argv" "[Ljava/lang/String;"
      entryRef = MethodRef "AwsumMain" "__entryArgEither" "(Ljava/lang/Object;)Ljava/lang/Object;"
      objArr = ClassRef "[Ljava/lang/Object;"
      f3 = Frame [VObject objArr, VInteger, VObject objArr] []
      f4 = Frame [VObject objArr, VInteger, VObject objArr, VObject objArr] []
   in JvmMethod
        { jmName = "__getArgs",
          jmPublic = False,
          jmDesc = "()Ljava/lang/Object;",
          -- 5: the Cons build peaks at @aload_3; iconst_1; aaload@
          -- (arr, arr, idx, validated, 1).
          jmBody =
            [GetStatic argvField, Astore 0, PushInt 1, ANewArray objectClass, Dup, PushInt 0]
              <> boxedTag nilTag
              <> [ AAStore,
                   Astore 2,
                   Aload 0,
                   ArrayLength,
                   Istore 1,
                   Label loop (Just f3),
                   Iload 1,
                   Ifle done,
                   Iload 1,
                   PushInt 1,
                   ISub,
                   Istore 1,
                   Aload 0,
                   Iload 1,
                   Aaload,
                   InvokeStatic entryRef,
                   CheckCast objArr,
                   Astore 3,
                   Aload 3,
                   PushInt 0,
                   Aaload,
                   CheckCast integerClass,
                   InvokeVirtual integerIntValue,
                   PushInt rightTag,
                   IfICmpNe left,
                   PushInt 3,
                   ANewArray objectClass,
                   Dup,
                   PushInt 0
                 ]
              <> boxedTag consTag
              <> [AAStore, Dup, PushInt 1, Aload 3, PushInt 1, Aaload, AAStore, Dup, PushInt 2, Aload 2, AAStore, Astore 2, Goto loop, Label left (Just f4), Aload 3, AReturn, Label done (Just f3), PushInt 2, ANewArray objectClass, Dup, PushInt 0]
              <> boxedTag rightTag
              <> [AAStore, Dup, PushInt 1, Aload 2, AAStore, AReturn]
        }

-- | The @System.in@-to-EOF read loop shared by both stdin primitives:
--   accumulates bytes into a @ByteArrayOutputStream@ (8192-byte chunks) and
--   leaves the captured @byte[]@ on the stack. Slots 0 (the stream) and 2
--   (the per-read count) are consumed; the caller continues from slot 0
--   onward. Label names are parameterised so the two callers don't collide.
stdinReadLoop :: Text -> [JvmInstr]
stdinReadLoop prefix =
  let loop = LabelId (prefix <> "_loop")
      done = LabelId (prefix <> "_done")
      baos = ClassRef "java/io/ByteArrayOutputStream"
      byteArr = ClassRef "[B"
      f1 = Frame [VObject baos, VObject byteArr] []
      f2 = Frame [VObject baos, VObject byteArr, VInteger] []
   in [ New baos,
        Dup,
        InvokeSpecial (MethodRef "java/io/ByteArrayOutputStream" "<init>" "()V"),
        Astore 0,
        PushInt 8192,
        NewArrayByte,
        Astore 1,
        Label loop (Just f1),
        GetStatic (FieldRef "java/lang/System" "in" "Ljava/io/InputStream;"),
        Aload 1,
        PushInt 0,
        PushInt 8192,
        InvokeVirtual (MethodRef "java/io/InputStream" "read" "([BII)I"),
        Istore 2,
        Iload 2,
        Ifle done,
        Aload 0,
        Aload 1,
        PushInt 0,
        Iload 2,
        InvokeVirtual (MethodRef "java/io/ByteArrayOutputStream" "write" "([BII)V"),
        Goto loop,
        Label done (Just f2),
        Aload 0,
        InvokeVirtual (MethodRef "java/io/ByteArrayOutputStream" "toByteArray" "()[B")
      ]

-- | @__stdinReadAll@ — consume @System.in@ to EOF, then strict-UTF-8 decode
--   the bytes via @__stdinDecodeStrict@.
stdinReadAllSpec :: JvmMethod
stdinReadAllSpec =
  JvmMethod
    { jmName = "__stdinReadAll",
      jmPublic = False,
      jmDesc = "()Ljava/lang/Object;",
      jmBody =
        stdinReadLoop "L_stdin"
          <> [ InvokeStatic (MethodRef "AwsumMain" "__stdinDecodeStrict" "([B)Ljava/lang/Object;"),
               AReturn
             ]
    }

-- | @__stdinDecodeStrict(byte[])@ — strict UTF-8 decode (RFC 3629) via a
--   @CharsetDecoder@ in its default REPORT mode, using the exception-free
--   @decode(in, out, true)@ + @CoderResult.isError()@ API. On a malformed or
--   incomplete sequence: @Left InvalidUtf8@. On success: length-cap the
--   decoded @String@ (@Left StringTooLong@ over 2^27 UTF-16 code units) else
--   @Right s@. The @CharBuffer@ is sized to @bytes.length@ — always enough,
--   since UTF-8 never expands to more chars than bytes — so the decode never
--   reports overflow. Two frames at @too_long@ / @invalid@.
stdinDecodeStrictSpec :: (Int, Int, Int, Int, Int32, Int32) -> JvmMethod
stdinDecodeStrictSpec (rightTag, leftTag, stlTag, iuTag, stlRowTag, iuRowTag) =
  let tooLong = LabelId "L_stdec_too_long"
      invalid = LabelId "L_stdec_invalid"
      byteArr = ClassRef "[B"
      byteBuf = ClassRef "java/nio/ByteBuffer"
      decoder = ClassRef "java/nio/charset/CharsetDecoder"
      charBuf = ClassRef "java/nio/CharBuffer"
      strCls = ClassRef "java/lang/String"
      fInvalid = Frame [VObject byteArr, VObject byteBuf, VObject decoder, VObject charBuf] []
      fTooLong = Frame [VObject byteArr, VObject byteBuf, VObject decoder, VObject charBuf, VObject strCls] []
      -- inner CCon (slot 6) → row cell (slot 7) → Left cell; mirrors
      -- '__entryArgEither's buildLeft exactly.
      buildLeft innerTag rowTag =
        [PushInt 1, ANewArray objectClass, Dup, PushInt 0]
          <> boxedTag innerTag
          <> [AAStore, Astore 6, PushInt 2, ANewArray objectClass, Dup, PushInt 0, LoadInt32 rowTag, InvokeStatic integerValueOf, AAStore, Dup, PushInt 1, Aload 6, AAStore, Astore 7, PushInt 2, ANewArray objectClass, Dup, PushInt 0]
          <> boxedTag leftTag
          <> [AAStore, Dup, PushInt 1, Aload 7, AAStore, AReturn]
   in JvmMethod
        { jmName = "__stdinDecodeStrict",
          jmPublic = False,
          jmDesc = "([B)Ljava/lang/Object;",
          jmBody =
            [ Aload 0,
              InvokeStatic (MethodRef "java/nio/ByteBuffer" "wrap" "([B)Ljava/nio/ByteBuffer;"),
              Astore 1,
              GetStatic (FieldRef "java/nio/charset/StandardCharsets" "UTF_8" "Ljava/nio/charset/Charset;"),
              InvokeVirtual (MethodRef "java/nio/charset/Charset" "newDecoder" "()Ljava/nio/charset/CharsetDecoder;"),
              Astore 2,
              Aload 0,
              ArrayLength,
              InvokeStatic (MethodRef "java/nio/CharBuffer" "allocate" "(I)Ljava/nio/CharBuffer;"),
              Astore 3,
              Aload 2,
              Aload 1,
              Aload 3,
              PushInt 1,
              InvokeVirtual (MethodRef "java/nio/charset/CharsetDecoder" "decode" "(Ljava/nio/ByteBuffer;Ljava/nio/CharBuffer;Z)Ljava/nio/charset/CoderResult;"),
              InvokeVirtual (MethodRef "java/nio/charset/CoderResult" "isError" "()Z"),
              Ifne invalid,
              Aload 3,
              InvokeVirtual (MethodRef "java/nio/Buffer" "flip" "()Ljava/nio/Buffer;"),
              Pop,
              Aload 3,
              InvokeVirtual (MethodRef "java/nio/CharBuffer" "toString" "()Ljava/lang/String;"),
              Astore 4,
              Aload 4,
              InvokeVirtual (MethodRef "java/lang/String" "length" "()I"),
              LoadInt32 134217728,
              IfICmpGt tooLong,
              PushInt 2,
              ANewArray objectClass,
              Dup,
              PushInt 0
            ]
              <> boxedTag rightTag
              <> [AAStore, Dup, PushInt 1, Aload 4, AAStore, AReturn, Label tooLong (Just fTooLong)]
              <> buildLeft stlTag stlRowTag
              <> [Label invalid (Just fInvalid)]
              <> buildLeft iuTag iuRowTag
        }

-- | @__stdinReadAllBytes@ — consume @System.in@ to EOF, then build a prelude
--   @List UInt8@ (Cons cells, slot 1) right-to-left from the captured byte
--   array (slot 0), each byte boxed as @Integer.valueOf(b & 0xFF)@. No decode,
--   no error row. One frame at the build loop / done.
stdinReadAllBytesSpec :: (Int, Int) -> JvmMethod
stdinReadAllBytesSpec (nilTag, consTag) =
  let bloop = LabelId "L_stdinbytes_build_loop"
      bdone = LabelId "L_stdinbytes_build_done"
      byteArr = ClassRef "[B"
      objArr = ClassRef "[Ljava/lang/Object;"
      fBuild = Frame [VObject byteArr, VObject objArr, VInteger] []
   in JvmMethod
        { jmName = "__stdinReadAllBytes",
          jmPublic = False,
          jmDesc = "()Ljava/lang/Object;",
          jmBody =
            stdinReadLoop "L_stdinbytes_read"
              <> [ Astore 0,
                   PushInt 1,
                   ANewArray objectClass,
                   Dup,
                   PushInt 0
                 ]
              <> boxedTag nilTag
              <> [ AAStore,
                   Astore 1,
                   Aload 0,
                   ArrayLength,
                   Istore 2,
                   Label bloop (Just fBuild),
                   Iload 2,
                   Ifle bdone,
                   Iinc 2 (-1),
                   PushInt 3,
                   ANewArray objectClass,
                   Dup,
                   PushInt 0
                 ]
              <> boxedTag consTag
              <> [ AAStore,
                   Dup,
                   PushInt 1,
                   Aload 0,
                   Iload 2,
                   Baload,
                   PushInt 255,
                   IAnd,
                   InvokeStatic integerValueOf,
                   AAStore,
                   Dup,
                   PushInt 2,
                   Aload 1,
                   AAStore,
                   Astore 1,
                   Goto bloop,
                   Label bdone (Just fBuild),
                   Aload 1,
                   AReturn
                 ]
        }

-- | @main@ — the JVM entry point (the only @public static@ method). Redirects
--   @System.out@ to a UTF-8 @PrintStream@ (so supplementary code points survive
--   a non-UTF-8 host console), stashes @args@ into @AwsumMain.__argv@ for
--   @__getArgs@, then runs @v_main@'s IO tree through @runIO@ and discards the
--   result. No branches, so no StackMapTable. Takes the mangled @v_main@ /
--   @runIO@ names (the caller has the mangler; this module stays prelude-free).
--   Honest limits: @5@ / @1@.
mainSpec :: Text -> Text -> JvmMethod
mainSpec mangledMain mangledRunIO =
  JvmMethod
    { jmName = "main",
      jmDesc = "([Ljava/lang/String;)V",
      jmPublic = True,
      jmBody =
        [ New (ClassRef "java/io/PrintStream"),
          Dup,
          New (ClassRef "java/io/FileOutputStream"),
          Dup,
          GetStatic (FieldRef "java/io/FileDescriptor" "out" "Ljava/io/FileDescriptor;"),
          InvokeSpecial (MethodRef "java/io/FileOutputStream" "<init>" "(Ljava/io/FileDescriptor;)V"),
          PushInt 1,
          LdcString "UTF-8",
          InvokeSpecial (MethodRef "java/io/PrintStream" "<init>" "(Ljava/io/OutputStream;ZLjava/lang/String;)V"),
          InvokeStatic (MethodRef "java/lang/System" "setOut" "(Ljava/io/PrintStream;)V"),
          Aload 0,
          PutStatic (FieldRef "AwsumMain" "__argv" "[Ljava/lang/String;"),
          InvokeStatic (MethodRef "AwsumMain" mangledMain "()Ljava/lang/Object;"),
          InvokeStatic (MethodRef "AwsumMain" mangledRunIO "(Ljava/lang/Object;)Ljava/lang/Object;"),
          Pop,
          Return
        ]
    }

-- | @__lengthCodePoints@: @String.codePointCount(0, length)@, boxed.
lengthCodePointsSpec :: JvmMethod
lengthCodePointsSpec =
  JvmMethod
    { jmName = "__lengthCodePoints",
      jmPublic = False,
      jmDesc = "(Ljava/lang/Object;)Ljava/lang/Object;",
      jmBody =
        [ Aload 0,
          CheckCast (ClassRef "java/lang/String"),
          Astore 1,
          Aload 1,
          PushInt 0,
          Aload 1,
          InvokeVirtual (MethodRef "java/lang/String" "length" "()I"),
          InvokeVirtual (MethodRef "java/lang/String" "codePointCount" "(II)I"),
          InvokeStatic integerValueOf,
          AReturn
        ]
    }

-- | @__lengthUtf16CodeUnits@: JVM strings are UTF-16, so @String.length()@
--   is exactly the code-unit count, boxed.
lengthUtf16CodeUnitsSpec :: JvmMethod
lengthUtf16CodeUnitsSpec =
  JvmMethod
    { jmName = "__lengthUtf16CodeUnits",
      jmPublic = False,
      jmDesc = "(Ljava/lang/Object;)Ljava/lang/Object;",
      jmBody =
        [ Aload 0,
          CheckCast (ClassRef "java/lang/String"),
          InvokeVirtual (MethodRef "java/lang/String" "length" "()I"),
          InvokeStatic integerValueOf,
          AReturn
        ]
    }

-- | @__lengthUtf8Bytes@: standard (not modified) UTF-8 byte count via
--   @String.getBytes(StandardCharsets.UTF_8).length@, boxed. The byte array
--   is dropped on the next instruction.
lengthUtf8BytesSpec :: JvmMethod
lengthUtf8BytesSpec =
  JvmMethod
    { jmName = "__lengthUtf8Bytes",
      jmPublic = False,
      jmDesc = "(Ljava/lang/Object;)Ljava/lang/Object;",
      jmBody =
        [ Aload 0,
          CheckCast (ClassRef "java/lang/String"),
          GetStatic (FieldRef "java/nio/charset/StandardCharsets" "UTF_8" "Ljava/nio/charset/Charset;"),
          InvokeVirtual (MethodRef "java/lang/String" "getBytes" "(Ljava/nio/charset/Charset;)[B"),
          ArrayLength,
          InvokeStatic integerValueOf,
          AReturn
        ]
    }

-- | @__predUInt8@: @v == 0@ → @Left UnderflowError@, else @Right (v-1)@.
predUInt8Spec :: (Int, Int, Int) -> JvmMethod
predUInt8Spec tags =
  predSuccSpec "__predUInt8" "L_predu8_ok" [] Ifne tags [PushInt 1, ISub]

-- | @__succUInt8@: @v == 255@ (@sipush 255@) → @Right (v+1)@, else @Left OverflowError@.
succUInt8Spec :: (Int, Int, Int) -> JvmMethod
succUInt8Spec tags =
  predSuccSpec "__succUInt8" "L_succu8_ok" [PushInt 255] IfICmpNe tags [PushInt 1, IAdd]

-- | @__predInt32@: @v == -2147483648@ (@ldc@) → @Left UnderflowError@, else @Right (v-1)@.
predInt32Spec :: (Int, Int, Int) -> JvmMethod
predInt32Spec tags =
  predSuccSpec "__predInt32" "L_pred_ok" [PushInt (-2147483648)] IfICmpNe tags [PushInt 1, ISub]

-- | @__succInt32@: @v == 2147483647@ (@ldc@) → @Left OverflowError@, else @Right (v+1)@.
succInt32Spec :: (Int, Int, Int) -> JvmMethod
succInt32Spec tags =
  predSuccSpec "__succInt32" "L_succ_ok" [PushInt 2147483647] IfICmpNe tags [PushInt 1, IAdd]

-- | @__negInt32@: @v == -2147483648@ (@ldc@) → @Left OverflowError@, else @Right (-v)@.
negInt32Spec :: (Int, Int, Int) -> JvmMethod
negInt32Spec tags =
  predSuccSpec "__negInt32" "L_neg_ok" [PushInt (-2147483648)] IfICmpNe tags [INeg]

-- | @__addInt32@ / @__subInt32@ — signed overflow via the sign-bit XOR trick
--   (@(a^r)&(b^r)@ for add, @(a^b)&(a^r)@ for sub; sign bit set ⇒ overflow).
--   Slots: 0/1 = the boxed args, 2/3/4 = int @a@/@b@/@result@, 5 = scratch for
--   the error cell. On overflow the sign of @a@ splits Overflow (@a >= 0@) vs
--   Underflow (@a < 0@); each boxes its ctor tag then wraps it in the error
--   row (@LoadInt32@ for the FNV row hash). Two frames at the two error
--   labels: @append [int,int,int]@ then @same@ — derived by the classifier.
--   Tuple: (OverflowError ctor, UnderflowError ctor, Left, Right, Overflow
--   row hash, Underflow row hash).
addSubInt32Spec :: Text -> Text -> JvmInstr -> [JvmInstr] -> (Int, Int, Int, Int, Int32, Int32) -> JvmMethod
addSubInt32Spec name labelBase arithOp xorDetect (overCtor, underCtor, leftTag, rightTag, overRow, underRow) =
  let over = LabelId (labelBase <> "_over")
      under = LabelId (labelBase <> "_under")
      frame = Frame [VObject objectClass, VObject objectClass, VInteger, VInteger, VInteger] []
      innerBox ct = [PushInt 1, ANewArray objectClass, Dup, PushInt 0] <> boxedTag ct <> [AAStore, Astore 5]
      rowBox rt =
        [PushInt 2, ANewArray objectClass, Dup, PushInt 0, LoadInt32 rt, InvokeStatic integerValueOf, AAStore, Dup, PushInt 1, Aload 5, AAStore, Astore 5]
      leftWrap = [PushInt 2, ANewArray objectClass, Dup, PushInt 0] <> boxedTag leftTag <> [AAStore, Dup, PushInt 1, Aload 5, AAStore, AReturn]
      errBlock ct rt = innerBox ct <> rowBox rt <> leftWrap
   in JvmMethod
        { jmName = name,
          jmPublic = False,
          jmDesc = "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
          jmBody =
            [ Aload 0,
              CheckCast integerClass,
              InvokeVirtual integerIntValue,
              Istore 2,
              Aload 1,
              CheckCast integerClass,
              InvokeVirtual integerIntValue,
              Istore 3,
              Iload 2,
              Iload 3,
              arithOp,
              Istore 4
            ]
              <> xorDetect
              <> [Iflt over]
              <> [PushInt 2, ANewArray objectClass, Dup, PushInt 0]
              <> boxedTag rightTag
              <> [AAStore, Dup, PushInt 1, Iload 4, InvokeStatic integerValueOf, AAStore, AReturn]
              <> [Label over (Just frame), Iload 2, Iflt under]
              <> errBlock overCtor overRow
              <> [Label under (Just frame)]
              <> errBlock underCtor underRow
        }

-- | @__addInt32@: overflow detect @(a ^ sum) & (b ^ sum)@.
addInt32Spec :: (Int, Int, Int, Int, Int32, Int32) -> JvmMethod
addInt32Spec =
  addSubInt32Spec "__addInt32" "L_addi32" IAdd [Iload 2, Iload 4, IXor, Iload 3, Iload 4, IXor, IAnd]

-- | @__subInt32@: overflow detect @(a ^ b) & (a ^ diff)@.
subInt32Spec :: (Int, Int, Int, Int, Int32, Int32) -> JvmMethod
subInt32Spec =
  addSubInt32Spec "__subInt32" "L_subi32" ISub [Iload 2, Iload 3, IXor, Iload 2, Iload 4, IXor, IAnd]

-- | @__mulInt32@ — widen both args to @long@, @lmul@, then range-check the
--   product against [INT32_MIN, INT32_MAX] with @lcmp@ (@ifgt@ ⇒ Overflow,
--   @iflt@ ⇒ Underflow). The two error labels are reached with the dup'd
--   @long@ product still on the stack, so each carries a
--   @same_locals_1_stack_item [VLong]@ frame (slot 2 = error-cell scratch).
--   Tuple: (OverflowError ctor, UnderflowError ctor, Left, Right, Overflow
--   row hash, Underflow row hash).
mulInt32Spec :: (Int, Int, Int, Int, Int32, Int32) -> JvmMethod
mulInt32Spec (overCtor, underCtor, leftTag, rightTag, overRow, underRow) =
  let over = LabelId "L_muli32_over"
      under = LabelId "L_muli32_under"
      frame = Frame [VObject objectClass, VObject objectClass] [VLong]
      leftRow ct rt =
        [Pop2, PushInt 1, ANewArray objectClass, Dup, PushInt 0]
          <> boxedTag ct
          <> [AAStore, Astore 2, PushInt 2, ANewArray objectClass, Dup, PushInt 0, LoadInt32 rt, InvokeStatic integerValueOf, AAStore, Dup, PushInt 1, Aload 2, AAStore, Astore 2, PushInt 2, ANewArray objectClass, Dup, PushInt 0]
          <> boxedTag leftTag
          <> [AAStore, Dup, PushInt 1, Aload 2, AAStore, AReturn]
   in JvmMethod
        { jmName = "__mulInt32",
          jmPublic = False,
          jmDesc = "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
          jmBody =
            [Aload 0, CheckCast integerClass, InvokeVirtual integerIntValue, I2L, Aload 1, CheckCast integerClass, InvokeVirtual integerIntValue, I2L, LMul]
              <> [Dup2, LoadInt32 2147483647, I2L, LCmp, Ifgt over]
              <> [Dup2, LoadInt32 (-2147483648), I2L, LCmp, Iflt under]
              <> [L2I, InvokeStatic integerValueOf, Astore 2, PushInt 2, ANewArray objectClass, Dup, PushInt 0]
              <> boxedTag rightTag
              <> [AAStore, Dup, PushInt 1, Aload 2, AAStore, AReturn]
              <> [Label over (Just frame)]
              <> leftRow overCtor overRow
              <> [Label under (Just frame)]
              <> leftRow underCtor underRow
        }

-- | @__predUInt32@: @v == 0@ → @Left UnderflowError@, else @Right (v-1)@.
predUInt32Spec :: (Int, Int, Int) -> JvmMethod
predUInt32Spec tags =
  predSuccSpec "__predUInt32" "L_predu32_ok" [] Ifne tags [PushInt 1, ISub]

-- | @__succUInt32@: @v == 4294967295@ (@iconst_m1@ bit pattern) → @Right (v+1)@,
--   else @Left OverflowError@.
succUInt32Spec :: (Int, Int, Int) -> JvmMethod
succUInt32Spec tags =
  predSuccSpec "__succUInt32" "L_succu32_ok" [PushInt (-1)] IfICmpNe tags [PushInt 1, IAdd]
