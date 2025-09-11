module Awsum.Codegen (Target (..)) where

import Relude

data Target
  = TargetJS
  | TargetLua
  deriving stock (Eq, Show)
