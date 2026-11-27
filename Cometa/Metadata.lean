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

import Cometa.Metadatum

/-! Labeled transaction metadata, constructed and inspected through cardano-c.
Labels must be unique. Nested metadata maps retain their ordered pairs.
-/

namespace Cometa

-- TYPES ----------------------------------------------------------------------

/-- Checked metadata label map with exact imported or native-produced bytes. -/
structure Metadata where
  private mk ::
  /-- Label/value entries in native label order. -/
  entries : List (UInt64 × Metadatum)
  /-- Uniqueness checked on the actual native snapshot. -/
  unique : (entries.map Prod.fst).Nodup
  private cbor : ByteArray

namespace Metadata

-- DEFINITIONS ----------------------------------------------------------------

/-- Parse through the native metadata codec and reject duplicate labels or
out-of-bounds leaves. Retain exact original bytes for inspection.
-/
def ofCbor (bytes : ByteArray) : EIO Error Metadata := do
  let .node _ _ _ _ _ children ←
    (Internal.componentDecode 15 bytes).adapt (.native "Metadata.ofCbor")
  let entries ← EIO.ofExcept (children.mapM fun | .node _ label _ _ _ values => do
    match values with
    | [value] => return (label, ← Metadatum.ofNative value)
    | _ => throw (.invalidInput "Invalid native metadata entry"))
  if unique : (entries.map Prod.fst).Nodup then return ⟨entries, unique, bytes⟩
  else throw (.invalidInput "Duplicate metadata label")

/-- Construct native metadata with unique labels and checked semantic values. -/
def ofList (entries : List (UInt64 × Metadatum)) : EIO Error Metadata := do
  unless (entries.map Prod.fst).Nodup do throw (.invalidInput "Duplicate metadata label")
  let children ← EIO.ofExcept (entries.mapM fun (label, value) => do
    return Internal.Component.node 0 label ByteArray.empty ByteArray.empty "" [← value.toNative])
  let fields := Internal.Component.node 0 0 ByteArray.empty ByteArray.empty "" children
  let bytes ← (Internal.componentEncode 15 fields).adapt (.native "Metadata.ofList")
  ofCbor bytes

/-- Exact metadata map bytes. Embedding into fresh auxiliary data may normalize them. -/
def toCbor (metadata : Metadata) : ByteArray := metadata.cbor

-- THEOREMS -------------------------------------------------------------------

/-- The copied native label map has no duplicate labels. -/
theorem labels_unique (metadata : Metadata) : (metadata.entries.map Prod.fst).Nodup := metadata.unique

end Metadata
end Cometa
