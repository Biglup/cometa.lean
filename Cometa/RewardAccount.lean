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

import Cometa.Address
import Cometa.Credential
import Cometa.Network

/-! Native reward-account construction and inspection. These accounts identify
staking credentials; they do not establish registration, rewards, or authority.
-/

namespace Cometa

-- TYPES ----------------------------------------------------------------------

/-- A native reward address with copied network and staking credential. -/
structure RewardAccount where
  private mk ::
  /-- Network reported by the native getter. -/
  network : Network
  /-- Key or script staking credential reported by the native getter. -/
  credential : Credential
  private address : Address

namespace RewardAccount

-- DEFINITIONS ----------------------------------------------------------------

/-- Parse exactly 29 address bytes through cardano-c. Payment headers and reserved
network discriminators are rejected rather than normalized into reward accounts.
-/
def ofBytes (bytes : ByteArray) : EIO Error RewardAccount := do
  let .node kind _ encoded _ _ children ←
    (Internal.componentDecode 12 bytes).adapt (.native "RewardAccount.ofBytes")
  let network ← match kind with
    | 0 => pure Network.testnet
    | 1 => pure Network.mainnet
    | _ => throw (.invalidInput "Unsupported reward-account network")
  let credential ← match children with
    | [node] => EIO.ofExcept (Credential.ofNative node)
    | _ => throw (.invalidInput "Invalid native reward-account snapshot")
  let address ← Address.ofBytes encoded
  return ⟨network, credential, address⟩

/-- Validate an already parsed address as a reward account. -/
def ofAddress (address : Address) : EIO Error RewardAccount := ofBytes address.toBytes

/-- Parse a Bech32 reward address. Require the native lowercase display
encoding, rejecting text whose payload would be normalized or truncated. -/
def ofString (text : String) : EIO Error RewardAccount := do
  let account ← ofAddress (← Address.ofString text)
  unless text == account.address.toString do
    throw (.invalidInput "Noncanonical reward-account text")
  return account

/-- Construct a key or script reward account with the native address constructor. -/
def create (network : Network) (credential : Credential) : EIO Error RewardAccount := do
  let fields := Internal.Component.node (if network == .mainnet then 1 else 0)
    0 ByteArray.empty ByteArray.empty "" [credential.toNative]
  let bytes ← (Internal.componentEncode 12 fields).adapt (.native "RewardAccount.create")
  ofBytes bytes

/-- Serialized address bytes (not a CBOR byte string). -/
def toBytes (account : RewardAccount) : ByteArray := account.address.toBytes

/-- Native Bech32 display encoding. -/
def toString (account : RewardAccount) : String := account.address.toString

/-- The checked general address representation. -/
def toAddress (account : RewardAccount) : Address := account.address

instance : BEq RewardAccount := ⟨fun left right => left.toBytes == right.toBytes⟩
instance : ToString RewardAccount := ⟨toString⟩

end RewardAccount
end Cometa
