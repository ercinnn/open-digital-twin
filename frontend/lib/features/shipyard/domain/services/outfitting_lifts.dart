import 'dart:math' as math;

import '../../../digital_twin/domain/entities/twin_entities.dart';
import '../entities/production_entities.dart';
import '../entities/resource_entities.dart';
import 'hull_block_geometry.dart';
import 'lift_plan.dart';

/// A heavy item of an afloat outfitting work package, lifted on board by a
/// quay crane ([count] lifts of [weightT] each).
class OutfittingLiftItem {
  const OutfittingLiftItem(this.label, this.count, this.weightT);

  final String label;
  final int count;
  final double weightT;

  @override
  bool operator ==(Object other) =>
      other is OutfittingLiftItem && other.label == label && other.count == count && other.weightT == weightT;

  @override
  int get hashCode => Object.hash(label, count, weightT);

  @override
  String toString() => '$count x $label ${weightT.toStringAsFixed(1)} t';
}

/// Quay crane lifts of the afloat outfitting: every work package row brings
/// its heavy items on board ([itemsOf]: hatch cover panels, windlass and
/// mooring winches, lifeboat, generator sets, switchboard, pipe spool bundles,
/// ...; weights estimated from the hull size). Each item gets one `planned`
/// `lift` booking (`activity_id` = the package row) on a crane whose
/// `metadata.location` is the row's area (outfitting quay: 28 t luffing,
/// 2 x 50 t jib), the smallest that carries it first, in the first free window
/// (working hours of [LiftPlan]) from its share of the package days on; the
/// items of a package are spread evenly over the package. Items already booked
/// (same row and title, not cancelled) are skipped, so the plan can be repeated
/// after packages are added or moved.
class OutfittingLifts {
  const OutfittingLifts._();

  /// Ship types with cargo hatches (hatch cover panels in deck machinery).
  static final _hatchTypes = RegExp('bulk|cargo|container|multi.?purpose|ore|log', caseSensitive: false);

  /// Hull size factor: L x B relative to a 100 m x 16 m ship, 0.3 .. 4.
  static double scaleOf(HullShape shape) => (shape.length * shape.beam / 1600).clamp(0.3, 4.0);

  /// Cargo holds of a dry cargo ship: about one per 25 m of length, 2 .. 9.
  static int holdsOf(HullShape shape) => (shape.length / 25).round().clamp(2, 9);

  static bool hasHatchCovers(Hull hull) => _hatchTypes.hasMatch(hull.shipType ?? '');

  static double _t(double v) => (v * 10).round() / 10;

  /// Heavy items of [package] for [hull]; [packageDays] sizes the pipe spool
  /// deliveries (one bundle per week of the piping package).
  static List<OutfittingLiftItem> itemsOf(Hull hull, WorkPackage package, {int packageDays = 14}) {
    final shape = HullShape.of(hull, const {});
    final s = scaleOf(shape);
    return switch (package) {
      WorkPackage.outfittingSteel => [OutfittingLiftItem('Foremast & radar mast', 1, _t(2 + 3 * s))],
      WorkPackage.deckMachinery => [
        if (hasHatchCovers(hull)) OutfittingLiftItem('Hatch cover panel', 2 * holdsOf(shape), _t(12 * s)),
        OutfittingLiftItem('Windlass / mooring winch', 2, _t(8 * s)),
        OutfittingLiftItem('Aft mooring winch', 2, _t(5 * s)),
        OutfittingLiftItem('Lifeboat & davit', 1, _t(5 + 4 * s)),
      ],
      WorkPackage.machinery => [
        OutfittingLiftItem('Generator set', 3, _t(4 + 8 * s)),
        OutfittingLiftItem('Boiler & heat exchanger module', 1, _t(3 + 4 * s)),
        const OutfittingLiftItem('Emergency generator', 1, 3),
      ],
      WorkPackage.piping => [
        OutfittingLiftItem('Pipe spool bundle', math.max(2, (packageDays / 7).ceil()), _t(2 + 2 * s)),
      ],
      WorkPackage.electrical => [
        OutfittingLiftItem('Main switchboard', 1, _t(3 + 3 * s)),
        const OutfittingLiftItem('Cable drum set', 2, 4),
      ],
      WorkPackage.accommodation => [OutfittingLiftItem('HVAC & galley unit', 2, _t(2 + 2 * s))],
      WorkPackage.painting => const [],
    };
  }

  /// Booking title of lift [index] (0-based) of [item].
  static String titleOf(Hull hull, OutfittingLiftItem item, int index) =>
      '${hull.hullNo} ${item.label}${item.count > 1 ? ' ${index + 1}/${item.count}' : ''} lift';

  /// Note on the generated bookings.
  static const estimateNote = 'Weight estimated from the hull size - correct the load when the item weight is known.';

  static LiftPlanResult forHull({
    required Hull hull,
    required List<ProductionActivity> activities,
    required List<TwinComponent> components,
    required List<ResourceBooking> bookings,
    required DateTime now,
  }) {
    final today = dateOnly(now);
    final rows = activities.where((a) => a.hullId == hull.id && a.workPackage != null && !a.isDone).toList()
      ..sort((a, b) => a.workPackage!.index.compareTo(b.workPackage!.index));
    if (rows.isEmpty) return const LiftPlanResult([], []);

    final booked = {
      for (final b in bookings)
        if (!b.isCancelled && b.activityId != null) (b.activityId!, b.title),
    };
    final cranes = components.where((c) => c.category == 'crane').toList();
    final busy = <String, List<(DateTime, DateTime)>>{
      for (final c in cranes)
        c.id: [
          for (final b in bookings)
            if (!b.isCancelled && b.componentId == c.id && b.slot == 1) (b.startsAt, b.endsAt),
        ],
    };

    // Every lift still to book, with the day it should happen (its share of the package).
    final wanted = <({ProductionActivity row, OutfittingLiftItem item, String title, DateTime day, int days})>[];
    for (final a in rows) {
      final first = a.forecastStart(today);
      final days = daysBetween(first, a.forecastEnd(today)).clamp(1, 180);
      final items = itemsOf(hull, a.workPackage!, packageDays: days);
      final total = items.fold<int>(0, (n, i) => n + i.count);
      var k = 0;
      for (final item in items) {
        for (var i = 0; i < item.count; i++, k++) {
          final title = titleOf(hull, item, i);
          if (booked.contains((a.id, title))) continue;
          wanted.add((row: a, item: item, title: title, day: addDays(first, (k * days / total).floor()), days: days));
        }
      }
    }
    wanted.sort((x, y) {
      final c = x.day.compareTo(y.day);
      return c != 0 ? c : x.row.workPackage!.index.compareTo(y.row.workPackage!.index);
    });

    final drafts = <BookingDraft>[];
    final perCrane = <String, int>{};
    final noCrane = <String>{};
    final tooHeavy = <String>[];
    final noWindow = <String>[];
    final areaName = {for (final c in components) c.meshNodeId: c.name};

    for (final w in wanted) {
      final a = w.row;
      final atArea = cranes.where((c) => c.metadata['location'] == a.locationNodeId).toList();
      if (atArea.isEmpty) {
        noCrane.add(areaName[a.locationNodeId] ?? a.locationNodeId ?? '—');
        continue;
      }
      final fitting = atArea.where((c) => (resourceCapacityT(c) ?? double.infinity) >= w.item.weightT).toList()
        ..sort((x, y) => (resourceCapacityT(x) ?? double.infinity).compareTo(resourceCapacityT(y) ?? double.infinity));
      if (fitting.isEmpty) {
        tooHeavy.add('${w.item.label} (${w.item.weightT.toStringAsFixed(0)} t)');
        continue;
      }
      final duration = LiftPlan.liftDuration(w.item.weightT);
      final window = _firstFreeWindow(a.forecastStart(today), w.day, w.days, fitting, busy, duration, now);
      if (window == null) {
        noWindow.add(w.title.replaceFirst('${hull.hullNo} ', ''));
        continue;
      }
      final (crane, start) = window;
      final end = start.add(duration);
      busy[crane.id]!.add((start, end));
      perCrane[crane.id] = (perCrane[crane.id] ?? 0) + 1;
      drafts.add(
        BookingDraft(
          projectId: hull.projectId,
          componentId: crane.id,
          hullId: hull.id,
          activityId: a.id,
          title: w.title,
          type: BookingType.lift,
          slot: 1,
          startsAt: start,
          endsAt: end,
          loadT: w.item.weightT,
          status: BookingStatus.planned,
          notes: estimateNote,
        ),
      );
    }
    drafts.sort((x, y) => x.startsAt.compareTo(y.startsAt));

    String list(Iterable<String> l) => l.length <= 6 ? l.join(', ') : '${l.take(6).join(', ')} +${l.length - 6} more';
    return LiftPlanResult(drafts, [
      if (noCrane.isNotEmpty) 'No crane at ${list(noCrane)} (metadata.location): its package lifts are not booked.',
      if (tooHeavy.isNotEmpty)
        'Heavier than the cranes at the quay (tandem lift or floating crane needed): ${list(tooHeavy.toSet())}.',
      if (noWindow.isNotEmpty) 'No free crane window in the package days (or they are past): ${list(noWindow)}.',
    ], cranes: perCrane);
  }

  /// First (crane, start) inside the working hours, from [preferred] to the
  /// end of the package days, then the earlier package days; per day the
  /// cranes in the given order, then the hour.
  static (TwinComponent, DateTime)? _firstFreeWindow(
    DateTime first,
    DateTime preferred,
    int days,
    List<TwinComponent> cranes,
    Map<String, List<(DateTime, DateTime)>> busy,
    Duration duration,
    DateTime now,
  ) {
    final offset = daysBetween(first, preferred).clamp(0, days - 1);
    for (var n = 0; n < days; n++) {
      final day = addDays(first, (offset + n) % days);
      for (final crane in cranes) {
        for (var h = LiftPlan.dayStartHour; h + duration.inHours <= LiftPlan.dayEndHour; h++) {
          final start = DateTime(day.year, day.month, day.day, h);
          final end = start.add(duration);
          if (start.isBefore(now)) continue;
          if (busy[crane.id]!.every((w) => !(w.$1.isBefore(end) && w.$2.isAfter(start)))) return (crane, start);
        }
      }
    }
    return null;
  }
}
