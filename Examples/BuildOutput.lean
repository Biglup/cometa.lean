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

/-! Construct a multi-asset output with inline data and a native reference script.
This offline example does not mint assets, balance, sign, or submit a transaction.
All application steps and the error boundary are kept in this file.
-/

open Cometa

-- DEFINITIONS ----------------------------------------------------------------

/-- Parse asset identifiers and decimal amounts, retaining arbitrary precision
until the output constructor checks the final aggregate quantity bounds.
-/
private def parseValue (policyText nameText quantityText lovelaceText : String) :
    Except Error Value := do
  let policy ← PolicyId.ofHex policyText
  let name ← AssetName.ofHex nameText
  let some quantity := quantityText.toInt?
    | throw (.invalidInput "Asset quantity must be a decimal integer")
  let some lovelace := lovelaceText.toInt?
    | throw (.invalidInput "Lovelace must be a decimal integer")

  return Value.lovelace lovelace + Value.singleton (.native policy name) quantity

/-- Combine typed data and scripts with the recipient and checked asset bundle. -/
private def buildOutput (addressText policyText nameText quantityText lovelaceText : String) :
    EIO Error Output := do
  let address ← Address.ofString addressText
  let value ← EIO.ofExcept (parseValue policyText nameText quantityText lovelaceText)

  let datum ← EncodedPlutusData.ofData (.constr 0 [.integer 42])
  let reference ← Script.ofNative (.all [.invalidBefore 100, .invalidAfter 200])
  EIO.ofExcept (Output.create address value (.inline datum) (some reference))

/-- Check the native codec, then inspect the complete decoded output. -/
private def report (output : Output) : IO Unit := do
  let checked ← output.checkNativeEncoding.toIO (IO.userError ∘ toString)

  let imported ← (EncodedOutput.ofCbor checked.val).toIO (IO.userError ∘ toString)
  let decoded := imported.toOutput

  IO.println s!"Recipient: {decoded.address}"
  for (asset, quantity) in decoded.value.val.toList do
    IO.println s!"{asset}: {quantity}"
  match decoded.datum with
  | .none => IO.println "Datum: none"
  | .hash digest => IO.println s!"Datum hash: {digest.toHex}"
  | .inline data => IO.println s!"Inline datum: {Hex.ofBytes data.toCbor}"

  if let some script := decoded.referenceScript then
    IO.println s!"Reference script hash: {script.hash.toHex}"
  IO.println s!"Output CBOR: {Hex.ofBytes imported.toCbor}"

/-- Handle argument, construction, native-codec, and reporting errors once. -/
def main (args : List String) : IO UInt32 := do
  let [address, policy, name, quantity, lovelace] := args
    | IO.eprintln "Usage: buildOutput ADDRESS POLICY_ID ASSET_NAME_HEX QUANTITY LOVELACE"; return 1

  try
    let output ← (buildOutput address policy name quantity lovelace).toIO (IO.userError ∘ toString)
    report output
    return 0
  catch error =>
    IO.eprintln s!"{error}"
    return 1
