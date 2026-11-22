import 'package:flutter_test/flutter_test.dart';
import 'package:open_digital_twin/core/status/component_status.dart';
import 'package:open_digital_twin/features/digital_twin/domain/entities/twin_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/production_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/resource_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/services/lift_plan.dart';
import 'package:open_digital_twin/features/shipyard/domain/services/outfitting_lifts.dart';

const quayArea = 'NODE_A19_OUTFITTING_QUAY';

void main() {
  final now = DateTime(2027, 12, 31, 9);

  Hull hull({double length = 99, double beam = 13, String? shipType = 'Bulk Carrier'}) => Hull(
    id: 'h1',
    projectId: 'p',
    hullNo: 'NB-1001',
    contractType: 'newbuild',
    status: HullStatus.afloatOutfitting,
    metadata: const {},
    lengthM: length,
    beamM: beam,
    shipType: shipType,
  );

  TwinComponent crane(String id, double swl, {String location = quayArea}) => TwinComponent(
    id: id,
    projectId: 'p',
    meshNodeId: 'NODE_${id.toUpperCase()}',
    name: id,
    status: ComponentStatus.normal,
    metadata: {'swl_t': swl, 'location': location},
    updatedAt: DateTime(2026),
    category: 'crane',
  );

  final luffing = crane('luffing', 28);
  final jib1 = crane('jib1', 50);
  final jib2 = crane('jib2', 50);
  final cranes = [jib1, luffing, jib2];

  ProductionActivity package(
    WorkPackage p,
    DateTime start,
    int days, {
    String location = quayArea,
    DateTime? actualEnd,
  }) => ProductionActivity(
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

  ResourceBooking existing(BookingDraft d, {bool cancelled = false}) => ResourceBooking(
    id: 'bk-${d.title}',
    projectId: 'p',
    componentId: d.componentId,
    activityId: d.activityId,
    hullId: d.hullId,
    title: d.title,
    type: d.type,
    slot: d.slot,
    startsAt: d.startsAt,
    endsAt: d.endsAt,
    loadT: d.loadT,
    status: cancelled ? BookingStatus.cancelled : BookingStatus.planned,
  );

  test('heavy items per package scale with the hull; hatch covers only for cargo ships', () {
    final nb = hull();
    final deck = OutfittingLifts.itemsOf(nb, WorkPackage.deckMachinery);
    // 99 m -> 4 holds -> 8 panels; scale 99 x 13 / 1600 = 0.80.
    expect(deck.first, const OutfittingLiftItem('Hatch cover panel', 8, 9.7));
    expect(
      OutfittingLifts.itemsOf(hull(shipType: 'Tug'), WorkPackage.deckMachinery).map((i) => i.label),
      isNot(contains('Hatch cover panel')),
    );
    expect(OutfittingLifts.itemsOf(nb, WorkPackage.painting), isEmpty);
    expect(OutfittingLifts.itemsOf(nb, WorkPackage.piping, packageDays: 19).single.count, 3);
    final big = OutfittingLifts.itemsOf(hull(length: 200, beam: 32), WorkPackage.deckMachinery).first;
    expect(big.count, 16);
    expect(big.weightT, 48); // scale capped at 4
    for (final p in WorkPackage.values) {
      for (final i in OutfittingLifts.itemsOf(nb, p)) {
        expect(i.count, greaterThan(0));
        expect(i.weightT, greaterThan(0));
      }
    }
  });

  test('books every item on the smallest quay crane that carries it, spread over the package days', () {
    final start = DateTime(2028, 1, 2);
    final rows = [package(WorkPackage.deckMachinery, start, 12), package(WorkPackage.machinery, start, 10)];
    final r = OutfittingLifts.forHull(hull: hull(), activities: rows, components: cranes, bookings: const [], now: now);
    expect(r.warnings, isEmpty);
    // Deck: 8 hatch panels + 2 windlass + 2 aft winches + lifeboat; machinery: 3 gensets + boiler + emergency gen.
    expect(r.bookings, hasLength(13 + 5));
    for (final b in r.bookings) {
      expect(b.type, BookingType.lift);
      expect(b.status, BookingStatus.planned);
      expect(b.slot, 1);
      expect(b.hullId, 'h1');
      expect(b.loadT, lessThanOrEqualTo(28));
      expect(b.startsAt.hour, greaterThanOrEqualTo(LiftPlan.dayStartHour));
      expect(b.endsAt.hour, lessThanOrEqualTo(LiftPlan.dayEndHour));
      expect(b.notes, OutfittingLifts.estimateNote);
      final row = rows.firstWhere((a) => a.id == b.activityId);
      expect(b.startsAt.isBefore(row.plannedStart), isFalse);
      expect(b.startsAt.isBefore(row.plannedEnd), isTrue);
    }
    // All items are < 28 t: the luffing crane takes them first.
    expect(r.cranes[luffing.id], greaterThan(r.cranes[jib1.id] ?? 0));
    // The panels are spread over the deck package, not stacked on its first day.
    final panels = r.bookings.where((b) => b.title.contains('Hatch cover panel')).toList();
    expect(panels.map((b) => dateOnly(b.startsAt)).toSet().length, greaterThan(3));
    expect(panels.map((b) => b.title), contains('NB-1001 Hatch cover panel 1/8 lift'));
    // Ordered by time, no overlap per crane.
    for (var i = 1; i < r.bookings.length; i++) {
      expect(r.bookings[i].startsAt.isBefore(r.bookings[i - 1].startsAt), isFalse);
    }
    for (final c in cranes) {
      final own = r.bookings.where((b) => b.componentId == c.id).toList();
      for (var i = 0; i < own.length; i++) {
        for (var j = i + 1; j < own.length; j++) {
          expect(own[i].startsAt.isBefore(own[j].endsAt) && own[j].startsAt.isBefore(own[i].endsAt), isFalse);
        }
      }
    }
  });

  test('heavier items take the 50 t jib; too heavy items and missing cranes are reported', () {
    final start = DateTime(2028, 1, 2);
    final big = hull(length: 200, beam: 32); // hatch panels 48 t, generator sets 36 t
    final r = OutfittingLifts.forHull(
      hull: big,
      activities: [package(WorkPackage.deckMachinery, start, 20), package(WorkPackage.machinery, start, 20)],
      components: cranes,
      bookings: const [],
      now: now,
    );
    final panel = r.bookings.firstWhere((b) => b.title.contains('Hatch cover panel'));
    expect([jib1.id, jib2.id], contains(panel.componentId));
    expect(r.warnings, isEmpty);

    final onlyLuffing = OutfittingLifts.forHull(
      hull: big,
      activities: [package(WorkPackage.deckMachinery, start, 20)],
      components: [luffing],
      bookings: const [],
      now: now,
    );
    expect(onlyLuffing.warnings.single, contains('Hatch cover panel (48 t)'));
    final docked = OutfittingLifts.forHull(
      hull: hull(),
      activities: [package(WorkPackage.electrical, start, 5, location: 'NODE_A18_FLOATING_DOCK')],
      components: cranes,
      bookings: const [],
      now: now,
    );
    expect(docked.bookings, isEmpty);
    expect(docked.warnings.single, contains('No crane at'));
  });

  test('booked items are skipped; cancelled ones, existing windows and the past are respected', () {
    final start = DateTime(2028, 1, 2);
    final rows = [package(WorkPackage.electrical, start, 3)];
    final first = OutfittingLifts.forHull(
      hull: hull(),
      activities: rows,
      components: cranes,
      bookings: const [],
      now: now,
    );
    expect(first.bookings, hasLength(3));
    final again = OutfittingLifts.forHull(
      hull: hull(),
      activities: rows,
      components: cranes,
      bookings: [existing(first.bookings[0]), existing(first.bookings[1], cancelled: true)],
      now: now,
    );
    expect(again.bookings.map((b) => b.title).toSet(), {first.bookings[1].title, first.bookings[2].title});
    expect(
      again.bookings.any(
        (b) => b.componentId == first.bookings[0].componentId && b.startsAt == first.bookings[0].startsAt,
      ),
      isFalse,
    );

    // A finished package gets no lifts; a running one only from now on.
    expect(
      OutfittingLifts.forHull(
        hull: hull(),
        activities: [package(WorkPackage.electrical, start, 3, actualEnd: DateTime(2028, 1, 4))],
        components: cranes,
        bookings: const [],
        now: now,
      ).bookings,
      isEmpty,
    );
    final late = OutfittingLifts.forHull(
      hull: hull(),
      activities: [package(WorkPackage.electrical, DateTime(2027, 12, 20), 3)],
      components: cranes,
      bookings: const [],
      now: now,
    );
    expect(late.bookings, isNotEmpty);
    expect(late.bookings.every((b) => !b.startsAt.isBefore(now)), isTrue);
  });
}
