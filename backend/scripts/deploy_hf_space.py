"""Deploy the backend to a Hugging Face Space (Docker SDK).

Reads from the repository root `.env`:
    HF_TOKEN                   Hugging Face access token with *write* permission (required)
    HF_SPACE                   "<owner>/<space-name>" (optional, default "<your-user>/open-digital-twin-backend")
    SUPABASE_URL               stored as a Space variable
    SUPABASE_SERVICE_ROLE_KEY  stored as a Space SECRET (never committed to the Space repo)
    CORS_ORIGINS               optional, default https://ercinnn.github.io

What it does:
    1. creates the Space if missing (public, Docker SDK, port 7860)
    2. sets Space variables/secrets
    3. uploads backend/Dockerfile, requirements.txt, app/ and a generated README.md
    4. with --wait: follows the build until the Space is RUNNING and prints the BACKEND_URL

Run from backend/:
    .venv\\Scripts\\python -m pip install -r requirements-deploy.txt
    .venv\\Scripts\\python -m scripts.deploy_hf_space --wait
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
import tempfile
import time
from pathlib import Path

from dotenv import load_dotenv
from huggingface_hub import HfApi

BACKEND_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = BACKEND_DIR.parent
DEFAULT_SPACE_NAME = "open-digital-twin-backend"
DEFAULT_CORS_ORIGINS = "https://ercinnn.github.io"
DEFAULT_CORS_ORIGIN_REGEX = r"https?://(localhost|127\.0\.0\.1)(:\d+)?"

SPACE_README = """---
title: Open Digital Twin Backend
emoji: 🚢
colorFrom: blue
colorTo: indigo
sdk: docker
app_port: 7860
pinned: false
short_description: CAD/BIM ingest API (FastAPI + Headless Blender)
---

# Open Digital Twin Platform - backend

FastAPI service that turns STEP / IFC / OCX / OBJ / STL files into a component BOM and a
Blender-optimized `.glb` for the Open Digital Twin Platform. All endpoints except `/health`
require the Supabase session of an editor (`Authorization: Bearer <access_token>`).

- `GET /health?deep=true`
- `POST /api/v1/ingest/{project_id}/jobs` -> `GET /api/v1/ingest/jobs/{job_id}`

Source code: https://github.com/ercinnn/open-digital-twin (deployed by `backend/scripts/deploy_hf_space.py`).
"""


def require_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise SystemExit(f"{name} is missing in .env")
    return value


def space_url(api: HfApi, repo_id: str) -> str:
    host = getattr(api.space_info(repo_id), "host", None)
    if host:
        return host.rstrip("/")
    owner, name = repo_id.split("/", 1)
    return f"https://{re.sub(r'[^a-z0-9-]', '-', f'{owner}-{name}'.lower())}.hf.space"


def stage_files(target: Path) -> None:
    shutil.copy2(BACKEND_DIR / "Dockerfile", target / "Dockerfile")
    shutil.copy2(BACKEND_DIR / "requirements.txt", target / "requirements.txt")
    shutil.copytree(
        BACKEND_DIR / "app",
        target / "app",
        ignore=shutil.ignore_patterns("__pycache__", "*.pyc"),
    )
    (target / "README.md").write_text(SPACE_README, encoding="utf-8")


def wait_until_running(api: HfApi, repo_id: str, timeout_s: int = 1800) -> str:
    deadline = time.time() + timeout_s
    last = None
    while time.time() < deadline:
        stage = str(api.get_space_runtime(repo_id).stage)
        if stage != last:
            print(f"      stage: {stage}")
            last = stage
        if stage.endswith("RUNNING"):
            return stage
        if "ERROR" in stage:
            raise SystemExit(f"Space failed with stage {stage}. See the build/container logs on huggingface.co.")
        time.sleep(15)
    raise SystemExit("Timed out waiting for the Space to start.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--wait", action="store_true", help="Follow the build until the Space is running.")
    parser.add_argument("--skip-secrets", action="store_true", help="Only upload code; keep existing Space settings.")
    args = parser.parse_args()

    load_dotenv(REPO_ROOT / ".env")
    token = require_env("HF_TOKEN")
    api = HfApi(token=token)
    owner = api.whoami()["name"]
    repo_id = os.getenv("HF_SPACE", "").strip() or f"{owner}/{DEFAULT_SPACE_NAME}"

    print(f"[1/4] Ensuring Space {repo_id} exists ...")
    api.create_repo(repo_id, repo_type="space", space_sdk="docker", private=False, exist_ok=True)

    if args.skip_secrets:
        print("[2/4] Skipping Space settings (--skip-secrets).")
    else:
        print("[2/4] Setting Space variables and secrets ...")
        api.add_space_variable(repo_id, "SUPABASE_URL", require_env("SUPABASE_URL"))
        api.add_space_variable(repo_id, "CORS_ORIGINS", os.getenv("CORS_ORIGINS", "").strip() or DEFAULT_CORS_ORIGINS)
        api.add_space_variable(repo_id, "CORS_ORIGIN_REGEX", DEFAULT_CORS_ORIGIN_REGEX)
        api.add_space_secret(repo_id, "SUPABASE_SERVICE_ROLE_KEY", require_env("SUPABASE_SERVICE_ROLE_KEY"))
        print("      SUPABASE_URL, CORS_ORIGINS, CORS_ORIGIN_REGEX (variables), SUPABASE_SERVICE_ROLE_KEY (secret)")

    print("[3/4] Uploading Dockerfile, requirements.txt, app/ ...")
    with tempfile.TemporaryDirectory() as tmp:
        staging = Path(tmp)
        stage_files(staging)
        api.upload_folder(
            repo_id=repo_id,
            repo_type="space",
            folder_path=staging,
            delete_patterns=["app/**"],
            commit_message="Deploy backend from open-digital-twin",
        )

    url = space_url(api, repo_id)
    if args.wait:
        print("[4/4] Waiting for the Docker build (first build ~10-15 min) ...")
        wait_until_running(api, repo_id)
    else:
        print("[4/4] Build started (use --wait to follow it).")
    print(f"Space page : https://huggingface.co/spaces/{repo_id}")
    print(f"BACKEND_URL: {url}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
