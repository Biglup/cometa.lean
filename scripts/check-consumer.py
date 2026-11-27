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

"""Compile and run the example from an independent downstream Lake package."""

# IMPORTS ---------------------------------------------------------------------

import json
import shutil
import subprocess
import tempfile
from pathlib import Path

# DEFINITIONS -----------------------------------------------------------------


def main() -> None:
    """Resolve Cometa by path without adding downstream linker flags."""
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="cometa-lean-consumer-") as directory:
        consumer = Path(directory)
        shutil.copyfile(root / "lean-toolchain", consumer / "lean-toolchain")
        shutil.copyfile(root / "Examples/InspectAddress.lean", consumer / "Main.lean")
        (consumer / "lakefile.lean").write_text(
            "import Lake\nopen Lake DSL\npackage consumer\n"
            f"require cometa from {json.dumps(str(root))}\n"
            "lean_exe inspect where\n  root := `Main\n", encoding="utf-8")
        address = "addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz"
        subprocess.run(["lake", "exe", "inspect", address, "2000000"], cwd=consumer, check=True)
        print("Independent downstream consumer passed")


if __name__ == "__main__":
    main()
