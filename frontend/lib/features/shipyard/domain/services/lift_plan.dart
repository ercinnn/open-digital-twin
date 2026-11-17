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

/// New crane, window, load and notes of an existing lift ([LiftPlan.syncLoads]).
class LiftUpdate {
  const LiftUpdate({
    required this.booking,
    required this.blockNo,
    required this.componentId,
    required this.startsAt,
    required this.endsAt,
    required this.loadT,
    required this.notes,
  });

  final ResourceBooking booking;
  final String blockNo;

  /// Crane (component id); differs from the booking's when the block is too heavy for it.
  final String componentId;
  final DateTime startsAt;
  final DateTime endsAt;
  final double? loadT;
  final String? notes;

  bool get movedCrane => componentId != booking.componentId;

  bool get movedStart => startsAt != booking.startsAt;
}

/// Result of [LiftPlan.syncLoads]: updates to apply in order plus notes on lifts left as they are.
class LiftSyncResult {
  const LiftSyncResult(this.updates, this.warnings);

  final List<LiftUpdate> updates;
  final List<String> warnings;
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
          notes: loadT == null ? noWeightNote : null,
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

  /// Note of lifts booked for a block without a weight.
  static const noWeightNote = 'Block weight not entered - booked without a capacity check.';

  /// Brings the `planned` erection lifts of [hull]'s blocks in line with the
  /// block weights: `load_t` = weight, window length = [liftDuration]. A lift
  /// keeps its start when the new window still fits the working day and is
  /// free; otherwise it moves to the first free window of the erection days.
  /// A block heavier than the booked crane moves to the smallest crane at the
  /// erection area that carries it. Lifts that are already running / past or
  /// not `planned` (confirmed by the operator) are left alone and reported.
  ///
  /// [weightKgOverrides] (block component id -> kg, `null` = cleared) wins over
  /// the components' `weight_kg`, so edits can be planned before the component
  /// list reloads. Apply the updates in the returned order: each window was
  /// checked against the earlier updates and the later lifts' current windows.
  static LiftSyncResult syncLoads({
    required Hull hull,
    required List<ProductionActivity> activities,
    required List<TwinComponent> components,
    required List<ResourceBooking> bookings,
    required DateTime now,
    Map<String, double?> weightKgOverrides = const {},
  }) {
    final byId = {for (final c in components) c.id: c};
    final activityById = {for (final a in activities) a.id: a};
    final cranes = components.where((c) => c.category == 'crane').toList();
    final busy = <String, List<(DateTime, DateTime)>>{
      for (final c in cranes)
        c.id: [
          for (final b in bookings)
            if (!b.isCancelled && b.componentId == c.id && b.slot == 1) (b.startsAt, b.endsAt),
        ],
    };

    final lifts =
        bookings.where((b) {
          final a = b.activityId == null ? null : activityById[b.activityId];
          return b.type == BookingType.lift &&
              !b.isCancelled &&
              a != null &&
              a.hullId == hull.id &&
              a.componentId != null &&
              a.stage == ProductionStage.erection;
        }).toList()..sort((x, y) => x.startsAt.compareTo(y.startsAt));

    final updates = <LiftUpdate>[];
    final locked = <String>[];
    final tooHeavy = <String>[];
    final noWindow = <String>[];

    for (final b in lifts) {
      final a = activityById[b.activityId]!;
      final block = byId[a.componentId];
      final blockNo = '${block?.metadata['block_no'] ?? block?.name ?? a.code}';
      final kg = weightKgOverrides.containsKey(a.componentId) ? weightKgOverrides[a.componentId] : block?.weightKg;
      final loadT = kg == null || kg <= 0 ? null : kg / 1000;
      final duration = liftDuration(loadT);
      final sameLoad = (loadT == null && b.loadT == null) || (loadT != null && b.loadT != null && (loadT - b.loadT!).abs() < 0.0005);
      if (sameLoad && b.endsAt.difference(b.startsAt) == duration) continue;
      if (b.status != BookingStatus.planned || b.startsAt.isBefore(now)) {
        locked.add(blockNo);
        continue;
      }

      final crane = byId[b.componentId];
      final fitsCrane = loadT == null || crane == null || (resourceCapacityT(crane) ?? double.infinity) >= loadT;
      final own = busy[b.componentId];
      own?.remove((b.startsAt, b.endsAt));

      DateTime? start;
      var craneId = b.componentId;
      final keptEnd = b.startsAt.add(duration);
      final dayEnd = DateTime(b.startsAt.year, b.startsAt.month, b.startsAt.day, dayEndHour);
      if (fitsCrane &&
          !keptEnd.isAfter(dayEnd) &&
          (own ?? const []).every((w) => !(w.$1.isBefore(keptEnd) && w.$2.isAfter(b.startsAt)))) {
        start = b.startsAt;
      } else {
        final atArea = cranes.where((c) => c.metadata['location'] == a.locationNodeId).toList();
        final fitting =
            atArea.where((c) {
              final cap = resourceCapacityT(c);
              return loadT == null || cap == null || cap >= loadT;
            }).toList()..sort((x, y) {
              // The booked crane first, then the smallest that carries the block.
              if (x.id == b.componentId) return -1;
              if (y.id == b.componentId) return 1;
              return (resourceCapacityT(x) ?? double.infinity).compareTo(resourceCapacityT(y) ?? double.infinity);
            });
        if (fitting.isEmpty) {
          own?.add((b.startsAt, b.endsAt));
          tooHeavy.add('$blockNo (${loadT!.toStringAsFixed(0)} t)');
          continue;
        }
        final window = _firstFreeWindow(a, fitting, busy, duration, now);
        if (window == null) {
          own?.add((b.startsAt, b.endsAt));
          noWindow.add(blockNo);
          continue;
        }
        craneId = window.$1.id;
        start = window.$2;
      }

      final end = start.add(duration);
      busy[craneId]?.add((start, end));
      final notes = loadT == null
          ? (b.notes == null || b.notes!.trim().isEmpty ? noWeightNote : b.notes)
          : (b.notes == noWeightNote ? null : b.notes);
      updates.add(
        LiftUpdate(booking: b, blockNo: blockNo, componentId: craneId, startsAt: start, endsAt: end, loadT: loadT, notes: notes),
      );
    }

    String list(List<String> l) => l.length <= 6 ? l.join(', ') : '${l.take(6).join(', ')} +${l.length - 6} more';
    return LiftSyncResult(updates, [
      if (locked.isNotEmpty)
        'Not changed (confirmed by the crane operator, running or past): ${list(locked)} - '
            'update their load in Resources.',
      if (tooHeavy.isNotEmpty) 'Heavier than the cranes at the erection area, lift kept unchanged: ${list(tooHeavy)}.',
      if (noWindow.isNotEmpty) 'No free crane window for the longer lift in the erection days: ${list(noWindow)}.',
    ]);
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
