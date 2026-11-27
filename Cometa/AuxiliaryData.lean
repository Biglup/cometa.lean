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

import Cometa.Metadata
import Cometa.Script

/-! Native auxiliary data, including metadata, native scripts and Plutus V1–V4.
Imported bytes and their native hash are retained exactly; reconstructing a view
uses the native tagged-map writer and may change the hash. Scripts here are
auxiliary payloads, not transaction witnesses or execution evidence.
-/

namespace Cometa
namespace AuxiliaryData

-- TYPES ----------------------------------------------------------------------

/-- All fields supported by the pinned auxiliary-data implementation. -/
structure Config where
  /-- Optional label map; absence differs from a present empty map. -/
  metadata : Option Metadata := none
  /-- Optional ordered native scripts; semantic reconstruction can normalize CBOR. -/
  nativeScripts : Option (List NativeScript) := none
  /-- Optional ordered Plutus V1 program bytes; present empty lists stay present. -/
  plutusV1 : Option (List ByteArray) := none
  /-- Optional ordered Plutus V2 program bytes; present empty lists stay present. -/
  plutusV2 : Option (List ByteArray) := none
  /-- Optional ordered Plutus V3 program bytes; present empty lists stay present. -/
  plutusV3 : Option (List ByteArray) := none
  /-- Optional ordered Plutus V4 program bytes; present empty lists stay present. -/
  plutusV4 : Option (List ByteArray) := none

end AuxiliaryData

/-- Auxiliary data with copied semantic fields and exact native identity. -/
structure AuxiliaryData where
  private mk ::
  /-- Complete field snapshot from native getters. -/
  view : AuxiliaryData.Config
  private cbor : ByteArray
  private digest : Hash 32

namespace AuxiliaryData

-- DEFINITIONS ----------------------------------------------------------------

private def programs (kind : UInt64) (value : Option (List ByteArray)) : List Internal.Component :=
  match value with
  | none => []
  | some items => [.node kind 0 ByteArray.empty ByteArray.empty ""
      (items.map fun bytes => .node 0 0 bytes ByteArray.empty "" [])]

/-- Parse historical metadata-only, metadata/native-script pair, or tagged-map
forms through cardano-c. Hash the exact cached native encoding.
-/
def ofCbor (bytes : ByteArray) : EIO Error AuxiliaryData := do
  let .node _ _ hash _ _ fields ←
    (Internal.componentDecode 16 bytes).adapt (.native "AuxiliaryData.ofCbor")
  let mut view : Config := {}
  for field in fields do
    let .node kind _ payload _ _ children := field
    let programs := children.map fun | .node _ _ bytes _ _ _ => bytes
    match kind with
    | 0 => view := { view with metadata := some (← Metadata.ofCbor payload) }
    | 1 => view := { view with nativeScripts := some (← EIO.ofExcept (children.mapM NativeScript.ofNative)) }
    | 2 => view := { view with plutusV1 := some programs }
    | 3 => view := { view with plutusV2 := some programs }
    | 4 => view := { view with plutusV3 := some programs }
    | 5 => view := { view with plutusV4 := some programs }
    | _ => throw (.invalidInput "Unknown native auxiliary-data field")
  return ⟨view, bytes, ← EIO.ofExcept (Hash.ofBytes hash)⟩

/-- Construct all requested fields through native setters, serialize and inspect.
The writer selects tag 259; empty fields are not silently omitted.
-/
def create (config : Config) : EIO Error AuxiliaryData := do
  let mut fields := []
  if let some metadata := config.metadata then
    fields := fields ++ [.node 0 0 metadata.toCbor ByteArray.empty "" []]
  if let some scripts := config.nativeScripts then
    fields := fields ++ [.node 1 0 ByteArray.empty ByteArray.empty "" (scripts.map NativeScript.toNative)]
  fields := fields ++ programs 2 config.plutusV1 ++ programs 3 config.plutusV2 ++
    programs 4 config.plutusV3 ++ programs 5 config.plutusV4
  let bytes ← (Internal.componentEncode 16 (.node 0 0 ByteArray.empty ByteArray.empty "" fields))
    |>.adapt (.native "AuxiliaryData.create")
  ofCbor bytes

/-- Exact original or native-produced auxiliary-data encoding. -/
def toCbor (data : AuxiliaryData) : ByteArray := data.cbor

/-- Native BLAKE2b-256 digest of the exact encoding, suitable for body field 7. -/
def hash (data : AuxiliaryData) : Hash 32 := data.digest

/-- Check a body commitment against this native-computed hash and return evidence
for the observed equality. This does not prove the native hash implementation.
-/
def checkCommitment (data : AuxiliaryData) (expected : Option (Hash 32)) :
    Except Error (PLift (expected = some data.hash)) :=
  if agrees : expected = some data.hash then .ok ⟨agrees⟩
  else .error (.invalidInput "Auxiliary data does not match the body commitment")

-- THEOREMS -------------------------------------------------------------------

/-- Success establishes equality between the supplied commitment and observed hash. -/
theorem checkCommitment_sound (data : AuxiliaryData) (expected : Option (Hash 32))
    (success : (data.checkCommitment expected).isOk = true) : expected = some data.hash := by
  unfold checkCommitment at success
  split at success <;> simp_all [Except.isOk, Except.toBool]

end AuxiliaryData
end Cometa
