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

/-- Copy native-script fields for the corresponding C constructors. -/
def toNative : NativeScript → Internal.Component
  | .signature hash => .node 0 0 hash.bytes ByteArray.empty "" []
  | .all scripts => .node 1 0 ByteArray.empty ByteArray.empty "" (scripts.map toNative)
  | .any scripts => .node 2 0 ByteArray.empty ByteArray.empty "" (scripts.map toNative)
  | .atLeast required scripts => .node 3 required ByteArray.empty ByteArray.empty "" (scripts.map toNative)
  | .invalidBefore slot => .node 4 slot ByteArray.empty ByteArray.empty "" []
  | .invalidAfter slot => .node 5 slot ByteArray.empty ByteArray.empty "" []
  | .requireGuard credential => .node 6 0 ByteArray.empty ByteArray.empty "" [credential.toNative]

/-- Validate a semantic snapshot from native script getters. -/
def ofNative : Internal.Component → Except Error NativeScript
  | .node kind number bytes _ _ children => do
    match kind with
    | 0 => return .signature (← Hash.ofBytes bytes)
    | 1 => return .all (← children.mapM ofNative)
    | 2 => return .any (← children.mapM ofNative)
    | 3 => return .atLeast number (← children.mapM ofNative)
    | 4 => return .invalidBefore number
    | 5 => return .invalidAfter number
    | 6 =>
      let [credential] := children | throw (.invalidInput "Missing native guard credential")
      return .requireGuard (← Credential.ofNative credential)
    | _ => throw (.invalidInput "Unknown native script kind")

/-- Construct and encode a native-script tree through cardano-c. -/
def toCbor (script : NativeScript) : EIO Error ByteArray :=
  (Internal.componentEncode 4 script.toNative).adapt (.native "NativeScript.toCbor")

/-- Parse a tree using the native script reader and getters. -/
def ofCbor (bytes : ByteArray) : EIO Error NativeScript := do
  let fields ← (Internal.componentDecode 4 bytes).adapt (.native "NativeScript.ofCbor")
  EIO.ofExcept (ofNative fields)

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

/-- Construct, encode and hash a typed script through native objects. -/
def ofNative (script : NativeScript) : EIO Error Script := do
  let fields := Internal.Component.node 0 0 ByteArray.empty ByteArray.empty "" [script.toNative]
  let cbor ← (Internal.componentEncode 5 fields).adapt (.native "Script.ofNative")
  create (.native script) cbor

/-- Construct a native Plutus script wrapper without executing its program. -/
def ofPlutus (version : PlutusVersion) (program : ByteArray) : EIO Error Script := do
  if program.isEmpty then throw (.invalidInput "A Plutus program must be nonempty")
  let fields := Internal.Component.node version.tag 0 program ByteArray.empty "" []
  let cbor ← (Internal.componentEncode 5 fields).adapt (.native "Script.ofPlutus")
  create (.plutus version program) cbor

/-- Parse and hash through cardano-c, retaining the exact imported envelope.
Semantic fields come from native getters. Re-encoding a native-script tree may
change its payload bytes and hash; inspecting `view` leaves identity unchanged.
-/
def ofCbor (bytes : ByteArray) : EIO Error Script := do
  let .node language _ program _ _ children ←
    (Internal.componentDecode 5 bytes).adapt (.native "Script.ofCbor")
  if language == 0 then
    let [tree] := children | throw (.invalidInput "Missing native script tree")
    create (.native (← EIO.ofExcept (NativeScript.ofNative tree))) bytes
  else
    let version ← match language with
      | 1 => pure PlutusVersion.v1
      | 2 => pure PlutusVersion.v2
      | 3 => pure PlutusVersion.v3
      | 4 => pure PlutusVersion.v4
      | _ => throw (.invalidInput "Unknown native Plutus language")
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
