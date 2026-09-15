"""Recover a known animation-compatible GLB and remove only its painted stripe.

Defaults to inspection. --apply backs up the current GLB outside Godot's import
tree, then remaps stripe primitives to the shell material. Vertex/skin/animation
buffers and node hierarchy are copied unchanged from the requested git revision.
"""
import argparse
import copy
import datetime
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess


def chunks(data):
    magic, version, total = struct.unpack_from("<4sII", data)
    assert magic == b"glTF" and version == 2 and total == len(data)
    result = []
    offset = 12
    while offset < total:
        length, kind = struct.unpack_from("<II", data, offset)
        result.append((kind, data[offset + 8:offset + 8 + length]))
        offset += 8 + length
    assert offset == total and result[0][0] == 0x4E4F534A
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-ref", required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    relative = "Models/Characters/pilot/pilot.glb"
    target = repo / relative
    revision = subprocess.check_output(
        ["git", "rev-parse", "--verify", args.source_ref + "^{commit}"], cwd=repo
    ).decode().strip()
    old = subprocess.check_output(["git", "show", f"{revision}:{relative}"], cwd=repo)
    parts = chunks(old)
    original = json.loads(parts[0][1])
    updated = copy.deepcopy(original)
    names = [material.get("name") for material in updated["materials"]]
    stripe, shell = names.index("Helmet_Color"), names.index("Helmet_Color_2")
    changed = 0
    for mesh in updated["meshes"]:
        for primitive in mesh["primitives"]:
            if primitive.get("material") == stripe:
                primitive["material"] = shell
                changed += 1
    assert changed > 0, "No authored stripe primitive found"
    for key in original:
        if key != "meshes":
            assert updated[key] == original[key], key
    encoded = json.dumps(updated, separators=(",", ":"), ensure_ascii=False).encode()
    encoded += b" " * (-len(encoded) % 4)
    payload = b"".join(struct.pack("<II", len(data), kind) + data
                       for kind, data in [(parts[0][0], encoded)] + parts[1:])
    repaired = struct.pack("<4sII", b"glTF", 2, 12 + len(payload)) + payload
    assert chunks(repaired)[1:] == parts[1:], "Binary buffers must stay identical"
    report = {"source_commit": revision, "remapped_primitives": changed,
              "source_bones": [len(s["joints"]) for s in original.get("skins", [])],
              "target": str(target), "sha256": hashlib.sha256(repaired).hexdigest()}
    if args.apply:
        backup_dir = Path(os.environ["LOCALAPPDATA"]) / "Project-Flight" / "asset-backups" / (
            "pilot-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f"))
        backup_dir.mkdir(parents=True, exist_ok=False)
        current = target.read_bytes()
        backup = backup_dir / "pilot-before-rig-repair.glb"
        backup.write_bytes(current)
        assert backup.read_bytes() == current
        target.write_bytes(repaired)
        report["preserved_user_export"] = str(backup)
        (backup_dir / "repair.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
