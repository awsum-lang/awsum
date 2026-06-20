-- | The Core simplifier. See [docs/simplify.md](../../docs/simplify.md).
--
-- Coexistence substrate (not full ANF): @CCase@ / @CRowCase@ keep their arm
-- binders. Two layers:
--
--   * a /program-level/ bottom-up round of non-recursive function inlining
--     ('inlineCalls'), declarations visited callees-first so every inlined
--     body is already in its final simplified form, and
--
--   * /local/ rule families run to a per-declaration fixpoint: single-use
--     case-binder inline, case-of-known-constructor, integer const-fold, and
--     the @let@ family (copy-propagation, dead-@let@, single-use-@let@
--     inline, known-projection, @let@-from-scrutinee floating).
--
-- __Single-use binder inline.__ A binder used exactly once inlines into a
-- 'CProj' of the scrutinee at its one use, when the scrutinee is a variable
-- bound to a local or parameter:
--
-- @
--   case s of K [v] -> C[v]      -- v used once as a plain CVar, s a local/param variable
--     ==>
--   case s of K [] -> C[CProj s i]   (binder kept in the list, now unused)
-- @
--
-- The binder is left in the arm's binder list (positions, hence slots, stay
-- stable) but becomes unused; 'Awsum.Lifetime' and the codegens skip a binder
-- unused in its arm body (via 'binderUsedIn'), so the @const v = s[i]@ binding
-- disappears and the field read happens inline at the use.
--
-- A binder is inlined only when it occurs exactly once as a 'CVar' and never
-- as the variable of a 'CProj' / 'CReuse' (those need a name, not an
-- expression) — both facts come from one 'occurrences' walk of the arm body.
--
-- The scrutinee must be a 'CVar' that is /not/ a top-level 'CValDef'. On
-- LLVM/WASM a 'CValDef' reference lowers to a getter /call/ that allocates a
-- fresh cell on every reference (see @borrowedSource@ in "Awsum.Codegen.LLVM"),
-- so a 'CProj' over it would re-invoke the getter — the case match and the
-- projection would read two different cells, and the second leaks. The carve-out
-- is the same boundary @borrowedSource@ already draws. A non-variable scrutinee
-- is left alone for now (a later cut @let@-binds it via 'CLet').
--
-- An arm rebuilding a cell of the scrutinee's arity keeps its binders only
-- when the scrutinee is /reuse-eligible/ ('Awsum.Lifetime.scrutReuseEligible'
-- — a parameter of the enclosing function; row scrutinees never qualify):
-- only there can 'Awsum.Reuse' rewrite the reconstruction in place, which the
-- extracted-binder shape protects. See 'inlineArm'.
--
-- The inline is sound only on the /final/ Core shape — this is why the pass
-- has a single run point, after 'Awsum.Tco'. Its same-arity carve-out
-- (below) reasons about the cells it can see; run before 'Awsum.Cps' /
-- 'Awsum.Scc', those passes later introduce same-arity 'CCon's (continuation
-- cells, argument packs) the carve-out could not anticipate, and
-- 'Awsum.Reuse' then rewrites one of them in place next to the manufactured
-- 'CProj' — the projection reads overwritten slots. (Observed at a trial
-- post-Defunctionalize run point: a @Cons b rest@ inline widened the Cps
-- capture from the field @b@ to the whole cell, and Reuse turned the K cell
-- into @CReuse bytes@ beside @CProj bytes 2@.)
--
-- __Case-of-known-constructor.__ A case whose scrutinee is a literal
-- constructor (or row injection) selects its arm at compile time:
--
-- @
--   case (CCon t fs) of … (t, vs, body) …   ==>   body[vs := fs]
--   case (CRow t v)  of … (t, x,  body) …   ==>   body[x := v]
-- @
--
-- The scrutinee allocation and the dispatch both disappear, and 'Awsum.Reuse'
-- loses nothing — the cell it could have reused is never built. The rewrite
-- fires only when every binder passes the substitution gates (see 'knownArm')
-- and runs /before/ the arm body is simplified: the reverse order would let
-- the inline above manufacture @CProj binder@ names inside the body, and the
-- @usedAsName@ gate would then block the substitution for good.
--
-- The same collapse fires when the scrutinee names a /top-level constant/: a
-- 'CValDef' whose final simplified body is a constructor tree built entirely
-- of constructors and literals ('constValDef'; a plain-'CVar' body chases to
-- its target's registered entry, so alias chains fold too). Only constant
-- trees register — on JVM\/CLR\/JS a 'CValDef' is evaluated once at startup
-- and read per reference, so a substituted field that carried computation
-- would re-run it per execution of the collapse site; a constant tree
-- carries none, has no free names (the capture guard is vacuous), and its
-- materialisation is bounded by 'inlineAlwaysMaxSize'. On LLVM\/WASM, where
-- a 'CValDef' reference is a getter call allocating a fresh cell per
-- reference, the collapse strictly removes allocations. Declarations are
-- visited dependency-first (the 'stronglyConnected' order below; its edges
-- include plain 'CVar' references), so a constant's body is final before any
-- reader is simplified — a 300-constant @and@-chain folds to its final
-- 'Bool' and the constants fall to the tree-shake.
--
-- __Case-of-case fusion.__ A case whose scrutinee is /another/ case fuses:
-- every inner arm whose body is a literal constructor (or a registered
-- top-level constant) has the outer case resolved against it at compile time
-- — the same 'knownArm' gates — and the remaining arms jump to a /join
-- point/ ('CJoin' \/ 'CJump') holding the outer case once:
--
-- @
--   case (case s of A -> True; B -> e) of arms
--     ==>
--   CJoin $j [v] (case v of arms)
--     (case s of A -> \<arms[True], resolved\>; B -> CJump $j [e])
-- @
--
-- Gates ('tryFuseInner'): at least one arm must resolve statically — fusing
-- without a single collapse only restructures; the selected outer arm's own
-- free names must not collide with the inner arm's binders (checked /before/
-- substitution — afterwards the substituted fields legitimately mention
-- them); a static resolution materialises a copy of its outer arm, and the
-- copy count is the selection count plus one whenever a join exists (the
-- body retains the whole outer case) — more than one copy must be small and
-- case-free, or the arm demotes to the jump side, so the case-node count —
-- the termination measure every fusion strictly decreases — never grows;
-- and an unresolved arm whose tails transfer control cannot become a jump
-- argument ('foreignTransferIn') — a transfer is not a value. Outer arms
-- move freely: one carrying a 'CContinue' (or a jump to an enclosing join)
-- only occurs when the fused case sits in the corresponding tail position,
-- so the join body — which every backend keeps inside the function — holds
-- the transfer in a legal position by construction. A tower of
-- literal-armed cases — @and@\/@or@\/@not@ chains over a parameter —
-- re-collapses to a single case per level, so the inliner's size budget
-- never fills and a 300-deep call chain folds end-to-end; a loop dispatch
-- whose outer arm recurses fuses into a join whose body continues the loop.
-- A case whose scrutinee is a residual join consumes it when every value
-- tail of the join resolves against the consumer's arms ('consumeJoin' —
-- all-or-nothing, so a join body never acquires an outward jump, the one
-- shape the expression-position emitters do not lower), which is what lets
-- a tower keep collapsing above its first residual join.
--
-- The minted node leaves the pass as-is: the post-pass tree-shake, the
-- memory passes ('Awsum.Lifetime', 'Awsum.Reuse') and all five codegens
-- handle it natively. The no-simplify differential's Off leg never sees a
-- join (only this pass mints them).
--
-- __Integer const-fold.__ A call to an integer built-in whose operands are
-- all literals is evaluated at compile time ('constFold'):
--
-- @
--   addInt32 2 3            ==>  Right 5
--   addInt32 2147483647 1   ==>  Left (OverflowError : (UnderflowError | OverflowError))
--   succUInt8 255           ==>  Left OverflowError
--   eqUInt32 7 7            ==>  True
-- @
--
-- The result is the /value/ the runtime helper would have built — overflow
-- folds to the same @Left@ the helper returns, never a compile error (errors
-- are values). The payload mirrors each helper's shape exactly: the signed
-- @add@\/@sub@\/@mul@ family injects the error constructor into its
-- two-label row (a 'CRow' carrying the label's FNV-1a tag, the same
-- 'rowTag' the codegen helpers embed), the single-error operations build a
-- bare error constructor. Covered: @add@\/@sub@\/@mul@\/@succ@\/@pred@\/@eq@
-- over the three integer types plus @negInt32@. String built-ins are left
-- alone for now — a folded result 'CString' would sit outside the
-- source-literal length cap, and a concatenation over 21845 UTF-16 code
-- units cannot be carried by a single JVM @CONSTANT_Utf8_info@ entry.
--
-- A folded result is a literal constructor, so case-of-known-constructor
-- picks it up in the same walk: a whole case chain over literal arithmetic
-- collapses to the branch the runtime would have taken.
--
-- __Function inlining.__ A call to a non-recursive function whose body fits
-- the size bound is replaced by the body with the arguments bound in
-- ('inlineCallSite'). Eligibility ('inlinableCallee'): a 'CFunDef' with no
-- 'CLoop' \/ 'CContinue' \/ self-call (post-'Awsum.Tco' that is exactly
-- "non-recursive"), never referenced outside a callee position, and either
-- small ('inlineAlwaysMaxSize') or called from exactly one site
-- ('inlineSingleSiteMaxSize' — the function then disappears entirely via the
-- post-'Awsum.Simplify' tree-shake). The post-'Awsum.Tco' call graph is a
-- DAG ('Awsum.Scc' fused every cycle, 'Awsum.StackSafety' verified, 'Awsum.Tco'
-- folded self-tail-calls into loops), so inlining along it cannot create
-- recursion; declarations are processed callees-first along that DAG, so a
-- callee's registered body is final — and its size honest — by the time its
-- callers are considered.
--
-- Per argument the gates mirror 'knownArm' exactly: an unused parameter
-- drops its argument unevaluated; a parameter used once substitutes any
-- pure argument (an effectful one stays 'CLet'-bound — the single use may
-- sit inside a case arm, where the effect would run conditionally); a
-- parameter used more than once substitutes only a duplicable argument (a
-- non-'CValDef' 'CVar') and otherwise shares the argument through a
-- 'CLet'; a parameter used as the /name/ of a 'CProj' is renamed to the
-- argument variable, or to a fresh 'CLet' binder when the argument is not
-- a plain variable or is spelled like another parameter (this also
-- legalises a 'CValDef' argument — the getter runs once into the binder
-- and the projection reads the local).
-- Every binder of the inlined body is renamed fresh ('freshenBinders'),
-- and the parameter renames run /before/ the argument substitution — a
-- substituted argument may mention a caller variable spelled like a
-- parameter, which a rename over the already-substituted tree would
-- capture — so capture is impossible in both directions and the per-name
-- slot maps of the stack backends stay unambiguous.
--
-- __The @let@ family.__ With the inliner as the first 'CLet' producer, the
-- @let@ rules become live ('finishLet' / the @conEnv@ walk):
--
--   * /dead-let/: a binder with no remaining use drops its right-hand side
--     unevaluated (Core is pure — 'IO' is data);
--   * /single-use-let inline/: one 'CVar' use takes the right-hand side at
--     the same or conditionally lower frequency ('CLoop' only wraps whole
--     function bodies, and no 'CLet' body ever contains one);
--   * /copy-propagation/: a variable right-hand side replaces the binder
--     everywhere, including 'CProj' name positions — gated on non-'CValDef'
--     (a getter reference re-evaluates per use) and on the source name not
--     being re-bound below;
--   * /known-projection/: @CProj n i@ over a visible @CLet n (CCon t fs)@
--     takes field @i@ directly when every field is a duplicable variable —
--     use counts on @n@ then fall, and the dead-let \/ single-use rules
--     collapse the cell on the next fixpoint iteration (@fst (Tuple2 a b)@
--     ends as @a@, allocation gone);
--   * /let-from-scrutinee floating/: @case (let x = e in b) of …@ floats to
--     @let x = e in case b of …@, exposing @b@ to case-of-known-constructor.
module Awsum.Simplify (simplifyProgram) where

import Awsum.CallGraph (containsSelfCall, declName, stronglyConnected)
import Awsum.Core
import Awsum.HM (rowTag)
import Awsum.Lifetime (scrutReuseEligible, soleScrutineeUse)
import Awsum.Syntax (Name, Type' (TyCon), noSpan)
import Data.Char (isDigit)
import Data.Graph qualified as G
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Relude

-- | Bodies at most this many Core nodes inline at every call site.
inlineAlwaysMaxSize :: Int
inlineAlwaysMaxSize = 16

-- | Bodies at most this many Core nodes inline when the whole program
--   contains exactly one call to them — the definition then falls to the
--   tree-shake, so the rewrite never grows the program.
inlineSingleSiteMaxSize :: Int
inlineSingleSiteMaxSize = 128

-- | Run the simplifier over the program: one bottom-up function-inlining
--   round over the declarations in callees-first order (reverse topological
--   over the post-'Awsum.Tco' call DAG), each declaration also taken to a
--   fixpoint of the local rules. Termination of the local fixpoint: every
--   productive rewrite strictly shrinks a finite measure (known-case removes
--   a case node; the inlines remove a 'CVar' occurrence or a call node; the
--   @let@ rules remove a 'CLet' or a 'CProj'; the float strictly lowers the
--   number of 'CLet's in scrutinee position without adding nodes).
--
--   The set of top-level 'CValDef' names is threaded in so no rule puts a
--   getter reference behind a projection or duplicates it (see the module
--   header); the constant 'CValDef' bodies registered so far ('constValDef')
--   feed the case-over-constant collapse; the 'PreludeTags' give 'constFold'
--   the constructor tags of the @Either@ \/ @Bool@ \/ error cells it builds —
--   the same table the codegen runtime helpers read. Output declaration order
--   is the input order.
simplifyProgram :: PreludeTags -> CoreProgram -> CoreProgram
simplifyProgram pt prog@(CoreProgram ds) =
  let valDefs = Set.fromList [n | CValDef n _ <- ds]
      refs = programRefs prog
      sccs = stronglyConnected prog
      cyclic = Set.fromList [n | G.CyclicSCC ns <- sccs, n <- ns]
      order = concatMap G.flattenSCC sccs
      declByName = Map.fromList [(declName d, d) | d <- ds]
      step (acc, env, vals) n = case Map.lookup n declByName of
        Nothing -> pure (acc, env, vals)
        Just d -> do
          d' <- simplifyDecl pt valDefs vals env d
          let env' = case d' of
                CFunDef f ps body
                  | inlinableCallee refs cyclic f body ->
                      Map.insert f (InlineInfo ps body) env
                _ -> env
              vals' = case d' of
                CValDef v body
                  | Just c <- constValDef vals body -> Map.insert v c vals
                _ -> vals
          pure (Map.insert n d' acc, env', vals')
      (finalDecls, _, _) =
        evalState (foldlM step (Map.empty, Map.empty, Map.empty) order) 0
   in CoreProgram [Map.findWithDefault d (declName d) finalDecls | d <- ds]

-- | Is this just-simplified 'CValDef' body registrable for the
--   case-over-constant collapse? Either an alias — a plain 'CVar' whose
--   target is already registered (chased to that entry, so an alias chain
--   folds to one constant) — or a constructor tree built entirely of
--   constructors and literals, topped by the only shapes a case scrutinises
--   ('CCon' \/ 'CRow'), within the inliner's always-inline size policy.
--   Nothing with any computation inside — no call, no variable, no case:
--   substituting such a field would re-run it per execution of the collapse
--   site, where the managed backends evaluated the 'CValDef' once at startup
--   (the module header has the full frequency argument).
constValDef :: Map Name CExpr -> CExpr -> Maybe CExpr
constValDef vals = \case
  CVar m -> Map.lookup m vals
  e@(CCon _ fs) | all constTree fs, exprSize e <= inlineAlwaysMaxSize -> Just e
  e@(CRow _ v) | constTree v, exprSize e <= inlineAlwaysMaxSize -> Just e
  _ -> Nothing
  where
    constTree = \case
      CCon _ fs -> all constTree fs
      CRow _ v -> constTree v
      CIntLit _ _ -> True
      CString _ -> True
      _ -> False

-- | A registered inline candidate: parameter list + final simplified body.
data InlineInfo = InlineInfo [Name] CExpr

-- | May calls to this function be replaced by its body? Non-recursive only
--   — no 'CLoop' \/ 'CContinue' (post-'Awsum.Tco' self-recursion), no
--   residual self-call, not a member of a call-graph cycle (defensive: the
--   pipeline leaves none) — never referenced outside a callee position, and
--   within the size policy ('inlineAlwaysMaxSize' \/
--   'inlineSingleSiteMaxSize'). Call-site counts come from one pre-round
--   walk; processing callers after callees keeps a single-site decision
--   consistent, because only inlining into a /later/ declaration could copy
--   a call site, and by then the callee's own decision is already made.
inlinableCallee :: Map Name (Int, Int) -> Set Name -> Name -> CExpr -> Bool
inlinableCallee refs cyclic f body =
  let (calleeUses, otherUses) = Map.findWithDefault (0, 0) f refs
      size = exprSize body
   in not (Set.member f cyclic)
        && not (hasLoopOrContinue body)
        && not (containsSelfCall f body)
        && otherUses
        == 0
        && (size <= inlineAlwaysMaxSize || (calleeUses == 1 && size <= inlineSingleSiteMaxSize))

-- | One declaration: local fixpoint, then the inlining walk, then the local
--   fixpoint again over whatever the substitution exposed. The first
--   fixpoint runs before inlining so literal cases collapse first and no
--   body is inlined into an arm a later rewrite would discard.
simplifyDecl :: PreludeTags -> Set Name -> Map Name CExpr -> Map Name InlineInfo -> CDecl -> State Int CDecl
simplifyDecl pt valDefs vals env = \case
  CFunDef n ps body -> CFunDef n ps <$> pipeline ps body
  CValDef n rhs -> CValDef n <$> pipeline [] rhs
  where
    pipeline ps e = do
      e1 <- fixpoint ps e
      e2 <- inlineCalls valDefs env e1
      if e2 == e1 then pure e1 else fixpoint ps e2
    fixpoint ps e = do
      e' <- simplifyExpr pt ps valDefs vals e
      if e' == e then pure e else fixpoint ps e'

-- | One bottom-up walk, with one exception to the order: a known-constructor
--   scrutinee — literal, or a 'CVar' naming a registered constant 'CValDef'
--   (@vals@) — rewrites the /raw/ arm body first and recurses into the result
--   (see the module header for why). The 'CVar'-scrutinee check and the
--   value-def carve-out for the projection inline both live here, as does
--   the case-of-case dispatch: a scrutinee that simplifies to a case
--   attempts 'tryFuseInner' (which mints join names, hence 'State Int') and
--   falls back to plain arm recursion when the fusion gates fail.
--
--   The walk threads @conEnv@: for every in-scope @CLet n (CCon _ fs)@ whose
--   fields are all duplicable variables (and whose names — including @n@ —
--   are not re-bound below), the fields are recorded so a @CProj n i@ can
--   take field @i@ directly (known-projection). The duplicability gate makes
--   the substitution free — a variable read adds no work — while the cell
--   itself stays until the falling use counts let dead-let remove it. The
--   bindings visible at a 'CJoin' scope over both its branches, so @conEnv@
--   flows into the join body and the inner expression alike.
simplifyExpr :: PreludeTags -> [Name] -> Set Name -> Map Name CExpr -> CExpr -> State Int CExpr
simplifyExpr pt params valDefs vals = go Set.empty Map.empty
  where
    -- @sk@ — binders bound above whose sole use is an inner case's
    -- scrutinee: 'Awsum.Lifetime' sinks their drop into that case's arms
    -- ('soleScrutineeUse'), making the cell a reuse target there, so the
    -- same-arity carve-out treats them like parameters.
    go :: Set Name -> Map Name [CExpr] -> CExpr -> State Int CExpr
    go sk conEnv = \case
      CCase scrut alts -> do
        scrut' <- go sk conEnv scrut
        let elig = \case
              CVar m -> scrutReuseEligible params m || Set.member m sk
              _ -> False
            armsDefault s = finishCase (elig s) s =<< traverse (\(t, vs, b) -> (t,vs,) <$> go (sinkExtend vs b sk) conEnv b) alts
            fuseOr s =
              tryFuseInner (nominalOuter valDefs vals alts) s >>= \case
                Just fused -> go sk conEnv fused
                Nothing -> armsDefault s
        case scrut' of
          CCon tag fs
            | Just body <- knownNominal valDefs tag fs alts -> go sk conEnv body
          CLet x rhs inner
            | letFloatOkFromScrut x [(vs, b) | (_, vs, b) <- alts] ->
                go sk conEnv (CLet x rhs (CCase inner alts))
          s@CCase {} -> fuseOr s
          s@CRowCase {} -> fuseOr s
          s@(CJoin j ps jbody jinner)
            | Just (jbody', jinner') <- consumeJoin (nominalOuter valDefs vals alts) jbody jinner ->
                go sk conEnv (CJoin j ps jbody' jinner')
            | otherwise -> armsDefault s
          s@(CVar n)
            | Just (CCon tag fs) <- Map.lookup n vals,
              Just body <- knownNominal valDefs tag fs alts ->
                go sk conEnv body
            | not (Set.member n valDefs) ->
                finishCase (elig s) s =<< traverse (\(t, vs, b) -> (t,vs,) . inlineArm (elig s) n (zip vs [0 ..]) . identityRecon n t vs <$> go (sinkExtend vs b sk) conEnv b) alts
          s -> armsDefault s
      CRowCase scrut alts -> do
        scrut' <- go sk conEnv scrut
        let armsDefault s = finishRowCase s =<< traverse (\(t, v, b) -> (t,v,) <$> go (sinkExtend [v] b sk) conEnv b) alts
            fuseOr s =
              tryFuseInner (rowOuter valDefs vals alts) s >>= \case
                Just fused -> go sk conEnv fused
                Nothing -> armsDefault s
        case scrut' of
          CRow tag v
            | Just body <- knownRow valDefs tag v alts -> go sk conEnv body
          CLet x rhs inner
            | letFloatOkFromScrut x [([v], b) | (_, v, b) <- alts] ->
                go sk conEnv (CLet x rhs (CRowCase inner alts))
          s@CCase {} -> fuseOr s
          s@CRowCase {} -> fuseOr s
          s@(CJoin j ps jbody jinner)
            | Just (jbody', jinner') <- consumeJoin (rowOuter valDefs vals alts) jbody jinner ->
                go sk conEnv (CJoin j ps jbody' jinner')
            | otherwise -> armsDefault s
          s@(CVar n)
            | Just (CRow tag v) <- Map.lookup n vals,
              Just body <- knownRow valDefs tag v alts ->
                go sk conEnv body
            | not (Set.member n valDefs) ->
                -- Row scrutinees are never reuse-eligible ('Awsum.Reuse'
                -- descends through 'CRowCase' without matching), so the
                -- same-arity carve-out never applies here.
                finishRowCase s =<< traverse (\(t, v, b) -> (t,v,) . inlineArm False n [(v, 0)] . identityRowRecon n t v <$> go (sinkExtend [v] b sk) conEnv b) alts
          s -> armsDefault s
      CCall f xs -> do
        f' <- go sk conEnv f
        args <- traverse (go sk conEnv) xs
        case f' of
          CBuiltIn op
            | Just folded <- constFold pt op args -> pure folded
          _ -> pure (CCall f' args)
      CCon t fs -> CCon t <$> traverse (go sk conEnv) fs
      CRow t v -> CRow t <$> go sk conEnv v
      CLoop b -> CLoop <$> go sk conEnv b
      CContinue xs -> CContinue <$> traverse (go sk conEnv) xs
      CLet n rhs b -> do
        rhs' <- go sk conEnv rhs
        let conEnv' = case knownCellFields valDefs n rhs' b of
              Just fs -> Map.insert n fs conEnv
              Nothing -> conEnv
        finishLet valDefs n rhs' <$> go (sinkExtend [n] b sk) conEnv' b
      CDrop n b -> CDrop n <$> go sk conEnv b
      CReuse rm n t fs -> CReuse rm n t <$> traverse (go sk conEnv) fs
      CJoin j ps body inner -> CJoin j ps <$> go sk conEnv body <*> go sk conEnv inner
      CJump j args -> CJump j <$> traverse (go sk conEnv) args
      e@(CProj n i)
        | Just fs <- Map.lookup n conEnv, Just f <- fs !!? (i - 1) -> pure f
        | otherwise -> pure e
      e@(CVar _) -> pure e
      e@(CString _) -> pure e
      e@(CIntLit _ _) -> pure e
      e@(CBuiltIn _) -> pure e

-- | Eliminate or keep a constructed case whose arms are already
--   simplified. When every arm body is the same expression — one arm
--   trivially qualifies — the dispatch decides nothing and the case
--   collapses to that body, dropping the scrutinee with its computation
--   (the established dead-computation stance of dead-let and unused
--   inline arguments; a scrutinee is a value position, so it is
--   transfer-free and self-contained — a scrutinee-'CJoin' dies with its
--   own jumps). Identical transfer bodies are fine: the collapsed body
--   inherits the case's position. Four gates: the scrutinee must not be
--   effectful ('effectfulIn' — @runIO@'s @case (print s) of Unit -> …@ is
--   exactly this shape, and the call is the effect); no arm binder may be
--   read by the body (two syntactically equal bodies reading their own
--   arms' binders are not semantically equal — the deterministic @__p0@
--   names repeat across arms and bind different fields); when the
--   scrutinee is reuse-eligible (@reuseable@, resolved at the dispatch
--   site: a parameter or a sink-eligible binder — same gate single-use
--   inlining honours), no field-binding arm may rebuild a cell of its own
--   arity (collapsing would starve 'Awsum.Reuse' of the linear-scrutinee
--   shape and a hot loop would allocate again; binder-less arms are
--   exempt, see 'collapseIdentical'); and an empty case (uninhabited
--   scrutinee) stays.
finishCase :: Bool -> CExpr -> [(Int, [Name], CExpr)] -> State Int CExpr
finishCase reuseable scrut alts =
  fromMaybe (pure (CCase scrut alts)) (collapseIdentical reuseable scrut [(vs, b) | (_, vs, b) <- alts])

-- | Extend the sink-eligibility set with the binders of one arm (or one
--   @let@) whose sole use in @b@ is an inner case's scrutinee — the shape
--   whose drop 'Awsum.Lifetime.insertDrops' sinks into that case's arms
--   ('Awsum.Lifetime.soleScrutineeUse' is the shared predicate).
sinkExtend :: [Name] -> CExpr -> Set Name -> Set Name
sinkExtend vs b sk =
  foldl' (\acc v -> if soleScrutineeUse v b then Set.insert v acc else acc) sk vs

-- | Row form of 'finishCase'. A row scrutinee is never a reuse target
--   ('Awsum.Reuse' descends through 'CRowCase' without matching), so the
--   same-arity gate never applies.
finishRowCase :: CExpr -> [(Word32, Name, CExpr)] -> State Int CExpr
finishRowCase scrut alts =
  fromMaybe (pure (CRowCase scrut alts)) (collapseIdentical False scrut [([v], b) | (_, v, b) <- alts])

-- | The shared check of 'finishCase' / 'finishRowCase': the common body,
--   when the arms have one and the gates pass. A pure scrutinee is dropped
--   with the dispatch; an effectful one keeps evaluating — the dispatch
--   alone goes, the call sequenced before the body through a dead 'CLet'
--   that 'finishLet''s effect gate then preserves. @runIO@'s print arm —
--   @case (print s) of Unit -> next@ — is exactly that: the print stays,
--   the single-arm switch around it disappears.
collapseIdentical :: Bool -> CExpr -> [([Name], CExpr)] -> Maybe (State Int CExpr)
collapseIdentical reuseable scrut = \case
  arms@((_, b0) : rest)
    | all ((== b0) . snd) rest,
      all (\(vs, _) -> not (any (`binderUsedIn` b0) vs)) arms,
      -- Keep the case when the scrutinee is reuse-eligible (@reuseable@ —
      -- 'scrutReuseEligible' at the caller) and some arm is a 'reuseTargetArm':
      -- its drop is a linear-scrutinee cell 'Awsum.Reuse' would rewrite in
      -- place, which collapsing the dispatch would starve. Binder-less arms
      -- are never targets, so the boolean absorbing elements (@and x False@,
      -- @or x True@, a 300-arm @-> True@ extractor) still collapse.
      not reuseable || not (any (\(vs, _) -> reuseTargetArm (length vs) b0) arms) ->
        Just
          $ if effectfulIn scrut
            then (\e -> CLet e scrut b0) <$> freshName "eff"
            else pure b0
  _ -> Nothing

-- | May @case (let x = rhs in inner) of alts@ float to
--   @let x = rhs in case inner of alts@? Sound whenever @x@ is not already
--   free in any arm (the floated binding would capture it). Arms are given
--   as (binders, body) so the row and nominal forms share the check. Pure
--   Core makes the evaluation-order change unobservable; the float exposes
--   @inner@ to case-of-known-constructor.
letFloatOkFromScrut :: Name -> [([Name], CExpr)] -> Bool
letFloatOkFromScrut x alts =
  x `Set.notMember` foldMap (\(vs, b) -> freeNames b `Set.difference` Set.fromList vs) alts

-- | Is @CLet n rhs body@ a registrable known cell for known-projection —
--   @rhs@ a literal constructor whose fields are all duplicable variables,
--   with neither the field names nor @n@ re-bound anywhere in @body@ (the
--   deterministic-@__p0@ shadowing hazard again)? Returns the fields.
knownCellFields :: Set Name -> Name -> CExpr -> CExpr -> Maybe [CExpr]
knownCellFields valDefs n rhs body = case rhs of
  CCon _ fs -> do
    names <- traverse fieldVar fs
    let bound = boundNamesIn body
    guard (n `Set.notMember` bound)
    guard (all (`Set.notMember` bound) names)
    pure fs
  _ -> Nothing
  where
    fieldVar = \case
      CVar v | not (Set.member v valDefs) -> Just v
      _ -> Nothing

-- | Eliminate or keep a simplified @CLet@. In gate order: a binder with no
--   use at all drops its right-hand side unevaluated (dead-let; Core is
--   pure); a single plain-'CVar' use takes the right-hand side at the same
--   or conditionally lower frequency (no 'CLet' body contains a 'CLoop' —
--   loops only wrap whole function bodies — so no use site is hotter than
--   the binding was); a variable right-hand side propagates into every use
--   including 'CProj' \/ 'CReuse' name positions (copy-propagation), gated
--   on non-'CValDef' (a getter re-evaluates per reference) and on the source
--   name not being re-bound in the body. Capture guards as in 'knownArm'.
finishLet :: Set Name -> Name -> CExpr -> CExpr -> CExpr
finishLet valDefs n rhs body =
  case Map.findWithDefault (0, False) n (occurrences body) of
    -- An effectful right-hand side must keep evaluating even unused
    -- ('effectfulIn'); the fall-through keeps the binding. The same gate
    -- holds the single-use inline: the one use may sit inside a case arm,
    -- and substituting an effectful right-hand side there would demote the
    -- effect to that arm's frequency.
    (0, False) | not (effectfulIn rhs) -> body
    (1, False)
      | not (effectfulIn rhs),
        Set.disjoint (freeNames rhs) (boundNamesIn body) ->
          substVars (Map.fromList [(n, rhs)]) body
    _ -> case rhs of
      CVar v
        | not (Set.member v valDefs),
          v `Set.notMember` boundNamesIn body ->
            renameVarFull n v body
      _ -> CLet n rhs body

-- ════════════════════════════════════════════════════════════════════════════
-- Case-of-case fusion
-- ════════════════════════════════════════════════════════════════════════════

-- | The consuming (outer) case of a case-of-case, abstracted over its
--   nominal/row form so 'tryFuseInner' is written once. @ocResolve@ takes
--   the inner arm's binders and its body; when the body is a literal
--   constructor (or chases to a registered constant), it picks the outer
--   arm the runtime would pick and substitutes through 'knownArm' — the
--   returned key identifies the selected outer arm for the duplication
--   gate, which @ocArmBody@ serves. @ocRebuild@ places the outer case over
--   a fresh scrutinee as the join body.
data OuterCase = OuterCase
  { ocResolve :: [Name] -> CExpr -> Maybe (Either Int Word32, CExpr),
    ocArmBody :: Either Int Word32 -> Maybe CExpr,
    ocRebuild :: CExpr -> CExpr,
    -- | Does any outer arm jump to an enclosing join ('jumpsOutwardIn')?
    --   Such arms occur when the fused case sits in a tail of that join's
    --   inner expression — legal Core — but moving them into a /minted/
    --   join's body would make a join body that jumps outward, the one
    --   shape the expression-position emitters do not lower (the same
    --   boundary 'consumeJoin' draws). The jump side of 'tryFuseInner' is
    --   gated on this; the all-static side is not (resolved copies stay at
    --   the tails the originals occupied).
    ocJumpsOutward :: Bool
  }

-- | The outer case is nominal (@CCase _ alts@). The capture guard runs on
--   the outer arm body /before/ substitution: its own free names (minus its
--   own binders) must not collide with the inner arm's binders — afterwards
--   the substituted fields legitimately mention them, so the directions
--   would be indistinguishable.
nominalOuter :: Set Name -> Map Name CExpr -> [(Int, [Name], CExpr)] -> OuterCase
nominalOuter valDefs vals alts =
  OuterCase
    { ocResolve = \innerBinders body -> do
        (tag, fs) <- conView vals body
        (ovs, ob) <- listToMaybe [(ovs, ob) | (t, ovs, ob) <- alts, t == tag]
        guard (length ovs == length fs)
        guard (Set.disjoint (freeNames ob `Set.difference` Set.fromList ovs) (Set.fromList innerBinders))
        rb <- knownArm valDefs (zip ovs fs) ob
        pure (Left tag, rb),
      ocArmBody = \case
        Left tag -> listToMaybe [ob | (t, _, ob) <- alts, t == tag]
        Right _ -> Nothing,
      ocRebuild = (`CCase` alts),
      ocJumpsOutward = any (\(_, _, ob) -> jumpsOutwardIn ob) alts
    }

-- | The outer case is a row case (@CRowCase _ alts@).
rowOuter :: Set Name -> Map Name CExpr -> [(Word32, Name, CExpr)] -> OuterCase
rowOuter valDefs vals alts =
  OuterCase
    { ocResolve = \innerBinders body -> do
        (tag, payload) <- rowView vals body
        (ov, ob) <- listToMaybe [(ov, ob) | (t, ov, ob) <- alts, t == tag]
        guard (Set.disjoint (Set.delete ov (freeNames ob)) (Set.fromList innerBinders))
        rb <- knownArm valDefs [(ov, payload)] ob
        pure (Right tag, rb),
      ocArmBody = \case
        Right tag -> listToMaybe [ob | (t, _, ob) <- alts, t == tag]
        Left _ -> Nothing,
      ocRebuild = (`CRowCase` alts),
      ocJumpsOutward = any (\(_, _, ob) -> jumpsOutwardIn ob) alts
    }

-- | A literal constructor view of an expression — direct, or chased through
--   a registered top-level constant (the same lookup the case-over-constant
--   collapse uses, so the two rules accept the same scrutinee shapes).
conView :: Map Name CExpr -> CExpr -> Maybe (Int, [CExpr])
conView vals = \case
  CCon t fs -> Just (t, fs)
  CVar n | Just (CCon t fs) <- Map.lookup n vals -> Just (t, fs)
  _ -> Nothing

-- | Row form of 'conView'.
rowView :: Map Name CExpr -> CExpr -> Maybe (Word32, CExpr)
rowView vals = \case
  CRow t v -> Just (t, v)
  CVar n | Just (CRow t v) <- Map.lookup n vals -> Just (t, v)
  _ -> Nothing

-- | Case-of-case fusion (see the module header). The scrutinee is itself a
--   case; per inner arm, the outer case either resolves statically
--   (@ocResolve@ succeeded and the duplication gate holds) or the arm jumps
--   to a join holding the outer case once. Nothing — the case stays as it
--   is — when no arm resolves at all. Outer arms move into the join body
--   freely: a transfer in one ('CContinue', a jump to an enclosing join)
--   only occurs when the fused case sits in the corresponding tail
--   position, so the body — kept inside the function by every backend —
--   holds it in a legal position by construction.
--
--   The duplication gate: a static resolution materialises a copy of its
--   selected outer arm — the copy count is the selection count, plus one
--   whenever a join exists, because the join body retains the whole outer
--   case, every arm included. More than one copy must be small
--   ('inlineAlwaysMaxSize') and case-free — fusion's termination measure is
--   the case-node count, which removing the outer case strictly decreases
--   only if no duplicated copy carries a case; and an outer arm holding a
--   @do@-chain continuation would otherwise double per bind level (the
--   int32_parse 2^12 blowup: substituted copy + join-body copy at every
--   level). An arm whose selected outer arm fails the gate is demoted to
--   the jump side (the literal travels as the jump argument and dispatches
--   at runtime, exactly as it did before the fusion), not a reason to
--   abort; a fusion left with no static arm at all is not performed.
tryFuseInner :: OuterCase -> CExpr -> State Int (Maybe CExpr)
tryFuseInner outer = \case
  CCase is ialts ->
    fuseArms
      [(vs, b) | (_, vs, b) <- ialts]
      (CCase is . zipWith (\(t, vs, _) b' -> (t, vs, b')) ialts)
  CRowCase is ialts ->
    fuseArms
      [([v], b) | (_, v, b) <- ialts]
      (CRowCase is . zipWith (\(t, v, _) b' -> (t, v, b')) ialts)
  _ -> pure Nothing
  where
    fuseArms :: [([Name], CExpr)] -> ([CExpr] -> CExpr) -> State Int (Maybe CExpr)
    fuseArms arms rebuild = do
      let plans = [(b, ocResolve outer vs b) | (vs, b) <- arms]
          selKeys = [k | (_, Just (k, _)) <- plans]
          dupOk jumpExists k =
            (not jumpExists && length (filter (== k) selKeys) <= 1)
              || maybe
                False
                (\ob -> exprSize ob <= inlineAlwaysMaxSize && not (containsCase ob))
                (ocArmBody outer k)
          gateWith jumpExists = [(b, p >>= \(k, rb) -> rb <$ guard (dupOk jumpExists k)) | (b, p) <- plans]
          jump0 = any (isNothing . snd) plans
          final0 = gateWith jump0
          -- A demotion creates the jump that re-prices every single-selection
          -- copy; the flag is boolean-monotone, so one re-gate reaches the
          -- fixpoint.
          final
            | not jump0 && any (isNothing . snd) final0 = gateWith True
            | otherwise = final0
          nStatic = length [() | (_, Just _) <- final]
          needJump = any (isNothing . snd) final
          -- A non-resolved arm becomes the /argument/ of its jump — a value
          -- position. An arm whose tails transfer control (a 'CJump' to an
          -- enclosing join, a 'CContinue' to the enclosing loop) cannot move
          -- there: a transfer is not a value. Statically-resolved arms are
          -- literal trees and carry none.
          jumpArmsOk = all (\(b, rb) -> isJust rb || not (foreignTransferIn b)) final
      if nStatic == 0 || (needJump && (not jumpArmsOk || ocJumpsOutward outer))
        then pure Nothing
        else do
          -- A resolved copy may bind names (a 'CLet' an earlier inline left
          -- in the selected outer arm). Materialising it beside the join
          -- body's original — or beside a sibling copy selecting the same
          -- arm — would declare one binder at two sites in one declaration,
          -- which the binder-name uniqueness the stack backends' slot maps
          -- rely on (JVM 'namedSlotAssignments') rejects. Freshen each copy.
          final' <- traverse (\(b, mrb) -> (b,) <$> traverse freshenBinders mrb) final
          if not needJump
            then pure (Just (rebuild [rb | (_, Just rb) <- final']))
            else do
              j <- freshJoinName
              v <- freshName "scrut"
              let bodies = [fromMaybe (CJump j [b]) rb | (b, rb) <- final']
              pure (Just (CJoin j [v] (ocRebuild outer (CVar v)) (rebuild bodies)))

-- | Case-of-join: the consuming case of a scrutinee-'CJoin' resolves
--   against every value tail of the join — its body's and its inner
--   expression's — or not at all. Each leaf tail must be a literal
--   constructor tree (or chase to a registered constant) whose selected
--   consumer arm passes the same 'ocResolve' gates as the fusion's static
--   arms plus the strict duplication pricing (several tails may select one
--   arm: small and case-free, or no deal); the substituted arm lands at the
--   tail's own position, so the capture guard runs against the binders the
--   path from the node re-binds (the deterministic @__p0@ names repeat
--   within a declaration). All-or-nothing is what keeps the join's shape
--   inside what every backend emits: a partial push would need the
--   leftover tails to jump to a fresh consumer join — a join whose body
--   jumps outward, the one shape the expression-position emitters do not
--   lower (their bodies are values; only the statement walks route
--   arbitrary transfers). A declined consumer stays where it was — a case
--   over the join node, today's emittable form — and a transfer tail
--   ('CJump', 'CContinue') passes through untouched: its value never
--   reaches the consumer. This is what lets a tower keep collapsing above
--   its first residual join: the level above it folds into the join's
--   tails, and the next level then sees a join again.
consumeJoin :: OuterCase -> CExpr -> CExpr -> Maybe (CExpr, CExpr)
consumeJoin oc jbody jinner = (,) <$> goT Set.empty jbody <*> goT Set.empty jinner
  where
    goT bound = \case
      CCase s alts -> CCase s <$> traverse (\(t, vs, b) -> (t,vs,) <$> goT (bound <> Set.fromList vs) b) alts
      CRowCase s alts -> CRowCase s <$> traverse (\(t, v, b) -> (t,v,) <$> goT (Set.insert v bound) b) alts
      CLet x rhs b -> CLet x rhs <$> goT (Set.insert x bound) b
      CJoin j2 ps2 b2 i2 -> CJoin j2 ps2 <$> goT (bound <> Set.fromList ps2) b2 <*> goT bound i2
      -- Not produced before 'Awsum.Lifetime'; decline rather than reason
      -- about a shape this pass never sees.
      CDrop {} -> Nothing
      e@(CJump _ _) -> Just e
      e@(CContinue _) -> Just e
      CLoop _ -> Nothing
      e@(CVar _) -> resolveLeaf bound e
      e@(CCon _ _) -> resolveLeaf bound e
      e@(CRow _ _) -> resolveLeaf bound e
      e@(CCall _ _) -> resolveLeaf bound e
      e@(CReuse {}) -> resolveLeaf bound e
      e@(CProj _ _) -> resolveLeaf bound e
      e@(CString _) -> resolveLeaf bound e
      e@(CIntLit _ _) -> resolveLeaf bound e
      e@(CBuiltIn _) -> resolveLeaf bound e
    resolveLeaf bound v = do
      (key, rb) <- ocResolve oc (Set.toList bound) v
      ob <- ocArmBody oc key
      -- Binder-free on top of small and case-free: several tails may select
      -- one consumer arm, and this pure walk cannot freshen per copy — a
      -- 'CLet'-bearing arm materialised twice would declare one binder at
      -- two sites in the declaration.
      guard (exprSize ob <= inlineAlwaysMaxSize && not (containsCase ob) && Set.null (boundNamesIn ob))
      -- The consumer may itself sit in an enclosing join's inner tail, so
      -- its arms can legally end in a transfer (a 'CJump' there, or a
      -- 'CContinue' in a loop) — but substituting such an arm into THIS
      -- join's body tails would give the body an outward transfer, the one
      -- shape the expression-position emitters do not lower. Declining
      -- keeps the consumer where it was: a case over the join node inside
      -- the enclosing join's tail — arm-root jumps over a self-contained
      -- scrutinee, the form every backend already emits.
      guard (not (foreignTransferIn ob))
      pure rb

-- | Does the expression transfer control out of itself — a 'CContinue' (its
--   'CLoop' wraps the whole function body, always outside), or a 'CJump' to
--   a join not declared within the expression? A complete nested 'CJoin' is
--   self-contained: jumps to it stay legal wherever the whole node moves.
--   Gates the jump side of 'tryFuseInner' — a transfer is not a value, so
--   it cannot move into a jump's argument position.
foreignTransferIn :: CExpr -> Bool
foreignTransferIn = go Set.empty
  where
    go declared = \case
      CContinue _ -> True
      CJump j args -> j `Set.notMember` declared || any (go declared) args
      CJoin j _ body inner -> go declared body || go (Set.insert j declared) inner
      CLoop b -> go declared b
      CCall f xs -> go declared f || any (go declared) xs
      CCon _ fs -> any (go declared) fs
      CRow _ v -> go declared v
      CCase s alts -> go declared s || any (\(_, _, b) -> go declared b) alts
      CRowCase s alts -> go declared s || any (\(_, _, b) -> go declared b) alts
      CLet _ rhs b -> go declared rhs || go declared b
      CDrop _ b -> go declared b
      CReuse _ _ _ fs -> any (go declared) fs
      CVar _ -> False
      CProj _ _ -> False
      CString _ -> False
      CIntLit _ _ -> False
      CBuiltIn _ -> False

-- | Does the expression jump to a join declared outside itself? Unlike
--   'foreignTransferIn', a 'CContinue' does not count: a loop transfer
--   occurs only when the fused case sits in loop-tail position, where every
--   backend walks the minted join's body with its full tail emitter. An
--   outward jump is different — its target join may itself sit in
--   expression position, and a minted join whose body jumps outward is the
--   one shape the expression-position emitters do not lower. Gates the
--   join-minting side of 'tryFuseInner' via 'ocJumpsOutward'.
jumpsOutwardIn :: CExpr -> Bool
jumpsOutwardIn = go Set.empty
  where
    go declared = \case
      CJump j args -> j `Set.notMember` declared || any (go declared) args
      CJoin j _ body inner -> go declared body || go (Set.insert j declared) inner
      CContinue xs -> any (go declared) xs
      CLoop b -> go declared b
      CCall f xs -> go declared f || any (go declared) xs
      CCon _ fs -> any (go declared) fs
      CRow _ v -> go declared v
      CCase s alts -> go declared s || any (\(_, _, b) -> go declared b) alts
      CRowCase s alts -> go declared s || any (\(_, _, b) -> go declared b) alts
      CLet _ rhs b -> go declared rhs || go declared b
      CDrop _ b -> go declared b
      CReuse _ _ _ fs -> any (go declared) fs
      CVar _ -> False
      CProj _ _ -> False
      CString _ -> False
      CIntLit _ _ -> False
      CBuiltIn _ -> False

-- | Any 'CCase' / 'CRowCase' node anywhere — including inside a 'CJoin',
--   whose body always holds one. The duplication gate of 'tryFuseInner'.
containsCase :: CExpr -> Bool
containsCase = go
  where
    go = \case
      CCase {} -> True
      CRowCase {} -> True
      CJoin {} -> True
      CCall f xs -> go f || any go xs
      CCon _ fs -> any go fs
      CRow _ v -> go v
      CLoop b -> go b
      CContinue xs -> any go xs
      CLet _ rhs b -> go rhs || go b
      CDrop _ b -> go b
      CReuse _ _ _ fs -> any go fs
      CJump _ args -> any go args
      CVar _ -> False
      CProj _ _ -> False
      CString _ -> False
      CIntLit _ _ -> False
      CBuiltIn _ -> False

-- | A fresh join-point name: @$join<k>@. Same counter as 'freshName', its
--   own prefix — join names are labels, not value names, and no other pass
--   mints the prefix, so a 'CJump' resolves unambiguously program-wide.
freshJoinName :: State Int Name
freshJoinName = do
  k <- get
  put (k + 1)
  pure ("$join" <> show k)

-- ════════════════════════════════════════════════════════════════════════════
-- Function inlining
-- ════════════════════════════════════════════════════════════════════════════

-- | Replace every eligible call with the callee's bound body, bottom-up
--   (arguments first, so an inner call inlines before the outer site is
--   considered). Only full-arity direct calls qualify — 'Awsum.Saturate'
--   guarantees there are no others, but a mismatch must miss the rewrite
--   rather than mis-bind.
inlineCalls :: Set Name -> Map Name InlineInfo -> CExpr -> State Int CExpr
inlineCalls valDefs env = go
  where
    go = \case
      CCall f xs -> do
        f' <- go f
        xs' <- traverse go xs
        case f' of
          CVar g
            | Just info@(InlineInfo ps _) <- Map.lookup g env,
              length ps == length xs' ->
                inlineCallSite valDefs info xs'
          _ -> pure (CCall f' xs')
      CCase s alts -> CCase <$> go s <*> traverse (\(t, vs, b) -> (t,vs,) <$> go b) alts
      CRowCase s alts -> CRowCase <$> go s <*> traverse (\(t, v, b) -> (t,v,) <$> go b) alts
      CCon t fs -> CCon t <$> traverse go fs
      CRow t v -> CRow t <$> go v
      CLoop b -> CLoop <$> go b
      CContinue xs -> CContinue <$> traverse go xs
      CLet x rhs b -> CLet x <$> go rhs <*> go b
      CDrop x b -> CDrop x <$> go b
      CReuse rm x t fs -> CReuse rm x t <$> traverse go fs
      CJoin j ps body inner -> CJoin j ps <$> go body <*> go inner
      CJump j args -> CJump j <$> traverse go args
      e@(CVar _) -> pure e
      e@(CProj _ _) -> pure e
      e@(CString _) -> pure e
      e@(CIntLit _ _) -> pure e
      e@(CBuiltIn _) -> pure e

-- | How one argument is bound to its parameter.
data ArgPlan
  = -- | Parameter unused: the argument is dropped unevaluated.
    ADrop
  | -- | Substitute the argument expression for every 'CVar' use.
    ASubst CExpr
  | -- | Rename the parameter to this name in every position (plain uses and
    --   'CProj' \/ 'CReuse' name positions); 'Just' an expression means the
    --   name is a fresh binder and a @CLet name expr@ wraps the result.
    ARename Name (Maybe CExpr)

-- | Inline one call: freshen the body's binders, plan each (parameter,
--   argument) pair with 'knownArm'-mirroring gates (see the module header),
--   apply the substitutions and renames, and wrap the shared arguments in
--   'CLet's in argument order. The freshened binders make capture impossible:
--   the body re-binds no name an argument can mention, and no parameter is
--   ever re-bound.
inlineCallSite :: Set Name -> InlineInfo -> [CExpr] -> State Int CExpr
inlineCallSite valDefs (InlineInfo ps body) args = do
  body' <- freshenBinders body
  let occ = occurrences body'
  plans <- forM (zip ps args) $ \(p, arg) ->
    case Map.findWithDefault (0, False) p occ of
      -- The parameter is a 'CProj' / 'CReuse' name somewhere: the binding
      -- must stay a /name/. A plain non-'CValDef' variable argument renames
      -- straight to it — unless it is spelled like another parameter, which
      -- the rename pass below would then hit ('renameVarFull' has no scope
      -- to tell them apart); anything else — including a 'CValDef'
      -- reference, whose getter must not re-run per projection (the
      -- @borrowedSource@ boundary; the extra cells would leak) — binds to a
      -- fresh 'CLet' binder, so the getter runs once and the projections
      -- read the local.
      (_, True) -> case arg of
        CVar v | not (Set.member v valDefs), v `notElem` ps -> pure (p, ARename v Nothing)
        _ -> do
          x <- freshName p
          pure (p, ARename x (Just arg))
      -- An effectful argument must keep evaluating even unused
      -- ('effectfulIn'); the fall-through shares it through a 'CLet'.
      (0, False) | not (effectfulIn arg) -> pure (p, ADrop)
      -- A single use may sit inside one arm of a case in the body, so an
      -- effectful argument must not substitute there — the effect would
      -- run only when that arm is selected. The fall-through binds it
      -- through a 'CLet', evaluated unconditionally in argument order
      -- (and 'finishLet''s own effect gate keeps that 'CLet' in place).
      (1, False) | not (effectfulIn arg) -> pure (p, ASubst arg)
      (_, False)
        | duplicableArg arg -> pure (p, ASubst arg)
        | otherwise -> do
            x <- freshName p
            pure (p, ARename x (Just arg))
  let substMap = Map.fromList [(p, e) | (p, ASubst e) <- plans]
      renames = [(p, t) | (p, ARename t _) <- plans]
      lets = [(t, a) | (_, ARename t (Just a)) <- plans]
      -- Renames run /before/ the substitution: a substituted argument may
      -- mention a caller variable spelled like a parameter (parameter
      -- names are not freshened — they are exactly what the body's
      -- references target), and a rename over the already-substituted tree
      -- would capture those references ('and a b = case a of …' inlined
      -- where the second argument mentions the caller's own 'a'). Renamed
      -- first, the body's parameter references are out of the way, and
      -- 'substVars' never re-walks what it injects.
      bound = substVars substMap (foldl' (\e (p, t) -> renameVarFull p t e) body' renames)
  pure (foldr (uncurry CLet) bound lets)
  where
    duplicableArg = \case
      CVar v -> not (Set.member v valDefs)
      _ -> False

-- | A fresh, deterministic local name: @$inl<k>$<stem>@. User identifiers
--   cannot contain @$@ and no other pass mints the @$inl@ prefix, so the
--   name is globally unique; the stem keeps @core.txt@ readable. Re-inlining
--   an already-inlined body strips the previous wrap so names don't snowball.
freshName :: Name -> State Int Name
freshName base = do
  k <- get
  put (k + 1)
  pure ("$inl" <> show k <> "$" <> stem)
  where
    stem = case T.stripPrefix "$inl" base of
      Just rest | (digits, tl) <- T.span isDigit rest, not (T.null digits), Just s <- T.stripPrefix "$" tl -> s
      _ -> base

-- | Rename every binder of an inlined body to a fresh name — 'CCase' /
--   'CRowCase' arm binders and 'CLet' binders, with references (including
--   'CProj' / 'CReuse' name positions) following their binder. Afterwards
--   the body binds no name that exists anywhere else, so substitution into
--   it cannot capture, and the per-name slot/frame maps of the stack
--   backends see each binding exactly once per scope.
freshenBinders :: CExpr -> State Int CExpr
freshenBinders = go Map.empty
  where
    ref env v = Map.findWithDefault v v env
    bind env v = do
      v' <- freshName v
      pure (v', Map.insert v v' env)
    binds env = foldlM (\(acc, e) v -> first (\v' -> acc <> [v']) <$> bind e v) ([], env)
    go env = \case
      CVar v -> pure (CVar (ref env v))
      CProj v i -> pure (CProj (ref env v) i)
      CReuse rm v t fs -> CReuse rm (ref env v) t <$> traverse (go env) fs
      CCall f xs -> CCall <$> go env f <*> traverse (go env) xs
      CCon t fs -> CCon t <$> traverse (go env) fs
      CRow t v -> CRow t <$> go env v
      CCase s alts ->
        CCase
          <$> go env s
          <*> forM alts (\(t, vs, b) -> do (vs', env') <- binds env vs; (t,vs',) <$> go env' b)
      CRowCase s alts ->
        CRowCase
          <$> go env s
          <*> forM alts (\(t, v, b) -> do (v', env') <- bind env v; (t,v',) <$> go env' b)
      CLoop b -> CLoop <$> go env b
      CContinue xs -> CContinue <$> traverse (go env) xs
      CLet x rhs b -> do
        rhs' <- go env rhs
        (x', env') <- bind env x
        CLet x' rhs' <$> go env' b
      CDrop x b -> CDrop (ref env x) <$> go env b
      -- A join name is a binder too — an inlined body copied twice must not
      -- declare the same label twice. It freshens with its own minter (the
      -- value-name env carries the mapping; the namespaces cannot collide)
      -- and is in scope only inside the inner expression; the parameters
      -- only inside the join body.
      CJoin j ps body inner -> do
        j' <- freshJoinName
        let envJ = Map.insert j j' env
        (ps', envP) <- binds envJ ps
        body' <- go envP body
        CJoin j' ps' body' <$> go envJ inner
      CJump j args -> CJump (ref env j) <$> traverse (go env) args
      e@(CString _) -> pure e
      e@(CIntLit _ _) -> pure e
      e@(CBuiltIn _) -> pure e

-- | Rename @old@ to @new@ in every reference position — 'CVar' and the name
--   positions of 'CProj' / 'CReuse'. Stops under a binder that re-introduces
--   @old@ (defensive; freshened bodies never re-bind a parameter).
renameVarFull :: Name -> Name -> CExpr -> CExpr
renameVarFull old new = go
  where
    rn v = if v == old then new else v
    go = \case
      CVar v -> CVar (rn v)
      CProj v i -> CProj (rn v) i
      CReuse rm v t fs -> CReuse rm (rn v) t (map go fs)
      CCall f xs -> CCall (go f) (map go xs)
      CCon t fs -> CCon t (map go fs)
      CRow t v -> CRow t (go v)
      CCase s alts -> CCase (go s) [(t, vs, if old `elem` vs then b else go b) | (t, vs, b) <- alts]
      CRowCase s alts -> CRowCase (go s) [(t, v, if v == old then b else go b) | (t, v, b) <- alts]
      CLoop b -> CLoop (go b)
      CContinue xs -> CContinue (map go xs)
      CLet x rhs b -> CLet x (go rhs) (if x == old then b else go b)
      CDrop x b -> CDrop (rn x) (go b)
      -- Join names live in their own namespace; only the parameters can
      -- shadow a value name, and only inside the join body.
      CJoin j ps body inner -> CJoin j ps (if old `elem` ps then body else go body) (go inner)
      CJump j args -> CJump j (map go args)
      e@(CString _) -> e
      e@(CIntLit _ _) -> e
      e@(CBuiltIn _) -> e

-- | Per top-level name: how many times it is called directly (callee
--   position) and how many times it is referenced any other way ('CVar' in
--   term position, 'CProj' / 'CReuse' name). Local binders pollute the map
--   harmlessly — 'Awsum.UniquifyLocals' guarantees no local shares a
--   top-level name, and only top-level names are ever looked up.
programRefs :: CoreProgram -> Map Name (Int, Int)
programRefs (CoreProgram ds) = foldl' (Map.unionWith plus) Map.empty (map declRefs ds)
  where
    plus :: (Int, Int) -> (Int, Int) -> (Int, Int)
    plus (a, b) (c, d) = (a + c, b + d)
    declRefs = \case
      CFunDef _ _ b -> go b
      CValDef _ b -> go b
    goMany :: [CExpr] -> Map Name (Int, Int)
    goMany = foldl' (Map.unionWith plus) Map.empty . map go
    go :: CExpr -> Map Name (Int, Int)
    go = \case
      CCall (CVar f) xs -> Map.unionWith plus (Map.singleton f (1, 0)) (goMany xs)
      CCall f xs -> Map.unionWith plus (go f) (goMany xs)
      CVar n -> Map.singleton n (0, 1)
      CProj n _ -> Map.singleton n (0, 1)
      CReuse _ n _ fs -> Map.unionWith plus (Map.singleton n (0, 1)) (goMany fs)
      CCon _ fs -> goMany fs
      CRow _ v -> go v
      CCase s alts -> Map.unionWith plus (go s) (goMany [b | (_, _, b) <- alts])
      CRowCase s alts -> Map.unionWith plus (go s) (goMany [b | (_, _, b) <- alts])
      CLoop b -> go b
      CContinue xs -> goMany xs
      CLet _ rhs b -> Map.unionWith plus (go rhs) (go b)
      CDrop _ b -> go b
      -- A jump's target is a label, not a top-level reference.
      CJoin _ _ body inner -> Map.unionWith plus (go body) (go inner)
      CJump _ args -> goMany args
      CString _ -> Map.empty
      CIntLit _ _ -> Map.empty
      CBuiltIn _ -> Map.empty

-- | Node count of an expression — the inliner's size measure.
exprSize :: CExpr -> Int
exprSize = go
  where
    go :: CExpr -> Int
    go = \case
      CCall f xs -> 1 + go f + sum (map go xs)
      CCon _ fs -> 1 + sum (map go fs)
      CRow _ v -> 1 + go v
      CCase s alts -> 1 + go s + sum [go b | (_, _, b) <- alts]
      CRowCase s alts -> 1 + go s + sum [go b | (_, _, b) <- alts]
      CLoop b -> 1 + go b
      CContinue xs -> 1 + sum (map go xs)
      CLet _ rhs b -> 1 + go rhs + go b
      CDrop _ b -> 1 + go b
      CReuse _ _ _ fs -> 1 + sum (map go fs)
      CJoin _ _ body inner -> 1 + go body + go inner
      CJump _ args -> 1 + sum (map go args)
      CVar _ -> 1
      CProj _ _ -> 1
      CString _ -> 1
      CIntLit _ _ -> 1
      CBuiltIn _ -> 1

-- | Does the body contain the TCO loop forms? Their presence marks the
--   declaration as (formerly) self-recursive — never inlined.
hasLoopOrContinue :: CExpr -> Bool
hasLoopOrContinue = go
  where
    go = \case
      CLoop _ -> True
      CContinue _ -> True
      CCall f xs -> go f || any go xs
      CCon _ fs -> any go fs
      CRow _ v -> go v
      CCase s alts -> go s || any (\(_, _, b) -> go b) alts
      CRowCase s alts -> go s || any (\(_, _, b) -> go b) alts
      CLet _ rhs b -> go rhs || go b
      CDrop _ b -> go b
      CReuse _ _ _ fs -> any go fs
      CJoin _ _ body inner -> go body || go inner
      CJump _ args -> any go args
      CVar _ -> False
      CProj _ _ -> False
      CString _ -> False
      CIntLit _ _ -> False
      CBuiltIn _ -> False

-- | Compile-time evaluation of the integer built-ins over literal operands
--   (see the module header). The result is exactly the cell the runtime
--   helper builds, so folding is observationally invisible — pinned by the
--   @constFold-differential@ property and the no-simplify differential
--   suite, whose 'SimplifyOff' leg routes the same literals to the runtime
--   helpers.
--
--   Each equation requires operands of the built-in's own 'IntType' — after
--   typechecking nothing else can appear, but a mismatch must miss the fold
--   rather than evaluate under the wrong width. Arithmetic is on the
--   literals' arbitrary-precision 'Integer' payloads, range-checked against
--   the result type exactly as the helpers check (signed @add@\/@sub@\/@mul@
--   against both ends, unsigned against one — the other is unreachable, see
--   "Awsum.BuiltIn").
constFold :: PreludeTags -> Name -> [CExpr] -> Maybe CExpr
constFold pt op args = case (op, args) of
  ("addInt32", [CIntLit a TInt32, CIntLit b TInt32]) -> Just (int32Arith (a + b))
  ("subInt32", [CIntLit a TInt32, CIntLit b TInt32]) -> Just (int32Arith (a - b))
  ("mulInt32", [CIntLit a TInt32, CIntLit b TInt32]) -> Just (int32Arith (a * b))
  ("negInt32", [CIntLit a TInt32]) -> Just (if a == lo TInt32 then leftOverflow else right (negate a) TInt32)
  ("succInt32", [CIntLit a TInt32]) -> Just (if a == hi TInt32 then leftOverflow else right (a + 1) TInt32)
  ("predInt32", [CIntLit a TInt32]) -> Just (if a == lo TInt32 then leftUnderflow else right (a - 1) TInt32)
  ("eqInt32", [CIntLit a TInt32, CIntLit b TInt32]) -> Just (boolCon (a == b))
  ("addUInt8", [CIntLit a TUInt8, CIntLit b TUInt8]) -> Just (unsignedAdd TUInt8 a b)
  ("subUInt8", [CIntLit a TUInt8, CIntLit b TUInt8]) -> Just (unsignedSub TUInt8 a b)
  ("mulUInt8", [CIntLit a TUInt8, CIntLit b TUInt8]) -> Just (unsignedMul TUInt8 a b)
  ("succUInt8", [CIntLit a TUInt8]) -> Just (if a == hi TUInt8 then leftOverflow else right (a + 1) TUInt8)
  ("predUInt8", [CIntLit a TUInt8]) -> Just (if a == 0 then leftUnderflow else right (a - 1) TUInt8)
  ("eqUInt8", [CIntLit a TUInt8, CIntLit b TUInt8]) -> Just (boolCon (a == b))
  ("addUInt32", [CIntLit a TUInt32, CIntLit b TUInt32]) -> Just (unsignedAdd TUInt32 a b)
  ("subUInt32", [CIntLit a TUInt32, CIntLit b TUInt32]) -> Just (unsignedSub TUInt32 a b)
  ("mulUInt32", [CIntLit a TUInt32, CIntLit b TUInt32]) -> Just (unsignedMul TUInt32 a b)
  ("succUInt32", [CIntLit a TUInt32]) -> Just (if a == hi TUInt32 then leftOverflow else right (a + 1) TUInt32)
  ("predUInt32", [CIntLit a TUInt32]) -> Just (if a == 0 then leftUnderflow else right (a - 1) TUInt32)
  ("eqUInt32", [CIntLit a TUInt32, CIntLit b TUInt32]) -> Just (boolCon (a == b))
  _ -> Nothing
  where
    -- Signed Int32 add/sub/mul: both overflow directions are reachable, and
    -- the error side is the structural two-label row — 'CRow' wrapped, like
    -- the helpers' returns.
    int32Arith r
      | r > hi TInt32 = CCon (ptLeft pt) [CRow overflowRowTag (CCon (ptOverflowError pt) [])]
      | r < lo TInt32 = CCon (ptLeft pt) [CRow underflowRowTag (CCon (ptUnderflowError pt) [])]
      | otherwise = right r TInt32
    -- Unsigned add/sub/mul: one reachable failure direction each, so the
    -- error side is the bare single-constructor type — no row.
    unsignedAdd ty a b = if a + b > hi ty then leftOverflow else right (a + b) ty
    unsignedSub ty a b = if a < b then leftUnderflow else right (a - b) ty
    unsignedMul ty a b = if a * b > hi ty then leftOverflow else right (a * b) ty
    right r ty = CCon (ptRight pt) [CIntLit r ty]
    leftOverflow = CCon (ptLeft pt) [CCon (ptOverflowError pt) []]
    leftUnderflow = CCon (ptLeft pt) [CCon (ptUnderflowError pt) []]
    boolCon c = CCon (if c then ptTrue pt else ptFalse pt) []
    lo ty = if intSigned ty then negate (2 ^ (intWidth ty - 1)) else 0
    hi ty = if intSigned ty then 2 ^ (intWidth ty - 1) - 1 else 2 ^ intWidth ty - 1

-- | Row tags of the two error labels of the signed-arithmetic row
--   @(UnderflowError | OverflowError)@ — the same FNV-1a hashes the codegen
--   helpers embed ('Awsum.Codegen.JS' et al. compute them identically).
overflowRowTag, underflowRowTag :: Word32
overflowRowTag = rowTag (TyCon noSpan "OverflowError")
underflowRowTag = rowTag (TyCon noSpan "UnderflowError")

-- | Case-of-known-constructor, nominal form: pick the arm whose tag matches
--   the literal 'CCon' and substitute its fields for the binders. Nothing
--   when no arm matches (cannot happen after exhaustiveness +
--   @pruneDeadArms@, but the rewrite must not invent a result), when arities
--   disagree, or when a substitution gate fails.
knownNominal :: Set Name -> Int -> [CExpr] -> [(Int, [Name], CExpr)] -> Maybe CExpr
knownNominal valDefs tag fs alts = do
  (vs, body) <- listToMaybe [(armVs, b) | (t, armVs, b) <- alts, t == tag]
  guard (length vs == length fs)
  knownArm valDefs (zip vs fs) body

-- | Case-of-known-constructor, row form: the row wrapper disappears and the
--   matching arm's binder takes the payload.
knownRow :: Set Name -> Word32 -> CExpr -> [(Word32, Name, CExpr)] -> Maybe CExpr
knownRow valDefs tag payload alts = do
  (v, body) <- listToMaybe [(armV, b) | (t, armV, b) <- alts, t == tag]
  knownArm valDefs [(v, payload)] body

-- | Substitution gates + the simultaneous substitution itself, shared by the
--   nominal and row forms of case-of-known-constructor. @pairs@ are
--   @(binder, field)@; Nothing (the case stays) unless every binder passes:
--
--     * never used as the /name/ of a 'CProj' \/ 'CReuse' — substitution puts
--       an expression where those positions need a name;
--     * used once: any field substitutes — evaluated once as before, at the
--       same or a conditionally lower frequency ('CLoop' only wraps whole
--       function bodies, so no use site sits in a hotter context than the
--       scrutinee did);
--     * used more than once: only a duplicable field, i.e. a non-'CValDef'
--       'CVar' — variable reads add no work, while anything else would
--       duplicate it ('CIntLit' \/ 'CString' are fresh-cell sources on
--       LLVM\/WASM, a 'CValDef' reference is a getter call, a nullary 'CCon'
--       may allocate);
--     * a binder used zero times drops its field unevaluated — Core is pure
--       ('IO' is data), so this is dead-code elimination.
--
--   Capture check: a substituted field's free names must not be re-bound
--   anywhere in the body ('boundNamesIn') — lowering's deterministic pattern
--   names (@__p0@ restarts per nesting level) make this real, the same
--   hazard class 'scrutShadowedIn' guards for the projection inline. Fields
--   spelled like /other/ binders need no check: 'substVars' is simultaneous
--   and never re-walks an injected expression.
--
--   No self-call can be moved into tail position by the substitution:
--   a 'CCon' \/ 'CRow' field is a non-tail position, and after 'Awsum.Cps' +
--   the stack-safety verifier no non-tail self-call exists to begin with.
knownArm :: Set Name -> [(Name, CExpr)] -> CExpr -> Maybe CExpr
knownArm valDefs pairs body = do
  let occ = occurrences body
      usesOf v = fromMaybe (0, False) (Map.lookup v occ)
      substituted = [(v, f) | (v, f) <- pairs, fst (usesOf v) >= 1]
  guard (not (any (snd . usesOf . fst) pairs))
  -- A single use may sit inside one arm of a case in the body, so an
  -- effectful field must not substitute even there — the effect would run
  -- at that arm's frequency instead of once.
  guard (all (\(v, f) -> (fst (usesOf v) == 1 && not (effectfulIn f)) || duplicable f) substituted)
  -- A field bound to an unused binder is dropped unevaluated — which an
  -- effectful field ('effectfulIn') must never be.
  guard (all (\(v, f) -> fst (usesOf v) >= 1 || not (effectfulIn f)) pairs)
  guard (Set.disjoint (foldMap (freeNames . snd) substituted) (boundNamesIn body))
  pure (substVars (Map.fromList substituted) body)
  where
    duplicable = \case
      CVar n -> not (Set.member n valDefs)
      _ -> False

-- | Identity reconstruction: an arm that rebuilds the very cell it
--   matched — the same tag, every binder back in its own slot — is the
--   scrutinee. @case x of (t, [v1..vk], C[CCon t [CVar v1 .. CVar vk]])@
--   reduces the reconstruction to @CVar x@ (the do-desugar's
--   @Left e -> Left e@ re-injection residue, threaded by Cps into the
--   @$apply@ dispatchers; the nullary instance covers @True -> True@ and
--   @Leaf -> Leaf@). The replacement composes downstream in the same
--   fixpoint: a continue argument collapses to a parameter self-pass,
--   arms that become syntactically equal fold via 'collapseIdentical',
--   and the vanished reconstruction releases the same-arity carve-out on
--   the arm's other binders. Skipped when the scrutinee or any binder is
--   re-bound inside the body (the deterministic @__p0@ names repeat
--   across nesting levels; a blind replacement would name an inner cell).
identityRecon :: Name -> Int -> [Name] -> CExpr -> CExpr
identityRecon scrut tag vs body
  | not (Set.disjoint (Set.fromList (scrut : vs)) (boundNamesIn body)) = body
  | otherwise = rewriteIdentity isIdentity scrut body
  where
    isIdentity = \case
      CCon t fs -> t == tag && fs == map CVar vs
      _ -> False

-- | The row form of 'identityRecon': @(rt, v, C[CRow rt (CVar v)])@ —
--   re-injecting the matched alternative unchanged — reduces to the
--   scrutinee.
identityRowRecon :: Name -> Word32 -> Name -> CExpr -> CExpr
identityRowRecon scrut rtag v body
  | not (Set.disjoint (Set.fromList [scrut, v]) (boundNamesIn body)) = body
  | otherwise = rewriteIdentity isIdentity scrut body
  where
    isIdentity = \case
      CRow rt (CVar w) -> rt == rtag && w == v
      _ -> False

-- | Replace every node matching the identity predicate with the
--   scrutinee variable, everywhere in the arm body (shadowing excluded by
--   the callers' gate).
rewriteIdentity :: (CExpr -> Bool) -> Name -> CExpr -> CExpr
rewriteIdentity p scrut = goR
  where
    goR e
      | p e = CVar scrut
      | otherwise = case e of
          CCall f xs -> CCall (goR f) (map goR xs)
          CCon t fs -> CCon t (map goR fs)
          CRow t x -> CRow t (goR x)
          CCase s alts -> CCase (goR s) [(t, ns, goR b) | (t, ns, b) <- alts]
          CRowCase s alts -> CRowCase (goR s) [(t, w, goR b) | (t, w, b) <- alts]
          CLoop b -> CLoop (goR b)
          CContinue xs -> CContinue (map goR xs)
          CDrop m b -> CDrop m (goR b)
          CReuse rm m t fs -> CReuse rm m t (map goR fs)
          CLet x rhs b -> CLet x (goR rhs) (goR b)
          CJoin j ps jb inner -> CJoin j ps (goR jb) (goR inner)
          CJump j args -> CJump j (map goR args)
          leaf@(CVar _) -> leaf
          leaf@(CProj _ _) -> leaf
          leaf@(CString _) -> leaf
          leaf@(CIntLit _ _) -> leaf
          leaf@(CBuiltIn _) -> leaf

-- | Inline each qualifying single-use binder @(name, fieldIndex)@ into
--   @CProj s slot@. Eligibility for every binder comes from one 'occurrences'
--   walk of @body@, so the substitutions are order-independent.
--
--   Carve-out: if the scrutinee is reuse-eligible (@reuseable@ —
--   'scrutReuseEligible' at the caller: a parameter of the enclosing
--   function, the only shape whose in-arm drop 'Awsum.Reuse' can match) and
--   the arm reconstructs a /same-arity/ cell, none of its binders are
--   inlined. Reuse may rewrite such a reconstruction of a linear scrutinee
--   into an in-place 'CReuse' on @s@; a 'CProj s i' field of (or sibling
--   to) that 'CReuse' reads overwritten\/freed slots (@revInto@,
--   @countDown@), so Reuse's own scrut-use gate ('binderUsedIn') would refuse the rewrite
--   and the hot loop would allocate again. Leaving the binders extracted
--   keeps Reuse on its tested 'CVar'-field path. Where no reuse is
--   reachable — the scrutinee is an arm\/let binder (CPS K-cells), or the
--   case is a 'CRowCase' — the carve-out is waived and the cleanup applies
--   like everywhere else. (Soundness does not rest on this gate: if a
--   simplifier renaming later turns the scrutinee name into a parameter —
--   copy-propagation of @CLet x (CVar p)@, a known-constructor field
--   substitution — Reuse's scrut-use gate still refuses to rewrite beside a
--   manufactured projection; the only cost is that missed reuse.)
--
--   Second carve-out: if the scrutinee name @s@ is itself shadowed inside the
--   arm body, none of its binders are inlined either — see 'scrutShadowedIn'.
inlineArm :: Bool -> Name -> [(Name, Int)] -> CExpr -> CExpr
inlineArm reuseable s binders body
  | reuseable, reuseTargetArm (length binders) body = body
  | scrutShadowedIn s body = body
  | otherwise =
      let occ = occurrences body
          eligible = Map.fromList [(v, CProj s (k + 1)) | (v, k) <- binders, Map.lookup v occ == Just (1, False)]
       in if Map.null eligible then body else substVars eligible body

-- | Is an arm with @arity@ field binders a 'Awsum.Reuse' target the same-arity
--   carve-out must not disturb — a field-binding arm (@arity > 0@) whose body
--   rebuilds a cell of that same arity? The single source of the carve-out's
--   shape, shared by the single-use-binder inline ('inlineArm') and the
--   identical-arms collapse ('collapseIdentical'): only a reuse-eligible
--   scrutinee (the @reuseable@ caller flag) consults it, and only there is the
--   extracted-binder reconstruction Reuse rewrites in place. Binder-less arms
--   are never targets — their "arity" is zero, which any nullary constructor
--   in the body would match, and there is no field cell to reuse.
reuseTargetArm :: Int -> CExpr -> Bool
reuseTargetArm arity body = arity > 0 && reconstructsSameArity arity body

-- | Does the arm body build a 'CCon' of exactly @arity@ fields — a cell the
--   same shape as the scrutinee, which 'Awsum.Reuse' could rewrite into an
--   in-place 'CReuse' on the scrutinee? Consulted only through 'reuseTargetArm'
--   (for reuse-eligible scrutinees, 'scrutReuseEligible'); within that scope it
--   stays conservative — any same-arity 'CCon' counts, whether or not Reuse
--   will actually fire.
reconstructsSameArity :: Int -> CExpr -> Bool
reconstructsSameArity arity = go
  where
    go = \case
      CCon _ fs -> length fs == arity || any go fs
      CRow _ x -> go x
      CCall f xs -> go f || any go xs
      CCase s alts -> go s || any (\(_, _, b) -> go b) alts
      CRowCase s alts -> go s || any (\(_, _, b) -> go b) alts
      CLoop b -> go b
      CContinue xs -> any go xs
      CLet _ rhs b -> go rhs || go b
      CDrop _ b -> go b
      CReuse _ _ _ fs -> any go fs
      CJoin _ _ body inner -> go body || go inner
      CJump _ args -> any go args
      CVar _ -> False
      CProj _ _ -> False
      CString _ -> False
      CIntLit _ _ -> False
      CBuiltIn _ -> False

-- | Is the scrutinee name @s@ re-bound (shadowed) anywhere inside the arm
--   body — by an inner @CCase@/@CRowCase@ arm binder or a @CLet@? If so, no
--   binder of this arm may be inlined: replacing a field read with @CProj s i@
--   moves it to a position where @s@ may resolve to the inner binding instead
--   of the matched cell, reading the wrong cell.
--
--   This is real, not defensive. Lowering mints /deterministic/ pattern-binder
--   names (@desugarPatsM@: @__p0@, @__pa0@, …) so that sibling arms of one case
--   share names and @mergeAlts@ can fuse them — but the same counter restarts
--   per nesting level, so two nested @Just (Tuple2 …)@ patterns both bind
--   @__p0@. With binders kept, each is extracted in its own scope before the
--   inner @__p0@ shadows it; inlining @a@ into @CProj __p0 1@ would push @a@'s
--   read down into the inner @__p0@'s scope, so @a@ would read the inner cell's
--   field 1 (@parseInput@: @Tuple3 a b c@ became @Tuple3 b b c@). The dual of
--   the target-name capture avoidance in 'substVars' — here the /source/ name
--   is the one at risk of capture.
scrutShadowedIn :: Name -> CExpr -> Bool
scrutShadowedIn s body = Set.member s (boundNamesIn body)

-- | Every name bound anywhere inside an expression — case-arm binders,
--   row-arm binders, 'CLet' binders. The conservative half of both capture
--   checks: a field moved into a body must not have a free name the body
--   re-binds somewhere ('knownArm'), and a 'CProj' over the scrutinee must
--   not move under a re-binding of the scrutinee's name ('scrutShadowedIn').
boundNamesIn :: CExpr -> Set Name
boundNamesIn = go
  where
    go = \case
      CCase s alts -> go s <> foldMap (\(_, vs, b) -> Set.fromList vs <> go b) alts
      CRowCase s alts -> go s <> foldMap (\(_, v, b) -> Set.singleton v <> go b) alts
      CLet n rhs b -> Set.singleton n <> go rhs <> go b
      CCall f xs -> go f <> foldMap go xs
      CCon _ fs -> foldMap go fs
      CRow _ v -> go v
      CLoop b -> go b
      CContinue xs -> foldMap go xs
      CDrop _ b -> go b
      CReuse _ _ _ fs -> foldMap go fs
      -- The join parameters are value binders; the join name is a label in
      -- its own namespace and cannot capture a value name.
      CJoin _ ps body inner -> Set.fromList ps <> go body <> go inner
      CJump _ args -> foldMap go args
      CVar _ -> mempty
      CProj _ _ -> mempty
      CString _ -> mempty
      CIntLit _ _ -> mempty
      CBuiltIn _ -> mempty

-- | Every name an expression references — 'CVar' uses plus 'CProj' /
--   'CReuse' name positions; exactly the keys 'occurrences' reports.
freeNames :: CExpr -> Set Name
freeNames = Map.keysSet . occurrences

-- | One shadowing-aware walk of an arm body. For each free name it reports
--   @(cvarUses, usedAsName)@: how many times the name occurs as a plain 'CVar',
--   and whether it ever occurs as the /variable/ of a 'CProj' / 'CReuse' (a
--   position that needs a name, so the binder cannot be replaced by an
--   expression). A binder is inlinable iff its entry is exactly @(1, False)@.
--
--   This subsumes what used to be two separate walks; it is the single source
--   of truth for "how is this name used", and lines up with 'binderUsedIn'
--   (a name is used iff @cvarUses > 0 || usedAsName@). Does not descend under a
--   binder that reintroduces a name (shadowing).
occurrences :: CExpr -> Map Name (Int, Bool)
occurrences = go
  where
    goList = foldr (merge . go) Map.empty
    go = \case
      CVar n -> Map.singleton n (1, False)
      CProj n _ -> Map.singleton n (0, True)
      CReuse _ n _ fs -> merge (Map.singleton n (0, True)) (goList fs)
      CCall f xs -> merge (go f) (goList xs)
      CCon _ fs -> goList fs
      CRow _ v -> go v
      CCase s alts -> foldr (merge . arm) (go s) alts
      CRowCase s alts -> foldr (merge . rowArm) (go s) alts
      CLoop b -> go b
      CContinue xs -> goList xs
      CLet n rhs b -> merge (go rhs) (shadow [n] (go b))
      CDrop _ b -> go b
      -- The join name is a label, not a value occurrence; the parameters
      -- shadow inside the join body only.
      CJoin _ ps body inner -> merge (shadow ps (go body)) (go inner)
      CJump _ args -> goList args
      CString _ -> Map.empty
      CIntLit _ _ -> Map.empty
      CBuiltIn _ -> Map.empty

    arm (_, vs, b) = shadow vs (go b)
    rowArm (_, v, b) = shadow [v] (go b)

    merge :: Map Name (Int, Bool) -> Map Name (Int, Bool) -> Map Name (Int, Bool)
    merge = Map.unionWith (\(c1, b1) (c2, b2) -> (c1 + c2, b1 || b2))
    shadow names m = foldr Map.delete m names

-- | Simultaneous substitution of variables: each @CVar v@ in the map's
--   domain is replaced by its expression. Does not descend under a binder
--   that re-introduces a mapped name, and never re-walks an injected
--   expression — so a field that happens to mention a name spelled like
--   another binder cannot be hit by that binder's substitution. Callers rule
--   out the remaining capture directions up front ('boundNamesIn' /
--   'scrutShadowedIn') and guarantee no mapped name appears in a 'CProj' /
--   'CReuse' name position (the @usedAsName@ gate in 'knownArm' /
--   'inlineArm').
substVars :: Map Name CExpr -> CExpr -> CExpr
substVars = go
  where
    go sub = \case
      e@(CVar n) -> fromMaybe e (Map.lookup n sub)
      CCall f xs -> CCall (go sub f) (map (go sub) xs)
      CCon t fs -> CCon t (map (go sub) fs)
      CRow t v -> CRow t (go sub v)
      CCase sc alts -> CCase (go sub sc) [(t, vs, go (foldr Map.delete sub vs) b) | (t, vs, b) <- alts]
      CRowCase sc alts -> CRowCase (go sub sc) [(t, v, go (Map.delete v sub) b) | (t, v, b) <- alts]
      CLoop b -> CLoop (go sub b)
      CContinue xs -> CContinue (map (go sub) xs)
      CLet n rhs b -> CLet n (go sub rhs) (go (Map.delete n sub) b)
      CDrop n b -> CDrop n (go sub b)
      CReuse rm n t fs -> CReuse rm n t (map (go sub) fs)
      CJoin j ps body inner -> CJoin j ps (go (foldr Map.delete sub ps) body) (go sub inner)
      CJump j args -> CJump j (map (go sub) args)
      e@(CProj _ _) -> e
      e@(CString _) -> e
      e@(CIntLit _ _) -> e
      e@(CBuiltIn _) -> e
