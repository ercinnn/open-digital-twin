import 'package:flutter/material.dart';

/// Mirrors the `components.status` check constraint in Supabase.
enum ComponentStatus {
  normal('normal', 'Normal', Color(0xFF22C55E), Icons.check_circle_outline),
  inProgress('in_progress', 'In Progress', Color(0xFF3B82F6), Icons.construction),
  warning('warning', 'Warning', Color(0xFFF59E0B), Icons.warning_amber_rounded),
  alert('alert', 'Alert', Color(0xFFEF4444), Icons.crisis_alert);

  const ComponentStatus(this.dbValue, this.label, this.color, this.icon);

  /// Exact value stored in PostgreSQL and sent to the Three.js viewer.
  final String dbValue;
  final String label;
  final Color color;
  final IconData icon;

  static ComponentStatus fromDb(String? value) {
    return ComponentStatus.values.firstWhere((s) => s.dbValue == value, orElse: () => ComponentStatus.normal);
  }

  int get severity => switch (this) {
    ComponentStatus.alert => 3,
    ComponentStatus.warning => 2,
    ComponentStatus.inProgress => 1,
    ComponentStatus.normal => 0,
  };
}
