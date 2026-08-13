#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
python3 - "$ROOT" <<'PY'
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1])
cases = json.loads((root / "tests/fixtures/install-state-cases.json").read_text())
fields = json.loads((root / "scripts/lib/install-state-schema.json").read_text())["fields"]

with tempfile.TemporaryDirectory() as temporary:
    temp = Path(temporary)
    home = temp / "home"
    install_dir = temp / "squarebox"
    state_dir = install_dir / ".squarebox"
    home.mkdir()
    state_dir.mkdir(parents=True)
    base = {
        "FORMAT": "1",
        "INSTALL_ID": "test-install-123",
        "RUNTIME": "docker",
        "INSTALL_DIR": str(install_dir),
        "WORKSPACE_DIR": str(temp / "workspace"),
        "GIT_CONFIG_DIR": str(install_dir / ".squarebox/identity/git"),
        "HOME_VOLUME": "squarebox-home",
        "CONTAINER_NAME": "squarebox",
        "IMAGE_ALIAS": "squarebox",
        "IMAGE_REPOSITORY": "ghcr.io/squarewavesystems/squarebox",
        "IMAGE_REF": "ghcr.io/squarewavesystems/squarebox@sha256:" + "b" * 64,
        "IMAGE_ID": "sha256:" + "c" * 64,
        "IMAGE_DIGEST": "ghcr.io/squarewavesystems/squarebox@sha256:" + "b" * 64,
        "SOURCE_REF": "v1.2.3",
        "SOURCE_COMMIT": "a" * 40,
        "RELEASE_TAG": "v1.2.3",
        "REQUESTED_TAG": "latest",
        "PUID": "1000",
        "PGID": "1000",
        "BUILD": "0",
        "EDGE": "0",
        "SHELL_INIT": str(home / ".squarebox-shell-init"),
        "SHELL_RC": str(home / ".bashrc"),
        "ORIGIN": "https://github.com/SquareWaveSystems/squarebox.git",
        "HOME_VOLUME_ADOPTED": "0",
    }
    env = os.environ.copy()
    env.update({
        "HOME": str(home),
        "SQUAREBOX_DIR": str(install_dir),
        "SQUAREBOX_LIFECYCLE_FUNCTIONS_ONLY": "1",
    })
    for case in cases:
        values = base.copy()
        for key, value in case.get("set", {}).items():
            values[key] = value.replace("{ROOT}", str(temp))
        removed = set(case.get("remove", []))
        lines = [f"{field}={values[field]}" for field in fields if field not in removed]
        lines.extend(case.get("append", []))
        newline = "\r\n" if case.get("encoding") == "crlf" else "\n"
        state_file = state_dir / "install-state"
        state_file.write_bytes((newline.join(lines) + newline).encode())
        for adapter in ("install.sh", "uninstall.sh"):
            load = 'load_state "$STATE_FILE"' if adapter == "install.sh" else 'load_state'
            command = f'adapter=$1; set --; source "$adapter"; {load}'
            result = subprocess.run(
                ["bash", "-c", command, "fixture", str(root / adapter)],
                env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            )
            accepted = result.returncode == 0
            if accepted != case["accept"]:
                outcome = "accepted" if accepted else "rejected"
                detail = result.stderr.strip() or result.stdout.strip()
                raise SystemExit(f"{adapter} {outcome} {case['name']}: {detail}")

print(f"ok - Bash lifecycle adapters agree on {len(cases)} shared Install identity fixtures")
PY
