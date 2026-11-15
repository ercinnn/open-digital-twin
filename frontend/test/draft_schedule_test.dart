import 'package:flutter_test/flutter_test.dart';
import 'package:open_digital_twin/features/shipyard/data/models/production_models.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/production_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/services/draft_schedule.dart';

void main() {
  final today = DateTime(2026, 11, 16);

  Hull hull({
    String contractType = 'newbuild',
    DateTime? contract,
    DateTime? cutting,
    DateTime? keel,
    DateTime? launching,
    DateTime? delivery,
    String? location,
  }) => Hull(
    id: 'h4',
    projectId: 'p',
    hullNo: 'NB-1004',
    contractType: contractType,
    status: HullStatus.planned,
    metadata: const {},
    contractDate: contract,
    steelCuttingDate: cutting,
    keelLayingDate: keel,
    launchingDate: launching,
    contractDeliveryDate: delivery,
    locationNodeId: location,
  );

  final newbuild = hull(
    contract: DateTime(2026, 11, 16),
    cutting: DateTime(2027, 1, 16),
    keel: DateTime(2027, 4, 16),
    launching: DateTime(2027, 8, 16),
    delivery: DateTime(2028, 1, 16),
  );

  group('activityCodeFor', () {
    test('builds codes from the hull number and keeps them unique', () {
      expect(activityCodeFor('NB-1004', ProductionStage.cutting, {}), 'NB1004-CUT');
      expect(activityCodeFor('nb-1004', ProductionStage.cutting, {'NB1004-CUT'}), 'NB1004-CUT-2');
      expect(activityCodeFor('NB-1004', ProductionStage.cutting, {'NB1004-CUT', 'nb1004-cut-2'}), 'NB1004-CUT-3');
    });
  });

  group('DraftSchedule.forHull', () {
    test('a newbuild gets 12 ordered, valid hull-level rows', () {
      final r = DraftSchedule.forHull(newbuild, today: today, firstSortOrder: 74);
      expect(r.isValid, isTrue);
      expect(r.activities, hasLength(12));
      expect(r.activities.map((a) => a.stage).toSet(), hasLength(12));
      for (final a in r.activities) {
        expect(a.validationErrors(), isEmpty, reason: a.code);
        expect(a.plannedDays, greaterThanOrEqualTo(1), reason: a.code);
        expect(a.hullId, 'h4');
        expect(a.componentId, isNull);
        expect(a.name, startsWith('NB-1004 '));
      }
      expect(r.activities.first.sortOrder, 74);
      expect(r.activities.last.sortOrder, 85);
      expect({for (final a in r.activities) a.code}, hasLength(12));
    });

    test('milestones anchor the stages', () {
      final rows = {for (final a in DraftSchedule.forHull(newbuild, today: today).activities) a.stage: a};
      expect(rows[ProductionStage.cutting]!.plannedStart, newbuild.steelCuttingDate);
      expect(rows[ProductionStage.erection]!.plannedStart, newbuild.keelLayingDate);
      expect(rows[ProductionStage.erection]!.plannedEnd, newbuild.launchingDate);
      expect(rows[ProductionStage.launching]!.plannedStart, newbuild.launchingDate);
      expect(rows[ProductionStage.delivery]!.plannedEnd, newbuild.contractDeliveryDate);
      expect(rows[ProductionStage.erection]!.locationNodeId, 'NODE_A16_BUILDING_BERTH');
      expect(rows[ProductionStage.seaTrials]!.locationNodeId, isNull);
      // Steel work finishes before launching, afloat work before delivery.
      for (final s in [ProductionStage.cutting, ProductionStage.blockAssembly, ProductionStage.preOutfitting]) {
        expect(rows[s]!.plannedEnd.isBefore(newbuild.launchingDate!), isTrue, reason: s.name);
      }
      expect(rows[ProductionStage.seaTrials]!.plannedEnd.isAfter(newbuild.contractDeliveryDate!), isFalse);
    });

    test('keel laying defaults to 45 % of the build window when missing', () {
      final h = hull(cutting: DateTime(2027, 1, 1), launching: DateTime(2027, 11, 28), delivery: DateTime(2028, 4, 1));
      final erection = DraftSchedule.forHull(h, today: today).activities.firstWhere(
        (a) => a.stage == ProductionStage.erection,
      );
      // 331-day build window x 0.45 = 149 days after steel cutting.
      expect(erection.plannedStart, DateTime(2027, 5, 30));
    });

    test('reports the missing milestones', () {
      final r = DraftSchedule.forHull(hull(), today: today);
      expect(r.isValid, isFalse);
      expect(r.problems, [
        'Enter the steel cutting date.',
        'Enter the launching date.',
        'Enter the contract delivery date.',
      ]);
    });

    test('rejects windows that are too short or a keel outside the build window', () {
      final short = hull(cutting: DateTime(2027, 1, 1), launching: DateTime(2027, 1, 20), delivery: DateTime(2027, 1, 25));
      expect(DraftSchedule.forHull(short, today: today).problems, hasLength(2));
      final badKeel = hull(
        cutting: DateTime(2027, 1, 1),
        keel: DateTime(2026, 12, 1),
        launching: DateTime(2027, 6, 1),
        delivery: DateTime(2027, 12, 1),
      );
      expect(DraftSchedule.forHull(badKeel, today: today).problems, ['Keel laying must lie between steel cutting and launching.']);
    });

    test('avoids codes that already exist in the project', () {
      final r = DraftSchedule.forHull(newbuild, today: today, existingCodes: {'NB1004-CUT'});
      expect(r.activities.first.code, 'NB1004-CUT-2');
    });

    test('a repair gets one docking row at its dock, starting today at the earliest', () {
      final r = DraftSchedule.forHull(
        hull(
          contractType: 'repair',
          contract: DateTime(2026, 11, 1),
          delivery: DateTime(2026, 12, 10),
          location: 'NODE_A18_FLOATING_DOCK',
        ),
        today: today,
      );
      expect(r.isValid, isTrue);
      final a = r.activities.single;
      expect(a.stage, ProductionStage.dockingRepair);
      expect(a.plannedStart, today);
      expect(a.plannedEnd, DateTime(2026, 12, 10));
      expect(a.locationNodeId, 'NODE_A18_FLOATING_DOCK');
    });
  });

  group('ActivityDraft', () {
    final draft = ActivityDraft(
      projectId: 'p',
      hullId: 'h4',
      code: 'NB1004-CUT',
      name: ' NB-1004 Plate & profile cutting ',
      stage: ProductionStage.cutting,
      plannedStart: DateTime(2027, 1, 16),
      plannedEnd: DateTime(2027, 6, 1),
      locationNodeId: 'NODE_A05_CNC_CUTTING_SHOP',
      sortOrder: 74,
      notes: '  ',
    );

    test('validation', () {
      expect(draft.validationErrors(), isEmpty);
      final bad = ActivityDraft(
        projectId: 'p',
        hullId: null,
        code: '',
        name: ' ',
        stage: ProductionStage.cutting,
        plannedStart: DateTime(2027, 2, 1),
        plannedEnd: DateTime(2027, 1, 1),
      );
      expect(bad.validationErrors(), hasLength(3));
    });

    test('insert row and plan update', () {
      final row = ProductionActivityModel.insert(draft);
      expect(row['activity_code'], 'NB1004-CUT');
      expect(row['hull_id'], 'h4');
      expect(row['name'], 'NB-1004 Plate & profile cutting');
      expect(row['stage'], 'cutting');
      expect(row['planned_start'], '2027-01-16');
      expect(row['planned_end'], '2027-06-01');
      expect(row['notes'], isNull);
      expect(row['sort_order'], 74);
      final update = ProductionActivityModel.planUpdate(draft);
      for (final key in ['activity_code', 'project_id', 'progress_pct', 'actual_start', 'actual_end']) {
        expect(update.containsKey(key), isFalse, reason: key);
      }
    });
  });
}
