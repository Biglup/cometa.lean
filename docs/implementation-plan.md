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

# Implementation plan

## Direction

Grow the binding through complete workflows, using the pinned cardano-c release
for ledger serialization and cryptography. Public values are immutable Lean
snapshots; native effects use `EIO Error`. Pure validation uses `Except Error`.
Proofs describe the Lean model and do not certify the native implementation or
ledger acceptance. Keep examples in one file with named steps and one error
boundary. Preserve Apache-2.0 notices and section separators throughout.

## Current milestone: inspect a serialized transaction offline

This milestone is the execution scope of the transaction-inspection PR. It supplies
the transaction representation needed by later signing and provider workflows,
without requiring credentials, funding, or a network connection.

1. **Audit and representation.** Inspect the pinned native transaction reader,
   body/hash accessors, input/output collections, and CBOR cache semantics. Check
   Lean 4.36 generated C layouts before implementing the new FFI. Specify ownership
   for every acquired native object and borrowed byte buffer.
2. **Checked bytes and identifiers.** Add strict hexadecimal decoding and lowercase
   encoding, plus a 32-byte transaction identifier with checked constructors and a
   length invariant. Reject odd-length strings and non-hex characters without
   echoing input. Keep output references distinct from whole transactions.
3. **Native transaction snapshot.** Parse exactly one transaction, rejecting trailing
   bytes. Copy its body identifier, fee, declared script-validity flag, spending
   inputs, and ordinary output summaries into Lean; release all native references
   on success and failure. Preserve the original full transaction bytes exactly.
   Output summaries include address, lovelace, and complete output CBOR so assets,
   datum, and reference scripts are retained without pretending they were decoded.
4. **Public API.** Expose `Transaction.ofCbor`, `ofHex`, `toCbor`, `toHex`, and pure
   observations. Document that parsing is structural, input order is the native
   reader's sorted order, summaries exclude collateral returns, and the script-validity
   flag is declared data rather than a validation result. Do not expose mutable
   handles or public constructors that bypass parsing.
5. **Complete example and docs.** Add a single-file CLI that reads a CBOR-hex file,
   parses it, and prints its ID, fee, inputs, and ordinary output summaries. Use
   named read/inspect/report steps. Include a public synthetic fixture and a
   runnable README command; make explicit that the example does not submit.
6. **Regression and ownership checks.** Exercise historical, mempool, and block framing, native body
   hashing against independent BLAKE2b-256 vectors, noncanonical body preservation,
   malformed/truncated/trailing input, identifiers, output summaries, and repeated
   success/error paths. Check constructor privacy and the identifier invariant.
   Audit generated C; run native tests, interpreter checks, kernel checking,
   formatting, source/license checks, packaging tests, Valgrind, docs, and the clean
   downstream consumer. Add the example to CI and check the actual PR run.
7. **Delivery.** Update this plan with results and limitations, commit using the
   repository-local signing identity, verify the signature, push, and open a PR.
   Do not bump the release version, create a tag, or publish a release implicitly.

Acceptance: a fresh consumer can parse the fixture, reproduce its exact bytes,
inspect the expected identifier/fee/input/output data, and receive structured
errors for rejected input. Local and CI memory checks must report no invalid
accesses or definitely lost native allocations. No live-network claim is made.

## Execution record

The inspection milestone is implemented: strict hex conversion, proof-bearing
transaction IDs, immutable transaction snapshots, spending input references, and
ordinary output summaries are exported through `Cometa`. The single-file example
and its synthetic fixture run without a wallet or provider.

Local Linux x86_64 validation covers the native and malformed-input suites,
interpreter execution, private constructor boundaries, kernel checking of model
laws and identifier length, all 17 packaging regression tests, source/license and
format checks, API docs, and both examples in a fresh downstream package. Valgrind
reports zero errors and zero definitely/indirectly lost bytes; Lean runtime
allocations remain at exit. CI repeats these checks and tests the actual release
source archive. There has been no preprod run, wallet access, signing, submission,
version bump, or release publication in this milestone.

## Subsequent milestones

These describe the dependency order beyond this PR; they are not implemented by
an inspection API and must not be advertised as available.

1. **Multi-asset outputs and richer plans.** Policy IDs, byte-valued asset names,
   bounded quantities, datum/reference-script representations, checked values,
   output serialization, spending/reference inputs, minting, validity intervals,
   and explicit fees/deposits. Prove useful accounting/order laws separately from
   native serialization. Add an offline output-construction example.
2. **Encrypted wallets and scoped signing.** Inspect the other bindings' encrypted
   wallet format and key derivation. Introduce prompt-based password input, explicit
   secret lifetime/cleanup, derivation/address discovery, and signing with witness
   merging that preserves transaction-body bytes. Never print secrets or pass
   passwords through command-line arguments. Test public vectors and wrong-password
   failures before introducing a live workflow.
3. **Provider reads.** Add a small provider interface with typed network/UTxO/protocol
   parameters. Start with one provider and fixture-backed contract tests; then add
   Koios, Kupmios, and Hydra without assuming their query capabilities are identical.
   Define HTTP errors, timeouts, pagination, and unavailable data explicitly.
4. **Build, sign, and submit.** Integrate native balancing and protocol parameters,
   validate network/change address, expose evaluation and submission, compare the
   returned ID, and await confirmation with a timeout. A single-file SendLovelace
   example must unlock an encrypted wallet, build, sign, submit, and confirm.
   Run against preprod only with an explicitly selected configuration and funds.
5. **Broader parity and releases.** Match other bindings' examples for assets,
   staking, scripts, governance, and contextual transactions as their APIs land.
   Add provider matrices and preprod/Hydra integration coverage, then expand tested
   platforms and publish a release whose notes match the implemented surface.
