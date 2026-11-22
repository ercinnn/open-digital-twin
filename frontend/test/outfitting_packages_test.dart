import 'package:flutter_test/flutter_test.dart';
import 'package:open_digital_twin/features/shipyard/data/models/production_models.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/production_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/quality_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/services/draft_schedule.dart';
import 'package:open_digital_twin/features/shipyard/domain/services/inspection_plan.dart';
import 'package:open_digital_twin/features/shipyard/domain/services/outfitting_packages.dart';

const quay = 'NODE_A19_OUTFITTING_QUAY';

void main() {
  final today = DateTime(2026, 11, 16);
  Hull hull({String contractType = 'newbuild', DateTime? launching, DateTime? delivery}) => Hull(
    id: 'h4',
    projectId: 'p',
    hullNo: 'NB-1004',
    contractType: contractType,
    status: HullStatus.planned,
    metadata: const {},
    steelCuttingDate: DateTime(2027, 1, 16),
    keelLayingDate: DateTime(2027, 4, 16),
    launchingDate: launching ?? DateTime(2027, 8, 16),
    contractDeliveryDate: delivery ?? DateTime(2028, 1, 16),
  );
  final nb = hull();
  const departments = {'OUT': 'd-out', 'PNT': 'd-pnt'};

  List<ProductionActivity> stored(List<ActivityDraft> drafts) => [
    for (final (i, d) in drafts.indexed)
      ProductionActivity(
        id: 'a$i',
        projectId: 'p',
        hullId: d.hullId,
        componentId: d.componentId,
        code: d.code,
        name: d.name,
        stage: d.stage,
        locationNodeId: d.locationNodeId,
        plannedStart: d.plannedStart,
        plannedEnd: d.plannedEnd,
        progressPct: 0,
        sortOrder: d.sortOrder,
        workPackage: d.workPackage,
      ),
  ];

  /// The draft with a single generic outfitting row, as stored rows.
  final generic = stored(DraftSchedule.forHull(nb, today: today).activities);
  final genericRow = generic.singleWhere((a) => a.stage == ProductionStage.outfitting);

  test('package windows follow the template inside the outfitting window', () {
    final start = DateTime(2027, 8, 17), end = DateTime(2027, 12, 25); // 130 days
    final (s, e) = OutfittingPackages.windowOf(WorkPackage.painting, start, end);
    expect(s, DateTime(2027, 11, 16)); // 70 % = day 91
    expect(e, end);
    expect(OutfittingPackages.windowOf(WorkPackage.outfittingSteel, start, end).$1, start);
    // A very short window still gives every package one day.
    final short = OutfittingPackages.windowOf(WorkPackage.painting, start, DateTime(2027, 8, 18));
    expect(daysBetween(short.$1, short.$2), 1);
    expect(OutfittingPackages.template.keys, WorkPackage.values);
  });

  test('a generic outfitting row becomes the piping package, the others are inserted', () {
    final plan = OutfittingPackages.forHull(
      nb,
      generic,
      existingCodes: {for (final a in generic) a.code},
      firstSortOrder: 50,
      departmentIdByCode: departments,
    );
    expect(plan.isValid, isTrue, reason: plan.problems.join());
    expect(plan.start, genericRow.plannedStart);
    expect(plan.end, genericRow.plannedEnd);
    final c = plan.convert!;
    expect(c.row.id, genericRow.id);
    expect(c.draft.code, genericRow.code);
    expect(c.draft.workPackage, WorkPackage.piping);
    expect(c.draft.name, 'NB-1004 Piping systems');
    expect(plan.create, hasLength(6));
    expect(plan.create.map((a) => a.workPackage), isNot(contains(WorkPackage.piping)));
    expect(plan.create.first.code, 'NB1004-OUTFIT-OSTL');
    expect(plan.create.map((a) => a.sortOrder), [50, 51, 52, 53, 54, 55]);
    for (final a in plan.rows) {
      expect(a.validationErrors(), isEmpty, reason: a.code);
      expect(a.stage, ProductionStage.outfitting);
      expect(a.locationNodeId, quay);
      expect(a.componentId, isNull);
      expect(a.plannedStart.isBefore(plan.start!), isFalse, reason: a.code);
      expect(a.plannedEnd.isAfter(plan.end!), isFalse, reason: a.code);
      expect(a.departmentId, a.workPackage == WorkPackage.painting ? 'd-pnt' : 'd-out');
    }
    expect(plan.rows.first, same(c.draft));
  });

  test('repeating plans only the packages still missing, in the same window', () {
    final first = OutfittingPackages.forHull(nb, generic, existingCodes: {for (final a in generic) a.code});
    final half = first.create.take(3).toList();
    final afterwards = [
      for (final a in generic)
        if (a.id != genericRow.id) a,
      ...stored([first.convert!.draft, ...half]).map(
        (a) => ProductionActivity(
          id: 'p-${a.code}',
          projectId: a.projectId,
          hullId: a.hullId,
          code: a.code,
          name: a.name,
          stage: a.stage,
          plannedStart: a.plannedStart,
          plannedEnd: a.plannedEnd,
          progressPct: 0,
          sortOrder: a.sortOrder,
          locationNodeId: a.locationNodeId,
          workPackage: a.workPackage,
        ),
      ),
    ];
    final again = OutfittingPackages.forHull(nb, afterwards, existingCodes: {for (final a in afterwards) a.code});
    expect(again.isValid, isTrue);
    expect(again.convert, isNull);
    expect(again.create.map((a) => a.workPackage), [
      WorkPackage.electrical,
      WorkPackage.accommodation,
      WorkPackage.painting,
    ]);
    // The window is recovered from the piping package (rounding: a day at most).
    expect(daysBetween(genericRow.plannedStart, again.start!).abs(), lessThanOrEqualTo(1));
    expect(daysBetween(genericRow.plannedEnd, again.end!).abs(), lessThanOrEqualTo(1));
    for (final (i, a) in again.create.indexed) {
      expect(daysBetween(first.create[3 + i].plannedStart, a.plannedStart).abs(), lessThanOrEqualTo(1));
      expect(daysBetween(first.create[3 + i].plannedEnd, a.plannedEnd).abs(), lessThanOrEqualTo(1));
    }

    final all = [...afterwards, ...stored(again.create)];
    final done = OutfittingPackages.forHull(nb, all);
    expect(done.isValid, isFalse);
    expect(done.problems.single, contains('already planned'));
  });

  test('a started or finished generic row is not split; repairs have no packages', () {
    final started = [
      for (final a in generic) a.id == genericRow.id ? a.copyWith(actualStart: DateTime(2027, 8, 17)) : a,
    ];
    expect(OutfittingPackages.forHull(nb, started).problems.single, contains('already started'));
    final finished = [for (final a in started) a.id == genericRow.id ? a.copyWith(actualEnd: DateTime(2027, 9, 1)) : a];
    expect(OutfittingPackages.forHull(nb, finished).problems.single, contains('finished'));
    expect(OutfittingPackages.forHull(hull(contractType: 'repair'), generic).isValid, isFalse);
  });

  test('without an outfitting row the window starts after launching; too short windows are refused', () {
    final noOutfitting = [
      for (final a in generic)
        if (a.stage != ProductionStage.outfitting) a,
    ];
    final plan = OutfittingPackages.forHull(nb, noOutfitting);
    expect(plan.isValid, isTrue);
    expect(plan.convert, isNull);
    expect(plan.create, hasLength(WorkPackage.values.length));
    final (o0, o1) = DraftSchedule.outfittingWindow(nb.launchingDate!, nb.contractDeliveryDate!);
    expect(plan.start, o0);
    expect(plan.end, o1);

    final tight = hull(launching: DateTime(2027, 8, 16), delivery: DateTime(2027, 8, 24));
    final r = OutfittingPackages.forHull(tight, const []);
    expect(r.isValid, isFalse);
    expect(r.problems.single, contains('shorter than'));
  });

  test('the draft schedule can split the afloat outfitting into packages', () {
    final r = DraftSchedule.forHull(nb, today: today, outfittingPackages: true, departmentIdByCode: departments);
    expect(r.isValid, isTrue);
    expect(r.activities, hasLength(12 - 1 + WorkPackage.values.length));
    final packages = r.activities.where((a) => a.workPackage != null).toList();
    expect(packages.map((a) => a.workPackage), WorkPackage.values);
    expect(packages.every((a) => a.stage == ProductionStage.outfitting), isTrue);
    expect(r.activities.where((a) => a.stage == ProductionStage.outfitting && a.workPackage == null), isEmpty);
    // Sort orders and codes stay consecutive / unique.
    expect([for (final a in r.activities) a.sortOrder], List.generate(r.activities.length, (i) => i + 1));
    expect({for (final a in r.activities) a.code}, hasLength(r.activities.length));
    final (o0, o1) = DraftSchedule.outfittingWindow(nb.launchingDate!, nb.contractDeliveryDate!);
    expect(packages.first.plannedStart, o0);
    expect(packages.map((a) => a.plannedEnd).reduce((a, b) => a.isAfter(b) ? a : b), o1);
  });

  test('work package rows are stored with their package and department', () {
    final d = OutfittingPackages.rows(
      nb,
      DateTime(2027, 8, 17),
      DateTime(2027, 10, 1),
      packages: const [WorkPackage.painting],
      codes: {},
      firstSortOrder: 1,
      departmentIdByCode: departments,
    ).single;
    final row = ProductionActivityModel.insert(d);
    expect(row['work_package'], 'painting');
    expect(row['department_id'], 'd-pnt');
    expect(row['activity_code'], 'NB1004-OUTFIT-PNT');
    final read = ProductionActivityModel.fromJson({...row, 'id': 'x', 'progress_pct': 0});
    expect(read.workPackage, WorkPackage.painting);
    // A plan update without department keeps the row's department.
    final plain = ActivityDraft(
      projectId: 'p',
      hullId: 'h4',
      code: 'X',
      name: 'X',
      stage: ProductionStage.outfitting,
      plannedStart: DateTime(2027),
      plannedEnd: DateTime(2027, 1, 2),
    );
    expect(ProductionActivityModel.planUpdate(plain).containsKey('department_id'), isFalse);
    expect(ProductionActivityModel.planUpdate(plain)['work_package'], isNull);
    expect(
      ActivityDraft(
        projectId: 'p',
        hullId: 'h4',
        code: 'X',
        name: 'X',
        stage: ProductionStage.commissioning,
        plannedStart: DateTime(2027),
        plannedEnd: DateTime(2027, 1, 2),
        workPackage: WorkPackage.piping,
      ).validationErrors(),
      hasLength(1),
    );
  });

  test('each package gets its own ITP point; the pressure test goes to piping only', () {
    final rows = stored(DraftSchedule.forHull(nb, today: today, outfittingPackages: true).activities);
    final nodes = {for (final n in stageDefaultLocations.values.whereType<String>()) n: 'c-$n'};
    final plan = InspectionPlan.fromSchedule(hull: nb, activities: rows, componentIdByNode: nodes);
    final outfittingIds = {
      for (final a in rows)
        if (a.stage == ProductionStage.outfitting) a.id: a.workPackage,
    };
    final points = plan.where((q) => outfittingIds.containsKey(q.activityId)).toList();
    expect(points, hasLength(WorkPackage.values.length));
    expect({for (final q in points) outfittingIds[q.activityId]}, WorkPackage.values.toSet());
    final pressure = points.where((q) => q.type == InspectionType.pressureTest).single;
    expect(outfittingIds[pressure.activityId], WorkPackage.piping);
    expect(pressure.holdPoint, isTrue);
    // Witness only: outfitting steel and electrical; the others are hold points.
    expect(
      {for (final q in points.where((q) => !q.holdPoint)) outfittingIds[q.activityId]},
      {WorkPackage.outfittingSteel, WorkPackage.electrical},
    );
    // Points of one package only (package dialog).
    final one = InspectionPlan.fromSchedule(
      hull: nb,
      activities: rows,
      componentIdByNode: nodes,
      activityId: rows.firstWhere((a) => a.workPackage == WorkPackage.machinery).id,
    );
    expect(one.single.description, 'NB-1004 Shaft alignment & main engine chocking');
    expect(one.single.componentId, 'c-$quay');
  });
}
