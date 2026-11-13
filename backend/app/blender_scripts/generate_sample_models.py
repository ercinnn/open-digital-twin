"""Generate the demo digital-twin .glb models with Headless Blender.

Usage:
    blender --background --factory-startup --python-exit-code 1 \
        --python backend/app/blender_scripts/generate_sample_models.py -- \
        [--output-dir backend/sample_models]

Outputs:
    nb42_engine_room.glb  -> NODE_MAIN_ENGINE_PORT, NODE_SW_COOLING_PUMP_01,
                             NODE_HULL_BLOCK_ER_04, NODE_FUEL_PURIFIER_01
    villa_b04.glb         -> NODE_RC_COLUMN_S01, NODE_HEAT_PUMP_UNIT,
                             NODE_CONCEALED_PIPE_KITCHEN (+ CTX_* context meshes)
    demo_shipyard.glb     -> NODE_A01..NODE_A20 yard areas, NODE_CRN_* cranes,
                             NODE_NB1001_BLOCK_* newbuild blocks (+ CTX_* sea, ships,
                             production-flow arrows)

CTX_* objects may carry a `ctx_opacity` custom property (glTF extras) that the
viewer uses instead of its default ghost opacity.

3D mapping contract: every component is ONE mesh object whose object name (the
glTF node name) and custom property `mesh_node_id` (glTF extras) equal the
`components.mesh_node_id` column in Supabase. Context-only geometry is prefixed
with `CTX_` and is not part of the BOM.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    default_out = Path(__file__).resolve().parents[2] / "sample_models"
    parser = argparse.ArgumentParser(description="Generate demo twin GLB models.")
    parser.add_argument("--output-dir", type=Path, default=default_out)
    return parser.parse_args(argv)


# --------------------------------------------------------------------------- #
# Scene / material helpers
# --------------------------------------------------------------------------- #


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0


_MATERIAL_CACHE: dict[str, bpy.types.Material] = {}


def material(
    name: str,
    color: tuple[float, float, float],
    metallic: float = 0.0,
    roughness: float = 0.5,
    alpha: float = 1.0,
) -> bpy.types.Material:
    if name in _MATERIAL_CACHE:
        return _MATERIAL_CACHE[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Alpha"].default_value = alpha
    mat.diffuse_color = (*color, alpha)
    if alpha < 1.0:
        mat.blend_method = "BLEND"
        mat.use_backface_culling = False
    _MATERIAL_CACHE[name] = mat
    return mat


class PartBuilder:
    """Accumulates primitives into a single bmesh -> one mesh object (one glTF node)."""

    def __init__(self) -> None:
        self.bm = bmesh.new()

    def box(
        self,
        center: tuple[float, float, float],
        size: tuple[float, float, float],
        rot_y_deg: float = 0.0,
    ) -> "PartBuilder":
        rot = Matrix.Rotation(math.radians(rot_y_deg), 4, "Y") if rot_y_deg else Matrix.Identity(4)
        mat = Matrix.Translation(Vector(center)) @ rot @ Matrix.Diagonal((*size, 1.0))
        bmesh.ops.create_cube(self.bm, size=1.0, matrix=mat)
        return self

    def polyhedron(self, verts: list[tuple[float, float, float]], faces: list[tuple[int, ...]]) -> "PartBuilder":
        bm_verts = [self.bm.verts.new(v) for v in verts]
        for face in faces:
            self.bm.faces.new([bm_verts[i] for i in face])
        return self

    def gable_roof(
        self, center: tuple[float, float, float], length: float, span: float, rise: float, axis: str = "X"
    ) -> "PartBuilder":
        """Triangular prism roof; `center` is the middle of the eave plane, ridge runs along `axis`."""
        cx, cy, cz = center
        hl, hs = length / 2, span / 2
        if axis == "X":
            pts = [(-hl, -hs, 0), (-hl, hs, 0), (-hl, 0, rise), (hl, -hs, 0), (hl, hs, 0), (hl, 0, rise)]
        else:
            pts = [(-hs, -hl, 0), (hs, -hl, 0), (0, -hl, rise), (-hs, hl, 0), (hs, hl, 0), (0, hl, rise)]
        verts = [(cx + x, cy + y, cz + z) for x, y, z in pts]
        return self.polyhedron(verts, [(0, 2, 1), (3, 4, 5), (0, 3, 5, 2), (1, 2, 5, 4), (0, 1, 4, 3)])

    def wedge(
        self,
        base_center: tuple[float, float],
        width: float,
        length: float,
        z0: float,
        z1: float,
        direction: str = "Y+",
    ) -> "PartBuilder":
        """Bow-shaped wedge: full `width` at the base, tapering to a vertical stem `length` away."""
        bx, by = base_center
        sign = 1.0 if direction.endswith("+") else -1.0
        if direction.startswith("Y"):
            a, b, tip = (bx - width / 2, by), (bx + width / 2, by), (bx, by + sign * length)
        else:
            a, b, tip = (bx, by - width / 2), (bx, by + width / 2), (bx + sign * length, by)
        verts = [(*a, z0), (*b, z0), (*tip, z0), (*a, z1), (*b, z1), (*tip, z1)]
        return self.polyhedron(verts, [(0, 2, 1), (3, 4, 5), (0, 1, 4, 3), (1, 2, 5, 4), (2, 0, 3, 5)])

    def cone(
        self,
        center: tuple[float, float, float],
        radius: float,
        depth: float,
        direction: tuple[float, float, float],
        segments: int = 16,
    ) -> "PartBuilder":
        """Cone whose tip points along `direction` (used for flow arrowheads)."""
        rot = Vector((0, 0, 1)).rotation_difference(Vector(direction).normalized()).to_matrix().to_4x4()
        mat = Matrix.Translation(Vector(center)) @ rot
        bmesh.ops.create_cone(
            self.bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius, radius2=0.0, depth=depth, matrix=mat
        )
        return self

    def cylinder(
        self,
        center: tuple[float, float, float],
        radius: float,
        depth: float,
        axis: str = "Z",
        radius_top: float | None = None,
        segments: int = 32,
    ) -> "PartBuilder":
        rot = {
            "Z": Matrix.Identity(4),
            "X": Matrix.Rotation(math.radians(90), 4, "Y"),
            "Y": Matrix.Rotation(math.radians(90), 4, "X"),
        }[axis]
        mat = Matrix.Translation(Vector(center)) @ rot
        bmesh.ops.create_cone(
            self.bm,
            cap_ends=True,
            cap_tris=False,
            segments=segments,
            radius1=radius,
            radius2=radius if radius_top is None else radius_top,
            depth=depth,
            matrix=mat,
        )
        return self

    def sphere(self, center: tuple[float, float, float], radius: float) -> "PartBuilder":
        mat = Matrix.Translation(Vector(center))
        bmesh.ops.create_uvsphere(self.bm, u_segments=32, v_segments=16, radius=radius, matrix=mat)
        return self

    def build(
        self,
        node_id: str,
        mat: bpy.types.Material,
        collection: bpy.types.Collection,
        ctx_opacity: float | None = None,
    ) -> bpy.types.Object:
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        mesh = bpy.data.meshes.new(node_id)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for poly in mesh.polygons:
            poly.use_smooth = False
        mesh.materials.append(mat)
        obj = bpy.data.objects.new(node_id, mesh)
        obj["mesh_node_id"] = node_id
        if ctx_opacity is not None:
            obj["ctx_opacity"] = ctx_opacity  # glTF extras -> viewer ghost opacity for CTX_ meshes
        collection.objects.link(obj)
        return obj


def pipe_from_polylines(
    node_id: str,
    polylines: list[list[tuple[float, float, float]]],
    radius: float,
    mat: bpy.types.Material,
    collection: bpy.types.Collection,
) -> bpy.types.Object:
    """Sweep a circular profile along polylines and bake the result into one mesh object."""
    curve = bpy.data.curves.new(f"{node_id}_curve", type="CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 4
    curve.use_fill_caps = True
    for points in polylines:
        spline = curve.splines.new("POLY")
        spline.points.add(len(points) - 1)
        for idx, (x, y, z) in enumerate(points):
            spline.points[idx].co = (x, y, z, 1.0)
    tmp = bpy.data.objects.new(f"{node_id}_tmp", curve)
    collection.objects.link(tmp)

    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(tmp.evaluated_get(depsgraph))
    mesh.name = node_id
    bpy.data.objects.remove(tmp, do_unlink=True)
    bpy.data.curves.remove(curve)

    mesh.materials.clear()
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(node_id, mesh)
    obj["mesh_node_id"] = node_id
    collection.objects.link(obj)
    return obj


def export_glb(path: Path) -> list[str]:
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        export_extras=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
        use_selection=False,
    )
    return sorted(o.name for o in bpy.context.scene.objects if o.type == "MESH")


# --------------------------------------------------------------------------- #
# NB-42 Harbor Tugboat - Engine Room
# Coordinates (Blender Z-up, metres): +X forward, +Y port, Z up from base line.
# --------------------------------------------------------------------------- #


def build_engine_room(col: bpy.types.Collection) -> None:
    steel = material("MAT_HULL_STEEL_AH36", (0.55, 0.58, 0.62), metallic=0.85, roughness=0.45)
    engine_paint = material("MAT_ENGINE_GREEN_RAL6011", (0.27, 0.42, 0.30), metallic=0.3, roughness=0.5)
    bronze = material("MAT_NI_AL_BRONZE", (0.72, 0.52, 0.30), metallic=0.9, roughness=0.35)
    stainless = material("MAT_STAINLESS_316L", (0.80, 0.82, 0.84), metallic=0.95, roughness=0.25)

    # ---- Hull block ER-04: double bottom + side shell ----------------------
    hull = PartBuilder()
    length, beam, db_height, shell_t = 8.0, 7.0, 1.0, 0.04
    hull.box((0, 0, shell_t / 2), (length, beam, shell_t))  # bottom shell
    hull.box((0, 0, db_height), (length, beam - 0.4, shell_t))  # tank top / inner bottom
    for x in [-3.5 + i for i in range(8)]:  # transverse floors
        hull.box((x, 0, db_height / 2), (0.03, beam - 0.4, db_height))
    for y in (-2.4, -1.2, 0.0, 1.2, 2.4):  # longitudinal girders
        hull.box((0, y, db_height / 2), (length, 0.03, db_height))
    # Cutaway: only the port side shell (+Y) is modelled so the twin can be inspected
    # from starboard without the shell plating hiding the machinery.
    for side in (1,):  # side shell + side frames
        y = side * (beam / 2)
        hull.box((0, y, 1.75), (length, shell_t, 3.5))
        for x in [-3.5 + i for i in range(8)]:
            hull.box((x, y - side * 0.12, 2.2), (0.08, 0.24, 2.4))
    hull.build("NODE_HULL_BLOCK_ER_04", steel, col)

    # ---- Main engine (port) ------------------------------------------------
    me = PartBuilder()
    ey, base_z = 1.6, db_height + shell_t / 2
    me.box((0.0, ey, base_z + 0.15), (4.2, 1.5, 0.3))  # bedplate / seating
    me.box((0.0, ey, base_z + 0.95), (3.8, 1.2, 1.3))  # crankcase / block
    me.box((0.0, ey, base_z + 1.75), (3.6, 0.95, 0.3))  # cylinder block top
    for i in range(6):  # cylinder heads + rocker covers
        cx = -1.5 + i * 0.6
        me.box((cx, ey, base_z + 2.05), (0.5, 0.75, 0.3))
        me.cylinder((cx, ey + 0.2, base_z + 2.3), 0.05, 0.2)  # injector stub
    me.box((0.0, ey - 0.62, base_z + 1.6), (3.4, 0.18, 0.22))  # exhaust manifold
    me.cylinder((2.25, ey - 0.3, base_z + 1.9), 0.32, 0.6, axis="X")  # turbocharger
    me.cylinder((2.25, ey - 0.3, base_z + 2.35), 0.18, 0.5)  # exhaust uptake
    me.cylinder((-2.2, ey, base_z + 0.85), 0.7, 0.2, axis="X", segments=48)  # flywheel
    me.cylinder((-2.6, ey, base_z + 0.85), 0.18, 0.6, axis="X")  # output shaft
    me.box((0.0, ey + 0.72, base_z + 0.7), (2.0, 0.25, 0.4))  # lube oil cooler
    me.build("NODE_MAIN_ENGINE_PORT", engine_paint, col)

    # ---- Sea water cooling pump No.1 (starboard) ---------------------------
    pump = PartBuilder()
    px, py = -2.0, -1.9
    pump.box((px, py, base_z + 0.05), (0.8, 0.6, 0.1))  # base plate
    pump.cylinder((px, py, base_z + 0.35), 0.3, 0.32, axis="Y", segments=40)  # volute casing
    pump.cylinder((px, py, base_z + 0.75), 0.14, 0.3)  # lantern / coupling
    pump.cylinder((px, py, base_z + 1.15), 0.22, 0.55)  # motor
    pump.cylinder((px, py, base_z + 1.48), 0.16, 0.1)  # fan cowl
    pump.cylinder((px - 0.45, py, base_z + 0.35), 0.1, 0.5, axis="X")  # suction nozzle
    pump.cylinder((px, py - 0.4, base_z + 0.55), 0.08, 0.45, axis="Y")  # discharge nozzle
    pump.cylinder((px - 0.72, py, base_z + 0.35), 0.16, 0.04, axis="X")  # suction flange
    pump.build("NODE_SW_COOLING_PUMP_01", bronze, col)

    # ---- HFO/MGO fuel purifier No.1 (starboard, forward) -------------------
    pur = PartBuilder()
    fx, fy = 1.6, -2.1
    pur.box((fx, fy, base_z + 0.2), (1.0, 0.8, 0.4))  # frame / gear housing
    pur.cylinder((fx, fy, base_z + 0.75), 0.36, 0.7, segments=48)  # bowl casing
    pur.cylinder((fx, fy, base_z + 1.25), 0.36, 0.3, radius_top=0.12, segments=48)  # hood cone
    pur.cylinder((fx, fy, base_z + 1.45), 0.06, 0.18)  # outlet neck
    pur.cylinder((fx + 0.62, fy, base_z + 0.35), 0.16, 0.4, axis="X")  # motor
    pur.cylinder((fx - 0.45, fy + 0.25, base_z + 0.9), 0.04, 0.6, axis="X")  # feed pipe
    pur.build("NODE_FUEL_PURIFIER_01", stainless, col)


# --------------------------------------------------------------------------- #
# Didim Coastal Villa B-04
# Coordinates: X east, Y north, Z up from finished ground-floor slab level.
# --------------------------------------------------------------------------- #


def build_villa(col: bpy.types.Collection) -> None:
    concrete = material("MAT_CONCRETE_C30_37", (0.66, 0.66, 0.64), roughness=0.9)
    ghost_concrete = material("MAT_CTX_CONCRETE_GHOST", (0.78, 0.80, 0.82), roughness=0.9, alpha=0.18)
    ghost_wall = material("MAT_CTX_WALL_GHOST", (0.93, 0.90, 0.84), roughness=0.9, alpha=0.22)
    casing = material("MAT_GALVANIZED_CASING", (0.88, 0.89, 0.90), metallic=0.6, roughness=0.4)
    pipe_mat = material("MAT_PERT_AL_MULTILAYER", (0.85, 0.20, 0.15), roughness=0.4)

    # ---- Context: ground slab, other columns, kitchen wall -----------------
    PartBuilder().box((0, 0, -0.125), (10.0, 8.0, 0.25)).build("CTX_GROUND_SLAB", ghost_concrete, col)
    PartBuilder().box((0, 0, 3.775), (10.0, 8.0, 0.25)).build("CTX_FIRST_FLOOR_SLAB", ghost_concrete, col)
    for idx, (x, y) in enumerate([(4.5, -3.5), (-4.5, 3.5), (4.5, 3.5), (0.0, -3.5), (0.0, 3.5)], start=2):
        PartBuilder().box((x, y, 1.825), (0.4, 0.4, 3.65)).build(f"CTX_RC_COLUMN_S{idx:02d}", ghost_concrete, col)
    PartBuilder().box((2.25, 3.5, 1.45), (4.1, 0.2, 2.9)).build("CTX_KITCHEN_WALL", ghost_wall, col)

    # ---- Structural RC column S01 (grid A-1) -------------------------------
    column = PartBuilder()
    column.box((-4.5, -3.5, 1.825), (0.4, 0.4, 3.65))  # 400x400 shaft between slabs
    column.box((-4.5, -3.5, -0.55), (1.4, 1.4, 0.6))  # pad footing below slab
    column.box((-4.5, -3.5, -0.2), (0.5, 0.5, 0.15))  # column kicker
    column.build("NODE_RC_COLUMN_S01", concrete, col)

    # ---- Heat pump outdoor unit (east facade) ------------------------------
    hp = PartBuilder()
    hx, hy = 5.9, -0.5
    hp.box((hx, hy, 0.06), (1.3, 0.6, 0.12))  # concrete plinth
    for dy in (-0.18, 0.18):  # anti-vibration feet
        hp.box((hx, hy + dy, 0.17), (1.1, 0.06, 0.1))
    hp.box((hx, hy, 0.72), (0.45, 1.15, 1.0))  # casing (fan faces +X)
    hp.cylinder((hx + 0.24, hy - 0.18, 0.78), 0.3, 0.04, axis="X", segments=48)  # fan grille
    hp.cylinder((hx + 0.26, hy - 0.18, 0.78), 0.06, 0.04, axis="X")  # fan hub
    hp.box((hx + 0.235, hy + 0.38, 0.78), (0.02, 0.28, 0.6))  # service panel
    hp.cylinder((hx - 0.4, hy + 0.3, 0.5), 0.03, 0.5, axis="X")  # flow pipe to building
    hp.cylinder((hx - 0.4, hy + 0.42, 0.5), 0.03, 0.5, axis="X")  # return pipe
    hp.build("NODE_HEAT_PUMP_UNIT", casing, col)

    # ---- Concealed hot + cold pipe run inside the kitchen wall -------------
    wall_y = 3.5
    hot = [(0.4, wall_y, 0.0), (0.4, wall_y, 1.10), (3.6, wall_y, 1.10), (3.6, wall_y, 0.62), (3.75, wall_y - 0.12, 0.62)]
    cold = [(0.55, wall_y, 0.0), (0.55, wall_y, 1.22), (3.8, wall_y, 1.22), (3.8, wall_y, 0.62), (3.95, wall_y - 0.12, 0.62)]
    # Display radius exaggerated (real DN20) so the run stays visible/clickable at building scale.
    pipe_from_polylines("NODE_CONCEALED_PIPE_KITCHEN", [hot, cold], 0.045, pipe_mat, col)


# --------------------------------------------------------------------------- #
# Demo Shipyard - yard operations + NB-1001 production flow
# Coordinates: X east, Y north, Z up from yard ground level (metres, real scale).
# Sea lies to the south and east; the waterline is at Z = -3.
# Layout is a simplified, axis-aligned version of the reference layout plan
# (areas 1-20). Footprints are representative; real capacities live in the
# components.metadata column.
# --------------------------------------------------------------------------- #

SEA_Z = -3.0


def _hangar(pb: PartBuilder, x0: float, x1: float, y0: float, y1: float, height: float) -> PartBuilder:
    """Clad steel hall: wall box + gable roof along the long axis + large doors on both gable ends."""
    cx, cy, lx, ly = (x0 + x1) / 2, (y0 + y1) / 2, x1 - x0, y1 - y0
    pb.box((cx, cy, height / 2), (lx, ly, height))
    if lx >= ly:
        pb.gable_roof((cx, cy, height), lx, ly, 0.16 * ly, axis="X")
        for x in (x0 - 0.4, x1 + 0.4):
            pb.box((x, cy, height * 0.36), (0.8, ly * 0.55, height * 0.72))
    else:
        pb.gable_roof((cx, cy, height), ly, lx, 0.16 * lx, axis="Y")
        for y in (y0 - 0.4, y1 + 0.4):
            pb.box((cx, y, height * 0.36), (lx * 0.55, 0.8, height * 0.72))
    return pb


def _slab(pb: PartBuilder, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> PartBuilder:
    return pb.box(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (x1 - x0, y1 - y0, z1 - z0))


def _gantry_crane(pb: PartBuilder, x_left: float, x_right: float, y: float, height: float, trolley_x: float) -> PartBuilder:
    """Portal / goliath crane spanning along X: twin-post legs, box girder, trolley, hoist and hook."""
    for x in (x_left, x_right):
        pb.box((x, y, 1.5), (7.0, 22.0, 3.0))  # travelling bogie
        for dy in (-6.0, 6.0):
            pb.box((x, y + dy, height / 2 + 1.5), (3.0, 3.0, height - 3.0))  # leg posts
        pb.box((x, y, height * 0.5), (2.0, 12.0, 1.6))  # leg bracing
        pb.box((x, y, height - 1.0), (4.0, 15.0, 2.0))  # leg head
    span = x_right - x_left
    pb.box(((x_left + x_right) / 2, y, height + 4.5), (span + 14.0, 11.0, 9.0))  # main girder
    pb.box((trolley_x, y, height + 11.5), (16.0, 13.0, 5.0))  # trolley
    for dy in (-2.5, 2.5):
        pb.cylinder((trolley_x, y + dy, height - 18.0), 0.35, 36.0, segments=8)  # hoist ropes
    pb.box((trolley_x, y, height - 37.0), (5.0, 7.0, 4.0))  # hook block
    return pb


def _jib_crane(pb: PartBuilder, x: float, y: float) -> PartBuilder:
    """Rail-mounted level-luffing quay crane: portal, slewing tower, cabin, inclined boom toward the sea (+X)."""
    for lx in (x - 10.0, x + 10.0):
        for ly in (y - 6.0, y + 6.0):
            pb.box((lx, ly, 6.0), (1.6, 1.6, 12.0))  # portal legs
    pb.box((x, y, 12.75), (23.0, 15.0, 1.5))  # portal deck
    pb.cylinder((x, y, 22.0), 2.4, 17.0, segments=16)  # slewing tower
    pb.box((x - 3.0, y, 32.5), (12.0, 6.0, 5.0))  # machinery house
    pb.box((x + 3.5, y - 3.6, 31.5), (3.0, 2.2, 3.0))  # operator cabin
    pb.box((x - 10.5, y, 32.0), (4.0, 5.0, 4.0))  # counterweight
    angle, length = 32.0, 46.0
    pivot = Vector((x + 3.0, y, 33.0))
    direction = Vector((math.cos(math.radians(angle)), 0.0, math.sin(math.radians(angle))))
    center = pivot + direction * (length / 2)
    pb.box(tuple(center), (length, 1.8, 1.8), rot_y_deg=-angle)  # boom
    tip = pivot + direction * length
    pb.cylinder((tip.x, y, tip.z / 2 + 4.0), 0.25, tip.z - 8.0, segments=6)  # hoist rope
    pb.box((tip.x, y, 3.0), (2.0, 2.0, 2.0))  # hook block
    return pb


def _ship(
    col: bpy.types.Collection,
    name: str,
    x0: float,
    x1: float,
    y0: float,
    y1: float,
    keel_z: float,
    depth: float,
    bow: str = "Y+",
) -> None:
    """Context ship: parallel-body hull + bow wedge + aft superstructure and funnel (stern at the opposite end)."""
    hull_mat = material("MAT_CTX_SHIP_HULL", (0.55, 0.16, 0.12), roughness=0.6)
    house_mat = material("MAT_CTX_SHIP_HOUSE", (0.92, 0.92, 0.90), roughness=0.6)
    beam, cx = x1 - x0, (x0 + x1) / 2
    bow_len = beam * 0.9
    hull = PartBuilder()
    if bow == "Y+":
        _slab(hull, x0, x1, y0, y1 - bow_len, keel_z, keel_z + depth)
        hull.wedge((cx, y1 - bow_len), beam, bow_len, keel_z, keel_z + depth, "Y+")
        stern_y = y0
    else:
        _slab(hull, x0, x1, y0 + bow_len, y1, keel_z, keel_z + depth)
        hull.wedge((cx, y0 + bow_len), beam, bow_len, keel_z, keel_z + depth, "Y-")
        stern_y = y1
    hull.build(f"CTX_{name}_HULL", hull_mat, col, ctx_opacity=0.35)
    sign = 1.0 if bow == "Y+" else -1.0
    deck = keel_z + depth
    house = PartBuilder()
    house.box((cx, stern_y + sign * 14.0, deck + 9.0), (beam * 0.8, 18.0, 18.0))
    house.box((cx, stern_y + sign * 14.0, deck + 19.0), (beam * 1.0, 10.0, 2.0))  # bridge wings
    house.cylinder((cx, stern_y + sign * 4.0, deck + 12.0), 2.8, 24.0, segments=12)  # funnel
    house.build(f"CTX_{name}_SUPERSTRUCTURE", house_mat, col, ctx_opacity=0.35)


def _flow_line(
    col: bpy.types.Collection,
    node_id: str,
    points: list[tuple[float, float, float]],
    mat: bpy.types.Material,
) -> None:
    """Axis-aligned production-flow line with a chevron arrowhead on every segment."""
    pb = PartBuilder()
    for (ax, ay, az), (bx, by, bz) in zip(points, points[1:]):
        size = (max(abs(bx - ax), 2.0), max(abs(by - ay), 2.0), max(abs(bz - az), 2.0))
        pb.box(((ax + bx) / 2, (ay + by) / 2, (az + bz) / 2), size)
        direction = (bx - ax, by - ay, bz - az)
        mid = ((ax + bx) / 2, (ay + by) / 2, (az + bz) / 2)
        pb.cone(mid, 5.0, 12.0, direction)
    pb.build(node_id, mat, col, ctx_opacity=0.75)


def build_shipyard(col: bpy.types.Collection) -> None:
    ground = material("MAT_CTX_YARD_GROUND", (0.40, 0.42, 0.45), roughness=0.95)
    sea = material("MAT_CTX_SEA", (0.06, 0.30, 0.55), roughness=0.2)
    road = material("MAT_CTX_ROAD", (0.16, 0.17, 0.19), roughness=0.95)
    flow_steel = material("MAT_CTX_FLOW_STEEL", (1.0, 0.50, 0.08), roughness=0.5)
    flow_outfit = material("MAT_CTX_FLOW_OUTFITTING", (0.10, 0.80, 0.90), roughness=0.5)
    ghost_hull = material("MAT_CTX_NB1001_ENVELOPE", (0.70, 0.36, 0.30), roughness=0.6)

    cladding = material("MAT_HALL_CLADDING", (0.70, 0.74, 0.79), metallic=0.4, roughness=0.5)
    paint_hall = material("MAT_PAINT_HALL_CLADDING", (0.60, 0.70, 0.82), metallic=0.3, roughness=0.5)
    office = material("MAT_OFFICE_FACADE", (0.86, 0.86, 0.83), roughness=0.7)
    concrete = material("MAT_CONCRETE_PAVING", (0.62, 0.62, 0.60), roughness=0.9)
    rust = material("MAT_STEEL_STOCK", (0.45, 0.30, 0.22), metallic=0.6, roughness=0.7)
    dock_blue = material("MAT_FLOATING_DOCK", (0.16, 0.28, 0.55), metallic=0.5, roughness=0.5)
    crane_blue = material("MAT_CRANE_BLUE_RAL5005", (0.08, 0.30, 0.70), metallic=0.5, roughness=0.45)
    crane_yellow = material("MAT_CRANE_YELLOW_RAL1003", (0.95, 0.72, 0.08), metallic=0.4, roughness=0.45)
    primer = material("MAT_BLOCK_SHOP_PRIMER", (0.56, 0.22, 0.16), metallic=0.5, roughness=0.6)

    # ---- Context: sea, land platform (with the dry-dock pit left open), roads ----
    _slab(PartBuilder(), -60, 960, -120, 680, SEA_Z - 0.4, SEA_Z).build("CTX_SEA", sea, col, ctx_opacity=0.55)
    land = PartBuilder()
    _slab(land, 0, 140, 0, 560, -8, 0)
    _slab(land, 196, 800, 0, 560, -8, 0)
    _slab(land, 140, 196, 370, 560, -8, 0)
    land.build("CTX_YARD_GROUND", ground, col, ctx_opacity=1.0)
    roads = PartBuilder()
    _slab(roads, 222, 760, 172, 186, 0, 0.08)  # south ring road
    _slab(roads, 206, 222, 0, 560, 0, 0.08)  # west road between docks and shops
    _slab(roads, 222, 760, 422, 436, 0, 0.08)  # road between steel line and assembly halls
    _slab(roads, 745, 760, 30, 560, 0, 0.08)  # quay apron road
    roads.build("CTX_ROADS", road, col, ctx_opacity=1.0)
    laydown = PartBuilder()  # outfitting laydown area + container stacks + pipe racks south of the shops
    _slab(laydown, 440, 740, 30, 105, 0, 0.12)
    for i in range(10):
        for tier in range(1 + i % 3):
            laydown.box((462 + i * 14, 50, 1.45 + tier * 2.6), (2.5, 12.2, 2.6))  # containers
    for i in range(6):
        laydown.box((620 + i * 18, 80, 2.0), (12.0, 6.0, 4.0))  # pipe spool racks
    laydown.build("CTX_LAYDOWN_AREA", road, col, ctx_opacity=0.5)

    # ---- 1 Steel & profile stockyard ------------------------------------------
    a01 = PartBuilder()
    _slab(a01, 230, 400, 440, 540, 0, 0.3)
    for row in range(6):
        for colm in range(8):
            h = 1.2 + ((row * 7 + colm * 3) % 5) * 0.35
            a01.box((242 + colm * 20, 452 + row * 14, 0.3 + h / 2), (14.0, 3.5, h))  # plate stacks
    for colm in range(4):
        a01.box((250 + colm * 40, 535, 1.6), (30.0, 1.2, 2.6))  # profile racks
    a01.build("NODE_A01_STEEL_STOCKYARD", rust, col)

    # ---- 2 General warehouses / 3 customs & bonded area ------------------------
    _hangar(PartBuilder(), 20, 130, 440, 530, 14).build("NODE_A02_GENERAL_WAREHOUSE", cladding, col)
    a03 = _hangar(PartBuilder(), 150, 200, 470, 530, 10)
    _slab(a03, 150, 200, 400, 462, 0, 0.15)
    for i in range(6):
        a03.box((158 + (i % 3) * 16, 412 + (i // 3) * 30, 1.45), (12.2, 2.5, 2.6))  # containers
    a03.build("NODE_A03_CUSTOMS_BONDED_AREA", cladding, col)

    # ---- Steel line: 4 blasting & primer -> 5 CNC -> 6 bending -> 7 panel line ---
    _hangar(PartBuilder(), 420, 525, 470, 500, 12).build("NODE_A04_BLASTING_PRIMER_LINE", cladding, col)
    _hangar(PartBuilder(), 540, 640, 450, 515, 16).build("NODE_A05_CNC_CUTTING_SHOP", cladding, col)
    _hangar(PartBuilder(), 655, 745, 450, 515, 18).build("NODE_A06_BENDING_PRESS_SHOP", cladding, col)
    _hangar(PartBuilder(), 620, 745, 340, 410, 20).build("NODE_A07_PANEL_SUB_ASSEMBLY_LINE", cladding, col)

    # ---- 8 Indoor block assembly hall / 10 block blasting & paint hall ---------
    _hangar(PartBuilder(), 440, 600, 330, 420, 32).build("NODE_A08_BLOCK_ASSEMBLY_HALL", cladding, col)
    _hangar(PartBuilder(), 270, 420, 335, 415, 25).build("NODE_A10_BLOCK_BLASTING_PAINT_HALL", paint_hall, col)

    # ---- 9 Outdoor block joining yard (grand-block assembly) -------------------
    a09 = PartBuilder()
    _slab(a09, 230, 520, 190, 310, 0, 0.25)
    for gx in range(5):
        for gy in range(3):
            if gx == 1 and gy == 1:
                continue  # space occupied by block SS-201
            x, y = 262 + gx * 55, 215 + gy * 38
            for dx in (-7, 7):
                for dy in (-5, 5):
                    a09.box((x + dx, y + dy, 0.95), (1.2, 1.2, 1.4))  # block support stools
    a09.build("NODE_A09_OUTDOOR_BLOCK_JOINING_YARD", concrete, col)

    # ---- Outfitting shops 11-15 -----------------------------------------------
    _hangar(PartBuilder(), 580, 660, 260, 310, 14).build("NODE_A11_PIPE_SHOP", cladding, col)
    _hangar(PartBuilder(), 680, 740, 260, 310, 14).build("NODE_A12_MECHANICAL_MACHINING_SHOP", cladding, col)
    _hangar(PartBuilder(), 580, 640, 195, 240, 12).build("NODE_A13_ELECTRICAL_AUTOMATION_SHOP", cladding, col)
    _hangar(PartBuilder(), 660, 740, 195, 240, 12).build("NODE_A14_CARPENTRY_INSULATION_SHOP", cladding, col)
    _hangar(PartBuilder(), 580, 740, 120, 165, 12).build("NODE_A15_OUTFITTING_LIGHT_STEEL_SHOP", cladding, col)

    # ---- 16 Building berth (slipway) with Goliath crane rails ------------------
    a16 = PartBuilder()
    _slab(a16, 50, 90, -40, 360, SEA_Z, 0.6)  # berth slab, runs into the sea for launching
    for x in (62.0, 78.0):
        a16.box((x, 160, 0.9), (1.5, 400, 0.6))  # sliding ways
    for i in range(37):
        a16.box((70, 42 + i * 6, 1.3), (2.0, 1.5, 1.4))  # keel blocks
    for x in (36.0, 104.0):
        a16.box((x, 180, 0.4), (4.0, 360, 0.8))  # goliath crane rails
    a16.build("NODE_A16_BUILDING_BERTH", concrete, col)

    # ---- 17 Dry dock (pit open to the south) + pump house ----------------------
    a17 = PartBuilder()
    floor_z = -12.0
    _slab(a17, 143, 193, 4, 362, floor_z - 1.0, floor_z)  # dock floor
    _slab(a17, 140, 143, 0, 365, floor_z - 1.0, 0.3)  # west wall
    _slab(a17, 193, 196, 0, 365, floor_z - 1.0, 0.3)  # east wall
    _slab(a17, 140, 196, 362, 365, floor_z - 1.0, 0.3)  # head wall
    _slab(a17, 143, 193, 0, 4, floor_z - 1.0, -1.0)  # caisson gate
    for i in range(20):
        a17.box((168, 40 + i * 12, floor_z + 0.7), (2.0, 1.5, 1.4))  # docking blocks
    _slab(a17, 198, 205, 330, 350, 0, 7)  # pump house
    a17.build("NODE_A17_DRY_DOCK", concrete, col)
    _ship(col, "SHIP_IN_DRY_DOCK", 150, 186, 40, 300, floor_z + 1.4, 18.0, bow="Y+")

    # ---- 18 Floating dock (north-east, in the sea) ------------------------------
    a18 = PartBuilder()
    _slab(a18, 840, 872, 480, 630, -8, -2)  # pontoon
    _slab(a18, 840, 844, 480, 630, -2, 14)  # west wing wall
    _slab(a18, 868, 872, 480, 630, -2, 14)  # east wing wall
    for y in (500, 610):
        for x in (842, 870):
            a18.box((x, y, 18), (3.0, 3.0, 8.0))  # wing-wall crane pedestals
    a18.build("NODE_A18_FLOATING_DOCK", dock_blue, col)
    _ship(col, "SHIP_IN_FLOATING_DOCK", 848, 864, 492, 618, -1.0, 11.0, bow="Y+")

    # ---- 19 Outfitting quay (400 m) --------------------------------------------
    a19 = PartBuilder()
    _slab(a19, 760, 800, 40, 440, -8, 0.6)  # quay deck
    for y in range(50, 440, 20):
        a19.cylinder((797, y, 1.1), 0.5, 1.0, segments=10)  # bollards
        a19.box((800.6, y + 10, -1.5), (1.2, 4.0, 3.0))  # fenders
    for x in (770.0, 790.0):
        a19.box((x, 240, 0.8), (1.0, 400, 0.4))  # crane rails
    a19.build("NODE_A19_OUTFITTING_QUAY", concrete, col)
    _ship(col, "SHIP_AT_QUAY_01", 808, 838, 60, 240, -9.0, 16.0, bow="Y-")
    _ship(col, "SHIP_AT_QUAY_02", 806, 832, 265, 425, -8.0, 14.0, bow="Y+")

    # ---- 20 Management, engineering & support (HSE, canteen, gas/transformer) ---
    a20 = PartBuilder()
    _slab(a20, 240, 330, 40, 95, 0, 16)  # main office block
    _slab(a20, 250, 320, 50, 85, 16, 18)  # roof plant
    _slab(a20, 340, 385, 40, 72, 0, 7)  # canteen / HSE building
    for i in range(3):
        a20.cylinder((400 + i * 8, 52, 7.0), 2.5, 14.0, segments=16)  # O2 / acetylene / CO2 tanks
    _slab(a20, 395, 425, 70, 85, 0, 4)  # transformer substation
    a20.build("NODE_A20_MANAGEMENT_ENGINEERING", office, col)

    # ---- Cranes ------------------------------------------------------------------
    _gantry_crane(PartBuilder(), 36, 104, 140, 85, 70).build("NODE_CRN_GOLIATH_600T", crane_blue, col)
    _gantry_crane(PartBuilder(), 141.5, 194.5, 320, 55, 168).build("NODE_CRN_DRYDOCK_PORTAL_400T", crane_blue, col)
    _jib_crane(PartBuilder(), 780, 150).build("NODE_CRN_QUAY_JIB_50T_01", crane_yellow, col)
    _jib_crane(PartBuilder(), 780, 330).build("NODE_CRN_QUAY_JIB_50T_02", crane_yellow, col)

    # ---- Newbuild NB-1001 on the building berth (stern toward the sea) --------
    keel = 2.0
    hull_x0, hull_x1 = 54.0, 86.0
    envelope = PartBuilder()
    _slab(envelope, hull_x0, hull_x1, 36, 230, keel, keel + 22.0)
    envelope.wedge((70, 230), hull_x1 - hull_x0, 30.0, keel, keel + 22.0, "Y+")
    envelope.build("CTX_NB1001_HULL_ENVELOPE", ghost_hull, col, ctx_opacity=0.12)

    def double_bottom(y0: float, y1: float) -> PartBuilder:
        pb = PartBuilder()
        _slab(pb, hull_x0, hull_x1, y0, y1, keel, keel + 0.3)  # bottom shell
        _slab(pb, hull_x0 + 1, hull_x1 - 1, y0, y1, keel + 2.4, keel + 2.7)  # inner bottom
        for y in [y0 + 0.5 + i * 3.0 for i in range(int((y1 - y0) // 3.0))]:
            pb.box((70, y, keel + 1.35), (hull_x1 - hull_x0 - 2, 0.2, 2.4))  # floors
        for x in (58.0, 64.0, 70.0, 76.0, 82.0):
            pb.box((x, (y0 + y1) / 2, keel + 1.35), (0.2, y1 - y0, 2.4))  # girders
        return pb

    double_bottom(36, 60).build("NODE_NB1001_BLOCK_DB_101", primer, col)
    double_bottom(60, 84).build("NODE_NB1001_BLOCK_DB_102", primer, col)

    er = PartBuilder()  # engine-room block erected on top of DB-101
    base = keel + 2.7
    for x in (hull_x0 + 0.5, hull_x1 - 0.5):
        er.box((x, 48, base + 7.0), (1.0, 24.0, 14.0))  # side shell + frames
    er.box((70, 59.5, base + 7.0), (hull_x1 - hull_x0, 1.0, 14.0))  # forward ER bulkhead
    er.box((70, 48, base + 9.0), (hull_x1 - hull_x0, 24.0, 0.4))  # 2nd deck (partial flat)
    er.box((70, 48, base + 1.0), (8.0, 14.0, 2.0))  # main engine seating
    er.build("NODE_NB1001_BLOCK_ER_301", primer, col)

    ss = PartBuilder()  # side-shell block waiting on the outdoor joining yard
    ss.box((317.0, 253.0, 7.0), (1.0, 30.0, 12.0))  # shell plating
    ss.box((323.0, 253.0, 1.4), (12.0, 30.0, 0.6))  # bottom flat / deck
    for y in [239.0 + i * 3.5 for i in range(9)]:
        ss.box((319.5, y, 7.0), (4.0, 0.3, 12.0))  # web frames
    ss.box((319.5, 253.0, 9.5), (4.0, 30.0, 0.4))  # side stringer
    ss.build("NODE_NB1001_BLOCK_SS_201", primer, col)

    bow = PartBuilder()  # bow block outside the paint hall (coating in progress)
    bow.wedge((262.0, 375.0), 30.0, 26.0, 1.0, 17.0, "X-")
    bow.box((262.5, 375.0, 9.0), (1.0, 30.0, 16.0))  # collision bulkhead
    bow.build("NODE_NB1001_BLOCK_BOW_501", primer, col)

    # ---- Production flow arrows (context) -------------------------------------
    z = 58.0
    _flow_line(
        col,
        "CTX_FLOW_STEEL",
        [(315, 490, z), (700, 490, z), (700, 375, z), (345, 375, z), (345, 250, z), (120, 250, z)],
        flow_steel,
    )
    _flow_line(col, "CTX_FLOW_OUTFITTING_QUAY", [(660, 220, 42), (775, 220, 42)], flow_outfit)
    _flow_line(col, "CTX_FLOW_OUTFITTING_BLOCKS", [(590, 220, 42), (500, 220, 42)], flow_outfit)


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #


def generate(builder, out_path: Path) -> list[str]:
    reset_scene()
    _MATERIAL_CACHE.clear()
    collection = bpy.data.collections.new("TWIN")
    bpy.context.scene.collection.children.link(collection)
    builder(collection)
    nodes = export_glb(out_path)
    print(f"ODT_EXPORTED {out_path} nodes={nodes}")
    return nodes


def main() -> None:
    args = parse_args()
    out_dir: Path = args.output_dir.resolve()
    manifest = {
        "nb42_engine_room.glb": generate(build_engine_room, out_dir / "nb42_engine_room.glb"),
        "villa_b04.glb": generate(build_villa, out_dir / "villa_b04.glb"),
        "demo_shipyard.glb": generate(build_shipyard, out_dir / "demo_shipyard.glb"),
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print("ODT_OK")


if __name__ == "__main__":
    main()
