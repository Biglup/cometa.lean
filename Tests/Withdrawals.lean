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

/-! Native reward/withdrawal fixtures, validation boundaries and body integration.
Addresses use synthetic public hashes; expected CBOR is independent literal data.
-/

namespace Tests.Withdrawals

open Cometa

-- HELPERS --------------------------------------------------------------------

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def require (result : Except Error α) : IO α := IO.ofExcept (result.mapError toString)

private def native (action : EIO Error α) : IO α := action.toIO (IO.userError ∘ toString)

private def hex (text : String) : IO ByteArray := require (Hex.toBytes text)

private def coin (amount : Nat) : IO Lovelace := require (Lovelace.ofNat amount)

private def reject (action : EIO Error α) (label : String) : IO Unit := do
  match ← action.toIO' with
  | .error _ => pure ()
  | .ok _ => throw (IO.userError ("Invalid withdrawal input accepted: " ++ label))

private def hashHex : String := String.ofList (List.replicate 56 '1')

private def account (network : Network := .testnet) (script : Bool := false) : IO RewardAccount := do
  let hash ← require (Hash.ofHex hashHex)
  native (RewardAccount.create network (if script then .script hash else .key hash))

-- REWARD ACCOUNTS ------------------------------------------------------------

private def testAccounts : IO Unit := do
  for (network, script, header) in [(Network.testnet, false, "e0"), (.mainnet, false, "e1"),
      (.testnet, true, "f0"), (.mainnet, true, "f1")] do
    let reward ← account network script
    check (Hex.ofBytes reward.toBytes == header ++ hashHex) "independent reward bytes"
    check (reward.network == network) "reward network getter"
    let hash ← require (Hash.ofHex hashHex)
    check (decide (reward.credential = if script then .script hash else .key hash)) "credential getter"
    check (!(reward.toAddress.isPayment)) "reward became payment address"
    check ((← native (RewardAccount.ofString reward.toString)) == reward) "reward Bech32 round trip"
    reject (RewardAccount.ofString reward.toString.toUpper) "native parser rejects uppercase Bech32"
    check ((← native (RewardAccount.ofAddress reward.toAddress)) == reward) "address conversion"
    for size in [:reward.toBytes.size] do
      reject (RewardAccount.ofBytes (reward.toBytes.extract 0 size)) "truncated account"
    reject (RewardAccount.ofBytes (reward.toBytes ++ ⟨#[0]⟩)) "trailing account bytes"

  for header in ["00", "60", "70", "80", "90", "d0", "e2", "ff"] do
    reject (RewardAccount.ofBytes (← hex (header ++ hashHex))) "wrong address kind/network"
  for text in ["", "not an address", "stake_test1invalid",
      "addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz"] do
    reject (RewardAccount.ofString text) "invalid reward text"
  reject (RewardAccount.ofString "stake_test1uqg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygqhfl0dk")
    "Bech32 payload with trailing address bytes"
  let reward ← account
  reject (RewardAccount.ofString (reward.toString ++ String.singleton (Char.ofNat 0))) "NUL in text"

-- MAPS AND BODY INTEGRATION --------------------------------------------------

private def testMaps : IO Unit := do
  let key ← account
  let script ← account .testnet true
  let maximum ← coin 18446744073709551615
  let zero ← coin 0
  let withdrawals ← native (Withdrawals.ofList [⟨script, maximum⟩, ⟨key, zero⟩])
  let expected := "a2581de0" ++ hashHex ++ "00581df0" ++ hashHex ++ "1bffffffffffffffff"
  check (Hex.ofBytes withdrawals.toCbor == expected) "independent withdrawal map vector"
  check ((withdrawals.entries.map fun entry => entry.account) == [key, script]) "native ordering"
  check (withdrawals.totalLovelace == maximum.value) "zero and unsigned maximum retained"
  let both ← native (Withdrawals.ofList [⟨key, maximum⟩, ⟨script, maximum⟩])
  check (both.totalLovelace == 36893488147419103230) "unbounded observed total"
  reject (Withdrawals.ofList [⟨key, zero⟩, ⟨key, maximum⟩]) "duplicate requested account"
  reject (Withdrawals.ofCbor (← hex ("a2581de0" ++ hashHex ++ "00581de0" ++ hashHex ++ "01")))
    "duplicate imported account with different amounts"

  let preserved ← hex ("bf581de0" ++ hashHex ++ "1800ff")
  let imported ← native (Withdrawals.ofCbor preserved)
  check (imported.toCbor == preserved && imported.totalLovelace == 0) "nonminimal indefinite import"
  let empty ← native (Withdrawals.ofList [])
  check (Hex.ofBytes empty.toCbor == "a0" && empty.entries.isEmpty) "empty map"

  for size in [:withdrawals.toCbor.size] do
    reject (Withdrawals.ofCbor (withdrawals.toCbor.extract 0 size)) s!"map prefix {size}"
  reject (Withdrawals.ofCbor (withdrawals.toCbor ++ ⟨#[0]⟩)) "trailing map item"
  for malformed in ["80", "a1581de0" ++ hashHex ++ "20", "a1581de0" ++ hashHex ++ "f6",
      "a1581d60" ++ hashHex ++ "00", "a1581de2" ++ hashHex ++ "00",
      "a1581ee0" ++ hashHex ++ "0000", "a141e000"] do
    let bytes ← hex malformed
    reject (Withdrawals.ofCbor bytes) "malformed map/key/amount"
    reject (TransactionBody.ofCbor (← hex ("a400800180020005" ++ malformed))) "nested malformed map"

  let inputs ← native (InputSet.ofList [])
  let simple ← native (TransactionBody.create {
    inputs, outputs := #[], fee := zero, withdrawals := some withdrawals })
  check (Hex.ofBytes simple.toCbor == "a400d90102800180020005" ++ expected) "independent body vector"
  check (simple.id.toHex == "03c49f5de4ef10edc1f4e89732fd83b062260b9fd8eca00522f9d5a93df62732")
    "independent BLAKE2b-256 withdrawal body hash"
  let body ← native (TransactionBody.create {
    inputs, outputs := #[], fee := zero, withdrawals := some withdrawals
    invalidAfter := some 42, network := some .testnet, donation := some zero })
  let config ← require body.toConfig
  check (config.withdrawals.any fun value => value.toCbor == withdrawals.toCbor) "body getter"
  check (!body.hasAdditionalFields && config.invalidAfter == some 42) "modeled body fields"
  let rebuilt ← native (TransactionBody.create config)
  check (rebuilt.toCbor == body.toCbor) "complete config reconstruction"
  let transaction ← native (Transaction.ofBody body)
  check (transaction.id == body.id) "withdrawal transaction identity"

  let absent ← native (TransactionBody.create { inputs, outputs := #[], fee := zero })
  let present ← native (TransactionBody.create {
    inputs, outputs := #[], fee := zero, withdrawals := some empty })
  check (absent.view.withdrawals.isNone && present.view.withdrawals.isSome) "absent versus empty"
  check (Hex.ofBytes present.toCbor == "a400d90102800180020005a0") "empty field retained"

  let exactBody ← hex ("a400800180020005bf581de0" ++ hashHex ++ "1800ff")
  let exact ← native (TransactionBody.ofCbor exactBody)
  let assembled ← native (Transaction.ofBody exact)
  check (assembled.toCbor == ⟨#[0x84]⟩ ++ exactBody ++ ⟨#[0xa0, 0xf5, 0xf6]⟩)
    "assembly preserves original withdrawal body bytes"
  reject (TransactionBody.ofCbor (← hex (
    "a400800180020005a2581de0" ++ hashHex ++ "00581de0" ++ hashHex ++ "01")))
    "duplicate nested account"
  for _ in [:100] do
    let parsed ← native (Withdrawals.ofCbor withdrawals.toCbor)
    check (parsed.totalLovelace == maximum.value) "repeated map getter ownership"
    let parsedBody ← native (TransactionBody.ofCbor body.toCbor)
    let _ ← native (Transaction.ofBody parsedBody)
    reject (Withdrawals.ofCbor (withdrawals.toCbor.extract 0 (withdrawals.toCbor.size - 1)))
      "repeated partially populated map failure"

/-- Exercise concrete native accounts, maps and transaction-body integration. -/
def run : IO Unit := do
  testAccounts
  testMaps

end Tests.Withdrawals
