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

    def box(self, center: tuple[float, float, float], size: tuple[float, float, float]) -> "PartBuilder":
        mat = Matrix.Translation(Vector(center)) @ Matrix.Diagonal((*size, 1.0))
        bmesh.ops.create_cube(self.bm, size=1.0, matrix=mat)
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

    def build(self, node_id: str, mat: bpy.types.Material, collection: bpy.types.Collection) -> bpy.types.Object:
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        mesh = bpy.data.meshes.new(node_id)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for poly in mesh.polygons:
            poly.use_smooth = False
        mesh.materials.append(mat)
        obj = bpy.data.objects.new(node_id, mesh)
        obj["mesh_node_id"] = node_id
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
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print("ODT_OK")


if __name__ == "__main__":
    main()
