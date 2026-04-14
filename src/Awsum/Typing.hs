-- | Simple /monomorphic/ type checker for the surface AST ('Awsum.Syntax').
--
-- MVP scope and design notes:
--   • Built-in type constructors: @"String"@ and @"IOUnit"@.
--   • User-defined sum types via @type Color = Red | Green | Blue@.
--   • The only function type constructor is right-associative arrow @->@.
--   • No let-generalization, no unification variables, no inference beyond what is
--     written in signatures: every top-level definition must have an explicit 'Sig'.
--   • Built-ins are injected from imports: currently only @IO.Stdout.print : String -> IOUnit@.
--   • We enforce @main : String -> IOUnit@.
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
--   7) Verify presence and exact type of 'main'.
module Awsum.Typing
  ( typecheckProgram,
    typeOfExpr,
    TypeError (..),
    prettyPrintTypeError,
    typeErrorSpan,
  )
where

import Awsum.Syntax
import Control.Monad (foldM, foldM_)
import Data.Map.Strict qualified as M
import Data.Set qualified as S
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
  where
    showType :: Type' -> Text
    showType = \case
      TyVar n -> n
      TyCon n -> n
      TyApp f x -> showType f <> " " <> showTypeAtom x
      TyArrow a b -> showType a <> " -> " <> showType b
    showTypeAtom :: Type' -> Text
    showTypeAtom t@TyApp {} = "(" <> showType t <> ")"
    showTypeAtom t@TyArrow {} = "(" <> showType t <> ")"
    showTypeAtom t = showType t

-- | Typing environment: maps fully-qualified names to types.
--   We use 'QName' to keep the door open for qualified built-ins.
type Env = M.Map QName Type'

-- | Constructor info: type name, type parameters, field types, sibling constructors.
data ConInfo = ConInfo
  { ciTypeName :: Name,
    ciTypeParams :: [Name],
    ciFieldTypes :: [Type'],
    ciSiblings :: [Name]
  }
  deriving stock (Show, Eq)

-- | Constructor environment: maps constructor name → 'ConInfo'.
type ConEnv = M.Map Name ConInfo

-- | Helper to create a local (unqualified) 'QName'.
qLocal :: Name -> QName
qLocal = QName []

-- | Populate built-ins based on the set of imports present in the file.
--   Currently only provides:
--     IO.Stdout.print : String -> IOUnit
builtinEnvFromImports :: [ImportDecl] -> Env
builtinEnvFromImports imps =
  let modLists = [toList ns | ImportDecl _ ns _ <- imps]
      hasImport xs = elem xs modLists
      ioPrint =
        if hasImport ["IO", "Stdout"]
          then
            M.singleton
              (QName ["IO", "Stdout"] "print")
              (TyArrow (TyCon "String") (TyCon "IOUnit"))
          else mempty
   in ioPrint

-- | Flatten a right-associative arrow type into @(argument types, result type)@.
--   Example: @a -> b -> c@  ⇒  @([a, b], c)@.
splitArrow :: Type' -> ([Type'], Type')
splitArrow = go []
  where
    go acc (TyArrow a b) = go (acc <> [a]) b
    go acc t = (acc, t)

-- | Validate that a written type only mentions known constructors.
wellFormedTypeWith :: SrcSpan -> S.Set Name -> Type' -> Either TypeError ()
wellFormedTypeWith sp userTypes = \case
  TyVar _ -> Right ()
  TyCon "String" -> Right ()
  TyCon "IOUnit" -> Right ()
  TyCon n
    | S.member n userTypes -> Right ()
    | otherwise -> Left (UnknownTypeCon sp n)
  TyApp f x -> wellFormedTypeWith sp userTypes f >> wellFormedTypeWith sp userTypes x
  TyArrow a b -> wellFormedTypeWith sp userTypes a >> wellFormedTypeWith sp userTypes b

type Subst = M.Map Name Type'

applySubst :: Subst -> Type' -> Type'
applySubst s = \case
  TyVar v -> fromMaybe (TyVar v) (M.lookup v s)
  TyCon c -> TyCon c
  TyApp f x -> TyApp (applySubst s f) (applySubst s x)
  TyArrow a b -> TyArrow (applySubst s a) (applySubst s b)

compose :: Subst -> Subst -> Subst
compose s2 s1 = (applySubst s2 <$> s1) `M.union` s2

match :: Type' -> Type' -> Maybe Subst
match = go
  where
    go (TyVar v) t = Just (M.singleton v t)
    go t (TyVar v) = Just (M.singleton v t)
    go (TyCon c1) (TyCon c2)
      | c1 == c2 = Just M.empty
      | otherwise = Nothing
    go (TyApp f1 x1) (TyApp f2 x2) = do
      s1 <- go f1 f2
      s2 <- go (applySubst s1 x1) (applySubst s1 x2)
      pure (compose s2 s1)
    go (TyArrow a1 b1) (TyArrow a2 b2) = do
      s1 <- go a1 a2
      s2 <- go (applySubst s1 b1) (applySubst s1 b2)
      pure (compose s2 s1)
    go _ _ = Nothing

-- | Build the return type of a constructor given the type name and type parameters.
--   @conReturnType "Color" []@    → @TyCon "Color"@
--   @conReturnType "Lookup" ["a"]@ → @TyApp (TyCon "Lookup") (TyVar "a")@
conReturnType :: Name -> [Name] -> Type'
conReturnType tName [] = TyCon tName
conReturnType tName tvs = foldl' TyApp (TyCon tName) (map TyVar tvs)

-- | Build the full type of a constructor: @fieldType1 -> ... -> returnType@.
conType :: Name -> [Name] -> [Type'] -> Type'
conType tName tvs = foldr TyArrow (conReturnType tName tvs)

-- | Type-constructor map: type name → list of constructor names (including empty types).
type TypeConsMap = M.Map Name [Name]

-- | Build a constructor environment from @type@ declarations.
--   Returns (set of type names, constructor env, constructor value env, type-constructor map).
buildConEnv :: [Decl] -> Either TypeError (S.Set Name, ConEnv, Env, TypeConsMap)
buildConEnv decls = do
  let typeDefs = [(sp, n, tvs, cs) | TypeDecl sp n tvs cs _ <- decls]
  -- Check for duplicate type names.
  foldM_ checkDupType S.empty typeDefs
  -- Build the constructor environment.
  conEnv <- foldM insertCons M.empty typeDefs
  -- Build the value environment for constructors with proper polymorphic types.
  let conValEnv =
        M.fromList
          [ (qLocal cName, conType tName tvs flds)
          | (_sp, tName, tvs, cs) <- typeDefs,
            ConDef cName flds <- cs
          ]
      typeNames = S.fromList [n | (_sp, n, _tvs, _cs) <- typeDefs]
      typeConsMap =
        M.fromList
          [ (tName, [cName | ConDef cName _ <- cs])
          | (_sp, tName, _tvs, cs) <- typeDefs
          ]
  pure (typeNames, conEnv, conValEnv, typeConsMap)
  where
    checkDupType seen (sp, n, _tvs, _) =
      if S.member n seen
        then Left (DuplicateTypeDef sp n)
        else Right (S.insert n seen)

    insertCons m (sp, tName, tvs, cs) = do
      let conNames = [cName | ConDef cName _ <- cs]
      foldM (insertOne sp tName tvs conNames cs) m conNames

    insertOne sp tName tvs allCons cs m cName =
      if M.member cName m
        then Left (DuplicateConstructor sp cName)
        else
          let flds = [fs | ConDef cn fs <- cs, cn == cName]
           in Right (M.insert cName (ConInfo tName tvs (concat flds) allCons) m)

-- | Check a whole program against explicit signatures.
--   Returns 'Right ()' on success; otherwise a descriptive 'TypeError'.
typecheckProgram :: Program -> Either TypeError ()
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

  -- Validate every written type (no unknown TyCons).
  mapM_ (\(sp, _, t) -> wellFormedTypeWith sp userTypeNames t) sigsList

  -- Ensure unique definition names (shadowing is not allowed at top level).
  foldM_ insertDefName S.empty defsList

  -- Check each definition body against its declared type.
  forM_ defsList $ \(sp, n, args, body) -> do
    ty <- maybeToRight (MissingSignature sp n) (M.lookup n sigEnv)
    let (argTys, retTy) = splitArrow ty
    when (length argTys /= length args)
      $ Left (ArityMismatch sp n (length argTys) (length args))

    -- Build an environment visible inside the body:
    --   built-ins from imports ⊔ constructors ⊔ parameters ⊔ all top-level signatures.
    let envBuiltins = builtinEnvFromImports imports
        envParams = M.fromList [(qLocal x, t) | (x, t) <- zip args argTys]
        envTop = M.fromList [(qLocal n', t') | (_sp', n', t') <- sigsList]
        env = M.unions [envBuiltins, conValEnv, envParams, envTop]

    bodyTy <- typeOfExpr conEnv typeConsMap env body
    unless (bodyTy == retTy)
      $ Left (TypeMismatch retTy bodyTy body)

  -- Enforce presence and exact type of 'main'.
  case M.lookup "main" sigEnv of
    Nothing -> Left MainMissing
    Just ty ->
      let want = TyArrow (TyCon "String") (TyCon "IOUnit")
       in unless (ty == want) (Left (MainWrongType ty))

  Right ()
  where
    insertSig m (sp, n, t) =
      if M.member n m
        then Left (DuplicateSignature sp n)
        else Right (M.insert n t m)

    insertDefName s (sp, n, _, _) =
      if S.member n s
        then Left (DuplicateDefinition sp n)
        else Right (S.insert n s)

-- | Infer/check the type of an expression under the given environment.
--   This function /checks/ consistency; it does not invent polymorphism.
typeOfExpr :: ConEnv -> TypeConsMap -> Env -> Expr -> Either TypeError Type'
typeOfExpr conEnv tcm env = \case
  ELit _sp (LString _) -> Right (TyCon "String")
  EVar sp q ->
    case M.lookup q env of
      Just t -> Right t
      Nothing ->
        case q of
          QName (_ : _) _ -> Left (NotImported sp q) -- looks qualified but missing import
          _ -> Left (UnknownVar sp q)
  EParens _sp e ->
    typeOfExpr conEnv tcm env e
  ECon sp name ->
    case M.lookup (qLocal name) env of
      Just t -> Right t
      Nothing -> Left (UnknownConstructor sp name)
  EApp _sp f x -> do
    tf <- typeOfExpr conEnv tcm env f
    case tf of
      TyArrow a b -> do
        tx <- typeOfExpr conEnv tcm env x
        case match a tx of
          Just s -> Right (applySubst s b)
          Nothing -> Left (TypeMismatch a tx x)
      _ -> Left (NotAFunction f tf)
  -- String concatenation is only defined for (String, String) → String.
  EInfix sp OpConcat l r -> do
    tl <- typeOfExpr conEnv tcm env l
    tr <- typeOfExpr conEnv tcm env r
    if tl == TyCon "String" && tr == TyCon "String"
      then Right (TyCon "String")
      else
        -- pick the first offender for a more helpful message
        let blame = if tl /= TyCon "String" then tl else tr
         in Left (TypeMismatch (TyCon "String") blame (EInfix sp OpConcat l r))
  ECase sp scrut alts _ -> do
    scrutTy <- typeOfExpr conEnv tcm env scrut
    -- Scrutinee must be a user-defined sum type.
    tyName <- case extractTyCon scrutTy of
      Just n | M.member n tcm -> Right n
      _ -> Left (CaseOnNonSumType sp scrutTy)
    let allCons = fromMaybe [] (M.lookup tyName tcm)
    -- Compute substitution from type parameters to concrete types.
    -- E.g. for Lookup String: match (Lookup a) against (Lookup String) → {a → String}
    let scrutSubst = case anyConInfo tyName conEnv of
          Just ci ->
            let genericRetTy = conReturnType tyName (ciTypeParams ci)
             in fromMaybe M.empty (match genericRetTy scrutTy)
          Nothing -> M.empty
    -- Type-check each arm; collect arm types and covered constructors.
    (armTypes, coveredCons) <- foldM (checkArm sp env scrutSubst) ([], []) (toList alts)
    -- Exhaustiveness: every inhabited constructor must appear exactly once.
    -- A constructor is uninhabited if any of its field types (after substitution)
    -- resolves to a type with no constructors (e.g. Never).
    let missing = filter (`notElem` coveredCons) allCons
        inhabitedMissing = filter (isConInhabited conEnv tcm scrutSubst) missing
    unless (null inhabitedMissing) $ Left (NonExhaustiveCase sp tyName inhabitedMissing)
    -- All arms must agree on the result type.
    case armTypes of
      [] -> Left (NonExhaustiveCase sp tyName allCons)
      (firstTy : restTys) -> do
        forM_ restTys $ \ty ->
          unless (ty == firstTy)
            $ Left (CaseBranchTypeMismatch firstTy ty scrut)
        Right firstTy
  where
    checkArm caseSp envLocal scrutSubst (tys, cons) (CaseAlt _ (PCon cName pats) body _) = do
      -- Verify the constructor belongs to the scrutinee type.
      ci <- maybeToRight (UnknownConstructor (exprSpan body) cName) (M.lookup cName conEnv)
      -- Reject duplicate (unreachable) patterns.
      when (cName `elem` cons) $ Left (UnreachableCase caseSp cName)
      -- Reject patterns on uninhabited constructors (unreachable).
      case uninhabitedFieldType conEnv tcm scrutSubst cName of
        Just emptyTy -> Left (UnreachableCaseUninhabited caseSp cName emptyTy)
        Nothing -> pass
      -- Bind pattern variables from constructor fields.
      let fieldTys = map (applySubst scrutSubst) (ciFieldTypes ci)
          bindings = patternBindings conEnv pats fieldTys
          envWithBindings = M.union (M.fromList [(qLocal n, t) | (n, t) <- bindings]) envLocal
      bodyTy <- typeOfExpr conEnv tcm envWithBindings body
      pure (tys <> [bodyTy], cons <> [cName])
    checkArm _ _ _ _ CaseAlt {} =
      Left (TELowering "only constructor patterns are supported")

-- | Extract variable bindings from patterns and their corresponding types.
--   Recurses into nested constructor patterns to bind deeply nested variables.
patternBindings :: ConEnv -> [Pattern] -> [Type'] -> [(Name, Type')]
patternBindings conEnv pats tys = concatMap go (zip pats tys)
  where
    go (PVar n, t) = [(n, t)]
    go (PWild, _) = []
    go (PCon cName innerPats, ty) =
      case M.lookup cName conEnv of
        Nothing -> []
        Just ci ->
          let genericRetTy = conReturnType (ciTypeName ci) (ciTypeParams ci)
              innerSubst = fromMaybe M.empty (match genericRetTy ty)
              fieldTys = map (applySubst innerSubst) (ciFieldTypes ci)
           in patternBindings conEnv innerPats fieldTys

-- | Extract the type constructor name from a type (peeling off TyApp).
extractTyCon :: Type' -> Maybe Name
extractTyCon (TyCon n) = Just n
extractTyCon (TyApp f _) = extractTyCon f
extractTyCon _ = Nothing

-- | Get 'ConInfo' for any constructor of the given type.
anyConInfo :: Name -> ConEnv -> Maybe ConInfo
anyConInfo tyName conEnv =
  find (\ci -> ciTypeName ci == tyName) (M.elems conEnv)

-- | A constructor is inhabited if all its field types (after substitution) are inhabited.
--   A type is uninhabited if it has no constructors (e.g. @type Never@),
--   or all its constructors require an uninhabited field (e.g. @Box Never@).
isConInhabited :: ConEnv -> TypeConsMap -> Subst -> Name -> Bool
isConInhabited conEnv tcm subst cName =
  case M.lookup cName conEnv of
    Nothing -> True
    Just ci ->
      let fieldTys = map (applySubst subst) (ciFieldTypes ci)
       in all (isTypeInhabited conEnv tcm) fieldTys

-- | If a constructor has an uninhabited field type, return that type.
uninhabitedFieldType :: ConEnv -> TypeConsMap -> Subst -> Name -> Maybe Type'
uninhabitedFieldType conEnv tcm subst cName =
  case M.lookup cName conEnv of
    Nothing -> Nothing
    Just ci ->
      let fieldTys = map (applySubst subst) (ciFieldTypes ci)
       in find (not . isTypeInhabited conEnv tcm) fieldTys

-- | A type is inhabited unless it resolves to a user-defined type whose
--   constructors all require an uninhabited field (recursively).
--   @type Never@ → uninhabited (0 constructors).
--   @Box Never@  → uninhabited (Box requires Never which is uninhabited).
isTypeInhabited :: ConEnv -> TypeConsMap -> Type' -> Bool
isTypeInhabited conEnv tcm ty =
  case extractTyCon ty of
    Just n -> case M.lookup n tcm of
      Nothing -> True -- built-in, inhabited
      Just [] -> False -- 0 constructors
      Just cons ->
        -- Compute substitution for this concrete type (e.g. Box Never → {a → Never})
        let subst = case anyConInfo n conEnv of
              Just ci ->
                let genericRetTy = conReturnType n (ciTypeParams ci)
                 in fromMaybe M.empty (match genericRetTy ty)
              Nothing -> M.empty
         in any (isConInhabited conEnv tcm subst) cons
    Nothing -> True
