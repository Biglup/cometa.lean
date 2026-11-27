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

import Cometa.Asset
import Cometa.Internal.Component

/-! Finite signed asset bundles with arbitrary-precision arithmetic. Duplicate
entries add and missing assets have quantity zero. Output/mint serialization
checks domain-specific bounds separately; intermediate balances never wrap.
-/

namespace Cometa

-- TYPES ----------------------------------------------------------------------

/-- A finite signed asset bundle. Observations aggregate duplicate asset entries. -/
structure Value where
  private mk ::
  private entries : List (AssetId × Int)

namespace Value

-- DEFINITIONS ----------------------------------------------------------------

/-- Assemble a signed bundle; duplicate asset quantities add without overflow. -/
def ofList (entries : List (AssetId × Int)) : Value := ⟨entries⟩

/-- The empty bundle. -/
def zero : Value := ⟨[]⟩

/-- One signed asset quantity. -/
def singleton (asset : AssetId) (amount : Int) : Value := ⟨[(asset, amount)]⟩

/-- An arbitrary signed amount of ada measured in lovelace. -/
def lovelace (amount : Int) : Value := singleton .ada amount

/-- Sum the requested asset's quantities; absent assets have quantity zero. -/
def quantity (value : Value) (asset : AssetId) : Int :=
  (value.entries.map fun entry => if entry.1 = asset then entry.2 else 0).sum

/-- Add signed bundles without wrapping, clamping, or output validation. -/
def add (left right : Value) : Value := ⟨left.entries ++ right.entries⟩

instance : Add Value := ⟨add⟩

/-- Multiply all quantities by an arbitrary signed scalar. -/
def scale (factor : Int) (value : Value) : Value :=
  ⟨value.entries.map fun (asset, amount) => (asset, factor * amount)⟩

/-- Negate every quantity, retaining exact signed arithmetic. -/
def negate (value : Value) : Value := value.scale (-1)

/-- Subtract right from left; negative results are retained. -/
def difference (left right : Value) : Value := left + right.negate

/-- Unique nonzero quantities in first-occurrence asset order. This order is not
CBOR map order; serialization sorts encoded keys independently.
-/
def toList (value : Value) : List (AssetId × Int) :=
  let assets := (value.entries.map Prod.fst).eraseDups
  let quantities := assets.map fun asset => (asset, value.quantity asset)
  quantities.filter fun entry => entry.2 != 0

/-- No asset has a nonzero quantity. -/
def isZero (value : Value) : Bool := value.toList.isEmpty

/-- Output representability: nonnegative unsigned 64-bit lovelace and nonnegative
signed-64-bit native quantities. This does not establish minimum ada or ledger validity.
-/
def ValidOutput (value : Value) : Prop :=
  ∀ entry ∈ value.toList, 0 ≤ entry.2 ∧
    entry.2 ≤ (if entry.1 = .ada then 18446744073709551615 else 9223372036854775807)

instance (value : Value) : Decidable value.ValidOutput :=
  inferInstanceAs (Decidable (∀ entry ∈ value.toList, _))

/-- A value accompanied by evidence that all output quantity bounds hold. -/
abbrev CheckedOutput := {value : Value // value.ValidOutput}

/-- Check output quantity bounds and return their evidence; no native call is made. -/
def checkOutput (value : Value) : Except Error CheckedOutput :=
  if h : value.ValidOutput then .ok ⟨value, h⟩
  else .error (.invalidInput "Output quantities must be nonnegative and fit their native bounds")

/-- Copy checked scalar fields for native value/multi-asset construction. This
transport is not CBOR; integer bounds are checked by the calling codec API.
-/
def toNative (value : Value) : Internal.Component :=
  let assets := value.toList.filterMap fun (asset, amount) =>
    match asset with
    | .ada => none
    | .native policy name => some (Internal.Component.node 0 (Int64.ofInt amount).toUInt64
        policy.bytes name.bytes "" [])
  .node 0 (value.quantity .ada).toNat.toUInt64 ByteArray.empty ByteArray.empty "" assets

/-- Check native getter results before exposing them as a Lean bundle. Duplicate
asset identities are rejected rather than silently aggregated during import.
-/
def ofNative : Internal.Component → Except Error Value
  | .node _ coin _ _ _ entries => do
    let mut result := Value.lovelace coin.toNat
    let mut seen : List AssetId := []
    for entry in entries do
      let .node _ amount policy name _ _ := entry
      let asset := AssetId.native (← PolicyId.ofBytes policy) (← AssetName.ofBytes name)
      if seen.contains asset then throw (.invalidInput "Duplicate native asset identity")
      seen := asset :: seen
      result := result + Value.singleton asset (Int64.ofUInt64 amount).toInt
    return result

/-- Construct and serialize a checked value through cardano-c. -/
def CheckedOutput.toCbor (checked : CheckedOutput) : EIO Error ByteArray :=
  (Internal.componentEncode 1 checked.val.toNative).adapt (.native "Value.toOutputCbor")

/-- Check quantity bounds, then use the native value constructor and writer. -/
def toOutputCbor (value : Value) : EIO Error ByteArray := do
  let checked ← EIO.ofExcept value.checkOutput
  checked.toCbor

/-- Construct and serialize a native mint/burn map. Ada must be zero and native
quantities must fit signed 64 bits. Zero aggregates are omitted.
-/
def toMintCbor (value : Value) : EIO Error ByteArray := do
  if value.quantity .ada != 0 then throw (.invalidInput "Ada cannot be minted or burned")
  if value.toList.any (fun entry => entry.2 < -9223372036854775808 || entry.2 > 9223372036854775807) then
    throw (.invalidInput "Mint quantities must fit signed 64 bits")
  (Internal.componentEncode 2 value.toNative).adapt (.native "Value.toMintCbor")

/-- Parse with the native value reader, then prove bounds for its copied quantities. -/
def ofOutputCbor (bytes : ByteArray) : EIO Error CheckedOutput := do
  let fields ← (Internal.componentDecode 1 bytes).adapt (.native "Value.ofOutputCbor")
  EIO.ofExcept (ofNative fields >>= checkOutput)

/-- Parse a signed mint/burn map through the native multi-asset reader. -/
def ofMintCbor (bytes : ByteArray) : EIO Error Value := do
  let fields ← (Internal.componentDecode 2 bytes).adapt (.native "Value.ofMintCbor")
  EIO.ofExcept (ofNative fields)

-- THEOREMS -------------------------------------------------------------------

/-- Bundle addition conserves each asset's signed quantity exactly. -/
@[simp] theorem quantity_add (left right : Value) (asset : AssetId) :
    (left + right).quantity asset = left.quantity asset + right.quantity asset := by
  change ((left.entries ++ right.entries).map _).sum = _
  simp only [List.map_append, List.sum_append, quantity]

/-- Successful validation establishes the bounds for the original requested value. -/
theorem checkOutput_sound (value : Value) (checked : CheckedOutput)
    (success : value.checkOutput = .ok checked) : value.ValidOutput := by
  unfold checkOutput at success
  split at success <;> simp_all

/-- Every checked output carries a proof of the declared quantity bounds. -/
theorem checkedOutput_valid (checked : CheckedOutput) : checked.val.ValidOutput := checked.property

end Value
end Cometa
