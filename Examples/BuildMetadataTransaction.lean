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

/-! Attach labeled text metadata to an unsigned transaction built from a supplied
UTxO. Return its value, less an explicit fee, to its existing payment address.
The example does not calculate fees/minimum ada, query chain state, sign or submit.
-/

open Cometa

-- APPLICATION STEPS ---------------------------------------------------------

/-- Parse an unsigned 64-bit label or slot without truncating it. -/
private def unsigned (text : String) : Except Error UInt64 := do
  let some value := text.toNat? | throw (.invalidInput "Expected an unsigned decimal integer")
  if value > 18446744073709551615 then throw (.invalidInput "Integer exceeds UInt64")
  return value.toUInt64

/-- Construct metadata and its native hash before committing the hash to the body.
The assembly call checks that the supplied payload matches that commitment.
-/
private def assemble (utxoHex labelText message feeText expiryText : String) : EIO Error Transaction := do
  let utxo ← UTxO.ofCbor (← EIO.ofExcept (Hex.toBytes utxoHex))
  let label ← EIO.ofExcept (unsigned labelText)
  let expiry ← EIO.ofExcept (unsigned expiryText)
  let feeValue ← EIO.ofExcept (unsigned feeText)
  let fee ← EIO.ofExcept (Lovelace.ofNat feeValue.toNat)

  let metadata ← Metadata.ofList [(label, .text message)]
  let auxiliary ← AuxiliaryData.create { metadata := some metadata }

  let returned := utxo.output.value.val.difference (Value.lovelace fee.value)
  let output ← Output.create utxo.output.address returned
  let inputs ← InputSet.ofList [utxo.reference]
  let body ← TransactionBody.create {
    inputs, outputs := #[output], fee
    invalidAfter := some expiry
    auxiliaryDataHash := some auxiliary.hash }

  Transaction.withAuxiliaryData body auxiliary

-- ENTRY POINT ---------------------------------------------------------------

/-- Read one UTxO fixture and report file/domain/native errors at one boundary. -/
def main (args : List String) : IO UInt32 := do
  let [utxoFile, label, message, fee, expiry] := args
    | IO.eprintln "Usage: buildMetadataTransaction UTXO_HEX_FILE LABEL TEXT FEE VALID_UNTIL"; return 1

  try
    let source ← IO.FS.readFile utxoFile
    let action := assemble source.trimAscii.toString label message fee expiry
    let transaction ← action.toIO (IO.userError ∘ toString)

    IO.println s!"Transaction ID: {transaction.id}"
    IO.println s!"Explicit fee: {transaction.fee.value} lovelace"
    IO.println s!"Unsigned transaction CBOR: {transaction.toHex}"
    return 0
  catch error =>
    IO.eprintln s!"{error}"
    return 1
