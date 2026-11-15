import 'package:flutter/material.dart';

enum BookingType {
  lift('lift', 'Lift', Icons.precision_manufacturing_outlined, Color(0xFFFACC15)),
  docking('docking', 'Docking', Icons.directions_boat_filled_outlined, Color(0xFF22D3EE)),
  berthing('berthing', 'Berthing', Icons.anchor, Color(0xFF38BDF8)),
  maintenance('maintenance', 'Maintenance', Icons.build_outlined, Color(0xFFA3E635)),
  reservation('reservation', 'Reservation', Icons.event_available_outlined, Color(0xFFA78BFA));

  const BookingType(this.dbValue, this.label, this.icon, this.color);

  final String dbValue;
  final String label;
  final IconData icon;
  final Color color;

  static BookingType fromDb(String? v) => BookingType.values.firstWhere((t) => t.dbValue == v, orElse: () => BookingType.lift);
}

enum BookingStatus {
  planned('planned', 'Planned'),
  confirmed('confirmed', 'Confirmed'),
  inProgress('in_progress', 'In progress'),
  suspended('suspended', 'Suspended'),
  done('done', 'Done'),
  cancelled('cancelled', 'Cancelled');

  const BookingStatus(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static BookingStatus fromDb(String? v) =>
      BookingStatus.values.firstWhere((s) => s.dbValue == v, orElse: () => BookingStatus.planned);
}

/// Table `resource_bookings`.
class ResourceBooking {
  const ResourceBooking({
    required this.id,
    required this.projectId,
    required this.componentId,
    required this.title,
    required this.type,
    required this.slot,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    this.hullId,
    this.activityId,
    this.loadT,
    this.suspendedReason,
    this.notes,
  });

  final String id;
  final String projectId;
  final String componentId;
  final String? hullId;
  final String? activityId;
  final String title;
  final BookingType type;
  final int slot;
  final DateTime startsAt;
  final DateTime endsAt;
  final double? loadT;
  final BookingStatus status;
  final String? suspendedReason;
  final String? notes;

  bool get isCancelled => status == BookingStatus.cancelled;

  bool overlaps(DateTime from, DateTime to) => startsAt.isBefore(to) && endsAt.isAfter(from);

  /// Status as shown to the user: confirmed bookings whose window is running count
  /// as in progress, finished windows as done (the database keeps the planned value).
  BookingStatus effectiveStatus(DateTime now) {
    if (status == BookingStatus.cancelled || status == BookingStatus.suspended || status == BookingStatus.done) {
      return status;
    }
    if (!endsAt.isAfter(now)) return BookingStatus.done;
    if (!startsAt.isAfter(now)) return BookingStatus.inProgress;
    return status;
  }
}

/// New booking entered in the app.
class BookingDraft {
  const BookingDraft({
    required this.projectId,
    required this.componentId,
    required this.title,
    required this.type,
    required this.slot,
    required this.startsAt,
    required this.endsAt,
    this.hullId,
    this.loadT,
    this.notes,
  });

  final String projectId;
  final String componentId;
  final String? hullId;
  final String title;
  final BookingType type;
  final int slot;
  final DateTime startsAt;
  final DateTime endsAt;
  final double? loadT;
  final String? notes;
}

/// Booked share of a time window per resource (overlapping bookings counted once per slot).
double utilization(Iterable<ResourceBooking> bookings, DateTime from, DateTime to, {int slots = 1}) {
  final window = to.difference(from).inMinutes;
  if (window <= 0) return 0;
  var booked = 0;
  for (final b in bookings) {
    if (b.isCancelled || !b.overlaps(from, to)) continue;
    final s = b.startsAt.isBefore(from) ? from : b.startsAt;
    final e = b.endsAt.isAfter(to) ? to : b.endsAt;
    booked += e.difference(s).inMinutes;
  }
  return (booked / (window * slots)).clamp(0, 1).toDouble();
}
