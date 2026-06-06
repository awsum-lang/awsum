-- | Prettyprinter layout glue shared by the text renderers — the formatter
--   ('Awsum.Render') and the codegen projections that build a @Doc@
--   ('Awsum.Codegen.JS.Syntax', 'Awsum.Codegen.WASM'). One copy of each
--   primitive so the renderers can't drift.
module Awsum.Pretty
  ( vsepHard,
    vsepBlank,
    layoutUnbounded,
  )
where

import Prettyprinter
  ( Doc,
    LayoutOptions (..),
    PageWidth (Unbounded),
    concatWith,
    hardline,
    layoutPretty,
  )
import Prettyprinter.Render.Text (renderStrict)
import Relude

-- | One forced line break between successive items.
vsepHard :: [Doc ann] -> Doc ann
vsepHard = concatWith (\a b -> a <> hardline <> b)

-- | A blank line between successive items (two forced breaks).
vsepBlank :: [Doc ann] -> Doc ann
vsepBlank = concatWith (\a b -> a <> hardline <> hardline <> b)

-- | Project a 'Doc' to text at 'Unbounded' page width — for renderers whose
--   every break is a 'hardline', so no layout decision depends on width.
--   prettyprinter emits no trailing whitespace, so blank lines come out empty.
layoutUnbounded :: Doc ann -> Text
layoutUnbounded = renderStrict . layoutPretty (LayoutOptions {layoutPageWidth = Unbounded})
