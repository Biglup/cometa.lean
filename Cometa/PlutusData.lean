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
import Cometa.Internal.Cbor
import Cometa.Internal.Output

/-! Typed construction of every Plutus data form, with a separate preserved
encoding identity. Map order and duplicate keys are retained by the encoder.
Hashing and imported-CBOR validation use the pinned native implementation.
-/

namespace Cometa

-- TYPES ----------------------------------------------------------------------

/-- Semantic Plutus data. Integers are arbitrary precision and bytes need not be text. -/
inductive PlutusData where
  /-- Constructor alternative and ordered fields. -/
  | constr (alternative : UInt64) (fields : List PlutusData)
  /-- Ordered map entries, including duplicate keys. -/
  | map (entries : List (PlutusData × PlutusData))
  /-- Ordered list entries. -/
  | list (entries : List PlutusData)
  /-- Arbitrary signed integer. -/
  | integer (value : Int)
  /-- Arbitrary byte sequence, encoded in chunks no larger than 64 bytes. -/
  | bytes (value : ByteArray)

/-- Validated datum bytes and their native-computed BLAKE2b-256 identity. -/
structure EncodedPlutusData where
  private mk ::
  private cbor : ByteArray
  private digest : Hash 32

namespace PlutusData

-- DEFINITIONS ----------------------------------------------------------------

/-- Encode semantic data using shortest integers, definite arrays/maps, and
bounded byte chunks. Re-encoding a parsed datum can change its hash; retain
`EncodedPlutusData.toCbor` when preserving an imported identity.
-/
def toCbor : PlutusData → ByteArray
  | .constr alternative fields =>
    let encoded := Internal.Cbor.array (fields.map toCbor)
    if alternative < 7 then Internal.Cbor.tag (121 + alternative) encoded
    else if alternative < 128 then Internal.Cbor.tag (1280 + alternative - 7) encoded
    else Internal.Cbor.tag 102 (Internal.Cbor.array [Internal.Cbor.unsigned alternative, encoded])
  | .map entries => Internal.Cbor.map (entries.map fun entry => (toCbor entry.1, toCbor entry.2))
  | .list entries => Internal.Cbor.array (entries.map toCbor)
  | .integer value => Internal.Cbor.integer value
  | .bytes value => Internal.Cbor.boundedBytes value
termination_by data => sizeOf data
decreasing_by
  all_goals simp_wf
  all_goals first
    | decreasing_tactic
    | (rename_i membership
       have smaller := List.sizeOf_lt_of_mem membership
       cases entry
       simp_all only [Prod.mk.sizeOf_spec]
       omega)

end PlutusData

namespace EncodedPlutusData

private def byteAt (bytes : ByteArray) (index : Nat) : Except Error UInt8 :=
  match bytes[index]? with
  | some byte => .ok byte
  | none => .error (.invalidInput "Truncated Plutus data CBOR")

/-- Check the ledger's byte-leaf/chunk bound before the native grammar parser.
The scan skips byte payloads and encoded integer arguments; native parsing still
checks container structure, constructor tags, and the complete datum grammar.
-/
private def checkByteChunks (bytes : ByteArray) : Except Error Unit := do
  let mut position := 0
  for _ in [:bytes.size] do
    if position == bytes.size then return ()
    let first ← byteAt bytes position
    position := position + 1
    let major := first.toNat / 32
    let additional := first.toNat % 32
    let mut argument := additional

    if 24 ≤ additional && additional ≤ 27 then
      argument := 0
      for _ in [:2 ^ (additional - 24)] do
        let byte ← byteAt bytes position
        position := position + 1
        argument := argument * 256 + byte.toNat
    else if 28 ≤ additional && additional < 31 then
      throw (.invalidInput "Reserved CBOR argument in Plutus data")

    if major == 2 && additional != 31 then
      if argument > 64 then throw (.invalidInput "Plutus data byte chunks must not exceed 64 bytes")
      if position + argument > bytes.size then throw (.invalidInput "Truncated Plutus data bytes")
      position := position + argument
  return ()

/-- Validate exactly one native-supported datum and hash its exact bytes.
Byte leaves/chunks, including bignum payloads, must be at most 64 bytes.
This checks datum serialization, not a validator's application-specific schema.
-/
def ofCbor (bytes : ByteArray) : EIO Error EncodedPlutusData := do
  EIO.ofExcept (checkByteChunks bytes)
  let digest ← (Internal.datumHash bytes).adapt (.native "EncodedPlutusData.ofCbor")
  return ⟨bytes, ← EIO.ofExcept (Hash.ofBytes digest)⟩

/-- Encode and validate typed data, assigning a fresh encoding identity. -/
def ofData (data : PlutusData) : EIO Error EncodedPlutusData := ofCbor data.toCbor

/-- Exact validated datum bytes. -/
def toCbor (data : EncodedPlutusData) : ByteArray := data.cbor

/-- Native-computed digest over the exact datum bytes, not a normalized encoding. -/
def hash (data : EncodedPlutusData) : Hash 32 := data.digest

instance : BEq EncodedPlutusData := ⟨fun left right => left.cbor == right.cbor⟩

end EncodedPlutusData
end Cometa
