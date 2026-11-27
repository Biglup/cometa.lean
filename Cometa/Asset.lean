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

import Cometa.Hash

/-! Native asset identifiers: a 28-byte policy and a name of at most 32 bytes.
Names are arbitrary bytes, not necessarily UTF-8. Empty names are permitted.
-/

namespace Cometa

-- TYPES ----------------------------------------------------------------------

/-- A native asset's 28-byte minting-policy script hash. -/
abbrev PolicyId := Hash 28

/-- A byte-valued native asset name with its ledger length bound. -/
structure AssetName where
  /-- The exact name bytes, which need not be text. -/
  bytes : ByteArray
  /-- Native asset names contain at most 32 bytes. -/
  isValid : bytes.size ≤ 32
  deriving DecidableEq

/-- Ada or a native asset identified by policy and name. -/
inductive AssetId where
  /-- Ada quantities are measured in lovelace. -/
  | ada
  /-- A native asset's policy and arbitrary byte name. -/
  | native (policy : PolicyId) (name : AssetName)
  deriving DecidableEq

-- DEFINITIONS ----------------------------------------------------------------

namespace PolicyId

/-- Validate a 28-byte policy identifier. -/
def ofBytes (bytes : ByteArray) : Except Error PolicyId := Hash.ofBytes bytes

/-- Parse exactly 28 bytes of strict hexadecimal. -/
def ofHex (text : String) : Except Error PolicyId := Hash.ofHex text

end PolicyId

namespace AssetName

/-- Validate name bytes without interpreting them as text. -/
def ofBytes (bytes : ByteArray) : Except Error AssetName :=
  if h : bytes.size ≤ 32 then .ok ⟨bytes, h⟩
  else .error (.invalidInput "An asset name must contain at most 32 bytes")

/-- Parse strict hexadecimal; empty names are accepted. -/
def ofHex (text : String) : Except Error AssetName := do
  ofBytes (← Hex.toBytes text)

/-- Encode UTF-8 text, then check its byte length rather than its character count. -/
def ofString (text : String) : Except Error AssetName := ofBytes text.toUTF8

/-- Exact name bytes. -/
def toBytes (name : AssetName) : ByteArray := name.bytes

/-- Lowercase hexadecimal representation, safe for nontext names. -/
def toHex (name : AssetName) : String := Hex.ofBytes name.bytes

instance : BEq AssetName := ⟨fun left right => left.bytes == right.bytes⟩

/-- Every constructible asset name respects the byte-length limit. -/
@[simp] theorem toBytes_size (name : AssetName) : name.toBytes.size ≤ 32 := name.isValid

end AssetName

instance : BEq AssetId := ⟨fun left right => decide (left = right)⟩

instance : ToString AssetId where
  toString
    | .ada => "lovelace"
    | .native policy name => s!"{policy}.{name.toHex}"

end Cometa
