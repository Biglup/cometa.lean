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

Typed Cardano address and transaction inspection, with payment-plan construction
for Lean 4.
The native adapter uses cardano-c **2.0.0-rc.7**; the toolchain is pinned to
**Lean 4.36.0**.

The API parses addresses and serialized transactions, validates lovelace amounts,
and models ordered payments. It does not yet unlock wallets, build transactions, sign, or submit.
Plan theorems describe the Lean model; they do not verify cardano-c or ledger execution.

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

Both are complete single-file programs. These offline examples do not build,
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

## Documentation and conventions

Public definitions document their units, bounds, errors, and effects in Lean doc
comments. [CODING_CONVENTIONS.md](CODING_CONVENTIONS.md) describes layout, section
separators, validation, FFI ownership, and proof boundaries. The
[development guide](docs/development.md#api-documentation) explains how to build
the doc-gen4 reference locally.

The [implementation plan](docs/implementation-plan.md) records this milestone
and the path toward multi-asset outputs, encrypted wallets, providers, and a
complete build/sign/submit workflow. The [coverage contract](docs/api-coverage.md)
requires full transaction-building parity, replaceable providers/evaluators/coin
selectors, and direct access to native instances with explicit proof boundaries.

Licensed under [Apache-2.0](LICENSE).

Release archives and the manual publication workflow are described in
[Releasing](docs/releasing.md). Reservoir indexes the GitHub repository; there is
no separate package upload to Reservoir.
