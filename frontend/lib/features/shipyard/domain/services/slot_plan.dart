import '../entities/production_entities.dart';
import '../entities/slot_entities.dart';

/// A block row and the slot it gets.
class SlotAssignment {
  const SlotAssignment(this.row, this.slot, {this.waitOverlap = false});

  final ProductionActivity row;
  final AreaSlot slot;

  /// The slot is free for the row's own work window, but another block works
  /// there while this one still waits for its next stage (the database only
  /// checks the work windows).
  final bool waitOverlap;
}

/// A row that gets no slot, with the reason.
class SlotIssue {
  const SlotIssue(this.row, this.message);

  final ProductionActivity row;
  final String message;
}

class SlotPlanResult {
  const SlotPlanResult({required this.clears, required this.assignments, required this.issues});

  /// Not started rows whose slot is given up first (re-assignment).
  final List<ProductionActivity> clears;
  final List<SlotAssignment> assignments;
  final List<SlotIssue> issues;

  bool get isEmpty => clears.isEmpty && assignments.isEmpty;

  /// Assignments per area mesh id.
  Map<String, int> countsByArea() {
    final result = <String, int>{};
    for (final a in assignments) {
      result.update(a.row.locationNodeId!, (v) => v + 1, ifAbsent: () => 1);
    }
    return result;
  }
}

/// Puts the block rows of a hull on the numbered slots of their areas
/// (migration 021). A block holds its slot from the start of its row until its
/// next row starts (it waits in the area), at least until the row's planned
/// end. Rows are planned in start order; each takes the lowest numbered slot
/// that carries the block and is free for that whole stay, else - still valid
/// for the database, which only compares work windows - one free for its work
/// window ([SlotAssignment.waitOverlap]). Rows already on a slot keep it (also
/// those of other hulls); finished rows are left alone.
class SlotPlan {
  const SlotPlan._();

  /// Rows of one block ordered by planned start.
  static List<ProductionActivity> _ordered(Iterable<ProductionActivity> rows) => rows.toList()
    ..sort((a, b) {
      final c = a.plannedStart.compareTo(b.plannedStart);
      return c != 0 ? c : a.sortOrder.compareTo(b.sortOrder);
    });

  /// [start, end) the block of [row] stays in the row's area.
  static (DateTime, DateTime) stayOf(ProductionActivity row, List<ProductionActivity> blockRows) {
    final ordered = _ordered(blockRows);
    final i = ordered.indexWhere((r) => r.id == row.id);
    var end = row.plannedEnd;
    if (i >= 0 && i + 1 < ordered.length) {
      final next = ordered[i + 1].plannedStart;
      if (next.isAfter(end)) end = next;
    }
    return (row.plannedStart, end);
  }

  static bool _overlaps((DateTime, DateTime) a, (DateTime, DateTime) b) => a.$1.isBefore(b.$2) && b.$1.isBefore(a.$2);

  /// [weightsT] = block weight in tonnes by component id (missing / `null` =
  /// unknown, no load check). [reassign] gives up the slots of the hull's rows
  /// that have not started and plans them again.
  static SlotPlanResult forHull({
    required String hullId,
    required List<ProductionActivity> activities,
    required AreaSlots slots,
    Map<String, double?> weightsT = const {},
    bool reassign = false,
  }) {
    final byBlock = <String, List<ProductionActivity>>{};
    for (final a in activities) {
      if (a.componentId != null) byBlock.putIfAbsent(a.componentId!, () => []).add(a);
    }
    bool slotted(ProductionActivity a) => a.componentId != null && slots.of(a.locationNodeId).isNotEmpty;

    final clears = <ProductionActivity>[
      if (reassign)
        for (final a in activities)
          if (a.hullId == hullId && slotted(a) && a.slotNo != null && a.isNotStarted) a,
    ];
    final cleared = {for (final a in clears) a.id};
    final todo = _ordered(
      activities.where(
        (a) => a.hullId == hullId && slotted(a) && !a.isDone && (a.slotNo == null || cleared.contains(a.id)),
      ),
    );

    // Occupation per area + slot: (stay, work window) of every row keeping its slot.
    final taken = <(String, int), List<((DateTime, DateTime), (DateTime, DateTime))>>{};
    void occupy(ProductionActivity a, int slotNo) {
      final stay = stayOf(a, byBlock[a.componentId] ?? [a]);
      taken.putIfAbsent((a.locationNodeId!, slotNo), () => []).add((stay, (a.plannedStart, a.plannedEnd)));
    }

    for (final a in activities) {
      if (a.slotNo != null && a.locationNodeId != null && !cleared.contains(a.id)) occupy(a, a.slotNo!);
    }

    final assignments = <SlotAssignment>[];
    final issues = <SlotIssue>[];
    for (final row in todo) {
      final area = row.locationNodeId!;
      final weight = weightsT[row.componentId];
      final candidates = slots.of(area).where((s) => s.carries(weight)).toList();
      if (candidates.isEmpty) {
        issues.add(SlotIssue(row, 'no slot of ${_short(area)} carries ${weight!.toStringAsFixed(1)} t'));
        continue;
      }
      final stay = stayOf(row, byBlock[row.componentId] ?? [row]);
      final work = (row.plannedStart, row.plannedEnd);
      AreaSlot? pick;
      var waitOverlap = false;
      for (final s in candidates) {
        if (!(taken[(area, s.slotNo)] ?? const []).any((t) => _overlaps(t.$1, stay))) {
          pick = s;
          break;
        }
      }
      if (pick == null) {
        for (final s in candidates) {
          if (!(taken[(area, s.slotNo)] ?? const []).any((t) => _overlaps(t.$2, work))) {
            pick = s;
            waitOverlap = true;
            break;
          }
        }
      }
      if (pick == null) {
        issues.add(
          SlotIssue(
            row,
            'all ${candidates.length} slots of ${_short(area)} are taken '
            '${formatDate(row.plannedStart)} → ${formatDate(row.plannedEnd)}',
          ),
        );
        continue;
      }
      assignments.add(SlotAssignment(row, pick, waitOverlap: waitOverlap));
      occupy(row, pick.slotNo);
    }
    return SlotPlanResult(clears: clears, assignments: assignments, issues: issues);
  }

  /// `NODE_A08_BLOCK_ASSEMBLY_HALL` -> `A08`.
  static String _short(String areaNodeId) {
    final m = RegExp(r'^NODE_(A\d+)').firstMatch(areaNodeId);
    return m?.group(1) ?? areaNodeId;
  }
}
