import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../auth/presentation/providers/auth_providers.dart';
import '../../../domain/entities/production_entities.dart';
import '../../providers/shipyard_providers.dart';

/// Details of one schedule row; editors can report progress and actual dates.
class ActivityDialog extends ConsumerStatefulWidget {
  const ActivityDialog({super.key, required this.activity, required this.locationName, this.blockName});

  final ProductionActivity activity;
  final String? locationName;
  final String? blockName;

  static Future<void> show(
    BuildContext context, {
    required ProductionActivity activity,
    String? locationName,
    String? blockName,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => ActivityDialog(activity: activity, locationName: locationName, blockName: blockName),
    );
  }

  @override
  ConsumerState<ActivityDialog> createState() => _ActivityDialogState();
}

class _ActivityDialogState extends ConsumerState<ActivityDialog> {
  late ProductionActivity _draft = widget.activity;
  late final _notes = TextEditingController(text: widget.activity.notes ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool start}) async {
    final today = ref.read(todayProvider);
    final initial = (start ? _draft.actualStart : _draft.actualEnd) ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: addDays(today, -730),
      lastDate: today,
    );
    if (picked == null) return;
    setState(() {
      _draft = start
          ? _draft.copyWith(actualStart: picked)
          : _draft.copyWith(actualEnd: picked, actualStart: _draft.actualStart ?? picked, progressPct: 100);
    });
  }

  Future<void> _save() async {
    final today = ref.read(todayProvider);
    var a = _draft.copyWith(notes: _notes.text.trim().isEmpty ? null : _notes.text.trim());
    if (a.progressPct > 0 && a.actualStart == null) a = a.copyWith(actualStart: today);
    if (a.progressPct >= 100 && a.actualEnd == null) a = a.copyWith(actualEnd: today);
    if (a.progressPct < 100 && a.actualEnd != null) a = a.copyWith(clearActualEnd: true);
    if (a.actualEnd != null && a.actualStart != null && a.actualEnd!.isBefore(a.actualStart!)) {
      a = a.copyWith(actualEnd: a.actualStart);
    }
    setState(() => _saving = true);
    try {
      await ref.read(shipyardRepositoryProvider).updateActivityProgress(a);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e'), backgroundColor: const Color(0xFF7F1D1D)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.activity;
    final today = ref.watch(todayProvider);
    final canEdit = ref.watch(isEditorProvider);
    final late = a.isLate(today);
    final rows = <(String, String)>[
      ('Code', a.code),
      ('Stage', a.stage.label),
      if (widget.blockName != null) ('Block', widget.blockName!),
      ('Location', widget.locationName ?? a.locationNodeId ?? '—'),
      ('Planned', '${formatDate(a.plannedStart)} → ${formatDate(a.plannedEnd)} (${a.plannedDays} d)'),
      ('Actual', '${formatDate(a.actualStart)} → ${a.actualEnd == null ? (a.isActive ? 'running' : '—') : formatDate(a.actualEnd)}'),
      ('Forecast end', formatDate(a.forecastEnd(today))),
    ];
    return AlertDialog(
      title: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: a.stage.color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Text(a.name, style: const TextStyle(fontSize: 17))),
          if (late)
            const Chip(
              visualDensity: VisualDensity.compact,
              label: Text('Late', style: TextStyle(color: Color(0xFFFCA5A5))),
              side: BorderSide(color: Color(0xFFEF4444)),
            ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (k, v) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 110, child: Text(k, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5))),
                      Expanded(child: SelectableText(v, style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Progress', style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: 100,
                      divisions: 20,
                      value: _draft.progressPct.clamp(0, 100).toDouble(),
                      label: '${_draft.progressPct.round()} %',
                      onChanged: canEdit && !_saving ? (v) => setState(() => _draft = _draft.copyWith(progressPct: v)) : null,
                    ),
                  ),
                  SizedBox(width: 44, child: Text('${_draft.progressPct.round()} %', textAlign: TextAlign.end)),
                ],
              ),
              if (canEdit) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _saving ? null : () => _pickDate(start: true),
                      icon: const Icon(Icons.play_circle_outline, size: 18),
                      label: Text('Actual start: ${formatDate(_draft.actualStart)}'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : () => _pickDate(start: false),
                      icon: const Icon(Icons.flag_outlined, size: 18),
                      label: Text('Actual end: ${formatDate(_draft.actualEnd)}'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notes,
                  enabled: !_saving,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
              ] else if ((a.notes ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(a.notes!, style: const TextStyle(color: AppTheme.textMuted)),
              ],
              if (!canEdit)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    'Read-only: sign in with an editor account to report progress.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(canEdit ? 'Cancel' : 'Close')),
        if (canEdit)
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
      ],
    );
  }
}
