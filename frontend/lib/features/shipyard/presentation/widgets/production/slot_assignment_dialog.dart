import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../../digital_twin/presentation/providers/twin_providers.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/entities/slot_entities.dart';
import '../../../domain/repositories/shipyard_repository.dart';
import '../../../domain/services/slot_plan.dart';
import '../../providers/shipyard_providers.dart';
import '../scene_actions.dart';

/// Puts the block rows of a hull on the numbered slots of their areas
/// ([SlotPlan.forHull], migration 021): preview per area, then one update per
/// row (slots given up first). A failed run can be resumed: rows already on a
/// slot keep it. Returns a message for the snack bar when something was saved.
class SlotAssignmentDialog extends ConsumerStatefulWidget {
  const SlotAssignmentDialog({
    super.key,
    required this.projectId,
    required this.hulls,
    required this.existing,
    this.initialHullId,
  });

  final String projectId;
  final List<Hull> hulls;
  final List<ProductionActivity> existing;
  final String? initialHullId;

  static Future<String?> show(
    BuildContext context, {
    required String projectId,
    required List<Hull> hulls,
    required List<ProductionActivity> existing,
    String? initialHullId,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SlotAssignmentDialog(
        projectId: projectId,
        hulls: hulls,
        existing: existing,
        initialHullId: initialHullId,
      ),
    );
  }

  @override
  ConsumerState<SlotAssignmentDialog> createState() => _SlotAssignmentDialogState();
}

class _SlotAssignmentDialogState extends ConsumerState<SlotAssignmentDialog> {
  late final List<Hull> _candidates = widget.hulls
      .where((h) => widget.existing.any((a) => a.hullId == h.id && a.componentId != null))
      .toList();
  late String? _hullId = _candidates.any((h) => h.id == widget.initialHullId)
      ? widget.initialHullId
      : _candidates.firstOrNull?.id;
  bool _reassign = false;
  bool _saving = false;
  int _done = 0;
  String? _error;

  Future<void> _save(Hull hull, SlotPlanResult plan) async {
    setState(() {
      _saving = true;
      _done = 0;
      _error = null;
    });
    final repo = ref.read(shipyardRepositoryProvider);
    try {
      // Free first, then assign in start order: no intermediate double booking.
      for (final row in plan.clears) {
        await repo.setActivitySlot(row.id, null);
        if (mounted) setState(() => _done++);
      }
      for (final a in plan.assignments) {
        await repo.setActivitySlot(a.row.id, a.slot.slotNo);
        if (mounted) setState(() => _done++);
      }
      if (mounted) {
        final n = plan.assignments.length;
        Navigator.of(context).pop(
          '${hull.hullNo}: $n row${n == 1 ? '' : 's'} on area slots'
          '${plan.issues.isEmpty ? '' : ', ${plan.issues.length} without a free slot'}.',
        );
      }
    } on ShipyardException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '${e.message} ($_done done; run again to continue).';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final slots = ref.watch(areaSlotsProvider(widget.projectId));
    final slotsLoading = ref.watch(areaSlotListProvider(widget.projectId)).isLoading;
    final components = ref.watch(componentsProvider(widget.projectId)).value ?? const <TwinComponent>[];
    final byNode = {for (final c in components) c.meshNodeId: c};
    final weights = {
      for (final c in components)
        if (c.category == 'hull_structure') c.id: c.weightKg == null ? null : c.weightKg! / 1000,
    };
    final hull = _candidates.where((h) => h.id == _hullId).firstOrNull;
    final plan = hull == null || slots.isEmpty
        ? null
        : SlotPlan.forHull(
            hullId: hull.id,
            activities: widget.existing,
            slots: slots,
            weightsT: weights,
            reassign: _reassign,
          );
    final total = plan == null ? 0 : plan.clears.length + plan.assignments.length;
    return AlertDialog(
      title: const Text('Assign area slots'),
      content: SizedBox(
        width: 640,
        child: _candidates.isEmpty
            ? const Text('No hull has block schedule rows yet. Add blocks and draft the schedule first.')
            : slots.isEmpty
            ? Text(
                slotsLoading
                    ? 'Loading the area slots…'
                    : 'This yard has no area slots yet (table area_slots). Blocks are lined up in their areas.',
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _hullId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Hull', helperText: 'Hulls with block schedule rows.'),
                      items: [
                        for (final h in _candidates)
                          DropdownMenuItem(value: h.id, child: Text(h.displayName, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: _saving ? null : (v) => setState(() => _hullId = v),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: _reassign,
                      onChanged: _saving ? null : (v) => setState(() => _reassign = v ?? false),
                      title: const Text('Plan the slots of not started rows again'),
                      subtitle: const Text('Started and finished rows keep their slot.'),
                    ),
                    const Text(
                      'A block holds its slot from the start of a row until its next row starts (it waits in '
                      'the area). Each row takes the lowest numbered free slot that carries the block; the '
                      'database rejects a second block on a slot in an overlapping planned window.',
                      style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 10),
                    if (plan != null) ...[
                      _Summary(plan: plan, slots: slots, byNode: byNode),
                      if (plan.issues.isNotEmpty)
                        _Message(
                          lines: [
                            for (final i in plan.issues.take(12)) '${i.row.code}: ${i.message}',
                            if (plan.issues.length > 12) '… ${plan.issues.length - 12} more',
                          ],
                          error: true,
                        ),
                      if (plan.isEmpty && plan.issues.isEmpty)
                        const _Message(lines: ['Every open block row of this hull already has a slot.']),
                    ],
                    if (_saving) ...[
                      const SizedBox(height: 10),
                      LinearProgressIndicator(value: total == 0 ? null : _done / total),
                      const SizedBox(height: 4),
                      Text('$_done / $total rows saved', style: const TextStyle(fontSize: 12)),
                    ],
                    if (_error != null) _Message(lines: ['Stopped: $_error'], error: true),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        if (hull != null && plan != null && !plan.isEmpty)
          FilledButton(
            onPressed: _saving ? null : () => _save(hull, plan),
            child: Text(
              'Assign ${plan.assignments.length} slot${plan.assignments.length == 1 ? '' : 's'}'
              '${plan.clears.isEmpty ? '' : ' (free ${plan.clears.length})'}',
            ),
          ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.plan, required this.slots, required this.byNode});

  final SlotPlanResult plan;
  final AreaSlots slots;
  final Map<String, TwinComponent> byNode;

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted);
    const cell = TextStyle(fontSize: 12);
    final counts = plan.countsByArea();
    final waits = <String, int>{};
    final open = <String, int>{};
    for (final a in plan.assignments.where((a) => a.waitOverlap)) {
      waits.update(a.row.locationNodeId!, (v) => v + 1, ifAbsent: () => 1);
    }
    for (final i in plan.issues) {
      open.update(i.row.locationNodeId!, (v) => v + 1, ifAbsent: () => 1);
    }
    final areas = {...counts.keys, ...open.keys}.toList()..sort();
    if (areas.isEmpty) return const SizedBox.shrink();
    return Table(
      columnWidths: const {0: FlexColumnWidth(3), 1: FixedColumnWidth(56), 2: FixedColumnWidth(64), 3: FixedColumnWidth(70), 4: FixedColumnWidth(70)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        const TableRow(
          children: [
            Padding(padding: EdgeInsets.only(bottom: 4), child: Text('AREA', style: head)),
            Text('SLOTS', style: head, textAlign: TextAlign.end),
            Text('ROWS', style: head, textAlign: TextAlign.end),
            Text('WAIT ⚠', style: head, textAlign: TextAlign.end),
            Text('NO SLOT', style: head, textAlign: TextAlign.end),
          ],
        ),
        for (final area in areas)
          TableRow(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppTheme.outline))),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Text(shortComponentName(byNode[area], fallback: area), style: cell, overflow: TextOverflow.ellipsis),
              ),
              Text('${slots.of(area).length}', style: cell, textAlign: TextAlign.end),
              Text('${counts[area] ?? 0}', style: cell, textAlign: TextAlign.end),
              Tooltip(
                message: 'Free for the work window, but another block works on the slot while this one waits',
                child: Text(
                  '${waits[area] ?? 0}',
                  style: cell.copyWith(color: (waits[area] ?? 0) > 0 ? const Color(0xFFFBBF24) : null),
                  textAlign: TextAlign.end,
                ),
              ),
              Text(
                '${open[area] ?? 0}',
                style: cell.copyWith(color: (open[area] ?? 0) > 0 ? const Color(0xFFFCA5A5) : null),
                textAlign: TextAlign.end,
              ),
            ],
          ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.lines, this.error = false});

  final List<String> lines;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? const Color(0xFFFCA5A5) : AppTheme.textMuted;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: error ? const Color(0xFF450A0A) : AppTheme.outline,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final l in lines) Text('• $l', style: TextStyle(color: color, fontSize: 12.5))],
      ),
    );
  }
}
