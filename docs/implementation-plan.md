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

## Completion requirement

The binding must expose all transaction-relevant APIs needed to construct any
valid transaction in the ledger eras and protocol versions covered by the pinned
cardano-c baseline, with capability parity against the other Cometa bindings.
Payment examples are incremental milestones, not the final scope. New upstream
era features require an explicit baseline update and coverage audit; being
serializable does not imply a feature is activated on preprod or mainnet.

Provide both a complete typed assembly API and convenient planning/balancing APIs.
A high-level builder must not restrict callers to its predefined recipes. Every
body field, witness kind, certificate, governance action, supported script language,
and contextual/subtransaction feature must be constructible and inspectable.
Opaque CBOR pass-through alone does not count as typed construction coverage.

[API coverage and extension contracts](api-coverage.md) is the mandatory scope
checklist. Track native adapters, custom Lean implementations, and proof coverage
separately. Each implementation PR must update its affected coverage rows and
record the relevant native exports, public APIs, and tests before claiming parity.

## Completed milestone: inspect a serialized transaction offline

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

## Output-construction slice

Added proof-bearing fixed-size hashes and asset names, arbitrary-precision signed
values, separate checked output/mint encodings, complete typed native-script
construction, Plutus V1–V4 program wrappers, all Plutus data constructors, and
map/legacy output construction with datum/reference-script support.

`Value.quantity_add` and `Value.checkOutput_sound` establish model/validator laws.
`Output.checkNativeEncoding` exercises the concrete C output codec and returns a
checked equality for that observed result. `BuildOutput.lean` is a complete
single-file example using that operation. Native datum/script hashes are checked
against independent vectors; the coverage document maps each implemented family
to its native/schema boundary and records open APIs and quantity-range limits.

Semantic decoding of values, scripts, Plutus data and complete outputs is now
implemented. `EncodedOutput` and imported scripts/datums retain exact original
bytes alongside their semantic views. Duplicate output/asset map keys and unknown
fields are rejected. Native alternative 6 (require guard) is included with typed
key/script credentials; the initial 0–5 inventory was incomplete. VM operations,
complete transaction assembly, and the extension adapters below remain open.

Local Linux x86_64 checks pass: native/encoding tests, interpreter and constructor
checks, kernel checking, packaging regressions, formatting/licenses, API docs,
and all three examples in a clean consumer. Valgrind reports zero errors and
zero definitely/indirectly lost bytes, with Lean runtime allocations remaining.
CI repeats the checks and runs the consumer from the release source archive.
No wallet, live-network, transaction submission or release operation is included.

## Remaining implementation sequence

All stages below are required for completion. The sequence keeps each PR testable;
it does not defer less common transaction capabilities indefinitely.

1. **Complete values, scripts, and outputs.** Policy IDs, arbitrary byte asset names,
   unsigned output quantities versus signed mint/burn quantities, checked values,
   all Plutus data constructors, datum hashes/inline data, native scripts and every
   pinned Plutus version, and reference scripts. Preserve encoding where identity
   depends on it. Complete construction, serialization and semantic decoding for
   these components; construction is implemented in the output slice above.
2. **Complete transaction components and assembly.** UTxOs, spending/reference/
   collateral inputs, all body fields, withdrawals, metadata and auxiliary data,
   witnesses/redeemers, protocol parameters/updates, every certificate/governance
   variant, and contextual/subtransaction fields. Provide complete typed builders
   independently of balancing convenience functions; retain explicit era/context
   checks and the distinction between absent and empty fields.
3. **Public extension contracts and concrete native instances.** Introduce ordinary
   Lean structures of functions for providers, evaluators, selectors, and signers.
   Publish typed requests/results and explicit errors. Wrap C largest-first and
   random-improve selectors, native top-level/subtransaction evaluators, the C
   provider-backed evaluator, and C provider implementations supplied through the
   supported adapter boundary. Support custom Lean implementations and bridging
   them into native builders. Test callback lifetimes, errors, and cleanup.
4. **Proof-oriented validation of actual instances.** Define pure specifications
   and executable validators with kernel-checked soundness proofs. Run the real C
   instances from Lean, validate their returned snapshots, and expose checked
   results where properties are decidable. Run the same conformance suite against
   C-backed and custom instances. Keep finite execution evidence distinct from
   universal correctness of the C algorithms; see the proof contract below.
5. **Encrypted wallets and scoped signing.** Match the other bindings' encrypted
   wallet format, derivation and signing features. Support prompt-based passwords,
   explicit secret cleanup, witness merging, external signers, and preservation of
   unchanged body bytes. Test public vectors and wrong-password/error paths.
6. **Balancing and end-to-end workflows.** Inject provider, evaluator, coin selector,
   and signer explicitly. Cover coin/asset conservation, implicit deposits/refunds,
   minimum ada, all fee components, collateral, budget/commitment recalculation,
   change and bounded convergence. Build/sign/submit/confirm examples must unlock
   an encrypted wallet and show the main workflow in one file. Include advanced
   script, governance, and contextual transactions, not just payments.
7. **Provider implementations and full parity validation.** Cover Blockfrost, Koios,
   Kupmios, Hydra, and the supported native-provider adapter. Exercise every query
   and effect, pagination, absence, errors, timeouts, and unsupported capabilities.
   Compare serialized fields, hashes, fees, selection, and evaluation with the
   pinned native implementation and other bindings. Run preprod and a
   preprod-backed Hydra deployment where those features are supported; use
   appropriate ledger fixtures for features not activated there.
8. **Release readiness.** Close every required coverage gap, match the other
   bindings' example workflows, complete native/custom adapter conformance and
   proof checks, audit platform support, and publish accurate feature/version
   coverage. No partial milestone is advertised as full transaction parity.
