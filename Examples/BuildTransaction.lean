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

/-! Assemble an unsigned transaction from one supplied UTxO, with explicit fee
and upper validity slot. Change retains native assets. This offline example does
not establish UTxO freshness, minimum ada/fees, evaluate scripts, sign or submit.
-/

open Cometa

-- APPLICATION STEPS ---------------------------------------------------------

/-- Parse a nonnegative coin amount with the native representation bound. -/
private def amount (text : String) : Except Error Lovelace := do
  let some value := text.toNat? | throw (.invalidInput "Expected a decimal lovelace amount")
  Lovelace.ofNat value

/-- Decode the provided UTxO, create payment/change outputs, then call the native
body and transaction constructors. Balancing policy remains explicit here.
-/
private def assemble (utxoHex recipientText amountText feeText expiryText : String) :
    EIO Error Transaction := do
  let utxo ← UTxO.ofCbor (← EIO.ofExcept (Hex.toBytes utxoHex))
  let recipient ← Address.ofString recipientText
  let payment ← EIO.ofExcept (amount amountText)
  let fee ← EIO.ofExcept (amount feeText)
  let some expiry := expiryText.toNat? | throw (.invalidInput "Expected a decimal validity slot")
  if expiry > 18446744073709551615 then throw (.invalidInput "Validity slot exceeds UInt64")

  let paymentValue := Value.lovelace payment.value
  let change := utxo.output.value.val.difference (paymentValue + Value.lovelace fee.value)
  let _ ← EIO.ofExcept change.checkOutput
  let paymentOutput ← Output.create recipient paymentValue
  let mut outputs := #[paymentOutput]
  unless change.isZero do
    outputs := outputs.push (← Output.create utxo.output.address change)

  let inputs ← InputSet.ofList [utxo.reference]
  let body ← TransactionBody.create {
    inputs, outputs, fee
    invalidAfter := some expiry.toUInt64
    network := some .testnet }
  Transaction.ofBody body

-- ENTRY POINT ---------------------------------------------------------------

/-- Handle file, validation and native errors at one application boundary. -/
def main (args : List String) : IO UInt32 := do
  let [utxoFile, recipient, payment, fee, expiry] := args
    | IO.eprintln "Usage: buildTransaction UTXO_HEX_FILE RECIPIENT LOVELACE FEE VALID_UNTIL"; return 1

  try
    let source ← IO.FS.readFile utxoFile
    let action := assemble source.trimAscii.toString recipient payment fee expiry
    let transaction ← action.toIO (IO.userError ∘ toString)

    IO.println s!"Transaction ID: {transaction.id}"
    IO.println s!"Explicit fee: {transaction.fee.value} lovelace"
    IO.println s!"Outputs: {transaction.outputs.size}"
    IO.println s!"Unsigned transaction CBOR: {transaction.toHex}"
    return 0
  catch error =>
    IO.eprintln s!"{error}"
    return 1
