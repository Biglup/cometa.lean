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
import Cometa.Value
import Cometa.PlutusData
import Cometa.Script

/-! Native transaction-output construction and inspection with checked Lean fields.
Pure validators check payment addresses and quantity bounds; native constructors
and codecs build the representation. This does not determine minimum ada.
-/

namespace Cometa

-- TYPES ----------------------------------------------------------------------

/-- The three transaction-output datum forms. -/
inductive Datum where
  /-- No datum. -/
  | none
  /-- The 32-byte hash of an off-chain datum. -/
  | hash (digest : Hash 32)
  /-- Exact validated inline datum encoding. -/
  | inline (data : EncodedPlutusData)

/-- A complete output with checked quantities and a payment destination. -/
structure Output where
  private mk ::
  /-- Recipient, excluding reward accounts. -/
  address : Address
  /-- Asset bundle with evidence of nonnegative, representable output quantities. -/
  value : Value.CheckedOutput
  /-- No datum, a datum hash, or inline data. -/
  datum : Datum
  /-- Optional native or versioned Plutus reference script. -/
  referenceScript : Option Script
  /-- The recipient has a payment-address header, rather than a reward header. -/
  paymentAddress : address.isPayment = true
  private cbor : ByteArray

namespace Output

-- DEFINITIONS ----------------------------------------------------------------

private def nativeFields (address : Address) (value : Value) (datum : Datum)
    (reference : Option Script) : Internal.Component :=
  let datumFields := match datum with
    | .none => Internal.Component.node 0 0 ByteArray.empty ByteArray.empty "" []
    | .hash digest => .node 1 0 digest.bytes ByteArray.empty "" []
    | .inline data => .node 2 0 data.toCbor ByteArray.empty "" []
  let scriptFields := match reference with
    | none => Internal.Component.node 0 0 ByteArray.empty ByteArray.empty "" []
    | some script => .node 1 0 script.toCbor ByteArray.empty "" []
  .node 0 0 address.toBytes ByteArray.empty "" [value.toNative, datumFields, scriptFields]

/-- Check destination and quantity invariants, then construct and serialize a
complete output through cardano-c. This does not balance or establish minimum ada.
-/
def create (address : Address) (value : Value) (datum : Datum := .none)
    (referenceScript : Option Script := none) : EIO Error Output := do
  if paymentAddress : address.isPayment = true then
    let checked ← EIO.ofExcept value.checkOutput
    let fields := nativeFields address value datum referenceScript
    let bytes ← (Internal.componentEncode 6 fields).adapt (.native "Output.create")
    return ⟨address, checked, datum, referenceScript, paymentAddress, bytes⟩
  else
    throw (.invalidInput "A reward account cannot receive an output")

/-- Return the map encoding produced by the native output writer at construction.
This is a cached snapshot; accessing it performs no hidden native effect.
-/
def toCbor (output : Output) : ByteArray := output.cbor

/-- Encode a legacy array using the native CBOR writer and native value codec.
The pinned output writer emits maps only, so this compatibility adapter explicitly
writes the legacy container. Inline data and reference scripts are rejected.
-/
def toLegacyCbor (output : Output) : EIO Error ByteArray := do
  if output.referenceScript.isSome then
    throw (.invalidInput "Legacy outputs cannot carry reference scripts")
  if let .inline _ := output.datum then
    throw (.invalidInput "Legacy outputs cannot carry inline data")
  (Internal.componentEncode 7 (nativeFields output.address output.value.val output.datum none)).adapt (.native "Output.toLegacyCbor")

/-- Reparse and serialize the cached output using the native codec. -/
def toNativeCbor (output : Output) : EIO Error ByteArray :=
  (Internal.outputRoundTrip output.toCbor).adapt (.native "Output.toNativeCbor")

/-- Check native round-trip stability for this output. The evidence concerns this
observed result, not an independent codec or a universal theorem about C.
-/
def checkNativeEncoding (output : Output) :
    EIO Error {bytes : ByteArray // bytes = output.toCbor} := do
  let bytes ← output.toNativeCbor
  if agreement : bytes = output.toCbor then return ⟨bytes, agreement⟩
  else throw (.invalidInput "Native output round trip changed its encoding")

-- DECODING -------------------------------------------------------------------

private def decodeDatum : Internal.Component → EIO Error Datum
  | .node 0 _ _ _ _ _ => pure .none
  | .node 1 _ bytes _ _ _ => return .hash (← EIO.ofExcept (Hash.ofBytes bytes))
  | .node 2 _ bytes _ _ _ => return .inline (← EncodedPlutusData.ofCbor bytes)
  | _ => throw (.invalidInput "Invalid native datum snapshot")

/-- Parse through the native output codec, copy its complete getter results, and
check public invariants. The resulting encoding is produced by the native map
writer; `EncodedOutput` separately retains the original input representation.
-/
def ofCbor (bytes : ByteArray) : EIO Error Output := do
  let .node _ _ addressBytes _ _ fields ←
    (Internal.componentDecode 6 bytes).adapt (.native "Output.ofCbor")
  let [valueFields, datumFields, scriptFields] := fields
    | throw (.invalidInput "Incomplete native output snapshot")
  let address ← Address.ofBytes addressBytes
  let value ← EIO.ofExcept (Value.ofNative valueFields)
  let datum ← decodeDatum datumFields
  let reference : Option Script ← match scriptFields with
    | .node 0 _ _ _ _ _ => pure none
    | .node 1 _ scriptBytes _ _ _ => pure (some (← Script.ofCbor scriptBytes))
    | _ => throw (.invalidInput "Invalid native reference-script snapshot")
  create address value datum reference

-- THEOREMS -------------------------------------------------------------------

/-- Every constructed output carries evidence for its value's quantity bounds. -/
theorem value_valid (output : Output) : output.value.val.ValidOutput := output.value.property

/-- Every constructed output's recipient has a payment-address header. -/
theorem address_isPayment (output : Output) : output.address.isPayment = true :=
  output.paymentAddress

end Output

-- ENCODED OUTPUTS ------------------------------------------------------------

/-- Validated output retaining its exact imported representation alongside fields. -/
structure EncodedOutput where
  private mk ::
  private bytes : ByteArray
  private contents : Output

namespace EncodedOutput

/-- Decode complete output fields while preserving legacy, indefinite, and
nonminimal encodings. Validation is component validation, not ledger acceptance.
-/
def ofCbor (bytes : ByteArray) : EIO Error EncodedOutput := do
  return ⟨bytes, ← Output.ofCbor bytes⟩

/-- Encode a constructed output using the fresh map representation. -/
def ofOutput (output : Output) : EncodedOutput := ⟨output.toCbor, output⟩

/-- Inspect the validated semantic fields without changing the retained bytes. -/
def toOutput (output : EncodedOutput) : Output := output.contents

/-- Return the exact validated representation. -/
def toCbor (output : EncodedOutput) : ByteArray := output.bytes

end EncodedOutput
end Cometa
