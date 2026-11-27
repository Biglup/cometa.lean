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

import Cometa.Hash
import Cometa.Internal.Component

/-! Key/script credentials. The containing ledger field determines their role;
construction proves hash length, not ownership or authority.
-/

namespace Cometa

-- TYPES ----------------------------------------------------------------------

/-- A key or script credential with a 28-byte hash. -/
inductive Credential where
  /-- Verification-key hash. -/
  | key (hash : Hash 28)
  /-- Script hash. -/
  | script (hash : Hash 28)
  deriving DecidableEq

namespace Credential

-- DEFINITIONS ----------------------------------------------------------------

/-- Copied fields for the native credential constructor. -/
def toNative (credential : Credential) : Internal.Component :=
  match credential with
  | .key hash => .node 0 0 hash.bytes ByteArray.empty "" []
  | .script hash => .node 1 0 hash.bytes ByteArray.empty "" []

/-- Validate a snapshot obtained from native credential getters. -/
def ofNative : Internal.Component → Except Error Credential
  | .node 0 _ bytes _ _ _ => return .key (← Hash.ofBytes bytes)
  | .node 1 _ bytes _ _ _ => return .script (← Hash.ofBytes bytes)
  | _ => .error (.invalidInput "Unknown native credential kind")

/-- Construct and encode a credential through cardano-c. -/
def toCbor (credential : Credential) : EIO Error ByteArray :=
  (Internal.componentEncode 0 credential.toNative).adapt (.native "Credential.toCbor")

/-- Parse a credential through cardano-c and check the copied hash length. -/
def ofCbor (bytes : ByteArray) : EIO Error Credential := do
  let fields ← (Internal.componentDecode 0 bytes).adapt (.native "Credential.ofCbor")
  EIO.ofExcept (ofNative fields)

end Credential
end Cometa
