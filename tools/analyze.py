#!/usr/bin/env python3
"""Strict type analysis with Roblox globals, without Studio.

luau-analyze cannot follow Roblox instance-path requires (`require(script.Parent.X)`), so this
script mirrors src/ into build/analyze/ with those requires rewritten to string paths the
analyzer resolves, then runs the (patched) luau-analyze with tools/globalTypes.d.luau.
Line numbers are preserved, so reported positions apply to the real files.

Usage: tools/analyze.py [src/shared src/server ...]   (default: all of src/)
"""
import os
import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MIRROR = ROOT / "build" / "analyze"
DEFS = ROOT / "tools" / "globalTypes.d.luau"

# service/folder -> source dir (mirrors default.project.json)
MOUNTS = {
    ("ReplicatedStorage", "EoE"): "src/shared",
    ("ServerScriptService", "EoE"): "src/server",
    ("ServerStorage", "EoE"): "src/server",
}

ROOT_RE = re.compile(
    r'^\s*local\s+(\w+)\s*=\s*game:GetService\("(\w+)"\)(?::WaitForChild\("(\w+)"\)|\.(\w+))\s*$'
)
SERVICE_RE = re.compile(r'^\s*local\s+(\w+)\s*=\s*game:GetService\("(\w+)"\)\s*$')
SERVICE_CHILD_RE = re.compile(r'^\s*local\s+(\w+)\s*=\s*(\w+)(?::WaitForChild\("(\w+)"\)|\.(\w+))\s*$')
ALIAS_RE = re.compile(r'^\s*local\s+(\w+)\s*=\s*(\w+)((?:\.\w+)+)\s*$')
REQ_RE = re.compile(r'require\(([\w.]+)\)')
SERVICE_CALL_RE = re.compile(r'game:GetService\("(\w+)"\)')

# Ignore list: diagnostics that are noise for this project (none yet).
IGNORE = ("Variable 'Shared' is never used",)


def rel_require(from_file: pathlib.Path, target: pathlib.Path) -> str:
    """Relative string path from the requiring file's directory to the target module."""
    base = from_file.parent
    if from_file.name == "init.luau":
        base = from_file.parent.parent  # per the Luau require spec, init.luau's "./" is its folder's parent
    rel = os.path.relpath(target, base).replace(os.sep, "/")
    if not rel.startswith("."):
        rel = "./" + rel
    return rel


def resolve_chain(from_file: pathlib.Path, chain: list[str], roots: dict) -> pathlib.Path | None:
    """Turn ['script','Parent','Parent','X'] or ['Shared','X'] into a module path."""
    head, *rest = chain
    if head == "script":
        node = from_file if from_file.name != "init.luau" else from_file.parent
        for part in rest:
            if part == "Parent":
                node = node.parent if node.suffix != ".luau" else node.parent
                if node.name.endswith(".luau"):
                    node = node.parent
            else:
                node = node / part
        return node
    if head in roots:
        node = roots[head]
        for part in rest:
            node = node / part
        return node
    return None


def to_module_file(node: pathlib.Path) -> pathlib.Path | None:
    """Map a logical node path (without extension) to an actual .luau file."""
    if node.suffix == ".luau" and node.exists():
        return node
    for cand in (node.with_suffix(".luau"), node / "init.luau"):
        if cand.exists():
            return cand
    for suffix in (".server.luau", ".client.luau"):
        cand = node.with_name(node.name + suffix)
        if cand.exists():
            return cand
    return None


def rewrite(src_file: pathlib.Path, text: str) -> str:
    roots: dict[str, pathlib.Path] = {}
    services: dict[str, str] = {}
    out_lines = []
    for line in text.splitlines():
        m = SERVICE_RE.match(line)
        if m:
            services[m.group(1)] = m.group(2)
            out_lines.append(line)
            continue
        m = SERVICE_CHILD_RE.match(line)
        if m and m.group(2) in services:
            mount = MOUNTS.get((services[m.group(2)], m.group(3) or m.group(4)))
            if mount:
                roots[m.group(1)] = ROOT / mount
            out_lines.append(line)
            continue
        m = ROOT_RE.match(line)
        if m:
            name, service, folder = m.group(1), m.group(2), m.group(3) or m.group(4)
            mount = MOUNTS.get((service, folder))
            if mount:
                roots[name] = ROOT / mount
            out_lines.append(line)
            continue
        m = ALIAS_RE.match(line)
        if m and m.group(2) in roots:
            roots[m.group(1)] = roots[m.group(2)].joinpath(*m.group(3).strip(".").split("."))
            out_lines.append(line)
            continue
        if m and m.group(2) == "script":
            node = resolve_chain(src_file, ["script"] + m.group(3).strip(".").split("."), roots)
            if node is not None:
                roots[m.group(1)] = node
            out_lines.append(line)
            continue

        def repl(mm: re.Match) -> str:
            chain = mm.group(1).split(".")
            node = resolve_chain(src_file, chain, roots)
            if node is None:
                return mm.group(0)
            target = to_module_file(node)
            if target is None:
                return mm.group(0)
            logical = target
            if logical.name == "init.luau":
                logical = logical.parent
            else:
                logical = logical.with_suffix("")
                if logical.suffix in (".server", ".client"):
                    logical = logical.with_suffix("")
            rel = rel_require(src_file, logical)
            return f'require("{rel}")'

        line = REQ_RE.sub(repl, line)
        # The analyzer has no luau-lsp magic for GetService: cast to the service type in the mirror.
        line = SERVICE_CALL_RE.sub(r'(game:GetService("\1") :: \1)', line)
        out_lines.append(line)
    return "\n".join(out_lines) + "\n"


def main() -> int:
    targets = [pathlib.Path(a) for a in sys.argv[1:]] or [ROOT / "src"]
    if MIRROR.exists():
        shutil.rmtree(MIRROR)
    files = []
    for p in sorted((ROOT / "src").rglob("*.luau")):
        dest = MIRROR / p.relative_to(ROOT)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(rewrite(p, p.read_text(encoding="utf-8")), encoding="utf-8")
        if any(p.resolve().is_relative_to((ROOT / t).resolve()) for t in targets):
            files.append(dest)
    # the mirror must contain the whole tree so cross-module requires resolve
    luau_analyze = shutil.which("luau-analyze") or os.path.expanduser("~/.local/bin/luau-analyze")
    cmd = [luau_analyze, "--mode=strict", "--solver=new", f"--definitions={DEFS}", "--formatter=plain"] + [str(f) for f in files]
    proc = subprocess.run(cmd, capture_output=True, text=True, cwd=MIRROR)
    out = proc.stdout + proc.stderr
    count = 0
    for line in out.splitlines():
        if not line.strip() or any(s in line for s in IGNORE):
            continue
        line = line.replace(str(MIRROR) + "/", "").replace("./", "", 1) if line.startswith("./") else line.replace(str(MIRROR) + "/", "")
        print(line)
        count += 1
    print(f"{count} diagnostics in {len(files)} files")
    return 1 if count else 0


if __name__ == "__main__":
    sys.exit(main())
