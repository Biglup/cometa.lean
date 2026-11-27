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
import Tests.WitnessFixtures

/-! Native signature verification and witness merging using independent public
vectors. No private keys, wallet unlocks or live transactions are involved.
-/

namespace Tests.KeyWitnesses

open Cometa
open WitnessFixtures

-- HELPERS --------------------------------------------------------------------

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def require (result : Except Error α) : IO α := IO.ofExcept (result.mapError toString)

private def native (action : EIO Error α) : IO α := action.toIO (IO.userError ∘ toString)

private def hex (text : String) : IO ByteArray := require (Hex.toBytes text)

private def witness (text : String) : IO VKeyWitness := do
  native (VKeyWitness.ofCbor (← hex text))

private def reject (action : EIO Error α) (label : String) : IO Unit := do
  match ← action.toIO' with
  | .error _ => pure ()
  | .ok _ => throw (IO.userError ("Invalid key-witness input accepted: " ++ label))

private def baseTransaction : IO Transaction :=
  native (Transaction.ofHex ("84" ++ TransactionFixtures.body ++ "a0f5f6"))

-- NATIVE WITNESSES -----------------------------------------------------------

private def testWitnesses : IO Unit := do
  let first ← witness first
  let transaction ← baseTransaction
  check (first.keyHash.toHex == keyHash) "independent native public-key hash"
  check (← native (first.verifyTransaction transaction.id)) "independent body signature"
  check (!(← native (first.verify ByteArray.empty))) "wrong message accepted"
  let empty ← witness emptyMessageWitness
  check (← native (empty.verify ByteArray.empty)) "published empty-message Ed25519 vector"
  check (!(← native (empty.verify ⟨#[0]⟩))) "changed message accepted"
  let recreated ← native (VKeyWitness.create first.verificationKey first.signature)
  check (recreated.toCbor == first.toCbor && recreated == first) "native witness constructors"

  let noncanonical ← hex ("9f5820" ++ Hex.ofBytes first.verificationKey ++ "5840" ++ Hex.ofBytes first.signature ++ "ff")
  let imported ← native (VKeyWitness.ofCbor noncanonical)
  check (imported.toCbor == noncanonical && imported == first) "encoding-independent witness identity"
  for (key, signature) in [
      (ByteArray.empty, first.signature), (first.verificationKey.extract 0 31, first.signature),
      (first.verificationKey ++ ⟨#[0]⟩, first.signature),
      (first.verificationKey, first.signature.extract 0 63),
      (first.verificationKey, first.signature ++ ⟨#[0]⟩)] do
    reject (VKeyWitness.create key signature) "key/signature length"
  let invalid ← native (VKeyWitness.create first.verificationKey ⟨Array.replicate 64 0⟩)
  check (!(← native (invalid.verifyTransaction transaction.id))) "invalid signature accepted"

  for size in [:first.toCbor.size] do
    reject (VKeyWitness.ofCbor (first.toCbor.extract 0 size)) "truncated witness"
  reject (VKeyWitness.ofCbor (first.toCbor ++ ⟨#[0]⟩)) "trailing witness bytes"

-- COLLECTIONS AND CHECKED MERGES ---------------------------------------------

private def testSets : IO Unit := do
  let first ← witness first
  let second ← witness second
  let collection ← native (VKeyWitnessSet.ofList [first, second])
  check (Hex.ofBytes collection.toCbor == "d9010282" ++ WitnessFixtures.first ++ WitnessFixtures.second)
    "independent tagged witness-set vector"
  check (collection.witnesses == [first, second] && collection.tagged) "native ordering and tagging"
  let untagged ← native (VKeyWitnessSet.ofList [first] false)
  check (Hex.ofBytes untagged.toCbor == "81" ++ WitnessFixtures.first && !untagged.tagged)
    "explicit untagged construction"
  let indefinite ← hex ("9f" ++ WitnessFixtures.first ++ "ff")
  check ((← native (VKeyWitnessSet.ofCbor indefinite)).toCbor == indefinite) "exact imported set bytes"
  reject (VKeyWitnessSet.ofList [first, first]) "duplicate requested key"
  reject (VKeyWitnessSet.ofCbor (← hex ("82" ++ WitnessFixtures.first ++ WitnessFixtures.first)))
    "duplicate imported key"
  let conflicting ← native (VKeyWitness.create first.verificationKey ⟨Array.replicate 64 0⟩)
  reject (VKeyWitnessSet.ofList [first, conflicting]) "conflicting requested key"
  let left ← native (VKeyWitnessSet.ofList [first])
  let right ← native (VKeyWitnessSet.ofList [second])
  let _ ← require (VKeyWitnessSet.checkMerge left right collection)
  reject (EIO.ofExcept (VKeyWitnessSet.checkMerge left right left)) "validator lost added witness"
  reject (EIO.ofExcept (VKeyWitnessSet.checkMerge left left collection)) "validator extra witness"
  reject (EIO.ofExcept (VKeyWitnessSet.checkMerge collection left left)) "validator lost original witness"
  let transaction ← baseTransaction
  check (← native (collection.verifyTransaction transaction.id)) "both native signature checks"
  let empty ← native (VKeyWitnessSet.ofList [])
  check (empty.witnesses.isEmpty && (← native (empty.verifyTransaction transaction.id))) "empty set semantics"

  for size in [:collection.toCbor.size] do
    reject (VKeyWitnessSet.ofCbor (collection.toCbor.extract 0 size)) "truncated witness set"
  reject (VKeyWitnessSet.ofCbor (collection.toCbor ++ ⟨#[0]⟩)) "trailing witness-set bytes"
  reject (VKeyWitnessSet.ofCbor (← hex ("d9010381" ++ WitnessFixtures.first))) "wrong set tag"

  -- The native child allocates before rejecting a malformed indefinite ending.
  -- Both standalone and nested wrappers must release it on that error path.
  let malformed := "9f5820" ++ Hex.ofBytes first.verificationKey ++ "5840" ++ Hex.ofBytes first.signature ++ "00ff"
  reject (VKeyWitness.ofCbor (← hex malformed)) "malformed child ending"
  reject (VKeyWitnessSet.ofCbor (← hex ("81" ++ malformed))) "malformed nested child ending"
  reject (Transaction.ofHex ("84" ++ TransactionFixtures.body ++ "a10081" ++ malformed ++ "f5f6"))
    "malformed transaction child ending"

private def testTransactions : IO Unit := do
  let transaction ← baseTransaction
  let first ← witness first
  let second ← witness second
  let left ← native (VKeyWitnessSet.ofList [first])
  let right ← native (VKeyWitnessSet.ofList [second])
  let empty ← native (VKeyWitnessSet.ofList [])
  check ((← native transaction.keyWitnesses).isNone) "absent key-witness field"
  check ((← native (transaction.addKeyWitnesses empty)).toCbor == transaction.toCbor) "empty addition is exact no-op"

  let signed ← native (transaction.addKeyWitnesses left)
  check (signed.id == transaction.id) "body ID unchanged"
  check ((← native signed.keyWitnesses).any fun value => value.witnesses == [first]) "first signature attached"
  check (Hex.ofBytes signed.toCbor == "84" ++ TransactionFixtures.body ++ "a100" ++ Hex.ofBytes left.toCbor ++ "f5f6")
    "independent full signed transaction encoding"
  let twice ← native (signed.addKeyWitnesses left)
  check (twice.toCbor == signed.toCbor) "identical signature is idempotent"
  let both ← native (signed.addKeyWitnesses right)
  check ((← native both.keyWitnesses).any fun value => value.witnesses == [first, second]) "both signatures retained"

  let untagged ← native (VKeyWitnessSet.ofList [first] false)
  let oldStyle ← native (transaction.addKeyWitnesses untagged)
  check ((← native oldStyle.keyWitnesses).any fun value => !value.tagged) "new set honors tagging request"
  let extended ← native (oldStyle.addKeyWitnesses right)
  check ((← native extended.keyWitnesses).any fun value => !value.tagged) "existing tag style retained"

  let bad ← native (VKeyWitness.create first.verificationKey ⟨Array.replicate 64 0⟩)
  let invalid ← native (VKeyWitnessSet.ofList [bad])
  reject (transaction.addKeyWitnesses invalid) "bad incoming signature"
  reject (signed.addKeyWitnesses invalid) "conflicting signature"
  let invalidTransaction ← native (Transaction.ofHex (
    "84" ++ TransactionFixtures.body ++ "a100" ++ Hex.ofBytes invalid.toCbor ++ "f5f6"))
  reject (invalidTransaction.addKeyWitnesses right) "bad existing signature"
  let duplicates ← native (Transaction.ofHex (
    "84" ++ TransactionFixtures.body ++ "a10082" ++ WitnessFixtures.first ++ WitnessFixtures.first ++ "f5f6"))
  reject duplicates.keyWitnesses "duplicate keys in imported transaction"

  let nonminimal ← native (Transaction.ofHex ("84" ++ TransactionFixtures.nonminimalBody ++ "a0f5f6"))
  reject (nonminimal.addKeyWitnesses left) "signature from normalized body"
  let exactWitness ← witness WitnessFixtures.nonminimal
  let exactSet ← native (VKeyWitnessSet.ofList [exactWitness])
  let exact ← native (nonminimal.addKeyWitnesses exactSet)
  check (Hex.ofBytes exact.toCbor == "84" ++ TransactionFixtures.nonminimalBody ++
    "a100" ++ Hex.ofBytes exactSet.toCbor ++ "f5f6") "exact nonminimal body retained"

  for (frame, ending) in [("83", "f6"), ("84", "f6f4")] do
    let framed ← native (Transaction.ofHex (frame ++ TransactionFixtures.body ++ "a0" ++ ending))
    let merged ← native (framed.addKeyWitnesses left)
    check (merged.id == framed.id && merged.scriptValidity == framed.scriptValidity)
      "historical/block frame identity and declared validity"

  let emptyField ← native (Transaction.ofHex ("84" ++ TransactionFixtures.body ++ "a10080f5f6"))
  check ((← native emptyField.keyWitnesses).any fun value => value.witnesses.isEmpty && !value.tagged)
    "present empty collection differs from absence"
  for _ in [:100] do
    let merged ← native (signed.addKeyWitnesses right)
    check ((← native merged.keyWitnesses).any fun value => value.witnesses.length == 2) "repeated native merge"
    reject (transaction.addKeyWitnesses invalid) "repeated signature error"

-- PRESERVATION OF ALL OTHER WITNESS FIELDS ------------------------------------

private def testOtherFields : IO Unit := do
  let auxiliary := WitnessFixtures.auxiliary
  let body := WitnessFixtures.committedBody
  let bootstrap := "845820" ++ firstKey ++ "5840" ++ String.ofList (List.replicate 128 '0') ++
    "5820" ++ String.ofList (List.replicate 64 '0') ++ "41a0"
  let fields := "01d9010281820400" ++ "02d9010281" ++ bootstrap ++
    "03d9010281420102" ++ "04d90102811801" ++ "05a18200008201820000" ++
    "06d9010281420304" ++ "07d9010281420506" ++ "08d9010281420708"
  let transaction ← native (Transaction.ofHex ("84" ++ body ++ "a8" ++ fields ++ "f4" ++ auxiliary))
  let incoming ← native (VKeyWitnessSet.ofList [← witness committedWitness])
  let merged ← native (transaction.addKeyWitnesses incoming)
  check (Hex.ofBytes merged.toCbor == "84" ++ body ++ "a9" ++ fields ++
    "00" ++ Hex.ofBytes incoming.toCbor ++ "f4" ++ auxiliary)
    "body, auxiliary data, bootstrap, all scripts, nonminimal datum, redeemer and validity preserved"
  check ((← native merged.auxiliaryData).any fun value => Hex.ofBytes value.toCbor == auxiliary)
    "auxiliary getter after witness merging"

/-- Run concrete native key codecs, verification and transaction merge tests. -/
def run : IO Unit := do
  testWitnesses
  testSets
  testTransactions
  testOtherFields

end Tests.KeyWitnesses
