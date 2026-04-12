module Awsum.Codegen (Target (..)) where

import Relude

data Target
  = TargetJS
  | TargetLua
  | TargetLLVM
  deriving stock (Eq, Show)
