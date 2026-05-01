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
--   Left $do_e_… -> Left $do_e_…
--   Right a -> case e2 a of
--     Left $do_e_… -> Left $do_e_…
--     Right b -> pureEither (Tuple2 a b)
-- @
--
-- Inlining the bind pattern at this stage means @do@ continuations
-- never appear as surface lambdas, so multi-bind blocks where later
-- steps reference earlier-bound variables — the common shape —
-- compile end-to-end without the runtime needing first-class
-- closures. Each synthetic @$do_e_…@ name is suffixed with the
-- bind's source position so nested do-blocks don't trip the
-- same-module no-shadowing rule.
--
-- The trailing expression is the user's verbatim — typically a
-- 'pureEither' application, which is just an ordinary prelude
-- function. There is no @pure@ soft keyword: writing @pure x@ in a
-- @do@ block is a plain unbound-name error like anywhere else, and
-- once type classes land 'pure' will return as a polymorphic
-- function rather than as a syntactic rewrite.
--
-- @let@ statements inside @do@ are rewritten to 'ELet' wrapping the
-- rest of the block — i.e. @do { let n = e; rest }@ becomes
-- @ELet n e (go rest)@. The standalone @let n = e in body@ form
-- (an 'ELet' parsed directly as an expression) flows through
-- unchanged; both forms reach lowering as the same 'ELet' node.
--
-- The rewrite is purely syntactic and hard-coded to the @Either@
-- shape — there is no type-class dispatch yet.
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

-- | Run the desugarer over a 'Program'. Pure tree rewrite — no extra
--   declarations are introduced, only the body of each 'FunDef' is
--   rewritten in place.
desugarProgram :: Program -> Either DesugarError Program
desugarProgram p = do
  decls' <- traverse desugarDecl (decls p)
  pure p {decls = decls'}

desugarDecl :: Decl -> Either DesugarError Decl
desugarDecl = \case
  FunDef sp n params body c -> do
    body' <- desugarExpr body
    let (params', wrappedBody) = liftParamPatterns params body'
    pure (FunDef sp n params' wrappedBody c)
  d -> pure d

desugarExpr :: Expr -> Either DesugarError Expr
desugarExpr = \case
  EDo sp stmts -> desugarDo sp stmts
  ELam sp params body -> do
    body' <- desugarExpr body
    let (params', wrappedBody) = liftParamPatterns params body'
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
    desugarCaseAlt (CaseAlt c pat body mc) = do
      body' <- desugarExpr body
      pure (CaseAlt c pat body' mc)

-- | Translate a 'do'-block into nested @case@ on @Either@. Each
--   bind step becomes:
--
--   @
--   case <expr> of
--     Left $do_e_<line>_<col> -> Left $do_e_<line>_<col>
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
--   continuations never appear as surface lambdas, so the lambda-
--   lifting / closure machinery (which currently can't carry
--   captured locals through a runtime function value) doesn't have
--   to come into play. Multi-bind do-blocks where later steps
--   reference earlier-bound variables — the common shape — work
--   end-to-end.
--
--   Each generated @$do_e_<line>_<col>@ name is unique by source
--   position so nested do-blocks don't trip the same-module no-
--   shadowing rule.
desugarDo :: SrcSpan -> [DoStmt] -> Either DesugarError Expr
desugarDo sp = go
  where
    go [] = Right (EVar sp (QName [] "$emptyDoBlock"))
    go [DoExpr _ e] = desugarExpr e
    go (DoBind bsp pat e : rest) = do
      e' <- desugarExpr e
      body <- go rest
      let errName = "$do_e_" <> spanTag bsp
          leftPat = PCon bsp "Left" [PVar bsp errName]
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
          arms = CaseAlt [] leftPat leftBody Nothing :| [CaseAlt [] rightPat body Nothing]
      Right (ECase sp e' arms [])
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
    go (DoExpr esp _ : _ : _) = Left (DesugarBindNameStillUsed esp "<non-final-expr>")

    -- Source-position-derived suffix used to make the synthetic Left
    -- error binder unique across nested do-binds. Same-module no-
    -- shadowing would otherwise reject two binds with the same
    -- generated name in scope at once.
    spanTag s =
      show (spanStartLine s) <> "_" <> show (spanStartCol s)

-- | Rewrite any 'ParamPat' parameter into a fresh 'Param' plus a
--   single-arm 'ECase' wrapping the body that destructures the
--   synthesised name back to the user-written pattern. After this
--   pass, the AST contains only 'Param' bindings — typecheck and
--   lowering never see destructuring patterns at parameter
--   positions.
--
--   Each 'ParamPat' contributes one nesting level to the body:
--   given @f (Tuple3 a b c) (Just x) = body@, lifting produces
--   @f $arg_<sp1> $arg_<sp2> = case $arg_<sp1> of Tuple3 a b c ->
--   case $arg_<sp2> of Just x -> body@. Exhaustiveness is then
--   validated by the standard 'caseArmsNominal' machinery —
--   single-constructor types pass trivially; refutable patterns
--   (e.g. @Just x@ on a 'Maybe') raise 'NonExhaustiveCase'.
--
--   The synthetic name uses the original 'ParamPat' span so two
--   destructuring parameters in the same function don't collide.
liftParamPatterns :: [Param] -> Expr -> ([Param], Expr)
liftParamPatterns params body =
  let (params', wrappers) = foldr step ([], id) params
   in (params', wrappers body)
  where
    step :: Param -> ([Param], Expr -> Expr) -> ([Param], Expr -> Expr)
    step (Param sp n) (ps, wrap) = (Param sp n : ps, wrap)
    step (ParamPat sp pat) (ps, wrap) =
      let n = "$arg_" <> show (spanStartLine sp) <> "_" <> show (spanStartCol sp)
          newWrap inner =
            ECase
              sp
              (EVar sp (QName [] n))
              (CaseAlt [] pat (wrap inner) Nothing :| [])
              []
       in (Param sp n : ps, newWrap)

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
rewriteLet :: SrcSpan -> Pattern -> Maybe Type' -> Expr -> Expr -> Either DesugarError Expr
rewriteLet sp pat mAnnot e' body' = case pat of
  PVar _ _ -> Right (ELet sp pat mAnnot e' body')
  PWild _ -> Right (ELet sp pat mAnnot e' body')
  _ -> case mAnnot of
    Just _ -> Left (DesugarPatternLetAscription sp)
    Nothing ->
      Right (ECase sp e' (CaseAlt [] pat body' Nothing :| []) [])
