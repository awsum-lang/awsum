module Awsum.Codegen (Target (..)) where

import Relude

data Target
  = TargetJS
  | TargetLua
  | TargetLLVM
  | TargetJVM
  | TargetWASM
  | TargetCLR
  deriving stock (Eq, Show)
