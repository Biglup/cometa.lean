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

import Cometa.RewardAccount
import Cometa.Lovelace

/-! Native reward withdrawal maps with checked account uniqueness. Zero amounts
are retained, including script withdrawals used for validation. No rewards query,
authorization, or era-specific ledger check is performed.
-/

namespace Cometa

-- TYPES ----------------------------------------------------------------------

/-- One reward-account withdrawal in lovelace. -/
structure Withdrawal where
  /-- Account whose rewards are withdrawn. -/
  account : RewardAccount
  /-- Unsigned native coin amount; zero is allowed. -/
  amount : Lovelace

/-- Exact native map bytes and entries in native address-byte order. -/
structure Withdrawals where
  private mk ::
  /-- Entries copied through indexed native getters, without coalescing. -/
  entries : List Withdrawal
  /-- Uniqueness of the observed serialized reward-account identities. -/
  unique : (entries.map fun entry => entry.account.toBytes).Nodup
  private cbor : ByteArray

namespace Withdrawals

-- DEFINITIONS ----------------------------------------------------------------

/-- Parse exactly one native withdrawal map, then reject duplicate accounts in
its getter snapshot. Imported bytes are retained, including nonminimal encodings.
-/
def ofCbor (bytes : ByteArray) : EIO Error Withdrawals := do
  let .node _ _ _ _ _ children ←
    (Internal.componentDecode 13 bytes).adapt (.native "Withdrawals.ofCbor")
  let entries ← children.mapM fun | .node _ amount address _ _ _ => do
    let account ← RewardAccount.ofBytes address
    let amount ← EIO.ofExcept (Lovelace.ofNat amount.toNat)
    pure (Withdrawal.mk account amount)
  if unique : (entries.map fun entry => entry.account.toBytes).Nodup then
    return ⟨entries, unique, bytes⟩
  else throw (.invalidInput "Duplicate withdrawal account")

/-- Construct and inspect a native map. Duplicate accounts are rejected even if
amounts match; entries are sorted by the native writer and zero amounts remain.
-/
def ofList (entries : List Withdrawal) : EIO Error Withdrawals := do
  unless (entries.map fun entry => entry.account.toBytes).Nodup do
    throw (.invalidInput "Duplicate withdrawal account")
  let children := entries.map fun entry => Internal.Component.node 0 entry.amount.value.toUInt64
    entry.account.toBytes ByteArray.empty "" []
  let fields := Internal.Component.node 0 0 ByteArray.empty ByteArray.empty "" children
  let bytes ← (Internal.componentEncode 13 fields).adapt (.native "Withdrawals.ofList")
  ofCbor bytes

/-- Exact imported bytes or the native encoding produced at construction. -/
def toCbor (withdrawals : Withdrawals) : ByteArray := withdrawals.cbor

/-- Sum of observed amounts without overflow. This may exceed one native coin;
callers must check bounds when using it to construct an output.
-/
def totalLovelace (withdrawals : Withdrawals) : Nat :=
  (withdrawals.entries.map fun entry => entry.amount.value).sum

-- THEOREMS -------------------------------------------------------------------

/-- Every accepted native snapshot has unique serialized reward accounts. -/
theorem accounts_unique (withdrawals : Withdrawals) :
    (withdrawals.entries.map fun entry => entry.account.toBytes).Nodup := withdrawals.unique

end Withdrawals
end Cometa
