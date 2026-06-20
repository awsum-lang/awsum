-- | Awsum Core IR (intermediate representation).
--
--   • call-by-value,
--   • zero-arg surface defs are lowered to /constants/ ('CValDef').
--
-- Invariants (assumed by codegens and passes):
--   • 'CBuiltIn' must only appear in the /function position/ of 'CCall' (never as a standalone term).
--   • Arity of 'CCall' arguments must match the built-in being called.
--   • 'CValDef' models a pure /constant/ (no effects by construction).
--   • Names in 'CVar' refer either to top-level defs or function parameters.
--   • 'CLoop' appears only at the top of a 'CFunDef' body, produced by the
--     TCO pass. Inside the wrapped body, self-recursive tail calls have
--     been replaced with 'CContinue'.
--   • 'CContinue' appears only inside a 'CLoop' wrapping the same function.
--     Its argument list has the same arity as the enclosing function's
--     parameter list, positionally matched.
module Awsum.Core
  ( IntType (..),
    intSigned,
    intWidth,
    intTypeName,
    CExpr (..),
    CDecl (..),
    CoreProgram (..),
    PreludeTags (..),
    ReuseMode (..),
    usedBuiltIns,
    usesIntLit,
    nextFreshConTag,
    binderUsedIn,
    effectfulIn,
    reusedBinders,
    children,
    freeVars,
    renameVar,
  )
where

import Awsum.Syntax (Name)
import Data.Set qualified as Set
import Relude

-- | Concrete built-in integer type. One constructor per shipped type so
--   every pattern match is exhaustive — adding a future variant (Int64,
--   …) forces every backend and codegen site to handle it rather
--   than silently falling through an @_ -> error@ catch-all.
data IntType = TInt32 | TUInt8 | TUInt32
  deriving stock (Show, Eq, Ord)

-- | True iff the type's value space is signed. Keeps the old (signed, width)
--   query pattern available without re-introducing invalid combinations at
--   the type level.
intSigned :: IntType -> Bool
intSigned = \case
  TInt32 -> True
  TUInt8 -> False
  TUInt32 -> False

-- | Bit width of the type's runtime representation (32 for 'TInt32' /
--   'TUInt32', 8 for 'TUInt8').
intWidth :: IntType -> Int
intWidth = \case
  TInt32 -> 32
  TUInt8 -> 8
  TUInt32 -> 32

-- | Canonical surface name of an 'IntType' (e.g. @Int32@, @UInt8@, @UInt32@).
intTypeName :: IntType -> Name
intTypeName = \case
  TInt32 -> "Int32"
  TUInt8 -> "UInt8"
  TUInt32 -> "UInt32"

-- | How a 'CReuse' may take its cell — the static uniqueness evidence
--   'Awsum.Reuse.insertReuse' attaches when it rewrites.
--
--     * 'ReuseUnique' — the dying cell is an Scc argument pack or a Cps
--       continuation cell (its constructor tag was minted above
--       'nextFreshConTag' of the pre-Scc program). Those cells are
--       created and consumed entirely inside the compiler-generated
--       loop, never stored into user data and never visible to user
--       code, so no other holder can exist: every backend mutates in
--       place unconditionally.
--     * 'ReuseGuarded' — a user-visible cell (a list node, a tree node,
--       an IO step). The local drop only proves the /binder's/
--       reference dies; the caller may retain the structure (Awsum is
--       pure — @let ys = reverse xs@ keeps @xs@ readable), so
--       uniqueness is a runtime property. LLVM/WASM check the refcount
--       and copy-on-write when shared; the managed backends have no
--       refcount header to check and allocate a fresh cell instead.
data ReuseMode = ReuseUnique | ReuseGuarded
  deriving stock (Show, Eq, Ord)

-- | Core expressions.
data CExpr
  = -- | Local or top-level variable reference.
    CVar Name
  | -- | String literal (already unescaped).
    CString Text
  | -- | Integer literal tagged with its declared type.
    --   Value is stored as arbitrary-precision 'Integer'; the typechecker
    --   has already verified it fits in 'IntType''s range.
    CIntLit Integer IntType
  | -- | Function/built-in application; left-associated by construction.
    CCall CExpr [CExpr]
  | -- | Constructor: integer tag + fields (fields empty for nullary constructors).
    CCon Int [CExpr]
  | -- | Case expression: scrutinee + alternatives @[(tag, bound-var names, body)]@.
    CCase CExpr [(Int, [Name], CExpr)]
  | -- | Row-tagged value: a 32-bit hash that identifies the row label
    --   plus the underlying value of the alternative type. Produced at
    --   lowering time when an expression is implicitly injected into a
    --   structural-sum position — e.g. the call @f "hi"@ with
    --   @f : (Int32 | String) -> …@ wraps @"hi"@ in
    --   @CRow (rowTag String) "hi"@. Distinct from 'CCon' so backends
    --   can pick a representation appropriate for hash-based dispatch
    --   (typically an inline @{tag, value}@ box) without conflating it
    --   with positional nominal constructors.
    CRow Word32 CExpr
  | -- | Row case: scrutinee + alternatives keyed by the same 32-bit
    --   hash that 'CRow' used at injection time. Each arm binds the
    --   row's underlying value to a single name (the inner pattern of
    --   a 'PAscribe' arm in the surface). Dispatch is by exact hash
    --   equality; the typechecker has already proved exhaustiveness
    --   over the closed row.
    CRowCase CExpr [(Word32, Name, CExpr)]
  | -- | Reference to a compiler-provided built-in. The 'Name' is either
    --   an unqualified prelude built-in (e.g. @showInt32@) looked up in
    --   'Awsum.BuiltIn', or a dotted qualified name (e.g.
    --   @IO.Stdout.print@) looked up in the program type's platform
    --   table ('Awsum.Program.platformTable'). Every backend dispatches
    --   on this name to emit the per-target implementation.
    CBuiltIn Name
  | -- | Function body wrapped by the TCO pass. Semantically the value of
    --   the wrapped expression, operationally a jump label: when the body
    --   evaluates to a 'CContinue', execution jumps back to the label with
    --   the function's parameters re-bound to the continue arguments. Only
    --   appears at the top of a 'CFunDef' body.
    CLoop CExpr
  | -- | Positional re-entry into the nearest enclosing 'CLoop' with fresh
    --   parameter values. Produced by the TCO pass in place of a self-tail
    --   call. Arity must match the enclosing function's parameter list.
    CContinue [CExpr]
  | -- | Liveness annotation produced by 'Awsum.Lifetime.insertDrops':
    --   @CDrop n body@ asserts that the binder @n@ becomes dead
    --   /after/ @body@ has been fully evaluated. The expression's
    --   value is the value of @body@. Codegen emits the per-target
    --   reclaim for @n@ after @body@'s value has been produced.
    --
    --   Semantics: "n dead /after/ body", so the same placement is
    --   safe under both linear free (LLVM/WASM) and slot-nullify
    --   (JVM/CLR/JS). See 'Awsum.Lifetime' for the placement algorithm
    --   and ownership discipline (CCall/CCon/CContinue arg uses
    --   transfer ownership; no drop is emitted for transferred
    --   binders).
    --
    --   Convention (resolved once here, relied on by 'freeVars' and
    --   'renameVar'): @n@ is a /reference/ position, not a binder.
    --   'CDrop' does not bind @n@ — it annotates the death of a name
    --   bound by an enclosing scope (a parameter, a 'CLet', a case-arm
    --   binder), and evaluating the reclaim needs that cell. So @n@
    --   counts as free in @CDrop n body@ (like the cell name of
    --   'CReuse'), and a rename of the enclosing binder must rewrite
    --   @n@ and descend into @body@ — treating it as a binder would
    --   leave a drop naming a renamed-away (or freed) cell. ('binderUsedIn'
    --   answers a different question — "is the binder still really used,
    --   such that eliding it loses a use" — and deliberately does /not/
    --   count a drop, since eliding a binder elides its drop too.)
    CDrop Name CExpr
  | -- | Cell reuse à la Lean 4. @CReuse mode n tag fields@ writes @tag@
    --   into slot 0 of the existing user-pointer at @n@ and the
    --   @fields@ values into slots 1, 2, …, length fields. The result
    --   value of the expression is @n@ itself — same physical pointer
    --   as before, just with new contents.
    --
    --   Produced by 'Awsum.Reuse.insertReuse' from a 'CCon' whose
    --   surrounding 'CCase' scrutinee is a linear 'CVar n' followed by
    --   a 'CDrop n' wrap. The reuse pass removes the 'CDrop' (since
    --   the cell is reused, not freed) and rewrites the nested 'CCon'
    --   in place.
    --
    --   Invariant: the cell at @n@ has at least @1 + length fields@
    --   slots. Currently the reuse pass only matches when the matched
    --   arm's pattern has exactly @length fields@ binders (so the
    --   slot count is exact) — see 'Awsum.Reuse.rewriteFirstCCon'.
    --
    --   Backend lowering by 'ReuseMode': a 'ReuseUnique' cell mutates in
    --   place unconditionally on every backend; a 'ReuseGuarded' cell
    --   mutates under a runtime uniqueness check with copy-on-write on
    --   the reference-counted backends (LLVM/WASM) and falls back to a
    --   plain allocation on the managed ones (no refcount header to
    --   check). The pre-existing refcount header on LLVM/WASM is left
    --   intact — the block is still heap-allocated, so on a later
    --   'CDrop' '__free_recursive' will correctly recognise it.
    CReuse ReuseMode Name Int [CExpr]
  | -- | Let-binding: @let n = rhs in body@. The expression's value is
    --   @body@'s value with @n@ bound to @rhs@'s value throughout @body@;
    --   @rhs@ is evaluated once. @rhs@ is in non-tail position, @body@ is in
    --   tail position iff the @CLet@ itself is (so 'Awsum.Cps' / 'Awsum.Tco'
    --   recurse into @body@ as a tail and @rhs@ as a non-tail).
    --
    --   Part of the ANF representation of case-binding: a case scrutinee and
    --   its pattern fields become @let@s (the latter bound to a 'CProj').
    --   Also the form 'Awsum.Simplify' inlines (single-use @let@) and floats.
    CLet Name CExpr CExpr
  | -- | Field projection: slot @Int@ of the constructor cell bound to @Name@
    --   (slot 0 is the tag; fields occupy slots 1.., the same layout
    --   'CReuse' writes). A /leaf/ of the 'CExpr' tree, like 'CVar' — it has
    --   no sub-expressions.
    --
    --   A pure read. The reference-count / ownership discipline (whether a
    --   field is moved out, when @Name@'s cell is freed) is governed by
    --   'CDrop' placement in 'Awsum.Lifetime', not by the projection itself —
    --   so on every backend 'CProj' lowers to a plain slot load, exactly as a
    --   case-arm field binder does today.
    --
    --   In the ANF form, a case-arm field binder becomes
    --   @let v = CProj scrut slot in …@.
    CProj Name Int
  | -- | Join point: @CJoin j params joinBody inner@ declares the label @j@
    --   with @params@ over @joinBody@, then evaluates @inner@. The
    --   expression's value is @inner@'s value on paths whose tail is not a
    --   'CJump', and @joinBody@'s value (with @params@ bound to the jump's
    --   arguments) on paths that jump. The dual of 'CLoop': a forward label
    --   instead of a backward one.
    --
    --   Produced by case-of-case fusion in 'Awsum.Simplify' so the outer
    --   case's arms exist once instead of being copied into every inner arm.
    --   The join name is a minted @$join$…@ — its own namespace, never a
    --   'CVar', untouched by substitution.
    --
    --   Invariants: 'CJump' to @j@ appears only in tail positions of
    --   @inner@, with arity matching @params@; @joinBody@ never jumps to
    --   @j@ (no cycles — stack safety is settled before 'Awsum.Simplify'
    --   runs). A 'CContinue' inside @joinBody@ is legal: every backend
    --   lowers the node natively, so the body stays inside its 'CLoop'.
    CJoin Name [Name] CExpr CExpr
  | -- | Jump to the named enclosing 'CJoin': bind its parameters to @args@
    --   and continue with its body. Appears only in tail positions of the
    --   join's @inner@ expression, like 'CContinue' inside 'CLoop'.
    CJump Name [CExpr]
  deriving stock (Show, Eq)

-- | Top-level Core declarations.
data CDecl
  = -- | First-order function: @f x1 .. xn = body@.
    CFunDef Name [Name] CExpr
  | -- | Constant value: @c = rhs@ (zero-arg defs lower here).
    CValDef Name CExpr
  deriving stock (Show, Eq)

-- | A Core program is just a list of top-level declarations.
-- Backends may choose any emission order if they respect language scoping rules.
newtype CoreProgram = CoreProgram {cdecls :: [CDecl]}
  deriving stock (Show, Eq)

-- | The constructor tags codegen runtime helpers need to construct
-- values of well-known prelude types (e.g. @Left StringTooLong@ from
-- @__concat@'s overflow path). Under globally-unique tags every
-- constructor's tag depends on declaration order and the size of
-- everything that came before it, so the helpers — which build these
-- values out of band of the user's program — must look the tags up
-- rather than hardcode them.
--
-- Populated from 'ConInfoEnv' at the end of elaboration and passed
-- alongside 'CoreProgram' to every codegen. The fields cover exactly
-- the constructors that appear in any runtime helper's emitted
-- expression — adding a helper that creates a new constructor type
-- means adding a field here.
data PreludeTags = PreludeTags
  { ptLeft :: !Int,
    ptRight :: !Int,
    ptJust :: !Int,
    ptNothing :: !Int,
    ptTrue :: !Int,
    ptFalse :: !Int,
    ptUnit :: !Int,
    ptTuple2 :: !Int,
    ptNil :: !Int,
    ptCons :: !Int,
    ptUnderflowError :: !Int,
    ptOverflowError :: !Int,
    ptParseError :: !Int,
    ptStringTooLong :: !Int,
    ptUnpairedUtf16Surrogate :: !Int,
    ptInvalidUtf8 :: !Int
  }
  deriving stock (Show, Eq)

-- | Every 'CBuiltIn' name referenced in the program. Backends gate
--   runtime helpers (@__print@, @__predInt32@, future @__addInt32@, ...)
--   on this so programs that don't touch a given built-in don't pay for it.
usedBuiltIns :: CoreProgram -> Set Name
usedBuiltIns (CoreProgram ds) = foldMap declBuiltIns ds
  where
    declBuiltIns (CFunDef _ _ body) = exprBuiltIns body
    declBuiltIns (CValDef _ body) = exprBuiltIns body
    exprBuiltIns e = self <> foldMap exprBuiltIns (children e)
      where
        self = case e of
          CBuiltIn n -> Set.singleton n
          _ -> mempty

-- | Smallest 'Int' strictly greater than every constructor tag used
--   anywhere in the program ('CCon' construction sites and 'CCase'
--   arm tags). Used by tag-minting passes ('Awsum.Scc',
--   'Awsum.LowerClosures', 'Awsum.Cps') to allocate fresh
--   synthetic-type tags that do not collide with any existing
--   nominal-constructor tag (or with each other, when threaded
--   through). Globally unique constructor tags are what makes
--   'pruneDeadArms' precise — without them, two unrelated types
--   sharing a tag value mask each other's reachability.
--
--   Returns @0@ when the program references no constructor tags at
--   all (vacuous program).
nextFreshConTag :: CoreProgram -> Int
nextFreshConTag (CoreProgram ds) =
  1 + foldl' max (-1) (concatMap declConTags ds)
  where
    declConTags :: CDecl -> [Int]
    declConTags = \case
      CFunDef _ _ body -> exprConTags body
      CValDef _ body -> exprConTags body
    exprConTags :: CExpr -> [Int]
    exprConTags e = self <> concatMap exprConTags (children e)
      where
        self = case e of
          CCon t _ -> [t]
          CReuse _ _ t _ -> [t]
          CCase _ alts -> [t | (t, _, _) <- alts]
          _ -> []

-- | Does the program contain any integer literal? Backends that rely on
--   boxing helpers (e.g. WASM's @__box_i32@) can drop them when the
--   answer is 'False'.
usesIntLit :: CoreProgram -> Bool
usesIntLit (CoreProgram ds) = any declHasInt ds
  where
    declHasInt (CFunDef _ _ body) = exprHasInt body
    declHasInt (CValDef _ body) = exprHasInt body
    exprHasInt e = self || any exprHasInt (children e)
      where
        self = case e of
          CIntLit _ _ -> True
          _ -> False

-- | Does @v@ appear in @e@ — as a 'CVar', or as the variable of a 'CProj' /
--   'CReuse'? Shadowing-aware: does not descend under a binder that
--   reintroduces @v@.
--
--   This is the single predicate the arm-binder elision rests on. Its one
--   producer is 'Awsum.Simplify', which inlines a binder only when it occurs
--   exactly once as a 'CVar' and never as a name — and the inline replaces
--   that lone 'CVar' with @CProj scrut i@ (the /scrutinee/, not the binder),
--   so the binder's @binderUsedIn@ drops to 'False'. Its six consumers —
--   'Awsum.Lifetime' (skips the binder's 'CDrop') and all five codegens (skip
--   extracting / binding / inc'ing it) — must all read this same predicate, so
--   that the set a consumer elides is exactly the set the producer inlined. A
--   future 'Awsum.Simplify' rule that inlines a binder into something other
--   than a @CProj scrut@, or a new consumer that forgets the gate, has to keep
--   that equality or it reintroduces a dead binding or an unbalanced refcount.
binderUsedIn :: Name -> CExpr -> Bool
binderUsedIn v = go
  where
    go = \case
      CVar n -> n == v
      CProj n _ -> n == v
      CCall f xs -> go f || any go xs
      CCon _ fs -> any go fs
      CRow _ x -> go x
      CCase s alts -> go s || any (\(_, vs, b) -> notElem v vs && go b) alts
      CRowCase s alts -> go s || any (\(_, w, b) -> v /= w && go b) alts
      CLoop b -> go b
      CContinue xs -> any go xs
      CLet n rhs b -> go rhs || (n /= v && go b)
      CDrop _ b -> go b
      CReuse _ n _ fs -> n == v || any go fs
      -- The join name is a minted @$join$…@, never a value binder, so only
      -- the params shadow @v@ — and only inside the join body.
      CJoin _ ps body inner -> (notElem v ps && go body) || go inner
      CJump _ args -> any go args
      CString _ -> False
      CIntLit _ _ -> False
      CBuiltIn _ -> False

-- | Does evaluating this expression perform I/O — does it call one of the
--   platform-effect primitives? The four @internal*@ built-ins are the
--   only calls in Core whose evaluation is observable: user-facing
--   platform effects are lowered to constructor cells (effects are data),
--   and the primitives survive only inside @runIO@'s walker, where the
--   call /is/ the effect. Everything else is pure — droppable when unused
--   and reorderable among other pure expressions; an effectful call is
--   neither. Gates 'Awsum.Simplify''s unused-position drops (a collapsed
--   case's scrutinee, a dead let's right-hand side, an unused inline
--   argument, a dropped known-constructor field) and the JS codegen's
--   parameter-rebind scheduling.
effectfulIn :: CExpr -> Bool
effectfulIn = goE
  where
    effectful :: Set Name
    effectful = Set.fromList ["internalStdoutPrint", "internalGetArgs", "internalStdinReadAllString", "internalStdinReadAllBytes"]
    goE e = self || any goE (children e)
      where
        self = case e of
          CBuiltIn n -> n `Set.member` effectful
          _ -> False

-- | Every binder whose cell a 'CReuse' inside this expression overwrites.
--   'effectfulIn' is about evaluation being observable outside the
--   program; this is about it being observable by /sibling/ expressions:
--   a 'CReuse' rewrites the cell its binder names in place, so a sibling
--   that mentions the same binder (a projection, a call receiving it)
--   reads different contents depending on which of the two evaluates
--   first. Reordering two expressions is sound exactly when no binder
--   returned here for one is mentioned by the other. Feeds the JS
--   codegen's parameter-rebind scheduling, which keeps such conflicting
--   pairs in source evaluation order.
reusedBinders :: CExpr -> [Name]
reusedBinders e = self <> concatMap reusedBinders (children e)
  where
    self = case e of
      CReuse _ n _ _ -> [n]
      _ -> []

-- | The immediate sub-expressions of a node, in source-evaluation order
--   (callee before args, scrutinee before arms, @rhs@ before @body@, …).
--   The single structural-recursion point the binder-/unaware/ folds above
--   ('usedBuiltIns', 'nextFreshConTag', 'usesIntLit', 'effectfulIn',
--   'reusedBinders') share: each is "this node's own contribution" combined
--   over @children@, so a new 'CExpr' constructor forces an update here once
--   rather than in every fold. Leaves ('CVar', 'CString', 'CIntLit',
--   'CBuiltIn', 'CProj') have none.
--
--   The /order/ is load-bearing for the list-valued fold 'reusedBinders'
--   (the JS codegen keeps reuse-conflicting pairs in this order), so it
--   mirrors the left-to-right evaluation order of each constructor.
--
--   Binder-/aware/ traversals ('freeVars', 'binderUsedIn', 'renameVar')
--   cannot use this: they must subtract or stop at the binders a node
--   introduces (case/row arms, 'CLet', 'CJoin' params), which a flat child
--   list discards. They stay explicit recursions — one copy each, here.
children :: CExpr -> [CExpr]
children = \case
  CVar _ -> []
  CString _ -> []
  CIntLit _ _ -> []
  CBuiltIn _ -> []
  CProj _ _ -> []
  CCall f xs -> f : xs
  CCon _ fs -> fs
  CCase s alts -> s : [b | (_, _, b) <- alts]
  CRow _ v -> [v]
  CRowCase s alts -> s : [b | (_, _, b) <- alts]
  CLoop b -> [b]
  CContinue xs -> xs
  CDrop _ b -> [b]
  CReuse _ _ _ fs -> fs
  CLet _ rhs body -> [rhs, body]
  CJoin _ _ body inner -> [body, inner]
  CJump _ args -> args

-- | Free variables of a Core expression: every name referenced from an
--   enclosing scope. Binder-aware — the binders a node introduces (case /
--   row arms, 'CLet', 'CJoin' params) scope over their sub-expressions and
--   are subtracted. The reference positions are 'CVar', 'CProj', and the
--   cell name of 'CReuse' and 'CDrop': all count the named cell as free,
--   because evaluating the node needs it (see the 'CDrop' convention on the
--   node). One copy for the whole compiler — 'Awsum.Cps' (continuation
--   capture) and 'Awsum.ElaborateLower' (tree-shake, partial-application
--   lift) both call this.
freeVars :: CExpr -> Set Name
freeVars = \case
  CVar n -> Set.singleton n
  CProj n _ -> Set.singleton n
  CString _ -> mempty
  CIntLit _ _ -> mempty
  CBuiltIn _ -> mempty
  CCall f xs -> freeVars f <> foldMap freeVars xs
  CCon _ fs -> foldMap freeVars fs
  CCase s alts -> freeVars s <> foldMap armFv alts
  CRow _ v -> freeVars v
  CRowCase s alts -> freeVars s <> foldMap rowArmFv alts
  CLoop b -> freeVars b
  CContinue xs -> foldMap freeVars xs
  CDrop n b -> Set.insert n (freeVars b)
  CReuse _ n _ fs -> Set.insert n (foldMap freeVars fs)
  CLet n rhs body -> freeVars rhs <> Set.delete n (freeVars body)
  CJoin _ ps body inner -> (freeVars body `Set.difference` Set.fromList ps) <> freeVars inner
  CJump _ args -> foldMap freeVars args
  where
    armFv (_, bound, body) = freeVars body `Set.difference` Set.fromList bound
    rowArmFv (_, bound, body) = Set.delete bound (freeVars body)

-- | Rename every free occurrence of @from@ to @to@ — every reference
--   position ('CVar', 'CProj', and the cell name of 'CReuse' / 'CDrop'),
--   stopping under a binder that re-introduces @from@ (case / row arm,
--   'CLet', 'CJoin' param). The caller supplies a fresh @to@, so there is no
--   capture to avoid. The 'CDrop' name is a reference (see the node), so it
--   is renamed and descended into — never treated as a binder, which would
--   leave a drop naming the wrong cell. One copy for the whole compiler:
--   'Awsum.Cps' (apply-arm freshening), 'Awsum.ElaborateLower' (arm-binder
--   reconciliation), and 'Awsum.Simplify' (single-use binder inline) all
--   call this.
renameVar :: Name -> Name -> CExpr -> CExpr
renameVar from to = go
  where
    rn v = if v == from then to else v
    go = \case
      CVar v -> CVar (rn v)
      CProj v i -> CProj (rn v) i
      CReuse rm v t fs -> CReuse rm (rn v) t (map go fs)
      CCall f xs -> CCall (go f) (map go xs)
      CCon t fs -> CCon t (map go fs)
      CRow t v -> CRow t (go v)
      CCase s alts -> CCase (go s) [(t, vs, if from `elem` vs then b else go b) | (t, vs, b) <- alts]
      CRowCase s alts -> CRowCase (go s) [(t, v, if v == from then b else go b) | (t, v, b) <- alts]
      CLoop b -> CLoop (go b)
      CContinue xs -> CContinue (map go xs)
      CLet x rhs b -> CLet x (go rhs) (if x == from then b else go b)
      CDrop x b -> CDrop (rn x) (go b)
      CJoin j ps body inner -> CJoin j ps (if from `elem` ps then body else go body) (go inner)
      CJump j args -> CJump j (map go args)
      e@(CString _) -> e
      e@(CIntLit _ _) -> e
      e@(CBuiltIn _) -> e
