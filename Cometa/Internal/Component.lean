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

/-! Internal copied-field transport for native component objects. This is not a
CBOR syntax tree: tags identify native object alternatives, numbers carry native
scalar fields, and children contain snapshots from native getters. No handles
escape an FFI call. See cbits/cometa_components.h for the audited layout.
-/

namespace Cometa.Internal

-- TYPES ----------------------------------------------------------------------

/-- Internal transport node. Unused fields are empty; public wrappers check shape. -/
inductive Component where
  /-- Native alternative, scalar, two byte buffers, decimal integer, and children. -/
  | node (kind number : UInt64) (bytes extra : ByteArray) (text : String)
      (children : List Component)

-- FOREIGN IMPORTS ------------------------------------------------------------

/-- Construct native objects and serialize with their native writer.
Families: 0 credential, 1 value, 2 mint, 3 data, 4 native script, 5 script, 6 output, 7 legacy output (encoding only),
8 input, 9 input set, 10 UTxO, 11 transaction body, 12 reward account (raw address
bytes rather than CBOR), 13 withdrawal map, 14 metadatum, 15 metadata,
16 auxiliary data, 17 verification-key witness, 18 key-witness set.
-/
@[extern "cometa_lean_component_encode"]
opaque componentEncode (family : UInt8) (fields : @& Component) : EIO UInt32 ByteArray

/-- Parse exactly one native object and copy its getter results into Lean storage. -/
@[extern "cometa_lean_component_decode"]
opaque componentDecode (family : UInt8) (bytes : @& ByteArray) : EIO UInt32 Component

end Cometa.Internal
