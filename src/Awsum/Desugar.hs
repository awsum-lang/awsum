-- | Surface-AST desugaring pass run before typechecking.
--
-- Translates @do@-blocks into a chain of nested @case@-on-'Either'
-- expressions /at desugar time/, before typechecking:
--
-- @
-- do
--   a <- e1
--   b <- e2 a
--   pureEither (Tuple2 a b)
-- @
--
-- becomes
--
-- @
-- case e1 of
--   Left $do_e_N -> Left $do_e_N
--   Right a -> case e2 a of
--     Left $do_e_M -> Left $do_e_M
--     Right b -> pureEither (Tuple2 a b)
-- @
--
-- Inlining the bind pattern here means @do@ continuations
-- never appear as surface lambdas, so multi-bind blocks where later
-- steps reference earlier-bound variables compile end-to-end without
-- the runtime needing first-class closures. Each synthetic @$do_e_N@
-- name uses a monotonic counter so nested do-blocks don't trip the
-- same-module no-shadowing rule and so layout / comment changes do
-- not perturb the generated names (the counter walks the AST in
-- document order; positions in the source are not part of the name).
--
-- The trailing expression is the user's verbatim — typically a
-- 'pureEither' call, which is an ordinary prelude function. There is
-- no @pure@ soft keyword; once type classes land, 'pure' will return
-- as a polymorphic function rather than as a syntactic rewrite.
--
-- @let@ inside @do@ rewrites to 'ELet' wrapping the rest of the block:
-- @do { let n = e; rest }@ → @ELet n e (go rest)@. The standalone
-- @let n = e in body@ form parses directly to 'ELet' and flows through
-- unchanged.
--
-- Purely syntactic and hard-coded to 'Either' — no type-class dispatch
-- yet.
--
-- ==== Fresh-name counter
--
-- The whole pass runs in @StateT Int (Either DesugarError)@. The
-- 'Int' is a monotonic counter shared between '$do_e_' and '$arg_'
-- synthesis sites; it starts at @0@ and grows in document order.
-- Two consequences worth naming:
--
--   * Names are deterministic with respect to the AST alone — layout,
--     comments, and blank lines (none of which reach the AST) cannot
--     change them. So @awsum format@ never changes any generated
--     synthetic name, and any future test that snapshots Core IR or
--     codegen output is stable under cosmetic edits.
--   * Counter is /global per program/, not per function. The
--     supercompiler/inliner work assumed by future passes benefits
--     from globally unique binder names: substitution on inline
--     becomes rename-free, because no two binders in the whole
--     program ever share a synthetic name.
module Awsum.Desugar (desugarProgram, DesugarError (..)) where

import Awsum.Syntax
import Relude

-- | Reasons the desugarer can refuse a 'do' block. Surfaced as part
--   of the lowering error channel by 'Awsum.ElaborateLower'.
data DesugarError
  = -- | The bound name of a 'do'-bind is used by the continuation
    --   such that the lambda cannot be eliminated by η or 'const'.
    --   Carries the bind's source span and the bound name.
    DesugarBindNameStillUsed SrcSpan Name
  | -- | A 'let'-binding with both a destructuring pattern on the
    --   LHS and a type ascription. Caught at desugar time before
    --   the non-'PVar' rewrite to 'ECase' would silently drop the
    --   ascription. Carries the let's source span; mapped onto the
    --   typechecker's 'PatternLetAscription' diagnostic.
    DesugarPatternLetAscription SrcSpan
  deriving stock (Show, Eq)

-- | Desugaring monad: a monotonic 'Int' counter for synthetic-name
--   minting, layered on top of the existing 'Either DesugarError'
--   result channel.
type DesugarM = StateT Int (Either DesugarError)

-- | Allocate the next index from the shared counter.
freshIx :: DesugarM Int
freshIx = do
  i <- get
  put (i + 1)
  pure i

-- | Mint a fresh @$do_e_N@ name for a do-bind's synthetic Left binder.
freshDoErrName :: DesugarM Name
freshDoErrName = ("$do_e_" <>) . show <$> freshIx

-- | Mint a fresh @$arg_N@ name for a 'ParamPat' lift.
freshArgName :: DesugarM Name
freshArgName = ("$arg_" <>) . show <$> freshIx

-- | Run the desugarer over a 'Program'. Pure tree rewrite — no extra
--   declarations are introduced, only the body of each 'FunDef' is
--   rewritten in place. The synthetic-name counter starts at @0@ and
--   is consumed top-to-bottom in document order; the counter is
--   discarded after the run.
desugarProgram :: Program -> Either DesugarError Program
desugarProgram p = evalStateT (go p) 0
  where
    go prog = do
      decls' <- traverse desugarDecl (decls prog)
      pure prog {decls = decls'}

desugarDecl :: Decl -> DesugarM Decl
desugarDecl = \case
  FunDef sp n params body c doc -> do
    body' <- desugarExpr body
    (params', wrappedBody) <- liftParamPatterns params body'
    pure (FunDef sp n params' wrappedBody c doc)
  d -> pure d

desugarExpr :: Expr -> DesugarM Expr
desugarExpr = \case
  EDo sp stmts -> desugarDo sp stmts
  ELam sp params body -> do
    body' <- desugarExpr body
    (params', wrappedBody) <- liftParamPatterns params body'
    pure (ELam sp params' wrappedBody)
  EApp sp f x -> EApp sp <$> desugarExpr f <*> desugarExpr x
  EInfix sp op l r -> EInfix sp op <$> desugarExpr l <*> desugarExpr r
  EParens sp e -> EParens sp <$> desugarExpr e
  ECase sp scrut alts cs -> do
    scrut' <- desugarExpr scrut
    alts' <- traverse desugarCaseAlt alts
    pure (ECase sp scrut' alts' cs)
  ELet sp pat mAnnot e body -> do
    e' <- desugarExpr e
    body' <- desugarExpr body
    rewriteLet sp pat mAnnot e' body'
  e -> pure e
  where
    desugarCaseAlt alt = do
      body' <- desugarExpr (caseAltBody alt)
      pure (mkCaseAlt (caseAltLeading alt) (caseAltPattern alt) body' (caseAltTrailing alt))

-- | Translate a 'do'-block into nested @case@ on @Either@. Each
--   bind step becomes:
--
--   @
--   case <expr> of
--     Left $do_e_N -> Left $do_e_N
--     Right <param>           -> <rest>
--   @
--
--   The 'Left' arm bubbles the error up; row-injection in 'checkExpr'
--   widens it to whatever the surrounding signature requires (set-
--   semantic union of all @Left@-side label types collected by the
--   chain). The 'Right' arm binds the user's name and falls through
--   to the rest of the block.
--
--   Inlining the @bindEither@ pattern at desugar time means
--   continuations never appear as surface lambdas. The downstream
--   defunctionalization / closure-lowering passes could handle them
--   if they did, but generating a direct nested 'case' shape skips
--   the round-trip and keeps the generated Core simpler — useful for
--   reading 'awsum core' output. Multi-bind do-blocks where later
--   steps reference earlier-bound variables — the common shape —
--   work end-to-end.
--
--   Each generated @$do_e_N@ name uses the shared monotonic counter
--   so nested do-blocks don't trip the same-module no-shadowing
--   rule.
desugarDo :: SrcSpan -> [DoStmt] -> DesugarM Expr
desugarDo sp = go
  where
    go [] = pure (EVar sp (QName [] "$emptyDoBlock"))
    go [DoExpr _ e] = desugarExpr e
    go (DoBind bsp pat e : rest) = do
      e' <- desugarExpr e
      body <- go rest
      errName <- freshDoErrName
      let leftPat = PCon bsp "Left" [PVar bsp errName]
          leftBody = EApp bsp (ECon bsp "Left") (EVar bsp (QName [] errName))
          -- The user's bind LHS pattern goes inside 'Right'. If
          -- it's a simple 'PVar'/'PWild' the resulting case is
          -- exhaustive trivially; if it's a constructor pattern
          -- on a single-constructor type (e.g. 'Tuple3 a b c'),
          -- still exhaustive; if it's a refutable pattern from a
          -- multi-constructor type (e.g. 'Just x'), the standard
          -- 'NonExhaustiveCase' check will reject it with a
          -- pointer to the missing constructor — same diagnostic
          -- the user would have seen had they written the case
          -- by hand. No special "refutable in do-bind" error.
          rightPat = PCon bsp "Right" [pat]
          arms = mkCaseAlt [] leftPat leftBody Nothing :| [mkCaseAlt [] rightPat body Nothing]
      pure (ECase bsp e' arms [])
    go (DoLet lsp pat mAnnot e : rest) = do
      e' <- desugarExpr e
      body <- go rest
      -- Apply the same pattern-let rewrite the standalone form
      -- gets: a non-'PVar' / non-'PWild' LHS becomes a single-arm
      -- 'ECase'; ascription on a destructuring LHS is rejected.
      rewriteLet lsp pat mAnnot e' body
    -- Bare expression in a non-final position is rejected; the
    -- typechecker also flags this, but we catch it here too so the
    -- desugar output stays well-formed.
    go (DoExpr esp _ : _ : _) = lift (Left (DesugarBindNameStillUsed esp "<non-final-expr>"))

-- | Rewrite each /destructuring/ 'ParamPat' parameter into a fresh
--   'Param' plus a single-arm 'ECase' wrapping the body that
--   destructures the synthesised name back to the user-written pattern.
--   After this pass, typecheck and lowering never see destructuring
--   patterns at parameter positions. A /type-ascription/ param @(x : T)@
--   is left as a 'ParamPat' (it is a parameter annotation, resolved or
--   rejected by the typechecker — see 'mkParam').
--
--   Each 'ParamPat' contributes one nesting level to the body:
--   given @f (Tuple3 a b c) (Just x) = body@, lifting produces
--   @f $arg_N $arg_M = case $arg_N of Tuple3 a b c ->
--   case $arg_M of Just x -> body@. Exhaustiveness is then
--   validated by the standard 'caseArmsNominal' machinery —
--   single-constructor types pass trivially; refutable patterns
--   (e.g. @Just x@ on a 'Maybe') raise 'NonExhaustiveCase'.
--
--   Synthetic names are drawn from the shared monotonic counter, so
--   two destructuring parameters in the same function don't collide
--   and the names don't depend on source position. The walk is
--   left-to-right in document order, so the /leftmost/ 'ParamPat'
--   gets the lowest counter value and ends up as the /outermost/
--   case wrapper — matching the user's reading order.
liftParamPatterns :: [Param] -> Expr -> DesugarM ([Param], Expr)
liftParamPatterns params body = do
  pieces <- traverse mkParam params
  let (params', wrappers) = unzip pieces
      -- Compose so the leftmost ParamPat's wrapper ends up
      -- outermost.
      wrap = foldr (.) id wrappers
  pure (params', wrap body)
  where
    mkParam :: Param -> DesugarM (Param, Expr -> Expr)
    mkParam p@(Param _ _) = pure (p, id)
    -- A type-ascription parameter @(x : T)@ is a parameter annotation,
    -- not a destructuring pattern: the typechecker resolves it against
    -- the param type from context (lambda) or rejects it (top-level
    -- def). Pass it through untouched rather than rewriting to a @case@,
    -- which would type the annotation against a nominal scrutinee and
    -- fail.
    mkParam p@(ParamPat _ (PAscribe {})) = pure (p, id)
    mkParam (ParamPat sp pat) = do
      n <- freshArgName
      let newWrap inner =
            ECase
              sp
              (EVar sp (QName [] n))
              (mkCaseAlt [] pat inner Nothing :| [])
              []
      pure (Param sp n, newWrap)

-- | Apply the let-binding rewrite rule:
--
--     * 'PVar' / 'PWild' — kept as 'ELet' so 'ElaborateLower'
--       handles it via the '$let$N captures n = body' lift
--       (which guarantees the right-hand side is evaluated
--       exactly once).
--     * Destructuring pattern (e.g. @Tuple3 a b c@) without an
--       ascription — rewritten to a single-arm 'ECase'; standard
--       exhaustiveness machinery in 'caseArmsNominal' validates
--       it (single-constructor types pass trivially,
--       multi-constructor types raise 'NonExhaustiveCase'
--       against the missing constructors).
--     * Destructuring pattern with an ascription — rejected
--       up front: ascribing a destructuring LHS as a whole is
--       ambiguous; the user should ascribe the right-hand side
--       (or use a 'PVar' binder and destructure inside the body).
--
--   Shared by both standalone 'let-in' and 'do { let … }', so the
--   rewrite happens exactly once regardless of source shape.
rewriteLet :: SrcSpan -> Pattern -> Maybe (Type', LetSigLayout) -> Expr -> Expr -> DesugarM Expr
rewriteLet sp pat mAnnot e' body' = case pat of
  PVar _ _ -> pure (ELet sp pat mAnnot e' body')
  PWild _ -> pure (ELet sp pat mAnnot e' body')
  _ -> case mAnnot of
    Just _ -> lift (Left (DesugarPatternLetAscription sp))
    Nothing ->
      pure (ECase sp e' (mkCaseAlt [] pat body' Nothing :| []) [])
