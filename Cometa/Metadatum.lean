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

import Cometa.Internal.Component
import Cometa.Error

/-! Metadata values and native codecs. Integers use the ledger CBOR range;
byte/text leaves are at most 64 bytes, measured in UTF-8 for text. Semantic map
entries retain ordering and duplicates; application schemas are not validated.
-/

namespace Cometa

-- TYPES ----------------------------------------------------------------------

/-- A transaction metadata value, distinct from Plutus data. -/
inductive Metadatum where
  /-- Ordered key/value pairs; keys may themselves be any metadata value. -/
  | map (entries : List (Metadatum × Metadatum))
  /-- Ordered metadata values. -/
  | list (entries : List Metadatum)
  /-- Integer checked against -2^64 through 2^64-1 by native-boundary wrappers. -/
  | integer (value : Int)
  /-- Binary leaf checked against the 64-byte bound. -/
  | bytes (value : ByteArray)
  /-- Unicode text checked against the 64-byte UTF-8 bound. -/
  | text (value : String)

namespace Metadatum

-- DEFINITIONS ----------------------------------------------------------------

/-- Copy fields and validate scalar bounds before calling native constructors.
Text is transported as bytes so embedded NULs are not truncated by a C string.
-/
def toNative : Metadatum → Except Error Internal.Component
  | .map entries => do
    let fields ← entries.mapM fun entry => do
      return [← toNative entry.1, ← toNative entry.2]
    return .node 0 0 ByteArray.empty ByteArray.empty "" fields.flatten
  | .list entries => do
    return .node 1 0 ByteArray.empty ByteArray.empty "" (← entries.mapM toNative)
  | .integer value => do
    unless -18446744073709551616 ≤ value && value ≤ 18446744073709551615 do
      throw (.invalidInput "Metadata integer exceeds the ledger CBOR range")
    return .node 2 0 ByteArray.empty ByteArray.empty (toString value) []
  | .bytes value => do
    unless value.size ≤ 64 do throw (.invalidInput "Metadata byte leaf exceeds 64 bytes")
    return .node 3 0 value ByteArray.empty "" []
  | .text value => do
    unless value.toUTF8.size ≤ 64 do throw (.invalidInput "Metadata text exceeds 64 UTF-8 bytes")
    return .node 4 0 value.toUTF8 ByteArray.empty "" []
termination_by data => sizeOf data
decreasing_by
  all_goals simp_wf
  all_goals first
    | decreasing_tactic
    | (rename_i membership
       have smaller := List.sizeOf_lt_of_mem membership
       cases entry
       simp_all only [Prod.mk.sizeOf_spec]
       omega)

private def pairs : List Metadatum → Except Error (List (Metadatum × Metadatum))
  | [] => .ok []
  | key :: value :: rest => do return (key, value) :: (← pairs rest)
  | [_] => .error (.invalidInput "Incomplete native metadata map snapshot")

/-- Check copied native getters, including UTF-8 and leaf/integer bounds. -/
def ofNative : Internal.Component → Except Error Metadatum
  | .node kind _ payload _ decimal children => do
    let value ← match kind with
      | 0 => return .map (← pairs (← children.mapM ofNative))
      | 1 => return .list (← children.mapM ofNative)
      | 2 =>
        let some value := decimal.toInt? | throw (.invalidInput "Invalid native metadata integer")
        pure (.integer value)
      | 3 => pure (.bytes payload)
      | 4 =>
        let some value := String.fromUTF8? payload | throw (.invalidInput "Invalid metadata UTF-8")
        pure (.text value)
      | _ => throw (.invalidInput "Unknown native metadata kind")
    -- Container children were checked recursively; validate each scalar only once.
    if kind ≥ 2 then
      let _ ← value.toNative
      pure ()
    return value

/-- Construct and serialize through cardano-c after checking metadata bounds. -/
def toCbor (value : Metadatum) : EIO Error ByteArray := do
  let fields ← EIO.ofExcept value.toNative
  (Internal.componentEncode 14 fields).adapt (.native "Metadatum.toCbor")

/-- Parse exactly one value natively, then validate the copied semantic result.
Re-encoding this view can normalize the original bytes.
-/
def ofCbor (bytes : ByteArray) : EIO Error Metadatum := do
  let fields ← (Internal.componentDecode 14 bytes).adapt (.native "Metadatum.ofCbor")
  EIO.ofExcept (ofNative fields)

end Metadatum
end Cometa
