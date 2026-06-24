-- | Final naming-hygiene pass: bound the length of /synthesised/ top-level
--   names so codegen never emits a symbol past a backend's limit.
--
--   The flattening passes build names by concatenation — 'Awsum.Scc' joins
--   every member of a merged SCC, 'Awsum.Cps' wraps with @$cps$@ / @$apply$@,
--   'Awsum.Defunctionalize' prepends @$df$@ to the specialised callee — so a
--   program with deep mutual recursion through defunctionalised higher-order
--   functions can compound a single name to thousands of bytes. The JVM caps
--   a method/field name at 65535 bytes (the @CONSTANT_Utf8@ u2 length); past
--   it the @.class@ is silently corrupt. LLVM / JS / WASM tolerate long names
--   (WASM dispatches by index), so the failure is JVM-only — an
--   identical-results break.
--
--   Run last (after every name-producing pass), this rewrites each top-level
--   name that is synthesised (a @$@ prefix — a source identifier can never
--   start with @$@, so user names are never touched) and longer than
--   'synthNameThreshold' into a bounded @<prefix>$x$<hash>@ form, and repoints
--   every reference. User identifiers are bounded separately, at parse time,
--   by 'Awsum.Parser.maxIdentifierChars'.
module Awsum.ShortenNames (shortenSynthesizedNames, shortNameFor, synthNameThreshold) where

import Awsum.CallGraph (declName)
import Awsum.Core (CDecl (..), CoreProgram (..), renameVar)
import Awsum.HM (fnv1a32)
import Awsum.Syntax (Name)
import Data.Map.Strict qualified as M
import Data.Set qualified as Set
import Data.Text qualified as T
import Relude

-- | A synthesised name longer than this (bytes ≈ ASCII chars) is rewritten.
--   Comfortably under every backend's symbol limit (the tightest, JVM's
--   @CONSTANT_Utf8@, is 65535), and above every name a normal program
--   produces — only the fused-recursion monsters cross it.
synthNameThreshold :: Int
synthNameThreshold = 128

-- | Bound the length of synthesised top-level names; identity on a program
--   whose names are all short enough (the common case — no change).
shortenSynthesizedNames :: CoreProgram -> CoreProgram
shortenSynthesizedNames prog =
  let names = map declName (cdecls prog)
      long = sort [n | n <- names, isSynthesised n, T.length n > synthNameThreshold]
   in case long of
        [] -> prog
        _ ->
          let renames = assignShorts (Set.fromList names) long
           in prog {cdecls = map (renameDecl renames) (cdecls prog)}

-- | A source identifier starts with a letter or @_@ (never @$@), so a leading
--   @$@ marks a compiler-synthesised name — the only kind we rewrite.
isSynthesised :: Name -> Bool
isSynthesised = T.isPrefixOf "$"

-- | Assign each over-long name a short replacement, kept globally unique
--   against the existing names and the replacements chosen so far.
assignShorts :: Set Name -> [Name] -> M.Map Name Name
assignShorts used0 = go used0 M.empty
  where
    go _ acc [] = acc
    go used acc (n : rest) =
      let short = freshUnique used (shortNameFor n)
       in go (Set.insert short used) (M.insert n short acc) rest

-- | First of @base@, @base_1@, @base_2@, … not already taken. The hash in
--   @base@ makes a clash astronomically unlikely; the counter makes aliasing
--   two distinct names impossible.
freshUnique :: Set Name -> Name -> Name
freshUnique used base = go (0 :: Int)
  where
    go n =
      let cand = if n == 0 then base else base <> "_" <> show n
       in if cand `Set.member` used then go (n + 1) else cand

-- | Bounded replacement for an over-long synthesised name: a readable prefix
--   (keeps the @$scc$@ / @$cps$@ / @$df$@ provenance) plus an FNV-1a tag of
--   the full name — stable across unrelated edits, unlike a global counter.
shortNameFor :: Name -> Name
shortNameFor n = T.take 48 n <> "$x$" <> show (fnv1a32 n)

-- | Rewrite a declaration's own name and every name it references.
renameDecl :: M.Map Name Name -> CDecl -> CDecl
renameDecl renames = \case
  CFunDef n ps b -> CFunDef (rn n) ps (renameBody b)
  CValDef n b -> CValDef (rn n) (renameBody b)
  where
    rn x = M.findWithDefault x x renames
    -- Replacements are fresh ($x$-tagged), disjoint from the keys, so the
    -- folded renames never chain into one another.
    renameBody b = M.foldrWithKey renameVar b renames
