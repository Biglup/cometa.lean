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

import Cometa.Asset
import Cometa.Credential
import Cometa.Internal.Cbor
import Cometa.Internal.Output

/-! Typed native-script trees and versioned Plutus program bytes. Script hashing
uses the actual native implementation. Construction does not execute a program
or assert that its language is activated on a selected network.
-/

namespace Cometa

-- TYPES ----------------------------------------------------------------------

/-- Every native script constructor supported by the pinned baseline. -/
inductive NativeScript where
  /-- Require a witness for a 28-byte verification-key hash. -/
  | signature (keyHash : Hash 28)
  /-- Require every child script. An empty list is satisfied. -/
  | all (scripts : List NativeScript)
  /-- Require at least one child script. An empty list is unsatisfied. -/
  | any (scripts : List NativeScript)
  /-- Require at least the given number of children. Thresholds above the child
  count describe unsatisfiable scripts; construction does not reject them.
  -/
  | atLeast (required : UInt64) (scripts : List NativeScript)
  /-- Inclusive validity lower bound, in slots. -/
  | invalidBefore (slot : UInt64)
  /-- Exclusive validity upper bound, in slots. -/
  | invalidAfter (slot : UInt64)
  /-- Require a key/script credential in transaction guards (Dijkstra onwards). -/
  | requireGuard (credential : Credential)

/-- Declared Plutus language. Availability depends on ledger era/protocol context. -/
inductive PlutusVersion where
  /-- Plutus V1. -/
  | v1
  /-- Plutus V2. -/
  | v2
  /-- Plutus V3. -/
  | v3
  /-- Plutus V4, supported by the pinned native baseline. -/
  | v4
  deriving DecidableEq, BEq

/-- Semantic view of a constructed or imported script. -/
inductive ScriptView where
  /-- Typed native-script tree. -/
  | native (script : NativeScript)
  /-- Declared language and nonempty opaque compiled program bytes. -/
  | plutus (version : PlutusVersion) (program : ByteArray)

/-- Validated script envelope and its native-computed policy hash. -/
structure Script where
  private mk ::
  private contents : ScriptView
  private cbor : ByteArray
  private digest : PolicyId

namespace NativeScript

-- DEFINITIONS ----------------------------------------------------------------

/-- Serialize a native-script tree without its outer language envelope. -/
def toCbor : NativeScript → ByteArray
  | .signature hash => Internal.Cbor.array [Internal.Cbor.unsigned 0, Internal.Cbor.bytes hash.bytes]
  | .all scripts => Internal.Cbor.array [Internal.Cbor.unsigned 1, Internal.Cbor.array (scripts.map toCbor)]
  | .any scripts => Internal.Cbor.array [Internal.Cbor.unsigned 2, Internal.Cbor.array (scripts.map toCbor)]
  | .atLeast required scripts => Internal.Cbor.array [Internal.Cbor.unsigned 3,
      Internal.Cbor.unsigned required, Internal.Cbor.array (scripts.map toCbor)]
  | .invalidBefore slot => Internal.Cbor.array [Internal.Cbor.unsigned 4, Internal.Cbor.unsigned slot]
  | .invalidAfter slot => Internal.Cbor.array [Internal.Cbor.unsigned 5, Internal.Cbor.unsigned slot]
  | .requireGuard credential => Internal.Cbor.array [Internal.Cbor.unsigned 6, credential.toCbor]

end NativeScript

private def nativeFromTerm : Internal.Cbor.Term → Except Error NativeScript
  | .array [.unsigned 0, bytes] => do return .signature (← Hash.ofBytes (← bytes.asBytes))
  | .array [.unsigned 1, .array children] => do return .all (← children.mapM nativeFromTerm)
  | .array [.unsigned 2, .array children] => do return .any (← children.mapM nativeFromTerm)
  | .array [.unsigned 3, .unsigned required, .array children] =>
    do return .atLeast required (← children.mapM nativeFromTerm)
  | .array [.unsigned 4, .unsigned slot] => .ok (.invalidBefore slot)
  | .array [.unsigned 5, .unsigned slot] => .ok (.invalidAfter slot)
  | .array [.unsigned 6, credential] => do return .requireGuard (← Internal.credentialFromTerm credential)
  | _ => .error (.invalidInput "Invalid native script tag, arity or field")

namespace NativeScript

/-- Decode a native-script semantic tree, including guard alternative 6. Re-encoding
may normalize it; use Script.ofCbor to preserve an imported envelope and hash.
-/
def ofCbor (bytes : ByteArray) : Except Error NativeScript := do
  nativeFromTerm (← Internal.Cbor.decode bytes)

end NativeScript

namespace PlutusVersion

/-- Script-envelope language tag and hash discriminator, from 1 through 4. -/
def tag : PlutusVersion → UInt64
  | .v1 => 1
  | .v2 => 2
  | .v3 => 3
  | .v4 => 4

end PlutusVersion

namespace Script

private def create (view : ScriptView) (cbor : ByteArray) : EIO Error Script := do
  let digest ← (Internal.scriptHash cbor).adapt (.native "Script.create")
  return ⟨view, cbor, ← EIO.ofExcept (PolicyId.ofBytes digest)⟩

/-- Validate and hash a typed native script through the native implementation. -/
def ofNative (script : NativeScript) : EIO Error Script :=
  create (.native script) (Internal.Cbor.array [Internal.Cbor.unsigned 0, script.toCbor])

/-- Wrap nonempty compiled bytes without executing or Flat-decoding the program.
The language is part of the hash; unknown versions cannot be constructed.
-/
def ofPlutus (version : PlutusVersion) (program : ByteArray) : EIO Error Script := do
  if program.isEmpty then throw (.invalidInput "A Plutus program must be nonempty")
  create (.plutus version program)
    (Internal.Cbor.array [Internal.Cbor.unsigned version.tag, Internal.Cbor.bytes program])

/-- Decode exactly one native/Plutus script envelope, retaining every input byte.
Native trees retain semantics; Plutus programs retain their unwrapped bytes.
Unknown languages, malformed trees, empty programs and trailing data are rejected.
Imported native-script payload bytes determine their hash, including nonminimal
encodings. The enclosing language-array encoding itself is not hash input.
-/
def ofCbor (bytes : ByteArray) : EIO Error Script := do
  let term ← EIO.ofExcept (Internal.Cbor.decode bytes)
  let .array [.unsigned language, payload] := term
    | throw (.invalidInput "A script envelope must contain language and payload")
  if language == 0 then
    let tree ← EIO.ofExcept (nativeFromTerm payload)
    create (.native tree) bytes
  else
    let version ← match language with
      | 1 => pure PlutusVersion.v1
      | 2 => pure PlutusVersion.v2
      | 3 => pure PlutusVersion.v3
      | 4 => pure PlutusVersion.v4
      | _ => throw (.invalidInput "Unknown Plutus language")
    let program ← EIO.ofExcept payload.asBytes
    if program.isEmpty then throw (.invalidInput "A Plutus program must be nonempty")
    create (.plutus version program) bytes

/-- Semantic view without exposing a mutable native handle. -/
def view (script : Script) : ScriptView := script.contents

/-- Complete `[language, script]` envelope, suitable for reference-script embedding. -/
def toCbor (script : Script) : ByteArray := script.cbor

/-- Native-computed script hash, including the language discriminator. -/
def hash (script : Script) : PolicyId := script.digest

end Script
end Cometa
