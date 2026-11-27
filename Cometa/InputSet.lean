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

import Cometa.OutputReference

/-! Native input sets with checked uniqueness. Disjointness is an explicit caller
check; no era-specific rule for spending, reference, or collateral overlap is assumed.
-/

namespace Cometa

-- TYPES ----------------------------------------------------------------------

/-- Native input-set bytes and a duplicate-free snapshot in native order. -/
structure InputSet where
  private mk ::
  /-- Members copied from the native set getters. -/
  references : List OutputReference
  /-- Checked uniqueness of this observed native result. -/
  unique : references.Nodup
  private cbor : ByteArray

namespace InputSet

-- DEFINITIONS ----------------------------------------------------------------

private def checked (bytes : ByteArray) (fields : Internal.Component) : Except Error InputSet := do
  let .node _ _ _ _ _ children := fields
  let references ← children.mapM OutputReference.ofNative
  if unique : references.Nodup then return ⟨references, unique, bytes⟩
  else throw (.invalidInput "Duplicate input reference")

/-- Parse a native input set and check that its observed members are unique.
Both tagged and untagged native-supported encodings retain their input bytes.
-/
def ofCbor (bytes : ByteArray) : EIO Error InputSet := do
  let fields ← (Internal.componentDecode 9 bytes).adapt (.native "InputSet.ofCbor")
  EIO.ofExcept (checked bytes fields)

/-- Reject duplicate requested inputs before native set insertion could coalesce
them, then construct, encode and inspect the actual native set.
-/
def ofList (references : List OutputReference) : EIO Error InputSet := do
  unless references.Nodup do throw (.invalidInput "Duplicate input reference")
  let fields := Internal.Component.node 0 0 ByteArray.empty ByteArray.empty ""
    (references.map OutputReference.toNative)
  let bytes ← (Internal.componentEncode 9 fields).adapt (.native "InputSet.ofList")
  ofCbor bytes

/-- Exact validated native input-set encoding. -/
def toCbor (inputs : InputSet) : ByteArray := inputs.cbor

/-- No reference occurs in both observed sets. This is a model predicate, not a
claim that a transaction meets all input rules for its ledger era.
-/
def Disjoint (left right : InputSet) : Prop :=
  ∀ reference ∈ left.references, reference ∉ right.references

instance (left right : InputSet) : Decidable (Disjoint left right) :=
  List.decidableBAll (fun reference => reference ∉ right.references) left.references

/-- Execute a disjointness check and return evidence for the actual input snapshots. -/
def checkDisjoint (left right : InputSet) : Except Error (PLift (Disjoint left right)) :=
  if h : Disjoint left right then .ok ⟨h⟩
  else .error (.invalidInput "Input sets overlap")

-- THEOREMS -------------------------------------------------------------------

/-- Every successfully constructed or imported set has unique observed members. -/
theorem references_unique (inputs : InputSet) : inputs.references.Nodup := inputs.unique

/-- A successful disjointness result establishes the predicate for both snapshots. -/
theorem checkDisjoint_sound (left right : InputSet)
    (success : (checkDisjoint left right).isOk = true) : Disjoint left right := by
  unfold checkDisjoint at success
  split at success <;> simp_all [Except.isOk, Except.toBool]

end InputSet
end Cometa
