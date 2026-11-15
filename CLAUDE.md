# CLAUDE.md - Open Digital Twin Platform Architecture & Rules

## 1. Project Overview
Open-source, license-free **Digital Twin Platform** for Marine Engineering (ships/shipyards) and AEC (buildings/villas). Ingests open formats (`.step`, `.ifc`, `.ocx`, plus `.obj`/`.stl`/`.glb`), extracts component hierarchies (BOM) and physical properties via Python, optimizes 3D meshes into `.glb` via Headless Blender, stores data & real-time telemetry in Supabase, and renders interactive 3D scenes inside Flutter via an embedded Three.js bridge.

## 2. Tech Stack & Strict Boundaries
- **Frontend:** Flutter (Web & Desktop primary, Mobile compatible) + `flutter_riverpod` (3.x) + `supabase_flutter`.
- **3D Engine:** Embedded `Three.js` r170 (`frontend/assets/viewer/`, loaded from jsDelivr `three@0.170.0`) communicating with Flutter via bidirectional JS channels `FlutterToThree` / `ThreeToFlutter`. Message shape `{"channel", "type", "payload"}`; the full command/event contract is the header comment of `twin_scene.js` - keep it in sync when adding commands.
  - Commands: `load_model`, `set_statuses`, `select_node`, `focus_node`, `focus_nodes`, `reset_camera`, `set_color_mode` (`status`|`material`|`overlay`), plus the shipyard commands in §8a.
  - Events: `viewer_ready`, `model_progress`, `model_loaded{mesh_node_ids,url}`, `model_error`, `node_selected`, `marker_selected`, `viewer_error`.
- **Backend:** Python 3.11+ `FastAPI` + `trimesh` (+`cascadio` for STEP) / `ifcopenshell` + Headless **Blender** 4.2 LTS (`blender --background --python ...`).
- **Database & Realtime:** Supabase (PostgreSQL, Storage, Auth, Realtime). Project ref `unksjqvehethysjubclj` (Frankfurt).

## 3. Coding & Naming Conventions (CRITICAL)
- **Database Naming:** ALL PostgreSQL tables, columns, foreign keys, RPCs, and storage buckets MUST be strictly in **English** using `snake_case` (`projects`, `components`, `documents`, `telemetry_logs`, `mesh_node_id`).
- **3D Mapping Rule:** Every 3D mesh node exported to `.glb` MUST preserve its exact `mesh_node_id` matching the `mesh_node_id` column in Supabase `components`.
  - Node ids are `NODE_<UPPER_SNAKE>` (≤ 60 chars, see `cad_parser.sanitize_node_id`), stored both as the glTF node name and in `extras.mesh_node_id`.
  - Context-only geometry (not in the BOM) is prefixed `CTX_`; the viewer ghosts it and makes it non-pickable (optional glTF extras `ctx_opacity` 0..1 overrides the default 0.16; >= 0.99 renders opaque).
  - Shipyard hull blocks (`NODE_NB1001_BLOCK_*`) are modelled at their ERECTED position; the viewer moves them to the yard area of their running/last schedule row (`set_placements`), ghosts them while in parts (cutting/bending/panel) and hides them before the first activity.
  - The ingest pipeline fails with HTTP 500 if any BOM id is missing from the exported GLB.
- **Flutter Architecture:** Feature-First Clean Architecture (`data`, `domain`, `presentation`). Provide complete, step-by-step file implementations without placeholders or TODOs.
- **Secrets:** `SUPABASE_SERVICE_ROLE_KEY` lives ONLY in the root `.env` (backend). `frontend/.env` is bundled into the app as an asset and must contain public values only.
- **Access model (migration 003):** `anon` + `authenticated` can only SELECT. Writes require an editor: an authenticated user listed in `public.app_editors` (checked by RPC `is_editor()`). Signing up alone grants nothing. The UI hides/disables write controls unless `isEditorProvider` is true. Add an editor with: `insert into public.app_editors (user_id) select id from auth.users where email = '<email>';`
- **Backend auth:** every FastAPI endpoint except `/health` requires `Authorization: Bearer <Supabase access token>` of an editor (`app/auth.py`: token validated by Supabase Auth + row in `app_editors`). The Flutter `BackendApiClient` sends the current session token. `AUTH_REQUIRED=false` disables this for isolated local experiments only. CORS: `CORS_ORIGINS` (exact, default `*`) + `CORS_ORIGIN_REGEX`; no cookies/credentials.
- **Backend env (root `.env`, template `.env.example`):** `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_DB_PASSWORD` (scripts/CLI), `BLENDER_PATH`, `CORS_ORIGINS`, `CORS_ORIGIN_REGEX`, `AUTH_REQUIRED` (default `true`), `MAX_FACES_PER_NODE` (default 60000, decimation target), `BLENDER_TIMEOUT_S` (default 900). Frontend template: `frontend/.env.example` (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `BACKEND_URL`).
- **Status values:** `normal` (green), `in_progress` (blue), `warning` (orange), `alert` (pulsing red). Sensor simulation never overwrites `in_progress`.

## 4. Core Pipeline
1. Upload `.step` / `.ifc` / `.ocx` / `.obj` / `.stl` to Supabase Storage bucket `raw-cad-files` (path `<project_id>/<file>`; saved in `projects.raw_file_url`).
2. The app starts a background job `POST /api/v1/ingest/{project_id}/jobs` (202) and polls `GET /api/v1/ingest/jobs/{job_id}` (jobs run one at a time, kept in memory - a server restart forgets them; the synchronous `POST /api/v1/ingest/{project_id}` remains for scripts) -> `cad_parser.py` tessellates + extracts BOM into `components` (upsert on `(project_id, mesh_node_id)`), Headless Blender (`convert_to_glb.py`) cleans/decimates and exports `.glb` to `processed-models/<project_id>/model.glb`; `projects.glb_model_url` is updated.
3. Flutter loads `.glb` in Three.js. Clicking a mesh emits `node_selected` with `mesh_node_id` to load component details, documents, and live telemetry.
4. Supabase Realtime updates on `components.status` dynamically recolor the corresponding 3D mesh node.
5. Sensor simulation runs IN THE DATABASE (migration 004): pg_cron job `odt_simulate_telemetry` inserts one reading per metric per minute for every project and derives `components.status` from `public.metric_profiles` thresholds; `odt_telemetry_retention` deletes `telemetry_logs` older than 4 days (hourly); `odt_cron_history_cleanup` trims `cron.job_run_details`. The app button calls RPC `simulate_telemetry(p_project_id)` (editors only); "Live" mode auto-stops after 10 min. The Python simulator (`POST /api/v1/telemetry/simulate/{project_id}`) remains for local use; `metric_profiles` MUST mirror `telemetry_simulator.PROFILES` (enforced by a backend test) - change both together via a new migration.

## 5. Repository Layout
```
CLAUDE.md, ROADMAP.md (Turkish), .env.example, .gitignore, .gitattributes (LF line endings, binary GLB/PNG/PDF)
.github/workflows/deploy-web.yml   # Flutter web build -> GitHub Pages
.github/workflows/supabase-keepalive.yml  # twice-weekly REST ping so the free project is not paused
supabase/
  config.toml                      # supabase init (CLI linked to the remote project)
  migrations/001_initial_schema.sql  # tables, indexes, trigger, realtime publication
  migrations/002_rls_policies.sql    # RLS, buckets, storage policies (demo write policies replaced by 003)
  migrations/003_editor_write_policies.sql  # read-only public access, editor-only writes (app_editors)
  migrations/004_db_telemetry_simulator.sql # metric_profiles, simulate_telemetry RPC, pg_cron (1/min, 4-day retention)
  migrations/005_shipyard_production.sql    # _odt_secure_table() helper, hulls, production_activities (Gantt rows)
  migrations/006_shipyard_organization.sql  # departments (tree), shifts, area_assignments (headcount, no personal data)
  migrations/007_shipyard_resources.sql     # resource_bookings: no-overlap exclusion constraint, capacity check, crane-alarm suspend/resume
  migrations/008_shipyard_materials.sql     # material_items (stock), material_trace_events (QR/RFID tag history)
  migrations/009_shipyard_quality.sql       # quality_inspections (auto pass/fail from acceptance band), punch_items
  migrations/010_shipyard_hse.sql           # work_permits (gas test enforced for hot work / confined space), hse_zones, hse_incidents
  migrations/011_shipyard_dashboard.sql     # latest_telemetry(project_id) RPC
  seed.sql                         # 3 demo projects (tug, villa, shipyard), 42 components, 36 documents, 2496 telemetry rows
                                   # + shipyard operations (6 hulls, 73 activities, org, bookings, stock, QA, HSE), dates relative to current_date
backend/
  Dockerfile, .dockerignore        # python:3.11-slim + Blender 4.2 LTS (Linux), port $PORT (default 7860); not deployed yet
  requirements-deploy.txt          # huggingface_hub + psycopg (tooling, not in the image)
  app/main.py                      # FastAPI app, CORS, GET /health[?deep=true]
  app/auth.py                      # require_editor dependency (Supabase token + app_editors)
  app/config.py                    # .env loading, Blender discovery, CORS/auth settings
  app/schemas.py                   # Pydantic request/response models
  app/routers/ingest.py            # ingest jobs (POST .../{project_id}/jobs, GET .../jobs/{job_id}) + sync POST
  app/services/ingest_jobs.py      # in-memory single-worker job runner
  app/routers/telemetry.py         # POST /api/v1/telemetry/simulate/{project_id}
  app/services/cad_parser.py       # STEP/IFC/OCX/OBJ/STL -> BOM + named trimesh Scene (Y-up)
  app/services/blender_runner.py   # subprocess wrapper for Headless Blender
  app/services/ingest_service.py   # download -> parse -> Blender -> upload -> upsert
  app/services/telemetry_simulator.py  # per-category sensor profiles + thresholds
  app/services/supabase_client.py  # service-role client
  app/blender_scripts/convert_to_glb.py          # import, clean, decimate, export GLB
  app/blender_scripts/generate_sample_models.py  # builds the 3 demo GLBs
  scripts/deploy_hf_space.py       # creates/updates a Hugging Face Docker Space (needs HF PRO)
  scripts/publish_sample_assets.py # uploads demo GLBs + generated demo documents
  scripts/reset_demo_data.py       # re-applies supabase/seed.sql over the pooler (+ --publish)
  scripts/sample_documents.py      # PDF/PNG generators (marked DEMO)
  sample_models/                   # nb42_engine_room.glb, villa_b04.glb, demo_shipyard.glb
                                   #   + manifest.json (node ids per GLB, written by generate_sample_models.py)
  tests/test_backend.py            # 17 tests: parser/node ids, editor auth, ingest jobs, PROFILES == metric_profiles,
                                   #   seed node ids exist, shipyard tables secured, sample GLB mapping contract
frontend/
  .env.example                     # public values only (bundled as an asset)
  assets/viewer/index.html, twin_scene.js   # Three.js scene + bridge
  lib/core/                        # config, theme, backend client, providers, status enum
  lib/shared/widgets/              # status badges, loading/error/empty, section card
  lib/features/auth/               # editor sign-in, read-only gating
  lib/features/projects/           # dashboard, create project, upload + ingest
  lib/features/digital_twin/       # split view, component tree, inspector, telemetry, docs, viewer bridge
  lib/features/shipyard/           # yard operations dock (shown when a project has hulls):
                                   #   Dashboard, Production (Gantt + 3D timeline), Organization, Cranes & docks,
                                   #   Materials, Quality, HSE; scene overlays/pins/labels/layers, camera presets
  test/                            # widget_test, production_schedule_test, shipyard_domain_test (pure Dart domain logic)
```

## 6. Run Commands
```powershell
# Backend (from backend/)
py -3.11 -m venv .venv                     # first time only
.venv\Scripts\python -m pip install -r requirements.txt
.venv\Scripts\python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
curl http://localhost:8000/health?deep=true
.venv\Scripts\python -m pytest -q

# OPTIONAL - deploy the backend to a Hugging Face Docker Space (requires HF PRO; HF_TOKEN with write access
# in the ROOT .env, never frontend/.env; optional HF_SPACE=<owner>/<name>). First Docker build ~10-15 min.
.venv\Scripts\python -m pip install -r requirements-deploy.txt
.venv\Scripts\python -m scripts.deploy_hf_space --wait          # --skip-secrets: code only

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
# NOTE: the CLI runs a seed file only once. After editing seed.sql it merely records the new hash
# ("Updating seed hash") without executing it. Re-apply it with (resets ALL demo projects, then
# re-links documents + GLBs):
#   backend\.venv\Scripts\python -m pip install -r requirements-deploy.txt   # once (psycopg)
#   backend\.venv\Scripts\python -m scripts.reset_demo_data --publish        # from backend/
```

## 7. Public Website (GitHub Pages)
- URL: https://ercinnn.github.io/open-digital-twin/ — built by `.github/workflows/deploy-web.yml` on every push to `main` touching `frontend/**` (Flutter stable pinned to `3.47.9` in the workflow; bump it together with local upgrades).
- CI injects config with `--dart-define` from repository secrets `SUPABASE_URL`, `SUPABASE_ANON_KEY` (optional repo variable `BACKEND_URL`, default `http://localhost:8000`). `AppConfig` prefers dart-defines and falls back to `frontend/.env`.
- Built with `--base-href /open-digital-twin/`. Locally in Git Bash prefix with `MSYS_NO_PATHCONV=1` or the path gets mangled.
- Ingest calls the FastAPI backend, which currently runs ONLY locally (`BACKEND_URL` default `http://localhost:8000`): on the public site it works for a signed-in editor whose own machine runs the backend. The code is cloud-ready (`backend/Dockerfile`, editor auth, background jobs, the app waits on `/health` while a sleeping instance wakes); hosting options are in `ROADMAP.md`. Hugging Face Docker Spaces need a PRO subscription (free cpu-basic returns 402) - `scripts/deploy_hf_space.py` only works with PRO. "Simulate Live Sensor" uses the Supabase RPC; telemetry also updates every minute without any user.

## 8. Sensor / Telemetry Integration Contract
Real sensors replace the simulator; the app needs no changes as long as readings land in `telemetry_logs`.
- **Data flow:** sensor -> gateway (Raspberry Pi / ESP32 / PLC / ship AMS via Modbus TCP, OPC UA, NMEA 2000; building BMS via Modbus/BACnet) -> HTTPS or MQTT bridge -> `telemetry_logs` insert -> Supabase Realtime -> inspector charts.
- **Row format:** `component_id` (resolve from `components.mesh_node_id`), `metric_name` (snake_case English), `metric_value` (numeric), `unit`, `recorded_at` (UTC; defaults to `now()`).
- **Thresholds:** reuse the metric names in `telemetry_simulator.PROFILES` (e.g. `vibration_velocity`, `power_consumption`) so thresholds stay consistent. IMPORTANT: threshold evaluation and automatic `components.status` changes currently live ONLY in the simulators (Python + `public._simulate_project_telemetry`) — rows inserted directly by real sensors update charts but do NOT recolor meshes until an insert trigger evaluates `public.metric_profiles` (see `ROADMAP.md`).
- **Security:** never deploy `SUPABASE_SERVICE_ROLE_KEY` to field devices. RLS only allows editors to insert. Planned approach: per-device API keys validated by a Supabase Edge Function that may only insert telemetry (revocable per device).
- **Volume:** aggregate at the gateway (e.g. 1-minute averages or send-on-change); per-second raw data exhausts the free plan (500 MB DB). The built-in simulator alone writes ~130k rows/day (90 metrics x 1/min, ~100-190 MB at 4-day retention); adding projects/metrics or real sensors needs the retention window re-checked.

## 8a. Shipyard Operations Module (migrations 005-011)
- Shown for projects with rows in `hulls` (demo project 3). All tables use `_odt_secure_table()`: public SELECT, editor-only writes (same model as 003); realtime on `production_activities`, `resource_bookings`, `punch_items`, `work_permits`.
- Business rules live in the DATABASE: booking overlap per (resource, slot) = exclusion constraint (`btree_gist`, error 23P01); load > `metadata.swl_t`/`lifting_capacity_t` rejected; crane turning `alert` suspends its running/imminent bookings and resumes them when the alarm clears (works for real sensors too); hot work / confined space permits need O2 19.5-23.5 % and LEL < 10 % to become `active`; inspections with a measured value are set pass/fail from the acceptance band.
- Block placement / Gantt / KPI logic is pure Dart (`features/shipyard/domain/services/`), unit tested. Viewer commands added: `set_placements`, `set_overlay` (+ color mode `overlay`), `set_markers` (pins, event `marker_selected`, ids `punch:|qi:|permit:|incident:<uuid>`), `set_highlights` (blink), `set_labels`, `set_hidden`, `focus_nodes`.
- `ThreeViewerController.detach(sender)` ignores stale senders: a rebuilt viewport is mounted before the old one is disposed.
- Every `NODE_*` referenced by the operations seed must exist in the demo components (backend test). Same-day bookings in the seed are relative to the current hour.
- `postgrest` `.order()` defaults to DESCENDING - always pass `ascending:` explicitly.

## 9. Git & GitHub
- Repository: https://github.com/ercinnn/open-digital-twin (public). Default branch `main`.
- Commits MUST use the GitHub noreply address (repo-local `git config user.email` is already set to `203698815+ercinnn@users.noreply.github.com`); never commit with a personal email — the repo is public.
- Never commit `.env` / `frontend/.env` (both gitignored). Secrets for CI are GitHub repository secrets.
- GitHub CLI: `C:\Program Files\GitHub CLI\gh.exe` (token scopes `repo`, `workflow`, `read:org`, `gist`). Pushing changes under `.github/workflows/` requires the `workflow` scope.

## 10. Roadmap
Planned but not yet implemented work is tracked in `ROADMAP.md` (written in Turkish): hosting the cloud CAD ingest (code is ready, a host must be chosen), persistent ingest jobs, database-side thresholds for real sensors (insert trigger on `telemetry_logs`), per-device ingest endpoint + gateway, real `.step`/`.ocx` file tests, desktop/mobile viewer tests, GitHub Actions upgrades off Node 20, and the next shipyard steps (department-scoped editors, pg_cron booking status progression, in-area block slots, remaining NB-1001/NB-1002 block geometry, camera QR/RFID scanning). Already done and documented here: the 24/7 pg_cron simulator (migration 004), editor-only backend auth + background jobs, the shipyard module (005-011). Check `ROADMAP.md` before starting related work; when an item is done, remove it there and document it in this file.

## 11. Environment Notes (Windows dev machine)
- Blender 4.2 LTS: `C:\Program Files\Blender Foundation\Blender 4.2\blender.exe` (`BLENDER_PATH` in `.env`). Without Blender, ingest falls back to an unoptimized trimesh GLB and reports a warning.
- `ifcopenshell` needs the Microsoft Visual C++ 2015-2022 x64 runtime (`MSVCP140.dll`).
- trimesh 5.x merges OBJ objects unless loaded with `split_objects=True` (handled in `cad_parser.py`).
- Riverpod 3: family notifiers receive their argument via the constructor (`NotifierProvider.family(MyNotifier.new)`); use `ref.listenManual(..., fireImmediately: true)` in `initState` for side effects.
- file_picker 13: `FilePicker.pickFiles(...)` is static and returns `List<PlatformFile>`; read bytes with `readAsBytes()`.
