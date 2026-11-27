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

/-! Internal transaction snapshot ABI. Each product field is boxed, including
`UInt64` and `Bool`; arrays own their elements. No native handles escape a call.
-/

namespace Cometa.Internal

-- TYPES ----------------------------------------------------------------------

/-- Copied transaction hash and native unsigned output index. -/
abbrev RawInput := ByteArray × UInt64

/-- Copied address bytes, unsigned lovelace, and reserialized complete output CBOR. -/
abbrev RawOutput := ByteArray × UInt64 × ByteArray

/-- Body ID, fee, declared script validity, spending inputs, and ordinary outputs. -/
abbrev RawTransaction := ByteArray × UInt64 × Bool × Array RawInput × Array RawOutput

-- FOREIGN IMPORTS ------------------------------------------------------------

/-- Borrow exactly one transaction's CBOR and return an owned snapshot.
The reader rejects trailing bytes; failure returns a boxed native error code.
-/
@[extern "cometa_lean_transaction_from_cbor"]
opaque transactionFromCbor (bytes : @& ByteArray) : EIO UInt32 RawTransaction

/-- Build a native transaction with this body, an empty native witness set and
optional auxiliary data (empty bytes mean absent). Native caches retain imported identity.
-/
@[extern "cometa_lean_unsigned_transaction"]
opaque unsignedTransaction (body : @& ByteArray) (scriptValidity : Bool)
    (auxiliary : @& ByteArray) : EIO UInt32 ByteArray

/-- Extract exact auxiliary bytes from a native transaction; empty means absent. -/
@[extern "cometa_lean_transaction_auxiliary"]
opaque transactionAuxiliary (bytes : @& ByteArray) : EIO UInt32 ByteArray

end Cometa.Internal
