"""Runtime configuration loaded from the repository root `.env`."""

from __future__ import annotations

import glob
import os
import shutil
import sys
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path

from dotenv import load_dotenv

BACKEND_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = BACKEND_DIR.parent
BLENDER_SCRIPTS_DIR = BACKEND_DIR / "app" / "blender_scripts"
SAMPLE_MODELS_DIR = BACKEND_DIR / "sample_models"

load_dotenv(REPO_ROOT / ".env")
load_dotenv(BACKEND_DIR / ".env", override=True)


def _candidate_blender_paths() -> list[str]:
    candidates: list[str] = []
    env_path = os.getenv("BLENDER_PATH", "").strip()
    if env_path:
        candidates.append(env_path)
    on_path = shutil.which("blender")
    if on_path:
        candidates.append(on_path)
    if sys.platform == "win32":
        found = glob.glob(r"C:\Program Files\Blender Foundation\Blender *\blender.exe")
        candidates.extend(sorted(found, reverse=True))
    elif sys.platform == "darwin":
        candidates.append("/Applications/Blender.app/Contents/MacOS/Blender")
    else:
        candidates.extend(["/usr/bin/blender", "/usr/local/bin/blender", "/snap/bin/blender"])
    return candidates


def resolve_blender_path() -> str | None:
    for candidate in _candidate_blender_paths():
        if candidate and Path(candidate).is_file():
            return str(Path(candidate))
    return None


@dataclass(frozen=True)
class Settings:
    supabase_url: str
    supabase_service_role_key: str
    blender_path: str | None
    cors_origins: list[str] = field(default_factory=lambda: ["*"])
    raw_bucket: str = "raw-cad-files"
    models_bucket: str = "processed-models"
    docs_bucket: str = "component-docs"
    max_faces_per_node: int = 60000
    blender_timeout_s: int = 900

    @property
    def supabase_configured(self) -> bool:
        return bool(self.supabase_url and self.supabase_service_role_key)


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    origins = [o.strip() for o in os.getenv("CORS_ORIGINS", "*").split(",") if o.strip()]
    return Settings(
        supabase_url=os.getenv("SUPABASE_URL", "").strip(),
        supabase_service_role_key=os.getenv("SUPABASE_SERVICE_ROLE_KEY", "").strip(),
        blender_path=resolve_blender_path(),
        cors_origins=origins or ["*"],
        max_faces_per_node=int(os.getenv("MAX_FACES_PER_NODE", "60000")),
        blender_timeout_s=int(os.getenv("BLENDER_TIMEOUT_S", "900")),
    )
