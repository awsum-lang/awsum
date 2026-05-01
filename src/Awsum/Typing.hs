-- | Simple /monomorphic/ type checker for the surface AST ('Awsum.Syntax').
--
-- Scope and design notes:
--   • Built-in type constructors: @"String"@ and @"IO"@ (the @Unit@ in
--     @IO Unit@ is a prelude-defined sum type, not a built-in).
--   • User-defined sum types via @type Color = Red | Green | Blue@.
--   • The only function type constructor is right-associative arrow @->@.
--   • No let-generalization, no unification variables, no inference beyond what is
--     written in signatures: every top-level definition must have an explicit 'Sig'.
--   • Platform-gated names are injected from the program type's platform
--     table ('Awsum.Program.platformTable'), filtered by the imports present
--     in the file (e.g. @IO.Stdout.print@ requires both @--program-type cli@
--     and @import IO.Stdout@).
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
    splitArrow,
    intTypeRange,
  )
where

import Awsum.BuiltIn (lookupBuiltIn)
import Awsum.HM (Subst, applySubst, collectTypeVars, flattenRow, freshenType, rowSubsume, unify)
import Awsum.Program (ProgramType, platformTable)
import Awsum.Syntax
import Control.Monad (foldM, foldM_)
import Data.Graph qualified as G
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import Data.Text qualified as T
import Numeric (showHex)
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
  | -- | A 'let' binding @let n = e in body@ where the typechecker
    --   could not synthesise a type for @e@ on its own and the
    --   user did not provide an annotation. Fields: span of the
    --   binder name, the binder, and the underlying synth error
    --   that prompted the request for an annotation. Same shape
    --   as 'AmbiguousIntLiteral' — fix is always to add the
    --   missing annotation: @let n : T = e in body@.
    --
    --   The common trigger is a @do@-block whose @<-@ steps
    --   return @Either@ with different error labels: the row-union
    --   of those errors can't be inferred bottom-up, but it can be
    --   pushed top-down through the bindings once an annotation
    --   names the expected type.
    MissingLetAnnotation SrcSpan Name TypeError
  | -- | A 'let'-binding with both a destructuring pattern on the
    --   LHS and a type ascription, e.g. @let (Tuple3 a b c) : T = e@.
    --   The ascription belongs on the right-hand side (or as the
    --   pattern's inner binders' types, when those features land);
    --   ascribing the destructured pattern as a whole is ambiguous
    --   and not currently supported. Field: span of the let
    --   binder. Fix: drop the ascription, or use a 'PVar' binder
    --   and ascribe the right-hand side.
    PatternLetAscription SrcSpan
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
  | -- | A constructor field references a type variable that is not in
    --   the type declaration's parameter list. Without this check the
    --   typechecker would silently treat the free variable as a fresh
    --   per-constructor tyvar, making the constructor unusable at any
    --   concrete type — see e.g. @type X = X a@. Span points at the
    --   offending @TyVar@ so the editor underlines just the identifier.
    UnknownTypeVariable SrcSpan Name
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
  | -- | Two or more top-level /values/ reference each other in a cycle
    --   with no function indirection. There is no fixed point —
    --   evaluating any of them demands another with no base case — so
    --   the program is semantically ill-formed. Pure user error;
    --   reported without any "compiler bug" hedging. Span points at
    --   the first member whose source location we can recover.
    MutuallyRecursiveValues SrcSpan [Name]
  | -- | A recursion shape the compiler cannot currently transform to
    --   a stack-safe form: either a call-graph cycle involving at
    --   least one 'CFunDef' that 'Awsum.Scc' did not know how to
    --   merge, or a 'CFunDef' with a non-tail self-call that
    --   'Awsum.Cps' did not rewrite. Programs landing here may well
    --   be correct — the compiler just lacks the transformation to
    --   lower them safely. Span points at the first member whose
    --   source location we can recover.
    StackUnsafeRecursion SrcSpan [Name]
  | -- | A @case@ arm ascribes a pattern to a type that is not one of
    --   the row's labels — e.g. @(n : Bool)@ inside a @case x of …@
    --   where @x : (Int32 | String)@. The first 'Type'' is the
    --   ascribed type (the user's claim), the second is the scrutinee
    --   row (the universe of valid labels).
    RowLabelNotInScrut SrcSpan Type' Type'
  | -- | A @case@ on a structural-sum scrutinee does not exhaust every
    --   alternative of the row. Carries the labels that have no
    --   covering arm; the row itself sets the universe so the user can
    --   tell what was expected. Mirrors 'NonExhaustiveCase' for nominal
    --   sums.
    NonExhaustiveRow SrcSpan [Type'] Type'
  | -- | A wildcard (@_@) or variable pattern was used at the top of a
    --   @case@ arm whose scrutinee is a structural sum. Catch-all
    --   patterns on rows are forbidden by design — exhaustiveness on
    --   structural sums is a load-bearing invariant of the language.
    RowCatchAllPattern SrcSpan
  | -- | The same row label has more than one covering @case@ arm,
    --   making the second arm unreachable. Carries the duplicated
    --   label so the diagnostic can name it. Mirrors 'UnreachableCase'
    --   for nominal sums.
    DuplicateRowArm SrcSpan Type'
  | -- | A constructor pattern in a row-case names a constructor whose
    --   owning type is not one of the scrutinee row's labels. Carries
    --   the constructor's source span, the constructor name, and the
    --   scrutinee row so the diagnostic can show which labels were on
    --   the table. Distinct from 'RowLabelNotInScrut' (the PAscribe
    --   analogue).
    RowLabelNotForConstructor SrcSpan Name Type'
  | -- | A lambda was used in a synthesis position — i.e. one where
    --   surrounding context does not provide an expected arrow type.
    --   The expected-type-driven check in 'checkExpr' is the only
    --   place that can give a lambda a type.
    LambdaInSynthesisPosition SrcSpan
  | -- | A 'do' block was used in a synthesis position. Like lambdas,
    --   'do' has no synthesis form — it desugars through 'bindEither'
    --   against the surrounding expected type.
    DoInSynthesisPosition SrcSpan
  | -- | The scrutinee of a 'do' bind statement (the right-hand side of
    --   @x <- e@) does not have an 'Either' type. The current
    --   desugaring is hardcoded to 'bindEither', so any other shape
    --   means the user wrote a 'do' block in a context the compiler
    --   does not know how to translate.
    DoBindNonEither SrcSpan Type'
  | -- | A 'do' block does not end with an expression — its last
    --   statement is a bind or a let, leaving the block without a
    --   well-typed result.
    DoBlockMissingResult SrcSpan
  | -- | A lambda has more parameters than the expected arrow type
    --   provides. Carries the lambda's span, the expected type, and
    --   the lambda's parameter count.
    LambdaShapeMismatch SrcSpan Type' Int
  | -- | The /row tag collision check/: two distinct row labels in this
    --   program canonicalise to the same 32-bit FNV-1a hash, so the
    --   runtime would silently confuse one for the other on row-case
    --   dispatch. Carries the two colliding labels, the shared
    --   'Word32' tag, and (when resolvable from the head 'TyCon' name)
    --   the 'SrcSpan' of the second label's @type@ declaration —
    --   that's what the user would actually rename to fix the
    --   collision, so 'typeErrorSpan' prefers it over the labels'
    --   usage spans. The message names both labels regardless.
    RowTagCollision Type' Type' Word32 (Maybe SrcSpan)
  deriving stock (Show, Eq)

-- | If @e@ is a fully-applied constructor expression
--   @ECon name `EApp` arg1 `EApp` arg2 …@, return the constructor
--   name and its argument list. Walks left-associated 'EApp' chains
--   and peels 'EParens'. Returns 'Nothing' for any other shape.
collectConApp :: Expr -> Maybe (Name, [Expr])
collectConApp = go []
  where
    go acc (EApp _ f x) = go (x : acc) f
    go acc (EParens _ inner) = go acc inner
    go acc (ECon _ n) = Just (n, acc)
    go _ _ = Nothing

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
  MissingLetAnnotation sp _ _ -> Just sp
  PatternLetAscription sp -> Just sp
  Shadowing sp _ -> Just sp
  ReferencingIgnored sp _ -> Just sp
  ReferencingIgnoredTypeVar sp _ -> Just sp
  UnnamedTypeParameter sp -> Just sp
  DuplicateTypeParameter sp _ -> Just sp
  UnknownTypeVariable sp _ -> Just sp
  UnnamedType sp -> Just sp
  UnnamedConstructor sp -> Just sp
  ReferencingIgnoredConstructor sp _ _ -> Just sp
  UnknownBuiltIn sp _ -> Just sp
  BuiltInTypeMismatch sp _ _ _ _ -> Just sp
  MutuallyRecursiveValues sp _ -> Just sp
  StackUnsafeRecursion sp _ -> Just sp
  RowLabelNotInScrut sp _ _ -> Just sp
  NonExhaustiveRow sp _ _ -> Just sp
  RowCatchAllPattern sp -> Just sp
  DuplicateRowArm sp _ -> Just sp
  RowLabelNotForConstructor sp _ _ -> Just sp
  LambdaInSynthesisPosition sp -> Just sp
  DoInSynthesisPosition sp -> Just sp
  DoBindNonEither sp _ -> Just sp
  DoBlockMissingResult sp -> Just sp
  LambdaShapeMismatch sp _ _ -> Just sp
  RowTagCollision l1 l2 _ mDeclSp ->
    -- Span priority: the second label's @type@ declaration (what the
    -- user would actually rename) → the second label's usage site →
    -- the first label's usage site → 'Nothing'. The decl-span lookup
    -- happens at error-construction time in 'Awsum.ElaborateLower'
    -- where the program-level type-name table is in scope; here we
    -- just pick the best available span. The labels arrive in
    -- pattern-order from 'buildRowAltsM', so the second label is the
    -- later-introduced one — that's the one to point at when we have
    -- to fall back from a missing decl span.
    --
    -- 'Eq SrcSpan' is uniformly @True@ to keep AST equality
    -- position-blind, so the @noSpan@ test compares underlying ints.
    let realSp sp =
          if spanStartLine sp
            == 0
            && spanStartCol sp
            == 0
            && spanEndLine sp
            == 0
            && spanEndCol sp
            == 0
            then Nothing
            else Just sp
     in case mDeclSp of
          Just sp -> Just sp
          Nothing -> case realSp (typeSpan l2) of
            Just sp -> Just sp
            Nothing -> realSp (typeSpan l1)

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
  MainWrongType ty -> "Wrong type for 'main': expected String -> IO Unit, got " <> showType ty
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
  MissingLetAnnotation _ n _underlying ->
    "Cannot infer the type of let-binding '"
      <> n
      <> "'. Add an explicit type annotation: `let "
      <> n
      <> " : <type> = …`."
  PatternLetAscription _ ->
    "Type ascription on a destructuring let-binding is not supported. Drop the ascription and rely on the right-hand side's type, or use a single-name binder (`let n : T = e`) and destructure inside the body."
  Shadowing _ n -> "Shadowing is not allowed: '" <> n <> "' is already bound in an enclosing scope"
  ReferencingIgnored _ n ->
    "Cannot reference '" <> n <> "': identifiers starting with '_' are marked as intentionally unused"
  ReferencingIgnoredTypeVar _ n ->
    "Cannot reference type parameter '" <> n <> "': identifiers starting with '_' are marked as intentionally unused"
  UnnamedTypeParameter _ ->
    "Type parameter must have a name; use '_a' (or similar) to mark one as intentionally unused"
  DuplicateTypeParameter _ n ->
    "Duplicate type parameter: '" <> n <> "' is already declared in this type"
  UnknownTypeVariable _ n ->
    "Unknown type variable: '" <> n <> "' is not declared as a type parameter"
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
  MutuallyRecursiveValues _ names ->
    "Mutually recursive top-level values cannot be evaluated: "
      <> T.intercalate ", " names
      <> ". The values reference each other in a cycle with no base case, "
      <> "so there is no computable result."
  StackUnsafeRecursion _ names ->
    "Awsum cannot guarantee stack safety for this program. The recursion "
      <> "involving "
      <> T.intercalate ", " names
      <> " uses a shape the compiler does not currently transform to a "
      <> "stack-safe form. If you believe this is a bug, please open an "
      <> "issue on GitHub with a minimal example."
  RowLabelNotInScrut _ ascr scrut ->
    "Pattern ascribes type "
      <> showType ascr
      <> ", which is not one of the alternatives of the scrutinee row "
      <> showType scrut
  NonExhaustiveRow _ missing scrut ->
    "Non-exhaustive case on structural sum "
      <> showType scrut
      <> ": missing alternative"
      <> (if length missing > 1 then "s " else " ")
      <> T.intercalate ", " (map showType missing)
  RowCatchAllPattern _ ->
    "Wildcard / variable patterns are not allowed at the top of a "
      <> "case arm whose scrutinee is a structural sum. Each alternative "
      <> "must be matched explicitly with '(x : T)' for the corresponding "
      <> "label — exhaustiveness without catch-all is a load-bearing "
      <> "invariant of the language."
  DuplicateRowArm _ ty ->
    "Duplicate case arm: alternative "
      <> showType ty
      <> " is already covered by an earlier arm in this case."
  RowLabelNotForConstructor _ cName scrut ->
    "Constructor '"
      <> cName
      <> "' is not in any alternative of the structural sum "
      <> showType scrut
      <> "."
  LambdaInSynthesisPosition _ ->
    "A lambda expression needs an expected arrow type from the "
      <> "surrounding context. Use it as an argument to a function "
      <> "whose parameter is a function type, or in another position "
      <> "where its type is fixed."
  DoInSynthesisPosition _ ->
    "A 'do' block needs an expected type from the surrounding context. "
      <> "Use it as the body of a definition with an explicit signature, "
      <> "or as an argument whose expected type is known."
  DoBindNonEither _ ty ->
    "The right-hand side of '<-' in a 'do' block must produce an "
      <> "'Either e a' value, but its type is "
      <> showType ty
      <> "."
  DoBlockMissingResult _ ->
    "A 'do' block must end with an expression that produces the "
      <> "result; the final statement here is a bind ('<-') or 'let'."
  LambdaShapeMismatch _ expected nParams ->
    "Lambda with "
      <> show nParams
      <> " parameter(s) cannot be checked against expected type "
      <> showType expected
      <> "."
  RowTagCollision lbl1 lbl2 tag _ ->
    "Row tag collision: labels "
      <> showType lbl1
      <> " and "
      <> showType lbl2
      <> " both hash to 0x"
      <> toText (showHex32 tag)
      <> ". Rename one of them so the runtime can tell row "
      <> "alternatives apart."
  where
    showType :: Type' -> Text
    showType = \case
      TyVar _ n -> n
      TyCon _ n -> n
      TyApp _ f x -> showType f <> " " <> showTypeAtom x
      TyArrow _ a b -> showType a <> " -> " <> showType b
      TyOr _ a b -> showType a <> " | " <> showType b
    showTypeAtom :: Type' -> Text
    showTypeAtom t@TyApp {} = "(" <> showType t <> ")"
    showTypeAtom t@TyArrow {} = "(" <> showType t <> ")"
    showTypeAtom t@TyOr {} = "(" <> showType t <> ")"
    showTypeAtom t = showType t

    rangeText :: Name -> Text
    rangeText n = case intTypeRange n of
      Just (lo, hi) -> show lo <> ".." <> show hi
      Nothing -> "?"

    showHex32 :: Word32 -> String
    showHex32 w =
      let s = showHex w ""
       in replicate (8 - length s) '0' <> s

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

-- | Populate platform-gated built-ins visible in this file.
--
--   Two gates combine: the /program-type/ gate picks which platform
--   table we consult ('Awsum.Program.platformTable'); the /import/
--   gate filters that table down to entries whose module path is
--   actually imported by the user code. Both must pass for a name to
--   end up in the returned environment.
--
--   Prelude-visible functions (@showInt32@, @concatString@, …) are
--   /not/ handled here — they live in 'stdlib/Prelude.aww' and reach
--   their per-target implementations through 'Awsum.BuiltIn'.
builtinEnvFromImports :: ProgramType -> [ImportDecl] -> Env
builtinEnvFromImports progType imps =
  let modLists = [toList ns | ImportDecl _ ns _ <- imps]
      hasImport xs = elem xs modLists
      visible (QName mods _) = hasImport mods
   in M.filterWithKey (\k _ -> visible k) (platformTable progType)

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
  TyCon _ "IO" -> Right ()
  TyCon _ "Int32" -> Right ()
  TyCon _ "UInt8" -> Right ()
  TyCon sp n
    | S.member n userTypes -> Right ()
    | otherwise -> Left (UnknownTypeCon sp n)
  TyApp _ f x -> wellFormedTypeWith userTypes f >> wellFormedTypeWith userTypes x
  TyArrow _ a b -> wellFormedTypeWith userTypes a >> wellFormedTypeWith userTypes b
  TyOr _ a b -> wellFormedTypeWith userTypes a >> wellFormedTypeWith userTypes b

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
--   field types. Enforces four invariants:
--
--     1. Every parameter has a name; bare @_@ is rejected ('UnnamedTypeParameter').
--     2. No two parameters share a name ('DuplicateTypeParameter').
--     3. No constructor field mentions an ignored type variable (a
--        'TyVar' whose name starts with @_@) — if the user marks a type
--        parameter as intentionally unused, they must not then turn
--        around and use it ('ReferencingIgnoredTypeVar').
--     4. Every type variable in a constructor field must appear in the
--        declaration's parameter list ('UnknownTypeVariable'). Without
--        this, @type X = X a@ would silently treat @a@ as a fresh
--        per-constructor tyvar disconnected from the type's parameters.
validateTypeParams :: SrcSpan -> [Param] -> [ConDef] -> Either TypeError ()
validateTypeParams _declSp params cons = do
  -- 1) Reject bare '_' as a type parameter name. Type parameters are
  --    always 'Param' (the parser uses 'paramBinderNoLine' which only
  --    accepts a simple name), so 'paramName' / 'paramSpan' return
  --    the user-written values directly here.
  forM_ params $ \p ->
    when (paramName p == "_") $ Left (UnnamedTypeParameter (paramSpan p))
  -- 2) Reject duplicate parameter names.
  foldM_ checkDup S.empty params
  -- 3) Reject references to ignored type variables inside constructor fields.
  --    The 'TyVar' carries its own source span, so the error points at
  --    the exact identifier rather than the whole type declaration.
  forM_ cons $ \(ConDef _ _ flds) ->
    forM_ flds checkNoIgnoredTyVar
  -- 4) Reject type variables that aren't in the parameter list.
  let declared = S.fromList (map paramName params)
  forM_ cons $ \(ConDef _ _ flds) ->
    forM_ flds (checkDeclaredTyVar declared)
  where
    checkDup seen p =
      let n = paramName p
       in if S.member n seen
            then Left (DuplicateTypeParameter (paramSpan p) n)
            else Right (S.insert n seen)

    checkNoIgnoredTyVar = \case
      TyVar sp n | "_" `T.isPrefixOf` n -> Left (ReferencingIgnoredTypeVar sp n)
      TyVar _ _ -> Right ()
      TyCon _ _ -> Right ()
      TyApp _ f x -> checkNoIgnoredTyVar f >> checkNoIgnoredTyVar x
      TyArrow _ a b -> checkNoIgnoredTyVar a >> checkNoIgnoredTyVar b
      TyOr _ a b -> checkNoIgnoredTyVar a >> checkNoIgnoredTyVar b

    -- The '_'-prefixed case is already rejected by checkNoIgnoredTyVar
    -- above with a more specific error; skip it here to avoid masking
    -- that diagnostic when both apply.
    checkDeclaredTyVar declared = \case
      TyVar _ n | "_" `T.isPrefixOf` n -> Right ()
      TyVar sp n
        | S.member n declared -> Right ()
        | otherwise -> Left (UnknownTypeVariable sp n)
      TyCon _ _ -> Right ()
      TyApp _ f x -> checkDeclaredTyVar declared f >> checkDeclaredTyVar declared x
      TyArrow _ a b -> checkDeclaredTyVar declared a >> checkDeclaredTyVar declared b
      TyOr _ a b -> checkDeclaredTyVar declared a >> checkDeclaredTyVar declared b

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
--
--   The 'preludeNames' argument names top-level definitions that come
--   from the bundled prelude — used to scope the no-shadowing rule to
--   /the same module/ a binder lives in. A user function's parameter
--   may shadow a prelude top-level (different module), and vice versa;
--   shadowing within the same module — between a function parameter
--   and a top-level of that same module, or between two enclosing
--   binders in nested case arms — stays a hard error. Pass
--   'S.empty' when there's no other module to consider (e.g.
--   verifying the prelude in isolation, where every top-level lives
--   in module @Prelude@ and no exemption applies).
typecheckProgram :: ProgramType -> Set Name -> Program -> Either TypeError [Warning]
typecheckProgram progType preludeNames Program {imports, decls} = do
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
        -- The alias form @foo = expr@ binds zero params even when the
        -- signature has arrow shape: the RHS itself carries the whole
        -- function type, and we typecheck it against the full signature.
        -- This generalizes the original @foo = BuiltIn.bar@ shape to any
        -- expression of matching arrow type (e.g. @foo = IO.Stdout.print@
        -- or @foo = otherTopLevel@), eta-expanded by 'lowerDecl'.
        isAliasForm = null args && not (null argTys)
    unless isAliasForm
      $ when (length argTys /= length args)
      $ Left (ArityMismatch sp n (length argTys) (length args))

    -- For built-in alias-form decls, check the builtin's registered type
    -- against the declared signature up-front. If they disagree, surface
    -- a dedicated 'BuiltInTypeMismatch' (with both spans) rather than the
    -- generic 'TypeMismatch' 'checkExpr' would produce below — the
    -- compiler-dev reader needs to know this is a sig-vs-table
    -- disagreement, not an ordinary user type error.
    when (isAliasForm && isBareBuiltIn body) $ case bareBuiltInRef body of
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
    let envBuiltins = builtinEnvFromImports progType imports
        namedArgs = [(p, t) | (p, t) <- zip args argTys, paramName p /= "_"]
        envParams = M.fromList [(qLocal (paramName p), t) | (p, t) <- namedArgs]
        envTop = M.fromList [(qLocal n', t') | (_sp', n', t') <- sigsList]
        envOuter = M.unions [envBuiltins, conValEnv, envTop]
        env = M.union envParams envOuter
        expectedBodyTy = if isAliasForm then ty else retTy
        -- Per-module shadow scope: a definition is in the prelude
        -- module iff its name is in 'preludeNames'. A binder inside
        -- it may shadow names from /other/ modules but not its own —
        -- 'crossModuleExempt' is exactly the set of "names from
        -- other modules" that the no-shadowing check ignores.
        allTopNames = S.fromList [n' | (_sp', n', _t') <- sigsList]
        userNames = allTopNames `S.difference` preludeNames
        crossModuleExempt =
          if n `S.member` preludeNames
            then userNames
            else preludeNames

    -- Reject shadowing: params must be unique and must not collide with
    -- any already-visible name from the same module (constructor, import,
    -- same-module top-level signature). Cross-module top-levels are
    -- exempt — see 'crossModuleExempt'.
    checkNoShadow envOuter crossModuleExempt [(paramSpan p, paramName p) | (p, _) <- namedArgs]

    checkExpr conEnv typeConsMap crossModuleExempt env expectedBodyTy body

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

-- | Entry-point check: verify the program declares @main : String -> IO Unit@.
--   Called only from @build@/@run@ — modules without @main@ (libraries,
--   @Prelude.aww@) pass 'typecheckProgram' but fail here when an executable
--   is requested.
requireMain :: Program -> Either TypeError ()
requireMain Program {decls} =
  case listToMaybe [t | Sig _ "main" t _ <- toList decls] of
    Nothing -> Left MainMissing
    Just ty ->
      let want = TyArrow noSpan (TyCon noSpan "String") (TyApp noSpan (TyCon noSpan "IO") (TyCon noSpan "Unit"))
       in unless (ty == want) (Left (MainWrongType ty))

-- | Reject a fresh list of binders if any of them are already in scope or
--   duplicate each other. Used for function parameters and for the variables
--   introduced by a single case-arm pattern. Each binder carries its own span
--   so the error points exactly at the shadowing identifier.
--
--   The 'crossModuleExempt' set names top-level definitions from /other/
--   modules — currently this is the prelude when we're checking a user
--   function, or the user-defined names when we're checking a prelude
--   function. A binder may shadow a name in this exempt set without
--   triggering a 'Shadowing' error. Within a module the rule stays
--   strict: a parameter or pattern variable cannot collide with another
--   top-level definition of the same module, with an enclosing parameter,
--   or with another binder in the same form. Built-ins live under
--   qualified names and constructor names are uppercase, so they can't
--   collide with lowercase binders regardless of exemption.
checkNoShadow :: Env -> Set Name -> [(SrcSpan, Name)] -> Either TypeError ()
checkNoShadow env crossModuleExempt = foldM_ addOne env
  where
    addOne acc (sp, n)
      | M.member (qLocal n) acc && not (S.member n crossModuleExempt) =
          Left (Shadowing sp n)
      | otherwise =
          Right (M.insert (qLocal n) (TyCon noSpan "<binder>") acc)

-- | Check that an expression has the given expected type.
--
-- Used at the /boundary/ where the expected type is known — currently the
-- body of a top-level definition checked against its declared return type.
-- This is where 'LInt' literals get their type: they have no synthesis form
-- (no defaulting), so they must appear in a context that fixes the type.
-- | Split @TyArrow a (TyArrow b … (TyArrow z r))@ into
--   @([a, b, …, z], r)@, taking the first @n@ argument types. Returns
--   'Nothing' if the type does not have at least @n@ arrows.
zipParamsToArrow :: Type' -> Int -> Maybe ([Type'], Type')
zipParamsToArrow t 0 = Just ([], t)
zipParamsToArrow (TyArrow _ a b) n = do
  (rest, r) <- zipParamsToArrow b (n - 1)
  Just (a : rest, r)
zipParamsToArrow _ _ = Nothing

-- | Typecheck a 'do'-block against an expected type. The desugaring
--   target is 'bindEither', so the block's overall type must be
--   'Either e a'. Each @x <- e@ runs 'e' under the
--   environment built so far, requires its type to be 'Either e' a''
--   for some 'e'' (subsumable into the overall row), and binds 'x' at
--   'a''. The terminal expression is checked against the overall
--   expected type.
checkDoBlock :: ConEnv -> TypeConsMap -> Set Name -> Env -> SrcSpan -> Type' -> [DoStmt] -> Either TypeError ()
checkDoBlock conEnv tcm crossExempt env sp expected = goStmts env
  where
    goStmts _ [] = Left (DoBlockMissingResult sp)
    goStmts envCur [DoExpr _ e] = checkExpr conEnv tcm crossExempt envCur expected e
    goStmts envCur (DoBind bsp pat e : rest) = do
      tx <- typeOfExpr conEnv tcm envCur e
      payload <- case tx of
        TyApp _ (TyApp _ (TyCon _ "Either") _err) ok -> Right ok
        _ -> Left (DoBindNonEither bsp tx)
      checkNoShadow envCur crossExempt (collectPatternVars [pat])
      let bindings = patternBindings conEnv [pat] [payload]
          envNext = M.union (M.fromList [(qLocal n, t) | (n, t) <- bindings]) envCur
      goStmts envNext rest
    goStmts envCur (DoLet lsp pat mAnnot e : rest) = do
      when (notPVarPat pat && isJust mAnnot)
        $ Left (PatternLetAscription lsp)
      ty <- case mAnnot of
        Just t -> do
          checkExpr conEnv tcm crossExempt envCur t e
          Right t
        Nothing -> case typeOfExpr conEnv tcm envCur e of
          Right t -> Right t
          Left err -> Left (MissingLetAnnotation lsp (patternBinderName pat) err)
      checkNoShadow envCur crossExempt (collectPatternVars [pat])
      let bindings = patternBindings conEnv [pat] [ty]
          envNext = M.union (M.fromList [(qLocal n, t) | (n, t) <- bindings]) envCur
      goStmts envNext rest
    -- Bare expression in a non-final position: with the hardcoded-
    -- Either desugar there is no analogue to '>>' (would need a Unit
    -- in the row), so reject up front.
    goStmts _ (DoExpr esp _ : _ : _) = Left (DoBlockMissingResult esp)

checkExpr :: ConEnv -> TypeConsMap -> Set Name -> Env -> Type' -> Expr -> Either TypeError ()
checkExpr conEnv tcm crossExempt env expected = \case
  -- Lambda: split @expected@ into @arg → result@ pairs, bind each
  -- parameter at the corresponding argument type, then check the
  -- body against the residual result type. The body may itself be
  -- another lambda — we walk the arrow chain rather than handling
  -- one parameter at a time, so multi-parameter lambdas like
  -- @\\a b -> e@ split correctly against @A -> B -> R@.
  ELam sp params body -> do
    (paramTypes, resultTy) <- case zipParamsToArrow expected (length params) of
      Just split -> Right split
      Nothing -> Left (LambdaShapeMismatch sp expected (length params))
    -- Reject parameters that shadow existing bindings.
    checkNoShadow env crossExempt [(s, n) | Param s n <- params]
    let bindings = zip (map paramName params) paramTypes
        env' = M.union (M.fromList [(qLocal n, t) | (n, t) <- bindings]) env
    checkExpr conEnv tcm crossExempt env' resultTy body
  -- 'do'-blocks desugar to a chain of 'bindEither' calls whose
  -- trailing expression is the user's verbatim (typically a
  -- 'pureEither' application); we typecheck them by recursing on
  -- the desugared form and then erasing the EDo node by overwriting
  -- the body in 'lowerExpr' (the desugar is also done there). Here
  -- we just check the statements one by one, threading bindings
  -- into scope.
  EDo sp stmts -> checkDoBlock conEnv tcm crossExempt env sp expected stmts
  -- 'let pat = e in body' (or 'let pat : T = e in body'): if the
  -- user supplied an annotation we check @e@ against it; otherwise
  -- we synthesise @e@'s type and wrap any synth failure in
  -- 'MissingLetAnnotation'. Either way, @body@ is checked against
  -- the surrounding @expected@ so a bare integer literal as the
  -- body (or inside it) still gets the right concrete type.
  -- No-shadowing honours @crossExempt@ so prelude-shadowing rules
  -- apply consistently. Non-'PVar' patterns are rewritten to
  -- 'ECase' by 'Awsum.Desugar' before typecheck — this clause
  -- only sees 'PVar' / 'PWild' bindings.
  ELet lsp pat mAnnot e body -> do
    when (notPVarPat pat && isJust mAnnot)
      $ Left (PatternLetAscription lsp)
    te <- case mAnnot of
      Just t -> do
        checkExpr conEnv tcm crossExempt env t e
        Right t
      Nothing -> case typeOfExpr conEnv tcm env e of
        Right t -> Right t
        Left err -> Left (MissingLetAnnotation lsp (patternBinderName pat) err)
    checkNoShadow env crossExempt (collectPatternVars [pat])
    let bindings = patternBindings conEnv [pat] [te]
        envNext = M.union (M.fromList [(qLocal n, t) | (n, t) <- bindings]) env
    checkExpr conEnv tcm crossExempt envNext expected body
  ELit sp (LInt n) ->
    case expected of
      TyCon _ tyName
        | Just (lo, hi) <- intTypeRange tyName -> checkIntRange sp n tyName lo hi
      -- D.1: implicit injection — a bare integer literal in a row
      -- position resolves to the row's unique integer-typed alternative.
      -- If the row has zero or several integer labels we can't pick a
      -- type, and 'AmbiguousIntLiteral' / 'TypeMismatch' fire.
      TyOr {} -> case rowIntLabel expected of
        Just (tyName, lo, hi) -> checkIntRange sp n tyName lo hi
        Nothing -> Left (TypeMismatch expected (TyCon noSpan "<integer literal>") (ELit sp (LInt n)))
      _ -> Left (TypeMismatch expected (TyCon noSpan "<integer literal>") (ELit sp (LInt n)))
  EParens _sp e -> checkExpr conEnv tcm crossExempt env expected e
  -- Bidirectional check on @case@ scrutinees: push the expected type
  -- into each arm body, so e.g. an @Int32@-result function can write
  -- a literal @0@ in a case arm and have it pinned to @Int32@
  -- without a separate @zero : Int32@ binding. Without this clause
  -- the case would fall through to synthesis and the literal would
  -- be reported as 'AmbiguousIntLiteral'.
  ECase sp scrut alts _ -> do
    void
      $ caseArms conEnv tcm crossExempt env sp scrut alts
      $ \envArm body -> checkExpr conEnv tcm crossExempt envArm expected body
  -- Bidirectional check at constructor applications: when the
  -- enclosing context fixes a concrete return type, match it against
  -- the constructor's generic return shape and propagate the
  -- resulting substitution into each field's check. Without this,
  -- @Right 1 : Either ErrorA Int32@ can't typecheck — the integer
  -- literal would be checked against a freshened tyvar @b$N@ instead
  -- of @Int32@.
  e@(EApp {})
    | Just (cName, args) <- collectConApp e,
      Just ci <- M.lookup cName conEnv,
      length args == length (ciFieldTypes ci) -> do
        let genericRetTy = conReturnType (ciTypeName ci) (ciTypeParams ci)
            freshGenericRetTy = freshenType "$check" genericRetTy
            freshFieldTys = map (freshenType "$check") (ciFieldTypes ci)
        case unify freshGenericRetTy expected of
          Right s ->
            let fieldExpected = map (applySubst s) freshFieldTys
             in zipWithM_ (checkExpr conEnv tcm crossExempt env) fieldExpected args
          Left _ -> do
            actual <- typeOfExpr conEnv tcm env e
            unless (rowSubsume expected actual)
              $ Left (TypeMismatch expected actual e)
  -- Non-constructor application: prefer the existing synth-and-
  -- subsume path; on failure, fall back to a bidirectional spine-
  -- based check that pushes @expected@ into the argument positions.
  -- The fallback is what lets a bare integer literal flow through a
  -- polymorphic call site like @apply (\n -> n) 42 : Int32@ — the
  -- forward unify from the result type pins @apply@'s @a@ tyvar to
  -- @Int32@, which the bare literal would otherwise be checked
  -- against an unresolved tyvar and rejected. Cases the forward
  -- path already accepts (most polymorphic uses with named arguments)
  -- continue to take that branch unchanged.
  e@(EApp {}) ->
    case typeOfExpr conEnv tcm env e of
      Right actual | rowSubsume expected actual -> Right ()
      _ -> do
        let (appHead, spineArgs) = appSpine e
        tHead <- typeOfExpr conEnv tcm env appHead
        case zipParamsToArrow tHead (length spineArgs) of
          Just (argTys, resultTy) -> do
            s0 <- unifyOrSubsume expected resultTy e
            foldM_ (checkArgStep conEnv tcm env) s0 (zip argTys spineArgs)
          Nothing -> do
            actual <- typeOfExpr conEnv tcm env e
            unless (rowSubsume expected actual)
              $ Left (TypeMismatch expected actual e)
  e -> do
    actual <- typeOfExpr conEnv tcm env e
    -- Boundary acceptance: equality is too strict once 'TyOr' enters
    -- the picture. 'rowSubsume' is the asymmetric relation — implicit
    -- injection extended through nominal heads — that lets
    -- @Left ErrA : Either ErrA r@ flow into @Either (ErrA | ErrB) Int32@
    -- without explicit wrapping. For non-row expected types it falls
    -- back to structural equality (free tyvars on either side accept
    -- anything, which preserves the prior behaviour for polymorphic
    -- constructor instantiation).
    unless (rowSubsume expected actual)
      $ Left (TypeMismatch expected actual e)
  where
    checkIntRange sp n tyName lo hi
      | n >= lo && n <= hi = Right ()
      | otherwise = Left (IntLiteralOutOfRange sp n tyName)

    -- Find the unique integer-typed label of a row, if there is one.
    -- Used by 'checkExpr ELit' to resolve a bare integer literal in a
    -- structural-sum position.
    rowIntLabel :: Type' -> Maybe (Name, Integer, Integer)
    rowIntLabel ty =
      case [(n, lo, hi) | TyCon _ n <- flattenRow ty, Just (lo, hi) <- [intTypeRange n]] of
        [single] -> Just single
        _ -> Nothing

    -- Spine of an application: peel parens and left-associated 'EApp's
    -- to recover @(head, [arg1, arg2, …])@. Used by the bidirectional
    -- 'EApp' clause above so a multi-argument call is checked against
    -- the head's full arrow chain in one step.
    appSpine :: Expr -> (Expr, [Expr])
    appSpine = go []
      where
        go acc (EApp _ f x) = go (x : acc) f
        go acc (EParens _ inner) = go acc inner
        go acc h = (h, acc)

    unifyOrSubsume expectedTy actualTy origExpr =
      case unify expectedTy actualTy of
        Right s -> Right s
        Left _ ->
          if rowSubsume expectedTy actualTy
            then Right mempty
            else Left (TypeMismatch expectedTy actualTy origExpr)

    -- Check one argument against its (possibly substituted) expected
    -- type, accumulate any new substitution learned from it, and
    -- compose it onto the running 'Subst' that subsequent arguments
    -- will see. Composition order is "new after old" so the latest
    -- bindings shadow stale ones.
    checkArgStep cEnv tcm' env' subst (argTy, arg) = do
      let argTy' = applySubst subst argTy
      sArg <- checkArgSubst cEnv tcm' env' argTy' arg
      pure (sArg <> subst)

    -- Variant of 'checkExpr' that also reports the substitution
    -- gleaned from this argument — needed so binders introduced by a
    -- polymorphic call ('a' in @apply : (a -> b) -> a -> b@) get
    -- pinned by the lambda body's identity before the next argument is
    -- checked. Lambdas recurse through their bodies; everything else
    -- goes through 'checkExpr' for validation and uses 'unify' on the
    -- synthesised type when one is available.
    checkArgSubst cEnv tcm' env' argExpected = \case
      EParens _ inner -> checkArgSubst cEnv tcm' env' argExpected inner
      ELam sp params body -> do
        (paramTypes, resultTy) <- case zipParamsToArrow argExpected (length params) of
          Just split -> Right split
          Nothing -> Left (LambdaShapeMismatch sp argExpected (length params))
        checkNoShadow env' crossExempt [(s, n) | Param s n <- params]
        let paramBindings = zip (map paramName params) paramTypes
            envInner = M.union (M.fromList [(qLocal n, t) | (n, t) <- paramBindings]) env'
        checkArgSubst cEnv tcm' envInner resultTy body
      arg -> do
        checkExpr cEnv tcm' crossExempt env' argExpected arg
        case typeOfExpr cEnv tcm' env' arg of
          Right actual -> case unify argExpected actual of
            Right s -> Right s
            Left _ -> Right mempty
          Left _ -> Right mempty

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
          ELit _ (LInt _) -> checkExpr conEnv tcm S.empty env a x $> b
          EParens _ (ELit _ (LInt _)) -> checkExpr conEnv tcm S.empty env a x $> b
          -- Lambdas and 'do' blocks have no synthesis form; they
          -- typecheck only against the expected argument type.
          ELam {} -> checkExpr conEnv tcm S.empty env a x $> b
          EParens _ ELam {} -> checkExpr conEnv tcm S.empty env a x $> b
          EDo {} -> checkExpr conEnv tcm S.empty env a x $> b
          EParens _ EDo {} -> checkExpr conEnv tcm S.empty env a x $> b
          _ -> do
            tx <- typeOfExpr conEnv tcm env x
            -- Prefer 'unify' so any tyvar-binding substitution flows
            -- into the result type ('applySubst s b'); fall back to
            -- 'rowSubsume' when 'unify' fails on row-shape mismatches
            -- the typechecker has decided are still subsumable. The
            -- fallback covers two cases: direct row injection
            -- (@ErrA ⊆ (ErrA | ErrB)@), and cross-boundary injection
            -- through a nominal head (@Maybe Bool ⊆ Maybe (Bool | Unit)@)
            -- — including nested in EApp synth, so a synthesised
            -- @describeMaybe defaultJust@ inside a @++@ chain gets
            -- accepted alongside the 'checkExpr' path that already
            -- handles the standalone form.
            case unify a tx of
              Right s -> Right (applySubst s b)
              Left _ ->
                if rowSubsume a tx
                  then Right b
                  else Left (TypeMismatch a tx x)
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
    -- Synthesis-position 'case': we have no crossExempt context here
    -- (the caller's check-mode 'checkExpr' would have one, but a
    -- nested synth-position ECase doesn't carry it through). Pattern
    -- variables in this branch are checked against the same scope
    -- they'd hit elsewhere; cross-module shadowing only applies on
    -- the check-mode path.
    armTypes <- caseArms conEnv tcm S.empty env sp scrut alts (typeOfExpr conEnv tcm)
    -- All arms must agree on the result type (via unification, not equality).
    case armTypes of
      [] -> Left (TELowering "case expression with no arms (unreachable: NonEmpty CaseAlt)")
      (firstTy : restTys) ->
        foldM
          ( \acc ty -> case unify acc ty of
              Right s -> Right (applySubst s acc)
              Left _ -> Left (CaseBranchTypeMismatch acc ty scrut)
          )
          firstTy
          restTys
  -- Lambdas have no synthesis form — they only typecheck when an
  -- expected arrow type is in scope ('checkExpr ELam'). Reaching this
  -- clause means a lambda was used in a position that requires
  -- synthesis (e.g. as the head of an application).
  ELam sp _ _ -> Left (LambdaInSynthesisPosition sp)
  -- 'let n = e in body' (or 'let n : T = e in body'): if the user
  -- provided an annotation, check @e@ against it and bind @n@ at
  -- @T@; otherwise synthesise @e@'s type and bind @n@ at the
  -- result. On synthesis failure (most commonly: a do-block whose
  -- `<-` steps return `Either` with different error labels, where
  -- the row-union can't be inferred bottom-up), wrap the
  -- underlying error in 'MissingLetAnnotation' to point the user
  -- at the right fix. No-shadowing is enforced on the check-mode
  -- path (no @crossExempt@ is in scope here, so we use 'S.empty'
  -- — same as the synth-mode 'ECase' branch above).
  ELet lsp pat mAnnot e body -> do
    when (notPVarPat pat && isJust mAnnot)
      $ Left (PatternLetAscription lsp)
    te <- case mAnnot of
      Just t -> do
        checkExpr conEnv tcm S.empty env t e
        Right t
      Nothing -> case typeOfExpr conEnv tcm env e of
        Right t -> Right t
        Left err -> Left (MissingLetAnnotation lsp (patternBinderName pat) err)
    checkNoShadow env S.empty (collectPatternVars [pat])
    let bindings = patternBindings conEnv [pat] [te]
        envNext = M.union (M.fromList [(qLocal n, t) | (n, t) <- bindings]) env
    typeOfExpr conEnv tcm envNext body
  -- 'do'-blocks also need an expected type — the desugaring goes
  -- through 'bindEither' whose return rows accumulate only when the
  -- surrounding context constrains them.
  EDo sp _ -> Left (DoInSynthesisPosition sp)

-- | Shared case-analysis: validate the scrutinee, type-check every arm
--   with the supplied body action, and verify exhaustiveness.
--
--   The body action decides how to type-check each arm body — currently
--   only 'typeOfExpr' (synthesise) is wired in by the inference path,
--   but the parameterisation lets a future bidirectional 'checkExpr'
--   clause push an expected type into each arm without duplicating the
--   scrutinee / pattern / exhaustiveness machinery. Wiring that
--   check-mode clause is intentionally deferred until 'checkExpr'
--   itself uses 'Awsum.HM.unify' in its catch-all fallback — pushing
--   into arms with the current equality-based fallback would reject
--   programs whose arm bodies build polymorphic constructors (e.g.
--   @Left e -> Left e@), since their synthesised types carry freshened
--   tyvars that 'unify' resolves inter-arm but @('==')@ does not.
caseArms ::
  ConEnv ->
  TypeConsMap ->
  Set Name ->
  Env ->
  SrcSpan ->
  Expr ->
  NonEmpty CaseAlt ->
  (Env -> Expr -> Either TypeError a) ->
  Either TypeError [a]
caseArms conEnv tcm crossExempt env sp scrut alts runBody = do
  scrutTy <- typeOfExpr conEnv tcm env scrut
  case scrutTy of
    -- Structural-sum scrutinee: rows have a different exhaustiveness
    -- model (PAscribe arms covering each label) and forbid catch-all
    -- patterns; dispatch to a dedicated helper.
    TyOr {} -> caseArmsRow conEnv tcm crossExempt env sp scrutTy alts runBody
    -- Nominal-sum scrutinee: existing path.
    _ -> caseArmsNominal scrutTy
  where
    caseArmsNominal scrutTy = do
      -- Scrutinee must be a user-defined sum type.
      tyName <- case extractTyCon scrutTy of
        Just n | M.member n tcm -> Right n
        _ -> Left (CaseOnNonSumType sp scrutTy)
      let allCons = fromMaybe [] (M.lookup tyName tcm)
      -- Compute substitution from type parameters to concrete types.
      -- E.g. for Lookup String: unify (Lookup a) with (Lookup String) → {a → String}
      -- Freshen generic type variables to avoid name collisions with scrutinee type variables.
      let scrutSubst = case anyConInfo tyName conEnv of
            Just ci ->
              let genericRetTy = conReturnType tyName (ciTypeParams ci)
                  freshGenericRetTy = freshenType "$scrut" genericRetTy
               in fromRight mempty (unify freshGenericRetTy scrutTy)
            Nothing -> mempty
      -- Type-check each arm; collect arm results and covered patterns.
      -- We track full patterns (not just constructor names) to handle nested patterns correctly.
      (armResults, coveredPatterns) <- foldM (handleArm sp env scrutSubst) ([], []) (toList alts)
      -- Exhaustiveness: every inhabited constructor must appear at least once.
      -- For simple patterns (no nesting), each constructor should appear exactly once.
      let topLevelCons = [cName | (cName, _) <- coveredPatterns]
          missing = filter (`notElem` topLevelCons) allCons
          inhabitedMissing = filter (isConInhabited conEnv tcm S.empty scrutSubst) missing
      unless (null inhabitedMissing) $ Left (NonExhaustiveCase sp tyName inhabitedMissing)
      -- Recursive exhaustiveness: for each top-level constructor that
      -- appears, check that the column of inner-pattern fields exhausts
      -- the constructor's field types. Without this, @case x of Right
      -- (Just _) -> …; Left _ -> …@ would be silently accepted at type
      -- 'Either e (Maybe a)' and crash at runtime on @Right Nothing@ —
      -- because the top-level @Right@/@Left@ are both covered but the
      -- nested @Maybe@ has only @Just@.
      let perCon = M.fromListWith (<>) [(c, [fields]) | (c, fields) <- coveredPatterns]
      forM_ (M.toList perCon) $ \(cName, armsFields) ->
        case M.lookup cName conEnv of
          Just ci | not (null (ciFieldTypes ci)) -> do
            -- The freshening suffix must match the one used when
            -- 'scrutSubst' was built ('"$scrut"'), or the
            -- substitution's keys won't line up with these field
            -- types and the apply silently no-ops.
            let freshFieldTys = map (freshenType "$scrut") (ciFieldTypes ci)
                fieldTys = map (applySubst scrutSubst) freshFieldTys
                columns = transpose armsFields
            zipWithM_ (checkPatternColumnCovers sp conEnv tcm) fieldTys columns
          _ -> Right ()
      pure armResults

    handleArm caseSp envLocal scrutSubst (results, patterns) (CaseAlt _ (PCon patSp cName pats) body _) = do
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
      checkNoShadow envLocal crossExempt (collectPatternVars pats)
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
      result <- runBody envWithBindings body
      pure (results <> [result], patterns <> [currentPattern])
    handleArm _ _ _ _ CaseAlt {} =
      Left (TELowering "only constructor patterns are supported")

-- | Specialised case-arm handling for structural-sum scrutinees. A row
--   case accepts 'PAscribe' arms (one per row label, exhaustive) and
--   'PCon' arms whose owning type is one of the row's nominal labels;
--   'PVar' and 'PWild' on a row scrutinee are rejected with dedicated
--   errors. The user matches each alternative as @(x : T)@ and may then
--   destructure inside the arm body.
--
--   The membership check (the ascribed type is a label of the
--   scrutinee row) and the exhaustiveness check (every label has a
--   covering arm) live here; the underlying pattern-binding mechanics
--   reuse 'patternBindings' so nested constructor patterns inside the
--   inner of 'PAscribe' work the same as in nominal arms.
caseArmsRow ::
  ConEnv ->
  TypeConsMap ->
  Set Name ->
  Env ->
  SrcSpan ->
  Type' ->
  NonEmpty CaseAlt ->
  (Env -> Expr -> Either TypeError a) ->
  Either TypeError [a]
caseArmsRow conEnv tcm crossExempt env sp scrutTy alts runBody = do
  (results, ascribed, perLabelConArms) <-
    foldM handleRowArm ([], [], M.empty) (toList alts)
  let missing = filter (`notExhaust` (ascribed, perLabelConArms)) labels
  unless (null missing) $ Left (NonExhaustiveRow sp missing scrutTy)
  -- Recursive inner-pattern coverage: for each label covered by 'PCon'
  -- arms, every constructor of the nominal type must appear, and the
  -- merged inner-pattern lists must in turn cover the substituted
  -- field types.
  forM_ (M.toList perLabelConArms) $ uncurry checkLabelConCoverage
  pure results
  where
    labels = flattenRow scrutTy

    notExhaust label (ascribedSet, perLabelConArms) = case label of
      TyVar _ _ -> False -- open row tail, no obligation
      _ ->
        notElem label ascribedSet
          && not (label `M.member` perLabelConArms)

    -- Locate the row label whose head 'TyCon' matches @tyName@.
    findLabel tyName =
      find (\l -> extractTyCon l == Just tyName) labels

    handleRowArm (results, ascribed, perCon) (CaseAlt _ pat body _) = case pat of
      PAscribe patSp inner ascrTy -> do
        unless (ascrTy `elem` labels)
          $ Left (RowLabelNotInScrut patSp ascrTy scrutTy)
        when (ascrTy `elem` ascribed)
          $ Left (DuplicateRowArm patSp ascrTy)
        when (ascrTy `M.member` perCon)
          $ Left (DuplicateRowArm patSp ascrTy)
        rejectIgnoredConstructor conEnv inner
        checkNoShadow env crossExempt (collectPatternVars [inner])
        -- Bind the inner pattern with the ascribed type — that is the
        -- key semantic difference from a nominal arm: 'n' in
        -- @case x of (n : Int32) -> …@ is bound at type 'Int32', not
        -- at the scrutinee's union type.
        let bindings = patternBindings conEnv [inner] [ascrTy]
            envWithBindings = M.union (M.fromList [(qLocal n, t) | (n, t) <- bindings]) env
        result <- runBody envWithBindings body
        pure (results <> [result], ascribed <> [ascrTy], perCon)
      PCon patSp cName innerPats -> do
        ci <- maybeToRight (UnknownConstructor patSp cName) (M.lookup cName conEnv)
        let cTyName = ciTypeName ci
        label <-
          maybeToRight (RowLabelNotForConstructor patSp cName scrutTy) (findLabel cTyName)
        when (label `elem` ascribed)
          $ Left (DuplicateRowArm patSp label)
        rejectIgnoredConstructor conEnv (PCon patSp cName innerPats)
        checkNoShadow env crossExempt (collectPatternVars innerPats)
        -- Substitute the constructor's generic field types using the
        -- row label as the concrete return type — this gives the same
        -- per-arm field types that 'caseArmsNominal' computes for
        -- nested patterns.
        let genericRetTy = conReturnType cTyName (ciTypeParams ci)
            freshGenericRetTy = freshenType "$rowscrut" genericRetTy
            scrutSubst = fromRight mempty (unify freshGenericRetTy label)
            freshFieldTys = map (freshenType "$rowscrut") (ciFieldTypes ci)
            fieldTys = map (applySubst scrutSubst) freshFieldTys
            bindings = patternBindings conEnv innerPats fieldTys
            envWithBindings = M.union (M.fromList [(qLocal n, t) | (n, t) <- bindings]) env
        result <- runBody envWithBindings body
        let perCon' =
              M.insertWith (M.unionWith (<>)) label (M.singleton cName [(innerPats, fieldTys, patSp)]) perCon
        pure (results <> [result], ascribed, perCon')
      PVar patSp _ ->
        Left (RowCatchAllPattern patSp)
      PWild patSp ->
        Left (RowCatchAllPattern patSp)

    -- Verify that the nominal label's constructors are all covered by
    -- the @PCon@ arms gathered for that label, and that for every
    -- constructor the merged inner-pattern columns exhaust their field
    -- types.
    checkLabelConCoverage label byCon = do
      tyName <-
        maybeToRight (CaseOnNonSumType sp label) (extractTyCon label)
      ci <-
        maybeToRight (CaseOnNonSumType sp label)
          $ find (\c -> ciTypeName c == tyName) (M.elems conEnv)
      let allCons = ciSiblings ci
          present = M.keys byCon
          missingCons = filter (`notElem` present) allCons
      unless (null missingCons)
        $ Left (NonExhaustiveCase sp tyName missingCons)
      -- For each present constructor, verify the inner patterns column-
      -- wise cover the substituted field types.
      forM_ (M.toList byCon) $ \(_cName, armsForCon) -> case armsForCon of
        [] -> pass
        ((_, fieldTys0, _) : _) ->
          let columns = transpose [pats | (pats, _, _) <- armsForCon]
           in zipWithM_ (checkPatternColumnCovers sp conEnv tcm) fieldTys0 columns

-- | Verify that a column of patterns (one per arm, all at the same
--   position) exhausts @ty@. Used both by 'caseArmsRow' to validate
--   that, e.g., @Just (b : Bool)@ / @Just (u : Unit)@ together cover
--   the @(Bool | Unit)@ field of @Just@, and by 'caseArmsNominal'
--   to recurse into nested constructor patterns inside each
--   top-level arm.
--
--   Three cases on @ty@:
--
--     * @TyVar@ — open tail; no exhaustiveness check possible.
--     * @TyOr@ — row-shaped; per-label coverage with no catch-all
--       (PAscribe arms cover their ascribed label, PCon arms cover
--       the row label whose head matches the constructor's owning
--       type).
--     * Nominal sum — every inhabitant constructor must appear,
--       and for each present constructor we recurse into its
--       field columns at the substituted field types. Missing
--       inhabited constructors raise 'NonExhaustiveCase';
--       uninhabited ones (e.g. @Just Never@) are silently skipped
--       because they can't appear at runtime.
checkPatternColumnCovers ::
  SrcSpan -> ConEnv -> TypeConsMap -> Type' -> [Pattern] -> Either TypeError ()
checkPatternColumnCovers sp conEnv tcm ty pats
  | any isWildcardPat pats = Right () -- a single 'PVar'/'PWild' covers everything
  | otherwise = case ty of
      TyVar _ _ -> Right () -- open tail
      TyOr {} -> do
        let labels = flattenRow ty
            ascribed = [ascr | PAscribe _ _ ascr <- pats]
            perCon =
              M.fromListWith
                (<>)
                [ (cName, [(innerPats, ())])
                | PCon _ cName innerPats <- pats
                ]
            covered l =
              l
                `elem` ascribed
                || maybe False (`M.member` perCon) (extractTyCon l)
            missing = filter (\l -> not (isOpenLabel l) && not (covered l)) labels
        unless (null missing) $ Left (NonExhaustiveRow sp missing ty)
      _ -> case extractTyCon ty of
        Just tyName -> do
          let perCon =
                M.fromListWith
                  (<>)
                  [ (cName, [innerPats])
                  | PCon _ cName innerPats <- pats
                  ]
          ci <-
            maybeToRight (CaseOnNonSumType sp ty)
              $ find (\c -> ciTypeName c == tyName) (M.elems conEnv)
          let allCons = ciSiblings ci
              missingCons = filter (`notElem` M.keys perCon) allCons
              -- The substitution that maps @tyName@'s type-params to
              -- @ty@'s concrete arguments — needed both for the
              -- 'isConInhabited' filter on missing constructors and
              -- for substituting the present constructor's field
              -- types when we recurse.
              tySubst =
                let genericRetTy = conReturnType tyName (ciTypeParams ci)
                    freshGenericRetTy = freshenType "$exh" genericRetTy
                 in fromRight mempty (unify freshGenericRetTy ty)
              inhabitedMissing =
                filter (isConInhabited conEnv tcm S.empty tySubst) missingCons
          unless (null inhabitedMissing)
            $ Left (NonExhaustiveCase sp tyName inhabitedMissing)
          -- Recurse into each present constructor's field columns.
          -- This is what catches @Right (Just _)@ / @Left _@ leaving
          -- @Right Nothing@ uncovered: top-level @Right@/@Left@ are
          -- both present, but the @Right@-arm's field column on
          -- @Maybe a@ contains only @Just _@.
          forM_ (M.toList perCon) $ \(cName, armsFields) ->
            case M.lookup cName conEnv of
              Just ci' | not (null (ciFieldTypes ci')) -> do
                let freshFieldTys = map (freshenType "$exh") (ciFieldTypes ci')
                    fieldTys = map (applySubst tySubst) freshFieldTys
                    columns = transpose armsFields
                zipWithM_ (checkPatternColumnCovers sp conEnv tcm) fieldTys columns
              _ -> Right ()
        Nothing -> Right ()
  where
    isWildcardPat (PVar _ _) = True
    isWildcardPat (PWild _) = True
    isWildcardPat _ = False
    isOpenLabel (TyVar _ _) = True
    isOpenLabel _ = False

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
  PWild _ -> Right ()
  PAscribe _ inner _ -> rejectIgnoredConstructor conEnv inner

-- | True when the pattern is /not/ a 'PVar'. Used to gate features
--   that only apply to simple binder forms (e.g. type ascription on
--   a let-binding only makes sense when the LHS is a single name —
--   for destructuring patterns the user should ascribe the
--   right-hand side instead).
notPVarPat :: Pattern -> Bool
notPVarPat = \case
  PVar _ _ -> False
  _ -> True

-- | Best-effort name for a pattern, used in 'MissingLetAnnotation'
--   so the diagnostic can say "Cannot infer the type of let-binding
--   '<name>'" without lying about the syntactic shape. 'PVar'
--   returns the bound name; 'PWild' returns "_"; constructor and
--   ascription patterns shouldn't reach here in normal flow (the
--   desugarer rewrites them to 'ECase' before typecheck), but we
--   provide a defensive fallback so the diagnostic still prints
--   something useful.
patternBinderName :: Pattern -> Name
patternBinderName = \case
  PVar _ n -> n
  PWild _ -> "_"
  PCon _ c _ -> c
  PAscribe _ inner _ -> patternBinderName inner

-- | Collect all variable binders from a list of (possibly nested) patterns,
--   in left-to-right order, paired with the span of each binder.
collectPatternVars :: [Pattern] -> [(SrcSpan, Name)]
collectPatternVars = concatMap go
  where
    go (PVar sp n) = [(sp, n)]
    go (PWild _) = []
    go (PCon _ _ inner) = concatMap go inner
    go (PAscribe _ inner _) = go inner

-- | Extract variable bindings from patterns and their corresponding types.
--   Recurses into nested constructor patterns to bind deeply nested variables.
patternBindings :: ConEnv -> [Pattern] -> [Type'] -> [(Name, Type')]
patternBindings conEnv pats tys = concatMap go (zip pats tys)
  where
    go (PVar _ n, t) = [(n, t)]
    go (PWild _, _) = []
    go (PCon _ cName innerPats, ty) =
      case M.lookup cName conEnv of
        Nothing -> []
        Just ci ->
          let genericRetTy = conReturnType (ciTypeName ci) (ciTypeParams ci)
              -- Freshen generic type variables to avoid collisions with scrutinee type variables.
              freshGenericRetTy = freshenType "$inner" genericRetTy
              freshFieldTys = map (freshenType "$inner") (ciFieldTypes ci)
              innerSubst = fromRight mempty (unify freshGenericRetTy ty)
              fieldTys = map (applySubst innerSubst) freshFieldTys
           in patternBindings conEnv innerPats fieldTys
    -- 'PAscribe' overrides the scrutinee's type with the ascribed one
    -- for the purpose of binding the inner pattern's variables: in
    -- @case x of (n : Int32) -> …@ where @x : (Int32 | String)@, the
    -- variable @n@ is bound with type @Int32@, not the whole sum.
    -- The membership check (the ascribed type really is a label of the
    -- scrutinee's row) lives in the caseArms helper.
    go (PAscribe _ inner ty, _) = patternBindings conEnv [inner] [ty]

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
                     in fromRight mempty (unify freshGenericRetTy ty)
                  Nothing -> mempty
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
    patternEqual (PWild _) (PWild _) = True
    patternEqual (PWild _) (PVar _ _) = True -- wildcard matches variable
    patternEqual (PVar _ _) (PWild _) = True -- variable matches wildcard
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
      ELam _ params body ->
        go body `S.difference` S.fromList (map paramName params)
      EDo _ stmts -> goDoStmts stmts
      ELet _ pat _ e body -> go e <> (go body `S.difference` patternBoundNames pat)
    goDoStmts [] = S.empty
    goDoStmts (s : rest) = case s of
      DoBind _ pat e ->
        go e <> (goDoStmts rest `S.difference` patternBoundNames pat)
      DoLet _ pat _ e -> go e <> (goDoStmts rest `S.difference` patternBoundNames pat)
      DoExpr _ e -> go e <> goDoStmts rest
    patternBoundNames p = case p of
      PVar _ n -> S.singleton n
      PWild _ -> S.empty
      PCon _ _ ps -> foldMap patternBoundNames ps
      PAscribe _ inner _ -> patternBoundNames inner

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
