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
import Cometa.Internal.CborDecoder
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
  private contents : PlutusData

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

private def bytesInteger (bytes : ByteArray) : Nat :=
  bytes.data.foldl (fun value byte => value * 256 + byte.toNat) 0

private def fromTerm : Internal.Cbor.Term → Except Error PlutusData
  | .unsigned value => .ok (.integer value.toNat)
  | .negative value => .ok (.integer (-Int.ofNat value.toNat - 1))
  | term@(.bytes _) => do return .bytes (← term.asBytes (some 64))
  | .array items => do return .list (← items.mapM fromTerm)
  | .map entries => do
    let pairs ← entries.mapM fun entry => do return (← fromTerm entry.1, ← fromTerm entry.2)
    return .map pairs
  | .tag number item => do
    if number == 2 || number == 3 then
      let magnitude := bytesInteger (← item.asBytes (some 64))
      return .integer (if number == 2 then magnitude else -Int.ofNat magnitude - 1)
    else if number == 102 then
      let .array [.unsigned alternative, .array fields] := item
        | throw (.invalidInput "Invalid general Plutus constructor")
      return .constr alternative (← fields.mapM fromTerm)
    else
      let alternative ← if 121 ≤ number && number ≤ 127 then pure (number - 121)
        else if 1280 ≤ number && number ≤ 1400 then pure (number - 1280 + 7)
        else throw (.invalidInput "Unknown Plutus data tag")
      let .array fields := item | throw (.invalidInput "Constructor fields must be an array")
      return .constr alternative (← fields.mapM fromTerm)
  | _ => .error (.invalidInput "Unsupported Plutus data item")
termination_by term => sizeOf term
decreasing_by
  all_goals simp_wf
  all_goals first
    | decreasing_tactic
    | (rename_i membership
       have smaller := List.sizeOf_lt_of_mem membership
       cases entry
       simp_all only [Prod.mk.sizeOf_spec]
       omega)

/-- Decode exactly one semantic datum, checking constructor arities, tags and
64-byte leaves/chunks. Map order and duplicate keys are preserved. Re-encoding
this semantic tree may change identity; use EncodedPlutusData for preservation.
-/
def ofCbor (bytes : ByteArray) : Except Error PlutusData := do
  fromTerm (← Internal.Cbor.decode bytes)

end PlutusData

namespace EncodedPlutusData

/-- Validate exactly one native-supported datum and hash its exact bytes.
Byte leaves/chunks, including bignum payloads, must be at most 64 bytes.
This checks datum serialization, not a validator's application-specific schema.
-/
def ofCbor (bytes : ByteArray) : EIO Error EncodedPlutusData := do
  let contents ← EIO.ofExcept (PlutusData.ofCbor bytes)
  let digest ← (Internal.datumHash bytes).adapt (.native "EncodedPlutusData.ofCbor")
  return ⟨bytes, ← EIO.ofExcept (Hash.ofBytes digest), contents⟩

/-- Encode and validate typed data, assigning a fresh encoding identity. -/
def ofData (data : PlutusData) : EIO Error EncodedPlutusData := ofCbor data.toCbor

/-- Exact validated datum bytes. -/
def toCbor (data : EncodedPlutusData) : ByteArray := data.cbor

/-- Inspect the semantic tree without changing its original encoding or hash. -/
def toData (data : EncodedPlutusData) : PlutusData := data.contents

/-- Native-computed digest over the exact datum bytes, not a normalized encoding. -/
def hash (data : EncodedPlutusData) : Hash 32 := data.digest

instance : BEq EncodedPlutusData := ⟨fun left right => left.cbor == right.cbor⟩

end EncodedPlutusData
end Cometa
