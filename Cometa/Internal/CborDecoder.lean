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
import Cometa.Internal.Cbor

/-! Total CBOR decoding for transaction component schemas. Map order/duplicates
and byte-string chunks are retained for schema-specific validation. Text, floats,
and application-specific simple values are outside this component decoder.
-/

namespace Cometa.Internal.Cbor

-- TYPES ----------------------------------------------------------------------

/-- Decoded structure; integers retain their unsigned CBOR argument. -/
inductive Term where
  /-- Unsigned integer. -/
  | unsigned (value : UInt64)
  /-- Negative integer represented as minus one minus the argument. -/
  | negative (argument : UInt64)
  /-- Ordered definite byte chunks; an indefinite byte string may have no chunks. -/
  | bytes (chunks : List ByteArray)
  /-- Ordered array items. -/
  | array (items : List Term)
  /-- Ordered map entries, retaining duplicates for domain-specific checks. -/
  | map (entries : List (Term × Term))
  /-- Tagged item. -/
  | tag (number : UInt64) (item : Term)
  /-- Boolean, null, or undefined (CBOR simple values 20 through 23). -/
  | simple (value : UInt8)

private structure Header where
  major : Nat
  argument : Option UInt64

-- READER ---------------------------------------------------------------------

private def malformed (message : String) : Except Error α :=
  .error (.invalidInput ("Invalid CBOR: " ++ message))

private def byteAt (bytes : ByteArray) (position : Nat) : Except Error UInt8 :=
  match bytes[position]? with
  | some byte => .ok byte
  | none => malformed "truncated item"

private def readHeader (bytes : ByteArray) (position : Nat) : Except Error (Header × Nat) := do
  let first ← byteAt bytes position
  let major := first.toNat / 32
  let additional := first.toNat % 32
  if additional < 24 then return (⟨major, some additional.toUInt64⟩, position + 1)
  if additional == 31 then return (⟨major, none⟩, position + 1)
  if additional > 27 then malformed "reserved additional information"
  else
    let mut cursor := position + 1
    let mut argument : UInt64 := 0
    for _ in [:2 ^ (additional - 24)] do
      let byte ← byteAt bytes cursor
      argument := argument * 256 + byte.toUInt64
      cursor := cursor + 1
    return (⟨major, some argument⟩, cursor)

private def readBytes (bytes : ByteArray) (position : Nat) (length : UInt64) :
    Except Error (ByteArray × Nat) := do
  let ending := position + length.toNat
  if ending > bytes.size then malformed "truncated byte string"
  else return (bytes.extract position ending, ending)

private def readChunks (bytes : ByteArray) (position : Nat) :
    Except Error (List ByteArray × Nat) := do
  let mut cursor := position
  let mut chunks := []
  for _ in [:bytes.size - position + 1] do
    if bytes[cursor]? == some 0xff then return (chunks.reverse, cursor + 1)
    let (header, next) ← readHeader bytes cursor
    let some length := header.argument | malformed "nested indefinite byte string"
    if header.major != 2 then malformed "non-byte chunk in byte string"
    else
      let (chunk, ending) ← readBytes bytes next length
      chunks := chunk :: chunks
      cursor := ending
  malformed "missing byte-string break"

private def readItems (readNext : Nat → Except Error (Term × Nat))
    (bytes : ByteArray) (position : Nat) (count : Option Nat) :
    Except Error (List Term × Nat) := do
  let limit := count.getD (bytes.size - position + 1)
  if count.isSome && limit > bytes.size - position then malformed "container length exceeds remaining bytes"
  else
    let mut cursor := position
    let mut items := []
    for _ in [:limit] do
      if count.isNone && bytes[cursor]? == some 0xff then return (items.reverse, cursor + 1)
      let (item, ending) ← readNext cursor
      items := item :: items
      cursor := ending
    if count.isNone then malformed "missing container break"
    else return (items.reverse, cursor)

private def pairs : List Term → Except Error (List (Term × Term))
  | [] => .ok []
  | key :: value :: rest => do return (key, value) :: (← pairs rest)
  | [_] => malformed "map key has no value"

private def readTerm (bytes : ByteArray) : Nat → Nat → Except Error (Term × Nat)
  | 0, _ => malformed "nesting exceeds input byte count"
  | fuel + 1, position => do
    let (header, cursor) ← readHeader bytes position
    match header.major, header.argument with
    | 0, some value => return (.unsigned value, cursor)
    | 1, some value => return (.negative value, cursor)
    | 2, some length =>
      let (chunk, ending) ← readBytes bytes cursor length
      return (.bytes [chunk], ending)
    | 2, none =>
      let (chunks, ending) ← readChunks bytes cursor
      return (.bytes chunks, ending)
    | 4, count =>
      let (items, ending) ← readItems (readTerm bytes fuel) bytes cursor (count.map UInt64.toNat)
      return (.array items, ending)
    | 5, count =>
      let (items, ending) ← readItems (readTerm bytes fuel) bytes cursor (count.map fun n => n.toNat * 2)
      return (.map (← pairs items), ending)
    | 6, some number =>
      let (item, ending) ← readTerm bytes fuel cursor
      return (.tag number item, ending)
    | 7, some value =>
      if cursor == position + 1 && 20 ≤ value && value ≤ 23 then return (.simple value.toUInt8, cursor)
      else malformed "unsupported simple value or float"
    | _, _ => malformed "unsupported item or unexpected break"

-- SCHEMA HELPERS -------------------------------------------------------------

/-- Decode exactly one complete component, accepting definite/indefinite containers
and nonminimal integer widths. Fuel is derived from input size, not a protocol
nesting restriction. Trailing bytes and malformed breaks are rejected.
-/
def decode (bytes : ByteArray) : Except Error Term := do
  let (term, ending) ← readTerm bytes (bytes.size + 1) 0
  if ending != bytes.size then malformed "trailing bytes"
  else return term

/-- Read an unsigned integer without coercing negative integers or tagged bignums. -/
def Term.asUnsigned : Term → Except Error UInt64
  | .unsigned value => .ok value
  | _ => malformed "expected unsigned integer"

/-- Read a signed 64-bit quantity; wider and tagged quantities are rejected. -/
def Term.asSigned64 : Term → Except Error Int
  | .unsigned value =>
    if value ≤ 9223372036854775807 then .ok value.toNat
    else malformed "quantity exceeds signed 64-bit limit"
  | .negative value =>
    if value ≤ 9223372036854775807 then .ok (-Int.ofNat value.toNat - 1)
    else malformed "quantity below signed 64-bit limit"
  | _ => malformed "expected signed integer quantity"

/-- Concatenate a byte string's chunks, optionally checking each chunk's size. -/
def Term.asBytes (term : Term) (maximumChunk : Option Nat := none) : Except Error ByteArray := do
  let .bytes chunks := term | malformed "expected byte string"
  if let some maximum := maximumChunk then
    if chunks.any (fun chunk => chunk.size > maximum) then
      malformed "byte chunk exceeds schema limit"
    else return concat chunks
  else return concat chunks

/-- Extract ordered map pairs without normalizing their keys. -/
def Term.asMap : Term → Except Error (List (Term × Term))
  | .map entries => .ok entries
  | _ => malformed "expected map"

/-- Extract the byte payload of a tag-24 embedded CBOR item. -/
def Term.asEmbedded : Term → Except Error ByteArray
  | .tag 24 item => item.asBytes
  | _ => malformed "expected tag-24 embedded CBOR"

end Cometa.Internal.Cbor
