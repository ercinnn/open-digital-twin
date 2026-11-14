"""POST /api/v1/telemetry/simulate/{project_id} - push simulated live sensor readings."""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Body, Depends, HTTPException
from fastapi.concurrency import run_in_threadpool

from app.auth import require_editor
from app.schemas import SimulateRequest, SimulateResponse
from app.services.supabase_client import SupabaseNotConfiguredError
from app.services.telemetry_simulator import simulate_project

router = APIRouter(prefix="/api/v1/telemetry", tags=["telemetry"])


@router.post("/simulate/{project_id}", response_model=SimulateResponse)
async def simulate_telemetry(
    project_id: UUID,
    body: SimulateRequest | None = Body(default=None),
    _editor_id: str = Depends(require_editor),
) -> SimulateResponse:
    request = body or SimulateRequest()
    try:
        result = await run_in_threadpool(
            simulate_project,
            str(project_id),
            request.steps,
            request.update_status,
            request.interval_seconds,
            request.seed,
        )
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except SupabaseNotConfiguredError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    return SimulateResponse(**result)
