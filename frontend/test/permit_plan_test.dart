import 'package:flutter_test/flutter_test.dart';
import 'package:open_digital_twin/features/shipyard/data/models/hse_models.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/block_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/hse_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/production_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/quality_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/resource_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/services/permit_plan.dart';

HullBlock block(String no, String type) => HullBlock(
  componentId: 'b-$no',
  meshNodeId: 'NODE_NB1001_BLOCK_${no.replaceAll('-', '_')}',
  hullNo: 'NB-1001',
  blockNo: no,
  name: 'Block $no',
  side: BlockSide.centre,
  erectionSequence: 1,
  type: BlockType.byCode(type),
);

ProductionActivity row(
  String id,
  String blockNo,
  ProductionStage stage,
  DateTime start,
  int days, {
  DateTime? actualStart,
  DateTime? actualEnd,
}) => ProductionActivity(
  id: id,
  projectId: 'p',
  hullId: 'h1',
  componentId: 'b-$blockNo',
  code: id,
  name: 'NB-1001 $blockNo ${stage.label}',
  stage: stage,
  locationNodeId: 'NODE_A16_BUILDING_BERTH',
  plannedStart: start,
  plannedEnd: addDays(start, days),
  actualStart: actualStart,
  actualEnd: actualEnd,
  progressPct: 0,
  sortOrder: 0,
);

WorkPermit permit(String activityId, PermitType type, DateTime from, {PermitStatus status = PermitStatus.approved}) =>
    WorkPermit(
      id: 'w-$activityId-${type.name}',
      componentId: 'b-DB-101',
      activityId: activityId,
      permitNo: 'PTW-2611-101',
      type: type,
      description: 'x',
      status: status,
      validFrom: from,
      validTo: from.add(const Duration(hours: 10)),
      position: MarkerPosition.top,
    );

void main() {
  final now = DateTime(2027, 1, 4, 9, 30);
  final today = dateOnly(now);

  test('permit types by stage; tank blocks add confined space; workshop stages need none', () {
    final db = BlockType.byCode('DB');
    final dk = BlockType.byCode('DK');
    expect(PermitPlan.typesFor(ProductionStage.cutting, db), isEmpty);
    expect(PermitPlan.typesFor(ProductionStage.panel, db), isEmpty);
    expect(PermitPlan.typesFor(ProductionStage.blockAssembly, dk), isEmpty);
    expect(PermitPlan.typesFor(ProductionStage.blockAssembly, db), [PermitType.confinedSpace]);
    expect(PermitPlan.typesFor(ProductionStage.blastingPainting, dk), [PermitType.painting]);
    expect(PermitPlan.typesFor(ProductionStage.preOutfitting, dk), [PermitType.hotWork]);
    expect(PermitPlan.typesFor(ProductionStage.erection, dk), [
      PermitType.lifting,
      PermitType.hotWork,
      PermitType.workAtHeight,
    ]);
    expect(PermitPlan.typesFor(ProductionStage.erection, db), contains(PermitType.confinedSpace));
  });

  group('forBlock', () {
    final b = block('DB-101', 'DB');
    final rows = [
      row('cut', 'DB-101', ProductionStage.cutting, addDays(today, -20), 5, actualEnd: addDays(today, -15)),
      row('asm', 'DB-101', ProductionStage.blockAssembly, addDays(today, -3), 10),
      row('pnt', 'DB-101', ProductionStage.blastingPainting, addDays(today, 6), 4),
      row('erect', 'DB-101', ProductionStage.erection, addDays(today, 20), 4),
      row('other', 'DB-102', ProductionStage.blockAssembly, today, 4),
    ];

    test('running rows and rows starting within 7 days; finished and later rows are left out', () {
      final needs = PermitPlan.forBlock(block: b, activities: rows, permits: const [], now: now);
      expect(needs.map((n) => (n.activity.id, n.type)), [
        ('asm', PermitType.confinedSpace),
        ('pnt', PermitType.painting),
        ('pnt', PermitType.confinedSpace),
      ]);
      expect(needs.every((n) => !n.covered), isTrue);
    });

    test('a current permit of the same row and type covers the need; closed or over ones do not', () {
      final needs = PermitPlan.forBlock(
        block: b,
        activities: rows,
        permits: [
          permit('asm', PermitType.confinedSpace, DateTime(2027, 1, 4, 7)),
          permit('pnt', PermitType.painting, DateTime(2027, 1, 4, 7), status: PermitStatus.closed),
          permit('pnt', PermitType.confinedSpace, DateTime(2027, 1, 3, 7)), // ended yesterday 17:00
        ],
        now: now,
      );
      expect(needs.where((n) => n.covered).map((n) => n.activity.id), ['asm']);
    });

    test('a row reported running stays listed even when its plan is over', () {
      final late = row(
        'late',
        'DB-101',
        ProductionStage.preOutfitting,
        addDays(today, -30),
        5,
        actualStart: addDays(today, -30),
      );
      final needs = PermitPlan.forBlock(block: b, activities: [late], permits: const [], now: now);
      expect(needs.single.type, PermitType.hotWork);
    });
  });

  group('suggest', () {
    final b = block('DK-401', 'DK');

    test('a lifting permit takes the booked crane lift of the row', () {
      final erect = row('erect', 'DK-401', ProductionStage.erection, addDays(today, 2), 4);
      final need = PermitNeed(activity: erect, type: PermitType.lifting, permits: const []);
      final lift = ResourceBooking(
        id: 'l1',
        projectId: 'p',
        componentId: 'crane',
        activityId: 'erect',
        title: 'lift',
        type: BookingType.lift,
        slot: 1,
        startsAt: DateTime(2027, 1, 6, 7),
        endsAt: DateTime(2027, 1, 6, 10),
        status: BookingStatus.planned,
      );
      final s = PermitPlan.suggest(need: need, block: b, bookings: [lift], now: now);
      expect((s.validFrom, s.hours), (DateTime(2027, 1, 6, 7), 3));
      expect(s.description, 'NB-1001 DK-401 erection: lifting (crane lift)');
      // Without a lift: the first day shift of the row.
      final none = PermitPlan.suggest(need: need, block: b, bookings: const [], now: now);
      expect((none.validFrom, none.hours), (DateTime(2027, 1, 6, 7), 10));
    });

    test('a running row: from the next full hour to the end of the day shift, else tomorrow', () {
      final asm = row('pre', 'DK-401', ProductionStage.preOutfitting, addDays(today, -1), 4);
      final need = PermitNeed(activity: asm, type: PermitType.hotWork, permits: const []);
      final s = PermitPlan.suggest(need: need, block: b, bookings: const [], now: now);
      expect((s.validFrom, s.hours), (DateTime(2027, 1, 4, 10), 7));
      final evening = PermitPlan.suggest(need: need, block: b, bookings: const [], now: DateTime(2027, 1, 4, 16, 30));
      expect((evening.validFrom, evening.hours), (DateTime(2027, 1, 5, 7), 10));
      final early = PermitPlan.suggest(need: need, block: b, bookings: const [], now: DateTime(2027, 1, 4, 5));
      expect((early.validFrom, early.hours), (DateTime(2027, 1, 4, 7), 10));
    });
  });

  test('permit rows carry the schedule row', () {
    final draft = PermitDraft(
      projectId: 'p',
      componentId: 'b1',
      activityId: 'a1',
      permitNo: 'ptw-2701-101',
      type: PermitType.lifting,
      description: 'Erection lift',
      validFrom: DateTime(2027, 1, 6, 7),
      validTo: DateTime(2027, 1, 6, 10),
    );
    expect(WorkPermitModel.insert(draft)['activity_id'], 'a1');
    final p = WorkPermitModel.fromJson({
      'id': 'w1',
      'component_id': 'b1',
      'activity_id': 'a1',
      'permit_no': 'PTW-2701-101',
      'permit_type': 'lifting',
      'description': 'x',
      'status': 'requested',
      'valid_from': '2027-01-06T04:00:00Z',
      'valid_to': '2027-01-06T07:00:00Z',
    });
    expect(p.activityId, 'a1');
    expect(p.isCurrent(DateTime.utc(2027, 1, 6, 5)), isTrue);
    expect(p.isCurrent(DateTime.utc(2027, 1, 6, 8)), isFalse);
  });
}
