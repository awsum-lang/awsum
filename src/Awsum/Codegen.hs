module Awsum.Codegen (Target (..)) where

import Relude

data Target
  = TargetJS
  | TargetLua
  | TargetLLVM
  | TargetJVM
  | TargetWASM
  deriving stock (Eq, Show)
