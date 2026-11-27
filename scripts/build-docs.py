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

import os
import subprocess
from urllib.parse import urlsplit
from pathlib import Path

# DEFINITIONS -----------------------------------------------------------------


def main() -> None:
    """Override Git configuration only for the documentation subprocess tree."""
    root = Path(__file__).resolve().parents[1]
    environment = os.environ.copy()
    # Do not inherit authenticated URL rewrites from a developer's Git config.
    for key in list(environment):
        if key.startswith("GIT_CONFIG_") or key == "GIT_CONFIG":
            del environment[key]
    environment.update({
        "DOCGEN_SRC": "github",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": os.devnull,
        "GIT_CONFIG_COUNT": "1",
        "GIT_CONFIG_KEY_0": "remote.origin.url",
        "GIT_CONFIG_VALUE_0": "https://github.com/Biglup/cometa.lean",
    })
    remote = subprocess.check_output(
        ["git", "remote", "get-url", "origin"], cwd=root, env=environment, text=True)
    if urlsplit(remote.strip()).username is not None:
        raise SystemExit("Refusing documentation generation with an authenticated Git URL")
    subprocess.run(["lake", "build", "Cometa:docs"], cwd=root / "docbuild",
                   env=environment, check=True)


if __name__ == "__main__":
    main()
