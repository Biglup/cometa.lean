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

import Cometa.VKeyWitness

/-! Native key-witness collections with checked key uniqueness. Native insertion
can replace a signature for an existing key; checked construction rejects duplicate
keys instead. A merge validator describes observed contents independently of order.
-/

namespace Cometa

-- TYPES ----------------------------------------------------------------------

/-- A native key-witness collection with one signature per public key. -/
structure VKeyWitnessSet where
  private mk ::
  /-- Members in native collection order. -/
  witnesses : List VKeyWitness
  /-- Public-key uniqueness checked on the copied native snapshot. -/
  unique : (witnesses.map VKeyWitness.verificationKey).Nodup
  /-- Whether the imported or constructed set carries CBOR tag 258. -/
  tagged : Bool
  private cbor : ByteArray

namespace VKeyWitnessSet

-- DEFINITIONS ----------------------------------------------------------------

/-- Parse through the native set reader and reject repeated public keys, even
when signatures match. Original tagged/untagged bytes remain available unchanged.
-/
def ofCbor (bytes : ByteArray) : EIO Error VKeyWitnessSet := do
  let .node tagged _ _ _ _ children ←
    (Internal.componentDecode 18 bytes).adapt (.native "VKeyWitnessSet.ofCbor")
  let witnesses ← children.mapM fun | .node _ _ encoded _ _ _ => VKeyWitness.ofCbor encoded
  if unique : (witnesses.map VKeyWitness.verificationKey).Nodup then
    return ⟨witnesses, unique, tagged != 0, bytes⟩
  else throw (.invalidInput "Duplicate verification key")

/-- Construct a native set without silently replacing requested signatures.
Tagged sets are the default; older workflows can explicitly request untagged sets.
-/
def ofList (witnesses : List VKeyWitness) (tagged : Bool := true) : EIO Error VKeyWitnessSet := do
  unless (witnesses.map VKeyWitness.verificationKey).Nodup do
    throw (.invalidInput "Duplicate verification key")
  let children := witnesses.map fun witness => Internal.Component.node 0 0
    witness.toCbor ByteArray.empty "" []
  let fields := Internal.Component.node (if tagged then 1 else 0) 0 ByteArray.empty ByteArray.empty "" children
  let bytes ← (Internal.componentEncode 18 fields).adapt (.native "VKeyWitnessSet.ofList")
  ofCbor bytes

/-- Exact original or native-produced collection bytes. -/
def toCbor (witnesses : VKeyWitnessSet) : ByteArray := witnesses.cbor

/-- Semantic key/signature identities in observed order. -/
def identities (witnesses : VKeyWitnessSet) : List (ByteArray × ByteArray) :=
  witnesses.witnesses.map VKeyWitness.identity

/-- Verify every key witness against a transaction ID using the native verifier.
The empty collection succeeds vacuously; signer completeness is a separate policy.
-/
def verifyTransaction (witnesses : VKeyWitnessSet) (identifier : TransactionId) : EIO Error Bool := do
  for witness in witnesses.witnesses do
    unless ← witness.verifyTransaction identifier do return false
  return true

/-- The observed result contains exactly the union of both input collections.
It must retain all original/requested signatures and introduce no extra witnesses.
-/
def MergeResult (before additions result : VKeyWitnessSet) : Prop :=
  (∀ identity ∈ before.identities, identity ∈ result.identities) ∧
  (∀ identity ∈ additions.identities, identity ∈ result.identities) ∧
  (∀ identity ∈ result.identities, identity ∈ before.identities ∨ identity ∈ additions.identities)

instance (before additions result : VKeyWitnessSet) : Decidable (MergeResult before additions result) :=
  inferInstanceAs (Decidable (
    (∀ identity ∈ before.identities, identity ∈ result.identities) ∧
    (∀ identity ∈ additions.identities, identity ∈ result.identities) ∧
    (∀ identity ∈ result.identities, identity ∈ before.identities ∨ identity ∈ additions.identities)))

/-- Validate the actual native merge result and return evidence for its contents. -/
def checkMerge (before additions result : VKeyWitnessSet) :
    Except Error (PLift (MergeResult before additions result)) :=
  if preserved : MergeResult before additions result then .ok ⟨preserved⟩
  else .error (.invalidInput "Native witness merge changed the requested contents")

-- THEOREMS -------------------------------------------------------------------

/-- Every accepted collection has unique observed public keys. -/
theorem keys_unique (witnesses : VKeyWitnessSet) :
    (witnesses.witnesses.map VKeyWitness.verificationKey).Nodup := witnesses.unique

/-- A successful validator establishes preservation and absence of extra members.
This theorem concerns checked snapshots, not native merge or Ed25519 correctness.
-/
theorem checkMerge_sound (before additions result : VKeyWitnessSet)
    (success : (checkMerge before additions result).isOk = true) : MergeResult before additions result := by
  unfold checkMerge at success
  split at success <;> simp_all [Except.isOk, Except.toBool]

end VKeyWitnessSet
end Cometa
