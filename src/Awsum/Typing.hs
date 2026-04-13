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
    UnknownVar QName
  | -- | Application where callee does not have an arrow type.
    NotAFunction Expr Type'
  | -- | (expected, actual, in expression)
    TypeMismatch Type' Type' Expr
  | -- | (function name, expected #args, actual #args)
    ArityMismatch Name Int Int
  | -- | Top-level definition without a signature.
    MissingSignature Name
  | DuplicateSignature Name
  | DuplicateDefinition Name
  | -- | A 'TyCon' the checker does not recognize.
    UnknownTypeCon Name
  | MainMissing
  | -- | 'main' present but with a different type.
    MainWrongType Type'
  | -- | Qualified name used without importing its module path.
    NotImported QName
  | -- | Lowering error
    TELowering Text
  | -- | Duplicate type name in @type@ declarations.
    DuplicateTypeDef Name
  | -- | Constructor name used in multiple @type@ declarations.
    DuplicateConstructor Name
  | -- | Constructor not defined by any @type@ declaration.
    UnknownConstructor Name
  | -- | Case expression does not cover all constructors.
    NonExhaustiveCase Name [Name]
  | -- | Arms of a case expression have different types.
    CaseBranchTypeMismatch Type' Type' Expr
  | -- | Scrutinee of case is not a sum type.
    CaseOnNonSumType Type'
  deriving stock (Show, Eq)

prettyPrintTypeError :: TypeError -> Text
prettyPrintTypeError = show

-- | Typing environment: maps fully-qualified names to types.
--   We use 'QName' to keep the door open for qualified built-ins.
type Env = M.Map QName Type'

-- | Constructor environment: maps constructor name → (type name, list of all constructor names).
type ConEnv = M.Map Name (Name, [Name])

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
wellFormedTypeWith :: S.Set Name -> Type' -> Either TypeError ()
wellFormedTypeWith userTypes = \case
  TyVar _ -> Right ()
  TyCon "String" -> Right ()
  TyCon "IOUnit" -> Right ()
  TyCon n
    | S.member n userTypes -> Right ()
    | otherwise -> Left (UnknownTypeCon n)
  TyArrow a b -> wellFormedTypeWith userTypes a >> wellFormedTypeWith userTypes b

type Subst = M.Map Name Type'

applySubst :: Subst -> Type' -> Type'
applySubst s = \case
  TyVar v -> fromMaybe (TyVar v) (M.lookup v s)
  TyCon c -> TyCon c
  TyArrow a b -> TyArrow (applySubst s a) (applySubst s b)

compose :: Subst -> Subst -> Subst
compose s2 s1 = (applySubst s2 <$> s1) `M.union` s2

match :: Type' -> Type' -> Maybe Subst
match = go
  where
    go (TyVar v) t = Just (M.singleton v t)
    go (TyCon c1) (TyCon c2)
      | c1 == c2 = Just M.empty
      | otherwise = Nothing
    go (TyArrow a1 b1) (TyArrow a2 b2) = do
      s1 <- go a1 a2
      s2 <- go (applySubst s1 b1) (applySubst s1 b2)
      pure (compose s2 s1)
    go _ _ = Nothing

-- | Build a constructor environment from @type@ declarations.
--   Returns (set of type names, constructor env, constructor value env).
buildConEnv :: [Decl] -> Either TypeError (S.Set Name, ConEnv, Env)
buildConEnv decls = do
  let typeDefs = [(n, cs) | TypeDecl n _ cs _ <- decls]
  -- Check for duplicate type names.
  foldM_ checkDupType S.empty typeDefs
  -- Build the constructor environment.
  conEnv <- foldM insertCons M.empty typeDefs
  -- Build the value environment for constructors (each constructor has the type of its parent).
  let conValEnv =
        M.fromList
          [ (qLocal cName, TyCon tName)
          | (tName, cs) <- typeDefs,
            ConDef cName _ <- toList cs
          ]
      typeNames = S.fromList (map fst typeDefs)
  pure (typeNames, conEnv, conValEnv)
  where
    checkDupType seen (n, _) =
      if S.member n seen
        then Left (DuplicateTypeDef n)
        else Right (S.insert n seen)

    insertCons m (tName, cs) = do
      let conNames = [cName | ConDef cName _ <- toList cs]
      foldM (insertOne tName conNames) m conNames

    insertOne tName allCons m cName =
      if M.member cName m
        then Left (DuplicateConstructor cName)
        else Right (M.insert cName (tName, allCons) m)

-- | Check a whole program against explicit signatures.
--   Returns 'Right ()' on success; otherwise a descriptive 'TypeError'.
typecheckProgram :: Program -> Either TypeError ()
typecheckProgram Program {imports, decls} = do
  -- 1) Build constructor environment from type declarations.
  (userTypeNames, conEnv, conValEnv) <- buildConEnv (toList decls)

  -- 2) Partition top-level decls into signatures and definitions.
  let (sigsList, defsList) = partitionEithers (mapMaybe toEither (toList decls))
      toEither = \case
        Sig n t _ -> Just (Left (n, t))
        FunDef n as e _ -> Just (Right (n, as, e))
        CommentDecl _ -> Nothing
        TypeDecl {} -> Nothing

  -- Build the signature environment; reject duplicates early.
  sigEnv <- foldM insertSig M.empty sigsList

  -- Validate every written type (no unknown TyCons).
  mapM_ (wellFormedTypeWith userTypeNames . snd) sigsList

  -- Ensure unique definition names (shadowing is not allowed at top level).
  foldM_ insertDefName S.empty defsList

  -- Check each definition body against its declared type.
  forM_ defsList $ \(n, args, body) -> do
    ty <- maybeToRight (MissingSignature n) (M.lookup n sigEnv)
    let (argTys, retTy) = splitArrow ty
    when (length argTys /= length args)
      $ Left (ArityMismatch n (length argTys) (length args))

    -- Build an environment visible inside the body:
    --   built-ins from imports ⊔ constructors ⊔ parameters ⊔ all top-level signatures.
    let envBuiltins = builtinEnvFromImports imports
        envParams = M.fromList [(qLocal x, t) | (x, t) <- zip args argTys]
        envTop = M.fromList [(qLocal n', t') | (n', t') <- sigsList]
        env = M.unions [envBuiltins, conValEnv, envParams, envTop]

    bodyTy <- typeOfExpr conEnv env body
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
    insertSig m (n, t) =
      if M.member n m
        then Left (DuplicateSignature n)
        else Right (M.insert n t m)

    insertDefName s (n, _, _) =
      if S.member n s
        then Left (DuplicateDefinition n)
        else Right (S.insert n s)

-- | Infer/check the type of an expression under the given environment.
--   This function /checks/ consistency; it does not invent polymorphism.
typeOfExpr :: ConEnv -> Env -> Expr -> Either TypeError Type'
typeOfExpr conEnv env = \case
  ELit (LString _) -> Right (TyCon "String")
  EVar q ->
    case M.lookup q env of
      Just t -> Right t
      Nothing ->
        case q of
          QName (_ : _) _ -> Left (NotImported q) -- looks qualified but missing import
          _ -> Left (UnknownVar q)
  EParens e ->
    typeOfExpr conEnv env e
  ECon name ->
    case M.lookup name conEnv of
      Just (tyName, _) -> Right (TyCon tyName)
      Nothing -> Left (UnknownConstructor name)
  EApp f x -> do
    tf <- typeOfExpr conEnv env f
    case tf of
      TyArrow a b -> do
        tx <- typeOfExpr conEnv env x
        case match a tx of
          Just s -> Right (applySubst s b)
          Nothing -> Left (TypeMismatch a tx x)
      _ -> Left (NotAFunction f tf)
  -- String concatenation is only defined for (String, String) → String.
  EInfix OpConcat l r -> do
    tl <- typeOfExpr conEnv env l
    tr <- typeOfExpr conEnv env r
    if tl == TyCon "String" && tr == TyCon "String"
      then Right (TyCon "String")
      else
        -- pick the first offender for a more helpful message
        let blame = if tl /= TyCon "String" then tl else tr
         in Left (TypeMismatch (TyCon "String") blame (EInfix OpConcat l r))
  ECase scrut alts _ -> do
    scrutTy <- typeOfExpr conEnv env scrut
    -- Scrutinee must be a user-defined sum type.
    tyName <- case scrutTy of
      TyCon n | M.member n (allTypeConstructors conEnv) -> Right n
      _ -> Left (CaseOnNonSumType scrutTy)
    let allCons = fromMaybe [] (M.lookup tyName (allTypeConstructors conEnv))
    -- Type-check each arm; collect arm types and covered constructors.
    (armTypes, coveredCons) <- foldM (checkArm env) ([], []) (toList alts)
    -- Exhaustiveness: every constructor must appear exactly once.
    let missing = filter (`notElem` coveredCons) allCons
    unless (null missing) $ Left (NonExhaustiveCase tyName missing)
    -- All arms must agree on the result type.
    case armTypes of
      [] -> Left (NonExhaustiveCase tyName allCons)
      (firstTy : restTys) -> do
        forM_ restTys $ \ty ->
          unless (ty == firstTy)
            $ Left (CaseBranchTypeMismatch firstTy ty scrut)
        Right firstTy
  where
    checkArm envLocal (tys, cons) (CaseAlt _ (PCon cName _) body _) = do
      -- Verify the constructor belongs to the scrutinee type.
      whenNothing_ (M.lookup cName conEnv) (Left (UnknownConstructor cName))
      bodyTy <- typeOfExpr conEnv envLocal body
      pure (tys <> [bodyTy], cons <> [cName])
    checkArm _ _ CaseAlt {} =
      Left (TELowering "only constructor patterns are supported")

-- | Helper: build a map from type name → list of constructor names.
allTypeConstructors :: ConEnv -> M.Map Name [Name]
allTypeConstructors conEnv =
  M.fromListWith (<>) [(tyName, [cName]) | (cName, (tyName, _)) <- M.toList conEnv]
