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

import Cometa

/-! Synthetic, unsigned transaction vectors. These spend a nonexistent zero hash;
no keys, signatures, credentials, or funded-wallet data are included. Hashes were
computed independently with Python hashlib.blake2b(body, digest_size=32).
-/

namespace Tests.TransactionFixtures

-- FIXTURES -------------------------------------------------------------------

/-- CIP-19 enterprise address bytes reused by the synthetic output. -/
def addressHex : String := "609493315cd92eb5d8c4304e67b7e16ae36d61d34502694657811a2c8e"

private def input : String :=
  "825820" ++ String.ofList (List.replicate 64 '0') ++ "00"

private def output : String := "a200581d" ++ addressHex ++ "011a001e8480"

/-- One ordinary input, one 2 ADA output, and a 170000 lovelace fee. -/
def body : String := "a30081" ++ input ++ "0181" ++ output ++ "021a00029810"

/-- Independent hash of the exact body above. -/
def bodyId : String := "0acf273bdc5c4ed46a1aaeb83c45580c8694f6a20af72263abd60810fc6f8c7a"

/-- Canonically encoded output with one native asset, inline datum, and reference script. -/
def richOutput : String :=
  "a400581d" ++ addressHex ++ "01821a001e8480a1581c" ++
  String.ofList (List.replicate 56 '1') ++ "a14361626301" ++
  "028201d81842182a" ++ "03d818582282008200581c" ++
  String.ofList (List.replicate 56 '2')

/-- Body containing the rich output. -/
def richBody : String := "a30081" ++ input ++ "0181" ++ richOutput ++ "021a00029810"

/-- Independent hash of the rich body. -/
def richId : String := "eb008a28122020b433caaf282522c4371af03941ac502ad88ab5a3f45a912341"

/-- Body using a nonminimal unsigned encoding for fee 170000. -/
def nonminimalBody : String :=
  "a30081" ++ input ++ "0181" ++ output ++ "021b0000000000029810"

/-- Independent hash of the nonminimal body, distinct from the canonical body ID. -/
def nonminimalId : String :=
  "e86d6a5627adbfc7c11ffc7a7a58c515c19cc5583c6f9b24867ea53aad9d4b48"

end Tests.TransactionFixtures
