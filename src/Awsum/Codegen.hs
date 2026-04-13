module Awsum.Codegen (Target (..)) where

import Relude

data Target
  = TargetJS
  | TargetLua
  | TargetLLVM
  | TargetJVM
  deriving stock (Eq, Show)
