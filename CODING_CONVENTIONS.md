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

# Coding conventions

## Lean

Use the pinned toolchain and ordinary Lean syntax: two-space indentation,
`UpperCamelCase` types/modules, `lowerCamelCase` definitions, and descriptive
`snake_case` theorem names. Prefer Lean's `ofString`/`ofNat` constructor vocabulary
and `toString`/`toBytes` observations; reserve `?` for optional results and avoid
partial `!` APIs for ordinary input handling. Put imports before module documentation and namespace
contents. Group substantial files with ordinary `-- TYPES`, `-- DEFINITIONS`,
`-- THEOREMS`, or `-- FOREIGN IMPORTS` separators. Avoid empty sections and a
separator for every definition.

Write `/-- ... -/` documentation for public definitions, types, fields, and
constructors, and `/-! ... -/` module introductions. Explain units, accepted input,
ordering, bounds, errors, and effects. Put native ownership details in internal
modules. Missing-documentation and compiler warnings are errors in package builds.

Prefer small named steps and blank lines between validation, acquisition, and
results. Use direct `do` notation rather than dense compositions. Give public
functions explicit types. Keep examples complete and runnable, with clear names
and a single application error boundary.

Use `Except Error` for pure validation and `EIO Error` for fallible effects. Convert
system errors explicitly when integrating `IO`. Use `Option` for legitimate
absence. Avoid unchecked indexing, panic-based validation, or printing secrets.
Do not introduce a custom effects framework or type classes without a concrete
caller workflow that benefits from them.

Use proof-bearing values where an invariant is naturally expressible in Lean.
Provide ordinary checked constructors for runtime input. Do not derive instances
that bypass validation. Check private constructor and record-update boundaries.
Only claim laws actually proved; keep the distinction between a Lean model and
native behavior explicit. Do not claim that FFI execution is kernel-verified.

## Native adapter

Use C11 and ClangFormat 18 with the checked-in configuration. Use the C binding's
section separators and document ownership beside each entry point. Inspect the
pinned Lean compiler's generated C declarations; ABI details can change between
Lean versions. Borrow inputs only for the duration of a call, copy borrowed native
buffers, and release native references on every recoverable path.

Keep raw entry points internal. Native allocation failure may be returned as a
domain error; Lean runtime allocation failure is not a recoverable `EIO` promise.
Scope secrets explicitly when wallet operations are introduced. A finalizer alone
is not a secret-lifetime design.

## Supporting files

Python uses four-space indentation, type annotations, and short documented helper
functions. Downloads must use HTTPS, immutable version pins, and checked hashes.
Do not alter the user's global toolchain or Git configuration.

Each authored text file carries the Biglup Labs copyright and Apache-2.0 notice.
Comment-free metadata uses an adjacent `.license` file. Preserve upstream notices
when importing code or vectors, and record their revision and license.
