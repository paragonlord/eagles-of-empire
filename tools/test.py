#!/usr/bin/env python3
"""Bundle src/ + tests/ into one Luau chunk and run it in the Luau CLI (no Roblox needed).

Usage: tools/test.py [-k filter] [--keep]
Tree mapping mirrors default.project.json:
  src/shared -> ReplicatedStorage/EoE, src/server -> ServerScriptService/EoE,
  src/client -> StarterPlayer/StarterPlayerScripts/EoEClient, tests -> Tests
"""
import argparse
import json
import os
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MOUNTS = {
    "src/shared": "ReplicatedStorage/EoE",
    "src/server": "ServerScriptService/EoE",
    "src/client": "StarterPlayer/StarterPlayerScripts/EoEClient",
    "tests": "Tests",
}


def luau_string(s: str) -> str:
    level = 0
    while f"]{'=' * level}]" in s:
        level += 1
    eq = "=" * level
    return f"[{eq}[\n{s}]{eq}]"


def collect():
    sources = {}
    for src_dir, mount in MOUNTS.items():
        base = ROOT / src_dir
        if not base.exists():
            continue
        for p in sorted(base.rglob("*.luau")):
            rel = p.relative_to(base).with_suffix("")
            key = f"{mount}/{rel.as_posix()}"
            sources[key] = p.read_text(encoding="utf-8")
    return sources


def bundle(filter_: str | None) -> str:
    prelude = (ROOT / "tools" / "prelude.luau").read_text(encoding="utf-8")
    entries = ",\n".join(f"  [{json.dumps(k)}] = {luau_string(v)}" for k, v in collect().items())
    table = "{\n" + entries + "\n}"
    out = prelude.replace("__SOURCES__", table, 1)
    out = out.replace("__FILTER__", repr(filter_) if filter_ else "nil", 1)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("-k", dest="filter", default=None)
    ap.add_argument("--keep", action="store_true")
    args = ap.parse_args()
    luau = shutil.which("luau") or os.path.expanduser("~/.local/bin/luau")
    if not os.path.exists(luau):
        print("luau CLI not found (build from luau-lang/luau or put it on PATH)", file=sys.stderr)
        return 2
    build = ROOT / "build"
    build.mkdir(exist_ok=True)
    bundle_path = build / "test_bundle.luau"
    bundle_path.write_text(bundle(args.filter), encoding="utf-8")
    rc = subprocess.call([luau, "-O1", str(bundle_path)])
    if not args.keep and rc == 0:
        bundle_path.unlink(missing_ok=True)
    return rc


if __name__ == "__main__":
    sys.exit(main())
