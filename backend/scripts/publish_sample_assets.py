"""Publish demo assets to Supabase Storage and link them in the database.

1. (optional --generate) runs Headless Blender generate_sample_models.py
2. verifies each sample .glb contains every components.mesh_node_id of its project
3. uploads the .glb files to `processed-models` and sets projects.glb_model_url
4. generates the seeded documents (PDF/PNG), uploads them to `component-docs`
   and rewrites documents.file_url to the public URL

Run from backend/:
    .venv\\Scripts\\python -m scripts.publish_sample_assets --generate
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

from app.config import BLENDER_SCRIPTS_DIR, SAMPLE_MODELS_DIR, get_settings
from app.services.blender_runner import run_blender_script
from app.services.ingest_service import glb_node_names
from app.services.supabase_client import get_supabase, public_url, upload_bytes
from scripts.sample_documents import build_document

DEMO_MODELS = {
    "11111111-1111-1111-1111-111111111111": "nb42_engine_room.glb",
    "22222222-2222-2222-2222-222222222222": "villa_b04.glb",
    "33333333-3333-3333-3333-333333333333": "demo_shipyard.glb",
}


def generate_models() -> None:
    print("[1/4] Generating sample models with Headless Blender ...")
    run_blender_script(
        BLENDER_SCRIPTS_DIR / "generate_sample_models.py",
        ["--output-dir", str(SAMPLE_MODELS_DIR)],
        timeout_s=600,
    )


def publish_models() -> None:
    settings = get_settings()
    client = get_supabase()
    print("[2/4] Verifying 3D mapping contract ...")
    for project_id, filename in DEMO_MODELS.items():
        path = SAMPLE_MODELS_DIR / filename
        if not path.exists():
            raise SystemExit(f"Missing {path}. Run with --generate.")
        nodes = glb_node_names(path)
        expected = {
            r["mesh_node_id"]
            for r in client.table("components").select("mesh_node_id").eq("project_id", project_id).execute().data
        }
        missing = expected - nodes
        if missing:
            raise SystemExit(f"{filename} is missing mesh nodes {sorted(missing)}")
        print(f"      {filename}: {len(expected)} components matched -> {sorted(expected)}")

    print("[3/4] Uploading models to 'processed-models' ...")
    for project_id, filename in DEMO_MODELS.items():
        object_path = f"{project_id}/{filename}"
        upload_bytes(settings.models_bucket, object_path, (SAMPLE_MODELS_DIR / filename).read_bytes(), "model/gltf-binary")
        url = f"{public_url(settings.models_bucket, object_path)}?v={int(time.time())}"
        client.table("projects").update({"glb_model_url": url}).eq("id", project_id).execute()
        print(f"      {object_path} -> {url}")


def publish_documents(force: bool) -> None:
    settings = get_settings()
    client = get_supabase()
    marker = f"/object/public/{settings.docs_bucket}/"
    print("[4/4] Generating + uploading component documents to 'component-docs' ...")
    projects = {p["id"]: p for p in client.table("projects").select("id,name,domain_type").in_("id", list(DEMO_MODELS)).execute().data}
    components = {
        c["id"]: c
        for c in client.table("components").select("*").in_("project_id", list(DEMO_MODELS)).execute().data
    }
    documents = client.table("documents").select("*").in_("component_id", list(components)).execute().data
    published = 0
    for doc in documents:
        file_url: str = doc["file_url"]
        if file_url.startswith("http"):
            if not force or marker not in file_url:
                continue
            object_path = file_url.split(marker, 1)[1].split("?", 1)[0]
        else:
            object_path = file_url.lstrip("/")
        component = components[doc["component_id"]]
        siblings = [c for c in components.values() if c["project_id"] == component["project_id"]]
        payload, content_type = build_document(
            {**doc, "object_path": object_path}, component, projects[component["project_id"]], siblings
        )
        upload_bytes(settings.docs_bucket, object_path, payload, content_type)
        url = public_url(settings.docs_bucket, object_path)
        client.table("documents").update({"file_url": url}).eq("id", doc["id"]).execute()
        published += 1
        print(f"      {object_path} ({len(payload) // 1024} KB)")
    print(f"      {published} documents published.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--generate", action="store_true", help="Run Headless Blender to (re)generate the GLBs first.")
    parser.add_argument("--force-docs", action="store_true", help="Regenerate documents that already have URLs.")
    args = parser.parse_args()
    if args.generate:
        generate_models()
    publish_models()
    publish_documents(args.force_docs)
    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
