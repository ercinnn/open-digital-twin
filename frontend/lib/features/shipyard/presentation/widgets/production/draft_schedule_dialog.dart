import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../domain/entities/block_entities.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/repositories/shipyard_repository.dart';
import '../../../domain/services/draft_schedule.dart';
import '../../providers/shipyard_providers.dart';

/// Generates a draft schedule from the hull milestones, shows it as a preview
/// and inserts it. Hulls without schedule rows get a full draft (steel work per
/// block when the hull has blocks, else hull level); hulls with rows are only
/// offered for blocks that have no rows yet. Returns the hull id when created.
class DraftScheduleDialog extends ConsumerStatefulWidget {
  const DraftScheduleDialog({
    super.key,
    required this.hulls,
    required this.existing,
    required this.areas,
    required this.components,
    this.initialHullId,
  });

  final List<Hull> hulls;
  final List<ProductionActivity> existing;
  final List<TwinComponent> areas;
  final List<TwinComponent> components;
  final String? initialHullId;

  static Future<String?> show(
    BuildContext context, {
    required List<Hull> hulls,
    required List<ProductionActivity> existing,
    required List<TwinComponent> areas,
    required List<TwinComponent> components,
    String? initialHullId,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DraftScheduleDialog(
        hulls: hulls,
        existing: existing,
        areas: areas,
        components: components,
        initialHullId: initialHullId,
      ),
    );
  }

  @override
  ConsumerState<DraftScheduleDialog> createState() => _DraftScheduleDialogState();
}

class _DraftScheduleDialogState extends ConsumerState<DraftScheduleDialog> {
  late final Map<String, List<HullBlock>> _blocks = {
    for (final h in widget.hulls) h.id: blocksOfHull(widget.components, h.hullNo),
  };
  late final Set<String> _scheduledComponents = {
    for (final a in widget.existing)
      if (a.componentId != null) a.componentId!,
  };
  late final List<Hull> _candidates = widget.hulls
      .where((h) => !_hasRows(h) || (!h.isRepair && _unscheduled(h).isNotEmpty))
      .toList();
  late String? _hullId = _candidates.any((h) => h.id == widget.initialHullId)
      ? widget.initialHullId
      : _candidates.firstOrNull?.id;
  bool _perBlock = true;
  bool _saving = false;
  String? _error;

  Hull? get _hull => _candidates.where((h) => h.id == _hullId).firstOrNull;

  bool _hasRows(Hull h) => widget.existing.any((a) => a.hullId == h.id);

  List<HullBlock> _unscheduled(Hull h) =>
      _blocks[h.id]!.where((b) => !_scheduledComponents.contains(b.componentId)).toList();

  DraftScheduleResult? _result() {
    final hull = _hull;
    if (hull == null) return null;
    final maxSort = widget.existing.fold<int>(0, (m, a) => a.sortOrder > m ? a.sortOrder : m);
    final codes = {for (final a in widget.existing) a.code};
    if (_hasRows(hull)) {
      return BlockSchedule.forBlocks(
        hull,
        _blocks[hull.id]!,
        only: {for (final b in _unscheduled(hull)) b.componentId},
        existingCodes: codes,
        firstSortOrder: maxSort + 1,
      );
    }
    return DraftSchedule.forHull(
      hull,
      today: ref.read(todayProvider),
      existingCodes: codes,
      firstSortOrder: maxSort + 1,
      blocks: _perBlock && !hull.isRepair ? _blocks[hull.id]! : const [],
    );
  }

  String _summary(Hull hull, DraftScheduleResult result) {
    final blockRows = result.activities.where((a) => a.componentId != null);
    final blockCount = {for (final a in blockRows) a.componentId}.length;
    final span = '${formatDate(result.activities.map((a) => a.plannedStart).reduce(_min))} → '
        '${formatDate(result.activities.map((a) => a.plannedEnd).reduce(_max))}';
    if (_hasRows(hull)) {
      return '$blockCount block${blockCount == 1 ? '' : 's'} without schedule rows get ${result.activities.length} '
          'activities ($span), slotted into the erection sequence of all ${_blocks[hull.id]!.length} blocks. '
          'The existing rows of ${hull.hullNo} stay unchanged.';
    }
    final perBlock = blockCount == 0
        ? ''
        : ' Steel work and erection are planned per block ($blockCount blocks, ${blockRows.length} rows); '
              'the blocks move through the shops to the berth on the 3D timeline.';
    return '${result.activities.length} activities, $span.$perBlock '
        'Every row can be changed or deleted afterwards (tap its bar in the Gantt).';
  }

  static DateTime _min(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
  static DateTime _max(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

  Future<void> _create(DraftScheduleResult result) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(shipyardRepositoryProvider).createActivities(result.activities);
      if (mounted) Navigator.of(context).pop(_hullId);
    } on ShipyardException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result();
    final hull = _hull;
    final blockCount = hull == null ? 0 : _blocks[hull.id]!.length;
    final areaNames = {for (final a in widget.areas) a.meshNodeId: a.name};
    return AlertDialog(
      title: Text(hull != null && _hasRows(hull) ? 'Schedule new blocks' : 'Draft schedule from milestones'),
      content: SizedBox(
        width: 680,
        child: _candidates.isEmpty
            ? const Text(
                'Every hull already has schedule rows and every block is scheduled. Add single activities '
                'instead, or delete the rows of a hull to draft it again.',
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _hullId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Hull',
                        helperText: 'Hulls without schedule rows, or with blocks that have none.',
                      ),
                      items: [
                        for (final h in _candidates)
                          DropdownMenuItem(value: h.id, child: Text(h.displayName, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: _saving ? null : (v) => setState(() => _hullId = v),
                    ),
                    if (hull != null && !hull.isRepair && !_hasRows(hull) && blockCount > 0)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: _perBlock,
                        onChanged: _saving ? null : (v) => setState(() => _perBlock = v ?? true),
                        title: Text('Plan steel work and erection per block ($blockCount blocks)'),
                        subtitle: const Text(
                          'Each block gets its own cutting → coating chain and erection slot (erection sequence). '
                          'Off: one hull-level row per stage.',
                        ),
                      ),
                    const SizedBox(height: 12),
                    if (result != null && !result.isValid)
                      _Problems(
                        title: 'The milestones of ${hull!.hullNo} are not enough for a draft:',
                        lines: [
                          ...result.problems,
                          'Fix them on the Dashboard (tap the hull card), then open this dialog again.',
                        ],
                      ),
                    if (result != null && result.isValid) ...[
                      Text(
                        _summary(hull!, result),
                        style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                      ),
                      const SizedBox(height: 8),
                      _Preview(activities: result.activities, areaNames: areaNames),
                    ],
                    if (_error != null) _Problems(title: 'Not created:', lines: [_error!]),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        if (result != null && result.isValid)
          FilledButton(
            onPressed: _saving ? null : () => _create(result),
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Create ${result.activities.length} activities'),
          ),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.activities, required this.areaNames});

  final List<ActivityDraft> activities;
  final Map<String, String> areaNames;

  /// Hull rows one by one; block rows summed up per stage (count, first start, last end).
  List<({ProductionStage stage, String label, String? location, DateTime start, DateTime end})> _lines() {
    final lines = <({ProductionStage stage, String label, String? location, DateTime start, DateTime end})>[];
    final byStage = <ProductionStage, List<ActivityDraft>>{};
    for (final a in activities) {
      if (a.componentId == null) {
        lines.add((stage: a.stage, label: a.stage.label, location: a.locationNodeId, start: a.plannedStart, end: a.plannedEnd));
      } else {
        byStage.putIfAbsent(a.stage, () => []).add(a);
      }
    }
    final blockLines = [
      for (final stage in ProductionStage.values)
        if (byStage[stage] case final rows?)
          (
            stage: stage,
            label: '${stage.label} · ${rows.length} block${rows.length == 1 ? '' : 's'}',
            location: rows.first.locationNodeId,
            start: rows.map((a) => a.plannedStart).reduce((a, b) => a.isBefore(b) ? a : b),
            end: rows.map((a) => a.plannedEnd).reduce((a, b) => a.isAfter(b) ? a : b),
          ),
    ];
    return [...blockLines, ...lines];
  }

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted);
    const cell = TextStyle(fontSize: 12);
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2.2),
        1: FlexColumnWidth(1.6),
        2: FixedColumnWidth(86),
        3: FixedColumnWidth(86),
        4: FixedColumnWidth(44),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        const TableRow(
          children: [
            Padding(padding: EdgeInsets.only(bottom: 4), child: Text('STAGE', style: head)),
            Text('LOCATION', style: head),
            Text('START', style: head),
            Text('END', style: head),
            Text('DAYS', style: head, textAlign: TextAlign.end),
          ],
        ),
        for (final a in _lines())
          TableRow(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppTheme.outline))),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: a.stage.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: Text(a.label, style: cell, overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
              Text(
                a.location == null ? '—' : _shortArea(areaNames[a.location] ?? a.location!),
                style: cell,
                overflow: TextOverflow.ellipsis,
              ),
              Text(formatDate(a.start), style: cell),
              Text(formatDate(a.end), style: cell),
              Text('${daysBetween(a.start, a.end)}', style: cell, textAlign: TextAlign.end),
            ],
          ),
      ],
    );
  }

  /// "Area 05 - CNC Cutting Shop" -> "CNC Cutting Shop".
  static String _shortArea(String name) {
    final i = name.indexOf(' - ');
    return i < 0 ? name : name.substring(i + 3);
  }
}

class _Problems extends StatelessWidget {
  const _Problems({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFF450A0A), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12.5, fontWeight: FontWeight.w600)),
          for (final l in lines) Text('• $l', style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12.5)),
        ],
      ),
    );
  }
}
