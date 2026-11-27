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
python3 scripts/setup-native.py
lake build cometaTests inspectAddress
lake test
lake lean Tests/Invariants.lean
lake env leanchecker Cometa.Plan
python3 scripts/check-source.py
python3 scripts/check-consumer.py
clang-format-18 --dry-run --Werror cbits/cometa_lean.c
```

The setup script downloads cardano-c **2.0.0-rc.7**, verifies its SHA256, and installs
it under `.lake/native`. For an offline build, pass `--archive /path/to/archive`.
`lake clean` may remove prepared artifacts; rerun setup when needed. No native
files or toolchain binaries belong in Git.

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
cd docbuild
lake update
DOCGEN_SRC=file lake build Cometa:docs
python3 -m http.server --directory .lake/build/doc 8000
```

The generated reference is local; no hosted documentation deployment is claimed.
Use local source links during development. The generator's default GitHub mode
reads Git remote URLs, which may contain authentication information. Only use
GitHub source links in a publishing environment with credential-free remote URLs.

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
