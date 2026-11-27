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
import Tests.OutputFixtures
import Tests.TransactionFixtures

/-! Semantic decoding, exact encoding retention, and malformed-input boundaries. -/

namespace Tests.Decoding

open Cometa

-- HELPERS --------------------------------------------------------------------

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def require (result : Except Error α) : IO α :=
  IO.ofExcept (result.mapError toString)

private def native (action : EIO Error α) : IO α := action.toIO (IO.userError ∘ toString)

private def hex (text : String) : IO ByteArray := require (Hex.toBytes text)

private def reject (action : EIO Error α) (label : String := "") : IO Unit := do
  match ← action.toIO' with
  | .error _ => pure ()
  | .ok _ => throw (IO.userError ("Malformed component accepted: " ++ label))

-- TESTS ----------------------------------------------------------------------

private def testValues : IO Unit := do
  let policy ← require (PolicyId.ofBytes ⟨Array.replicate 28 0x11⟩)
  let name ← require (AssetName.ofString "a")
  let asset := AssetId.native policy name
  let otherPolicy ← require (PolicyId.ofBytes ⟨Array.replicate 28 0x33⟩)
  let otherAsset := AssetId.native otherPolicy name
  let value := Value.lovelace 18446744073709551615 + Value.singleton asset 17 +
    Value.singleton otherAsset 29
  let encoded ← native value.toOutputCbor
  let decoded ← native (Value.ofOutputCbor encoded)
  check (decoded.val.quantity .ada == value.quantity .ada && decoded.val.quantity asset == 17)
    "output value quantities"
  check (decoded.val.quantity otherAsset == 29) "multiple native policy snapshots"
  let mint := Value.singleton asset (-9223372036854775808) + Value.singleton otherAsset 31
  let restored ← native (Value.ofMintCbor (← native mint.toMintCbor))
  check (restored.quantity asset == -9223372036854775808 && restored.quantity otherAsset == 31)
    "signed mint quantities across policies"
  let policyHex := "581c" ++ policy.toHex
  let emptyDuplicate ← native (Value.ofOutputCbor
    (← hex ("8200a2" ++ policyHex ++ "a0" ++ policyHex ++ "a0")))
  check emptyDuplicate.val.isZero "native reader coalesces duplicate empty policy maps"
  for text in ["20", "8200a1" ++ policyHex ++ "a1416120",
      "8200a1" ++ policyHex ++ "a2416101416102",
      "8200a1" ++ policyHex ++ "a141611b8000000000000000"] do
    reject (Value.ofOutputCbor (← hex text)) text

private def testData : IO Unit := do
  for (data, encoded, _) in OutputFixtures.datums do
    let decoded ← native (PlutusData.ofCbor (← hex encoded))
    check ((← native decoded.toCbor) == (← native data.toCbor)) "datum semantic round trip"
  for text in ["1817", "9f1817ff", "bf01020103ff", "c249010000000000000000"] do
    let bytes ← hex text
    let encoded ← native (EncodedPlutusData.ofCbor bytes)
    check (encoded.toCbor == bytes) "exact datum bytes"
    let decoded ← native (PlutusData.ofCbor bytes)
    check ((← native encoded.toData.toCbor) == (← native decoded.toCbor)) "datum semantic view"
  for text in ["d80000", "d8668100", "d87900", "c201", "f6", "0100"] do
    reject (PlutusData.ofCbor (← hex text)) text

private def testScripts : IO Unit := do
  let hash ← require (Hash.ofBytes (size := 28) ⟨Array.replicate 28 0x22⟩)
  for credential in [Credential.key hash, Credential.script hash] do
    let restored ← native (Credential.ofCbor (← native credential.toCbor))
    check (restored == credential) "credential round trip"
    let tree := NativeScript.requireGuard credential
    let script ← native (Script.ofNative tree)
    let imported ← native (Script.ofCbor script.toCbor)
    check (script.hash == imported.hash) "guard hash round trip"
    let decoded ← native (NativeScript.ofCbor (← native tree.toCbor))
    check ((← native decoded.toCbor) == (← native tree.toCbor)) "guard semantic round trip"

  let canonical ← native (Script.ofNative (.signature hash))
  let indefinite ← native (Script.ofCbor (← hex ("9f008200581c" ++ hash.toHex ++ "ff")))
  check (indefinite.hash == canonical.hash) "outer envelope does not affect native hash"
  let nonminimalBytes ← hex ("8200821800581c" ++ hash.toHex)
  let nonminimal ← native (Script.ofCbor nonminimalBytes)
  check (nonminimal.hash.toHex == "84995578371b4788583e176d7bb6da60d4af6d77cb0956393653d259")
    "independent BLAKE2b-224 imported-payload vector"
  check (nonminimal.hash != canonical.hash && nonminimal.toCbor == nonminimalBytes)
    "native payload identity preserved"
  match nonminimal.view with
  | .native tree => check ((← native tree.toCbor) == (← native (NativeScript.signature hash).toCbor)) "native semantic view"
  | _ => throw (IO.userError "Wrong script view")

  for (version, _) in OutputFixtures.plutusHashes do
    let canonical ← native (Script.ofPlutus version (← hex "deadbeef"))
    let bytes := ⟨#[0x9f, version.tag.toUInt8]⟩ ++ (← hex "5f42dead42beefffff")
    let imported ← native (Script.ofCbor bytes)
    check (imported.hash == canonical.hash && imported.toCbor == bytes) "Plutus chunked import"
  for text in ["820540", "820140", "8200820700", "8200820600", "82018200", "8201410000"] do
    reject (Script.ofCbor (← hex text)) text

private def testOutputs : IO Unit := do
  let bytes ← hex TransactionFixtures.richOutput
  let encoded ← native (EncodedOutput.ofCbor bytes)
  let output := encoded.toOutput
  check (encoded.toCbor == bytes && output.toCbor == bytes) "rich output semantic round trip"
  check (output.value.val.quantity .ada == 2000000) "decoded output coin"
  match output.datum, output.referenceScript with
  | .inline data, some script =>
    check ((← native data.toData.toCbor) == (← native (PlutusData.integer 42).toCbor)) "inline datum decoded"
    check (script.hash.toHex == OutputFixtures.nativeSignatureHash) "reference script decoded"
  | _, _ => throw (IO.userError "Missing complete output fields")

  let simple ← native (Cometa.Output.create output.address (Value.lovelace 23))
  let address := ⟨#[0x58, output.address.toBytes.size.toUInt8]⟩ ++ output.address.toBytes
  let legacy := ⟨#[0x9f]⟩ ++ address ++ (← hex "1817ff")
  let imported ← native (EncodedOutput.ofCbor legacy)
  check (imported.toCbor == legacy && imported.toOutput.toCbor == simple.toCbor)
    "legacy exact bytes and normalized fields"
  let datumHash ← require (Hash.ofBytes (size := 32) ⟨Array.replicate 32 1⟩)
  let withHash ← native (Cometa.Output.create output.address (Value.lovelace 23) (.hash datumHash))
  let decoded ← native (Cometa.Output.ofCbor (← native withHash.toLegacyCbor))
  check (decoded.toCbor == withHash.toCbor) "legacy datum hash"
  let addressHex := Hex.ofBytes address
  for text in ["a0", "a100" ++ addressHex,
      "a300" ++ addressHex ++ "00170117", "a300" ++ addressHex ++ "01170400",
      "a300" ++ addressHex ++ "01170282004100",
      "a300" ++ addressHex ++ "0117034100", "83" ++ addressHex ++ "17f6"] do
    reject (EncodedOutput.ofCbor (← hex text)) text
  for size in [:bytes.size] do
    reject (EncodedOutput.ofCbor (bytes.extract 0 size))
  reject (EncodedOutput.ofCbor (bytes ++ ⟨#[0]⟩))
  for _ in [:100] do
    let imported ← native (EncodedOutput.ofCbor bytes)
    check (imported.toOutput.toCbor == bytes) "repeated complete output import"

private def testNativeBoundaries : IO Unit := do
  let key ← require (Hash.ofBytes (size := 28) ⟨Array.replicate 28 0x22⟩)
  let nativeTree := NativeScript.all [.signature key, .invalidBefore 42]
  let program ← native (Script.ofPlutus .v4 (← hex "deadbeef"))
  let cases : List (UInt8 × ByteArray) := [
    (0, ← native (Credential.key key).toCbor),
    (1, ← native (Value.lovelace 42).toOutputCbor),
    (2, ← native Value.zero.toMintCbor),
    (3, ← native (PlutusData.constr 128 [.integer (-1), .bytes ⟨#[0, 1]⟩]).toCbor),
    (4, ← native nativeTree.toCbor),
    (5, program.toCbor),
    (6, ← hex TransactionFixtures.richOutput)]
  for (family, bytes) in cases do
    for size in [:bytes.size] do
      reject ((Internal.componentDecode family (bytes.extract 0 size)).adapt (.native "test.prefix"))
        s!"family {family}, prefix {size}"
    reject ((Internal.componentDecode family (bytes ++ ⟨#[0]⟩)).adapt (.native "test.trailing"))
    for _ in [:100] do
      let _ ← native ((Internal.componentDecode family bytes).adapt (.native "test.snapshot"))

/-- Run semantic and exact-encoding decoding checks. -/
def run : IO Unit := do
  testValues
  testData
  testScripts
  testOutputs
  testNativeBoundaries

end Tests.Decoding
