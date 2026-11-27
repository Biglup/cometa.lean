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

/-! Typed construction, proved bounds, and direct native codec conformance. -/

namespace Tests.Output

open Cometa

-- HELPERS --------------------------------------------------------------------

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def require (result : Except Error α) : IO α :=
  IO.ofExcept (result.mapError toString)

private def native (action : EIO Error α) : IO α := action.toIO (IO.userError ∘ toString)

private def failed : Except Error α → Bool
  | .error _ => true
  | .ok _ => false

private def expectFailure (action : EIO Error α) : IO Unit := do
  match ← action.toIO' with
  | .error _ => pure ()
  | .ok _ => throw (IO.userError "Malformed native input accepted")

private def hex (text : String) : IO ByteArray := require (Hex.toBytes text)

private def policy : IO PolicyId := require (PolicyId.ofBytes ⟨Array.replicate 28 0x11⟩)

private def recipient : IO Address := native (Address.ofString
  "addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz")

-- TESTS ----------------------------------------------------------------------

private def testAssets : IO Unit := do
  for size in [0, 1, 27, 29] do
    check (failed (PolicyId.ofBytes ⟨Array.replicate size 0⟩)) "policy length"
  check ((← policy).bytes.size == 28) "valid policy"
  for size in [0, 1, 31, 32] do
    let name ← require (AssetName.ofBytes ⟨Array.replicate size 0xff⟩)
    check (name.bytes.size == size) "binary asset name"
  check (failed (AssetName.ofBytes ⟨Array.replicate 33 0⟩)) "long name accepted"
  check (failed (AssetName.ofString (String.ofList (List.replicate 17 'é')))) "UTF-8 byte bound"
  check (failed (AssetName.ofHex "0g")) "invalid name hex"

private def testValues : IO Unit := do
  let asset := AssetId.native (← policy) (← require (AssetName.ofString "abc"))
  let value := Value.ofList [(asset, 7), (.ada, 2), (asset, -3), (.ada, -2)]
  check (value.quantity asset == 4 && value.quantity .ada == 0) "duplicate aggregation"
  check (value.toList == [(asset, 4)]) "zero aggregate removal"
  check ((value + value.negate).isZero) "signed cancellation"
  check ((value.difference (Value.singleton asset 9)).quantity asset == -5) "signed subtraction"
  check ((value.scale 100000000000000000000).quantity asset == 400000000000000000000)
    "arbitrary-precision intermediate value"
  check (failed ((Value.lovelace (-1)).checkOutput)) "negative ada accepted"
  check (failed ((Value.lovelace 18446744073709551616).checkOutput)) "ada overflow"
  check (failed ((Value.singleton asset 9223372036854775808).checkOutput)) "asset overflow"
  check (failed ((Value.singleton asset (-1)).checkOutput)) "negative output asset"
  check (failed ((Value.lovelace 1).toMintCbor)) "ada mint accepted"
  check (failed ((Value.singleton asset (-9223372036854775809)).toMintCbor)) "mint underflow"
  let mint ← require ((Value.singleton asset (-9223372036854775808)).toMintCbor)
  check (Hex.ofBytes mint == "a1581c" ++ (← policy).toHex ++ "a1436162633b7fffffffffffffff")
    "signed mint boundary"
  let mintTransaction := "84a400800180020009" ++ Hex.ofBytes mint ++ "a0f5f6"
  let parsed ← native (Transaction.ofHex mintTransaction)
  check (parsed.toHex == mintTransaction) "native signed mint parsing"

  let z ← require (AssetName.ofString "z")
  let aa ← require (AssetName.ofString "aa")
  let ordered := Value.ofList [(.native (← policy) aa, 2), (.native (← policy) z, 1), (.ada, 0)]
  let orderedOutput ← require (Cometa.Output.create (← recipient) ordered)
  let _ ← native orderedOutput.checkNativeEncoding
  let encoded ← require ordered.toOutputCbor
  check (Hex.ofBytes encoded == "8200a1581c" ++ (← policy).toHex ++ "a2417a0142616102")
    "CBOR name ordering must be length-first, not lexical"

private def testData : IO Unit := do
  for (data, expected, digest) in OutputFixtures.datums do
    check (Hex.ofBytes data.toCbor == expected) "typed datum encoding"
    let encoded ← native (EncodedPlutusData.ofData data)
    check (encoded.hash.toHex == digest && encoded.toCbor == data.toCbor) "native datum hash"

  let chunked ← native (EncodedPlutusData.ofData (.bytes ⟨Array.replicate 65 0xab⟩))
  check (chunked.hash.toHex == OutputFixtures.chunkedHash) "64-byte datum chunking"
  let oversized : ByteArray := ⟨#[0x58, 0x41] ++ Array.replicate 65 0xab⟩
  expectFailure (EncodedPlutusData.ofCbor oversized)
  expectFailure (EncodedPlutusData.ofCbor (⟨#[0x81]⟩ ++ oversized))
  expectFailure (EncodedPlutusData.ofCbor (⟨#[0xc2]⟩ ++ oversized))
  let huge ← native (EncodedPlutusData.ofData (.integer (2 ^ 520)))
  let expectedHuge : ByteArray := ⟨#[0xc2, 0x5f, 0x58, 0x40, 1] ++
    Array.replicate 63 0 ++ #[0x42, 0, 0, 0xff]⟩
  check (huge.toCbor == expectedHuge) "large bignum magnitude or chunking"
  let negative ← native (EncodedPlutusData.ofData (.integer (-(2 ^ 520) - 1)))
  check (negative.toCbor == (⟨#[0xc3]⟩ ++ expectedHuge.extract 1 expectedHuge.size)) "negative bignum magnitude"

  let canonical ← native (EncodedPlutusData.ofCbor (← hex "17"))
  let nonminimal ← native (EncodedPlutusData.ofCbor (← hex "1817"))
  check (canonical.hash != nonminimal.hash && Hex.ofBytes nonminimal.toCbor == "1817")
    "imported datum identity must not be normalized"
  for text in ["", "ff", "f6", "0100", "d879", "5f4100", "a101"] do
    expectFailure (EncodedPlutusData.ofCbor (← hex text))

private def testScripts : IO Unit := do
  let keyHash ← require (Hash.ofBytes (size := 28) ⟨Array.replicate 28 0x22⟩)
  let signature ← native (Script.ofNative (.signature keyHash))
  check (signature.hash.toHex == OutputFixtures.nativeSignatureHash) "native script hash"
  let scripts : List NativeScript := [.all [], .any [], .atLeast 0 [],
    .invalidBefore 0, .invalidAfter 18446744073709551615,
    .all [.signature keyHash, .any [.invalidBefore 100, .invalidAfter 200]],
    .atLeast 2 [.signature keyHash, .all []], .atLeast 3 [], .atLeast 18446744073709551615 []]
  for script in scripts do
    let encoded ← native (Script.ofNative script)
    check (encoded.hash.bytes.size == 28) "native script form"

  for (version, digest) in OutputFixtures.plutusHashes do
    let encoded ← native (Script.ofPlutus version (← hex "deadbeef"))
    check (encoded.hash.toHex == digest) "Plutus language hash discriminator"
    expectFailure (Script.ofPlutus version ByteArray.empty)

private def testOutputs : IO Unit := do
  let address ← recipient
  let asset := AssetId.native (← policy) (← require (AssetName.ofString "abc"))
  let value := Value.lovelace 2000000 + Value.singleton asset 1
  let datum ← native (EncodedPlutusData.ofData (.integer 42))
  let keyHash ← require (Hash.ofBytes (size := 28) ⟨Array.replicate 28 0x22⟩)
  let script ← native (Script.ofNative (.signature keyHash))
  let output ← require (Cometa.Output.create address value (.inline datum) (some script))
  check (Hex.ofBytes output.toCbor == TransactionFixtures.richOutput) "complete output vector"
  let checked ← native output.checkNativeEncoding
  check (checked.val == output.toCbor) "native full-output round trip"
  check (failed output.toLegacyCbor) "legacy accepted inline datum/reference script"

  let hashOutput ← require (Cometa.Output.create address value (.hash datum.hash))
  let legacy ← require hashOutput.toLegacyCbor
  check ((← native ((Internal.outputRoundTrip legacy).adapt (.native "test.legacy"))) == hashOutput.toCbor) "legacy datum-hash output"
  let simple ← require (Cometa.Output.create address (Value.lovelace 18446744073709551615))
  check ((← native simple.toNativeCbor) == simple.toCbor) "unsigned maximum coin"
  let maximumAsset ← require (Cometa.Output.create address (Value.singleton asset 9223372036854775807))
  check ((← native maximumAsset.toNativeCbor) == maximumAsset.toCbor) "maximum asset quantity"
  let reward ← native (Address.ofString
    "stake_test1uqehkck0lajq8gr28t9uxnuvgcqrc6070x3k9r8048z8y5gssrtvn")
  check (failed (Cometa.Output.create reward value)) "reward destination accepted"

  for (version, _) in OutputFixtures.plutusHashes do
    let reference ← native (Script.ofPlutus version (← hex "deadbeef"))
    let withReference ← require (Cometa.Output.create address value .none (some reference))
    check ((← native withReference.toNativeCbor) == withReference.toCbor) "Plutus reference output"

  let transactionHex := "84a300800181" ++ Hex.ofBytes output.toCbor ++ "0200a0f5f6"
  let transaction ← native (Cometa.Transaction.ofHex transactionHex)
  let some summary := transaction.outputs[0]? | throw (IO.userError "missing output")
  check (summary.toCbor == output.toCbor) "constructed output survived transaction inspection"

  for size in [:output.toCbor.size] do
    expectFailure ((Internal.outputRoundTrip (output.toCbor.extract 0 size)).adapt (.native "test.output"))
  for text in ["", "80", "8205", "82004100", "82008204186400"] do
    expectFailure ((Internal.scriptHash (← hex text)).adapt (.native "test.script"))

  for _ in [:100] do
    check ((← native output.toNativeCbor) == output.toCbor) "repeated output codec"
    let _ ← native (EncodedPlutusData.ofData (.integer (-18446744073709551617)))
    let _ ← native (Script.ofNative (.signature keyHash))
    expectFailure ((Internal.outputRoundTrip (output.toCbor ++ ⟨#[0]⟩)).adapt (.native "test.output"))
    expectFailure (EncodedPlutusData.ofCbor (← hex "d879"))

/-- Run multi-asset, script, datum, and output construction conformance checks. -/
def run : IO Unit := do
  testAssets
  testValues
  testData
  testScripts
  testOutputs

end Tests.Output
