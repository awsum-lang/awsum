module Awsum.Codegen (Target (..)) where

import Relude

data Target
  = TargetLLVM
  | TargetJVM
  | TargetCLR
  | TargetWASM
  | TargetJS
  deriving stock (Eq, Show)
