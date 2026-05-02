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
  arbitrary = ImportDecl [] <$> genNonEmpty genUIdent <*> genComment
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

genComment :: Gen (Maybe Text)
genComment = frequency [(3, pure Nothing), (1, Just <$> genStr)]

genInt :: Gen Integer
genInt =
  frequency
    [ (3, choose (-2147483648, 2147483647)), -- Int32 range
      (2, choose (0, 255)) -- UInt8 range
    ]

instance Arbitrary Expr where
  arbitrary = sized go
    where
      go 0 =
        oneof
          [ EVar noSpan <$> arbitrary,
            EParens noSpan . EVar noSpan <$> arbitrary, -- parentheses around atom for round-trip tests
            ELit noSpan . LString <$> genStr,
            ELit noSpan . LInt <$> genInt,
            EBuiltIn noSpan <$> genLIdent
          ]
      go n =
        frequency
          [ (4, EVar noSpan <$> arbitrary),
            (2, EParens noSpan <$> go (n - 1)),
            (2, ELit noSpan . LString <$> genStr),
            (2, ELit noSpan . LInt <$> genInt),
            (1, EBuiltIn noSpan <$> genLIdent),
            (5, EApp noSpan <$> go (n `div` 2) <*> go (n `div` 2)),
            (5, EInfix noSpan OpConcat <$> go (n `div` 2) <*> go (n `div` 2))
          ]
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
    ECase _sp scrut alts cs ->
      [scrut]
        <> [ECase noSpan s' alts cs | s' <- shrink scrut]
    EBuiltIn _sp n -> EBuiltIn noSpan <$> shrinkIdent n
    -- Lambdas, 'do' blocks and 'let'-bindings aren't generated by
    -- 'arbitrary' yet — shrink them down to the inner expression(s)
    -- so other shrinkers still terminate when one creeps in via a
    -- smart constructor.
    ELam _sp _ body -> [body]
    EDo _sp stmts -> stmts >>= doStmtExprs
      where
        doStmtExprs = \case
          DoBind _ _ e -> [e]
          DoLet _ _ _ e -> [e] -- pattern in DoLet not generated; only present via smart constructors
          DoExpr _ e -> [e]
    ELet _sp _ _ e body -> [e, body]

instance Arbitrary Decl where
  arbitrary =
    oneof
      [ Sig noSpan <$> genLIdent <*> arbitrary <*> genComment,
        FunDef noSpan <$> genLIdent <*> listOf genParam <*> arbitrary <*> genComment
      ]
    where
      genParam = Param noSpan <$> genLIdent
  shrink = \case
    Sig _sp n t mc ->
      [Sig noSpan n' t mc | n' <- shrinkIdent n] <> [Sig noSpan n t' mc | t' <- shrink t]
    FunDef _sp n as e mc ->
      [FunDef noSpan n' as e mc | n' <- shrinkIdent n]
        <> [FunDef noSpan n (take i as) e mc | i <- [0 .. length as - 1]]
        <> [FunDef noSpan n as e' mc | e' <- shrink e]
    CommentDecl c -> [CommentDecl c]
    TypeDecl {} -> []

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
