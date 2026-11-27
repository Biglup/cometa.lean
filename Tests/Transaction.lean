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

/-! Transaction ABI, representation, and malformed-input regressions. -/

namespace Tests.Transaction

open Cometa TransactionFixtures

-- HELPERS --------------------------------------------------------------------

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def require (result : Except Error α) : IO α :=
  IO.ofExcept (result.mapError toString)

private def failed : Except Error α → Bool
  | .error _ => true
  | .ok _ => false

private def parse (text : String) : IO Cometa.Transaction :=
  (Cometa.Transaction.ofHex text).toIO (IO.userError ∘ toString)

private def expectFailure (text : String) : IO Unit := do
  match ← (Cometa.Transaction.ofHex text).toIO' with
  | .error _ => pure ()
  | .ok _ => throw (IO.userError "Malformed transaction was accepted")

-- TESTS ----------------------------------------------------------------------

private def testHex : IO Unit := do
  let allBytes : ByteArray := ⟨(List.range 256).toArray.map Nat.toUInt8⟩
  check ((← require (Hex.toBytes (Hex.ofBytes allBytes))) == allBytes) "hex byte range"
  check ((← require (Hex.toBytes "aAfF00")) == ⟨#[170, 255, 0]⟩) "mixed-case hex"
  check ((← require (Hex.toBytes "")).isEmpty) "empty hex"
  for text in ["0", "000", "0g", " 00", "00\n", "0x00", "ＡＡ", "💫"] do
    check (Hex.toBytes text |> failed) "invalid hex accepted"
  check (Hex.toBytes ("00" ++ String.singleton (Char.ofNat 0)) |> failed) "NUL accepted"

private def testIdentifiers : IO Unit := do
  let identifier ← require (TransactionId.ofHex bodyId)
  check (identifier.toHex == bodyId && identifier.toBytes.size == 32) "identifier round trip"
  check ((← require (TransactionId.ofHex bodyId.toUpper)) == identifier) "identifier case"
  for size in [0, 1, 31, 33, 64] do
    check (TransactionId.ofBytes ⟨Array.replicate size 0⟩ |> failed) "ID length accepted"
  let reference : OutputReference := ⟨identifier, 18446744073709551615⟩
  check (toString reference == bodyId ++ "#18446744073709551615") "reference index"

private def testFrames : IO Unit := do
  for (start, ending, validity) in [
      ("83", "a0f6", true), ("84", "a0f5f6", true), ("84", "a0f4f6", false),
      ("84", "a0f6f4", false), ("9f", "a0f5f6ff", true),
      ("9f", "a0f6ff", true), ("9f", "a0f6f4ff", false)] do
    let encoded := start ++ body ++ ending
    let transaction ← parse encoded
    check (transaction.toHex == encoded) "outer framing changed"
    check (transaction.id.toHex == bodyId) "body hash differs from independent vector"
    check (transaction.scriptValidity == validity) "script validity flag"
    check (transaction.fee.value == 170000) "fee"
    check (transaction.inputs.size == 1 && transaction.outputs.size == 1) "input/output count"
    let some input := transaction.inputs[0]? | throw (IO.userError "missing input")
    check (input.transactionId.toHex == String.ofList (List.replicate 64 '0')) "input hash"
    check (input.index == 0) "input index"
    let some output := transaction.outputs[0]? | throw (IO.userError "missing output")
    check (Hex.ofBytes output.address.toBytes == addressHex) "output address"
    check (output.lovelace.value == 2000000) "output lovelace"
    let roundTrip ← (Cometa.Transaction.ofCbor transaction.toCbor).toIO (IO.userError ∘ toString)
    check (roundTrip == transaction) "CBOR round trip"

private def testPreservation : IO Unit := do
  let transaction ← parse ("84" ++ nonminimalBody ++ "a0f5f6")
  check (transaction.id.toHex == nonminimalId && transaction.id.toHex != bodyId)
    "nonminimal body was reserialized before hashing"
  check (transaction.toHex == "84" ++ nonminimalBody ++ "a0f5f6") "nonminimal CBOR changed"

  let rich ← parse ("84" ++ richBody ++ "a0f5f6")
  check (rich.id.toHex == richId) "rich body hash"
  let some output := rich.outputs[0]? | throw (IO.userError "missing rich output")
  check (Hex.ofBytes output.toCbor == richOutput) "assets, inline datum, or script lost"

private def testBoundsAndCollections : IO Unit := do
  let zeroHash := String.ofList (List.replicate 64 '0')
  let input := "825820" ++ zeroHash
  let address := "00581d" ++ addressHex
  let maximum := "1bffffffffffffffff"
  let largeOutput := "a2" ++ address ++ "01" ++ maximum
  let largeBody := "a30081" ++ input ++ maximum ++ "0181" ++ largeOutput ++ "02" ++ maximum
  let large ← parse ("84" ++ largeBody ++ "a0f5f6")
  check (large.fee.value == 18446744073709551615) "fee truncated"
  let some reference := large.inputs[0]? | throw (IO.userError "missing large input")
  let some output := large.outputs[0]? | throw (IO.userError "missing large output")
  check (reference.index.toNat == 18446744073709551615) "input index truncated"
  check (output.lovelace.value == 18446744073709551615) "unsigned output coin truncated"
  check (Hex.ofBytes output.toCbor == largeOutput) "unsigned output coin re-encoding"

  let ordinaryOutput := "a2" ++ address ++ "0101"
  let spending := "83" ++ input ++ "01" ++ input ++ "00" ++ input ++ "00"
  let collateral := "81" ++ input ++ "02"
  let references := "81" ++ input ++ "03"
  let collectionBody := "a600" ++ spending ++ "0182" ++ largeOutput ++ ordinaryOutput ++
    "02000d" ++ collateral ++ "10" ++ ordinaryOutput ++ "12" ++ references
  let collections ← parse ("84" ++ collectionBody ++ "a0f5f6")
  check (collections.inputs.map (·.index) == #[0, 0, 1]) "input order, duplicates, or scope"
  check (collections.outputs.map (·.lovelace.value) == #[18446744073709551615, 1])
    "output order or collateral-return exclusion"

  let empty ← parse "84a3008001800200a0f5f6"
  check (empty.inputs.isEmpty && empty.outputs.isEmpty && empty.fee.value == 0)
    "empty collections are structural data, not a ledger-validity assertion"

private def testRejected : IO Unit := do
  for text in ["", "00", "80", "84", "84a0a0f5f6", "84" ++ body,
      "84" ++ body ++ "a0f5", "84" ++ body ++ "a0f5f600",
      "84" ++ body ++ "a0f5f684" ++ body ++ "a0f5f6"] do
    expectFailure text
  match ← (Cometa.Transaction.ofHex "00").toIO' with
  | .error (.native operation code) =>
    check (operation == "Transaction.ofCbor" && code != 0) "native error context lost"
  | _ => throw (IO.userError "Expected a structured native decoding failure")

  let encoded ← require (Hex.toBytes ("84" ++ body ++ "a0f5f6"))
  for size in [:encoded.size] do
    match ← (Cometa.Transaction.ofCbor (encoded.extract 0 size)).toIO' with
    | .error _ => pure ()
    | .ok _ => throw (IO.userError "Truncated transaction accepted")

private def testOwnership : IO Unit := do
  for _ in [:200] do
    let transaction ← parse ("84" ++ richBody ++ "a0f5f6")
    check (transaction.id.toHex == richId) "repeated parse changed hash"
    expectFailure ("84" ++ body ++ "a0f5f600")
    expectFailure ("84" ++ body ++ "a0")

/-- Run offline transaction and identifier regressions, including ownership loops. -/
def run : IO Unit := do
  testHex
  testIdentifiers
  testFrames
  testPreservation
  testBoundsAndCollections
  testRejected
  testOwnership

end Tests.Transaction
