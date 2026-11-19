import '../../domain/entities/quality_entities.dart';
import 'json_utils.dart';

MarkerPosition readMarker(Map<String, dynamic> json) => MarkerPosition(
  readDouble(json['marker_u']) ?? 0.5,
  readDouble(json['marker_v']) ?? 0.5,
  readDouble(json['marker_w']) ?? 1,
);

class QualityInspectionModel {
  const QualityInspectionModel._();

  static QualityInspection fromJson(Map<String, dynamic> json) => QualityInspection(
    id: json['id'] as String,
    componentId: json['component_id'] as String,
    hullId: json['hull_id'] as String?,
    activityId: json['activity_id'] as String?,
    holdPoint: json['hold_point'] as bool? ?? false,
    type: InspectionType.fromDb(json['inspection_type'] as String?),
    referenceNo: json['reference_no'] as String,
    description: json['description'] as String?,
    result: InspectionResult.fromDb(json['result'] as String?),
    measuredValue: readDouble(json['measured_value']),
    unit: json['unit'] as String?,
    acceptanceMin: readDouble(json['acceptance_min']),
    acceptanceMax: readDouble(json['acceptance_max']),
    inspector: json['inspector'] as String?,
    witnessedBy: json['witnessed_by'] as String?,
    inspectedAt: readTimestamp(json['inspected_at']) ?? DateTime.now(),
    position: readMarker(json),
    notes: json['notes'] as String?,
  );

  /// Row for `insert into quality_inspections` (a planned, pending inspection).
  static Map<String, dynamic> insert(InspectionDraft d) {
    String? text(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
    return {
      'project_id': d.projectId,
      'component_id': d.componentId,
      'hull_id': d.hullId,
      'activity_id': d.activityId,
      'hold_point': d.holdPoint,
      'inspection_type': d.type.dbValue,
      'reference_no': d.referenceNo.trim().toUpperCase(),
      'description': text(d.description),
      'result': InspectionResult.pending.dbValue,
      'unit': text(d.unit),
      'acceptance_min': d.acceptanceMin,
      'acceptance_max': d.acceptanceMax,
      'inspector': text(d.inspector),
      'witnessed_by': text(d.witnessedBy),
      'inspected_at': writeTimestamp(d.plannedAt),
      'notes': text(d.notes),
      'marker_u': 0.5,
      'marker_v': 0.5,
      'marker_w': 1,
    };
  }

  /// Columns written when a result is recorded. With a measured value and an
  /// acceptance band, [result] `pending` lets the database trigger decide pass / fail.
  static Map<String, dynamic> resultUpdate({
    required InspectionResult result,
    required DateTime inspectedAt,
    double? measuredValue,
    String? notes,
  }) => {
    'result': result.dbValue,
    'measured_value': measuredValue,
    'inspected_at': writeTimestamp(inspectedAt),
    'notes': notes == null || notes.trim().isEmpty ? null : notes.trim(),
  };
}

class PunchItemModel {
  const PunchItemModel._();

  static PunchItem fromJson(Map<String, dynamic> json) => PunchItem(
    id: json['id'] as String,
    componentId: json['component_id'] as String,
    hullId: json['hull_id'] as String?,
    itemNo: json['item_no'] as String,
    description: json['description'] as String,
    category: json['category'] as String? ?? 'hull',
    raisedBy: json['raised_by'] as String? ?? 'yard_qa',
    priority: PunchPriority.fromDb(json['priority'] as String?),
    status: PunchStatus.fromDb(json['status'] as String?),
    raisedAt: readTimestamp(json['raised_at']) ?? DateTime.now(),
    dueDate: readDate(json['due_date']),
    closedAt: readTimestamp(json['closed_at']),
    position: readMarker(json),
  );

  static Map<String, dynamic> insert(PunchDraft d, String itemNo) => {
    'project_id': d.projectId,
    'component_id': d.componentId,
    'hull_id': d.hullId,
    'item_no': itemNo,
    'description': d.description,
    'category': d.category,
    'raised_by': d.raisedBy,
    'priority': d.priority.dbValue,
    'due_date': writeDate(d.dueDate),
    'marker_u': 0.5,
    'marker_v': 0.5,
    'marker_w': 1,
  };
}
