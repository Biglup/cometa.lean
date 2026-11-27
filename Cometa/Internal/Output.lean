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

/-! Native codec and hashing boundaries. Inputs are borrowed only during a call;
results contain copied bytes and every native object is released before return.
-/

namespace Cometa.Internal

-- FOREIGN IMPORTS ------------------------------------------------------------

/-- Parse one output and return a complete native-reserialized snapshot. -/
@[extern "cometa_lean_output_round_trip"]
opaque outputRoundTrip (bytes : @& ByteArray) : EIO UInt32 ByteArray

/-- Parse exactly one Plutus datum, then hash its exact original bytes with BLAKE2b-256. -/
@[extern "cometa_lean_datum_hash"]
opaque datumHash (bytes : @& ByteArray) : EIO UInt32 ByteArray

/-- Parse a constructed script envelope and copy its native 28-byte script hash. -/
@[extern "cometa_lean_script_hash"]
opaque scriptHash (bytes : @& ByteArray) : EIO UInt32 ByteArray

end Cometa.Internal
