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

"""Install the pinned cardano-c release into this package's private build directory."""

# IMPORTS ---------------------------------------------------------------------

import argparse
import hashlib
import json
import os
import platform
import shutil
import tarfile
import tempfile
import urllib.request
from pathlib import Path

# DEFINITIONS -----------------------------------------------------------------

VERSION = "2.0.0-rc.7"
ARTIFACTS = {
    ("Linux", "x86_64"): (
        "linux-x86_64-gcc",
        "8577844997cdd7ec9e3982e22bd2db5f75ec4e58cb8b39684eefd22cb1b981a6",
    ),
    ("Linux", "aarch64"): (
        "linux-arm64-gcc",
        "92a6c2b5980764fe659b4e2df5e59f31eee869d8ad97297658802343b03c050f",
    ),
    ("Darwin", "arm64"): (
        "macos-arm64-gcc",
        "2925c07a70e305067b16cdc4488ee6e2a8d200f3c6e676c8f2593b5afcd9515c",
    ),
    ("Darwin", "x86_64"): (
        "macos-x86_64-gcc",
        "e8a78793c423978e8fa4585febb87d478fb9268e1ed6720b3b1cb05003d72434",
    ),
}


def installed(destination: Path, expected: str) -> bool:
    """Check the cached installation, including every header and native library."""
    try:
        record = json.loads((destination / "install.json").read_text())
        files = record["files"]
        if record["archive_sha256"] != expected or not isinstance(files, dict) or not files:
            return False
        for name, digest in record["files"].items():
            path = destination / name
            if not path.resolve().is_relative_to(destination.resolve()):
                return False
            if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
                return False
        return True
    except (OSError, ValueError, KeyError, TypeError):
        return False


def install_locked(archive: Path | None, ensure: bool) -> None:
    """Verify the platform archive before extracting its headers and shared library."""
    target = ARTIFACTS.get((platform.system(), platform.machine()))
    if target is None:
        raise SystemExit("No pinned native archive is configured for this platform")
    suffix, expected = target
    destination = Path(__file__).resolve().parents[1] / ".lake" / "native"
    destination.parent.mkdir(parents=True, exist_ok=True)
    if ensure and installed(destination, expected):
        return

    with tempfile.TemporaryDirectory(dir=destination.parent) as temporary:
        staging = Path(temporary)
        downloaded = staging / "native.tar.gz"
        if archive is None:
            name = f"libcardano-c-{VERSION}-{suffix}.tar.gz"
            url = f"https://github.com/Biglup/cardano-c/releases/download/v{VERSION}/{name}"
            with (
                urllib.request.urlopen(url, timeout=120) as response,
                downloaded.open("wb") as output,
            ):
                shutil.copyfileobj(response, output)
        else:
            shutil.copyfile(archive, downloaded)
        if hashlib.sha256(downloaded.read_bytes()).hexdigest() != expected:
            raise SystemExit("Native archive SHA256 mismatch; nothing installed")

        extracted = staging / "extracted"
        with tarfile.open(downloaded) as package:
            package.extractall(extracted, filter="data")
        files = {
            path.relative_to(extracted).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(extracted.rglob("*")) if path.is_file()
        }
        record = {"archive_sha256": expected, "files": files}
        (extracted / "install.json").write_text(json.dumps(record, sort_keys=True) + "\n")
        # Preserve the working installation until the verified replacement is ready.
        previous = staging / "previous"
        if destination.exists():
            destination.rename(previous)
        try:
            extracted.rename(destination)
        except OSError:
            if previous.exists():
                previous.rename(destination)
            raise
    print(f"Installed cardano-c {VERSION}: {destination}")


def install(archive: Path | None, ensure: bool = False) -> None:
    """Serialize concurrent Lake builds sharing this package's native directory."""
    if platform.system() not in {"Linux", "Darwin"}:
        raise SystemExit("Automatic native setup currently supports Linux and macOS")
    import fcntl

    cache = Path(__file__).resolve().parents[1] / ".lake"
    cache.mkdir(parents=True, exist_ok=True)
    with (cache / "native.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        install_locked(archive, ensure)


def main() -> None:
    """Accept an optional offline archive; never bypass checksum verification."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, help="Use a previously downloaded platform archive")
    parser.add_argument("--ensure", action="store_true", help="Reuse a verified installation")
    args = parser.parse_args()
    offline = os.environ.get("COMETA_NATIVE_ARCHIVE")
    install(args.archive or (Path(offline) if offline else None), args.ensure)


if __name__ == "__main__":
    main()
