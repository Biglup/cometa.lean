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

/-! Native address entry points. Not part of the supported public API.

Each call returns copied bytes and text; native references never escape the call.
The native error payload is a boxed `UInt32`, not an `IO.Error` object.
-/

namespace Cometa.Internal

-- FOREIGN IMPORTS ------------------------------------------------------------

/-- Parse borrowed UTF-8 text and return a Lean-owned address snapshot. -/
@[extern "cometa_lean_address_from_text"]
opaque addressFromText (text : @& String) : EIO UInt32 (ByteArray × String)

/-- Parse borrowed serialized bytes and return a Lean-owned address snapshot. -/
@[extern "cometa_lean_address_from_bytes"]
opaque addressFromBytes (bytes : @& ByteArray) : EIO UInt32 (ByteArray × String)

/-- Read the linked native library version. -/
@[extern "cometa_lean_native_version"]
opaque nativeVersion : BaseIO String

end Cometa.Internal
