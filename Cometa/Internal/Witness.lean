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

/-! Borrowed-input native key-witness operations. All references stay inside C;
only copied encodings and native verification results cross the boundary.
-/

namespace Cometa.Internal

-- FOREIGN IMPORTS ------------------------------------------------------------

/-- Verify a parsed witness against arbitrary message bytes using native Ed25519. -/
@[extern "cometa_lean_vkey_verify"]
opaque vkeyVerify (witness : @& ByteArray) (message : @& ByteArray) : EIO UInt32 Bool

/-- Extract the native key-witness collection; empty bytes mean the field is absent. -/
@[extern "cometa_lean_transaction_vkeys"]
opaque transactionVkeys (transaction : @& ByteArray) : EIO UInt32 ByteArray

/-- Apply a native key-witness collection to a transaction. Check native body,
auxiliary payload, other witness fields and declared validity remain unchanged.
-/
@[extern "cometa_lean_transaction_apply_vkeys"]
opaque transactionApplyVkeys (transaction : @& ByteArray) (witnesses : @& ByteArray) :
    EIO UInt32 ByteArray

end Cometa.Internal
