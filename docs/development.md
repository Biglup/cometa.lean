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
lake build cometaTests inspectAddress inspectTransaction buildOutput
lake test
lake lean Tests/Invariants.lean
lake env leanchecker Cometa.Plan
lake env leanchecker Cometa.TransactionId
lake env leanchecker Cometa.Value
lake env leanchecker Cometa.Output
lake exe inspectTransaction Examples/transaction.cbor.hex
python3 scripts/check-source.py
python3 -m unittest discover -s Tests/Packaging -v
python3 scripts/check-consumer.py
clang-format-18 --dry-run --Werror cbits/cometa_lean.c
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
map normalization. Encoding groups native assets by policy and sorts encoded map
keys by length then bytes, matching the pinned native asset-map comparator.

The new audit covers `lib/src/assets/asset_name_map.c`,
`lib/src/plutus_data/plutus_data.c`, `lib/src/scripts/script.c`, the native-script
and Plutus V1–V4 implementations, and the existing output/value codecs. Native
script thresholds use `size_t`; the public UInt64 range matches the supported
64-bit platforms. Hash getters return owned references. Datum hashing consumes
exact original bytes after native parsing, including nonminimal encodings.
The additional pure import scan enforces the 64-byte datum leaf/chunk bound.

The three externs in `Cometa.Internal.Output` borrow a byte array and return
`EIO UInt32 ByteArray`. Generated C in the Script, PlutusData and Output modules
confirms a single borrowed argument, no world argument, and the standard IO-result
layout. Readers, writers, parsed data/scripts/outputs and hashes are unreferenced
on every return path. All returned bytes are copied into Lean ownership.

`Output.checkNativeEncoding` calls the actual output codec and compares its result
with the pure constructed encoding. Success returns a subtype carrying equality
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

## Component decoding audit

The pure component CBOR reader bounds recursion by input byte count and checks
container lengths before traversal. It retains map order, duplicate entries and
byte-string chunks for schema validation. Output and asset schemas reject duplicate
keys; Plutus data maps retain their ordered pairs. Imported output, datum and
script wrappers preserve original bytes separately from decoded fields.

The pinned `cardano_script_from_cbor` leaves its outer array ending unread. The
adapter explicitly consumes that ending before its complete-input check, allowing
indefinite envelopes while rejecting trailing items. Native-script payload caches
remain intact for hashing. Tests distinguish changes to the outer envelope from
changes to the hashed payload, including an independent Python `hashlib.blake2b`
224-bit vector (zero language byte followed by the nonminimal native payload).
No foreign declaration or ownership convention changed in this slice.
