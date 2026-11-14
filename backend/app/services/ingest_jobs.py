"""Background ingest jobs.

A CAD ingest (parse + Headless Blender + upload) can take minutes, longer than
many hosting proxies keep an HTTP request open. Clients therefore start a job
and poll its status. Jobs run one at a time (Blender is CPU/RAM heavy) and are
kept in memory: a restart of the server forgets them, which clients report as
"job not found - start the ingest again".
"""

from __future__ import annotations

import logging
import threading
import uuid
from collections import OrderedDict
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Callable

from app.services.ingest_service import IngestError
from app.services.supabase_client import SupabaseNotConfiguredError

logger = logging.getLogger(__name__)

MAX_KEPT_JOBS = 50


def _now() -> datetime:
    return datetime.now(timezone.utc)


@dataclass
class IngestJob:
    job_id: str
    project_id: str
    requested_by: str
    status: str = "queued"  # queued | running | succeeded | failed
    created_at: datetime = field(default_factory=_now)
    started_at: datetime | None = None
    finished_at: datetime | None = None
    result: dict[str, Any] | None = None
    error: str | None = None
    error_status: int | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "job_id": self.job_id,
            "project_id": self.project_id,
            "status": self.status,
            "created_at": self.created_at,
            "started_at": self.started_at,
            "finished_at": self.finished_at,
            "result": self.result,
            "error": self.error,
            "error_status": self.error_status,
        }


class IngestJobRunner:
    def __init__(self, max_workers: int = 1) -> None:
        self._executor = ThreadPoolExecutor(max_workers=max_workers, thread_name_prefix="ingest")
        self._jobs: OrderedDict[str, IngestJob] = OrderedDict()
        self._lock = threading.Lock()

    def submit(self, project_id: str, requested_by: str, work: Callable[[], dict[str, Any]]) -> IngestJob:
        job = IngestJob(job_id=uuid.uuid4().hex, project_id=project_id, requested_by=requested_by)
        with self._lock:
            self._jobs[job.job_id] = job
            while len(self._jobs) > MAX_KEPT_JOBS:
                oldest_id, oldest = next(iter(self._jobs.items()))
                if oldest.status in ("queued", "running"):
                    break
                self._jobs.pop(oldest_id)
        self._executor.submit(self._run, job, work)
        return job

    def get(self, job_id: str) -> IngestJob | None:
        with self._lock:
            return self._jobs.get(job_id)

    def _run(self, job: IngestJob, work: Callable[[], dict[str, Any]]) -> None:
        job.status, job.started_at = "running", _now()
        try:
            job.result = work()
            job.status = "succeeded"
        except IngestError as exc:
            job.status, job.error, job.error_status = "failed", str(exc.detail), exc.status_code
        except SupabaseNotConfiguredError as exc:
            job.status, job.error, job.error_status = "failed", str(exc), 503
        except Exception as exc:  # unexpected: keep the server alive, report to the client
            logger.exception("Ingest job %s failed", job.job_id)
            job.status, job.error, job.error_status = "failed", f"{type(exc).__name__}: {exc}", 500
        finally:
            job.finished_at = _now()


runner = IngestJobRunner()
