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
import Tests.Transaction
import Tests.Output

/-! Boundary and native integration checks. No credentials or network are used. -/

open Cometa

-- FIXTURES -------------------------------------------------------------------

-- CIP-19 vectors, also present in cardano-c's Apache-2.0 address corpus.
-- See docs/development.md for the pinned source and provenance.
private def paymentText :=
  "addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz"

private def rewardText :=
  "stake_test1uqehkck0lajq8gr28t9uxnuvgcqrc6070x3k9r8048z8y5gssrtvn"

-- HELPERS --------------------------------------------------------------------

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def expectFailure (action : EIO Error α) (message : String) : IO Unit := do
  match ← action.toIO' with
  | .error _ => pure ()
  | .ok _ => throw (IO.userError message)

private def require (result : Except Error α) : IO α :=
  IO.ofExcept (result.mapError toString)

-- TESTS ----------------------------------------------------------------------

private def testAmounts : IO Unit := do
  let zero ← require (Lovelace.ofNat 0)
  let maximum ← require (Lovelace.ofNat 18446744073709551615)
  let one ← require (Lovelace.ofNat 1)
  check (zero.value == 0) "zero lovelace"
  check (maximum.value == 18446744073709551615) "maximum lovelace"
  expectFailure (EIO.ofExcept (Lovelace.ofInt (-1))) "negative lovelace must fail"
  expectFailure (EIO.ofExcept (Lovelace.ofNat 18446744073709551616)) "overflow must fail"
  expectFailure (EIO.ofExcept (maximum.add one)) "addition must reject overflow"
  check ((← require (maximum.add zero)).value == maximum.value) "adding zero"

private def testAddresses : IO Unit := do
  let address ← (Address.ofString paymentText).toIO (IO.userError ∘ toString)
  check (address.toString == paymentText) "text round trip"
  let expected : ByteArray := ⟨#[
    0x60, 0x94, 0x93, 0x31, 0x5c, 0xd9, 0x2e, 0xb5, 0xd8, 0xc4,
    0x30, 0x4e, 0x67, 0xb7, 0xe1, 0x6a, 0xe3, 0x6d, 0x61, 0xd3,
    0x45, 0x02, 0x69, 0x46, 0x57, 0x81, 0x1a, 0x2c, 0x8e]⟩
  check (address.toBytes == expected) "CIP-19 enterprise address bytes"
  check (address.toBytes[0]? == some 0x60) "enterprise address header"
  let restored ← (Address.ofBytes address.toBytes).toIO (IO.userError ∘ toString)
  check (restored == address) "bytes round trip"

  expectFailure (Address.ofString "") "empty text accepted"
  expectFailure (Address.ofString "not an address") "malformed text accepted"
  expectFailure (Address.ofString "地址") "non-ASCII address accepted"
  expectFailure (Address.ofString (paymentText ++ String.singleton (Char.ofNat 0)))
    "embedded NUL accepted"
  expectFailure (Address.ofString (paymentText ++ "q")) "bad checksum accepted"
  expectFailure (Address.ofBytes ByteArray.empty) "empty bytes accepted"
  expectFailure (Address.ofBytes ⟨#[0x60]⟩) "truncated address accepted"
  match ← (Address.ofBytes ⟨#[0x90]⟩).toIO' with
  | .error (.native operation code) =>
    check (operation == "Address.ofBytes" && code != 0) "native error payload lost"
  | _ => throw (IO.userError "Reserved header must return a structured native error")

  -- Exercise repeated ownership transfer on both success and error paths.
  for _ in [:1000] do
    let copy ← (Address.ofBytes address.toBytes).toIO (IO.userError ∘ toString)
    check (copy == address) "repeated parsing changed bytes"
    expectFailure (Address.ofBytes ⟨#[0x60]⟩) "repeated invalid parse accepted"

private def testPlans : IO Unit := do
  let recipient ← (Address.ofString paymentText).toIO (IO.userError ∘ toString)
  let reward ← (Address.ofString rewardText).toIO (IO.userError ∘ toString)
  let amount ← require (Lovelace.ofNat 2000000)
  expectFailure (EIO.ofExcept (Payment.create reward amount)) "reward account accepted for payment"
  let payment ← require (Payment.create recipient amount)
  let plan := Plan.payTo payment ++ Plan.payTo payment
  check (plan.payments.length == 2) "duplicate payments must be retained"
  check (plan.totalLovelace == 4000000) "plan total"

/-- Run validation and native ABI checks against the pinned release. -/
def main : IO Unit := do
  check ((← nativeVersion) == "2.0.0-rc.7") "unexpected native version"
  testAmounts
  testAddresses
  testPlans
  Tests.Transaction.run
  Tests.Output.run
  IO.println "Cometa boundary and native integration tests passed"
