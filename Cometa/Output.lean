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

/-! Complete typed transaction-output construction. Pure validation checks payment
addresses and quantity bounds; it does not balance a transaction or determine
minimum ada. Native codec interoperation is a separate, explicit operation.
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

namespace Output

-- DEFINITIONS ----------------------------------------------------------------

/-- Construct an output with full datum/reference-script support. This checks
address kind and quantity bounds, not network, era, size, minimum ada or balance.
-/
def create (address : Address) (value : Value) (datum : Datum := .none)
    (referenceScript : Option Script := none) : Except Error Output := do
  if paymentAddress : address.isPayment = true then
    return ⟨address, ← value.checkOutput, datum, referenceScript, paymentAddress⟩
  else
    throw (.invalidInput "A reward account cannot receive an output")

/-- Encode a fresh Babbage-style map output, retaining exact inline datum bytes.
Multi-asset maps are deterministically ordered; absence remains distinct from
an inline datum or an explicitly supplied reference script.
-/
def toCbor (output : Output) : ByteArray :=
  let fields := [(Internal.Cbor.unsigned 0, Internal.Cbor.bytes output.address.toBytes),
    (Internal.Cbor.unsigned 1, output.value.toCbor)]
  let fields := match output.datum with
    | .none => fields
    | .hash digest => fields ++ [(Internal.Cbor.unsigned 2,
        Internal.Cbor.array [Internal.Cbor.unsigned 0, Internal.Cbor.bytes digest.bytes])]
    | .inline data => fields ++ [(Internal.Cbor.unsigned 2,
        Internal.Cbor.array [Internal.Cbor.unsigned 1,
          Internal.Cbor.tag 24 (Internal.Cbor.bytes data.toCbor)])]
  let fields := match output.referenceScript with
    | none => fields
    | some script => fields ++ [(Internal.Cbor.unsigned 3,
        Internal.Cbor.tag 24 (Internal.Cbor.bytes script.toCbor))]
  Internal.Cbor.map fields

/-- Encode a legacy array output. Inline data and reference scripts are rejected;
legacy arrays support only an absent datum or a 32-byte datum hash.
-/
def toLegacyCbor (output : Output) : Except Error ByteArray := do
  if output.referenceScript.isSome then
    throw (.invalidInput "Legacy outputs cannot carry reference scripts")
  let fields := [Internal.Cbor.bytes output.address.toBytes, output.value.toCbor]
  match output.datum with
  | .none => return Internal.Cbor.array fields
  | .hash digest => return Internal.Cbor.array (fields ++ [Internal.Cbor.bytes digest.bytes])
  | .inline _ => throw (.invalidInput "Legacy outputs cannot carry inline data")

/-- Parse and serialize this output through the actual pinned C codec. This is
useful for native integration and conformance checks; it is not ledger validation.
The returned bytes may use native-normalized encodings.
-/
def toNativeCbor (output : Output) : EIO Error ByteArray :=
  (Internal.outputRoundTrip output.toCbor).adapt (.native "Output.toNativeCbor")

/-- Run the actual C codec and check exact agreement with the constructed bytes.
The returned evidence concerns this observed result, not every execution of C.
Use `toNativeCbor` directly when inspecting normalization differences.
-/
def checkNativeEncoding (output : Output) :
    EIO Error {bytes : ByteArray // bytes = output.toCbor} := do
  let bytes ← output.toNativeCbor
  if agreement : bytes = output.toCbor then return ⟨bytes, agreement⟩
  else throw (.invalidInput "Native output encoding differs from the constructed encoding")

-- DECODING -------------------------------------------------------------------

private structure Parts where
  address : Internal.Cbor.Term
  value : Internal.Cbor.Term
  datum : Option Internal.Cbor.Term := none
  script : Option Internal.Cbor.Term := none

private def outputParts : Internal.Cbor.Term → Except Error Parts
  | .array [address, value] => return ⟨address, value, none, none⟩
  | .array [address, value, digest] =>
    return ⟨address, value, some (.array [.unsigned 0, digest]), none⟩
  | .map fields => do
    let mut address := none
    let mut value := none
    let mut datum := none
    let mut script := none
    let mut seen : List UInt64 := []
    for (key, item) in fields do
      let key ← key.asUnsigned
      if seen.contains key then throw (.invalidInput "Duplicate output field")
      seen := key :: seen
      match key with
      | 0 => address := some item
      | 1 => value := some item
      | 2 => datum := some item
      | 3 => script := some item
      | _ => throw (.invalidInput "Unknown output field")
    let some destination := address | throw (.invalidInput "Missing output address")
    let some amount := value | throw (.invalidInput "Missing output value")
    return ⟨destination, amount, datum, script⟩
  | _ => throw (.invalidInput "Expected an output array or map")

private def decodeDatum : Internal.Cbor.Term → EIO Error Datum
  | .array [.unsigned 0, digest] => do
    let bytes ← EIO.ofExcept digest.asBytes
    return .hash (← EIO.ofExcept (Hash.ofBytes bytes))
  | .array [.unsigned 1, embedded] => do
    let bytes ← EIO.ofExcept embedded.asEmbedded
    return .inline (← EncodedPlutusData.ofCbor bytes)
  | _ => throw (.invalidInput "Invalid output datum option")

/-- Decode a legacy array or map output into checked fields. Re-encoding this
semantic value produces a fresh map; use `EncodedOutput` to retain input bytes.
Unknown fields, duplicate keys, malformed embeddings and invalid bounds fail.
-/
def ofCbor (bytes : ByteArray) : EIO Error Output := do
  let parts ← EIO.ofExcept (Internal.Cbor.decode bytes >>= outputParts)
  let addressBytes ← EIO.ofExcept parts.address.asBytes
  let address ← Address.ofBytes addressBytes
  let value ← EIO.ofExcept (Internal.outputValueFromTerm parts.value)
  let datum ← match parts.datum with
    | none => pure Datum.none
    | some item => decodeDatum item
  let reference : Option Script ← match parts.script with
    | none => pure none
    | some item => do
      let embedded ← EIO.ofExcept item.asEmbedded
      pure (some (← Script.ofCbor embedded))
  EIO.ofExcept (create address value.val datum reference)

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
