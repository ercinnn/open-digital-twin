import 'package:flutter_test/flutter_test.dart';
import 'package:open_digital_twin/features/shipyard/data/models/quality_models.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/production_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/quality_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/services/draft_schedule.dart';
import 'package:open_digital_twin/features/shipyard/domain/services/inspection_plan.dart';

void main() {
  final today = DateTime(2026, 11, 16);
  final hull = Hull(
    id: 'h4',
    projectId: 'p',
    hullNo: 'NB-1004',
    contractType: 'newbuild',
    status: HullStatus.planned,
    metadata: const {},
    steelCuttingDate: DateTime(2027, 1, 16),
    keelLayingDate: DateTime(2027, 4, 16),
    launchingDate: DateTime(2027, 8, 16),
    contractDeliveryDate: DateTime(2028, 1, 16),
  );

  /// The 12-row draft schedule of NB-1004 as stored rows.
  final activities = [
    for (final (i, d) in DraftSchedule.forHull(hull, today: today).activities.indexed)
      ProductionActivity(
        id: 'a$i',
        projectId: 'p',
        hullId: d.hullId,
        code: d.code,
        name: d.name,
        stage: d.stage,
        locationNodeId: d.locationNodeId,
        plannedStart: d.plannedStart,
        plannedEnd: d.plannedEnd,
        progressPct: 0,
        sortOrder: d.sortOrder,
      ),
  ];
  final nodes = {for (final n in stageDefaultLocations.values.whereType<String>()) n: 'c-$n'};

  group('nextInspectionReference', () {
    test('uses the hull digits and continues the highest number', () {
      expect(nextInspectionReference('NB-1004', const []), 'QI-1004-0001');
      expect(nextInspectionReference('NB-1001', ['QI-1001-0412', 'qi-1001-0501', 'QI-2611-0012']), 'QI-1001-0502');
      expect(nextInspectionReference('NB-1004', const [], offset: 2), 'QI-1004-0003');
    });
  });

  group('InspectionPlan.fromSchedule', () {
    final plan = InspectionPlan.fromSchedule(
      hull: hull,
      activities: activities,
      componentIdByNode: nodes,
      fallbackComponentId: 'c-quay',
    );

    test('plans the hold / witness points of every stage with a template', () {
      // cutting 1, panel 1, block assembly 2, coating 1, pre-outfitting 1, erection 2,
      // launching 1, outfitting 1, commissioning 1, sea trials 1 = 12 (bending / delivery: none)
      expect(plan, hasLength(12));
      expect(plan.map((d) => d.referenceNo).toSet(), hasLength(12));
      expect(plan.first.referenceNo, 'QI-1004-0001');
      expect(plan.every((d) => d.hullId == 'h4' && d.validationErrors().isEmpty), isTrue);
    });

    test('is ordered by planned time on the last day of the activity, 10:00', () {
      for (var i = 1; i < plan.length; i++) {
        expect(plan[i].plannedAt.isBefore(plan[i - 1].plannedAt), isFalse);
      }
      final cutting = activities.firstWhere((a) => a.stage == ProductionStage.cutting);
      expect(plan.first.plannedAt, DateTime(cutting.plannedEnd.year, cutting.plannedEnd.month, cutting.plannedEnd.day, 10));
    });

    test('uses the type presets and pins to the activity area or the fallback', () {
      final dft = plan.firstWhere((d) => d.type == InspectionType.coatingDft);
      expect((dft.unit, dft.acceptanceMin, dft.acceptanceMax), ('um', 250.0, 450.0));
      expect(dft.componentId, 'c-NODE_A10_BLOCK_BLASTING_PAINT_HALL');
      final ut = plan.firstWhere((d) => d.type == InspectionType.ndtUt);
      expect(ut.acceptanceMin, isNull);
      expect(ut.witnessedBy, 'Class surveyor');
      final trials = plan.firstWhere((d) => d.description!.contains('Sea trials'));
      expect(trials.componentId, 'c-quay');
    });

    test('continues existing references and skips activities of other hulls', () {
      final again = InspectionPlan.fromSchedule(
        hull: hull,
        activities: [
          ...activities,
          ProductionActivity(
            id: 'x',
            projectId: 'p',
            hullId: 'other',
            code: 'X',
            name: 'X',
            stage: ProductionStage.cutting,
            plannedStart: today,
            plannedEnd: today,
            progressPct: 0,
            sortOrder: 0,
          ),
        ],
        componentIdByNode: nodes,
        existingReferences: ['QI-1004-0007'],
      );
      // No fallback: the sea-trials inspection has no place to be pinned and is skipped.
      expect(again, hasLength(11));
      expect(again.first.referenceNo, 'QI-1004-0008');
    });
  });

  group('InspectionDraft & rows', () {
    final draft = InspectionDraft(
      projectId: 'p',
      componentId: 'c1',
      hullId: 'h4',
      type: InspectionType.dimensional,
      referenceNo: ' qi-1004-0001 ',
      description: ' ',
      unit: 'mm',
      acceptanceMax: 3,
      inspector: 'Yard dimensional control',
      plannedAt: DateTime(2027, 6, 1, 10),
    );

    test('validation', () {
      expect(draft.validationErrors(), isEmpty);
      final bad = InspectionDraft(
        projectId: 'p',
        componentId: null,
        type: InspectionType.coatingDft,
        referenceNo: ' ',
        acceptanceMin: 450,
        acceptanceMax: 250,
        plannedAt: today,
      );
      expect(bad.validationErrors(), hasLength(3));
    });

    test('insert row is pending, normalized and pinned on top of the component', () {
      final row = QualityInspectionModel.insert(draft);
      expect(row['reference_no'], 'QI-1004-0001');
      expect(row['result'], 'pending');
      expect(row['description'], isNull);
      expect(row['inspection_type'], 'dimensional');
      expect(row['acceptance_max'], 3);
      expect(row['inspected_at'], DateTime(2027, 6, 1, 10).toUtc().toIso8601String());
      expect((row['marker_u'], row['marker_v'], row['marker_w']), (0.5, 0.5, 1));
    });

    test('result update keeps the database in charge of pass / fail', () {
      final row = QualityInspectionModel.resultUpdate(
        result: InspectionResult.pending,
        inspectedAt: DateTime(2027, 6, 1, 11),
        measuredValue: 3.4,
        notes: '  ',
      );
      expect(row['result'], 'pending');
      expect(row['measured_value'], 3.4);
      expect(row['notes'], isNull);
    });
  });
}
