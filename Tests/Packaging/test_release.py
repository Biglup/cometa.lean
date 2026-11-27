# Copyright 2026 Biglup Labs
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Regression checks for release provenance, upload guards, and cache integrity."""

# IMPORTS ---------------------------------------------------------------------

import contextlib
import hashlib
import importlib.util
import io
import json
import os
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

# DEFINITIONS -----------------------------------------------------------------

ROOT = Path(__file__).resolve().parents[2]


def load(name: str, path: Path):
    """Load maintenance scripts without invoking their command-line entry points."""
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


release = load("cometa_release", ROOT / "scripts/release.py")
native = load("cometa_native", ROOT / "scripts/setup-native.py")


class ReleaseTests(unittest.TestCase):
    """Use disposable Git repositories; these fixture commits are never pushed."""

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.patch = patch.object(release, "ROOT", self.root)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        (self.root / "scripts").mkdir()
        (self.root / "scripts/setup-native.py").write_text(
            (ROOT / "scripts/setup-native.py").read_text())
        (self.root / "lakefile.lean").write_text('package cometa where\n  version := v!"0.1.0"\n')
        (self.root / "lean-toolchain").write_text("leanprover/lean4:v4.36.0\n")
        (self.root / "LICENSE").write_text("Apache-2.0\n")
        (self.root / ".gitignore").write_text(".release/\ndocs/\n__pycache__/\n")
        self.git("init", "--quiet")
        self.git("add", ".")
        self.commit()
        self.docs = self.root / "docs"
        (self.docs / "Cometa").mkdir(parents=True)
        (self.docs / "Cometa/Address.html").write_text(
            '<a href="https://github.com/Biglup/cometa.lean">source</a>')
        self.output = self.root / ".release"
        self.revision = self.git("rev-parse", "HEAD")
        self.env = patch.dict(os.environ, {"GITHUB_SHA": self.revision})
        self.env.start()
        self.addCleanup(self.env.stop)

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, text=True).strip()

    def commit(self):
        # Only disposable test fixtures use an unsigned synthetic identity.
        self.git("-c", "user.name=Release fixture", "-c", "user.email=test@example.invalid",
                 "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "Fixture")

    def prepare(self):
        with contextlib.redirect_stdout(io.StringIO()):
            release.prepare(self.output, self.docs)
        return release.verify(self.output)

    def test_archive_provenance_and_clean_contents(self):
        manifest = self.prepare()
        self.assertEqual(manifest["source_revision"], self.revision)
        with tarfile.open(self.output / "cometa-0.1.0.tar.gz") as archive:
            names = archive.getnames()
        self.assertIn("cometa-0.1.0/lakefile.lean", names)
        self.assertFalse(any("/.git/" in name or "/docs/" in name for name in names))

    def test_modified_archive_is_rejected(self):
        self.prepare()
        (self.output / "cometa-0.1.0.tar.gz").write_bytes(b"modified")
        with self.assertRaisesRegex(ValueError, "Artifact hash mismatch"):
            release.verify(self.output)

    def test_dirty_checkout_is_rejected(self):
        (self.root / "LICENSE").write_text("changed")
        with self.assertRaisesRegex(ValueError, "clean committed"):
            self.prepare()

    def test_workflow_revision_mismatch_is_rejected(self):
        with patch.dict(os.environ, {"GITHUB_SHA": "0" * 40}):
            with self.assertRaisesRegex(ValueError, "workflow revision"):
                self.prepare()

    def test_local_documentation_links_are_rejected(self):
        (self.docs / "Cometa/Address.html").write_text(
            '<a href="file:///private/source">source</a>')
        with self.assertRaisesRegex(ValueError, "Local source link"):
            self.prepare()

    def test_credential_patterns_are_rejected_without_echoing(self):
        secret = b"ghp_" + b"X" * 40
        with self.assertRaises(ValueError) as caught:
            release.check_content("example", secret)
        self.assertNotIn(secret.decode(), str(caught.exception))
        address = "https://user:password" + chr(64) + "github.com/example"
        with self.assertRaises(ValueError):
            release.check_content("link", address.encode())

    def test_branch_publication_is_rejected_before_api_calls(self):
        with patch.dict(os.environ, {"GITHUB_REF": "refs/heads/main"}):
            with patch.object(release, "api") as api:
                with self.assertRaisesRegex(ValueError, "version-matching tag"):
                    release.check_tag()
                api.assert_not_called()

    def tag_responses(self, verified=True, revision=None):
        return [
            {"object": {"type": "tag", "sha": "tag-object"}},
            {"tag": "v0.1.0", "verification": {"verified": verified},
             "object": {"type": "commit", "sha": revision or self.revision}},
        ]

    def test_signed_tag_and_target_are_verified(self):
        with patch.dict(os.environ, {"GITHUB_REF": "refs/tags/v0.1.0"}):
            with patch.object(release, "api", side_effect=self.tag_responses()):
                self.assertEqual(release.check_tag(), "v0.1.0")
            for responses in [self.tag_responses(False), self.tag_responses(revision="wrong")]:
                with patch.object(release, "api", side_effect=responses):
                    with self.assertRaisesRegex(ValueError, "signature or target"):
                        release.check_tag()

    def test_lightweight_tag_is_rejected(self):
        with patch.dict(os.environ, {"GITHUB_REF": "refs/tags/v0.1.0"}):
            with patch.object(release, "api", return_value={"object": {"type": "commit"}}):
                with self.assertRaisesRegex(ValueError, "annotated, signed"):
                    release.check_tag()

    def existing_release(self):
        return {"id": 7, "tag_name": "v0.1.0", "draft": True,
                "assets": [{"name": p.name, "digest": "sha256:" + release.sha256(p)}
                           for p in self.output.iterdir()]}

    def test_retry_does_not_replace_different_assets(self):
        self.prepare()
        existing = self.existing_release()
        existing["assets"][0]["digest"] = "sha256:wrong"
        with patch.object(release, "verify", return_value={"version": "0.1.0"}), \
                patch.object(release, "check_tag", return_value="v0.1.0"), \
                patch.object(release, "run", return_value=json.dumps(existing)) as run, \
                patch.object(release, "api") as api:
            with self.assertRaisesRegex(ValueError, "asset differs"):
                release.publish(self.output, True)
            self.assertEqual(run.call_count, 1)
            api.assert_not_called()

    def test_identical_retry_only_finalizes_after_verification(self):
        self.prepare()
        existing = self.existing_release()
        with patch.object(release, "verify", return_value={"version": "0.1.0"}), \
                patch.object(release, "check_tag", return_value="v0.1.0"), \
                patch.object(release, "run", return_value=json.dumps(existing)) as run, \
                patch.object(release, "api", side_effect=[
                    existing, {**existing, "draft": False, "prerelease": True}]) as api, \
                contextlib.redirect_stdout(io.StringIO()):
            release.publish(self.output, True)
            self.assertEqual(run.call_count, 1)
            self.assertEqual(api.call_args.args[1],
                             {"draft": False, "prerelease": True, "make_latest": "false"})

    def test_new_release_uploads_all_files_before_becoming_public(self):
        self.prepare()
        uploaded = self.existing_release()
        draft = {**uploaded, "assets": []}
        published = {**uploaded, "draft": False, "prerelease": True}
        with patch.object(release, "verify", return_value={"version": "0.1.0"}), \
                patch.object(release, "check_tag", return_value="v0.1.0"), \
                patch.object(release, "run", return_value="") as run, \
                patch.object(release, "api", side_effect=[draft, uploaded, published]) as api, \
                contextlib.redirect_stdout(io.StringIO()):
            release.publish(self.output, True)
            commands = [call.args for call in run.call_args_list]
            self.assertIn("--draft", commands[1])
            uploads = [args for args in commands if args[1:3] == ("release", "upload")]
            self.assertEqual(len(uploads), 4)
            self.assertTrue(all("--clobber" not in args for args in uploads))
            self.assertFalse(api.call_args.args[1]["draft"])

    def test_bad_uploaded_digest_keeps_release_unpublished(self):
        self.prepare()
        existing = self.existing_release()
        wrong = {**existing, "assets": []}
        with patch.object(release, "verify", return_value={"version": "0.1.0"}), \
                patch.object(release, "check_tag", return_value="v0.1.0"), \
                patch.object(release, "run", return_value=json.dumps(existing)), \
                patch.object(release, "api", return_value=wrong) as api:
            with self.assertRaisesRegex(ValueError, "draft retained"):
                release.publish(self.output, True)
            self.assertEqual(api.call_count, 1)


class NativeCacheTests(unittest.TestCase):
    """A cached installation must have intact contents before Lake can reuse it."""

    def test_corrupt_or_missing_file_invalidates_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            header = root / "header.h"
            header.write_bytes(b"valid")
            record = {"archive_sha256": "expected", "files": {
                "header.h": hashlib.sha256(b"valid").hexdigest()}}
            (root / "install.json").write_text(json.dumps(record))
            self.assertTrue(native.installed(root, "expected"))
            self.assertFalse(native.installed(root, "other-version"))
            header.write_bytes(b"corrupt")
            self.assertFalse(native.installed(root, "expected"))
            header.unlink()
            self.assertFalse(native.installed(root, "expected"))
            (root / "install.json").write_text('{"archive_sha256":"expected","files":[]}')
            self.assertFalse(native.installed(root, "expected"))


if __name__ == "__main__":
    unittest.main()
