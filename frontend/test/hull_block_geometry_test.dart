import 'package:flutter_test/flutter_test.dart';
import 'package:open_digital_twin/core/status/component_status.dart';
import 'package:open_digital_twin/features/digital_twin/domain/entities/twin_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/block_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/production_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/services/hull_block_geometry.dart';

Hull hull(String no, {double? length = 99, double? beam = 13, String? location}) => Hull(
  id: no,
  projectId: 'p1',
  hullNo: no,
  contractType: 'newbuild',
  status: HullStatus.values.first,
  metadata: const {},
  lengthM: length,
  beamM: beam,
  locationNodeId: location,
);

TwinComponent block(String hull, String no, String type, {String? side, int seq = 1}) => TwinComponent(
  id: '$hull/$no',
  projectId: 'p1',
  meshNodeId: blockMeshNodeId(hull, no),
  name: '$hull Block $no',
  status: ComponentStatus.normal,
  metadata: {'hull_no': hull, 'block_no': no, 'block_type': type, 'side': side, 'erection_sequence': seq},
  updatedAt: DateTime(2026),
  category: hullBlockCategory,
);

/// World bounding box of the points of a node's parts (cylinders by their axis ends).
({double minX, double maxX, double minY, double maxY, double minZ, double maxZ}) bounds(ProceduralNode n) {
  final (ox, oy, oz) = n.origin;
  final xs = <double>[], ys = <double>[], zs = <double>[];
  void add(double u, double v, double h) {
    xs.add(ox + v);
    ys.add(oy + h);
    zs.add(oz - u);
  }

  for (final p in n.parts) {
    switch (p) {
      case SectionPart():
        for (final (v, h) in p.points) {
          add(p.u0, v, h);
          add(p.u1, v, h);
        }
      case PlanPart():
        for (final (u, v) in p.points) {
          add(u, v, p.h0);
          add(u, v, p.h1);
        }
      case VerticalCylinderPart():
        add(p.u, p.v, p.h0);
        add(p.u, p.v, p.h1);
      case TransverseCylinderPart():
        add(p.u, p.v0, p.h);
        add(p.u, p.v1, p.h);
    }
  }
  double min(List<double> l) => l.reduce((a, b) => a < b ? a : b);
  double max(List<double> l) => l.reduce((a, b) => a > b ? a : b);
  return (minX: min(xs), maxX: max(xs), minY: min(ys), maxY: max(ys), minZ: min(zs), maxZ: max(zs));
}

void main() {
  final comps = [
    block('NB-1001', 'DB-101', 'DB', seq: 1),
    block('NB-1001', 'DB-102', 'DB', seq: 2),
    block('NB-1001', 'SS-201P', 'SS', side: 'port', seq: 3),
    block('NB-1001', 'SS-201S', 'SS', side: 'starboard', seq: 4),
    block('NB-1001', 'ACC-601', 'ACC', seq: 5),
    block('NB-1001', 'FUN-601', 'FUN', seq: 6),
    block('NB-1001', 'BOW-501', 'BOW', seq: 7),
    block('NB-1001', 'BT-501', 'BT', seq: 8),
    block('NB-1001', 'X-1', 'BLK', seq: 9),
  ];

  ProceduralNode node(List<ProceduralNode> nodes, String id) => nodes.firstWhere((n) => n.meshNodeId == id);

  test('one envelope and one node per block, on the building berth', () {
    final nodes = HullBlockGeometry.build([hull('NB-1001')], comps);
    expect(nodes.length, comps.length + 1);
    expect(nodes.first.meshNodeId, 'CTX_NB1001_HULL_ENVELOPE');
    expect(nodes.first.contextOpacity, isNotNull);
    expect(nodes.every((n) => n.parts.isNotEmpty), isTrue);
    expect(nodes.every((n) => n.origin == (70.0, 2.0, -36.0)), isTrue);
    expect(nodes.first.toJson()['id'], 'CTX_NB1001_HULL_ENVELOPE');
  });

  test('blocks of one type split the region aft to fore in block number order', () {
    final nodes = HullBlockGeometry.build([hull('NB-1001')], comps);
    final db1 = bounds(node(nodes, 'NODE_NB1001_BLOCK_DB_101'));
    final db2 = bounds(node(nodes, 'NODE_NB1001_BLOCK_DB_102'));
    // Bow toward -Z: the forward block has smaller z.
    expect(db2.maxZ, lessThan(db1.minZ));
    expect(db1.minY, 2.0);
    // Inside the hull (99 m from the stern at z -36).
    for (final b in [db1, db2]) {
      expect(b.maxZ, lessThanOrEqualTo(-36));
      expect(b.minZ, greaterThanOrEqualTo(-36 - 99));
      expect(b.minX, greaterThanOrEqualTo(70 - 6.5 - 1e-9));
      expect(b.maxX, lessThanOrEqualTo(70 + 6.5 + 1e-9));
    }
  });

  test('port blocks are at -x, starboard at +x; superstructure above the deck', () {
    final nodes = HullBlockGeometry.build([hull('NB-1001')], comps);
    final port = bounds(node(nodes, 'NODE_NB1001_BLOCK_SS_201P'));
    final sb = bounds(node(nodes, 'NODE_NB1001_BLOCK_SS_201S'));
    expect(port.maxX, lessThan(70));
    expect(sb.minX, greaterThan(70));
    final shape = HullShape.of(hull('NB-1001'), const {});
    final acc = bounds(node(nodes, 'NODE_NB1001_BLOCK_ACC_601'));
    final fun = bounds(node(nodes, 'NODE_NB1001_BLOCK_FUN_601'));
    expect(acc.minY, greaterThan(2 + shape.depth - 0.01));
    expect(fun.minY, greaterThanOrEqualTo(acc.maxY));
    final bow = bounds(node(nodes, 'NODE_NB1001_BLOCK_BOW_501'));
    expect(bow.minZ, closeTo(-36 - 99, 1e-6));
    expect(node(nodes, 'NODE_NB1001_BLOCK_BT_501').parts.single, isA<TransverseCylinderPart>());
    expect(node(nodes, 'NODE_NB1001_BLOCK_FUN_601').color, isNot(node(nodes, 'NODE_NB1001_BLOCK_DB_101').color));
    // Other blocks wait next to the hull (port side, on the ground).
    final other = bounds(node(nodes, 'NODE_NB1001_BLOCK_X_1'));
    expect(other.maxX, lessThan(70 - 6.5));
  });

  test('hulls without blocks are skipped, several hulls stand in tandem, dry dock hulls go to the dock', () {
    final nodes = HullBlockGeometry.build(
      [hull('NB-1002', length: 80), hull('NB-1001'), hull('NB-1003'), hull('NB-1004', location: dryDock.areaNodeId)],
      [...comps, block('NB-1002', 'DB-101', 'DB'), block('NB-1004', 'DB-101', 'DB')],
    );
    final origins = {for (final n in nodes) n.meshNodeId.split('_')[1]: n.origin};
    expect(origins.keys, containsAll(['NB1001', 'NB1002', 'NB1004']));
    expect(origins.containsKey('NB1003'), isFalse);
    expect(origins['NB1001'], (70.0, 2.0, -36.0));
    // NB-1002 behind NB-1001 (99 m + bulb + 12 m gap).
    expect(origins['NB1002']!.$3, lessThan(-36 - 99 - 12 + 1e-9));
    expect(origins['NB1004'], (dryDock.x, dryDock.keelY, dryDock.firstSternZ));
  });

  test('missing dimensions use defaults; plan clipping keeps the cut inside the range', () {
    final shape = HullShape.of(hull('NB-9', length: null, beam: null), const {});
    expect(shape.length, 160);
    expect(shape.beam, greaterThan(20));
    final nodes = HullBlockGeometry.hullNodes(
      'NB-9',
      [
        for (final no in ['BOW-501', 'BOW-502']) HullBlock.fromComponent(block('NB-9', no, 'BOW')),
      ],
      shape,
      (0, 0, 0),
    );
    final b1 = bounds(nodes[1]), b2 = bounds(nodes[2]);
    expect(b1.maxZ, closeTo(-shape.foreStart, 1e-6));
    expect(b2.minZ, closeTo(-shape.length, 1e-6));
    expect(b1.minZ, greaterThan(b2.maxZ));
  });
}
