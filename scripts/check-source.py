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

"""Check license coverage, whitespace, and forbidden proof placeholders."""

# IMPORTS ---------------------------------------------------------------------

import re
from pathlib import Path

# DEFINITIONS -----------------------------------------------------------------


def main() -> None:
    """Inspect authored files, excluding Git metadata and generated Lake artifacts."""
    root = Path(__file__).resolve().parents[1]
    failures: list[str] = []
    excluded = {".git", ".lake", ".release", "__pycache__", "assets"}
    for path in root.rglob("*"):
        relative = path.relative_to(root)
        if not path.is_file() or excluded.intersection(relative.parts):
            continue
        if path.name == "LICENSE":
            continue
        text = path.read_text(encoding="utf-8")
        notice = text
        if path.name in {"lean-toolchain", "lake-manifest.json"}:
            sidecar = path.with_name(path.name + ".license")
            notice = sidecar.read_text(encoding="utf-8")
        if "SPDX-License-Identifier: Apache-2.0" not in notice:
            failures.append(f"{relative}: missing license notice")
        if not text.endswith("\n") or any(line.rstrip() != line for line in text.splitlines()):
            failures.append(f"{relative}: trailing whitespace or missing final newline")
        forbidden = r"\b(sorry|admit)\b|^\s*(axiom|unsafe)\s"
        if path.suffix == ".lean" and re.search(forbidden, text, re.M):
            failures.append(f"{relative}: proof placeholder or unaudited unsafe declaration")
    if failures:
        raise SystemExit("\n".join(failures))
    print("Source license, whitespace, and proof-placeholder checks passed")


if __name__ == "__main__":
    main()
