"""CAD ingest: parse raw CAD into BOM + optimized GLB (editors only).

POST /api/v1/ingest/{project_id}/jobs   start a background job (202) - used by the app
GET  /api/v1/ingest/jobs/{job_id}       poll job status / result
POST /api/v1/ingest/{project_id}        synchronous variant (scripts, local use)
"""

from __future__ import annotations

from functools import partial
from uuid import UUID

from fastapi import APIRouter, Body, Depends, HTTPException, status
from fastapi.concurrency import run_in_threadpool

from app.auth import require_editor
from app.schemas import IngestJobResponse, IngestRequest, IngestResponse
from app.services.ingest_jobs import runner
from app.services.ingest_service import IngestError, run_ingest
from app.services.supabase_client import SupabaseNotConfiguredError

router = APIRouter(prefix="/api/v1/ingest", tags=["ingest"])


def _ingest_call(project_id: UUID, request: IngestRequest):
    return partial(
        run_ingest,
        str(project_id),
        request.storage_path,
        request.max_faces_per_node,
        request.unit_scale,
        request.prune_missing,
    )


@router.post("/{project_id}/jobs", response_model=IngestJobResponse, status_code=status.HTTP_202_ACCEPTED)
async def start_ingest_job(
    project_id: UUID,
    body: IngestRequest | None = Body(default=None),
    editor_id: str = Depends(require_editor),
) -> IngestJobResponse:
    job = runner.submit(str(project_id), editor_id, _ingest_call(project_id, body or IngestRequest()))
    return IngestJobResponse(**job.to_dict())


@router.get("/jobs/{job_id}", response_model=IngestJobResponse)
async def get_ingest_job(job_id: str, _editor_id: str = Depends(require_editor)) -> IngestJobResponse:
    job = runner.get(job_id)
    if job is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Ingest job not found (the server may have restarted) - start the ingest again.",
        )
    return IngestJobResponse(**job.to_dict())


@router.post("/{project_id}", response_model=IngestResponse)
async def ingest_project(
    project_id: UUID,
    body: IngestRequest | None = Body(default=None),
    _editor_id: str = Depends(require_editor),
) -> IngestResponse:
    try:
        result = await run_in_threadpool(_ingest_call(project_id, body or IngestRequest()))
    except IngestError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
    except SupabaseNotConfiguredError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    return IngestResponse(**result)
