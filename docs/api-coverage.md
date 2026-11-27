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

Full transaction-building parity is the target. Lean provides typed outputs, core
transaction bodies, reward withdrawals, metadata/auxiliary data and unsigned assembly, but
complete transaction assembly and workflow dependencies remain open. Every remaining
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
| Primitive values | Addresses/credentials and their construction, networks, hashes, transaction IDs, asset IDs/names, bounded coin/asset quantities, rationals and slots | Address parsing, native key/script reward-account construction, fixed-size hashes, transaction/policy/asset IDs and names; other primitive families remain open |
| Values and outputs | Multi-asset values, complete outputs, datum hashes/inline datums, reference scripts, exact encodings where required | Signed bundles, output/mint encoding, typed map/legacy output construction, all datum forms and reference scripts; semantic decoding implemented |
| Inputs and UTxOs | Spending/reference/collateral inputs, resolved outputs, uniqueness and disjointness rules | Native reference/input-set/UTxO construction and inspection; checked uniqueness and explicit proved disjointness checks |
| Body fields | Fee, validity interval, network, mint/burn, withdrawals, certificates, required signers/guards, hashes, collateral/return/total, legacy updates and all optional fields | Native core-body construction and getters for keys 0, 1, 2, 3, 5, 7, 8, 9, 11, 13–18, 21–22; remaining fields listed below |
| Scripts and data | Every native-script variant; pinned Plutus V1/V2/V3/V4 support; arbitrary Plutus data, script/datum hashes and language discrimination | Typed native scripts, Plutus V1–V4 wrappers/hashes, all Plutus data constructors, checked imported datum bytes; semantic decoding implemented; VM operations remain open |
| Witnesses and redeemers | Verification-key and bootstrap witnesses, native/Plutus script witnesses, datums, all redeemer purposes, budgets, purpose/index mapping, merging and signing | Opaque preservation only |
| Metadata and auxiliary data | All metadata forms, scripts, auxiliary-data encoding/hash and body commitment | Native metadata forms and label maps, native/Plutus V1–V4 auxiliary scripts, exact hash and checked attachment; historical encoding selection/native parse limits noted below |
| Staking and pools | All certificate variants, registration/deregistration, delegation and combinations, pool registration/retirement, relays/metadata/owners, reward withdrawals and applicable BLS fields | Native key/script reward accounts and checked withdrawal maps; certificates, pools and BLS fields remain open |
| Governance | DReps, committee credentials, anchors, constitution, all governance actions, votes, proposals, deposits/refunds, treasury/donations and parameter changes | Missing |
| Protocol parameters | Complete snapshots and updates, cost models, prices/budgets, voting thresholds, era-specific fields, version/availability distinctions | Missing |
| Contextual transactions | Subtransaction bodies/builders/witnesses, guards and required top-level guards, direct deposits, account-balance intervals, starting-balance requirements, contextual indices and batch accounting | Missing |
| Transaction assembly | Typed construction of every supported body/witness/auxiliary combination; historical/mempool/block frames; exact imported bytes and safe updates | Native unsigned assembly with empty witnesses and optional checked auxiliary data, exact imported body/payload preservation, and inspection; typed witnesses and frame selection remain open |
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

## Output-construction implementation evidence

This is a construction slice, not closure of the full component-API rows.

| Feature / native or schema boundary | Public Lean API | Evidence and remaining scope |
| --- | --- | --- |
| 28-byte policy hashes; 0–32-byte names | `Hash`, `PolicyId`, `AssetName`, `AssetId` | Length proofs; binary/UTF-8 boundary tests; credential roles and address construction remain open |
| Coin/multi-asset value and mint maps; `cardano_value_new/from_cbor/to_cbor` and `cardano_multi_asset_new/from_cbor/to_cbor` | `Value.ofList`, `quantity`, arithmetic, `checkOutput`, `toOutputCbor`, `toMintCbor` | Aggregation/zero removal, signed limits, canonical policy/name ordering, native output and mint parsing; `quantity_add` and `checkOutput_sound`; native output/mint semantic decoding and checked getter snapshots |
| Output arrays/maps and datum tags 0/1; `cardano_transaction_output_from_cbor` / `to_cbor` | `Output.create`, `toCbor`, `toLegacyCbor`, `toNativeCbor`, `checkNativeEncoding` | Full rich-output fixture, legacy conversion, all datum/reference combinations, truncation/trailing failures; output quantity/payment-header proofs and a checked native-result equality; `Output.ofCbor` and exact `EncodedOutput` imports |
| Native script kinds 0–6 (including require guard); native variant constructors/getters; `cardano_script_from_cbor` / `get_hash` | `NativeScript` and `Script.ofNative` | All constructors, nested scripts, 64-bit threshold/slot boundaries, independent signature-script hash; semantic decoding and exact imported script hashes |
| Script language tags 1–4 | `PlutusVersion`, `Script.ofPlutus`, `view`, `toCbor`, `hash` | Independent language-discriminated hashes and reference-output round trips for every version; semantic decoding implemented; program execution and parameter application remain open |
| Plutus constructors 121–127 / 1280–1400 / 102; maps/lists/integers/bytes; `cardano_plutus_data_new_*`, `from_cbor`, `to_cbor`, typed getters and `cardano_blake2b_compute_hash` | `PlutusData.toCbor`, `EncodedPlutusData.ofData`, `ofCbor`, `toCbor`, `hash` | Independent vectors, arbitrary signed bignums, 64-byte chunks, preserved nonminimal identity, malformed imports; `PlutusData.ofCbor` and `EncodedPlutusData.toData` semantic views |

### Native transaction construction

| Native boundary | Public Lean API | Evidence / remaining scope |
| --- | --- | --- |
| `cardano_transaction_input_new/from_cbor/to_cbor` and getters | `OutputReference.toCbor/ofCbor` | Independent input vector, UInt64 index boundary, complete-input rejection |
| Native input-set constructor, insertion, reader, writer and getters | `InputSet.ofList/ofCbor`, `checkDisjoint` | Reject requested/imported duplicate references; native ordering; `references_unique` and checker soundness |
| `cardano_utxo_new/from_cbor/to_cbor`, input/output getters | `UTxO.create/ofCbor` | Complete rich-output vector; truncation/error paths; no unspentness assertion |
| Native body constructor and setters/getters | `TransactionBody.Config`, `create/ofCbor`, `view`, `toConfig` | Combined fee, validity, hashes, mint, collateral, guards, network, reference inputs and treasury fields; independent base body/hash vector |
| `cardano_transaction_new`, empty witness-set constructor, validity setter and writer | `Transaction.ofBody` | Exact nonminimal/imported body bytes and IDs, declared validity flags, unmodeled-field retention, repeated native ownership |

### Reward-account and withdrawal evidence

| Native boundary | Public Lean API | Evidence / remaining scope |
| --- | --- | --- |
| `cardano_reward_address_from_credentials/from_bytes`, network/credential/byte getters | `RewardAccount.create/ofBytes/ofString/ofAddress`, `network`, `credential`, `toBytes/toString/toAddress` | Key/script × mainnet/testnet vectors; exact 29-byte and reward-header validation; reserved networks rejected; lowercase native Bech32 only |
| `cardano_withdrawal_map_new/insert/from_cbor/to_cbor/get_key_value_at` | `Withdrawals.ofList/ofCbor`, `entries`, `toCbor`, `totalLovelace` | Native ordering; duplicate requested/imported account rejection; zero and UInt64 maximum amounts; unbounded total; truncation/trailing errors; exact imported bytes; `accounts_unique` theorem over checked snapshots |
| `cardano_transaction_body_set_withdrawals/get_withdrawals`, body key 5 | `TransactionBody.Config.withdrawals`, `create/ofCbor/toConfig`, `Transaction.ofBody` | Absent versus present-empty; combined body fields; independent encoding/hash vector; exact imported-body assembly; nested invalid-key and duplicate rejection |

The pinned reward parser can normalize payment headers and ignore extra bytes.
The adapter validates raw map keys and reward bytes before parsing, using the
native CBOR reader for map traversal. Text imports must match the native lowercase
display encoding. Native indexed map getters retain duplicate entries; Lean checks
uniqueness rather than looking up a key and accidentally repeating its first amount.
Original map bytes are retained by `Withdrawals`; embedding a map in a newly built
body normalizes its encoding through the native writer. Existing body bytes remain
unchanged during assembly. No rewards query, registration, authorization, minimum
fee or script execution is established by these offline checks.

### Metadata and auxiliary-data evidence

| Native boundary | Public Lean API | Evidence / remaining scope |
| --- | --- | --- |
| `cardano_metadatum_new_map/list/integer_from_string/bytes/string`, native codecs and typed getters | `Metadatum` constructors, `toCbor/ofCbor` | All five variants; nested/duplicate map pairs retained; Unicode/NUL text, 64-byte UTF-8 bounds, integers -2^64 through 2^64-1; imported bounds checked |
| Native transaction-metadata constructor, insertion, codec and indexed pair getter | `Metadata.ofList/ofCbor`, `entries/toCbor`, `labels_unique` | Unique UInt64 labels, native ordering, maximum labels, absent/empty and nonminimal input; theorem concerns checked getter snapshots |
| Native auxiliary constructor, metadata/native/Plutus V1–V4 setters/getters, codec and hash | `AuxiliaryData.Config`, `create/ofCbor/view/toCbor/hash` | Combined six-field independent CBOR/hash vector; all empty fields preserved; original cache retained; complete semantic reconstruction |
| `cardano_transaction_new/get_auxiliary_data` with native body/auxiliary caches | `Transaction.withAuxiliaryData/auxiliaryData`, `AuxiliaryData.checkCommitment` | Reject missing/wrong commitments; verify observed body ID and payload bytes; exact historical/nonminimal vectors; `checkCommitment_sound` proves checked equality, not native hashing correctness |

New auxiliary objects use the pinned writer's tag-259 map. Metadata-only and
historical array forms can be imported and retained; typed selection of historical
output encodings remains open. The pinned parser also accepts a one-element
historical array and rejects the indefinite two-element historical array. Tests
record these native behaviors without claiming ledger validity. Resolving that
native parse limitation remains part of full encoding parity.

Metadata labels must be unique; nested semantic maps retain duplicate pairs.
Labels and integers are checked independently: labels are UInt64, while negative
metadata integers extend to -2^64. Byte/text leaves are limited to 64 bytes, with
strict UTF-8 and embedded NUL preservation for text. Rebuilding a semantic view
may normalize bytes; keep `toCbor` or the complete imported auxiliary object when
identity matters. Auxiliary scripts are not witnesses and are not evaluated.

Typed construction is still required for body keys 4 (certificates),
6 (legacy updates), 19–20 (voting/proposals), and 23–27
(contextual/subtransaction/account fields). Native parsing and assembly preserve
these fields; a partial view is not counted as typed construction coverage.
`toConfig` rejects bodies containing them rather than silently dropping data.

Required signers and guards share native body field 14. `Config.guards` represents
both key and script credentials; the native writer chooses bare-key-hash or
credential form. It omits explicitly empty guard sets. `create` and `toConfig`
reject that unsupported reconstruction case; imported bytes remain usable for
assembly. Other supported optional fields preserve absent versus present-empty
state. Native input-set serialization emits tag 258, so rebuilding normalizes
untagged input-set representations. Imported body bytes are never rebuilt during
`Transaction.ofBody`.

The C value implementation uses signed 64-bit native-asset quantities. This slice
checks that native bound explicitly; it must not be advertised as establishing
all possible ledger quantity ranges. Wider quantities stay representable in the
pure signed model. A native/ledger range mismatch must be resolved before the
full-parity completion claim. Lovelace output encoding retains all unsigned
64-bit bits, with a native round-trip regression.

All component production codecs now delegate to cardano-c. Lean checks copied
hash lengths, asset names, destination kinds, and quantity bounds. The pure
`Value` arithmetic model remains distinct from C operations. The native datum
reader accepts oversized byte leaves; its multi-asset reader can coalesce repeated
policy maps. These behaviors are tested and are not ledger-validity guarantees.
Constructed datum chunking and container choices belong to the native writer.
Duplicate output fields are rejected using the native CBOR reader before invoking
the pinned output parser, whose overwrite path can otherwise leak a reference.
The native output writer only emits maps; the explicit legacy adapter uses the
native CBOR writer plus native value serialization for its array representation.

These checks are offline Linux x86_64 checks. There is no network/era activation
or script-execution claim. The provider/evaluator/selector adapters and their
proof-oriented contracts below are still required, not implemented by codec tests.

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
