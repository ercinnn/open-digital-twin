"""Subprocess wrapper around Headless Blender (`blender --background --python ...`)."""

from __future__ import annotations

import json
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

from app.config import BLENDER_SCRIPTS_DIR, get_settings


class BlenderError(RuntimeError):
    pass


@dataclass
class OptimizationResult:
    optimizer: str  # "blender" | "passthrough"
    node_report: list[dict]
    log_tail: str


def run_blender_script(script: Path, script_args: list[str], timeout_s: int | None = None) -> str:
    settings = get_settings()
    if not settings.blender_path:
        raise BlenderError("Blender executable not found. Set BLENDER_PATH in .env.")
    cmd = [
        settings.blender_path,
        "--background",
        "--factory-startup",
        "--python-exit-code",
        "1",
        "--python",
        str(script),
        "--",
        *script_args,
    ]
    proc = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout_s or settings.blender_timeout_s,
    )
    output = (proc.stdout or "") + (proc.stderr or "")
    if proc.returncode != 0 or "ODT_OK" not in output:
        tail = "\n".join(output.strip().splitlines()[-25:])
        raise BlenderError(f"Blender exited with code {proc.returncode}:\n{tail}")
    return output


def optimize_glb(src: Path, dst: Path, max_faces_per_node: int) -> OptimizationResult:
    """Decimate/clean `src` (.glb/.obj/.stl/...) into `dst` .glb, preserving node names.

    Falls back to a byte-for-byte passthrough when Blender is not installed so the
    pipeline still produces a valid model (already named per the mapping contract).
    """
    settings = get_settings()
    if not settings.blender_path:
        shutil.copyfile(src, dst)
        return OptimizationResult(optimizer="passthrough", node_report=[], log_tail="Blender not found")

    manifest = dst.with_suffix(".manifest.json")
    output = run_blender_script(
        BLENDER_SCRIPTS_DIR / "convert_to_glb.py",
        [
            "--input",
            str(src),
            "--output",
            str(dst),
            "--max-faces-per-node",
            str(max_faces_per_node),
            "--manifest",
            str(manifest),
        ],
    )
    report = json.loads(manifest.read_text(encoding="utf-8"))["nodes"] if manifest.exists() else []
    tail = "\n".join(output.strip().splitlines()[-5:])
    return OptimizationResult(optimizer="blender", node_report=report, log_tail=tail)
