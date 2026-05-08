-- | Surface syntax for Awsum.
--
-- Invariants & conventions (enforced by the parser, not the types here):
--  • Module segments (in imports) are UpperCamelCase, value names are lowerCamelCase.
--  • Arrow types are right-associative (a -> b -> c == a -> (b -> c)).
module Awsum.Syntax
  ( Name,
    SrcSpan (..),
    noSpan,
    spanBetween,
    exprSpan,
    Program (..),
    ImportDecl (..),
    Decl (..),
    EmptyKind (..),
    ConDef (..),
    Type' (..),
    QName (..),
    Op' (..),
    Literal (..),
    Expr (..),
    DoStmt (..),
    CaseAlt (..),
    caseAltLeading,
    caseAltPattern,
    caseAltBody,
    caseAltTrailing,
    mkCaseAlt,
    isBlockBody,
    Pattern (..),
    Comment (..),
    Param (..),
    paramName,
    paramSpan,
    typeSpan,
  )
where

import Relude

-- | Source span: start and end positions (1-based, matching Megaparsec and editors).
data SrcSpan = SrcSpan
  { spanStartLine :: !Int,
    spanStartCol :: !Int,
    spanEndLine :: !Int,
    spanEndCol :: !Int
  }
  deriving stock (Show)

-- | SrcSpan equality is always True so that AST equality ignores positions.
--   This lets all existing tests continue working without changing expected values.
instance Eq SrcSpan where _ == _ = True

-- | SrcSpan ordering also ignores positions (mirrors 'Eq') so derived
--   'Ord' on AST nodes with embedded spans compares only the semantic
--   parts. Needed because 'Type'' derives 'Ord' and is used as a key
--   elsewhere.
instance Ord SrcSpan where compare _ _ = EQ

-- | Placeholder span for hand-constructed ASTs (tests, Arbitrary instances).
noSpan :: SrcSpan
noSpan = SrcSpan 0 0 0 0

-- | Combine two spans into one covering both.
spanBetween :: SrcSpan -> SrcSpan -> SrcSpan
spanBetween a b = SrcSpan (spanStartLine a) (spanStartCol a) (spanEndLine b) (spanEndCol b)

-- | Extract the source span from an expression.
exprSpan :: Expr -> SrcSpan
exprSpan = \case
  EVar sp _ -> sp
  EApp sp _ _ -> sp
  EInfix sp _ _ _ -> sp
  EParens sp _ -> sp
  ELit sp _ -> sp
  ECon sp _ -> sp
  ECase sp _ _ _ -> sp
  EBuiltIn sp _ -> sp
  ELam sp _ _ -> sp
  EDo sp _ -> sp
  ELet sp _ _ _ _ -> sp

-- | Lexical identifier (kept as 'Text' for simplicity).
--   The parser is responsible for validating case/style rules.
type Name = Text

-- | Qualified module path, e.g. @IO.Stdout@ ⇒ @\"IO\" :| [\"Stdout\"]@.
type ModulePath = NonEmpty Name

-- | A single source file: zero or more imports and a /non-empty/ list of top-level declarations.
--   Parser guarantees @decls@ is 'NonEmpty' (empty programs are rejected).
data Program = Program
  { -- | @import Foo.Bar@
    imports :: [ImportDecl],
    -- | at least one declaration
    decls :: NonEmpty Decl
  }
  deriving stock (Show, Eq)

-- | Import declaration with optional leading comments and trailing inline comment.
--   Leading comments appear before the @import@ keyword on preceding lines;
--   the trailing comment is an optional @-- …@ on the same line.
data ImportDecl = ImportDecl [Comment] ModulePath (Maybe Text)
  deriving stock (Show, Eq)

-- Comments (payloads are stored *without* delimiters)
data Comment
  = LineComment Text -- text after "--"
  | BlockComment Text -- text between "{-" and "-}"
  deriving stock (Show, Eq)

-- | A bound function parameter, with the source span of the identifier.
--   Spans let downstream tooling (warnings, quick-fixes) point at exactly
--   the offending parameter rather than the whole definition.
--
--   The two constructors mirror the two surface shapes:
--
--     * @Param sp n@ — a plain name (@f x = …@). The common case;
--       the typechecker and lowering only ever see this variant.
--     * @ParamPat sp pat@ — a destructuring pattern
--       (@f (Tuple3 a b c) = …@). The 'Awsum.Desugar' pass
--       rewrites every 'ParamPat' to a fresh 'Param' plus a
--       single-arm 'ECase' wrapping the body, so by the time the
--       AST reaches typecheck only 'Param' remains. Keeping
--       'ParamPat' in the AST (rather than desugaring at parse
--       time) lets the renderer round-trip the original source
--       shape.
data Param
  = Param SrcSpan Name
  | ParamPat SrcSpan Pattern
  deriving stock (Show, Eq)

-- | Extract the textual name of a parameter. For 'ParamPat' returns
--   the leading binder name extracted from the pattern (a defensive
--   value used by error messages; the desugarer normally rewrites
--   'ParamPat' away before any code looks at the name).
paramName :: Param -> Name
paramName (Param _ n) = n
paramName (ParamPat _ pat) = patternLeadName pat
  where
    patternLeadName = \case
      PVar _ n -> n
      PWild _ -> "_"
      PCon _ c _ -> c
      PAscribe _ inner _ -> patternLeadName inner

-- | Extract the source span of a parameter (the identifier or
--   pattern itself).
paramSpan :: Param -> SrcSpan
paramSpan (Param sp _) = sp
paramSpan (ParamPat sp _) = sp

-- | Marker on a 'TypeDecl' distinguishing the two ways an uninhabited
--   type can be declared. 'NotEmpty' is an ordinary type declaration;
--   the type may have zero constructors (uninhabited but a distinct
--   row label) or any positive number. 'Empty' is the @empty type X@
--   form: explicitly declared empty, treated as the row identity by
--   the typechecker — any two 'Empty'-declared types are
--   interchangeable in row positions, and a value of an 'Empty' type
--   subsumes into any expected type via 'Awsum.HM.rowSubsume'. The
--   parser rejects @empty type X = …@ (constructors not allowed) and
--   @empty type X a@ (parameters not allowed); the field on
--   'TypeDecl' is what the typechecker consults to lift each TyCon
--   reference to a 'TyEmpty' before unification or row work.
data EmptyKind = NotEmpty | Empty
  deriving stock (Show, Eq, Ord)

-- | Top-level declaration.
data Decl
  = -- | Type signature: @main : τ -- comment@
    Sig SrcSpan Name Type' (Maybe Text)
  | -- | Function/value definition: @f x y = e  -- comment@.
    --   The argument list may be empty in the /surface/.
    --   Lowering will treat zero-arg defs as /constants/.
    FunDef SrcSpan Name [Param] Expr (Maybe Text)
  | -- | Sum type declaration. Two surface forms:
    --
    --   @type Bool = True | False@ — ordinary type, possibly with
    --   constructors; zero-constructor variant @type Never@ is
    --   uninhabited but a distinct row label.
    --
    --   @empty type Never@ — explicitly empty; row identity per
    --   'EmptyKind'. Forbidden: constructors and parameters on this
    --   form.
    --
    --   Type parameters carry their own span (as 'Param') so the
    --   unused-type-parameter warning can target precisely the
    --   identifier.
    TypeDecl SrcSpan Name [Param] [ConDef] (Maybe Text) EmptyKind
  | CommentDecl Comment
  deriving stock (Show, Eq)

-- | Constructor definition inside a 'TypeDecl'.
--   The 'SrcSpan' covers just the constructor's name in the source so
--   quick-fixes (e.g. rename '_C' to 'C') can target it precisely.
--   Field types are stored for future use (e.g. @Just a@); empty for nullary constructors.
data ConDef = ConDef SrcSpan Name [Type']
  deriving stock (Show, Eq)

-- | Surface types. Each constructor carries a 'SrcSpan' covering the
--   portion of source that introduced it, so diagnostics can point at a
--   single type identifier (e.g. a @_A@ reference) instead of the whole
--   signature line. Spans are ignored by derived 'Eq' / 'Ord'.
data Type'
  = -- | Type variable, e.g. 'a'.
    TyVar SrcSpan Name
  | -- | Type constructor, e.g. @\"String\"@, @\"IO\"@.
    TyCon SrcSpan Name
  | -- | Reference to a type declared with @empty type X@. Distinct
    --   from 'TyCon' because the typechecker treats every 'TyEmpty'
    --   as the row identity: two distinct 'TyEmpty' names unify (the
    --   type system is the same uninhabited type up to renaming),
    --   any 'TyEmpty' subsumes into any row position, and
    --   'canonicalLabel' folds them all to a single canonical
    --   @\"_empty\"@ tag so codegen-side row-tag dispatch agrees with
    --   type-system equivalence. The original name is preserved for
    --   diagnostics. Created by the elaborator from a parsed
    --   'TyCon' once the program's empty-type set is known —
    --   parser-time output is always 'TyCon'.
    TyEmpty SrcSpan Name
  | -- | Type application, e.g. @Lookup String@.
    TyApp SrcSpan Type' Type'
  | -- | Arrow type @a -> b@ (right-associative by convention).
    TyArrow SrcSpan Type' Type'
  | -- | Structural sum type @T1 | T2@ — the syntactic form of an
    --   anonymous union of two alternatives. Right-associative as
    --   stored, but treated set-associatively (commutative, idempotent)
    --   by the unifier. Precedence: lower than @->@, so @(A | B) -> C@
    --   requires parens around the union to keep it on the LHS of the
    --   arrow.
    TyOr SrcSpan Type' Type'
  deriving stock (Show, Eq, Ord)

-- | Extract the source span of a type.
typeSpan :: Type' -> SrcSpan
typeSpan = \case
  TyVar sp _ -> sp
  TyCon sp _ -> sp
  TyEmpty sp _ -> sp
  TyApp sp _ _ -> sp
  TyArrow sp _ _ -> sp
  TyOr sp _ _ -> sp

-- | Qualified value name: module path (possibly empty) + base name.
--   Examples:
--     • @IO.Stdout.print@ ⇒ @QName [\"IO\",\"Stdout\"] \"print\"@
--     • @input@           ⇒ @QName [] \"input\"@
data QName = QName [Name] Name
  deriving stock (Show, Eq, Ord)

-- | Infix operator tags used by the surface syntax.
--   Extend this when new symbolic ops appear (remember to update parser/render/fixities).
data Op'
  = -- | @e1 ++ e2@ (left-associative, tighter than @|>@)
    OpConcat
  | -- | @e1 |> e2@ — left-pipe, left-associative, lowest precedence.
    --   Pure syntactic rewrite: @x |> f@ lowers to @EApp f x@ in
    --   'Awsum.ElaborateLower' before any Core-to-Core pass sees it,
    --   so there is no residual call frame and @(|>)@ is not a name.
    OpPipe
  deriving stock (Show, Eq)

-- | Literals in the surface language.
--   Integer literals are untyped at the syntax level — the type is determined by
--   context during typechecking (no defaulting).
data Literal
  = LString Text
  | LInt Integer
  deriving stock (Show, Eq)

-- | Surface expressions.
data Expr
  = -- | Variable or qualified function name.
    EVar SrcSpan QName
  | -- | Function application (left-associative).
    EApp SrcSpan Expr Expr
  | -- | Infix application (e.g. @++@). Parser assigns fixities.
    EInfix SrcSpan Op' Expr Expr
  | -- | Explicit parentheses as written by the user.
    --   Kept to make render ∘ parse an identity in tests.
    EParens SrcSpan Expr
  | -- | Literal (currently only strings).
    ELit SrcSpan Literal
  | -- | Constructor reference (uppercase, e.g. @True@, @Nothing@).
    ECon SrcSpan Name
  | -- | Pattern matching: @case e of { alt1; alt2; … }@.
    --   The trailing @[Comment]@ holds comments after the last arm — useful for
    --   temporarily commenting-out the last alternative while editing.
    ECase SrcSpan Expr (NonEmpty CaseAlt) [Comment]
  | -- | Reference to a compiler-provided built-in: @BuiltIn.foo@.
    --   'BuiltIn' is a reserved namespace, not a user module — the parser
    --   recognises this form directly and the typechecker resolves the
    --   name against the compiler's built-in table. Used in @stdlib/Prelude.aww@
    --   to forward surface functions (e.g. @showInt32 = BuiltIn.showInt32@)
    --   to their per-target implementations.
    EBuiltIn SrcSpan Name
  | -- | Lambda abstraction: @\\x y -> body@. Always at least one
    --   parameter; the parser forbids the zero-arg form.
    --
    --   Lambdas have no synthesis form — they only typecheck against an
    --   expected arrow type from surrounding context (a function-arg
    --   position, a top-level signature's return shape, etc.). At
    --   lowering time they are lifted to fresh top-level helpers with
    --   captured free variables added as explicit parameters; the
    --   surface expression itself becomes a partial application of the
    --   helper to the captures.
    ELam SrcSpan [Param] Expr
  | -- | @do@ block: a sequence of statements desugared at the next
    --   pass into a chain of 'bindEither' calls whose trailing
    --   expression is the user's verbatim (typically a 'pureEither'
    --   application). Hardcoded to the @Either@ monad shape in this
    --   iteration — there is no type-class dispatch yet.
    EDo SrcSpan [DoStmt]
  | -- | Let-binding: @let n = e in body@ or @let n : T = e in body@.
    --   Binds @n@ to the value of @e@ in scope of @body@. The
    --   optional 'Type' is the user-written ascription on the
    --   binder; when present, @e@ is checked against it (which
    --   lets the typechecker push an expected type down through
    --   shapes whose result row would otherwise be ambiguous,
    --   e.g. a @do@-block whose @<-@ steps return @Either@ with
    --   different error labels).
    --
    --   Lowering synthesises a fresh top-level helper
    --   @$let$N captures n = body'@ and emits a saturated call
    --   @$let$N captures e@ — same machinery as 'ELam' lifting but
    --   the application is fully applied at the call site, so
    --   saturate sees a direct call and no PAP / closure runtime
    --   is needed.
    --
    --   @do@-blocks containing @let@ desugar to nested 'ELet's
    --   wrapping the rest of the block (one 'ELet' per @let@
    --   statement); see 'Awsum.Desugar'.
    ELet SrcSpan Pattern (Maybe Type') Expr Expr
  deriving stock (Show, Eq)

-- | A single statement inside a 'EDo' block. Each statement maps to
--   one node in the desugared chain:
--
--   * @DoBind p e@ — @p <- e@. The continuation runs with the bound
--     pattern in scope; desugar to @bindEither e (\\p -> rest)@.
--   * @DoLet n e@ — @let n = e@ (or @let n : T = e@). Binds @n@ to
--     the value of @e@ for the rest of the block. The optional
--     'Type' is the user-written ascription, used when the
--     synthesised RHS type would otherwise be ambiguous (same role
--     as on standalone 'ELet'). Desugars to an 'ELet' wrapping the
--     remaining statements (the body of which is the trailing
--     'DoExpr').
--   * @DoExpr e@ — a bare expression. As the last statement it is the
--     block's result; in earlier positions the typechecker rejects it
--     since we have no @>>@ analogue without a unit type at the row.
data DoStmt
  = DoBind SrcSpan Pattern Expr
  | DoLet SrcSpan Pattern (Maybe Type') Expr
  | DoExpr SrcSpan Expr
  deriving stock (Show, Eq)

-- | A single alternative in a @case@ expression.
--   Leading comments appear before the arm; trailing is an optional inline
--   @-- …@ that the parser only encounters when the body's render ends on
--   the same line as the arm started.
--
--   Two constructors split by body shape because of a parser invariant:
--   when the body is /block-form/ (an @ECase@ or @EDo@ that ends inside
--   its own last arm/stmt, transitively reachable through @ELet@ / @ELam@
--   / @EApp@ / @EInfix@ tails), any trailing @--@ on the same line as the
--   inner last arm is consumed by /that inner arm/, and the outer arm is
--   left without a trailing comment. The parser therefore never builds
--   @CaseAlt@ with trailing on a block-form body. Encoding the same
--   invariant in the type prevents 'Arbitrary Expr' from generating an
--   unparseable shape and lets nested @ECase@/@EDo@ flow through the
--   property-test generator.
--
--   Preserving comments inside indented blocks (before, between, and after arms)
--   lets users comment-out / uncomment individual case arms while editing, without
--   the formatter destroying those comments on save.
data CaseAlt
  = -- | Body's render does not /end inside/ a nested case/do — the
    --   parser can pick up an optional trailing @-- …@ on the same line.
    CaseAltLeaf [Comment] Pattern Expr (Maybe Text)
  | -- | Body's render ends inside its own last arm/stmt — a trailing
    --   @--@ is impossible at the parser level, so the constructor has
    --   no slot for it.
    CaseAltBlock [Comment] Pattern Expr
  deriving stock (Show, Eq)

-- | Leading comments of an arm — present on either constructor.
caseAltLeading :: CaseAlt -> [Comment]
caseAltLeading = \case
  CaseAltLeaf c _ _ _ -> c
  CaseAltBlock c _ _ -> c

-- | Pattern of an arm.
caseAltPattern :: CaseAlt -> Pattern
caseAltPattern = \case
  CaseAltLeaf _ p _ _ -> p
  CaseAltBlock _ p _ -> p

-- | Body of an arm.
caseAltBody :: CaseAlt -> Expr
caseAltBody = \case
  CaseAltLeaf _ _ b _ -> b
  CaseAltBlock _ _ b -> b

-- | Trailing comment if present. 'CaseAltBlock' has no trailing slot
--   by construction, so it always returns 'Nothing'.
caseAltTrailing :: CaseAlt -> Maybe Text
caseAltTrailing = \case
  CaseAltLeaf _ _ _ t -> t
  CaseAltBlock {} -> Nothing

-- | Smart constructor that picks the right 'CaseAlt' variant based on
--   trailing-presence and body shape. Mirrors what the parser's
--   'Awsum.Parser.groupCaseItems' decides — desugaring and other passes
--   that rebuild arms reuse this so the type-level invariant
--   (no trailing on block-form body) is upheld in one place.
--
--   Discards a 'Just trailing' silently when the body is block-form.
--   That can only happen if upstream code mis-paired them — the parser
--   never produces this combination, so on a well-formed AST the
--   discard is unreachable.
mkCaseAlt :: [Comment] -> Pattern -> Expr -> Maybe Text -> CaseAlt
mkCaseAlt lc pat body mc
  | isBlockBody body = CaseAltBlock lc pat body
  | otherwise = CaseAltLeaf lc pat body mc

-- | Predicate that classifies an expression by whether its rendered form
--   ends in a position where the parser would consume a trailing @--@ as
--   /this/ expression's, rather than as the trailing of some nested
--   case-arm or do-stmt /inside/ it.
--
--   * @ECase@ / @EDo@ at the outermost — block: the last arm/stmt's own
--     trailing-comment slot eats any subsequent @--@.
--   * @ELet@ / @ELam@ — recurse into the body (the let-in body / lambda
--     body /is/ the last syntactic position).
--   * @EApp@ — recurse into the rightmost argument (right-associative
--     application; the rightmost arg is the last token rendered).
--   * @EInfix@ — recurse into the right operand.
--   * @EParens@ — never block: the closing @)@ ends on its own line for
--     multi-line inner forms (see 'Awsum.Render'), so the parser is
--     positioned right after @)@ when looking for trailing.
--   * Everything else (variables, literals, constructors, builtins) —
--     leaf, single-token render.
isBlockBody :: Expr -> Bool
isBlockBody = \case
  ECase {} -> True
  EDo {} -> True
  ELet _ _ _ _ body -> isBlockBody body
  ELam _ _ body -> isBlockBody body
  EApp _ _ x -> isBlockBody x
  EInfix _ _ _ b -> isBlockBody b
  EParens {} -> False
  EVar {} -> False
  ELit {} -> False
  ECon {} -> False
  EBuiltIn {} -> False

-- | Patterns for @case@ alternatives.
--   Currently only constructor patterns; variable and wildcard are for future use.
data Pattern
  = -- | Constructor pattern, e.g. @Just x@. The 'SrcSpan' covers the
    --   constructor's name in the source so quick-fixes targeting the
    --   pattern (e.g. rename '_C' to 'C') can edit precisely.
    --   Fields are empty for nullary constructors.
    PCon SrcSpan Name [Pattern]
  | -- | Variable binding (future). Span covers just the identifier.
    PVar SrcSpan Name
  | -- | Wildcard @_@. Span covers the underscore so diagnostics
    --   targeting the wildcard (e.g. 'RowCatchAllPattern') can point
    --   at it precisely instead of at the surrounding case arm.
    PWild SrcSpan
  | -- | Type-ascribed pattern @(p : T)@: an inner pattern with an
    --   explicit type annotation. Used to discriminate alternatives of
    --   a structural sum at the pattern level — e.g. given a scrutinee
    --   of type @(Int32 | String)@, the pattern @(n : Int32)@ binds @n@
    --   to the @Int32@ alternative. Parens are part of the surface
    --   syntax (not just a parser detail) — without them the @':'@ would
    --   collide with the case-arrow @\'->\'@ in the surface grammar.
    --   The 'SrcSpan' covers the whole parenthesised pattern so editor
    --   tooling can highlight the ascription as a unit.
    PAscribe SrcSpan Pattern Type'
  deriving stock (Show, Eq)
