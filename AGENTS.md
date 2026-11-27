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

# Repository instructions

Read [CODING_CONVENTIONS.md](CODING_CONVENTIONS.md) before editing.

- Build complete, small workflows before expanding the API. Keep examples in one
  file with named steps and one error boundary; never imply a plan was submitted.
- Inspect pinned Lean and native source before changing an FFI declaration.
  Audit generated C signatures, borrowing, result layout, and every reference.
- Keep native effects in `EIO` or `BaseIO`. No unproved axioms, `sorry`, or unsafe
  implementation shortcuts in public APIs or theorems.
- Run the checks in `docs/development.md`; report platform and live-network limits.
- Use the repository-local Git identity and signing key. Before pushing a commit,
  verify its signature and intended identity; do not override them with globals.
- Never commit credentials, private keys, native build products, or tool caches.
- Keep Apache-2.0 notices and logical section separators in authored source files.
  Use sidecar `.license` files for formats that cannot contain comments.

- Treat `docs/api-coverage.md` as the full transaction-construction scope. Update
  affected coverage when adding APIs; small workflows do not reduce parity goals.
- Keep providers, evaluators, coin selectors, and signers replaceable. Expose the
  concrete C instances through audited adapters as well as custom Lean callbacks.
- Separate pure proofs and proved result validators from native conformance tests.
  Never assert C correctness as an axiom or infer it from successful FFI execution.
