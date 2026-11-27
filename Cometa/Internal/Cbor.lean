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

import Init.Data.ByteArray.Lex

/-! Internal CBOR construction for finite in-memory values. No decoder or ledger
validity claim is provided by these encoding helpers. Domain bounds are checked
by public constructors before unsigned conversion.
-/

namespace Cometa.Internal.Cbor

-- DEFINITIONS ----------------------------------------------------------------

private def header (major : UInt8) (value : UInt64) : ByteArray := Id.run do
  if value < 24 then return ⟨#[major * 32 + value.toUInt8]⟩
  let (marker, width) : UInt8 × Nat :=
    if value ≤ 255 then (24, 1) else if value ≤ 65535 then (25, 2)
    else if value ≤ 4294967295 then (26, 4) else (27, 8)
  let mut result : ByteArray := ⟨#[major * 32 + marker]⟩
  for index in [:width] do
    result := result.push ((value.toNat / 256 ^ (width - index - 1)) % 256).toUInt8
  return result

/-- Shortest CBOR encoding of an unsigned 64-bit integer. -/
def unsigned (value : UInt64) : ByteArray := header 0 value

/-- Definite byte string without a domain-specific size limit. -/
def bytes (value : ByteArray) : ByteArray := header 2 value.size.toUInt64 ++ value

/-- Concatenate an ordered sequence of already encoded CBOR items. -/
def concat (items : List ByteArray) : ByteArray := items.foldl (· ++ ·) ByteArray.empty

/-- Definite array, preserving order and duplicates. -/
def array (items : List ByteArray) : ByteArray :=
  header 4 items.length.toUInt64 ++ concat items

/-- Definite map, preserving supplied order and duplicates. -/
def map (items : List (ByteArray × ByteArray)) : ByteArray :=
  header 5 items.length.toUInt64 ++ concat (items.flatMap fun (key, value) => [key, value])

/-- CBOR tag followed by an encoded item. -/
def tag (number : UInt64) (item : ByteArray) : ByteArray := header 6 number ++ item

/-- Plutus byte strings use chunks no longer than 64 bytes. -/
def boundedBytes (value : ByteArray) : ByteArray :=
  if value.size ≤ 64 then bytes value
  else
    ⟨#[0x5f]⟩ ++ concat ((List.range ((value.size + 63) / 64)).map fun index =>
      bytes (value.extract (index * 64) (min value.size ((index + 1) * 64)))) ++ ⟨#[0xff]⟩

private def magnitude (value : Nat) (result : List UInt8 := []) : List UInt8 :=
  if _h : value = 0 then result
  else magnitude (value / 256) (value.toUInt8 :: result)
termination_by value
decreasing_by exact Nat.div_lt_self (Nat.pos_of_ne_zero _h) (by decide)

/-- Arbitrary signed integer, using chunked positive/negative bignums when needed. -/
def integer (value : Int) : ByteArray :=
  let negative := value < 0
  let amount := if negative then (-value - 1).toNat else value.toNat
  if amount ≤ 18446744073709551615 then
    header (if negative then 1 else 0) amount.toUInt64
  else
    tag (if negative then 3 else 2) (boundedBytes ⟨(magnitude amount).toArray⟩)

/-- Deterministic CBOR map ordering: shorter encoded keys first, then byte order. -/
def canonicalMap (items : List (ByteArray × ByteArray)) : ByteArray :=
  map (items.mergeSort fun left right =>
    if left.1.size == right.1.size then compare left.1 right.1 != .gt
    else left.1.size < right.1.size)

end Cometa.Internal.Cbor
