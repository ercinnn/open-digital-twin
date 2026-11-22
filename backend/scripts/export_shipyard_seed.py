"""Export the ship project entered in the app (demo shipyard, project 3) into seed.sql.

`reset_demo_data` re-applies seed.sql and wipes everything entered in the app.
This script reads the app data from the remote database and rewrites two
generated regions of supabase/seed.sql (the rest of the file is hand-written):

  -- >>> export:production   hulls, hull blocks (components hull_structure),
                             schedule rows (production_activities)
  -- >>> export:operations   app-planned crane lifts (resource_bookings with an
                             activity_id), block material reservations,
                             quality inspections (ITP points and single ones),
                             work permits

Dates become day offsets from the export day (current_date of the database =
day 0), so the demo stays "live" whenever the seed is re-applied. Blocks get no
NODE_* literals (their mesh id is derived in SQL, other rows join on hull_no +
block_no), so the GLB contract test only sees the yard nodes.

Not exported (hand-written seed sections): stock items, maintenance bookings,
organization, HSE zones and incidents. Issued reservations are replayed as `issued`, so the database
lowers the seeded stock on hand again (and writes the trace event) - do not also
lower quantity_on_hand in the stock section.

Connection: like reset_demo_data (supabase/.temp/pooler-url + SUPABASE_DB_PASSWORD).

Run from backend/:
    .venv\\Scripts\\python -m scripts.export_shipyard_seed [--dry-run]
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sys
from decimal import Decimal

from scripts.reset_demo_data import SEED_FILE, connection_url

PROJECT_ID = "33333333-3333-3333-3333-333333333333"
P = f"'{PROJECT_ID}'"


# ---------------------------------------------------------------------------
# SQL literals
# ---------------------------------------------------------------------------
def lit(value: object) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, Decimal):
        value = value.normalize()
        text = format(value, "f")
        return text
    if isinstance(value, (int, float)):
        return repr(value)
    return "'" + str(value).replace("'", "''") + "'"


def days(value: dt.date | None, day0: dt.date) -> str:
    return "null" if value is None else str((value - day0).days)


def utc_offset(value: dt.datetime | None, day0: dt.date) -> tuple[str, str]:
    """(day offset, minutes after midnight UTC) of a timestamptz."""
    if value is None:
        return "null", "null"
    v = value.astimezone(dt.timezone.utc)
    return str((v.date() - day0).days), str(v.hour * 60 + v.minute)


def values_block(header: str, rows: list[list[str]]) -> str:
    """`(values ...)` rows with aligned columns and a comment header."""
    widths = [max(len(r[i]) for r in rows) for i in range(len(rows[0]))]
    lines = []
    for n, r in enumerate(rows):
        cells = [c + "," + " " * (widths[i] - len(c)) for i, c in enumerate(r[:-1])] + [r[-1]]
        lines.append("    (" + " ".join(cells) + ")" + ("," if n < len(rows) - 1 else ""))
    return f"    -- {header}\n" + "\n".join(lines)


# ---------------------------------------------------------------------------
# Sections
# ---------------------------------------------------------------------------
def production_sql(cur, day0: dt.date) -> tuple[str, dict[str, int]]:
    hulls = cur.execute(
        """select hull_no, name, ship_type, contract_type, owner_name, class_society, length_m, beam_m, deadweight_t,
                  contract_date, steel_cutting_date, keel_laying_date, launching_date, contract_delivery_date,
                  forecast_delivery_date, status, location_node_id, metadata
             from public.hulls where project_id = %s order by hull_no""",
        (PROJECT_ID,),
    ).fetchall()
    blocks = cur.execute(
        """select metadata, name, material, weight_kg
             from public.components
            where project_id = %s and category = 'hull_structure'
            order by metadata->>'hull_no', (metadata->>'erection_sequence')::int nulls last, metadata->>'block_no'""",
        (PROJECT_ID,),
    ).fetchall()
    activities = cur.execute(
        """select h.hull_no, c.metadata->>'block_no', a.activity_code, a.name, a.stage, a.location_node_id,
                  a.planned_start, a.planned_end, a.actual_start, a.actual_end, a.progress_pct, a.sort_order, a.notes,
                  c.category, a.work_package, d.code
             from public.production_activities a
             left join public.hulls h on h.id = a.hull_id
             left join public.components c on c.id = a.component_id
             left join public.departments d on d.id = a.department_id
            where a.project_id = %s
            order by h.hull_no, a.sort_order, a.activity_code""",
        (PROJECT_ID,),
    ).fetchall()
    for a in activities:
        if a[13] is not None and a[13] != "hull_structure":
            raise SystemExit(f"Schedule row {a[2]} is linked to a non-block component - not supported by the export")

    out = [
        "-- >>> export:production (generated by scripts.export_shipyard_seed - do not edit by hand)",
        "-- Hulls and production schedule (005): ship projects entered in the app (Production tab:",
        '-- "New hull", "Blocks", "Plan" > Draft schedule), exported on '
        f"{day0.isoformat()}. Dates are day offsets",
        "-- from current_date (export day = 0). Blocks have no Blender geometry (the viewer draws them,",
        "-- HullBlockGeometry): their mesh_node_id is derived here like blockMeshNodeId() in",
        "-- block_entities.dart, other rows reference them by hull_no + block_no.",
    ]
    if hulls:
        rows = []
        for h in hulls:
            rows.append(
                [lit(h[0]), lit(h[1]), lit(h[2]), lit(h[3]), lit(h[4]), lit(h[5]), lit(h[6]), lit(h[7]), lit(h[8])]
                + [days(d, day0) for d in h[9:15]]
                + [lit(h[15]), lit(h[16]), lit(json.dumps(h[17] or {}, sort_keys=True))]
            )
        out.append(
            """insert into public.hulls
    (project_id, hull_no, name, ship_type, contract_type, owner_name, class_society, length_m, beam_m, deadweight_t,
     contract_date, steel_cutting_date, keel_laying_date, launching_date, contract_delivery_date, forecast_delivery_date,
     status, location_node_id, metadata)
select """
            + P
            + """, x.hull_no, x.name, x.ship_type, x.contract_type, x.owner_name, x.class_society,
       x.length_m::numeric, x.beam_m::numeric, x.dwt::numeric,
       current_date + x.d_contract::int, current_date + x.d_cut::int, current_date + x.d_keel::int,
       current_date + x.d_launch::int, current_date + x.d_delivery::int, current_date + x.d_forecast::int,
       x.status, x.location, x.metadata::jsonb
from (values
"""
            + values_block(
                "hull, name, ship type, contract, owner, class, L, B, dwt, days: contract, steel cutting, keel, "
                "launching, delivery, forecast; status, location, metadata",
                rows,
            )
            + """
) as x(hull_no, name, ship_type, contract_type, owner_name, class_society, length_m, beam_m, dwt,
       d_contract, d_cut, d_keel, d_launch, d_delivery, d_forecast, status, location, metadata);
"""
        )
    if blocks:
        known = {"hull_no", "block_no", "block_type", "block_type_label", "zone", "side", "erection_sequence"}
        rows = []
        for meta, name, material, weight in blocks:
            extra = {k: v for k, v in meta.items() if k not in known}
            text = json.dumps(extra, sort_keys=True)
            if "NODE_" in text:
                raise SystemExit(f"Block {meta.get('block_no')} metadata references a NODE_* id - not supported")
            rows.append(
                [
                    lit(meta.get("hull_no")),
                    lit(meta.get("block_no")),
                    lit(meta.get("block_type")),
                    lit(meta.get("block_type_label")),
                    lit(meta.get("zone")),
                    lit(meta.get("side")),
                    lit(meta.get("erection_sequence")),
                    lit(name),
                    lit(material),
                    lit(weight),
                    lit(text),
                ]
            )
        out.append(
            """-- Hull blocks (category hull_structure, metadata as written by the Blocks dialog).
insert into public.components (project_id, mesh_node_id, name, category, material, weight_kg, status, metadata)
select """
            + P
            + """,
       'NODE_' || regexp_replace(upper(x.hull_no), '[^A-Z0-9]', '', 'g') || '_BLOCK_'
           || regexp_replace(upper(x.block_no), '[^A-Z0-9]+', '_', 'g'),
       x.name, 'hull_structure', x.material, x.weight_kg::numeric, 'normal',
       x.extra::jsonb || jsonb_build_object('hull_no', x.hull_no, 'block_no', x.block_no, 'block_type', x.block_type,
                          'block_type_label', x.type_label, 'zone', x.zone, 'side', x.side,
                          'erection_sequence', x.seq::int)
from (values
"""
            + values_block(
                "hull, block, type, type label, zone, side, erection sequence, name, material, weight kg, "
                "other metadata",
                rows,
            )
            + """
) as x(hull_no, block_no, block_type, type_label, zone, side, seq, name, material, weight_kg, extra);
"""
        )
    if activities:
        rows = []
        for a in activities:
            rows.append(
                [
                    lit(a[0]),
                    lit(a[1]),
                    lit(a[2]),
                    lit(a[3]),
                    lit(a[4]),
                    lit(a[5]),
                    days(a[6], day0),
                    days(a[7], day0),
                    days(a[8], day0),
                    days(a[9], day0),
                    lit(a[10]),
                    lit(a[11]),
                    lit(a[12]),
                    lit(a[14]),
                    lit(a[15]),
                ]
            )
        out.append(
            """-- Schedule rows: shop chain + erection per block (block null = hull rows launching ... delivery,
-- work package = afloat outfitting package, 017; department by code).
insert into public.production_activities
    (project_id, hull_id, component_id, activity_code, name, stage, location_node_id, planned_start, planned_end,
     actual_start, actual_end, progress_pct, sort_order, notes, work_package, department_id)
select """
            + P
            + """, h.id, c.id, x.code, x.name, x.stage, x.location, current_date + x.d0::int, current_date + x.d1::int,
       current_date + x.a0::int, current_date + x.a1::int, x.progress::numeric, x.sort::int, x.notes, x.package, d.id
from (values
"""
            + values_block(
                "hull, block, activity code, name, stage, location, planned start, end, actual start, end (days), "
                "progress %, sort, notes, work package, department",
                rows,
            )
            + """
) as x(hull_no, block_no, code, name, stage, location, d0, d1, a0, a1, progress, sort, notes, package, dept)
left join public.hulls h on h.project_id = """
            + P
            + """ and h.hull_no = x.hull_no
left join public.components c on c.project_id = """
            + P
            + """ and c.category = 'hull_structure'
    and c.metadata->>'hull_no' = x.hull_no and c.metadata->>'block_no' = x.block_no
left join public.departments d on d.project_id = """
            + P
            + """ and d.code = x.dept;
"""
        )
    out.append("-- <<< export:production")
    return "\n".join(out) + "\n", {"hulls": len(hulls), "blocks": len(blocks), "schedule rows": len(activities)}


def operations_sql(cur, day0: dt.date) -> tuple[str, dict[str, int]]:
    lifts = cur.execute(
        """select c.mesh_node_id, h.hull_no, a.activity_code, b.title, b.booking_type, b.slot, b.starts_at, b.ends_at,
                  b.load_t, b.status, b.notes
             from public.resource_bookings b
             join public.components c on c.id = b.component_id
             join public.production_activities a on a.id = b.activity_id
             left join public.hulls h on h.id = b.hull_id
            where b.project_id = %s
            order by b.starts_at, a.activity_code""",
        (PROJECT_ID,),
    ).fetchall()
    reservations = cur.execute(
        """select i.item_code, c.category, c.metadata->>'hull_no', c.metadata->>'block_no', c.mesh_node_id,
                  h.hull_no, r.quantity, r.needed_by, r.status, r.issued_at, r.notes, a.activity_code
             from public.material_reservations r
             join public.material_items i on i.id = r.item_id
             join public.components c on c.id = r.component_id
             left join public.hulls h on h.id = r.hull_id
             left join public.production_activities a on a.id = r.activity_id
            where r.project_id = %s
            order by c.metadata->>'hull_no', (c.metadata->>'erection_sequence')::int nulls last, c.mesh_node_id,
                     i.item_code, r.created_at""",
        (PROJECT_ID,),
    ).fetchall()

    inspections = cur.execute(
        """select q.reference_no, q.inspection_type, c.category, c.metadata->>'hull_no', c.metadata->>'block_no',
                  c.mesh_node_id, h.hull_no, a.activity_code, q.hold_point, q.description, q.result, q.measured_value,
                  q.unit, q.acceptance_min, q.acceptance_max, q.inspector, q.witnessed_by, q.inspected_at,
                  q.marker_u, q.marker_v, q.marker_w, q.notes
             from public.quality_inspections q
             join public.components c on c.id = q.component_id
             left join public.hulls h on h.id = q.hull_id
             left join public.production_activities a on a.id = q.activity_id
            where q.project_id = %s
            order by q.inspected_at, q.reference_no""",
        (PROJECT_ID,),
    ).fetchall()

    permits = cur.execute(
        """select w.permit_no, w.permit_type, c.category, c.metadata->>'hull_no', c.metadata->>'block_no',
                  c.mesh_node_id, h.hull_no, a.activity_code, w.description, w.status, w.valid_from, w.valid_to,
                  w.issued_to, w.gas_test_o2_pct, w.gas_test_lel_pct, w.gas_tested_at, w.precautions,
                  w.marker_u, w.marker_v, w.marker_w
             from public.work_permits w
             join public.components c on c.id = w.component_id
             left join public.hulls h on h.id = w.hull_id
             left join public.production_activities a on a.id = w.activity_id
            where w.project_id = %s
            order by w.valid_from, w.permit_no""",
        (PROJECT_ID,),
    ).fetchall()

    checklist = cur.execute(
        """select a.activity_code, k.item_code, k.title, k.category, k.required, k.status, k.completed_at,
                  k.completed_by, k.notes, k.sort_order
             from public.handover_checklist_items k
             join public.production_activities a on a.id = k.activity_id
            where k.project_id = %s
            order by a.activity_code, k.sort_order, k.item_code""",
        (PROJECT_ID,),
    ).fetchall()

    out = ["-- >>> export:operations (generated by scripts.export_shipyard_seed - do not edit by hand)"]
    if lifts:
        rows = []
        for node, hull_no, code, title, btype, slot, start, end, load_t, status, notes in lifts:
            d0, m0 = utc_offset(start, day0)
            d1, m1 = utc_offset(end, day0)
            rows.append(
                [lit(node), lit(hull_no), lit(code), lit(title), lit(btype), lit(slot), d0, m0, d1, m1]
                + [lit(load_t), lit(status), lit(notes)]
            )
        out.append(
            """-- Block erection lifts (Resources "Plan block lifts"), one per erection schedule row:
-- day offsets from current_date, minutes after midnight UTC.
insert into public.resource_bookings
    (project_id, component_id, hull_id, activity_id, title, booking_type, slot, starts_at, ends_at, load_t, status, notes)
select """
            + P
            + """, c.id, h.id, a.id, x.title, x.booking_type, x.slot,
       (current_date + x.d0::int)::timestamp at time zone 'UTC' + make_interval(mins => x.m0::int),
       (current_date + x.d1::int)::timestamp at time zone 'UTC' + make_interval(mins => x.m1::int),
       x.load_t::numeric, x.status, x.notes
from (values
"""
            + values_block(
                "resource node, hull, activity code, title, type, slot, d0, m0, d1, m1, load_t, status, notes", rows
            )
            + """
) as x(node, hull_no, activity_code, title, booking_type, slot, d0, m0, d1, m1, load_t, status, notes)
join public.components c on c.project_id = """
            + P
            + """ and c.mesh_node_id = x.node
left join public.hulls h on h.project_id = """
            + P
            + """ and h.hull_no = x.hull_no
join public.production_activities a on a.project_id = """
            + P
            + """ and a.activity_code = x.activity_code;
"""
        )
    if reservations:
        rows = []
        for code, category, b_hull, b_no, node, hull_no, qty, needed, status, issued, notes, act in reservations:
            is_block = category == "hull_structure"
            issued_d, issued_m = utc_offset(issued, day0)
            rows.append(
                [
                    lit(code),
                    lit(b_hull if is_block else None),
                    lit(b_no if is_block else None),
                    lit(None if is_block else node),
                    lit(hull_no),
                    lit(qty),
                    days(needed, day0),
                    lit(status),
                    issued_d,
                    issued_m,
                    lit(notes),
                    lit(act),
                ]
            )
        out.append(
            """-- Material reservations (012; Blocks dialog > block, Materials "Reserve steel"; work packages:
-- activity = package row, component = its yard area, 018 / Materials "Reserve outfitting").
-- The database recalculates material_items.quantity_block_reserved; `issued` rows lower
-- the stock on hand and write the trace event again.
insert into public.material_reservations
    (project_id, item_id, component_id, hull_id, quantity, needed_by, status, issued_at, notes, activity_id)
select """
            + P
            + """, i.id, c.id, h.id, x.quantity::numeric, current_date + x.d_needed::int, x.status,
       (current_date + x.d_issued::int)::timestamp at time zone 'UTC' + make_interval(mins => x.m_issued::int),
       x.notes, a.id
from (values
"""
            + values_block(
                "item, block hull, block, other component node, hull, quantity, needed by (days), status, "
                "issued (days, minutes UTC), notes, activity",
                rows,
            )
            + """
) as x(item_code, block_hull, block_no, node, hull_no, quantity, d_needed, status, d_issued, m_issued, notes, activity)
join public.material_items i on i.project_id = """
            + P
            + """ and i.item_code = x.item_code
join public.components c on c.project_id = """
            + P
            + """
    and ((x.block_no is not null and c.category = 'hull_structure'
          and c.metadata->>'hull_no' = x.block_hull and c.metadata->>'block_no' = x.block_no)
      or (x.block_no is null and c.mesh_node_id = x.node))
left join public.hulls h on h.project_id = """
            + P
            + """ and h.hull_no = x.hull_no
left join public.production_activities a on a.project_id = """
            + P
            + """ and a.activity_code = x.activity;
"""
        )
    if inspections:
        rows = []
        for q in inspections:
            is_block = q[2] == "hull_structure"
            d, m = utc_offset(q[17], day0)
            rows.append(
                [lit(q[0]), lit(q[1])]
                + [lit(q[3] if is_block else None), lit(q[4] if is_block else None), lit(None if is_block else q[5])]
                + [lit(v) for v in q[6:17]]
                + [d, m]
                + [lit(v) for v in q[18:22]]
            )
        out.append(
            """-- Quality inspections (009 / 013; Quality "Plan", block dialog > Inspections): ITP points are
-- linked to their schedule row by activity code; inspected_at = planned time while pending.
insert into public.quality_inspections
    (project_id, component_id, hull_id, activity_id, hold_point, inspection_type, reference_no, description, result,
     measured_value, unit, acceptance_min, acceptance_max, inspector, witnessed_by, inspected_at,
     marker_u, marker_v, marker_w, notes)
select """
            + P
            + """, c.id, h.id, a.id, x.hold::boolean, x.itype, x.ref, x.descr, x.result,
       x.measured::numeric, x.unit, x.amin::numeric, x.amax::numeric, x.inspector, x.witness,
       (current_date + x.d::int)::timestamp at time zone 'UTC' + make_interval(mins => x.m::int),
       x.u::numeric, x.v::numeric, x.w::numeric, x.notes
from (values
"""
            + values_block(
                "reference, type, block hull, block, other component node, hull, activity code, hold point, "
                "description, result, measured, unit, min, max, inspector, witness, days, minutes UTC, u, v, w, notes",
                rows,
            )
            + """
) as x(ref, itype, block_hull, block_no, node, hull_no, activity_code, hold, descr, result, measured, unit, amin, amax,
       inspector, witness, d, m, u, v, w, notes)
join public.components c on c.project_id = """
            + P
            + """
    and ((x.block_no is not null and c.category = 'hull_structure'
          and c.metadata->>'hull_no' = x.block_hull and c.metadata->>'block_no' = x.block_no)
      or (x.block_no is null and c.mesh_node_id = x.node))
left join public.hulls h on h.project_id = """
            + P
            + """ and h.hull_no = x.hull_no
left join public.production_activities a on a.project_id = """
            + P
            + """ and a.activity_code = x.activity_code;
"""
        )
    if permits:
        rows = []
        for w in permits:
            is_block = w[2] == "hull_structure"
            f_d, f_m = utc_offset(w[10], day0)
            t_d, t_m = utc_offset(w[11], day0)
            g_d, g_m = utc_offset(w[15], day0)
            rows.append(
                [lit(w[0]), lit(w[1])]
                + [lit(w[3] if is_block else None), lit(w[4] if is_block else None), lit(None if is_block else w[5])]
                + [lit(v) for v in w[6:10]]
                + [f_d, f_m, t_d, t_m]
                + [lit(v) for v in w[12:15]]
                + [g_d, g_m]
                + [lit(v) for v in w[16:20]]
            )
        out.append(
            """-- Work permits (010 / 015; HSE "Request permit", block dialog > Permits). Inserted after the
-- lifts: an active lifting permit of an erection row needs its booked crane lift.
insert into public.work_permits
    (project_id, component_id, hull_id, activity_id, permit_no, permit_type, description, status, valid_from, valid_to,
     issued_to, gas_test_o2_pct, gas_test_lel_pct, gas_tested_at, precautions, marker_u, marker_v, marker_w)
select """
            + P
            + """, c.id, h.id, a.id, x.permit_no, x.ptype, x.descr, x.status,
       (current_date + x.fd::int)::timestamp at time zone 'UTC' + make_interval(mins => x.fm::int),
       (current_date + x.td::int)::timestamp at time zone 'UTC' + make_interval(mins => x.tm::int),
       x.issued_to, x.o2::numeric, x.lel::numeric,
       (current_date + x.gd::int)::timestamp at time zone 'UTC' + make_interval(mins => x.gm::int),
       x.precautions, x.u::numeric, x.v::numeric, x.w::numeric
from (values
"""
            + values_block(
                "permit no, type, block hull, block, other component node, hull, activity code, description, status, "
                "valid from (days, minutes UTC), valid to (days, minutes UTC), issued to, O2 %, LEL %, "
                "gas tested (days, minutes UTC), precautions, u, v, w",
                rows,
            )
            + """
) as x(permit_no, ptype, block_hull, block_no, node, hull_no, activity_code, descr, status, fd, fm, td, tm,
       issued_to, o2, lel, gd, gm, precautions, u, v, w)
join public.components c on c.project_id = """
            + P
            + """
    and ((x.block_no is not null and c.category = 'hull_structure'
          and c.metadata->>'hull_no' = x.block_hull and c.metadata->>'block_no' = x.block_no)
      or (x.block_no is null and c.mesh_node_id = x.node))
left join public.hulls h on h.project_id = """
            + P
            + """ and h.hull_no = x.hull_no
left join public.production_activities a on a.project_id = """
            + P
            + """ and a.activity_code = x.activity_code;
"""
        )
    if checklist:
        rows = []
        for code, item, title, category, required, status, completed, by, notes, sort in checklist:
            c_d, c_m = utc_offset(completed, day0)
            rows.append(
                [lit(code), lit(item), lit(title), lit(category), lit(required), lit(status), c_d, c_m]
                + [lit(by), lit(notes), lit(sort)]
            )
        out.append(
            """-- Sea trial / delivery checklists (019; Production: tap the sea trials / delivery bar > Checklist).
insert into public.handover_checklist_items
    (project_id, activity_id, item_code, title, category, required, status, completed_at, completed_by, notes,
     sort_order)
select """
            + P
            + """, a.id, x.item, x.title, x.category, x.required::boolean, x.status,
       (current_date + x.cd::int)::timestamp at time zone 'UTC' + make_interval(mins => x.cm::int),
       x.done_by, x.notes, x.sort::int
from (values
"""
            + values_block(
                "activity code, item, title, category, required, status, completed (days, minutes UTC), by, notes, "
                "sort",
                rows,
            )
            + """
) as x(activity_code, item, title, category, required, status, cd, cm, done_by, notes, sort)
join public.production_activities a on a.project_id = """
            + P
            + """ and a.activity_code = x.activity_code;
"""
        )
    out.append("-- <<< export:operations")
    counts = {
        "crane lifts": len(lifts),
        "material reservations": len(reservations),
        "inspections": len(inspections),
        "permits": len(permits),
        "checklist items": len(checklist),
    }
    return "\n".join(out) + "\n", counts


def replace_region(seed: str, name: str, body: str) -> str:
    pattern = re.compile(rf"^-- >>> export:{name}\b.*?^-- <<< export:{name}\n", re.S | re.M)
    if len(pattern.findall(seed)) != 1:
        raise SystemExit(f"seed.sql must contain exactly one region '-- >>> export:{name}' ... '-- <<< export:{name}'")
    return pattern.sub(lambda _: body, seed, count=1)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true", help="Print the counts, do not write seed.sql.")
    args = parser.parse_args()

    try:
        import psycopg
    except ImportError as exc:  # pragma: no cover - tooling dependency
        raise SystemExit("psycopg is not installed: pip install -r requirements-deploy.txt") from exc

    with psycopg.connect(connection_url()) as conn:
        day0 = conn.execute("select current_date").fetchone()[0]
        production, counts = production_sql(conn, day0)
        operations, more = operations_sql(conn, day0)
    counts.update(more)

    raw = SEED_FILE.read_bytes().decode("utf-8")
    crlf = "\r\n" in raw
    seed = raw.replace("\r\n", "\n")
    seed = replace_region(seed, "production", production)
    seed = replace_region(seed, "operations", operations)
    summary = ", ".join(f"{v} {k}" for k, v in counts.items())
    if args.dry_run:
        print(f"Export day {day0}: {summary} (dry run, seed.sql unchanged)")
        return 0
    SEED_FILE.write_bytes((seed.replace("\n", "\r\n") if crlf else seed).encode("utf-8"))
    print(f"seed.sql updated (export day {day0}): {summary}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
