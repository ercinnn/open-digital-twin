import 'package:flutter/material.dart';

/// Table `departments` (tree via [parentId]).
class Department {
  const Department({
    required this.id,
    required this.projectId,
    required this.code,
    required this.name,
    required this.colorHex,
    required this.sortOrder,
    this.parentId,
    this.managerTitle,
    this.description,
  });

  final String id;
  final String projectId;
  final String code;
  final String name;
  final String? parentId;
  final String? managerTitle;
  final String colorHex;
  final String? description;
  final int sortOrder;

  Color get color {
    final v = int.tryParse(colorHex.replaceFirst('#', ''), radix: 16);
    return v == null ? const Color(0xFF94A3B8) : Color(0xFF000000 | v);
  }
}

/// Table `shifts`.
class Shift {
  const Shift({required this.id, required this.code, required this.name, required this.startsAt, required this.endsAt});

  final String id;
  final String code;
  final String name;

  /// 'HH:MM'
  final String startsAt;
  final String endsAt;

  String get window => '$startsAt–$endsAt';
}

/// Table `area_assignments`: department staffing of an area / crane per shift.
class AreaAssignment {
  const AreaAssignment({
    required this.id,
    required this.departmentId,
    required this.componentId,
    required this.headcount,
    required this.isResponsible,
    this.shiftId,
    this.roleDescription,
  });

  final String id;
  final String departmentId;
  final String componentId;
  final String? shiftId;
  final int headcount;
  final bool isResponsible;
  final String? roleDescription;
}

/// Organization data of one yard project with derived lookups.
class Organization {
  Organization({required this.departments, required this.shifts, required this.assignments});

  final List<Department> departments;
  final List<Shift> shifts;
  final List<AreaAssignment> assignments;

  late final Map<String, Department> byId = {for (final d in departments) d.id: d};

  bool get isEmpty => departments.isEmpty;

  List<Department> childrenOf(String? parentId) =>
      departments.where((d) => d.parentId == parentId).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// Department and all of its descendants.
  Set<String> subtreeIds(String departmentId) {
    final result = <String>{departmentId};
    for (final child in childrenOf(departmentId)) {
      result.addAll(subtreeIds(child.id));
    }
    return result;
  }

  /// Owning department per component id.
  Map<String, Department> responsibleByComponent() {
    final map = <String, Department>{};
    for (final a in assignments) {
      if (!a.isResponsible) continue;
      final d = byId[a.departmentId];
      if (d != null) map[a.componentId] = d;
    }
    return map;
  }

  /// Headcount per shift id for a set of departments (`null` key = unassigned shift).
  Map<String?, int> headcountByShift(Set<String> departmentIds) {
    final map = <String?, int>{};
    for (final a in assignments) {
      if (!departmentIds.contains(a.departmentId)) continue;
      map[a.shiftId] = (map[a.shiftId] ?? 0) + a.headcount;
    }
    return map;
  }

  int headcount(Set<String> departmentIds) => headcountByShift(departmentIds).values.fold(0, (a, b) => a + b);

  /// Components (areas / cranes) a set of departments works on: id -> responsible?
  Map<String, bool> componentsOf(Set<String> departmentIds) {
    final map = <String, bool>{};
    for (final a in assignments) {
      if (!departmentIds.contains(a.departmentId)) continue;
      map[a.componentId] = (map[a.componentId] ?? false) || a.isResponsible;
    }
    return map;
  }

  /// Staffing rows of one component.
  List<AreaAssignment> forComponent(String componentId) =>
      assignments.where((a) => a.componentId == componentId).toList();
}
