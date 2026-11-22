import 'package:flutter_test/flutter_test.dart';
import 'package:open_digital_twin/features/shipyard/data/models/material_models.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/hse_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/material_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/production_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/quality_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/resource_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/work_scope.dart';
import 'package:open_digital_twin/features/shipyard/domain/services/outfitting_materials.dart';
import 'package:open_digital_twin/features/shipyard/domain/services/permit_plan.dart';

const quay = 'NODE_A19_OUTFITTING_QUAY';

void main() {
  final now = DateTime(2028, 1, 4, 9, 30);
  final nb = Hull(
    id: 'h1',
    projectId: 'p',
    hullNo: 'NB-1001',
    contractType: 'newbuild',
    status: HullStatus.afloatOutfitting,
    metadata: const {},
    lengthM: 99,
    beamM: 13,
    shipType: 'Bulk Carrier',
  );

  ProductionActivity package(WorkPackage p, DateTime start, int days, {DateTime? actualEnd, String? location = quay}) =>
      ProductionActivity(
        id: 'a-${p.dbValue}',
        projectId: 'p',
        hullId: 'h1',
        code: 'NB1001-OUTFIT-${p.code}',
        name: 'NB-1001 ${p.label}',
        stage: ProductionStage.outfitting,
        locationNodeId: location,
        plannedStart: start,
        plannedEnd: addDays(start, days),
        actualStart: actualEnd == null ? null : start,
        actualEnd: actualEnd,
        progressPct: 0,
        sortOrder: p.index,
        workPackage: p,
      );

  MaterialItem item(String code, String unit, {StockCategory type = StockCategory.pipe}) => MaterialItem(
    id: 'i-$code',
    itemCode: code,
    description: code,
    type: type,
    unit: unit,
    onHand: 100,
    reserved: 0,
    reorderLevel: 0,
  );

  final items = [
    item('PIPE-ST-DN150', 'm'),
    item('PIPE-CUNI-DN100', 'm'),
    item('VALVE-BF-DN150', 'pcs'),
    item('PAINT-PU-TOP', 'l', type: StockCategory.paint),
    item('PAINT-EP-150', 'l', type: StockCategory.paint),
  ];
  const nodes = {quay: 'c-quay'};

  group('OutfittingMaterialPlan', () {
    final rows = [
      package(WorkPackage.piping, DateTime(2028, 1, 2), 19),
      package(WorkPackage.painting, DateTime(2028, 1, 18), 7),
      package(WorkPackage.electrical, DateTime(2028, 1, 5), 20),
      package(WorkPackage.machinery, DateTime(2028, 1, 2), 10, actualEnd: DateTime(2028, 1, 3)),
    ];

    test('one reservation per package and item, at the quay, needed at the package start', () {
      final r = OutfittingMaterialPlan.forHull(
        hull: nb,
        activities: rows,
        items: items,
        reservations: const [],
        componentIdByNode: nodes,
      );
      // piping 3 + painting 2; electrical: cables not in stock; machinery finished.
      expect(r.drafts, hasLength(5));
      expect(r.warnings.single, contains('CABLE-PWR-3X95, CABLE-SIG-4X1.5'));
      for (final d in r.drafts) {
        expect(d.componentId, 'c-quay');
        expect(d.hullId, 'h1');
        expect(d.activityId, isNotNull);
        expect(d.validationErrors(), isEmpty);
        expect(d.notes, OutfittingMaterialPlan.draftNote);
      }
      final pipe = r.drafts.firstWhere((d) => d.itemId == 'i-PIPE-ST-DN150');
      expect(pipe.activityId, 'a-piping');
      expect(pipe.neededBy, DateTime(2028, 1, 2));
      // 900 m x 0.80 (99 x 13 / 1600) = 723.9 -> 724 m.
      expect(pipe.quantity, 724);
      final topCoat = r.drafts.firstWhere((d) => d.itemId == 'i-PAINT-PU-TOP');
      expect(topCoat.quantity % 10, 0);
      final row = ReservationModel.insert(pipe);
      expect(row['activity_id'], 'a-piping');
      expect(row['component_id'], 'c-quay');
    });

    test('items already reserved for a package are skipped; rows without an area are reported', () {
      final existing = MaterialReservation(
        id: 'r1',
        itemId: 'i-PIPE-ST-DN150',
        componentId: 'c-quay',
        activityId: 'a-piping',
        quantity: 500,
        status: ReservationStatus.issued,
      );
      final r = OutfittingMaterialPlan.forHull(
        hull: nb,
        activities: [rows.first, package(WorkPackage.painting, DateTime(2028, 1, 18), 7, location: null)],
        items: items,
        reservations: [existing],
        componentIdByNode: nodes,
      );
      expect(r.drafts.map((d) => d.itemId), ['i-PIPE-CUNI-DN100', 'i-VALVE-BF-DN150']);
      expect(r.warnings.single, contains('NB1001-OUTFIT-PNT'));
      expect(OutfittingMaterialPlan.quantityOf(const PackageMaterial('X', 1.04), 1, 't'), 1.1);
    });
  });

  group('WorkScope', () {
    final row = package(WorkPackage.piping, DateTime(2028, 1, 2), 19);
    final scope = WorkScope.package(row);

    test('a package owns the records linked to its row, pinned to the quay', () {
      expect(scope.isPackage, isTrue);
      expect(scope.code, 'Piping systems');
      expect(scope.noun, 'work package');
      expect(scope.componentIdIn(nodes), 'c-quay');
      expect(scope.activityId, 'a-piping');
      expect(scope.ownsRow(row), isTrue);
      expect(scope.ownsRow(package(WorkPackage.painting, DateTime(2028, 1, 18), 7)), isFalse);
      MaterialReservation res(String? activityId) => MaterialReservation(
        id: 'r',
        itemId: 'i',
        componentId: 'c-quay',
        activityId: activityId,
        quantity: 1,
        status: ReservationStatus.reserved,
      );
      expect(scope.ownsReservation(res('a-piping')), isTrue);
      // Another hull's material at the same quay is not this package's.
      expect(scope.ownsReservation(res(null)), isFalse);
    });
  });

  group('PermitPlan for work packages', () {
    test('package permit types', () {
      expect(PermitPlan.typesForPackage(WorkPackage.deckMachinery), [PermitType.lifting, PermitType.hotWork]);
      expect(PermitPlan.typesForPackage(WorkPackage.electrical), [PermitType.electricalIsolation]);
      expect(PermitPlan.typesForPackage(WorkPackage.painting), contains(PermitType.confinedSpace));
      expect(PermitPlan.typesForPackage(WorkPackage.accommodation), isEmpty);
      expect(PermitPlan.typesForPackage(null), isEmpty);
    });

    test('needs of a running package, covered by its permits; lifting follows the quay lift', () {
      final deck = package(WorkPackage.deckMachinery, DateTime(2028, 1, 3), 12);
      final permit = WorkPermit(
        id: 'w1',
        componentId: 'c-quay',
        activityId: deck.id,
        permitNo: 'PTW-1',
        type: PermitType.hotWork,
        description: 'x',
        status: PermitStatus.approved,
        validFrom: DateTime(2028, 1, 4, 7),
        validTo: DateTime(2028, 1, 4, 17),
        position: MarkerPosition.top,
      );
      final needs = PermitPlan.forScope(
        scope: WorkScope.package(deck),
        activities: [deck, package(WorkPackage.painting, DateTime(2028, 1, 18), 7)],
        permits: [permit],
        now: now,
      );
      // Painting starts in 14 days: outside the look-ahead.
      expect(needs.map((n) => n.type), [PermitType.lifting, PermitType.hotWork]);
      expect(needs.firstWhere((n) => n.type == PermitType.hotWork).covered, isTrue);
      final lifting = needs.firstWhere((n) => n.type == PermitType.lifting);
      expect(lifting.covered, isFalse);
      final lift = ResourceBooking(
        id: 'b1',
        projectId: 'p',
        componentId: 'crane',
        activityId: deck.id,
        title: 'NB-1001 Hatch cover panel 1/8 lift',
        type: BookingType.lift,
        slot: 1,
        startsAt: DateTime(2028, 1, 5, 7),
        endsAt: DateTime(2028, 1, 5, 10),
        status: BookingStatus.planned,
      );
      final s = PermitPlan.suggest(need: lifting, title: deck.name, bookings: [lift], now: now);
      expect(s.validFrom, DateTime(2028, 1, 5, 7));
      expect(s.hours, 3);
      expect(s.description, 'NB-1001 Deck machinery & hatch covers: lifting (crane lift)');
    });
  });
}
