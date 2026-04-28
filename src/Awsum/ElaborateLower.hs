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
import Awsum.Program (ProgramType, platformTable)
import Awsum.Scc (sccMergeProgram)
import Awsum.StackSafety (verifyStackSafety)
import Awsum.StackSafety qualified as StackSafety
import Awsum.Syntax
import Awsum.Tco (tcoProgram)
import Awsum.Typing (TypeError (..), Warning, isBareBuiltIn, splitArrow, typecheckProgram)
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
    leConInfo :: ConInfoEnv
  }

-- | Constructor info: maps constructor name → (tag, arity).
type ConInfoEnv = M.Map Name (Int, Int)

-- | Build constructor info from @type@ declarations.
--   Each constructor gets a 0-based tag and its arity (number of fields).
buildConInfo :: [Decl] -> ConInfoEnv
buildConInfo ds =
  M.fromList
    [ (cName, (idx, length cFields))
    | TypeDecl _sp _ _ cs _ <- ds,
      (ConDef _ cName cFields, idx) <- zip cs [0 ..]
    ]

-- | Synthetic name for a constructor wrapper function.
--   Uses @$con$@ prefix which cannot collide with user-defined names.
conWrapperName :: Name -> Name
conWrapperName name = "$con$" <> name

-- | Generate wrapper 'CFunDef's for every non-nullary constructor.
--   E.g. @type Box a = Box a@ produces:
--     @CFunDef "$con$Box" ["$x0"] (CCon 0 [CVar "$x0"])@
genConWrappers :: ConInfoEnv -> [CDecl]
genConWrappers conInfo =
  [ CFunDef (conWrapperName name) params (CCon tag (map CVar params))
  | (name, (tag, arity)) <- M.toList conInfo,
    arity > 0,
    let params = ["$x" <> show i | i <- [0 .. arity - 1]]
  ]

-- | Check the surface program (types) and lower it to Core IR.
--   On success we return @(warnings, core)@: the Core program for codegen
--   plus any non-fatal warnings the typechecker collected.
elaborateLowerProgram :: ProgramType -> Program -> Either TypeError ([Warning], CoreProgram)
elaborateLowerProgram progType prog = do
  -- 1) Elaboration step: just typecheck; no evidence/dictionaries yet.
  warnings <- typecheckProgram progType prog
  -- 2) Lowering: drop signatures, convert defs/exprs. Fail gracefully on unknown primitives.
  let ds = toList (decls prog)
      conInfo = buildConInfo ds
      sigMap = M.fromList [(n, t) | Sig _sp n t _ <- ds]
      env = mkLowerEnv progType conInfo sigMap
  mds <- traverse (lowerDecl env sigMap) ds
  -- 3) Tree-shake: drop Core declarations unreachable from 'main'.
  --    Covers both user functions that no one calls and prelude
  --    helpers the user program does not touch (e.g.
  --    @showUnderflowError@ in a program that never uses @predInt32@).
  --    Constructor wrappers are generated after this reachability is
  --    known so they're only materialised for constructors still
  --    present in the surviving code.
  let userDecls = catMaybes mds
      allWrappers = genConWrappers conInfo
      allDecls = userDecls <> allWrappers
      callGraph = M.fromList [(declName' d, declFreeVars d) | d <- allDecls]
      reachableFromMain = reachableCore "main" callGraph
      live = filter (\d -> Set.member (declName' d) reachableFromMain) allDecls
      core = CoreProgram live
  -- 4) Saturate under-applied direct calls via lambda-lifting.
  core' <- saturateProgram core
  -- 5) SCC-merge for mutual recursion. Every strongly-connected
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
  let sccMerged = treeShakeFromMain (sccMergeProgram core')
  -- 6) CPS + defunctionalization for non-tail self-recursion. For each
  --    function with a non-tail self-call, emit a (wrapper, '$cps$f',
  --    '$apply$f') trio; the continuation chain now lives as an ADT on
  --    the heap instead of as frames on the system stack, and '$cps$f'
  --    and '$apply$f' are both self-tail-recursive so the following TCO
  --    pass folds them into loops. See 'Awsum.Cps' and docs/recursion.md.
  let cpsed = cpsProgram sccMerged
  -- 7) Stack-safety verifier. After SCC merge and CPS there must be
  --    no non-trivial call-graph cycle and no CFunDef with a non-tail
  --    self-call — both mean a recursion shape that would silently
  --    overflow the system stack at depth on some backend. Any
  --    remainder is a compile error (no escape hatch): the program is
  --    either user-level ill-formed (mutually recursive 'CValDef's,
  --    which have no fixed point) or a compiler bug.
  case verifyStackSafety cpsed of
    [] -> pass
    (issue : _) -> Left (toTypeError sigMap issue)
  -- 8) Self-TCO: rewrite self-recursive tail calls into 'CContinue', and
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
mkLowerEnv :: ProgramType -> ConInfoEnv -> M.Map Name Type' -> LowerEnv
mkLowerEnv progType conInfo sigMap =
  let userSigs = M.fromList [(QName [] n, t) | (n, t) <- M.toList sigMap]
      lookupName q = M.lookup q (userSigs <> platformTable progType)
   in LowerEnv {leProgramType = progType, leTypeOf = lookupName, leConInfo = conInfo}

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

    liftPap f args ar = do
      let missing = ar - length args
          etas = ["$eta" <> show i | i <- [0 .. missing - 1]]
          freeInArgs = foldMap freeVars args `Set.intersection` locals
      if not (Set.null freeInArgs)
        then
          lift
            $ Left
            $ TELowering
            $ "partial application with local captures is not supported: captured "
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
  CCall f xs -> freeVars f <> foldMap freeVars xs
  CLoop b -> freeVars b
  CContinue xs -> foldMap freeVars xs

-- | Lower a top-level declaration.
--   • Type signatures and type declarations are erased (they already influenced checking).
--   • Zero-arg defs become constants ('CValDef'), others become first-order functions.
--   • The signature, when present, gives the expected result type — used by
--     'lowerExpr' to resolve the type of any 'LInt' literal appearing in the
--     body (surface integer literals are untyped).
lowerDecl :: LowerEnv -> M.Map Name Type' -> Decl -> Either TypeError (Maybe CDecl)
lowerDecl env sigMap = \case
  Sig {} -> Right Nothing
  CommentDecl _ -> Right Nothing
  TypeDecl {} -> Right Nothing
  -- Alias declaration @foo = BuiltIn.bar@: no Core def is emitted.
  -- User references to @foo@ are routed to 'CBuiltIn' at 'lowerVar',
  -- so there is no function body to carry — the builtin itself is the
  -- implementation, and every backend knows how to emit it in place.
  FunDef _sp _n [] body _ | isBareBuiltIn body -> Right Nothing
  -- Generalised alias form @foo = expr@ where the signature has arrow
  -- shape and the RHS is not a bare @BuiltIn.bar@: eta-expand to a
  -- regular first-order function. The body becomes a fully-applied call
  -- of the RHS to fresh @$eta_i@ parameters, which keeps the invariant
  -- that 'CBuiltIn' only ever appears in callee position of 'CCall' (the
  -- RHS may be a platform effect like @IO.Stdout.print@) and lets every
  -- backend treat @foo@ as a normal top-level function.
  FunDef _sp n [] body _
    | Just ty <- M.lookup n sigMap,
      let (argTys, _) = splitArrow ty,
      not (null argTys) -> do
        body' <- lowerExpr env Nothing body
        let etas = ["$eta" <> show (i :: Int) | i <- [0 .. length argTys - 1]]
            call = CCall body' (map CVar etas)
        pure $ Just $ CFunDef n etas call
  FunDef _sp n args body _ -> do
    let (argTys, resultTy) = case M.lookup n sigMap of
          Just t -> splitArrowN (length args) t
          Nothing -> ([], Nothing)
        -- Extend env with the function's parameters so 'lowerExpr' can
        -- resolve their types at use sites (currently only matters if a
        -- parameter's type is propagated into a literal, but keeps the
        -- lookup uniform).
        paramEntries =
          [ (QName [] (paramName p), ty)
          | (p, Just ty) <- zip args (map Just argTys <> repeat Nothing)
          ]
        env' = extendLowerEnv env paramEntries
    body' <- lowerExpr env' resultTy body
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
lowerExpr :: LowerEnv -> Maybe Type' -> Expr -> Either TypeError CExpr
lowerExpr env expected = \case
  EParens _sp e -> lowerExpr env expected e
  EVar _sp qn -> lowerVar env qn
  ELit _sp (LString t) -> Right (CString t)
  ELit sp (LInt n) -> case expected of
    Just (TyCon _ "Int32") -> Right (CIntLit n TInt32)
    Just (TyCon _ "UInt8") -> Right (CIntLit n TUInt8)
    -- The typechecker runs first and raises 'AmbiguousIntLiteral' /
    -- 'IntLiteralOutOfRange' / 'TypeMismatch' for every offending literal,
    -- so reaching here means lowering failed to thread the expected type.
    -- Surface that as a lowering bug rather than silently discarding the value.
    _ -> Left (TELowering ("integer literal without a known numeric type at " <> show (spanStartLine sp) <> ":" <> show (spanStartCol sp)))
  EInfix _sp OpConcat l r ->
    let strExpected = Just (TyCon noSpan "String")
     in CCall (CBuiltIn "concatString")
          <$> sequenceA [lowerExpr env strExpected l, lowerExpr env strExpected r]
  ECon _sp name -> case M.lookup name (leConInfo env) of
    Just (tag, 0) -> Right (CCon tag [])
    Just (_tag, _arity) -> Right (CVar (conWrapperName name))
    Nothing -> Left (TELowering ("unknown constructor: " <> name))
  EBuiltIn _sp name -> Right (CBuiltIn name)
  ECase _sp scrut alts _ -> do
    scrut' <- lowerExpr env Nothing scrut
    alts' <- traverse (lowerAlt env expected) (toList alts)
    merged <- mergeAlts alts'
    Right (CCase scrut' merged)
  EApp _sp f x -> do
    let (f0, xs) = collectApps f [x]
    case f0 of
      ECon _sp' name -> case M.lookup name (leConInfo env) of
        Just (tag, _arity) -> do
          xs' <- traverse (lowerExpr env Nothing) xs
          Right (CCon tag xs')
        Nothing -> Left (TELowering ("unknown constructor: " <> name))
      _ -> do
        -- Recover argument types from the head's declared type so integer
        -- literals in argument position get their IntType.
        let argTys = case f0 of
              EVar _ qn -> case leTypeOf env qn of
                Just t -> fst (splitArrowN (length xs) t)
                Nothing -> []
              _ -> []
            argExpected = map Just argTys <> repeat Nothing
        f0' <- lowerExpr env Nothing f0
        xs' <- zipWithM (lowerExpr env) argExpected xs
        Right (CCall f0' xs')

-- | Lower a single case alternative: look up the constructor tag,
--   desugar nested patterns into nested CCase, and lower the body.
--   The 'Maybe Type'' is the expected type of the whole case expression
--   and is propagated to each arm body so integer literals inside arms get
--   their 'IntType'.
lowerAlt :: LowerEnv -> Maybe Type' -> CaseAlt -> Either TypeError (Int, [Name], CExpr)
lowerAlt env expected (CaseAlt _ (PCon _ cName pats) body _) = do
  (tag, _arity) <- maybeToRight (TELowering ("unknown constructor in pattern: " <> cName)) (M.lookup cName (leConInfo env))
  body' <- lowerExpr env expected body
  let (topVars, wrappedBody) = desugarPats (leConInfo env) "__" 0 pats body'
  Right (tag, topVars, wrappedBody)
lowerAlt _ _ CaseAlt {} =
  Left (TELowering "only constructor patterns are supported in case")

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
      -- (same number of vars, all bodies are CCase on the first var)
      case (body, map (\(_, vs, b) -> (vs, b)) rest) of
        (CCase (CVar scrutVar) innerAlts, otherBodies) -> do
          -- Check if all other bodies are also CCase on their first var
          allInnerAlts <- foldM collectInnerAlts innerAlts otherBodies
          -- Recursively merge the collected inner alternatives
          mergedInnerAlts <- mergeAlts allInnerAlts
          -- Use a consistent variable name (take from first alt)
          Right [(tag, vars, CCase (CVar scrutVar) mergedInnerAlts)]
        _ ->
          -- Not all bodies are CCase, or they don't match - this is an error
          -- (patterns with same outer constructor but different nesting structure)
          Left (TELowering $ "conflicting pattern shapes for constructor tag " <> show tag)

    collectInnerAlts :: [(Int, [Name], CExpr)] -> ([Name], CExpr) -> Either TypeError [(Int, [Name], CExpr)]
    collectInnerAlts acc (_vars, CCase (CVar _scrutVar) innerAlts) =
      Right (acc <> innerAlts)
    collectInnerAlts _ _ =
      Left (TELowering "conflicting pattern shapes in merge")

-- | Desugar a list of sub-patterns into flat variable bindings,
--   wrapping the body in nested CCase for any nested constructor patterns.
--   Uses path-based naming (e.g. @__p0@, @__p0_p0@) for fresh variables.
desugarPats :: ConInfoEnv -> Text -> Int -> [Pattern] -> CExpr -> ([Name], CExpr)
desugarPats _ _ _ [] body = ([], body)
desugarPats conInfo prefix idx (p : ps) body =
  let (restVars, restBody) = desugarPats conInfo prefix (idx + 1) ps body
   in case p of
        PVar _ n -> (n : restVars, restBody)
        PWild ->
          let fresh = prefix <> "w" <> show idx
           in (fresh : restVars, restBody)
        PCon _ innerCon innerPats ->
          let fresh = prefix <> "p" <> show idx
              innerTag = maybe 0 fst (M.lookup innerCon conInfo)
              innerPrefix = fresh <> "_"
              (innerVars, innerBody) = desugarPats conInfo innerPrefix 0 innerPats restBody
           in (fresh : restVars, CCase (CVar fresh) [(innerTag, innerVars, innerBody)])

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
