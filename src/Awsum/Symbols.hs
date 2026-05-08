-- | Top-level symbol extraction from 'Program'.
--
-- The output drives IDE features that need to enumerate the visible
-- declarations of a source file — outline panes, breadcrumbs, workspace
-- symbol search — without running the full typechecker.  The representation
-- intentionally mirrors the VS Code / LSP @DocumentSymbol@ shape so editors
-- can consume the emitted JSON with minimal glue.
--
-- What we emit:
--
--   * /functions/  — 'FunDef' with at least one argument
--   * /constants/  — zero-arg 'FunDef'
--   * /types/      — 'TypeDecl'
--
-- We skip imports, constructors, and comments — they don't appear in
-- the outline shape we emit.
--
-- A 'Sig' immediately paired with a 'FunDef' of the same name is merged into
-- a single symbol so the outline shows one entry per binding (the signature's
-- name is the selection range; the range spans signature-through-definition).
-- Orphan 'Sig' decls (no matching 'FunDef') are emitted on their own, so
-- malformed programs still navigate usefully.
module Awsum.Symbols
  ( Symbol (..),
    SymbolKind (..),
    symbolsOfProgram,
    symbolsToJson,
  )
where

import Awsum.Syntax
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import Data.Text qualified as T
import Relude

-- | Coarse category for a symbol.  Mirrors the subset of LSP/VS Code
--   'SymbolKind' values the outline cares about.
data SymbolKind
  = SkFunction
  | SkConstant
  | SkType
  deriving stock (Show, Eq)

-- | A single entry in the outline.
--   'symRange' covers the whole declaration (and, when paired, the signature
--   above it); 'symSelectionRange' points at just the name the IDE should
--   highlight on navigation.
data Symbol = Symbol
  { symKind :: SymbolKind,
    symName :: Name,
    symRange :: SrcSpan,
    symSelectionRange :: SrcSpan,
    symChildren :: [Symbol]
  }
  deriving stock (Show, Eq)

-- | Extract top-level symbols from a 'Program', preserving source order.
symbolsOfProgram :: Program -> [Symbol]
symbolsOfProgram Program {decls} =
  let ds = toList decls
      funDefByName = M.fromList [(n, (sp, args)) | FunDef sp n args _ _ <- ds]
   in snd $ foldl' (emit funDefByName) (S.empty, []) ds
  where
    emit ::
      M.Map Name (SrcSpan, [Param]) ->
      (S.Set Name, [Symbol]) ->
      Decl ->
      (S.Set Name, [Symbol])
    emit funDefByName (processed, acc) = \case
      Sig sp n _ _ ->
        let sym = case M.lookup n funDefByName of
              Just (fnSp, args) -> mkBindingSymbol args n (combineSpans sp fnSp) (nameSpanAt sp n)
              Nothing -> mkBindingSymbol [] n sp (nameSpanAt sp n) -- orphan sig
         in (S.insert n processed, acc <> [sym])
      FunDef sp n args _body _
        | S.member n processed -> (processed, acc) -- already emitted with its sig
        | otherwise ->
            let sym = mkBindingSymbol args n sp (nameSpanAt sp n)
             in (S.insert n processed, acc <> [sym])
      TypeDecl sp n _tvars _cons _ _ ->
        (processed, acc <> [Symbol SkType n sp (typeNameSpanAt sp n) []])
      CommentDecl _ -> (processed, acc)

    mkBindingSymbol :: [Param] -> Name -> SrcSpan -> SrcSpan -> Symbol
    mkBindingSymbol args n range selRange =
      let kind = case args of [] -> SkConstant; _ -> SkFunction
       in Symbol kind n range selRange []

    combineSpans :: SrcSpan -> SrcSpan -> SrcSpan
    combineSpans a b =
      SrcSpan (spanStartLine a) (spanStartCol a) (spanEndLine b) (spanEndCol b)

    -- A Sig or FunDef span starts at the name, so the name range is the
    -- first @length name@ columns of the span's start line.
    nameSpanAt :: SrcSpan -> Name -> SrcSpan
    nameSpanAt sp n =
      let startCol = spanStartCol sp
       in SrcSpan (spanStartLine sp) startCol (spanStartLine sp) (startCol + T.length n)

    -- A TypeDecl span starts at the @type@ keyword.  We approximate the
    -- name position as @startCol + length "type "@ (5 chars) — good enough
    -- for single-space source; formatter guarantees this shape.
    typeNameSpanAt :: SrcSpan -> Name -> SrcSpan
    typeNameSpanAt sp n =
      let startCol = spanStartCol sp + T.length "type "
       in SrcSpan (spanStartLine sp) startCol (spanStartLine sp) (startCol + T.length n)

-- | Render a list of symbols as a JSON array matching the LSP
--   'DocumentSymbol' shape (1-based line/col, consistent with Awsum's
--   existing diagnostic JSON).
symbolsToJson :: [Symbol] -> Text
symbolsToJson syms = "[" <> T.intercalate "," (map symbolToJson syms) <> "]"

symbolToJson :: Symbol -> Text
symbolToJson (Symbol k n r sr cs) =
  "{\"kind\":"
    <> jsonString (kindText k)
    <> ",\"name\":"
    <> jsonString n
    <> ",\"range\":"
    <> rangeToJson r
    <> ",\"selectionRange\":"
    <> rangeToJson sr
    <> ",\"children\":"
    <> symbolsToJson cs
    <> "}"

kindText :: SymbolKind -> Text
kindText = \case
  SkFunction -> "function"
  SkConstant -> "constant"
  SkType -> "type"

rangeToJson :: SrcSpan -> Text
rangeToJson (SrcSpan sl sc el ec) =
  "{\"startLine\":"
    <> show sl
    <> ",\"startCol\":"
    <> show sc
    <> ",\"endLine\":"
    <> show el
    <> ",\"endCol\":"
    <> show ec
    <> "}"

jsonString :: Text -> Text
jsonString t = "\"" <> T.concatMap esc t <> "\""
  where
    esc c = case c of
      '"' -> "\\\""
      '\\' -> "\\\\"
      '\n' -> "\\n"
      '\r' -> "\\r"
      '\t' -> "\\t"
      _ -> one c
