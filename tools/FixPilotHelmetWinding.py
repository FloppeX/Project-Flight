"""Inspect/fix helmet orientation against connected shell faces, without re-export.

Only inconsistent triangle indices and their split vertex normals are changed.
The surrounding shell is the orientation reference, not an assumed sphere.
"""
import argparse
from collections import Counter, defaultdict
import datetime
import json
import os
from pathlib import Path
import struct

from RestoreCompatiblePilotHelmet import chunks


def repair(data):
    parts = chunks(data)
    doc = json.loads(parts[0][1])
    assert parts[1][0] == 0x004E4942
    binary_offset = 28 + len(parts[0][1])

    def accessor(index):
        a = doc["accessors"][index]
        assert "sparse" not in a
        view = doc["bufferViews"][a["bufferView"]]
        assert view.get("buffer", 0) == 0
        count = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[a["type"]]
        fmt = "<" + {5126: "f", 5125: "I", 5123: "H", 5121: "B"}[a["componentType"]] * count
        start = binary_offset + view.get("byteOffset", 0) + a.get("byteOffset", 0)
        stride = view.get("byteStride", struct.calcsize(fmt))
        offsets = [start + i * stride for i in range(a["count"])]
        return fmt, offsets, [struct.unpack_from(fmt, data, off) for off in offsets]

    result = bytearray(data)
    changed_triangles = changed_vertices = 0
    for mesh in doc["meshes"]:
        primitives = mesh["primitives"]
        triangles = []
        edges = defaultdict(list)
        primitive_counts = Counter()
        for pi, primitive in enumerate(primitives):
            material = doc["materials"][primitive["material"]] if "material" in primitive else {}
            if not material.get("name", "").startswith("Helmet_Color"):
                continue
            assert primitive.get("mode", 4) == 4
            vertices = accessor(primitive["attributes"]["POSITION"])[2]
            indices = [v[0] for v in accessor(primitive["indices"])[2]]
            for off in range(0, len(indices), 3):
                ids = indices[off:off + 3]
                points = [tuple(round(x, 5) for x in vertices[i]) for i in ids]
                tid = len(triangles)
                triangles.append((pi, off, ids))
                primitive_counts[pi] += 1
                for a, b in zip(points, points[1:] + points[:1]):
                    assert a != b, "Degenerate edge after position matching"
                    edges[tuple(sorted((a, b)))].append((tid, a < b))
        if not triangles:
            continue
        shell = primitive_counts.most_common(1)[0][0]
        adjacency = defaultdict(list)
        for faces in edges.values():
            assert len(faces) <= 2, "Non-manifold helmet edge; inspect manually"
            if len(faces) == 2:
                (a, da), (b, db) = faces
                adjacency[a].append((b, da == db))
                adjacency[b].append((a, da == db))
        flips = {}
        for start in range(len(triangles)):
            if start in flips:
                continue
            flips[start] = False
            pending, component = [start], []
            while pending:
                a = pending.pop()
                component.append(a)
                for b, invert in adjacency[a]:
                    desired = flips[a] ^ invert
                    if b not in flips:
                        flips[b] = desired
                        pending.append(b)
                    else:
                        assert flips[b] == desired, "Non-orientable helmet"
            reference = [i for i in component if triangles[i][0] == shell]
            assert reference, "Disconnected patch lacks a shell reference"
            if sum(flips[i] for i in reference) > len(reference) / 2:
                for i in component:
                    flips[i] = not flips[i]
            assert not any(flips[i] for i in reference), "Would alter main shell; inspect manually"
        vertex_flips = defaultdict(set)
        for i, (pi, off, ids) in enumerate(triangles):
            for vertex in ids:
                vertex_flips[pi, vertex].add(flips[i])
            if flips[i]:
                fmt, offsets, _ = accessor(primitives[pi]["indices"])
                struct.pack_into(fmt, result, offsets[off + 1], ids[2])
                struct.pack_into(fmt, result, offsets[off + 2], ids[1])
                changed_triangles += 1
        for (pi, vertex), states in vertex_flips.items():
            assert len(states) == 1, "Vertex shared across flipped/unflipped faces; requires splitting"
            if states != {True}:
                continue
            attrs = primitives[pi]["attributes"]
            fmt, offsets, normals = accessor(attrs["NORMAL"])
            assert fmt == "<fff"
            struct.pack_into(fmt, result, offsets[vertex], *[-x for x in normals[vertex]])
            if "TANGENT" in attrs:
                fmt, offsets, tangents = accessor(attrs["TANGENT"])
                assert fmt == "<ffff"
                x, y, z, w = tangents[vertex]
                struct.pack_into(fmt, result, offsets[vertex], x, y, z, -w)
            changed_vertices += 1
    assert chunks(result)[0] == parts[0], "Scene hierarchy/animation JSON must not change"
    return bytes(result), {"flipped_triangles": changed_triangles, "corrected_normals": changed_vertices}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--check", action="store_true", help="Fail if inconsistent faces remain")
    args = parser.parse_args()
    target = Path(__file__).resolve().parent.parent / "Models/Characters/pilot/pilot.glb"
    original = target.read_bytes()
    corrected, report = repair(original)
    assert repair(corrected)[1]["flipped_triangles"] == 0, "Repair must be idempotent"
    if args.apply and corrected != original:
        backup_dir = Path(os.environ["LOCALAPPDATA"]) / "Project-Flight/asset-backups" / (
            "pilot-normals-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f"))
        backup_dir.mkdir(parents=True, exist_ok=False)
        backup = backup_dir / "pilot-before-normal-repair.glb"
        backup.write_bytes(original)
        assert backup.read_bytes() == original
        target.write_bytes(corrected)
        report["backup"] = str(backup)
    print(json.dumps(report, indent=2))
    if args.check and report["flipped_triangles"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
