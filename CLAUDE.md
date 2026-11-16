# CLAUDE.md - Open Digital Twin Platform

Open-source digital twin for ships / shipyards and buildings. CAD (`.step` `.ifc` `.ocx` `.obj` `.stl`) -> Python BOM + Headless Blender `.glb` -> Supabase (data, storage, realtime) -> Flutter app with an embedded Three.js viewer.

## 1. Next task (do this first)
**Step 6 - show NB-1004 block by block in 3D** (steps 1-5c, all done in the app: add/edit hull, schedule, stock, inspections, permits).
- Model `NODE_NB1004_BLOCK_*` meshes in `backend/app/blender_scripts/generate_sample_models.py` (at their ERECTED position) and add them as `components` in `supabase/seed.sql`.
- Move NB-1004 itself (hull, schedule rows) into `seed.sql`: rows created in the app are deleted by `reset_demo_data`.
- Use block-level schedule rows (`component_id` = block) so `set_placements` moves the blocks; the app's draft schedule is hull-level only.
- Solve the berth clash: NB-1001 stays at its erected position on the berth forever (also after launching), NB-1004 would overlap.
- Then: backend test (every seeded `NODE_*` exists), regenerate GLBs, `scripts.publish_sample_assets`, `scripts.reset_demo_data --publish`.

## 2. Stack
- Frontend: Flutter (Web + Windows primary) + `flutter_riverpod` 3.x + `supabase_flutter`. Feature-first clean architecture (`data` / `domain` / `presentation`); complete files, no TODOs.
- 3D: Three.js r170 in `frontend/assets/viewer/` (iframe on web, WebView2 on Windows), channels `FlutterToThree` / `ThreeToFlutter`.
- Backend: Python 3.11 FastAPI + trimesh (`cascadio` for STEP) / `ifcopenshell` + Blender 4.2 LTS headless. Runs only locally for now.
- Supabase project `unksjqvehethysjubclj` (Frankfurt).

**Where things are**
- `supabase/migrations/001-011` (schema, RLS, simulator, shipyard), `supabase/seed.sql` (3 demo projects: tug, villa, shipyard).
- `backend/app/` (`routers/`, `services/cad_parser.py`, `ingest_service.py`, `telemetry_simulator.py`, `blender_scripts/`), `backend/scripts/`, `backend/tests/`.
- `frontend/lib/core/` (config, theme, backend client), `features/{auth,projects,digital_twin,shipyard}/`, `frontend/assets/viewer/`.

## 3. Rules (critical)
- **DB names:** English `snake_case` for tables, columns, RPCs, buckets.
- **Mesh ids:** every GLB node keeps its `mesh_node_id` = `components.mesh_node_id`; format `NODE_<UPPER_SNAKE>` (<= 60 chars, `cad_parser.sanitize_node_id`), stored as node name and `extras.mesh_node_id`. Ingest fails (HTTP 500) if a BOM id is missing in the GLB.
- **Context geometry** `CTX_*`: not in the BOM, ghosted and not pickable (`extras.ctx_opacity` 0..1, default 0.16, >= 0.99 opaque).
- **Hull blocks** `NODE_<HULL>_BLOCK_*` are modelled at their erected position; the viewer moves them to the area of their running / last schedule row, ghosts them during cutting / bending / panel and hides them before the first activity.
- **Secrets:** `SUPABASE_SERVICE_ROLE_KEY` only in the root `.env`. `frontend/.env` is bundled into the app: public values only. Never commit either.
- **Access:** `anon` / `authenticated` read only. Writes need an editor (row in `public.app_editors`, RPC `is_editor()`); the UI shows write controls only if `isEditorProvider`. Add one: `insert into public.app_editors (user_id) select id from auth.users where email = '<email>';`
- **Backend auth:** all endpoints except `/health` need `Authorization: Bearer <editor access token>` (`app/auth.py`). `AUTH_REQUIRED=false` only for local experiments.
- **Status values:** `normal` green, `in_progress` blue, `warning` orange, `alert` pulsing red. Simulators never overwrite `in_progress`.
- **Business rules live in the database** (constraints / triggers); the app shows their error messages (`ShipyardRepositoryImpl._rethrow`).

## 4. Pipeline
1. Upload CAD to bucket `raw-cad-files` (`<project_id>/<file>`, `projects.raw_file_url`).
2. App starts `POST /api/v1/ingest/{project_id}/jobs` (202) and polls `GET /api/v1/ingest/jobs/{job_id}` (one job at a time, in memory). `cad_parser.py` -> BOM upsert into `components` on `(project_id, mesh_node_id)`; Blender `convert_to_glb.py` -> `processed-models/<project_id>/model.glb`, `projects.glb_model_url`. Without Blender: unoptimized trimesh GLB + warning.
3. Click on a mesh -> `node_selected` -> details, documents, telemetry. Realtime on `components.status` recolors meshes.
4. Sensor simulation runs in the DB (migration 004): pg_cron `odt_simulate_telemetry` (1/min, thresholds from `metric_profiles`), `odt_telemetry_retention` (4 days), `odt_cron_history_cleanup`. Button = RPC `simulate_telemetry` (editors); "Live" stops after 10 min. `metric_profiles` MUST mirror `telemetry_simulator.PROFILES` (backend test) - change both in a new migration.

## 5. Shipyard module (migrations 005-011, demo project 3)
- Shown for projects with rows in `hulls`. Tables use `_odt_secure_table()` (public read, editor write); realtime on `production_activities`, `resource_bookings`, `punch_items`, `work_permits`.
- DB rules: booking overlap per (resource, slot) = exclusion constraint (23P01); load > `metadata.swl_t` / `lifting_capacity_t` rejected; crane `alert` suspends / resumes its bookings; hot work / confined space need O2 19.5-23.5 % and LEL < 10 % to become `active`; inspections with a measured value get pass / fail from the acceptance band.
- Editors can create / edit in the app: hulls (Production "New hull", Dashboard card tap), schedule rows (Production "Plan": draft from milestones, add, edit plan, delete), stock items (Materials "New item", tap to edit), inspections (Quality "Plan": single or ITP draft from the schedule; record result, delete), permits (HSE "Request permit", then approve / activate).
- Pure Dart logic in `features/shipyard/domain/services/` (placements, Gantt, KPIs, `draft_schedule.dart`, `inspection_plan.dart`) and draft classes with `validationErrors()` in `domain/entities/`, all unit tested.
- Viewer commands: `set_placements`, `set_overlay` (color mode `overlay`), `set_markers` (event `marker_selected`, ids `punch:|qi:|permit:|incident:<uuid>`), `set_highlights`, `set_labels`, `set_hidden`, `focus_nodes`. `ThreeViewerController.detach(sender)` ignores stale senders.
- Every `NODE_*` referenced by the operations seed must exist in the demo components (backend test). Seed dates are relative to `current_date` / the current hour.

## 6. Gotchas
- PostgREST `.order()` defaults to DESCENDING: always pass `ascending:`.
- Web: the viewer iframe swallows clicks under Flutter dialogs / menus; `three_viewport_web.dart` makes it click-through while another route covers the page. Keep it when touching the viewport.
- Web: horizontal lists need explicit mouse support (scrollbar, drag, wheel), see `_HullStrip` in `dashboard_tab.dart`.
- `DropdownButtonFormField.initialValue` is read once: give it a `ValueKey` when the value changes programmatically.
- Riverpod 3: family notifiers get their argument via the constructor; use `ref.listenManual(..., fireImmediately: true)` in `initState`; check `mounted` before using `ref` after an `await`.
- Do not run `dart format` on existing folders (the code is not dart-format clean); format only new files.
- trimesh 5 merges OBJ objects unless `split_objects=True`; `ifcopenshell` needs the MSVC 2015-2022 x64 runtime. file_picker 13: static `FilePicker.pickFiles`, read with `readAsBytes()`.
- Supabase CLI runs `seed.sql` only once; after editing it use `scripts.reset_demo_data --publish` (resets ALL demo projects, incl. data entered in the app).

## 7. Commands
```powershell
# Backend (backend/)
py -3.11 -m venv .venv; .venv\Scripts\python -m pip install -r requirements.txt
.venv\Scripts\python -m uvicorn app.main:app --reload --port 8000     # curl localhost:8000/health?deep=true
.venv\Scripts\python -m pytest -q
"C:\Program Files\Blender Foundation\Blender 4.2\blender.exe" --background --factory-startup --python-exit-code 1 --python app/blender_scripts/generate_sample_models.py
.venv\Scripts\python -m scripts.publish_sample_assets [--generate] [--force-docs]
.venv\Scripts\python -m pip install -r requirements-deploy.txt          # psycopg, huggingface_hub (tooling)
.venv\Scripts\python -m scripts.reset_demo_data --publish               # re-apply seed.sql
.venv\Scripts\python -m scripts.deploy_hf_space --wait                  # optional, needs HF PRO + HF_TOKEN in root .env

# Frontend (frontend/)
flutter pub get; flutter analyze; flutter test
flutter run -d chrome | windows

# Supabase CLI (%USERPROFILE%\scoop\shims\supabase.exe)
supabase link --project-ref unksjqvehethysjubclj -p <SUPABASE_DB_PASSWORD>
supabase db push --include-seed -p <SUPABASE_DB_PASSWORD>
```

## 8. Deployment
- Web: https://ercinnn.github.io/open-digital-twin/ - `.github/workflows/deploy-web.yml` on every push to `main` touching `frontend/**` (~3 min). Config via `--dart-define` from repo secrets `SUPABASE_URL`, `SUPABASE_ANON_KEY` (variable `BACKEND_URL`, default `http://localhost:8000`); `AppConfig` falls back to `frontend/.env`. `--base-href /open-digital-twin/` (Git Bash: `MSYS_NO_PATHCONV=1`).
- Only ingest needs the backend; everything else talks to Supabase directly. `supabase-keepalive.yml` pings the free project twice a week.
- Backend is cloud-ready (`backend/Dockerfile`, port `$PORT`/7860) but not hosted; options in `ROADMAP.md`. HF Docker Spaces need PRO.

## 9. Sensors (real devices replace the simulator)
- Flow: sensor -> gateway (Modbus TCP, OPC UA, NMEA 2000, BACnet) -> HTTPS / MQTT bridge -> `telemetry_logs` (`component_id`, snake_case `metric_name`, `metric_value`, `unit`, `recorded_at` UTC) -> realtime charts.
- Reuse metric names of `telemetry_simulator.PROFILES`. Thresholds / status changes exist only in the simulators: direct inserts update charts but do not recolor meshes until an insert trigger is added (`ROADMAP.md`).
- Never put the service-role key on devices; planned: per-device keys via an Edge Function. Aggregate at the gateway (1-min averages); the simulator alone writes ~130k rows/day (free plan: 500 MB).

## 10. Git
- Repo https://github.com/ercinnn/open-digital-twin (public), branch `main`. Commit with the noreply address (repo-local `user.email` is set); never a personal email.
- `gh`: `C:\Program Files\GitHub CLI\gh.exe` (scopes `repo`, `workflow`); pushing `.github/workflows/` needs `workflow`.
- Further planned work: `ROADMAP.md` (check before related work, remove items when done).
