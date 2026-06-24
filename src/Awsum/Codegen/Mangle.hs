-- | The single source of truth for turning an Awsum identifier into a
--   codegen-safe symbol. Shared by all five backends so the escaping discipline
--   lives in one place — a missed copy used to mean a silent per-backend split.
module Awsum.Codegen.Mangle
  ( mangle,
    mangleNoPrefix,
  )
where

import Data.Char qualified as Char
import Data.Text qualified as T
import Numeric (showHex)
import Relude

-- | Map an identifier to a codegen-safe symbol — valid in every backend's
--   identifier grammar — with a @v_@ prefix so generated names never collide
--   with a backend's reserved entry point (LLVM @\@main@, WASI @_start@, the C
--   @main@). The JS backend keeps the program entry point literally @main@ for
--   its runner and so special-cases it before calling this.
--
--   Output alphabet: @[A-Za-z0-9_$]@. The @$@ is the compiler's own sigil for
--   minted names (@$cps$f@, @$scc$…@, @$apply$f@) — it never appears in user
--   source (the parser admits only @[A-Za-z0-9_']@), so any name carrying it is
--   provably not a user name, which is what keeps minted names from colliding
--   with user names for free. @$@ is a valid identifier character on all five
--   targets (LLVM IR @[-a-zA-Z$._0-9]@, JS, JVM \/ CIL unqualified names, WAT
--   idchars), so it passes through unescaped — one marker end to end, not a
--   sigil we convert into a second sigil.
--
--   The map is total and injective. The only escapes are for characters a user
--   /can/ write that aren't universally legal: the apostrophe (primed names like
--   @xs'@) and — as a safety net — any non-ASCII code point, which the parser
--   currently rejects but which could later be admitted by escaping rather than
--   rejecting, without touching any backend.
mangle :: Text -> Text
mangle = ("v_" <>) . mangleNoPrefix

-- | The escape without the @v_@ prefix.
--
--   Injective: every escape begins with @_@ and the character right after it
--   (@_@\/@q@\/@u@) selects the case, so distinct names never produce the same
--   symbol; @$@ and the alphanumerics map to themselves and nothing else maps
--   onto them.
--
--     * @[A-Za-z0-9$]@     → itself
--     * @_@                → @__@
--     * @'@                → @_q@   (@q@ for quote\/prime — a primed name @xs'@)
--     * any other char @c@ → @_u<hex>_@   (lowercase code point, @_@-terminated;
--                                          @q@ is never a hex digit, so this
--                                          can't be confused with the case above)
--
--   The last case is unreachable for parser-accepted input (identifiers are
--   ASCII @[A-Za-z0-9_']@ and the only minted character is @$@) — it is the
--   safety net described on 'mangle'.
mangleNoPrefix :: Text -> Text
mangleNoPrefix = T.concatMap escapeChar
  where
    escapeChar :: Char -> Text
    escapeChar c
      | Char.isAsciiUpper c || Char.isAsciiLower c || Char.isDigit c || c == '$' = T.singleton c
      | c == '_' = "__"
      | c == '\'' = "_q"
      | otherwise = "_u" <> toText (showHex (Char.ord c) "") <> "_"
