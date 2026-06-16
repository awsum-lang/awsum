-- | Bidirectional type checker for the surface AST ('Awsum.Syntax').
--
-- Scope and design notes:
--   • Built-in type constructors: @"String"@ and @"IO"@ (the @Unit@ in
--     @IO Never Unit@ is a prelude-defined sum type, not a built-in).
--   • User-defined sum types via @type Color = Red | Green | Blue@.
--   • The only function type constructor is right-associative arrow @->@.
--   • Hindley-Milner unification via 'Awsum.HM' under bidirectional
--     checking: expected types propagate down through 'ECase' arms,
--     constructor applications, and 'EApp' chains. Every top-level
--     definition still requires an explicit 'Sig' — no let-generalisation
--     at the top level — but local 'ELet' and lambda parameters get fresh
--     unification variables when no expected type is in scope.
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
    maxStringLitUtf16CodeUnits,
    emptyTypeNamesInProgram,
    markEmptyType,
    markEmptyTypesInDecl,
  )
where

import Awsum.BuiltIn (lookupBuiltIn)
import Awsum.HM (Subst, applySubst, collectTypeVars, flattenRow, freshenType, nullSubst, rowRetagNeeded, rowSubsume, singletonSubst, stripSyntheticTyvarSuffix, unify)
import Awsum.Program (ProgramType, platformTable)
import Awsum.Syntax
import Awsum.TExpr (TAlt (..), TDecl (..), TExpr (..), TParam (..), TPattern (..), TRowAlt (..), TypedProgram (..), substTExpr, tAltBody, tRowAltBody, texprType)
import Control.Monad (foldM, foldM_)
import Data.Char qualified as Char
import Data.Graph qualified as G
import Data.List (partition)
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import Data.Text qualified as T
import Numeric (showHex)
import Relude

-- ════════════════════════════════════════════════════════════════════════════
-- 'Check' monad
--
-- A thin newtype over 'Either TypeError'. The bidirectional checker
-- elaborates each expression into a typed 'TExpr' — the authoritative
-- type information consumed by row-monomorphisation, lowering, and LSP
-- hover. Call-site substitutions are pushed into the elaborated tree
-- directly ('substTExpr' at each 'EApp'); the monad itself carries only
-- the type-error short-circuit.
-- ════════════════════════════════════════════════════════════════════════════

type role Check representational

newtype Check a = Check {runCheck :: Either TypeError a}

instance Functor Check where
  fmap f (Check m) = Check (fmap f m)

instance Applicative Check where
  pure a = Check (Right a)
  Check f <*> Check a = Check (f <*> a)

instance Monad Check where
  Check m >>= k = Check (m >>= runCheck . k)

-- | Short-circuit with a type error.
throwTE :: TypeError -> Check a
throwTE = Check . Left

-- | Lift a pure 'Either TypeError' into 'Check'. Pure helpers
--   (@unify@, @wellFormedTypeWith@, @patternBindings@) stay in
--   'Either'; this is how their results flow back into 'Check'.
liftEither :: Either TypeError a -> Check a
liftEither = Check

-- | Catch a 'TypeError' and run a 'Check'-monad recovery. Used in
--   the bidirectional fallback ('checkExpr' constructor-app branch:
--   on unify failure, fall through to the synth+subsume path) and at
--   un-annotated let-bindings ('MissingLetAnnotation' wraps the
--   underlying synth error).
catchTE :: Check a -> (TypeError -> Check a) -> Check a
catchTE (Check (Right a)) _ = Check (Right a)
catchTE (Check (Left e)) handler = handler e

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
  | -- | String literal exceeds the language-fixed maximum length
    --   ('maxStringLengthUtf16CodeUnits' = 2^27 UTF-16 code units).
    --   Fields: span, literal length in UTF-16 code units.
    --   Symmetric to 'IntLiteralOutOfRange': both reject literals that
    --   can't fit in the language's representable range, before the
    --   value escapes to runtime.
    StringLiteralTooLong SrcSpan Int
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
  | -- | A 'let'-binding whose right-hand side has a type the row
    --   monomorphiser cannot specialise: a free variable that is both a
    --   structural-sum alternative (so it would need a runtime row tag) and
    --   a parameter (so it is a combinator's input-side row variable). The
    --   canonical case is a partially-applied row combinator bound
    --   polymorphically — @let pb = bindEither oa@: @pb@'s result row
    --   @(EA | e2)@ has @e2@ as an alternative, and @e2@ also sits in the
    --   continuation parameter @Int32 -> Either e2 b@. Awsum resolves rows
    --   per call-site, not per let-bound value, so one shared closure used
    --   at several error rows cannot be compiled. Fields: binder span,
    --   binder name. Fix: annotate the binding so the row is pinned
    --   (@let pb : T = …@), or inline the combinator at each use. A
    --   genuinely-polymorphic output tail (@let f = zeroOr@, the variable
    --   only in the result) and a non-row polymorphic value
    --   (@let id = \\x -> x@) are not affected.
    PolymorphicRowLet SrcSpan Name
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
  | -- | A @case@ arm on a nominal scrutinee used a non-constructor
    --   pattern. Nominal sums are matched by enumerating constructors:
    --   a @(x : T)@ ascription pattern only discriminates a
    --   structural-sum scrutinee, and binding the whole value (a
    --   catch-all) is not allowed. Carries the offending pattern's span
    --   and the scrutinee type. Replaces a span-less internal error that
    --   used to localise to @1:1@; also reached by the desugared forms
    --   @let (x : T) = e@ and a nominal-typed @\\(x : T) -> e@ that the
    --   lambda-annotation path does not claim.
    NonConstructorNominalArm SrcSpan Type'
  | -- | A lambda parameter annotation @\\(x : T) -> …@ disagreed with
    --   the parameter type the surrounding context requires. Carries the
    --   annotation span, the annotated type, and the expected type.
    LambdaParamAnnotationMismatch SrcSpan Type' Type'
  | -- | A type annotation on a top-level definition's parameter
    --   (@f (x : T) = …@). The parameter type is fixed by the mandatory
    --   signature, so the annotation is a redundant restatement that can
    --   only agree or conflict — rejected. Lambdas (which have no
    --   signature) accept the annotation; top-level definitions do not.
    TopLevelParamAnnotation SrcSpan
  | -- | A destructuring parameter was type-ascribed
    --   (@\\((Tuple2 a b) : T) -> …@). Mirrors 'PatternLetAscription':
    --   ascribe a simple binder, or destructure without an annotation.
    AscribedDestructuringParam SrcSpan
  deriving stock (Show, Eq)

-- | If @e@ is a fully-applied constructor expression
--   @ECon name `EApp` arg1 `EApp` arg2 …@, return the constructor's
--   span (the bare 'ECon' node, used for emitting hover-trace
--   records), its name, and its argument list. Walks left-associated
--   'EApp' chains and peels 'EParens'. Returns 'Nothing' for any
--   other shape.
collectConApp :: Expr -> Maybe (SrcSpan, Name, [Expr])
collectConApp = go []
  where
    go acc (EApp _ f x) = go (x : acc) f
    go acc (EParens _ inner) = go acc inner
    go acc (ECon sp n) = Just (sp, n, acc)
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
  StringLiteralTooLong sp _ -> Just sp
  MissingLetAnnotation sp _ _ -> Just sp
  PolymorphicRowLet sp _ -> Just sp
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
  NonConstructorNominalArm sp _ -> Just sp
  LambdaParamAnnotationMismatch sp _ _ -> Just sp
  TopLevelParamAnnotation sp -> Just sp
  AscribedDestructuringParam sp -> Just sp

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
  MainWrongType ty -> "Wrong type for 'main': expected IO Never Unit, got " <> showType ty
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
  StringLiteralTooLong _ n ->
    "String literal exceeds maximum length: "
      <> show n
      <> " UTF-16 code units (max: "
      <> show maxStringLitUtf16CodeUnits
      <> ", bounded by JVM's CONSTANT_Utf8_info u2 length field)."
  MissingLetAnnotation _ n _underlying ->
    "Cannot infer the type of let-binding '"
      <> n
      <> "'. Add an explicit type annotation: `let "
      <> n
      <> " : <type> = …`."
  PolymorphicRowLet _ n ->
    "Cannot monomorphise let-binding '"
      <> n
      <> "': its type has a row variable in a parameter position — a "
      <> "partially-applied row combinator (like `bindEither`) bound "
      <> "polymorphically. Awsum resolves rows per call-site, not per "
      <> "let-bound value. Add an explicit type annotation to pin the row "
      <> "(`let "
      <> n
      <> " : <type> = …`), or inline the combinator at each use."
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
  NonConstructorNominalArm _ ty ->
    "Case on a nominal type requires constructor patterns. A '(x : T)' "
      <> "ascription pattern discriminates a structural-sum scrutinee, "
      <> "not a nominal type like "
      <> showType ty
      <> "; binding the whole value (a catch-all) is not allowed. Match "
      <> "each constructor."
  LambdaParamAnnotationMismatch _ annotated expected ->
    "Lambda parameter annotated as "
      <> showType annotated
      <> " but the surrounding context requires "
      <> showType expected
      <> "."
  TopLevelParamAnnotation _ ->
    "Type annotations on top-level parameters are not allowed: the "
      <> "parameter type comes from the function's signature. Drop the "
      <> "annotation."
  AscribedDestructuringParam _ ->
    "A destructuring parameter cannot be type-ascribed. Annotate a "
      <> "simple binder ('\\(x : T) -> …') or destructure without an "
      <> "annotation ('\\(Tuple2 a b) -> …')."
  where
    showType :: Type' -> Text
    showType = \case
      TyVar _ n -> stripSyntheticTyvarSuffix n
      TyCon _ n -> n
      TyEmpty _ n -> n
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

-- | Maximum length of a string literal in UTF-16 code units. Bounded
--   tighter than the runtime cap ('maxStringLengthUtf16CodeUnits' in
--   'stdlib/Prelude.aww') by JVM's per-literal ceiling: each
--   'CONSTANT_Utf8_info' entry in the constant pool stores its length
--   in a 'u2' field (max 65535 UTF-8 bytes). Worst-case UTF-8
--   expansion of a UTF-16 code unit is 3 bytes (BMP-3-byte content —
--   CJK ideographs, hangul, most non-Latin scripts), so
--   'floor (65535 / 3) = 21845' is the largest UTF-16 code unit count
--   whose worst-case Modified-UTF-8 encoding still fits 'u2'. Keeping
--   the cap in code units (same unit as the runtime cap) means the
--   spec stays in one measure regardless of content.
maxStringLitUtf16CodeUnits :: Int
maxStringLitUtf16CodeUnits = 21845

-- | Length of 'Text' measured in UTF-16 code units. BMP code points
--   contribute 1, supplementary (>= U+10000, encoded as a surrogate
--   pair on UTF-16-native runtimes) contribute 2.
utf16CodeUnits :: Text -> Int
utf16CodeUnits = T.foldl' (\n c -> n + if Char.ord c > 0xFFFF then 2 else 1) 0

-- | Inclusive (min, max) range for a numeric built-in type.
--   Returns 'Nothing' for types that are not known integer types.
intTypeRange :: Name -> Maybe (Integer, Integer)
intTypeRange = \case
  "Int32" -> Just (-2147483648, 2147483647)
  "UInt8" -> Just (0, 255)
  "UInt32" -> Just (0, 4294967295)
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
  TyCon _ "UInt32" -> Right ()
  TyCon sp n
    | S.member n userTypes -> Right ()
    | otherwise -> Left (UnknownTypeCon sp n)
  -- 'TyEmpty' is produced by the empty-type rewrite from a TyCon
  -- whose name matched an 'empty type X' declaration; the user-types
  -- check has already accepted that name as known.
  TyEmpty _ _ -> Right ()
  TyApp _ f x -> wellFormedTypeWith userTypes f >> wellFormedTypeWith userTypes x
  TyArrow _ a b -> wellFormedTypeWith userTypes a >> wellFormedTypeWith userTypes b
  TyOr _ a b -> wellFormedTypeWith userTypes a >> wellFormedTypeWith userTypes b

-- | Collect every name declared with the @empty type@ keyword from a
--   program's top-level declarations. Used by callers (the
--   typechecker, the elaborator) that need to rewrite TyCon
--   references for those names into 'TyEmpty' before any type-shape
--   work runs.
emptyTypeNamesInProgram :: Program -> Set Name
emptyTypeNamesInProgram Program {decls} =
  S.fromList [n | TypeDecl _ n _ _ _ Empty _ <- toList decls]

-- | Walk a 'Type'' and replace every 'TyCon' whose name is in the
--   given 'Set' (the set of types declared with the @empty type@
--   keyword) with a 'TyEmpty' carrying the same name and span.
--   Non-'TyCon' nodes recurse structurally.
markEmptyType :: Set Name -> Type' -> Type'
markEmptyType emptyNames = go
  where
    go = \case
      TyCon sp n | n `S.member` emptyNames -> TyEmpty sp n
      t@TyVar {} -> t
      t@TyCon {} -> t
      t@TyEmpty {} -> t
      TyApp sp f x -> TyApp sp (go f) (go x)
      TyArrow sp a b -> TyArrow sp (go a) (go b)
      TyOr sp a b -> TyOr sp (go a) (go b)

-- | Apply 'markEmptyType' across a top-level declaration. Handles
--   signatures and the constructor-field types inside a 'TypeDecl';
--   leaves 'FunDef' / 'CommentDecl' alone (function bodies are walked
--   later inside 'checkExpr', where any ascription embedded in a
--   'PAscribe' / 'ELet' / 'DoLet' still passes through 'rowSubsume',
--   which already accepts a 'TyEmpty' on the actual side).
markEmptyTypesInDecl :: Set Name -> Decl -> Decl
markEmptyTypesInDecl emptyNames = \case
  Sig sp n t mc doc -> Sig sp n (markEmptyType emptyNames t) mc doc
  TypeDecl sp n ps cs mc ek doc ->
    TypeDecl sp n ps (map markCon cs) mc ek doc
    where
      markCon (ConDef cSp cName flds) =
        ConDef cSp cName (map (markEmptyType emptyNames) flds)
  d@FunDef {} -> d
  d@CommentDecl {} -> d

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
  let typeDecls = [(sp, n, tvs, cs) | TypeDecl sp n tvs cs _ _ _ <- decls]
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
      TyEmpty _ _ -> Right ()
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
      TyEmpty _ _ -> Right ()
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
typecheckProgram :: ProgramType -> Set Name -> Program -> Either TypeError (TypedProgram, [Warning])
typecheckProgram progType preludeNames Program {imports, decls} = do
  -- 0) Resolve every TyCon reference whose name was declared with the
  -- 'empty type' keyword to a 'TyEmpty', so the typechecker sees the
  -- row-identity flag uniformly. The rewrite covers signatures and
  -- constructor field types — references inside 'ELet' / 'DoLet' /
  -- 'PAscribe' ascriptions in expression bodies still arrive as
  -- 'TyCon' but flow through 'rowSubsume' (which accepts a 'TyEmpty'
  -- on the actual side regardless of the expected side's shape), so
  -- the practical user-level invariant — values of any 'empty type'
  -- subsume into any expected position — holds end-to-end.
  let emptyTypeNames =
        S.fromList [n | TypeDecl _ n _ _ _ Empty _ <- toList decls]
      declsResolved = fmap (markEmptyTypesInDecl emptyTypeNames) decls

  -- 1) Build constructor environment from type declarations.
  (userTypeNames, conEnv, conValEnv, typeConsMap) <- buildConEnv (toList declsResolved)

  -- 2) Partition top-level decls into signatures and definitions.
  let (sigsList, defsList) = partitionEithers (mapMaybe toEither (toList declsResolved))
      toEither = \case
        Sig sp n t _ _ -> Just (Left (sp, n, t))
        FunDef sp n as e _ _ -> Just (Right (sp, n, as, e))
        CommentDecl _ _ -> Nothing
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
  defResults <- forM defsList $ \(sp, n, args, body) -> do
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

    -- A type annotation on a top-level parameter (@f (x : T) = …@) is
    -- rejected: the parameter type is fixed by the mandatory signature,
    -- so the annotation can only restate or contradict it. (Destructuring
    -- params are already rewritten to a @case@ by 'Awsum.Desugar'; only
    -- annotation params survive as a 'ParamPat' here.) Lambdas keep the
    -- annotation — see 'resolveLamParamsChecked'.
    forM_ args $ \case
      ParamPat psp (PAscribe {}) -> Left (TopLevelParamAnnotation psp)
      _ -> Right ()

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

    -- Elaborate the body into its 'TExpr' (the authoritative typed tree
    -- consumed by monomorphisation, lowering, and LSP hover). On type
    -- error the body's partial elaboration is discarded by 'throwTE'.
    bodyTExpr <- runCheck (checkExpr conEnv typeConsMap crossModuleExempt env expectedBodyTy body)

    -- Unused-parameter warnings: report any user-named parameter (not @_@,
    -- not @_foo@) that the body does not reference. Underscore-prefixed
    -- names are an explicit opt-out and never warned on.
    let referenced = freeNames body
        warnings =
          [ UnusedParameter (paramSpan p) (paramName p)
          | p <- args,
            let nm = paramName p,
            not ("_" `T.isPrefixOf` nm),
            not (S.member nm referenced)
          ]

    -- A def with surface parameters is a function; a zero-arg def
    -- (including the alias form, whose signature is an arrow) is a
    -- constant. Param types come from the signature split.
    let tdecl = case args of
          [] -> TValDef n bodyTExpr
          _ -> TFunDef n [TParam (paramSpan p) t (paramName p) | (p, t) <- zip args argTys] bodyTExpr
    pure (warnings, tdecl)

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
  -- Reachability roots are 'main' plus every '_'-prefixed top-level: a
  -- '_name' definition is the user's explicit "keep this around even
  -- though nothing currently calls it" mark, and references it makes
  -- to other top-levels are real uses — without this, helpers used
  -- solely from a '_'-prefixed def would be reported as unused even
  -- though deleting them would break the kept def.
  -- 'freeNames body' collects every unqualified name the body mentions, but
  -- a top-level def's own parameters are also unqualified — without
  -- subtracting them, a one-letter param name leaks into the reachable set
  -- and silently masks an identically-named top-level. (E.g. '(++) a b =
  -- BuiltIn.concatString a b' would otherwise mark every user-level 'a'
  -- defined alongside it as reachable from main.)
  let callGraph =
        M.fromList
          [ (n, freeNames body `S.difference` S.fromList (map paramName args))
          | (_sp, n, args, body) <- defsList
          ]
      topLevelWarnings = case M.lookup "main" sigEnv of
        Nothing -> []
        Just _ ->
          let underscoreRoots =
                [n | (_sp, n, _args, _body) <- defsList, "_" `T.isPrefixOf` n]
              roots = "main" : underscoreRoots
              reachableFromRoots =
                S.unions [reachable r callGraph | r <- roots]
              unusedSet =
                S.fromList
                  [ n
                  | (_sp, n, _args, _body) <- defsList,
                    n /= "main",
                    not ("_" `T.isPrefixOf` n),
                    not (S.member n reachableFromRoots)
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
        | TypeDecl _ _ params cs _ _ _ <- toList declsResolved
        ]
      typeParamWarnings =
        [ UnusedTypeParameter sp n
        | (params, cs) <- typeDeclParams,
          let fieldVars = S.unions [collectTypeVars t | ConDef _ _ flds <- cs, t <- flds],
          Param sp n <- params,
          not ("_" `T.isPrefixOf` n),
          not (S.member n fieldVars)
        ]

  let (defWarnings, tdecls) = unzip defResults
      typedProgram = TypedProgram (toList declsResolved) tdecls

  Right (typedProgram, concat defWarnings <> topLevelWarnings <> typeParamWarnings)
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

-- | Entry-point check: verify the program declares
--   @main : IO Never Unit@.
--   Called only from @build@/@run@ — modules without @main@ (libraries,
--   @Prelude.aww@) pass 'typecheckProgram' but fail here when an executable
--   is requested.
--
--   The signature has no parameter: command-line input arrives via
--   @IO.Args.getArgs@ inside the IO chain (a platform built-in
--   registered in 'Awsum.Program.Cli'), not as an entry-point
--   argument. The error row 'Never' means @main@ has handled all
--   IO failures by the time it is built — typically via
--   @|> handleErrorIO h@ at the tail of the chain.
requireMain :: Program -> Either TypeError ()
requireMain Program {decls} =
  case listToMaybe [t | Sig _ "main" t _ _ <- toList decls] of
    Nothing -> Left MainMissing
    Just ty ->
      let want =
            TyApp
              noSpan
              (TyApp noSpan (TyCon noSpan "IO") (TyCon noSpan "Never"))
              (TyCon noSpan "Unit")
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

-- | A lambda parameter after classification: a plain binder (@x@ / @_@)
--   or an annotated binder @(x : T)@ / @(_ : T)@. 'Awsum.Desugar'
--   rewrites destructuring @ParamPat@s (@\\(Tuple2 a b) -> …@) to a
--   @case@ before typecheck, but passes annotation @ParamPat@s through
--   untouched — a top-down parameter type for a lambda has no other
--   surface form. Each clause that types an 'ELam' classifies its
--   params through this, so the three sites (check, spine, synthesis)
--   stay in step.
data LamParam
  = LamPlain SrcSpan Name
  | LamAnnot SrcSpan Name Type'

classifyLamParam :: Param -> Either TypeError LamParam
classifyLamParam = \case
  Param sp n -> Right (LamPlain sp n)
  ParamPat sp (PAscribe _ (PVar _ n) annT) -> Right (LamAnnot sp n annT)
  ParamPat sp (PAscribe _ (PWild _) annT) -> Right (LamAnnot sp "_" annT)
  ParamPat sp (PAscribe {}) -> Left (AscribedDestructuringParam sp)
  -- Defensive: destructuring @ParamPat@s are rewritten to a @case@ by
  -- 'Awsum.Desugar' before typecheck, so any other shape reaching here
  -- is an internal pipeline error.
  ParamPat sp _ ->
    Left (TELowering ("internal: un-desugared parameter pattern at " <> show (spanStartLine sp) <> ":" <> show (spanStartCol sp)))

lamParamName :: LamParam -> Name
lamParamName (LamPlain _ n) = n
lamParamName (LamAnnot _ n _) = n

lamParamSpan :: LamParam -> SrcSpan
lamParamSpan (LamPlain sp _) = sp
lamParamSpan (LamAnnot sp _ _) = sp

-- | No-shadow entries for a lambda's params. A bare @_@ binds nothing
--   (so repeated @\\_ _ -> …@ does not self-collide); every other name
--   — including @_foo@, which is bound but unreferenceable — is checked.
lamParamShadowEntries :: [LamParam] -> [(SrcSpan, Name)]
lamParamShadowEntries =
  mapMaybe (\lp -> if lamParamName lp == "_" then Nothing else Just (lamParamSpan lp, lamParamName lp))

-- | Resolve classified params against the expected param types from the
--   surrounding context (check / spine modes). A plain binder takes the
--   expected type; an annotated binder must unify with it — a mismatch
--   is 'LambdaParamAnnotationMismatch' pointing at the annotation. The
--   binder is bound at the /resolved/ type @applySubst s annT@ (the more
--   concrete of the two), so the body sees the annotated type and a
--   wrong body use is reported inside the lambda rather than at a
--   sibling argument. The accumulated substitution is returned so the
--   caller can pin a context type variable the annotation resolves — in
--   the spine, that lets @apply (\\(n : Int32) -> …) 5@ check @5@ against
--   @Int32@. The substitution threads left-to-right across params so
--   shared variables (@\\(x : a) (y : a) -> …@) stay consistent.
resolveLamParamsChecked :: [LamParam] -> [Type'] -> Check ([(Name, Type')], [TParam], Subst)
resolveLamParamsChecked = go mempty [] []
  where
    go s accB accT (lp : lps) (ty0 : tys) =
      let ty = applySubst s ty0
       in case lp of
            LamPlain sp n -> go s ((n, ty) : accB) (TParam sp ty n : accT) lps tys
            LamAnnot sp n annT -> case unify (applySubst s annT) ty of
              Right s2 ->
                let s' = s2 <> s
                    rt = applySubst s' annT
                 in go s' ((n, rt) : accB) (TParam sp rt n : accT) lps tys
              Left _ -> throwTE (LambdaParamAnnotationMismatch sp annT ty)
    -- 'lps' and 'tys' always have equal length (both derived from the
    -- same parameter list); the base case fires when both are empty.
    go s accB accT _ _ = pure (reverse accB, reverse accT, s)

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

checkExpr :: ConEnv -> TypeConsMap -> Set Name -> Env -> Type' -> Expr -> Check TExpr
checkExpr conEnv tcm crossExempt env expected = \case
  -- Lambda: split @expected@ into @arg → result@ pairs, bind each
  -- parameter at the corresponding argument type, then check the
  -- body against the residual result type. The body may itself be
  -- another lambda — we walk the arrow chain rather than handling
  -- one parameter at a time, so multi-parameter lambdas like
  -- @\\a b -> e@ split correctly against @A -> B -> R@.
  ELam sp params body -> do
    (paramTypes, resultTy) <- case zipParamsToArrow expected (length params) of
      Just split -> pure split
      Nothing -> throwTE (LambdaShapeMismatch sp expected (length params))
    lps <- liftEither (mapM classifyLamParam params)
    -- Reject parameters that shadow existing bindings.
    liftEither (checkNoShadow env crossExempt (lamParamShadowEntries lps))
    -- A @(x : T)@ param must agree with the expected type; a plain param
    -- takes it directly. Any substitution the annotations resolve is
    -- pushed into the result type before checking the body.
    (bindings, tparams, s) <- resolveLamParamsChecked lps paramTypes
    let env' = M.union (M.fromList [(qLocal n, t) | (n, t) <- bindings]) env
    bodyE <- checkExpr conEnv tcm crossExempt env' (applySubst s resultTy) body
    pure (TLam sp (applySubst s expected) tparams bodyE)
  -- 'do'-blocks are rewritten to nested 'bindEither' / 'case' by
  -- 'Awsum.Desugar' before typechecking — both the lowering path and
  -- the LSP trace path desugar first, so no 'EDo' reaches here. The
  -- clause stays for exhaustiveness; reaching it is an internal
  -- pipeline error.
  EDo sp _stmts ->
    throwTE (TELowering ("internal: do-block survived desugaring at " <> show (spanStartLine sp) <> ":" <> show (spanStartCol sp)))
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
  ELet lsp pat mAnnot e body ->
    elabLet conEnv tcm crossExempt env lsp pat mAnnot e $ \envNext -> do
      bodyE <- checkExpr conEnv tcm crossExempt envNext expected body
      pure (bodyE, expected)
  ELit sp (LInt n) ->
    case expected of
      TyCon _ tyName
        | Just (lo, hi) <- intTypeRange tyName -> do
            checkIntRange sp n tyName lo hi
            pure (TLit sp expected (LInt n))
      -- D.1: implicit injection — a bare integer literal in a row
      -- position resolves to the row's unique integer-typed alternative,
      -- then is wrapped in a 'TCoerce' that injects it into the row.
      -- If the row has zero or several integer labels we can't pick a
      -- type, and 'AmbiguousIntLiteral' / 'TypeMismatch' fire.
      TyOr {} -> case rowIntLabel expected of
        Just (tyName, lo, hi) -> do
          checkIntRange sp n tyName lo hi
          let lblTy = TyCon noSpan tyName
          pure (TCoerce sp lblTy expected (TLit sp lblTy (LInt n)))
        Nothing -> throwTE (TypeMismatch expected (TyCon noSpan "<integer literal>") (ELit sp (LInt n)))
      _ -> throwTE (TypeMismatch expected (TyCon noSpan "<integer literal>") (ELit sp (LInt n)))
  EParens _sp e -> checkExpr conEnv tcm crossExempt env expected e
  -- Bidirectional check on @case@ scrutinees: push the expected type
  -- into each arm body, so e.g. an @Int32@-result function can write
  -- a literal @0@ in a case arm and have it pinned to @Int32@
  -- without a separate @zero : Int32@ binding. Without this clause
  -- the case would fall through to synthesis and the literal would
  -- be reported as 'AmbiguousIntLiteral'.
  ECase sp scrut alts _ -> do
    (scrutE, elab) <-
      caseArms conEnv tcm crossExempt env sp scrut alts $ \envArm body ->
        checkExpr conEnv tcm crossExempt envArm expected body
    pure $ case elab of
      NominalArms talts -> TCase sp expected scrutE talts
      RowArms tralts -> TRowCase sp expected scrutE tralts
  -- Bidirectional check at constructor applications: when the
  -- enclosing context fixes a concrete return type, match it against
  -- the constructor's generic return shape and propagate the
  -- resulting substitution into each field's check. Without this,
  -- @Right 1 : Either ErrorA Int32@ can't typecheck — the integer
  -- literal would be checked against a freshened tyvar @b$N@ instead
  -- of @Int32@.
  e@(EApp {})
    | Just (conSp, cName, args) <- collectConApp e,
      Just ci <- M.lookup cName conEnv,
      length args == length (ciFieldTypes ci) -> do
        let genericRetTy = conReturnType (ciTypeName ci) (ciTypeParams ci)
            freshGenericRetTy = freshenType "$check" genericRetTy
            freshFieldTys = map (freshenType "$check") (ciFieldTypes ci)
            -- Full freshened constructor type for the hover record's
            -- /instantiated/ slot — fields fed through the return type.
            freshConTy = foldr (TyArrow noSpan) freshGenericRetTy freshFieldTys
            -- /Declared/ scheme: env-stored polymorphic conType (with
            -- the original 'a', 'b' tyvar names from the 'TypeDecl').
            declaredConTy = fromMaybe freshConTy (M.lookup (qLocal cName) env)
        case unify freshGenericRetTy expected of
          Right s -> do
            let instConTy = applySubst s freshConTy
                resultTy = applySubst s freshGenericRetTy
                fieldExpected = map (applySubst s) freshFieldTys
            argEs <- zipWithM (checkExpr conEnv tcm crossExempt env) fieldExpected args
            pure (TApp conSp resultTy (TConRef conSp declaredConTy instConTy cName) argEs)
          Left _ -> do
            eE <- typeOfExpr conEnv tcm env e
            acceptInto expected eE e
  -- Non-constructor application. The bidirectional spine check
  -- synthesises the head, then threads a substitution through the
  -- arguments left-to-right, pushing @expected@ into each position. Two
  -- jobs ride on that thread:
  --
  --   • a bare integer literal flows through a polymorphic call site like
  --     @apply (\n -> n) 42 : Int32@ — the forward unify from the result
  --     type pins @apply@'s @a@ tyvar to @Int32@ before the literal (which
  --     has no synthesised type) is checked;
  --   • a row combinator's still-free result-row variable is pinned from
  --     @expected@ before an inline lambda / @do@ continuation is checked,
  --     so the continuation is elaborated against a /concrete/ result row
  --     and its own @Left@ injections record their coercions. Without this
  --     the continuation is checked against an abstract row, no coercion is
  --     emitted (a label does not coerce into a bare variable), and the
  --     injected payload reaches lowering untagged — a cross-target row
  --     dispatch break.
  --
  -- Synthesis is tried first and kept for the common case; it is redone via
  -- the spine only when it left a row variable that @expected@ pins while an
  -- argument is an inline lambda / @do@ (the deferred-coercion case), or on
  -- synth failure.
  e@(EApp {}) ->
    let (appHead, spineArgs) = appSpine e
        spine = do
          headE0 <- typeOfExpr conEnv tcm env appHead
          -- Freshen the head's /instantiated/ scheme variables with a
          -- per-application-span suffix. 'typeOfExpr' returns a polymorphic
          -- reference (@TVar decl inst@) whose @inst@ slot still carries the
          -- combinator's own scheme names (@a@, @e1@, @e2@, @b@ for
          -- @andThenIO@). Two nested applications of the /same/ combinator
          -- — @andThenIO c2 (andThenIO c1 z)@ — would otherwise share those
          -- names, and the spine threads substitutions positionally
          -- (@argTy' = applySubst subst' argTy@): the inner step binding
          -- @a := T@ from its operand then leaks into the outer step's @a@
          -- (its result element), so the outer continuation is checked
          -- against the inner input type. (The synthesis path is immune —
          -- it resolves each subtree to a concrete type bottom-up before
          -- combining — but a continuation it cannot synthesise, e.g. a
          -- destructuring @\\(Tuple2 a b) -> …@, falls to this spine.) The
          -- @decl@ slot is left untouched so 'Awsum.MonomorphizeRows' still
          -- sees the original scheme. The suffix keys off the /head
          -- occurrence's/ span, not the application's: a left-nested @|>@
          -- chain rewrites every step to an 'EApp' sharing the leftmost
          -- operand's start position, so @exprSpan e@ would collide across
          -- steps, whereas each @andThenIO@ token sits at its own position.
          let headE = freshenHeadInst (exprSpan appHead) headE0
          case zipParamsToArrow (texprType headE) (length spineArgs) of
            Just (argTys, resultTy) -> do
              -- Validate the result shape, but do /not/ keep unify's
              -- positional pairing of the combinator's result row. For a
              -- two-variable result row like @Either (e1 | e2) b@,
              -- 'unifyRows' matches @(e1 | e2)@ against @expected@'s labels
              -- left-to-right (greedy first-fit), pinning the input-side
              -- @e1@ to whichever label is written first instead of letting
              -- the operand pin it — an order-dependent mis-binding. The fold
              -- is seeded from 'solveRowVars' instead (below): it pins the
              -- non-row result variables (e.g. @b ↦ Int32@) and /defers/ a
              -- row that still has more than one free variable, so the
              -- operand pins @e1@ and the per-step solve pins @e2@.
              _ <- unifyOrSubsume expected resultTy e
              -- Process arguments in two groups so a row variable is pinned
              -- by the argument that feeds it before any inline continuation
              -- is checked: first the synthesising arguments (they pin the
              -- combinator's input-side variables, e.g. @e1@ from @oa@), then
              -- the deferred ones (lambda / do / bare literal). Each step
              -- first pins, via 'solveRowVars', the result-row variable(s)
              -- @expected@ resolves — so by the time a continuation is
              -- checked, its result row is concrete and its own injections
              -- record their coercions. Original positions are restored at
              -- the end.
              -- A row variable that occurs only in the result, never in a
              -- consumed parameter, is passed to 'solveRowVars' as a /tail/
              -- variable: it must not be row-absorbed — bound, as the single
              -- free variable of a row, to the expected row's whole label set.
              -- For a genuinely-polymorphic output tail (the @e@ of
              -- @zeroOr : Int32 -> Either (EZ | e) Int32@) that absorb would
              -- make the head's @inst@ un-expressible as a substitution
              -- instance of @declared@ (one declared row variable cannot
              -- absorb two-or-more labels in 'Awsum.HM.unifyRows'), crashing
              -- row-monomorphisation's @unify declared inst@. Plain-variable
              -- pinning is /not/ suppressed, so a partial combinator's
              -- residual row variable is still pinned structurally by a
              -- concrete expected type (@let pb : (Int32 -> Either EB Int32)
              -- -> … = bindEither oa@ matches @e2@ against @EB@ in the
              -- parameter), which only the row-absorb would otherwise break.
              let resultOnlyVars =
                    collectTypeVars resultTy `S.difference` foldMap collectTypeVars argTys
              let s0 = solveRowVars False (collectTypeVars expected) resultOnlyVars resultTy expected
                  indexed = zip3 [0 :: Int ..] argTys spineArgs
                  (synthArgs, deferredArgs) =
                    partition (\(_, _, arg) -> not (isDeferredArg arg)) indexed
                  step pinAllFree (acc, subst) (i, argTy, arg) = do
                    let subst' =
                          subst
                            <> solveRowVars pinAllFree (collectTypeVars expected) resultOnlyVars (applySubst subst resultTy) expected
                        argTy' = applySubst subst' argTy
                    (argE, sArg) <- checkArgSubst conEnv tcm env argTy' arg
                    pure ((i, argE) : acc, sArg <> subst')
              -- Synth args stay conservative — each operand pins its own
              -- input-side row variable. The deferred phase ('step True')
              -- then pins every still-free result-row variable from
              -- @expected@, so an inline continuation after a @pure@-like
              -- operand is checked against a concrete row.
              (synthEs, sAfterSynth) <- foldM (step False) ([], s0) synthArgs
              (allEs, sBeforeFinal) <- foldM (step True) (synthEs, sAfterSynth) deferredArgs
              -- Final pin: a result-row variable still free after every
              -- argument was checked — e.g. the input-side @e1@ of
              -- @bindEither (pureEither n) namedCont@, contributed by a
              -- @pure@-like operand and fed by no deferred argument — is
              -- pinned from @expected@ as an upper bound, so the call head's
              -- instantiated type is concrete for row-monomorphisation. The
              -- pin composes on the /left/ so an operand's own free row
              -- variable, which @sBeforeFinal@ aliased the call's variable to,
              -- resolves transitively through to the concrete labels.
              let sFinal =
                    solveRowVars True (collectTypeVars expected) resultOnlyVars (applySubst sBeforeFinal resultTy) expected
                      <> sBeforeFinal
              -- Substitute the call head with the fully-threaded
              -- substitution. Without this the head keeps its abstract
              -- instantiated type, so 'monomorphizeRows' sees no row
              -- widening and leaves a row-combinator's injected payload
              -- untagged.
              let argEs = map snd (sortWith fst allEs)
              pure (TApp (exprSpan e) expected (substTExpr sFinal headE) argEs)
            Nothing -> do
              eE <- typeOfExpr conEnv tcm env e
              acceptInto expected eE e
     in -- Synthesis runs once; 'Check' is a pure 'Either', so branch on its
        -- result instead of calling 'spine' inside a 'catchTE' that would
        -- re-run it on a 'spine' failure. When @expected@ pins a variable the
        -- synth elaboration left open — a result row that a nested
        -- continuation's injection must be tagged against, or a row still free
        -- after a @pure@-like operand — redo bidirectionally via 'spine' so
        -- those injections are tagged and the call head specialises. Otherwise
        -- accept the synth result. Each branch keeps the other as its fallback,
        -- so a shape one path cannot type still checks via the other, and
        -- 'spine' runs at most once.
        case runCheck (typeOfExpr conEnv tcm env e) of
          Right eE
            | nullSubst (solveRowVars True (collectTypeVars expected) S.empty (texprType eE) expected) ->
                acceptInto expected eE e `catchTE` const spine
            | otherwise -> spine `catchTE` const (acceptInto expected eE e)
          Left _ -> spine
  -- @x |> f@ is pure syntax for @f x@. Delegating to the 'EApp' check
  -- gives the bidirectional spine logic above for free, so a pipe call
  -- against a polymorphic head (@x |> apply g@) gets the same
  -- expected-type propagation as the direct application form.
  EInfix sp OpPipe l r -> checkExpr conEnv tcm crossExempt env expected (EApp sp r l)
  e -> do
    eE <- typeOfExpr conEnv tcm env e
    -- Boundary acceptance via 'acceptInto': 'rowSubsume' is the
    -- asymmetric relation — implicit injection extended through nominal
    -- heads — that lets @Left ErrA : Either ErrA r@ flow into
    -- @Either (ErrA | ErrB) Int32@. A genuine widening is recorded as a
    -- 'TCoerce'; a value flowing into a still-abstract row (the two
    -- unify) is left untouched.
    acceptInto expected eE e
  where
    checkIntRange :: SrcSpan -> Integer -> Name -> Integer -> Integer -> Check ()
    checkIntRange sp n tyName lo hi
      | n >= lo && n <= hi = pass
      | otherwise = throwTE (IntLiteralOutOfRange sp n tyName)

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

    -- Freshen the /instantiated/ slot of a spine head's type with a suffix
    -- unique to the application's span, so nested applications of the same
    -- polymorphic combinator do not share scheme-variable names (see the
    -- call site). The /declared/ slot is preserved — 'Awsum.MonomorphizeRows'
    -- recovers the per-call-site instantiation from @unify declared inst@,
    -- which renaming the inst side leaves intact. A monomorphic head
    -- ('TBuiltIn') and non-reference heads (e.g. a 'TLam', whose parameters
    -- already carry span-unique names) are returned unchanged.
    freshenHeadInst :: SrcSpan -> TExpr -> TExpr
    freshenHeadInst sp =
      let suffix = "$spine" <> show (spanStartLine sp) <> "_" <> show (spanStartCol sp)
       in \case
            TVar vsp decl inst q -> TVar vsp decl (freshenType suffix inst) q
            TConRef csp decl inst n -> TConRef csp decl (freshenType suffix inst) n
            other -> other

    -- An argument with no synthesised type of its own: an inline lambda /
    -- @do@ continuation (defers its row coercions against an abstract result
    -- row) or a bare integer literal (no defaulting). The spine processes
    -- these /after/ the synthesising arguments, so the latter pin the
    -- combinator's input-side row variables first and 'solveRowVars' can
    -- then resolve the one the continuation feeds from @expected@. Ordering
    -- the literal last is also what keeps @apply (\n -> n) 42@ working — the
    -- lambda pins @a@ before the literal is checked against it.
    isDeferredArg :: Expr -> Bool
    isDeferredArg = \case
      ELam {} -> True
      ELit _ (LInt _) -> True
      EParens _ inner -> isDeferredArg inner
      _ -> False

    unifyOrSubsume :: Type' -> Type' -> Expr -> Check Subst
    unifyOrSubsume expectedTy actualTy origExpr =
      case unify expectedTy actualTy of
        Right s -> pure s
        Left _ ->
          if rowSubsume expectedTy actualTy
            then pure mempty
            else throwTE (TypeMismatch expectedTy actualTy origExpr)

    -- Elaborate one argument against its expected type, returning both
    -- its 'TExpr' and the substitution gleaned from it — needed so
    -- binders introduced by a polymorphic call ('a' in
    -- @apply : (a -> b) -> a -> b@) get pinned by the lambda body's
    -- identity before the next argument is checked. Lambdas recurse
    -- through their bodies; everything else goes through 'checkExpr'
    -- for elaboration and uses 'unify' on the synthesised type when one
    -- is available.
    checkArgSubst :: ConEnv -> TypeConsMap -> Env -> Type' -> Expr -> Check (TExpr, Subst)
    checkArgSubst cEnv tcm' env' argExpected = \case
      EParens _ inner -> checkArgSubst cEnv tcm' env' argExpected inner
      ELam sp params body -> do
        (paramTypes, resultTy) <- case zipParamsToArrow argExpected (length params) of
          Just split -> pure split
          Nothing -> throwTE (LambdaShapeMismatch sp argExpected (length params))
        lps <- liftEither (mapM classifyLamParam params)
        liftEither (checkNoShadow env' crossExempt (lamParamShadowEntries lps))
        -- The annotations' substitution is returned with the body's, so a
        -- context variable an annotation pins (apply's @a@ in
        -- @apply (\\(n : Int32) -> …) 5@) is visible to sibling arguments
        -- the spine checks after this one.
        (paramBindings, tparams, sParams) <- resolveLamParamsChecked lps paramTypes
        let envInner = M.union (M.fromList [(qLocal n, t) | (n, t) <- paramBindings]) env'
        (bodyE, sBody) <- checkArgSubst cEnv tcm' envInner (applySubst sParams resultTy) body
        let s = sBody <> sParams
        pure (TLam sp (applySubst s argExpected) tparams bodyE, s)
      arg -> do
        argE <- checkExpr cEnv tcm' crossExempt env' argExpected arg
        -- The synthesised type is used only for spine-subst chaining;
        -- failures are squashed to 'mempty' to preserve the original
        -- best-effort semantics.
        s <-
          catchTE
            ( do
                actual <- texprType <$> typeOfExpr cEnv tcm' env' arg
                whenRight mempty (unify argExpected actual) pure
            )
            (\_ -> pure mempty)
        pure (argE, s)

-- | The substitution a check-mode argument (a lambda or literal, which
--   has no synthesisable root type) pins on tyvars shared with the
--   callee's signature. For a lambda it descends into the body and
--   unifies the body's type against the expected result; for anything
--   else it unifies the expected type with the argument's own type.
--   Mirrors the former lowering-time @argSubst@, but on the typed AST —
--   it is what keeps a row-combinator continuation's error label
--   (@e2 := EB@) flowing to the call head so 'Awsum.MonomorphizeRows'
--   sees a fully concrete instantiation.
argSubstT :: Type' -> TExpr -> Subst
argSubstT expected = \case
  TLam _ _ params body ->
    case zipParamsToArrow expected (length params) of
      Just (paramTys, resultTy) ->
        -- Recover what the params pin on the callee's tyvars before
        -- descending into the body. For a plain param the typed param's
        -- type already /is/ the expected one, so this unifies to nothing;
        -- an annotated param @\\(n : Int32) -> …@ carries the concrete
        -- annotation, which pins the callee's @a@ — letting a sibling
        -- bare-literal argument (@apply (\\(n : Int32) -> …) 5@) be checked
        -- against that concrete type rather than an open variable.
        let sParams = mconcat (zipWith (\pty (TParam _ pt _) -> fromRight mempty (unify pty pt)) paramTys params)
         in sParams <> argSubstT (applySubst sParams resultTy) body
      Nothing -> mempty
  e -> fromRight mempty (unify expected (texprType e))

-- | Solve the free instantiation variables of an application's @inferred@
--   result type against the @target@ type the surrounding context requires,
--   returning a substitution. Used by the 'EApp' spine check to pin a row
--   combinator's still-free result-row variable from the enclosing expected
--   type /before/ an inline lambda / @do@ continuation is elaborated.
--
--   Why this exists. A row-polymorphic combinator used as a @do@-block
--   continuation (@bindEither oa (\\_n -> do …)@) leaves its error-row
--   variable @e2@ free: the @do@-block desugars to a nested @case@ whose
--   node type is the still-abstract expected type, so the lambda's result
--   row never gets pinned by plain unification ('argSubstT' unifies @e2@
--   with itself). Checked against an abstract row, the continuation's own
--   @Left@ injections record no 'TCoerce' (a label does not coerce into a
--   bare variable), so they reach lowering untagged and cross-target row
--   dispatch breaks. Pinning @e2@ from @target@ first means the
--   continuation is checked against a concrete result row and its
--   injections get their coercions through the normal path.
--
--   We walk @(inferred, target)@ in parallel and bind:
--
--     * a /row variable/ — only when it is the /single/ free variable of
--       its row — to /every/ concrete label of the target row (its upper
--       bound). Not the set difference against labels already concrete on
--       the inferred side: the continuation is not yet checked, so a label
--       it shares with the operand must stay in the bound or its injection
--       is rejected; per-label tags make the wider bound harmless. With two
--       or more free variables the split is ambiguous and left alone — the
--       other variables are pinned by their own arguments (e.g. @e1@ by
--       @oa@) and a later step solves the one that remains.
--     * a /plain instantiation variable/ to the sub-type @target@ has there
--       (the continuation's success @b@ ↦ @Int32@).
--
--   Variables that are /rigid/ in the enclosing context — those of
--   @target@, like the @e@ / @b@ of @mapRight : Either e a -> (a -> b) ->
--   Either e b@ — are never bound, so a genuinely polymorphic call site
--   stays polymorphic.
--
--   @tailVars@ are variables that must not be /row-absorbed/ — bound, as a
--   free variable of a row, to the target row's whole label set. They are
--   the spine's result-only variables. A genuinely-polymorphic output tail
--   (@zeroOr@'s @e@ in @Either (EZ | e) Int32@) absorbed that way would make
--   the call head's @inst@ un-expressible as a substitution instance of
--   @declared@ (one declared row variable cannot absorb two-or-more labels),
--   crashing row-monomorphisation's @unify declared inst@. Plain-variable
--   pinning of a @tailVar@ is /not/ suppressed: a partial combinator's
--   residual @e2@ pinned structurally against a concrete @target@ (the
--   @Either EB@ inside @(Int32 -> Either EB Int32) -> …@) stays correct —
--   only the row-absorb is unsafe.
solveRowVars :: Bool -> S.Set Name -> S.Set Name -> Type' -> Type' -> Subst
solveRowVars pinAllFree rigid tailVars = go
  where
    go inferred target = case (inferred, target) of
      -- Row on the inferred side: when exactly one of its variables is free,
      -- bind it to the target row's full concrete-label set (see below).
      (TyOr {}, _) ->
        let infVars = [v | TyVar _ v <- flattenRow inferred, not (S.member v rigid)]
            -- Bind the single free row variable to /every/ concrete label of
            -- the target, not the set difference against labels already
            -- present on the inferred side. The continuation has not been
            -- checked yet, so which of those labels it /also/ produces is
            -- unknown; subtracting a shared label would check the
            -- continuation against too narrow a row and reject its injection
            -- of that label. Per-label tags make a wider-than-needed bound
            -- harmless (a label keeps its tag in any row), and an upper bound
            -- is always sound.
            targetConcrete = [l | l <- flattenRow target, isConcreteAlt l]
         in case infVars of
              -- Single free row variable: bind it to the target's concrete
              -- labels. Guard on a non-empty set so a still-abstract target
              -- (no concrete label at this position) never binds the variable
              -- to @Never@ — the @rowFromLabels [] = Never@ trap that would
              -- reject a valid injection. Same guard as the multi-variable arm
              -- below; an empty set falls through to @mempty@. A @tailVar@ is
              -- never row-absorbed (see the haddock): the guard fails and the
              -- variable is left free for the generic body / plain-var pin.
              [v]
                | not (null targetConcrete),
                  not (S.member v tailVars) ->
                    singletonSubst v (rowFromLabels targetConcrete)
              -- Two or more free variables: their split is ambiguous, so the
              -- conservative (synth) phase defers — the operand pins one, a
              -- later step solves the other. Once every synthesising operand
              -- has been checked (the @pinAllFree@ deferred phase), a row
              -- variable still free was contributed by a non-failing,
              -- @pure@-like operand: it injects nothing, so binding it /and/
              -- the continuation's variable to the target's full
              -- concrete-label set is a sound upper bound. Same non-empty
              -- guard against the @Never@ trap.
              _
                | pinAllFree && not (null targetConcrete) ->
                    mconcat [singletonSubst v (rowFromLabels targetConcrete) | v <- infVars, not (S.member v tailVars)]
                | otherwise -> mempty
      -- Plain instantiation variable on the inferred side: the target pins
      -- it. Skip rigid context variables and the no-op self-bind.
      (TyVar _ v, _)
        | S.member v rigid -> mempty
        | TyVar _ w <- target, w == v -> mempty
        | otherwise -> singletonSubst v target
      (TyApp _ inf inx, TyApp _ sf sx) -> go inf sf <> go inx sx
      (TyArrow _ ia ib, TyArrow _ sa sb) -> go ia sa <> go ib sb
      _ -> mempty

    isConcreteAlt = \case
      TyVar _ _ -> False
      TyEmpty _ _ -> False
      _ -> True

    -- A row from a label list: empty → the row identity (an @empty@-shaped
    -- type, vacuously subsuming everywhere) when the continuation cannot
    -- fail; one → that label; many → a 'TyOr' (nesting / order irrelevant,
    -- rows are set-semantic). 'noSpan' throughout — these labels come from
    -- the target, which already carries its own diagnostic spans.
    rowFromLabels = \case
      [] -> TyEmpty noSpan "Never"
      (t : ts) -> foldr (TyOr noSpan) t ts

-- | Accept a synthesised value of type @actual@ into a position
--   requiring @expected@, recording an explicit 'TCoerce' iff the
--   acceptance is a genuine row widening — i.e. the two do /not/ unify
--   but @actual@ subsumes into @expected@. When they unify (including
--   when @expected@ still carries tyvars the surrounding call will
--   instantiate) no coercion is emitted, so a value flowing into an
--   as-yet-abstract row position is left untouched rather than wrapped
--   in a coercion to an abstract target. This is the single rule for
--   where row injection nodes appear.
acceptInto :: Type' -> TExpr -> Expr -> Check TExpr
acceptInto expected eE srcExpr =
  let actual = texprType eE
   in if not (rowSubsume expected actual)
        then throwTE (TypeMismatch expected actual srcExpr)
        else
          if needsRowCoerce expected actual
            then pure (TCoerce (exprSpan srcExpr) actual expected eE)
            else pure eE

-- | Does accepting a value of type @actual@ into a position requiring
--   @expected@ need a row injection? Yes exactly when, at some
--   structural position, @expected@ is a structural sum ('TyOr') while
--   @actual@ at that position is /not/ a row — a single label being
--   injected. Two rows in the same position is a sub-row → wider-row
--   widening, which is a no-op at runtime (per-label tags), so no
--   coercion is emitted there. Recurses through nominal heads ('TyApp')
--   and arrows so a row nested inside @Either@ / @IO@ / a function
--   result is still found.
--
--   Crucially this is /not/ decided by 'unify': unifying a row against a
--   tyvar-laden one (@(e1 | e2) ~ e1@) succeeds by collapsing the
--   variables, which would mask the very injection we must record.
needsRowCoerce :: Type' -> Type' -> Bool
needsRowCoerce expected actual = case (expected, actual) of
  (TyOr {}, TyOr {}) -> rowRetagNeeded actual expected
  (TyOr {}, _) -> True
  (TyApp _ ef ex, TyApp _ af ax) -> needsRowCoerce ef af || needsRowCoerce ex ax
  (TyArrow _ ea eb, TyArrow _ aa ab) -> needsRowCoerce aa ea || needsRowCoerce eb ab
  _ -> False

-- | Shared elaboration of a @let pat = e in body@ (and its ascribed
--   form). The two call sites — 'checkExpr' (body checked against an
--   expected type) and 'typeOfExpr' (body synthesised) — differ only in
--   the shadowing-exempt set and how the body is elaborated, passed in as
--   @checkBody@, which returns the elaborated body and the @let@'s type.
-- | True when a let-bound value's type cannot be row-monomorphised: it has a
--   free variable that is BOTH a structural-sum alternative (so it would
--   carry a runtime row tag) AND in a parameter position (so it is a
--   combinator's input-side row variable, resolved per call-site rather than
--   per let value). @let pb = bindEither oa@ binds such a @pb@ — @e2@ is an
--   alternative of the result row @(EA | e2)@ and also sits in the
--   continuation parameter @Int32 -> Either e2 b@. Left alone: a
--   genuinely-polymorphic output tail (@let f = zeroOr@ — the variable only
--   in the result), a single-variable error row (@let m = mapLeft oa@ — @e2@
--   is an 'Either' argument, not a sum alternative), and a non-row
--   polymorphic value (@let id = \\x -> x@).
unmonomorphizableRowLet :: Type' -> Bool
unmonomorphizableRowLet te =
  not (S.null (S.intersection (rowAltVars te) (paramVars te)))
  where
    -- Variables occurring as an alternative of some structural sum.
    rowAltVars :: Type' -> S.Set Name
    rowAltVars t = case t of
      TyOr {} ->
        let alts = flattenRow t
         in S.fromList [v | TyVar _ v <- alts] <> foldMap rowAltVars alts
      TyApp _ a b -> rowAltVars a <> rowAltVars b
      TyArrow _ a b -> rowAltVars a <> rowAltVars b
      _ -> mempty
    -- Variables occurring anywhere left of an arrow (in a parameter).
    paramVars :: Type' -> S.Set Name
    paramVars t = case t of
      TyArrow _ a b -> collectTypeVars a <> paramVars b
      _ -> mempty

elabLet :: ConEnv -> TypeConsMap -> S.Set Name -> Env -> SrcSpan -> Pattern -> Maybe Type' -> Expr -> (Env -> Check (TExpr, Type')) -> Check TExpr
elabLet conEnv tcm exempt env lsp pat mAnnot e checkBody = do
  when (notPVarPat pat && isJust mAnnot)
    $ throwTE (PatternLetAscription lsp)
  (rhsE, te) <- case mAnnot of
    Just t -> do
      eE <- checkExpr conEnv tcm exempt env t e
      pure (eE, t)
    Nothing -> do
      eE <-
        typeOfExpr conEnv tcm env e
          `catchTE` \err ->
            throwTE (MissingLetAnnotation lsp (patternBinderName pat) err)
      let te = texprType eE
      -- Reject a polymorphic let-bound row combinator before it reaches
      -- lowering: row-monomorphisation is per call-site, so a shared closure
      -- carrying a free union-row variable in a parameter position cannot be
      -- specialised, and its injection would reach the consuming case
      -- untagged. The annotated form pins the row and compiles.
      when (unmonomorphizableRowLet te)
        $ throwTE (PolymorphicRowLet lsp (patternBinderName pat))
      pure (eE, te)
  liftEither (checkNoShadow env exempt (collectPatternVars [pat]))
  let bindings = patternBindings conEnv [pat] [te]
      envNext = M.union (M.fromList [(qLocal n, t) | (n, t) <- bindings]) env
  (bodyE, letTy) <- checkBody envNext
  pure (TLet lsp letTy (elabPattern conEnv pat te) rhsE bodyE)

-- | Infer/check the type of an expression under the given environment.
--   This function /checks/ consistency; it does not invent polymorphism.
typeOfExpr :: ConEnv -> TypeConsMap -> Env -> Expr -> Check TExpr
typeOfExpr conEnv tcm env = \case
  ELit sp (LString s) -> do
    let n = utf16CodeUnits s
    when (n > maxStringLitUtf16CodeUnits) (throwTE (StringLiteralTooLong sp n))
    pure (TLit sp (TyCon sp "String") (LString s))
  ELit sp (LInt _) -> throwTE (AmbiguousIntLiteral sp)
  EVar sp q ->
    case q of
      -- Bindings whose name starts with '_' are intentionally unused and
      -- must not be referenced — regardless of whether they happen to be
      -- in scope (they can be, e.g. an unused-but-kept top-level definition).
      QName [] n | "_" `T.isPrefixOf` n -> throwTE (ReferencingIgnored sp n)
      _ -> case M.lookup q env of
        Just t -> pure (TVar sp t t q)
        Nothing ->
          case q of
            QName (_ : _) _ -> throwTE (NotImported sp q) -- looks qualified but missing import
            _ -> throwTE (UnknownVar sp q)
  EParens _sp e ->
    typeOfExpr conEnv tcm env e
  ECon sp name
    | "_" `T.isPrefixOf` name -> throwTE (ReferencingIgnored sp name)
    | otherwise ->
        case M.lookup (qLocal name) env of
          Just t ->
            -- Freshen type variables using source position as unique suffix
            -- to ensure each constructor usage gets a fresh polymorphic instance.
            let suffix = "$" <> show (spanStartLine sp) <> "_" <> show (spanStartCol sp)
                freshened = freshenType suffix t
             in pure (TConRef sp t freshened name)
          Nothing -> throwTE (UnknownConstructor sp name)
  EBuiltIn sp name ->
    case lookupBuiltIn name of
      Just t -> pure (TBuiltIn sp t name)
      Nothing -> throwTE (UnknownBuiltIn sp name)
  EApp sp f x -> do
    tfE <- typeOfExpr conEnv tcm env f
    case texprType tfE of
      TyArrow _ a b -> do
        -- Arguments with no synthesis form (bare integer literals —
        -- no defaulting; lambdas; 'do' blocks) typecheck only against
        -- the expected argument type from the callee's signature, so
        -- we delegate to 'checkExpr' for those shapes (which also
        -- inserts any 'TCoerce' the argument's row position needs).
        -- 'EParens' wraps each shape transparently.
        let checkAgainstA = do
              xE <- checkExpr conEnv tcm S.empty env a x
              -- A lambda / literal argument has no synthesisable root
              -- type, but its body can still pin tyvars shared with the
              -- callee's signature — the @e2@ in a row-combinator
              -- continuation @\\_n -> ob@. Recover that substitution and
              -- push it through the result type and the function
              -- sub-tree, exactly as the synth path's 'unify' does, so
              -- the call head's instantiated type is fully concrete for
              -- row-monomorphisation downstream.
              let s = argSubstT a xE
              pure (TApp sp (applySubst s b) (substTExpr s tfE) [substTExpr s xE])
        case x of
          ELit _ (LInt _) -> checkAgainstA
          EParens _ (ELit _ (LInt _)) -> checkAgainstA
          ELam {} -> checkAgainstA
          EParens _ ELam {} -> checkAgainstA
          EDo {} -> checkAgainstA
          EParens _ EDo {} -> checkAgainstA
          _ -> do
            xE <- typeOfExpr conEnv tcm env x
            let tx = texprType xE
            -- Prefer 'unify' so any tyvar-binding substitution flows
            -- into the result type ('applySubst s b') and into both
            -- sub-'TExpr's ('substTExpr s'); fall back to 'rowSubsume'
            -- when 'unify' fails on row-shape mismatches the
            -- typechecker has decided are still subsumable, recording
            -- the widening as an explicit 'TCoerce' on the argument.
            -- The fallback covers two cases: direct row injection
            -- (@ErrA ⊆ (ErrA | ErrB)@), and cross-boundary injection
            -- through a nominal head (@Maybe Bool ⊆ Maybe (Bool | Unit)@).
            case unify a tx of
              Right s ->
                -- The call-site subst flows through the function subtree's
                -- node types — this is where instantiation propagates up
                -- the spine. No row coercion is inserted here: a successful
                -- 'unify' means the argument already matches the parameter
                -- (modulo this subst), so there is no widening to record.
                -- Row injection happens only on the 'Left' branch below,
                -- where 'unify' failed but 'rowSubsume' accepts a sub-row
                -- into a wider one. This relies on 'unifyRows' rejecting a
                -- concrete sub-row flowing into a wider concrete row (e.g.
                -- @Maybe Bool@ does not unify with @Maybe (Bool | Unit)@);
                -- if that invariant ever relaxes, this branch must insert a
                -- 'TCoerce' too.
                pure (TApp sp (applySubst s b) (substTExpr s tfE) [substTExpr s xE])
              Left _ ->
                if rowSubsume a tx
                  then
                    let xE' = if needsRowCoerce a tx then TCoerce (exprSpan x) tx a xE else xE
                     in pure (TApp sp b tfE [xE'])
                  else throwTE (TypeMismatch a tx x)
      _ -> throwTE (NotAFunction f (texprType tfE))
  -- @x |> f@ is pure syntax for @f x@. Delegating to the 'EApp' clause
  -- means @|>@ inherits all of its bidirectional special-cases (lambda
  -- argument, integer-literal in argument position, constructor-spine
  -- check, …) for free. The synthesised @EApp@ keeps the original span,
  -- so locations in any error remain accurate.
  EInfix sp OpPipe l r -> typeOfExpr conEnv tcm env (EApp sp r l)
  -- String concatenation `a ++ b` is defined for (String, String) and
  -- returns `Either StringTooLong String`. The 'Left StringTooLong' arm
  -- is produced by every backend's '__concat' runtime helper when the
  -- combined UTF-16 length would exceed 'maxStringLengthUtf16CodeUnits'.
  EInfix sp OpConcat l r -> do
    lE <- typeOfExpr conEnv tcm env l
    rE <- typeOfExpr conEnv tcm env r
    let tl = texprType lE
        tr = texprType rE
    if tl == TyCon noSpan "String" && tr == TyCon noSpan "String"
      then
        let resTy =
              TyApp
                noSpan
                (TyApp noSpan (TyCon noSpan "Either") (TyCon noSpan "StringTooLong"))
                (TyCon noSpan "String")
            -- @a ++ b@ lowers to @CCall (CBuiltIn "concatString") [a, b]@;
            -- the elaborated form mirrors that as a call to the built-in.
            concatTy = TyArrow noSpan (TyCon noSpan "String") (TyArrow noSpan (TyCon noSpan "String") resTy)
         in pure (TApp sp resTy (TBuiltIn sp concatTy "concatString") [lE, rE])
      else
        -- pick the first offender for a more helpful message
        let blame = if tl /= TyCon noSpan "String" then tl else tr
         in throwTE (TypeMismatch (TyCon noSpan "String") blame (EInfix sp OpConcat l r))
  ECase sp scrut alts _ -> do
    -- Synthesis-position 'case': we have no crossExempt context here
    -- (the caller's check-mode 'checkExpr' would have one, but a
    -- nested synth-position ECase doesn't carry it through). Pattern
    -- variables in this branch are checked against the same scope
    -- they'd hit elsewhere; cross-module shadowing only applies on
    -- the check-mode path.
    (scrutE, elab) <- caseArms conEnv tcm S.empty env sp scrut alts (typeOfExpr conEnv tcm)
    -- All arms must agree on the result type (via unification, not equality).
    let armBodyTypes = case elab of
          NominalArms talts -> map (texprType . tAltBody) talts
          RowArms tralts -> map (texprType . tRowAltBody) tralts
    resultTy <- case armBodyTypes of
      [] -> throwTE (TELowering "case expression with no arms (unreachable: NonEmpty CaseAlt)")
      (firstTy : restTys) ->
        foldM
          ( \acc ty -> case unify acc ty of
              Right s -> pure (applySubst s acc)
              Left _ -> throwTE (CaseBranchTypeMismatch acc ty scrut)
          )
          firstTy
          restTys
    pure $ case elab of
      NominalArms talts -> TCase sp resultTy scrutE talts
      RowArms tralts -> TRowCase sp resultTy scrutE tralts
  -- Lambdas in synthesis position get fresh tyvars per parameter,
  -- suffixed by the lambda's source span so two distinct lambdas
  -- never share a tyvar name (mirrors the @"$check"@ / @"$scrut"@
  -- suffixing pattern 'freshenType' uses elsewhere). The body is
  -- synthesised in the extended env; the result type is the curried
  -- arrow chain.
  --
  -- Why this is sound without let-generalisation. Each downstream
  -- 'EVar' lookup of the let-bound name returns the stored arrow
  -- type unchanged, and each 'EApp' runs its 'unify' locally without
  -- propagating the resulting substitution back into 'env'. So two
  -- uses of the same let-bound lambda at different concrete types
  -- ('id 5' and 'id "hello"') do not interact: each one binds the
  -- shared tyvar locally, returns its result, and discards the
  -- substitution. We therefore get operationally-correct
  -- polymorphism for closed lambdas without the full HM-monad
  -- threading.
  ELam sp params body -> do
    lps <- liftEither (mapM classifyLamParam params)
    liftEither (checkNoShadow env S.empty (lamParamShadowEntries lps))
    -- In synthesis position no expected type flows in, so a plain param
    -- gets a fresh (span-suffixed, so distinct uses of a polymorphic
    -- lambda don't interact) tyvar. An annotated param contributes its
    -- annotation as the parameter type instead — the only way to pin a
    -- synthesis-position lambda's input (e.g. @let f = \\(n : Int32) -> …@)
    -- without spelling out the whole arrow, since body-driven
    -- constraints are not threaded back into the arrow type here.
    let suffix = "$" <> show (spanStartLine sp) <> "_" <> show (spanStartCol sp)
        resolveSynth (LamPlain pSp n) = (pSp, n, TyVar pSp (n <> suffix))
        resolveSynth (LamAnnot pSp n annT) = (pSp, n, annT)
        resolved = map resolveSynth lps
        paramTys = [t | (_, _, t) <- resolved]
        bindings = [(n, t) | (_, n, t) <- resolved]
        env' = M.union (M.fromList [(qLocal n, t) | (n, t) <- bindings]) env
    bodyE <- typeOfExpr conEnv tcm env' body
    let arrowTy = foldr (TyArrow noSpan) (texprType bodyE) paramTys
        tparams = [TParam pSp t n | (pSp, n, t) <- resolved]
    pure (TLam sp arrowTy tparams bodyE)
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
  ELet lsp pat mAnnot e body ->
    elabLet conEnv tcm S.empty env lsp pat mAnnot e $ \envNext -> do
      bodyE <- typeOfExpr conEnv tcm envNext body
      pure (bodyE, texprType bodyE)
  -- 'do'-blocks also need an expected type — the desugaring goes
  -- through 'bindEither' whose return rows accumulate only when the
  -- surrounding context constrains them.
  EDo sp _ -> throwTE (DoInSynthesisPosition sp)
  -- Expression-level type ascription @(e : T)@: bidirectional anchor.
  -- The user-written @T@ becomes the expected type for the inner
  -- expression, then is also the synthesised result. This is what
  -- makes @(42 : Int32)@, @pureEither (42 : Int32)@, etc. work —
  -- the ascription pins a context that synthesis alone cannot.
  -- 'crossExempt' resets to 'S.empty' at this synth boundary, same
  -- convention as 'ELet' / 'ECase' here.
  --
  -- If the surrounding context disagrees with @T@, the 'checkExpr'
  -- catch-all subsumes the synthesised @T@ against the ambient
  -- expected and reports any mismatch pointing at the @(e : T)@ form.
  EAscribe _sp e ty ->
    checkExpr conEnv tcm S.empty env ty e

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
  (Env -> Expr -> Check TExpr) ->
  Check (TExpr, CaseElab)
caseArms conEnv tcm crossExempt env sp scrut alts runBody = do
  scrutE <- typeOfExpr conEnv tcm env scrut
  let scrutTy = texprType scrutE
  elab <- case scrutTy of
    -- Structural-sum scrutinee: rows have a different exhaustiveness
    -- model (PAscribe arms covering each label) and forbid catch-all
    -- patterns; dispatch to a dedicated helper.
    TyOr {} -> caseArmsRow conEnv tcm crossExempt env sp scrutTy alts runBody
    -- Nominal-sum scrutinee: existing path.
    _ -> caseArmsNominal scrutTy
  pure (scrutE, elab)
  where
    caseArmsNominal scrutTy = do
      -- Scrutinee must be a user-defined sum type.
      tyName <- case extractTyCon scrutTy of
        Just n | M.member n tcm -> pure n
        _ -> throwTE (CaseOnNonSumType sp scrutTy)
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
      (talts, coveredPatterns) <- foldM (handleArm sp scrutTy env scrutSubst) ([], []) (toList alts)
      -- Exhaustiveness: every inhabited constructor must appear at least once.
      -- For simple patterns (no nesting), each constructor should appear exactly once.
      let topLevelCons = [cName | (cName, _) <- coveredPatterns]
          missing = filter (`notElem` topLevelCons) allCons
          inhabitedMissing = filter (isConInhabited conEnv tcm S.empty scrutSubst) missing
      unless (null inhabitedMissing) $ throwTE (NonExhaustiveCase sp tyName inhabitedMissing)
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
            liftEither $ zipWithM_ (checkPatternColumnCovers sp conEnv tcm) fieldTys columns
          _ -> pass
      pure (NominalArms talts)

    handleArm caseSp scrutTy envLocal scrutSubst (talts, patterns) alt = case caseAltPattern alt of
      PCon patSp cName pats -> do
        let body = caseAltBody alt
        -- Reject @_X@ constructor references at any depth in the pattern.
        liftEither (mapM_ (rejectIgnoredConstructor conEnv) (PCon patSp cName pats : pats))
        -- Verify the constructor belongs to the scrutinee type.
        ci <- liftEither (maybeToRight (UnknownConstructor (exprSpan body) cName) (M.lookup cName conEnv))
        -- Reject duplicate (unreachable) patterns by comparing full pattern structure.
        let currentPattern = (cName, pats)
        when (patternMatches conEnv currentPattern patterns) $ throwTE (UnreachableCase caseSp cName)
        -- Reject shadowing: pattern variables (including those in nested patterns)
        -- must not duplicate each other and must not collide with anything
        -- already visible in the arm. Each binder carries its own span so the
        -- error arrow lands on the offending identifier, not on a usage site.
        liftEither (checkNoShadow envLocal crossExempt (collectPatternVars pats))
        -- Compute field types with proper freshening and substitution.
        -- First freshen the constructor's field types with the same suffix used for scrutSubst,
        -- then apply the matched substitution.
        let freshFieldTys = map (freshenType "$scrut") (ciFieldTypes ci)
            fieldTys = map (applySubst scrutSubst) freshFieldTys
        -- Reject patterns on uninhabited constructors (unreachable).
        case find (not . isTypeInhabited conEnv tcm) fieldTys of
          Just emptyTy -> throwTE (UnreachableCaseUninhabited caseSp cName emptyTy)
          Nothing -> pass
        -- Bind pattern variables from constructor fields.
        let bindings = patternBindings conEnv pats fieldTys
            envWithBindings = M.union (M.fromList [(qLocal n, t) | (n, t) <- bindings]) envLocal
        bodyE <- runBody envWithBindings body
        let talt = TAlt (elabPattern conEnv (PCon patSp cName pats) scrutTy) bodyE
        pure (talts <> [talt], patterns <> [currentPattern])
      other ->
        throwTE (NonConstructorNominalArm (patternSpan other) scrutTy)

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
  (Env -> Expr -> Check TExpr) ->
  Check CaseElab
caseArmsRow conEnv tcm crossExempt env sp scrutTy alts runBody = do
  (tralts, ascribed, perLabelConArms) <-
    foldM handleRowArm ([], [], M.empty) (toList alts)
  let missing = filter (`notExhaust` (ascribed, perLabelConArms)) labels
  unless (null missing) $ throwTE (NonExhaustiveRow sp missing scrutTy)
  -- Recursive inner-pattern coverage: for each label covered by 'PCon'
  -- arms, every constructor of the nominal type must appear, and the
  -- merged inner-pattern lists must in turn cover the substituted
  -- field types.
  forM_ (M.toList perLabelConArms) $ uncurry checkLabelConCoverage
  pure (RowArms tralts)
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

    handleRowArm (tralts, ascribed, perCon) alt = case caseAltPattern alt of
      PAscribe patSp inner ascrTy -> do
        let body = caseAltBody alt
        unless (ascrTy `elem` labels)
          $ throwTE (RowLabelNotInScrut patSp ascrTy scrutTy)
        when (ascrTy `elem` ascribed)
          $ throwTE (DuplicateRowArm patSp ascrTy)
        when (ascrTy `M.member` perCon)
          $ throwTE (DuplicateRowArm patSp ascrTy)
        liftEither (rejectIgnoredConstructor conEnv inner)
        liftEither (checkNoShadow env crossExempt (collectPatternVars [inner]))
        -- Bind the inner pattern with the ascribed type — that is the
        -- key semantic difference from a nominal arm: 'n' in
        -- @case x of (n : Int32) -> …@ is bound at type 'Int32', not
        -- at the scrutinee's union type.
        let bindings = patternBindings conEnv [inner] [ascrTy]
            envWithBindings = M.union (M.fromList [(qLocal n, t) | (n, t) <- bindings]) env
        bodyE <- runBody envWithBindings body
        -- Keep the 'TPAscribe' wrapper so lowering can tell a @(x : T)@
        -- row arm from a constructor arm (both inner shapes could
        -- otherwise elaborate to the same typed pattern).
        let tralt = TRowAlt ascrTy (TPAscribe patSp ascrTy (elabPattern conEnv inner ascrTy)) bodyE
        pure (tralts <> [tralt], ascribed <> [ascrTy], perCon)
      PCon patSp cName innerPats -> do
        let body = caseAltBody alt
        ci <- liftEither (maybeToRight (UnknownConstructor patSp cName) (M.lookup cName conEnv))
        let cTyName = ciTypeName ci
        label <-
          liftEither (maybeToRight (RowLabelNotForConstructor patSp cName scrutTy) (findLabel cTyName))
        when (label `elem` ascribed)
          $ throwTE (DuplicateRowArm patSp label)
        liftEither (rejectIgnoredConstructor conEnv (PCon patSp cName innerPats))
        liftEither (checkNoShadow env crossExempt (collectPatternVars innerPats))
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
        bodyE <- runBody envWithBindings body
        let tralt = TRowAlt label (elabPattern conEnv (PCon patSp cName innerPats) label) bodyE
            perCon' =
              M.insertWith (M.unionWith (<>)) label (M.singleton cName [(innerPats, fieldTys, patSp)]) perCon
        pure (tralts <> [tralt], ascribed, perCon')
      PVar patSp _ ->
        throwTE (RowCatchAllPattern patSp)
      PWild patSp ->
        throwTE (RowCatchAllPattern patSp)

    -- Verify that the nominal label's constructors are all covered by
    -- the @PCon@ arms gathered for that label, and that for every
    -- constructor the merged inner-pattern columns exhaust their field
    -- types.
    checkLabelConCoverage label byCon = do
      tyName <-
        liftEither (maybeToRight (CaseOnNonSumType sp label) (extractTyCon label))
      ci <-
        liftEither
          $ maybeToRight (CaseOnNonSumType sp label)
          $ find (\c -> ciTypeName c == tyName) (M.elems conEnv)
      let allCons = ciSiblings ci
          present = M.keys byCon
          missingCons = filter (`notElem` present) allCons
      unless (null missingCons)
        $ throwTE (NonExhaustiveCase sp tyName missingCons)
      -- For each present constructor, verify the inner patterns column-
      -- wise cover the substituted field types.
      forM_ (M.toList byCon) $ \(_cName, armsForCon) -> case armsForCon of
        [] -> pass
        ((_, fieldTys0, _) : _) ->
          let columns = transpose [pats | (pats, _, _) <- armsForCon]
           in liftEither $ zipWithM_ (checkPatternColumnCovers sp conEnv tcm) fieldTys0 columns

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
              -- Freshening suffix must be '"$scrut"' so the keys line
              -- up with the '"$scrut"'-freshened field types inside
              -- 'isConInhabited' (and the recursive
              -- 'checkPatternColumnCovers' below). With a different
              -- suffix the substitution silently no-ops and uninhabited
              -- siblings get reported as missing.
              tySubst =
                let genericRetTy = conReturnType tyName (ciTypeParams ci)
                    freshGenericRetTy = freshenType "$scrut" genericRetTy
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
                let freshFieldTys = map (freshenType "$scrut") (ciFieldTypes ci')
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

-- | The source span of a pattern's own node (constructor name,
--   identifier, underscore, or the whole parenthesised ascription).
patternSpan :: Pattern -> SrcSpan
patternSpan = \case
  PCon sp _ _ -> sp
  PVar sp _ -> sp
  PWild sp -> sp
  PAscribe sp _ _ -> sp

-- | Build a typed pattern ('TPattern') from a surface 'Pattern' and the
--   type it matches. Mirrors 'patternBindings'\'s recursion: a 'PCon'
--   field's type is derived by unifying the constructor's freshened
--   return type with the matched type and substituting into its field
--   types; a 'PAscribe' overrides the matched type with the ascribed
--   alternative. Each binder ('TPVar') carries its resolved type so
--   lowering can pick its 'Awsum.Core.CDropKind'.
elabPattern :: ConEnv -> Pattern -> Type' -> TPattern
elabPattern conEnv = go
  where
    go (PVar sp n) ty = TPVar sp ty n
    go (PWild sp) ty = TPWild sp ty
    go (PAscribe sp inner ascrTy) _ty = TPAscribe sp ascrTy (go inner ascrTy)
    go (PCon sp cName innerPats) ty =
      case M.lookup cName conEnv of
        Nothing -> TPCon sp ty cName []
        Just ci ->
          let genericRetTy = conReturnType (ciTypeName ci) (ciTypeParams ci)
              freshGenericRetTy = freshenType "$inner" genericRetTy
              freshFieldTys = map (freshenType "$inner") (ciFieldTypes ci)
              innerSubst = fromRight mempty (unify freshGenericRetTy ty)
              fieldTys = map (applySubst innerSubst) freshFieldTys
           in TPCon sp ty cName (zipWith go innerPats fieldTys)

-- | How 'caseArms' classified the scrutinee: a nominal sum (each arm a
--   'TAlt') or a structural sum / row (each arm a 'TRowAlt' tagged by
--   the row label it selects). The 'ECase' clauses build a 'TCase' or
--   'TRowCase' from it.
data CaseElab = NominalArms [TAlt] | RowArms [TRowAlt]

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
-- 'TyEmpty' carries the same nominal name as the originating
-- declaration; for the purposes of exhaustiveness and constructor
-- lookup it behaves like a 'TyCon' (the name resolves to a
-- 'TypeDecl' with zero constructors — every @empty type X@ has zero
-- constructors by parser-side rejection).
extractTyCon (TyEmpty _ n) = Just n
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
      EAscribe _ e _ -> go e
      ELit _ _ -> S.empty
      ECon _ _ -> S.empty
      EBuiltIn _ _ -> S.empty
      ECase _ scrut alts _ ->
        go scrut <> foldMap goAlt (toList alts)
      ELam _ params body ->
        go body `S.difference` S.fromList (map paramName params)
      EDo _ stmts -> goDoStmts stmts
      ELet _ pat _ e body -> go e <> (go body `S.difference` patternBoundNames pat)
    goAlt alt = go (caseAltBody alt) `S.difference` patternBoundNames (caseAltPattern alt)
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
