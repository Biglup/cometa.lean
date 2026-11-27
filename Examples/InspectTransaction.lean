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

/-! Inspect a CBOR-hex transaction file without accessing a wallet or network.
Run `lake exe inspectTransaction Examples/transaction.cbor.hex`.
-/

open Cometa

-- DEFINITIONS ----------------------------------------------------------------

/-- Read a hex file, allowing surrounding file whitespace, and parse one transaction. -/
private def readTransaction (path : System.FilePath) : IO Transaction := do
  let text ← IO.FS.readFile path
  (Transaction.ofHex text.trimAscii.toString).toIO (IO.userError ∘ toString)

/-- Report declared fields; parsing does not verify signatures or ledger validity. -/
private def report (transaction : Transaction) : IO Unit := do
  IO.println s!"Transaction ID: {transaction.id}"
  IO.println s!"Fee: {transaction.fee} lovelace"
  IO.println s!"Declared script validity: {transaction.scriptValidity}"

  IO.println s!"Spending inputs: {transaction.inputs.size}"
  for input in transaction.inputs do
    IO.println s!"  {input}"

  IO.println s!"Ordinary outputs: {transaction.outputs.size}"
  for (output, index) in transaction.outputs.toList.zipIdx do
    IO.println s!"  #{index}: {output.address}"
    IO.println s!"    Lovelace component: {output.lovelace}"
  IO.println "Output summaries omit asset details. No validation or submission was performed."

/-- Keep file, parsing, and reporting errors at one application boundary. -/
def main (args : List String) : IO UInt32 := do
  let [path] := args
    | IO.eprintln "Usage: inspectTransaction CBOR_HEX_FILE"; return 1

  try
    let transaction ← readTransaction path
    report transaction
    return 0
  catch error =>
    IO.eprintln s!"{error}"
    return 1
