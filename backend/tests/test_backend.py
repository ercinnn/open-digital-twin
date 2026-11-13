"""Offline unit tests (no Supabase calls): health, CAD parsing, mapping contract, simulator."""

from __future__ import annotations

import random
import re
from pathlib import Path

import pytest
import trimesh
from fastapi.testclient import TestClient

from app.config import SAMPLE_MODELS_DIR
from app.main import app
from app.services.cad_parser import CadParseError, parse_cad_file, sanitize_node_id
from app.services.ingest_service import normalize_storage_path
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
