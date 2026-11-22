import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../auth/presentation/providers/auth_providers.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/repositories/shipyard_repository.dart';
import '../../../domain/services/handover_checklist.dart';
import '../../providers/shipyard_providers.dart';

/// What the caller should do after [ActivityDialog] closed.
enum ActivityDialogResult {
  editPlan,
  deleted,

  /// Open the materials / inspections / permits of the work package row.
  packageWork,

  /// Open the sea trial / delivery checklist of the row.
  checklist,
}

/// Details of one schedule row; editors can report progress and actual dates,
/// open the plan editor or delete the row.
class ActivityDialog extends ConsumerStatefulWidget {
  const ActivityDialog({super.key, required this.activity, required this.locationName, this.blockName});

  final ProductionActivity activity;
  final String? locationName;
  final String? blockName;

  static Future<ActivityDialogResult?> show(
    BuildContext context, {
    required ProductionActivity activity,
    String? locationName,
    String? blockName,
  }) {
    return showDialog<ActivityDialogResult>(
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

  Future<void> _delete() async {
    final a = widget.activity;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete activity?'),
        content: Text(
          '${a.code} · ${a.name}\n\nThe row is removed from the schedule. This cannot be undone. '
          'Crane / dock bookings linked to it are kept without the link.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB91C1C)),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(shipyardRepositoryProvider).deleteActivity(a.id);
      if (mounted) Navigator.of(context).pop(ActivityDialogResult.deleted);
    } on ShipyardException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: ${e.message}'), backgroundColor: const Color(0xFF7F1D1D)),
      );
    }
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
      // Finishing (or reopening) launching moves the hull in the database (migration 016).
      if (a.stage == ProductionStage.launching && a.hullId != null) ref.invalidate(hullsProvider(a.projectId));
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
        if (HandoverChecklist.hasChecklist(widget.activity))
          TextButton.icon(
            onPressed: _saving ? null : () => Navigator.of(context).pop(ActivityDialogResult.checklist),
            icon: const Icon(Icons.checklist, size: 18),
            label: const Text('Checklist'),
          ),
        if (widget.activity.workPackage != null)
          TextButton.icon(
            onPressed: _saving ? null : () => Navigator.of(context).pop(ActivityDialogResult.packageWork),
            icon: const Icon(Icons.handyman_outlined, size: 18),
            label: const Text('Materials, ITP & permits'),
          ),
        if (canEdit) ...[
          TextButton(
            onPressed: _saving ? null : _delete,
            child: const Text('Delete', style: TextStyle(color: Color(0xFFFCA5A5))),
          ),
          OutlinedButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(ActivityDialogResult.editPlan),
            child: const Text('Edit plan'),
          ),
        ],
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
