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

/-! Assemble an unsigned reward-withdrawal transaction from one supplied UTxO.
The reward amount, fee and validity slot are explicit. This offline example does
not query rewards, calculate minimum fees, create witnesses, evaluate scripts or
submit. A real transaction needs current chain data and authorization for both
the spending input and reward account (including redeemers for Plutus accounts).
-/

open Cometa

-- APPLICATION STEPS ---------------------------------------------------------

/-- Parse a nonnegative coin amount, retaining the native UInt64 bound. -/
private def amount (text : String) : Except Error Lovelace := do
  let some value := text.toNat? | throw (.invalidInput "Expected a decimal lovelace amount")
  Lovelace.ofNat value

/-- Return the input value and withdrawn rewards to the input's payment address,
less an explicit fee. Native assets remain in that output.
-/
private def assemble (utxoHex accountText rewardsText feeText expiryText : String) :
    EIO Error Transaction := do
  let utxo ← UTxO.ofCbor (← EIO.ofExcept (Hex.toBytes utxoHex))
  let account ← RewardAccount.ofString accountText
  let rewards ← EIO.ofExcept (amount rewardsText)
  let fee ← EIO.ofExcept (amount feeText)
  let some expiry := expiryText.toNat? | throw (.invalidInput "Expected a decimal validity slot")
  if expiry > 18446744073709551615 then throw (.invalidInput "Validity slot exceeds UInt64")

  let available := utxo.output.value.val + Value.lovelace rewards.value
  let returned := available.difference (Value.lovelace fee.value)
  let output ← Output.create utxo.output.address returned
  let inputs ← InputSet.ofList [utxo.reference]
  let withdrawals ← Withdrawals.ofList [⟨account, rewards⟩]

  let body ← TransactionBody.create {
    inputs, outputs := #[output], fee, withdrawals := some withdrawals
    invalidAfter := some expiry.toUInt64
    network := some account.network }
  Transaction.ofBody body

-- ENTRY POINT ---------------------------------------------------------------

/-- Read the supplied fixture and report file/domain/native errors once. -/
def main (args : List String) : IO UInt32 := do
  let [utxoFile, account, rewards, fee, expiry] := args
    | IO.eprintln "Usage: withdrawRewards UTXO_HEX_FILE REWARD_ACCOUNT LOVELACE FEE VALID_UNTIL"; return 1

  try
    let source ← IO.FS.readFile utxoFile
    let action := assemble source.trimAscii.toString account rewards fee expiry
    let transaction ← action.toIO (IO.userError ∘ toString)

    IO.println s!"Transaction ID: {transaction.id}"
    IO.println s!"Explicit fee: {transaction.fee.value} lovelace"
    IO.println s!"Unsigned transaction CBOR: {transaction.toHex}"
    return 0
  catch error =>
    IO.eprintln s!"{error}"
    return 1
