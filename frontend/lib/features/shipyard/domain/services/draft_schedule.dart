import '../entities/production_entities.dart';

/// Yard area where a stage usually runs (mesh ids of the demo shipyard). `null`
/// for work outside the yard (sea trials).
const stageDefaultLocations = <ProductionStage, String?>{
  ProductionStage.cutting: 'NODE_A05_CNC_CUTTING_SHOP',
  ProductionStage.bending: 'NODE_A06_BENDING_PRESS_SHOP',
  ProductionStage.panel: 'NODE_A07_PANEL_SUB_ASSEMBLY_LINE',
  ProductionStage.blockAssembly: 'NODE_A08_BLOCK_ASSEMBLY_HALL',
  ProductionStage.blastingPainting: 'NODE_A10_BLOCK_BLASTING_PAINT_HALL',
  ProductionStage.preOutfitting: 'NODE_A09_OUTDOOR_BLOCK_JOINING_YARD',
  ProductionStage.erection: 'NODE_A16_BUILDING_BERTH',
  ProductionStage.launching: 'NODE_A16_BUILDING_BERTH',
  ProductionStage.outfitting: 'NODE_A19_OUTFITTING_QUAY',
  ProductionStage.commissioning: 'NODE_A19_OUTFITTING_QUAY',
  ProductionStage.seaTrials: null,
  ProductionStage.delivery: 'NODE_A19_OUTFITTING_QUAY',
  ProductionStage.dockingRepair: 'NODE_A17_DRY_DOCK',
};

/// Suffix of generated activity codes (`NB1004-CUT`).
const _stageCodes = <ProductionStage, String>{
  ProductionStage.cutting: 'CUT',
  ProductionStage.bending: 'BND',
  ProductionStage.panel: 'PNL',
  ProductionStage.blockAssembly: 'ASM',
  ProductionStage.blastingPainting: 'PNT',
  ProductionStage.preOutfitting: 'POF',
  ProductionStage.erection: 'ERECT',
  ProductionStage.launching: 'LAUNCH',
  ProductionStage.outfitting: 'OUTFIT',
  ProductionStage.commissioning: 'COMM',
  ProductionStage.seaTrials: 'TRIALS',
  ProductionStage.delivery: 'DELIVERY',
  ProductionStage.dockingRepair: 'DOCKING',
};

/// Default activity names per stage (prefixed with the hull number).
const stageDefaultNames = <ProductionStage, String>{
  ProductionStage.cutting: 'Plate & profile cutting',
  ProductionStage.bending: 'Bending & forming',
  ProductionStage.panel: 'Panel line & sub-assembly',
  ProductionStage.blockAssembly: 'Block assembly',
  ProductionStage.blastingPainting: 'Block blasting & coating',
  ProductionStage.preOutfitting: 'Grand-block joining & pre-outfitting',
  ProductionStage.erection: 'Hull erection on berth',
  ProductionStage.launching: 'Launching',
  ProductionStage.outfitting: 'Afloat outfitting at quay',
  ProductionStage.commissioning: 'Commissioning & harbour acceptance tests',
  ProductionStage.seaTrials: 'Sea trials',
  ProductionStage.delivery: 'Delivery & flag change',
  ProductionStage.dockingRepair: 'Docking & repair',
};

/// Unique activity code for [stage] of [hullNo] (`NB-1004` -> `NB1004-CUT`,
/// then `NB1004-CUT-2`, ... when taken). Codes are unique per project.
String activityCodeFor(String hullNo, ProductionStage stage, Set<String> existingCodes) {
  final prefix = hullNo.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
  final base = '$prefix-${_stageCodes[stage]}';
  final taken = {for (final c in existingCodes) c.toUpperCase()};
  if (!taken.contains(base)) return base;
  var n = 2;
  while (taken.contains('$base-$n')) {
    n++;
  }
  return '$base-$n';
}

/// Result of [DraftSchedule.forHull]: rows to insert, or why none could be made.
class DraftScheduleResult {
  const DraftScheduleResult(this.activities, this.problems);

  final List<ActivityDraft> activities;
  final List<String> problems;

  bool get isValid => problems.isEmpty && activities.isNotEmpty;
}

/// Hull-level draft schedule derived from the hull milestones. The fractions
/// follow a typical block-built newbuild: steel work overlaps from steel cutting
/// until shortly before launching, erection runs keel laying -> launching, and the
/// afloat phase ends with commissioning, sea trials and delivery.
class DraftSchedule {
  const DraftSchedule._();

  /// Shortest windows the template can spread over (days).
  static const minBuildDays = 30;
  static const minAfloatDays = 14;

  static DraftScheduleResult forHull(
    Hull hull, {
    required DateTime today,
    Set<String> existingCodes = const {},
    int firstSortOrder = 1,
  }) {
    final delivery = hull.contractDeliveryDate ?? hull.forecastDeliveryDate;
    final codes = {...existingCodes};
    var sort = firstSortOrder;

    ActivityDraft row(ProductionStage stage, DateTime start, DateTime end, {String? location}) {
      final code = activityCodeFor(hull.hullNo, stage, codes);
      codes.add(code);
      return ActivityDraft(
        projectId: hull.projectId,
        hullId: hull.id,
        code: code,
        name: '${hull.hullNo} ${stageDefaultNames[stage]}',
        stage: stage,
        plannedStart: start,
        // Every bar lasts at least one day.
        plannedEnd: end.isAfter(start) ? end : addDays(start, 1),
        locationNodeId: location ?? stageDefaultLocations[stage],
        sortOrder: sort++,
      );
    }

    if (!hull.isRepair && hull.steelCuttingDate != null && hull.launchingDate != null) {
      final s = hull.steelCuttingDate!;
      final l = hull.launchingDate!;
      final problems = <String>[
        if (delivery == null) 'Enter the contract delivery date.',
        if (daysBetween(s, l) < minBuildDays) 'Launching must be at least $minBuildDays days after steel cutting.',
        if (delivery != null && daysBetween(l, delivery) < minAfloatDays)
          'Delivery must be at least $minAfloatDays days after launching.',
      ];
      final p = daysBetween(s, l);
      var k = hull.keelLayingDate ?? addDays(s, (p * 0.45).round());
      if (!k.isAfter(s) || !k.isBefore(l)) {
        problems.add('Keel laying must lie between steel cutting and launching.');
        k = addDays(s, (p * 0.45).round());
      }
      if (problems.isNotEmpty) return DraftScheduleResult(const [], problems);

      final d = delivery!;
      final a = daysBetween(l, d);
      DateTime build(double f) => addDays(s, (p * f).round());
      DateTime afloatBack(double f) => addDays(d, -(a * f).round());
      return DraftScheduleResult([
        row(ProductionStage.cutting, s, build(0.55)),
        row(ProductionStage.bending, build(0.05), build(0.60)),
        row(ProductionStage.panel, build(0.08), build(0.65)),
        row(ProductionStage.blockAssembly, build(0.12), build(0.80)),
        row(ProductionStage.blastingPainting, build(0.20), build(0.88)),
        row(ProductionStage.preOutfitting, build(0.25), build(0.92)),
        row(ProductionStage.erection, k, l),
        row(ProductionStage.launching, l, addDays(l, 1)),
        row(ProductionStage.outfitting, addDays(l, 1), afloatBack(0.20)),
        row(ProductionStage.commissioning, addDays(l, (a * 0.45).round()), afloatBack(0.12)),
        row(ProductionStage.seaTrials, afloatBack(0.10), addDays(afloatBack(0.03), -1)),
        row(ProductionStage.delivery, addDays(d, -1), d),
      ], const []);
    }

    if (hull.isRepair) {
      final start = hull.contractDate == null || hull.contractDate!.isBefore(dateOnly(today))
          ? dateOnly(today)
          : hull.contractDate!;
      if (delivery == null) return const DraftScheduleResult([], ['Enter the contract delivery date.']);
      if (!delivery.isAfter(start)) {
        return const DraftScheduleResult([], ['Delivery must be after today and after the contract date.']);
      }
      return DraftScheduleResult([
        row(ProductionStage.dockingRepair, start, delivery, location: hull.locationNodeId),
      ], const []);
    }

    return DraftScheduleResult(const [], [
      if (hull.steelCuttingDate == null) 'Enter the steel cutting date.',
      if (hull.launchingDate == null) 'Enter the launching date.',
      if (delivery == null) 'Enter the contract delivery date.',
    ]);
  }
}
