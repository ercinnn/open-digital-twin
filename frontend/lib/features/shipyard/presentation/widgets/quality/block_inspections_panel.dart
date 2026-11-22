import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../auth/presentation/providers/auth_providers.dart';
import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../../digital_twin/presentation/providers/twin_providers.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/entities/quality_entities.dart';
import '../../../domain/entities/work_scope.dart';
import '../../../domain/repositories/shipyard_repository.dart';
import '../../../domain/services/inspection_plan.dart';
import '../../providers/shipyard_providers.dart';
import 'inspection_plan_dialogs.dart';
import 'quality_dialogs.dart';

/// ITP inspections of one hull block or afloat outfitting work package (tab of
/// the block / package dialog): its inspection points with their schedule row
/// and result, the ITP draft for its schedule rows that have no points yet,
/// single inspections, and recording results (tap a row).
class BlockInspectionsPanel extends ConsumerStatefulWidget {
  const BlockInspectionsPanel({super.key, required this.projectId, required this.scope, required this.hull});

  final String projectId;
  final WorkScope scope;
  final Hull? hull;

  @override
  ConsumerState<BlockInspectionsPanel> createState() => _BlockInspectionsPanelState();
}

class _BlockInspectionsPanelState extends ConsumerState<BlockInspectionsPanel> {
  bool _saving = false;
  String? _error;

  void _refresh() => ref.invalidate(inspectionsProvider(widget.projectId));

  Future<void> _draft(List<InspectionDraft> drafts) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(shipyardRepositoryProvider).createInspections(drafts);
      _refresh();
    } on ShipyardException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _planOne(List<TwinComponent> components, List<QualityInspection> all, String? componentId) async {
    final saved = await NewInspectionDialog.show(
      context,
      projectId: widget.projectId,
      hulls: ref.read(hullsProvider(widget.projectId)).value ?? [if (widget.hull != null) widget.hull!],
      components: components,
      existing: all,
      initialHullId: widget.hull?.id,
      initialComponentId: componentId,
    );
    if (saved == true && mounted) _refresh();
  }

  Future<void> _open(QualityInspection q, TwinComponent? component) async {
    await showDialog<void>(
      context: context,
      builder: (_) => InspectionDialog(inspection: q, component: component),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final projectId = widget.projectId;
    final inspections = ref.watch(inspectionsProvider(projectId));
    final activities = ref.watch(activitiesProvider(projectId)).value ?? const <ProductionActivity>[];
    final components = ref.watch(componentsProvider(projectId)).value ?? const <TwinComponent>[];
    final canEdit = ref.watch(isEditorProvider);
    final all = inspections.value ?? const <QualityInspection>[];
    final scope = widget.scope;
    final componentIdByNode = {for (final c in components) c.meshNodeId: c.id};
    final componentId = scope.componentIdIn(componentIdByNode);
    final block = components.where((c) => c.id == componentId).firstOrNull;
    final rowsById = {for (final a in activities) a.id: a};
    final blockRows = activities.where(scope.ownsRow).toList();
    final mine = all.where(scope.ownsInspection).toList()
      ..sort((a, b) => a.inspectedAt.compareTo(b.inspectedAt));
    final hull = widget.hull;
    final drafts = hull == null || !inspections.hasValue
        ? const <InspectionDraft>[]
        : InspectionPlan.fromSchedule(
            hull: hull,
            activities: activities,
            componentIdByNode: componentIdByNode,
            existingReferences: all.map((q) => q.referenceNo),
            existing: all,
            componentId: scope.block?.componentId,
            activityId: scope.activityId,
          );
    int count(InspectionResult r) => mine.where((q) => q.result == r).length;
    final openHolds = mine.where((q) => q.isOpenHold).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (inspections.isLoading && !inspections.hasValue)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (inspections.hasError)
            Text('Could not load inspections: ${inspections.error}', style: const TextStyle(color: Color(0xFFFCA5A5)))
          else ...[
            Text(
              mine.isEmpty
                  ? 'No inspections for this ${scope.noun} yet.'
                  : '${mine.length} inspection${mine.length == 1 ? '' : 's'} · ${count(InspectionResult.pass)} pass · '
                        '${count(InspectionResult.pending)} pending · ${count(InspectionResult.fail)} fail'
                        '${count(InspectionResult.conditional) == 0 ? '' : ' · ${count(InspectionResult.conditional)} conditional'}'
                        ' · $openHolds open hold point${openHolds == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
            if (openHolds > 0)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text(
                  'A schedule row with an open hold point (H) cannot be reported finished.',
                  style: TextStyle(fontSize: 12, color: Color(0xFFF59E0B)),
                ),
              ),
            const SizedBox(height: 8),
            for (final q in mine) _row(q, rowsById[q.activityId], block),
            if (canEdit) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _saving || drafts.isEmpty ? null : () => _draft(drafts),
                    icon: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome_motion_outlined, size: 18),
                    label: Text(
                      drafts.isEmpty
                          ? 'ITP planned'
                          : 'Plan ITP: ${drafts.length} point${drafts.length == 1 ? '' : 's'} '
                                '(${drafts.where((d) => d.holdPoint).length} H)',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => _planOne(components, all, componentId),
                    icon: const Icon(Icons.playlist_add_check, size: 18),
                    label: const Text('Plan inspection…'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                blockRows.isEmpty
                    ? 'The block has no schedule rows: draft its schedule first (Production → Plan).'
                    : drafts.isEmpty
                    ? 'Every inspection point of the ${scope.noun}\'s ${blockRows.length} schedule '
                          'row${blockRows.length == 1 ? '' : 's'} is planned.'
                    : 'The ITP draft adds the hold / witness points of the ${scope.noun}\'s schedule rows that have '
                          'none yet (planned on the last day of each row, 10:00).',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: Color(0xFFFCA5A5))),
              ),
          ],
        ],
      ),
    );
  }

  Widget _row(QualityInspection q, ProductionActivity? row, TwinComponent? block) {
    final planned = q.result == InspectionResult.pending;
    return InkWell(
      onTap: () => _open(q, block),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.outline)),
        ),
        child: Row(
          children: [
            Icon(Icons.fact_check_outlined, size: 18, color: q.result.color),
            const SizedBox(width: 8),
            SizedBox(
              width: 28,
              child: q.holdPoint
                  ? Tooltip(
                      message: q.isOpenHold ? 'Hold point - open' : 'Hold point - released',
                      child: Text(
                        'H',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: q.isOpenHold ? const Color(0xFFF59E0B) : const Color(0xFF22C55E),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${q.type.label} · ${q.description ?? q.referenceNo}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  Text(
                    [
                      q.referenceNo,
                      if (row != null) row.stage.label,
                      '${planned ? 'planned' : 'inspected'} ${formatDate(q.inspectedAt)}',
                      if (q.measuredValue != null) '${q.measuredValue} ${q.unit ?? ''}'.trim(),
                      if (q.witnessedBy != null) 'witness: ${q.witnessedBy}',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              q.result.label,
              style: TextStyle(fontSize: 12, color: q.result.color, fontWeight: FontWeight.w700),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }
}
