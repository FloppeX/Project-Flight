#!/usr/bin/env python3
"""Build a seated default pose for the SWAT GLB while keeping the rig intact."""

from __future__ import annotations

import argparse
import json
import math
import struct
from pathlib import Path

import numpy as np

try:
    from PIL import Image, ImageDraw
except ImportError:  # pragma: no cover - preview is optional
    Image = None
    ImageDraw = None


JSON_CHUNK_TYPE = 0x4E4F534A
BIN_CHUNK_TYPE = 0x004E4942

COMPONENTS = {
    5120: ("b", 1),
    5121: ("B", 1),
    5122: ("h", 2),
    5123: ("H", 2),
    5125: ("I", 4),
    5126: ("f", 4),
}
NUM_COMPONENTS = {
    "SCALAR": 1,
    "VEC2": 2,
    "VEC3": 3,
    "VEC4": 4,
    "MAT4": 16,
}

DEATH_TIME = 0.382
IDLE_TIME = 0.0
DEATH_TRANSLATION_NODES = {3, 73, 75, 77, 79}
DEATH_ROTATION_NODES = {3, 67, 68, 70, 71, 73, 75, 77, 79}
IDLE_ROTATION_NODES = {4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 39, 40, 41, 42}
LOCAL_TWEAKS = [
    (4, (1.0, 0.0, 0.0), 8.0),
    (5, (1.0, 0.0, 0.0), 8.0),
    (6, (1.0, 0.0, 0.0), 12.0),
    (7, (1.0, 0.0, 0.0), 8.0),
]
PREVIEW_NODES = [2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 39, 40, 41, 42, 67, 68, 69, 70, 71, 72, 73, 77]


def qnorm(q: np.ndarray) -> np.ndarray:
    return q / np.linalg.norm(q)


def qmul(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return np.array(
        [
            aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
            aw * bw - ax * bx - ay * by - az * bz,
        ],
        dtype=float,
    )


def qaxis(axis: tuple[float, float, float], degrees: float) -> np.ndarray:
    axis_arr = np.array(axis, dtype=float)
    axis_arr /= np.linalg.norm(axis_arr)
    theta = math.radians(degrees) / 2.0
    sin_theta = math.sin(theta)
    return np.array(
        [axis_arr[0] * sin_theta, axis_arr[1] * sin_theta, axis_arr[2] * sin_theta, math.cos(theta)],
        dtype=float,
    )


def qmat(q: np.ndarray) -> np.ndarray:
    x, y, z, w = q
    n = x * x + y * y + z * z + w * w
    s = 2.0 / n if n else 0.0
    xx, yy, zz = x * x * s, y * y * s, z * z * s
    xy, xz, yz = x * y * s, x * z * s, y * z * s
    wx, wy, wz = w * x * s, w * y * s, w * z * s
    return np.array(
        [
            [1.0 - (yy + zz), xy - wz, xz + wy],
            [xy + wz, 1.0 - (xx + zz), yz - wx],
            [xz - wy, yz + wx, 1.0 - (xx + yy)],
        ],
        dtype=float,
    )


def qslerp(a: np.ndarray, b: np.ndarray, t: float) -> np.ndarray:
    a = qnorm(a)
    b = qnorm(b)
    dot = float(np.dot(a, b))
    if dot < 0.0:
        b = -b
        dot = -dot
    if dot > 0.9995:
        return qnorm(a + t * (b - a))
    theta_0 = math.acos(max(-1.0, min(1.0, dot)))
    sin_theta_0 = math.sin(theta_0)
    theta = theta_0 * t
    return math.sin(theta_0 - theta) / sin_theta_0 * a + math.sin(theta) / sin_theta_0 * b


class GlbPoseTool:
    def __init__(self, input_path: Path) -> None:
        self.input_path = input_path
        self.gltf, self.binary_blob = self._read_glb(input_path)
        self.nodes = self.gltf["nodes"]
        self.parents = self._build_parents()
        self.base_translations = {
            idx: np.array(node.get("translation", [0.0, 0.0, 0.0]), dtype=float) for idx, node in enumerate(self.nodes)
        }
        self.base_rotations = {
            idx: qnorm(np.array(node.get("rotation", [0.0, 0.0, 0.0, 1.0]), dtype=float))
            for idx, node in enumerate(self.nodes)
        }
        self.animations = self._load_animations()

    @staticmethod
    def _read_glb(path: Path) -> tuple[dict, bytes]:
        with path.open("rb") as fh:
            magic, version, _length = struct.unpack("<III", fh.read(12))
            if magic != 0x46546C67:
                raise ValueError(f"{path} is not a valid GLB file.")
            if version != 2:
                raise ValueError(f"Unsupported GLB version {version}.")

            json_length, json_type = struct.unpack("<II", fh.read(8))
            if json_type != JSON_CHUNK_TYPE:
                raise ValueError("First GLB chunk is not JSON.")
            gltf = json.loads(fh.read(json_length))

            chunk_header = fh.read(8)
            if not chunk_header:
                binary_blob = b""
            else:
                bin_length, bin_type = struct.unpack("<II", chunk_header)
                if bin_type != BIN_CHUNK_TYPE:
                    raise ValueError("Second GLB chunk is not binary.")
                binary_blob = fh.read(bin_length)

        return gltf, binary_blob

    def _build_parents(self) -> dict[int, int]:
        parents: dict[int, int] = {}
        for parent_idx, node in enumerate(self.nodes):
            for child_idx in node.get("children", []):
                parents[child_idx] = parent_idx
        return parents

    def _accessor_data(self, accessor_index: int) -> np.ndarray:
        accessor = self.gltf["accessors"][accessor_index]
        buffer_view = self.gltf["bufferViews"][accessor["bufferView"]]
        fmt, component_size = COMPONENTS[accessor["componentType"]]
        component_count = NUM_COMPONENTS[accessor["type"]]
        count = accessor["count"]
        offset = buffer_view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        stride = buffer_view.get("byteStride", component_count * component_size)
        output = np.zeros((count, component_count), dtype=float)
        for row in range(count):
            output[row] = struct.unpack_from("<" + fmt * component_count, self.binary_blob, offset + row * stride)
        return output[:, 0] if component_count == 1 else output

    def _load_animations(self) -> dict[str, list[tuple[int, str, np.ndarray, np.ndarray]]]:
        animation_map: dict[str, list[tuple[int, str, np.ndarray, np.ndarray]]] = {}
        for animation in self.gltf.get("animations", []):
            name = animation.get("name")
            if not name:
                continue
            channels: list[tuple[int, str, np.ndarray, np.ndarray]] = []
            for channel in animation["channels"]:
                sampler = animation["samplers"][channel["sampler"]]
                channels.append(
                    (
                        channel["target"]["node"],
                        channel["target"]["path"],
                        self._accessor_data(sampler["input"]),
                        self._accessor_data(sampler["output"]),
                    )
                )
            animation_map[name] = channels
        return animation_map

    @staticmethod
    def _sample_channel(times: np.ndarray, values: np.ndarray, t: float, path: str) -> np.ndarray:
        if t <= times[0]:
            return values[0]
        if t >= times[-1]:
            return values[-1]

        idx = int(np.searchsorted(times, t, side="right") - 1)
        idx = max(0, min(idx, len(times) - 2))
        t0 = times[idx]
        t1 = times[idx + 1]
        alpha = 0.0 if t1 == t0 else float((t - t0) / (t1 - t0))

        if path == "rotation":
            return qslerp(values[idx], values[idx + 1], alpha)
        return values[idx] + alpha * (values[idx + 1] - values[idx])

    def _sample_animation(
        self,
        animation_name: str,
        t: float,
        translation_nodes: set[int],
        rotation_nodes: set[int],
        translations: dict[int, np.ndarray],
        rotations: dict[int, np.ndarray],
    ) -> None:
        channels = self.animations.get(animation_name)
        if not channels:
            raise ValueError(f"Animation '{animation_name}' was not found in {self.input_path}.")

        for node_idx, path, times, values in channels:
            if path == "translation" and node_idx in translation_nodes:
                translations[node_idx] = self._sample_channel(times, values, t, path)
            elif path == "rotation" and node_idx in rotation_nodes:
                rotations[node_idx] = self._sample_channel(times, values, t, path)

    def build_sit_pose(self) -> tuple[dict[int, np.ndarray], dict[int, np.ndarray]]:
        translations = {idx: value.copy() for idx, value in self.base_translations.items()}
        rotations = {idx: value.copy() for idx, value in self.base_rotations.items()}

        self._sample_animation(
            "CharacterArmature|Death",
            DEATH_TIME,
            DEATH_TRANSLATION_NODES,
            DEATH_ROTATION_NODES,
            translations,
            rotations,
        )
        self._sample_animation(
            "CharacterArmature|Idle_Neutral",
            IDLE_TIME,
            set(),
            IDLE_ROTATION_NODES,
            translations,
            rotations,
        )

        for node_idx, axis, degrees in LOCAL_TWEAKS:
            rotations[node_idx] = qnorm(qmul(rotations[node_idx], qaxis(axis, degrees)))

        return translations, rotations

    def apply_pose(self, translations: dict[int, np.ndarray], rotations: dict[int, np.ndarray], strip_animations: bool) -> None:
        for node_idx, translation in translations.items():
            self.nodes[node_idx]["translation"] = [float(v) for v in translation]
        for node_idx, rotation in rotations.items():
            self.nodes[node_idx]["rotation"] = [float(v) for v in qnorm(rotation)]

        generator = self.gltf.setdefault("asset", {}).get("generator", "Unknown")
        self.gltf["asset"]["generator"] = f"{generator} | seated pose by pose_swat_sit.py"
        if strip_animations:
            self.gltf.pop("animations", None)

    def write_glb(self, output_path: Path) -> None:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        json_bytes = json.dumps(self.gltf, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        json_bytes += b" " * ((4 - len(json_bytes) % 4) % 4)

        binary_blob = self.binary_blob + (b"\x00" * ((4 - len(self.binary_blob) % 4) % 4))
        total_length = 12 + 8 + len(json_bytes) + 8 + len(binary_blob)

        with output_path.open("wb") as fh:
            fh.write(struct.pack("<III", 0x46546C67, 2, total_length))
            fh.write(struct.pack("<II", len(json_bytes), JSON_CHUNK_TYPE))
            fh.write(json_bytes)
            fh.write(struct.pack("<II", len(binary_blob), BIN_CHUNK_TYPE))
            fh.write(binary_blob)

    def world_positions(
        self, translations: dict[int, np.ndarray], rotations: dict[int, np.ndarray]
    ) -> tuple[dict[int, np.ndarray], dict[int, np.ndarray]]:
        world_t: dict[int, np.ndarray] = {}
        world_r: dict[int, np.ndarray] = {}
        for node_idx in range(len(self.nodes)):
            parent_idx = self.parents.get(node_idx)
            local_r = qmat(rotations[node_idx])
            local_t = translations[node_idx]
            if parent_idx is None:
                world_r[node_idx] = local_r
                world_t[node_idx] = local_t
            else:
                world_r[node_idx] = world_r[parent_idx] @ local_r
                world_t[node_idx] = world_t[parent_idx] + world_r[parent_idx] @ local_t
        return world_t, world_r

    def save_preview(self, output_path: Path, translations: dict[int, np.ndarray], rotations: dict[int, np.ndarray]) -> None:
        if Image is None or ImageDraw is None:
            raise RuntimeError("Preview requested but Pillow is not installed.")

        output_path.parent.mkdir(parents=True, exist_ok=True)
        world_t, _world_r = self.world_positions(translations, rotations)
        points = np.array([world_t[idx] for idx in PREVIEW_NODES], dtype=float)
        index_lookup = {node_idx: offset for offset, node_idx in enumerate(PREVIEW_NODES)}
        chains = [
            (parent_idx, child_idx)
            for child_idx, parent_idx in self.parents.items()
            if child_idx in index_lookup and parent_idx in index_lookup
        ]

        image = Image.new("RGB", (800, 450), "white")
        draw = ImageDraw.Draw(image)
        for view_idx, (label, axis_x, axis_y) in enumerate((("Front", 0, 1), ("Side", 2, 1))):
            x0 = 20 + view_idx * 390
            y0 = 40
            width = 350
            height = 370
            sample = np.array([[p[axis_x], p[axis_y]] for p in points], dtype=float)
            minimum = sample.min(0)
            maximum = sample.max(0)
            size = np.maximum(maximum - minimum, 1e-6)
            scale = min(width / (size[0] * 1.2), height / (size[1] * 1.2))
            center = (minimum + maximum) / 2.0

            def project(vec: np.ndarray) -> tuple[float, float]:
                px = (vec[axis_x] - center[0]) * scale + x0 + width / 2.0
                py = -(vec[axis_y] - center[1]) * scale + y0 + height / 2.0
                return px, py

            draw.rectangle([x0, y0, x0 + width, y0 + height], outline=(220, 220, 220))
            draw.text((x0 + 8, y0 + 8), f"Sit Pose {label}", fill="black")
            for parent_idx, child_idx in chains:
                draw.line([project(world_t[parent_idx]), project(world_t[child_idx])], fill=(40, 70, 180), width=3)
            for node_idx in PREVIEW_NODES:
                px, py = project(world_t[node_idx])
                draw.ellipse([px - 4, py - 4, px + 4, py + 4], fill=(200, 50, 50))

        image.save(output_path)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True, help="Source GLB.")
    parser.add_argument("--output", type=Path, required=True, help="Output GLB with seated default pose.")
    parser.add_argument("--preview", type=Path, help="Optional preview PNG for the seated skeleton pose.")
    parser.add_argument("--strip-animations", action="store_true", help="Remove animation clips from the output GLB.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    tool = GlbPoseTool(args.input)
    translations, rotations = tool.build_sit_pose()
    tool.apply_pose(translations, rotations, strip_animations=args.strip_animations)
    tool.write_glb(args.output)
    if args.preview:
        tool.save_preview(args.preview, translations, rotations)


if __name__ == "__main__":
    main()
