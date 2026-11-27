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

-- THEOREMS -------------------------------------------------------------------

/-- Every constructed output carries evidence for its value's quantity bounds. -/
theorem value_valid (output : Output) : output.value.val.ValidOutput := output.value.property

/-- Every constructed output's recipient has a payment-address header. -/
theorem address_isPayment (output : Output) : output.address.isPayment = true :=
  output.paymentAddress

end Output
end Cometa
