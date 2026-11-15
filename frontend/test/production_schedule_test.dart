import 'package:flutter_test/flutter_test.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/production_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/services/production_schedule.dart';

final today = DateTime(2026, 11, 14);

ProductionActivity act(
  String code,
  ProductionStage stage,
  int startOffset,
  int days, {
  String component = 'blk',
  String? location,
  int? actualStart,
  int? actualEnd,
  double progress = 0,
}) {
  return ProductionActivity(
    id: code,
    projectId: 'p',
    hullId: 'h',
    componentId: component,
    code: code,
    name: code,
    stage: stage,
    locationNodeId: location ?? 'NODE_${stage.dbValue.toUpperCase()}',
    plannedStart: addDays(today, startOffset),
    plannedEnd: addDays(today, startOffset + days),
    actualStart: actualStart == null ? null : addDays(today, actualStart),
    actualEnd: actualEnd == null ? null : addDays(today, actualEnd),
    progressPct: progress,
    sortOrder: 0,
  );
}

void main() {
  group('date helpers', () {
    test('daysBetween counts calendar days across DST changes', () {
      expect(daysBetween(DateTime(2026, 3, 28), DateTime(2026, 3, 30)), 2);
      expect(daysBetween(DateTime(2026, 10, 24), DateTime(2026, 10, 26)), 2);
      expect(formatDate(DateTime(2026, 1, 5)), '2026-01-05');
    });
  });

  group('ProductionActivity forecast', () {
    test('late, not started activity is shifted to today', () {
      final a = act('cut', ProductionStage.cutting, -3, 6);
      expect(a.forecastStart(today), today);
      expect(a.forecastEnd(today), addDays(today, 6));
      expect(a.isLate(today), isTrue);
    });

    test('overdue running activity ends tomorrow at the earliest', () {
      final a = act('pnl', ProductionStage.panel, -12, 9, actualStart: -11, progress: 40);
      expect(a.forecastEnd(today), addDays(today, 1));
      expect(a.isLate(today), isTrue);
    });

    test('planned fraction is linear over the planned window', () {
      final a = act('asm', ProductionStage.blockAssembly, -5, 10);
      expect(a.plannedFractionAt(today), closeTo(0.5, 1e-9));
      expect(a.plannedFractionAt(addDays(today, -9)), 0);
      expect(a.plannedFractionAt(addDays(today, 20)), 1);
    });
  });

  group('block placement', () {
    final schedule = ProductionSchedule([
      act('cut', ProductionStage.cutting, -20, 6, actualStart: -20, actualEnd: -14, progress: 100),
      act('asm', ProductionStage.blockAssembly, -12, 16, actualStart: -12, progress: 60),
      act('erc', ProductionStage.erection, 10, 5),
    ]);

    test('hidden before the first activity', () {
      expect(schedule.placementsAt(addDays(today, -30), today)['blk']!.kind, PlacementKind.hidden);
    });

    test('ghost at the shop while steel is in parts', () {
      final p = schedule.placementsAt(addDays(today, -18), today)['blk']!;
      expect(p.kind, PlacementKind.area);
      expect(p.ghost, isTrue);
      expect(p.areaNodeId, 'NODE_CUTTING');
    });

    test('waits at the last area between activities, solid', () {
      final p = schedule.placementsAt(addDays(today, -13), today)['blk']!;
      expect(p.kind, PlacementKind.area);
      expect(p.areaNodeId, 'NODE_CUTTING');
      expect(p.ghost, isFalse);
    });

    test('running block assembly places the block in the hall today', () {
      final p = schedule.placementsAt(today, today)['blk']!;
      expect(p.areaNodeId, 'NODE_BLOCK_ASSEMBLY');
      expect(p.toViewerJson(), {'mode': 'area', 'area': 'NODE_BLOCK_ASSEMBLY', 'ghost': false});
    });

    test('erected from the erection stage on', () {
      final p = schedule.placementsAt(addDays(today, 12), today)['blk']!;
      expect(p.kind, PlacementKind.erected);
      expect(p.toViewerJson(), {'mode': 'home'});
    });
  });

  group('progress', () {
    test('earned vs planned and SPI', () {
      final items = [
        act('a', ProductionStage.cutting, -10, 10, actualStart: -10, actualEnd: -1, progress: 100),
        act('b', ProductionStage.panel, -5, 10, actualStart: -5, progress: 20),
      ];
      final p = ProductionSchedule.progressOf(items, today);
      expect(p.earnedPct, closeTo(60, 1e-9)); // (10*100 + 10*20) / 20
      expect(p.plannedPct, closeTo(75, 1e-9)); // (10*100 + 10*50) / 20
      expect(p.spi, closeTo(0.8, 1e-9));
      expect(p.lateCount, 0);
    });
  });
}
