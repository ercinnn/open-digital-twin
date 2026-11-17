import 'package:flutter_test/flutter_test.dart';
import 'package:open_digital_twin/core/status/component_status.dart';
import 'package:open_digital_twin/features/digital_twin/domain/entities/twin_entities.dart';
import 'package:open_digital_twin/features/shipyard/data/models/resource_models.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/production_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/resource_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/services/lift_plan.dart';

void main() {
  final now = DateTime(2026, 11, 17, 9);
  const berth = 'NODE_A16_BUILDING_BERTH';
  const dock = 'NODE_A17_DRY_DOCK';

  final hull = Hull(
    id: 'h1',
    projectId: 'p',
    hullNo: 'NB-1001',
    contractType: 'newbuild',
    status: HullStatus.planned,
    metadata: const {},
  );

  TwinComponent comp(String id, String category, Map<String, dynamic> metadata, {double? weightKg}) => TwinComponent(
    id: id,
    projectId: 'p',
    meshNodeId: 'NODE_${id.toUpperCase()}',
    name: id,
    status: ComponentStatus.normal,
    metadata: metadata,
    updatedAt: DateTime(2026),
    category: category,
    weightKg: weightKg,
  );

  final goliath = comp('goliath', 'crane', {'swl_t': 600, 'location': berth});
  final portal = comp('portal', 'crane', {'swl_t': 400, 'location': dock});
  final quay = comp('quay', 'crane', {'swl_t': 50, 'location': 'NODE_A19_OUTFITTING_QUAY'});
  TwinComponent block(String no, {double? weightKg}) =>
      comp('b-$no', 'hull_structure', {'block_no': no}, weightKg: weightKg);

  var seq = 0;
  ProductionActivity erection(
    String blockNo,
    DateTime start, {
    int days = 2,
    String location = berth,
    String? hullId = 'h1',
    DateTime? actualEnd,
    ProductionStage stage = ProductionStage.erection,
    bool hullLevel = false,
  }) => ProductionActivity(
    id: 'a-$blockNo-${seq++}',
    projectId: 'p',
    hullId: hullId,
    componentId: hullLevel ? null : 'b-$blockNo',
    code: 'NB1001-$blockNo-ERECT',
    name: 'NB-1001 $blockNo Erection',
    stage: stage,
    locationNodeId: location,
    plannedStart: start,
    plannedEnd: addDays(start, days),
    actualStart: actualEnd == null ? null : start,
    actualEnd: actualEnd,
    progressPct: 0,
    sortOrder: seq,
  );

  ResourceBooking booking(String craneId, DateTime start, DateTime end, {String? activityId, bool cancelled = false}) =>
      ResourceBooking(
        id: 'bk-${start.toIso8601String()}',
        projectId: 'p',
        componentId: craneId,
        activityId: activityId,
        title: 'Existing',
        type: BookingType.maintenance,
        slot: 1,
        startsAt: start,
        endsAt: end,
        status: cancelled ? BookingStatus.cancelled : BookingStatus.confirmed,
      );

  LiftPlanResult plan(
    List<ProductionActivity> activities,
    List<TwinComponent> blocks, {
    List<ResourceBooking> bookings = const [],
  }) => LiftPlan.forHull(
    hull: hull,
    activities: activities,
    components: [goliath, portal, quay, ...blocks],
    bookings: bookings,
    now: now,
  );

  test('one planned lift per block erection on the crane of the erection area', () {
    final day = DateTime(2027, 1, 4);
    final r = plan(
      [erection('DB-101', day), erection('DB-102', day), erection('X', day, stage: ProductionStage.cutting)],
      [block('DB-101', weightKg: 85000), block('DB-102', weightKg: 320000)],
    );
    expect(r.bookings, hasLength(2));
    final first = r.bookings.first;
    expect(first.componentId, 'goliath');
    expect(first.type, BookingType.lift);
    expect(first.status, BookingStatus.planned);
    expect(first.activityId, startsWith('a-DB-101'));
    expect(first.hullId, 'h1');
    expect(first.title, 'NB-1001 DB-101 erection lift');
    expect(first.loadT, 85);
    expect(first.startsAt, DateTime(2027, 1, 4, 7));
    expect(first.endsAt, DateTime(2027, 1, 4, 10));
    // Same day, same crane: the heavier block follows (6 h window still fits).
    expect(r.bookings[1].startsAt, DateTime(2027, 1, 4, 10));
    expect(r.bookings[1].endsAt, DateTime(2027, 1, 4, 16));
    expect(r.cranes, {'goliath': 2});
    expect(r.warnings, isEmpty);
  });

  test('busy crane windows and the end of the working day push the lift on', () {
    final day = DateTime(2027, 2, 1);
    final r = plan(
      [erection('DB-101', day)],
      [block('DB-101')],
      bookings: [
        booking('goliath', DateTime(2027, 2, 1, 6), DateTime(2027, 2, 1, 15)),
        booking('goliath', DateTime(2027, 2, 1, 15), DateTime(2027, 2, 1, 17), cancelled: true),
      ],
    );
    // The busy window ends at 15:00 and a 3 h lift would end after 17:00 (the cancelled booking does not count).
    expect(r.bookings.single.startsAt, DateTime(2027, 2, 2, 7));
    expect(r.warnings.single, contains('no weight'));
    expect(r.bookings.single.notes, contains('capacity'));
  });

  test('already booked, finished and other hulls\' erections are skipped', () {
    final day = DateTime(2027, 3, 1);
    final booked = erection('DB-101', day);
    final r = plan(
      [
        booked,
        erection('DB-102', day, actualEnd: addDays(day, 1)),
        erection('DB-103', day, hullId: 'h2'),
        erection('HULL', day, hullLevel: true),
      ],
      [block('DB-101'), block('DB-102'), block('DB-103')],
      bookings: [booking('goliath', DateTime(2027, 3, 1, 7), DateTime(2027, 3, 1, 10), activityId: booked.id)],
    );
    expect(r.bookings, isEmpty);
    expect(r.warnings, isEmpty);
  });

  test('dry dock erections use the dock crane; missing cranes, overloads and past days are reported', () {
    final r = plan(
      [
        erection('DD-1', DateTime(2027, 4, 1), location: dock),
        erection('HEAVY', DateTime(2027, 4, 1)),
        erection('SHOP', DateTime(2027, 4, 1), location: 'NODE_A08_BLOCK_ASSEMBLY_HALL'),
        // Not started and overdue: forecast = today, but 09:00 + ... today still has room.
        erection('LATE', DateTime(2026, 11, 1), days: 1),
      ],
      [
        block('DD-1', weightKg: 120000),
        block('HEAVY', weightKg: 700000),
        block('SHOP', weightKg: 10000),
        block('LATE', weightKg: 10000),
      ],
    );
    expect(r.bookings.firstWhere((b) => b.title.contains('DD-1')).componentId, 'portal');
    expect(r.bookings.firstWhere((b) => b.title.contains('DD-1')).loadT, 120);
    final late = r.bookings.firstWhere((b) => b.title.contains('LATE'));
    expect(late.startsAt.isBefore(now), isFalse);
    expect(late.startsAt, DateTime(2026, 11, 17, 9));
    expect(r.warnings, hasLength(2));
    expect(r.warnings.first, contains('No crane at NODE_A08_BLOCK_ASSEMBLY_HALL'));
    expect(r.warnings.last, contains('HEAVY (700 t)'));
  });

  test('no free window inside the erection days is reported', () {
    final day = DateTime(2027, 5, 3);
    final r = plan(
      [erection('DB-101', day, days: 1)],
      [block('DB-101', weightKg: 50000)],
      bookings: [booking('goliath', DateTime(2027, 5, 3, 6), DateTime(2027, 5, 3, 16))],
    );
    expect(r.bookings, isEmpty);
    expect(r.warnings.single, contains('No free crane window'));
  });

  test('lift windows by weight and the insert row', () {
    expect(LiftPlan.liftDuration(null).inHours, 3);
    expect(LiftPlan.liftDuration(250).inHours, 4);
    expect(LiftPlan.liftDuration(450).inHours, 6);
    final r = plan([erection('DB-101', DateTime(2027, 1, 4))], [block('DB-101', weightKg: 85000)]);
    final row = ResourceBookingModel.insert(r.bookings.single);
    expect(row['status'], 'planned');
    expect(row['activity_id'], startsWith('a-DB-101'));
    expect(row['booking_type'], 'lift');
    expect(row['load_t'], 85);
  });

  group('syncLoads', () {
    ResourceBooking lift(
      ProductionActivity a,
      String craneId,
      DateTime start, {
      int hours = 3,
      double? loadT,
      BookingStatus status = BookingStatus.planned,
      String? notes = LiftPlan.noWeightNote,
    }) => ResourceBooking(
      id: 'lift-${a.id}',
      projectId: 'p',
      componentId: craneId,
      hullId: 'h1',
      activityId: a.id,
      title: '${a.name} lift',
      type: BookingType.lift,
      slot: 1,
      startsAt: start,
      endsAt: start.add(Duration(hours: hours)),
      loadT: loadT,
      status: status,
      notes: notes,
    );

    LiftSyncResult sync(
      List<ProductionActivity> activities,
      List<TwinComponent> blocks,
      List<ResourceBooking> bookings, {
      List<TwinComponent> extraCranes = const [],
      Map<String, double?> overrides = const {},
    }) => LiftPlan.syncLoads(
      hull: hull,
      activities: activities,
      components: [goliath, portal, quay, ...extraCranes, ...blocks],
      bookings: bookings,
      now: now,
      weightKgOverrides: overrides,
    );

    test('weights become the load; longer lifts keep their start or move to a free window', () {
      final day = DateTime(2027, 1, 4);
      final a1 = erection('DB-101', day);
      final a2 = erection('DB-102', day);
      final a3 = erection('DB-103', day);
      final r = sync(
        [a1, a2, a3],
        [block('DB-101'), block('DB-102', weightKg: 250000), block('DB-103')],
        [
          lift(a1, 'goliath', DateTime(2027, 1, 4, 7)),
          lift(a2, 'goliath', DateTime(2027, 1, 4, 10)),
          lift(a3, 'goliath', DateTime(2027, 1, 4, 13)),
        ],
        // DB-101 edited in the dialog, the component list has not reloaded yet.
        overrides: {'b-DB-101': 85000},
      );
      expect(r.warnings, isEmpty);
      // DB-103 has no weight and a 3 h window: nothing to change.
      expect(r.updates.map((u) => u.blockNo), ['DB-101', 'DB-102']);
      final first = r.updates.first;
      expect(first.loadT, 85);
      expect(first.startsAt, DateTime(2027, 1, 4, 7));
      expect(first.endsAt, DateTime(2027, 1, 4, 10));
      expect(first.notes, isNull);
      expect(first.movedStart || first.movedCrane, isFalse);
      // 250 t -> 4 h: 10:00-14:00 runs into DB-103 at 13:00, next free 4 h window is the next morning.
      final second = r.updates.last;
      expect(second.loadT, 250);
      expect(second.startsAt, DateTime(2027, 1, 5, 7));
      expect(second.endsAt, DateTime(2027, 1, 5, 11));
      expect(second.movedStart, isTrue);
      expect(second.componentId, 'goliath');
    });

    test('cleared weight restores the note; confirmed and past lifts are only reported', () {
      final a1 = erection('DB-101', DateTime(2027, 1, 4));
      final a2 = erection('DB-102', DateTime(2027, 1, 4));
      final a3 = erection('DB-103', DateTime(2026, 11, 16));
      final r = sync(
        [a1, a2, a3],
        [block('DB-101', weightKg: 50000), block('DB-102', weightKg: 90000), block('DB-103', weightKg: 40000)],
        [
          lift(a1, 'goliath', DateTime(2027, 1, 4, 7), loadT: 50, notes: null),
          lift(a2, 'goliath', DateTime(2027, 1, 4, 10), status: BookingStatus.confirmed),
          lift(a3, 'goliath', DateTime(2026, 11, 16, 7)),
        ],
        overrides: {'b-DB-101': null},
      );
      final u = r.updates.single;
      expect(u.blockNo, 'DB-101');
      expect(u.loadT, isNull);
      expect(u.notes, LiftPlan.noWeightNote);
      expect(u.startsAt, DateTime(2027, 1, 4, 7));
      expect(r.warnings.single, allOf(contains('DB-102'), contains('DB-103'), contains('confirmed')));
    });

    test('a block too heavy for the booked crane moves to a crane that carries it', () {
      final jib = comp('jib', 'crane', {'swl_t': 100, 'location': berth});
      final a1 = erection('DB-101', DateTime(2027, 1, 4));
      final a2 = erection('DB-102', DateTime(2027, 1, 4));
      final r = sync(
        [a1, a2],
        [block('DB-101', weightKg: 300000), block('DB-102', weightKg: 700000)],
        [lift(a1, 'jib', DateTime(2027, 1, 4, 9)), lift(a2, 'jib', DateTime(2027, 1, 4, 13))],
        extraCranes: [jib],
      );
      final u = r.updates.single;
      expect(u.componentId, 'goliath');
      expect(u.movedCrane, isTrue);
      expect(u.loadT, 300);
      expect(u.startsAt, DateTime(2027, 1, 4, 7));
      expect(u.endsAt, DateTime(2027, 1, 4, 11));
      expect(r.warnings.single, contains('DB-102 (700 t)'));
      final row = ResourceBookingModel.planUpdate(
        componentId: u.componentId,
        startsAt: u.startsAt,
        endsAt: u.endsAt,
        loadT: u.loadT,
        notes: u.notes,
      );
      expect(row['component_id'], 'goliath');
      expect(row['load_t'], 300);
      expect(row.containsKey('status'), isFalse);
    });
  });
}
