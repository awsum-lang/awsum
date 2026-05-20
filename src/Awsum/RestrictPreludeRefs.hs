-- | Reject user-code references to prelude-private names.
--
-- The bundled prelude declares 'type IO' (whose constructors only the
-- runtime walker is meant to construct or pattern-match) and 'runIO'
-- (the runtime walker itself, called from per-backend entry-point glue
-- via a string template — not a Core call edge). Until Awsum has a real
-- module system with @export@/@import@, there is no language-level way
-- to mark these as private; this pass is the temporary substitute.
--
-- Why it matters: Awsum has no catch-all on @case@, so every new
-- constructor added to @type IO@ would be a breaking change for any
-- user program that wrote @case io of …@. Disallowing the references
-- before any user code relies on them preserves our freedom to extend
-- @IO@ with new platform effects.
--
-- The check runs on the raw user 'Program' /before/ 'withPrelude'
-- splices the prelude in. When modules land, this module is deleted
-- and the diagnostic migrates into the standard \"@X@ is not exported\"
-- path.
module Awsum.RestrictPreludeRefs
  ( PreludeRefViolation (..),
    restrictPreludeRefs,
  )
where

import Awsum.Prelude (preludeProgram)
import Awsum.Syntax
import Data.Set qualified as S
import Relude

-- | One use-site reference to a prelude-private name. The 'SrcSpan'
--   covers the offending identifier in user source so editors can
--   highlight it precisely.
data PreludeRefViolation = PreludeRefViolation SrcSpan Name
  deriving stock (Show, Eq)

-- | Collect every user-source reference to a prelude-private name.
--   Returns @[]@ for a clean program /and/ for the bundled prelude
--   itself (so @awsum check stdlib/Prelude.aww@ during compiler
--   development stays silent — same idempotency trick 'withPrelude'
--   already uses). The list is in source-order; multiple violations in
--   one program are all reported at once.
restrictPreludeRefs :: Program -> [PreludeRefViolation]
restrictPreludeRefs userProg
  | userProg == preludeProgram = []
  | otherwise = concatMap violationsInDecl userProg.decls
  where
    violationsInDecl :: Decl -> [PreludeRefViolation]
    violationsInDecl = \case
      FunDef _ _ params body _ ->
        concatMap violationsInParam params <> violationsInExpr body
      Sig {} -> []
      TypeDecl {} -> []
      CommentDecl _ -> []

    violationsInParam :: Param -> [PreludeRefViolation]
    violationsInParam = \case
      Param _ _ -> []
      ParamPat _ pat -> violationsInPattern pat

    violationsInExpr :: Expr -> [PreludeRefViolation]
    violationsInExpr = \case
      EVar sp (QName [] n)
        | S.member n privateNames -> [PreludeRefViolation sp n]
        | otherwise -> []
      EVar _ (QName (_ : _) _) -> []
      ECon sp n
        | S.member n privateNames -> [PreludeRefViolation sp n]
        | otherwise -> []
      EApp _ f x -> violationsInExpr f <> violationsInExpr x
      EInfix _ _ l r -> violationsInExpr l <> violationsInExpr r
      EParens _ e -> violationsInExpr e
      ELit _ _ -> []
      ECase _ scrut alts _ ->
        violationsInExpr scrut <> concatMap violationsInAlt (toList alts)
      EBuiltIn _ _ -> []
      ELam _ params body ->
        concatMap violationsInParam params <> violationsInExpr body
      EDo _ stmts -> concatMap violationsInDoStmt stmts
      ELet _ pat _ rhs body ->
        violationsInPattern pat <> violationsInExpr rhs <> violationsInExpr body
      EAscribe _ e _ -> violationsInExpr e

    violationsInAlt :: CaseAlt -> [PreludeRefViolation]
    violationsInAlt alt =
      violationsInPattern (caseAltPattern alt) <> violationsInExpr (caseAltBody alt)

    violationsInDoStmt :: DoStmt -> [PreludeRefViolation]
    violationsInDoStmt = \case
      DoBind _ pat e -> violationsInPattern pat <> violationsInExpr e
      DoLet _ pat _ e -> violationsInPattern pat <> violationsInExpr e
      DoExpr _ e -> violationsInExpr e

    violationsInPattern :: Pattern -> [PreludeRefViolation]
    violationsInPattern = \case
      PCon sp n fields ->
        let here = [PreludeRefViolation sp n | S.member n privateNames]
         in here <> concatMap violationsInPattern fields
      PVar _ _ -> []
      PWild _ -> []
      PAscribe _ inner _ -> violationsInPattern inner

-- | Names the user is forbidden from referencing: every constructor of
--   the prelude's @type IO@, plus the literal @runIO@. Constructors are
--   read from the parsed prelude — they grow automatically when a new
--   platform effect adds another constructor to @IO@. @runIO@ is the
--   single non-constructor exception and is hardcoded here.
privateNames :: Set Name
privateNames = S.insert "runIO" ioConstructors
  where
    ioConstructors =
      S.fromList
        [ cn
        | TypeDecl _ "IO" _ cons _ _ <- toList preludeProgram.decls,
          ConDef _ cn _ <- cons
        ]
