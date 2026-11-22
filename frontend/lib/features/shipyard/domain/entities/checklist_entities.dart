import 'package:flutter/material.dart';

/// Mirrors the `handover_checklist_items.category` check constraint (019).
enum ChecklistCategory {
  trial('trial', 'Trial', Icons.speed),
  certificate('certificate', 'Certificate', Icons.verified_outlined),
  document('document', 'Document', Icons.description_outlined),
  handover('handover', 'Handover', Icons.handshake_outlined);

  const ChecklistCategory(this.dbValue, this.label, this.icon);

  final String dbValue;
  final String label;
  final IconData icon;

  static ChecklistCategory fromDb(String? v) =>
      ChecklistCategory.values.firstWhere((c) => c.dbValue == v, orElse: () => ChecklistCategory.trial);
}

/// Mirrors the `handover_checklist_items.status` check constraint (019).
enum ChecklistStatus {
  open('open', 'Open', Color(0xFFF59E0B)),
  done('done', 'Done', Color(0xFF22C55E)),
  waived('waived', 'Waived', Color(0xFF94A3B8));

  const ChecklistStatus(this.dbValue, this.label, this.color);

  final String dbValue;
  final String label;
  final Color color;

  static ChecklistStatus fromDb(String? v) =>
      ChecklistStatus.values.firstWhere((s) => s.dbValue == v, orElse: () => ChecklistStatus.open);
}

/// Table `handover_checklist_items`: one item of the sea trials / delivery
/// checklist of a hull-level schedule row.
class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.activityId,
    required this.code,
    required this.title,
    required this.category,
    required this.required,
    required this.status,
    required this.sortOrder,
    this.hullId,
    this.completedAt,
    this.completedBy,
    this.notes,
  });

  final String id;
  final String activityId;
  final String? hullId;
  final String code;
  final String title;
  final ChecklistCategory category;

  /// The row cannot be reported finished while a required item is open (database).
  final bool required;
  final ChecklistStatus status;
  final DateTime? completedAt;
  final String? completedBy;

  /// Result / remark; the reason when waived.
  final String? notes;
  final int sortOrder;

  bool get isOpen => status == ChecklistStatus.open;

  /// Open and required: blocks finishing the row.
  bool get blocks => required && isOpen;
}

/// A new checklist item (insert into `handover_checklist_items`).
class ChecklistDraft {
  const ChecklistDraft({
    required this.projectId,
    required this.activityId,
    required this.code,
    required this.title,
    required this.category,
    this.required = true,
    this.sortOrder = 0,
    this.hullId,
  });

  final String projectId;
  final String activityId;
  final String? hullId;
  final String code;
  final String title;
  final ChecklistCategory category;
  final bool required;
  final int sortOrder;

  List<String> validationErrors({Iterable<String> existingCodes = const []}) => [
    if (code.trim().isEmpty) 'Enter a code.',
    if (title.trim().isEmpty) 'Enter a title.',
    if (existingCodes.any((c) => c.toUpperCase() == code.trim().toUpperCase()))
      'The checklist already has an item ${code.trim().toUpperCase()}.',
  ];
}
