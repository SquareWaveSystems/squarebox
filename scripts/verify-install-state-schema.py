#!/usr/bin/env python3
"""Fail when a FORMAT=1 lifecycle adapter drifts from its schema contract."""

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCHEMA = json.loads((ROOT / "scripts/lib/install-state-schema.json").read_text())
EXPECTED = SCHEMA["fields"]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"install-state schema drift: {message}")


def powershell_fields(text: str, name: str) -> None:
    match = re.search(r"\$StateFields = @\((.*?)\n\)", text, re.S)
    require(match is not None, f"{name} has no closed field set")
    actual = re.findall(r"'([A-Z_]+)'", match.group(1))
    require(actual == EXPECTED, f"{name} field order is {actual}")


def bash_fields(text: str, name: str) -> None:
    match = re.search(r'^STATE_KEYS="([A-Z_ ]+)"$', text, re.M)
    require(match is not None, f"{name} has no closed field set")
    require(match.group(1).split() == EXPECTED, f"{name} field order differs")
    load = text.split("load_state() {", 1)[1].split("\n}", 1)[0]
    whitelist = re.search(r'case "\$key" in\n\s*([A-Z_|]+)\)', load)
    require(whitelist is not None, f"{name} has no parser field whitelist")
    require(whitelist.group(1).split("|") == EXPECTED, f"{name} parser whitelist differs")


texts = {name: (ROOT / name).read_text() for name in (
    "install.sh", "uninstall.sh", "install.ps1", "uninstall.ps1"
)}
for name in ("install.sh", "uninstall.sh"):
    bash_fields(texts[name], name)
for name in ("install.ps1", "uninstall.ps1"):
    powershell_fields(texts[name], name)

bash_writer = texts["install.sh"].split("write_state() {", 1)[1].split("\n}", 1)[0]
require(re.findall(r"([A-Z_]+)=", bash_writer) == EXPECTED,
        "install.sh writer order differs")
ps_writer = texts["install.ps1"].split("$stateLines = @(", 1)[1].split("\n)", 1)[0]
require(re.findall(r'["\']([A-Z_]+)=', ps_writer) == EXPECTED,
        "install.ps1 writer order differs")

for name, text in texts.items():
    require("install-state" in text, f"{name} does not identify the state artifact")
    require(not re.search(r'^\s*(?:source|\.)\s+[^\n]*install-state', text, re.M),
            f"{name} executes Install identity data")

for name in ("install.sh", "uninstall.sh"):
    text = texts[name]
    require("*//*|*/../*|*/..|*/./*|*/." in text,
            f"{name} does not reject non-normalized paths")
    require("0:0:0|0:0:1|1:0:0|1:0:1|1:1:0|1:1:1" in text,
            f"{name} does not enforce EDGE requires BUILD")
for name in ("install.ps1", "uninstall.ps1"):
    text = texts[name]
    require("[IO.Path]::GetFullPath($Value)" in text and "$Value -ceq $full" in text,
            f"{name} does not enforce normalized paths")
    require("$pathTail -match '[\\\\/]{2,}'" in text,
            f"{name} does not reject repeated path separators consistently")
    require("$State.EDGE -eq '1' -and $State.BUILD -ne '1'" in text,
            f"{name} does not enforce EDGE requires BUILD")

print("ok - Install identity adapters match the authoritative FORMAT=1 schema")
