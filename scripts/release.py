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

"""Prepare, verify, and publish immutable Cometa source and documentation releases."""

# IMPORTS ---------------------------------------------------------------------

import argparse
import gzip
import hashlib
import importlib.util
import io
import json
import os
import re
import subprocess
import tarfile
import tempfile
from pathlib import Path

# DEFINITIONS -----------------------------------------------------------------

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "Biglup/cometa.lean"
CREDENTIAL = re.compile(
    rb"https?://[^/\s\"<>]+@|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}"
    rb"|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"
)


def run(*arguments: str) -> str:
    """Run a metadata command without echoing possibly sensitive diagnostics."""
    result = subprocess.run(arguments, cwd=ROOT, capture_output=True, text=True)
    if result.returncode:
        first_line = result.stderr.splitlines()[:1]
        detail = CREDENTIAL.sub(b"[REDACTED]", "".join(first_line).encode()).decode()
        raise ValueError(f"{arguments[0]} failed (exit {result.returncode}): {detail}")
    return result.stdout.strip()


def version() -> str:
    """Read the single authoritative package version from the Lake declaration."""
    match = re.search(r'^  version := v!"([0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?)"$',
                      (ROOT / "lakefile.lean").read_text(), re.M)
    if not match:
        raise ValueError("Missing or invalid Lake package version")
    return match[1]


def sha256(path: Path) -> str:
    """Hash an artifact without loading the entire file into memory."""
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def check_content(name: str, data: bytes, documentation: bool = False) -> None:
    """Reject credentials and nonportable generated source links before packaging."""
    if CREDENTIAL.search(data):
        raise ValueError(f"Credential pattern in {name}; content not printed")
    if documentation and re.search(rb'href=[\"\'](?:file:|vscode:)', data):
        raise ValueError(f"Local source link in release documentation: {name}")


def native_metadata() -> dict:
    """Read the pinned native version and platform archive hashes without installing."""
    spec = importlib.util.spec_from_file_location("cometa_native", ROOT / "scripts/setup-native.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return {"version": module.VERSION,
            "archives": {name: digest for name, digest in module.ARTIFACTS.values()}}


def write_docs(path: Path, directory: Path, prefix: str, timestamp: int) -> None:
    """Create a deterministic docs archive containing the package license."""
    if not (directory / "Cometa/Address.html").is_file():
        raise ValueError("Missing generated Cometa API documentation")
    with path.open("wb") as output, gzip.GzipFile(fileobj=output, mode="wb", mtime=0) as zipped:
        with tarfile.open(fileobj=zipped, mode="w") as archive:
            files = [(p.relative_to(directory).as_posix(), p) for p in sorted(directory.rglob("*"))
                     if p.is_file()]
            files.append(("LICENSE", ROOT / "LICENSE"))
            for name, source in files:
                data = source.read_bytes()
                check_content(name, data, documentation=True)
                info = tarfile.TarInfo(f"{prefix}/{name}")
                info.size, info.mtime, info.mode = len(data), timestamp, 0o644
                archive.addfile(info, io.BytesIO(data))


def prepare(output: Path, docs: Path) -> None:
    """Package committed source and generated docs, then record exact provenance."""
    if run("git", "status", "--porcelain"):
        raise ValueError("Release preparation requires a clean committed checkout")
    revision = run("git", "rev-parse", "HEAD")
    if os.environ.get("GITHUB_SHA", revision) != revision:
        raise ValueError("Checkout does not match the workflow revision")
    package_version = version()
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        raise ValueError("Use an empty release output directory")
    source = output / f"cometa-{package_version}.tar.gz"
    payload = subprocess.check_output([
        "git", "archive", "--format=tar", f"--prefix=cometa-{package_version}/", revision
    ], cwd=ROOT)
    with tarfile.open(fileobj=io.BytesIO(payload)) as archive:
        for entry in archive:
            if entry.isfile():
                check_content(entry.name, archive.extractfile(entry).read())
            if any(part in {".git", ".lake", ".release", "__pycache__"}
                   for part in Path(entry.name).parts):
                raise ValueError(f"Generated content in source archive: {entry.name}")
    source.write_bytes(gzip.compress(payload, mtime=0))
    documentation = output / f"cometa-{package_version}-docs.tar.gz"
    timestamp = int(run("git", "show", "-s", "--format=%ct", "HEAD"))
    write_docs(documentation, docs, f"cometa-{package_version}-docs", timestamp)
    manifest = {
        "schema_version": 1,
        "version": package_version,
        "source_revision": revision,
        "repository": REPOSITORY,
        "lean_toolchain": (ROOT / "lean-toolchain").read_text().strip(),
        "native": native_metadata(), "validated_platforms": ["linux-x86_64"],
        "files": {p.name: sha256(p) for p in [source, documentation]},
    }
    metadata = output / "manifest.json"
    metadata.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    checksums = "".join(f"{sha256(p)}  {p.name}\n" for p in [source, documentation, metadata])
    (output / "SHA256SUMS").write_text(checksums)
    print(f"Prepared Cometa {package_version} at {revision}")


def verify(directory: Path) -> dict:
    """Check the exact artifact set and every hash before any publication."""
    manifest = json.loads((directory / "manifest.json").read_text())
    package_version = version()
    expected_files = {f"cometa-{package_version}.tar.gz", f"cometa-{package_version}-docs.tar.gz"}
    if (manifest["version"] != package_version or manifest["repository"] != REPOSITORY
            or manifest["source_revision"] != run("git", "rev-parse", "HEAD")
            or manifest["lean_toolchain"] != (ROOT / "lean-toolchain").read_text().strip()
            or manifest["native"] != native_metadata()
            or set(manifest["files"]) != expected_files):
        raise ValueError("Release manifest does not match this checkout")
    hashes = dict(manifest["files"])
    hashes["manifest.json"] = sha256(directory / "manifest.json")
    expected = "".join(f"{digest}  {name}\n" for name, digest in hashes.items())
    actual = (directory / "SHA256SUMS").read_text()
    if set(actual.splitlines()) != set(expected.splitlines()):
        raise ValueError("Checksum manifest mismatch")
    if {p.name for p in directory.iterdir()} != set(hashes) | {"SHA256SUMS"}:
        raise ValueError("Unexpected or missing release artifact")
    for name, digest in hashes.items():
        if sha256(directory / name) != digest:
            raise ValueError(f"Artifact hash mismatch: {name}")
    return manifest


def api(path: str, body: dict | None = None) -> dict:
    """Call GitHub with structured JSON, never interpolating a shell command."""
    if body is None:
        return json.loads(run("gh", "api", path))
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json") as payload:
        json.dump(body, payload)
        payload.flush()
        return json.loads(run("gh", "api", "--method", "PATCH", path, "--input", payload.name))


def check_tag() -> str:
    """Require a GitHub-verified annotated version tag targeting this exact commit."""
    tag = f"v{version()}"
    if os.environ.get("GITHUB_REF") != f"refs/tags/{tag}":
        raise ValueError("Publication requires a version-matching tag, not a branch")
    reference = api(f"repos/{REPOSITORY}/git/ref/tags/{tag}")
    if reference["object"]["type"] != "tag":
        raise ValueError("Publication requires an annotated, signed tag")
    signed = api(f"repos/{REPOSITORY}/git/tags/{reference['object']['sha']}")
    if (signed["tag"] != tag or not signed["verification"]["verified"]
            or signed["object"]["type"] != "commit"
            or signed["object"]["sha"] != run("git", "rev-parse", "HEAD")):
        raise ValueError("Tag signature or target verification failed")
    return tag


def publish(directory: Path, prerelease: bool) -> None:
    """Upload exact artifacts via a draft; retries never replace existing assets."""
    manifest = verify(directory)
    tag = check_tag()
    query = f".[] | select(.tag_name == {json.dumps(tag)})"
    existing = run("gh", "api", "--paginate", f"repos/{REPOSITORY}/releases", "--jq", query)
    release = json.loads(existing) if existing else None
    if release is None:
        run("gh", "release", "create", tag, "--repo", REPOSITORY, "--verify-tag", "--draft",
            "--title", f"Cometa.lean {manifest['version']}", "--notes",
            "Source distribution and API reference. "
            "See manifest.json for toolchain and native pins.")
        release = api(f"repos/{REPOSITORY}/releases/tags/{tag}")
    assets = {a["name"]: a for a in release["assets"]}
    local = {p.name: p for p in directory.iterdir()}
    if set(assets) - set(local):
        raise ValueError("Existing release contains unexpected assets")
    # Check all existing files before uploading any missing ones.
    for name, asset in assets.items():
        if asset.get("digest") != f"sha256:{sha256(local[name])}":
            raise ValueError(f"Existing release asset differs: {name}")
    for name, path in local.items():
        if name not in assets:
            run("gh", "release", "upload", tag, str(path), "--repo", REPOSITORY)
    uploaded = api(f"repos/{REPOSITORY}/releases/{release['id']}")
    digests = {a["name"]: a.get("digest") for a in uploaded["assets"]}
    if digests != {name: f"sha256:{sha256(path)}" for name, path in local.items()}:
        raise ValueError("Uploaded release assets failed verification; draft retained")
    published = api(f"repos/{REPOSITORY}/releases/{release['id']}",
                    {"draft": False, "prerelease": prerelease, "make_latest": "false"})
    if published["draft"] or published["prerelease"] != prerelease:
        raise ValueError("GitHub release visibility or prerelease flag was not updated")
    print(f"Published https://github.com/{REPOSITORY}/releases/tag/{tag}")


def main() -> None:
    """Default to local preparation; publication is an explicit separate command."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["prepare", "verify", "check-tag", "publish"])
    parser.add_argument("--directory", type=Path, default=ROOT / ".release")
    parser.add_argument("--docs", type=Path, default=ROOT / "docbuild/.lake/build/doc")
    parser.add_argument("--stable", action="store_true", help="Publish without the prerelease flag")
    args = parser.parse_args()
    if args.command == "prepare":
        prepare(args.directory, args.docs)
    elif args.command == "verify":
        verify(args.directory)
        print("Release artifacts verified")
    elif args.command == "check-tag":
        print(check_tag())
    else:
        publish(args.directory, not args.stable)


if __name__ == "__main__":
    main()
