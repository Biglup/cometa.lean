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

/-! Read a transaction and externally supplied key-witness collection, verify their
signatures against the exact body hash, and merge through cardano-c. This program
does not unlock wallets, generate signatures, evaluate scripts or submit. Verified
key signatures alone do not establish that all ledger requirements are satisfied.
-/

open Cometa

-- APPLICATION STEPS ---------------------------------------------------------

/-- Parse both inputs and attach witnesses with the binding's verification and
preservation checks. Each external signer must sign the exact transaction ID.
-/
private def attach (transactionHex witnessesHex : String) : EIO Error Transaction := do
  let transaction ← Transaction.ofHex transactionHex
  let witnesses ← VKeyWitnessSet.ofCbor (← EIO.ofExcept (Hex.toBytes witnessesHex))
  transaction.addKeyWitnesses witnesses

-- ENTRY POINT ---------------------------------------------------------------

/-- Read public transaction/witness files and handle file/domain/native errors once. -/
def main (args : List String) : IO UInt32 := do
  let [transactionFile, witnessesFile] := args
    | IO.eprintln "Usage: attachKeyWitnesses TRANSACTION_HEX_FILE WITNESSES_HEX_FILE"; return 1

  try
    let transactionSource ← IO.FS.readFile transactionFile
    let witnessesSource ← IO.FS.readFile witnessesFile
    let action := attach transactionSource.trimAscii.toString witnessesSource.trimAscii.toString
    let transaction ← action.toIO (IO.userError ∘ toString)
    let witnesses ← transaction.keyWitnesses.toIO (IO.userError ∘ toString)
    let count := (witnesses.map fun value => value.witnesses.length).getD 0

    IO.println s!"Transaction ID: {transaction.id}"
    IO.println s!"Verified key witnesses: {count}"
    IO.println s!"Transaction CBOR: {transaction.toHex}"
    return 0
  catch error =>
    IO.eprintln s!"{error}"
    return 1
