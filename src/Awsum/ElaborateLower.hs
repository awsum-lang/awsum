-- | Single-pass /elaboration + lowering/ from surface 'Awsum.Syntax' to 'Awsum.Core'.
--
-- Why one pass?  Minimal work for the current surface language:
--   1) /Elaboration/ : rely on the type checker to validate the program
--      (no dictionaries/implicit args yet).
--   2) /Lowering/    : erase surface sugar and map built-ins to Core nodes.
--
-- Notes:
--   • We treat zero-argument top-level defs as /constants/ ('CValDef').
--   • We erase explicit type signatures ('Sig') — they are checked, then dropped.
--   • Qualified names are resolved here to platform built-ins (e.g. @IO.Stdout.print@).
--   • Application is flattened to a single 'CCall' with all arguments (left-assoc).
--   • Non-nullary constructors used as values (not at head of application)
--     are eta-expanded into synthetic wrapper functions.
--
-- Invariants (assumed by codegen/tests):
--   • After lowering, zero-arg defs do NOT become functions; they are 'CValDef'.
--   • 'CBuiltIn' only appears in callee position of 'CCall'.
--   • Unsupported qualified names fail fast with a clear error.
module Awsum.ElaborateLower (elaborateLowerProgram) where

import Awsum.BuiltIn (lookupBuiltIn)
import Awsum.Core
import Awsum.Cps (cpsProgram)
import Awsum.Defunctionalize (defunctionalizeProgram)
import Awsum.Desugar (desugarProgram)
import Awsum.Desugar qualified as Desugar
import Awsum.HM (Subst, applySubst, canonicalLabel, flattenRow, rowTag, singletonSubst, unify)
import Awsum.Prelude (preludeDefNames)
import Awsum.Program (ProgramType, platformTable)
import Awsum.Scc (sccMergeProgram)
import Awsum.StackSafety (verifyStackSafety)
import Awsum.StackSafety qualified as StackSafety
import Awsum.Syntax
import Awsum.Tco (tcoProgram)
import Awsum.Typing (TypeError (..), Warning, intTypeRange, isBareBuiltIn, splitArrow, typecheckProgram)
import Control.Monad (foldM)
import Data.List (groupBy)
import Data.Map.Strict qualified as M
import Data.Set qualified as Set
import Data.Text qualified as T
import Relude

-- | Static info carried through lowering so it can fill in the type of every
--   'LInt' literal (integer literals are untyped in the surface AST; the
--   typechecker validates them against context but doesn't annotate the tree).
--
--   • 'leTypeOf' resolves qualified/unqualified names to their declared type —
--     user signatures, built-in functions ('IO.Stdout.print', 'Int32.show', …)
--     and nullary-constructor names. We use it at 'EApp' sites to recover the
--     argument type and propagate it to the argument expression.
--   • 'leConInfo' is the same constructor tag/arity map used by the rest of
--     lowering; carried alongside so we can pass a single record around.
data LowerEnv = LowerEnv
  { -- | Program type we are lowering for. Consulted by 'lowerVar' to
    --   resolve qualified names against the right platform table.
    leProgramType :: ProgramType,
    leTypeOf :: QName -> Maybe Type',
    leConInfo :: ConInfoEnv,
    -- | Source spans of every user @type T = …@ declaration, keyed
    --   by the type's name. Consumed by the row tag collision check
    --   to point its diagnostic at the @type@ declaration of one of
    --   the colliding labels (what the user would rename) rather
    --   than at the case-arm pattern that triggered the detection.
    leTypeDeclSpans :: M.Map Name SrcSpan
  }

-- | Constructor info as seen by the lowerer: tag, arity, owning type
--   name, type-parameter names, and field types in the un-substituted
--   form they came in from the @type@ declaration. The type-name and
--   field-type details support implicit injection of constructor
--   arguments through nominal heads — when @Left x@ is lowered with
--   expected outer type @Either (ErrA | ErrB) Int32@, the field-type
--   @a@ unifies with @(ErrA | ErrB)@ so the inner call can wrap a
--   bare @ErrA@ as @CRow (rowTag ErrA) (CCon …)@.
data ConInfo = ConInfo
  { ciTag :: Int,
    ciArity :: Int,
    ciTypeName :: Name,
    ciTypeParams :: [Name],
    ciFieldTypes :: [Type']
  }
  deriving stock (Show)

type ConInfoEnv = M.Map Name ConInfo

-- | Build constructor info from @type@ declarations. Each constructor
--   gets a 0-based tag, its arity, the owning type's name, the
--   declared type-parameter names of that type, and its field types.
buildConInfo :: [Decl] -> ConInfoEnv
buildConInfo ds =
  M.fromList
    [ (cName, ConInfo idx (length cFields) tName [n | Param _ n <- ps] cFields)
    | TypeDecl _sp tName ps cs _ <- ds,
      (ConDef _ cName cFields, idx) <- zip cs [0 ..]
    ]

-- | Synthetic name for a constructor wrapper function.
--   Uses @$con$@ prefix which cannot collide with user-defined names.
conWrapperName :: Name -> Name
conWrapperName name = "$con$" <> name

-- | State threaded through the lowering of a single program: a fresh
--   counter for synthetic names (lifted lambdas, cross-boundary row
--   coercion helpers), the accumulator of those lifted helpers, the
--   row-tag table that powers the /row tag collision check/, and a
--   memo of already-synthesised cross-boundary coercion helpers keyed
--   by @(canonicalSource, canonicalTarget)@ so a given @T1 → T2@
--   coercion gets one shared @$lift$N@ regardless of how many sites
--   trigger it (and so recursive types like @List a@ have a stable
--   helper to recurse through).
--
--   Helpers are produced in reverse order; the pipeline reverses on
--   read.
--
--   The row-tag table maps each 'Word32' tag minted via 'recordRowTag'
--   to the set of canonical labels (keyed by 'canonicalLabel' text)
--   that produced it, with one representative 'Type'' per canonical
--   label kept around for the diagnostic. After lowering completes,
--   any tag mapped to two or more distinct canonical labels is a
--   collision and the program is rejected with 'RowTagCollision'.
data LowerState = LowerState
  { lsFresh :: !Int,
    lsHelpers :: ![CDecl],
    lsRowTags :: !(M.Map Word32 (M.Map Text Type')),
    lsLifters :: !(M.Map (Text, Text) Name)
  }

-- | Lowering monad — lambda-lift state on top of the existing
--   'Either TypeError' result channel.
type LowerM = StateT LowerState (Either TypeError)

-- | Mint a fresh helper name '$lam$N' and bump the counter.
freshLamName :: LowerM Name
freshLamName = do
  s <- get
  put s {lsFresh = lsFresh s + 1}
  pure ("$lam$" <> show (lsFresh s))

-- | Mint a fresh cross-boundary coercion helper name '$lift$N' and
--   bump the counter. Used by 'synthCoerce' when a value of nominal
--   type @Maybe Bool@ has to flow into a slot expecting
--   @Maybe (Bool | Unit)@: the helper destructures the source-shaped
--   value and reconstructs it with row tags injected at every
--   row-vs-non-row mismatch under the common nominal head.
freshLiftName :: LowerM Name
freshLiftName = do
  s <- get
  put s {lsFresh = lsFresh s + 1}
  pure ("$lift$" <> show (lsFresh s))

-- | Mint a fresh helper name '$let$N' for a lifted let-binding body
--   and bump the counter. The shared @lsFresh@ counter keeps every
--   synthesised helper name unique across the program regardless of
--   whether it came from a lambda lift, a coercion, or a let.
freshLetName :: LowerM Name
freshLetName = do
  s <- get
  put s {lsFresh = lsFresh s + 1}
  pure ("$let$" <> show (lsFresh s))

-- | Append a lifted helper definition to the program.
emitHelper :: CDecl -> LowerM ()
emitHelper d = modify (\s -> s {lsHelpers = d : lsHelpers s})

-- | Compute a row label's tag and register the (label, tag) pair in
--   the row-tag table consulted by the post-lowering /row tag
--   collision check/. Always replaces the inline 'rowTag' call inside
--   lowering so every label-derived tag gets recorded; calling
--   'rowTag' directly here would silently bypass collision detection.
recordRowTag :: Type' -> LowerM Word32
recordRowTag lbl = do
  let tag = rowTag lbl
      key = canonicalLabel lbl
  modify
    ( \s ->
        s
          { lsRowTags =
              M.insertWith
                (M.unionWith const)
                tag
                (M.singleton key lbl)
                (lsRowTags s)
          }
    )
  pure tag

-- | Inspect the row-tag table for collisions: any 32-bit tag that two
--   or more distinct canonical labels hashed to is a 'RowTagCollision'.
--   Returns 'Right ()' when every tag has exactly one canonical label
--   behind it (or zero — the program might not use row sums at all).
--   The 'M.Map Name SrcSpan' resolves a label's head 'TyCon' name to
--   the source span of its @type@ declaration, baked into the
--   diagnostic so it points at what the user would actually rename.
checkRowTagCollisions :: M.Map Name SrcSpan -> M.Map Word32 (M.Map Text Type') -> Either TypeError ()
checkRowTagCollisions declSpans tbl =
  case mapMaybe asCollision (M.toList tbl) of
    [] -> Right ()
    (err : _) -> Left err
  where
    asCollision (tag, labels) = case M.elems labels of
      (l1 : l2 : _) -> Just (RowTagCollision l1 l2 tag (tyConDeclSpan declSpans l2))
      _ -> Nothing

-- | Resolve a row label to the source span of its head 'TyCon's @type@
--   declaration, when the label is rooted at a nominal type the user
--   has declared. Used by the row tag collision check to point at the
--   declaration line rather than the usage site.
--
--   Walks 'TyApp' chains to the head — so @Maybe (Bool | Unit)@ resolves
--   to @type Maybe …@. 'TyVar' / 'TyArrow' / 'TyOr' have no nominal
--   head and yield 'Nothing'.
tyConDeclSpan :: M.Map Name SrcSpan -> Type' -> Maybe SrcSpan
tyConDeclSpan declSpans = go
  where
    go (TyCon _ n) = M.lookup n declSpans
    go (TyApp _ f _) = go f
    go _ = Nothing

-- | Lift an 'Either TypeError' computation into 'LowerM'.
liftEither :: Either TypeError a -> LowerM a
liftEither = lift

-- | Locally-bound names visible to lambda-capture analysis: function
--   parameters, outer lambda parameters, and case-arm pattern
--   binders. Top-level definitions are /not/ in this set; they are
--   resolved by name at runtime and never need to be captured.
type Locals = Set Name

-- | Names referenced by the expression that are not bound by any
--   enclosing 'ELam' parameter, 'case' arm pattern, or 'do' bind.
--   Used to compute lambda captures at lifting time: the captures of
--   a lambda are this set intersected with the surrounding 'Locals'.
freeReferences :: Expr -> Set Name
freeReferences = go
  where
    go = \case
      EVar _ (QName [] n) -> Set.singleton n
      EVar _ _ -> Set.empty
      EApp _ f x -> go f <> go x
      EInfix _ _ l r -> go l <> go r
      EParens _ e -> go e
      ELit _ _ -> Set.empty
      ECon _ _ -> Set.empty
      EBuiltIn _ _ -> Set.empty
      ECase _ scrut alts _ ->
        go scrut
          <> foldMap
            ( \(CaseAlt _ pat body _) ->
                go body `Set.difference` patternBoundNames pat
            )
            (toList alts)
      ELam _ params body ->
        go body `Set.difference` Set.fromList (map paramName params)
      EDo _ stmts -> goDoStmts stmts
      ELet _ pat _ e body -> go e <> (go body `Set.difference` patternBoundNames pat)

    goDoStmts [] = Set.empty
    goDoStmts (s : rest) = case s of
      DoBind _ pat e ->
        go e <> (goDoStmts rest `Set.difference` patternBoundNames pat)
      DoLet _ pat _ e -> go e <> (goDoStmts rest `Set.difference` patternBoundNames pat)
      DoExpr _ e -> go e <> goDoStmts rest

    patternBoundNames p = case p of
      PVar _ n -> Set.singleton n
      PWild _ -> Set.empty
      PCon _ _ ps -> foldMap patternBoundNames ps
      PAscribe _ inner _ -> patternBoundNames inner

-- | Map a 'DesugarError' from the surface-AST do-notation rewrite
--   into the 'TypeError' channel that the rest of the pipeline
--   speaks.
desugarErrorToTypeError :: Desugar.DesugarError -> TypeError
desugarErrorToTypeError = \case
  Desugar.DesugarBindNameStillUsed sp _n ->
    DoInSynthesisPosition sp
  Desugar.DesugarPatternLetAscription sp ->
    PatternLetAscription sp

-- | Generate wrapper 'CFunDef's for every non-nullary constructor.
--   E.g. @type Box a = Box a@ produces:
--     @CFunDef "$con$Box" ["$x0"] (CCon 0 [CVar "$x0"])@
genConWrappers :: ConInfoEnv -> [CDecl]
genConWrappers conInfo =
  [ CFunDef (conWrapperName name) params (CCon (ciTag ci) (map CVar params))
  | (name, ci) <- M.toList conInfo,
    ciArity ci > 0,
    let params = ["$x" <> show i | i <- [0 .. ciArity ci - 1]]
  ]

-- | Check the surface program (types) and lower it to Core IR.
--   On success we return @(warnings, core)@: the Core program for codegen
--   plus any non-fatal warnings the typechecker collected.
-- | Run a 'LowerM' computation, returning its result and the
--   accumulated lifted helpers (in source order — they're appended
--   to the user-decl list in the program pipeline).
runLowerM :: LowerM a -> Either TypeError (a, [CDecl], M.Map Word32 (M.Map Text Type'))
runLowerM m = do
  (a, st) <- runStateT m (LowerState 0 [] M.empty M.empty)
  pure (a, reverse (lsHelpers st), lsRowTags st)

elaborateLowerProgram :: ProgramType -> Program -> Either TypeError ([Warning], CoreProgram)
elaborateLowerProgram progType progIn = do
  -- 0) Pre-typecheck desugar: rewrite 'do' blocks into nested
  --    'bindEither' calls with 'ELam' continuations. Lambdas
  --    themselves are kept as 'ELam' nodes — the typechecker handles
  --    them bidirectionally; lambda-lifting happens during lowering,
  --    where the type context is available.
  prog <- first desugarErrorToTypeError (desugarProgram progIn)
  -- 1) Elaboration step: just typecheck; no evidence/dictionaries yet.
  warnings <- typecheckProgram progType preludeDefNames prog
  -- 2) Lowering: drop signatures, convert defs/exprs. Fail gracefully on unknown primitives.
  let ds = toList (decls prog)
      conInfo = buildConInfo ds
      sigMap = M.fromList [(n, t) | Sig _sp n t _ <- ds]
      -- Narrow each TypeDecl span to just the type's name (the
      -- formatter guarantees the leading 'type ' prefix is exactly
      -- five chars), so the row tag collision diagnostic underlines
      -- 'AFB4F' rather than the whole 'type AFB4F = MkAFB4F' line.
      -- Same heuristic 'Awsum.Typing.typeNameSubSpan' uses for
      -- 'DuplicateTypeDef' / 'UnnamedType' diagnostics.
      typeDeclSpans = M.fromList [(n, narrowToName sp n) | TypeDecl sp n _ _ _ <- ds]
      narrowToName sp n =
        let nameStartCol = spanStartCol sp + T.length "type "
         in SrcSpan
              (spanStartLine sp)
              nameStartCol
              (spanStartLine sp)
              (nameStartCol + T.length n)
      env = mkLowerEnv progType conInfo sigMap typeDeclSpans
  (mds, liftedHelpers, rowTags) <- runLowerM (traverse (lowerDeclM env sigMap) ds)
  -- Row tag collision check: reject programs in which two distinct
  -- structural-sum labels canonicalise to the same FNV-1a 32-bit hash.
  -- The hash space is 2^32 wide, so a collision in a hand-written
  -- program is vanishingly unlikely, but the check is a hard guard
  -- against adversarial label names where the runtime would otherwise
  -- silently confuse one alternative for another at row-case dispatch.
  checkRowTagCollisions typeDeclSpans rowTags
  -- 3) Tree-shake: drop Core declarations unreachable from 'main'.
  --    Covers both user functions that no one calls and prelude
  --    helpers the user program does not touch (e.g.
  --    @showUnderflowError@ in a program that never uses @predInt32@).
  --    Constructor wrappers are generated after this reachability is
  --    known so they're only materialised for constructors still
  --    present in the surviving code.
  let userDecls = catMaybes mds
      allWrappers = genConWrappers conInfo
      allDecls = userDecls <> liftedHelpers <> allWrappers
      callGraph = M.fromList [(declName' d, declFreeVars d) | d <- allDecls]
      reachableFromMain = reachableCore "main" callGraph
      live = filter (\d -> Set.member (declName' d) reachableFromMain) allDecls
      core = CoreProgram live
  -- 4) Defunctionalise: specialise each higher-order-function call
  --    site for the closure statically flowing in. After this pass
  --    no first-class function value remains in any reachable
  --    position; HOFs and their callers are fully first-order so
  --    every backend handles them without a closure runtime. See
  --    'Awsum.Defunctionalize' for the structural rules.
  --
  --    Specialisations leave the original polymorphic HOFs (and any
  --    lifted lambdas with captures) in place; tree-shaking from
  --    'main' immediately afterwards drops them, since every
  --    reachable call site has been replaced by a call to a
  --    specialisation.
  core' <- treeShakeFromMain <$> defunctionalizeProgram core
  -- 5) Saturate under-applied direct calls via lambda-lifting.
  core'' <- saturateProgram core'
  -- 6) SCC-merge for mutual recursion. Every strongly-connected
  --    component with more than one function is fused into a single
  --    self-recursive '$scc$' function tagged by "which member is
  --    active"; each original public name becomes a one-line wrapper.
  --    After this step, mutual recursion has become self-recursion —
  --    tail cross-calls get TCO'd below, non-tail cross-calls feed into
  --    the CPS pass. See 'Awsum.Scc' and docs/recursion.md.
  --
  --    SCC rewrites every cross-call to go through the merged function
  --    rather than through the member's original name, so wrappers for
  --    members that were only called from inside the SCC become dead.
  --    Re-run reachability from 'main' to prune them (and anything
  --    else that fell out of scope through the rewrite).
  let sccMerged = treeShakeFromMain (sccMergeProgram core'')
  -- 7) CPS + defunctionalization for non-tail self-recursion. For each
  --    function with a non-tail self-call, emit a (wrapper, '$cps$f',
  --    '$apply$f') trio; the continuation chain now lives as an ADT on
  --    the heap instead of as frames on the system stack, and '$cps$f'
  --    and '$apply$f' are both self-tail-recursive so the following TCO
  --    pass folds them into loops. See 'Awsum.Cps' and docs/recursion.md.
  let cpsed = cpsProgram sccMerged
  -- 8) Stack-safety verifier. After SCC merge and CPS there must be
  --    no non-trivial call-graph cycle and no CFunDef with a non-tail
  --    self-call — both mean a recursion shape that would silently
  --    overflow the system stack at depth on some backend. Any
  --    remainder is a compile error (no escape hatch): the program is
  --    either user-level ill-formed (mutually recursive 'CValDef's,
  --    which have no fixed point) or a compiler bug.
  case verifyStackSafety cpsed of
    [] -> pass
    (issue : _) -> Left (toTypeError sigMap issue)
  -- 9) Self-TCO: rewrite self-recursive tail calls into 'CContinue', and
  --    wrap affected function bodies in 'CLoop'. Backends compile the
  --    wrapped form into a loop + jump rather than a recursive call,
  --    guaranteeing stack safety for tail recursion across all targets.
  pure (warnings, tcoProgram cpsed)

-- | Translate a 'StackSafetyIssue' into a user-facing 'TypeError',
-- recovering a source span from the corresponding 'Sig' in the surface
-- AST when available (generated names like @$cps$f@ won't have one
-- and fall back to 'noSpan').
toTypeError :: M.Map Name Type' -> StackSafety.StackSafetyIssue -> TypeError
toTypeError sigMap = \case
  StackSafety.MutuallyRecursiveValues names ->
    MutuallyRecursiveValues (spanFor names) names
  StackSafety.UnsupportedRecursionShape names ->
    StackUnsafeRecursion (spanFor names) names
  where
    spanFor :: [Name] -> SrcSpan
    spanFor names = fromMaybe noSpan (viaNonEmpty head (mapMaybe lookupSpan names))

    lookupSpan :: Name -> Maybe SrcSpan
    lookupSpan n = case M.lookup n sigMap of
      Just (TyVar sp _) -> Just sp
      Just (TyCon sp _) -> Just sp
      Just (TyApp sp _ _) -> Just sp
      Just (TyArrow sp _ _) -> Just sp
      Just (TyOr sp _ _) -> Just sp
      Nothing -> Nothing

-- | Reachability over the Core call graph starting from @root@.
reachableCore :: Name -> M.Map Name (Set Name) -> Set Name
reachableCore root graph = go (Set.singleton root) [root]
  where
    go visited [] = visited
    go visited (n : rest) =
      let neighbours = fromMaybe Set.empty (M.lookup n graph)
          fresh = Set.filter (`Set.notMember` visited) neighbours
       in go (visited <> fresh) (rest <> Set.toList fresh)

-- | Drop declarations that are no longer reachable from @main@. Used
-- after passes that rewrite call sites to fresh targets (like SCC
-- merge, which routes every cross-call through @$scc$...@ and can
-- leave the original member's wrapper dead).
treeShakeFromMain :: CoreProgram -> CoreProgram
treeShakeFromMain (CoreProgram ds) =
  let graph = M.fromList [(declName' d, declFreeVars d) | d <- ds]
      reached = reachableCore "main" graph
      live = [d | d <- ds, Set.member (declName' d) reached]
   in CoreProgram live

-- | Top-level name of a Core declaration.
declName' :: CDecl -> Name
declName' = \case
  CFunDef n _ _ -> n
  CValDef n _ -> n

-- | Free variables referenced in a top-level Core declaration. Used by
--   'elaborateLowerProgram' to drop unused constructor wrappers.
declFreeVars :: CDecl -> Set Name
declFreeVars = \case
  CFunDef _ _ body -> freeVars body
  CValDef _ body -> freeVars body

-- | Build the name→type lookup used by 'lowerExpr' to propagate expected
--   types down to integer literals. Combines user signatures, the current
--   program type's platform-effect table, and (as a future hook)
--   constructor types.
mkLowerEnv :: ProgramType -> ConInfoEnv -> M.Map Name Type' -> M.Map Name SrcSpan -> LowerEnv
mkLowerEnv progType conInfo sigMap typeDeclSpans =
  let userSigs = M.fromList [(QName [] n, t) | (n, t) <- M.toList sigMap]
      lookupName q = M.lookup q (userSigs <> platformTable progType)
   in LowerEnv
        { leProgramType = progType,
          leTypeOf = lookupName,
          leConInfo = conInfo,
          leTypeDeclSpans = typeDeclSpans
        }

-- | Saturate under-applied direct calls by lambda-lifting.
--
-- For each 'CCall (CVar f) args' where 'f' is a known top-level function whose arity
-- exceeds the number of supplied arguments, we generate a helper top-level
-- 'CFunDef' that takes the missing arguments and calls the original with the full
-- list. The call site is replaced with a bare reference to the helper, which every
-- backend already renders as a first-class function value.
--
-- This handles partial application whose bound arguments only reference other
-- top-level names (no local captures). If a bound argument references a local
-- parameter we fail with 'TELowering' — closure support would require a runtime
-- PAP representation in each backend and is out of scope here.
saturateProgram :: CoreProgram -> Either TypeError CoreProgram
saturateProgram (CoreProgram ds) = do
  let arityMap = M.fromList [(n, length as) | CFunDef n as _ <- ds]
  (ds', extras) <- runStateT (traverse (saturateDecl arityMap) ds) []
  pure (CoreProgram (ds' <> reverse extras))

type SatM = StateT [CDecl] (Either TypeError)

saturateDecl :: M.Map Name Int -> CDecl -> SatM CDecl
saturateDecl am = \case
  CFunDef n args body ->
    CFunDef n args <$> saturateExpr am (fromList args) body
  CValDef n rhs ->
    CValDef n <$> saturateExpr am mempty rhs

saturateExpr :: M.Map Name Int -> Set Name -> CExpr -> SatM CExpr
saturateExpr am locals = go
  where
    go = \case
      e@(CString _) -> pure e
      e@(CIntLit _ _) -> pure e
      e@(CVar _) -> pure e
      e@(CBuiltIn _) -> pure e
      CCon tag fs -> CCon tag <$> traverse go fs
      CCase s alts -> CCase <$> go s <*> traverse goAlt alts
      CRow tag v -> CRow tag <$> go v
      CRowCase s alts ->
        CRowCase <$> go s <*> traverse goRowAlt alts
      CCall callee args -> do
        callee' <- go callee
        args' <- traverse go args
        case callee' of
          CVar f
            | Just ar <- M.lookup f am,
              length args' < ar ->
                liftPap f args' ar
          _ -> pure (CCall callee' args')
      -- Saturation runs before the TCO pass, so 'CLoop' / 'CContinue'
      -- cannot appear here. Keep the cases so the exhaustiveness check
      -- is honest; they are no-ops if the pipeline order ever changes.
      CLoop b -> CLoop <$> go b
      CContinue xs -> CContinue <$> traverse go xs
    goAlt (tag, vars, body) = do
      body' <- saturateExpr am (locals <> fromList vars) body
      pure (tag, vars, body')

    goRowAlt (tag, var, body) = do
      body' <- saturateExpr am (Set.insert var locals) body
      pure (tag, var, body')

    liftPap f args ar = do
      let missing = ar - length args
          etas = ["$eta" <> show i | i <- [0 .. missing - 1]]
          freeInArgs = foldMap freeVars args `Set.intersection` locals
      -- Defunctionalisation runs before saturate and rewrites every
      -- reachable closure (top-level partial application with captured
      -- locals) into a fully-applied call to a specialised first-order
      -- helper. A surviving capture here would generate a '$pap$N' that
      -- references names not in scope at top level — a hard codegen
      -- error rather than something the user can act on. We keep the
      -- branch as an internal-invariant assertion.
      if not (Set.null freeInArgs)
        then
          lift
            $ Left
            $ TELowering
            $ "internal: saturate observed a partial application with "
            <> "local captures after defunctionalisation — captured "
            <> T.intercalate ", " (toList freeInArgs)
        else do
          extras <- get
          let idx = length extras
              papName = "$pap$" <> show idx
              papBody = CCall (CVar f) (args <> map CVar etas)
              papDecl = CFunDef papName etas papBody
          put (papDecl : extras)
          pure (CVar papName)

freeVars :: CExpr -> Set Name
freeVars = \case
  CString _ -> mempty
  CIntLit _ _ -> mempty
  CVar n -> one n
  CBuiltIn _ -> mempty
  CCon _ fs -> foldMap freeVars fs
  CCase s alts ->
    freeVars s
      <> foldMap (\(_, vs, b) -> freeVars b `Set.difference` fromList vs) alts
  CRow _ v -> freeVars v
  CRowCase s alts ->
    freeVars s
      <> foldMap (\(_, v, b) -> freeVars b `Set.difference` Set.singleton v) alts
  CCall f xs -> freeVars f <> foldMap freeVars xs
  CLoop b -> freeVars b
  CContinue xs -> foldMap freeVars xs

-- | Lower a top-level declaration.
--   • Type signatures and type declarations are erased (they already influenced checking).
--   • Zero-arg defs become constants ('CValDef'), others become first-order functions.
--   • The signature, when present, gives the expected result type — used by
--     'lowerExpr' to resolve the type of any 'LInt' literal appearing in the
--     body (surface integer literals are untyped).
-- | Lower a top-level declaration. The function's parameters become
--   the initial 'Locals' set so that any 'ELam' inside the body
--   knows which names it can capture.
lowerDeclM :: LowerEnv -> M.Map Name Type' -> Decl -> LowerM (Maybe CDecl)
lowerDeclM env sigMap = \case
  Sig {} -> pure Nothing
  CommentDecl _ -> pure Nothing
  TypeDecl {} -> pure Nothing
  FunDef _sp _n [] body _ | isBareBuiltIn body -> pure Nothing
  FunDef _sp n [] body _
    | Just ty <- M.lookup n sigMap,
      let (argTys, _) = splitArrow ty,
      not (null argTys) -> do
        body' <- lowerExprM env Set.empty Nothing body
        let etas = ["$eta" <> show (i :: Int) | i <- [0 .. length argTys - 1]]
            call = CCall body' (map CVar etas)
        pure $ Just $ CFunDef n etas call
  FunDef _sp n args body _ -> do
    let (argTys, resultTy) = case M.lookup n sigMap of
          Just t -> splitArrowN (length args) t
          Nothing -> ([], Nothing)
        paramEntries =
          [ (QName [] (paramName p), ty)
          | (p, Just ty) <- zip args (map Just argTys <> repeat Nothing)
          ]
        env' = extendLowerEnv env paramEntries
        locals = Set.fromList (map paramName args)
    body' <- lowerExprM env' locals resultTy body
    let args' = freshenWildcardArgs (map paramName args)
    pure $ Just $ case args' of
      [] -> CValDef n body' -- zero-arg def ⇒ constant
      _ -> CFunDef n args' body'

-- | Split an arrow type into @(first n arg types, result type)@.
--   Example: @splitArrowN 2 (A -> B -> C -> D)  ==>  ([A,B], Just (C -> D))@.
--   If the type does not have enough arrows, returns @(partial args, Nothing)@.
splitArrowN :: Int -> Type' -> ([Type'], Maybe Type')
splitArrowN = go []
  where
    go acc 0 t = (reverse acc, Just t)
    go acc k (TyArrow _ a b) = go (a : acc) (k - 1) b
    go acc _ _ = (reverse acc, Nothing)

-- | Add extra name→type entries to a 'LowerEnv' (e.g. function parameters).
extendLowerEnv :: LowerEnv -> [(QName, Type')] -> LowerEnv
extendLowerEnv env entries =
  let extra = M.fromList entries
      look q = M.lookup q extra <|> leTypeOf env q
   in env {leTypeOf = look}

-- | Replace each @"_"@ in the argument list with a unique fresh name
--   (@$wild0@, @$wild1@, …) so emitted local names never collide.
freshenWildcardArgs :: [Name] -> [Name]
freshenWildcardArgs = go (0 :: Int)
  where
    go _ [] = []
    go i ("_" : xs) = ("$wild" <> show i) : go (i + 1) xs
    go i (x : xs) = x : go i xs

-- | Lower a surface expression to Core.
--     • drop explicit parentheses,
--     • translate string literals verbatim,
--     • resolve integer literals to typed 'CIntLit' using the expected type
--       ('Maybe Type'') propagated from an enclosing signature or function arg,
--     • map @e1 ++ e2@ to a primitive call,
--     • flatten left-associated application into a single 'CCall', propagating
--       argument types down so nested literals are resolved,
--     • map constructors to integer tags,
--     • non-nullary constructors used as values become wrapper references,
--     • map @case@ to tag-based dispatch.
--
-- The 'Maybe Type'' argument is the expected type of the expression, if known
-- from context (e.g. the signature's return type, or the argument slot of a
-- call). It is only consulted for 'LInt' literals — every other expression
-- ignores it.
-- | Lower an expression — threads 'LowerM' state so 'ELam' nodes can
--   emit lifted top-level helpers, plus a 'Locals' set tracking which
--   names are in-scope local bindings (for capture analysis).
lowerExprM :: LowerEnv -> Locals -> Maybe Type' -> Expr -> LowerM CExpr
lowerExprM env locals expected = \case
  EParens _sp e -> lowerExprM env locals expected e
  EVar _sp qn -> liftEither (lowerVar env qn)
  ELit _sp (LString t) -> pure (CString t)
  ELit sp (LInt n) -> case expected of
    Just (TyCon _ "Int32") -> pure (CIntLit n TInt32)
    Just (TyCon _ "UInt8") -> pure (CIntLit n TUInt8)
    Just (TyCon _ "UInt32") -> pure (CIntLit n TUInt32)
    _ -> liftEither $ Left (TELowering ("integer literal without a known numeric type at " <> show (spanStartLine sp) <> ":" <> show (spanStartCol sp)))
  EInfix _sp OpConcat l r ->
    -- (a ++ b) lowers to `Right (concatString a b)`, matching Prelude's
    -- `(++) : String -> String -> Either StringTooLong String` claim.
    -- Phase 1 always produces Right; the Left branch becomes reachable in
    -- phase 2.x when length validation lands in the runtime.
    let strExpected = Just (TyCon noSpan "String")
     in do
          l' <- lowerExprM env locals strExpected l
          r' <- lowerExprM env locals strExpected r
          let concatCall = CCall (CBuiltIn "concatString") [l', r']
          -- 'Right' has tag 1 in `type Either a b = Left a | Right b`.
          pure (CCon 1 [concatCall])
  ECon _sp name -> case M.lookup name (leConInfo env) of
    Just ci
      | ciArity ci == 0 -> do
          let bare = CCon (ciTag ci) []
              tyName = ciTypeName ci
          case expected of
            Just expRow@(TyOr {})
              | Just lbl <- find (\l -> tyConHead l == Just tyName) (flattenRow expRow) -> do
                  tag <- recordRowTag lbl
                  pure (CRow tag bare)
            _ -> pure bare
      | otherwise -> pure (CVar (conWrapperName name))
    Nothing -> liftEither $ Left (TELowering ("unknown constructor: " <> name))
  EBuiltIn _sp name -> pure (CBuiltIn name)
  ELam sp params body -> liftLambda env locals expected sp params body
  -- After 'Awsum.Desugar', any non-'PVar' / non-'PWild' let-binding
  -- has been rewritten to 'ECase'. The lowering only sees simple
  -- name (or wildcard) bindings here; 'PWild' uses the same
  -- '$let_w_<sp>' synthetic-name path that 'lowerLet' applies for
  -- 'PVar' under the hood.
  ELet sp pat mAnnot e body -> case pat of
    PVar _ n -> lowerLet env locals expected sp n mAnnot e body
    PWild psp ->
      let n = "$let_w_" <> show (spanStartLine psp) <> "_" <> show (spanStartCol psp)
       in lowerLet env locals expected sp n mAnnot e body
    _ -> liftEither $ Left (TELowering "non-PVar let-binding should have been desugared by Awsum.Desugar")
  EDo _sp _ -> liftEither $ Left (TELowering "do-block not desugared before lowering — internal pipeline error")
  ECase _sp scrut alts _ -> do
    scrut' <- lowerExprM env locals Nothing scrut
    let mScrutTy = synthLabelType env scrut
    case mScrutTy of
      Just scrutRowTy@(TyOr {}) -> do
        rowAlts <- buildRowAltsM env locals expected scrutRowTy (toList alts)
        pure (CRowCase scrut' rowAlts)
      _ -> do
        alts' <- traverse (lowerAltM env locals mScrutTy expected) (toList alts)
        merged <- liftEither (mergeAlts alts')
        pure (CCase scrut' merged)
  EApp _sp f x -> do
    let (f0, xs) = collectApps f [x]
    case f0 of
      ECon _sp' name -> case M.lookup name (leConInfo env) of
        Just ci -> do
          let (effectiveOuter, mWrapLabel) = case expected of
                Just outer@(TyOr {})
                  | Just lbl <- find (\l -> tyConHead l == Just (ciTypeName ci)) (flattenRow outer) ->
                      (Just lbl, Just lbl)
                Just outer -> (Just outer, Nothing)
                Nothing -> (Nothing, Nothing)
              argExpected = constructorArgExpected ci effectiveOuter
          mWrapTag <- traverse recordRowTag mWrapLabel
          xs' <- zipWithM (lowerArgWithRowInjectionM env locals) argExpected xs
          let bare = CCon (ciTag ci) xs'
          pure $ case mWrapTag of
            Just t -> CRow t bare
            Nothing -> bare
        Nothing -> liftEither $ Left (TELowering ("unknown constructor: " <> name))
      EDo _ _ -> liftEither $ Left (TELowering "do-block not desugared before lowering — internal pipeline error")
      _ -> do
        -- A lambda head ('(\x -> x) 5'-shape) doesn't live in 'leTypeOf',
        -- but 'synthLabelType' synthesises an arrow type for it (with
        -- span-unique fresh tyvars in parameter slots). Treating that
        -- synthesised type the same way as a 'leTypeOf' lookup gives
        -- the bidirectional unify below something to chew on, so a
        -- bare integer literal as an argument gets pinned through the
        -- outer expected result type.
        let isLamHead = \case
              ELam {} -> True
              EParens _ inner -> isLamHead inner
              _ -> False
            mHeadTy = case f0 of
              EVar _ qn -> leTypeOf env qn
              _ | isLamHead f0 -> synthLabelType env f0
              _ -> Nothing
            (argTys, mResultTy) = case mHeadTy of
              Just t -> splitArrowN (length xs) t
              Nothing -> ([], Nothing)
            -- Mirror the typechecker's bidirectional EApp clause: when
            -- the surrounding context fixes the result type and the
            -- function's signature is polymorphic, unifying the
            -- generic result with the outer expected pins the type
            -- variables that appear in the argument slots. We also
            -- collect substitutions from individual arguments —
            -- specifically, a lambda whose body is a 'EVar' contributes
            -- the body's binding to the lambda's expected result type
            -- — so a bare integer literal under a polymorphic call
            -- like @apply (\n -> n) 42 : Int32@ reaches its 'CIntLit'
            -- conversion with @Int32@ in hand instead of an unresolved
            -- @a@ tyvar.
            sResult = case (expected, mResultTy) of
              (Just outer, Just rty) -> fromRight mempty (unify rty outer)
              _ -> mempty
            sArgs = foldMap (uncurry (argSubst env)) [(applySubst sResult t, x') | (t, x') <- zip argTys xs]
            sFinal = sArgs <> sResult
            argTys' = map (applySubst sFinal) argTys
            argExpected = map Just argTys' <> repeat Nothing
        -- For lambda heads ('(\x -> x) 5'-shape calls), pass the
        -- synthesised arrow type as expected so 'liftLambda' can
        -- split it into per-parameter and result types — same path
        -- it already takes when the lambda flows into a HOF
        -- argument slot. For non-lambda heads we keep 'Nothing'
        -- (their type comes from a top-level signature or local
        -- binding).
        let f0Expected = if isLamHead f0 then mHeadTy else Nothing
        f0' <- lowerExprM env locals f0Expected f0
        xs' <- zipWithM (lowerArgWithRowInjectionM env locals) argExpected xs
        let bare = CCall f0' xs'
            mResultTy' = applySubst sFinal <$> mResultTy
        wrapInjectedM (leConInfo env) expected mResultTy' bare

-- | Best-effort substitution that an argument expression contributes
--   given a (possibly tyvar-laden) expected type. Used by 'lowerExprM'
--   on non-constructor 'EApp' to refine the argument-type slots that
--   depend on type variables shared with the function's polymorphic
--   signature — e.g. the @a@ in @apply : (a -> b) -> a -> b@ that the
--   lambda body's type @n : a@ pins to @Int32@ when checked against
--   the lambda's expected result. Mirrors what the typechecker's
--   bidirectional 'EApp' clause learns; needed here because lowering
--   propagates expected types per-argument independently and would
--   otherwise reach a bare integer literal with @a@ unresolved.
argSubst :: LowerEnv -> Type' -> Expr -> Subst
argSubst env expected = \case
  EParens _ inner -> argSubst env expected inner
  EVar _ qn -> case leTypeOf env qn of
    Just t -> fromRight mempty (unify expected t)
    Nothing -> mempty
  ELam _ params body -> case splitArrowN (length params) expected of
    (paramTys, Just resTy)
      | length paramTys == length params ->
          let env' =
                extendLowerEnv
                  env
                  [(QName [] (paramName p), pTy) | (p, pTy) <- zip params paramTys]
           in argSubst env' resTy body
    _ -> mempty
  _ -> mempty

-- | Lift an 'ELam' to a fresh top-level helper. The lambda's
--   parameter types come from the expected outer arrow; its
--   captures come from the names referenced inside the body that
--   intersect the surrounding 'Locals' (function parameters and
--   outer lambda parameters). Returns a partial application of the
--   helper to the captured names — the lambda's own parameters
--   remain unsupplied, so saturate / TCO see the resulting CCall as
--   an under-applied call to a known top-level function.
liftLambda :: LowerEnv -> Locals -> Maybe Type' -> SrcSpan -> [Param] -> Expr -> LowerM CExpr
liftLambda env locals mExpected _sp params body = do
  -- Split the expected arrow type into per-parameter types and the
  -- result type. The typechecker has already validated the lambda
  -- against this expected type; if 'mExpected' is 'Nothing' or has
  -- the wrong shape, that's an internal lowering bug.
  (paramTys, resultTy) <- case mExpected of
    Just t -> case splitArrowN (length params) t of
      (pTys, Just r) | length pTys == length params -> pure (pTys, Just r)
      _ -> liftEither $ Left (TELowering "lambda's expected type doesn't match its arity at lowering")
    Nothing -> liftEither $ Left (TELowering "lambda has no expected type at lowering")
  let paramNames = map paramName params
      lamParamSet = Set.fromList paramNames
  -- Captures: free references in body restricted to in-scope locals,
  -- minus the lambda's own parameters (which shadow outer names of
  -- the same name — but the no-shadowing rule has already ruled this
  -- out at typecheck time).
  let captures = Set.toAscList ((freeReferences body `Set.intersection` locals) `Set.difference` lamParamSet)
      captureTypes =
        [ fromMaybe (TyVar noSpan "_capture") (leTypeOf env (QName [] c))
        | c <- captures
        ]
  -- Recursively lower the body with the lambda's params added to
  -- both env and locals. Capture types are already in env (they
  -- come from the enclosing definition).
  let env' =
        extendLowerEnv
          env
          ( [(QName [] (paramName p), pTy) | (p, pTy) <- zip params paramTys]
              <> [(QName [] c, ty) | (c, ty) <- zip captures captureTypes]
          )
      locals' = Set.union lamParamSet locals
  body' <- lowerExprM env' locals' resultTy body
  helperName <- freshLamName
  let allParams = captures <> paramNames
  emitHelper (CFunDef helperName (freshenWildcardArgs allParams) body')
  pure $ case captures of
    [] -> CVar helperName
    _ -> CCall (CVar helperName) (map CVar captures)

-- | Lower @let n = e in body@ by lifting the body into a fresh
--   top-level helper @$let$N captures n = body'@ and emitting a
--   /saturated/ call @$let$N captures e@. The helper takes the
--   let-binder as its last formal parameter; captures from the
--   enclosing scope are prepended so the helper itself is a closed
--   first-order function — exactly the shape every backend already
--   handles.
--
--   This shares the lift mechanism with 'liftLambda', but the call
--   is fully applied at the call site, so 'saturate' sees a direct
--   call to a known top-level function rather than a partial
--   application. No closure / PAP runtime is needed; @e@ is
--   evaluated exactly once regardless of how many times @n@ appears
--   in @body@.
--
--   The let-binder's type is best-effort synthesised via
--   'synthLabelType'; if synthesis can't pin it down (e.g. the RHS
--   is a polymorphic application whose result depends on the outer
--   expected type and we don't have it here), we fall back to a
--   tyvar — the same conservative answer 'liftLambda' uses for
--   unknown capture types. The let-binder is then in scope for
--   nested lookups in @body@ even when the precise type is unknown.
lowerLet ::
  LowerEnv ->
  Locals ->
  Maybe Type' ->
  SrcSpan ->
  Name ->
  Maybe Type' ->
  Expr ->
  Expr ->
  LowerM CExpr
lowerLet env locals expected _sp n mAnnot e body = do
  -- Prefer the user-written ascription as @n@'s type when present —
  -- it's the same type the typechecker pushed into 'checkExpr' for
  -- @e@, so 'body' lookups (e.g., row-tag resolution on a binder
  -- whose type is row-shaped) see it correctly. Without an
  -- ascription, fall back to best-effort 'synthLabelType' on @e@,
  -- mirroring the lambda-lift capture-type policy.
  let nTy = case mAnnot of
        Just t -> t
        Nothing -> fromMaybe (TyVar noSpan "_letBind") (synthLabelType env e)
      bodyFree = freeReferences body
      -- Captures: every local visible at the let site that 'body'
      -- references, minus the let-binder itself (which is supplied
      -- by the call, not captured).
      captures = Set.toAscList ((bodyFree `Set.intersection` locals) `Set.difference` Set.singleton n)
      captureTypes =
        [ fromMaybe (TyVar noSpan "_capture") (leTypeOf env (QName [] c))
        | c <- captures
        ]
      env' =
        extendLowerEnv
          env
          ( (QName [] n, nTy)
              : [(QName [] c, ty) | (c, ty) <- zip captures captureTypes]
          )
      locals' = Set.insert n locals
  body' <- lowerExprM env' locals' expected body
  e' <- lowerExprM env locals (Just nTy) e
  helperName <- freshLetName
  let allParams = captures <> [n]
  emitHelper (CFunDef helperName (freshenWildcardArgs allParams) body')
  pure (CCall (CVar helperName) (map CVar captures <> [e']))

-- | Per-argument expected types for a constructor application.
--
--   Given the constructor's 'ConInfo' and the outer expected type
--   pushed in by the surrounding context, return @Just t@ for each
--   field where @t@ is the field type with the constructor's type
--   parameters bound to the concrete arguments matched out of the
--   outer expected type, and @Nothing@ where the binding cannot be
--   determined (no outer expected, or shape mismatch). Implicit
--   injection through nominal heads relies on these expected types
--   reaching 'lowerArgWithRowInjection'.
constructorArgExpected :: ConInfo -> Maybe Type' -> [Maybe Type']
constructorArgExpected ci mOuter =
  case mOuter of
    Just outerTy ->
      let genericRet = applyTyParams (ciTypeName ci) (ciTypeParams ci)
       in case unify genericRet outerTy of
            Right s -> map (Just . applySubst s) (ciFieldTypes ci)
            Left _ -> map (const Nothing) (ciFieldTypes ci)
    Nothing -> map (const Nothing) (ciFieldTypes ci)

-- | Build the un-substituted result type for a constructor: e.g.
--   @applyTyParams "Either" ["a", "b"] = TyApp (TyApp (TyCon "Either") (TyVar "a")) (TyVar "b")@.
--   Mirrors 'Awsum.Typing.conReturnType' but is local to lowering so
--   we don't depend on the typechecker's conEnv.
applyTyParams :: Name -> [Name] -> Type'
applyTyParams n [] = TyCon noSpan n
applyTyParams n tvs = foldl' (\acc tv -> TyApp noSpan acc (TyVar noSpan tv)) (TyCon noSpan n) tvs

-- | Lower an argument expression, wrapping with 'CRow' when the
--   parameter type is a structural sum and the argument's actual type
--   matches one of the row's labels (implicit injection reified at
--   lowering time so the runtime sees a tagged value), or generating
--   a cross-boundary coercion helper when the source value was built
--   in a context whose runtime shape differs from the target's
--   (e.g. @Maybe Bool@ flowing into @Maybe (Bool | Unit)@ — the inner
--   @Bool@ has a positional constructor tag at construction site but
--   needs a row-hash tag at the use site).
--
--   For non-row parameter types this is just 'lowerExpr', except
--   when the source synthesised type is structurally compatible with
--   the target via cross-boundary coercion, in which case 'synthCoerce'
--   emits a @$lift$N@ helper that walks the value and rebuilds it in
--   the target shape.
lowerArgWithRowInjectionM :: LowerEnv -> Locals -> Maybe Type' -> Expr -> LowerM CExpr
lowerArgWithRowInjectionM env locals mExpected x = case mExpected of
  Just expected@(TyOr {}) ->
    let labels = flattenRow expected
        intLabels = [TyCon noSpan n | TyCon _ n <- labels, isJust (intTypeRange n)]
     in case x of
          ELit _ (LInt _) -> case intLabels of
            [intLabel] -> do
              v <- lowerExprM env locals (Just intLabel) x
              tag <- recordRowTag intLabel
              pure (CRow tag v)
            _ -> liftEither $ Left (TELowering "lowering: integer literal in row position has no unique int label")
          EParens _ inner -> lowerArgWithRowInjectionM env locals mExpected inner
          _ -> case synthLabelType env x of
            Just lbl@(TyVar _ _)
              | lbl `elem` labels ->
                  lowerExprM env locals (Just lbl) x
            Just lbl | lbl `elem` labels -> do
              v <- lowerExprM env locals (Just lbl) x
              tag <- recordRowTag lbl
              pure (CRow tag v)
            -- Cross-boundary into a TyOr: source isn't an exact label,
            -- but matches one of them under coercion (e.g. source
            -- @Maybe Bool@, target row has @Maybe (Bool | Unit)@ as a
            -- label). Synthesise a coercion to the matching label and
            -- then wrap with that label's row tag.
            Just src
              | Just lbl <- findCoercibleLabel src labels -> do
                  v <- lowerExprM env locals (Just src) x
                  wrap <- synthCoerce (leConInfo env) src lbl
                  v' <- wrap v
                  tag <- recordRowTag lbl
                  pure (CRow tag v')
            _ -> lowerExprM env locals mExpected x
  -- Non-row expected: cross-boundary coercion when source and target
  -- share a nominal head but differ in row positions inside it.
  Just expected -> case synthLabelType env x of
    Just src
      | not (typeEq src expected),
        coercible src expected -> do
          v <- lowerExprM env locals (Just src) x
          wrap <- synthCoerce (leConInfo env) src expected
          wrap v
    _ -> lowerExprM env locals mExpected x
  Nothing -> lowerExprM env locals mExpected x

-- | Structural equality on types (ignoring spans).
typeEq :: Type' -> Type' -> Bool
typeEq a b = canonicalLabel a == canonicalLabel b

-- | Cheap pre-check: is there a coercion @src → tgt@ that 'synthCoerce'
--   could synthesise? Used to gate the 'synthCoerce' call so we don't
--   emit helpers (or fail) on unrelated types where the typechecker
--   has already validated equality. The actual building work happens
--   in 'synthCoerce'.
coercible :: Type' -> Type' -> Bool
coercible src tgt
  | typeEq src tgt = True
  | TyVar {} <- tgt = True
  | TyVar {} <- src = True
  | TyOr {} <- tgt = any (coercible src) (flattenRow tgt)
  -- Source is a row but target isn't: would lose alternatives.
  | TyOr {} <- src = False
  -- Multi-arg type constructors land here as nested TyApps; recurse
  -- on both sides so a head difference deeper than one level (e.g.
  -- @Either ErrB Int32@ vs @Either (ErrA | ErrB) Int32@, where the
  -- first @TyApp@ pair already differs because the inner row sits
  -- inside @TyApp Either …@) still resolves through 'synthCoerce'.
  | TyApp _ f1 x1 <- src,
    TyApp _ f2 x2 <- tgt =
      coercible f1 f2 && coercible x1 x2
  | otherwise = False

-- | Find a label in the target row that 'src' can be coerced to.
--   Prefers exact matches (handled by caller before this is reached);
--   falls back to recursive 'coercible' check.
findCoercibleLabel :: Type' -> [Type'] -> Maybe Type'
findCoercibleLabel src = find (coercible src)

-- | Apply implicit row-injection to an already-lowered CExpr based on
--   the expression's source and expected types. Mirrors
--   'lowerArgWithRowInjectionM' but operates post-lowering, so it can
--   wrap expression positions whose lowering doesn't recursively
--   thread the expected type — e.g. the result of a non-constructor
--   call, where the expected type informs argument lowering but the
--   call result itself was returned unwrapped.
wrapInjectedM :: ConInfoEnv -> Maybe Type' -> Maybe Type' -> CExpr -> LowerM CExpr
wrapInjectedM conInfo (Just expected@(TyOr {})) (Just src) bare
  | src `elem` flattenRow expected = do
      tag <- recordRowTag src
      pure (CRow tag bare)
  | Just lbl <- findCoercibleLabel src (flattenRow expected),
    not (typeEq src lbl) = do
      wrap <- synthCoerce conInfo src lbl
      v <- wrap bare
      tag <- recordRowTag lbl
      pure (CRow tag v)
wrapInjectedM conInfo (Just expected) (Just src) bare
  | not (typeEq src expected),
    not (isTyOr expected),
    coercible src expected = do
      wrap <- synthCoerce conInfo src expected
      wrap bare
  where
    isTyOr (TyOr {}) = True
    isTyOr _ = False
wrapInjectedM _ _ _ bare = pure bare

-- | Synthesise a CExpr-level coercion from @src@ to @tgt@. The
--   returned function wraps a CExpr of source type into one of target
--   type — identity when types agree, a 'CRow' wrap when target is a
--   row and source is one of its labels, or an emitted '$lift$N'
--   helper that destructures a nominal-headed value and reconstructs
--   it with row tags injected per-field.
--
--   Helpers are memoised by @(canonicalLabel src, canonicalLabel tgt)@
--   so recursive types like @List a@ get a single self-recursive
--   helper rather than an infinite expansion.
synthCoerce :: ConInfoEnv -> Type' -> Type' -> LowerM (CExpr -> LowerM CExpr)
synthCoerce _ src tgt
  | typeEq src tgt = pure pure
synthCoerce _ (TyVar _ _) _ = pure pure
synthCoerce _ _ (TyVar _ _) = pure pure
synthCoerce conInfo src tgt@(TyOr {}) =
  case findCoercibleLabel src (flattenRow tgt) of
    Just lbl -> do
      inner <- synthCoerce conInfo src lbl
      tag <- recordRowTag lbl
      pure (\v -> do v' <- inner v; pure (CRow tag v'))
    Nothing ->
      liftEither
        $ Left
          ( TELowering
              ( "synthCoerce: no row label in "
                  <> canonicalLabel tgt
                  <> " accepts "
                  <> canonicalLabel src
              )
          )
synthCoerce conInfo src tgt
  | Just headName <- tyConHead src,
    Just headName' <- tyConHead tgt,
    headName == headName' =
      synthNominalHeadCoerce conInfo headName src tgt
synthCoerce _ src tgt =
  liftEither
    $ Left
      ( TELowering
          ( "synthCoerce: incompatible shapes "
              <> canonicalLabel src
              <> " ≁ "
              <> canonicalLabel tgt
          )
      )

-- | Coerce two type-applications sharing a common nominal head.
--   Generates (or reuses, via the @lsLifters@ memo) a top-level
--   helper @$lift$N : src -> tgt@ that destructures via @case@ on
--   each constructor of the head's owning type and reconstructs with
--   per-field coercions in target shape. The memo entry is registered
--   /before/ the body is generated, so recursive types reach a
--   self-recursive call instead of looping.
synthNominalHeadCoerce :: ConInfoEnv -> Name -> Type' -> Type' -> LowerM (CExpr -> LowerM CExpr)
synthNominalHeadCoerce conInfo tyName src tgt = do
  let key = (canonicalLabel src, canonicalLabel tgt)
  st <- get
  case M.lookup key (lsLifters st) of
    Just helper -> pure (\v -> pure (CCall (CVar helper) [v]))
    Nothing -> do
      helper <- freshLiftName
      modify (\s -> s {lsLifters = M.insert key helper (lsLifters s)})
      let cons = constructorsOfType conInfo tyName
          srcParams = maybe [] ciTypeParams (M.lookup (firstConName cons) conInfo)
          -- Freshen the generic-head's parameters (and the per-field
          -- types that mention them) before unifying. Without this,
          -- an input type whose tyvar happens to share a name with
          -- one of the type's own parameters — e.g. @Either PE a@,
          -- where @a@ also names @Either@'s second parameter — would
          -- cross-bind during 'unify' and corrupt the per-field
          -- substitution. The "$ctor" suffix is just a marker; the
          -- exact name doesn't matter as long as it doesn't collide
          -- with any tyvar in @src@ or @tgt@.
          freshSubst =
            mconcat [singletonSubst p (TyVar noSpan (p <> "$ctor")) | p <- srcParams]
          freshGeneric = applySubst freshSubst (applyTyParams tyName srcParams)
          srcSubst = fromRight mempty $ unify freshGeneric src
          tgtSubst = fromRight mempty $ unify freshGeneric tgt
      arms <-
        forM cons $ \(_cName, ci) -> do
          let tag = ciTag ci
              fieldNames = ["__f" <> show i | i <- [(0 :: Int) .. ciArity ci - 1]]
              fields = map (applySubst freshSubst) (ciFieldTypes ci)
              srcFields = map (applySubst srcSubst) fields
              tgtFields = map (applySubst tgtSubst) fields
          coercedFields <-
            forM (zip3 fieldNames srcFields tgtFields) $ \(fn, sTy, tTy) -> do
              wrap <- synthCoerce conInfo sTy tTy
              wrap (CVar fn)
          pure (tag, fieldNames, CCon tag coercedFields)
      let body = CCase (CVar "__input") arms
      emitHelper (CFunDef helper ["__input"] body)
      pure (\v -> pure (CCall (CVar helper) [v]))

-- | All constructors of a given user-defined type, sorted by tag.
--   Used by 'synthNominalHeadCoerce' to walk the constructors of the
--   shared head when building the destructure-and-rebuild helper.
constructorsOfType :: ConInfoEnv -> Name -> [(Name, ConInfo)]
constructorsOfType conInfo tyName =
  sortOn
    (ciTag . snd)
    [(cn, ci) | (cn, ci) <- M.toList conInfo, ciTypeName ci == tyName]

-- | First constructor name from a 'constructorsOfType' result; used
--   only to fetch the owning type's type-parameter list (every
--   constructor of the same type carries the same parameters, so any
--   one will do; we take the first for determinism).
firstConName :: [(Name, ConInfo)] -> Name
firstConName ((n, _) : _) = n
firstConName [] = "" -- empty type: no constructors, body never runs

-- | Best-effort synthesis of an expression's type, used at lowering
--   time to pick the right row label for implicit injection.
--   Intentionally partial — only the shapes that can flow into a row
--   position in user-facing programs.
synthLabelType :: LowerEnv -> Expr -> Maybe Type'
synthLabelType env = \case
  EVar _ qn -> leTypeOf env qn
  EBuiltIn _ n -> lookupBuiltIn n
  ELit _ (LString _) -> Just (TyCon noSpan "String")
  ELit _ (LInt _) -> Nothing -- caller resolves via row's int label
  EParens _ inner -> synthLabelType env inner
  EInfix {} -> Just (TyCon noSpan "String") -- the only infix op is ++ : String -> String -> String
  e@(EApp _ f _) -> case synthLabelType env (collectAppHead f) of
    Just t ->
      let (params, ret) = splitArrow t
          appliedArgs = countAppArgs e
       in -- Only the /saturated/ shape is honest here: an under-applied
          -- call returns a residual function type ('a -> b' rather than
          -- 'b'), and the simple @snd . splitArrow@ shortcut would
          -- silently misrepresent it as the final result type. Return
          -- 'Nothing' for partial applications so the caller falls
          -- through to the no-info path instead of coercing against a
          -- wrong shape — same conservative answer we already give for
          -- 'ELam' / 'EDo'.
          if appliedArgs == length params
            then Just ret
            else Nothing
    Nothing -> Nothing
  ECon _ name -> case M.lookup name (leConInfo env) of
    Just ci | ciArity ci == 0 -> Just (TyCon noSpan (ciTypeName ci))
    _ -> Nothing -- non-nullary constructor types are polymorphic in field types
  ECase {} -> Nothing
  -- Closed lambdas synthesise an arrow type using fresh, span-unique
  -- tyvar names for parameters — same suffix scheme as
  -- 'Awsum.Typing'\''s synthesis-form 'typeOfExpr ELam' so a
  -- bare 'let id = \\x -> x in body' has a coherent binder type at
  -- lowering time without forcing the user to write 'let id : a -> a'.
  -- Returns 'Nothing' only when the body itself cannot be synthesised
  -- — that case still falls back to the '_letBind' placeholder in
  -- 'lowerLet'.
  ELam sp params body ->
    let suffix = "$" <> show (spanStartLine sp) <> "_" <> show (spanStartCol sp)
        paramTys = [TyVar pSp (n <> suffix) | Param pSp n <- params]
        paramEntries =
          [(QName [] (paramName p), pTy) | (p, pTy) <- zip params paramTys]
        env' = extendLowerEnv env paramEntries
     in foldr (TyArrow noSpan) <$> synthLabelType env' body <*> pure paramTys
  EDo {} -> Nothing -- 'do' blocks similarly need an expected type
  ELet _ pat mAnnot e body ->
    -- Prefer the user-supplied ascription as the binder's type
    -- (only valid for 'PVar' patterns — non-'PVar' lets are
    -- rewritten to 'ECase' before this path is reached, so a
    -- 'Just' ascription here implies a 'PVar' LHS). Without an
    -- ascription, fall back to best-effort 'synthLabelType' on
    -- @e@. Either way extend the env for nested label lookups in
    -- @body@; if neither path pins the type down, use a tyvar
    -- placeholder so the recursion still terminates and the caller
    -- treats 'Nothing' as "no info" anyway.
    let nTy = case mAnnot of
          Just t -> t
          Nothing -> fromMaybe (TyVar noSpan "_letBind") (synthLabelType env e)
        names = case pat of
          PVar _ n -> [n]
          PWild _ -> []
          _ -> [] -- shouldn't reach here; rewritten to ECase
        env' = extendLowerEnv env [(QName [] n, nTy) | n <- names]
     in synthLabelType env' body
  where
    countAppArgs :: Expr -> Int
    countAppArgs = go (0 :: Int)
      where
        go acc (EApp _ inner _) = go (acc + 1) inner
        go acc (EParens _ inner) = go acc inner
        go acc _ = acc

-- | Strip nested 'EApp' to expose the head expression (the function
--   reference). Used by 'synthLabelType' when synthesising the type of
--   an applied call.
collectAppHead :: Expr -> Expr
collectAppHead = \case
  EApp _ f _ -> collectAppHead f
  e -> e

-- | Lower a single case alternative: look up the constructor tag,
--   desugar nested patterns into nested CCase, and lower the body.
--
--   * @mScrutTy@ is the synthesised type of the scrutinee, when known.
--     When the constructor's owning type matches, it lets us
--     compute per-field types after substituting the type-parameters,
--     which then feed into 'extendLowerEnv' so binders referenced in
--     the arm body (e.g. nested @case e of …@ on a row-typed @e@)
--     resolve their types correctly. Without this, lowering would
--     not know the type of @e@ in @Left e -> case e of …@.
--   * @expected@ is the expected type of the whole case expression
--     and is propagated to each arm body so integer literals inside
--     arms get their @IntType@.
lowerAltM :: LowerEnv -> Locals -> Maybe Type' -> Maybe Type' -> CaseAlt -> LowerM (Int, [Name], CExpr)
lowerAltM env locals mScrutTy expected (CaseAlt _ (PCon _ cName pats) body _) = do
  ci <- liftEither $ maybeToRight (TELowering ("unknown constructor in pattern: " <> cName)) (M.lookup cName (leConInfo env))
  let tag = ciTag ci
      patBinders = collectPatternBindings (leConInfo env) ci mScrutTy pats
      env' = extendLowerEnv env [(QName [] n, t) | (n, t) <- patBinders]
      locals' = Set.union (Set.fromList (map fst patBinders)) locals
      -- Per-field substituted types — feed into 'desugarPatsM' so a
      -- 'PAscribe' targeting a row-typed field emits the right
      -- 'CRowCase' wrapper instead of being silently stripped.
      subst = case mScrutTy of
        Just outerTy ->
          let genericRet = applyTyParams (ciTypeName ci) (ciTypeParams ci)
           in fromRight mempty (unify genericRet outerTy)
        Nothing -> mempty
      fieldTys = map (Just . applySubst subst) (ciFieldTypes ci)
  body' <- lowerExprM env' locals' expected body
  (topVars, wrappedBody) <- desugarPatsM (leConInfo env) "__" 0 (zip pats fieldTys) body'
  pure (tag, topVars, wrappedBody)
lowerAltM _ _ _ _ CaseAlt {} =
  liftEither $ Left (TELowering "only constructor patterns are supported in case")

-- | Walk a pattern list under a known constructor and return
--   @[(binder, type)]@ entries for each 'PVar' binder reached. The
--   substitution of the constructor's type parameters is taken from
--   unifying the constructor's generic return type against the
--   scrutinee's type (when known); otherwise binders default to the
--   raw field types from the @type@ declaration.
collectPatternBindings :: ConInfoEnv -> ConInfo -> Maybe Type' -> [Pattern] -> [(Name, Type')]
collectPatternBindings conInfo ci mScrutTy pats =
  let subst = case mScrutTy of
        Just outerTy ->
          let genericRet = applyTyParams (ciTypeName ci) (ciTypeParams ci)
           in fromRight mempty (unify genericRet outerTy)
        Nothing -> mempty
      fieldTys = map (applySubst subst) (ciFieldTypes ci)
   in concatMap (uncurry (gather conInfo)) (zip pats fieldTys)
  where
    gather _ (PVar _ n) ty = [(n, ty)]
    gather _ (PWild _) _ = []
    -- 'PAscribe' overrides the field's type with the ascribed one for
    -- the inner binder — mirrors 'Awsum.Typing.patternBindings'. This
    -- makes @b@ in @Just (b : Bool)@ resolvable as 'Bool' at lowering
    -- time, so a nested @case b of …@ goes through the nominal
    -- 'CCase' path, not 'CRowCase'.
    gather conInfo' (PAscribe _ inner ascrTy) _ty = gather conInfo' inner ascrTy
    gather conInfo' (PCon _ innerCon innerPats) ty =
      case M.lookup innerCon conInfo' of
        Just innerCi ->
          let innerSubst =
                fromRight mempty
                  $ unify (applyTyParams (ciTypeName innerCi) (ciTypeParams innerCi)) ty
              innerFieldTys = map (applySubst innerSubst) (ciFieldTypes innerCi)
           in concatMap (uncurry (gather conInfo')) (zip innerPats innerFieldTys)
        Nothing -> []

-- | Lower the arms of a row-case scrutinee into a list of
--   @(rowTag, binder, body)@ tuples (the shape consumed by
--   'CRowCase'). A row case may combine 'PAscribe' arms (one per row
--   label) and 'PCon' arms (whose owning type matches one of the
--   row's nominal labels). Constructor arms targeting the same row
--   label are merged into a single CRow arm whose body is a 'CCase'
--   over the constructors of that label — mirroring how 'mergeAlts'
--   handles repeated outer constructors in nominal-case lowering.
buildRowAltsM :: LowerEnv -> Locals -> Maybe Type' -> Type' -> [CaseAlt] -> LowerM [(Word32, Name, CExpr)]
buildRowAltsM env locals expected scrutTy alts = do
  rawArms <- traverse (lowerRowArmM env locals expected scrutTy) alts
  let grouped =
        groupBy
          (\(t1, _, _) (t2, _, _) -> t1 == t2)
          (sortWith fstOf3 rawArms)
  traverse buildOne grouped
  where
    fstOf3 (a, _, _) = a

    -- Within one tag-equal group, the legitimate cases are: a single
    -- 'AscribeShape', or one-or-more 'ConShape's that all targeted
    -- the same row label. Anything else means two structurally
    -- distinct labels canonicalised to the same FNV-1a tag — caught
    -- here as 'RowTagCollision' rather than the global
    -- 'checkRowTagCollisions' post-pass, because lowering would
    -- otherwise bail out with a less helpful 'TELowering' before
    -- the post-pass gets to run.
    buildOne :: [(Word32, Type', RowArmShape)] -> LowerM (Word32, Name, CExpr)
    buildOne [] = liftEither $ Left (TELowering "buildRowAlts: empty group (unreachable)")
    buildOne grouped =
      case findCollidingLabels grouped of
        Just (l1, l2, tag) ->
          liftEither
            $ Left (RowTagCollision l1 l2 tag (tyConDeclSpan (leTypeDeclSpans env) l2))
        Nothing -> case grouped of
          [(tag, _, AscribeShape var body)] -> pure (tag, var, body)
          ((tag, _, ConShape {}) : _) -> do
            let conAlts = [(t, vs, b) | (_, _, ConShape t vs b) <- grouped]
            merged <- liftEither (mergeAlts conAlts)
            let var :: Name
                var = "__rw"
            pure (tag, var, CCase (CVar var) merged)
          ((_, _, AscribeShape _ _) : _ : _) ->
            -- Same canonical label appearing twice as a PAscribe arm:
            -- the typechecker's 'DuplicateRowArm' check should have
            -- ruled this out before lowering, so reaching here is a
            -- compiler-internal pipeline error.
            liftEither
              $ Left
                ( TELowering
                    "row case has duplicate PAscribe arms for the same label (typechecker should have rejected this as DuplicateRowArm)"
                )

    -- Look at the labels of a tag-equal group: if two of them have
    -- different canonical forms, the FNV-1a hash collided across
    -- distinct labels — return the first such pair plus the shared
    -- tag. All labels equal under 'canonicalLabel' is the legitimate
    -- "multiple PCon arms for the same row label" case.
    findCollidingLabels :: [(Word32, Type', RowArmShape)] -> Maybe (Type', Type', Word32)
    findCollidingLabels [] = Nothing
    findCollidingLabels ((tag, l0, _) : rest) =
      case find (\(_, l, _) -> canonicalLabel l /= canonicalLabel l0) rest of
        Just (_, l1, _) -> Just (l0, l1, tag)
        Nothing -> Nothing

-- | Per-arm intermediate value used by 'buildRowAlts'. 'AscribeShape'
--   carries the binder name and lowered body for a @(x : T) -> body@
--   arm; 'ConShape' carries the constructor's tag, the de-sugared
--   top-level variable list, and the lowered body wrapped in any
--   nested CCase that 'desugarPats' produced for inner patterns.
data RowArmShape
  = AscribeShape Name CExpr
  | ConShape Int [Name] CExpr

-- | Lower a single user-written row-case arm, returning its row tag
--   and an intermediate shape. PAscribe arms produce 'AscribeShape';
--   PCon arms find the row label whose head 'TyCon' matches the
--   constructor's owning type, substitute the row label into the
--   constructor's generic field types, extend the lowering env with
--   the resulting pattern bindings, and produce 'ConShape'.
lowerRowArmM :: LowerEnv -> Locals -> Maybe Type' -> Type' -> CaseAlt -> LowerM (Word32, Type', RowArmShape)
lowerRowArmM env locals expected _scrutTy (CaseAlt _ (PAscribe _ inner ascrTy) body _) = do
  let var = case inner of
        PVar _ n -> n
        _ -> "__rw"
      env' = extendLowerEnv env [(QName [] var, ascrTy)]
      locals' = Set.insert var locals
  body' <- lowerExprM env' locals' expected body
  tag <- recordRowTag ascrTy
  pure (tag, ascrTy, AscribeShape var body')
lowerRowArmM env locals expected scrutTy (CaseAlt _ (PCon _ cName innerPats) body _) = do
  ci <-
    liftEither
      $ maybeToRight
        (TELowering ("unknown constructor in row pattern: " <> cName))
        (M.lookup cName (leConInfo env))
  let cTyName = ciTypeName ci
      labels = flattenRow scrutTy
      mLabel = find (\l -> tyConHead l == Just cTyName) labels
  rowLabel <-
    liftEither
      $ maybeToRight
        ( TELowering
            ( "row label for constructor '"
                <> cName
                <> "' not in scrutinee row (typechecker should have rejected this)"
            )
        )
        mLabel
  let bindings = collectPatternBindings (leConInfo env) ci (Just rowLabel) innerPats
      env' = extendLowerEnv env [(QName [] n, t) | (n, t) <- bindings]
      locals' = Set.union (Set.fromList (map fst bindings)) locals
  body' <- lowerExprM env' locals' expected body
  (topVars, wrappedBody) <- lowerRowConInnerPatsM innerPats body'
  tag <- recordRowTag rowLabel
  pure (tag, rowLabel, ConShape (ciTag ci) topVars wrappedBody)
lowerRowArmM _ _ _ _ CaseAlt {} =
  liftEither $ Left (TELowering "row case arms must be (x : T) or constructor patterns")

-- | Translate the inner-pattern list of a 'PCon' arm in a row case.
--   For each pattern position, return the top-level binder name
--   (consumed by 'CCase' arm) and a wrapper that injects any
--   ascription-driven 'CRowCase' destructuring around the body. The
--   wrappers compose left-to-right by 'foldr'.
--
--   Monadic so that the tags minted for ascription-pattern row-cases
--   feed into the row-tag table consulted by the post-lowering
--   /row tag collision check/ (see 'recordRowTag').
lowerRowConInnerPatsM :: [Pattern] -> CExpr -> LowerM ([Name], CExpr)
lowerRowConInnerPatsM pats body0 = do
  entries <- zipWithM perPat [0 :: Int ..] pats
  let topVars = map fst entries
      wrapped = foldr (\(_, w) acc -> w acc) body0 entries
  pure (topVars, wrapped)
  where
    perPat _ (PVar _ n) = pure (n, id)
    perPat idx (PWild _) = pure ("__pw" <> show idx, id)
    perPat idx (PAscribe _ inner ascrTy) = do
      let topVar = "__pa" <> show idx
          innerName = case inner of
            PVar _ n -> n
            _ -> "__rw"
      tag <- recordRowTag ascrTy
      pure
        ( topVar,
          \b -> CRowCase (CVar topVar) [(tag, innerName, b)]
        )
    perPat idx _ = pure ("__pother" <> show idx, id) -- typechecker rules out other shapes

-- | Extract the head 'TyCon' name from a type, peeling 'TyApp' chains.
--   Returns 'Nothing' for 'TyVar', 'TyArrow', 'TyOr'.
tyConHead :: Type' -> Maybe Name
tyConHead (TyCon _ n) = Just n
tyConHead (TyApp _ f _) = tyConHead f
tyConHead _ = Nothing

-- | Merge case alternatives that have the same outer tag.
--   When multiple alts match the same constructor with nested patterns,
--   merge their inner case expressions into a single nested case.
--   Example: @Ok (Ok x) -> ...@ and @Ok (Err x) -> ...@ both have tag 0 for Ok,
--   so we merge them into a single alt with a nested case on the inner Result.
mergeAlts :: [(Int, [Name], CExpr)] -> Either TypeError [(Int, [Name], CExpr)]
mergeAlts alts =
  let grouped = groupBy (\(t1, _, _) (t2, _, _) -> t1 == t2) (sortOn (\(t, _, _) -> t) alts)
   in traverse mergeGroup grouped >>= Right . concat
  where
    mergeGroup :: [(Int, [Name], CExpr)] -> Either TypeError [(Int, [Name], CExpr)]
    mergeGroup [] = Right []
    mergeGroup [alt] = Right [alt]
    mergeGroup ((tag, vars, body) : rest) = do
      -- Check if all alts in this group have the same structure
      -- (same number of vars, all bodies are CCase or CRowCase on
      -- the first var). The 'CRowCase' branch covers row-case arms
      -- whose outer constructor is the same and whose ascription-
      -- driven inner 'CRowCase' wrappers (introduced by
      -- 'lowerRowConInnerPats') need to be unioned into a single
      -- multi-arm 'CRowCase'.
      case (body, map (\(_, vs, b) -> (vs, b)) rest) of
        (CCase (CVar scrutVar) innerAlts, otherBodies) -> do
          allInnerAlts <- foldM collectInnerAlts innerAlts otherBodies
          mergedInnerAlts <- mergeAlts allInnerAlts
          Right [(tag, vars, CCase (CVar scrutVar) mergedInnerAlts)]
        (CRowCase (CVar scrutVar) innerAlts, otherBodies) -> do
          allInnerAlts <- foldM collectInnerRowAlts innerAlts otherBodies
          Right [(tag, vars, CRowCase (CVar scrutVar) allInnerAlts)]
        _ ->
          Left (TELowering $ "conflicting pattern shapes for constructor tag " <> show tag)

    collectInnerAlts :: [(Int, [Name], CExpr)] -> ([Name], CExpr) -> Either TypeError [(Int, [Name], CExpr)]
    collectInnerAlts acc (_vars, CCase (CVar _scrutVar) innerAlts) =
      Right (acc <> innerAlts)
    collectInnerAlts _ _ =
      Left (TELowering "conflicting pattern shapes in merge")

    collectInnerRowAlts ::
      [(Word32, Name, CExpr)] ->
      ([Name], CExpr) ->
      Either TypeError [(Word32, Name, CExpr)]
    collectInnerRowAlts acc (_vars, CRowCase (CVar _scrutVar) innerAlts) =
      Right (acc <> innerAlts)
    collectInnerRowAlts _ _ =
      Left (TELowering "conflicting row-case shapes in merge")

-- | Desugar a list of sub-patterns into flat variable bindings,
--   wrapping the body with the right Core dispatchers:
--
--   * @PVar n@ binds the field directly under that name (no wrap).
--   * @PWild@ binds a deterministic placeholder (@__w<idx>@).
--   * @PCon@ wraps the body in a nested @CCase@ over the field, with
--     the inner constructor's pattern recursively desugared.
--   * @PAscribe inner T@ wraps the body in a @CRowCase@ keyed by
--     @rowTag T@ — needed when the field's type is a structural sum
--     and the arm matches one of its labels. The /generated/ outer
--     binder name is deterministic (@__pa<idx>@), so two @Just (… : T1)@
--     and @Just (… : T2)@ arms on the same outer constructor share a
--     binder and 'mergeAlts' can merge their @CRowCase@ bodies into a
--     single multi-label dispatch instead of bailing with
--     "conflicting pattern shapes in merge". Without this, lowering a
--     non-row-headed scrutinee whose constructor field happens to be
--     row-typed would lose the row-tag lookup the typechecker just
--     validated.
--
--   Each pattern position carries its substituted field type
--   (@'Maybe' Type'@) so nested 'PCon' inside 'PAscribe' (or vice
--   versa) can compute the right inner field types for the next
--   recursion level.
--
--   Monadic so the row-tag table seen by the post-lowering /row tag
--   collision check/ records every tag this lowerer mints.
desugarPatsM ::
  ConInfoEnv -> Text -> Int -> [(Pattern, Maybe Type')] -> CExpr -> LowerM ([Name], CExpr)
desugarPatsM _ _ _ [] body = pure ([], body)
desugarPatsM conInfo prefix idx ((p, mFieldTy) : ps) body = do
  (restVars, restBody) <- desugarPatsM conInfo prefix (idx + 1) ps body
  case p of
    PVar _ n -> pure (n : restVars, restBody)
    PWild _ ->
      let fresh = prefix <> "w" <> show idx
       in pure (fresh : restVars, restBody)
    PCon _ innerCon innerPats -> do
      let fresh = prefix <> "p" <> show idx
          innerTag = maybe 0 ciTag (M.lookup innerCon conInfo)
          innerPrefix = fresh <> "_"
          innerFieldTys = innerFieldTypes conInfo innerCon mFieldTy (length innerPats)
      (innerVars, innerBody) <-
        desugarPatsM conInfo innerPrefix 0 (zip innerPats innerFieldTys) restBody
      pure (fresh : restVars, CCase (CVar fresh) [(innerTag, innerVars, innerBody)])
    PAscribe _ inner ascrTy -> do
      let topVar = prefix <> "pa" <> show idx
      tag <- recordRowTag ascrTy
      (innerName, innerBody) <- ascribeInner conInfo prefix idx inner restBody
      pure (topVar : restVars, CRowCase (CVar topVar) [(tag, innerName, innerBody)])

-- | Lower the inner pattern of a 'PAscribe'. For the common shapes
--   ('PVar', 'PWild') this is just a name; for nested patterns
--   ('PCon' or another 'PAscribe') we delegate to 'desugarPatsM' to
--   build the right wrapping around the body.
ascribeInner ::
  ConInfoEnv -> Text -> Int -> Pattern -> CExpr -> LowerM (Name, CExpr)
ascribeInner _ _ _ (PVar _ n) body = pure (n, body)
ascribeInner _ prefix idx (PWild _) body = pure (prefix <> "paw" <> show idx, body)
ascribeInner conInfo prefix idx other body = do
  let innerPrefix = prefix <> "pa" <> show idx <> "_"
  (vars, wrappedBody) <- desugarPatsM conInfo innerPrefix 0 [(other, Nothing)] body
  case vars of
    [v] -> pure (v, wrappedBody)
    _ -> liftEither $ Left (TELowering "ascribeInner: nested pattern produced unexpected binders")

-- | Substituted field types of an inner constructor application,
--   given the outer field's known type. Falls back to 'Nothing's when
--   the outer field type is unknown or doesn't unify with the inner
--   constructor's owning type — the recursion still runs, just
--   without per-field type info that 'PAscribe' would have needed.
innerFieldTypes :: ConInfoEnv -> Name -> Maybe Type' -> Int -> [Maybe Type']
innerFieldTypes conInfo innerCon mFieldTy arity =
  case M.lookup innerCon conInfo of
    Just innerCi ->
      let innerSubst = case mFieldTy of
            Just fieldTy ->
              fromRight mempty
                $ unify (applyTyParams (ciTypeName innerCi) (ciTypeParams innerCi)) fieldTy
            Nothing -> mempty
       in map (Just . applySubst innerSubst) (ciFieldTypes innerCi)
    Nothing -> replicate arity Nothing

-- | Collect a chain of applications into (head, args) in left-to-right order.
--   Example:
--     collectApps (f a b) []  ==>  (f, [a,b])
collectApps :: Expr -> [Expr] -> (Expr, [Expr])
collectApps f acc = case f of
  EApp _sp f' x' -> collectApps f' (x' : acc)
  _ -> (f, acc)

-- | Lower a (possibly qualified) variable to either a Core variable or
--   a 'CBuiltIn' reference.
--
--   Supported:
--     • An unqualified name registered in 'Awsum.BuiltIn.builtIns'
--       → 'CBuiltIn' keyed by the unqualified name (the user reaches
--       it through the prelude's @BuiltIn.foo@ alias, e.g.
--       @showInt32 = BuiltIn.showInt32@).
--     • A qualified name registered in the current program type's
--       'platformTable' (e.g. @IO.Stdout.print@ for @--program-type cli@)
--       → 'CBuiltIn' keyed by the /dotted/ qualified name, so backends
--       can dispatch per effect without collision with prelude built-ins.
--     • Other unqualified names → Core variables.
--
--   Everything else: fail fast with a helpful message. By this point
--   the typechecker has already rejected unknown qualified names via
--   'builtinEnvFromImports', so reaching the error branch is a
--   lowering bug rather than a user error.
lowerVar :: LowerEnv -> QName -> Either TypeError CExpr
lowerVar env q@(QName mods n) =
  case mods of
    [] | Just _ <- lookupBuiltIn n -> Right (CBuiltIn n)
    [] -> Right (CVar n)
    _
      | M.member q (platformTable env.leProgramType) ->
          Right (CBuiltIn (prettyQName mods n))
    _ ->
      Left
        $ TELowering
        $ "unsupported qualified name: "
        <> prettyQName mods n
  where
    prettyQName ms name = T.intercalate "." (ms <> [name])
