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
module Awsum.ElaborateLower (SimplifyMode (..), elaborateLowerProgram, elaborateLowerProgramWith) where

import Awsum.BuiltIn (builtIns, lookupBuiltIn)
import Awsum.Core
import Awsum.Cps (alphaRename, cpsProgram)
import Awsum.Defunctionalize (defunctionalizeProgram)
import Awsum.Desugar (desugarProgram)
import Awsum.Desugar qualified as Desugar
import Awsum.HM (applySubst, canonicalLabel, flattenRow, rowRetagNeeded, rowTag, singletonSubst, unify)
import Awsum.Lifetime (insertDrops)
import Awsum.LowerClosures (lowerClosuresProgram)
import Awsum.MonomorphizeRows (monomorphizeRows)
import Awsum.Prelude (preludeDefNames)
import Awsum.Program (ProgramType, platformTable)
import Awsum.Reuse (insertReuse)
import Awsum.Scc (sccMergeProgram)
import Awsum.Simplify (simplifyProgram)
import Awsum.StackSafety (verifyStackSafety)
import Awsum.StackSafety qualified as StackSafety
import Awsum.Syntax
import Awsum.TExpr (TAlt (..), TDecl (..), TExpr (..), TParam (..), TPattern (..), TRowAlt (..), TypedProgram (..), texprType, tparamType)
import Awsum.Tco (tcoProgram)
import Awsum.Typing (TypeError (..), Warning, emptyTypeNamesInProgram, extractTyCon, markEmptyTypesInDecl, splitArrow, typecheckProgram)
import Awsum.UniquifyLocals (uniquifyLocals)
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

-- | Look up the constructor tags codegen runtime helpers need (see
--   'PreludeTags' in 'Awsum.Core'). The names are all in the bundled
--   prelude, so a missing one means the prelude was edited
--   inconsistently; we fail loudly rather than substitute a default.
preludeTagsFromConInfo :: ConInfoEnv -> PreludeTags
preludeTagsFromConInfo conInfo =
  let tag :: Name -> Int
      tag n = case M.lookup n conInfo of
        Just ci -> ciTag ci
        Nothing ->
          error
            $ "preludeTagsFromConInfo: prelude is missing constructor '"
            <> n
            <> "' — runtime helpers depend on it; check stdlib/Prelude.aww."
   in PreludeTags
        { ptLeft = tag "Left",
          ptRight = tag "Right",
          ptJust = tag "Just",
          ptNothing = tag "Nothing",
          ptTrue = tag "True",
          ptFalse = tag "False",
          ptUnit = tag "Unit",
          ptTuple2 = tag "Tuple2",
          ptNil = tag "Nil",
          ptCons = tag "Cons",
          ptUnderflowError = tag "UnderflowError",
          ptOverflowError = tag "OverflowError",
          ptParseError = tag "ParseError",
          ptStringTooLong = tag "StringTooLong",
          ptUnpairedUtf16Surrogate = tag "UnpairedUtf16Surrogate",
          ptInvalidUtf8 = tag "InvalidUtf8"
        }

-- | Build constructor info from @type@ declarations. Each constructor
--   gets a globally unique tag (monotonic counter across every
--   @type@ declaration in the program), its arity, the owning type's
--   name, the declared type-parameter names of that type, and its
--   field types.
--
--   /Why globally unique?/ 'pruneDeadArms' uses the set of
--   reachable 'CCon' tags to decide which 'CCase' arms can be
--   dropped. If two unrelated types share a tag value (e.g. tag 3
--   meaning both 'IOGetArgs' in 'IO' and \"member 4\" in an
--   'Awsum.Scc'-merged sum type), constructing the value of one type
--   forces both arms to look reachable. Synthetic-tag-minting passes
--   ('Awsum.Scc', 'Awsum.LowerClosures', 'Awsum.Cps') honour the
--   same global namespace by allocating from 'nextFreshConTag'.
buildConInfo :: [Decl] -> ConInfoEnv
buildConInfo ds =
  M.fromList
    [ (cName, ConInfo tag (length cFields) tName [n | Param _ n <- ps] cFields)
    | (tag, (tName, ps, ConDef _ cName cFields)) <-
        zip
          [0 ..]
          [ (tName, ps, c)
          | TypeDecl _sp tName ps cs _ _ _ <- ds,
            c <- cs
          ]
    ]

-- | Synthetic name for a constructor wrapper function.
--   Uses @$con$@ prefix which cannot collide with user-defined names.
conWrapperName :: Name -> Name
conWrapperName name = "$con$" <> name

-- | Synthetic name for a built-in eta-wrapper function.
--   Uses @$bi$@ prefix which cannot collide with user-defined names.
--   Generated by 'etaExpandBuiltInValues' when a built-in is referenced
--   in value position; the wrapper's body is a saturated call to the
--   underlying 'CBuiltIn' in proper callee position, restoring the
--   pipeline invariant that 'CBuiltIn' only appears as a 'CCall' callee.
builtInEtaWrapperName :: Name -> Name
builtInEtaWrapperName name = "$bi$" <> name

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

-- | Mint a fresh binder name '$let_w_N' for a wildcard-LHS @let _ = e
--   in body@ that 'lowerLet' needs to give a name. Same shared counter
--   as the other mint helpers — the binder appears in Core IR and so
--   the codegen artefact, which is why it cannot encode a 'SrcSpan'
--   (see the topic doc in the private workspace).
freshLetWildName :: LowerM Name
freshLetWildName = do
  s <- get
  put s {lsFresh = lsFresh s + 1}
  pure ("$let_w_" <> show (lsFresh s))

-- | Mint a fresh binder name '$m$N' for reconciling the field binders of
--   case arms being merged. When same-tag arms bind a field to different
--   source names, the union keeps one canonical list — these globally
--   unique names — and alpha-renames each arm's body onto it. A fresh
--   target can neither chain (every name distinct) nor be captured (it
--   appears in no other binder), so the rename is unconditionally safe.
freshMergeName :: LowerM Name
freshMergeName = do
  s <- get
  put s {lsFresh = lsFresh s + 1}
  pure ("$m$" <> show (lsFresh s))

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

-- | Replace every bare 'CBuiltIn' in /value position/ with a reference to
--   a synthesised eta-wrapper, returning the rewritten expression plus the
--   set of built-in names that need wrappers generated.
--
--   The pipeline invariant ('Awsum.LowerClosures' header) is that
--   'CBuiltIn' may only appear as the callee of a 'CCall'. When a user
--   writes @bindIO io IO.Stdout.print@ or @apply showInt32 42@, the
--   surrounding 'EApp' doesn't wrap the built-in reference (it's used as a
--   value), so a bare 'CBuiltIn' would otherwise flow into a fn-typed
--   slot — Defunctionalize/LowerClosures don't encode it as a closure,
--   and the runtime '$applyN' dispatcher crashes on the non-'CCon' value.
--   This walk rewrites every such occurrence to @CVar ('$bi$' <> name)@;
--   the generator 'genBuiltInEtaWrappers' then materialises the matching
--   'CFunDef' whose body is a saturated 'CCall (CBuiltIn name) [args]'.
etaExpandBuiltInValues :: CExpr -> (CExpr, Set Name)
etaExpandBuiltInValues = goValue
  where
    -- /Value position/: a 'CBuiltIn' must be eta-wrapped.
    goValue :: CExpr -> (CExpr, Set Name)
    goValue = \case
      CBuiltIn n -> (CVar (builtInEtaWrapperName n), Set.singleton n)
      CCall callee args ->
        let (callee', n1) = goCallee callee
            (args', n2) = unzipFold (map goValue args)
         in (CCall callee' args', n1 <> n2)
      CCon t fs ->
        let (fs', ns) = unzipFold (map goValue fs)
         in (CCon t fs', ns)
      CCase scrut alts ->
        let (scrut', n1) = goValue scrut
            (alts', n2) = unzipFold (map goAlt alts)
         in (CCase scrut' alts', n1 <> n2)
      CRow t v ->
        let (v', ns) = goValue v
         in (CRow t v', ns)
      CRowCase scrut alts ->
        let (scrut', n1) = goValue scrut
            (alts', n2) = unzipFold (map goRowAlt alts)
         in (CRowCase scrut' alts', n1 <> n2)
      CLoop b ->
        let (b', ns) = goValue b
         in (CLoop b', ns)
      CContinue args ->
        let (args', ns) = unzipFold (map goValue args)
         in (CContinue args', ns)
      CDrop n b ->
        let (b', ns) = goValue b
         in (CDrop n b', ns)
      CReuse rm n t fs ->
        let (fs', ns) = unzipFold (map goValue fs)
         in (CReuse rm n t fs', ns)
      CLet x rhs body ->
        let (rhs', n1) = goValue rhs
            (body', n2) = goValue body
         in (CLet x rhs' body', n1 <> n2)
      CProj n i -> (CProj n i, mempty)
      CJoin {} -> error "ElaborateLower: CJoin is minted by Awsum.Simplify, which runs later"
      CJump {} -> error "ElaborateLower: CJump is minted by Awsum.Simplify, which runs later"
      e@(CVar _) -> (e, mempty)
      e@(CString _) -> (e, mempty)
      e@(CIntLit _ _) -> (e, mempty)

    -- /Callee position/ of a 'CCall': bare 'CBuiltIn' is legal here, so
    -- direct built-in calls 'CCall (CBuiltIn name) [args]' stay untouched.
    -- Any other callee shape (e.g. a 'CCall' producing a function value)
    -- is itself in value position and recurses through 'goValue'.
    goCallee :: CExpr -> (CExpr, Set Name)
    goCallee = \case
      e@(CBuiltIn _) -> (e, mempty)
      e -> goValue e

    goAlt :: (Int, [Name], CExpr) -> ((Int, [Name], CExpr), Set Name)
    goAlt (tag, vs, body) =
      let (body', ns) = goValue body
       in ((tag, vs, body'), ns)

    goRowAlt :: (Word32, Name, CExpr) -> ((Word32, Name, CExpr), Set Name)
    goRowAlt (tag, n, body) =
      let (body', ns) = goValue body
       in ((tag, n, body'), ns)

    unzipFold :: (Monoid m) => [(a, m)] -> ([a], m)
    unzipFold xs = (map fst xs, foldMap snd xs)

-- | Lift 'etaExpandBuiltInValues' over a single top-level declaration.
etaExpandDeclBuiltInValues :: CDecl -> (CDecl, Set Name)
etaExpandDeclBuiltInValues = \case
  CValDef n e ->
    let (e', ns) = etaExpandBuiltInValues e
     in (CValDef n e', ns)
  CFunDef n ps body ->
    let (body', ns) = etaExpandBuiltInValues body
     in (CFunDef n ps body', ns)

-- | Generate eta-wrapper 'CFunDef's for the listed built-in names.
--   Looks up each name's arity from 'Awsum.BuiltIn.builtIns' (unqualified
--   prelude built-ins) or 'Awsum.Program.platformTable' (qualified platform
--   effects keyed by their dotted form). Names that don't resolve (or
--   resolve to non-arrow types) are silently skipped — by construction the
--   walker only adds names that originated from 'CBuiltIn' positions, so
--   any missing entry is a registry bug, not a user error.
genBuiltInEtaWrappers :: ProgramType -> Set Name -> [CDecl]
genBuiltInEtaWrappers progType names =
  let tymap = builtInTypeByName progType
   in [ CFunDef wname params (CCall (CBuiltIn name) (map CVar params))
      | name <- Set.toList names,
        Just ty <- [M.lookup name tymap],
        let arity = countArrows ty,
        arity > 0,
        let wname = builtInEtaWrapperName name,
        let params = ["$x" <> show i | i <- [0 .. arity - 1]]
      ]
  where
    builtInTypeByName :: ProgramType -> Map Name Type'
    builtInTypeByName pt =
      let preludeMap = builtIns
          platformMap = M.mapKeys prettyQName (platformTable pt)
       in M.union preludeMap platformMap

    prettyQName :: QName -> Name
    prettyQName (QName mods n) = T.intercalate "." (mods <> [n])

    countArrows :: Type' -> Int
    countArrows = \case
      TyArrow _ _ rest -> 1 + countArrows rest
      _ -> 0

-- | Run a 'LowerM' computation, returning its result and the
--   accumulated lifted helpers (in source order — they're appended
--   to the user-decl list in the program pipeline).
runLowerM :: LowerM a -> Either TypeError (a, [CDecl], M.Map Word32 (M.Map Text Type'))
runLowerM m = do
  (a, st) <- runStateT m (LowerState 0 [] M.empty M.empty)
  pure (a, reverse (lsHelpers st), lsRowTags st)

-- | Whether the pipeline runs 'Awsum.Simplify'. 'SimplifyOff' is a
--   test-only instrument: the compiler's differential gates compile a
--   program both ways and assert identical runtime stdout, pinning
--   @runtime(simplify(core)) == runtime(core)@ with the runtime itself
--   as the oracle — and keeping every codegen exercised on raw,
--   unsimplified Core shapes. No public entry point exposes it: the CLI
--   and the LSP server go through 'elaborateLowerProgram', which is
--   always 'SimplifyOn'.
data SimplifyMode = SimplifyOn | SimplifyOff
  deriving stock (Show, Eq)

-- | Check the surface program (types) and lower it to Core IR.
--   On success we return @(warnings, core)@: the Core program for codegen
--   plus any non-fatal warnings the typechecker collected.
elaborateLowerProgram :: ProgramType -> Program -> Either TypeError ([Warning], PreludeTags, CoreProgram)
elaborateLowerProgram = elaborateLowerProgramWith SimplifyOn

-- | 'elaborateLowerProgram' with the 'Awsum.Simplify' pass switchable —
--   the entry point of the test suites' and @awsum-bench@'s no-simplify
--   differential runs.
elaborateLowerProgramWith :: SimplifyMode -> ProgramType -> Program -> Either TypeError ([Warning], PreludeTags, CoreProgram)
elaborateLowerProgramWith simplifyMode progType progIn = do
  -- 0) Pre-typecheck desugar: rewrite 'do' blocks into nested
  --    'bindEither' calls with 'ELam' continuations. Lambdas
  --    themselves are kept as 'ELam' nodes — the typechecker handles
  --    them bidirectionally; lambda-lifting happens during lowering,
  --    where the type context is available.
  progDesugared <- first desugarErrorToTypeError (desugarProgram progIn)
  -- 0.5) Resolve every TyCon reference whose name was declared with
  --      the @empty type@ keyword into a 'TyEmpty', so the
  --      typechecker and the lowering pass see the row-identity
  --      flag uniformly. Without this, a built-in registered as
  --      @IO Never X@ (which already carries 'TyEmpty') would
  --      mismatch a user signature still spelled @IO Never X@ as
  --      'TyCon' downstream of unification.
  let emptyNames = emptyTypeNamesInProgram progDesugared
      prog =
        progDesugared
          { decls =
              fmap (markEmptyTypesInDecl emptyNames) (decls progDesugared)
          }
  -- 1) Elaboration: typecheck → typed AST ('TypedProgram'), then
  --    row-monomorphisation (specialises row-polymorphic combinators at
  --    their concrete instantiations so the construction-site row
  --    injection in their bodies fires with real tags).
  (typedProg, warnings) <- typecheckProgram progType preludeDefNames prog
  let monoProg = monomorphizeRows typedProg
  -- 2) Lowering: drop signatures, convert defs/exprs. Fail gracefully on unknown primitives.
  let ds = toList (decls prog)
      conInfo = buildConInfo ds
      sigMap = M.fromList [(n, t) | Sig _sp n t _ _ <- ds]
      -- Narrow each TypeDecl span to just the type's name (the
      -- formatter guarantees the leading 'type ' prefix is exactly
      -- five chars), so the row tag collision diagnostic underlines
      -- 'AFB4F' rather than the whole 'type AFB4F = MkAFB4F' line.
      -- Same heuristic 'Awsum.Typing.typeNameSubSpan' uses for
      -- 'DuplicateTypeDef' / 'UnnamedType' diagnostics.
      typeDeclSpans = M.fromList [(n, narrowToName sp n) | TypeDecl sp n _ _ _ _ _ <- ds]
      narrowToName sp n =
        let nameStartCol = spanStartCol sp + T.length "type "
         in SrcSpan
              (spanStartLine sp)
              nameStartCol
              (spanStartLine sp)
              (nameStartCol + T.length n)
      env = mkLowerEnv progType conInfo sigMap typeDeclSpans
  (mds, liftedHelpers, rowTags) <- runLowerM (traverse (lowerTDecl env) (tpDefs monoProg))
  -- Row tag collision check: reject programs in which two distinct
  -- structural-sum labels canonicalise to the same FNV-1a 32-bit hash.
  -- The hash space is 2^32 wide, so a collision in a hand-written
  -- program is vanishingly unlikely, but the check is a hard guard
  -- against adversarial label names where the runtime would otherwise
  -- silently confuse one alternative for another at row-case dispatch.
  checkRowTagCollisions typeDeclSpans rowTags
  -- 3) Lower platform-effect built-ins to constructors of the prelude's
  --    `IO` type. After this pass, `CCall (CBuiltIn "IO.Stdout.print")
  --    [arg]` no longer appears in Core; it is replaced by
  --    `CCon ioStdoutPrintTag [arg, IOPure Unit]`. The actual print
  --    happens later, when the per-target runtime-loop (`__runIO`,
  --    emitted by codegen) walks the IO tree returned from `main`.
  --    Done before tree-shake so that the IO type's constructors enter
  --    reachability analysis as ordinary `CCon` references.
  let userDecls = catMaybes mds
      allWrappers = genConWrappers conInfo
      declsBeforeBI = userDecls <> liftedHelpers <> allWrappers <> [ioGetArgsContDecl conInfo, ioStdinReadAllStringContDecl conInfo, ioStdinReadAllBytesContDecl conInfo]
      -- Eta-expand every bare 'CBuiltIn' that appears in value position
      -- (constructor field, call argument, case scrutinee, etc.) into a
      -- reference to a synthesised wrapper. Restores the pipeline invariant
      -- that 'CBuiltIn' only appears as a 'CCall' callee. Runs before
      -- 'lowerIOPlatformBuiltinsDecl' so the wrapper bodies — themselves
      -- saturated 'CCall (CBuiltIn name) [args]' — get rewritten in the
      -- same pass when 'name' is a platform built-in like @IO.Stdout.print@.
      (declsAfterEta, etaNeeded) =
        let pairs = map etaExpandDeclBuiltInValues declsBeforeBI
         in (map fst pairs, foldMap snd pairs)
      builtInWrappers = genBuiltInEtaWrappers progType etaNeeded
      allDeclsRaw = declsAfterEta <> builtInWrappers
      allDecls = map (lowerIOPlatformBuiltinsDecl conInfo) allDeclsRaw
  --    Then tree-shake: drop Core declarations unreachable from 'main'.
  --    Covers both user functions that no one calls and prelude
  --    helpers the user program does not touch (e.g.
  --    @showUnderflowError@ in a program that never uses @predInt32@).
  --    Constructor wrappers are generated after this reachability is
  --    known so they're only materialised for constructors still
  --    present in the surviving code.
  --
  --    Roots: 'main' (the user entry point) plus 'runIO' (the prelude
  --    runtime that walks the IO tree returned by `main`). 'runIO' is
  --    not called from `main` in Core — the codegen entry-point glue
  --    wires `v_runIO(v_main(input))` as a string template — so the
  --    call-graph analysis must treat it as a separate root or it
  --    would shake away.
  let callGraph = M.fromList [(declName' d, declFreeVars d) | d <- allDecls]
      reachable = reachableCore "main" callGraph <> reachableCore "runIO" callGraph
      live = filter (\d -> Set.member (declName' d) reachable) allDecls
      -- Uniquify local binders that collide with a top-level name. A
      -- prelude pattern variable (e.g. @cont@ in @bindIO@'s @IOGetArgs@
      -- arm) can share a name with a user top-level — legal cross-module
      -- shadowing — but every pass below that resolves a bare 'CVar'
      -- against the global declaration table ('Awsum.Defunctionalize',
      -- 'Awsum.LowerClosures', 'Awsum.Cps') would mistake the local for
      -- the top-level, drop its captures, and emit a dangling closure.
      -- Renaming the collisions away restores the invariant those passes
      -- assume before the first one runs.
      core = uniquifyLocals (CoreProgram live)
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
  core' <- treeShakeFromMain conInfo <$> defunctionalizeProgram core
  -- 5) Lower residual function values: every closure that survived
  --    Defunctionalize (because it flowed into a constructor field
  --    or through a non-statically-resolvable call site) is encoded
  --    as a tagged 'CCon' and routed through a per-arity '$applyN'
  --    dispatcher. Without this, Saturate's "no partial application
  --    with local captures" invariant would fail the moment a Core
  --    program stores a closure in a constructor field.
  let lowered = treeShakeFromMain conInfo (lowerClosuresProgram core')
  -- 6) Saturate under-applied direct calls via lambda-lifting.
  core'' <- saturateProgram lowered
  -- 7) SCC-merge for mutual recursion. Every strongly-connected
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
  --    Every constructor tag from here up — Scc argument packs, Cps
  --    continuation cells — names a cell that lives and dies inside the
  --    compiler-generated loop machinery, never stored into user data.
  --    'Awsum.Reuse' uses this floor as the 'ReuseUnique' evidence.
  let mintedTagFloor = nextFreshConTag core''
  let sccMerged = treeShakeFromMain conInfo (sccMergeProgram core'')
  -- 8) CPS + defunctionalization for non-tail self-recursion. For each
  --    function with a non-tail self-call, emit a (wrapper, '$cps$f',
  --    '$apply$f') trio; the continuation chain now lives as an ADT on
  --    the heap instead of as frames on the system stack, and '$cps$f'
  --    and '$apply$f' are both self-tail-recursive so the following TCO
  --    pass folds them into loops. See 'Awsum.Cps' and docs/recursion.md.
  let cpsed = cpsProgram sccMerged
  -- 9) Second SCC-merge pass. When the original body has two or more
  --    non-tail self-calls in one expression (e.g. tree-mirror's
  --    'Node (mirror r) v (mirror l)'), 'Awsum.Cps' allocates one K_i
  --    per call and an earlier K_i's apply arm tail-calls '$cps$f' to
  --    start the next call — so '$cps$f' and '$apply$f' end up mutually
  --    recursive. Re-running 'Awsum.Scc' fuses any such pair into one
  --    self-recursive '$scc$' function tagged by which of the two is
  --    active (different arities handled by sum-typed args, same as
  --    pass 7). Single-non-tail-call functions stay unchanged: the
  --    apply body does not reference '$cps$f', so there is no cycle
  --    and the second SCC sees only size-1 SCCs.
  let cpsedSccd = treeShakeFromMain conInfo (sccMergeProgram cpsed)
  -- 10) Stack-safety verifier. After SCC merge and CPS there must be
  --    no non-trivial call-graph cycle and no CFunDef with a non-tail
  --    self-call — both mean a recursion shape that would silently
  --    overflow the system stack at depth on some backend. Any
  --    remainder is a compile error (no escape hatch): the program is
  --    either user-level ill-formed (mutually recursive 'CValDef's,
  --    which have no fixed point) or a compiler bug.
  case verifyStackSafety cpsedSccd of
    [] -> pass
    (issue : _) -> Left (toTypeError sigMap issue)
  -- 11) Self-TCO: rewrite self-recursive tail calls into 'CContinue', and
  --    wrap affected function bodies in 'CLoop'. Backends compile the
  --    wrapped form into a loop + jump rather than a recursive call,
  --    guaranteeing stack safety for tail recursion across all targets.
  let tcoed = tcoProgram cpsedSccd
  -- 12) Drop insertion: annotate the IR with 'CDrop' nodes marking
  --    where each binder becomes dead. LLVM and WASM lower them to
  --    '__free_recursive'; JVM/CLR/JS treat them as transparent
  --    wrappers (managed GC handles slot collection). Runs last so the
  --    placement reflects the final IR shape — earlier passes
  --    (Defunctionalize, LowerClosures, Saturate, Scc, Cps, Tco)
  --    freely rewrite bodies and would otherwise have to preserve
  --    drops through every transformation.
  -- 13) Cell reuse: rewrites the canonical
  --    'CCase (CVar n) [..., (t, vs, CDrop n inner), ...]' +
  --    matching-arity 'CCon' inside 'inner' into 'CReuse'. Runs
  --    after 'insertDrops' so it can rely on the drop placement as
  --    a proxy for linear-use of the scrutinee.
  -- 11.5) Simplify (coexistence substrate; see docs/simplify.md): inline a
  --    single-use case-arm binder into a 'CProj' of the (variable) scrutinee,
  --    so the @const v = s[i]@ binding disappears and the field read happens
  --    inline at the use; collapse a case over a literal constructor / row
  --    injection (case-of-known-constructor) into the matching arm's body;
  --    fold an integer built-in over literal operands into the value its
  --    runtime helper would build (the 'PreludeTags' supply the constructor
  --    tags of those cells, exactly as they do for the codegen helpers).
  --    Runs after Tco and before Lifetime — never after Reuse (the memory
  --    passes are the last word over the final shape), and never earlier:
  --    the inline rule is sound only on the final Core shape (see
  --    "Awsum.Simplify"). Tree-shake re-runs: collapsing a case can discard
  --    a never-evaluated field holding the last call edge to a function.
  --    'SimplifyOff' (test-only differential mode) skips the pass and its
  --    re-shake — exactly the pipeline as it stood before Simplify landed.
  let preludeTags = preludeTagsFromConInfo conInfo
      simplified = case simplifyMode of
        SimplifyOn -> treeShakeFromMain conInfo (simplifyProgram preludeTags tcoed)
        SimplifyOff -> tcoed
  pure (warnings, preludeTags, insertReuse mintedTagFloor (insertDrops simplified))

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
      Just (TyEmpty sp _) -> Just sp
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

-- | Synthetic top-level helper used by every @IOGetArgs@ rewrite.
--   Pattern-matches the @Either (StringTooLong | UnpairedUtf16Surrogate)
--   String@ returned by @BuiltIn.internalGetArgs@ at runtime and
--   routes @Left@ to @IOFail@, @Right@ to @IOPure@. Always emitted
--   when @IO.Args.getArgs@ is in the program; tree-shake drops the
--   helper if no construction site references it (programs that
--   don't read argv).
ioGetArgsContDecl :: ConInfoEnv -> CDecl
ioGetArgsContDecl conInfo =
  let tagFor n = case M.lookup n conInfo of
        Just ci -> ciTag ci
        Nothing -> error $ "ioGetArgsContDecl: prelude missing '" <> n <> "'"
      leftTag = tagFor "Left"
      rightTag = tagFor "Right"
      ioFailTag = tagFor "IOFail"
      ioPureTag = tagFor "IOPure"
   in CFunDef
        "$io_getargs_cont"
        ["result"]
        ( CCase
            (CVar "result")
            [ (leftTag, ["e"], CCon ioFailTag [CVar "e"]),
              (rightTag, ["s"], CCon ioPureTag [CVar "s"])
            ]
        )

-- | Synthetic top-level helper used by every @IOStdinReadAllString@
--   rewrite. Same routing of @Left@ to @IOFail@ and @Right@ to @IOPure@
--   as @$io_getargs_cont@, over the stdin error row @Either
--   (StringTooLong | InvalidUtf8) String@. Kept as a distinct top-level
--   so the effects' continuations stay separately tree-shakeable: a
--   program that uses only @IO.Stdin.readAllString@ pays no Core-size
--   cost for @$io_getargs_cont@ and vice versa.
ioStdinReadAllStringContDecl :: ConInfoEnv -> CDecl
ioStdinReadAllStringContDecl conInfo =
  let tagFor n = case M.lookup n conInfo of
        Just ci -> ciTag ci
        Nothing -> error $ "ioStdinReadAllStringContDecl: prelude missing '" <> n <> "'"
      leftTag = tagFor "Left"
      rightTag = tagFor "Right"
      ioFailTag = tagFor "IOFail"
      ioPureTag = tagFor "IOPure"
   in CFunDef
        "$io_stdinReadAllString_cont"
        ["result"]
        ( CCase
            (CVar "result")
            [ (leftTag, ["e"], CCon ioFailTag [CVar "e"]),
              (rightTag, ["s"], CCon ioPureTag [CVar "s"])
            ]
        )

-- | Synthetic top-level helper used by every @IOStdinReadAllBytes@
--   rewrite. The raw-byte read cannot fail on content, so there is no
--   @Either@ to unpack — the continuation lifts the @List UInt8@
--   straight to @IOPure@. Separately tree-shakeable like the others.
ioStdinReadAllBytesContDecl :: ConInfoEnv -> CDecl
ioStdinReadAllBytesContDecl conInfo =
  let tagFor n = case M.lookup n conInfo of
        Just ci -> ciTag ci
        Nothing -> error $ "ioStdinReadAllBytesContDecl: prelude missing '" <> n <> "'"
      ioPureTag = tagFor "IOPure"
   in CFunDef
        "$io_stdinReadAllBytes_cont"
        ["bytes"]
        (CCon ioPureTag [CVar "bytes"])

-- | Rewrite every @CCall (CBuiltIn "IO.Stdout.print") [arg]@ into the
--   constructor expression @CCon ioStdoutPrintTag [arg, CCon ioPureTag
--   [CCon unitTag []]]@ (where the tags are looked up from
--   'ConInfoEnv' rather than hard-coded so the rewrite stays in
--   lockstep with the prelude's declaration order).
--
--   After this pass the platform built-in's call site is gone from
--   Core; in its place is a heap-allocated description that the
--   per-target runtime-loop (`__runIO`, emitted by codegen) walks at
--   runtime. This is what makes IO lazy: the construction of
--   `IO.Stdout.print "x"` no longer performs the print — it merely
--   builds an @IOStdoutPrint@ cell — so a value bound by `let _ = …`
--   that never reaches `__runIO` produces no output.
lowerIOPlatformBuiltinsDecl :: ConInfoEnv -> CDecl -> CDecl
lowerIOPlatformBuiltinsDecl conInfo = \case
  CFunDef n args body -> CFunDef n args (rewriteExpr body)
  CValDef n body -> CValDef n (rewriteExpr body)
  where
    tagFor :: Name -> Int
    tagFor n = case M.lookup n conInfo of
      Just ci -> ciTag ci
      Nothing ->
        error
          $ "lowerIOPlatformBuiltinsDecl: prelude is missing constructor '"
          <> n
          <> "' — IO type or Unit was edited inconsistently."

    ioPureTag = tagFor "IOPure"
    ioStdoutPrintTag = tagFor "IOStdoutPrint"
    ioGetArgsTag = tagFor "IOGetArgs"
    ioStdinReadAllStringTag = tagFor "IOStdinReadAllString"
    ioStdinReadAllBytesTag = tagFor "IOStdinReadAllBytes"
    unitTag = tagFor "Unit"

    -- The terminator for a single `IO.Stdout.print s` call: after the
    -- print, the chain returns Unit. Built once and shared at every
    -- rewrite site for tidier Core; backends emit the structure at
    -- each construction site regardless.
    pureUnit = CCon ioPureTag [CCon unitTag []]

    rewriteExpr :: CExpr -> CExpr
    rewriteExpr = \case
      CCall (CBuiltIn "IO.Stdout.print") [arg] ->
        CCon ioStdoutPrintTag [rewriteExpr arg, pureUnit]
      -- 'IO.Args.getArgs' is a zero-arg platform built-in returning
      -- 'IO (StringTooLong | UnpairedUtf16Surrogate) String'. Rewrite
      -- to an 'IOGetArgs' constructor whose continuation is the
      -- shared synthetic helper '$io_getargs_cont' (lifted to a
      -- top-level CFunDef in 'elaborateLowerProgram'); the helper
      -- routes 'Left e' to 'IOFail e' and 'Right s' to 'IOPure s',
      -- which is what makes the platform built-in's user-visible
      -- type 'IO err String' (errors-in-row) rather than 'IO Never
      -- (Either err String)'.
      CCall (CBuiltIn "IO.Args.getArgs") [] ->
        CCon ioGetArgsTag [CVar "$io_getargs_cont"]
      -- 'IO.Stdin.readAllString' mirrors 'IO.Args.getArgs' at the Core
      -- level: zero-arg platform built-in, 'Either err String' result,
      -- same routing of failure-vs-success through the synthetic helper.
      -- The byte source (fd 0 vs argv) and error row (InvalidUtf8 vs
      -- UnpairedUtf16Surrogate) differ at runtime / in the type.
      CCall (CBuiltIn "IO.Stdin.readAllString") [] ->
        CCon ioStdinReadAllStringTag [CVar "$io_stdinReadAllString_cont"]
      -- 'IO.Stdin.readAllBytes' returns the raw bytes as 'List UInt8'
      -- with no decode and no error row; its continuation lifts the
      -- bytes straight to 'IOPure' (see '$io_stdinReadAllBytes_cont').
      CCall (CBuiltIn "IO.Stdin.readAllBytes") [] ->
        CCon ioStdinReadAllBytesTag [CVar "$io_stdinReadAllBytes_cont"]
      CCall f args -> CCall (rewriteExpr f) (map rewriteExpr args)
      CCon t fields -> CCon t (map rewriteExpr fields)
      CCase scrut alts ->
        CCase
          (rewriteExpr scrut)
          [(t, vs, rewriteExpr e) | (t, vs, e) <- alts]
      CRow t v -> CRow t (rewriteExpr v)
      CRowCase scrut alts ->
        CRowCase
          (rewriteExpr scrut)
          [(t, v, rewriteExpr e) | (t, v, e) <- alts]
      CLoop body -> CLoop (rewriteExpr body)
      CContinue args -> CContinue (map rewriteExpr args)
      CDrop n body -> CDrop n (rewriteExpr body)
      CReuse rm n t fs -> CReuse rm n t (map rewriteExpr fs)
      CLet x rhs body -> CLet x (rewriteExpr rhs) (rewriteExpr body)
      CJoin {} -> error "ElaborateLower: CJoin is minted by Awsum.Simplify, which runs later"
      CJump {} -> error "ElaborateLower: CJump is minted by Awsum.Simplify, which runs later"
      e@CProj {} -> e
      e@CVar {} -> e
      e@CString {} -> e
      e@CIntLit {} -> e
      e@CBuiltIn {} -> e

-- | Drop declarations that are no longer reachable from the program's
-- roots. Used after passes that rewrite call sites to fresh targets
-- (like SCC merge, which routes every cross-call through @$scc$...@
-- and can leave the original member's wrapper dead).
--
-- Roots are 'main' and 'runIO': the latter is the prelude's IO-tree
-- walker which the codegen entry-point glue calls on @main@'s result.
-- Because that call lives in a string template (not in Core), the
-- call-graph analysis would otherwise lose track of @runIO@ and
-- shake it away.
-- | Whole-program shake: drops top-level decls unreachable from
-- 'main'/'runIO' and case-arms whose constructor tag is never
-- actually constructed in the reachable code. Iterates the two until
-- a fixed point — pruning a dead arm can render a function
-- unreachable, dropping a function can shrink the live constructor-
-- tag set, which can enable more arm pruning.
--
-- Why arm pruning matters: 'runIO''s IO walker has an arm for every
-- 'IO' constructor (IOPure / IOFail / IOStdoutPrint / IOGetArgs).
-- A program that never constructs 'IOGetArgs' (no 'IO.Args.getArgs'
-- call site) sees the arm as dead code: it references '$apply1'
-- and 'BuiltIn.internalGetArgs', dragging in the per-arity
-- dispatcher and the per-target argv decoder. Pruning the arm cuts
-- that whole tail before it ever reaches codegen.
--
-- Generalises beyond 'runIO': any 'case' arm whose tag is not in
-- the program's reachable construction set is dead. Sum types whose
-- some constructors are never used produce smaller binaries. The
-- construction set is computed flow-sensitively by 'reachableTags' —
-- a construction reachable only through a dead arm does not count, so
-- a combinator arm that rebuilds the very constructor that gates it
-- (e.g. 'andThenIO' rebuilding 'IOGetArgs' inside its own tag-8 arm)
-- cannot keep itself alive.
--
-- Built-in baseline: built-ins like 'concatString' return values of
-- ADT types ('Either StringTooLong String') whose constructors are
-- created by per-target runtime helpers, not by 'CCon' nodes in
-- Core. To stay sound, we precompute every constructor tag of every
-- type mentioned in any built-in signature and treat them as always
-- constructable. Without this, 'Right' / 'Left' / 'Just' / 'Nothing'
-- (and the row tags inside their error rows) would look unreachable
-- and 'concat'-ed strings would dispatch through the wrong arm.
treeShakeFromMain :: ConInfoEnv -> CoreProgram -> CoreProgram
treeShakeFromMain conInfo =
  let baselineCon = builtinReachableConTags conInfo
      baselineRow = builtinReachableRowTags
   in fixpoint (step baselineCon baselineRow)
  where
    fixpoint f x =
      let x' = f x
       in if x' == x then x else fixpoint f x'
    step baselineCon baselineRow prog =
      let prog' = functionLevelShake prog
          (conTags, rowTags) = reachableTags baselineCon baselineRow prog'
       in mapBodies (pruneDeadArms conTags rowTags) prog'

-- | Set of constructor tags that built-ins might construct via
-- their per-target runtime helpers. Computed once per program from
-- the built-in registry: walk every signature, collect every
-- 'TyCon' name mentioned (anywhere — argument or result), and emit
-- each such type's full constructor list.
--
-- Over-approximates: a 'TyCon' mentioned only in an argument
-- position never has its constructors created by the built-in
-- itself, just consumed. Adding those constructors anyway keeps
-- the analysis trivially sound (we miss some pruning opportunities
-- but never drop a live arm). Tightening to "result-position only"
-- is possible but would need 'splitArrowN'-style application
-- analysis at every call site.
builtinReachableConTags :: ConInfoEnv -> Set Int
builtinReachableConTags conInfo =
  let typeNames = foldMap typesMentionedInType (M.elems builtIns)
   in Set.fromList [ciTag ci | (_, ci) <- M.toList conInfo, Set.member (ciTypeName ci) typeNames]

-- | Set of row tags that built-ins might construct. Each 'TyOr'
-- alternative's canonical label is FNV-hashed exactly the same way
-- 'CRow' produces tags at construction sites, so the resulting
-- 'Set Word32' is in the same namespace as 'CRowCase' arm tags.
builtinReachableRowTags :: Set Word32
builtinReachableRowTags =
  Set.fromList [rowTag lbl | t <- M.elems builtIns, lbl <- rowLabelsInType t]

-- | Collect every 'TyCon' name appearing anywhere in a 'Type''.
typesMentionedInType :: Type' -> Set Name
typesMentionedInType = \case
  TyCon _ n -> Set.singleton n
  TyVar _ _ -> mempty
  TyArrow _ a b -> typesMentionedInType a <> typesMentionedInType b
  TyApp _ f x -> typesMentionedInType f <> typesMentionedInType x
  TyOr _ a b -> typesMentionedInType a <> typesMentionedInType b
  TyEmpty _ _ -> mempty

-- | Collect every alternative of every 'TyOr' anywhere in a 'Type''
-- (recursive: rows nested inside 'TyApp' / 'TyArrow' / etc. are
-- walked). Each returned 'Type'' is a row label that backend
-- runtime helpers might wrap a 'CRow' tag around.
rowLabelsInType :: Type' -> [Type']
rowLabelsInType t = case t of
  TyOr {} -> flattenRow t <> concatMap rowLabelsInType (flattenRow t)
  TyArrow _ a b -> rowLabelsInType a <> rowLabelsInType b
  TyApp _ f x -> rowLabelsInType f <> rowLabelsInType x
  _ -> []

-- | Drop top-level decls unreachable from 'main' or 'runIO' via the
-- direct call graph. The two roots are needed because 'runIO' is
-- not called from 'main' in Core — the codegen entry-point glue
-- wires `v_runIO(v_main())` as a string template, not an edge in
-- the IR.
functionLevelShake :: CoreProgram -> CoreProgram
functionLevelShake (CoreProgram ds) =
  let graph = M.fromList [(declName' d, declFreeVars d) | d <- ds]
      reached = reachableCore "main" graph <> reachableCore "runIO" graph
      live = [d | d <- ds, Set.member (declName' d) reached]
   in CoreProgram live

-- | The '(CCon'/'CReuse' tag, 'CRow' tag)' construction sets reachable
-- in the program, as the least fixed point of a /guarded/ walk:
-- descent into a 'CCase' arm is gated on the arm's tag being a known
-- constructable 'CCon' tag, and into a 'CRowCase' arm on the arm's tag
-- being a known constructable row tag. The scrutinee is always walked
-- (it is evaluated whichever arm matches); only arm bodies are gated.
--
-- This is what distinguishes the sets from a flat "every tag textually
-- present" collection. A 'CCon t' that occurs only inside an arm whose
-- own tag nothing constructs is dead and must not seed itself — the
-- exact shape that defeats flat collection: 'andThenIO' / 'handleErrorIO'
-- rebuild 'IOGetArgs' (@CCon 8 [CCon 27 [cont]]@) inside their own tag-8
-- arm, so a flat walk sees tag 8 as constructable and keeps the arm,
-- which keeps the construction — a cycle disconnected from any real
-- 'IO.Args.getArgs' source. Gating the arm on tag 8 breaks it: with no
-- real construction of 8, the arm is never entered, never harvested.
--
-- Seed: the built-in baseline plus every construction outside any arm.
-- Each round opens the arms whose tags just became reachable and
-- harvests their constructions; the pair of sets grows monotonically,
-- bounded by every tag in the program, so iteration converges.
--
-- Sound (never prunes a live arm): an arm taken at runtime has a
-- scrutinee whose tag was constructed on a live path, hence is in the
-- set, hence the arm was walked and its constructions harvested. The
-- induction bottoms out at constructions outside any arm (always
-- harvested) and the baseline.
reachableTags :: Set Int -> Set Word32 -> CoreProgram -> (Set Int, Set Word32)
reachableTags baseCon baseRow (CoreProgram ds) = go baseCon baseRow
  where
    go cs rs =
      let (cs', rs') = foldMap (guardedTags cs rs . declBody) ds
          cs'' = baseCon <> cs'
          rs'' = baseRow <> rs'
       in if cs'' == cs && rs'' == rs then (cs, rs) else go cs'' rs''
    declBody = \case
      CFunDef _ _ body -> body
      CValDef _ body -> body

-- | Collect '(con tags, row tags)' constructed in @e@, descending into
-- a 'CCase' arm only when its tag is in @cs@ and into a 'CRowCase' arm
-- only when its tag is in @rs@. Con and row are gathered in one walk
-- because the two sets co-evolve: a live 'CCase' arm may construct row
-- tags and a live 'CRowCase' arm may construct con tags.
guardedTags :: Set Int -> Set Word32 -> CExpr -> (Set Int, Set Word32)
guardedTags cs rs = go
  where
    go = \case
      CCon t fs -> (Set.singleton t, mempty) <> foldMap go fs
      CReuse _ _ t fs -> (Set.singleton t, mempty) <> foldMap go fs
      CRow t v -> (mempty, Set.singleton t) <> go v
      CCase s alts -> go s <> foldMap (\(t, _, b) -> if Set.member t cs then go b else mempty) alts
      CRowCase s alts -> go s <> foldMap (\(t, _, b) -> if Set.member t rs then go b else mempty) alts
      CCall f xs -> go f <> foldMap go xs
      CLoop b -> go b
      CContinue xs -> foldMap go xs
      CDrop _ b -> go b
      CLet _ rhs body -> go rhs <> go body
      CJoin _ _ body inner -> go body <> go inner
      CJump _ args -> foldMap go args
      CProj _ _ -> mempty
      CVar _ -> mempty
      CString _ -> mempty
      CIntLit _ _ -> mempty
      CBuiltIn _ -> mempty

-- | Map a transformation across every top-level decl's body.
mapBodies :: (CExpr -> CExpr) -> CoreProgram -> CoreProgram
mapBodies f (CoreProgram ds) = CoreProgram (map go ds)
  where
    go (CFunDef n args body) = CFunDef n args (f body)
    go (CValDef n body) = CValDef n (f body)

-- | Drop 'CCase' / 'CRowCase' arms whose tag is not in the
-- reachable-construction set. If filtering would leave zero arms
-- the case is left untouched: an empty case crashes some backends'
-- emit logic, and a truly-empty match means the surrounding code
-- is itself unreachable, which a later iteration of 'treeShakeFromMain'
-- will catch via function-level reachability anyway.
pruneDeadArms :: Set Int -> Set Word32 -> CExpr -> CExpr
pruneDeadArms conTags rowTags = go
  where
    go = \case
      CCase s alts ->
        let s' = go s
            kept = [(t, vs, go b) | (t, vs, b) <- alts, Set.member t conTags]
         in CCase s' (if null kept then map (\(t, vs, b) -> (t, vs, go b)) alts else kept)
      CRowCase s alts ->
        let s' = go s
            kept = [(t, v, go b) | (t, v, b) <- alts, Set.member t rowTags]
         in CRowCase s' (if null kept then map (\(t, v, b) -> (t, v, go b)) alts else kept)
      CCall f xs -> CCall (go f) (map go xs)
      CCon t fs -> CCon t (map go fs)
      CRow t v -> CRow t (go v)
      CLoop b -> CLoop (go b)
      CContinue xs -> CContinue (map go xs)
      CDrop n b -> CDrop n (go b)
      CReuse rm n t fs -> CReuse rm n t (map go fs)
      CLet x rhs body -> CLet x (go rhs) (go body)
      CJoin j ps body inner -> CJoin j ps (go body) (go inner)
      CJump j args -> CJump j (map go args)
      e@(CProj _ _) -> e
      e@(CVar _) -> e
      e@(CString _) -> e
      e@(CIntLit _ _) -> e
      e@(CBuiltIn _) -> e

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
      -- Same story: 'CDrop' is produced by 'Awsum.Lifetime.insertDrops'
      -- after Tco, so saturate never sees it. Transparent passthrough
      -- keeps the pattern match exhaustive.
      CDrop n b -> CDrop n <$> go b
      -- 'CReuse' is also produced after Tco; passthrough.
      CReuse rm n t fs -> CReuse rm n t <$> traverse go fs
      CLet x rhs body -> CLet x <$> go rhs <*> go body
      CJoin {} -> error "Saturate: CJoin is minted by Awsum.Simplify, which runs later"
      CJump {} -> error "Saturate: CJump is minted by Awsum.Simplify, which runs later"
      e@(CProj _ _) -> pure e
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
  CDrop n b -> Set.delete n (freeVars b)
  CReuse _ n _ fs -> Set.insert n (foldMap freeVars fs)
  CLet n rhs body -> freeVars rhs <> Set.delete n (freeVars body)
  CProj n _ -> one n
  -- The join name is a label, not a reference; the parameters scope over
  -- the body only.
  CJoin _ ps body inner -> (freeVars body `Set.difference` Set.fromList ps) <> freeVars inner
  CJump _ args -> foldMap freeVars args

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
-- ════════════════════════════════════════════════════════════════════
-- TExpr-consuming lowering: the elaborated typed AST → Core. Replaces
-- the surface-'Expr' 'lowerExprM' path. Types come off the nodes, so
-- there is no 'expected'-type threading and no 'synthLabelType';
-- row injection appears solely as 'TCoerce' nodes the typechecker
-- placed; and 'monomorphizeRows' has already specialised every
-- row-polymorphic combinator upstream, so abstract-row 'TCoerce's never
-- reach here.
-- ════════════════════════════════════════════════════════════════════

-- | The bound name of a typed parameter.
tpName :: TParam -> Name
tpName (TParam _ _ n) = n

-- | Peel nested typed lambdas off a definition body, returning the
--   collected parameters and the innermost non-lambda body. Lets a
--   @f = \\a -> \\b -> e@ definition lower with @a@, @b@ on the LHS.
peelTLams :: TExpr -> ([TParam], TExpr)
peelTLams (TLam _ _ ps b) = let (ps', b') = peelTLams b in (ps <> ps', b')
peelTLams e = ([], e)

-- | Lower a typed top-level definition. Bare-built-in aliases
--   (@showInt32 = BuiltIn.showInt32@) are dropped — references resolve
--   to the built-in directly through 'lowerVar'. A zero-parameter def
--   whose body has an arrow type is the alias form (@foo = otherFn@) and
--   is eta-expanded; otherwise it is a constant.
lowerTDecl :: LowerEnv -> TDecl -> LowerM (Maybe CDecl)
lowerTDecl _ (TValDef _ (TBuiltIn {})) = pure Nothing
lowerTDecl env (TValDef n body)
  -- @f = \\a b -> e@ — move the lambda parameters onto the LHS (the
  -- typed equivalent of the old surface eta-contraction), so the body
  -- is a plain function rather than a lifted '$lam$N' helper that the
  -- enclosing def then over-applies.
  | (params@(_ : _), inner) <- peelTLams body =
      lowerTDecl env (TFunDef n params inner)
  | otherwise = do
      body' <- lowerTExpr env Set.empty body
      case splitArrow (texprType body) of
        (argTys, _)
          -- Alias form @f = expr@ whose signature is an arrow (e.g.
          -- @say = IO.Stdout.print@): eta-expand to a function so the
          -- alias is itself a first-order top-level definition.
          | not (null argTys) -> do
              let etas = ["$eta" <> show (i :: Int) | i <- [0 .. length argTys - 1]]
                  etaVars = map CVar etas
                  -- When the alias body is itself a (partial) call, append
                  -- the eta params to its argument list rather than wrapping
                  -- it in an outer CCall. A nested @CCall (CCall f xs) etas@
                  -- is defunctionalised into a closure CCon in callee
                  -- position, which 'Awsum.LowerClosures' cannot route
                  -- through an $applyN dispatcher — producing broken codegen.
                  applied = case body' of
                    CCall f innerArgs -> CCall f (innerArgs <> etaVars)
                    _ -> CCall body' etaVars
              pure $ Just $ CFunDef n etas applied
        _ -> pure $ Just $ CValDef n body'
lowerTDecl env (TFunDef n params body) = do
  let env' = extendLowerEnv env [(QName [] (tpName p), tparamType p) | p <- params]
      locals = Set.fromList (map tpName params)
  body' <- lowerTExpr env' locals body
  pure $ Just $ CFunDef n (freshenWildcardArgs (map tpName params)) body'

-- | Lower a typed expression to Core.
lowerTExpr :: LowerEnv -> Locals -> TExpr -> LowerM CExpr
lowerTExpr env locals = \case
  TVar _ _ _ qn -> liftEither (lowerVar env qn)
  TLit _ ty (LInt n) -> case ty of
    TyCon _ "Int32" -> pure (CIntLit n TInt32)
    TyCon _ "UInt8" -> pure (CIntLit n TUInt8)
    TyCon _ "UInt32" -> pure (CIntLit n TUInt32)
    _ -> liftEither $ Left (TELowering ("integer literal without a known numeric type: " <> canonicalLabel ty))
  TLit _ _ (LString t) -> pure (CString t)
  TBuiltIn _ ty name -> pure $ case ty of
    TyArrow {} -> CBuiltIn name
    _ -> CCall (CBuiltIn name) []
  TConRef _ _ _ name -> case M.lookup name (leConInfo env) of
    Just ci
      | ciArity ci == 0 -> pure (CCon (ciTag ci) [])
      | otherwise -> pure (CVar (conWrapperName name))
    Nothing -> liftEither $ Left (TELowering ("unknown constructor: " <> name))
  -- Spines are flat after 'monomorphizeRows', so the head is never a
  -- 'TApp'. A 'TBuiltIn' head lowers to 'CBuiltIn' (a valid 'CCall'
  -- callee), so no special case is needed there. A /saturated/
  -- constructor application arrives as @TApp (TConRef …) args@ (both
  -- check and synthesis modes build this shape) — lower it to a direct
  -- 'CCon' rather than a call to the '$con$…' wrapper, which
  -- Defunctionalize would otherwise mis-specialise.
  TApp _ _ headE args -> case headE of
    TConRef _ _ _ cName
      | Just ci <- M.lookup cName (leConInfo env),
        ciArity ci == length args -> do
          args' <- traverse (lowerTExpr env locals) args
          pure (CCon (ciTag ci) args')
    _ -> do
      headE' <- lowerTExpr env locals headE
      args' <- traverse (lowerTExpr env locals) args
      pure (CCall headE' args')
  TLam _ _ params body -> liftLambdaT env locals params body
  TLet _ _ pat rhs body -> lowerLetT env locals pat rhs body
  TCase _ _ scrut alts -> do
    scrut' <- lowerTExpr env locals scrut
    alts' <- traverse (lowerTAltM env locals) alts
    merged <- mergeAlts alts'
    pure (CCase scrut' merged)
  TRowCase _ _ scrut alts -> do
    scrut' <- lowerTExpr env locals scrut
    rowAlts <- buildRowAltsT env locals alts
    pure (CRowCase scrut' rowAlts)
  -- Row injection / widening: the typechecker recorded the source and
  -- target types, both concrete (monomorphisation made any combinator
  -- copy concrete), so the deep coercion builder injects with real tags.
  TCoerce _ src tgt inner -> do
    inner' <- lowerTExpr env locals inner
    coerceFn <- synthCoerce (leConInfo env) src tgt
    coerceFn inner'

-- | Erase a typed pattern back to its surface form, for reuse of the
--   pattern-structural helpers ('desugarPatsM', 'collectPatternBindings')
--   that already operate on surface 'Pattern's. The binder /types/ those
--   helpers need are recomputed from the matched type, exactly as on the
--   surface-lowering path.
tpatternToPattern :: TPattern -> Pattern
tpatternToPattern = \case
  TPVar sp _ n -> PVar sp n
  TPWild sp _ -> PWild sp
  TPCon sp _ n ps -> PCon sp n (map tpatternToPattern ps)
  TPAscribe sp ty p -> PAscribe sp (tpatternToPattern p) ty

-- | Free unqualified variable references in a typed expression, used for
--   capture analysis when lifting lambdas / lets. Constructor and
--   built-in names are top-level, not captures, so only 'TVar' counts.
freeReferencesT :: TExpr -> Set Name
freeReferencesT = go
  where
    go = \case
      TVar _ _ _ (QName [] n) -> Set.singleton n
      TVar {} -> mempty
      TLit {} -> mempty
      TBuiltIn {} -> mempty
      TConRef {} -> mempty
      TApp _ _ h args -> go h <> foldMap go args
      TLam _ _ params b -> go b `Set.difference` Set.fromList (map tpName params)
      TLet _ _ pat rhs b -> go rhs <> (go b `Set.difference` tpatBound pat)
      TCase _ _ scrut alts -> go scrut <> foldMap goAlt alts
      TRowCase _ _ scrut alts -> go scrut <> foldMap goRowAlt alts
      TCoerce _ _ _ inner -> go inner
    goAlt (TAlt pat b) = go b `Set.difference` tpatBound pat
    goRowAlt (TRowAlt _ pat b) = go b `Set.difference` tpatBound pat
    tpatBound = \case
      TPVar _ _ n -> Set.singleton n
      TPWild _ _ -> mempty
      TPCon _ _ _ ps -> foldMap tpatBound ps
      TPAscribe _ _ p -> tpatBound p

-- | Lift a typed lambda to a fresh top-level helper. Parameter types
--   come straight off the 'TParam's; captures are body-referenced
--   locals minus the lambda's own parameters. Mirrors 'liftLambda' on
--   the surface path but needs no expected-arrow split.
liftLambdaT :: LowerEnv -> Locals -> [TParam] -> TExpr -> LowerM CExpr
liftLambdaT env locals params body = do
  let paramNames = map tpName params
      lamParamSet = Set.fromList paramNames
      captures = Set.toAscList ((freeReferencesT body `Set.intersection` locals) `Set.difference` lamParamSet)
      captureTypes =
        [ fromMaybe (TyVar noSpan "_capture") (leTypeOf env (QName [] c))
        | c <- captures
        ]
      env' =
        extendLowerEnv
          env
          ( [(QName [] (tpName p), tparamType p) | p <- params]
              <> [(QName [] c, ty) | (c, ty) <- zip captures captureTypes]
          )
      locals' = Set.union lamParamSet locals
  body' <- lowerTExpr env' locals' body
  helperName <- freshLamName
  let allParams = captures <> paramNames
  emitHelper (CFunDef helperName (freshenWildcardArgs allParams) body')
  pure $ case captures of
    [] -> CVar helperName
    _ -> CCall (CVar helperName) (map CVar captures)

-- | Lower @let n = e in body@ by lifting the body into a fresh top-level
--   helper and emitting a saturated call. The binder's type is now
--   authoritative (off the 'TPVar' node), so no 'synthLabelType'
--   best-effort is needed. Only 'TPVar' / 'TPWild' binders survive
--   desugaring.
lowerLetT :: LowerEnv -> Locals -> TPattern -> TExpr -> TExpr -> LowerM CExpr
lowerLetT env locals pat rhs body = do
  (n, nTy) <- case pat of
    TPVar _ t nm -> pure (nm, t)
    TPWild _ t -> do
      nm <- freshLetWildName
      pure (nm, t)
    _ -> liftEither $ Left (TELowering "non-PVar let-binding should have been desugared by Awsum.Desugar")
  let captures = Set.toAscList ((freeReferencesT body `Set.intersection` locals) `Set.difference` Set.singleton n)
      captureTypes =
        [ fromMaybe (TyVar noSpan "_capture") (leTypeOf env (QName [] c))
        | c <- captures
        ]
      env' =
        extendLowerEnv
          env
          ((QName [] n, nTy) : [(QName [] c, ty) | (c, ty) <- zip captures captureTypes])
      locals' = Set.insert n locals
  body' <- lowerTExpr env' locals' body
  rhs' <- lowerTExpr env locals rhs
  helperName <- freshLetName
  let allParams = captures <> [n]
  emitHelper (CFunDef helperName (freshenWildcardArgs allParams) body')
  pure (CCall (CVar helperName) (map CVar captures <> [rhs']))

-- | Lower one nominal-case arm into @(tag, top-level binder names,
--   body)@. The inner patterns are erased to surface form so
--   'desugarPatsM' can build the nested-destructuring 'CCase' wrappers
--   exactly as on the surface path; binder types are recomputed from the
--   matched type via 'collectPatternBindings'.
lowerTAltM :: LowerEnv -> Locals -> TAlt -> LowerM (Int, [Name], CExpr)
lowerTAltM env locals (TAlt pat body) = case pat of
  TPCon _ tyMatched cName subTPats -> do
    ci <- liftEither $ maybeToRight (TELowering ("unknown constructor in pattern: " <> cName)) (M.lookup cName (leConInfo env))
    let subPats = map tpatternToPattern subTPats
        tag = ciTag ci
        patBinders = collectPatternBindings (leConInfo env) ci (Just tyMatched) subPats
        env' = extendLowerEnv env [(QName [] nm, t) | (nm, t) <- patBinders]
        locals' = Set.union (Set.fromList (map fst patBinders)) locals
        subst =
          let genericRet = applyTyParams (ciTypeName ci) (ciTypeParams ci)
           in fromRight mempty (unify genericRet tyMatched)
        fieldTys = map (Just . applySubst subst) (ciFieldTypes ci)
    body' <- lowerTExpr env' locals' body
    (topVars, wrappedBody) <- desugarPatsM (leConInfo env) "__" (0 :: Int) (zip subPats fieldTys) body'
    pure (tag, topVars, wrappedBody)
  _ -> liftEither $ Left (TELowering "only constructor patterns are supported in case")

-- | Lower the arms of a row-case into the @(rowTag, binder, body)@ shape
--   'CRowCase' consumes, merging constructor arms that target the same
--   row label into one 'CCase'. Mirrors 'buildRowAltsM' on the surface
--   path; the arm kind is recovered from the typed pattern ('TPAscribe'
--   for @(x : T)@ arms, 'TPCon' for constructor arms).
buildRowAltsT :: LowerEnv -> Locals -> [TRowAlt] -> LowerM [(Word32, Name, CExpr)]
buildRowAltsT env locals alts = do
  rawArms <- traverse (lowerRowArmT env locals) alts
  let grouped = groupBy (\(t1, _, _) (t2, _, _) -> t1 == t2) (sortWith fstOf3 rawArms)
  traverse buildOne grouped
  where
    fstOf3 (a, _, _) = a
    buildOne :: [(Word32, Type', RowArmShape)] -> LowerM (Word32, Name, CExpr)
    buildOne [] = liftEither $ Left (TELowering "buildRowAltsT: empty group (unreachable)")
    buildOne g = case findCollidingLabels g of
      Just (l1, l2, tag) ->
        liftEither $ Left (RowTagCollision l1 l2 tag (tyConDeclSpan (leTypeDeclSpans env) l2))
      Nothing -> case g of
        [(tag, _, AscribeShape var body)] -> pure (tag, var, body)
        ((tag, _, ConShape {}) : _) -> do
          let conAlts = [(t, vs, b) | (_, _, ConShape t vs b) <- g]
          merged <- mergeAlts conAlts
          let var = "__rw" :: Name
          pure (tag, var, CCase (CVar var) merged)
        ((_, _, AscribeShape _ _) : _ : _) ->
          liftEither $ Left (TELowering "row case has duplicate PAscribe arms for the same label (typechecker should have rejected this as DuplicateRowArm)")
    findCollidingLabels :: [(Word32, Type', RowArmShape)] -> Maybe (Type', Type', Word32)
    findCollidingLabels [] = Nothing
    findCollidingLabels ((tag, l0, _) : rest) =
      case find (\(_, l, _) -> canonicalLabel l /= canonicalLabel l0) rest of
        Just (_, l1, _) -> Just (l0, l1, tag)
        Nothing -> Nothing

-- | Lower one row-case arm into its row tag and intermediate shape.
lowerRowArmT :: LowerEnv -> Locals -> TRowAlt -> LowerM (Word32, Type', RowArmShape)
lowerRowArmT env locals (TRowAlt label pat body) = case pat of
  TPAscribe _ ascrTy inner -> do
    let var = case inner of
          TPVar _ _ n -> n
          _ -> "__rw"
        env' = extendLowerEnv env [(QName [] var, ascrTy)]
        locals' = Set.insert var locals
    body' <- lowerTExpr env' locals' body
    tag <- recordRowTag ascrTy
    pure (tag, ascrTy, AscribeShape var body')
  TPCon _ _ cName innerTPats -> do
    ci <-
      liftEither
        $ maybeToRight (TELowering ("unknown constructor in row pattern: " <> cName)) (M.lookup cName (leConInfo env))
    let innerPats = map tpatternToPattern innerTPats
        subst =
          let genericRet = applyTyParams (ciTypeName ci) (ciTypeParams ci)
           in fromRight mempty (unify genericRet label)
        fieldTys = map (Just . applySubst subst) (ciFieldTypes ci)
        patBinders = collectPatternBindings (leConInfo env) ci (Just label) innerPats
        env' = extendLowerEnv env [(QName [] nm, t) | (nm, t) <- patBinders]
        locals' = Set.union (Set.fromList (map fst patBinders)) locals
    body' <- lowerTExpr env' locals' body
    (topVars, wrappedBody) <- desugarPatsM (leConInfo env) "__" (0 :: Int) (zip innerPats fieldTys) body'
    tag <- recordRowTag label
    pure (tag, label, ConShape (ciTag ci) topVars wrappedBody)
  _ -> liftEither $ Left (TELowering "row-case arm must be an ascription or constructor pattern")

-- | Build the un-substituted result type for a constructor: e.g.
--   @applyTyParams "Either" ["a", "b"] = TyApp (TyApp (TyCon "Either") (TyVar "a")) (TyVar "b")@.
--   Mirrors 'Awsum.Typing.conReturnType' but is local to lowering so
--   we don't depend on the typechecker's conEnv.
applyTyParams :: Name -> [Name] -> Type'
applyTyParams n [] = TyCon noSpan n
applyTyParams n tvs = foldl' (\acc tv -> TyApp noSpan acc (TyVar noSpan tv)) (TyCon noSpan n) tvs

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
-- The single identity oracle. 'coercionIsIdentity' is True exactly when
-- the coercion is a no-op on the runtime representation, subsuming every
-- former fast path: equal types, a 'TyVar' / 'TyEmpty' end (a tyvar is
-- opaque; 'Never' is uninhabited, so coercing it is vacuous — this is
-- what lets @IO Never Unit@ flow into a wider @IO (E1 | E2) Unit@), and a
-- 'CRow'-tagged value widened within its row (per-label FNV tags are
-- stable across rows, so no re-wrap). The case the former fast paths
-- missed: a nominal head or function arrow whose every field / side
-- coercion is itself identity. That last one collapses the IO error-row
-- widening @IO Never X → IO (e | Never) X@ inserted by @andThenIO@ /
-- @bindIO@ / @mapIO@ / @handleErrorIO@, which used to emit a full
-- structural deep-copy '$lift$N' — itself recursive, hence CPS'd, with
-- defunctionalised continuation wrappers — for what is the identity.
synthCoerce conInfo src tgt
  | coercionIsIdentity conInfo src tgt = pure pure
-- Reached only when at least one concrete label's FNV tag moved (a
-- nominal head with a grown inner row, e.g. Maybe Bool -> Maybe (Bool |
-- Unit)): dispatch on the value's current label and re-coerce each into
-- the target row, re-tagging where the per-label tag changed.
synthCoerce conInfo src@(TyOr {}) tgt@(TyOr {}) = do
  arms <-
    traverse
      ( \lbl -> do
          coerceLbl <- synthCoerce conInfo lbl tgt
          tag <- recordRowTag lbl
          binder <- freshLiftName
          body <- coerceLbl (CVar binder)
          pure (tag, binder, body)
      )
      (flattenRow src)
  pure (\v -> pure (CRowCase v arms))
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
  | Just headName <- extractTyCon src,
    Just headName' <- extractTyCon tgt,
    headName == headName' =
      synthNominalHeadCoerce conInfo headName src tgt
-- Function-typed coercion: pointwise rebuild via a top-level helper
-- @$liftFn$N f = \a -> coerceB (f (coerceA a))@ where the per-side
-- coercions come from recursive 'synthCoerce'. Used when IO-row
-- widening (or any other nominal-head coercion) walks a constructor
-- field whose type is a function — e.g. `IOGetArgs (Either err
-- String -> IO e a)` coerced from `IO e1 a` to `IO (e1|e2) b` widens
-- the field from `… -> IO e1 a` to `… -> IO (e1|e2) b`. The
-- post-coercion closure lands in 'CCon' field position; subsequent
-- 'Awsum.LowerClosures' encodes it as a tagged 'CCon' and routes the
-- residual call through the right `$applyN` dispatcher.
synthCoerce conInfo (TyArrow _ srcA srcB) (TyArrow _ tgtA tgtB) = do
  argCoerce <- synthCoerce conInfo tgtA srcA
  resCoerce <- synthCoerce conInfo srcB tgtB
  helper <- freshLiftName
  let argName :: Name
      argName = "__arg"
      fnName :: Name
      fnName = "__f"
  argCoerced <- argCoerce (CVar argName)
  let inner = CCall (CVar fnName) [argCoerced]
  bodyCoerced <- resCoerce inner
  emitHelper (CFunDef helper [fnName, argName] bodyCoerced)
  pure (\v -> pure (CCall (CVar helper) [v]))
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
      arms <-
        forM (nominalConFieldTypes conInfo tyName src tgt) $ \(tag, fields) -> do
          coercedFields <-
            forM fields $ \(fn, sTy, tTy) -> do
              wrap <- synthCoerce conInfo sTy tTy
              wrap (CVar fn)
          pure (tag, map (\(fn, _, _) -> fn) fields, CCon tag coercedFields)
      let body = CCase (CVar "__input") arms
      emitHelper (CFunDef helper ["__input"] body)
      pure (\v -> pure (CCall (CVar helper) [v]))

-- | Per-constructor field-coercion types for a coercion @src → tgt@
--   between two type-applications that share a nominal head. For each
--   constructor of the head's owning type, returns its tag and a
--   @(fieldName, srcFieldType, tgtFieldType)@ triple per field. Shared
--   by 'synthNominalHeadCoerce' (which builds the destructure-and-rebuild
--   helper from these) and 'coercionIsIdentity' (which only inspects the
--   field types) so the two can never disagree on field shape — a
--   disagreement would be a miscompile, the predicate declaring identity
--   where the builder would have done real work.
--
--   Freshens the generic head's parameters (and the per-field types that
--   mention them) before unifying. Without this, an input type whose
--   tyvar happens to share a name with one of the type's own parameters
--   — e.g. @Either PE a@, where @a@ also names @Either@'s second
--   parameter — would cross-bind during 'unify' and corrupt the per-field
--   substitution. The "$ctor" suffix is just a marker; the exact name
--   doesn't matter as long as it doesn't collide with any tyvar in @src@
--   or @tgt@.
nominalConFieldTypes :: ConInfoEnv -> Name -> Type' -> Type' -> [(Int, [(Name, Type', Type')])]
nominalConFieldTypes conInfo tyName src tgt =
  let cons = constructorsOfType conInfo tyName
      srcParams = maybe [] ciTypeParams (M.lookup (firstConName cons) conInfo)
      freshSubst =
        mconcat [singletonSubst p (TyVar noSpan (p <> "$ctor")) | p <- srcParams]
      freshGeneric = applySubst freshSubst (applyTyParams tyName srcParams)
      srcSubst = fromRight mempty $ unify freshGeneric src
      tgtSubst = fromRight mempty $ unify freshGeneric tgt
   in [ ( ciTag ci,
          [ ("__f" <> show i, applySubst srcSubst f, applySubst tgtSubst f)
          | (i, fTy) <- zip [(0 :: Int) ..] (ciFieldTypes ci),
            let f = applySubst freshSubst fTy
          ]
        )
      | (_cName, ci) <- cons
      ]

-- | Is the coercion @src → tgt@ the identity on the runtime
--   representation? A greatest fixpoint over the type structure: the
--   nominal-head case assumes identity for the @(src, tgt)@ pair it is
--   currently deciding (the @seen@ set) before checking its fields, so a
--   recursive type like @IO@ — whose @IOStdoutPrint@ tail and
--   @IOGetArgs@-continuation result both recurse to the same coercion —
--   converges to True instead of looping. The answer drives the single
--   guard in 'synthCoerce'; every True branch is a genuine no-op:
--
--     * 'typeEq' — same type, nothing to do.
--     * 'TyVar' on either end — a tyvar is opaque; it can carry no
--       row-tag change.
--     * 'TyEmpty' source — uninhabited ('Never'), so vacuous.
--     * 'TyOr' → 'TyOr' with no concrete label re-tagged — per-label FNV
--       tags are stable across rows, so a 'CRow'-tagged value is already
--       valid in the wider row ('rowRetagNeeded' is the existing test).
--     * shared nominal head, all field coercions identity — the rebuild
--       @CCon tag [id f0, id f1, …]@ reconstructs the same cell.
--     * function arrow, both sides identity — @\\f a -> f a@ is @f@.
--
--   Injection into a row (@src@ not a row, @tgt@ a row) is never the
--   identity: it adds a 'CRow' tag. Anything else (incompatible shapes,
--   a row narrowed to a non-row) is conservatively False — 'synthCoerce'
--   handles or rejects it downstream.
coercionIsIdentity :: ConInfoEnv -> Type' -> Type' -> Bool
coercionIsIdentity conInfo = go Set.empty
  where
    go :: Set.Set (Text, Text) -> Type' -> Type' -> Bool
    go seen src tgt
      | typeEq src tgt = True
      | TyVar {} <- tgt = True
      | TyVar {} <- src = True
      | TyEmpty {} <- src = True
      | TyOr {} <- src, TyOr {} <- tgt = not (rowRetagNeeded src tgt)
      | TyOr {} <- tgt = False
      | TyOr {} <- src = False
      | TyArrow _ sA sB <- src,
        TyArrow _ tA tB <- tgt =
          go seen tA sA && go seen sB tB
      | Just h1 <- extractTyCon src,
        Just h2 <- extractTyCon tgt,
        h1 == h2 =
          let key = (canonicalLabel src, canonicalLabel tgt)
           in Set.member key seen
                || all
                  (\(_tag, fields) -> all (\(_fn, sTy, tTy) -> go (Set.insert key seen) sTy tTy) fields)
                  (nominalConFieldTypes conInfo h1 src tgt)
      | otherwise = False

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

-- | Per-arm intermediate value used by 'buildRowAlts'. 'AscribeShape'
--   carries the binder name and lowered body for a @(x : T) -> body@
--   arm; 'ConShape' carries the constructor's tag, the de-sugared
--   top-level variable list, and the lowered body wrapped in any
--   nested CCase that 'desugarPats' produced for inner patterns.
data RowArmShape
  = AscribeShape Name CExpr
  | ConShape Int [Name] CExpr

-- | Merge case alternatives that share an outer tag. Arms that match the
--   same constructor but differ only in deeper fields are unioned into one
--   arm whose body dispatches on those fields — e.g. @Ok (Ok x) -> …@ and
--   @Ok (Err x) -> …@ (both tag @Ok@) fold into one @Ok@ arm with a nested
--   case on the inner @Result@. Two obligations beyond plain concatenation:
--
--     * /Row fields/ merge recursively ('mergeRowAlts'), exactly like
--       nominal fields ('mergeAlts'). A row field followed by a further
--       discriminating field produces two arms with the same row tag; left
--       merely concatenated, the second tag duplicates the first and its
--       dispatch is lost.
--     * /Binders/ are reconciled ('reconcileVars' / 'reconcileVar'). The
--       union keeps one binder list; an arm whose binders differ is
--       alpha-renamed onto a fresh canonical list first, so no body
--       references a binder the merge dropped.
--
--   A residual shape conflict (one arm dispatches on a field, a sibling
--   binds it whole) is the forbidden partial-catch-all, which
--   'Awsum.Typing.rejectPartialCatchAll' rejects before lowering — so the
--   'TELowering' branches in 'mergeBodies' are defensive and unreachable
--   on well-typed input.
mergeAlts :: [(Int, [Name], CExpr)] -> LowerM [(Int, [Name], CExpr)]
mergeAlts alts = concat <$> traverse mergeGroup (groupByTag alts)
  where
    mergeGroup :: [(Int, [Name], CExpr)] -> LowerM [(Int, [Name], CExpr)]
    mergeGroup [] = pure []
    mergeGroup [alt] = pure [alt]
    mergeGroup grp@((tag, _, _) : _) = do
      (vars, bodies) <- reconcileVars [(vs, b) | (_, vs, b) <- grp]
      merged <- mergeBodies bodies
      pure [(tag, vars, merged)]

-- | Group case-alt triples by their (orderable) tag, sorting first so
--   'groupBy' collects all same-tag arms into one group. One copy shared by
--   'mergeAlts' and 'mergeRowAlts' so the sort key and the group predicate
--   can never drift apart (a mismatch would split same-tag arms and skip
--   the merge they require).
groupByTag :: (Ord t) => [(t, a, b)] -> [[(t, a, b)]]
groupByTag = groupBy (\(t1, _, _) (t2, _, _) -> t1 == t2) . sortOn (\(t, _, _) -> t)

-- | The structural-sum analogue of 'mergeAlts': merge row-case arms that
--   share a row tag, unioning their inner dispatchers. A group of size one
--   (a row label matched once) is left untouched.
mergeRowAlts :: [(Word32, Name, CExpr)] -> LowerM [(Word32, Name, CExpr)]
mergeRowAlts alts = concat <$> traverse mergeRowGroup (groupByTag alts)
  where
    mergeRowGroup :: [(Word32, Name, CExpr)] -> LowerM [(Word32, Name, CExpr)]
    mergeRowGroup [] = pure []
    mergeRowGroup [alt] = pure [alt]
    mergeRowGroup grp@((tag, _, _) : _) = do
      (var, bodies) <- reconcileVar [(v, b) | (_, v, b) <- grp]
      merged <- mergeBodies bodies
      pure [(tag, var, merged)]

-- | Union the inner dispatchers of same-tag arms. Every body in a
--   multi-arm group is the same shape — a 'CCase' / 'CRowCase' on the same
--   field binder — because the arms matched the same constructor and
--   differ only deeper; the field binders are positional and so identical
--   across the arms ('reconcileVars' has already made the top-level ones
--   coincide). A mismatched shape is the forbidden partial-catch-all
--   rejected upstream (see 'mergeAlts').
mergeBodies :: [CExpr] -> LowerM CExpr
mergeBodies [] = liftEither $ Left (TELowering "mergeBodies: empty group (unreachable)")
mergeBodies [body] = pure body
mergeBodies (body0 : rest) = case body0 of
  CCase (CVar scrutVar) innerAlts -> do
    allInnerAlts <- foldM collectCase innerAlts rest
    CCase (CVar scrutVar) <$> mergeAlts allInnerAlts
  CRowCase (CVar scrutVar) innerAlts -> do
    allInnerAlts <- foldM collectRow innerAlts rest
    CRowCase (CVar scrutVar) <$> mergeRowAlts allInnerAlts
  _ -> liftEither $ Left (TELowering "conflicting pattern shapes in merge")
  where
    collectCase acc (CCase (CVar _) innerAlts) = pure (acc <> innerAlts)
    collectCase _ _ = liftEither $ Left (TELowering "conflicting pattern shapes in merge")
    collectRow acc (CRowCase (CVar _) innerAlts) = pure (acc <> innerAlts)
    collectRow _ _ = liftEither $ Left (TELowering "conflicting row-case shapes in merge")

-- | Reconcile the field-binder lists of arms being merged. When every arm
--   already uses the same binders (the common case — deterministic
--   @__pN@ field names, or the same source name) keep them, so Core stays
--   readable. Otherwise mint a fresh canonical list and alpha-rename each
--   arm's body onto it; fresh targets ('freshMergeName') are globally
--   unique, so the rename neither chains nor captures.
reconcileVars :: [([Name], CExpr)] -> LowerM ([Name], [CExpr])
reconcileVars [] = pure ([], [])
reconcileVars arms@((vars0, _) : _)
  | all ((== vars0) . fst) arms = pure (vars0, map snd arms)
  | otherwise = do
      fresh <- traverse (const freshMergeName) vars0
      pure (fresh, [renameBinders (zip vs fresh) body | (vs, body) <- arms])

-- | Single-binder ('CRowCase' arm) counterpart of 'reconcileVars'.
reconcileVar :: [(Name, CExpr)] -> LowerM (Name, [CExpr])
reconcileVar [] = pure ("__rw", [])
reconcileVar arms@((var0, _) : _)
  | all ((== var0) . fst) arms = pure (var0, map snd arms)
  | otherwise = do
      fresh <- freshMergeName
      pure (fresh, [alphaRename v fresh body | (v, body) <- arms])

-- | Apply a positional binder renaming to a body. The targets are fresh
--   (so distinct from every source name and from each other), which is why
--   folding single-variable 'alphaRename's is equivalent to a simultaneous
--   substitution here — no rename can feed another.
renameBinders :: [(Name, Name)] -> CExpr -> CExpr
renameBinders pairs body = foldl' (\acc (from, to) -> alphaRename from to acc) body pairs

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
      let innerTag = maybe 0 ciTag (M.lookup innerCon conInfo)
      case rowLabelForCon conInfo innerCon mFieldTy of
        -- Row-typed field whose value is tagged by the label `innerCon`
        -- belongs to: dispatch on the row tag first — binding the
        -- unwrapped value — then on the constructor, mirroring the
        -- row-case path's `ConShape`. A bare `CCase` on the constructor
        -- tag would read the row tag instead and never match. The outer
        -- binder uses the shared `__pa<idx>` name (as `PAscribe` does), so
        -- a sibling ascription arm or another label-descent on the same
        -- field merges into one `CRowCase` rather than bailing with
        -- "conflicting pattern shapes in merge".
        Just label -> do
          let rowVar = prefix <> "pa" <> show idx
              rowInner = rowVar <> "c"
              innerPrefix = rowInner <> "_"
              innerFieldTys = innerFieldTypes conInfo innerCon (Just label) (length innerPats)
          labelTag <- recordRowTag label
          (innerVars, innerBody) <-
            desugarPatsM conInfo innerPrefix 0 (zip innerPats innerFieldTys) restBody
          pure
            ( rowVar : restVars,
              CRowCase
                (CVar rowVar)
                [(labelTag, rowInner, CCase (CVar rowInner) [(innerTag, innerVars, innerBody)])]
            )
        Nothing -> do
          let fresh = prefix <> "p" <> show idx
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

-- | When a 'PCon' field pattern's field type is a structural sum and the
--   constructor belongs to one of its labels (a nominal type appearing as
--   an alternative), return that label. The pattern then /descends/ into
--   the label — the field's value is row-tagged, so the match dispatches
--   on the row tag first and on the constructor second. 'Nothing' for a
--   nominal field, where the constructor matches the value directly.
rowLabelForCon :: ConInfoEnv -> Name -> Maybe Type' -> Maybe Type'
rowLabelForCon conInfo innerCon (Just fieldTy)
  | TyOr {} <- fieldTy,
    Just ci <- M.lookup innerCon conInfo =
      find (\l -> extractTyCon l == Just (ciTypeName ci)) (flattenRow fieldTy)
rowLabelForCon _ _ _ = Nothing

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
    [] | Just t <- lookupBuiltIn n -> Right (saturateBuiltIn n t)
    [] -> Right (CVar n)
    _
      | Just t <- M.lookup q (platformTable env.leProgramType) ->
          Right (saturateBuiltIn (prettyQName mods n) t)
    _ ->
      Left
        $ TELowering
        $ "unsupported qualified name: "
        <> prettyQName mods n
  where
    prettyQName ms name = T.intercalate "." (ms <> [name])
    -- Core invariant: 'CBuiltIn' may only appear in 'CCall' callee
    -- position. For function-typed built-ins this is satisfied by
    -- the surrounding 'EApp' clause that wraps in 'CCall'. For
    -- zero-arg built-ins (e.g. 'IO.Args.getArgs', a value-returning
    -- platform effect) there is no surrounding 'EApp', so saturate
    -- here: 'CCall (CBuiltIn name) []' preserves the invariant and
    -- matches the codegen contract.
    saturateBuiltIn name = \case
      TyArrow {} -> CBuiltIn name
      _ -> CCall (CBuiltIn name) []
