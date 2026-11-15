import '../../domain/entities/organization_entities.dart';
import 'json_utils.dart';

class DepartmentModel {
  const DepartmentModel._();

  static Department fromJson(Map<String, dynamic> json) => Department(
    id: json['id'] as String,
    projectId: json['project_id'] as String,
    code: json['code'] as String,
    name: json['name'] as String,
    parentId: json['parent_id'] as String?,
    managerTitle: json['manager_title'] as String?,
    colorHex: json['color'] as String? ?? '#94a3b8',
    description: json['description'] as String?,
    sortOrder: readInt(json['sort_order']) ?? 0,
  );
}

class ShiftModel {
  const ShiftModel._();

  static String _hhmm(Object? v) {
    final s = '${v ?? ''}';
    return s.length >= 5 ? s.substring(0, 5) : s;
  }

  static Shift fromJson(Map<String, dynamic> json) => Shift(
    id: json['id'] as String,
    code: json['code'] as String,
    name: json['name'] as String,
    startsAt: _hhmm(json['starts_at']),
    endsAt: _hhmm(json['ends_at']),
  );
}

class AreaAssignmentModel {
  const AreaAssignmentModel._();

  static AreaAssignment fromJson(Map<String, dynamic> json) => AreaAssignment(
    id: json['id'] as String,
    departmentId: json['department_id'] as String,
    componentId: json['component_id'] as String,
    shiftId: json['shift_id'] as String?,
    headcount: readInt(json['headcount']) ?? 0,
    isResponsible: json['is_responsible'] == true,
    roleDescription: json['role_description'] as String?,
  );
}
