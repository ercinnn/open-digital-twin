import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/repositories/shipyard_repository.dart';
import '../../../domain/services/draft_schedule.dart';
import '../../providers/shipyard_providers.dart';

/// Generates a hull-level draft schedule from the hull milestones, shows it as a
/// preview and inserts it. Only offered for hulls without schedule rows, so a
/// draft never mixes with an existing plan. Returns the hull id when created.
class DraftScheduleDialog extends ConsumerStatefulWidget {
  const DraftScheduleDialog({
    super.key,
    required this.hulls,
    required this.existing,
    required this.areas,
    this.initialHullId,
  });

  final List<Hull> hulls;
  final List<ProductionActivity> existing;
  final List<TwinComponent> areas;
  final String? initialHullId;

  static Future<String?> show(
    BuildContext context, {
    required List<Hull> hulls,
    required List<ProductionActivity> existing,
    required List<TwinComponent> areas,
    String? initialHullId,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DraftScheduleDialog(hulls: hulls, existing: existing, areas: areas, initialHullId: initialHullId),
    );
  }

  @override
  ConsumerState<DraftScheduleDialog> createState() => _DraftScheduleDialogState();
}

class _DraftScheduleDialogState extends ConsumerState<DraftScheduleDialog> {
  late final List<Hull> _candidates = widget.hulls
      .where((h) => !widget.existing.any((a) => a.hullId == h.id))
      .toList();
  late String? _hullId = _candidates.any((h) => h.id == widget.initialHullId)
      ? widget.initialHullId
      : _candidates.firstOrNull?.id;
  bool _saving = false;
  String? _error;

  Hull? get _hull => _candidates.where((h) => h.id == _hullId).firstOrNull;

  DraftScheduleResult? _result() {
    final hull = _hull;
    if (hull == null) return null;
    final maxSort = widget.existing.fold<int>(0, (m, a) => a.sortOrder > m ? a.sortOrder : m);
    return DraftSchedule.forHull(
      hull,
      today: ref.read(todayProvider),
      existingCodes: {for (final a in widget.existing) a.code},
      firstSortOrder: maxSort + 1,
    );
  }

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
    final areaNames = {for (final a in widget.areas) a.meshNodeId: a.name};
    return AlertDialog(
      title: const Text('Draft schedule from milestones'),
      content: SizedBox(
        width: 680,
        child: _candidates.isEmpty
            ? const Text(
                'Every hull already has schedule rows. Add single activities instead, '
                'or delete the rows of a hull to draft it again.',
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
                        helperText: 'Only hulls without schedule rows are listed.',
                      ),
                      items: [
                        for (final h in _candidates)
                          DropdownMenuItem(value: h.id, child: Text(h.displayName, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: _saving ? null : (v) => setState(() => _hullId = v),
                    ),
                    const SizedBox(height: 12),
                    if (result != null && !result.isValid)
                      _Problems(
                        title: 'The milestones of ${_hull!.hullNo} are not enough for a draft:',
                        lines: [
                          ...result.problems,
                          'Fix them on the Dashboard (tap the hull card), then open this dialog again.',
                        ],
                      ),
                    if (result != null && result.isValid) ...[
                      Text(
                        '${result.activities.length} activities, '
                        '${formatDate(result.activities.first.plannedStart)} → '
                        '${formatDate(result.activities.last.plannedEnd)}. '
                        'Every row can be changed or deleted afterwards (tap its bar in the Gantt).',
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
        for (final a in activities)
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
                    Expanded(child: Text(a.stage.label, style: cell, overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
              Text(
                a.locationNodeId == null ? '—' : _shortArea(areaNames[a.locationNodeId] ?? a.locationNodeId!),
                style: cell,
                overflow: TextOverflow.ellipsis,
              ),
              Text(formatDate(a.plannedStart), style: cell),
              Text(formatDate(a.plannedEnd), style: cell),
              Text('${a.plannedDays}', style: cell, textAlign: TextAlign.end),
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
