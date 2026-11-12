"""Ingest pipeline: raw CAD (Storage) -> BOM rows (components) + optimized .glb (Storage)."""

from __future__ import annotations

import logging
import tempfile
import time
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse

import trimesh

from app.config import get_settings
from app.services.blender_runner import BlenderError, optimize_glb
from app.services.cad_parser import CadParseError, parse_cad_file
from app.services.supabase_client import get_supabase, public_url, upload_bytes

logger = logging.getLogger("odt.ingest")


class IngestError(Exception):
    def __init__(self, status_code: int, detail: str) -> None:
        super().__init__(detail)
        self.status_code = status_code
        self.detail = detail


def normalize_storage_path(value: str, bucket: str) -> str:
    """Accept a bare object path, '<bucket>/<path>', or a full Supabase Storage URL."""
    raw = value.strip()
    if raw.startswith("http://") or raw.startswith("https://"):
        path = unquote(urlparse(raw).path)
        marker = f"/{bucket}/"
        if marker not in path:
            raise IngestError(400, f"URL does not point into bucket '{bucket}': {value}")
        return path.split(marker, 1)[1]
    raw = raw.lstrip("/")
    if raw.startswith(f"{bucket}/"):
        raw = raw[len(bucket) + 1 :]
    return raw


def glb_node_names(path: Path) -> set[str]:
    scene = trimesh.load(str(path), force="scene")
    return {str(n) for n in scene.graph.nodes_geometry}


def run_ingest(
    project_id: str,
    storage_path: str | None = None,
    max_faces_per_node: int | None = None,
    unit_scale: float | None = None,
    prune_missing: bool = False,
) -> dict[str, Any]:
    settings = get_settings()
    client = get_supabase()
    started = time.perf_counter()

    rows = client.table("projects").select("*").eq("id", project_id).limit(1).execute().data
    if not rows:
        raise IngestError(404, f"Project {project_id} not found")
    project = rows[0]

    source = storage_path or project.get("raw_file_url")
    if not source:
        raise IngestError(400, "Project has no raw_file_url. Upload a CAD file to 'raw-cad-files' first.")
    object_path = normalize_storage_path(source, settings.raw_bucket)

    try:
        data = client.storage.from_(settings.raw_bucket).download(object_path)
    except Exception as exc:
        raise IngestError(404, f"Could not download '{object_path}' from {settings.raw_bucket}: {exc}") from exc

    warnings: list[str] = []
    with tempfile.TemporaryDirectory(prefix="odt_ingest_") as tmp_dir:
        tmp = Path(tmp_dir)
        src = tmp / Path(object_path).name
        src.write_bytes(data)

        try:
            parsed = parse_cad_file(src, domain_type=project["domain_type"], unit_scale=unit_scale)
        except CadParseError as exc:
            raise IngestError(422, str(exc)) from exc
        warnings.extend(parsed.warnings)

        intermediate = tmp / "intermediate.glb"
        parsed.scene.export(str(intermediate), file_type="glb")

        output = tmp / "model.glb"
        try:
            optimization = optimize_glb(
                intermediate, output, max_faces_per_node or settings.max_faces_per_node
            )
        except BlenderError as exc:
            raise IngestError(500, f"Blender optimization failed: {exc}") from exc
        if optimization.optimizer == "passthrough":
            warnings.append("Blender not found - exported unoptimized trimesh GLB.")

        exported_nodes = glb_node_names(output)
        expected = {c.mesh_node_id for c in parsed.components}
        missing = sorted(expected - exported_nodes)
        if missing:
            raise IngestError(500, f"3D mapping contract violated; nodes missing from GLB: {missing}")

        glb_bytes = output.read_bytes()
        model_path = f"{project_id}/model.glb"
        upload_bytes(settings.models_bucket, model_path, glb_bytes, "model/gltf-binary")
        glb_url = f"{public_url(settings.models_bucket, model_path)}?v={int(time.time())}"

    component_rows = [c.to_row(project_id) for c in parsed.components]
    client.table("components").upsert(component_rows, on_conflict="project_id,mesh_node_id").execute()

    existing = (
        client.table("components").select("id,mesh_node_id").eq("project_id", project_id).execute().data
    )
    stale = [r for r in existing if r["mesh_node_id"] not in expected]
    if stale and prune_missing:
        client.table("components").delete().in_("id", [r["id"] for r in stale]).execute()

    client.table("projects").update({"glb_model_url": glb_url, "raw_file_url": object_path}).eq(
        "id", project_id
    ).execute()

    elapsed = round(time.perf_counter() - started, 2)
    logger.info("Ingested %s: %d components in %.2fs", project_id, len(component_rows), elapsed)
    return {
        "project_id": project_id,
        "source_path": object_path,
        "source_format": parsed.source_format,
        "unit_scale": parsed.unit_scale,
        "optimizer": optimization.optimizer,
        "glb_model_url": glb_url,
        "glb_size_bytes": len(glb_bytes),
        "components_upserted": len(component_rows),
        "stale_components": [r["mesh_node_id"] for r in stale],
        "stale_pruned": bool(stale and prune_missing),
        "mesh_node_ids": sorted(expected),
        "node_report": optimization.node_report,
        "warnings": warnings,
        "elapsed_s": elapsed,
    }
