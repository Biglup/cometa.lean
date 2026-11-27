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

import Cometa
import Tests.WitnessFixtures

/-! Compile-time checks that ordinary construction cannot bypass validation. -/

open Cometa

-- CONSTRUCTION BOUNDARIES -----------------------------------------------------

/-- error: Unknown constant `Cometa.Address.mk` -/
#guard_msgs in
#check Address.mk

/-- error: invalid {...} notation, constructor for `Payment` is marked as private -/
#guard_msgs in
example (payment : Payment) (recipient : Address) : Payment :=
  { payment with recipient := recipient }

/-- error: Unknown constant `Cometa.Payment.mk` -/
#guard_msgs in
#check Payment.mk

/-- error: Unknown constant `Cometa.Transaction.mk` -/
#guard_msgs in
#check Transaction.mk

/-- error: Unknown constant `Cometa.Transaction.OutputSummary.mk` -/
#guard_msgs in
#check Transaction.OutputSummary.mk

/-- error: invalid {...} notation, constructor for `Transaction.OutputSummary` is marked as private -/
#guard_msgs in
example (output : Transaction.OutputSummary) (address : Address) : Transaction.OutputSummary :=
  { output with address := address }

/-- error: Unknown constant `Cometa.Output.mk` -/
#guard_msgs in
#check Output.mk

/-- error: Unknown constant `Cometa.Script.mk` -/
#guard_msgs in
#check Script.mk

/-- error: Unknown constant `Cometa.EncodedPlutusData.mk` -/
#guard_msgs in
#check EncodedPlutusData.mk

/-- error: invalid {...} notation, constructor for `Output` is marked as private -/
#guard_msgs in
example (output : Output) (address : Address) : Output := { output with address := address }

/-- error: Unknown constant `Cometa.EncodedOutput.mk` -/
#guard_msgs in
#check EncodedOutput.mk

/-- error: Unknown constant `Cometa.InputSet.mk` -/
#guard_msgs in
#check InputSet.mk

/-- error: Unknown constant `Cometa.TransactionBody.mk` -/
#guard_msgs in
#check TransactionBody.mk

/-- error: Unknown constant `Cometa.UTxO.mk` -/
#guard_msgs in
#check UTxO.mk

/-- error: Unknown constant `Cometa.RewardAccount.mk` -/
#guard_msgs in
#check RewardAccount.mk

/-- error: Unknown constant `Cometa.Withdrawals.mk` -/
#guard_msgs in
#check Withdrawals.mk

/-- error: invalid {...} notation, constructor for `RewardAccount` is marked as private -/
#guard_msgs in
example (account : RewardAccount) : RewardAccount := { account with network := .mainnet }

/-- error: invalid {...} notation, constructor for `Withdrawals` is marked as private -/
#guard_msgs in
example (withdrawals : Withdrawals) : Withdrawals := { withdrawals with entries := [] }

/-- error: Unknown constant `Cometa.Metadata.mk` -/
#guard_msgs in
#check Metadata.mk

/-- error: Unknown constant `Cometa.AuxiliaryData.mk` -/
#guard_msgs in
#check AuxiliaryData.mk

/-- error: invalid {...} notation, constructor for `Metadata` is marked as private -/
#guard_msgs in
example (metadata : Metadata) : Metadata := { metadata with entries := [] }

/-- error: invalid {...} notation, constructor for `AuxiliaryData` is marked as private -/
#guard_msgs in
example (data : AuxiliaryData) : AuxiliaryData := { data with view := {} }

/-- error: Unknown constant `Cometa.VKeyWitness.mk` -/
#guard_msgs in
#check VKeyWitness.mk

/-- error: Unknown constant `Cometa.VKeyWitnessSet.mk` -/
#guard_msgs in
#check VKeyWitnessSet.mk

/-- error: invalid {...} notation, constructor for `VKeyWitness` is marked as private -/
#guard_msgs in
example (witness : VKeyWitness) : VKeyWitness := { witness with signature := ByteArray.empty }

/-- error: invalid {...} notation, constructor for `VKeyWitnessSet` is marked as private -/
#guard_msgs in
example (witnesses : VKeyWitnessSet) : VKeyWitnessSet := { witnesses with witnesses := [] }

-- MODEL LAWS -----------------------------------------------------------------

example (left right : Plan) :
    (left ++ right).totalLovelace = left.totalLovelace + right.totalLovelace :=
  Plan.totalLovelace_append left right

example (identifier : TransactionId) : identifier.toBytes.size = 32 :=
  TransactionId.toBytes_size identifier

example (left right : Value) (asset : AssetId) :
    (left + right).quantity asset = left.quantity asset + right.quantity asset :=
  Value.quantity_add left right asset

example (value : Value) (checked : Value.CheckedOutput)
    (success : value.checkOutput = .ok checked) : value.ValidOutput :=
  Value.checkOutput_sound value checked success

example (output : Output) : output.value.val.ValidOutput := Output.value_valid output

example (output : Output) : output.address.isPayment = true := Output.address_isPayment output

example (output : Output) (checked : {bytes : ByteArray // bytes = output.toCbor}) :
    checked.val = output.toCbor := checked.property

example (inputs : InputSet) : inputs.references.Nodup := InputSet.references_unique inputs

example (left right : InputSet)
    (success : (left.checkDisjoint right).isOk = true) : InputSet.Disjoint left right :=
  InputSet.checkDisjoint_sound left right success

-- INTERPRETER ---------------------------------------------------------------

/-- info: "2.0.0-rc.7" -/
#guard_msgs in
#eval nativeVersion

/-- info: "36fdff68dfe3660f1ceea60f018a0fd7a83da13def229108794c397a879b0436" -/
#guard_msgs in
#eval (do
  let transaction ← Transaction.ofHex "84a3008001800200a0f5f6"
  return transaction.id.toHex : EIO Error String).toIO (IO.userError ∘ toString)

/-- info: true -/
#guard_msgs in
#eval (do
  let datum ← EncodedPlutusData.ofData (.integer 42)
  return datum.hash.bytes.size == 32 : EIO Error Bool).toIO (IO.userError ∘ toString)

/-- info: true -/
#guard_msgs in
#eval (do
  let inputs ← InputSet.ofList []
  let fee ← EIO.ofExcept (Lovelace.ofNat 0)
  let body ← TransactionBody.create { inputs, outputs := #[], fee }
  let transaction ← Transaction.ofBody body
  return transaction.id == body.id : EIO Error Bool).toIO (IO.userError ∘ toString)

example (withdrawals : Withdrawals) :
    (withdrawals.entries.map fun entry => entry.account.toBytes).Nodup :=
  Withdrawals.accounts_unique withdrawals

/-- info: true -/
#guard_msgs in
#eval (do
  let hash ← EIO.ofExcept (Hash.ofBytes ⟨Array.replicate 28 0⟩)
  let account ← RewardAccount.create .testnet (.script hash)
  let zero ← EIO.ofExcept (Lovelace.ofNat 0)
  let withdrawals ← Withdrawals.ofList [⟨account, zero⟩]
  return withdrawals.entries.length == 1 : EIO Error Bool).toIO (IO.userError ∘ toString)

example (metadata : Metadata) : (metadata.entries.map Prod.fst).Nodup :=
  Metadata.labels_unique metadata

example (data : AuxiliaryData) (expected : Option (Hash 32))
    (success : (data.checkCommitment expected).isOk = true) : expected = some data.hash :=
  AuxiliaryData.checkCommitment_sound data expected success

/-- info: true -/
#guard_msgs in
#eval (do
  let metadata ← Metadata.ofList [(674, .text "hello")]
  let auxiliary ← AuxiliaryData.create { metadata := some metadata }
  let inputs ← InputSet.ofList []
  let fee ← EIO.ofExcept (Lovelace.ofNat 0)
  let body ← TransactionBody.create {
    inputs, outputs := #[], fee, auxiliaryDataHash := some auxiliary.hash }
  let transaction ← Transaction.withAuxiliaryData body auxiliary
  return (← transaction.auxiliaryData).any (fun payload => payload.toCbor == auxiliary.toCbor)
    : EIO Error Bool).toIO (IO.userError ∘ toString)

example (witness : VKeyWitness) : witness.verificationKey.size = 32 :=
  VKeyWitness.verificationKey_size witness

example (witness : VKeyWitness) : witness.signature.size = 64 := VKeyWitness.signature_size witness

example (witnesses : VKeyWitnessSet) : (witnesses.witnesses.map VKeyWitness.verificationKey).Nodup :=
  VKeyWitnessSet.keys_unique witnesses

example (before additions result : VKeyWitnessSet)
    (success : (VKeyWitnessSet.checkMerge before additions result).isOk = true) :
    VKeyWitnessSet.MergeResult before additions result :=
  VKeyWitnessSet.checkMerge_sound before additions result success

/-- info: true -/
#guard_msgs in
#eval (do
  let bytes ← EIO.ofExcept (Hex.toBytes Tests.WitnessFixtures.emptyMessageWitness)
  let witness ← VKeyWitness.ofCbor bytes
  witness.verify ByteArray.empty : EIO Error Bool).toIO (IO.userError ∘ toString)
