import '../../../digital_twin/domain/entities/twin_entities.dart';
import '../entities/production_entities.dart';
import '../entities/resource_entities.dart';

/// Safe working load of a crane / resource (`metadata.swl_t` or `lifting_capacity_t`).
double? resourceCapacityT(TwinComponent c) {
  for (final key in ['swl_t', 'lifting_capacity_t']) {
    final v = c.metadata[key];
    if (v is num) return v.toDouble();
  }
  return null;
}

/// Result of [LiftPlan.forHull]: bookings to insert plus notes on what could not
/// be planned (or was planned without a capacity check).
class LiftPlanResult {
  const LiftPlanResult(this.bookings, this.warnings, {this.cranes = const {}});

  final List<BookingDraft> bookings;
  final List<String> warnings;

  /// Crane component id -> number of lifts booked on it.
  final Map<String, int> cranes;
}

/// Crane lifts for block erection: one `lift` booking per erection row of a
/// hull (block-level rows, not done, without a booking yet) on a crane whose
/// `metadata.location` is the erection area (building berth -> Goliath, dry
/// dock -> dock portal crane) and whose capacity carries the block weight.
///
/// The lift is put into the first free window of the erection days inside the
/// working hours ([dayStartHour] - [dayEndHour]); windows already booked on the
/// crane (maintenance, other lifts) and windows in the past are skipped, so the
/// database's no-overlap constraint does not reject the batch. Generated
/// bookings are `planned`; the crane operator confirms them.
class LiftPlan {
  const LiftPlan._();

  static const dayStartHour = 7;
  static const dayEndHour = 17;

  /// Lift window by block weight (rigging, lift, fit-up and release).
  static Duration liftDuration(double? loadT) => Duration(
    hours: loadT == null || loadT <= 100
        ? 3
        : loadT <= 300
        ? 4
        : 6,
  );

  static LiftPlanResult forHull({
    required Hull hull,
    required List<ProductionActivity> activities,
    required List<TwinComponent> components,
    required List<ResourceBooking> bookings,
    required DateTime now,
  }) {
    final today = dateOnly(now);
    final booked = {
      for (final b in bookings)
        if (!b.isCancelled && b.activityId != null) b.activityId!,
    };
    final erections =
        activities
            .where(
              (a) =>
                  a.hullId == hull.id &&
                  a.componentId != null &&
                  a.stage == ProductionStage.erection &&
                  !a.isDone &&
                  !booked.contains(a.id),
            )
            .toList()
          ..sort((a, b) {
            final c = a.forecastStart(today).compareTo(b.forecastStart(today));
            return c != 0 ? c : a.sortOrder.compareTo(b.sortOrder);
          });
    if (erections.isEmpty) return const LiftPlanResult([], []);

    final byId = {for (final c in components) c.id: c};
    final cranes = components.where((c) => c.category == 'crane').toList();
    // Busy windows per crane: existing bookings, then the lifts planned here.
    final busy = <String, List<(DateTime, DateTime)>>{
      for (final c in cranes)
        c.id: [
          for (final b in bookings)
            if (!b.isCancelled && b.componentId == c.id && b.slot == 1) (b.startsAt, b.endsAt),
        ],
    };

    final drafts = <BookingDraft>[];
    final perCrane = <String, int>{};
    final noCrane = <String, List<String>>{};
    final tooHeavy = <String>[];
    final noWindow = <String>[];
    var withoutWeight = 0;

    for (final a in erections) {
      final block = byId[a.componentId];
      final blockNo = '${block?.metadata['block_no'] ?? block?.name ?? a.code}';
      final kg = block?.weightKg;
      final loadT = kg == null || kg <= 0 ? null : kg / 1000;
      final atArea = cranes.where((c) => c.metadata['location'] == a.locationNodeId).toList();
      if (atArea.isEmpty) {
        noCrane.putIfAbsent(a.locationNodeId ?? '—', () => []).add(blockNo);
        continue;
      }
      // Smallest crane that carries the block first (keeps the big one free).
      final fitting =
          atArea.where((c) {
            final cap = resourceCapacityT(c);
            return loadT == null || cap == null || cap >= loadT;
          }).toList()..sort(
            (x, y) => (resourceCapacityT(x) ?? double.infinity).compareTo(resourceCapacityT(y) ?? double.infinity),
          );
      if (fitting.isEmpty) {
        tooHeavy.add('$blockNo (${loadT!.toStringAsFixed(0)} t)');
        continue;
      }

      final duration = liftDuration(loadT);
      final window = _firstFreeWindow(a, fitting, busy, duration, now);
      if (window == null) {
        noWindow.add(blockNo);
        continue;
      }
      final (crane, start) = window;
      final end = start.add(duration);
      busy[crane.id]!.add((start, end));
      perCrane[crane.id] = (perCrane[crane.id] ?? 0) + 1;
      if (loadT == null) withoutWeight++;
      drafts.add(
        BookingDraft(
          projectId: hull.projectId,
          componentId: crane.id,
          hullId: hull.id,
          activityId: a.id,
          title: '${hull.hullNo} $blockNo erection lift',
          type: BookingType.lift,
          slot: 1,
          startsAt: start,
          endsAt: end,
          loadT: loadT,
          status: BookingStatus.planned,
          notes: loadT == null ? 'Block weight not entered - booked without a capacity check.' : null,
        ),
      );
    }

    String list(List<String> l) => l.length <= 6 ? l.join(', ') : '${l.take(6).join(', ')} +${l.length - 6} more';
    return LiftPlanResult(drafts, [
      for (final e in noCrane.entries)
        'No crane at ${byId.values.where((c) => c.meshNodeId == e.key).firstOrNull?.name ?? e.key} '
            '(metadata.location): ${list(e.value)}.',
      if (tooHeavy.isNotEmpty) 'Heavier than the cranes at the erection area: ${list(tooHeavy)}.',
      if (noWindow.isNotEmpty) 'No free crane window in the erection days (or they are past): ${list(noWindow)}.',
      if (withoutWeight > 0)
        '$withoutWeight block${withoutWeight == 1 ? ' has' : 's have'} no weight: booked without a load, '
            'so the database cannot check the crane capacity.',
    ], cranes: perCrane);
  }

  /// First (crane, start) inside the working hours of the erection days, earliest
  /// day first, then the cranes in the given order, then the hour.
  static (TwinComponent, DateTime)? _firstFreeWindow(
    ProductionActivity a,
    List<TwinComponent> cranes,
    Map<String, List<(DateTime, DateTime)>> busy,
    Duration duration,
    DateTime now,
  ) {
    final today = dateOnly(now);
    final first = a.forecastStart(today);
    final days = daysBetween(first, a.forecastEnd(today)).clamp(1, 60);
    for (var d = 0; d < days; d++) {
      final day = addDays(first, d);
      for (final crane in cranes) {
        for (var h = dayStartHour; h + duration.inHours <= dayEndHour; h++) {
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
