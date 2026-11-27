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

<div align="center">
  <a href="https://cometa.dev/" target="_blank">
    <img align="center" width="300" src="assets/cometa_lean.png" alt="Cometa.lean">
  </a>
</div>

<br>

<div align="center">

![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)
[![Twitter Follow](https://img.shields.io/twitter/follow/BiglupLabs?style=social)](https://x.com/BiglupLabs)

</div>

<hr>

# Cometa.lean

Typed Cardano values, scripts, data, and outputs for Lean 4, with address and
transaction inspection.
The native adapter uses cardano-c **2.0.0-rc.7**; the toolchain is pinned to
**Lean 4.36.0**.

The API constructs multi-asset outputs, native and versioned Plutus scripts, and
Plutus data. It also parses addresses and serialized transactions and models
ordered payments. Wallets, complete transaction assembly, balancing, signing, and
submission are still being implemented. Proofs describe the Lean models and
checked results; they do not verify all cardano-c or ledger execution.

## Build

Install the pinned Lean toolchain with Elan, Python 3.12+, and a C11 compiler.
Linux x86_64 requires glibc 2.33 or newer.

```sh
lake build
lake test
```

Lake prepares the native dependency automatically, including when Cometa is used
from another package. Downloads are version-pinned and SHA256-checked; subsequent
builds verify and reuse the local installation. See the
[development guide](docs/development.md) for offline setup, platform scope,
independent-consumer checks, memory checks, and API documentation generation.

## Examples

| Program | Workflow |
| --- | --- |
| [InspectAddress.lean](Examples/InspectAddress.lean) | Parse a recipient and amount, then construct an ordered payment plan. |
| [InspectTransaction.lean](Examples/InspectTransaction.lean) | Read transaction CBOR, calculate its ID, and inspect its fee, inputs, and output summaries. |
| [BuildOutput.lean](Examples/BuildOutput.lean) | Construct a multi-asset output, check its encoding through C, and decode its assets, inline datum and reference script. |

All are complete single-file programs. These offline examples do not build,
sign, or submit transactions.

### Inspect an address

[InspectAddress.lean](Examples/InspectAddress.lean) contains the complete program,
including argument validation and error reporting:

```sh
lake exe inspectAddress \
  addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz \
  2000000
```

Address parsing returns `EIO Error Address`. Amount validation and payment
construction return `Except Error ...`; combine that pure validation before
lifting it once into the effectful workflow. Parsed addresses are ordinary
Lean-owned values, with no native handles for callers to release.

`Plan.payTo` constructs a single-payment plan; `++` appends plans while retaining
order and duplicate payments. `Plan.totalLovelace_append` proves that composition
adds their requested lovelace totals. These totals exclude fees and deposits.

### Inspect a transaction

Run the example with the included synthetic, unsigned transaction:

```sh
lake exe inspectTransaction Examples/transaction.cbor.hex
```

It prints the transaction ID, declared fee and script-validity flag, spending
inputs, and each ordinary output's address and lovelace component. The fixture
spends a nonexistent input; it is for offline inspection, not submission.

The library API keeps the effectful parsing step separate from pure observations:

```lean
def inspect (cborHex : String) : EIO Cometa.Error String := do
  let transaction ← Cometa.Transaction.ofHex cborHex

  let identifier := transaction.id
  let fee := transaction.fee
  return s!"{identifier}: {fee} lovelace in fees"
```

`Transaction.toCbor` preserves every supplied byte, including body encoding,
witnesses, and outer framing. Output summaries retain complete native-reserialized
CBOR through `output.toCbor`; their `lovelace` field is only the ada component.
Parsing does not validate signatures, scripts, balances, or ledger acceptance.

### Construct a multi-asset output

```sh
lake exe buildOutput \
  addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz \
  11111111111111111111111111111111111111111111111111111111 \
  616263 1 2000000
```

This constructs an output holding 2 ADA and one unit of asset name `abc` under the
supplied synthetic policy. It attaches constructor data and a native timelock
reference script. It does not mint that asset or submit a transaction.

`Value` supports exact signed addition, subtraction, and scaling. Duplicate assets
add and zero totals disappear when inspecting or encoding the bundle. An output
must pass `Value.checkOutput`; mint/burn serialization uses separate signed bounds.
`Output.create` accepts all three datum forms and an optional reference script.

`Script.ofNative` covers signatures, all/any/threshold combinations, and validity
bounds. `Script.ofPlutus` supports V1 through V4 as opaque compiled programs, with
native-computed hashes. `PlutusData` covers constructors, ordered maps/lists,
arbitrary integers, and bytes; imported datum encodings retain their identity.
Language support does not imply activation on a particular network.

`Value.quantity_add` proves per-asset conservation under addition, and
`Value.checkOutput_sound` proves the validator's quantity guarantee.
`Output.checkNativeEncoding` runs the real C codec and returns bytes with evidence
of equality to this output's Lean encoding. That evidence is specific to the
checked result, not a universal proof of the C serializer.

## Documentation and conventions

Public definitions document their units, bounds, errors, and effects in Lean doc
comments. [CODING_CONVENTIONS.md](CODING_CONVENTIONS.md) describes layout, section
separators, validation, FFI ownership, and proof boundaries. The
[development guide](docs/development.md#api-documentation) explains how to build
the doc-gen4 reference locally.

The [implementation plan](docs/implementation-plan.md) records this milestone
and the remaining work toward complete transaction assembly, wallets, providers, and a
complete build/sign/submit workflow. The [coverage contract](docs/api-coverage.md)
requires full transaction-building parity, replaceable providers/evaluators/coin
selectors, and direct access to native instances with explicit proof boundaries.

Licensed under [Apache-2.0](LICENSE).

Release archives and the manual publication workflow are described in
[Releasing](docs/releasing.md). Reservoir indexes the GitHub repository; there is
no separate package upload to Reservoir.

### Inspect complete output fields

`Output.ofCbor` decodes legacy arrays and map outputs into checked addresses,
asset quantities, datum forms, and reference scripts. Use `EncodedOutput` when
the original representation must survive inspection:

```lean
def inspectOutput (bytes : ByteArray) : IO Unit := do
  let encoded ← (EncodedOutput.ofCbor bytes).toIO (IO.userError ∘ toString)
  let output := encoded.toOutput

  IO.println s!"Recipient: {output.address}"
  for (asset, quantity) in output.value.val.toList do
    IO.println s!"{asset}: {quantity}"

  if let some script := output.referenceScript then
    IO.println s!"Reference script: {script.hash.toHex}"
  IO.println s!"Original CBOR: {Hex.ofBytes encoded.toCbor}"
```

`encoded.toCbor` returns the exact imported bytes; `output.toCbor` produces a
fresh map encoding. `Script.ofCbor` and `EncodedPlutusData.ofCbor` likewise retain
imported bytes and their native-computed hashes while exposing `view` and
`toData`. Pure semantic decoders are available through `Value.ofOutputCbor`,
`Value.ofMintCbor`, `NativeScript.ofCbor`, and `PlutusData.ofCbor`.
These checks validate component structure and representable bounds, not ledger
acceptance. Native scripts include all seven pinned alternatives, including
Dijkstra require-guard scripts; availability still depends on the target era.
