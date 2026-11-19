import '../entities/block_entities.dart';
import '../entities/hse_entities.dart';
import '../entities/production_entities.dart';
import '../entities/resource_entities.dart';

/// One permit-to-work a schedule row of a block needs, and the permits that cover it.
class PermitNeed {
  const PermitNeed({required this.activity, required this.type, required this.permits});

  final ProductionActivity activity;
  final PermitType type;

  /// Current permits (not closed, not over) of this row and type.
  final List<WorkPermit> permits;

  bool get covered => permits.isNotEmpty;
}

/// A prefilled permit request for a [PermitNeed].
class PermitSuggestion {
  const PermitSuggestion({required this.validFrom, required this.hours, required this.description});

  final DateTime validFrom;
  final int hours;
  final String description;
}

/// Which permits the block work needs. Cutting, bending and panel work run in
/// designated workshops (no permit); the rest of a block's chain needs:
/// block assembly: confined space for tank blocks; blasting & coating: painting
/// (+ confined space for tanks); pre-outfitting: hot work; erection on the
/// berth / in the dock: lifting, hot work, work at height (+ confined space).
class PermitPlan {
  const PermitPlan._();

  /// Block types with tanks / voids that are entered during the work.
  static const tankTypes = {'DB', 'HPT', 'TST', 'WT', 'ER', 'BOW', 'BB', 'AFT', 'SKG', 'STL'};

  /// Rows starting within this many days are listed ahead of time.
  static const lookAheadDays = 7;

  /// Start of the day shift (local time) of permits planned ahead.
  static const shiftStartHour = 7;
  static const shiftHours = 10;

  static List<PermitType> typesFor(ProductionStage stage, BlockType? type) {
    final tank = type != null && tankTypes.contains(type.code);
    return switch (stage) {
      ProductionStage.blockAssembly => [if (tank) PermitType.confinedSpace],
      ProductionStage.blastingPainting => [PermitType.painting, if (tank) PermitType.confinedSpace],
      ProductionStage.preOutfitting => [PermitType.hotWork],
      ProductionStage.erection => [
        PermitType.lifting,
        PermitType.hotWork,
        PermitType.workAtHeight,
        if (tank) PermitType.confinedSpace,
      ],
      _ => const [],
    };
  }

  /// Needs of the rows of [block] that are running at [now] (planned or reported)
  /// or start within [lookAheadDays]; finished rows are left out. Ordered by row start.
  static List<PermitNeed> forBlock({
    required HullBlock block,
    required List<ProductionActivity> activities,
    required List<WorkPermit> permits,
    required DateTime now,
  }) {
    final today = dateOnly(now);
    final horizon = addDays(today, lookAheadDays);
    final rows = activities.where((a) {
      if (a.componentId != block.componentId || a.isDone) return false;
      if (a.isActive) return true;
      return !dateOnly(a.plannedEnd).isBefore(today) && !dateOnly(a.plannedStart).isAfter(horizon);
    }).toList()..sort((a, b) => a.plannedStart.compareTo(b.plannedStart));
    return [
      for (final a in rows)
        for (final t in typesFor(a.stage, block.type))
          PermitNeed(
            activity: a,
            type: t,
            permits: permits.where((p) => p.activityId == a.id && p.type == t && p.isCurrent(now)).toList(),
          ),
    ];
  }

  /// Window and description of a permit request for [need]: a lifting permit
  /// takes the next booked crane lift of the row; other permits the next day
  /// shift of the row (07:00, 10 h), or the next full hour when the row runs now.
  static PermitSuggestion suggest({
    required PermitNeed need,
    required HullBlock block,
    required List<ResourceBooking> bookings,
    required DateTime now,
  }) {
    final a = need.activity;
    final description =
        '${block.hullNo} ${block.blockNo} ${a.stage.label.toLowerCase()}: ${need.type.label.toLowerCase()}';
    if (need.type == PermitType.lifting) {
      final lifts =
          bookings
              .where(
                (b) =>
                    b.activityId == a.id &&
                    b.endsAt.isAfter(now) &&
                    const {BookingStatus.planned, BookingStatus.confirmed, BookingStatus.inProgress}.contains(b.status),
              )
              .toList()
            ..sort((x, y) => x.startsAt.compareTo(y.startsAt));
      if (lifts.isNotEmpty) {
        final lift = lifts.first;
        final start = lift.startsAt.isBefore(now) ? _nextHour(now) : lift.startsAt.toLocal();
        final hours = (lift.endsAt.difference(start).inMinutes / 60).ceil().clamp(1, 24);
        return PermitSuggestion(validFrom: start, hours: hours, description: '$description (crane lift)');
      }
    }
    final rowStart = DateTime(a.plannedStart.year, a.plannedStart.month, a.plannedStart.day, shiftStartHour);
    if (rowStart.isAfter(now)) {
      return PermitSuggestion(validFrom: rowStart, hours: shiftHours, description: description);
    }
    final todayShift = DateTime(now.year, now.month, now.day, shiftStartHour);
    final shiftEnd = todayShift.add(const Duration(hours: shiftHours));
    if (now.isBefore(shiftEnd.subtract(const Duration(hours: 1)))) {
      final start = now.isBefore(todayShift) ? todayShift : _nextHour(now);
      return PermitSuggestion(
        validFrom: start,
        hours: shiftEnd.difference(start).inHours.clamp(1, shiftHours),
        description: description,
      );
    }
    return PermitSuggestion(
      validFrom: todayShift.add(const Duration(days: 1)),
      hours: shiftHours,
      description: description,
    );
  }

  static DateTime _nextHour(DateTime now) => DateTime(now.year, now.month, now.day, now.hour + 1);
}
