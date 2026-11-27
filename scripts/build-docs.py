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

"""Generate API docs with explicit, credential-free GitHub source links."""

# IMPORTS ---------------------------------------------------------------------

import html
import os
import re
import subprocess
from pathlib import Path
from urllib.parse import quote, unquote, urlsplit

# DEFINITIONS -----------------------------------------------------------------

PUBLIC = "https://github.com/Biglup/cometa.lean/blob/"
SOURCE_LINK = re.compile(r'(<a href=")([^"]+)(">source</a>)')


def rewrite_sources(document: str, root: Path, revision: str) -> str:
    """Make generated Cometa source anchors portable, including cached pages."""
    def replace(match: re.Match) -> str:
        url = html.unescape(match[2])
        parsed = urlsplit(url)
        if parsed.scheme == "file":
            path = Path(unquote(parsed.path)).resolve().relative_to(root.resolve())
        elif url.startswith(PUBLIC):
            path = Path(unquote(parsed.path.split("/blob/", 1)[1].split("/", 1)[1]))
        else:
            return match[0]
        if path != Path("Cometa.lean") and not (
                path.parts[0] == "Cometa" and path.suffix == ".lean"
                and ".." not in path.parts):
            raise ValueError("Unexpected local documentation source path")
        fragment = f"#{parsed.fragment}" if parsed.fragment else ""
        target = PUBLIC + revision + "/" + quote(path.as_posix()) + fragment
        return match[1] + html.escape(target, quote=True) + match[3]

    return SOURCE_LINK.sub(replace, document)


def main() -> None:
    """Generate without consulting Git remotes, then attach public source URLs."""
    root = Path(__file__).resolve().parents[1]
    revision = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise SystemExit("Invalid source revision")
    environment = os.environ.copy()
    environment["DOCGEN_SRC"] = "file"
    subprocess.run(["lake", "build", "Cometa:docs"], cwd=root / "docbuild",
                   env=environment, check=True)
    directory = root / "docbuild/.lake/build/doc"
    for page in [directory / "Cometa.html", *(directory / "Cometa").rglob("*.html")]:
        document = page.read_text()
        page.write_text(rewrite_sources(document, root, revision))


if __name__ == "__main__":
    main()
