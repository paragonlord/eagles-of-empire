#!/usr/bin/env python3
"""Build build/EaglesOfEmpire.rbxlx from default.project.json without Rojo.

Supports the subset of the Rojo project format this repo uses: $className, $path,
$properties (bool / number / string / Color3 as [r,g,b] / {"Enum": n} / {"Content": url}),
nested folders, and the
.server.luau / .client.luau / init.luau naming rules. Output is a real XML place file that
Roblox Studio opens directly (File > Open from file).
"""
import json
import pathlib
import sys
from xml.sax.saxutils import escape

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "build" / "EaglesOfEmpire.rbxlx"
SYNC = ROOT / "build" / "sync.json"  # script manifest for tools/studio_sync.luau

_scripts: list = []  # {path: [instance names from the service], class, file}

_ref = 0


def ref() -> str:
    global _ref
    _ref += 1
    return f"RBX{_ref:08d}"


def cdata(s: str) -> str:
    return "<![CDATA[" + s.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def prop_xml(name: str, value) -> str:
    if isinstance(value, bool):
        return f'<bool name="{name}">{"true" if value else "false"}</bool>'
    if isinstance(value, (int, float)):
        return f'<float name="{name}">{value}</float>' if name not in ("CameraMaxZoomDistance",) else f'<float name="{name}">{value}</float>'
    if isinstance(value, str):
        return f'<string name="{name}">{escape(value)}</string>'
    if isinstance(value, dict) and "Enum" in value:  # Rojo's explicit form: {"Enum": 1280}
        return f'<token name="{name}">{int(value["Enum"])}</token>'
    if isinstance(value, dict) and "Content" in value:  # {"Content": "rbxassetid://..."}
        return f'<Content name="{name}"><url>{escape(value["Content"])}</url></Content>'
    if isinstance(value, list) and len(value) == 3:
        r, g, b = value
        return f'<Color3 name="{name}"><R>{r/255}</R><G>{g/255}</G><B>{b/255}</B></Color3>'
    raise ValueError(f"unsupported property {name}={value!r}")


def script_item(name: str, class_name: str, source: str) -> str:
    extra = ""
    if class_name == "Script":
        extra = '<token name="RunContext">0</token>'
    return (
        f'<Item class="{class_name}" referent="{ref()}"><Properties>'
        f'<bool name="Disabled">false</bool>'
        f'<string name="Name">{escape(name)}</string>'
        f'{extra}'
        f'<ProtectedString name="Source">{cdata(source)}</ProtectedString>'
        f'</Properties></Item>'
    )


def classify(filename: str):
    stem = filename[: -len(".luau")]
    if stem.endswith(".server"):
        return stem[: -len(".server")], "Script"
    if stem.endswith(".client"):
        return stem[: -len(".client")], "LocalScript"
    return stem, "ModuleScript"


def rel(p: pathlib.Path) -> str:
    return p.relative_to(ROOT).as_posix()


def dir_item(name: str, path: pathlib.Path, at: list) -> str:
    """A directory becomes a Folder, or a script if it holds init.luau."""
    children = []
    class_name, source = "Folder", None
    entry = {"path": at, "class": "Folder", "file": None}
    _scripts.append(entry)
    for p in sorted(path.iterdir()):
        if p.is_dir():
            children.append(dir_item(p.name, p, at + [p.name]))
        elif p.suffix == ".luau":
            stem, cls = classify(p.name)
            if stem == "init":
                class_name, source = cls, p.read_text(encoding="utf-8")
                entry["class"], entry["file"] = cls, rel(p)
            else:
                children.append(script_item(stem, cls, p.read_text(encoding="utf-8")))
                _scripts.append({"path": at + [stem], "class": cls, "file": rel(p)})
    if source is not None:
        extra = '<token name="RunContext">0</token>' if class_name == "Script" else ""
        head = (
            f'<Item class="{class_name}" referent="{ref()}"><Properties>'
            f'<bool name="Disabled">false</bool><string name="Name">{escape(name)}</string>{extra}'
            f'<ProtectedString name="Source">{cdata(source)}</ProtectedString></Properties>'
        )
    else:
        head = f'<Item class="Folder" referent="{ref()}"><Properties><string name="Name">{escape(name)}</string></Properties>'
    return head + "".join(children) + "</Item>"


def node_item(name: str, node: dict, at: list) -> str:
    if "$path" in node:
        return dir_item(name, ROOT / node["$path"], at)
    class_name = node.get("$className", "Folder")
    props = node.get("$properties", {})
    children = [node_item(k, v, at + [k]) for k, v in node.items() if not k.startswith("$")]
    prop_text = f'<string name="Name">{escape(name)}</string>' + "".join(prop_xml(k, v) for k, v in props.items())
    return f'<Item class="{class_name}" referent="{ref()}"><Properties>{prop_text}</Properties>' + "".join(children) + "</Item>"


def main() -> int:
    project = json.loads((ROOT / "default.project.json").read_text(encoding="utf-8"))
    tree = project["tree"]
    items = [node_item(k, v, [k]) for k, v in tree.items() if not k.startswith("$")]
    xml = (
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
        "<Meta name=\"ExplicitAutoJoints\">true</Meta><External>null</External><External>nil</External>"
        + "".join(items)
        + "</roblox>"
    )
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(xml, encoding="utf-8")
    SYNC.write_text(json.dumps(_scripts), encoding="utf-8")
    print(f"wrote {OUT} ({OUT.stat().st_size // 1024} KB, {_ref} instances)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
