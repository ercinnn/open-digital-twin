import 'package:flutter_test/flutter_test.dart';
import 'package:open_digital_twin/features/shipyard/data/models/production_models.dart';
import 'package:open_digital_twin/features/shipyard/data/models/slot_models.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/production_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/slot_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/services/production_schedule.dart';
import 'package:open_digital_twin/features/shipyard/domain/services/slot_plan.dart';

const hall = 'NODE_A08_BLOCK_ASSEMBLY_HALL';
const paint = 'NODE_A10_BLOCK_BLASTING_PAINT_HALL';

AreaSlot slot(String area, int no, {double? maxT}) => AreaSlot(
  id: '$area-$no',
  projectId: 'p',
  componentId: area,
  slotNo: no,
  code: '${area.substring(5, 8)}-0$no',
  centerX: 400.0 + no * 40,
  centerY: 350,
  sizeX: 36,
  sizeY: 40,
  maxLoadT: maxT,
);

ProductionActivity row(
  String id,
  String block,
  String area,
  DateTime start,
  int days, {
  ProductionStage stage = ProductionStage.blockAssembly,
  String hull = 'h1',
  int? slotNo,
  bool started = false,
  bool done = false,
}) => ProductionActivity(
  id: id,
  projectId: 'p',
  hullId: hull,
  componentId: block,
  code: id,
  name: id,
  stage: stage,
  locationNodeId: area,
  plannedStart: start,
  plannedEnd: addDays(start, days),
  actualStart: started || done ? start : null,
  actualEnd: done ? addDays(start, days) : null,
  progressPct: done ? 100 : 0,
  sortOrder: 1,
  slotNo: slotNo,
);

void main() {
  final d0 = DateTime(2027, 3, 1);
  // Area ids are mesh ids here (componentId -> mesh id is the identity).
  AreaSlots slots(List<AreaSlot> list) => AreaSlots(list, {for (final s in list) s.componentId: s.componentId});

  test('area slots are grouped by area mesh id and ordered by number', () {
    final s = AreaSlots([slot(hall, 2), slot(hall, 1), slot(paint, 1)], {hall: hall, paint: paint});
    expect(s.of(hall).map((x) => x.slotNo), [1, 2]);
    expect(s.find(hall, 2)!.code, 'A08-02');
    expect(s.find(hall, 9), isNull);
    expect(s.find(hall, null), isNull);
    expect(s.of('NODE_A16_BUILDING_BERTH'), isEmpty);
    expect(slot(hall, 1, maxT: 50).carries(60), isFalse);
    expect(slot(hall, 1, maxT: 50).carries(null), isTrue);
  });

  test('a block holds its slot until its next row starts', () {
    final a = row('a', 'b1', hall, d0, 5);
    final next = row('p', 'b1', paint, addDays(d0, 8), 3, stage: ProductionStage.blastingPainting);
    expect(SlotPlan.stayOf(a, [next, a]), (d0, addDays(d0, 8)));
    expect(SlotPlan.stayOf(next, [next, a]), (addDays(d0, 8), addDays(d0, 11)));
  });

  test('rows take the lowest free slot for their whole stay, in start order', () {
    final s = slots([slot(hall, 1), slot(hall, 2), slot(hall, 3)]);
    final acts = [
      row('b1-asm', 'b1', hall, d0, 5),
      row('b1-paint', 'b1', paint, addDays(d0, 10), 3, stage: ProductionStage.blastingPainting),
      row('b2-asm', 'b2', hall, addDays(d0, 7), 3), // b1 still waits on slot 1 until day 10
      row('b3-asm', 'b3', hall, addDays(d0, 12), 3), // slot 1 free again
    ];
    final plan = SlotPlan.forHull(hullId: 'h1', activities: acts, slots: s);
    expect({for (final a in plan.assignments) a.row.id: a.slot.slotNo}, {'b1-asm': 1, 'b2-asm': 2, 'b3-asm': 1});
    expect(plan.assignments.any((a) => a.waitOverlap), isFalse);
    expect(plan.clears, isEmpty);
    expect(plan.issues, isEmpty);
    expect(plan.countsByArea(), {hall: 3});
  });

  test('kept slots of other hulls count; a full area falls back to the work window, then reports', () {
    final s = slots([slot(hall, 1)]);
    final acts = [
      row('x-asm', 'x1', hall, d0, 4, hull: 'h2', slotNo: 1),
      // h1 block works after x1 but before x1's next row -> only the work window is free
      row('x-paint', 'x1', paint, addDays(d0, 9), 2, hull: 'h2', stage: ProductionStage.blastingPainting),
      row('b1-asm', 'b1', hall, addDays(d0, 5), 3),
      row('b2-asm', 'b2', hall, addDays(d0, 6), 3), // overlaps b1's work window
    ];
    final plan = SlotPlan.forHull(hullId: 'h1', activities: acts, slots: s);
    expect(plan.assignments.single.row.id, 'b1-asm');
    expect(plan.assignments.single.waitOverlap, isTrue);
    expect(plan.issues.single.row.id, 'b2-asm');
    expect(plan.issues.single.message, contains('all 1 slots of A08 are taken'));
  });

  test('heavy blocks skip weak slots; none strong enough is reported', () {
    final s = slots([slot(hall, 1, maxT: 20), slot(hall, 2, maxT: 80)]);
    final acts = [row('heavy', 'b1', hall, d0, 3), row('too-heavy', 'b2', hall, d0, 3)];
    final plan = SlotPlan.forHull(hullId: 'h1', activities: acts, slots: s, weightsT: {'b1': 45, 'b2': 120});
    expect(plan.assignments.single.slot.slotNo, 2);
    expect(plan.issues.single.message, 'no slot of A08 carries 120.0 t');
  });

  test('existing slots stay; re-planning frees only not started rows; finished rows are left alone', () {
    final s = slots([slot(hall, 1), slot(hall, 2)]);
    final acts = [
      row('running', 'b1', hall, d0, 10, slotNo: 2, started: true),
      row('planned', 'b2', hall, addDays(d0, 2), 3, slotNo: 1),
      row('done', 'b3', hall, addDays(d0, -10), 3, done: true),
      row('new', 'b4', hall, addDays(d0, 6), 2),
      row('berth', 'b5', 'NODE_A16_BUILDING_BERTH', d0, 2, stage: ProductionStage.erection),
    ];
    final keep = SlotPlan.forHull(hullId: 'h1', activities: acts, slots: s);
    expect(keep.clears, isEmpty);
    expect(keep.assignments.map((a) => (a.row.id, a.slot.slotNo)), [('new', 1)]);

    final again = SlotPlan.forHull(hullId: 'h1', activities: acts, slots: s, reassign: true);
    expect(again.clears.map((a) => a.id), ['planned']);
    expect(again.assignments.map((a) => (a.row.id, a.slot.slotNo)), [('planned', 1), ('new', 1)]);
  });

  test('placement: a block at an area stands on its row slot; the viewer payload carries it', () {
    final s = slots([slot(hall, 3)]);
    final acts = [row('asm', 'b1', hall, d0, 5, slotNo: 3)];
    final schedule = ProductionSchedule(acts);
    final p = schedule.placementsAt(addDays(d0, 1), d0, slots: s)['b1']!;
    expect(p.kind, PlacementKind.area);
    expect(p.slot!.code, 'A08-03');
    expect(p.toViewerJson(), {
      'mode': 'area',
      'area': hall,
      'ghost': false,
      'slot': {'x': 520.0, 'y': 350.0, 'sx': 36.0, 'sy': 40.0, 'code': 'A08-03'},
    });
    // Without slots (or without a slot number) the viewer lines the block up.
    expect(schedule.placementsAt(addDays(d0, 1), d0)['b1']!.toViewerJson().containsKey('slot'), isFalse);
    expect(p == schedule.placementsAt(addDays(d0, 1), d0)['b1'], isFalse);
  });

  test('models read the slot columns', () {
    final s = AreaSlotModel.fromJson({
      'id': 's',
      'project_id': 'p',
      'component_id': 'c',
      'slot_no': 4,
      'code': 'A08-04',
      'center_x_m': '580',
      'center_y_m': 352.5,
      'size_x_m': 36,
      'size_y_m': 40,
      'max_load_t': '200',
      'notes': 'Bay 4',
    });
    expect((s.slotNo, s.centerX, s.centerY, s.maxLoadT), (4, 580.0, 352.5, 200.0));
    final a = ProductionActivityModel.fromJson({
      'id': 'a',
      'project_id': 'p',
      'activity_code': 'X',
      'name': 'X',
      'stage': 'block_assembly',
      'planned_start': '2027-03-01',
      'planned_end': '2027-03-04',
      'slot_no': 4,
    });
    expect(a.slotNo, 4);
    expect(a.copyWith(progressPct: 10).slotNo, 4);
  });
}
