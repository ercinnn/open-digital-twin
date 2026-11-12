"""Pydantic request/response models for the public API."""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class HealthResponse(BaseModel):
    status: str
    service: str
    version: str
    supabase_configured: bool
    supabase_reachable: bool | None = None
    blender_available: bool
    blender_path: str | None


class IngestRequest(BaseModel):
    storage_path: str | None = Field(
        default=None,
        description="Object path in raw-cad-files (defaults to projects.raw_file_url).",
    )
    max_faces_per_node: int | None = Field(default=None, ge=100, le=2_000_000)
    unit_scale: float | None = Field(default=None, gt=0, description="Override source unit -> metre factor.")
    prune_missing: bool = Field(default=False, description="Delete components not present in the new model.")


class IngestResponse(BaseModel):
    project_id: str
    source_path: str
    source_format: str
    unit_scale: float
    optimizer: str
    glb_model_url: str
    glb_size_bytes: int
    components_upserted: int
    stale_components: list[str]
    stale_pruned: bool
    mesh_node_ids: list[str]
    node_report: list[dict[str, Any]]
    warnings: list[str]
    elapsed_s: float


class SimulateRequest(BaseModel):
    steps: int = Field(default=1, ge=1, le=60, description="Readings per metric to generate.")
    update_status: bool = Field(default=True, description="Derive components.status from thresholds.")
    interval_seconds: int = Field(default=5, ge=1, le=3600)
    seed: int | None = None


class StatusChange(BaseModel):
    mesh_node_id: str
    from_status: str
    to_status: str


class SimulateResponse(BaseModel):
    project_id: str
    components: int
    readings_inserted: int
    status_changes: list[StatusChange]
    readings: list[dict[str, Any]]
