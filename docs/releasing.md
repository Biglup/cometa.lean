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

# Releasing

The manual `Release` workflow prepares source and API documentation archives. Its
default `publish=false` runs every check and uploads workflow artifacts without
creating a GitHub release. Nothing is published automatically on a push or tag.
Merge the workflow into `main` before its first manual invocation.

## Preparation and checks

Both PR CI and the release workflow use the same validation job:

1. Check licenses, source formatting, and release-tool regression tests.
2. Build with automatic native setup, run native tests, constructor and interpreter
   checks, independently check the plan module, and run Valgrind.
3. Generate API documentation with credential-free GitHub source links.
4. Archive committed source and docs; record the source commit, Lean toolchain,
   native version and platform archive hashes in `manifest.json`.
5. Verify all artifact hashes and build an independent application from the source
   archive, starting without a native installation or Lake cache.

Only Linux x86_64 is release-validated currently. The assets are source and HTML
archives, not precompiled Lean libraries or portable executable bundles.

Run preparation from Actions, or after the workflow is merged:

```sh
gh workflow run release.yml --ref main -f publish=false
```

Download the `release-packages` artifact from that run. It contains:

- `cometa-VERSION.tar.gz`: committed package source, including native setup tooling.
- `cometa-VERSION-docs.tar.gz`: generated API reference and license.
- `manifest.json`: versions, source revision, and artifact hashes.
- `SHA256SUMS`: checksums for both archives and the manifest.

For local preparation, use a clean committed checkout with the pinned toolchain:

```sh
lake build cometaTests inspectAddress
lake test
python3 scripts/build-docs.py
python3 scripts/release.py prepare
python3 scripts/release.py verify
python3 scripts/check-consumer.py --archive .release/cometa-VERSION.tar.gz
```

The default output is `.release/`, which is ignored by Git. Use a new, empty output
directory on each preparation; existing artifacts are not overwritten.

## Publication

Set the intended version in `lakefile.lean`, merge the release changes, and create
an annotated tag signed with the repository's configured maintainer identity.
Replace `VERSION` and `COMMIT` below with the intended release values:

```sh
git tag -s vVERSION COMMIT -m "Cometa.lean VERSION"
git verify-tag vVERSION
git push origin vVERSION
gh workflow run release.yml --ref vVERSION -f publish=true -f prerelease=true
```

Publication requires a tag named exactly `v` followed by the package version.
GitHub must verify its signature, and the tag must directly target the exact
checkout commit. Branches, lightweight tags, and mismatched targets are rejected.
The full validation job runs again before publication.

Only the publication job receives `contents: write`; it uses GitHub's workflow
token and the `release` environment. No npm, Hackage, or Reservoir token is needed.
The job verifies the downloaded artifacts, creates a draft release, uploads the
files, verifies GitHub's asset digests, and only then publishes it. Prerelease is
the default; set `prerelease=false` explicitly when a stable release is intended.
The workflow does not move GitHub's latest-release designation.

Retries reuse matching assets. A different existing asset or an unexpected file
stops publication instead of replacing it. If an upload fails, inspect the draft
and rerun the failed publication job, which uses the same prepared artifact.
Do not regenerate a release under the same version to bypass an integrity failure.

## Reservoir

Reservoir automatically indexes qualifying public GitHub repositories. Keep the
root `lake-manifest.json`, recognized OSI-approved license, and pinned toolchain
committed. Its current inclusion rules also require at least two GitHub stars and
exclude forks. Indexing is approximately daily:
[Reservoir inclusion criteria](https://reservoir.lean-lang.org/inclusion-criteria).

Git tags provide versioned dependencies even before indexing. Cometa's first
release must describe its implemented API accurately; release automation does
not imply that wallet, signing, or provider functionality is already implemented.
