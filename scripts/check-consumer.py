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

"""Build and run a downstream application from clean source, with no native setup."""

# IMPORTS ---------------------------------------------------------------------

import argparse
import json
import shutil
import subprocess
import tarfile
import tempfile
from pathlib import Path

# DEFINITIONS -----------------------------------------------------------------


def unpack(archive: Path, destination: Path) -> Path:
    """Extract one source-package root using Python's safe data filter."""
    with tarfile.open(archive) as source:
        source.extractall(destination, filter="data")
    roots = list(destination.iterdir())
    if len(roots) != 1 or not (roots[0] / "Cometa.lean").is_file():
        raise ValueError("Expected one Cometa source package")
    return roots[0]


def verify(source: Path, consumer: Path) -> None:
    """Let Lake prepare native dependencies without extra downstream linker flags."""
    if (source / ".lake").exists():
        raise ValueError("Consumer verification requires clean source without a Lake cache")
    consumer.mkdir()
    shutil.copyfile(source / "lean-toolchain", consumer / "lean-toolchain")
    shutil.copyfile(source / "Examples/InspectAddress.lean", consumer / "Main.lean")
    shutil.copyfile(source / "Examples/InspectTransaction.lean", consumer / "TransactionMain.lean")
    (consumer / "lakefile.lean").write_text(
        "import Lake\nopen Lake DSL\npackage consumer\n"
        f"require cometa from {json.dumps(str(source))}\n"
        "lean_exe inspect where\n  root := `Main\n"
        "lean_exe inspectTransaction where\n  root := `TransactionMain\n", encoding="utf-8")
    address = "addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz"
    subprocess.run(["lake", "exe", "inspect", address, "2000000"], cwd=consumer, check=True)
    subprocess.run(["lake", "exe", "inspectTransaction",
                    str(source / "Examples/transaction.cbor.hex")], cwd=consumer, check=True)
    print("Clean-source downstream consumer passed (automatic native setup)")


def main() -> None:
    """Verify a release archive, or a clean copy of the current working source."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="cometa-lean-consumer-") as directory:
        temporary = Path(directory)
        if args.archive:
            source = unpack(args.archive, temporary / "source")
        else:
            source = temporary / "source"
            shutil.copytree(root, source, ignore=shutil.ignore_patterns(
                ".git", ".lake", "__pycache__", ".release"))
        verify(source, temporary / "consumer")


if __name__ == "__main__":
    main()
