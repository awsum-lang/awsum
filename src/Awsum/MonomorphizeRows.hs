-- | Row monomorphisation: a 'TypedProgram' → 'TypedProgram' pass that
--   specialises row-polymorphic top-level functions per concrete row
--   instantiation, run after typechecking and before lowering.
--
--   Why it exists. A polymorphic combinator like
--   @bindEither : Either e1 a -> (a -> Either e2 b) -> Either (e1 | e2) b@
--   is elaborated /once/, with @e1@ / @e2@ still type variables. Its body
--   injects its @Left@ payload into the result row via a 'TCoerce' whose
--   source and target carry those abstract labels — and an abstract
--   label has no statically-known row tag. Lowering that generic body
--   would emit the wrong tag; the row-case at the call site dispatches on
--   the /concrete/ label's tag and the two never line up.
--
--   The fix is static specialisation, consistent with how Awsum handles
--   every other "no runtime feature for this" case (closures via
--   defunctionalisation, etc.) rather than passing row evidence at
--   runtime. At each call site whose instantiation widens an abstract
--   row into a concrete multi-alternative one, we emit a specialised copy
--   of the callee with the call-site substitution applied to its body
--   ('substTExpr' turns the abstract @e1@ inside the 'TCoerce' into the
--   concrete @EA@), and repoint the call at the copy. Copies are
--   memoised by @(name, canonical-label of the instantiated type)@ and
--   their bodies are themselves walked, so a chain of widening
--   combinators specialises transitively; the memo is populated before a
--   body is walked, so a self-recursive widening call terminates.
--
--   This replaces the lowering-time @getOrCreateRowSpec@ /
--   @rowUnioningSpec@ machinery: the trigger is now the authoritative
--   @(declared, instantiated)@ pair the typechecker recorded on the call
--   head, not a best-effort re-synthesis of argument types.
module Awsum.MonomorphizeRows (monomorphizeRows) where

import Awsum.HM (applySubst, canonicalLabel, flattenRow, unify)
import Awsum.Syntax (Decl (..), Name, QName (..), Type' (..))
import Awsum.TExpr
import Data.Map.Strict qualified as M
import Relude

-- | Specialisation state threaded through the walk: a fresh-name
--   counter, the memo of already-created specialisations, and the
--   accumulated specialised declarations (newest first).
data MonoState = MonoState
  { msCounter :: !Int,
    msMemo :: !(Map (Name, Text) Name),
    msSpecs :: ![TDecl]
  }

monomorphizeRows :: TypedProgram -> TypedProgram
monomorphizeRows tp =
  let defMap = M.fromList [(tdeclName d, d) | d <- tpDefs tp]
      -- Declared signatures, used as the checking-mode expected type when
      -- walking a definition's body. A partial application of a row
      -- combinator (@partialB = bindEither oa@) leaves the continuation's
      -- result-row variable abstract on the call head — the concrete row
      -- lives only in the definition's signature, so the walk threads it
      -- down to recover it.
      sigMap = M.fromList [(n, t) | Sig _ n t _ _ <- tpProgramDecls tp]
      (rewritten, final) =
        runState (traverse (goDecl defMap sigMap) (tpDefs tp)) (MonoState 0 M.empty [])
   in tp {tpDefs = rewritten <> reverse (msSpecs final)}

goDecl :: Map Name TDecl -> Map Name Type' -> TDecl -> State MonoState TDecl
goDecl defMap sigMap = \case
  TFunDef n ps body ->
    -- The body is checked against the signature's result after the
    -- definition's own parameters.
    TFunDef n ps <$> goExpr defMap (M.lookup n sigMap >>= stripArrows (length ps)) body
  TValDef n body -> TValDef n <$> goExpr defMap (M.lookup n sigMap) body

-- | Rewrite an expression, specialising every fully-applied call to a
--   top-level row-polymorphic function whose instantiation widens an
--   abstract row to a concrete one. Application spines are normalised to
--   flat 'TApp' (head + all args) on the way through — both the binary
--   nodes 'typeOfExpr' builds and the flat nodes the spine-fallback
--   builds collapse to the same shape, which is all lowering needs.
goExpr :: Map Name TDecl -> Maybe Type' -> TExpr -> State MonoState TExpr
goExpr defMap = go
  where
    go expected e = case e of
      TApp sp ty _ _ ->
        let (headE, args) = collectTApp e
         in case headE of
              -- Specialisation fires only on an unqualified head, and
              -- that is exhaustive today: every 'defMap' entry is a
              -- top-level def, and top-level defs are reachable only
              -- unqualified (they live in the typechecker env under
              -- QName [], so a qualified reference to one is a
              -- NotImported error). The qualified heads that do exist
              -- are platform built-ins, whose names are not in defMap.
              -- When a module system lets a top-level row combinator be
              -- referenced qualified, BOTH this match and the bare-Name
              -- key of defMap must be revisited; resolve references to a
              -- unique top-level id before this pass.
              TVar hsp declared inst (QName [] name)
                | Just (TFunDef _ params _) <- M.lookup name defMap,
                  -- '<=' not '==': a partial application of a row-widening
                  -- combinator must specialise too. The prelude's
                  -- @bindIO io k = case io of IOGetArgs cont -> IOGetArgs
                  -- (bindIOAfterArgs cont k)@ applies @bindIOAfterArgs@ to
                  -- 2 of its 3 params (the third, the decode result, is
                  -- supplied later by the runtime).
                  length args <= length params,
                  -- Refine the head's recorded inst with the expected result
                  -- type. A partial application can leave the continuation's
                  -- result row abstract on the head — the concrete row then
                  -- lives only in the enclosing signature (@partialB =
                  -- bindEither oa@), which the walk threads down as
                  -- @expected@; 'refineInst' recovers it so the call
                  -- specialises and the continuation's payload is re-tagged.
                  let inst' = refineInst (length args) inst expected,
                  rowWidenedToConcrete declared inst' -> do
                    specName <- getOrCreateSpec defMap name declared inst' params
                    args' <- traverse (go Nothing) args
                    -- The specialised callee is monomorphic, so its
                    -- declared and instantiated types coincide at @inst'@.
                    pure (TApp sp ty (TVar hsp inst' inst' (QName [] specName)) args')
              _ -> do
                headE' <- go Nothing headE
                args' <- traverse (go Nothing) args
                pure (TApp sp ty headE' args')
      -- Checking-mode positions thread @expected@ down; everything else
      -- synthesises (@Nothing@).
      TLam sp ty params b -> TLam sp ty params <$> go (expected >>= stripArrows (length params)) b
      TLet sp ty pat rhs b -> TLet sp ty pat <$> go Nothing rhs <*> go expected b
      TCase sp ty scrut alts -> TCase sp ty <$> go Nothing scrut <*> traverse (goAlt expected) alts
      TRowCase sp ty scrut alts -> TRowCase sp ty <$> go Nothing scrut <*> traverse (goRowAlt expected) alts
      TCoerce sp s t inner -> TCoerce sp s t <$> go (Just s) inner
      -- A row-widening function used as a /value/ (HOF argument, stored in
      -- a constructor field, returned) — not the head of a 'TApp', so the
      -- call-site clause above never sees it. Without this it falls through
      -- to the catch-all, the generic body with its rigid tyvar reaches
      -- lowering, and the row injection is dropped as a vacuous tyvar
      -- coercion (a silent cross-backend miscompile). Specialise it here on
      -- the same trigger as the call site; 'getOrCreateSpec' re-walks the
      -- substituted body, so a use nested inside an enclosing definition is
      -- handled when that definition is itself specialised at a concrete row.
      TVar hsp declared inst (QName [] name)
        | Just (TFunDef _ params _) <- M.lookup name defMap,
          let inst' = refineInst 0 inst expected,
          rowWidenedToConcrete declared inst' -> do
            specName <- getOrCreateSpec defMap name declared inst' params
            pure (TVar hsp inst' inst' (QName [] specName))
      TVar {} -> pure e
      TLit {} -> pure e
      TBuiltIn {} -> pure e
      TConRef {} -> pure e
    goAlt expected (TAlt pat b) = TAlt pat <$> go expected b
    goRowAlt expected (TRowAlt lbl pat b) = TRowAlt lbl pat <$> go expected b

-- | Return (creating and memoising on first request) the name of the
--   specialisation of @fname@ at the instantiated type @inst@. The
--   substitution mapping the callee's signature tyvars to the concrete
--   instantiation comes from unifying its @declared@ scheme with @inst@;
--   it is applied to the callee's parameters and body, and the resulting
--   body is itself walked. The memo entry is registered before the body
--   is walked so a self-recursive widening call resolves to this name.
getOrCreateSpec :: Map Name TDecl -> Name -> Type' -> Type' -> [TParam] -> State MonoState Name
getOrCreateSpec defMap fname declared inst params = do
  let key = (fname, canonicalLabel inst)
  st <- get
  case M.lookup key (msMemo st) of
    Just specName -> pure specName
    Nothing -> do
      let specName = "$rowmono$" <> show (msCounter st) <> "$" <> fname
      put st {msCounter = msCounter st + 1, msMemo = M.insert key specName (msMemo st)}
      case M.lookup fname defMap of
        Just (TFunDef _ _ body) -> do
          -- 'unify' of a combinator's declared scheme against its concrete
          -- instantiation must succeed — 'inst' is by construction a
          -- substitution instance of 'declared'. A Left here is a compiler
          -- bug, not a user error, so fail loudly rather than silently
          -- specialising with an empty substitution (which would leave the
          -- body's abstract row labels untagged at lowering).
          let subst = case unify declared inst of
                Right s -> s
                Left _ ->
                  error
                    ( "MonomorphizeRows: the declared scheme of "
                        <> fname
                        <> " did not unify with its instantiation "
                        <> canonicalLabel inst
                        <> " — compiler invariant violated."
                    )
              params' = map (substTParam subst) params
          -- The spec body is fully substituted (concrete), so any inner
          -- combinator call already carries a concrete recorded inst — no
          -- expected type needs threading.
          body' <- goExpr defMap Nothing (substTExpr subst body)
          modify (\s -> s {msSpecs = TFunDef specName params' body' : msSpecs s})
          pure specName
        -- Only 'TFunDef' callees reach here (the caller checked
        -- @length args == length params@ against a 'TFunDef'); a
        -- 'TValDef' or absent entry is defensively left unspecialised.
        _ -> pure specName

-- | Flatten an application spine into @(head, [arg1, …, argN])@,
--   collapsing both binary and already-flat 'TApp' nesting.
collectTApp :: TExpr -> (TExpr, [TExpr])
collectTApp = go []
  where
    go acc (TApp _ _ h args) = go (args <> acc) h
    go acc h = (h, acc)

-- | Refine a head's recorded instantiated type using the checking-mode
--   expected type of the @nArgs@-argument application. The head applied to
--   its arguments must have the expected type, so unifying the recorded
--   inst's result-after-@nArgs@ against @expected@ recovers any row the
--   synth path left abstract — the continuation's result row on a partial
--   application, which lives only in the enclosing definition's signature.
--   Falls back to the recorded inst when there is no expected type or the
--   shapes disagree (a richer @expected@ only ever pins more, never less).
refineInst :: Int -> Type' -> Maybe Type' -> Type'
refineInst nArgs inst = \case
  Nothing -> inst
  Just expected -> case stripArrows nArgs inst of
    Just resultTy -> case unify resultTy expected of
      Right s -> applySubst s inst
      Left _ -> inst
    Nothing -> inst

-- | Drop @n@ leading arrows from a type, returning the residual result
--   type — the type of the value after @n@ curried applications. @Nothing@
--   if the type has fewer than @n@ arrows.
stripArrows :: Int -> Type' -> Maybe Type'
stripArrows 0 t = Just t
stripArrows n (TyArrow _ _ b) = stripArrows (n - 1) b
stripArrows _ _ = Nothing

-- | True when @gen@ has, in some structural position, a row containing a
--   type variable while @con@ has — in the same position — a fully
--   resolved row of two or more distinct concrete alternatives. That is
--   exactly the shape a polymorphic body cannot inject (an abstract
--   label has no static tag) but a concrete instantiation must. Partial
--   instantiations (some labels still variables) are left to the generic
--   body, whose construction-site injections are already correct.
--   Ported from the former lowering-time @rowWidenedToConcrete@.
rowWidenedToConcrete :: Type' -> Type' -> Bool
rowWidenedToConcrete gen con = case (gen, con) of
  (TyOr {}, _) ->
    let genHasVar = any isRowVar (flattenRow gen)
        conAlts = flattenRow con
        conConcrete = ordNub (filter isConcreteAlt conAlts)
     in genHasVar && not (any isRowVar conAlts) && length conConcrete >= 2
  (TyApp _ gf gx, TyApp _ cf cx) ->
    rowWidenedToConcrete gf cf || rowWidenedToConcrete gx cx
  (TyArrow _ ga gb, TyArrow _ ca cb) ->
    rowWidenedToConcrete ga ca || rowWidenedToConcrete gb cb
  _ -> False
  where
    isRowVar (TyVar _ _) = True
    isRowVar _ = False
    isConcreteAlt = \case
      TyVar _ _ -> False
      TyEmpty _ _ -> False
      _ -> True
