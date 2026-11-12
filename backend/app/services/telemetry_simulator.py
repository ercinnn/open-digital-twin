"""Live sensor simulator.

Each component category has a sensor profile. New readings are a mean-reverting
random walk starting from the latest stored value (so seeded trends continue
naturally), with occasional excursions toward the unhealthy direction. Thresholds
derive a health level per metric; the worst level can drive `components.status`
(which Supabase Realtime pushes to the 3D viewer). Workflow statuses such as
`in_progress` are never overwritten by sensor data.
"""

from __future__ import annotations

import random
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any

from app.services.supabase_client import get_supabase

STATUS_RANK = {"normal": 0, "warning": 1, "alert": 2}
SENSOR_DRIVEN_STATUSES = {"normal", "warning", "alert"}


@dataclass(frozen=True)
class MetricProfile:
    metric_name: str
    unit: str
    nominal: float
    sigma: float
    warning: float
    alert: float
    direction: str = "high"  # "high": larger is worse, "low": smaller is worse
    reversion: float = 0.18
    excursion_probability: float = 0.04
    minimum: float = 0.0


PROFILES: dict[str, list[MetricProfile]] = {
    "propulsion": [
        MetricProfile("engine_speed", "rpm", 898.0, 4.0, 960.0, 1000.0),
        MetricProfile("exhaust_gas_temperature", "°C", 382.0, 4.5, 420.0, 450.0),
        MetricProfile("lube_oil_pressure", "bar", 4.2, 0.06, 3.5, 3.0, direction="low"),
    ],
    "cooling_system": [
        MetricProfile("vibration_velocity", "mm/s", 3.2, 0.25, 4.5, 7.1),
        MetricProfile("discharge_pressure", "bar", 2.6, 0.05, 2.0, 1.6, direction="low"),
    ],
    "hull_structure": [
        MetricProfile("plate_strain", "µε", 310.0, 12.0, 900.0, 1200.0),
        MetricProfile("ambient_humidity", "%", 61.0, 1.5, 85.0, 95.0, minimum=0.0),
    ],
    "fuel_system": [
        MetricProfile("back_pressure", "bar", 1.6, 0.04, 2.0, 2.5),
        MetricProfile("separation_temperature", "°C", 97.5, 0.4, 102.0, 105.0),
    ],
    "structural": [
        MetricProfile("axial_strain", "µε", 185.0, 6.0, 600.0, 850.0),
        MetricProfile("tilt", "mrad", 0.22, 0.02, 1.5, 2.5),
    ],
    "hvac": [
        MetricProfile("power_consumption", "kW", 3.4, 0.3, 6.0, 7.5),
        MetricProfile("outlet_water_temperature", "°C", 45.0, 0.6, 55.0, 60.0),
        MetricProfile("coefficient_of_performance", "COP", 4.1, 0.08, 2.8, 2.2, direction="low"),
    ],
    "plumbing": [
        MetricProfile("line_pressure", "bar", 3.1, 0.05, 2.2, 1.5, direction="low"),
        MetricProfile("water_temperature", "°C", 47.0, 1.0, 60.0, 70.0),
    ],
    "electrical": [
        MetricProfile("power_draw", "kW", 2.0, 0.15, 4.0, 5.0),
        MetricProfile("conductor_temperature", "°C", 38.0, 0.8, 70.0, 90.0),
    ],
    "part": [
        MetricProfile("surface_temperature", "°C", 32.0, 0.6, 60.0, 75.0),
    ],
}


def profile_for(category: str | None) -> list[MetricProfile]:
    return PROFILES.get((category or "").lower(), PROFILES["part"])


def level_for(profile: MetricProfile, value: float) -> str:
    if profile.direction == "low":
        if value <= profile.alert:
            return "alert"
        if value <= profile.warning:
            return "warning"
        return "normal"
    if value >= profile.alert:
        return "alert"
    if value >= profile.warning:
        return "warning"
    return "normal"


def next_value(profile: MetricProfile, previous: float | None, rng: random.Random) -> float:
    current = profile.nominal if previous is None else previous
    value = current + profile.reversion * (profile.nominal - current) + rng.gauss(0.0, profile.sigma)
    if rng.random() < profile.excursion_probability:
        span = abs(profile.alert - profile.nominal)
        push = rng.uniform(0.35, 0.8) * span
        value += push if profile.direction == "high" else -push
    return round(max(profile.minimum, value), 3)


def worst_level(levels: list[str]) -> str:
    return max(levels, key=lambda lvl: STATUS_RANK[lvl]) if levels else "normal"


def _latest_values(component_ids: list[str]) -> dict[tuple[str, str], float]:
    latest: dict[tuple[str, str], float] = {}
    if not component_ids:
        return latest
    rows = (
        get_supabase()
        .table("telemetry_logs")
        .select("component_id,metric_name,metric_value,recorded_at")
        .in_("component_id", component_ids)
        .order("recorded_at", desc=True)
        .limit(max(200, 40 * len(component_ids)))
        .execute()
        .data
    )
    for row in rows:
        key = (row["component_id"], row["metric_name"])
        if key not in latest:
            latest[key] = float(row["metric_value"])
    return latest


def simulate_project(
    project_id: str,
    steps: int = 1,
    update_status: bool = True,
    interval_seconds: int = 5,
    seed: int | None = None,
) -> dict[str, Any]:
    client = get_supabase()
    project = client.table("projects").select("id").eq("id", project_id).limit(1).execute().data
    if not project:
        raise LookupError(f"Project {project_id} not found")

    components = (
        client.table("components")
        .select("id,mesh_node_id,name,category,status")
        .eq("project_id", project_id)
        .execute()
        .data
    )
    rng = random.Random(seed)
    latest = _latest_values([c["id"] for c in components])
    now = datetime.now(timezone.utc)

    rows: list[dict[str, Any]] = []
    status_changes: list[dict[str, Any]] = []
    for component in components:
        levels: list[str] = []
        for profile in profile_for(component.get("category")):
            key = (component["id"], profile.metric_name)
            value = latest.get(key)
            for step in range(steps):
                value = next_value(profile, value, rng)
                recorded_at = now - timedelta(seconds=interval_seconds * (steps - 1 - step))
                rows.append(
                    {
                        "component_id": component["id"],
                        "metric_name": profile.metric_name,
                        "metric_value": value,
                        "unit": profile.unit,
                        "recorded_at": recorded_at.isoformat(),
                    }
                )
            levels.append(level_for(profile, value))

        derived = worst_level(levels)
        current = component.get("status") or "normal"
        if update_status and current in SENSOR_DRIVEN_STATUSES and derived != current:
            client.table("components").update({"status": derived}).eq("id", component["id"]).execute()
            status_changes.append(
                {"mesh_node_id": component["mesh_node_id"], "from_status": current, "to_status": derived}
            )

    if rows:
        client.table("telemetry_logs").insert(rows).execute()

    return {
        "project_id": project_id,
        "components": len(components),
        "readings_inserted": len(rows),
        "status_changes": status_changes,
        "readings": rows,
    }
