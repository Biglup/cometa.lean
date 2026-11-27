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
import Cometa.Internal.Cbor

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

private def policyAssetsCbor (policy : PolicyId) (assets : List (PolicyId × AssetName × Int)) :
    ByteArray :=
  let entries := assets.filterMap fun (entryPolicy, name, amount) =>
    if entryPolicy == policy then
      some (Internal.Cbor.bytes name.bytes, Internal.Cbor.integer amount)
    else none
  Internal.Cbor.canonicalMap entries

private def multiAssetCbor (value : Value) : ByteArray :=
  let assets := value.toList.filterMap fun (asset, amount) =>
    match asset with
    | .ada => none
    | .native policy name => some (policy, name, amount)
  let policies := (assets.map fun entry => entry.1).eraseDups
  let entries := policies.map fun policy =>
    (Internal.Cbor.bytes policy.bytes, policyAssetsCbor policy assets)
  Internal.Cbor.canonicalMap entries

/-- Serialize a checked output value as coin or `[coin, multiasset]`. Native-asset
maps use deterministic encoded-key order. No input entries are silently discarded
except quantities whose aggregate is zero.
-/
def CheckedOutput.toCbor (checked : CheckedOutput) : ByteArray :=
  let value := checked.val
  let coin := Internal.Cbor.unsigned (value.quantity .ada).toNat.toUInt64
  if value.toList.any (fun entry => entry.1 != .ada) then
    Internal.Cbor.array [coin, multiAssetCbor value]
  else coin

/-- Check output bounds and encode the resulting value. -/
def toOutputCbor (value : Value) : Except Error ByteArray := do
  return (← value.checkOutput).toCbor

/-- Encode a mint/burn map. Ada must be zero; native quantities fit signed 64 bits.
Zero aggregates are omitted. An empty result is a map; omit the body field when
an era disallows a present empty mint field.
-/
def toMintCbor (value : Value) : Except Error ByteArray := do
  if value.quantity .ada != 0 then throw (.invalidInput "Ada cannot be minted or burned")
  if value.toList.any (fun entry => entry.2 < -9223372036854775808 || entry.2 > 9223372036854775807) then
    throw (.invalidInput "Mint quantities must fit signed 64 bits")
  return multiAssetCbor value

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
