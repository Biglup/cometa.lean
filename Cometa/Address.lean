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
import Cometa.Internal.Address

/-! Cardano addresses validated by the pinned native parser.

The bytes and display text are owned by Lean. Parsing is effectful; inspecting an
already parsed address is pure. Acceptance does not establish ledger-era validity,
network availability, or suitability as a payment destination.
-/

namespace Cometa

-- TYPES ----------------------------------------------------------------------

/-- A parsed Shelley, reward, pointer, or Byron address. -/
structure Address where
  private mk ::
  private bytes : ByteArray
  private text : String

namespace Address

-- DEFINITIONS ----------------------------------------------------------------

/-- Parse a Bech32 or Base58 address. Empty text and embedded NULs are rejected.
Native errors retain their numeric code; no input text is included in diagnostics.
-/
def ofString (text : String) : EIO Error Address := do
  if text.isEmpty || text.contains (Char.ofNat 0) then
    throw (.invalidInput "Address text must be nonempty and contain no NUL bytes")

  let (bytes, display) ← (Internal.addressFromText text).adapt (.native "Address.ofString")
  return ⟨bytes, display⟩

/-- Parse serialized address bytes. Empty or malformed input is rejected. -/
def ofBytes (bytes : ByteArray) : EIO Error Address := do
  if bytes.isEmpty then
    throw (.invalidInput "Address bytes must be nonempty")

  let (encoded, display) ← (Internal.addressFromBytes bytes).adapt (.native "Address.ofBytes")
  return ⟨encoded, display⟩

/-- Serialized address bytes. The result has ordinary immutable value semantics. -/
def toBytes (address : Address) : ByteArray := address.bytes

/-- Display encoding supplied by the native address parser. -/
def toString (address : Address) : String := address.text

/-- Whether the address has a payment-address header (types 0 through 8).
This excludes reward accounts; it does not check era-specific output rules.
-/
def isPayment (address : Address) : Bool :=
  match address.bytes[0]? with
  | some header => header.toNat / 16 ≤ 8
  | none => false

instance : BEq Address where
  beq left right := left.bytes == right.bytes

instance : ToString Address where
  toString := Address.toString

end Address

/-- Version of the cardano-c library loaded by this process. -/
def nativeVersion : BaseIO String := Internal.nativeVersion

end Cometa
