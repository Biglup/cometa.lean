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

import Cometa.Hash
import Cometa.TransactionId
import Cometa.Internal.Component
import Cometa.Internal.Witness

/-! Native verification-key witnesses. Construction checks representation, not
signature validity or spending authority. Verification uses cardano-c's Ed25519
implementation; no private keys are accepted or stored by this API.
-/

namespace Cometa

-- TYPES ----------------------------------------------------------------------

/-- A native witness with copied public key, signature and public-key hash. -/
structure VKeyWitness where
  private mk ::
  /-- The 32-byte Ed25519 verification key. -/
  verificationKey : ByteArray
  /-- The 64-byte Ed25519 signature. -/
  signature : ByteArray
  /-- Checked length of the copied native key. -/
  keySize : verificationKey.size = 32
  /-- Checked length of the copied native signature. -/
  signatureSize : signature.size = 64
  private digest : Hash 28
  private cbor : ByteArray

namespace VKeyWitness

-- DEFINITIONS ----------------------------------------------------------------

/-- Parse exactly one native witness, preserving original bytes. Invalid lengths
are rejected; a well-shaped signature can still fail cryptographic verification.
-/
def ofCbor (bytes : ByteArray) : EIO Error VKeyWitness := do
  let .node _ _ key signature _ children ←
    (Internal.componentDecode 17 bytes).adapt (.native "VKeyWitness.ofCbor")
  let digest ← match children with
    | [.node _ _ hash _ _ _] => EIO.ofExcept (Hash.ofBytes hash)
    | _ => throw (.invalidInput "Invalid native key-witness snapshot")
  if keySize : key.size = 32 then
    if signatureSize : signature.size = 64 then
      return ⟨key, signature, keySize, signatureSize, digest, bytes⟩
    else throw (.invalidInput "Expected a 64-byte signature")
  else throw (.invalidInput "Expected a 32-byte verification key")

/-- Construct through native public-key, signature and witness constructors. -/
def create (verificationKey signature : ByteArray) : EIO Error VKeyWitness := do
  let fields := Internal.Component.node 0 0 verificationKey signature "" []
  let bytes ← (Internal.componentEncode 17 fields).adapt (.native "VKeyWitness.create")
  ofCbor bytes

/-- Exact original or native-produced witness encoding. -/
def toCbor (witness : VKeyWitness) : ByteArray := witness.cbor

/-- Native BLAKE2b-224 public-key hash for matching key credentials. -/
def keyHash (witness : VKeyWitness) : Hash 28 := witness.digest

/-- Key/signature identity, independent of CBOR framing and cached hash. -/
def identity (witness : VKeyWitness) : ByteArray × ByteArray :=
  (witness.verificationKey, witness.signature)

/-- Native Ed25519 verification of exactly the supplied bytes, without hashing.
A false result is a signature failure, distinct from a native parse/allocation error.
-/
def verify (witness : VKeyWitness) (message : ByteArray) : EIO Error Bool :=
  (Internal.vkeyVerify witness.toCbor message).adapt (.native "VKeyWitness.verify")

/-- Verify the signature over the exact 32-byte transaction-body identifier. -/
def verifyTransaction (witness : VKeyWitness) (identifier : TransactionId) : EIO Error Bool :=
  witness.verify identifier.toBytes

instance : BEq VKeyWitness := ⟨fun left right => left.identity == right.identity⟩

-- THEOREMS -------------------------------------------------------------------

/-- Every accepted witness has a 32-byte verification key. -/
theorem verificationKey_size (witness : VKeyWitness) : witness.verificationKey.size = 32 :=
  witness.keySize

/-- Every accepted witness has a 64-byte signature. -/
theorem signature_size (witness : VKeyWitness) : witness.signature.size = 64 := witness.signatureSize

end VKeyWitness
end Cometa
