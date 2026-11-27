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

import Cometa.TransactionId
import Cometa.Internal.Component

/-! Output references constructed and parsed with the native transaction-input API. -/

namespace Cometa

-- TYPES ----------------------------------------------------------------------

/-- A reference to an output of an earlier transaction. -/
structure OutputReference where
  /-- Identifier of the transaction that created the output. -/
  transactionId : TransactionId
  /-- Zero-based index, retaining the native unsigned 64-bit representation.
  Construction does not check whether this index exists or fits an era's limits.
  -/
  index : UInt64
  deriving DecidableEq

instance : ToString OutputReference where
  toString reference := s!"{reference.transactionId}#{reference.index}"

namespace OutputReference

-- DEFINITIONS ----------------------------------------------------------------

/-- Copied fields for the native input constructor. -/
def toNative (reference : OutputReference) : Internal.Component :=
  .node 0 reference.index reference.transactionId.toBytes ByteArray.empty "" []

/-- Check the hash copied from native input getters. -/
def ofNative : Internal.Component → Except Error OutputReference
  | .node _ index hash _ _ _ => return ⟨← TransactionId.ofBytes hash, index⟩

/-- Construct and serialize a native transaction input. -/
def toCbor (reference : OutputReference) : EIO Error ByteArray :=
  (Internal.componentEncode 8 reference.toNative).adapt (.native "OutputReference.toCbor")

/-- Parse exactly one native input and copy its identifier/index. -/
def ofCbor (bytes : ByteArray) : EIO Error OutputReference := do
  let fields ← (Internal.componentDecode 8 bytes).adapt (.native "OutputReference.ofCbor")
  EIO.ofExcept (ofNative fields)

end OutputReference
end Cometa
