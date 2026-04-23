-- | Post-pipeline stack-safety verifier.
--
-- After 'Awsum.Scc' (mutual → self-recursion) and 'Awsum.Cps' (non-tail
-- self → tail-self via K chain) have run, the invariant is: /no
-- non-tail recursive call remains in the Core program/. Any remainder
-- is either a skipped SCC (today: an SCC containing a 'CValDef', which
-- has no fixed point and is a user error) or a bug in one of the
-- passes — both cases produce stack-unsafe code that would silently
-- overflow at depth.
--
-- This module walks the post-CPS Core and reports any violation so the
-- compiler can refuse to lower such a program to backends. It is
-- strictly a safety net: on every currently-green test the verifier
-- reports nothing.
--
-- See @docs\/recursion.md@ for the full pipeline and
-- @docs\/recursion-roadmap.md@ for the open work this check guards.
module Awsum.StackSafety
  ( StackSafetyIssue (..),
    verifyStackSafety,
  )
where

import Awsum.CallGraph (containsSelfCall, hasNonTailSelfCall, stronglyConnected)
import Awsum.Core
import Awsum.Syntax (Name)
import Data.Graph qualified as G
import Data.Map.Strict qualified as Map
import Relude

-- | What the verifier flags. Each constructor carries enough
-- information to build a user-facing diagnostic at the call site.
data StackSafetyIssue
  = -- | All members of a cycle are 'CValDef's. Mutually recursive
    -- top-level values have no fixed point (evaluating any of them
    -- demands another with no base case), so the program is
    -- semantically ill-formed regardless of the compiler — a plain
    -- user error. Reported without any "compiler bug" hedging.
    MutuallyRecursiveValues [Name]
  | -- | A recursion shape the compiler could not prove stack-safe.
    -- Covers both "a call-graph cycle with at least one 'CFunDef'
    -- that 'Awsum.Scc' didn't know how to merge" and "a 'CFunDef'
    -- with a non-tail self-call that 'Awsum.Cps' didn't transform".
    -- Programs landing here may well be correct — the compiler just
    -- lacks the transformation to lower them safely. Treated as a
    -- user-visible limitation, not an internal bug.
    UnsupportedRecursionShape [Name]
  deriving stock (Show, Eq)

-- | Collect every stack-safety violation in @prog@. An empty result
-- means the program is safe to hand off to 'Awsum.Tco' and the
-- backends.
verifyStackSafety :: CoreProgram -> [StackSafetyIssue]
verifyStackSafety prog@(CoreProgram ds) =
  mutualCycles <> nonTailSelf
  where
    declMap :: Map Name CDecl
    declMap = Map.fromList [(nameOf d, d) | d <- ds]

    nameOf :: CDecl -> Name
    nameOf = \case
      CFunDef n _ _ -> n
      CValDef n _ -> n

    isValDef :: Name -> Bool
    isValDef n = case Map.lookup n declMap of
      Just CValDef {} -> True
      _ -> False

    mutualCycles :: [StackSafetyIssue]
    mutualCycles =
      [ classifyCycle members
      | G.CyclicSCC members <- stronglyConnected prog,
        case members of
          [_] -> False -- size-1 SCC = self-recursion; checked separately below
          _ -> True
      ]

    classifyCycle :: [Name] -> StackSafetyIssue
    classifyCycle members
      | all isValDef members = MutuallyRecursiveValues members
      | otherwise = UnsupportedRecursionShape members

    nonTailSelf :: [StackSafetyIssue]
    nonTailSelf =
      [ UnsupportedRecursionShape [n]
      | CFunDef n _ body <- ds,
        -- Strip the TCO wrapper if it happens to be present (defensive:
        -- the verifier runs before Tco in the current pipeline, but we
        -- don't want to be fragile to reorderings).
        let unwrapped = stripLoop body,
        -- If a function body syntactically contains a non-tail self-
        -- reference to its own name, Cps failed to CPS-transform it
        -- (or chose not to). Either way it is a stack-safety hole.
        hasNonTailSelfCall n unwrapped,
        -- Sanity filter: we also want the function's own name to
        -- actually appear in the body (covers the case where
        -- 'hasNonTailSelfCall' is vacuously false on a body with no
        -- self-calls at all).
        containsSelfCall n unwrapped
      ]

    stripLoop :: CExpr -> CExpr
    stripLoop (CLoop b) = b
    stripLoop e = e
