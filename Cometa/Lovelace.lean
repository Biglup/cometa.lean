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

import Cometa.Error

/-! Bounded lovelace amounts. One ada is one million lovelace. -/

namespace Cometa

-- TYPES ----------------------------------------------------------------------

/-- A nonnegative amount representable by cardano-c's unsigned 64-bit coin type.
This bound is a representation limit, not a claim about circulating supply.
-/
structure Lovelace where
  /-- Amount in lovelace. -/
  value : Nat
  /-- The amount fits the native coin representation. -/
  isValid : value ≤ 18446744073709551615
  deriving DecidableEq

namespace Lovelace

-- DEFINITIONS ----------------------------------------------------------------

/-- Validate an arbitrary natural number without truncation or wrapping. -/
def ofNat (value : Nat) : Except Error Lovelace :=
  if h : value ≤ 18446744073709551615 then
    .ok ⟨value, h⟩
  else
    .error (.invalidInput "Lovelace exceeds the unsigned 64-bit limit")

/-- Validate a signed quantity. Negative values are rejected before conversion. -/
def ofInt (value : Int) : Except Error Lovelace :=
  if value < 0 then
    .error (.invalidInput "Lovelace must be nonnegative")
  else
    ofNat value.toNat

/-- Add amounts, rejecting overflow rather than wrapping. -/
def add (left right : Lovelace) : Except Error Lovelace :=
  ofNat (left.value + right.value)

instance : ToString Lovelace where
  toString amount := toString amount.value

end Lovelace
end Cometa
