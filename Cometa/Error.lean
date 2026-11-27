/-
Copyright 2026 Biglup Labs
SPDX-License-Identifier: Apache-2.0

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-/

/-! Structured failures shared by validation and native operations. -/

-- TYPES ----------------------------------------------------------------------

namespace Cometa

/-- Expected failures. Diagnostic fields must never contain secret material. -/
inductive Error where
  /-- Input violates a public format, bound, or domain restriction. -/
  | invalidInput (message : String)
  /-- A native operation failed with the original `cardano_error_t` code. -/
  | native (operation : String) (code : UInt32)
  deriving Repr, BEq

-- DEFINITIONS ----------------------------------------------------------------

instance : ToString Error where
  toString
    | .invalidInput message => message
    | .native operation code => s!"{operation} failed (cardano-c error {code})"

end Cometa
