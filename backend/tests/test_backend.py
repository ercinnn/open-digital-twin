"""Offline unit tests (no Supabase calls): health, CAD parsing, mapping contract, simulator."""

from __future__ import annotations

import random
import re
import time
from pathlib import Path
from types import SimpleNamespace

import pytest
import trimesh
from fastapi.testclient import TestClient

from app import auth as auth_module
from app.config import SAMPLE_MODELS_DIR
from app.main import app
from app.routers import ingest as ingest_router
from app.services.cad_parser import CadParseError, parse_cad_file, sanitize_node_id
from app.services.ingest_service import IngestError, normalize_storage_path
from app.services.telemetry_simulator import PROFILES, MetricProfile, level_for, next_value, worst_level


def test_health_ok() -> None:
    response = TestClient(app).get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert "blender_available" in body


def test_sanitize_node_id_is_stable_and_unique() -> None:
    used: set[str] = set()
    assert sanitize_node_id("NODE_MAIN_ENGINE_PORT", used) == "NODE_MAIN_ENGINE_PORT"
    assert sanitize_node_id("Engine Block #1", used) == "NODE_ENGINE_BLOCK_1"
    assert sanitize_node_id("engine-block 1", used) == "NODE_ENGINE_BLOCK_1_02"
    assert all(len(n) <= 60 for n in used)


def test_parse_obj_preserves_names_and_volume(tmp_path: Path) -> None:
    scene = trimesh.Scene()
    scene.add_geometry(trimesh.creation.box(extents=(2.0, 1.0, 0.5)), node_name="Main Engine", geom_name="Main Engine")
    scene.add_geometry(
        trimesh.creation.cylinder(radius=0.2, height=1.0), node_name="Cooling Pump", geom_name="Cooling Pump"
    )
    src = tmp_path / "parts.glb"
    scene.export(str(src))

    result = parse_cad_file(src, domain_type="marine")
    by_id = {c.mesh_node_id: c for c in result.components}
    assert set(by_id) == {"NODE_MAIN_ENGINE", "NODE_COOLING_PUMP"}
    engine = by_id["NODE_MAIN_ENGINE"]
    assert engine.category == "propulsion"
    assert engine.volume_m3 == pytest.approx(1.0, rel=1e-3)
    assert engine.weight_kg == pytest.approx(7850.0, rel=1e-3)  # domain default steel
    assert set(result.scene.graph.nodes_geometry) == set(by_id)


SEED_SQL = Path(__file__).resolve().parents[2] / "supabase" / "seed.sql"
_COMPONENT_ROW = re.compile(
    r"\(\s*'[0-9a-f-]{36}',\s*'(?P<project>[0-9a-f-]{36})',\s*'(?P<node>NODE_[A-Z0-9_]+)',\s*'[^']*',\s*'(?P<category>[a-z_]+)'"
)


def _seed_component_rows() -> list[re.Match[str]]:
    return list(_COMPONENT_ROW.finditer(SEED_SQL.read_text(encoding="utf-8")))


def _seed_mesh_node_ids(project_id: str) -> list[str]:
    return [m["node"] for m in _seed_component_rows() if m["project"] == project_id]


MIGRATIONS_DIR = Path(__file__).resolve().parents[2] / "supabase" / "migrations"
_PROFILE_ROW = re.compile(
    r"\('(?P<category>[a-z_]+)', '(?P<metric>[a-z_]+)', '(?P<unit>[^']*)', "
    r"(?P<nominal>[-0-9.]+), (?P<sigma>[-0-9.]+), (?P<warning>[-0-9.]+), (?P<alert>[-0-9.]+), "
    r"'(?P<direction>high|low)', (?P<reversion>[-0-9.]+), (?P<excursion>[-0-9.]+), (?P<minimum>[-0-9.]+), (?P<order>\d+)\)"
)


def test_database_metric_profiles_match_python_profiles() -> None:
    """migration 004 (metric_profiles) must mirror telemetry_simulator.PROFILES exactly."""
    sql = (MIGRATIONS_DIR / "004_db_telemetry_simulator.sql").read_text(encoding="utf-8")
    db = {(m["category"], m["metric"]): m for m in _PROFILE_ROW.finditer(sql)}
    expected = {(cat, p.metric_name): (i, p) for cat, profiles in PROFILES.items() for i, p in enumerate(profiles)}
    assert set(db) == set(expected)
    for key, (order, p) in expected.items():
        row = db[key]
        assert row["unit"] == p.unit, key
        assert row["direction"] == p.direction, key
        assert int(row["order"]) == order, key
        for field, value in (
            ("nominal", p.nominal),
            ("sigma", p.sigma),
            ("warning", p.warning),
            ("alert", p.alert),
            ("reversion", p.reversion),
            ("excursion", p.excursion_probability),
            ("minimum", p.minimum),
        ):
            assert float(row[field]) == pytest.approx(value), (key, field)


def test_seed_categories_have_sensor_profiles() -> None:
    rows = _seed_component_rows()
    assert len(rows) >= 36
    missing = {m["category"] for m in rows} - set(PROFILES)
    assert not missing, f"Seed categories without a telemetry profile: {sorted(missing)}"


def test_sample_models_satisfy_mapping_contract() -> None:
    expected = {
        "nb42_engine_room.glb": {
            "NODE_MAIN_ENGINE_PORT",
            "NODE_SW_COOLING_PUMP_01",
            "NODE_HULL_BLOCK_ER_04",
            "NODE_FUEL_PURIFIER_01",
        },
        "villa_b04.glb": {"NODE_RC_COLUMN_S01", "NODE_HEAT_PUMP_UNIT", "NODE_CONCEALED_PIPE_KITCHEN"},
        "demo_shipyard.glb": set(_seed_mesh_node_ids("33333333-3333-3333-3333-333333333333")),
    }
    assert len(expected["demo_shipyard.glb"]) == 29
    for filename, nodes in expected.items():
        path = SAMPLE_MODELS_DIR / filename
        if not path.exists():
            pytest.skip("Sample models not generated yet")
        scene = trimesh.load(str(path), force="scene")
        assert nodes <= set(scene.graph.nodes_geometry)


PROJECT_ID = "33333333-3333-3333-3333-333333333333"


class _FakeTable:
    def __init__(self, rows: list[dict]) -> None:
        self._rows = rows

    def select(self, *_args, **_kwargs) -> "_FakeTable":
        return self

    def eq(self, *_args, **_kwargs) -> "_FakeTable":
        return self

    def limit(self, *_args, **_kwargs) -> "_FakeTable":
        return self

    def execute(self) -> SimpleNamespace:
        return SimpleNamespace(data=self._rows)


class _FakeSupabase:
    """Accepts the token 'good' for user u1; u1 is an editor when `is_editor` is True."""

    def __init__(self, is_editor: bool) -> None:
        self._is_editor = is_editor
        self.auth = SimpleNamespace(get_user=self._get_user)

    @staticmethod
    def _get_user(token: str) -> SimpleNamespace:
        if token != "good":
            raise ValueError("invalid JWT")
        return SimpleNamespace(user=SimpleNamespace(id="u1"))

    def table(self, _name: str) -> _FakeTable:
        return _FakeTable([{"user_id": "u1"}] if self._is_editor else [])


def test_api_requires_editor_token() -> None:
    client = TestClient(app)
    assert client.post(f"/api/v1/ingest/{PROJECT_ID}/jobs").status_code == 401
    assert client.post(f"/api/v1/ingest/{PROJECT_ID}").status_code == 401
    assert client.get("/api/v1/ingest/jobs/abc").status_code == 401
    assert client.post(f"/api/v1/telemetry/simulate/{PROJECT_ID}").status_code == 401
    assert client.get("/health").status_code == 200


def test_invalid_token_and_non_editor_are_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    client = TestClient(app)
    monkeypatch.setattr(auth_module, "get_supabase", lambda: _FakeSupabase(is_editor=False))
    bad = client.post(f"/api/v1/ingest/{PROJECT_ID}/jobs", headers={"Authorization": "Bearer nope"})
    assert bad.status_code == 401
    forbidden = client.post(f"/api/v1/ingest/{PROJECT_ID}/jobs", headers={"Authorization": "Bearer good"})
    assert forbidden.status_code == 403


def test_ingest_job_lifecycle(monkeypatch: pytest.MonkeyPatch) -> None:
    client = TestClient(app)
    monkeypatch.setattr(auth_module, "get_supabase", lambda: _FakeSupabase(is_editor=True))
    fake_result = {
        "project_id": PROJECT_ID,
        "source_path": f"{PROJECT_ID}/model.step",
        "source_format": "step",
        "unit_scale": 0.001,
        "optimizer": "blender",
        "glb_model_url": "https://example.invalid/model.glb",
        "glb_size_bytes": 1234,
        "components_upserted": 3,
        "stale_components": [],
        "stale_pruned": False,
        "mesh_node_ids": ["NODE_A", "NODE_B", "NODE_C"],
        "node_report": [],
        "warnings": [],
        "elapsed_s": 0.1,
    }
    monkeypatch.setattr(ingest_router, "run_ingest", lambda *args: fake_result)
    headers = {"Authorization": "Bearer good"}

    started = client.post(f"/api/v1/ingest/{PROJECT_ID}/jobs", headers=headers, json={})
    assert started.status_code == 202
    job_id = started.json()["job_id"]

    body: dict = {}
    for _ in range(100):
        body = client.get(f"/api/v1/ingest/jobs/{job_id}", headers=headers).json()
        if body["status"] in ("succeeded", "failed"):
            break
        time.sleep(0.02)
    assert body["status"] == "succeeded", body
    assert body["result"]["components_upserted"] == 3
    assert client.get("/api/v1/ingest/jobs/unknown", headers=headers).status_code == 404


def test_failed_ingest_job_reports_error(monkeypatch: pytest.MonkeyPatch) -> None:
    client = TestClient(app)
    monkeypatch.setattr(auth_module, "get_supabase", lambda: _FakeSupabase(is_editor=True))

    def boom(*_args):
        raise IngestError(422, "No mesh geometry found")

    monkeypatch.setattr(ingest_router, "run_ingest", boom)
    headers = {"Authorization": "Bearer good"}
    job_id = client.post(f"/api/v1/ingest/{PROJECT_ID}/jobs", headers=headers).json()["job_id"]
    body: dict = {}
    for _ in range(100):
        body = client.get(f"/api/v1/ingest/jobs/{job_id}", headers=headers).json()
        if body["status"] in ("succeeded", "failed"):
            break
        time.sleep(0.02)
    assert body["status"] == "failed"
    assert body["error_status"] == 422
    assert "No mesh geometry" in body["error"]


def test_unsupported_extension() -> None:
    with pytest.raises(CadParseError):
        parse_cad_file(Path("model.dwg"))


def test_normalize_storage_path() -> None:
    url = "https://x.supabase.co/storage/v1/object/public/raw-cad-files/p1/model.step"
    assert normalize_storage_path(url, "raw-cad-files") == "p1/model.step"
    assert normalize_storage_path("raw-cad-files/p1/a.ifc", "raw-cad-files") == "p1/a.ifc"
    assert normalize_storage_path("/p1/a.ifc", "raw-cad-files") == "p1/a.ifc"


def test_threshold_levels() -> None:
    high = MetricProfile("vibration_velocity", "mm/s", 3.2, 0.2, 4.5, 7.1)
    low = MetricProfile("lube_oil_pressure", "bar", 4.2, 0.1, 3.5, 3.0, direction="low")
    assert level_for(high, 3.0) == "normal"
    assert level_for(high, 5.0) == "warning"
    assert level_for(high, 8.0) == "alert"
    assert level_for(low, 4.0) == "normal"
    assert level_for(low, 3.2) == "warning"
    assert level_for(low, 2.9) == "alert"
    assert worst_level(["normal", "alert", "warning"]) == "alert"


def test_random_walk_reverts_toward_nominal() -> None:
    profile = MetricProfile("x", "u", 10.0, 0.0, 20.0, 30.0, excursion_probability=0.0)
    rng = random.Random(1)
    value = 25.0
    for _ in range(30):
        value = next_value(profile, value, rng)
    assert abs(value - 10.0) < 0.2


def test_profiles_match_seed_metric_names() -> None:
    seed = (Path(__file__).resolve().parents[2] / "supabase" / "seed.sql").read_text(encoding="utf-8")
    for profiles in PROFILES.values():
        for profile in profiles:
            if profile.metric_name in ("power_draw", "conductor_temperature", "surface_temperature"):
                continue
            assert f"'{profile.metric_name}'" in seed
