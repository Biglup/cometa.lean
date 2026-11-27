<!--
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
-->

# Development

## Build and test

Use Lean **4.36.0**, Python **3.12+**, and a C11 compiler. The initial locally
validated platform is Linux x86_64 with glibc 2.33 or newer. Native archive pins are
also available for Linux ARM64 and macOS; availability is not a tested-platform claim.
Windows packaging has not been implemented.

```sh
lake build cometaTests inspectAddress inspectTransaction buildOutput buildTransaction withdrawRewards
lake test
lake lean Tests/Invariants.lean
lake env leanchecker Cometa.Plan
lake env leanchecker Cometa.TransactionId
lake env leanchecker Cometa.Value
lake env leanchecker Cometa.Output
lake env leanchecker Cometa.InputSet
lake env leanchecker Cometa.Withdrawals
lake exe inspectTransaction Examples/transaction.cbor.hex
python3 scripts/check-source.py
python3 -m unittest discover -s Tests/Packaging -v
python3 scripts/check-consumer.py
clang-format-18 --dry-run --Werror cbits/cometa_lean.c cbits/cometa_components.h cbits/cometa_transaction_build.h cbits/cometa_withdrawals.h
```

Lake runs native preparation before compiling the adapter. It downloads cardano-c
**2.0.0-rc.7**, verifies the archive SHA256, and checks the cached library and headers
on later builds. Concurrent builds serialize installation through a package-local
lock; a failed download or verification leaves the previous installation intact.

For offline builds, set `COMETA_NATIVE_ARCHIVE=/path/to/platform-archive.tar.gz`.
The same checksum verification applies. `lake clean` is safe: the next build
prepares missing native files automatically. No native files or toolchain binaries
belong in Git. The Python setup command remains available for explicit preparation.

The consumer check copies source into a fresh directory, excluding all caches.
Pass `--archive .release/cometa-VERSION.tar.gz` to test an actual release archive.
It never runs native setup itself; successful compilation must establish that
Lake resolved the native build dependency.

Run executables with `lake exe` (or `lake env`), which supplies the shared-library
search paths. The adapter links cardano-c directly; consumers load that dependency
at runtime rather than relinking it against Lean's older Linux glibc sysroot.
Use `lake lean Tests/Invariants.lean` for interpreter checks; bare `lake env lean`
does not load Lake's per-file native dependency setup.
Standalone deployment must bundle the shared libraries and configure their loader
paths; the build directory is not a portable binary distribution.

On Linux, check repeated native success/error paths with:

```sh
lake env valgrind --leak-check=full --errors-for-leak-kinds=definite \
  --error-exitcode=99 .lake/build/bin/cometaTests
```

Lean's runtime may retain process/thread allocations at exit. Inspect the report;
do not equate runtime allocations with proven native leaks or suppress errors broadly.

## API documentation

Public contracts live beside the code in Lean doc comments. Build the reference
with the separately pinned doc-gen4 project so consumers do not depend on it:

```sh
python3 scripts/build-docs.py
python3 -m http.server --directory docbuild/.lake/build/doc 8000
```

The helper generates local source links, then rewrites Cometa source anchors to
the public repository at the current commit. It never asks Git for remote URLs
or edits the user's Git configuration. Release
packaging rejects credential patterns and local source links. Only committed code
has valid GitHub source links; no hosted documentation deployment is claimed.

## Native boundary and provenance

Native revision: `a6f659d780f17b60ebafa170af919cca8173df09` (cardano-c v2.0.0-rc.7).
The first adapter audits `lib/src/address/address.c` and
`lib/include/cardano/address/address.h` at that revision. The `from_*` functions
transfer an address reference; `get_bytes` and `get_string` borrow buffers. The
adapter copies both buffers and unrefs the address before returning, including
cleanup of any non-null address on errors. No native pointer is stored in Lean.

Lean 4.36 removes the world argument from these compiled extern signatures.
`BaseIO String` returns the string directly; `EIO UInt32 (ByteArray × String)`
returns an IO-result object with either a boxed error code or an owned pair.
Check generated declarations in `.lake/build/ir/Cometa/Internal/Address.c` after
any toolchain change. `@&` parameters remain borrowed, not consumed by the adapter.

The test address strings are CIP-19 vectors, also used in cardano-c's Apache-2.0
address tests and Cometa.hs `test/Fixtures/Address.hs`. The native snapshot above
fixes their provenance. They are public test addresses, not funded-wallet material.

### Transaction snapshot audit

The transaction adapter audits `lib/src/transaction/transaction.c`,
`lib/src/transaction_body/{transaction_body,transaction_input,transaction_input_set,
transaction_output,transaction_output_list,value}.c`, and
`lib/src/collections/array.c` at the same pinned revision. The parser caches the
original body bytes; `cardano_transaction_get_id` hashes that cache. Cometa never
clears it and retains the original full transaction bytes in Lean. Output CBOR
is separately reserialized and may normalize framing.

Body, collection, input/output, address/value, and hash getters acquire references.
Collection `get` calls use `cardano_array_get`, which also increments its element's
reference count. Each acquired reference is released on success and error paths.
Partially populated Lean arrays are decremented on failure. Native buffers are
copied before their owners are released. The input parser sorts by hash/index
and retains duplicates; the output list preserves order.

`RawTransaction` uses right-associated `Prod` values, with boxed UInt64/Bool fields
and owned arrays of products. The generated declarations and product projections
in `.lake/build/ir/Cometa/Transaction.c` confirm a borrowed byte-array argument,
no world argument, and an IO-result return. Numeric projections unbox UInt64;
no native scalar struct-layout assumptions are used at this boundary.

The native value parser reads an unsigned 64-bit coin into signed storage. The
adapter casts it back to uint64, matching the native writer, and tests the maximum
value to prevent sign extension/truncation errors. This is a representation bound,
not a ledger supply or output-validity claim.

`Tests/TransactionFixtures.lean` defines synthetic unsigned CBOR vectors. Their
expected transaction IDs were calculated independently with Python's
`hashlib.blake2b(bytes.fromhex(body), digest_size=32).hexdigest()`. The fixtures
exercise historical/mempool/block and indefinite framing, nonminimal body bytes,
and an asset, inline datum, and reference script. The example fixture has one
2 ADA output, a 170000 lovelace fee, and a nonexistent all-zero input. No wallet
secrets or live transaction data are needed. The suite also checks every proper
byte prefix of the basic transaction, trailing data, collection ordering,
collateral exclusion, 64-bit bounds, and repeated native allocation paths.

### Output construction and checked native results

`Cometa.Value` keeps signed intermediate quantities unbounded. Only output and
mint encodings impose their respective native bounds. Addition is modeled by a
finite sequence of signed entries; observations aggregate duplicates, and zero
aggregates disappear. This representation keeps the quantity law independent of
map normalization. Native constructors receive the checked quantities; native
map writers choose policy/name ordering. Lean contains no production CBOR codec.

The new audit covers `lib/src/assets/asset_name_map.c`,
`lib/src/plutus_data/plutus_data.c`, `lib/src/scripts/script.c`, the native-script
and Plutus V1–V4 implementations, and the existing output/value codecs. Native
script thresholds use `size_t`; the public UInt64 range matches the supported
64-bit platforms. Hash getters return owned references. Datum hashing consumes
exact original bytes after native parsing, including nonminimal encodings.
The pinned reader accepts oversized byte leaves; parsing is not ledger validation.

The three externs in `Cometa.Internal.Output` borrow a byte array and return
`EIO UInt32 ByteArray`. Generated C in the Script, PlutusData and Output modules
confirms a single borrowed argument, no world argument, and the standard IO-result
layout. Readers, writers, parsed data/scripts/outputs and hashes are unreferenced
on every return path. All returned bytes are copied into Lean ownership.

`Output.checkNativeEncoding` calls the actual output codec and compares its result
with the cached native construction encoding. Success returns a subtype carrying equality
for that observed result. The proof does not assert universal correctness of the
C codec, script execution, minimum ada, or ledger acceptance. Value bounds and the
payment-header property have separate model proofs. Provider/evaluator/selector
instances and their future validators remain tracked in `api-coverage.md`.

`Tests/OutputFixtures.lean` contains independent Python hashlib digests for typed
data and language-discriminated script bytes. Tests cover arbitrary signed
bignums, byte chunking, nontext asset names, aggregation, mint/output bounds,
legacy/map outputs, every native-script form, V1–V4 reference scripts, malformed
imports, every truncated prefix of a rich output, and repeated ownership paths.
The single-file `BuildOutput.lean` example is also compiled and run by the clean
consumer test, including from the release source archive.

## Design references

- [Lean 4.36 address types](https://github.com/leanprover/lean4/blob/v4.36.0/src/Std/Net/Addr.lean):
  namespaced `ofString` construction, ordinary structures, and borrowed FFI input.
  Cometa uses `ofString`/`ofBytes` and `toString`/`toBytes`. Unlike the standard IP
  parser's `Option`, native allocation and parse failures remain distinguishable
  structured errors in `EIO`; this adapter has not been given a pure specification.

- [Lean 4.36 IO implementation](https://github.com/leanprover/lean4/blob/v4.36.0/src/Init/System/IO.lean):
  `EIO` and `Except` compose expected failures without per-call transformer wrappers.
- [Lean 4.36 Lake FFI example](https://github.com/leanprover/lean4/blob/v4.36.0/tests/lake/examples/ffi/lib/lakefile.lean):
  declared native build targets and shared-library dependencies. This package uses
  Lake's Lean-aware shared linker and keeps the native library as a runtime dependency.
- [Lean FFI reference](https://lean-lang.org/doc/reference/latest/Run-Time-Code/Foreign-Function-Interface/):
  ownership and ABI constraints. The compiler pin and generated declarations take
  precedence over examples written for earlier Lean versions.
- [doc-gen4 v4.36.0](https://github.com/leanprover/doc-gen4/tree/v4.36.0):
  separate documentation project and version-matched generator.

The ordinary caller workflow is parse address, validate amount and destination,
construct a plan, inspect its payments. Proofs establish accounting and composition
laws for that model only. Wallet unlocking, signing, providers, balancing, and
submission are not yet implemented and are not represented by placeholder APIs.

## Native component adapter audit

`Cometa.Internal.Component` transports copied fields, not CBOR syntax or native
handles. `cbits/cometa_components.h` is included once by the bridge translation
unit and tracked as a Lake build input. Families select the concrete credential,
value, multi-asset, Plutus-data, native-script, script, or output implementation.
Encoding calls native constructors and `*_to_cbor`; decoding calls native
`*_from_cbor` and getters. The legacy-output adapter uses the native CBOR writer
because the pinned high-level output writer only emits maps.

Generated C for Lean 4.36 confirms two arguments per entry point: unboxed UInt8
family and borrowed object, with the world erased. `Component.node` has four
owned object fields (bytes, extra bytes, decimal text, children) and two UInt64
scalar fields at offsets `4 * sizeof(void*)` and `4 * sizeof(void*) + 8`.
Decimal text transports arbitrary integers without narrowing; the adapter uses
native bigint conversion. Child lists are copied recursively. Constructors retain
child references; getters returning objects acquire references. Unref can leave a
non-null pointer when another owner retains it, so released locals are reset
before shared cleanup. Native buffers are copied before their owners are released.

The native output parser overwrites duplicate map fields without releasing the
previous reference. A small guard uses the native CBOR reader to reject duplicate
or missing fields before parsing; it does not decode the field payloads. Asset
snapshot validation rejects duplicate asset identities still present in native
getter results. Native policy-map coalescing remains observable and documented.
Plutus map snapshots use parallel key/value lists, preserving duplicate pairs.

The pinned `cardano_script_from_cbor` leaves its outer array ending unread. The
adapter consumes that ending before its complete-input check, allowing indefinite
envelopes while rejecting trailing items. Native-script payload caches remain
intact for hashing. Tests distinguish changes to the outer envelope from changes
to the hashed payload using an independent Python `hashlib.blake2b` vector.

Tests exercise all native variants, every truncated prefix across all seven
families, trailing bytes, repeated getter ownership, exact imported hashes, and
independent construction vectors. Native list construction chooses indefinite
nonempty Plutus lists; imported definite lists retain their original identity.
`Output.checkNativeEncoding` checks native round-trip stability only. It is not an
independent serializer comparison or a universal proof about the native codec.

## Input, UTxO and body assembly audit

The additional component families bind native input, input-set, UTxO and body
constructors/readers/writers/getters. `cbits/cometa_transaction_build.h` is a
tracked Lake source dependency included once after shared component helpers.
All returned native references are released, and reused locals are cleared after
unref. Borrowed scalar pointers from body getters are read while the body lives.
The unsigned-assembly entry point has generated C signature
`lean_object* cometa_lean_unsigned_transaction(lean_object*, uint8_t)`: borrowed
body bytes, unboxed validity flag, erased world and an owned EIO result.

The native body parser caches original CBOR. Assembly passes that object directly
to `cardano_transaction_new` without clearing its cache or rebuilding fields.
Tests compare complete transaction bytes for nonminimal bodies and bodies with
currently unmodeled fields, as well as independently computed BLAKE2b-256 IDs.
The tagged construction vector adds native input-set tag 258 to the existing
rich-output fixture; its digest is computed independently using Python hashlib.
The UTxO example uses a synthetic all-zero reference and the published CIP-19
address vector, with 5 ADA; it is not live wallet material.

The pinned C API represents required signers through key guards. The typed guard
list binds the shared native getter/setter directly, including script credentials.
Native guard serialization omits empty sets; the Lean constructor rejects an
explicit empty request instead of losing presence silently. Native body getters
for the remaining unmodeled field families set `hasAdditionalFields`, preventing a
partial `view` from being offered through `toConfig` for reconstruction.

Body parsing already rejects duplicate body keys. Nested output parsing can hit
the older duplicate-output-key overwrite issue documented above, so a preflight
uses native CBOR reader operations to apply the existing output-key guard to UTxO
outputs, ordinary body outputs and collateral returns. Field codecs remain native.

`InputSet.references_unique` describes the copied native result after validation.
`checkDisjoint_sound` concerns two observed input sets, not native algorithm
correctness or an era-specific spending/reference/collateral policy. No network,
minimum-fee, balancing, script-execution or signature guarantee is inferred.

## Reward-account and withdrawal audit

`cbits/cometa_withdrawals.h` is a tracked Lake build input included before the
body adapter. Component families 12 and 13 use the existing audited ABI; family 12
carries raw address bytes rather than CBOR. The pinned audit covers
`lib/src/address/{reward_address,address}.c`,
`lib/src/address/internals/reward_addr_pack.c`, and
`lib/src/common/withdrawal_map.c`. Reward constructors retain the credential;
credential and indexed map getters acquire references. All getter buffers are
copied and all references released, including partially populated error paths.

The pinned reward unpacker accepts payment headers and ignores bytes after the
credential. A narrow guard requires exactly 29 bytes, reward type 14/15, and
network 0/1 before parsing. Withdrawal map keys receive the same guard through
the native CBOR reader, including when nested in a body. Text parsing requires
the native lowercase display form, preventing accepted text from silently losing
trailing payload bytes. Uppercase Bech32 is rejected by this pinned native parser.
These are validation guards; all construction, serialization and field decoding
remain native. General `Address` parsing retains its existing native semantics.

Native map insertion and parsing retain duplicate accounts. The adapter uses
`get_key_value_at`, not key lookup, to preserve each observed amount before Lean
checks uniqueness. Both zero and all UInt64 bits are retained. The aggregate is
an unbounded Lean `Nat`; output construction separately checks native bounds.
Imported map bytes are cached in Lean, while a new body uses the native map writer
and can normalize them. An imported body retains its exact native cache for assembly.

`Tests/Withdrawals.lean` uses synthetic repeated-byte credential hashes and literal
CBOR vectors. Its body digest was independently computed using Python hashlib
BLAKE2b-256. The malformed Bech32 payload was generated once with the pinned native
Bech32 encoder from a 30-byte address; the account wrapper must reject it. The
example reuses the public CIP-19 reward address and synthetic UTxO fixture.
`Withdrawals.accounts_unique` describes only the checked native snapshot; it is
not a proof of native algorithm correctness, account rewards, or authorization.
