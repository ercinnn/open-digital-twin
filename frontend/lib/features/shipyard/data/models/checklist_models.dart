import '../../domain/entities/checklist_entities.dart';
import 'json_utils.dart';

class ChecklistItemModel {
  const ChecklistItemModel._();

  static ChecklistItem fromJson(Map<String, dynamic> json) => ChecklistItem(
    id: json['id'] as String,
    activityId: json['activity_id'] as String,
    hullId: json['hull_id'] as String?,
    code: json['item_code'] as String,
    title: json['title'] as String,
    category: ChecklistCategory.fromDb(json['category'] as String?),
    required: json['required'] as bool? ?? true,
    status: ChecklistStatus.fromDb(json['status'] as String?),
    completedAt: readTimestamp(json['completed_at']),
    completedBy: json['completed_by'] as String?,
    notes: json['notes'] as String?,
    sortOrder: readInt(json['sort_order']) ?? 0,
  );

  /// Row for `insert into handover_checklist_items` (the hull follows the row).
  static Map<String, dynamic> insert(ChecklistDraft d) => {
    'project_id': d.projectId,
    'activity_id': d.activityId,
    'hull_id': d.hullId,
    'item_code': d.code.trim().toUpperCase(),
    'title': d.title.trim(),
    'category': d.category.dbValue,
    'required': d.required,
    'sort_order': d.sortOrder,
  };

  /// Status change: completion time is set / cleared by the database.
  static Map<String, dynamic> statusUpdate(ChecklistStatus status, {String? notes, String? completedBy}) {
    final n = notes?.trim();
    final by = completedBy?.trim();
    return {
      'status': status.dbValue,
      'notes': n == null || n.isEmpty ? null : n,
      'completed_by': status == ChecklistStatus.open || by == null || by.isEmpty ? null : by,
    };
  }
}
