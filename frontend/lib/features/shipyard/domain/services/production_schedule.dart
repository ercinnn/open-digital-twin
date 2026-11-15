import '../entities/production_entities.dart';

/// Earned vs planned progress of a set of activities (duration weighted).
class ScheduleProgress {
  const ScheduleProgress({required this.earnedPct, required this.plannedPct, required this.lateCount});

  final double earnedPct;
  final double plannedPct;
  final int lateCount;

  /// Schedule performance index: < 1 behind plan, > 1 ahead.
  double? get spi => plannedPct <= 0 ? null : earnedPct / plannedPct;

  double get variancePct => earnedPct - plannedPct;
}

/// Pure schedule logic shared by the Gantt chart, the 3D timeline and the dashboard.
class ProductionSchedule {
  const ProductionSchedule(this.activities);

  final List<ProductionActivity> activities;

  /// Activities of one block ordered by forecast start.
  List<ProductionActivity> forComponent(String componentId, DateTime today) {
    final list = activities.where((a) => a.componentId == componentId).toList()
      ..sort((a, b) {
        final c = a.forecastStart(today).compareTo(b.forecastStart(today));
        return c != 0 ? c : a.sortOrder.compareTo(b.sortOrder);
      });
    return list;
  }

  /// Block placement at [date]:
  ///  * an activity running at [date] puts the block at its yard area (ghost while
  ///    the steel is still in parts); erection and later stages = erected position
  ///  * between activities the block waits at the last finished activity's area
  ///  * before its first activity the block does not exist yet (hidden)
  /// Blocks without schedule rows keep their modelled position (no entry).
  Map<String, BlockPlacement> placementsAt(DateTime date, DateTime today) {
    final d = dateOnly(date);
    final ids = activities.map((a) => a.componentId).whereType<String>().toSet();
    final result = <String, BlockPlacement>{};
    for (final id in ids) {
      result[id] = placementFor(forComponent(id, today), d, today);
    }
    return result;
  }

  static BlockPlacement placementFor(List<ProductionActivity> ordered, DateTime date, DateTime today) {
    if (ordered.isEmpty) return const BlockPlacement.erected();
    ProductionActivity? running;
    ProductionActivity? lastFinished;
    for (final a in ordered) {
      final start = a.forecastStart(today);
      final end = a.forecastEnd(today);
      if (!date.isBefore(start) && date.isBefore(end)) running = a;
      if (!end.isAfter(date)) lastFinished = a;
    }
    final source = running ?? lastFinished;
    if (source == null) return const BlockPlacement.hidden();
    if (source.stage.isErectedOrLater || source.locationNodeId == null) {
      return BlockPlacement.erected(activity: source);
    }
    return BlockPlacement.atArea(
      source.locationNodeId!,
      ghost: running != null && source.stage.isPartsStage,
      activity: source,
    );
  }

  /// Activities running at [date] (forecast dates).
  List<ProductionActivity> runningAt(DateTime date, DateTime today) {
    final d = dateOnly(date);
    return activities
        .where((a) => !d.isBefore(a.forecastStart(today)) && d.isBefore(a.forecastEnd(today)))
        .toList();
  }

  /// First and last forecast day of the whole schedule (padded).
  (DateTime, DateTime)? range(DateTime today, {int padDays = 5}) {
    if (activities.isEmpty) return null;
    var min = activities.first.plannedStart;
    var max = activities.first.plannedEnd;
    for (final a in activities) {
      for (final d in [a.plannedStart, a.forecastStart(today)]) {
        if (d.isBefore(min)) min = d;
      }
      for (final d in [a.plannedEnd, a.forecastEnd(today)]) {
        if (d.isAfter(max)) max = d;
      }
    }
    return (addDays(min, -padDays), addDays(max, padDays));
  }

  static ScheduleProgress progressOf(Iterable<ProductionActivity> items, DateTime today) {
    var weight = 0.0;
    var earned = 0.0;
    var planned = 0.0;
    var late = 0;
    for (final a in items) {
      final w = a.plannedDays.toDouble();
      weight += w;
      earned += w * (a.isDone ? 100 : a.progressPct);
      planned += w * a.plannedFractionAt(today) * 100;
      if (a.isLate(today) && !a.isDone) late++;
    }
    if (weight == 0) return const ScheduleProgress(earnedPct: 0, plannedPct: 0, lateCount: 0);
    return ScheduleProgress(earnedPct: earned / weight, plannedPct: planned / weight, lateCount: late);
  }

  ScheduleProgress progressForHull(String hullId, DateTime today) =>
      progressOf(activities.where((a) => a.hullId == hullId), today);
}
