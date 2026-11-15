import 'package:flutter/material.dart';

/// Calendar-day helpers (schedule columns are PostgreSQL `date`s).
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

/// Whole calendar days from [from] to [to] (DST-safe).
int daysBetween(DateTime from, DateTime to) => (dateOnly(to).difference(dateOnly(from)).inHours / 24).round();

String formatDate(DateTime? d) {
  if (d == null) return '—';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

String formatDateTime(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${formatDate(d)} ${two(d.hour)}:${two(d.minute)}';
}

/// Mirrors the `production_activities.stage` check constraint.
enum ProductionStage {
  cutting('cutting', 'Cutting', Color(0xFFF97316)),
  bending('bending', 'Bending', Color(0xFFFB923C)),
  panel('panel', 'Panel line', Color(0xFFFBBF24)),
  blockAssembly('block_assembly', 'Block assembly', Color(0xFF2DD4BF)),
  blastingPainting('blasting_painting', 'Blasting & coating', Color(0xFF60A5FA)),
  preOutfitting('pre_outfitting', 'Pre-outfitting', Color(0xFFA78BFA)),
  erection('erection', 'Erection', Color(0xFF22C55E)),
  launching('launching', 'Launching', Color(0xFF38BDF8)),
  outfitting('outfitting', 'Afloat outfitting', Color(0xFFC084FC)),
  commissioning('commissioning', 'Commissioning', Color(0xFFF472B6)),
  seaTrials('sea_trials', 'Sea trials', Color(0xFF22D3EE)),
  delivery('delivery', 'Delivery', Color(0xFFE2E8F0)),
  dockingRepair('docking_repair', 'Docking & repair', Color(0xFF94A3B8));

  const ProductionStage(this.dbValue, this.label, this.color);

  final String dbValue;
  final String label;
  final Color color;

  static ProductionStage fromDb(String? value) =>
      ProductionStage.values.firstWhere((s) => s.dbValue == value, orElse: () => ProductionStage.cutting);

  /// Steel is still loose parts: the block mesh is shown as a ghost at the shop.
  bool get isPartsStage =>
      this == ProductionStage.cutting || this == ProductionStage.bending || this == ProductionStage.panel;

  /// From erection on, a block sits at its modelled (erected) position in the hull.
  bool get isErectedOrLater =>
      this != ProductionStage.dockingRepair && index >= ProductionStage.erection.index;
}

enum HullStatus {
  planned('planned', 'Planned'),
  steelCutting('steel_cutting', 'Steel cutting'),
  blockProduction('block_production', 'Block production'),
  erection('erection', 'Erection on berth'),
  afloatOutfitting('afloat_outfitting', 'Afloat outfitting'),
  seaTrials('sea_trials', 'Sea trials'),
  delivered('delivered', 'Delivered'),
  docked('docked', 'Docked (repair)');

  const HullStatus(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static HullStatus fromDb(String? value) =>
      HullStatus.values.firstWhere((s) => s.dbValue == value, orElse: () => HullStatus.planned);
}

/// Table `hulls`.
class Hull {
  const Hull({
    required this.id,
    required this.projectId,
    required this.hullNo,
    required this.contractType,
    required this.status,
    required this.metadata,
    this.name,
    this.shipType,
    this.ownerName,
    this.classSociety,
    this.lengthM,
    this.beamM,
    this.deadweightT,
    this.contractDate,
    this.steelCuttingDate,
    this.keelLayingDate,
    this.launchingDate,
    this.contractDeliveryDate,
    this.forecastDeliveryDate,
    this.locationNodeId,
  });

  final String id;
  final String projectId;
  final String hullNo;
  final String? name;
  final String? shipType;
  final String contractType;
  final String? ownerName;
  final String? classSociety;
  final double? lengthM;
  final double? beamM;
  final double? deadweightT;
  final DateTime? contractDate;
  final DateTime? steelCuttingDate;
  final DateTime? keelLayingDate;
  final DateTime? launchingDate;
  final DateTime? contractDeliveryDate;
  final DateTime? forecastDeliveryDate;
  final HullStatus status;
  final String? locationNodeId;
  final Map<String, dynamic> metadata;

  bool get isRepair => contractType == 'repair';

  String get displayName => name == null || name!.isEmpty ? hullNo : '$hullNo · $name';

  /// Positive = forecast delivery later than the contract date.
  int? get deliveryDelayDays => contractDeliveryDate == null || forecastDeliveryDate == null
      ? null
      : daysBetween(contractDeliveryDate!, forecastDeliveryDate!);
}

/// Table `production_activities` (one Gantt bar).
class ProductionActivity {
  const ProductionActivity({
    required this.id,
    required this.projectId,
    required this.code,
    required this.name,
    required this.stage,
    required this.plannedStart,
    required this.plannedEnd,
    required this.progressPct,
    required this.sortOrder,
    this.hullId,
    this.componentId,
    this.locationNodeId,
    this.actualStart,
    this.actualEnd,
    this.departmentId,
    this.notes,
  });

  final String id;
  final String projectId;
  final String? hullId;
  final String? componentId;
  final String code;
  final String name;
  final ProductionStage stage;
  final String? locationNodeId;
  final DateTime plannedStart;
  final DateTime plannedEnd;
  final DateTime? actualStart;
  final DateTime? actualEnd;
  final double progressPct;
  final int sortOrder;
  final String? departmentId;
  final String? notes;

  bool get isDone => actualEnd != null;
  bool get isActive => actualStart != null && actualEnd == null;
  bool get isNotStarted => actualStart == null;

  int get plannedDays => daysBetween(plannedStart, plannedEnd).clamp(1, 100000);

  /// Start used for the timeline: actual if started, else planned - or today if the
  /// planned start already passed (a late activity cannot have started in the past).
  DateTime forecastStart(DateTime today) {
    if (actualStart != null) return actualStart!;
    return plannedStart.isBefore(today) ? dateOnly(today) : plannedStart;
  }

  /// End used for the timeline: actual if finished; running activities finish at
  /// the planned end or - when overdue - tomorrow at the earliest.
  DateTime forecastEnd(DateTime today) {
    if (actualEnd != null) return actualEnd!;
    if (actualStart != null) {
      final tomorrow = addDays(today, 1);
      return plannedEnd.isAfter(tomorrow) ? plannedEnd : tomorrow;
    }
    return addDays(forecastStart(today), plannedDays);
  }

  bool isLate(DateTime today) {
    if (actualEnd != null) return actualEnd!.isAfter(plannedEnd);
    if (actualStart == null) return plannedStart.isBefore(dateOnly(today));
    return plannedEnd.isBefore(dateOnly(today)) || forecastEnd(today).isAfter(plannedEnd);
  }

  /// Planned completion fraction (0..1) at [date], linear over the planned window.
  double plannedFractionAt(DateTime date) {
    final d = dateOnly(date);
    if (!d.isAfter(plannedStart)) return 0;
    if (!d.isBefore(plannedEnd)) return 1;
    return daysBetween(plannedStart, d) / plannedDays;
  }

  ProductionActivity copyWith({
    double? progressPct,
    DateTime? actualStart,
    DateTime? actualEnd,
    bool clearActualStart = false,
    bool clearActualEnd = false,
    String? notes,
  }) {
    return ProductionActivity(
      id: id,
      projectId: projectId,
      hullId: hullId,
      componentId: componentId,
      code: code,
      name: name,
      stage: stage,
      locationNodeId: locationNodeId,
      plannedStart: plannedStart,
      plannedEnd: plannedEnd,
      actualStart: clearActualStart ? null : (actualStart ?? this.actualStart),
      actualEnd: clearActualEnd ? null : (actualEnd ?? this.actualEnd),
      progressPct: progressPct ?? this.progressPct,
      sortOrder: sortOrder,
      departmentId: departmentId,
      notes: notes ?? this.notes,
    );
  }
}

enum PlacementKind { erected, area, hidden }

/// Where the 3D viewer should show a block mesh at a given date.
class BlockPlacement {
  const BlockPlacement._(this.kind, {this.areaNodeId, this.ghost = false, this.activity});

  const BlockPlacement.erected({ProductionActivity? activity}) : this._(PlacementKind.erected, activity: activity);

  const BlockPlacement.hidden() : this._(PlacementKind.hidden);

  const BlockPlacement.atArea(String areaNodeId, {bool ghost = false, ProductionActivity? activity})
    : this._(PlacementKind.area, areaNodeId: areaNodeId, ghost: ghost, activity: activity);

  final PlacementKind kind;
  final String? areaNodeId;

  /// Steel still in parts (cutting / bending / panel line).
  final bool ghost;

  /// Activity that determines the placement (running or last finished).
  final ProductionActivity? activity;

  /// Payload for the viewer command `set_placements`.
  Map<String, dynamic> toViewerJson() => switch (kind) {
    PlacementKind.erected => const {'mode': 'home'},
    PlacementKind.hidden => const {'mode': 'hidden'},
    PlacementKind.area => {'mode': 'area', 'area': areaNodeId, 'ghost': ghost},
  };

  @override
  bool operator ==(Object other) =>
      other is BlockPlacement && other.kind == kind && other.areaNodeId == areaNodeId && other.ghost == ghost;

  @override
  int get hashCode => Object.hash(kind, areaNodeId, ghost);
}
