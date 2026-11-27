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

/-! Public CBOR vectors and independent BLAKE2b digests computed with Python
hashlib. These are synthetic data/program bytes, not wallet material.
-/

namespace Tests.OutputFixtures

-- FIXTURES -------------------------------------------------------------------

/-- Typed data, expected CBOR, and independent 32-byte datum hash. -/
def datums : List (Cometa.PlutusData × String × String) := [
  (.integer 0, "00",
    "03170a2e7597b7b7e3d84c05391d139a62b157e78786d8c082f29dcf4c111314"),
  (.integer 23, "17",
    "dfff88be5df71a1e88b76d0f5a2449edb77d855b19b3824915bcdf9fc1311823"),
  (.integer 24, "1818",
    "df5078aee07dd171a343fb99d5fc1b5462fb3c94d82bf72dc1b77d9c0aceec29"),
  (.integer (-1), "20",
    "ae85d245a3d00bfde01f59f3c4fe0b4bfae1cb37e9cf91929eadcea4985711de"),
  (.integer (-25), "3818",
    "627460951005a4a9881182a8a32015b1dc85d5ee6f31e968b5b375115281e07a"),
  (.integer 18446744073709551615, "1bffffffffffffffff",
    "3fac877e3f1eaefb3cbb71eb8d49248b51571fd18dc02e74f464f038eb734935"),
  (.integer 18446744073709551616, "c249010000000000000000",
    "0b854352f6a4c02db6f13ac878a41f0b11f54950ad9b88170fb509c916ff0a71"),
  (.integer (-18446744073709551617), "c349010000000000000000",
    "42e2692b0e46ba0dc699ee2f1aa07e1bffb800c35c7b138ddb756d8bf998bc89"),
  (.constr 0 [], "d87980",
    "923918e403bf43c34b4ef6b48eb2ee04babed17320d8d1b9ff9ad086e86f44ec"),
  (.constr 6 [.integer 42], "d87f81182a",
    "eb74bd6ef2726b93c680508993ec3174e6c841f6b0c3a6a0d8d5a5df6787d810"),
  (.constr 7 [], "d9050080",
    "357ea89304163aa90e1bde5c87f453b082758b3268759b9d7ec41f8c7f971049"),
  (.constr 127 [], "d9057880",
    "f71845a17bc13e47607d4851644515047e2de0f39906099dd5b9991a3ec30cf1"),
  (.constr 128 [], "d86682188080",
    "e4886280ddea3623dfcce52c34b42d69d7932b6967798a1819442c6d9532c175"),
  (.constr 18446744073709551615 [], "d866821bffffffffffffffff80",
    "664c55e746b17540732868b76496a7ba4966e508f55b80a755649f68980ac51b"),
  (.list [.integer 1, .list [], .map []], "830180a0",
    "8402de8380b3cc333bb596fafac07a3b381110c9598aeb052b96ee19bdcc7654"),
  (.map [(.integer 1, .integer 0), (.integer 1, .integer 2)], "a201000102",
    "1a96916041fb02aed39d9b47c31d921f81c5b690fe30526a1dae3795456a7328")]

/-- Version and independent 28-byte hash of language tag followed by deadbeef. -/
def plutusHashes : List (Cometa.PlutusVersion × String) := [
  (.v1, "25bb4d267b8e9e68bc619d2cce69ae78e239e4f60623a59db077080f"),
  (.v2, "8dd97be9e6716b05f2cb163a45fd7663fe5ea9b8f4f319b9cfba5ebf"),
  (.v3, "2c492f3f2c90a40274051772c1008e60d9cde2ef84a8a37dbbddf8a9"),
  (.v4, "c6901fcdf41b26c0567e99e74431b7e65b21ad3852f4a91983df4aa8")]

/-- Independent hash of a 65-byte Plutus byte string with the required chunking. -/
def chunkedHash : String := "3c233c9351e09570389d32d74fd7e3de3efea97fa22b98163c37f176210e8156"

/-- Independent hash of a native signature script with a 28-byte 0x22 key hash. -/
def nativeSignatureHash : String := "6d88a61d44faea8672dd738057445517c8cb5fbcece60610df803b85"

end Tests.OutputFixtures
