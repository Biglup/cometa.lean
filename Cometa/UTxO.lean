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

import Cometa.OutputReference
import Cometa.Output

/-! Resolved input/output pairs backed by native UTxO objects. Construction does
not establish that the output exists or is still unspent on a network.
-/

namespace Cometa

-- TYPES ----------------------------------------------------------------------

/-- A native UTxO snapshot containing a reference and its complete resolved output. -/
structure UTxO where
  private mk ::
  /-- Transaction ID and output index. -/
  reference : OutputReference
  /-- Complete checked output returned by native getters. -/
  output : Output
  private cbor : ByteArray

namespace UTxO

-- DEFINITIONS ----------------------------------------------------------------

/-- Parse a native UTxO pair, checking copied reference and output invariants. -/
def ofCbor (bytes : ByteArray) : EIO Error UTxO := do
  let .node _ _ outputBytes _ _ children ←
    (Internal.componentDecode 10 bytes).adapt (.native "UTxO.ofCbor")
  let [input] := children | throw (.invalidInput "Incomplete native UTxO snapshot")
  let reference ← EIO.ofExcept (OutputReference.ofNative input)
  let output ← Output.ofCbor outputBytes
  return ⟨reference, output, bytes⟩

/-- Construct, encode and inspect an actual native UTxO object. -/
def create (reference : OutputReference) (output : Output) : EIO Error UTxO := do
  let fields := Internal.Component.node 0 0 output.toCbor ByteArray.empty "" [reference.toNative]
  let bytes ← (Internal.componentEncode 10 fields).adapt (.native "UTxO.create")
  ofCbor bytes

/-- Exact validated UTxO bytes; an observation has no hidden native effect. -/
def toCbor (utxo : UTxO) : ByteArray := utxo.cbor

end UTxO
end Cometa
