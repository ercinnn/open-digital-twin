import 'package:flutter_test/flutter_test.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/block_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/production_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/services/draft_schedule.dart';
import 'package:open_digital_twin/features/shipyard/domain/services/production_schedule.dart';

void main() {
  final today = DateTime(2026, 11, 17);

  Hull hull({DateTime? keel, String? location, String contractType = 'newbuild'}) => Hull(
    id: 'h1',
    projectId: 'p',
    hullNo: 'NB-1001',
    contractType: contractType,
    status: HullStatus.planned,
    metadata: const {},
    steelCuttingDate: DateTime(2026, 12, 1),
    keelLayingDate: keel ?? DateTime(2027, 3, 1),
    launchingDate: DateTime(2027, 12, 31),
    contractDeliveryDate: DateTime(2028, 1, 31),
    locationNodeId: location,
  );

  HullBlock block(String no, String type, int seq, {double? weightKg}) => HullBlock(
    componentId: 'c-$no',
    meshNodeId: blockMeshNodeId('NB-1001', no),
    hullNo: 'NB-1001',
    blockNo: no,
    name: 'NB-1001 Block $no',
    side: BlockSide.centre,
    erectionSequence: seq,
    type: BlockType.byCode(type),
    weightKg: weightKg,
  );

  final blocks = [
    block('BLG-101P', 'BLG', 3),
    block('DB-101', 'DB', 1),
    block('DB-102', 'DB', 2),
    block('ACC-601', 'ACC', 4),
  ];

  List<ActivityDraft> rowsOf(List<ActivityDraft> all, String componentId) =>
      all.where((a) => a.componentId == componentId).toList();

  group('DraftSchedule.forHull with blocks', () {
    final result = DraftSchedule.forHull(hull(), today: today, blocks: blocks, firstSortOrder: 10);

    test('steel work and erection per block, afloat phase per hull', () {
      expect(result.isValid, isTrue, reason: result.problems.join());
      final hullRows = result.activities.where((a) => a.componentId == null).map((a) => a.stage).toList();
      expect(hullRows, [
        ProductionStage.launching,
        ProductionStage.outfitting,
        ProductionStage.commissioning,
        ProductionStage.seaTrials,
        ProductionStage.delivery,
      ]);
      expect(rowsOf(result.activities, 'c-DB-101').map((a) => a.stage), [
        ProductionStage.cutting,
        ProductionStage.panel,
        ProductionStage.blockAssembly,
        ProductionStage.blastingPainting,
        ProductionStage.erection,
      ]);
      expect(rowsOf(result.activities, 'c-BLG-101P').map((a) => a.stage), contains(ProductionStage.bending));
      expect(rowsOf(result.activities, 'c-ACC-601').map((a) => a.stage), contains(ProductionStage.preOutfitting));
      final codes = result.activities.map((a) => a.code).toList();
      expect(codes.toSet().length, codes.length);
      expect(codes, contains('NB1001-BLG101P-BND'));
      expect(result.activities.first.sortOrder, 10);
      expect(result.activities.every((a) => a.validationErrors().isEmpty), isTrue);
    });

    test('erection follows the erection sequence between keel laying and launching', () {
      final erections = [
        for (final no in ['DB-101', 'DB-102', 'BLG-101P', 'ACC-601'])
          rowsOf(result.activities, 'c-$no').firstWhere((a) => a.stage == ProductionStage.erection),
      ];
      expect(erections.first.plannedStart, DateTime(2027, 3, 1));
      for (var i = 1; i < erections.length; i++) {
        expect(erections[i].plannedStart.isAfter(erections[i - 1].plannedStart), isTrue);
      }
      expect(erections.last.plannedEnd.isAfter(DateTime(2027, 12, 31)), isFalse);
      expect(erections.every((a) => a.locationNodeId == 'NODE_A16_BUILDING_BERTH'), isTrue);
    });

    test('each block chain runs in order in the shops and is ready before its erection', () {
      for (final b in blocks) {
        final rows = rowsOf(result.activities, b.componentId);
        for (var i = 1; i < rows.length; i++) {
          expect(rows[i].plannedStart.isBefore(rows[i - 1].plannedEnd), isFalse, reason: rows[i].code);
        }
        expect(rows.first.plannedStart.isBefore(DateTime(2026, 12, 1)), isFalse);
        expect(rows.first.locationNodeId, 'NODE_A05_CNC_CUTTING_SHOP');
      }
      // The first block starts on the steel cutting date, later ones just in time.
      expect(rowsOf(result.activities, 'c-DB-101').first.plannedStart, DateTime(2026, 12, 1));
      final acc = rowsOf(result.activities, 'c-ACC-601');
      final erection = acc.last;
      expect(daysBetween(acc[acc.length - 2].plannedEnd, erection.plannedStart), BlockSchedule.readyBufferDays);
    });

    test('the rows move the block from the shops to the berth in 3D', () {
      var id = 0;
      final activities = [
        for (final d in result.activities)
          ProductionActivity(
            id: '${id++}',
            projectId: d.projectId,
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
          ),
      ];
      final schedule = ProductionSchedule(activities);
      final rows = schedule.forComponent('c-DB-102', today);
      PlacementKind kindAt(DateTime d) => ProductionSchedule.placementFor(rows, d, today).kind;
      expect(kindAt(DateTime(2026, 11, 30)), PlacementKind.hidden);
      final assembly = rows.firstWhere((a) => a.stage == ProductionStage.blockAssembly);
      final atHall = ProductionSchedule.placementFor(rows, assembly.plannedStart, today);
      expect(atHall.areaNodeId, 'NODE_A08_BLOCK_ASSEMBLY_HALL');
      expect(atHall.ghost, isFalse);
      expect(kindAt(DateTime(2027, 6, 1)), PlacementKind.erected);
    });
  });

  group('BlockSchedule', () {
    test('short keel-laying lead shortens the stages of the first blocks, 1 day minimum', () {
      final r = DraftSchedule.forHull(
        hull(keel: DateTime(2026, 12, 11)),
        today: today,
        blocks: blocks,
      );
      expect(r.isValid, isTrue, reason: r.problems.join());
      final db1 = rowsOf(r.activities, 'c-DB-101');
      expect(db1[db1.length - 2].plannedEnd.isAfter(DateTime(2026, 12, 11)), isFalse);
      expect(db1.every((a) => a.plannedDays >= 1), isTrue);
      final tooShort = DraftSchedule.forHull(
        hull(keel: DateTime(2026, 12, 4)),
        today: today,
        blocks: blocks,
      );
      expect(tooShort.problems.single, contains('at least 5 days'));
    });

    test('rows only for the new blocks, in their slot of the full sequence', () {
      final all = BlockSchedule.forBlocks(hull(), blocks);
      final only = BlockSchedule.forBlocks(hull(), blocks, only: {'c-BLG-101P'}, existingCodes: {'NB1001-BLG101P-CUT'});
      expect({for (final a in only.activities) a.componentId}, {'c-BLG-101P'});
      DateTime erection(List<ActivityDraft> rows) =>
          rows.firstWhere((a) => a.componentId == 'c-BLG-101P' && a.stage == ProductionStage.erection).plannedStart;
      expect(erection(only.activities), erection(all.activities));
      expect(only.activities.first.code, 'NB1001-BLG101P-CUT-2');
      expect(BlockSchedule.forBlocks(hull(contractType: 'repair'), blocks).isValid, isFalse);
    });

    test('dry dock hulls are erected and launched in the dock', () {
      final r = DraftSchedule.forHull(
        hull(location: 'NODE_A17_DRY_DOCK'),
        today: today,
        blocks: blocks,
      );
      for (final a in r.activities.where(
        (a) => a.stage == ProductionStage.erection || a.stage == ProductionStage.launching,
      )) {
        expect(a.locationNodeId, 'NODE_A17_DRY_DOCK');
      }
    });

    test('heavier blocks take longer; fitDays keeps the order and the minimum', () {
      final light = BlockSchedule.daysOf(block('DB-1', 'DB', 1, weightKg: 30000));
      final heavy = BlockSchedule.daysOf(block('DB-2', 'DB', 1, weightKg: 180000));
      expect(heavy.reduce((a, b) => a + b), greaterThan(light.reduce((a, b) => a + b)));
      expect(BlockSchedule.daysOf(block('X', 'BLK', 1)), [5, 7, 14, 6]);
      expect(BlockSchedule.fitDays([5, 7, 14, 6], 40), [5, 7, 14, 6]);
      final fitted = BlockSchedule.fitDays([5, 7, 14, 6], 10);
      expect(fitted.reduce((a, b) => a + b), 10);
      expect(fitted.every((d) => d >= 1), isTrue);
      expect(BlockSchedule.fitDays([5, 7, 14, 6], 4), [1, 1, 1, 1]);
    });
  });
}
