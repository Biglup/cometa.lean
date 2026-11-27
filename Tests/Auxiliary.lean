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

/-! Native metadata/auxiliary construction, exact identity and commitment checks.
Literal CBOR and Python hashlib vectors are independent of the native writer.
-/

namespace Tests.Auxiliary

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
  | .ok _ => throw (IO.userError ("Invalid metadata/auxiliary input accepted: " ++ label))

private def metadata : IO Metadata := native (Metadata.ofList [(674, .text "hi")])

-- METADATA VALUES ------------------------------------------------------------

private def testValues : IO Unit := do
  let values : List (Metadatum × String) := [
    (.integer 0, "00"), (.integer (-1), "20"),
    (.integer 18446744073709551615, "1bffffffffffffffff"),
    (.integer (-18446744073709551616), "3bffffffffffffffff"),
    (.bytes ⟨#[0, 255]⟩, "4200ff"), (.bytes ByteArray.empty, "40"),
    (.text "", "60"), (.text "台", "63e58fb0"),
    (.text ("a" ++ String.singleton (Char.ofNat 0) ++ "b"), "63610062"),
    (.list [.integer 1, .text "x"], "82016178"),
    (.map [(.text "a", .integer 1), (.text "a", .integer 2)], "a2616101616102"),
    (.map [(.list [.integer 1], .map [])], "a18101a0")]
  for (value, expected) in values do
    let encoded ← native value.toCbor
    check (Hex.ofBytes encoded == expected) "independent metadata value vector"
    let decoded ← native (Metadatum.ofCbor encoded)
    check ((← native decoded.toCbor) == encoded) "complete metadata getter snapshot"
    for size in [:encoded.size] do
      reject (Metadatum.ofCbor (encoded.extract 0 size)) "truncated metadata value"
    reject (Metadatum.ofCbor (encoded ++ ⟨#[0]⟩)) "trailing metadata value"

  let _ ← native (Metadatum.bytes ⟨Array.replicate 64 255⟩).toCbor
  let _ ← native (Metadatum.text (String.ofList (List.replicate 64 'a'))).toCbor
  let _ ← native (Metadatum.text (String.ofList (List.replicate 32 'é'))).toCbor
  for value in [Metadatum.integer 18446744073709551616, .integer (-18446744073709551617),
      .bytes ⟨Array.replicate 65 0⟩, .text (String.ofList (List.replicate 65 'a')),
      .text (String.ofList (List.replicate 22 '台')),
      .list [.map [(.integer 0, .bytes ⟨Array.replicate 65 0⟩)]]] do
    reject value.toCbor "out-of-bounds construction"
  for encoded in ["f6", "f5", "61ff", "c249010000000000000000", "c349010000000000000000",
      "5841" ++ String.ofList (List.replicate 130 '0'),
      "7841" ++ String.ofList (List.replicate 130 '0')] do
    reject (Metadatum.ofCbor (← hex encoded)) "invalid imported value"

private def testLabels : IO Unit := do
  let labeled ← native (Metadata.ofList [(18446744073709551615, .integer 2), (0, .integer 1)])
  check (Hex.ofBytes labeled.toCbor == "a200011bffffffffffffffff02") "label ordering and UInt64 bound"
  check (labeled.entries.map Prod.fst == [0, 18446744073709551615]) "indexed label getters"
  reject (Metadata.ofList [(0, .integer 1), (0, .integer 2)]) "duplicate requested label"
  reject (Metadata.ofCbor (← hex "a200010002")) "duplicate imported label"
  reject (Metadata.ofCbor (← hex "a12000")) "negative label"
  let exact ← hex "bf18001801ff"
  let imported ← native (Metadata.ofCbor exact)
  check (imported.toCbor == exact) "nonminimal indefinite metadata preserved"
  let empty ← native (Metadata.ofList [])
  check (Hex.ofBytes empty.toCbor == "a0") "empty metadata"
  for size in [:labeled.toCbor.size] do
    reject (Metadata.ofCbor (labeled.toCbor.extract 0 size)) "truncated label map"
  reject (Metadata.ofCbor (labeled.toCbor ++ ⟨#[0]⟩)) "trailing label map"

-- AUXILIARY DATA AND TRANSACTIONS --------------------------------------------

private def testAuxiliary : IO Unit := do
  let metadata ← metadata
  let config : AuxiliaryData.Config := {
    metadata := some metadata, nativeScripts := some [.invalidBefore 42]
    plutusV1 := some [← hex "0102"], plutusV2 := some [← hex "0304"]
    plutusV3 := some [← hex "0506"], plutusV4 := some [← hex "0708"] }
  let auxiliary ← native (AuxiliaryData.create config)
  let expected := "d90103a600a11902a262686901818204182a0281420102038142030404814205060581420708"
  check (Hex.ofBytes auxiliary.toCbor == expected) "all auxiliary fields independent vector"
  check (auxiliary.hash.toHex == "65caa5d457b59d2e847224c38723b181eaf756b57edca2b1afa5d982c6ff0828") "independent auxiliary digest"
  check (auxiliary.view.metadata.any fun value => value.toCbor == metadata.toCbor) "metadata getter"
  check (auxiliary.view.plutusV1 == config.plutusV1 && auxiliary.view.plutusV2 == config.plutusV2 &&
    auxiliary.view.plutusV3 == config.plutusV3 && auxiliary.view.plutusV4 == config.plutusV4) "all Plutus getters"
  let rebuilt ← native (AuxiliaryData.create auxiliary.view)
  check (rebuilt.toCbor == auxiliary.toCbor) "complete auxiliary reconstruction"

  let absent ← native (AuxiliaryData.create {})
  let empty ← native (Metadata.ofList [])
  let present ← native (AuxiliaryData.create {
    metadata := some empty, nativeScripts := some [], plutusV1 := some []
    plutusV2 := some [], plutusV3 := some [], plutusV4 := some [] })
  check (Hex.ofBytes absent.toCbor == "d90103a0") "absent auxiliary fields"
  check (Hex.ofBytes present.toCbor == "d90103a600a001800280038004800580") "all empty fields retained"
  check (absent.view.metadata.isNone && present.view.metadata.isSome && present.view.plutusV4 == some [])
    "absent versus empty getter snapshots"

  for malformed in ["d90102a0", "d90103a206800680", "d90103a200a000a0", "d90103a100a200010002",
      "d90103a1018182ff00", "d90103a1028100", "83a08080", "9fa080ff", "f6"] do
    reject (AuxiliaryData.ofCbor (← hex malformed)) ("malformed auxiliary fields/envelope: " ++ malformed)
  for size in [:auxiliary.toCbor.size] do
    reject (AuxiliaryData.ofCbor (auxiliary.toCbor.extract 0 size)) s!"auxiliary prefix {size}"
  reject (AuxiliaryData.ofCbor (auxiliary.toCbor ++ ⟨#[0]⟩)) "trailing auxiliary data"

  let singleton ← native (AuxiliaryData.ofCbor (← hex "81a0"))
  check (singleton.view.metadata.isSome && singleton.view.nativeScripts.isNone)
    "native singleton historical envelope acceptance"

  let inputs ← native (InputSet.ofList [])
  let fee ← require (Lovelace.ofNat 0)
  let base : TransactionBody.Config := { inputs, outputs := #[], fee }
  let uncommitted ← native (TransactionBody.create base)
  reject (Transaction.withAuxiliaryData uncommitted auxiliary) "missing body commitment"
  let committed ← native (TransactionBody.create { base with auxiliaryDataHash := some auxiliary.hash })
  reject (Transaction.withAuxiliaryData committed absent) "mismatched body commitment"
  let transaction ← native (Transaction.withAuxiliaryData committed auxiliary false)
  check (transaction.id == committed.id && !transaction.scriptValidity) "assembly body identity/validity"
  check ((← native transaction.auxiliaryData).any fun value => value.toCbor == auxiliary.toCbor)
    "transaction getter retains auxiliary cache"
  for framing in [⟨#[0x83]⟩ ++ committed.toCbor ++ ⟨#[0xa0]⟩ ++ auxiliary.toCbor,
      ⟨#[0x84]⟩ ++ committed.toCbor ++ ⟨#[0xa0]⟩ ++ auxiliary.toCbor ++ ⟨#[0xf4]⟩] do
    let imported ← native (Transaction.ofCbor framing)
    check ((← native imported.auxiliaryData).any fun value => value.toCbor == auxiliary.toCbor)
      "historical/block transaction auxiliary extraction"
  let unsigned ← native (Transaction.ofBody uncommitted)
  check ((← native unsigned.auxiliaryData).isNone) "absent transaction auxiliary payload"

  let original ← hex "a1001801"
  let imported ← native (AuxiliaryData.ofCbor original)
  check (imported.hash.toHex == "f5804a1364362ae18df145c0cda3abdd15af9ac8c71376bed2c1c6399e64d5cd") "exact historical/nonminimal auxiliary hash"
  let body ← native (TransactionBody.ofCbor (← hex ("a4008001800200075820" ++ imported.hash.toHex)))
  let assembled ← native (Transaction.withAuxiliaryData body imported)
  check (assembled.toCbor == ⟨#[0x84]⟩ ++ body.toCbor ++ ⟨#[0xa0, 0xf5]⟩ ++ original)
    "exact body and auxiliary bytes retained together"
  let original ← hex "82a100180180"
  let imported ← native (AuxiliaryData.ofCbor original)
  check (imported.hash.toHex == "32f6b62665d8d8d4d9c29e2d6a21e3181135912f4a4e6ea4a47e9874d0571110") "exact historical/nonminimal auxiliary hash"
  let body ← native (TransactionBody.ofCbor (← hex ("a4008001800200075820" ++ imported.hash.toHex)))
  let assembled ← native (Transaction.withAuxiliaryData body imported)
  check (assembled.toCbor == ⟨#[0x84]⟩ ++ body.toCbor ++ ⟨#[0xa0, 0xf5]⟩ ++ original)
    "exact body and auxiliary bytes retained together"
  let original ← hex "d90103a100a1001801"
  let imported ← native (AuxiliaryData.ofCbor original)
  check (imported.hash.toHex == "4d7a6fd7b2d1af58d4f3c386399aeea4cf5b17fad92887ccc40d45a3638319cb") "exact historical/nonminimal auxiliary hash"
  let body ← native (TransactionBody.ofCbor (← hex ("a4008001800200075820" ++ imported.hash.toHex)))
  let assembled ← native (Transaction.withAuxiliaryData body imported)
  check (assembled.toCbor == ⟨#[0x84]⟩ ++ body.toCbor ++ ⟨#[0xa0, 0xf5]⟩ ++ original)
    "exact body and auxiliary bytes retained together"
  let original ← hex "d90103bf00bf18001801ffff"
  let imported ← native (AuxiliaryData.ofCbor original)
  check (imported.hash.toHex == "f486d3ec3e7ccd90d5b33b5579784a70a86b0ababb4f0c629a4da388d0750321") "exact historical/nonminimal auxiliary hash"
  let body ← native (TransactionBody.ofCbor (← hex ("a4008001800200075820" ++ imported.hash.toHex)))
  let assembled ← native (Transaction.withAuxiliaryData body imported)
  check (assembled.toCbor == ⟨#[0x84]⟩ ++ body.toCbor ++ ⟨#[0xa0, 0xf5]⟩ ++ original)
    "exact body and auxiliary bytes retained together"

  for _ in [:100] do
    let copy ← native (AuxiliaryData.ofCbor auxiliary.toCbor)
    let assembled ← native (Transaction.withAuxiliaryData committed copy)
    let _ ← native assembled.auxiliaryData
    reject (AuxiliaryData.ofCbor (auxiliary.toCbor.extract 0 (auxiliary.toCbor.size - 1)))
      "repeated partial auxiliary error"

/-- Exercise every metadata form, auxiliary field and transaction attachment. -/
def run : IO Unit := do
  testValues
  testLabels
  testAuxiliary

end Tests.Auxiliary
