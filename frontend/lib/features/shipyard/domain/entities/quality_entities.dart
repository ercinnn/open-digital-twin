import 'package:flutter/material.dart';

enum InspectionType {
  ndtUt('ndt_ut', 'NDT · UT'),
  ndtRt('ndt_rt', 'NDT · RT'),
  ndtMt('ndt_mt', 'NDT · MT'),
  ndtPt('ndt_pt', 'NDT · PT'),
  visualWeld('visual_weld', 'Visual weld'),
  coatingDft('coating_dft', 'Coating DFT'),
  dimensional('dimensional', 'Dimensional'),
  pressureTest('pressure_test', 'Pressure test'),
  classSurvey('class_survey', 'Class survey');

  const InspectionType(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static InspectionType fromDb(String? v) =>
      InspectionType.values.firstWhere((t) => t.dbValue == v, orElse: () => InspectionType.visualWeld);
}

enum InspectionResult {
  pending('pending', 'Pending', Color(0xFF94A3B8)),
  pass('pass', 'Pass', Color(0xFF22C55E)),
  fail('fail', 'Fail', Color(0xFFEF4444)),
  conditional('conditional', 'Conditional', Color(0xFFF59E0B));

  const InspectionResult(this.dbValue, this.label, this.color);

  final String dbValue;
  final String label;
  final Color color;

  static InspectionResult fromDb(String? v) =>
      InspectionResult.values.firstWhere((r) => r.dbValue == v, orElse: () => InspectionResult.pending);
}

/// Normalized pin position inside a component's bounding box.
class MarkerPosition {
  const MarkerPosition(this.u, this.v, this.w);
  final double u;
  final double v;
  final double w;

  static const top = MarkerPosition(0.5, 0.5, 1);
}

/// Table `quality_inspections`.
class QualityInspection {
  const QualityInspection({
    required this.id,
    required this.componentId,
    required this.type,
    required this.referenceNo,
    required this.result,
    required this.inspectedAt,
    required this.position,
    this.hullId,
    this.description,
    this.measuredValue,
    this.unit,
    this.acceptanceMin,
    this.acceptanceMax,
    this.inspector,
    this.witnessedBy,
    this.notes,
  });

  final String id;
  final String componentId;
  final String? hullId;
  final InspectionType type;
  final String referenceNo;
  final String? description;
  final InspectionResult result;
  final double? measuredValue;
  final String? unit;
  final double? acceptanceMin;
  final double? acceptanceMax;
  final String? inspector;
  final String? witnessedBy;
  final DateTime inspectedAt;
  final MarkerPosition position;
  final String? notes;

  String? get acceptanceText {
    if (acceptanceMin == null && acceptanceMax == null) return null;
    final u = unit == null ? '' : ' $unit';
    if (acceptanceMin != null && acceptanceMax != null) return '${_n(acceptanceMin!)}–${_n(acceptanceMax!)}$u';
    if (acceptanceMin != null) return '≥ ${_n(acceptanceMin!)}$u';
    return '≤ ${_n(acceptanceMax!)}$u';
  }

  static String _n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

/// Typical unit, acceptance band and inspector role of an inspection type
/// (values in line with the demo seed). A measured value outside the band is
/// set to `fail` by the database trigger `_evaluate_inspection`.
class InspectionPreset {
  const InspectionPreset({required this.inspector, this.unit, this.min, this.max});

  final String inspector;
  final String? unit;
  final double? min;
  final double? max;

  bool get hasBand => min != null || max != null;
}

const inspectionPresets = <InspectionType, InspectionPreset>{
  InspectionType.ndtUt: InspectionPreset(inspector: 'Yard NDT Level II'),
  InspectionType.ndtRt: InspectionPreset(inspector: 'External NDT company'),
  InspectionType.ndtMt: InspectionPreset(inspector: 'Yard NDT Level II'),
  InspectionType.ndtPt: InspectionPreset(inspector: 'Yard NDT Level II'),
  InspectionType.visualWeld: InspectionPreset(inspector: 'Yard QC inspector'),
  InspectionType.coatingDft: InspectionPreset(inspector: 'Yard coating inspector', unit: 'um', min: 250, max: 450),
  InspectionType.dimensional: InspectionPreset(inspector: 'Yard dimensional control', unit: 'mm', max: 3),
  InspectionType.pressureTest: InspectionPreset(inspector: 'Yard QC inspector', unit: 'bar', min: 15, max: 16),
  InspectionType.classSurvey: InspectionPreset(inspector: 'Class surveyor (demo)'),
};

/// A planned inspection entered by an editor (insert into `quality_inspections`,
/// result `pending`).
class InspectionDraft {
  const InspectionDraft({
    required this.projectId,
    required this.componentId,
    required this.type,
    required this.referenceNo,
    required this.plannedAt,
    this.hullId,
    this.description,
    this.unit,
    this.acceptanceMin,
    this.acceptanceMax,
    this.inspector,
    this.witnessedBy,
    this.notes,
  });

  final String projectId;

  /// Block or yard area the inspection is pinned to (required by the table).
  final String? componentId;
  final String? hullId;
  final InspectionType type;
  final String referenceNo;
  final String? description;
  final String? unit;
  final double? acceptanceMin;
  final double? acceptanceMax;
  final String? inspector;
  final String? witnessedBy;

  /// Stored in `inspected_at`; replaced by the real time when the result is recorded.
  final DateTime plannedAt;
  final String? notes;

  /// Human-readable problems; empty when the draft can be saved.
  List<String> validationErrors() => [
    if (componentId == null) 'Choose the block or area to inspect.',
    if (referenceNo.trim().isEmpty) 'Enter a reference number.',
    if (acceptanceMin != null && acceptanceMax != null && acceptanceMin! > acceptanceMax!)
      'The acceptance minimum is above the maximum.',
  ];
}

/// Next free inspection reference of a hull in the seed style `QI-<hull digits>-<4 digits>`
/// (`NB-1004` -> `QI-1004-0001`, then `QI-1004-0002`, ...).
String nextInspectionReference(String hullNo, Iterable<String> existingReferences, {int offset = 0}) {
  final digits = hullNo.replaceAll(RegExp(r'\D'), '');
  final key = digits.isEmpty ? hullNo.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '') : digits;
  final prefix = 'QI-$key-';
  var max = 0;
  for (final r in existingReferences) {
    final ref = r.trim().toUpperCase();
    if (!ref.startsWith(prefix)) continue;
    final n = int.tryParse(ref.substring(prefix.length));
    if (n != null && n > max) max = n;
  }
  return '$prefix${(max + 1 + offset).toString().padLeft(4, '0')}';
}

enum PunchPriority {
  a('A', Color(0xFFEF4444), 'Before next milestone'),
  b('B', Color(0xFFF59E0B), 'Before delivery'),
  c('C', Color(0xFFFACC15), 'Guarantee period allowed');

  const PunchPriority(this.dbValue, this.color, this.meaning);

  final String dbValue;
  final Color color;
  final String meaning;

  static PunchPriority fromDb(String? v) => PunchPriority.values.firstWhere((p) => p.dbValue == v, orElse: () => PunchPriority.b);
}

enum PunchStatus {
  open('open', 'Open'),
  inProgress('in_progress', 'In progress'),
  closed('closed', 'Closed');

  const PunchStatus(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static PunchStatus fromDb(String? v) => PunchStatus.values.firstWhere((s) => s.dbValue == v, orElse: () => PunchStatus.open);
}

/// Table `punch_items`.
class PunchItem {
  const PunchItem({
    required this.id,
    required this.componentId,
    required this.itemNo,
    required this.description,
    required this.category,
    required this.raisedBy,
    required this.priority,
    required this.status,
    required this.raisedAt,
    required this.position,
    this.hullId,
    this.dueDate,
    this.closedAt,
  });

  final String id;
  final String componentId;
  final String? hullId;
  final String itemNo;
  final String description;
  final String category;
  final String raisedBy;
  final PunchPriority priority;
  final PunchStatus status;
  final DateTime raisedAt;
  final DateTime? dueDate;
  final DateTime? closedAt;
  final MarkerPosition position;

  bool get isOpen => status != PunchStatus.closed;

  bool isOverdue(DateTime today) => isOpen && dueDate != null && dueDate!.isBefore(today);

  String get raisedByLabel => switch (raisedBy) {
    'owner' => 'Owner',
    'class' => 'Class',
    'flag' => 'Flag state',
    _ => 'Yard QA',
  };
}

/// New punch item raised in the app.
class PunchDraft {
  const PunchDraft({
    required this.projectId,
    required this.componentId,
    required this.description,
    required this.category,
    required this.raisedBy,
    required this.priority,
    this.hullId,
    this.dueDate,
  });

  final String projectId;
  final String componentId;
  final String? hullId;
  final String description;
  final String category;
  final String raisedBy;
  final PunchPriority priority;
  final DateTime? dueDate;
}
