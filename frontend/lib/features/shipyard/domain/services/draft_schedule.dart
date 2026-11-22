import 'dart:math' as math;

import '../entities/block_entities.dart';
import '../entities/production_entities.dart';
import 'outfitting_packages.dart';

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
String activityCodeFor(String hullNo, ProductionStage stage, Set<String> existingCodes) =>
    _uniqueCode('${_codePart(hullNo)}-${_stageCodes[stage]}', existingCodes);

/// Unique activity code of a block row (`NB-1001`, `SS-201P`, cutting -> `NB1001-SS201P-CUT`).
String blockActivityCodeFor(String hullNo, String blockNo, ProductionStage stage, Set<String> existingCodes) =>
    _uniqueCode('${_codePart(hullNo)}-${_codePart(blockNo)}-${_stageCodes[stage]}', existingCodes);

/// Unique activity code of an afloat outfitting work package (`NB1001-OUTFIT-PIPE`).
String workPackageCodeFor(String hullNo, WorkPackage package, Set<String> existingCodes) =>
    _uniqueCode('${_codePart(hullNo)}-${_stageCodes[ProductionStage.outfitting]}-${package.code}', existingCodes);

String _codePart(String s) => s.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

String _uniqueCode(String base, Set<String> existingCodes) {
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

  /// Keel laying used when the hull has none: 45 % into the steel work.
  static DateTime estimatedKeelLaying(DateTime steelCutting, DateTime launching) =>
      addDays(steelCutting, (daysBetween(steelCutting, launching) * 0.45).round());

  /// Afloat outfitting window of the template: the day after launching until
  /// 20 % of the afloat time before delivery.
  static (DateTime, DateTime) outfittingWindow(DateTime launching, DateTime delivery) =>
      (addDays(launching, 1), addDays(delivery, -(daysBetween(launching, delivery) * 0.20).round()));

  /// With [blocks] (newbuilds), the steel work and the erection are planned per
  /// block ([BlockSchedule]) and only launching ... delivery stay hull rows.
  /// With [outfittingPackages] the afloat outfitting is one row per work package
  /// ([OutfittingPackages]) instead of a single row.
  static DraftScheduleResult forHull(
    Hull hull, {
    required DateTime today,
    Set<String> existingCodes = const {},
    int firstSortOrder = 1,
    List<HullBlock> blocks = const [],
    bool outfittingPackages = false,
    Map<String, String> departmentIdByCode = const {},
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
      var k = hull.keelLayingDate ?? estimatedKeelLaying(s, l);
      if (!k.isAfter(s) || !k.isBefore(l)) {
        problems.add('Keel laying must lie between steel cutting and launching.');
        k = estimatedKeelLaying(s, l);
      }
      if (problems.isNotEmpty) return DraftScheduleResult(const [], problems);

      final blockRows = <ActivityDraft>[];
      if (blocks.isNotEmpty) {
        final r = BlockSchedule._rows(hull, blocks, s, k, l, codes: codes, firstSortOrder: sort);
        if (!r.isValid) return r;
        blockRows.addAll(r.activities);
        sort += blockRows.length;
      }

      final d = delivery!;
      final a = daysBetween(l, d);
      DateTime build(double f) => addDays(s, (p * f).round());
      DateTime afloatBack(double f) => addDays(d, -(a * f).round());
      final (o0, o1) = outfittingWindow(l, d);
      List<ActivityDraft> outfitting() {
        if (!outfittingPackages) return [row(ProductionStage.outfitting, o0, o1)];
        final rows = OutfittingPackages.rows(
          hull,
          o0,
          o1,
          codes: codes,
          firstSortOrder: sort,
          departmentIdByCode: departmentIdByCode,
        );
        sort += rows.length;
        return rows;
      }

      return DraftScheduleResult([
        if (blocks.isEmpty) ...[
          row(ProductionStage.cutting, s, build(0.55)),
          row(ProductionStage.bending, build(0.05), build(0.60)),
          row(ProductionStage.panel, build(0.08), build(0.65)),
          row(ProductionStage.blockAssembly, build(0.12), build(0.80)),
          row(ProductionStage.blastingPainting, build(0.20), build(0.88)),
          row(ProductionStage.preOutfitting, build(0.25), build(0.92)),
          row(ProductionStage.erection, k, l, location: BlockSchedule.berthOf(hull)),
        ] else
          ...blockRows,
        row(ProductionStage.launching, l, addDays(l, 1), location: BlockSchedule.berthOf(hull)),
        ...outfitting(),
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

/// Block-level draft: every block runs its own chain of steel stages in the
/// shops and is then erected on the berth (or in the dry dock), one after the
/// other in erection sequence between keel laying and launching. The rows move
/// the block meshes in 3D (`ProductionSchedule.placementsAt`).
///
/// * Erection: the sequence is spread evenly over keel laying -> launching
///   (minus a few days of launch preparation); each erection takes 1-4 days.
/// * Shops: the chain is back-scheduled to end [readyBufferDays] before the
///   erection and never starts before steel cutting (the first block starts on
///   it). When the time is too short the stages are shortened, 1 day minimum.
/// * Stage days depend on the block type (curved shell -> bending; engine room,
///   superstructure, thruster and stern -> pre-outfitting) and on the weight.
class BlockSchedule {
  const BlockSchedule._();

  static const readyBufferDays = 4;

  /// Standard stage days of a block of about [referenceWeightT].
  static const stageDays = <ProductionStage, int>{
    ProductionStage.cutting: 5,
    ProductionStage.bending: 4,
    ProductionStage.panel: 7,
    ProductionStage.blockAssembly: 14,
    ProductionStage.blastingPainting: 6,
    ProductionStage.preOutfitting: 8,
  };
  static const referenceWeightT = 80.0;

  /// Block types with curved shell plates (bending press).
  static const curvedTypes = {'BLG', 'BOW', 'BB', 'BT', 'FC', 'AFT', 'STF', 'SKG'};

  /// Block types that get pipes, seats and equipment before erection.
  static const outfittedTypes = {'ER', 'ERS', 'ERF', 'CAS', 'ACC', 'WH', 'FUN', 'MST', 'BT', 'AFT'};

  /// Yard area of erection and launching: the dry dock for hulls lying there.
  static String? berthOf(Hull hull) => hull.locationNodeId == stageDefaultLocations[ProductionStage.dockingRepair]
      ? hull.locationNodeId
      : stageDefaultLocations[ProductionStage.erection];

  /// Shop stages of a block, in order.
  static List<ProductionStage> stagesOf(BlockType? type) => [
    ProductionStage.cutting,
    if (curvedTypes.contains(type?.code)) ProductionStage.bending,
    ProductionStage.panel,
    ProductionStage.blockAssembly,
    ProductionStage.blastingPainting,
    if (outfittedTypes.contains(type?.code)) ProductionStage.preOutfitting,
  ];

  /// Standard days per shop stage of [block] (heavier blocks take longer).
  static List<int> daysOf(HullBlock block) {
    final w = block.weightKg;
    final f = w == null || w <= 0 ? 1.0 : math.sqrt(w / 1000 / referenceWeightT).clamp(0.6, 1.6);
    return [for (final s in stagesOf(block.type)) math.max(1, (stageDays[s]! * f).round())];
  }

  /// Rows for the blocks of a hull that already has a schedule: [blocks] are all
  /// blocks of the hull (they define the erection slots), rows are made only for
  /// those in [only] (default: all).
  static DraftScheduleResult forBlocks(
    Hull hull,
    List<HullBlock> blocks, {
    Set<String>? only,
    Set<String> existingCodes = const {},
    int firstSortOrder = 1,
  }) {
    if (hull.isRepair) return const DraftScheduleResult([], ['Repairs have no block schedule.']);
    final s = hull.steelCuttingDate;
    final l = hull.launchingDate;
    if (s == null || l == null) {
      return DraftScheduleResult(const [], [
        if (s == null) 'Enter the steel cutting date.',
        if (l == null) 'Enter the launching date.',
      ]);
    }
    if (daysBetween(s, l) < DraftSchedule.minBuildDays) {
      return const DraftScheduleResult([], [
        'Launching must be at least ${DraftSchedule.minBuildDays} days after steel cutting.',
      ]);
    }
    final k = hull.keelLayingDate ?? DraftSchedule.estimatedKeelLaying(s, l);
    if (!k.isAfter(s) || !k.isBefore(l)) {
      return const DraftScheduleResult([], ['Keel laying must lie between steel cutting and launching.']);
    }
    return _rows(hull, blocks, s, k, l, only: only, codes: {...existingCodes}, firstSortOrder: firstSortOrder);
  }

  static DraftScheduleResult _rows(
    Hull hull,
    List<HullBlock> blocks,
    DateTime s,
    DateTime k,
    DateTime l, {
    Set<String>? only,
    required Set<String> codes,
    required int firstSortOrder,
  }) {
    if (blocks.isEmpty) return const DraftScheduleResult([], ['The hull has no blocks.']);
    final ordered = [...blocks]
      ..sort((a, b) {
        final c = a.erectionSequence.compareTo(b.erectionSequence);
        return c != 0 ? c : a.blockNo.compareTo(b.blockNo);
      });
    final needed = ordered.fold<int>(0, (m, b) => math.max(m, stagesOf(b.type).length));
    if (daysBetween(s, k) < needed) {
      return DraftScheduleResult(const [], [
        'Keel laying must be at least $needed days after steel cutting to build the first block.',
      ]);
    }

    final erectionDays = daysBetween(k, l);
    final window = math.max(1, erectionDays - math.min(7, erectionDays ~/ 5));
    final spacing = window / ordered.length;
    final erectDays = (spacing * 1.5).round().clamp(1, 4);
    final berth = berthOf(hull);
    var sort = firstSortOrder;
    final rows = <ActivityDraft>[];

    ActivityDraft row(HullBlock b, ProductionStage stage, DateTime start, DateTime end, String? location) {
      final code = blockActivityCodeFor(hull.hullNo, b.blockNo, stage, codes);
      codes.add(code);
      return ActivityDraft(
        projectId: hull.projectId,
        hullId: hull.id,
        componentId: b.componentId,
        code: code,
        name: '${hull.hullNo} ${b.blockNo} ${stage.label}',
        stage: stage,
        plannedStart: start,
        plannedEnd: end.isAfter(start) ? end : addDays(start, 1),
        locationNodeId: location,
        sortOrder: sort++,
      );
    }

    for (final (i, b) in ordered.indexed) {
      if (only != null && !only.contains(b.componentId)) continue;
      final erectStart = addDays(k, (i * spacing).floor());
      final erectEndRaw = addDays(erectStart, erectDays);
      final erectEnd = erectEndRaw.isAfter(l) ? l : erectEndRaw;
      final stages = stagesOf(b.type);
      final available = daysBetween(s, erectStart);
      final days = fitDays(daysOf(b), available);
      final lead = days.fold<int>(0, (a, d) => a + d);
      final latest = addDays(erectStart, -math.min(lead + readyBufferDays, available));
      var start = i == 0 || latest.isBefore(s) ? s : latest;
      for (final (j, stage) in stages.indexed) {
        final end = addDays(start, days[j]);
        rows.add(row(b, stage, start, end, stageDefaultLocations[stage]));
        start = end;
      }
      rows.add(row(b, ProductionStage.erection, erectStart, erectEnd, berth));
    }
    return DraftScheduleResult(rows, const []);
  }

  /// [days] shortened proportionally to fill exactly [total] days (largest
  /// remainders round up; 1 day minimum each, taken from the longest stages).
  static List<int> fitDays(List<int> days, int total) {
    final sum = days.fold<int>(0, (a, d) => a + d);
    if (sum <= total) return days;
    final exact = [for (final d in days) d * total / sum];
    final fitted = [for (final e in exact) math.max(1, e.floor())];
    var diff = total - fitted.fold<int>(0, (a, d) => a + d);
    final byRemainder = List.generate(days.length, (j) => j)
      ..sort((a, b) => (exact[b] - exact[b].floor()).compareTo(exact[a] - exact[a].floor()));
    for (final j in byRemainder) {
      if (diff <= 0) break;
      fitted[j]++;
      diff--;
    }
    while (diff < 0) {
      var longest = 0;
      for (var j = 1; j < fitted.length; j++) {
        if (fitted[j] > fitted[longest]) longest = j;
      }
      if (fitted[longest] <= 1) break;
      fitted[longest]--;
      diff++;
    }
    return fitted;
  }

}
