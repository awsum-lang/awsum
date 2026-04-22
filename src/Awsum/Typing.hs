-- | Simple /monomorphic/ type checker for the surface AST ('Awsum.Syntax').
--
-- MVP scope and design notes:
--   • Built-in type constructors: @"String"@ and @"IOUnit"@.
--   • User-defined sum types via @type Color = Red | Green | Blue@.
--   • The only function type constructor is right-associative arrow @->@.
--   • No let-generalization, no unification variables, no inference beyond what is
--     written in signatures: every top-level definition must have an explicit 'Sig'.
--   • Built-ins are injected from imports: currently only @IO.Stdout.print : String -> IOUnit@.
--   • Presence and type of @main@ are /not/ checked here — this is a module-level
--     pass that accepts library-style modules (no @main@). The entry-point
--     check lives in 'requireMain' and is called only by @build@/@run@.
--
-- Algorithm (per program):
--   1) Extract type declarations, build constructor environment.
--   2) Partition remaining declarations into signatures and definitions.
--   3) Build a signature environment (ensuring no duplicates).
--   4) Validate each written type (only known TyCons are allowed).
--   5) Ensure no duplicate definitions and each def has a signature.
--   6) For each def:
--        a) check arity matches the arrow shape of its signature,
--        b) build a typing environment = {built-ins} ∪ {constructors} ∪ {params} ∪ {all sigs},
--        c) compute 'typeOfExpr' for the body and compare to the result type.
module Awsum.Typing
  ( typecheckProgram,
    requireMain,
    typeOfExpr,
    TypeError (..),
    prettyPrintTypeError,
    typeErrorSpan,
    Warning (..),
    warningSpan,
    warningMessage,
    isBareBuiltIn,
  )
where

import Awsum.BuiltIn (lookupBuiltIn)
import Awsum.Syntax
import Control.Monad (foldM, foldM_)
import Data.Graph qualified as G
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import Data.Text qualified as T
import Relude

-- | User-facing typing errors.
data TypeError
  = -- | Unqualified or unknown name not present in the environment.
    UnknownVar SrcSpan QName
  | -- | Application where callee does not have an arrow type.
    NotAFunction Expr Type'
  | -- | (expected, actual, in expression)
    TypeMismatch Type' Type' Expr
  | -- | (function name, expected #args, actual #args)
    ArityMismatch SrcSpan Name Int Int
  | -- | Top-level definition without a signature.
    MissingSignature SrcSpan Name
  | DuplicateSignature SrcSpan Name
  | DuplicateDefinition SrcSpan Name
  | -- | A 'TyCon' the checker does not recognize.
    UnknownTypeCon SrcSpan Name
  | MainMissing
  | -- | 'main' present but with a different type.
    MainWrongType Type'
  | -- | Qualified name used without importing its module path.
    NotImported SrcSpan QName
  | -- | Lowering error
    TELowering Text
  | -- | Duplicate type name in @type@ declarations.
    DuplicateTypeDef SrcSpan Name
  | -- | Constructor name used in multiple @type@ declarations.
    DuplicateConstructor SrcSpan Name
  | -- | Constructor not defined by any @type@ declaration.
    UnknownConstructor SrcSpan Name
  | -- | Case expression does not cover all constructors.
    NonExhaustiveCase SrcSpan Name [Name]
  | -- | A case arm that can never be reached (duplicate constructor).
    UnreachableCase SrcSpan Name
  | -- | A case arm on a constructor whose field type is uninhabited.
    UnreachableCaseUninhabited SrcSpan Name Type'
  | -- | Arms of a case expression have different types.
    CaseBranchTypeMismatch Type' Type' Expr
  | -- | Scrutinee of case is not a sum type.
    CaseOnNonSumType SrcSpan Type'
  | -- | Integer literal does not fit in the declared numeric type.
    --   Fields: span, literal value, type name (e.g. "Int32" or "UInt8").
    IntLiteralOutOfRange SrcSpan Integer Name
  | -- | Integer literal used in a context that does not determine its type.
    AmbiguousIntLiteral SrcSpan
  | -- | A local binding (function parameter or pattern variable) has the same
    --   name as an already-visible binding (outer param, top-level function,
    --   constructor, imported name, or a sibling binder in the same pattern).
    Shadowing SrcSpan Name
  | -- | An expression refers to a binding whose name starts with @_@.
    --   The convention: @_@ and @_foo@ name bindings that are intentionally
    --   unused — binding them is allowed (including top-level definitions
    --   that exist for their side-effect in a future module system), but
    --   referencing them makes the opt-out meaningless.
    ReferencingIgnored SrcSpan Name
  | -- | A constructor field references a type parameter whose name starts
    --   with @_@. Same principle as 'ReferencingIgnored' but at the type
    --   level: @type Phantom _tag = Phantom _tag@ is a contradiction.
    ReferencingIgnoredTypeVar SrcSpan Name
  | -- | A type parameter uses the bare underscore @_@ rather than a name
    --   like @_a@. Type parameters must be nameable (users need to talk
    --   about them in signatures and other constructor fields), so the
    --   wildcard form is rejected — always pick a name.
    UnnamedTypeParameter SrcSpan
  | -- | Two type parameters of the same type declaration share a name.
    DuplicateTypeParameter SrcSpan Name
  | -- | A type declaration uses bare @_@ as its type name. Type names
    --   must be addressable (any future signature mentioning the type
    --   needs a name to write down), so the wildcard form is rejected
    --   even when the type is intentionally unused — pick @_X@ instead.
    UnnamedType SrcSpan
  | -- | A constructor uses bare @_@ as its name. Same reasoning as
    --   'UnnamedType': constructors are referenced from expressions and
    --   patterns, so they must be nameable. Use @_C@ for an
    --   intentionally unused constructor.
    UnnamedConstructor SrcSpan
  | -- | A pattern matches on an @_C@-named constructor. Same convention
    --   as 'ReferencingIgnored', but specialised for case patterns: we
    --   carry the pattern's own span (where the user wrote @_C@) /and/
    --   the span of the constructor's name in its 'TypeDecl', so the
    --   quick-fix can rename both sites in one edit.
    ReferencingIgnoredConstructor SrcSpan SrcSpan Name
  | -- | A @BuiltIn.foo@ reference whose name is not in the compiler's
    --   built-in table ('Awsum.BuiltIn.builtIns'). The span is on the
    --   reference itself so editors can underline just @BuiltIn.foo@.
    UnknownBuiltIn SrcSpan Name
  | -- | An alias-form declaration @foo = BuiltIn.bar@ whose signature
    --   disagrees with the type registered for @bar@ in the compiler's
    --   built-in table. Fields: signature span, builtin-reference span,
    --   builtin name, declared type, registered type. Two spans so
    --   quick-fixes / diagnostics can point at both the signature (the
    --   thing the user typed) and the reference (what it aliases).
    BuiltInTypeMismatch SrcSpan SrcSpan Name Type' Type'
  deriving stock (Show, Eq)

-- | Extract the source span from a TypeError, if available.
typeErrorSpan :: TypeError -> Maybe SrcSpan
typeErrorSpan = \case
  UnknownVar sp _ -> Just sp
  NotAFunction e _ -> Just (exprSpan e)
  TypeMismatch _ _ e -> Just (exprSpan e)
  ArityMismatch sp _ _ _ -> Just sp
  MissingSignature sp _ -> Just sp
  DuplicateSignature sp _ -> Just sp
  DuplicateDefinition sp _ -> Just sp
  UnknownTypeCon sp _ -> Just sp
  MainMissing -> Nothing
  MainWrongType _ -> Nothing
  NotImported sp _ -> Just sp
  TELowering _ -> Nothing
  DuplicateTypeDef sp _ -> Just sp
  DuplicateConstructor sp _ -> Just sp
  UnknownConstructor sp _ -> Just sp
  NonExhaustiveCase sp _ _ -> Just sp
  UnreachableCase sp _ -> Just sp
  UnreachableCaseUninhabited sp _ _ -> Just sp
  CaseBranchTypeMismatch _ _ e -> Just (exprSpan e)
  CaseOnNonSumType sp _ -> Just sp
  IntLiteralOutOfRange sp _ _ -> Just sp
  AmbiguousIntLiteral sp -> Just sp
  Shadowing sp _ -> Just sp
  ReferencingIgnored sp _ -> Just sp
  ReferencingIgnoredTypeVar sp _ -> Just sp
  UnnamedTypeParameter sp -> Just sp
  DuplicateTypeParameter sp _ -> Just sp
  UnnamedType sp -> Just sp
  UnnamedConstructor sp -> Just sp
  ReferencingIgnoredConstructor sp _ _ -> Just sp
  UnknownBuiltIn sp _ -> Just sp
  BuiltInTypeMismatch sp _ _ _ _ -> Just sp

prettyPrintTypeError :: TypeError -> Text
prettyPrintTypeError = \case
  UnknownVar _ (QName _ n) -> "Unknown variable: " <> n
  NotAFunction _ ty -> "Not a function; has type " <> showType ty
  TypeMismatch expected actual _ -> "Type mismatch: expected " <> showType expected <> ", got " <> showType actual
  ArityMismatch _ name expected actual -> "Arity mismatch for " <> name <> ": expected " <> show expected <> " arguments, got " <> show actual
  MissingSignature _ name -> "Missing type signature for: " <> name
  DuplicateSignature _ name -> "Duplicate type signature for: " <> name
  DuplicateDefinition _ name -> "Duplicate definition for: " <> name
  UnknownTypeCon _ name -> "Unknown type constructor: " <> name
  MainMissing -> "Missing 'main' function"
  MainWrongType ty -> "Wrong type for 'main': expected String -> IOUnit, got " <> showType ty
  NotImported _ (QName _ n) -> "Not imported: " <> n
  TELowering msg -> msg
  DuplicateTypeDef _ name -> "Duplicate type definition: " <> name
  DuplicateConstructor _ name -> "Duplicate constructor: " <> name
  UnknownConstructor _ name -> "Unknown constructor: " <> name
  NonExhaustiveCase _ tyName missing -> "Non-exhaustive case on " <> tyName <> ": missing " <> show missing
  UnreachableCase _ name -> "Unreachable case: " <> name <> " is already covered"
  UnreachableCaseUninhabited _ conName ty -> "Unreachable case: " <> conName <> " can never match because " <> showType ty <> " has no constructors"
  CaseBranchTypeMismatch expected actual _ -> "Case branch type mismatch: expected " <> showType expected <> ", got " <> showType actual
  CaseOnNonSumType _ ty -> "Case on non-sum type: " <> showType ty
  IntLiteralOutOfRange _ n tyName ->
    "Integer literal " <> show n <> " out of range for " <> tyName <> " (valid range: " <> rangeText tyName <> ")"
  AmbiguousIntLiteral _ -> "Ambiguous integer literal: cannot infer type from context. Use an explicit type annotation."
  Shadowing _ n -> "Shadowing is not allowed: '" <> n <> "' is already bound in an enclosing scope"
  ReferencingIgnored _ n ->
    "Cannot reference '" <> n <> "': identifiers starting with '_' are marked as intentionally unused"
  ReferencingIgnoredTypeVar _ n ->
    "Cannot reference type parameter '" <> n <> "': identifiers starting with '_' are marked as intentionally unused"
  UnnamedTypeParameter _ ->
    "Type parameter must have a name; use '_a' (or similar) to mark one as intentionally unused"
  DuplicateTypeParameter _ n ->
    "Duplicate type parameter: '" <> n <> "' is already declared in this type"
  UnnamedType _ ->
    "Type name must not be bare '_'; use '_X' (or similar) to mark a type as intentionally unused"
  UnnamedConstructor _ ->
    "Constructor name must not be bare '_'; use '_C' (or similar) to mark a constructor as intentionally unused"
  ReferencingIgnoredConstructor _ _ n ->
    "Cannot match constructor '" <> n <> "': identifiers starting with '_' are marked as intentionally unused"
  UnknownBuiltIn _ n -> "Unknown builtin: 'BuiltIn." <> n <> "' is not provided by the compiler"
  BuiltInTypeMismatch _ _ n declared registered ->
    "Type mismatch for 'BuiltIn."
      <> n
      <> "': signature says "
      <> showType declared
      <> ", but the compiler registers it as "
      <> showType registered
  where
    showType :: Type' -> Text
    showType = \case
      TyVar _ n -> n
      TyCon _ n -> n
      TyApp _ f x -> showType f <> " " <> showTypeAtom x
      TyArrow _ a b -> showType a <> " -> " <> showType b
    showTypeAtom :: Type' -> Text
    showTypeAtom t@TyApp {} = "(" <> showType t <> ")"
    showTypeAtom t@TyArrow {} = "(" <> showType t <> ")"
    showTypeAtom t = showType t

    rangeText :: Name -> Text
    rangeText n = case intTypeRange n of
      Just (lo, hi) -> show lo <> ".." <> show hi
      Nothing -> "?"

-- | Inclusive (min, max) range for a numeric built-in type.
--   Returns 'Nothing' for types that are not known integer types.
intTypeRange :: Name -> Maybe (Integer, Integer)
intTypeRange = \case
  "Int32" -> Just (-2147483648, 2147483647)
  "UInt8" -> Just (0, 255)
  _ -> Nothing

-- | Typing environment: maps fully-qualified names to types.
--   We use 'QName' to keep the door open for qualified built-ins.
type Env = M.Map QName Type'

-- | Constructor info: type name, type parameters, field types, sibling
--   constructors, and the source span of the constructor's name in its
--   'TypeDecl' (used by quick-fixes that rename the declaration).
data ConInfo = ConInfo
  { ciTypeName :: Name,
    ciTypeParams :: [Name],
    ciFieldTypes :: [Type'],
    ciSiblings :: [Name],
    ciDeclSpan :: SrcSpan
  }
  deriving stock (Show, Eq)

-- | Constructor environment: maps constructor name → 'ConInfo'.
type ConEnv = M.Map Name ConInfo

-- | Helper to create a local (unqualified) 'QName'.
qLocal :: Name -> QName
qLocal = QName []

-- | Populate built-ins based on the set of imports present in the file.
--   Currently provides only @IO.Stdout.print : String -> IOUnit@ (enabled
--   by @import IO.Stdout@). The numeric show functions — @showInt32@ and
--   @showUInt8@ — live in 'stdlib/Prelude.aww' and reach their per-target
--   implementations through 'Awsum.BuiltIn'.
builtinEnvFromImports :: [ImportDecl] -> Env
builtinEnvFromImports imps =
  let modLists = [toList ns | ImportDecl _ ns _ <- imps]
      hasImport xs = elem xs modLists
      ioPrint =
        if hasImport ["IO", "Stdout"]
          then
            M.singleton
              (QName ["IO", "Stdout"] "print")
              (TyArrow noSpan (TyCon noSpan "String") (TyCon noSpan "IOUnit"))
          else mempty
   in ioPrint

-- | Flatten a right-associative arrow type into @(argument types, result type)@.
--   Example: @a -> b -> c@  ⇒  @([a, b], c)@.
splitArrow :: Type' -> ([Type'], Type')
splitArrow = go []
  where
    go acc (TyArrow _ a b) = go (acc <> [a]) b
    go acc t = (acc, t)

-- | Validate that a written type only mentions known constructors.
--   The 'Type'' value carries per-node spans, so errors point at the
--   offending identifier (e.g. @_A@) rather than the whole signature.
wellFormedTypeWith :: S.Set Name -> Type' -> Either TypeError ()
wellFormedTypeWith userTypes = \case
  TyVar _ _ -> Right ()
  TyCon sp n | "_" `T.isPrefixOf` n -> Left (ReferencingIgnored sp n)
  TyCon _ "String" -> Right ()
  TyCon _ "IOUnit" -> Right ()
  TyCon _ "Int32" -> Right ()
  TyCon _ "UInt8" -> Right ()
  TyCon sp n
    | S.member n userTypes -> Right ()
    | otherwise -> Left (UnknownTypeCon sp n)
  TyApp _ f x -> wellFormedTypeWith userTypes f >> wellFormedTypeWith userTypes x
  TyArrow _ a b -> wellFormedTypeWith userTypes a >> wellFormedTypeWith userTypes b

type Subst = M.Map Name Type'

applySubst :: Subst -> Type' -> Type'
applySubst s = \case
  TyVar sp v -> fromMaybe (TyVar sp v) (M.lookup v s)
  TyCon sp c -> TyCon sp c
  TyApp sp f x -> TyApp sp (applySubst s f) (applySubst s x)
  TyArrow sp a b -> TyArrow sp (applySubst s a) (applySubst s b)

compose :: Subst -> Subst -> Subst
compose s2 s1 = (applySubst s2 <$> s1) `M.union` s2

match :: Type' -> Type' -> Maybe Subst
match = go
  where
    go (TyVar _ v) t = Just (M.singleton v t)
    go t (TyVar _ v) = Just (M.singleton v t)
    go (TyCon _ c1) (TyCon _ c2)
      | c1 == c2 = Just M.empty
      | otherwise = Nothing
    go (TyApp _ f1 x1) (TyApp _ f2 x2) = do
      s1 <- go f1 f2
      s2 <- go (applySubst s1 x1) (applySubst s1 x2)
      pure (compose s2 s1)
    go (TyArrow _ a1 b1) (TyArrow _ a2 b2) = do
      s1 <- go a1 a2
      s2 <- go (applySubst s1 b1) (applySubst s1 b2)
      pure (compose s2 s1)
    go _ _ = Nothing

-- | Freshen type variables in a type by adding a suffix.
--   Used to avoid name collisions when matching generic types against concrete types.
freshenType :: Text -> Type' -> Type'
freshenType suffix ty = applySubst subst ty
  where
    vars = collectTypeVars ty
    subst = M.fromList [(v, TyVar noSpan (v <> suffix)) | v <- toList vars]

-- | Collect all type variables in a type.
collectTypeVars :: Type' -> S.Set Name
collectTypeVars (TyVar _ n) = S.singleton n
collectTypeVars (TyCon _ _) = S.empty
collectTypeVars (TyApp _ f x) = collectTypeVars f <> collectTypeVars x
collectTypeVars (TyArrow _ a b) = collectTypeVars a <> collectTypeVars b

-- | Build the return type of a constructor given the type name and type parameters.
--   @conReturnType "Color" []@    → @TyCon "Color"@
--   @conReturnType "Lookup" ["a"]@ → @TyApp (TyCon "Lookup") (TyVar "a")@
conReturnType :: Name -> [Name] -> Type'
conReturnType tName [] = TyCon noSpan tName
conReturnType tName tvs =
  foldl' (TyApp noSpan) (TyCon noSpan tName) (map (TyVar noSpan) tvs)

-- | Build the full type of a constructor: @fieldType1 -> ... -> returnType@.
conType :: Name -> [Name] -> [Type'] -> Type'
conType tName tvs = foldr (TyArrow noSpan) (conReturnType tName tvs)

-- | Type-constructor map: type name → list of constructor names (including empty types).
type TypeConsMap = M.Map Name [Name]

-- | Build a constructor environment from @type@ declarations.
--   Returns (set of type names, constructor env, constructor value env, type-constructor map).
buildConEnv :: [Decl] -> Either TypeError (S.Set Name, ConEnv, Env, TypeConsMap)
buildConEnv decls = do
  let typeDecls = [(sp, n, tvs, cs) | TypeDecl sp n tvs cs _ <- decls]
  -- Validate each declaration before building anything else:
  --   • bare '_' as type or constructor name — rejected;
  --   • bare '_' or duplicate type-parameter names — rejected;
  --   • '_foo' type-variable references inside constructor fields — rejected.
  forM_ typeDecls $ \(sp, n, tvs, cs) -> do
    -- The TypeDecl span starts at the @type@ keyword; the name sits
    -- @length "type "@ chars later (formatter guarantees this shape).
    let nameStartCol = spanStartCol sp + T.length "type "
        nameSp = SrcSpan (spanStartLine sp) nameStartCol (spanStartLine sp) (nameStartCol + T.length n)
    when (n == "_") $ Left (UnnamedType nameSp)
    forM_ cs $ \(ConDef cSp cName _) ->
      when (cName == "_") $ Left (UnnamedConstructor cSp)
    validateTypeParams sp tvs cs
  -- 'tvs' here is already reduced to bare names — the per-parameter spans
  -- only matter for the unused-type-parameter warning (emitted separately).
  let typeDefs = [(sp, n, map paramName tvs, cs) | (sp, n, tvs, cs) <- typeDecls]
  -- Check for duplicate type names.
  foldM_ checkDupType S.empty typeDefs
  -- Build the constructor environment.
  conEnv <- foldM insertCons M.empty typeDefs
  -- Build the value environment for constructors with proper polymorphic types.
  let conValEnv =
        M.fromList
          [ (qLocal cName, conType tName tvs flds)
          | (_sp, tName, tvs, cs) <- typeDefs,
            ConDef _ cName flds <- cs
          ]
      typeNames = S.fromList [n | (_sp, n, _tvs, _cs) <- typeDefs]
      typeConsMap =
        M.fromList
          [ (tName, [cName | ConDef _ cName _ <- cs])
          | (_sp, tName, _tvs, cs) <- typeDefs
          ]
  pure (typeNames, conEnv, conValEnv, typeConsMap)
  where
    checkDupType seen (sp, n, _tvs, _) =
      if S.member n seen
        then Left (DuplicateTypeDef (typeNameSubSpan sp n) n)
        else Right (S.insert n seen)

    -- The TypeDecl span starts at the @type@ keyword; the name sits
    -- @length "type "@ columns later. Narrowing to just the name span
    -- lets diagnostics underline `Either`, not the whole declaration.
    typeNameSubSpan sp n =
      let nameStartCol = spanStartCol sp + T.length "type "
       in SrcSpan (spanStartLine sp) nameStartCol (spanStartLine sp) (nameStartCol + T.length n)

    insertCons m (sp, tName, tvs, cs) =
      foldM (insertOne sp tName tvs cs) m cs

    insertOne sp tName tvs allCons m (ConDef cSp cName _) =
      if M.member cName m
        then Left (DuplicateConstructor sp cName)
        else
          let flds = [fs | ConDef _ cn fs <- allCons, cn == cName]
              siblings = [n | ConDef _ n _ <- allCons]
           in Right (M.insert cName (ConInfo tName tvs (concat flds) siblings cSp) m)

-- | Validate a single type declaration's parameter list and constructor
--   field types. Enforces three invariants:
--
--     1. Every parameter has a name; bare @_@ is rejected ('UnnamedTypeParameter').
--     2. No two parameters share a name ('DuplicateTypeParameter').
--     3. No constructor field mentions an ignored type variable (a
--        'TyVar' whose name starts with @_@) — if the user marks a type
--        parameter as intentionally unused, they must not then turn
--        around and use it ('ReferencingIgnoredTypeVar').
validateTypeParams :: SrcSpan -> [Param] -> [ConDef] -> Either TypeError ()
validateTypeParams _declSp params cons = do
  -- 1) Reject bare '_' as a type parameter name.
  forM_ params $ \(Param sp n) ->
    when (n == "_") $ Left (UnnamedTypeParameter sp)
  -- 2) Reject duplicate parameter names.
  foldM_ checkDup S.empty params
  -- 3) Reject references to ignored type variables inside constructor fields.
  --    The 'TyVar' carries its own source span, so the error points at
  --    the exact identifier rather than the whole type declaration.
  forM_ cons $ \(ConDef _ _ flds) ->
    forM_ flds checkNoIgnoredTyVar
  where
    checkDup seen (Param sp n) =
      if S.member n seen
        then Left (DuplicateTypeParameter sp n)
        else Right (S.insert n seen)

    checkNoIgnoredTyVar = \case
      TyVar sp n | "_" `T.isPrefixOf` n -> Left (ReferencingIgnoredTypeVar sp n)
      TyVar _ _ -> Right ()
      TyCon _ _ -> Right ()
      TyApp _ f x -> checkNoIgnoredTyVar f >> checkNoIgnoredTyVar x
      TyArrow _ a b -> checkNoIgnoredTyVar a >> checkNoIgnoredTyVar b

-- | A non-fatal observation about a program. Surfaced to editors as
--   yellow squigglies and to CI via @--strict@.
data Warning
  = -- | A function parameter was bound but never referenced in the body.
    --   Span covers just the parameter identifier so quick-fixes can
    --   replace it precisely.
    UnusedParameter SrcSpan Name
  | -- | A top-level definition is not reachable from @main@ (no transitive
    --   reference). Fields: span of the name in its @FunDef@ (used for
    --   caret placement), optional span of the matching 'Sig' name (the
    --   quick-fix renames both so the file stays type-correct), the name.
    UnusedTopLevel SrcSpan (Maybe SrcSpan) Name
  | -- | A type parameter is declared but never used in any constructor
    --   field of its type — likely a phantom parameter that was not
    --   marked with @_@. Span covers just the parameter identifier so
    --   the rename quick-fix targets it precisely.
    UnusedTypeParameter SrcSpan Name
  deriving stock (Show, Eq)

-- | Source span of a warning. This is the span the editor highlights —
--   for 'UnusedTopLevel' that's the @FunDef@ name, not the signature,
--   since the definition is the declaration most users think of.
warningSpan :: Warning -> SrcSpan
warningSpan = \case
  UnusedParameter sp _ -> sp
  UnusedTopLevel sp _ _ -> sp
  UnusedTypeParameter sp _ -> sp

-- | Human-readable message for a warning.
warningMessage :: Warning -> Text
warningMessage = \case
  UnusedParameter _ n -> "Unused parameter: '" <> n <> "'"
  UnusedTopLevel _ _ n -> "Unused top-level definition: '" <> n <> "'"
  UnusedTypeParameter _ n -> "Unused type parameter: '" <> n <> "'"

-- | Check a whole program against explicit signatures.
--   On success, returns the list of warnings discovered while checking.
--   On the first error, short-circuits with a descriptive 'TypeError'.
typecheckProgram :: Program -> Either TypeError [Warning]
typecheckProgram Program {imports, decls} = do
  -- 1) Build constructor environment from type declarations.
  (userTypeNames, conEnv, conValEnv, typeConsMap) <- buildConEnv (toList decls)

  -- 2) Partition top-level decls into signatures and definitions.
  let (sigsList, defsList) = partitionEithers (mapMaybe toEither (toList decls))
      toEither = \case
        Sig sp n t _ -> Just (Left (sp, n, t))
        FunDef sp n as e _ -> Just (Right (sp, n, as, e))
        CommentDecl _ -> Nothing
        TypeDecl {} -> Nothing

  -- Build the signature environment; reject duplicates early.
  sigEnv <- foldM insertSig M.empty sigsList

  -- Validate every written type (no unknown TyCons, no ignored refs).
  mapM_ (\(_sp, _, t) -> wellFormedTypeWith userTypeNames t) sigsList

  -- Ensure unique definition names (shadowing is not allowed at top level).
  foldM_ insertDefName S.empty defsList

  -- Precompute signature spans by name so alias-form mismatch errors
  -- can point at the signature exactly (as opposed to the whole FunDef).
  let sigSpanByName = M.fromList [(n, nameSubSpan sp n) | (sp, n, _t) <- sigsList]

  -- Check each definition body against its declared type, accumulating warnings.
  defWarnings <- forM defsList $ \(sp, n, args, body) -> do
    ty <- maybeToRight (MissingSignature sp n) (M.lookup n sigEnv)
    let (argTys, retTy) = splitArrow ty
        -- The alias form @foo = BuiltIn.bar@ binds zero params even when
        -- the signature has arrow shape: the RHS itself carries the whole
        -- function type, and we typecheck it against the full signature.
        -- This is the only place the zero-param shape is allowed for a
        -- non-trivial signature — every other zero-param def still needs
        -- its arity on the left of @=@.
        isBuiltInAlias = null args && isBareBuiltIn body
    unless isBuiltInAlias
      $ when (length argTys /= length args)
      $ Left (ArityMismatch sp n (length argTys) (length args))

    -- For alias-form decls, check the builtin's registered type against
    -- the declared signature up-front. If they disagree, surface a
    -- dedicated 'BuiltInTypeMismatch' (with both spans) rather than the
    -- generic 'TypeMismatch' 'checkExpr' would produce below — the
    -- compiler-dev reader needs to know this is a sig-vs-table
    -- disagreement, not an ordinary user type error.
    when isBuiltInAlias $ case bareBuiltInRef body of
      Just (bodySp, bn)
        | Just bty <- lookupBuiltIn bn,
          bty /= ty ->
            let sigSp = fromMaybe sp (M.lookup n sigSpanByName)
             in Left (BuiltInTypeMismatch sigSp bodySp bn ty bty)
      _ -> pass

    -- Build an environment visible inside the body:
    --   built-ins from imports ⊔ constructors ⊔ parameters ⊔ all top-level signatures.
    -- Bare-underscore parameters @_@ are wildcards: no binding is introduced
    -- so multiple @_@ params do not collide with each other or with anything.
    -- Underscore-prefixed names like @_foo@ are bound normally; the parser
    -- prevents them from being referenced because expression names cannot
    -- start with @_@.
    let envBuiltins = builtinEnvFromImports imports
        namedArgs = [(p, t) | (p, t) <- zip args argTys, paramName p /= "_"]
        envParams = M.fromList [(qLocal (paramName p), t) | (p, t) <- namedArgs]
        envTop = M.fromList [(qLocal n', t') | (_sp', n', t') <- sigsList]
        envOuter = M.unions [envBuiltins, conValEnv, envTop]
        env = M.union envParams envOuter
        expectedBodyTy = if isBuiltInAlias then ty else retTy

    -- Reject shadowing: params must be unique and must not collide with
    -- any already-visible name (constructor, import, top-level signature).
    checkNoShadow envOuter [(paramSpan p, paramName p) | (p, _) <- namedArgs]

    checkExpr conEnv typeConsMap env expectedBodyTy body

    -- Unused-parameter warnings: report any user-named parameter (not @_@,
    -- not @_foo@) that the body does not reference. Underscore-prefixed
    -- names are an explicit opt-out and never warned on.
    let referenced = freeNames body
    pure
      [ UnusedParameter (paramSpan p) (paramName p)
      | p <- args,
        let nm = paramName p,
        not ("_" `T.isPrefixOf` nm),
        not (S.member nm referenced)
      ]

  -- Unused top-level warnings: any definition not transitively reachable
  -- from 'main' is dead code (the whole-program compilation model tree-
  -- shakes it anyway). But we report only the *root causes*: if @f1@ is
  -- used solely from @f2@ and @f2@ is unreachable, only @f2@ is warned
  -- on — fixing @f2@ will reveal @f1@'s status on the next compile.
  --
  -- Mutual-recursion cycles are a single "root" — we emit a warning on
  -- every member of a source SCC in the unused subgraph, since deleting
  -- any one of them doesn't break the cycle.
  --
  -- If the module has no 'main', we skip this analysis: every top-level
  -- is a potential entry point for a library consumer and we can't tell
  -- from this file alone which are live.
  let callGraph = M.fromList [(n, freeNames body) | (_sp, n, _args, body) <- defsList]
      topLevelWarnings = case M.lookup "main" sigEnv of
        Nothing -> []
        Just _ ->
          let reachableFromMain = reachable "main" callGraph
              unusedSet =
                S.fromList
                  [ n
                  | (_sp, n, _args, _body) <- defsList,
                    n /= "main",
                    not ("_" `T.isPrefixOf` n),
                    not (S.member n reachableFromMain)
                  ]
              sourceSccMembers = sourceSccs callGraph unusedSet
              defSpanByName = M.fromList [(n, sp) | (sp, n, _args, _body) <- defsList]
           in [ UnusedTopLevel (nameSubSpan sp n) (M.lookup n sigSpanByName) n
              | n <- S.toList sourceSccMembers,
                Just sp <- [M.lookup n defSpanByName]
              ]

  -- Unused type-parameter warnings: any type parameter declared on a
  -- 'TypeDecl' that never appears in any of its constructor fields.
  -- Underscore-prefixed params are the explicit opt-out and are skipped.
  let typeDeclParams =
        [ (params, cs)
        | TypeDecl _ _ params cs _ <- toList decls
        ]
      typeParamWarnings =
        [ UnusedTypeParameter sp n
        | (params, cs) <- typeDeclParams,
          let fieldVars = S.unions [collectTypeVars t | ConDef _ _ flds <- cs, t <- flds],
          Param sp n <- params,
          not ("_" `T.isPrefixOf` n),
          not (S.member n fieldVars)
        ]

  Right (concat defWarnings <> topLevelWarnings <> typeParamWarnings)
  where
    insertSig m (sp, n, t) =
      if M.member n m
        then Left (DuplicateSignature sp n)
        else Right (M.insert n t m)

    insertDefName s (sp, n, _, _) =
      if S.member n s
        then Left (DuplicateDefinition sp n)
        else Right (S.insert n s)

-- | Is the expression a bare @BuiltIn.foo@ reference (modulo parens)?
--   Used to recognise the alias form @foo = BuiltIn.bar@ at top level.
isBareBuiltIn :: Expr -> Bool
isBareBuiltIn = \case
  EBuiltIn _ _ -> True
  EParens _ e -> isBareBuiltIn e
  _ -> False

-- | Extract the span and name of a bare @BuiltIn.foo@ reference, peeling
--   any surrounding parentheses. Returns 'Nothing' for anything else.
bareBuiltInRef :: Expr -> Maybe (SrcSpan, Name)
bareBuiltInRef = \case
  EBuiltIn sp n -> Just (sp, n)
  EParens _ e -> bareBuiltInRef e
  _ -> Nothing

-- | Entry-point check: verify the program declares @main : String -> IOUnit@.
--   Called only from @build@/@run@ — modules without @main@ (libraries,
--   @Prelude.aww@) pass 'typecheckProgram' but fail here when an executable
--   is requested.
requireMain :: Program -> Either TypeError ()
requireMain Program {decls} =
  case listToMaybe [t | Sig _ "main" t _ <- toList decls] of
    Nothing -> Left MainMissing
    Just ty ->
      let want = TyArrow noSpan (TyCon noSpan "String") (TyCon noSpan "IOUnit")
       in unless (ty == want) (Left (MainWrongType ty))

-- | Reject a fresh list of binders if any of them are already in scope or
--   duplicate each other. Used for function parameters and for the variables
--   introduced by a single case-arm pattern. Each binder carries its own span
--   so the error points exactly at the shadowing identifier.
checkNoShadow :: Env -> [(SrcSpan, Name)] -> Either TypeError ()
checkNoShadow = foldM_ addOne
  where
    addOne acc (sp, n) =
      if M.member (qLocal n) acc
        then Left (Shadowing sp n)
        else Right (M.insert (qLocal n) (TyCon noSpan "<binder>") acc)

-- | Check that an expression has the given expected type.
--
-- Used at the /boundary/ where the expected type is known — currently the
-- body of a top-level definition checked against its declared return type.
-- This is where 'LInt' literals get their type: they have no synthesis form
-- (no defaulting), so they must appear in a context that fixes the type.
checkExpr :: ConEnv -> TypeConsMap -> Env -> Type' -> Expr -> Either TypeError ()
checkExpr conEnv tcm env expected = \case
  ELit sp (LInt n) ->
    case expected of
      TyCon _ tyName
        | Just (lo, hi) <- intTypeRange tyName ->
            if n >= lo && n <= hi
              then Right ()
              else Left (IntLiteralOutOfRange sp n tyName)
      _ -> Left (TypeMismatch expected (TyCon noSpan "<integer literal>") (ELit sp (LInt n)))
  EParens _sp e -> checkExpr conEnv tcm env expected e
  e -> do
    actual <- typeOfExpr conEnv tcm env e
    unless (actual == expected) $ Left (TypeMismatch expected actual e)

-- | Infer/check the type of an expression under the given environment.
--   This function /checks/ consistency; it does not invent polymorphism.
typeOfExpr :: ConEnv -> TypeConsMap -> Env -> Expr -> Either TypeError Type'
typeOfExpr conEnv tcm env = \case
  ELit sp (LString _) -> Right (TyCon sp "String")
  ELit sp (LInt _) -> Left (AmbiguousIntLiteral sp)
  EVar sp q ->
    case q of
      -- Bindings whose name starts with '_' are intentionally unused and
      -- must not be referenced — regardless of whether they happen to be
      -- in scope (they can be, e.g. an unused-but-kept top-level definition).
      QName [] n | "_" `T.isPrefixOf` n -> Left (ReferencingIgnored sp n)
      _ -> case M.lookup q env of
        Just t -> Right t
        Nothing ->
          case q of
            QName (_ : _) _ -> Left (NotImported sp q) -- looks qualified but missing import
            _ -> Left (UnknownVar sp q)
  EParens _sp e ->
    typeOfExpr conEnv tcm env e
  ECon sp name
    | "_" `T.isPrefixOf` name -> Left (ReferencingIgnored sp name)
    | otherwise ->
        case M.lookup (qLocal name) env of
          Just t ->
            -- Freshen type variables using source position as unique suffix
            -- to ensure each constructor usage gets a fresh polymorphic instance.
            let suffix = "$" <> show (spanStartLine sp) <> "_" <> show (spanStartCol sp)
             in Right (freshenType suffix t)
          Nothing -> Left (UnknownConstructor sp name)
  EBuiltIn sp name ->
    case lookupBuiltIn name of
      Just t -> Right t
      Nothing -> Left (UnknownBuiltIn sp name)
  EApp _sp f x -> do
    tf <- typeOfExpr conEnv tcm env f
    case tf of
      TyArrow _ a b -> do
        -- If the argument is a bare integer literal we don't have a synthesis
        -- form for it (no defaulting) — the expected type from the callee's
        -- signature is the only way to give it a type. Delegate to 'checkExpr'
        -- in that case so range validation happens against the concrete 'a'.
        case x of
          ELit _ (LInt _) -> checkExpr conEnv tcm env a x $> b
          EParens _ (ELit _ (LInt _)) -> checkExpr conEnv tcm env a x $> b
          _ -> do
            tx <- typeOfExpr conEnv tcm env x
            case match a tx of
              Just s -> Right (applySubst s b)
              Nothing -> Left (TypeMismatch a tx x)
      _ -> Left (NotAFunction f tf)
  -- String concatenation is only defined for (String, String) → String.
  EInfix sp OpConcat l r -> do
    tl <- typeOfExpr conEnv tcm env l
    tr <- typeOfExpr conEnv tcm env r
    if tl == TyCon noSpan "String" && tr == TyCon noSpan "String"
      then Right (TyCon noSpan "String")
      else
        -- pick the first offender for a more helpful message
        let blame = if tl /= TyCon noSpan "String" then tl else tr
         in Left (TypeMismatch (TyCon noSpan "String") blame (EInfix sp OpConcat l r))
  ECase sp scrut alts _ -> do
    scrutTy <- typeOfExpr conEnv tcm env scrut
    -- Scrutinee must be a user-defined sum type.
    tyName <- case extractTyCon scrutTy of
      Just n | M.member n tcm -> Right n
      _ -> Left (CaseOnNonSumType sp scrutTy)
    let allCons = fromMaybe [] (M.lookup tyName tcm)
    -- Compute substitution from type parameters to concrete types.
    -- E.g. for Lookup String: match (Lookup a) against (Lookup String) → {a → String}
    -- Freshen generic type variables to avoid name collisions with scrutinee type variables.
    let scrutSubst = case anyConInfo tyName conEnv of
          Just ci ->
            let genericRetTy = conReturnType tyName (ciTypeParams ci)
                freshGenericRetTy = freshenType "$scrut" genericRetTy
             in fromMaybe M.empty (match freshGenericRetTy scrutTy)
          Nothing -> M.empty
    -- Type-check each arm; collect arm types and covered patterns.
    -- We track full patterns (not just constructor names) to handle nested patterns correctly.
    (armTypes, coveredPatterns) <- foldM (checkArm sp env scrutSubst) ([], []) (toList alts)
    -- Exhaustiveness: every inhabited constructor must appear at least once.
    -- For simple patterns (no nesting), each constructor should appear exactly once.
    -- For nested patterns, we just check that all top-level constructors are covered.
    let topLevelCons = [cName | (cName, _) <- coveredPatterns]
        missing = filter (`notElem` topLevelCons) allCons
        inhabitedMissing = filter (isConInhabited conEnv tcm S.empty scrutSubst) missing
    unless (null inhabitedMissing) $ Left (NonExhaustiveCase sp tyName inhabitedMissing)
    -- All arms must agree on the result type (via unification, not equality).
    case armTypes of
      [] -> Left (NonExhaustiveCase sp tyName allCons)
      (firstTy : restTys) ->
        foldM
          ( \acc ty -> case match acc ty of
              Just s -> Right (applySubst s acc)
              Nothing -> Left (CaseBranchTypeMismatch acc ty scrut)
          )
          firstTy
          restTys
  where
    checkArm caseSp envLocal scrutSubst (tys, patterns) (CaseAlt _ (PCon patSp cName pats) body _) = do
      -- Reject @_X@ constructor references at any depth in the pattern.
      mapM_ (rejectIgnoredConstructor conEnv) (PCon patSp cName pats : pats)
      -- Verify the constructor belongs to the scrutinee type.
      ci <- maybeToRight (UnknownConstructor (exprSpan body) cName) (M.lookup cName conEnv)
      -- Reject duplicate (unreachable) patterns by comparing full pattern structure.
      let currentPattern = (cName, pats)
      when (patternMatches conEnv currentPattern patterns) $ Left (UnreachableCase caseSp cName)
      -- Reject shadowing: pattern variables (including those in nested patterns)
      -- must not duplicate each other and must not collide with anything
      -- already visible in the arm. Each binder carries its own span so the
      -- error arrow lands on the offending identifier, not on a usage site.
      checkNoShadow envLocal (collectPatternVars pats)
      -- Compute field types with proper freshening and substitution.
      -- First freshen the constructor's field types with the same suffix used for scrutSubst,
      -- then apply the matched substitution.
      let freshFieldTys = map (freshenType "$scrut") (ciFieldTypes ci)
          fieldTys = map (applySubst scrutSubst) freshFieldTys
      -- Reject patterns on uninhabited constructors (unreachable).
      case find (not . isTypeInhabited conEnv tcm) fieldTys of
        Just emptyTy -> Left (UnreachableCaseUninhabited caseSp cName emptyTy)
        Nothing -> pass
      -- Bind pattern variables from constructor fields.
      let bindings = patternBindings conEnv pats fieldTys
          envWithBindings = M.union (M.fromList [(qLocal n, t) | (n, t) <- bindings]) envLocal
      bodyTy <- typeOfExpr conEnv tcm envWithBindings body
      pure (tys <> [bodyTy], patterns <> [currentPattern])
    checkArm _ _ _ _ CaseAlt {} =
      Left (TELowering "only constructor patterns are supported")

-- | Reject any @_X@-named constructor anywhere in a pattern. The error
--   carries both the pattern's own span and the span of the constructor
--   in its 'TypeDecl' so a quick-fix can rename both sites at once.
rejectIgnoredConstructor :: ConEnv -> Pattern -> Either TypeError ()
rejectIgnoredConstructor conEnv = \case
  PCon patSp cName inner
    | "_" `T.isPrefixOf` cName ->
        let declSp = maybe patSp ciDeclSpan (M.lookup cName conEnv)
         in Left (ReferencingIgnoredConstructor patSp declSp cName)
    | otherwise -> mapM_ (rejectIgnoredConstructor conEnv) inner
  PVar _ _ -> Right ()
  PWild -> Right ()

-- | Collect all variable binders from a list of (possibly nested) patterns,
--   in left-to-right order, paired with the span of each binder.
collectPatternVars :: [Pattern] -> [(SrcSpan, Name)]
collectPatternVars = concatMap go
  where
    go (PVar sp n) = [(sp, n)]
    go PWild = []
    go (PCon _ _ inner) = concatMap go inner

-- | Extract variable bindings from patterns and their corresponding types.
--   Recurses into nested constructor patterns to bind deeply nested variables.
patternBindings :: ConEnv -> [Pattern] -> [Type'] -> [(Name, Type')]
patternBindings conEnv pats tys = concatMap go (zip pats tys)
  where
    go (PVar _ n, t) = [(n, t)]
    go (PWild, _) = []
    go (PCon _ cName innerPats, ty) =
      case M.lookup cName conEnv of
        Nothing -> []
        Just ci ->
          let genericRetTy = conReturnType (ciTypeName ci) (ciTypeParams ci)
              -- Freshen generic type variables to avoid collisions with scrutinee type variables.
              freshGenericRetTy = freshenType "$inner" genericRetTy
              freshFieldTys = map (freshenType "$inner") (ciFieldTypes ci)
              innerSubst = fromMaybe M.empty (match freshGenericRetTy ty)
              fieldTys = map (applySubst innerSubst) freshFieldTys
           in patternBindings conEnv innerPats fieldTys

-- | Extract the type constructor name from a type (peeling off TyApp).
extractTyCon :: Type' -> Maybe Name
extractTyCon (TyCon _ n) = Just n
extractTyCon (TyApp _ f _) = extractTyCon f
extractTyCon _ = Nothing

-- | Get 'ConInfo' for any constructor of the given type.
anyConInfo :: Name -> ConEnv -> Maybe ConInfo
anyConInfo tyName conEnv =
  find (\ci -> ciTypeName ci == tyName) (M.elems conEnv)

-- | A constructor is inhabited if all its field types (after substitution) are inhabited.
--   A type is uninhabited if it has no constructors (e.g. @type Never@),
--   or all its constructors require an uninhabited field (e.g. @Box Never@).
isConInhabited :: ConEnv -> TypeConsMap -> S.Set Type' -> Subst -> Name -> Bool
isConInhabited conEnv tcm visited subst cName =
  case M.lookup cName conEnv of
    Nothing -> True
    Just ci ->
      -- Freshen field types with the same suffix used in scrutSubst, then apply substitution.
      let freshFieldTys = map (freshenType "$scrut") (ciFieldTypes ci)
          fieldTys = map (applySubst subst) freshFieldTys
       in all (isTypeInhabited' conEnv tcm visited) fieldTys

-- | A type is inhabited unless it resolves to a user-defined type whose
--   constructors all require an uninhabited field (recursively).
--   @type Never@ → uninhabited (0 constructors).
--   @Box Never@  → uninhabited (Box requires Never which is uninhabited).
--   Recursive types (e.g. @List a = Cons a (List a) | Nil@) are assumed inhabited
--   via coinductive interpretation: if we encounter the exact same concrete type
--   already being checked, we return True and let base-case constructors confirm it.
isTypeInhabited :: ConEnv -> TypeConsMap -> Type' -> Bool
isTypeInhabited conEnv tcm = isTypeInhabited' conEnv tcm S.empty

isTypeInhabited' :: ConEnv -> TypeConsMap -> S.Set Type' -> Type' -> Bool
isTypeInhabited' conEnv tcm visited ty
  | ty `S.member` visited = True -- recursive type, assume inhabited
  | otherwise =
      case extractTyCon ty of
        Just n -> case M.lookup n tcm of
          Nothing -> True -- built-in, inhabited
          Just [] -> False -- 0 constructors
          Just cons ->
            -- Compute substitution for this concrete type (e.g. Box Never → {a → Never})
            -- Freshen generic type variables to avoid collisions with concrete type variables.
            let visited' = S.insert ty visited
                subst = case anyConInfo n conEnv of
                  Just ci ->
                    let genericRetTy = conReturnType n (ciTypeParams ci)
                        freshGenericRetTy = freshenType "$scrut" genericRetTy
                     in fromMaybe M.empty (match freshGenericRetTy ty)
                  Nothing -> M.empty
             in any (isConInhabited conEnv tcm visited' subst) cons
        Nothing -> True

-- | Check if a pattern is already covered by any pattern in the list.
--   Compares full pattern structure (constructor name + nested patterns).
--   This handles nested patterns like @Ok (Ok value)@ vs @Ok (Err value)@.
patternMatches :: ConEnv -> (Name, [Pattern]) -> [(Name, [Pattern])] -> Bool
patternMatches _conEnv (cName, pats) = any (\(coveredName, coveredPats) -> cName == coveredName && patternsEqual pats coveredPats)
  where
    patternsEqual :: [Pattern] -> [Pattern] -> Bool
    patternsEqual ps1 ps2
      | length ps1 /= length ps2 = False
      | otherwise = and (zipWith patternEqual ps1 ps2)

    patternEqual :: Pattern -> Pattern -> Bool
    patternEqual (PVar _ _) (PVar _ _) = True -- all variables match
    patternEqual PWild PWild = True
    patternEqual PWild (PVar _ _) = True -- wildcard matches variable
    patternEqual (PVar _ _) PWild = True -- variable matches wildcard
    patternEqual (PCon _ c1 ps1) (PCon _ c2 ps2) =
      c1 == c2 && patternsEqual ps1 ps2
    patternEqual _ _ = False

-- | Collect every unqualified variable name referenced in an expression.
--   Used by the unused-parameter check; the language forbids shadowing,
--   so a simple set of all referenced names is sufficient — we never need
--   to subtract pattern bindings to disambiguate a parameter reference.
freeNames :: Expr -> S.Set Name
freeNames = go
  where
    go = \case
      EVar _ (QName [] n) -> S.singleton n
      EVar _ _ -> S.empty
      EApp _ f x -> go f <> go x
      EInfix _ _ l r -> go l <> go r
      EParens _ e -> go e
      ELit _ _ -> S.empty
      ECon _ _ -> S.empty
      EBuiltIn _ _ -> S.empty
      ECase _ scrut alts _ ->
        go scrut <> foldMap (\(CaseAlt _ _ body _) -> go body) (toList alts)

-- | Transitive set of names reachable from @root@ through the reference
--   graph. Used to decide which top-level definitions are unused: anything
--   not reachable from @main@ is dead code.
reachable :: Name -> M.Map Name (S.Set Name) -> S.Set Name
reachable root graph = go (S.singleton root) [root]
  where
    go visited [] = visited
    go visited (n : rest) =
      let neighbors = fromMaybe S.empty (M.lookup n graph)
          fresh = S.filter (`S.notMember` visited) neighbors
       in go (visited <> fresh) (rest <> S.toList fresh)

-- | Given the full program call graph and a set of unused names, return
--   the members of /source/ strongly-connected components in the unused
--   subgraph — the defs a human would consider "root causes" of dead code.
--
-- A source SCC has no incoming edges from outside the SCC (but within
-- @unused@). Singletons with no unused-predecessors are sources. Members
-- of a mutual-recursion cycle whose only external callers are all
-- reachable-from-main are all reported together, since removing any one
-- does not break the dead-code status of the others.
sourceSccs :: M.Map Name (S.Set Name) -> S.Set Name -> S.Set Name
sourceSccs callGraph unusedSet =
  let callsWithinUnused n =
        S.toList (S.intersection unusedSet (fromMaybe S.empty (M.lookup n callGraph)))
      nodes = [(n, n, callsWithinUnused n) | n <- S.toList unusedSet]
      sccs = G.stronglyConnComp nodes
      -- A SCC is a source iff no member is referenced by another unused
      -- node outside the SCC. Within-SCC references are fine (that's
      -- exactly what makes it a cycle).
      isSource members =
        let mset = S.fromList members
            external = S.difference unusedSet mset
         in not $ any (\m -> any (`S.member` mset) (M.lookup m callGraph `orEmpty`)) (S.toList external)
   in S.fromList [n | scc <- sccs, let ns = G.flattenSCC scc, isSource ns, n <- ns]
  where
    orEmpty = fromMaybe S.empty

-- | Span of the identifier @n@ within a @Sig@ / @FunDef@ span. The parser
--   writes these spans so that @spanStartLine@, @spanStartCol@ point at
--   the first character of the name, so the name's span is just the first
--   @length n@ characters of that line.  Mirrored from 'Awsum.Symbols'.
nameSubSpan :: SrcSpan -> Name -> SrcSpan
nameSubSpan sp n =
  let l = spanStartLine sp
      c = spanStartCol sp
   in SrcSpan l c l (c + T.length n)
