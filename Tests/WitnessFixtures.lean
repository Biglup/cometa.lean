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

/-! Public signature fixtures generated independently with Python cryptography
from the first two public Ed25519 test vectors in the pinned native test corpus.
Only public keys/signatures are stored here; no wallet or production key is used.
-/

namespace Tests.WitnessFixtures

-- FIXTURES -------------------------------------------------------------------

/-- First public test verification key. -/
def firstKey : String :=
  "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"

/-- Second public test verification key. -/
def secondKey : String :=
  "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"

/-- Independent BLAKE2b-224 digest of the first public key. -/
def keyHash : String :=
  "35dedd2982a03cf39e7dce03c839994ffdec2ec6b04f1cf2d40e61a3"

/-- First witness over TransactionFixtures.bodyId. -/
def first : String :=
  "825820d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a5840dd6a7b2a0c7ead1eba5766bc97c9d3d321234b6142d754e9e4792febb6af2cb9b569806c7deb73ee7361b1d5fb0935917b13f8ca5519558ad01e2020b9909d0c"

/-- Second witness over TransactionFixtures.bodyId. -/
def second : String :=
  "8258203d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c58406077b670b7fc2e662057cb791e9fd89622f885fab79ade9e6372235fc2551deda6afa5498abb85a66f3e8b3d20da7c1691be5e31547aaa6258dea535bfa8e903"

/-- First public key signs the exact nonminimal transaction body. -/
def nonminimal : String :=
  "825820d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a584065094683d62c9d50af1d08439ad1f7d170e88c3a70317e8545d96a9b379090e965742f86eb35df82eea4e3c1d28e6d46bc754304a713875fd9a1cf80a1c61607"

/-- Synthetic auxiliary payload. -/
def auxiliary : String :=
  "d90103a100a10001"

/-- Synthetic body containing the auxiliary-data commitment. -/
def committedBody : String :=
  "a4008001800200075820eb1f31a1879ea06c7517fa18f751d1713624fb1ddf1c5435bdc2e7aac0c0ab66"

/-- First public key signs the body with the auxiliary commitment. -/
def committedWitness : String :=
  "825820d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a5840d56bad9148452b01e6976bfe5556cd27b9ebfb2e31ef13ff81c9211cf8d25c6aff31923fb4e152d6fb47c7cc752fdd9a4f6c52741934ff7894ca04c4ce6f250d"

/-- Published empty-message signature vector, independently regenerated. -/
def emptyMessageWitness : String :=
  "825820d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a5840e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"

end Tests.WitnessFixtures
