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

import Cometa.InputSet
import Cometa.Lovelace
import Cometa.Output

/-! Explicit body construction and inspection using native constructors, setters,
readers and getters. Imported bodies retain all their original bytes, including
fields whose typed construction is not implemented yet. No balancing is implied.
-/

namespace Cometa

-- TYPES ----------------------------------------------------------------------

/-- Network discriminator carried by the optional transaction-body field. -/
inductive Network where
  /-- Test networks, including preprod and preview. -/
  | testnet
  /-- Cardano mainnet. -/
  | mainnet
  deriving DecidableEq, BEq

namespace TransactionBody

/-- Explicit construction fields currently bound to native body setters.
Absent optional fields remain distinct from present empty sets/maps where the
native writer supports them. Explicitly empty guards are rejected on construction
because the pinned writer omits that field.
This does not assert era activation, balance, minimum fees, or ledger validity.
-/
structure Config where
  /-- Spending inputs with checked uniqueness. -/
  inputs : InputSet
  /-- Ordinary outputs in application order. -/
  outputs : Array Output
  /-- Explicit fee; no fee calculation is performed. -/
  fee : Lovelace
  /-- Exclusive upper validity slot. -/
  invalidAfter : Option UInt64 := none
  /-- Inclusive lower validity slot. -/
  invalidBefore : Option UInt64 := none
  /-- Auxiliary-data commitment, without constructing or checking its payload. -/
  auxiliaryDataHash : Option (Hash 32) := none
  /-- Signed mint/burn bundle; ada must be zero. -/
  mint : Option Value := none
  /-- Script-data commitment, without budget/redeemer calculation. -/
  scriptDataHash : Option (Hash 32) := none
  /-- Collateral input set; no overlap or collateral sufficiency rule is inferred. -/
  collateral : Option InputSet := none
  /-- Required key/script credentials. Key-only sets use the native required-signer
  representation; script credentials select the contextual guard form.
  -/
  guards : Option (List Credential) := none
  /-- Optional body network discriminator. -/
  network : Option Network := none
  /-- Complete collateral-return output. -/
  collateralReturn : Option Output := none
  /-- Explicit total collateral in lovelace. -/
  totalCollateral : Option Lovelace := none
  /-- Reference inputs; disjointness can be checked explicitly with InputSet. -/
  referenceInputs : Option InputSet := none
  /-- Declared current treasury value in lovelace. -/
  treasuryValue : Option Lovelace := none
  /-- Treasury donation in lovelace. -/
  donation : Option Lovelace := none

end TransactionBody

/-- Native transaction body with exact encoding and a copied view of bound fields. -/
structure TransactionBody where
  private mk ::
  /-- Known core fields, read from native getters. This view is not necessarily
  complete: use `toConfig` before reconstructing an imported body.
  -/
  view : TransactionBody.Config
  /-- True when native getters expose fields not yet represented by Config. -/
  hasAdditionalFields : Bool
  private cbor : ByteArray
  private identifier : TransactionId

namespace TransactionBody

-- NATIVE FIELD TRANSPORT -----------------------------------------------------

private def field (kind : UInt64) (bytes : ByteArray := ByteArray.empty)
    (number : UInt64 := 0) (children : List Internal.Component := []) : Internal.Component :=
  .node kind number bytes ByteArray.empty "" children

private def addNumber (kind : UInt64) (value : Option UInt64)
    (fields : List Internal.Component) : List Internal.Component :=
  match value with
  | none => fields
  | some number => fields ++ [field kind ByteArray.empty number]

private def addBytes (kind : UInt64) (value : Option ByteArray)
    (fields : List Internal.Component) : List Internal.Component :=
  match value with
  | none => fields
  | some bytes => fields ++ [field kind bytes]

private def Config.toNative (config : Config) : EIO Error Internal.Component := do
  let mut fields := [field 0 config.inputs.toCbor,
    field 1 ByteArray.empty 0 (config.outputs.toList.map fun output => field 0 output.toCbor)]
  fields := addNumber 3 config.invalidAfter fields
  fields := addNumber 8 config.invalidBefore fields
  fields := addNumber 17 (config.totalCollateral.map fun coin => coin.value.toUInt64) fields
  fields := addNumber 21 (config.treasuryValue.map fun coin => coin.value.toUInt64) fields
  fields := addNumber 22 (config.donation.map fun coin => coin.value.toUInt64) fields
  fields := addBytes 7 (config.auxiliaryDataHash.map Hash.bytes) fields
  fields := addBytes 11 (config.scriptDataHash.map Hash.bytes) fields
  fields := addBytes 13 (config.collateral.map InputSet.toCbor) fields
  fields := addBytes 18 (config.referenceInputs.map InputSet.toCbor) fields
  fields := addBytes 16 (config.collateralReturn.map Output.toCbor) fields
  if let some mint := config.mint then
    fields := fields ++ [field 9 (← mint.toMintCbor)]
  if let some guards := config.guards then
    if guards.isEmpty then throw (.invalidInput "Native body writer omits explicitly empty guards")
    unless guards.Nodup do throw (.invalidInput "Duplicate guard credential")
    fields := fields ++ [field 14 ByteArray.empty 0 (guards.map Credential.toNative)]
  if let some network := config.network then
    fields := fields ++ [field 15 ByteArray.empty (if network == .mainnet then 1 else 0)]
  return .node 0 config.fee.value.toUInt64 ByteArray.empty ByteArray.empty "" fields

private def getField (kind : UInt64) (fields : List Internal.Component) : Except Error Internal.Component :=
  match fields.find? (fun | .node tag _ _ _ _ _ => tag == kind) with
  | some value => .ok value
  | none => .error (.invalidInput "Missing native body field")

private def readConfig (fee : UInt64) (fields : List Internal.Component) : EIO Error Config := do
  let .node _ _ inputBytes _ _ _ ← EIO.ofExcept (getField 0 fields)
  let .node _ _ _ _ _ outputFields ← EIO.ofExcept (getField 1 fields)
  let inputs ← InputSet.ofCbor inputBytes
  let outputs ← outputFields.toArray.mapM fun | .node _ _ bytes _ _ _ => Output.ofCbor bytes
  let fee ← EIO.ofExcept (Lovelace.ofNat fee.toNat)
  let mut config : Config := { inputs, outputs, fee }
  for node in fields do
    let .node kind number bytes _ _ children := node
    match kind with
    | 0 | 1 => pure ()
    | 3 => config := { config with invalidAfter := some number }
    | 8 => config := { config with invalidBefore := some number }
    | 7 => config := { config with auxiliaryDataHash := some (← EIO.ofExcept (Hash.ofBytes bytes)) }
    | 9 => config := { config with mint := some (← Value.ofMintCbor bytes) }
    | 11 => config := { config with scriptDataHash := some (← EIO.ofExcept (Hash.ofBytes bytes)) }
    | 13 => config := { config with collateral := some (← InputSet.ofCbor bytes) }
    | 14 =>
      let guards ← EIO.ofExcept (children.mapM Credential.ofNative)
      config := { config with guards := some guards }
    | 15 =>
      let network ← match number with
        | 0 => pure Network.testnet
        | 1 => pure Network.mainnet
        | _ => throw (.invalidInput "Unknown native body network")
      config := { config with network := some network }
    | 16 => config := { config with collateralReturn := some (← Output.ofCbor bytes) }
    | 17 => config := { config with totalCollateral := some (← EIO.ofExcept (Lovelace.ofNat number.toNat)) }
    | 18 => config := { config with referenceInputs := some (← InputSet.ofCbor bytes) }
    | 21 => config := { config with treasuryValue := some (← EIO.ofExcept (Lovelace.ofNat number.toNat)) }
    | 22 => config := { config with donation := some (← EIO.ofExcept (Lovelace.ofNat number.toNat)) }
    | _ => throw (.invalidInput "Unknown native body snapshot field")
  return config

-- DEFINITIONS ----------------------------------------------------------------

/-- Parse exactly one body through cardano-c and inspect the bound fields. All
original bytes are retained, including certificates/governance/contextual fields.
Copied spending/reference/collateral sets must pass the uniqueness validator.
-/
def ofCbor (bytes : ByteArray) : EIO Error TransactionBody := do
  let .node additional fee hash _ _ fields ←
    (Internal.componentDecode 11 bytes).adapt (.native "TransactionBody.ofCbor")
  let view ← readConfig fee fields
  let identifier ← EIO.ofExcept (TransactionId.ofBytes hash)
  return ⟨view, additional != 0, bytes, identifier⟩

/-- Construct with native body setters, serialize, then inspect native results.
No witness generation, balancing, script evaluation, or submission is performed.
-/
def create (config : Config) : EIO Error TransactionBody := do
  let fields ← config.toNative
  let bytes ← (Internal.componentEncode 11 fields).adapt (.native "TransactionBody.create")
  ofCbor bytes

/-- Exact original body bytes, or the native encoding produced at construction. -/
def toCbor (body : TransactionBody) : ByteArray := body.cbor

/-- Native BLAKE2b-256 hash of the exact body encoding. -/
def id (body : TransactionBody) : TransactionId := body.identifier

/-- Obtain a reconstruction configuration only when every present native body
field is modeled. Rebuilding can normalize encoding; retain `toCbor` for identity.
-/
def toConfig (body : TransactionBody) : Except Error Config :=
  if body.hasAdditionalFields then
    .error (.invalidInput "Body contains fields not yet represented by Config")
  else if body.view.guards.any List.isEmpty then
    .error (.invalidInput "Native body writer cannot preserve explicitly empty guards")
  else .ok body.view

end TransactionBody
end Cometa
