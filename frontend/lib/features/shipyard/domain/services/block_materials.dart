import '../entities/block_entities.dart';
import '../entities/material_entities.dart';
import '../entities/production_entities.dart';

/// Steel need of one block, split into plates and profiles.
class BlockSteelNeed {
  const BlockSteelNeed({
    required this.block,
    required this.weightT,
    required this.estimated,
    required this.grade,
    required this.plateT,
    required this.profileT,
    this.neededBy,
  });

  final HullBlock block;

  /// Net steel weight of the block (saved weight, else the estimate).
  final double weightT;

  /// [weightT] is the estimate (the block has no saved weight).
  final bool estimated;

  /// Steel grade of the block type (`AH36`, `A` for superstructure).
  final String grade;

  /// Gross quantities incl. the cutting allowance.
  final double plateT;
  final double profileT;

  /// Start of the block's first schedule row (cutting).
  final DateTime? neededBy;
}

/// Outcome of [SteelReservationPlan.draft].
class SteelReservationResult {
  const SteelReservationResult({
    required this.needs,
    required this.drafts,
    required this.totalByItem,
    required this.warnings,
    required this.skippedExisting,
  });

  /// Steel need of every block that has a weight (saved or estimated).
  final List<BlockSteelNeed> needs;

  /// Reservations to create (blocks that already have one of the item are skipped).
  final List<ReservationDraft> drafts;

  /// Quantity per stock item id in the item's unit.
  final Map<String, double> totalByItem;
  final List<String> warnings;

  /// (block, item) pairs left out because a reservation exists already.
  final int skippedExisting;
}

/// Reserves the hull steel of the blocks: block weight -> plates and profiles
/// (+ cutting allowance), from one plate item per steel grade and one profile
/// item, needed at the start of the block's first schedule row.
class SteelReservationPlan {
  const SteelReservationPlan._();

  /// Plate share of the hull steel weight (rest: profiles / stiffeners).
  static const plateShare = 0.80;

  /// Cutting scrap and offcuts on top of the net weight.
  static const allowance = 0.08;

  /// Units a steel reservation can be booked in.
  static const steelUnits = {'t', 'kg'};

  /// Steel grade of a block type: last word of its material (`Shipbuilding Steel AH36` -> `AH36`).
  static String gradeOf(BlockType? type) {
    final words = (type?.material ?? '').trim().split(RegExp(r'\s+'));
    final last = words.isEmpty ? '' : words.last.toUpperCase();
    return last.isEmpty ? 'AH36' : last;
  }

  /// Steel items of [category] usable for a draft, most free stock first.
  static List<MaterialItem> candidates(List<MaterialItem> items, StockCategory category) =>
      items.where((i) => i.type == category && steelUnits.contains(i.unit)).toList()
        ..sort((a, b) => b.available.compareTo(a.available));

  /// Default plate item for [grade]: same grade with the most free stock, else any plate.
  static MaterialItem? defaultPlate(List<MaterialItem> items, String grade) {
    final plates = candidates(items, StockCategory.plate);
    return plates.where((i) => (i.grade ?? '').trim().toUpperCase() == grade).firstOrNull ?? plates.firstOrNull;
  }

  /// Default profile item: the one with the most free stock.
  static MaterialItem? defaultProfile(List<MaterialItem> items) => candidates(items, StockCategory.profile).firstOrNull;

  static double _round(double v) => (v * 10).roundToDouble() / 10;

  /// Steel need per block of [blocks]: saved weight, else [estimatesT] (by component id).
  static List<BlockSteelNeed> needs({
    required List<HullBlock> blocks,
    required Map<String, double> estimatesT,
    required List<ProductionActivity> activities,
  }) {
    final firstStart = <String, DateTime>{};
    for (final a in activities) {
      final id = a.componentId;
      if (id == null) continue;
      final day = DateTime(a.plannedStart.year, a.plannedStart.month, a.plannedStart.day);
      final current = firstStart[id];
      if (current == null || day.isBefore(current)) firstStart[id] = day;
    }
    return [
      for (final b in blocks)
        if (_weightT(b, estimatesT) case final w?)
          BlockSteelNeed(
            block: b,
            weightT: w,
            estimated: !(b.weightKg != null && b.weightKg! > 0),
            grade: gradeOf(b.type),
            plateT: _round(w * plateShare * (1 + allowance)),
            profileT: _round(w * (1 - plateShare) * (1 + allowance)),
            neededBy: firstStart[b.componentId],
          ),
    ];
  }

  static double? _weightT(HullBlock b, Map<String, double> estimatesT) {
    if (b.weightKg != null && b.weightKg! > 0) return b.weightKg! / 1000;
    final e = estimatesT[b.componentId];
    return e != null && e > 0 ? e : null;
  }

  /// Reservations for the blocks of [hull]. [plateByGrade] maps a steel grade to
  /// its plate item (missing grade = no plates for those blocks); [profile] null
  /// = no profiles. A block that already has a reservation (open or issued) of an
  /// item gets none of it again, so the draft can be repeated for new blocks.
  static SteelReservationResult draft({
    required Hull hull,
    required List<HullBlock> blocks,
    required Map<String, double> estimatesT,
    required List<ProductionActivity> activities,
    required Map<String, MaterialItem> plateByGrade,
    required MaterialItem? profile,
    required List<MaterialReservation> existing,
  }) {
    final blockNeeds = needs(blocks: blocks, estimatesT: estimatesT, activities: activities);
    final taken = {for (final r in existing) (r.componentId, r.itemId)};
    final drafts = <ReservationDraft>[];
    final totals = <String, double>{};
    final warnings = <String>[];
    var skipped = 0;

    final noWeight = blocks.length - blockNeeds.length;
    if (noWeight > 0) {
      warnings.add(
        '$noWeight block${noWeight == 1 ? ' has' : 's have'} no weight and no estimate '
        '(enter L / B of the hull or the block weights) - left out.',
      );
    }
    final missingGrades = {
      for (final n in blockNeeds)
        if (!plateByGrade.containsKey(n.grade)) n.grade,
    };
    for (final g in missingGrades) {
      warnings.add('No plate item chosen for grade $g - those blocks get no plates.');
    }
    if (profile == null && blockNeeds.isNotEmpty) warnings.add('No profile item chosen - no profiles reserved.');

    void add(BlockSteelNeed n, MaterialItem item, double tonnes, String part) {
      if (tonnes <= 0) return;
      if (taken.contains((n.block.componentId, item.id))) {
        skipped++;
        return;
      }
      final qty = item.unit == 'kg' ? (tonnes * 1000).roundToDouble() : _round(tonnes);
      drafts.add(
        ReservationDraft(
          projectId: hull.projectId,
          itemId: item.id,
          componentId: n.block.componentId,
          hullId: hull.id,
          quantity: qty,
          neededBy: n.neededBy,
          notes:
              '$part for ${n.block.blockNo}: ${n.weightT.toStringAsFixed(1)} t block'
              '${n.estimated ? ' (estimate)' : ''}, ${(plateShare * 100).round()} / '
              '${((1 - plateShare) * 100).round()} % plates / profiles, +${(allowance * 100).round()} % allowance',
        ),
      );
      totals[item.id] = (totals[item.id] ?? 0) + qty;
    }

    for (final n in blockNeeds) {
      final plate = plateByGrade[n.grade];
      if (plate != null) add(n, plate, n.weightT * plateShare * (1 + allowance), 'Plates');
      if (profile != null) add(n, profile, n.weightT * (1 - plateShare) * (1 + allowance), 'Profiles');
    }
    return SteelReservationResult(
      needs: blockNeeds,
      drafts: drafts,
      totalByItem: {for (final e in totals.entries) e.key: _round(e.value)},
      warnings: warnings,
      skippedExisting: skipped,
    );
  }

  /// Items whose free stock does not cover [totalByItem]: item -> missing quantity.
  static Map<MaterialItem, double> shortages(List<MaterialItem> items, Map<String, double> totalByItem) => {
    for (final i in items)
      if (totalByItem[i.id] case final q? when q > i.available) i: _round(q - (i.available > 0 ? i.available : 0)),
  };
}
