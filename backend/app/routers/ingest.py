"""POST /api/v1/ingest/{project_id} - parse raw CAD into BOM + optimized GLB."""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Body, HTTPException
from fastapi.concurrency import run_in_threadpool

from app.schemas import IngestRequest, IngestResponse
from app.services.ingest_service import IngestError, run_ingest
from app.services.supabase_client import SupabaseNotConfiguredError

router = APIRouter(prefix="/api/v1/ingest", tags=["ingest"])


@router.post("/{project_id}", response_model=IngestResponse)
async def ingest_project(project_id: UUID, body: IngestRequest | None = Body(default=None)) -> IngestResponse:
    request = body or IngestRequest()
    try:
        result = await run_in_threadpool(
            run_ingest,
            str(project_id),
            request.storage_path,
            request.max_faces_per_node,
            request.unit_scale,
            request.prune_missing,
        )
    except IngestError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
    except SupabaseNotConfiguredError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    return IngestResponse(**result)
