-- | Surface /renderer/ (pretty-printer) for 'Awsum.Syntax'.
--
-- Layout is handled by @prettyprinter@ (a 'Doc' is built, then projected to
-- text once) rather than hand-rolled string concatenation — the same shape the
-- JS backend's 'Awsum.Codegen.JS.Syntax' uses. The formatter is /not/
-- width-adaptive: every line break is a 'hardline' chosen structurally (a
-- @let@ always splits to two lines, @case@ is always multi-line, a @|>@ chain
-- of three or more links is always multi-line), never by a page-width budget —
-- so there is no 'group' anywhere and the page width is 'Unbounded'. This keeps
-- the output a fixed point of the layout-sensitive parser: @parse ∘ render@ is
-- the identity and the formatter is idempotent (asserted in the test suite).
--
-- Indentation rides prettyprinter's /nesting level/: there is no threaded
-- @indent@ column. Wherever the surface grammar nests a block (case arms below
-- @of@, @do@ statements, @let@ bindings), the renderer wraps the broken part in
-- @nest k@, so a @hardline@ lands at exactly the right column with no explicit
-- padding. The two places a line's /prefix/ is indented deeper than the body's
-- own baseline — a @FunDef@ whose @=@ carries a trailing comment, and the
-- @|>@ steps of a pipe chain — keep that prefix as literal spaces so the body
-- keeps the shallower baseline the parser established for it.
--
-- Precedence (low → high):
--   1. @|>@          (left-associative; lowest)
--   2. @++@          (left-associative)
--   3. application   (left-associative)
--   4. atoms
--
-- Notes:
--   • We add a trailing newline to the whole program for friendlier CLI UX.
--   • String escaping matches the parser: \n \t \r \" \\ \0
module Awsum.Render
  ( renderProgram,
    renderDecl,
    renderType,
    renderExpr,
  )
where

import Awsum.Pretty (layoutUnbounded, vsepBlank, vsepHard)
import Awsum.Syntax
import Data.Char qualified as Char
import Data.Text qualified as T
import Prettyprinter
  ( Doc,
    align,
    hardline,
    hsep,
    nest,
    parens,
    rparen,
    vsep,
  )
import Prettyprinter.Internal qualified as PPI
import Relude

-- | Like prettyprinter's 'pretty' for 'Text': reports each line's width in
--   /code points/ ('Data.Text.length') to the layout engine. The renderer's
--   only column-sensitive combinator is 'align' (in 'renderLetBlock'), and the
--   Awsum parser tracks layout columns in code points too (see
--   "Awsum.SrcStream"), so the nesting 'align' pins matches the columns a
--   re-parse sees — @parse ∘ render@ stays the identity for any Unicode,
--   including a wide character before a layout anchor. (Equivalent to 'pretty';
--   kept as a named helper so the per-line split and single-'Char' path stay
--   explicit.)
dtext :: Text -> Doc ann
dtext = vsep . map lineDoc . T.splitOn "\n"
  where
    lineDoc :: Text -> Doc ann
    lineDoc t = case toString t of
      [] -> PPI.Empty
      [c] -> PPI.Char c
      _ -> PPI.Text (T.length t) t

-- ── Public fragment renderers ───────────────────────────────────────────────
-- These project the internal 'Doc' builders to text. 'renderProgram' (below)
-- is the whole-file entry point; these three render one node for consumers
-- that embed it in their own text (e.g. 'Awsum.Lsp' hover for 'renderType').

-- | Render a top-level declaration to text (no trailing newline).
renderDecl :: Decl -> Text
renderDecl = layoutUnbounded . declDoc

-- | Render a type to text (no trailing newline).
renderType :: Type' -> Text
renderType = layoutUnbounded . typeDoc

-- | Render an expression to text (no trailing newline).
renderExpr :: Expr -> Text
renderExpr = layoutUnbounded . exprDoc

-- | A trailing @-- comment@, or nothing.
renderTrailingComment :: Maybe Text -> Doc ann
renderTrailingComment = maybe mempty (\c -> " --" <> dtext c)

-- ── Program ─────────────────────────────────────────────────────────────────

-- | Render a whole program.
--   Emits the optional @{- module comment -}@ followed by a blank line,
--   then imports (if any), then a blank line, then top-level
--   declarations. Separates top-level definitions with a blank line.
--   Keeps a type signature attached to its definition. Always ends
--   with a trailing newline.
renderProgram :: Program -> Text
renderProgram Program {moduleComment, imports, decls} =
  layoutUnbounded doc
  where
    ims = fmap renderImport imports
    body = vsepBlank (groupDeclBlocks (toList decls)) <> hardline
    afterHeader = case ims of
      [] -> body
      _ -> vsepHard ims <> hardline <> hardline <> body
    doc = case moduleComment of
      Nothing -> afterHeader
      Just txt -> "{-" <> dtext txt <> "-}" <> hardline <> hardline <> afterHeader

-- | Group a type signature with the immediately following definition
--   (when they share the same name) so they render as a single block, and
--   group a run of source-adjacent top-level comments (no blank line
--   between them — e.g. a commented-out definition) into one block so the
--   blank-line block separator doesn't wedge a gap between every line. All
--   other top-level items become their own blocks. Blocks are then
--   separated by a blank line by 'renderProgram'.
groupDeclBlocks :: [Decl] -> [Doc ann]
groupDeclBlocks = \case
  (sig@(Sig _ n _ _ _) : def@(FunDef _ n' _ _ _ _) : rest)
    | n == n' ->
        (declDoc sig <> hardline <> declDoc def) : groupDeclBlocks rest
  (c@(CommentDecl _ _) : rest) ->
    -- A blank line in the source breaks the run, so the author's paragraph
    -- break between two comment blocks survives as a block boundary.
    let (more, rest') = takeAdjacentComments (declSpan c) rest
     in vsepHard (map declDoc (c : more)) : groupDeclBlocks rest'
  (d : rest) ->
    declDoc d : groupDeclBlocks rest
  [] -> []
  where
    takeAdjacentComments :: SrcSpan -> [Decl] -> ([Decl], [Decl])
    takeAdjacentComments prev (c@(CommentDecl _ _) : rest)
      | spansAdjacent prev (declSpan c) =
          let (more, rest') = takeAdjacentComments (declSpan c) rest
           in (c : more, rest')
    takeAdjacentComments _ rest = ([], rest)

-- | Render a single import (with optional leading comments and trailing comment).
renderImport :: ImportDecl -> Doc ann
renderImport (ImportDecl comments mods tcom) =
  let commentLines = map renderComment comments
      importLine = "import " <> dtext (T.intercalate "." (toList mods)) <> renderTrailingComment tcom
   in case commentLines of
        [] -> importLine
        _ -> vsepHard commentLines <> hardline <> importLine

-- | Render a top-level declaration. A leading doc comment (if any)
--   prints first in canonical @{- … -}@ block form, on its own line(s),
--   followed by the declaration body. Authoring style is /input only/:
--   regardless of whether the source had @-- doc@ lines or a @{- doc -}@
--   block, the formatted output is always block form.
declDoc :: Decl -> Doc ann
declDoc = \case
  Sig _sp name ty mc doc ->
    renderDocComment doc
      <> declDocName name
      <> " : "
      <> typeDoc ty
      <> renderTrailingComment mc
  FunDef _sp name args e mc doc ->
    let header = case args of
          [] -> declDocName name
          _ -> declDocName name <> " " <> hsep (map renderParam args)
        -- A FunDef's trailing comment must land on the '=' line, not
        -- after the body — the parser only looks for it through
        -- 'tcomBeforeBody'. The hazard isn't only direct ECase / EDo
        -- bodies: any body whose render ends inside a block-form's
        -- last arm/stmt (e.g. an ELam whose body is ECase) would
        -- otherwise let the FunDef comment fuse with the inner arm's
        -- trailing comment on the same line. 'rendersMultiLine'
        -- captures the same predicate the rest of the renderer uses.
        bodyAndComment = case e of
          ELet {} ->
            let (binds, finalBody) = collectLetChain e
             in " =" <> renderTrailingComment mc <> nest 2 (hardline <> renderLetBlock 0 binds finalBody)
          _
            | rendersMultiLine e ->
                case mc of
                  -- Body on a fresh line at column 2, but rendered at
                  -- nesting 0 (literal "  " prefix, not 'nest 2'): the
                  -- body keeps the left-margin baseline the parser
                  -- expects, so e.g. a case's arms land at column 2,
                  -- aligned under the body's own first token.
                  Just _ -> " =" <> renderTrailingComment mc <> hardline <> "  " <> exprDoc e
                  Nothing -> " = " <> exprDoc e
            | otherwise -> " = " <> exprDoc e <> renderTrailingComment mc
     in renderDocComment doc <> header <> bodyAndComment
  TypeDecl _sp name tvars cons mc emptyKind doc ->
    -- 'EmptyKind' = 'Empty' renders the @empty type X@ form, where the
    -- parser has already enforced that 'tvars' and 'cons' are both
    -- empty. Plain 'NotEmpty' renders as @type X …@ with whatever
    -- params and constructors the user wrote (zero or more of each).
    --
    -- Constructor list layout: zero, one or two constructors stay on
    -- the header line (@type Foo = A | B@); three or more flip to a
    -- multi-line form with @=@ and each subsequent @|@ on a fresh line
    -- at indent 2. The threshold is a fixed cliff rather than a
    -- column-width budget — readable, deterministic, no column tracking
    -- required. Trailing @-- comment@ docks on the final line in both
    -- shapes.
    let prefix = case emptyKind of
          Empty -> "empty type "
          NotEmpty -> "type "
        head' =
          prefix
            <> dtext name
            <> (if null tvars then "" else " " <> hsep (map (dtext . paramName) tvars))
        body = case cons of
          [] -> ""
          [c] -> " = " <> renderConDef c
          [c1, c2] -> " = " <> renderConDef c1 <> " | " <> renderConDef c2
          (c1 : rest) ->
            hardline
              <> "  = "
              <> renderConDef c1
              <> mconcat (map (\c -> hardline <> "  | " <> renderConDef c) rest)
     in renderDocComment doc <> head' <> body <> renderTrailingComment mc
  CommentDecl _sp c ->
    renderComment c
  where
    renderConDef (ConDef _ n []) = dtext n
    -- Constructor fields are parsed by 'pTypeAtomNoLineComments' — only
    -- atomic types (TyVar / TyCon / parenthesised). Anything more
    -- complex (TyApp like @IO e a@, TyArrow, TyOr) MUST be parenthesised
    -- on output, otherwise @parse . render@ produces a different AST
    -- (e.g. @Con String IO e a@ would become four single-token fields
    -- instead of @[String, IO e a]@). Using precedence 4 (atom) here
    -- forces the renderer to wrap any non-atom in parens.
    renderConDef (ConDef _ n fs) = dtext n <> " " <> hsep (map (typeDocPrec 4) fs)

-- | Wrap a top-level declaration name in parens when it's an operator
--   (e.g. @"++"@ renders as @(++)@), so @renderProgram . parseProgram@ is
--   a fixpoint on files that declare operators in the prelude style.
declDocName :: Name -> Doc ann
declDocName n
  | T.null n = dtext n
  | isBinderStart (T.head n) = dtext n
  | otherwise = "(" <> dtext n <> ")"
  where
    isBinderStart c = Char.isLower c || c == '_'

renderComment :: Comment -> Doc ann
renderComment = \case
  LineComment t -> "--" <> dtext t
  BlockComment t ->
    let trimmed = T.strip t
     in if T.null trimmed then "{- -}" else "{- " <> dtext trimmed <> " -}"

-- | Render an attached doc comment as a single @{- text -}@ block
--   followed by a newline (so the next declaration starts on its own
--   line). 'Nothing' renders empty, letting 'declDoc' call this
--   unconditionally. Author line breaks are preserved verbatim — the
--   formatter does not reflow markdown.
renderDocComment :: Maybe Text -> Doc ann
renderDocComment Nothing = ""
renderDocComment (Just t) = "{- " <> dtext t <> " -}" <> hardline

-- ── Types ───────────────────────────────────────────────────────────────────

-- | Entry point for types (uses a small precedence machine).
typeDoc :: Type' -> Doc ann
typeDoc = typeDocPrec 0

-- | @ctx@ is the precedence context we are printing into:
--   0 (top) < 1 (|) < 2 (->) < 3 (app) < 4 (atom).
--   We parenthesize when the inner precedence is strictly lower than the context.
typeDocPrec :: Int -> Type' -> Doc ann
typeDocPrec ctx = \case
  TyVar _ n -> dtext n
  TyCon _ n -> dtext n
  -- 'TyEmpty' renders as the user-written name. The @empty@ keyword
  -- only appears at the type's /declaration/ site (handled by the
  -- 'TypeDecl' branch above); references in signatures and
  -- expressions look like ordinary type-constructor references.
  TyEmpty _ n -> dtext n
  TyApp _ f x ->
    let s = typeDocPrec 3 f <> " " <> typeDocPrec 4 x
     in if 3 < ctx then parens s else s
  TyArrow _ t1 t2 ->
    let l = typeDocPrec 3 t1
        r = typeDocPrec 2 t2
        s = l <> " -> " <> r
     in if 2 < ctx then parens s else s
  TyOr _ t1 t2 ->
    -- @|@ is lower precedence than @->@, so a 'TyOr' on the LHS of an
    -- arrow needs parens (caller's @ctx@ pushes us above 1) and our own
    -- branches render at arrow-level (2): an arrow inside @T1 | T2@
    -- prints unparenthesised (`A -> B | C` re-parses to `(A -> B) | C`,
    -- the original AST), but a nested 'TyOr' on the LHS does need parens
    -- to preserve grouping when re-parsed.
    let l = typeDocPrec 2 t1
        r = typeDocPrec 1 t2
        s = l <> " | " <> r
     in if 1 < ctx then parens s else s

-- ── Expressions ─────────────────────────────────────────────────────────────

-- | Entry point for expressions (small precedence machine mirroring the parser).
exprDoc :: Expr -> Doc ann
exprDoc = exprDocPrec 0

-- | @ctx@ is the precedence context:
--   0 (top) < 1 (++) < 2 (app) < 3 (atom).
--   We parenthesize when inner precedence is strictly lower than @ctx@.
--   Indentation is carried by prettyprinter's nesting level (see the module
--   header): a block form wraps its broken part in @nest k@ so each 'hardline'
--   lands at the right column. Multi-line forms in a nested position close
--   their @)@ on a fresh 'hardline' so a trailing @--@ on the inner block's
--   last arm can't swallow it (the parser accepts @)@ on a fresh line via
--   'pParensNoLineComments').
--   Special case: explicit 'EParens' are always preserved verbatim to make
--   parse ∘ render round-trip possible in tests.
exprDocPrec :: Int -> Expr -> Doc ann
exprDocPrec ctx e =
  case e of
    EParens _sp e' ->
      -- Preserve user parentheses exactly as written. When the inner's
      -- render is multi-line — ECase / EDo at any depth inside,
      -- including through nested 'EParens' — close ')' on a fresh line.
      -- Otherwise a trailing '--' on the inner's last arm would eat the
      -- ')', and outer renderings would diverge between the original AST
      -- and the re-parsed (EParens-decorated) AST.
      let inner = exprDocPrec 0 e'
       in if rendersMultiLine e'
            then "(" <> inner <> hardline <> rparen
            else parens inner
    EAscribe _sp e' ty ->
      -- Expression-level type ascription: @(e : T)@. Renders verbatim
      -- with the parens — the parser only accepts ascription wrapped in
      -- parens, and ascription syntax ALWAYS uses parens. Multi-line
      -- inner expressions take the same fresh-line ')' treatment as
      -- 'EParens', with the type on that closing line.
      let inner = exprDocPrec 0 e'
       in if rendersMultiLine e'
            then "(" <> inner <> hardline <> " : " <> typeDoc ty <> rparen
            else "(" <> inner <> " : " <> typeDoc ty <> ")"
    ECase _sp scrut alts trailingComments ->
      -- Case is always at top precedence; parenthesize if nested. Arms
      -- sit at @nest 2@ below the 'case' line; their column is fixed by
      -- the first arm, which the parser reads after 'of', so this works
      -- regardless of where 'case' lands on the line. Scrutinee renders
      -- at ctx=1 because the parser's scrutinee grammar accepts only
      -- atoms, applications and '++' chains — block forms must be
      -- parenthesised or they don't reparse.
      let s = "case " <> exprDocPrec 1 scrut <> " of" <> nest 2 (hardline <> renderCaseAlts alts trailingComments)
       in if 0 < ctx then "(" <> s <> hardline <> rparen else s
    ELam _sp params body ->
      -- Lambda body extends as far right as possible — same precedence
      -- as 'case', so nested usage adds parens. When the lambda is
      -- itself wrapped in parens, render the body at ctx=1 so any
      -- block-form body (ECase/EDo) gets its own paren wrapping,
      -- preventing a trailing '--' on a nested case arm from eating the
      -- lambda's closing paren.
      let bodyCtx = if 0 < ctx then 1 else 0
          s = "\\" <> hsep (map renderParam params) <> " -> " <> exprDocPrec bodyCtx body
       in if 0 < ctx
            then
              if rendersMultiLine body
                then "(" <> s <> hardline <> rparen
                else parens s
            else s
    EDo _sp stmts ->
      -- Same fresh-line ')' trick as 'ECase' — the last DoStmt
      -- (typically a DoExpr containing a case) might end on a trailing
      -- comment that would otherwise swallow the ')'.
      let s = "do" <> nest 2 (hardline <> vsepHard (map renderDoStmt stmts))
       in if 0 < ctx then "(" <> s <> hardline <> rparen else s
    ELet {} ->
      -- Nested 'let' (not the function-body position handled in
      -- 'declDoc FunDef'). Single-binding renders as a 2-line block;
      -- a chain of nested 'ELet's collapses to an inline chain so it
      -- stays compact when embedded inside arguments or other
      -- expressions.
      --
      -- 'bodyCtx' is 1 when this 'ELet' is itself in a nested position:
      -- a block-form body (ECase / EDo) then wraps itself in parens. The
      -- wrapping at @ctx > 0@ also closes ')' on a fresh line, since the
      -- let-block body ends on its own line.
      let (binds, finalBody) = collectLetChain e
          bodyCtx = if 0 < ctx then 1 else 0
          -- An own-line signature forces the vertical block layout (the
          -- inline chain has nowhere to put a separate signature line);
          -- otherwise a single binding still gets the 2-line block and a
          -- multi-binding chain stays compact on one line.
          s
            | any isOwnLineBind binds = renderLetBlock bodyCtx binds finalBody
            | [single] <- binds = renderLetBlock bodyCtx [single] finalBody
            | otherwise = renderLetInlineChain bodyCtx binds finalBody
       in if 0 < ctx then "(" <> s <> hardline <> rparen else s
    _ ->
      let (prec, s) = case e of
            EVar _sp' q -> (3, renderQName q)
            ELit _sp' (LString t) -> (3, dtext ("\"" <> escape t <> "\""))
            ELit _sp' (LInt n) -> (3, dtext (renderInteger n))
            ECon _sp' n -> (3, dtext n)
            EBuiltIn _sp' n -> (3, "BuiltIn." <> dtext n)
            -- Application is left-assoc: print f at prec 2, arg at atom-precedence
            -- so nested apps on the right get parenthesized.
            EApp _sp' f x ->
              let f' = exprDocPrec 2 f
                  x' = exprDocPrec 3 x
               in (2, f' <> " " <> x')
            -- For left-assoc @++@: we print the right operand at a tighter
            -- context (2) so a chained ++ on the right becomes parenthesized.
            -- This preserves the original associativity in round-trips.
            EInfix _sp' OpConcat l r ->
              let l' = exprDocPrec 1 l
                  r' = exprDocPrec 2 r
               in (1, l' <> " ++ " <> r')
            -- @|>@ is the lowest-precedence binary operator (prec 0).
            -- Left-assoc: the right operand prints at ctx 1, so a nested
            -- @|>@ on the right wraps — preserving associativity. A
            -- nested @++@ on the right (prec 1) does /not/ wrap, so
            -- @x |> a ++ b@ round-trips unchanged.
            --
            -- The left operand prints at ctx 1 too, so @\\…@, @let@,
            -- @do@, @case@ wrap into parens — without that, the parser's
            -- greedy-rightward rule for those forms would swallow the
            -- @|> r@ tail and re-parse to a different tree. The exception
            -- is a nested @|>@ on the left, which we want to /not/ wrap
            -- (so the left-assoc chain stays flat); we render it at ctx 0.
            --
            -- Chains of three or more @|>@ operators render multi-line
            -- (one operator per line, leading the continuation), so
            -- pipelines read top-down in execution order. The @|>@ prefix
            -- sits two columns in (a literal "  " on the 'hardline'),
            -- while each step keeps the chain's own nesting baseline so a
            -- multi-line step doesn't drift rightward.
            e'@(EInfix _ OpPipe _ _) ->
              let chain = collectPipeChain e'
               in if length chain >= 3
                    then
                      let headExpr :| tailExprs = chain
                          firstStr = exprDocPrec 1 headExpr
                          stepStr step = hardline <> "  |> " <> exprDocPrec 1 step
                       in (0, firstStr <> mconcat (map stepStr tailExprs))
                    else
                      let EInfix _ _ l r = e'
                          lCtx = case l of
                            EInfix _ OpPipe _ _ -> 0
                            _ -> 1
                          l' = exprDocPrec lCtx l
                          r' = exprDocPrec 1 r
                       in (0, l' <> " |> " <> r')
       in if prec < ctx
            -- Multi-line @s@ wrapped flat would let the inner block's
            -- last line fuse with the closing ')' (and any subsequent
            -- ' -- comment'). When the body is multi-line, close ')' on a
            -- fresh line — same shape as 'EParens' above.
            then
              if rendersMultiLine e
                then "(" <> s <> hardline <> rparen
                else parens s
            else s
  where
    -- Matches the parser's escape table.
    escape :: Text -> Text
    escape = T.concatMap $ \c -> case c of
      '\n' -> "\\n"
      '\t' -> "\\t"
      '\r' -> "\\r"
      '\"' -> "\\\""
      '\\' -> "\\\\"
      '\0' -> "\\0"
      _ -> one c

renderCaseAlts :: NonEmpty CaseAlt -> [Comment] -> Doc ann
renderCaseAlts alts trailingComments =
  vsepHard (map renderCaseAlt (toList alts) <> map renderComment trailingComments)
  where
    renderCaseAlt = \case
      CaseAltLeaf leadingComments pat body mc ->
        vsepHard
          ( map renderComment leadingComments
              <> [renderPattern pat <> " -> " <> exprDocPrec 0 body <> renderTrailingComment mc]
          )
      CaseAltBlock leadingComments pat body ->
        vsepHard
          ( map renderComment leadingComments
              <> [renderPattern pat <> " -> " <> exprDocPrec 0 body]
          )

-- | Render a single 'do' statement.
renderDoStmt :: DoStmt -> Doc ann
renderDoStmt = \case
  DoBind _ pat e -> renderPattern pat <> " <- " <> exprDocPrec 0 e
  DoLet _ pat mAnnot e ->
    let patD = renderPatternAtom pat
        rhsD = exprDocPrec 0 e
     in case mAnnot of
          -- Own-line signature: the definition aligns under the binder
          -- (one nest deeper than the do-statement column), matching the
          -- parser's 'refCol' so it round-trips and the layout doesn't
          -- read the definition line as a new statement.
          Just (t, OwnLineSig) ->
            "let " <> patD <> " : " <> typeDoc t <> nest 4 (hardline <> patD <> " = " <> rhsD)
          Just (t, InlineSig) -> "let " <> patD <> " : " <> typeDoc t <> " = " <> rhsD
          Nothing -> "let " <> patD <> " = " <> rhsD
  -- ctx=1 so block forms at the head of a DoExpr (specifically ELet)
  -- get wrapped in parens. Without that wrap, the parser's 'pDoLet'
  -- greedily consumes 'let pat = expr' as a do-block-let and leaves
  -- the trailing 'in body' stranded; explicit parens force the full
  -- expression parser to handle 'let pat = expr in body' as one atom.
  DoExpr _ e -> exprDocPrec 1 e

-- ── Let-block helpers ───────────────────────────────────────────────────────

-- | Walk a chain of nested 'ELet's and return the bindings in source
--   order plus the eventual non-'ELet' body. Each binding carries
--   its optional type ascription.
collectLetChain :: Expr -> ([(SrcSpan, Pattern, Maybe (Type', LetSigLayout), Expr)], Expr)
collectLetChain = \case
  ELet sp pat mAnnot rhs body ->
    let (rest, finalBody) = collectLetChain body
     in ((sp, pat, mAnnot, rhs) : rest, finalBody)
  other -> ([], other)

-- | Does this binding carry an own-line signature (rendered over two
--   lines)? A let-chain with any such binding stays in the vertical block
--   layout — the inline-chain form has no place for a separate signature
--   line.
isOwnLineBind :: (SrcSpan, Pattern, Maybe (Type', LetSigLayout), Expr) -> Bool
isOwnLineBind (_, _, Just (_, OwnLineSig), _) = True
isOwnLineBind _ = False

-- | Render a let-block in Haskell-style layout. The caller positions the
--   @let@ keyword; everything else is offset from the /nesting baseline/
--   in effect at that point (which the caller sets with @nest@):
--
-- @
--     let n1 = e1        -- bindings after "let " (baseline+4 for breaks)
--         n2 = e2        -- baseline+4
--      in body           -- "in" at baseline+1, body at baseline+4
-- @
--
--   Single-binding still gets the 2-line shape — the user opted in to
--   "split into 2 lines" for every let.
renderLetBlock :: Int -> [(SrcSpan, Pattern, Maybe (Type', LetSigLayout), Expr)] -> Expr -> Doc ann
renderLetBlock bodyCtx binds finalBody = wrap letBlock
  where
    -- An own-line-signature binding needs its definition line at the
    -- binder column exactly. 'align' pins the block's nesting to the
    -- column where 'let' starts, so that holds in a nested expression
    -- position too (where the starting column isn't the ambient nesting
    -- level). InlineSig-only blocks have no second binding line to align
    -- and render exactly as before, so the common case is untouched.
    wrap = if any isOwnLineBind binds then align else id
    letBlock =
      "let "
        <> nest 4 bindsBlock
        -- "in" sits one column in from the baseline; "in " is three chars,
        -- so the body begins at baseline+4 — 'nest 3' (atop the enclosing
        -- 'nest 1') puts the body's own breaks there too.
        <> nest 1 (hardline <> "in " <> nest 3 (exprDocPrec bodyCtx finalBody))
    -- First binding follows "let " on the same line; each subsequent
    -- binding lands on a fresh line at the binding column (baseline+4).
    -- An own-line-signature binding (rendered over two lines) is fenced
    -- by a blank line on each interior side: we break twice between two
    -- bindings when either neighbour is two-line, once otherwise — so
    -- single-line bindings pack and a two-line one reads as its own
    -- paragraph. The 'let' head and the dedented 'in' are the outer
    -- bounds, so no blank line leads the first binding or trails the last.
    bindsBlock = case binds of
      [] -> error "renderLetBlock called with no bindings"
      (b0 : _) ->
        bindDoc b0
          <> mconcat
            [ (if twoLine prev || twoLine cur then hardline <> hardline else hardline) <> bindDoc cur
            | (prev, cur) <- zip binds (drop 1 binds)
            ]
    twoLine (_, _, Just (_, OwnLineSig), _) = True
    twoLine _ = False
    -- Bind RHS at ctx=0 — like a function body after '=' — so a block-form RHS
    -- (do / case / let / lambda) and a '|>' chain render without enclosing
    -- parens; the 'in' on its own dedented line (and the next binding) is
    -- unambiguous by layout. The exception is a RHS whose last line ends in a
    -- bare '--' comment: the 'NoLineComments' RHS parser stops at the comment
    -- and never reaches the 'in', so 'tailHasComment' forces ctx=1 (parens)
    -- there, and only there. (Explicit user parens are preserved — see EParens.)
    --
    -- 'OwnLineSig' puts the signature on its own line above the binding (both
    -- at the binding column); 'InlineSig' keeps 'n : T = e' on one line. The
    -- author's choice is preserved, not normalised.
    bindDoc (_, pat, mAnnot, rhs) =
      let patD = renderPatternAtom pat
          rhsD = exprDocPrec (if tailHasComment rhs then 1 else 0) rhs
       in case mAnnot of
            Just (t, OwnLineSig) ->
              patD <> " : " <> typeDoc t <> hardline <> patD <> " = " <> rhsD
            Just (t, InlineSig) ->
              patD <> " : " <> typeDoc t <> " = " <> rhsD
            Nothing ->
              patD <> " = " <> rhsD

-- | Render a chain of 'ELet's as a single inline string @let n1 = e1
--   in let n2 = e2 in body@. Used when the chain appears in a nested
--   position (function argument, infix operand, etc.) where the
--   layout form would be hard to align without column tracking.
renderLetInlineChain :: Int -> [(SrcSpan, Pattern, Maybe (Type', LetSigLayout), Expr)] -> Expr -> Doc ann
renderLetInlineChain bodyCtx binds finalBody =
  mconcat
    -- RHS at ctx=1: the inline ' in ' follows on the same line, so a block-form
    -- RHS must wrap itself in parens so a trailing '--' doesn't eat it.
    [ "let " <> renderPatternAtom pat <> annotText mAnnot <> " = " <> exprDocPrec 1 rhs <> " in "
    | (_, pat, mAnnot, rhs) <- binds
    ]
    <> exprDocPrec bodyCtx finalBody
  where
    -- Only reached for chains with no own-line signature (those route to
    -- 'renderLetBlock'), so the layout tag is always 'InlineSig' here —
    -- the ascription renders on the same line either way.
    annotText = maybe "" (\(t, _) -> " : " <> typeDoc t)

renderPattern :: Pattern -> Doc ann
renderPattern = \case
  PCon _ n [] -> dtext n
  PCon _ n ps -> dtext n <> " " <> hsep (map renderPatternAtom ps)
  PVar _ n -> dtext n
  PWild _ -> "_"
  PAscribe _ p ty -> "(" <> renderPattern p <> " : " <> typeDoc ty <> ")"

-- | Render an atomic pattern, parenthesizing nested constructor applications.
--   'PAscribe' is already self-parenthesised by 'renderPattern' so it's
--   already an atom; no extra parens are needed here.
renderPatternAtom :: Pattern -> Doc ann
renderPatternAtom p@(PCon _ _ (_ : _)) = "(" <> renderPattern p <> ")"
renderPatternAtom p = renderPattern p

-- | Render a function parameter. 'Param' (the common simple-name case)
--   prints as the bare identifier. 'ParamPat' (destructuring patterns)
--   always round-trips inside parentheses — the parens are
--   syntactically required at the param-binder level so the pattern can
--   be distinguished from a sequence of bare-name parameters.
renderParam :: Param -> Doc ann
renderParam (Param _ n) = dtext n
-- 'ParamPat (PVar n)' is equivalent to 'Param n' (the parser
-- canonicalises @(x)@ back to a bare binder); render it without
-- parens so the formatter is idempotent at the text level.
renderParam (ParamPat _ (PVar _ n)) = dtext n
-- A type-ascription parameter @(x : T)@ is already self-parenthesised
-- by 'renderPattern' (the @PAscribe@ case wraps in parens), so adding
-- another pair would print @((x : T))@.
renderParam (ParamPat _ p@(PAscribe {})) = renderPattern p
renderParam (ParamPat _ pat) = "(" <> renderPattern pat <> ")"

-- | Renderer-side companion: @True@ iff the rendered text spans
--   multiple lines. An AST predicate (not a check on rendered text),
--   so it can be consulted before laying out — it decides where a
--   FunDef's trailing comment lands and where a nested form closes its
--   @)@. Differs from a parser-side notion on 'EParens': outer parens
--   around a block form still render multi-line.
rendersMultiLine :: Expr -> Bool
rendersMultiLine = \case
  ECase {} -> True
  EDo {} -> True
  ELet {} -> True
  ELam _ _ body -> rendersMultiLine body
  EApp _ f x -> rendersMultiLine f || rendersMultiLine x
  e@(EInfix _ OpPipe _ _) | length (collectPipeChain e) >= 3 -> True
  EInfix _ _ a b -> rendersMultiLine a || rendersMultiLine b
  EParens _ inner -> rendersMultiLine inner
  EAscribe _ inner _ -> rendersMultiLine inner
  EVar {} -> False
  ELit {} -> False
  ECon {} -> False
  EBuiltIn {} -> False

-- | Whether this expression, rendered at ctx 0, ends its last line with a bare
--   (unparenthesised) trailing @--@ comment. In a let-binding RHS such a tail
--   would swallow the @in@ — or the next binding — on the following line, since
--   the @NoLineComments@ RHS parser stops at the comment. 'renderLetBlock'
--   wraps only those RHS in parens; everything else renders bare. Mirrors the
--   recursion of 'rendersMultiLine': a comment can surface as the tail only
--   through a @case@ arm (its own trailing comment, or a case-level trailing
--   comment), or by being the tail of a @do@ \/ @let@ \/ lambda whose final
--   sub-expression carries one. Applications, @++@\/@|>@ chains, 'EParens' and
--   'EAscribe' all end in an atom or a @)@ — any block form in those positions
--   is itself parenthesised — so they never leak a comment tail.
tailHasComment :: Expr -> Bool
tailHasComment e = case e of
  ECase _ _ alts trailing
    | not (null trailing) -> True
    | otherwise -> case last alts of
        CaseAltLeaf _ _ _ (Just _) -> True
        CaseAltLeaf _ _ body Nothing -> tailHasComment body
        CaseAltBlock _ _ body -> tailHasComment body
  EDo _ stmts -> maybe False stmtTail (viaNonEmpty last stmts)
  ELet {} -> tailHasComment (snd (collectLetChain e))
  ELam _ _ body -> tailHasComment body
  EApp {} -> False
  EInfix {} -> False
  EParens {} -> False
  EAscribe {} -> False
  EVar {} -> False
  ELit {} -> False
  ECon {} -> False
  EBuiltIn {} -> False
  where
    stmtTail = \case
      DoBind _ _ rhs -> tailHasComment rhs
      DoLet _ _ _ rhs -> tailHasComment rhs
      DoExpr _ inner -> tailHasComment inner

-- | Flatten a left-associative @|>@ chain into the spine of operands
--   (leftmost first). For an expression that is not a pipe at the
--   top, returns the singleton list. The chain is reconstructed so
--   the multi-line renderer can emit one operator per line.
collectPipeChain :: Expr -> NonEmpty Expr
collectPipeChain (EInfix _ OpPipe l r) =
  let lhsHead :| lhsTail = collectPipeChain l
   in lhsHead :| (lhsTail <> [r])
collectPipeChain e = e :| []

-- | Render a qualified or unqualified name.
renderQName :: QName -> Doc ann
renderQName (QName mods n) =
  case mods of
    [] -> dtext n
    _ -> dtext (T.intercalate "." (mods <> [n]))

-- | Canonical form for an integer literal in source.
--   Decimal digits, grouped by 3 from the right, with '_' between groups.
--   Grouping kicks in starting at 4 digits — values with 1–3 digits stay bare
--   ('42', '999'), values from 4 digits up get separators ('1_000',
--   '1_234_567'). Sign is preserved on the outside ('-1_000_000').
renderInteger :: Integer -> Text
renderInteger n
  | n < 0 = "-" <> renderNonNegative (negate n)
  | otherwise = renderNonNegative n
  where
    renderNonNegative :: Integer -> Text
    renderNonNegative k =
      let digits = show k
       in if T.length digits < 4
            then digits
            else
              let len = T.length digits
                  -- Size of the leading (possibly short) group: 1, 2, or 3.
                  firstLen = ((len - 1) `mod` 3) + 1
                  (lead, rest) = T.splitAt firstLen digits
               in lead <> chunksOf3 rest

    chunksOf3 :: Text -> Text
    chunksOf3 t
      | T.null t = ""
      | otherwise =
          let (h, r) = T.splitAt 3 t
           in "_" <> h <> chunksOf3 r
