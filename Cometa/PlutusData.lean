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
import Cometa.Internal.Component
import Cometa.Internal.Output

/-! Typed Plutus data views backed by native constructors, readers, writers and
hashing. Copied semantic trees remain separate from imported encoding identity.
Native map getters retain ordered pairs and duplicate keys.
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

/-- Copy semantic fields for native constructors; decimal text transports Int
without narrowing it to a machine integer. No CBOR is produced in Lean.
-/
def toNative : PlutusData → Internal.Component
  | .constr alternative fields => .node 0 alternative ByteArray.empty ByteArray.empty "" (fields.map toNative)
  | .map entries => .node 1 0 ByteArray.empty ByteArray.empty ""
      (entries.flatMap fun entry => [toNative entry.1, toNative entry.2])
  | .list entries => .node 2 0 ByteArray.empty ByteArray.empty "" (entries.map toNative)
  | .integer value => .node 3 0 ByteArray.empty ByteArray.empty (toString value) []
  | .bytes value => .node 4 0 value ByteArray.empty "" []
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

private def pairs : List PlutusData → Except Error (List (PlutusData × PlutusData))
  | [] => .ok []
  | key :: value :: rest => do return (key, value) :: (← pairs rest)
  | [_] => .error (.invalidInput "Incomplete native map snapshot")

/-- Validate and copy native data getters into the public semantic tree. -/
def ofNative : Internal.Component → Except Error PlutusData
  | .node kind number payload _ text children => do
    match kind with
    | 0 => return .constr number (← children.mapM ofNative)
    | 1 => return .map (← pairs (← children.mapM ofNative))
    | 2 => return .list (← children.mapM ofNative)
    | 3 =>
      let some value := text.toInt? | throw (.invalidInput "Invalid native integer snapshot")
      return .integer value
    | 4 => return .bytes payload
    | _ => throw (.invalidInput "Unknown native Plutus data kind")

/-- Construct native Plutus objects and serialize with the pinned native writer.
The native writer chooses container forms. Imported identity belongs to
`EncodedPlutusData`, not to a re-encoded semantic tree.
-/
def toCbor (data : PlutusData) : EIO Error ByteArray :=
  (Internal.componentEncode 3 data.toNative).adapt (.native "PlutusData.toCbor")

/-- Parse through the native Plutus data codec and copy all semantic fields. -/
def ofCbor (bytes : ByteArray) : EIO Error PlutusData := do
  let fields ← (Internal.componentDecode 3 bytes).adapt (.native "PlutusData.ofCbor")
  EIO.ofExcept (ofNative fields)

end PlutusData

namespace EncodedPlutusData

/-- Validate exactly one native-supported datum and hash its exact bytes.
This follows native parsing acceptance, which is broader than ledger validation
(for example, the pinned reader accepts oversized byte leaves).
-/
def ofCbor (bytes : ByteArray) : EIO Error EncodedPlutusData := do
  let contents ← PlutusData.ofCbor bytes
  let digest ← (Internal.datumHash bytes).adapt (.native "EncodedPlutusData.ofCbor")
  return ⟨bytes, ← EIO.ofExcept (Hash.ofBytes digest), contents⟩

/-- Encode and validate typed data, assigning a fresh encoding identity. -/
def ofData (data : PlutusData) : EIO Error EncodedPlutusData := do
  ofCbor (← data.toCbor)

/-- Exact validated datum bytes. -/
def toCbor (data : EncodedPlutusData) : ByteArray := data.cbor

/-- Inspect the semantic tree without changing its original encoding or hash. -/
def toData (data : EncodedPlutusData) : PlutusData := data.contents

/-- Native-computed digest over the exact datum bytes, not a normalized encoding. -/
def hash (data : EncodedPlutusData) : Hash 32 := data.digest

instance : BEq EncodedPlutusData := ⟨fun left right => left.cbor == right.cbor⟩

end EncodedPlutusData
end Cometa
