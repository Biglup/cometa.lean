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

import Cometa.Hex

/-! Fixed-size public hashes. A byte-length proof does not establish a preimage. -/

namespace Cometa

-- TYPES ----------------------------------------------------------------------

/-- Immutable hash bytes with an explicit length invariant. -/
structure Hash (size : Nat) where
  /-- Hash bytes in encoded order. -/
  bytes : ByteArray
  /-- The byte length matches the type parameter. -/
  isValid : bytes.size = size
  deriving DecidableEq

namespace Hash

-- DEFINITIONS ----------------------------------------------------------------

/-- Check the expected byte length without changing the bytes. -/
def ofBytes (bytes : ByteArray) : Except Error (Hash size) :=
  if h : bytes.size = size then .ok ⟨bytes, h⟩
  else .error (.invalidInput s!"Expected a {size}-byte hash")

/-- Parse strict hexadecimal and check the expected byte length. -/
def ofHex (text : String) : Except Error (Hash size) := do
  ofBytes (← Hex.toBytes text)

/-- The unchanged hash bytes. -/
def toBytes (hash : Hash size) : ByteArray := hash.bytes

/-- Lowercase hexadecimal without a prefix. -/
def toHex (hash : Hash size) : String := Hex.ofBytes hash.bytes

instance : BEq (Hash size) := ⟨fun left right => left.bytes == right.bytes⟩
instance : ToString (Hash size) := ⟨toHex⟩

-- THEOREMS -------------------------------------------------------------------

/-- Every constructible hash has the required length. -/
@[simp] theorem toBytes_size (hash : Hash size) : hash.toBytes.size = size := hash.isValid

end Hash
end Cometa
