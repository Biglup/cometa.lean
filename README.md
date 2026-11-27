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

Typed Cardano address inspection and payment-plan construction for Lean 4.
The native adapter uses cardano-c **2.0.0-rc.7**; the toolchain is pinned to
**Lean 4.36.0**.

This initial API parses addresses, validates lovelace amounts, and models ordered
payments. It does not yet unlock wallets, build transactions, sign, or submit.
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

## Example

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

## Documentation and conventions

Public definitions document their units, bounds, errors, and effects in Lean doc
comments. [CODING_CONVENTIONS.md](CODING_CONVENTIONS.md) describes layout, section
separators, validation, FFI ownership, and proof boundaries. The
[development guide](docs/development.md#api-documentation) explains how to build
the doc-gen4 reference locally.

Licensed under [Apache-2.0](LICENSE).

Release archives and the manual publication workflow are described in
[Releasing](docs/releasing.md). Reservoir indexes the GitHub repository; there is
no separate package upload to Reservoir.
