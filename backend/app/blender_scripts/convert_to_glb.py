"""Headless Blender mesh optimizer: CAD/mesh file -> decimated .glb.

Usage:
    blender --background --factory-startup --python-exit-code 1 \
        --python backend/app/blender_scripts/convert_to_glb.py -- \
        --input <file> --output <file.glb> [--max-faces-per-node 60000] \
        [--merge-distance 0.0001] [--manifest <file.json>]

Supported inputs:
    .glb / .gltf / .obj / .stl / .ply / .fbx  -> imported natively by Blender.
    .step / .stp / .ifc / .ocx                -> Blender has no native B-rep/IFC importer.
        The FastAPI pipeline (app/services/cad_parser.py) tessellates these with
        trimesh+cascadio / ifcopenshell into an intermediate .glb whose node names
        are already the final `mesh_node_id`s, then calls this script on that .glb.
        Passing them here directly exits with code 3 and a clear message.

3D mapping contract:
    Each mesh object's final name == its `mesh_node_id` (taken from the custom
    property `mesh_node_id` if present, else the imported object name with
    Blender's ".001" duplicate suffix stripped). The id is also written into the
    object's custom properties so it is exported as glTF `extras.mesh_node_id`.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import bmesh
import bpy

NATIVE_IMPORTERS = {".glb", ".gltf", ".obj", ".stl", ".ply", ".fbx"}
NEEDS_PRETESSELLATION = {".step", ".stp", ".ifc", ".ocx"}
_DUP_SUFFIX = re.compile(r"\.\d{3}$")


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Convert and decimate a mesh file into .glb")
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--max-faces-per-node", type=int, default=60000)
    parser.add_argument("--merge-distance", type=float, default=0.0001)
    parser.add_argument("--manifest", type=Path, default=None)
    return parser.parse_args(argv)


def import_file(path: Path) -> None:
    ext = path.suffix.lower()
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=str(path))
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=str(path))
    elif ext == ".stl":
        bpy.ops.wm.stl_import(filepath=str(path))
    elif ext == ".ply":
        bpy.ops.wm.ply_import(filepath=str(path))
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=str(path))
    else:
        raise ValueError(f"Unsupported extension for Blender import: {ext}")


def resolve_node_id(obj: bpy.types.Object) -> str:
    explicit = obj.get("mesh_node_id")
    if isinstance(explicit, str) and explicit.strip():
        return explicit.strip()
    return _DUP_SUFFIX.sub("", obj.name)


def clean_mesh(obj: bpy.types.Object, merge_distance: float) -> None:
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=merge_distance)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=merge_distance)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()


def optimize(max_faces: int, merge_distance: float) -> list[dict]:
    report: list[dict] = []
    mesh_objects = [o for o in bpy.context.scene.objects if o.type == "MESH"]

    # Pass 1: free every target name so renames never collide with ".001" copies.
    targets = {obj: resolve_node_id(obj) for obj in mesh_objects}
    for obj in mesh_objects:
        obj.name = f"__odt_tmp_{id(obj)}"

    for obj, node_id in targets.items():
        obj.name = node_id
        if obj.name != node_id:
            raise RuntimeError(f"Duplicate mesh_node_id in scene: {node_id}")
        obj["mesh_node_id"] = node_id
        obj.data.name = node_id

        faces_before = len(obj.data.polygons)
        clean_mesh(obj, merge_distance)
        faces_clean = len(obj.data.polygons)

        ratio = 1.0
        if max_faces > 0 and faces_clean > max_faces:
            ratio = max(0.01, max_faces / faces_clean)
            mod = obj.modifiers.new(name="ODT_DECIMATE", type="DECIMATE")
            mod.decimate_type = "COLLAPSE"
            mod.ratio = ratio
            mod.use_collapse_triangulate = True

        depsgraph = bpy.context.evaluated_depsgraph_get()
        faces_after = len(obj.evaluated_get(depsgraph).data.polygons)
        report.append(
            {
                "mesh_node_id": node_id,
                "faces_before": faces_before,
                "faces_after": faces_after,
                "decimate_ratio": round(ratio, 4),
            }
        )
    return report


def main() -> int:
    args = parse_args()
    src: Path = args.input.resolve()
    dst: Path = args.output.resolve()
    ext = src.suffix.lower()

    if not src.exists():
        print(f"ODT_ERROR input not found: {src}")
        return 2
    if ext in NEEDS_PRETESSELLATION:
        print(
            f"ODT_ERROR {ext} must be tessellated by app/services/cad_parser.py into an "
            "intermediate .glb before Blender optimization."
        )
        return 3
    if ext not in NATIVE_IMPORTERS:
        print(f"ODT_ERROR unsupported input extension: {ext}")
        return 2

    bpy.ops.wm.read_factory_settings(use_empty=True)
    import_file(src)
    report = optimize(args.max_faces_per_node, args.merge_distance)

    dst.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(dst),
        export_format="GLB",
        export_extras=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
        use_selection=False,
    )

    manifest_path = args.manifest or dst.with_suffix(".manifest.json")
    manifest_path.write_text(json.dumps({"output": str(dst), "nodes": report}, indent=2), encoding="utf-8")
    print(f"ODT_OK nodes={len(report)} output={dst}")
    return 0


if __name__ == "__main__":
    code = main()
    if code != 0:
        sys.exit(code)
