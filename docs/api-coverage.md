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

# API coverage and extension contracts

## Scope and baseline

Full transaction-building parity is the target. The current Lean implementation
only inspects transactions and models lovelace payment intentions. Every remaining
row below is a required implementation area, not an optional example backlog.

The audit baseline is cardano-c `a6f659d780f17b60ebafa170af919cca8173df09`
(2.0.0-rc.7). Reference binding checkouts reviewed for this plan:

- Haskell: `530692e62dcc467d9206ec66521e30b61a239660`, especially `Cometa.Transaction`,
  `Transaction.Fields`, `Transaction.Building`, `SubTransaction`, `Evaluation`,
  `CoinSelection`, and `Provider`.
- JavaScript: `0f7ae70e33ef82392d3503e9392c3f0abfc54524`, including the public
  `TxEvaluator` interface and provider/native adapter modules.
- Python: `a9ad3657aba56dd2411c017cbdfebe0940fefae0`, including the C evaluator,
  C provider, and C coin-selector wrappers and Python callback adapters.

These pins make comparisons reproducible; they do not assert that every other
binding is correct or complete. Native headers and era schemas remain part of the
audit. Reconcile the baseline whenever upstream changes.

## Required transaction coverage

| Area | Required public capabilities | Current Lean coverage |
| --- | --- | --- |
| Primitive values | Addresses/credentials and their construction, networks, hashes, transaction IDs, asset IDs/names, bounded coin/asset quantities, rationals and slots | Address parsing, transaction IDs, lovelace only |
| Values and outputs | Multi-asset values, complete outputs, datum hashes/inline datums, reference scripts, exact encodings where required | Address/coin summaries and native-reserialized output CBOR only |
| Inputs and UTxOs | Spending/reference/collateral inputs, resolved outputs, uniqueness and disjointness rules | Spending-reference inspection only |
| Body fields | Fee, validity interval, network, mint/burn, withdrawals, certificates, required signers/guards, hashes, collateral/return/total, legacy updates and all optional fields | Fee and spending/output inspection only |
| Scripts and data | Every native-script variant; pinned Plutus V1/V2/V3/V4 support; arbitrary Plutus data, script/datum hashes and language discrimination | Opaque preservation only |
| Witnesses and redeemers | Verification-key and bootstrap witnesses, native/Plutus script witnesses, datums, all redeemer purposes, budgets, purpose/index mapping, merging and signing | Opaque preservation only |
| Metadata and auxiliary data | All metadata forms, scripts, auxiliary-data encoding/hash and body commitment | Opaque preservation only |
| Staking and pools | All certificate variants, registration/deregistration, delegation and combinations, pool registration/retirement, relays/metadata/owners, reward withdrawals and applicable BLS fields | Missing |
| Governance | DReps, committee credentials, anchors, constitution, all governance actions, votes, proposals, deposits/refunds, treasury/donations and parameter changes | Missing |
| Protocol parameters | Complete snapshots and updates, cost models, prices/budgets, voting thresholds, era-specific fields, version/availability distinctions | Missing |
| Contextual transactions | Subtransaction bodies/builders/witnesses, guards and required top-level guards, direct deposits, account-balance intervals, starting-balance requirements, contextual indices and batch accounting | Missing |
| Transaction assembly | Typed construction of every supported body/witness/auxiliary combination; historical/mempool/block frames; exact imported bytes and safe updates | Exact imported bytes and native inspection only |
| Building and balancing | Explicit fees, minimum ada, execution/reference-script fees, deposits/refunds, mint/burn/withdrawal accounting, change, collateral, witness estimates, budgets, hashes and convergence | Lovelace payment-intention model only |
| Keys and wallets | Encrypted wallet interop, derivation, supported signing/witness paths, external signer injection and secret cleanup | Missing |
| Providers and lifecycle | All query/evaluation/submission/confirmation operations, built-in backends and custom/native adapters | Missing |

For each row, maintain a per-feature mapping as it is implemented: native symbol
or schema variant; Lean public constructor/accessor/operation; convenience builder
support; positive/negative vectors; proof or conformance evidence; supported era
and network-test status. Enumerate every body field, certificate, governance
action, script language, redeemer purpose, and protocol parameter. A module name
or one example is not sufficient evidence to mark a row complete. Any baseline
limitation preventing a valid transaction must be recorded and resolved, rather
than hidden behind an unsupported-operation result and counted as parity.

## Extension contracts

Use public Lean structures containing functions with typed requests/results and
`EIO Error` effects. Callers must be able to provide closures with application
state, choose a built-in instance, or use an adapter to an existing C instance.
Construction must not require editing internal modules, recompiling cardano-c,
or selecting from a closed enum of built-in implementations. Proof interfaces
may express laws separately; ordinary users need not prove a backend correct
before they can use it through checked operations.

| Extension | Request and result contract | Integration requirements |
| --- | --- | --- |
| Transaction evaluator | Exact transaction, explicit top-level/subtransaction target, resolved UTxOs, protocol/slot context as needed; return budgets keyed by existing redeemer identity and structured failures | Validate full coverage, uniqueness, bounds and unchanged script arguments; apply budgets and recompute commitments explicitly; never silently substitute another evaluator |
| Coin selector | Preselected/available UTxOs, complete multi-asset target, change address, output hints, constraints and protocol snapshot; return selected inputs and change | Check membership, uniqueness, preselection retention, coin/asset conservation and applicable size/minimum-ada constraints; expose deterministic configuration/seeding where supported |
| Provider | Network identity, parameters, address/asset UTxOs, NFT lookup, input/datum resolution, rewards, evaluation, submission and confirmation | Distinguish absence, empty success, unsupported capability and failure; document pagination/timeouts and non-atomic query observations; submission is explicit |
| Signer/key handler | Exact signing payload and required credentials/derivation context; return witnesses without mutating the body | Support encrypted software wallets and external/hardware/application signers; validate witness association and preserve body identity |
| Deferred building hooks | Resolved transaction context and stable purpose/index mappings for redeemer construction where supported by the baseline | Define ordering, permitted effects, failure propagation and when balancing may invoke a hook again |

Builder configuration explicitly accepts the provider, evaluator, selector and
signer dependencies appropriate to that stage. Offline assembly and balancing
must accept caller-supplied resolved data; they must not require a hosted provider
or wallet implicitly. Protocol context and randomness are explicit inputs where
needed. No hidden global instance chooses a strategy on behalf of a caller.

## Concrete C instances and bidirectional adapters

The generic interfaces must expose the actual native implementations, not Lean
reimplementations with similar names:

- `cardano_large_first_coin_selector_new` and the random-improve selector factories,
  including supported seed/options variants.
- `cardano_tx_evaluator_new_native`,
  `cardano_tx_evaluator_new_native_sub_transaction`, and
  `cardano_tx_evaluator_from_provider`.
- The `cardano_provider_t` interface and concrete provider objects supplied by C
  integrations. The core header inventory does not imply it ships a concrete
  implementation for every hosted backend; record factory/module availability.
- Lean-defined callbacks adapted to `cardano_provider_impl_t`,
  `cardano_coin_selector_impl_t`, and `cardano_tx_evaluator_impl_t` when a native
  builder consumes those interfaces.

Keep native handles opaque and use audited factory/adoption boundaries with
explicit owned/borrowed-reference contracts. Do not expose integer-to-pointer
casts as a normal API. Keep callback closures alive for the entire native use,
release them exactly once, propagate failures across the boundary, and define
thread affinity, reentrancy, cancellation and teardown behavior. Native instance
wrappers must be usable directly from Lean tests, not only buried inside builders.

Tests must demonstrate injection with a custom Lean implementation, direct use of
each available C factory, and Lean-to-C-to-Lean callback round trips. Cover success,
errors, partial results, teardown, and memory ownership without live credentials.

## Proof contract for native execution

Calling C through `EIO` does not make its behavior kernel-verified. The proof and
testing design must nevertheless let users exercise the concrete native instances
from Lean and obtain meaningful, checked guarantees about returned values.

1. Define pure request/result models and predicates such as selection conservation,
   input membership/disjointness, budget coverage/bounds, and body preservation.
2. Implement executable validators and prove their soundness in Lean: successful
   validation implies the specified predicate. Checked result types may pair a
   result with evidence for those predicates. Keep the raw snapshot accessible
   through an explicitly named inspection/testing boundary where appropriate.
3. Run the real C instance through the adapter, copy its result into Lean-owned
   data, and pass that data through the proved validator. Reject violations with
   structured errors. The guarantee concerns the checked request/result relation;
   it is not a theorem that the C algorithm always succeeds or is optimal.
4. Exercise deterministic fixtures and generated cases against the real native
   implementations, custom implementations, and independent references. For
   randomized selection, record the supported seed/configuration. Export selected
   public result fixtures when kernel-replayed concrete proofs are useful.
5. Keep distinct claims distinct: model theorems, checker soundness, proofs about
   concrete captured values, runtime conformance tests, and any future verified
   C-to-model refinement. No axiom or opaque FFI declaration may assert native
   correctness. Compiling or running a native decision procedure alone is not a
   universal proof of the C implementation.

Provider authenticity/freshness cannot be established from a well-shaped response
alone. Script budget coverage is not a proof that the evaluator executed the
ledger semantics correctly. Those stronger claims require appropriate evidence,
a formally related implementation, or an explicitly stated trust assumption.
Do not manufacture proofs for them from successful HTTP or FFI calls.

## Completion gates

Full parity requires all transaction coverage rows closed at the recorded baseline,
public custom/native extension paths, direct native-instance conformance tests,
proved validators for the declared invariants, differential serialization/hash/
fee/evaluation tests, complete single-file workflows, and supported-network tests.
Advanced fields must be tested in combination, including contextual transactions;
isolated constructors alone are insufficient. Preserve licenses, documentation,
formatting, ABI audits and the existing release/consumer checks throughout.
