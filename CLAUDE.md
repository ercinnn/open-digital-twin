# CLAUDE.md - Open Digital Twin Platform Architecture & Rules

## 1. Project Overview
Open-source, license-free **Digital Twin Platform** for Marine Engineering (ships/shipyards) and AEC (buildings/villas). Ingests open formats (`.step`, `.ifc`, `.ocx`, plus `.obj`/`.stl`/`.glb`), extracts component hierarchies (BOM) and physical properties via Python, optimizes 3D meshes into `.glb` via Headless Blender, stores data & real-time telemetry in Supabase, and renders interactive 3D scenes inside Flutter via an embedded Three.js bridge.

## 2. Tech Stack & Strict Boundaries
- **Frontend:** Flutter (Web & Desktop primary, Mobile compatible) + `flutter_riverpod` (3.x) + `supabase_flutter`.
- **3D Engine:** Embedded `Three.js` r170 (`frontend/assets/viewer/`) communicating with Flutter via bidirectional JS channels `FlutterToThree` / `ThreeToFlutter`.
- **Backend:** Python 3.11+ `FastAPI` + `trimesh` (+`cascadio` for STEP) / `ifcopenshell` + Headless **Blender** 4.2 LTS (`blender --background --python ...`).
- **Database & Realtime:** Supabase (PostgreSQL, Storage, Auth, Realtime). Project ref `unksjqvehethysjubclj` (Frankfurt).

## 3. Coding & Naming Conventions (CRITICAL)
- **Database Naming:** ALL PostgreSQL tables, columns, foreign keys, RPCs, and storage buckets MUST be strictly in **English** using `snake_case` (`projects`, `components`, `documents`, `telemetry_logs`, `mesh_node_id`).
- **3D Mapping Rule:** Every 3D mesh node exported to `.glb` MUST preserve its exact `mesh_node_id` matching the `mesh_node_id` column in Supabase `components`.
  - Node ids are `NODE_<UPPER_SNAKE>` (≤ 60 chars, see `cad_parser.sanitize_node_id`), stored both as the glTF node name and in `extras.mesh_node_id`.
  - Context-only geometry (not in the BOM) is prefixed `CTX_`; the viewer ghosts it and makes it non-pickable.
  - The ingest pipeline fails with HTTP 500 if any BOM id is missing from the exported GLB.
- **Flutter Architecture:** Feature-First Clean Architecture (`data`, `domain`, `presentation`). Provide complete, step-by-step file implementations without placeholders or TODOs.
- **Secrets:** `SUPABASE_SERVICE_ROLE_KEY` lives ONLY in the root `.env` (backend). `frontend/.env` is bundled into the app as an asset and must contain public values only.
- **Access model (migration 003):** `anon` + `authenticated` can only SELECT. Writes require an editor: an authenticated user listed in `public.app_editors` (checked by RPC `is_editor()`). Signing up alone grants nothing. The UI hides/disables write controls unless `isEditorProvider` is true. Add an editor with: `insert into public.app_editors (user_id) select id from auth.users where email = '<email>';`
- **Status values:** `normal` (green), `in_progress` (blue), `warning` (orange), `alert` (pulsing red). Sensor simulation never overwrites `in_progress`.

## 4. Core Pipeline
1. Upload `.step` / `.ifc` / `.ocx` / `.obj` / `.stl` to Supabase Storage bucket `raw-cad-files` (path `<project_id>/<file>`; saved in `projects.raw_file_url`).
2. Trigger `POST /api/v1/ingest/{project_id}` -> `cad_parser.py` tessellates + extracts BOM into `components` (upsert on `(project_id, mesh_node_id)`), Headless Blender (`convert_to_glb.py`) cleans/decimates and exports `.glb` to `processed-models/<project_id>/model.glb`; `projects.glb_model_url` is updated.
3. Flutter loads `.glb` in Three.js. Clicking a mesh emits `node_selected` with `mesh_node_id` to load component details, documents, and live telemetry.
4. Supabase Realtime updates on `components.status` dynamically recolor the corresponding 3D mesh node. `POST /api/v1/telemetry/simulate/{project_id}` inserts readings into `telemetry_logs` and derives status from thresholds.

## 5. Repository Layout
```
supabase/
  config.toml                      # supabase init (CLI linked to the remote project)
  migrations/001_initial_schema.sql  # tables, indexes, trigger, realtime publication
  migrations/002_rls_policies.sql    # RLS, buckets, storage policies (demo write policies replaced by 003)
  migrations/003_editor_write_policies.sql  # read-only public access, editor-only writes (app_editors)
  seed.sql                         # 2 demo projects, 7 components, 17 documents, 384 telemetry rows
backend/
  app/main.py                      # FastAPI app, CORS, GET /health[?deep=true]
  app/config.py                    # .env loading, Blender discovery
  app/schemas.py                   # Pydantic request/response models
  app/routers/ingest.py            # POST /api/v1/ingest/{project_id}
  app/routers/telemetry.py         # POST /api/v1/telemetry/simulate/{project_id}
  app/services/cad_parser.py       # STEP/IFC/OCX/OBJ/STL -> BOM + named trimesh Scene (Y-up)
  app/services/blender_runner.py   # subprocess wrapper for Headless Blender
  app/services/ingest_service.py   # download -> parse -> Blender -> upload -> upsert
  app/services/telemetry_simulator.py  # per-category sensor profiles + thresholds
  app/services/supabase_client.py  # service-role client
  app/blender_scripts/convert_to_glb.py          # import, clean, decimate, export GLB
  app/blender_scripts/generate_sample_models.py  # builds the 2 demo GLBs
  scripts/publish_sample_assets.py # uploads demo GLBs + generated demo documents
  scripts/sample_documents.py      # PDF/PNG generators (marked DEMO)
  sample_models/                   # nb42_engine_room.glb, villa_b04.glb
  tests/test_backend.py
frontend/
  assets/viewer/index.html, twin_scene.js   # Three.js scene + bridge
  lib/core/                        # config, theme, backend client, providers, status enum
  lib/shared/widgets/              # status badges, loading/error/empty, section card
  lib/features/auth/               # editor sign-in, read-only gating
  lib/features/projects/           # dashboard, create project, upload + ingest
  lib/features/digital_twin/       # split view, component tree, inspector, telemetry, docs, viewer bridge
```

## 6. Run Commands
```powershell
# Backend (from backend/)
py -3.11 -m venv .venv                     # first time only
.venv\Scripts\python -m pip install -r requirements.txt
.venv\Scripts\python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
curl http://localhost:8000/health?deep=true
.venv\Scripts\python -m pytest -q

# Regenerate demo GLBs with Headless Blender + publish models/documents to Supabase
"C:\Program Files\Blender Foundation\Blender 4.2\blender.exe" --background --factory-startup --python-exit-code 1 --python app/blender_scripts/generate_sample_models.py
.venv\Scripts\python -m scripts.publish_sample_assets [--generate] [--force-docs]

# Frontend (from frontend/)
flutter pub get
flutter analyze
flutter test
flutter run -d chrome          # Web (iframe + postMessage bridge)
flutter run -d windows         # Desktop (WebView2 via webview_windows)

# Supabase CLI (installed via scoop: %USERPROFILE%\scoop\shims\supabase.exe)
supabase link --project-ref unksjqvehethysjubclj -p <SUPABASE_DB_PASSWORD from .env>
supabase db push --include-seed -p <SUPABASE_DB_PASSWORD>
```

## 7. Public Website (GitHub Pages)
- URL: https://ercinnn.github.io/open-digital-twin/ — built by `.github/workflows/deploy-web.yml` on every push to `main` touching `frontend/**`.
- CI injects config with `--dart-define` from repository secrets `SUPABASE_URL`, `SUPABASE_ANON_KEY` (optional repo variable `BACKEND_URL`, default `http://localhost:8000`). `AppConfig` prefers dart-defines and falls back to `frontend/.env`.
- Built with `--base-href /open-digital-twin/`. Locally in Git Bash prefix with `MSYS_NO_PATHCONV=1` or the path gets mangled.
- Ingest + "Simulate Live Sensor" call the FastAPI backend, so on the public site they only work for an editor who runs the backend on their own machine.

## 8. Environment Notes (Windows dev machine)
- Blender 4.2 LTS: `C:\Program Files\Blender Foundation\Blender 4.2\blender.exe` (`BLENDER_PATH` in `.env`). Without Blender, ingest falls back to an unoptimized trimesh GLB and reports a warning.
- `ifcopenshell` needs the Microsoft Visual C++ 2015-2022 x64 runtime (`MSVCP140.dll`).
- trimesh 5.x merges OBJ objects unless loaded with `split_objects=True` (handled in `cad_parser.py`).
- Riverpod 3: family notifiers receive their argument via the constructor (`NotifierProvider.family(MyNotifier.new)`); use `ref.listenManual(..., fireImmediately: true)` in `initState` for side effects.
- file_picker 13: `FilePicker.pickFiles(...)` is static and returns `List<PlatformFile>`; read bytes with `readAsBytes()`.
