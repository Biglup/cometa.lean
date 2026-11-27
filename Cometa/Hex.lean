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

import Cometa.Error

/-! Strict hexadecimal conversion for public binary data. No whitespace, prefixes,
or separators are accepted. Empty text represents an empty byte array.
-/

namespace Cometa.Hex

-- DEFINITIONS ----------------------------------------------------------------

private def nibble (character : Char) : Option UInt8 :=
  if '0' ≤ character && character ≤ '9' then
    some (character.toNat - '0'.toNat).toUInt8
  else if 'a' ≤ character && character ≤ 'f' then
    some (character.toNat - 'a'.toNat + 10).toUInt8
  else if 'A' ≤ character && character ≤ 'F' then
    some (character.toNat - 'A'.toNat + 10).toUInt8
  else
    none

private def decode (characters : List Char) (bytes : ByteArray) : Except Error ByteArray :=
  match characters with
  | [] => .ok bytes
  | [_] => .error (.invalidInput "Hexadecimal text must have an even length")
  | high :: low :: rest => do
    let some high := nibble high
      | throw (.invalidInput "Invalid hexadecimal character")
    let some low := nibble low
      | throw (.invalidInput "Invalid hexadecimal character")
    decode rest (bytes.push (high * 16 + low))

/-- Decode ASCII hexadecimal, accepting either letter case and rejecting all other text.
Errors never include the supplied text. Empty input succeeds with empty bytes.
-/
def toBytes (text : String) : Except Error ByteArray :=
  decode text.toList ByteArray.empty

private def digit (value : Nat) : Char :=
  Char.ofNat (if value < 10 then '0'.toNat + value else 'a'.toNat + value - 10)

/-- Encode bytes as lowercase hexadecimal with two digits per byte and no prefix. -/
def ofBytes (bytes : ByteArray) : String :=
  String.ofList (bytes.data.toList.flatMap fun byte =>
    [digit (byte.toNat / 16), digit (byte.toNat % 16)])

end Cometa.Hex
