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
import Cometa.Lovelace
import Cometa.TransactionId
import Cometa.Internal.Transaction

/-! Immutable transaction inspection through cardano-c.

Parsing checks the native serialization format, not signatures, script execution,
ledger rules, balance, or network availability. The full input CBOR is retained
exactly: re-encoding a body could change its transaction ID. Native references
are released within each call; observations use only Lean-owned values.
-/

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
  deriving BEq

instance : ToString OutputReference where
  toString reference := s!"{reference.transactionId}#{reference.index}"

namespace Transaction

/-- Read-only summary of an ordinary output. This is not a complete value model. -/
structure OutputSummary where
  private mk ::
  /-- Parsed recipient address. No payment or network validity is asserted. -/
  address : Address
  /-- Lovelace component only; native assets are retained in `toCbor`. -/
  lovelace : Lovelace
  private cbor : ByteArray

/-- Complete output CBOR reserialized by cardano-c, including native assets,
datum, and reference script where present. Output framing may be normalized;
use `Transaction.toCbor` to retain the original transaction representation.
-/
def OutputSummary.toCbor (output : OutputSummary) : ByteArray := output.cbor

end Transaction

/-- A parsed transaction and immutable inspection snapshot. -/
structure Transaction where
  private mk ::
  private cbor : ByteArray
  private identifier : TransactionId
  private feeAmount : Lovelace
  private validity : Bool
  private spendingInputs : Array OutputReference
  private ordinaryOutputs : Array Transaction.OutputSummary

namespace Transaction

-- DEFINITIONS ----------------------------------------------------------------

private def inputOfRaw (input : Internal.RawInput) : Except Error OutputReference := do
  let (hash, index) := input
  return ⟨← TransactionId.ofBytes hash, index⟩

private def outputOfRaw (output : Internal.RawOutput) : EIO Error OutputSummary := do
  let (addressBytes, coin, cbor) := output
  let address ← Address.ofBytes addressBytes
  let lovelace ← EIO.ofExcept (Lovelace.ofNat coin.toNat)
  return ⟨address, lovelace, cbor⟩

/-- Parse exactly one native-supported transaction, rejecting empty, malformed,
or trailing data. Historical, mempool, and block frames use the native parser.
Acceptance does not establish ledger validity. The original bytes are preserved.
-/
def ofCbor (bytes : ByteArray) : EIO Error Transaction := do
  if bytes.isEmpty then
    throw (.invalidInput "Transaction CBOR must be nonempty")

  let (hash, fee, validity, inputs, outputs) ←
    (Internal.transactionFromCbor bytes).adapt (.native "Transaction.ofCbor")
  let identifier ← EIO.ofExcept (TransactionId.ofBytes hash)
  let feeAmount ← EIO.ofExcept (Lovelace.ofNat fee.toNat)
  let spendingInputs ← EIO.ofExcept (inputs.mapM inputOfRaw)
  let ordinaryOutputs ← outputs.mapM outputOfRaw
  return ⟨bytes, identifier, feeAmount, validity, spendingInputs, ordinaryOutputs⟩

/-- Parse strict hexadecimal transaction CBOR. No prefix or whitespace is accepted. -/
def ofHex (text : String) : EIO Error Transaction := do
  ofCbor (← EIO.ofExcept (Hex.toBytes text))

/-- Exact original transaction bytes, including witnesses and outer framing. -/
def toCbor (transaction : Transaction) : ByteArray := transaction.cbor

/-- Lowercase hexadecimal encoding of the exact original transaction bytes. -/
def toHex (transaction : Transaction) : String := Hex.ofBytes transaction.cbor

/-- BLAKE2b-256 hash of the original transaction-body bytes, computed natively. -/
def id (transaction : Transaction) : TransactionId := transaction.identifier

/-- Declared transaction fee in lovelace; not a minimum-fee calculation. -/
def fee (transaction : Transaction) : Lovelace := transaction.feeAmount

/-- Declared phase-two script-validity flag, not an evaluation result.
Historical three-field transactions implicitly declare `true`.
-/
def scriptValidity (transaction : Transaction) : Bool := transaction.validity

/-- Spending input references sorted by the native parser (hash, then index),
excluding collateral and reference inputs. Duplicate entries are retained;
parsing does not establish the ledger uniqueness rule.
-/
def inputs (transaction : Transaction) : Array OutputReference := transaction.spendingInputs

/-- Ordinary outputs in encoded order, excluding the collateral-return output.
Each summary includes only the lovelace component plus complete reserialized CBOR.
-/
def outputs (transaction : Transaction) : Array OutputSummary := transaction.ordinaryOutputs

instance : BEq Transaction where
  beq left right := left.cbor == right.cbor

end Transaction
end Cometa
