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

  /// Short hull-level events (1-2 days): the Gantt draws them as a diamond
  /// with a label when the bar is too narrow to read.
  bool get isMilestone =>
      this == ProductionStage.launching || this == ProductionStage.seaTrials || this == ProductionStage.delivery;

  /// From erection on, a block sits at its modelled (erected) position in the hull.
  bool get isErectedOrLater =>
      this != ProductionStage.dockingRepair && index >= ProductionStage.erection.index;
}

/// Afloat outfitting work package of a hull (mirrors the
/// `production_activities.work_package` check constraint, migration 017). The
/// work is done on board at the quay; [shopNodeId] is the yard shop that
/// prefabricates / supplies it, [departmentCode] the executing department.
enum WorkPackage {
  outfittingSteel('outfitting_steel', 'Outfitting steel', 'OSTL', 'NODE_A15_OUTFITTING_LIGHT_STEEL_SHOP', 'OUT',
      'Seats, ladders, gratings, railings, doors and hatches'),
  deckMachinery('deck_machinery', 'Deck machinery & hatch covers', 'DECK', 'NODE_A15_OUTFITTING_LIGHT_STEEL_SHOP', 'OUT',
      'Hatch covers, windlass, mooring winches, lifeboats and davits'),
  machinery('machinery', 'Machinery & shaft line', 'MACH', 'NODE_A12_MECHANICAL_MACHINING_SHOP', 'OUT',
      'Main engine chocking, shaft alignment, propeller, auxiliaries'),
  piping('piping', 'Piping systems', 'PIPE', 'NODE_A11_PIPE_SHOP', 'OUT',
      'Pipe spools, valves, ballast / bilge / fuel / cooling systems'),
  electrical('electrical', 'Electrical & automation', 'ELEC', 'NODE_A13_ELECTRICAL_AUTOMATION_SHOP', 'OUT',
      'Cable pulling, switchboards, alarm & monitoring, navigation'),
  accommodation('accommodation', 'Accommodation & insulation', 'ACCO', 'NODE_A14_CARPENTRY_INSULATION_SHOP', 'OUT',
      'Insulation, linings, furniture, galley and HVAC'),
  painting('painting', 'Final painting', 'PNT', 'NODE_A10_BLOCK_BLASTING_PAINT_HALL', 'PNT',
      'Touch-up after outfitting, tank coating, final coat and markings');

  const WorkPackage(this.dbValue, this.label, this.code, this.shopNodeId, this.departmentCode, this.scope);

  final String dbValue;
  final String label;

  /// Suffix of the activity code (`NB1001-OUTFIT-PIPE`).
  final String code;
  final String shopNodeId;
  final String departmentCode;
  final String scope;

  static WorkPackage? fromDb(String? value) => WorkPackage.values.where((w) => w.dbValue == value).firstOrNull;
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

/// Mirrors the `hulls.contract_type` check constraint.
enum HullContractType {
  newbuild('newbuild', 'New build'),
  repair('repair', 'Repair'),
  conversion('conversion', 'Conversion');

  const HullContractType(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static HullContractType fromDb(String? value) =>
      HullContractType.values.firstWhere((t) => t.dbValue == value, orElse: () => HullContractType.newbuild);
}

/// Mesh categories a hull can lie at (`hulls.location_node_id`).
const hullLocationCategories = ['docks_and_berths', 'floating_dock', 'outfitting_quay'];

/// A new hull entered by an editor (insert into `hulls`).
class HullDraft {
  const HullDraft({
    required this.projectId,
    required this.hullNo,
    this.contractType = HullContractType.newbuild,
    this.status = HullStatus.planned,
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

  final String projectId;
  final String hullNo;
  final HullContractType contractType;
  final HullStatus status;
  final String? name;
  final String? shipType;
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

  /// Defaults to [contractDeliveryDate] when not given (see [effectiveForecastDelivery]).
  final DateTime? forecastDeliveryDate;
  final String? locationNodeId;

  /// Hull numbers are stored trimmed and upper case (e.g. `NB-1004`).
  String get normalizedHullNo => hullNo.trim().toUpperCase();

  DateTime? get effectiveForecastDelivery => forecastDeliveryDate ?? contractDeliveryDate;

  /// Repairs have no steel cutting / keel laying / launching.
  bool get hasBuildMilestones => contractType != HullContractType.repair;

  /// Human-readable problems; empty when the draft can be saved.
  List<String> validationErrors({Iterable<String> existingHullNos = const []}) {
    final errors = <String>[];
    final no = normalizedHullNo;
    if (no.isEmpty) {
      errors.add('Enter a hull number.');
    } else if (no.length > 30) {
      errors.add('The hull number may have at most 30 characters.');
    } else if (existingHullNos.any((e) => e.trim().toUpperCase() == no)) {
      errors.add('Hull number $no already exists in this yard.');
    }

    for (final (label, value) in [('Length', lengthM), ('Beam', beamM), ('Deadweight', deadweightT)]) {
      if (value != null && value <= 0) errors.add('$label must be greater than 0.');
    }
    if (lengthM != null && beamM != null && lengthM! > 0 && beamM! >= lengthM!) {
      errors.add('Beam must be smaller than the length.');
    }

    // Milestones must not run backwards (only the dates that are filled in are compared).
    final milestones = <(String, DateTime?)>[
      ('Contract', contractDate),
      if (hasBuildMilestones) ...[
        ('Steel cutting', steelCuttingDate),
        ('Keel laying', keelLayingDate),
        ('Launching', launchingDate),
      ],
      ('Contract delivery', contractDeliveryDate),
    ];
    (String, DateTime)? previous;
    for (final (label, date) in milestones) {
      if (date == null) continue;
      if (previous != null && date.isBefore(previous.$2)) {
        errors.add('$label (${formatDate(date)}) is before ${previous.$1.toLowerCase()} (${formatDate(previous.$2)}).');
      }
      previous = (label, date);
    }
    final forecast = effectiveForecastDelivery;
    if (forecast != null && contractDate != null && forecast.isBefore(contractDate!)) {
      errors.add('Forecast delivery is before the contract date.');
    }
    return errors;
  }
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

/// A schedule row entered by an editor (insert / plan update of `production_activities`).
/// Progress and actual dates are reported separately ([ProductionActivity.copyWith]).
class ActivityDraft {
  const ActivityDraft({
    required this.projectId,
    required this.hullId,
    required this.code,
    required this.name,
    required this.stage,
    required this.plannedStart,
    required this.plannedEnd,
    this.locationNodeId,
    this.componentId,
    this.sortOrder = 0,
    this.notes,
    this.workPackage,
    this.departmentId,
  });

  final String projectId;
  final String? hullId;
  final String code;
  final String name;
  final ProductionStage stage;
  final DateTime plannedStart;
  final DateTime plannedEnd;
  final String? locationNodeId;
  final String? componentId;
  final int sortOrder;
  final String? notes;

  /// Afloat outfitting work package (hull-level outfitting rows only).
  final WorkPackage? workPackage;

  /// Executing department; `null` keeps the row's department on a plan update.
  final String? departmentId;

  int get plannedDays => daysBetween(plannedStart, plannedEnd);

  /// Human-readable problems; empty when the draft can be saved.
  List<String> validationErrors() => [
    if (code.trim().isEmpty) 'The activity code is missing.',
    if (name.trim().isEmpty) 'Enter a name.',
    if (plannedEnd.isBefore(plannedStart)) 'Planned end is before the planned start.',
    if (workPackage != null && (componentId != null || stage != ProductionStage.outfitting))
      'Work packages are hull-level afloat outfitting rows.',
  ];
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
    this.workPackage,
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

  /// Afloat outfitting work package (`null` for every other row).
  final WorkPackage? workPackage;

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
      workPackage: workPackage,
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
