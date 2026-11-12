"""Open Digital Twin Platform - FastAPI entry point.

Run (from backend/):
    .venv\\Scripts\\python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

import logging

from fastapi import FastAPI, Query
from fastapi.concurrency import run_in_threadpool
from fastapi.middleware.cors import CORSMiddleware

from app import __version__
from app.config import get_settings
from app.routers import ingest, telemetry
from app.schemas import HealthResponse
from app.services.supabase_client import get_supabase

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

settings = get_settings()

app = FastAPI(
    title="Open Digital Twin Platform API",
    version=__version__,
    description="CAD/BIM ingest (STEP, IFC, OCX, OBJ, STL) -> BOM + Blender-optimized GLB, and live telemetry simulation.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials="*" not in settings.cors_origins,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(ingest.router)
app.include_router(telemetry.router)


def _ping_supabase() -> bool:
    try:
        get_supabase().table("projects").select("id").limit(1).execute()
        return True
    except Exception:  # connectivity / auth errors all mean "not reachable"
        return False


@app.get("/health", response_model=HealthResponse, tags=["system"])
async def health(deep: bool = Query(default=False, description="Also ping Supabase.")) -> HealthResponse:
    reachable = await run_in_threadpool(_ping_supabase) if deep and settings.supabase_configured else None
    return HealthResponse(
        status="ok",
        service="open-digital-twin-backend",
        version=__version__,
        supabase_configured=settings.supabase_configured,
        supabase_reachable=reachable,
        blender_available=settings.blender_path is not None,
        blender_path=settings.blender_path,
    )
