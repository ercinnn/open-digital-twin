import 'dart:math' as math;

import '../../../digital_twin/domain/entities/twin_entities.dart';
import '../entities/block_entities.dart';
import '../entities/production_entities.dart';

/// A 2D point: (v, h) of a cross-section or (u, v) of a plan outline.
typedef P2 = (double, double);

/// Hull coordinates: `u` along the hull from the aft end (0) to the stem (L),
/// `v` across (+ starboard, - port), `h` up from the keel. The viewer maps them to
/// world coordinates with the hull origin `o` (stern, centreline, keel):
/// `x = o.x + v`, `y = o.y + h`, `z = o.z - u` (bow toward -Z, like the berth).
sealed class ShapePart {
  const ShapePart();
  Map<String, dynamic> toJson();
}

List<List<double>> _pts(List<P2> points) => [
  for (final p in points) [_r(p.$1), _r(p.$2)],
];

double _r(double v) => (v * 1000).roundToDouble() / 1000;

/// Cross-section polygon in (v, h), extruded along the hull from [u0] to [u1].
class SectionPart extends ShapePart {
  const SectionPart(this.points, this.u0, this.u1, {this.holes = const []});

  final List<P2> points;
  final List<List<P2>> holes;
  final double u0;
  final double u1;

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'section',
    'pts': _pts(points),
    if (holes.isNotEmpty) 'holes': [for (final h in holes) _pts(h)],
    'u0': _r(u0),
    'u1': _r(u1),
  };
}

/// Plan outline in (u, v), extruded upward from [h0] to [h1].
class PlanPart extends ShapePart {
  const PlanPart(this.points, this.h0, this.h1, {this.holes = const []});

  final List<P2> points;
  final List<List<P2>> holes;
  final double h0;
  final double h1;

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'plan',
    'pts': _pts(points),
    if (holes.isNotEmpty) 'holes': [for (final h in holes) _pts(h)],
    'h0': _r(h0),
    'h1': _r(h1),
  };
}

/// Vertical cylinder (funnel, mast) at (u, v) from [h0] to [h1].
class VerticalCylinderPart extends ShapePart {
  const VerticalCylinderPart(this.u, this.v, this.h0, this.h1, this.radiusBottom, [double? radiusTop])
    : radiusTop = radiusTop ?? radiusBottom;

  final double u;
  final double v;
  final double h0;
  final double h1;
  final double radiusBottom;
  final double radiusTop;

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'cyl',
    'axis': 'h',
    'u': _r(u),
    'v': _r(v),
    'h0': _r(h0),
    'h1': _r(h1),
    'r0': _r(radiusBottom),
    'r1': _r(radiusTop),
  };
}

/// Transverse cylinder (bow thruster tunnel) at (u, h) from [v0] to [v1].
class TransverseCylinderPart extends ShapePart {
  const TransverseCylinderPart(this.u, this.h, this.v0, this.v1, this.radius);

  final double u;
  final double h;
  final double v0;
  final double v1;
  final double radius;

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'cyl',
    'axis': 'v',
    'u': _r(u),
    'h': _r(h),
    'v0': _r(v0),
    'v1': _r(v1),
    'r0': _r(radius),
    'r1': _r(radius),
  };
}

/// One viewer node built in the app (no GLB mesh): a block (pickable, status
/// colored) or context geometry (`CTX_*`, ghosted, [contextOpacity] set).
class ProceduralNode {
  const ProceduralNode({
    required this.meshNodeId,
    required this.origin,
    required this.color,
    required this.parts,
    this.contextOpacity,
  });

  final String meshNodeId;

  /// World position of the hull origin (stern, centreline, keel).
  final (double, double, double) origin;
  final String color;
  final List<ShapePart> parts;
  final double? contextOpacity;

  Map<String, dynamic> toJson() => {
    'id': meshNodeId,
    'origin': [_r(origin.$1), _r(origin.$2), _r(origin.$3)],
    'color': color,
    if (contextOpacity != null) 'ctx_opacity': contextOpacity,
    'parts': [for (final p in parts) p.toJson()],
  };
}

/// Where hulls are erected in the demo yard GLB (`generate_sample_models.py`):
/// world x of the centreline, keel height (top of the keel / docking blocks),
/// world z of the first stern position and the landward limit (bow toward -Z).
class HullSite {
  const HullSite(
    this.areaNodeId, {
    required this.x,
    required this.keelY,
    required this.firstSternZ,
    required this.endZ,
  });

  final String areaNodeId;
  final double x;
  final double keelY;
  final double firstSternZ;
  final double endZ;
}

/// Building berth: slab x 50..90, Blender y -40..410 (z = -y), keel blocks from y 42.
const buildingBerth = HullSite('NODE_A16_BUILDING_BERTH', x: 70, keelY: 2.0, firstSternZ: -36, endZ: -400);

/// Dry dock: floor x 143..193, Blender y 4..362, docking blocks (top -10.6) from y 40.
const dryDock = HullSite('NODE_A17_DRY_DOCK', x: 168, keelY: -10.6, firstSternZ: -34, endZ: -360);

const _primer = '#9a4a32';
const _superstructure = '#dfe4ea';
const _funnel = '#c2410c';
const _envelope = '#cbd5e1';

/// Main dimensions and derived proportions of a hull used to shape its blocks.
class HullShape {
  HullShape({required this.length, required this.beam, required this.depth, required Set<String> types})
    : hasBilge = types.contains('BLG'),
      hasWingTank = types.contains('WT'),
      hasHopper = types.contains('HPT'),
      hasTopside = types.contains('TST'),
      hasStern = types.contains('SKG') || types.contains('STF'),
      hasPoop = types.contains('PP'),
      hasForecastle = types.contains('FC');

  /// Dimensions from the hull row; depth from `metadata.depth_m` or estimated.
  factory HullShape.of(Hull hull, Set<String> types) {
    final length = (hull.lengthM ?? 0) > 10 ? hull.lengthM! : 160.0;
    final beam = (hull.beamM ?? 0) > 2 ? hull.beamM! : length / 6.2;
    final depthValue = hull.metadata['depth_m'];
    final depth = depthValue is num && depthValue > 1
        ? depthValue.toDouble()
        : math.max(beam * 0.62, length / 14).clamp(2.5, 40.0).toDouble();
    return HullShape(length: length, beam: beam, depth: depth, types: types);
  }

  final double length;
  final double beam;
  final double depth;
  final bool hasBilge;
  final bool hasWingTank;
  final bool hasHopper;
  final bool hasTopside;
  final bool hasStern;
  final bool hasPoop;
  final bool hasForecastle;

  double get half => beam / 2;
  double get aftEnd => length * 0.08;
  double get erEnd => length * 0.23;
  double get foreStart => length * 0.87;
  double get foreLength => length - foreStart;

  /// Double bottom height.
  double get hdb => (depth * 0.15).clamp(0.9, 2.2).toDouble();
  double get erBottom => hdb * 1.3;

  /// Bilge chamfer at the bottom corners.
  double get chamfer => math.min(hdb * 0.9, half * 0.2);
  double get bilgeWidth => (beam * 0.13).clamp(1.0, 3.5).toDouble();
  double get shellBand => (beam * 0.05).clamp(0.5, 1.6).toDouble();
  double get wingTankWidth => hasWingTank ? (beam * 0.09).clamp(0.8, 2.4).toDouble() : 0;

  /// Inner edge of the side structure (shell band + wing tank).
  double get sideInner => half - shellBand - wingTankWidth;
  double get hopperWidth => (beam * 0.17).clamp(1.0, 6.0).toDouble();
  double get hopperHeight => depth * 0.22;
  double get topsideWidth => (beam * 0.18).clamp(1.0, 6.0).toDouble();
  double get topsideHeight => depth * 0.2;
  double get deckPlate => 0.5;
  double get coamingHeight => (depth * 0.16).clamp(1.0, 2.0).toDouble();
  double get hatchHalf => math.max(1.0, sideInner - (hasTopside ? topsideWidth : beam * 0.08));
  double get raisedDeck => 2.6;
  double get tier => 2.8;

  /// Cut-up of the aft body above the skeg / stern frame.
  double get cutUp => depth * 0.28;
  double get transomHalf => half * 0.72;

  /// Extra length of a bulbous bow beyond the stem.
  double get bulbOverhang => math.min(length * 0.04, 4.0);

  List<P2> get sternPlan => [(0, -transomHalf), (aftEnd, -half), (aftEnd, half), (0, transomHalf)];

  List<P2> get bowPlan {
    final fs = foreStart, f = foreLength;
    return [
      (fs, -half),
      (fs + 0.3 * f, -half * 0.98),
      (fs + 0.6 * f, -half * 0.8),
      (fs + 0.85 * f, -half * 0.45),
      (length, 0),
      (fs + 0.85 * f, half * 0.45),
      (fs + 0.6 * f, half * 0.8),
      (fs + 0.3 * f, half * 0.98),
      (fs, half),
    ];
  }

  /// Plan outline of the whole hull (stern, parallel body, bow).
  List<P2> get outline => [(0, -transomHalf), (aftEnd, -half), ...bowPlan, (aftEnd, half), (0, transomHalf)];

  /// Hold cross-section between the hopper and topside tanks (bulkheads).
  List<P2> holdSection() {
    final w = sideInner;
    final top = depth - deckPlate;
    final right = <P2>[
      if (hasHopper) ...[(w - hopperWidth, hdb), (w, hdb + hopperHeight)] else (w, hdb),
      if (hasTopside) ...[
        (w, depth - topsideHeight),
        (w - topsideWidth * (1 - deckPlate / topsideHeight), top),
      ] else
        (w, top),
    ];
    return [...right, for (final p in right.reversed) (-p.$1, p.$2)];
  }
}

/// Builds the 3D shapes of the hull blocks entered in the app (Production
/// "Blocks"), so the viewer can show them without a Blender model. Each block is
/// placed at its erected position from its type, side and number: blocks of one
/// type (and side) split the type's hull region along the length in block number
/// order (`DB-101` aft ... `DB-105` forward).
class HullBlockGeometry {
  const HullBlockGeometry._();

  /// Gap between neighbouring blocks along the hull (seams stay visible).
  static const seam = 0.06;

  /// Blocks of every hull (with at least one block) at its site, in tandem when a
  /// site hosts several hulls. Hulls whose location is the dry dock go there, all
  /// others on the building berth. Mesh ids already in the GLB are skipped by the viewer.
  static List<ProceduralNode> build(List<Hull> hulls, List<TwinComponent> components) {
    final nodes = <ProceduralNode>[];
    final nextStern = <HullSite, double>{};
    final sorted = [...hulls]..sort((a, b) => a.hullNo.compareTo(b.hullNo));
    for (final hull in sorted) {
      final blocks = blocksOfHull(components, hull.hullNo);
      if (blocks.isEmpty) continue;
      final site = hull.locationNodeId == dryDock.areaNodeId ? dryDock : buildingBerth;
      final shape = HullShape.of(hull, {for (final b in blocks) b.type?.code ?? 'BLK'});
      final sternZ = nextStern[site] ?? site.firstSternZ;
      nextStern[site] = sternZ - shape.length - shape.bulbOverhang - 12;
      nodes.addAll(hullNodes(hull.hullNo, blocks, shape, (site.x, site.keelY, sternZ)));
    }
    return nodes;
  }

  /// Envelope (context) and block nodes of one hull with the origin [origin].
  static List<ProceduralNode> hullNodes(
    String hullNo,
    List<HullBlock> blocks,
    HullShape shape,
    (double, double, double) origin,
  ) {
    final groups = <String, List<HullBlock>>{};
    for (final b in blocks) {
      final code = b.type?.code ?? 'BLK';
      final key = code == 'BLK' ? code : '$code/${b.side.name}';
      (groups[key] ??= []).add(b);
    }
    for (final list in groups.values) {
      list.sort((a, b) => a.blockNo.compareTo(b.blockNo));
    }
    final counts = {for (final e in groups.entries) e.key.split('/').first: e.value.length};
    final layout = _Layout(shape, counts);
    return [
      ProceduralNode(
        meshNodeId: 'CTX_${hullMeshKey(hullNo)}_HULL_ENVELOPE',
        origin: origin,
        color: _envelope,
        contextOpacity: 0.07,
        parts: [PlanPart(shape.outline, 0, shape.depth)],
      ),
      for (final list in groups.values)
        for (final (i, b) in list.indexed)
          ProceduralNode(
            meshNodeId: b.meshNodeId,
            origin: origin,
            color: _colorOf(b.type?.code),
            parts: layout.parts(b.type?.code ?? 'BLK', b.side, i, list.length),
          ),
    ];
  }

  static String _colorOf(String? code) => switch (code) {
    'FUN' => _funnel,
    'ACC' || 'WH' || 'MST' => _superstructure,
    _ => _primer,
  };
}

/// Part generator for one hull. [counts] = number of blocks per type code (both
/// sides of sided types together), used where blocks of one type stack up.
class _Layout {
  _Layout(this.s, this.counts);

  final HullShape s;
  final Map<String, int> counts;

  int _count(String code) => counts[code] ?? 0;

  /// The [i]-th of [n] equal segments of [a, b]; seams between neighbours, not at the ends.
  (double, double) _split(double a, double b, int i, int n) {
    final len = (b - a) / math.max(n, 1);
    final u0 = a + len * i, u1 = u0 + len;
    final gap = math.min(HullBlockGeometry.seam, len * 0.1);
    return (i > 0 ? u0 + gap : u0, i < n - 1 ? u1 - gap : u1);
  }

  static List<P2> _rect(double x0, double x1, double y0, double y1) => [(x0, y0), (x1, y0), (x1, y1), (x0, y1)];

  /// Mirrors a starboard section polygon to port (v -> -v).
  static List<P2> _side(List<P2> starboard, BlockSide side) =>
      side == BlockSide.port ? [for (final p in starboard) (-p.$1, p.$2)] : starboard;

  /// Sided parts: one part per side, both sides for a centre block of a sided type.
  static List<ShapePart> _sided(BlockSide side, ShapePart Function(BlockSide side) build) =>
      side == BlockSide.centre ? [build(BlockSide.starboard), build(BlockSide.port)] : [build(side)];

  /// Sutherland-Hodgman clip of a plan polygon to u in [a, b].
  static List<P2> clipU(List<P2> poly, double a, double b) {
    List<P2> clip(List<P2> input, bool Function(P2) inside, P2 Function(P2, P2) cut) {
      final out = <P2>[];
      for (var i = 0; i < input.length; i++) {
        final cur = input[i], prev = input[(i + input.length - 1) % input.length];
        final ci = inside(cur), pi = inside(prev);
        if (ci) {
          if (!pi) out.add(cut(prev, cur));
          out.add(cur);
        } else if (pi) {
          out.add(cut(prev, cur));
        }
      }
      return out;
    }

    P2 at(P2 p, P2 q, double u) {
      final t = (u - p.$1) / (q.$1 - p.$1);
      return (u, p.$2 + (q.$2 - p.$2) * t);
    }

    final lower = clip(poly, (p) => p.$1 >= a, (p, q) => at(p, q, a));
    return clip(lower, (p) => p.$1 <= b, (p, q) => at(p, q, b));
  }

  List<ShapePart> parts(String code, BlockSide side, int i, int n) {
    final half = s.half, d = s.depth, hdb = s.hdb, w = s.sideInner;
    final cargo = (s.erEnd, s.foreStart);
    final er = (s.aftEnd, s.erEnd);
    final accEnd = s.erEnd - s.length * 0.01;
    final accLen = accEnd - s.aftEnd;
    final accTop = d + s.tier * _count('ACC');
    final whTop = accTop + s.raisedDeck * _count('WH');
    switch (code) {
      // ---- Bottom
      case 'DB':
        final (u0, u1) = _split(cargo.$1, cargo.$2, i, n);
        final c = s.chamfer;
        final section = s.hasBilge
            ? _rect(-(half - s.bilgeWidth), half - s.bilgeWidth, 0, hdb)
            : <P2>[(-half + c, 0), (half - c, 0), (half, c), (half, hdb), (-half, hdb), (-half, c)];
        return [SectionPart(section, u0, u1)];
      case 'BLG':
        final (u0, u1) = _split(cargo.$1, cargo.$2, i, n);
        final c = s.chamfer, bw = s.bilgeWidth;
        final sb = <P2>[(half - bw, 0), (half - c, 0), (half, c), (half, hdb), (half - bw, hdb)];
        return _sided(side, (sd) => SectionPart(_side(sb, sd), u0, u1));
      // ---- Side shell & wing tanks
      case 'SS':
        final (u0, u1) = _split(cargo.$1, cargo.$2, i, n);
        final sb = _rect(half - s.shellBand, half, hdb, d);
        return _sided(side, (sd) => SectionPart(_side(sb, sd), u0, u1));
      case 'WT':
        final (u0, u1) = _split(cargo.$1, cargo.$2, i, n);
        final sb = _rect(w, half - s.shellBand, hdb, d);
        return _sided(side, (sd) => SectionPart(_side(sb, sd), u0, u1));
      case 'HPT':
        final (u0, u1) = _split(cargo.$1, cargo.$2, i, n);
        final sb = <P2>[(w - s.hopperWidth, hdb), (w, hdb), (w, hdb + s.hopperHeight)];
        return _sided(side, (sd) => SectionPart(_side(sb, sd), u0, u1));
      case 'TST':
        final (u0, u1) = _split(cargo.$1, cargo.$2, i, n);
        final sb = <P2>[(w, d - s.topsideHeight), (w, d), (w - s.topsideWidth, d)];
        return _sided(side, (sd) => SectionPart(_side(sb, sd), u0, u1));
      // ---- Engine room
      case 'ER':
        final (u0, u1) = _split(er.$1, er.$2, i, n);
        final c = s.chamfer, eb = s.erBottom;
        final seatLen = (u1 - u0) * 0.25;
        return [
          SectionPart([(-half + c, 0), (half - c, 0), (half, c), (half, eb), (-half, eb), (-half, c)], u0, u1),
          SectionPart(_rect(-s.beam * 0.1, s.beam * 0.1, eb, eb + math.min(1.6, d * 0.15)), u0 + seatLen, u1 - seatLen),
        ];
      case 'ERS':
        final (u0, u1) = _split(er.$1, er.$2, i, n);
        final sb = _rect(half - s.shellBand, half, s.erBottom, d);
        return _sided(side, (sd) => SectionPart(_side(sb, sd), u0, u1));
      case 'ERF':
        final (u0, u1) = _split(er.$1, er.$2, i, n);
        final inner = half - s.shellBand;
        return [SectionPart(_rect(-inner, inner, d * 0.55 - 0.2, d * 0.55 + 0.2), u0, u1)];
      case 'CAS':
        final (u0, u1) = _split(er.$1 + (er.$2 - er.$1) * 0.2, er.$2 - (er.$2 - er.$1) * 0.4, i, n);
        final cw = math.min(s.beam * 0.15, 3.0);
        return [SectionPart(_rect(-cw, cw, d * 0.58, d), u0, u1)];
      // ---- Decks & hatches
      case 'DK':
        final (u0, u1) = _split(cargo.$1, cargo.$2, i, n);
        final dw = w - (s.hasTopside ? s.topsideWidth : 0);
        return [SectionPart(_rect(-dw, dw, d - s.deckPlate, d), u0, u1)];
      case 'TD':
        final (u0, u1) = _split(cargo.$1, cargo.$2, i, n);
        return [SectionPart(_rect(-w, w, d * 0.55 - 0.2, d * 0.55 + 0.2), u0, u1)];
      case 'HC':
        final (a, b) = _split(cargo.$1, cargo.$2, i, n);
        final m = math.min(2.0, (b - a) * 0.12), t = 0.35, hw = s.hatchHalf;
        final outer = _rect(a + m, b - m, -hw, hw);
        final hole = _rect(a + m + t, b - m - t, -hw + t, hw - t);
        return [
          PlanPart(outer, d, d + s.coamingHeight, holes: [hole]),
        ];
      // ---- Fore body
      case 'BOW':
        final (u0, u1) = _split(s.foreStart, s.length, i, n);
        return [PlanPart(clipU(s.bowPlan, u0, u1), 0, d)];
      case 'BB':
        final (u0, u1) = _split(s.length - s.foreLength * 0.3, s.length + s.bulbOverhang, i, n);
        final cu = (u0 + u1) / 2, ru = (u1 - u0) / 2, rv = math.min(s.beam * 0.12, 2.5);
        final ellipse = <P2>[
          for (var k = 0; k < 20; k++) (cu + ru * math.cos(2 * math.pi * k / 20), rv * math.sin(2 * math.pi * k / 20)),
        ];
        return [PlanPart(ellipse, d * 0.04, d * 0.4)];
      case 'BT':
        final (u0, u1) = _split(s.foreStart + s.foreLength * 0.2, s.foreStart + s.foreLength * 0.5, i, n);
        final r = (d * 0.09).clamp(0.5, 1.5).toDouble();
        return [TransverseCylinderPart((u0 + u1) / 2, d * 0.28, -half - 0.15, half + 0.15, r)];
      case 'FC':
        final (u0, u1) = _split(s.foreStart, s.length, i, n);
        return [PlanPart(clipU(s.bowPlan, u0, u1), d, d + s.raisedDeck)];
      // ---- Superstructure (aft, above the engine room)
      case 'ACC':
        final setback = accLen * 0.06 * i;
        final hw = half * (0.9 - 0.04 * i);
        return [
          PlanPart(_rect(s.aftEnd + setback, accEnd, -hw, hw), d + s.tier * i + 0.04, d + s.tier * (i + 1) - 0.04),
        ];
      case 'WH':
        return [
          PlanPart(
            _rect(accEnd - accLen * 0.45, accEnd, -half, half),
            accTop + s.raisedDeck * i + 0.04,
            accTop + s.raisedDeck * (i + 1) - 0.04,
          ),
        ];
      case 'FUN':
        final r = math.min(s.beam * 0.12, 3.0);
        final height = math.max(5.0, d * 0.7);
        final r0 = r * math.pow(0.9, i).toDouble(), r1 = r * math.pow(0.9, i + 1).toDouble();
        return [
          VerticalCylinderPart(
            s.aftEnd + accLen * 0.25,
            0,
            accTop + height * i + 0.04,
            accTop + height * (i + 1),
            r0,
            r1,
          ),
        ];
      case 'MST':
        if (i == 0) return [VerticalCylinderPart(accEnd - accLen * 0.25, 0, whTop, whTop + 6, 0.3, 0.2)];
        final (u0, u1) = _split(s.foreStart, s.foreStart + s.foreLength * 0.6, i - 1, n - 1);
        final base = d + (s.hasForecastle ? s.raisedDeck : 0);
        return [VerticalCylinderPart((u0 + u1) / 2, 0, base, base + 8, 0.3, 0.2)];
      // ---- Aft body
      case 'AFT':
        final (u0, u1) = _split(0, s.aftEnd, i, n);
        return [PlanPart(clipU(s.sternPlan, u0, u1), s.hasStern ? s.cutUp : 0, d)];
      case 'STF':
        final (u0, u1) = _split(0, s.aftEnd * 0.3, i, n);
        return [SectionPart(_rect(-0.45, 0.45, 0, s.cutUp + d * 0.15), u0, u1)];
      case 'SKG':
        final (u0, u1) = _split(s.aftEnd * 0.3, s.aftEnd, i, n);
        final plan = <P2>[
          (s.aftEnd * 0.3, -0.5),
          (s.aftEnd, -half * 0.55),
          (s.aftEnd, half * 0.55),
          (s.aftEnd * 0.3, 0.5),
        ];
        return [PlanPart(clipU(plan, u0, u1), 0, s.cutUp)];
      case 'PP':
        final (u0, u1) = _split(0, s.aftEnd, i, n);
        return [PlanPart(clipU(s.sternPlan, u0, u1), d, d + s.raisedDeck)];
      // ---- Bulkheads (evenly spaced over the cargo length)
      case 'BH':
        final uc = cargo.$1 + (cargo.$2 - cargo.$1) * (i + 1) / (n + 1);
        return [SectionPart(s.holdSection(), uc - 0.3, uc + 0.3)];
      case 'LBH':
        final (u0, u1) = _split(cargo.$1, cargo.$2, i, n);
        return [SectionPart(_rect(-0.25, 0.25, hdb, d - s.deckPlate), u0, u1)];
      case 'STL':
        final uc = cargo.$1 + (cargo.$2 - cargo.$1) * (i + 1) / (n + 1);
        final sw = w - (s.hasHopper ? s.hopperWidth : 0);
        return [SectionPart(_rect(-sw, sw, hdb, hdb + math.min(d * 0.12, 1.5)), uc - 1.2, uc + 1.2)];
      // ---- Other blocks: a row next to the hull on the ground (port side)
      default:
        final u0 = 4.0 + i * 6.0;
        final v = -(half + 5);
        return [PlanPart(_rect(u0, u0 + 4, v - 2, v + 2), -1.4, 1.6)];
    }
  }
}
