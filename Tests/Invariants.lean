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
