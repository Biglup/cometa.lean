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
import Tests.TransactionFixtures

/-! Native input/UTxO construction, body setters/getters, exact body preservation,
and executable input-set validators. Synthetic fixtures require no network/wallet.
-/

namespace Tests.Assembly

open Cometa

-- HELPERS --------------------------------------------------------------------

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def require (result : Except Error α) : IO α := IO.ofExcept (result.mapError toString)

private def native (action : EIO Error α) : IO α := action.toIO (IO.userError ∘ toString)

private def hex (text : String) : IO ByteArray := require (Hex.toBytes text)

private def reject (action : EIO Error α) (label : String) : IO Unit := do
  match ← action.toIO' with
  | .error _ => pure ()
  | .ok _ => throw (IO.userError ("Malformed assembly input accepted: " ++ label))

private def reference (index : UInt64 := 0) : IO OutputReference := do
  return ⟨← require (TransactionId.ofBytes ⟨Array.replicate 32 0⟩), index⟩

private def coin (amount : Nat) : IO Lovelace := require (Lovelace.ofNat amount)

private def richOutput : IO Output := do
  native (Output.ofCbor (← hex TransactionFixtures.richOutput))

private def inputHex : String := "825820" ++ String.ofList (List.replicate 64 '0') ++ "00"

-- INPUTS AND UTXOS -----------------------------------------------------------

private def testInputs : IO Unit := do
  let first ← reference
  let second ← reference 1
  let inputBytes ← native first.toCbor
  check (Hex.ofBytes inputBytes == inputHex) "independent input vector"
  check ((← native (OutputReference.ofCbor inputBytes)) == first) "input getter snapshot"
  let maximum ← reference 18446744073709551615
  check ((← native (OutputReference.ofCbor (← native maximum.toCbor))) == maximum) "uint64 output index"

  let inputs ← native (InputSet.ofList [second, first])
  check (inputs.references == [first, second]) "native set ordering"
  reject (InputSet.ofList [first, first]) "duplicate construction"
  reject (InputSet.ofCbor (← hex ("82" ++ inputHex ++ inputHex)))
    "duplicate imported inputs"
  let left ← native (InputSet.ofList [first])
  let right ← native (InputSet.ofList [second])
  let _ ← require (left.checkDisjoint right)
  reject (EIO.ofExcept (left.checkDisjoint inputs)) "overlapping sets"

  let output ← richOutput
  let utxo ← native (UTxO.create first output)
  check (Hex.ofBytes utxo.toCbor == "82" ++ inputHex ++ TransactionFixtures.richOutput)
    "independent UTxO vector"
  check (utxo.reference == first && utxo.output.toCbor == output.toCbor) "complete native UTxO getters"

  for (family, bytes) in [(8, inputBytes), (9, inputs.toCbor), (10, utxo.toCbor)] do
    for size in [:bytes.size] do
      reject ((Internal.componentDecode family (bytes.extract 0 size)).adapt (.native "test.prefix"))
        s!"family {family}, prefix {size}"
    reject ((Internal.componentDecode family (bytes ++ ⟨#[0]⟩)).adapt (.native "test.trailing"))
      "trailing bytes"

-- BODIES AND ASSEMBLY --------------------------------------------------------

private def testBodyIdentity : IO Unit := do
  let inputs ← native (InputSet.ofCbor (← hex ("81" ++ inputHex)))
  let body ← native (TransactionBody.create { inputs, outputs := #[← richOutput], fee := ← coin 170000 })
  let expected := "a300d9010281" ++ inputHex ++ "0181" ++ TransactionFixtures.richOutput ++ "021a00029810"
  check (Hex.ofBytes body.toCbor == expected) "independent native body encoding"
  check (body.id.toHex == "1903ecedadec618506a79a72134abfff0913753986dec12b929e52896db03418")
    "independent native body hash"
  check (!body.hasAdditionalFields) "modeled body incorrectly marked incomplete"
  let _ ← require body.toConfig
  let transaction ← native (Transaction.ofBody body)
  check (transaction.toHex == "84" ++ expected ++ "a0f5f6")
    "native transaction frame and empty witnesses"
  check (transaction.id == body.id && transaction.fee.value == 170000) "assembled snapshot"
  let failedScripts ← native (Transaction.ofBody body false)
  check (!failedScripts.scriptValidity && failedScripts.id == body.id) "declared invalid flag"

  let original ← native (TransactionBody.ofCbor (← hex TransactionFixtures.nonminimalBody))
  let assembled ← native (Transaction.ofBody original)
  check (assembled.toHex == "84" ++ TransactionFixtures.nonminimalBody ++ "a0f5f6")
    "assembly must retain exact nonminimal body bytes"
  check (assembled.id.toHex == TransactionFixtures.nonminimalId) "nonminimal body ID"

  -- Certificates are not yet typed here. Native parsing/assembly must retain them.
  let duplicateOutput := "a300581d" ++ TransactionFixtures.addressHex ++
    "00581d" ++ TransactionFixtures.addressHex ++ "0100"
  reject (TransactionBody.ofCbor (← hex ("a300800181" ++ duplicateOutput ++ "0200")))
    "nested duplicate output keys"
  reject (UTxO.ofCbor (← hex ("82" ++ inputHex ++ duplicateOutput))) "UTxO duplicate output keys"

  let extraBytes ← hex "a40080018002000480"
  let extra ← native (TransactionBody.ofCbor extraBytes)
  check (extra.hasAdditionalFields && extra.toCbor == extraBytes) "unmodeled body fields preserved"
  reject (EIO.ofExcept extra.toConfig) "lossy reconstruction configuration"
  check ((← native (Transaction.ofBody extra)).toHex == "84a40080018002000480a0f5f6")
    "assembly retains unmodeled fields"

  for size in [:body.toCbor.size] do
    reject (TransactionBody.ofCbor (body.toCbor.extract 0 size)) s!"body prefix {size}"
  for text in ["", "a0", "a200800180", "a40080018002000200", "a3008001800220"] do
    reject (TransactionBody.ofCbor (← hex text)) text
  reject (TransactionBody.ofCbor (body.toCbor ++ ⟨#[0]⟩)) "body trailing bytes"

private def testBodyFields : IO Unit := do
  let spending ← native (InputSet.ofList [← reference])
  let collateral ← native (InputSet.ofList [← reference 1])
  let references ← native (InputSet.ofList [← reference 2])
  let empty ← native (InputSet.ofList [])
  let output ← richOutput
  let policy ← require (PolicyId.ofBytes ⟨Array.replicate 28 0x11⟩)
  let name ← require (AssetName.ofString "abc")
  let asset := AssetId.native policy name
  let key ← require (Hash.ofBytes (size := 28) ⟨Array.replicate 28 0x22⟩)
  let script ← require (Hash.ofBytes (size := 28) ⟨Array.replicate 28 0x33⟩)
  let auxHash ← require (Hash.ofBytes (size := 32) ⟨Array.replicate 32 0xaa⟩)
  let dataHash ← require (Hash.ofBytes (size := 32) ⟨Array.replicate 32 0xbb⟩)
  let config : TransactionBody.Config := {
    inputs := spending, outputs := #[output], fee := ← coin 170000
    invalidBefore := some 42, invalidAfter := some 1000
    auxiliaryDataHash := some auxHash, scriptDataHash := some dataHash
    mint := some (Value.singleton asset (-2))
    collateral := some collateral, referenceInputs := some references
    guards := some [.key key, .script script], network := some .testnet
    collateralReturn := some output, totalCollateral := some (← coin 3000000)
    treasuryValue := some (← coin 18446744073709551615), donation := some (← coin 1) }
  let body ← native (TransactionBody.create config)
  let view ← require body.toConfig
  check (view.invalidBefore == some 42 && view.invalidAfter == some 1000) "validity bounds"
  check (view.auxiliaryDataHash == some auxHash && view.scriptDataHash == some dataHash) "body commitments"
  let some mint := view.mint | throw (IO.userError "Missing native mint")
  check (mint.quantity asset == -2) "mint getter"
  check (view.collateral.map InputSet.toCbor == some collateral.toCbor &&
    view.referenceInputs.map InputSet.toCbor == some references.toCbor) "collateral/reference getters"
  check (view.guards == config.guards && view.network == some .testnet) "guard and network getters"
  check (view.collateralReturn.map Output.toCbor == some output.toCbor) "collateral return"
  check (view.totalCollateral.map Lovelace.value == some 3000000 &&
    view.treasuryValue.map Lovelace.value == some 18446744073709551615 &&
    view.donation.map Lovelace.value == some 1) "optional coin fields"
  let tx ← native (Transaction.ofBody body)
  check (tx.id == body.id) "combined body assembly"

  let basic : TransactionBody.Config := { inputs := empty, outputs := #[], fee := ← coin 0 }
  let absent ← native (TransactionBody.create basic)
  let present ← native (TransactionBody.create { basic with
    collateral := some empty, referenceInputs := some empty, mint := some Value.zero,
    invalidBefore := some 0, invalidAfter := some 18446744073709551615, network := some .mainnet })
  check (absent.toCbor != present.toCbor) "absent versus present empty body fields"
  check (present.view.mint.isSome && present.view.collateral.isSome &&
    present.view.referenceInputs.isSome && present.view.guards.isNone) "empty getter presence"
  check (present.view.invalidBefore == some 0 && present.view.invalidAfter == some 18446744073709551615 &&
    present.view.network == some .mainnet) "optional scalar boundaries"
  reject (TransactionBody.create { basic with guards := some [] }) "native empty-guard omission"
  let emptyGuards ← native (TransactionBody.ofCbor (← hex "a40080018002000e80"))
  check (emptyGuards.view.guards == some []) "import retains explicit empty guards"
  reject (EIO.ofExcept emptyGuards.toConfig) "empty-guard reconstruction would lose presence"
  check ((← native (Transaction.ofBody emptyGuards)).toHex == "84a40080018002000e80a0f5f6")
    "assembly preserves empty guards through native body cache"
  reject (TransactionBody.create { basic with guards := some [.key key, .key key] }) "duplicate guard"
  reject (TransactionBody.create { basic with mint := some (Value.lovelace 1) }) "ada mint"

  let signers ← native (TransactionBody.create { basic with guards := some [.key key] })
  check (signers.view.guards == some [.key key] && !signers.hasAdditionalFields) "required-signer compatibility"
  for _ in [:100] do
    let decoded ← native (TransactionBody.ofCbor body.toCbor)
    let assembled ← native (Transaction.ofBody decoded)
    check (assembled.id == body.id) "repeated native assembly"

/-- Run native input, resolved-output, body-field, and transaction assembly tests. -/
def run : IO Unit := do
  testInputs
  testBodyIdentity
  testBodyFields

end Tests.Assembly
