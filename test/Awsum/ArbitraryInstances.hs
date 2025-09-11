{-# OPTIONS_GHC -Wno-orphans #-}

module Awsum.ArbitraryInstances () where

import Awsum.Syntax
import Data.Char (isAlphaNum, toLower, toUpper)
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
  let raw = T.pack (firstCase c0 : cs)
  if T.toLower raw `elem` reserved then mkSafe firstCase else pure raw
  where
    isAlpha c = c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z'

genLIdent :: Gen Name
genLIdent = mkSafe toLower

genUIdent :: Gen Name
genUIdent = mkSafe toUpper

shrinkIdent :: Name -> [Name]
shrinkIdent t =
  let s = T.unpack t
   in [T.pack (take k s) | k <- [1 .. length s - 1]]

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
  arbitrary = ImportDecl <$> genNonEmpty genUIdent
  shrink (ImportDecl ne) = ImportDecl <$> shrinkNonEmpty shrinkIdent ne

-- | Prefer producing useful types for tests:
--   • 'TyVar' appears often (so polymorphic sigs like 'a -> b -> a' show up),
--   • 'TyCon' is biased toward known ones ("String", "IOUnit"), but can be any UIdent,
--   • 'TyArrow' recurses with smaller sizes.
instance Arbitrary Type' where
  arbitrary = sized go
    where
      go 0 =
        frequency
          [ (3, TyVar <$> genTyVarName),
            (3, TyCon <$> genKnownTyCon),
            (2, TyCon <$> genUIdent)
          ]
      go n =
        frequency
          [ (4, TyVar <$> genTyVarName),
            (3, TyCon <$> genKnownTyCon),
            (2, TyCon <$> genUIdent),
            (6, TyArrow <$> go (n `div` 2) <*> go (n `div` 2))
          ]

      -- small, readable type variable names; still valid 'lident'
      genTyVarName :: Gen Name
      genTyVarName =
        frequency
          [ (6, elements (map (T.singleton) ['a' .. 'f'])), -- common short vars
            (4, genLIdent)
          ]

      genKnownTyCon :: Gen Name
      genKnownTyCon = elements ["String", "IOUnit"]

  shrink = \case
    TyVar v -> TyVar <$> shrinkIdent v
    TyCon n -> TyCon <$> shrinkIdent n
    TyArrow a b ->
      [a, b]
        <> [TyArrow a' b | a' <- shrink a]
        <> [TyArrow a b' | b' <- shrink b]

instance Arbitrary QName where
  arbitrary = do
    -- 0..2 module segments (UIdent), then name (lident)
    k <- frequency [(3, pure 0), (2, pure 1), (1, pure 2)]
    mods <- replicateM k genUIdent
    nm <- genLIdent
    pure (QName mods nm)
  shrink (QName ms n) =
    -- shrink module prefix and the base name
    [QName (take i ms) n | i <- [0 .. length ms - 1]]
      <> [QName ms n' | n' <- shrinkIdent n]

genStr :: Gen Text
genStr = do
  k <- chooseInt (0, 8)
  let ok c = isAlphaNum c || c == ' ' || c == '_' || c == '-' -- avoid quotes/backslash
  T.pack <$> vectorOf k (suchThat arbitrary ok)

genComment :: Gen (Maybe Text)
genComment = frequency [(3, pure Nothing), (1, Just <$> genStr)]

instance Arbitrary Expr where
  arbitrary = sized go
    where
      go 0 =
        oneof
          [ EVar <$> arbitrary,
            EParens <$> (EVar <$> arbitrary), -- parentheses around atom for round-trip tests
            ELit . LString <$> genStr
          ]
      go n =
        frequency
          [ (4, EVar <$> arbitrary),
            (2, EParens <$> go (n - 1)),
            (2, ELit . LString <$> genStr),
            (5, EApp <$> go (n `div` 2) <*> go (n `div` 2)),
            (5, EInfix OpConcat <$> go (n `div` 2) <*> go (n `div` 2))
          ]
  shrink = \case
    ELit (LString t) -> [ELit (LString t') | t' <- shrinkIdent t]
    EVar q -> EVar <$> shrink q
    EParens e -> e : [EParens e' | e' <- shrink e]
    EApp f x -> [f, x] <> [EApp f' x | f' <- shrink f] <> [EApp f x' | x' <- shrink x]
    EInfix OpConcat l r ->
      [l, r]
        <> [EInfix OpConcat l' r | l' <- shrink l]
        <> [EInfix OpConcat l r' | r' <- shrink r]

instance Arbitrary Decl where
  arbitrary =
    oneof
      [ Sig <$> genLIdent <*> arbitrary <*> genComment,
        FunDef <$> genLIdent <*> listOf genLIdent <*> arbitrary <*> genComment
      ]
  shrink = \case
    Sig n t mc ->
      [Sig n' t mc | n' <- shrinkIdent n] <> [Sig n t' mc | t' <- shrink t]
    FunDef n as e mc ->
      [FunDef n' as e mc | n' <- shrinkIdent n]
        <> [FunDef n (take i as) e mc | i <- [0 .. length as - 1]]
        <> [FunDef n as e' mc | e' <- shrink e]
    CommentDecl c -> [CommentDecl c]

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
