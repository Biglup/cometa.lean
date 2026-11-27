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
import Cometa.Internal.CborDecoder

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

/-- Encode the credential as `[0, keyHash]` or `[1, scriptHash]`. -/
def toCbor : Credential → ByteArray
  | .key hash => Internal.Cbor.array [Internal.Cbor.unsigned 0, Internal.Cbor.bytes hash.bytes]
  | .script hash => Internal.Cbor.array [Internal.Cbor.unsigned 1, Internal.Cbor.bytes hash.bytes]

end Credential

namespace Internal

/-- Validate a credential's tag, arity and hash length without assigning a ledger role. -/
def credentialFromTerm : Cbor.Term → Except Error Credential
  | .array [.unsigned 0, bytes] => do return .key (← Hash.ofBytes (← bytes.asBytes))
  | .array [.unsigned 1, bytes] => do return .script (← Hash.ofBytes (← bytes.asBytes))
  | _ => .error (.invalidInput "Expected a key or script credential")

end Internal

namespace Credential

/-- Decode exactly one credential, rejecting unknown tags, bad lengths and trailing bytes. -/
def ofCbor (bytes : ByteArray) : Except Error Credential := do
  Internal.credentialFromTerm (← Internal.Cbor.decode bytes)

end Credential
end Cometa
