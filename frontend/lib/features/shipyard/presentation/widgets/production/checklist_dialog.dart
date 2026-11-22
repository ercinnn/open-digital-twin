import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../auth/presentation/providers/auth_providers.dart';
import '../../../domain/entities/checklist_entities.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/entities/quality_entities.dart';
import '../../../domain/repositories/shipyard_repository.dart';
import '../../../domain/services/handover_checklist.dart';
import '../../providers/shipyard_providers.dart';

/// Sea trial / delivery checklist of a hull-level row ([HandoverChecklist]):
/// create it from the template, tick items off (done with a remark, waived
/// with a reason, reopen), add own items. The row can only be reported
/// finished once no required item is open (database, migration 019).
class ChecklistDialog extends ConsumerStatefulWidget {
  const ChecklistDialog({super.key, required this.projectId, required this.row, required this.hull});

  final String projectId;
  final ProductionActivity row;
  final Hull hull;

  static Future<void> show(
    BuildContext context, {
    required String projectId,
    required ProductionActivity row,
    required Hull hull,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => ChecklistDialog(projectId: projectId, row: row, hull: hull),
    );
  }

  @override
  ConsumerState<ChecklistDialog> createState() => _ChecklistDialogState();
}

class _ChecklistDialogState extends ConsumerState<ChecklistDialog> {
  String? _busyId;
  String? _error;

  void _refresh() => ref.invalidate(checklistItemsProvider(widget.projectId));

  Future<void> _run(String busyId, Future<void> Function(ShipyardRepository repo) action) async {
    setState(() {
      _busyId = busyId;
      _error = null;
    });
    try {
      await action(ref.read(shipyardRepositoryProvider));
      _refresh();
    } on ShipyardException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// Remark (done) or reason (waived); `null` = cancelled.
  Future<String?> _askNote(ChecklistItem item, ChecklistStatus status) async {
    final controller = TextEditingController(text: item.notes ?? '');
    final waive = status == ChecklistStatus.waived;
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: Text('${item.code} ${waive ? 'waived' : 'done'}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: const TextStyle(color: AppTheme.textMuted)),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: waive ? 'Reason (required)' : 'Result / remark (optional)',
                    helperText: waive ? 'e.g. postponed to the guarantee period, agreed with the owner' : null,
                    errorText: error,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (waive && controller.text.trim().isEmpty) {
                  setLocal(() => error = 'Enter the reason.');
                  return;
                }
                Navigator.of(dialogContext).pop(controller.text);
              },
              child: Text(waive ? 'Waive' : 'Done'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _set(ChecklistItem item, ChecklistStatus status) async {
    String? notes = item.notes;
    if (status != ChecklistStatus.open) {
      final n = await _askNote(item, status);
      if (n == null || !mounted) return;
      notes = n;
    }
    await _run(item.id, (repo) => repo.setChecklistStatus(item.id, status, notes: notes));
  }

  Future<void> _addOwn(List<ChecklistItem> mine) async {
    final code = TextEditingController();
    final title = TextEditingController();
    var required = true;
    List<String> errors = const [];
    final draft = await showDialog<ChecklistDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: const Text('Add checklist item'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: code,
                  decoration: InputDecoration(
                    labelText: 'Code',
                    hintText: widget.row.stage == ProductionStage.delivery ? 'DL-20' : 'ST-20',
                  ),
                ),
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Item'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: required,
                  onChanged: (v) => setLocal(() => required = v ?? true),
                  title: const Text('Required (blocks finishing the row while open)'),
                ),
                for (final e in errors) Text(e, style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12.5)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final d = ChecklistDraft(
                  projectId: widget.projectId,
                  activityId: widget.row.id,
                  hullId: widget.hull.id,
                  code: code.text,
                  title: title.text,
                  category: widget.row.stage == ProductionStage.delivery
                      ? ChecklistCategory.handover
                      : ChecklistCategory.trial,
                  required: required,
                  sortOrder: mine.fold<int>(0, (m, i) => i.sortOrder > m ? i.sortOrder : m) + 10,
                );
                final e = d.validationErrors(existingCodes: mine.map((i) => i.code));
                if (e.isNotEmpty) {
                  setLocal(() => errors = e);
                  return;
                }
                Navigator.of(dialogContext).pop(d);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    code.dispose();
    title.dispose();
    if (draft == null || !mounted) return;
    await _run('add', (repo) => repo.createChecklistItems([draft]));
  }

  @override
  Widget build(BuildContext context) {
    final projectId = widget.projectId;
    final row = widget.row;
    final itemsAsync = ref.watch(checklistItemsProvider(projectId));
    final activities = ref.watch(activitiesProvider(projectId)).value ?? const <ProductionActivity>[];
    final punch = ref.watch(punchItemsProvider(projectId)).value ?? const <PunchItem>[];
    final canEdit = ref.watch(isEditorProvider);
    final all = itemsAsync.value ?? const <ChecklistItem>[];
    final mine = HandoverChecklist.itemsOf(row, all);
    final drafts = itemsAsync.hasValue ? HandoverChecklist.draftsFor(widget.hull, row, all) : const <ChecklistDraft>[];
    final progress = HandoverChecklist.progressOf(mine);
    final blockers = HandoverChecklist.blockers(row, all, activities);
    final openPunch = punch.where((p) => p.hullId == widget.hull.id && p.isOpen).length;
    final busy = _busyId != null;
    final size = MediaQuery.sizeOf(context);
    final delivery = row.stage == ProductionStage.delivery;

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.hull.hullNo} ${delivery ? 'delivery' : 'sea trials'} checklist'),
          Text(
            [
              row.code,
              '${formatDate(row.plannedStart)} → ${formatDate(row.plannedEnd)}',
              if (row.isDone) 'finished ${formatDate(row.actualEnd)}' else if (row.isActive) 'running',
            ].join(' · '),
            style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted, fontWeight: FontWeight.w400),
          ),
        ],
      ),
      content: SizedBox(
        width: 720,
        height: (size.height * 0.6).clamp(320.0, 620.0),
        child: itemsAsync.isLoading && !itemsAsync.hasValue
            ? const Center(child: CircularProgressIndicator())
            : itemsAsync.hasError
            ? Text(
                'Could not load the checklist: ${itemsAsync.error}',
                style: const TextStyle(color: Color(0xFFFCA5A5)),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      mine.isEmpty
                          ? 'No checklist yet.'
                          : '${progress.done} of ${progress.total} done · ${progress.waived} waived · '
                                '${progress.open} open',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      row.isDone
                          ? 'The row is reported finished.'
                          : blockers.isEmpty
                          ? 'Ready: the row can be reported finished (tap its bar, actual end).'
                          : 'Cannot be reported finished yet: ${blockers.join('; ')}.',
                      style: TextStyle(
                        fontSize: 12,
                        color: row.isDone || blockers.isEmpty ? const Color(0xFF22C55E) : const Color(0xFFF59E0B),
                      ),
                    ),
                    if (canEdit && drafts.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.tonalIcon(
                          onPressed: busy ? null : () => _run('template', (repo) => repo.createChecklistItems(drafts)),
                          icon: _busyId == 'template'
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.playlist_add_check, size: 18),
                          label: Text(
                            mine.isEmpty
                                ? 'Create the checklist (${drafts.length} items)'
                                : 'Add ${drafts.length} template item${drafts.length == 1 ? '' : 's'}',
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    for (final i in mine) _item(i, canEdit, busy, delivery && i.code == 'DL-05' ? openPunch : null),
                    if (canEdit && mine.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: busy ? null : () => _addOwn(mine),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add item…'),
                        ),
                      ),
                    if (_error != null)
                      Container(
                        margin: const EdgeInsets.only(top: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF450A0A),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(_error!, style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12.5)),
                      ),
                  ],
                ),
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  }

  Widget _item(ChecklistItem i, bool canEdit, bool busy, int? openPunch) {
    final details = [
      i.category.label,
      if (!i.required) 'optional',
      if (i.completedAt != null) '${i.status.label.toLowerCase()} ${formatDate(i.completedAt)}',
      if (i.notes != null && i.notes!.isNotEmpty) i.notes!,
      if (openPunch != null) '$openPunch open punch item${openPunch == 1 ? '' : 's'} on the hull',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.outline)),
      ),
      child: Row(
        children: [
          Icon(i.category.icon, size: 18, color: i.status.color),
          const SizedBox(width: 8),
          SizedBox(
            width: 50,
            child: Text(i.code, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i.title, style: const TextStyle(fontSize: 12.5)),
                Text(
                  details.join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: openPunch != null && openPunch > 0 && i.isOpen
                        ? const Color(0xFFF59E0B)
                        : AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_busyId == i.id)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (canEdit && i.isOpen) ...[
            FilledButton.tonal(
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: busy ? null : () => _set(i, ChecklistStatus.done),
              child: const Text('Done'),
            ),
            IconButton(
              tooltip: 'Waive (with a reason)',
              visualDensity: VisualDensity.compact,
              onPressed: busy ? null : () => _set(i, ChecklistStatus.waived),
              icon: const Icon(Icons.do_not_disturb_on_outlined, size: 18),
            ),
            IconButton(
              tooltip: 'Delete item',
              visualDensity: VisualDensity.compact,
              onPressed: busy ? null : () => _run(i.id, (repo) => repo.deleteChecklistItem(i.id)),
              icon: const Icon(Icons.delete_outline, size: 18),
            ),
          ] else ...[
            Text(
              i.status.label,
              style: TextStyle(fontSize: 12, color: i.status.color, fontWeight: FontWeight.w700),
            ),
            if (canEdit)
              IconButton(
                tooltip: 'Reopen',
                visualDensity: VisualDensity.compact,
                onPressed: busy ? null : () => _set(i, ChecklistStatus.open),
                icon: const Icon(Icons.undo, size: 18),
              ),
          ],
        ],
      ),
    );
  }
}
