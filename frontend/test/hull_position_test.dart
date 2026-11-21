import 'package:flutter_test/flutter_test.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/production_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/services/hull_position.dart';

const berth = 'NODE_A16_BUILDING_BERTH';
const dryDock = 'NODE_A17_DRY_DOCK';
const floatingDock = 'NODE_A18_FLOATING_DOCK';
const quay = 'NODE_A19_OUTFITTING_QUAY';

Hull hull({String id = 'h1', String? location, String contractType = 'newbuild'}) => Hull(
  id: id,
  projectId: 'p1',
  hullNo: 'NB-$id',
  contractType: contractType,
  status: HullStatus.planned,
  metadata: const {},
  locationNodeId: location,
);

var _seq = 0;

ProductionActivity row(
  ProductionStage stage,
  DateTime start,
  DateTime end, {
  String hullId = 'h1',
  String? componentId,
  String? location,
  DateTime? actualStart,
  DateTime? actualEnd,
}) => ProductionActivity(
  id: 'a${_seq++}',
  projectId: 'p1',
  hullId: hullId,
  componentId: componentId,
  code: '${stage.dbValue}-$_seq',
  name: stage.label,
  stage: stage,
  plannedStart: start,
  plannedEnd: end,
  progressPct: actualEnd != null ? 100 : 0,
  sortOrder: _seq,
  locationNodeId: location,
  actualStart: actualStart,
  actualEnd: actualEnd,
);

DateTime d(int month, int day) => DateTime(2027, month, day);

void main() {
  final today = d(1, 1);

  List<ProductionActivity> newbuild({String erectionSite = berth, String? dockingAt}) => [
    row(ProductionStage.cutting, d(1, 2), d(1, 8), componentId: 'b1', location: 'NODE_A05_CNC_CUTTING_SHOP'),
    row(ProductionStage.erection, d(1, 10), d(1, 20), componentId: 'b1', location: erectionSite),
    row(ProductionStage.launching, d(2, 1), d(2, 2), location: erectionSite),
    row(ProductionStage.outfitting, d(2, 2), d(3, 1), location: quay),
    row(ProductionStage.commissioning, d(2, 15), d(3, 5), location: quay),
    if (dockingAt != null) row(ProductionStage.dockingRepair, d(3, 5), d(3, 7), location: dockingAt),
    row(ProductionStage.seaTrials, d(3, 8), d(3, 12)),
    row(ProductionStage.delivery, d(3, 20), d(3, 21), location: quay),
  ];

  HullPosition at(List<ProductionActivity> rows, DateTime date, {Hull? h}) =>
      HullPositions.at(h ?? hull(), rows, date, today);

  test('on the berth until launching ends, then afloat at the quay', () {
    final rows = newbuild();
    expect(at(rows, d(1, 1)), const HullPosition(HullPositionKind.building, areaNodeId: berth));
    expect(at(rows, d(1, 15)), const HullPosition(HullPositionKind.building, areaNodeId: berth));
    final launchDay = at(rows, d(2, 1));
    expect(launchDay.kind, HullPositionKind.building);
    expect(launchDay.activity?.stage, ProductionStage.launching);
    final afloat = at(rows, d(2, 2));
    expect(afloat, const HullPosition(HullPositionKind.afloat, areaNodeId: quay));
    expect(afloat.activity?.stage, ProductionStage.outfitting);
    expect(afloat.inYard, isTrue);
  });

  test('sea trials = at sea, back at the quay before delivery, gone after it', () {
    final rows = newbuild();
    final trials = at(rows, d(3, 10));
    expect(trials.kind, HullPositionKind.atSea);
    expect(trials.inYard, isFalse);
    expect(at(rows, d(3, 15)), const HullPosition(HullPositionKind.afloat, areaNodeId: quay));
    expect(at(rows, d(3, 20)), const HullPosition(HullPositionKind.afloat, areaNodeId: quay));
    final delivered = at(rows, d(3, 21));
    expect(delivered.kind, HullPositionKind.delivered);
    expect(delivered.inYard, isFalse);
    expect(at(rows, d(6, 1)).kind, HullPositionKind.delivered);
  });

  test('a docking row after launching docks the hull; afterwards back at the quay', () {
    final rows = newbuild(dockingAt: floatingDock);
    expect(at(rows, d(3, 6)), const HullPosition(HullPositionKind.docked, areaNodeId: floatingDock));
    expect(at(rows, d(3, 7)), const HullPosition(HullPositionKind.afloat, areaNodeId: quay));
  });

  test('a hull built in the dry dock stays there until it floats out', () {
    final rows = newbuild(erectionSite: dryDock);
    expect(at(rows, d(1, 15)), const HullPosition(HullPositionKind.building, areaNodeId: dryDock));
    expect(at(rows, d(2, 3)), const HullPosition(HullPositionKind.afloat, areaNodeId: quay));
    // Without erection rows the hull location decides.
    expect(HullPositions.buildSite(hull(location: dryDock), const []), dryDock);
    expect(HullPositions.buildSite(hull(location: quay), const []), berth);
  });

  test('the database moving the hull to the quay does not move it back in time', () {
    // After launching the hull row lies at the quay; earlier dates still show the berth.
    final rows = newbuild();
    expect(at(rows, d(1, 15), h: hull(location: quay)).areaNodeId, berth);
  });

  test('a late launching keeps the hull on the berth until it is reported', () {
    final rows = [
      row(ProductionStage.launching, d(1, 1), d(1, 2), location: berth),
      row(ProductionStage.outfitting, d(1, 2), d(2, 1), location: quay),
    ];
    // Planned before "today" but not started: the forecast starts today.
    expect(HullPositions.at(hull(), rows, d(1, 10), d(1, 10)).kind, HullPositionKind.building);
    final reported = [
      row(ProductionStage.launching, d(1, 1), d(1, 2), location: berth, actualStart: d(1, 1), actualEnd: d(1, 2)),
      rows[1],
    ];
    expect(HullPositions.at(hull(), reported, d(1, 10), d(1, 10)).areaNodeId, quay);
  });

  test('without a launching row the hull lies at its location', () {
    expect(
      at(const [], d(1, 1), h: hull(location: quay)),
      const HullPosition(HullPositionKind.afloat, areaNodeId: quay),
    );
    expect(
      at(const [], d(1, 1), h: hull(location: floatingDock)),
      const HullPosition(HullPositionKind.docked, areaNodeId: floatingDock),
    );
    expect(
      at(
        const [],
        d(1, 1),
        h: hull(location: dryDock, contractType: 'repair'),
      ),
      const HullPosition(HullPositionKind.docked, areaNodeId: dryDock),
    );
    expect(at(const [], d(1, 1)), const HullPosition(HullPositionKind.building, areaNodeId: berth));
    expect(HullPositions.fromLocation(hull(location: quay)).kind, HullPositionKind.afloat);
  });

  test('positions of a yard are value-equal while no hull moves', () {
    final hulls = [hull(), hull(id: 'h2')];
    final rows = [...newbuild(), row(ProductionStage.launching, d(5, 1), d(5, 2), hullId: 'h2', location: berth)];
    final a = HullPositions.all(hulls, rows, d(2, 10), today);
    final b = HullPositions.all(hulls, rows, d(2, 20), today);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a['h2']!.areaNodeId, berth);
    expect(HullPositions.all(hulls, rows, d(3, 10), today), isNot(a));
  });
}
