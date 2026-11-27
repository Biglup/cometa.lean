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

/-! Checked 32-byte BLAKE2b-256 transaction-body identifiers.
A well-formed identifier does not establish that a transaction exists on chain.
-/

namespace Cometa

-- TYPES ----------------------------------------------------------------------

/-- A transaction-body hash with its exact byte-length invariant. -/
structure TransactionId where
  /-- Hash bytes in their encoded order. -/
  bytes : ByteArray
  /-- BLAKE2b-256 identifiers contain exactly 32 bytes. -/
  isValid : bytes.size = 32

namespace TransactionId

-- DEFINITIONS ----------------------------------------------------------------

/-- Validate the identifier length without changing its bytes. -/
def ofBytes (bytes : ByteArray) : Except Error TransactionId :=
  if h : bytes.size = 32 then
    .ok ⟨bytes, h⟩
  else
    .error (.invalidInput "A transaction ID must contain exactly 32 bytes")

/-- Parse exactly 64 ASCII hexadecimal digits, with either letter case. -/
def ofHex (text : String) : Except Error TransactionId := do
  ofBytes (← Hex.toBytes text)

/-- The 32 hash bytes, with immutable value semantics. -/
def toBytes (identifier : TransactionId) : ByteArray := identifier.bytes

/-- The 64 lowercase hexadecimal digits, without a prefix. -/
def toHex (identifier : TransactionId) : String := Hex.ofBytes identifier.bytes

instance : BEq TransactionId where
  beq left right := left.bytes == right.bytes

instance : ToString TransactionId where
  toString := toHex

-- THEOREMS -------------------------------------------------------------------

/-- Every constructible identifier has the required byte length. -/
@[simp] theorem toBytes_size (identifier : TransactionId) : identifier.toBytes.size = 32 :=
  identifier.isValid

end TransactionId
end Cometa
