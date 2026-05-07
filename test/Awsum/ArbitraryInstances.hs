{-# OPTIONS_GHC -Wno-orphans #-}

module Awsum.ArbitraryInstances () where

import Awsum.Syntax
import Data.Char (isAlphaNum, isAsciiLower, isAsciiUpper, toLower, toUpper)
import Data.Text qualified as T
import Relude
import Test.QuickCheck

identTailChar :: Gen Char
identTailChar =
  frequency
    [ (6, elements (['a' .. 'z'] <> ['A' .. 'Z'])),
      (3, elements ['0' .. '9']),
      (1, elements ['_', '\''])
    ]

reserved :: [Text]
reserved =
  [ "import",
    "type",
    "case",
    "of",
    "do",
    "class",
    "instance",
    "where",
    "if",
    "then",
    "else",
    "match",
    "with",
    "let",
    "in",
    "rec"
  ]

mkSafe :: (Char -> Char) -> Gen Text
mkSafe firstCase = sized $ \n -> do
  k <- chooseInt (0, max 0 (min 6 n)) -- tail length
  c0 <- suchThat arbitrary isAlpha -- first char must be a letter
  cs <- vectorOf k identTailChar
  let raw = toText (firstCase c0 : cs)
  if T.toLower raw `elem` reserved then mkSafe firstCase else pure raw
  where
    isAlpha c = isAsciiLower c || isAsciiUpper c

genLIdent :: Gen Name
genLIdent = mkSafe toLower

genUIdent :: Gen Name
genUIdent = mkSafe toUpper

shrinkIdent :: Name -> [Name]
shrinkIdent t =
  let s = toString t
   in [toText (take k s) | k <- [1 .. length s - 1]]

genNonEmpty :: Gen a -> Gen (NonEmpty a)
genNonEmpty g = (:|) <$> g <*> listOf g

shrinkNonEmpty :: (a -> [a]) -> NonEmpty a -> [NonEmpty a]
shrinkNonEmpty sh (x :| xs) =
  -- 1) shrink head
  [x' :| xs | x' <- sh x]
    <>
    -- 2) shrink tail (keeping at least one element)
    [ y :| ys
    | (y : ys) <- shrinkList sh (x : xs),
      not (null (y : ys))
    ]

-- ───────────────────────── Arbitrary instances ─────────────────────────

instance Arbitrary ImportDecl where
  arbitrary = ImportDecl <$> genLeadingComments <*> genNonEmpty genUIdent <*> genComment
  shrink (ImportDecl _ ne _) = ImportDecl [] <$> shrinkNonEmpty shrinkIdent ne <*> pure Nothing

-- | Prefer producing useful types for tests:
--   • 'TyVar' appears often (so polymorphic sigs like 'a -> b -> a' show up),
--   • 'TyCon' is biased toward known ones ("String", "IO"), but can be any UIdent,
--   • 'TyArrow' recurses with smaller sizes.
instance Arbitrary Type' where
  arbitrary = sized go
    where
      go 0 =
        frequency
          [ (3, TyVar noSpan <$> genTyVarName),
            (3, TyCon noSpan <$> genKnownTyCon),
            (2, TyCon noSpan <$> genUIdent)
          ]
      go n =
        frequency
          [ (4, TyVar noSpan <$> genTyVarName),
            (3, TyCon noSpan <$> genKnownTyCon),
            (2, TyCon noSpan <$> genUIdent),
            (3, TyApp noSpan <$> go (n `div` 2) <*> go (n `div` 2)),
            (6, TyArrow noSpan <$> go (n `div` 2) <*> go (n `div` 2)),
            (2, TyOr noSpan <$> go (n `div` 2) <*> go (n `div` 2))
          ]

      -- small, readable type variable names; still valid 'lident'
      genTyVarName :: Gen Name
      genTyVarName =
        frequency
          [ (6, elements (map one ['a' .. 'f'])), -- common short vars
            (4, genLIdent)
          ]

      genKnownTyCon :: Gen Name
      genKnownTyCon = elements ["String", "IO"]

  shrink = \case
    TyVar _ v -> TyVar noSpan <$> shrinkIdent v
    TyCon _ n -> TyCon noSpan <$> shrinkIdent n
    TyApp _ f x ->
      [f, x]
        <> [TyApp noSpan f' x | f' <- shrink f]
        <> [TyApp noSpan f x' | x' <- shrink x]
    TyArrow _ a b ->
      [a, b]
        <> [TyArrow noSpan a' b | a' <- shrink a]
        <> [TyArrow noSpan a b' | b' <- shrink b]
    TyOr _ a b ->
      [a, b]
        <> [TyOr noSpan a' b | a' <- shrink a]
        <> [TyOr noSpan a b' | b' <- shrink b]

instance Arbitrary QName where
  arbitrary = do
    -- 0..2 module segments (UIdent), then name (lident)
    k <- frequency [(3, pure 0), (2, pure 1), (1, pure 2)]
    mods <- replicateM k genUIdent
    QName mods <$> genLIdent
  shrink (QName ms n) =
    -- shrink module prefix and the base name
    [QName (take i ms) n | i <- [0 .. length ms - 1]]
      <> [QName ms n' | n' <- shrinkIdent n]

genStr :: Gen Text
genStr = do
  k <- chooseInt (0, 8)
  let ok c = isAlphaNum c || c == ' ' || c == '_' || c == '-' -- avoid quotes/backslash
  toText <$> vectorOf k (suchThat arbitrary ok)

-- | Single-line comment text. Empty texts are valid in the AST but
--   the renderer emits them as a bare @--@ that the parser
--   canonicalises back to 'Nothing'; the property's normaliser
--   ('normalizeTrailing') matches that on both sides, so empty
--   texts round-trip too.
genCommentText :: Gen Text
genCommentText = genStr

genComment :: Gen (Maybe Text)
genComment = frequency [(3, pure Nothing), (1, Just <$> genCommentText)]

-- | Generator for the text inside a 'BlockComment' that survives the
--   render→parse round-trip. The renderer wraps the trimmed body as
--   @{- body -}@ (single spaces around it), and the parser captures
--   everything between the delimiters verbatim — so the AST text
--   must be @" body "@ (one space, no-whitespace-on-edges body, one
--   space). Force that shape here.
genBlockCommentText :: Gen Text
genBlockCommentText = do
  inner <- genCommentText `suchThat` (not . T.null . T.strip)
  pure (" " <> T.strip inner <> " ")

-- | A single comment node — line or block.
genCommentNode :: Gen Comment
genCommentNode =
  oneof
    [ LineComment <$> genCommentText,
      BlockComment <$> genBlockCommentText
    ]

-- | Leading-comments list for positions that accept any number of
--   comments before the syntactic element they attach to. Mostly empty
--   so the round-trip property keeps exercising the comment-free
--   shapes too.
genLeadingComments :: Gen [Comment]
genLeadingComments =
  frequency
    [ (4, pure []),
      (2, vectorOf 1 genCommentNode),
      (1, vectorOf 2 genCommentNode)
    ]

genInt :: Gen Integer
genInt =
  frequency
    [ (3, choose (-2147483648, 2147483647)), -- Int32 range
      (2, choose (0, 255)) -- UInt8 range
    ]

-- | Patterns are size-bounded so 'PCon' fields don't explode.
--   Generated forms cover all four surface shapes; type ascriptions
--   carry a (small) 'Type'' and the inner pattern is rendered via
--   'renderPattern' (which already wraps 'PAscribe' in parens).
instance Arbitrary Pattern where
  arbitrary = sized go
    where
      go 0 =
        oneof
          [ PVar noSpan <$> genLIdent,
            PWild noSpan <$ pass,
            PCon noSpan <$> genUIdent <*> pure []
          ]
      go n =
        frequency
          [ (3, PVar noSpan <$> genLIdent),
            (2, pure (PWild noSpan)),
            (3, PCon noSpan <$> genUIdent <*> pure []),
            ( 2,
              do
                k <- chooseInt (1, min 2 n)
                PCon noSpan <$> genUIdent <*> vectorOf k (go (n `div` (k + 1)))
            ),
            (1, PAscribe noSpan <$> go (n `div` 2) <*> resize (n `div` 2) arbitrary)
          ]
  shrink = \case
    PVar _ n -> PVar noSpan <$> shrinkIdent n
    PWild _ -> []
    PCon _ n ps ->
      PCon noSpan n []
        : [PCon noSpan n' ps | n' <- shrinkIdent n]
          <> [PCon noSpan n ps' | ps' <- shrinkList shrink ps]
    PAscribe _ p t -> p : [PAscribe noSpan p' t | p' <- shrink p] <> [PAscribe noSpan p t' | t' <- shrink t]

instance Arbitrary ConDef where
  arbitrary = sized $ \n -> do
    name <- genUIdent
    k <- chooseInt (0, min 2 (max 0 n))
    -- The full 'Type'' arbitrary (including TyApp / TyArrow / TyOr).
    -- The renderer parenthesises non-atomic fields ('renderConDef'
    -- uses precedence 4), so the parse∘render round-trip survives
    -- arbitrary nested types in field position.
    fs <- vectorOf k (resize (n `div` 2) arbitrary)
    pure (ConDef noSpan name fs)
  shrink (ConDef _ n fs) =
    [ConDef noSpan n' fs | n' <- shrinkIdent n]
      <> [ConDef noSpan n (take i fs) | i <- [0 .. length fs - 1]]

instance Arbitrary CaseAlt where
  arbitrary = sized $ \n -> do
    pat <- resize (n `div` 2) arbitrary
    body <- resize (n `div` 2) arbitrary
    -- Trailing '--' on a CaseAlt only round-trips when the body's
    -- render ends on the same line as the arm (so the parser's
    -- 'pTrailingLineCommentMaybe' lands on the comment instead of
    -- finding empty space past a newline). 'isBlockBody' captures
    -- exactly that distinction; the type-level split into
    -- 'CaseAltLeaf' / 'CaseAltBlock' upgrades the rule from
    -- "generator avoids it" to "AST disallows the bad pairing", and
    -- 'mkCaseAlt' picks the right variant for us.
    mc <- if isBlockBody body then pure Nothing else genComment
    pure (mkCaseAlt [] pat body mc)
  shrink alt =
    let p = caseAltPattern alt
        e = caseAltBody alt
     in [mkCaseAlt [] p' e Nothing | p' <- shrink p]
          <> [mkCaseAlt [] p e' Nothing | e' <- shrink e]

-- | A 'do'-block statement. The renderer goes through
--   'renderPatternAtom' for the LHS, which parenthesises constructor
--   applications and leaves PAscribe self-parenthesised — so any
--   pattern shape works on a single line with the '='. The optional
--   type ascription mirrors the standalone 'let n : T = e' form.
instance Arbitrary DoStmt where
  arbitrary = sized $ \n ->
    frequency
      [ (3, DoBind noSpan <$> resize (n `div` 2) arbitrary <*> resize (n `div` 2) arbitrary),
        ( 2,
          do
            pat <- resize (n `div` 2) arbitrary
            mAnnot <- frequency [(3, pure Nothing), (1, Just <$> resize (n `div` 2) arbitrary)]
            e <- resize (n `div` 2) arbitrary
            pure (DoLet noSpan pat mAnnot e)
        ),
        (3, DoExpr noSpan <$> resize (n `div` 2) arbitrary)
      ]
  shrink = \case
    DoBind _ p e -> [DoBind noSpan p' e | p' <- shrink p] <> [DoBind noSpan p e' | e' <- shrink e]
    DoLet _ p t e -> [DoLet noSpan p t e' | e' <- shrink e]
    DoExpr _ e -> DoExpr noSpan <$> shrink e

-- | Surface expressions.
--
--   'ECase' / 'EDo' as nested subexpressions are generated. The
--   AST-level invariant on 'CaseAlt' (Leaf vs Block, see 'Awsum.Syntax')
--   guarantees a trailing '--' on an arm whose body is block-form is
--   not constructible — that was the only round-trip hazard here.
instance Arbitrary Expr where
  arbitrary = sized go
    where
      go 0 =
        oneof
          [ EVar noSpan <$> arbitrary,
            EParens noSpan . EVar noSpan <$> arbitrary, -- parentheses around atom for round-trip tests
            ELit noSpan . LString <$> genStr,
            ELit noSpan . LInt <$> genInt,
            ECon noSpan <$> genUIdent,
            EBuiltIn noSpan <$> genLIdent
          ]
      go n =
        frequency
          [ (4, EVar noSpan <$> arbitrary),
            (2, EParens noSpan <$> go (n - 1)),
            (2, ELit noSpan . LString <$> genStr),
            (2, ELit noSpan . LInt <$> genInt),
            (2, ECon noSpan <$> genUIdent),
            (1, EBuiltIn noSpan <$> genLIdent),
            (5, EApp noSpan <$> go (n `div` 2) <*> go (n `div` 2)),
            (5, EInfix noSpan OpConcat <$> go (n `div` 2) <*> go (n `div` 2)),
            (3, EInfix noSpan OpPipe <$> go (n `div` 2) <*> go (n `div` 2)),
            (2, genLam (n `div` 2)),
            (2, genLet (n `div` 2)),
            -- Block forms in nested position. Lower weight + steeper
            -- size division (n `div` 3) — they expand into multi-line
            -- shapes whose parser layout is layout-sensitive; flooding
            -- the generator with deeply nested blocks blows up the
            -- average tree size without proportional coverage gain.
            (1, ECase noSpan <$> go (n `div` 3) <*> resize (n `div` 3) (genNonEmpty arbitrary) <*> pure []),
            (1, EDo noSpan <$> resize (n `div` 3) (genDoBlockExpr (n `div` 3)))
          ]
      genLam n = do
        k <- chooseInt (1, 2)
        ps <- vectorOf k genParam
        ELam noSpan ps <$> go n
      genLet n = do
        name <- genLIdent
        ELet noSpan (PVar noSpan name) Nothing <$> go n <*> go n
      genParam = Param noSpan <$> genLIdent
  shrink = \case
    ELit _sp (LString t) -> [ELit noSpan (LString t') | t' <- shrinkIdent t]
    ELit _sp (LInt n) -> [ELit noSpan (LInt n') | n' <- shrink n]
    EVar _sp q -> EVar noSpan <$> shrink q
    EParens _sp e -> e : [EParens noSpan e' | e' <- shrink e]
    ECon _sp n -> ECon noSpan <$> shrinkIdent n
    EApp _sp f x -> [f, x] <> [EApp noSpan f' x | f' <- shrink f] <> [EApp noSpan f x' | x' <- shrink x]
    EInfix _sp OpConcat l r ->
      [l, r]
        <> [EInfix noSpan OpConcat l' r | l' <- shrink l]
        <> [EInfix noSpan OpConcat l r' | r' <- shrink r]
    EInfix _sp OpPipe l r ->
      [l, r]
        <> [EInfix noSpan OpPipe l' r | l' <- shrink l]
        <> [EInfix noSpan OpPipe l r' | r' <- shrink r]
    ECase _sp scrut alts cs ->
      [scrut]
        <> map caseAltBody (toList alts)
        <> [ECase noSpan s' alts cs | s' <- shrink scrut]
    EBuiltIn _sp n -> EBuiltIn noSpan <$> shrinkIdent n
    ELam _sp ps body -> body : [ELam noSpan ps body' | body' <- shrink body]
    EDo _sp stmts -> stmts >>= doStmtExprs
      where
        doStmtExprs = \case
          DoBind _ _ e -> [e]
          DoLet _ _ _ e -> [e]
          DoExpr _ e -> [e]
    ELet _sp _ _ e body -> [e, body] <> [ELet noSpan (PVar noSpan "x") Nothing e' body | e' <- shrink e] <> [ELet noSpan (PVar noSpan "x") Nothing e body' | body' <- shrink body]

-- | Body of an 'EDo' block: zero or more leading bind/let/expr
--   statements followed by a final 'DoExpr'. Shared between
--   'Arbitrary Expr' (nested @do@) and 'Arbitrary Decl' (function-body
--   @do@) so both paths obey the same shape constraint.
genDoBlockExpr :: Int -> Gen [DoStmt]
genDoBlockExpr n = do
  k <- chooseInt (0, min 3 (max 0 n))
  leading <- vectorOf k (resize (n `div` (k + 1)) arbitrary)
  finalE <- DoExpr noSpan <$> resize (n `div` (k + 1)) arbitrary
  pure (leading <> [finalE])

-- | Top-level declarations.
instance Arbitrary Decl where
  arbitrary =
    frequency
      [ (4, Sig noSpan <$> genLIdent <*> arbitrary <*> genComment),
        (4, genFunDef),
        (1, genTypeDecl),
        -- Top-level comment as a standalone declaration. When sandwiched
        -- between a 'Sig' and a 'FunDef' of the same name, it breaks the
        -- 'groupDeclBlocks' pairing — both ends still round-trip, just
        -- as two separate blocks with the comment between, which is
        -- exactly what the parser produces.
        (1, CommentDecl <$> genCommentNode)
      ]
    where
      -- Mostly plain-name parameters; an occasional destructuring
      -- 'ParamPat'. The parser canonicalises @(x)@ back to a bare
      -- 'Param' (see 'paramBinderG' in the parser); the normaliser
      -- ('normalizeParam') matches that on the AST side, so any
      -- 'ParamPat' shape — including @PVar@ or @PWild@ — round-trips
      -- through @parse∘render@ once both sides are normalised.
      genParam =
        frequency
          [ (8, Param noSpan <$> genLIdent),
            (1, ParamPat noSpan <$> genParamPat)
          ]
      genParamPat =
        oneof
          [ PVar noSpan <$> genLIdent,
            pure (PWild noSpan),
            PCon noSpan <$> genUIdent <*> pure [],
            do
              k <- chooseInt (1, 2)
              PCon noSpan <$> genUIdent <*> vectorOf k (resize 1 arbitrary),
            PAscribe noSpan <$> resize 1 arbitrary <*> resize 2 arbitrary
          ]
      genFunDef = sized $ \n -> do
        name <- genLIdent
        k <- chooseInt (0, min 3 (max 0 n))
        ps <- vectorOf k genParam
        body <- genFunBody (max 0 (n - k))
        FunDef noSpan name ps body <$> genComment
      -- Function bodies may additionally be 'ECase' or 'EDo' at the
      -- top level — these are layout-sensitive and only round-trip
      -- when the keyword sits at the head of the right-hand side,
      -- not nested inside an application or infix operator. So
      -- they're added here, not inside the generic 'Arbitrary Expr'.
      genFunBody n =
        frequency
          [ (6, resize n arbitrary),
            (1, ECase noSpan <$> resize (n `div` 2) arbitrary <*> resize (n `div` 2) (genNonEmpty arbitrary) <*> pure []),
            (1, EDo noSpan <$> resize (n `div` 2) (genDoBlockExpr n))
          ]
      genTypeDecl = sized $ \n -> do
        name <- genUIdent
        kTv <- chooseInt (0, min 2 (max 0 n))
        -- Type parameters can't be 'ParamPat' (the parser's
        -- 'paramBinderNoLine' is name-only): keep them simple.
        tvars <- vectorOf kTv (Param noSpan <$> genLIdent)
        kCon <- chooseInt (0, min 3 (max 0 n))
        cons <- vectorOf kCon (resize (n `div` 2) arbitrary)
        TypeDecl noSpan name tvars cons <$> genComment
  shrink = \case
    Sig _sp n t mc ->
      [Sig noSpan n' t mc | n' <- shrinkIdent n] <> [Sig noSpan n t' mc | t' <- shrink t]
    FunDef _sp n as e mc ->
      [FunDef noSpan n' as e mc | n' <- shrinkIdent n]
        <> [FunDef noSpan n (take i as) e mc | i <- [0 .. length as - 1]]
        <> [FunDef noSpan n as e' mc | e' <- shrink e]
    TypeDecl _sp n tvs cs mc ->
      [TypeDecl noSpan n' tvs cs mc | n' <- shrinkIdent n]
        <> [TypeDecl noSpan n (take i tvs) cs mc | i <- [0 .. length tvs - 1]]
        <> [TypeDecl noSpan n tvs cs' mc | cs' <- shrinkList shrink cs]
    CommentDecl _ -> []

instance Arbitrary Program where
  arbitrary = do
    ims <- listOf arbitrary
    -- at least one top-level declaration
    d0 <- arbitrary
    ds <- listOf arbitrary
    pure Program {imports = ims, decls = d0 :| ds}
  shrink (Program ims ds) =
    [Program ims' ds | ims' <- shrinkList shrink ims]
      <> [Program ims ds' | ds' <- shrinkNonEmpty shrink ds]
