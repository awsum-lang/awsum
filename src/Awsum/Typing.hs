-- | Simple /monomorphic/ type checker for the surface AST ('Awsum.Syntax').
--
-- MVP scope and design notes:
--   • Only two type constructors exist: @"String"@ and @"IOUnit"@.
--   • The only function type constructor is right-associative arrow @->@.
--   • No let-generalization, no unification variables, no inference beyond what is
--     written in signatures: every top-level definition must have an explicit 'Sig'.
--   • Built-ins are injected from imports: currently only @IO.Stdout.print : String -> IOUnit@.
--   • We distinguish:
--       - 'NotImported'   — a qualified name that exists only if its module was imported,
--       - 'UnknownVar'    — an unqualified name absent from the environment.
--   • We enforce @main : String -> IOUnit@.
--
-- Algorithm (per program):
--   1) Partition declarations into signatures and definitions.
--   2) Build a signature environment (ensuring no duplicates).
--   3) Validate each written type (only known TyCons are allowed).
--   4) Ensure no duplicate definitions and each def has a signature.
--   5) For each def:
--        a) check arity matches the arrow shape of its signature,
--        b) build a typing environment = {built-ins from imports} ∪ {params} ∪ {all sigs},
--        c) compute 'typeOfExpr' for the body and compare to the result type.
--   6) Verify presence and exact type of 'main'.
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
  deriving stock (Show, Eq)

prettyPrintTypeError :: TypeError -> Text
prettyPrintTypeError = show

-- | Typing environment: maps fully-qualified names to types.
--   We use 'QName' to keep the door open for qualified built-ins.
type Env = M.Map QName Type'

-- | Helper to create a local (unqualified) 'QName'.
qLocal :: Name -> QName
qLocal = QName []

-- | Populate built-ins based on the set of imports present in the file.
--   Currently only provides:
--     IO.Stdout.print : String -> IOUnit
builtinEnvFromImports :: [ImportDecl] -> Env
builtinEnvFromImports imps =
  let modLists = [toList ns | ImportDecl ns <- imps]
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
--   Extend this when you introduce new TyCons/kinds.
wellFormedType :: Type' -> Either TypeError ()
wellFormedType = \case
  TyVar _ -> Right ()
  TyCon "String" -> Right ()
  TyCon "IOUnit" -> Right ()
  TyCon n -> Left (UnknownTypeCon n)
  TyArrow a b -> wellFormedType a >> wellFormedType b

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

-- | Check a whole program against explicit signatures.
--   Returns 'Right ()' on success; otherwise a descriptive 'TypeError'.
typecheckProgram :: Program -> Either TypeError ()
typecheckProgram Program {imports, decls} = do
  -- Partition top-level decls into signatures and definitions.
  let (sigsList, defsList) = partitionEithers (mapMaybe toEither (toList decls))
      toEither = \case
        Sig n t _ -> Just (Left (n, t))
        FunDef n as e _ -> Just (Right (n, as, e))
        CommentDecl _ -> Nothing

  -- Build the signature environment; reject duplicates early.
  sigEnv <- foldM insertSig M.empty sigsList

  -- Validate every written type (no unknown TyCons).
  mapM_ (wellFormedType . snd) sigsList

  -- Ensure unique definition names (shadowing is not allowed at top level).
  foldM_ insertDefName S.empty defsList

  -- Check each definition body against its declared type.
  forM_ defsList $ \(n, args, body) -> do
    ty <- maybeToRight (MissingSignature n) (M.lookup n sigEnv)
    let (argTys, retTy) = splitArrow ty
    when (length argTys /= length args)
      $ Left (ArityMismatch n (length argTys) (length args))

    -- Build an environment visible inside the body:
    --   built-ins from imports ⊔ parameters ⊔ all top-level signatures.
    let envBuiltins = builtinEnvFromImports imports
        envParams = M.fromList [(qLocal x, t) | (x, t) <- zip args argTys]
        envTop = M.fromList [(qLocal n', t') | (n', t') <- sigsList]
        env = M.unions [envBuiltins, envParams, envTop]

    bodyTy <- typeOfExpr env body
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
typeOfExpr :: Env -> Expr -> Either TypeError Type'
typeOfExpr env = \case
  ELit (LString _) -> Right (TyCon "String")
  EVar q ->
    case M.lookup q env of
      Just t -> Right t
      Nothing ->
        case q of
          QName (_ : _) _ -> Left (NotImported q) -- looks qualified but missing import
          _ -> Left (UnknownVar q)
  EParens e ->
    typeOfExpr env e
  EApp f x -> do
    tf <- typeOfExpr env f
    case tf of
      TyArrow a b -> do
        tx <- typeOfExpr env x
        case match a tx of
          Just s -> Right (applySubst s b)
          Nothing -> Left (TypeMismatch a tx x)
      _ -> Left (NotAFunction f tf)
  -- String concatenation is only defined for (String, String) → String.
  EInfix OpConcat l r -> do
    tl <- typeOfExpr env l
    tr <- typeOfExpr env r
    if tl == TyCon "String" && tr == TyCon "String"
      then Right (TyCon "String")
      else
        -- pick the first offender for a more helpful message
        let blame = if tl /= TyCon "String" then tl else tr
         in Left (TypeMismatch (TyCon "String") blame (EInfix OpConcat l r))
