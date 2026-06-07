-- | The elaborated, type-annotated IR ('TExpr'), produced by the
--   bidirectional typechecker ('Awsum.Typing') and consumed by the
--   row-monomorphisation pass and by lowering to Core
--   ('Awsum.ElaborateLower').
--
--   'TExpr' is a /normalised/ form of the surface 'Awsum.Syntax.Expr',
--   not a one-to-one mirror: it drops the surface-only shapes that carry
--   no post-elaboration meaning — explicit parentheses, @do@ blocks
--   (desugared before the typechecker runs), the @|>@ pipe (rewritten to
--   application), and type ascription (resolved into the node's recorded
--   type). What remains is annotated with the type the typechecker
--   assigned, after the final substitution has been applied.
--
--   Two kinds of type annotation, so the LSP hover can be derived from
--   the tree directly:
--
--     * /Reference/ nodes ('TVar', 'TConRef') carry both the
--       /declared/ scheme (as written in the signature / constructor
--       declaration) and the /instantiated/ type at this occurrence.
--       'TBuiltIn' is monomorphic, so it carries a single type.
--     * Every other node carries the single resolved type the
--       typechecker gave it.
--
--   Row injection is /explicit/: wherever the typechecker accepts a
--   value of one type into a wider row position via
--   'Awsum.HM.rowSubsume', it wraps the value in a 'TCoerce' carrying the
--   source and target types. Lowering translates 'TCoerce' into the
--   'Awsum.Core.CRow' wrapping (deep, through nominal heads); no type
--   re-synthesis happens during lowering.
--
--   Case scrutinees are classified by the typechecker, not re-discovered
--   by lowering: a case on a structural sum is a 'TRowCase', on a nominal
--   sum a 'TCase'. A constructor used as a value is always a 'TConRef'
--   (bare, partial, or — as the head of a saturated 'TApp' — a full
--   application that lowering maps to a direct 'Awsum.Core.CCon').
--
--   Runtime tags ('Awsum.Core.CCon' integer tags, 'Awsum.Core.CRow'
--   32-bit row tags) are /not/ carried here — the typechecker is
--   tag-agnostic. 'TExpr' carries types and names; lowering maps each
--   type to its tag.
module Awsum.TExpr
  ( TExpr (..),
    TParam (..),
    TPattern (..),
    TAlt (..),
    TRowAlt (..),
    TDecl (..),
    TypedProgram (..),
    texprType,
    tparamType,
    tdeclName,
    tAltBody,
    tRowAltBody,
    substTExpr,
    substTParam,
  )
where

import Awsum.HM (Subst, applySubst, nullSubst)
import Awsum.Syntax (Decl, Literal, Name, QName, SrcSpan, Type' (..))
import Relude

-- | Elaborated expression. Every node carries its resolved type;
--   reference nodes additionally carry the declared scheme (see the
--   module header).
data TExpr
  = -- | Variable / qualified name. Fields: span, declared scheme,
    --   instantiated type at this occurrence, name.
    TVar SrcSpan Type' Type' QName
  | -- | Literal with its resolved type — the numeric type is already
    --   pinned (no defaulting), or @String@. Fields: span, type, literal.
    TLit SrcSpan Type' Literal
  | -- | Compiler built-in reference (@BuiltIn.foo@). Monomorphic at the
    --   reference, so a single type. Fields: span, type, name.
    TBuiltIn SrcSpan Type' Name
  | -- | Constructor used as a value. On its own (bare or partially
    --   applied) it lowers to the constructor wrapper function; as the
    --   head of a saturated 'TApp' it lowers directly to
    --   'Awsum.Core.CCon'. Fields: span, declared scheme, instantiated
    --   type, name.
    TConRef SrcSpan Type' Type' Name
  | -- | Application spine: head applied to one or more arguments. The
    --   'Type'' after the span is the result type of the whole
    --   application.
    TApp SrcSpan Type' TExpr [TExpr]
  | -- | Lambda. The 'Type'' after the span is the arrow type.
    TLam SrcSpan Type' [TParam] TExpr
  | -- | @let binder = rhs in body@. The 'Type'' after the span is the
    --   body's type. Only 'TPVar' / 'TPWild' binders survive desugaring.
    TLet SrcSpan Type' TPattern TExpr TExpr
  | -- | @case@ on a nominal sum. The 'Type'' after the span is the
    --   result type (every arm unified to it).
    TCase SrcSpan Type' TExpr [TAlt]
  | -- | @case@ on a structural sum (row). The 'Type'' after the span is
    --   the result type.
    TRowCase SrcSpan Type' TExpr [TRowAlt]
  | -- | Row injection / widening, inserted by the typechecker wherever a
    --   value of @src@ flows into a position of @tgt@ via
    --   'Awsum.HM.rowSubsume'. Fields: span, source type, target type,
    --   inner expression. The node's type is @tgt@.
    TCoerce SrcSpan Type' Type' TExpr
  deriving stock (Show, Eq)

-- | A typed function / lambda parameter. After desugaring every
--   parameter is a plain name (a destructuring 'Awsum.Syntax.ParamPat'
--   is rewritten to a fresh binder plus a @case@), so one shape suffices.
data TParam = TParam SrcSpan Type' Name
  deriving stock (Show, Eq)

-- | Typed pattern. Each binder carries its resolved type (consumed by
--   lowering for the binder's 'Awsum.Core.CDropKind'); 'TPAscribe'
--   carries the alternative type the row arm selects.
data TPattern
  = TPVar SrcSpan Type' Name
  | TPWild SrcSpan Type'
  | TPCon SrcSpan Type' Name [TPattern]
  | TPAscribe SrcSpan Type' TPattern
  deriving stock (Show, Eq)

-- | A nominal-@case@ arm: pattern + body.
data TAlt = TAlt TPattern TExpr
  deriving stock (Show, Eq)

-- | A row-@case@ arm. The 'Type'' is the row label this arm selects; its
--   FNV tag is computed by lowering.
data TRowAlt = TRowAlt Type' TPattern TExpr
  deriving stock (Show, Eq)

-- | The resolved type of an expression node — the /instantiated/ type
--   for reference nodes, the result type for a saturated constructor
--   application, the target type for a coercion.
texprType :: TExpr -> Type'
texprType = \case
  TVar _ _ inst _ -> inst
  TLit _ t _ -> t
  TBuiltIn _ t _ -> t
  TConRef _ _ inst _ -> inst
  TApp _ t _ _ -> t
  TLam _ t _ _ -> t
  TLet _ t _ _ _ -> t
  TCase _ t _ _ -> t
  TRowCase _ t _ _ -> t
  TCoerce _ _ tgt _ -> tgt

-- | The resolved type of a parameter binder.
tparamType :: TParam -> Type'
tparamType (TParam _ t _) = t

-- | The name a top-level declaration binds.
tdeclName :: TDecl -> Name
tdeclName = \case
  TFunDef n _ _ -> n
  TValDef n _ -> n

-- | The body expression of a nominal-case arm.
tAltBody :: TAlt -> TExpr
tAltBody (TAlt _ body) = body

-- | The body expression of a row-case arm.
tRowAltBody :: TRowAlt -> TExpr
tRowAltBody (TRowAlt _ _ body) = body

-- | Apply a substitution to every /instantiated/ / node / coercion /
--   binder type in the tree. The /declared/ schemes on reference nodes
--   are deliberately left untouched — they represent the user-facing
--   polymorphic scheme, which does not change with call-site context.
--
--   This is the primitive the row-monomorphisation pass uses to turn a
--   polymorphic combinator body's abstract row labels (the @e1@ inside a
--   'TCoerce') into the concrete labels of a particular instantiation.
substTExpr :: Subst -> TExpr -> TExpr
substTExpr s
  | nullSubst s = id
  | otherwise = go
  where
    go = \case
      TVar sp decl inst q -> TVar sp decl (applySubst s inst) q
      TLit sp t l -> TLit sp (applySubst s t) l
      TBuiltIn sp t n -> TBuiltIn sp (applySubst s t) n
      TConRef sp decl inst n -> TConRef sp decl (applySubst s inst) n
      TApp sp t f args -> TApp sp (applySubst s t) (go f) (map go args)
      TLam sp t ps body -> TLam sp (applySubst s t) (map (substTParam s) ps) (go body)
      TLet sp t pat rhs body -> TLet sp (applySubst s t) (substTPattern s pat) (go rhs) (go body)
      TCase sp t scrut alts -> TCase sp (applySubst s t) (go scrut) (map (substTAlt s) alts)
      TRowCase sp t scrut alts -> TRowCase sp (applySubst s t) (go scrut) (map (substTRowAlt s) alts)
      TCoerce sp src tgt inner -> TCoerce sp (applySubst s src) (applySubst s tgt) (go inner)

-- | Apply a substitution to a parameter's type.
substTParam :: Subst -> TParam -> TParam
substTParam s (TParam sp t n) = TParam sp (applySubst s t) n

-- | Apply a substitution to every type in a pattern.
substTPattern :: Subst -> TPattern -> TPattern
substTPattern s = \case
  TPVar sp t n -> TPVar sp (applySubst s t) n
  TPWild sp t -> TPWild sp (applySubst s t)
  TPCon sp t n ps -> TPCon sp (applySubst s t) n (map (substTPattern s) ps)
  TPAscribe sp t p -> TPAscribe sp (applySubst s t) (substTPattern s p)

substTAlt :: Subst -> TAlt -> TAlt
substTAlt s (TAlt pat body) = TAlt (substTPattern s pat) (substTExpr s body)

substTRowAlt :: Subst -> TRowAlt -> TRowAlt
substTRowAlt s (TRowAlt lbl pat body) =
  TRowAlt (applySubst s lbl) (substTPattern s pat) (substTExpr s body)

-- | A typed top-level definition. Function defs carry their typed
--   parameters; zero-argument defs — including the alias form
--   @foo = expr@ whose signature is an arrow — are 'TValDef' constants
--   (lowering eta-expands the alias form from the body's type).
data TDecl
  = TFunDef Name [TParam] TExpr
  | TValDef Name TExpr
  deriving stock (Show, Eq)

-- | The whole program after elaboration. 'tpProgramDecls' is the
--   surface declaration list (post-desugar, post-empty-type marking)
--   carried verbatim so lowering can build constructor info,
--   signatures, and declaration spans from it; 'tpDefs' are the
--   elaborated function / value definitions consumed by the
--   row-monomorphisation pass and by lowering.
data TypedProgram = TypedProgram
  { tpProgramDecls :: [Decl],
    tpDefs :: [TDecl]
  }
  deriving stock (Show, Eq)
