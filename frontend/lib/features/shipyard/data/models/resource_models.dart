import '../../domain/entities/resource_entities.dart';
import 'json_utils.dart';

class ResourceBookingModel {
  const ResourceBookingModel._();

  static ResourceBooking fromJson(Map<String, dynamic> json) => ResourceBooking(
    id: json['id'] as String,
    projectId: json['project_id'] as String,
    componentId: json['component_id'] as String,
    hullId: json['hull_id'] as String?,
    activityId: json['activity_id'] as String?,
    title: json['title'] as String,
    type: BookingType.fromDb(json['booking_type'] as String?),
    slot: readInt(json['slot']) ?? 1,
    startsAt: readTimestamp(json['starts_at']) ?? DateTime.now(),
    endsAt: readTimestamp(json['ends_at']) ?? DateTime.now(),
    loadT: readDouble(json['load_t']),
    status: BookingStatus.fromDb(json['status'] as String?),
    suspendedReason: json['suspended_reason'] as String?,
    notes: json['notes'] as String?,
  );

  static Map<String, dynamic> insert(BookingDraft d) => {
    'project_id': d.projectId,
    'component_id': d.componentId,
    'hull_id': d.hullId,
    'activity_id': d.activityId,
    'title': d.title,
    'booking_type': d.type.dbValue,
    'slot': d.slot,
    'starts_at': writeTimestamp(d.startsAt),
    'ends_at': writeTimestamp(d.endsAt),
    'load_t': d.loadT,
    'notes': d.notes,
    'status': d.status.dbValue,
  };
}
