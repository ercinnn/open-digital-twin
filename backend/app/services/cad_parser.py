"""CAD / BIM / mesh parsing: extracts the BOM (components) and a named trimesh Scene.

Every returned component has a `mesh_node_id`; the returned `trimesh.Scene`
contains exactly one geometry node per component whose node name equals that id
(3D mapping contract). The scene is converted to glTF's Y-up convention.

Supported formats
    .step/.stp   trimesh + cascadio (OpenCASCADE tessellation)
    .ifc         ifcopenshell geometry iterator + property sets / materials
    .ocx         Open Class 3D Exchange XML (plates / stiffeners / brackets / pillars)
    .obj/.stl/.ply/.glb/.gltf   trimesh
"""

from __future__ import annotations

import math
import multiprocessing
import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable

import numpy as np
import trimesh

SUPPORTED_EXTENSIONS = {".step", ".stp", ".ifc", ".ocx", ".obj", ".stl", ".ply", ".glb", ".gltf"}
_Z_UP_FORMATS = {".step", ".stp", ".ifc", ".ocx", ".stl", ".ply"}
MAX_NODE_ID_LENGTH = 60  # Blender object names are limited to 63 bytes.

# kg/m3, matched by lowercase keyword in the material name (first match wins).
MATERIAL_DENSITIES: list[tuple[str, float]] = [
    ("stainless", 8000.0),
    ("bronze", 7600.0),
    ("brass", 8500.0),
    ("copper", 8960.0),
    ("cast iron", 7200.0),
    ("aluminium", 2700.0),
    ("aluminum", 2700.0),
    ("titanium", 4500.0),
    ("ah36", 7850.0),
    ("dh36", 7850.0),
    ("s355", 7850.0),
    ("s235", 7850.0),
    ("steel", 7850.0),
    ("concrete", 2400.0),
    ("brick", 1900.0),
    ("glass", 2500.0),
    ("timber", 500.0),
    ("wood", 600.0),
    ("pvc", 1400.0),
    ("pe-rt", 940.0),
    ("pe-x", 940.0),
    ("hdpe", 950.0),
    ("gypsum", 1000.0),
    ("insulation", 40.0),
]

DOMAIN_DEFAULT_MATERIAL = {
    "marine": "Shipbuilding Steel AH36",
    "construction": "Concrete C30/37",
}

_CATEGORY_KEYWORDS: list[tuple[tuple[str, ...], str]] = [
    (("engine", "diesel", "gearbox", "propeller", "shaft", "thruster"), "propulsion"),
    (("pump", "cooler", "cooling", "heat_exchanger", "exchanger"), "cooling_system"),
    (("purifier", "separator", "fuel", "bunker"), "fuel_system"),
    (("hull", "block", "plate", "stiffener", "bracket", "frame", "girder", "bulkhead", "deck", "longitudinal"), "hull_structure"),
    (("column", "beam", "slab", "wall", "footing", "foundation", "pile", "stair", "roof"), "structural"),
    (("pipe", "valve", "fitting", "drain", "sanitary", "tap", "boiler"), "plumbing"),
    (("heat_pump", "hvac", "duct", "fan", "chiller", "ahu", "air"), "hvac"),
    (("cable", "panel", "switch", "light", "transformer", "generator"), "electrical"),
]

_IFC_CLASS_CATEGORY = {
    "IfcColumn": "structural",
    "IfcBeam": "structural",
    "IfcSlab": "structural",
    "IfcWall": "structural",
    "IfcWallStandardCase": "structural",
    "IfcFooting": "structural",
    "IfcPile": "structural",
    "IfcMember": "structural",
    "IfcPlate": "structural",
    "IfcStair": "structural",
    "IfcRoof": "structural",
    "IfcPipeSegment": "plumbing",
    "IfcPipeFitting": "plumbing",
    "IfcValve": "plumbing",
    "IfcSanitaryTerminal": "plumbing",
    "IfcFlowSegment": "plumbing",
    "IfcFlowFitting": "plumbing",
    "IfcUnitaryEquipment": "hvac",
    "IfcDuctSegment": "hvac",
    "IfcDuctFitting": "hvac",
    "IfcAirTerminal": "hvac",
    "IfcFan": "hvac",
    "IfcPump": "cooling_system",
    "IfcBoiler": "plumbing",
    "IfcCableSegment": "electrical",
    "IfcElectricDistributionBoard": "electrical",
    "IfcLightFixture": "electrical",
}


class CadParseError(ValueError):
    pass


@dataclass
class ParsedComponent:
    mesh_node_id: str
    name: str
    category: str | None
    material: str | None
    volume_m3: float | None
    weight_kg: float | None
    metadata: dict[str, Any] = field(default_factory=dict)

    def to_row(self, project_id: str) -> dict[str, Any]:
        return {
            "project_id": project_id,
            "mesh_node_id": self.mesh_node_id,
            "name": self.name,
            "category": self.category,
            "material": self.material,
            "volume_m3": None if self.volume_m3 is None else round(self.volume_m3, 6),
            "weight_kg": None if self.weight_kg is None else round(self.weight_kg, 3),
            "metadata": self.metadata,
        }


@dataclass
class ParseResult:
    components: list[ParsedComponent]
    scene: trimesh.Scene
    source_format: str
    unit_scale: float
    warnings: list[str] = field(default_factory=list)


# --------------------------------------------------------------------------- #
# Generic helpers
# --------------------------------------------------------------------------- #


def sanitize_node_id(raw: str, used: set[str]) -> str:
    """Deterministic, unique, glTF/Three.js/Blender-safe node id (`NODE_<UPPER_SNAKE>`)."""
    base = re.sub(r"[^A-Za-z0-9]+", "_", raw or "").strip("_").upper() or "PART"
    if not base.startswith("NODE_"):
        base = f"NODE_{base}"
    base = base[:MAX_NODE_ID_LENGTH].rstrip("_")
    candidate, index = base, 2
    while candidate in used:
        suffix = f"_{index:02d}"
        candidate = f"{base[: MAX_NODE_ID_LENGTH - len(suffix)]}{suffix}"
        index += 1
    used.add(candidate)
    return candidate


def humanize(raw: str) -> str:
    text = re.sub(r"^NODE_", "", raw or "", flags=re.IGNORECASE)
    text = re.sub(r"[_\-]+", " ", text).strip()
    return text.title() if text.isupper() or text.islower() else text or "Part"


def density_for(material: str | None) -> float | None:
    if not material:
        return None
    lowered = material.lower()
    for keyword, density in MATERIAL_DENSITIES:
        if keyword in lowered:
            return density
    return None


def guess_category(name: str) -> str:
    token = re.sub(r"[^a-z0-9]+", "_", name.lower())
    for keywords, category in _CATEGORY_KEYWORDS:
        if any(k in token for k in keywords):
            return category
    return "part"


def mesh_volume(mesh: trimesh.Trimesh) -> tuple[float | None, str]:
    """Volume of closed bodies in m3 (sum over watertight connected bodies)."""
    work = mesh.copy()
    work.merge_vertices()
    if work.is_volume:
        return abs(float(work.volume)), "closed_mesh"
    bodies = work.split(only_watertight=False)
    closed = [b for b in bodies if b.is_volume]
    if closed and len(closed) == len(bodies):
        return float(sum(abs(b.volume) for b in closed)), "sum_of_closed_bodies"
    if closed:
        return float(sum(abs(b.volume) for b in closed)), "partial_closed_bodies"
    return None, "open_surface"


def infer_unit_scale(meshes: Iterable[trimesh.Trimesh], fmt: str) -> float:
    """Heuristic: CAD exchange files are usually millimetres; scenes > 500 units => mm."""
    extents = [float(np.max(m.extents)) for m in meshes if len(m.vertices)]
    if not extents:
        return 1.0
    largest = max(extents)
    if fmt in (".step", ".stp", ".stl", ".obj", ".ply") and largest > 500.0:
        return 0.001
    return 1.0


def z_up_to_y_up() -> np.ndarray:
    return trimesh.transformations.rotation_matrix(-math.pi / 2.0, [1.0, 0.0, 0.0])


def finalize_component(
    node_id: str,
    name: str,
    mesh: trimesh.Trimesh,
    material: str | None,
    category: str | None,
    metadata: dict[str, Any],
    domain_type: str,
    known_volume: float | None = None,
    known_weight: float | None = None,
) -> ParsedComponent:
    metadata = dict(metadata)
    volume, method = (known_volume, "source_quantity") if known_volume is not None else mesh_volume(mesh)
    metadata["volume_method"] = method
    mat = material
    if not mat:
        mat = DOMAIN_DEFAULT_MATERIAL.get(domain_type)
        if mat:
            metadata["material_source"] = "domain_default"
    weight = known_weight
    if weight is None and volume is not None:
        density = density_for(mat)
        if density:
            weight = volume * density
            metadata["density_kg_m3"] = density
    bounds = mesh.bounds
    metadata["bbox_m"] = [round(float(v), 4) for v in (bounds[1] - bounds[0])]
    metadata["face_count"] = int(len(mesh.faces))
    metadata["surface_area_m2"] = round(float(mesh.area), 4)
    return ParsedComponent(
        mesh_node_id=node_id,
        name=name,
        category=category,
        material=mat,
        volume_m3=volume,
        weight_kg=weight,
        metadata=metadata,
    )


def _build_scene(items: list[tuple[str, trimesh.Trimesh]]) -> trimesh.Scene:
    scene = trimesh.Scene()
    for node_id, mesh in items:
        mesh.metadata["name"] = node_id
        scene.add_geometry(mesh, node_name=node_id, geom_name=node_id)
    return scene


# --------------------------------------------------------------------------- #
# Mesh formats (STEP via cascadio, OBJ/STL/PLY/GLB/GLTF)
# --------------------------------------------------------------------------- #


def _iter_scene_meshes(scene: trimesh.Scene) -> Iterable[tuple[str, trimesh.Trimesh]]:
    for node in scene.graph.nodes_geometry:
        transform, geom_name = scene.graph[node]
        geom = scene.geometry.get(geom_name)
        if not isinstance(geom, trimesh.Trimesh) or len(geom.faces) == 0:
            continue
        mesh = geom.copy()
        mesh.apply_transform(transform)
        label = node if node and node != geom_name and not str(node).startswith(geom_name + "_") else geom_name
        yield str(label or node), mesh


def parse_mesh_file(path: Path, domain_type: str, unit_scale: float | None) -> ParseResult:
    ext = path.suffix.lower()
    # OBJ: keep every `o`/`g` entry as its own node (trimesh merges them by default).
    load_kwargs: dict[str, Any] = {"split_objects": True, "split_groups": True} if ext == ".obj" else {}
    try:
        loaded = trimesh.load(str(path), force="scene", **load_kwargs)
    except Exception as exc:  # trimesh raises many exception types per loader
        raise CadParseError(f"Failed to load {ext} file: {exc}") from exc

    raw_items = list(_iter_scene_meshes(loaded))
    if not raw_items:
        raise CadParseError(f"No triangulated geometry found in {path.name}")

    scale = unit_scale if unit_scale else infer_unit_scale((m for _, m in raw_items), ext)
    rotate = z_up_to_y_up() if ext in _Z_UP_FORMATS else None

    used: set[str] = set()
    components: list[ParsedComponent] = []
    scene_items: list[tuple[str, trimesh.Trimesh]] = []
    for label, mesh in raw_items:
        if scale != 1.0:
            mesh.apply_scale(scale)
        if rotate is not None:
            mesh.apply_transform(rotate)
        node_id = sanitize_node_id(label, used)
        material_name = None
        visual_material = getattr(getattr(mesh, "visual", None), "material", None)
        if visual_material is not None and getattr(visual_material, "name", None):
            material_name = str(visual_material.name)
        components.append(
            finalize_component(
                node_id=node_id,
                name=humanize(label),
                mesh=mesh,
                material=material_name,
                category=guess_category(label),
                metadata={"source_format": ext.lstrip("."), "source_node": label},
                domain_type=domain_type,
            )
        )
        scene_items.append((node_id, mesh))

    return ParseResult(
        components=components,
        scene=_build_scene(scene_items),
        source_format=ext.lstrip("."),
        unit_scale=scale,
    )


# --------------------------------------------------------------------------- #
# IFC (ifcopenshell)
# --------------------------------------------------------------------------- #


def _ifc_material_name(element: Any) -> str | None:
    import ifcopenshell.util.element as uel

    mat = uel.get_material(element, should_skip_usage=True)
    if mat is None:
        return None
    if mat.is_a("IfcMaterial"):
        return mat.Name
    for attr, child in (
        ("MaterialLayers", "Material"),
        ("MaterialConstituents", "Material"),
        ("MaterialProfiles", "Material"),
    ):
        items = getattr(mat, attr, None)
        if items:
            names = [getattr(getattr(i, child, None), "Name", None) for i in items]
            names = [n for n in names if n]
            if names:
                return " / ".join(dict.fromkeys(names))
    if mat.is_a("IfcMaterialList"):
        names = [m.Name for m in mat.Materials if m.Name]
        return " / ".join(names) if names else None
    return getattr(mat, "Name", None)


def _jsonable(value: Any) -> Any:
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    if isinstance(value, (list, tuple)):
        return [_jsonable(v) for v in value]
    if isinstance(value, dict):
        return {str(k): _jsonable(v) for k, v in value.items()}
    return str(value)


def parse_ifc(path: Path, domain_type: str) -> ParseResult:
    try:
        import ifcopenshell
        import ifcopenshell.geom
        import ifcopenshell.util.element as uel
    except ImportError as exc:
        raise CadParseError(f"ifcopenshell is not available: {exc}") from exc

    try:
        model = ifcopenshell.open(str(path))
    except Exception as exc:
        raise CadParseError(f"Failed to open IFC: {exc}") from exc

    settings = ifcopenshell.geom.settings()
    settings.set("use-world-coords", True)
    iterator = ifcopenshell.geom.iterator(settings, model, max(1, multiprocessing.cpu_count() - 1))

    used: set[str] = set()
    components: list[ParsedComponent] = []
    scene_items: list[tuple[str, trimesh.Trimesh]] = []
    warnings: list[str] = []
    rotate = z_up_to_y_up()

    if not iterator.initialize():
        raise CadParseError("IFC file contains no product geometry")

    while True:
        shape = iterator.get()
        element = model.by_id(shape.id)
        verts = np.asarray(shape.geometry.verts, dtype=np.float64).reshape(-1, 3)
        faces = np.asarray(shape.geometry.faces, dtype=np.int64).reshape(-1, 3)
        if len(faces) and element is not None and not element.is_a("IfcOpeningElement"):
            mesh = trimesh.Trimesh(vertices=verts, faces=faces, process=True)
            mesh.apply_transform(rotate)
            ifc_class = element.is_a()
            label = f"{ifc_class[3:]}_{element.Name or element.GlobalId}"
            node_id = sanitize_node_id(label, used)

            psets = uel.get_psets(element)
            known_volume = known_weight = None
            for pset_name, props in psets.items():
                if not pset_name.startswith("Qto_"):
                    continue
                known_volume = known_volume or props.get("NetVolume") or props.get("GrossVolume")
                known_weight = known_weight or props.get("NetWeight") or props.get("GrossWeight")
            container = uel.get_container(element)
            metadata = {
                "source_format": "ifc",
                "ifc_class": ifc_class,
                "global_id": element.GlobalId,
                "tag": getattr(element, "Tag", None),
                "object_type": getattr(element, "ObjectType", None),
                "storey": getattr(container, "Name", None) if container else None,
                "property_sets": _jsonable({k: {pk: pv for pk, pv in v.items() if pk != "id"} for k, v in psets.items()}),
            }
            components.append(
                finalize_component(
                    node_id=node_id,
                    name=element.Name or f"{ifc_class[3:]} {element.GlobalId}",
                    mesh=mesh,
                    material=_ifc_material_name(element),
                    category=_IFC_CLASS_CATEGORY.get(ifc_class, guess_category(label)),
                    metadata=metadata,
                    domain_type=domain_type,
                    known_volume=float(known_volume) if known_volume else None,
                    known_weight=float(known_weight) if known_weight else None,
                )
            )
            scene_items.append((node_id, mesh))
        if not iterator.next():
            break

    if not components:
        raise CadParseError("IFC file produced no tessellated products")
    return ParseResult(components, _build_scene(scene_items), "ifc", 1.0, warnings)


# --------------------------------------------------------------------------- #
# OCX (Open Class 3D Exchange, XML)
# --------------------------------------------------------------------------- #

_OCX_PART_TAGS = {"Plate", "Stiffener", "Bracket", "Pillar", "Edgereinforcement", "Seam"}
_OCX_UNIT_SCALE = {"Umm": 0.001, "Ucm": 0.01, "Um": 1.0, "mm": 0.001, "m": 1.0}


def _local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _attr(el: ET.Element, name: str) -> str | None:
    for key, value in el.attrib.items():
        if _local(key) == name:
            return value
    return None


def _numeric(el: ET.Element | None) -> float | None:
    if el is None:
        return None
    raw = _attr(el, "numericvalue")
    if raw is None:
        return None
    scale = _OCX_UNIT_SCALE.get(_attr(el, "unit") or "Um", 1.0)
    return float(raw) * scale


def _child(el: ET.Element, name: str) -> ET.Element | None:
    for c in el:
        if _local(c.tag) == name:
            return c
    return None


def _ocx_points(el: ET.Element) -> list[tuple[float, float, float]]:
    pts: list[tuple[float, float, float]] = []
    for node in el.iter():
        tag = _local(node.tag)
        if tag in ("Point3D", "StartPoint", "EndPoint", "IntermediatePoint", "CenterPoint", "Origin"):
            x, y, z = (_numeric(_child(node, a)) for a in ("X", "Y", "Z"))
            if x is not None and y is not None and z is not None:
                pts.append((x, y, z))
            coords = _child(node, "Coordinates")
            if coords is not None and coords.text:
                vals = [float(v) for v in coords.text.split()]
                scale = _OCX_UNIT_SCALE.get(_attr(coords, "unit") or "Umm", 0.001)
                pts.extend(
                    (vals[i] * scale, vals[i + 1] * scale, vals[i + 2] * scale) for i in range(0, len(vals) - 2, 3)
                )
    return pts


def _ocx_solid(points: list[tuple[float, float, float]], thickness: float) -> tuple[trimesh.Trimesh, str]:
    arr = np.unique(np.round(np.asarray(points, dtype=np.float64), 6), axis=0)
    if len(arr) == 0:
        raise CadParseError("OCX element without coordinates")
    centered = arr - arr.mean(axis=0)
    _, singular, vt = np.linalg.svd(centered, full_matrices=False)
    tol = 1e-6 * max(1.0, float(singular[0]) if len(singular) else 1.0)
    rank = int(np.sum(singular > tol))
    if rank >= 3 and len(arr) >= 4:
        return trimesh.convex.convex_hull(arr), "convex_hull"
    if rank == 2:
        normal = vt[2] if vt.shape[0] > 2 else np.cross(vt[0], vt[1])
        normal = normal / np.linalg.norm(normal)
        offset = normal * (thickness / 2.0)
        return trimesh.convex.convex_hull(np.vstack([arr - offset, arr + offset])), "extruded_contour_hull"
    # Linear member (stiffener trace / pillar): box along the line.
    start, end = arr.min(axis=0), arr.max(axis=0)
    if len(arr) >= 2:
        direction = vt[0]
        proj = centered @ direction
        start = arr.mean(axis=0) + direction * proj.min()
        end = arr.mean(axis=0) + direction * proj.max()
    length = float(np.linalg.norm(end - start)) or thickness
    section = max(thickness, 0.15)
    box = trimesh.creation.box(extents=(length, section, section))
    axis = (end - start) / length if length else np.array([1.0, 0.0, 0.0])
    box.apply_transform(trimesh.geometry.align_vectors([1.0, 0.0, 0.0], axis))
    box.apply_translation((start + end) / 2.0)
    return box, "linear_member_box"


def parse_ocx(path: Path, domain_type: str) -> ParseResult:
    try:
        root = ET.parse(str(path)).getroot()
    except ET.ParseError as exc:
        raise CadParseError(f"Invalid OCX XML: {exc}") from exc

    materials: dict[str, dict[str, Any]] = {}
    for el in root.iter():
        if _local(el.tag) == "Material":
            mid = _attr(el, "id") or _attr(el, "GUIDRef")
            if mid:
                density = _numeric(_child(el, "Density"))
                # OCX densities are usually t/m3 (Ut_m3): numeric already scaled by 1 -> convert.
                dens_el = _child(el, "Density")
                if density is not None and dens_el is not None and (_attr(dens_el, "unit") or "").lower() in ("ut_m3",):
                    density *= 1000.0
                materials[mid] = {"name": _attr(el, "name") or mid, "density": density}

    used: set[str] = set()
    components: list[ParsedComponent] = []
    scene_items: list[tuple[str, trimesh.Trimesh]] = []
    warnings: list[str] = []
    rotate = z_up_to_y_up()

    parent_panel: dict[ET.Element, str] = {}
    for panel in root.iter():
        if _local(panel.tag) == "Panel":
            pname = _attr(panel, "name") or _attr(panel, "id") or "panel"
            for desc in panel.iter():
                parent_panel[desc] = pname

    for el in root.iter():
        tag = _local(el.tag)
        if tag not in _OCX_PART_TAGS:
            continue
        ident = _attr(el, "id") or _attr(el, "GUIDRef") or f"{tag}_{len(components) + 1}"
        label = _attr(el, "name") or ident
        thickness = 0.01
        material_ref = None
        for sub in el.iter():
            sub_tag = _local(sub.tag)
            if sub_tag in ("PlateMaterial", "Material") and sub is not el:
                material_ref = material_ref or _attr(sub, "materialRef") or _attr(sub, "localRef")
                t = _numeric(_child(sub, "Thickness"))
                if t:
                    thickness = t
            elif sub_tag == "Thickness" and _numeric(sub):
                thickness = _numeric(sub) or thickness
        points = _ocx_points(el)
        if not points:
            warnings.append(f"OCX {tag} '{label}' has no coordinates; skipped")
            continue
        mesh, method = _ocx_solid(points, thickness)
        mesh.apply_transform(rotate)
        mat = materials.get(material_ref or "", {})
        volume = float(abs(mesh.volume)) if mesh.is_volume else None
        weight = volume * mat["density"] if (volume is not None and mat.get("density")) else None
        node_id = sanitize_node_id(f"{tag}_{label}", used)
        components.append(
            finalize_component(
                node_id=node_id,
                name=label,
                mesh=mesh,
                material=mat.get("name"),
                category="hull_structure",
                metadata={
                    "source_format": "ocx",
                    "ocx_type": tag,
                    "ocx_id": ident,
                    "panel": parent_panel.get(el),
                    "thickness_m": round(thickness, 5),
                    "geometry_method": method,
                },
                domain_type=domain_type,
                known_volume=volume,
                known_weight=weight,
            )
        )
        scene_items.append((node_id, mesh))

    if not components:
        raise CadParseError("OCX file contains no structural parts with coordinates")
    return ParseResult(components, _build_scene(scene_items), "ocx", 1.0, warnings)


# --------------------------------------------------------------------------- #
# Entry point
# --------------------------------------------------------------------------- #


def parse_cad_file(path: Path, domain_type: str = "marine", unit_scale: float | None = None) -> ParseResult:
    ext = path.suffix.lower()
    if ext not in SUPPORTED_EXTENSIONS:
        raise CadParseError(f"Unsupported file type '{ext}'. Supported: {sorted(SUPPORTED_EXTENSIONS)}")
    if ext == ".ifc":
        return parse_ifc(path, domain_type)
    if ext == ".ocx":
        return parse_ocx(path, domain_type)
    return parse_mesh_file(path, domain_type, unit_scale)
