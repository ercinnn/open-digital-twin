import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../auth/presentation/providers/auth_providers.dart';
import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../../digital_twin/presentation/providers/twin_providers.dart';
import '../../../domain/entities/block_entities.dart';
import '../../../domain/entities/hse_entities.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/entities/resource_entities.dart';
import '../../../domain/services/permit_plan.dart';
import '../../providers/shipyard_providers.dart';
import 'hse_dialogs.dart';
import 'new_permit_dialog.dart';

/// Permits-to-work of one hull block (tab of the block dialog): the permits the
/// block's running / next rows need ([PermitPlan]) with a prefilled request for
/// each missing one, and all permits of the block (tap: approve, activate, close).
class BlockPermitsPanel extends ConsumerStatefulWidget {
  const BlockPermitsPanel({super.key, required this.projectId, required this.block, required this.hull});

  final String projectId;
  final HullBlock block;
  final Hull? hull;

  @override
  ConsumerState<BlockPermitsPanel> createState() => _BlockPermitsPanelState();
}

class _BlockPermitsPanelState extends ConsumerState<BlockPermitsPanel> {
  Future<void> _request({
    required List<TwinComponent> components,
    required List<WorkPermit> permits,
    PermitNeed? need,
  }) async {
    final now = DateTime.now();
    final suggestion = need == null
        ? null
        : PermitPlan.suggest(
            need: need,
            block: widget.block,
            bookings: ref.read(bookingsProvider(widget.projectId)).value ?? const <ResourceBooking>[],
            now: now,
          );
    final area = need?.activity.locationNodeId;
    final saved = await NewPermitDialog.show(
      context,
      projectId: widget.projectId,
      hulls: ref.read(hullsProvider(widget.projectId)).value ?? [?widget.hull],
      components: components,
      zones: ref.read(zonesProvider(widget.projectId)).value ?? const <HseZone>[],
      existing: permits,
      initialComponentId: widget.block.componentId,
      initialHullId: widget.hull?.id,
      activity: need?.activity,
      initialType: need?.type,
      initialDescription: suggestion?.description,
      initialFrom: suggestion?.validFrom,
      initialHours: suggestion?.hours,
      zoneComponentId: area == null ? null : components.where((c) => c.meshNodeId == area).firstOrNull?.id,
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permit requested - approve it next.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectId = widget.projectId;
    final permitsAsync = ref.watch(permitsProvider(projectId));
    final activities = ref.watch(activitiesProvider(projectId)).value ?? const <ProductionActivity>[];
    final components = ref.watch(componentsProvider(projectId)).value ?? const <TwinComponent>[];
    // Kept alive for the request dialog (lift window, zones).
    ref.watch(bookingsProvider(projectId));
    ref.watch(zonesProvider(projectId));
    final canEdit = ref.watch(isEditorProvider);
    final now = DateTime.now();
    final permits = permitsAsync.value ?? const <WorkPermit>[];
    final block = components.where((c) => c.id == widget.block.componentId).firstOrNull;
    final rowsById = {for (final a in activities) a.id: a};
    final mine = permits.where((p) => p.componentId == widget.block.componentId).toList()
      ..sort((a, b) => b.validFrom.compareTo(a.validFrom));
    final needs = PermitPlan.forBlock(block: widget.block, activities: activities, permits: permits, now: now);
    final missing = needs.where((n) => !n.covered).length;

    if (permitsAsync.isLoading && !permitsAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            needs.isEmpty
                ? 'No permit needed now: no permit-bound work of this block runs today or starts within '
                      '${PermitPlan.lookAheadDays} days (cutting, bending and panel work are workshop jobs).'
                : 'NEEDED FOR THE WORK NOW AND IN THE NEXT ${PermitPlan.lookAheadDays} DAYS'
                      '${missing == 0 ? ' - all covered' : ' - $missing missing'}',
            style: needs.isEmpty
                ? const TextStyle(fontSize: 12.5, color: AppTheme.textMuted)
                : const TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 0.8,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
          ),
          const SizedBox(height: 4),
          for (final n in needs) _need(n, canEdit, components, permits, now),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  'PERMITS OF THE BLOCK (${mine.length})',
                  style: const TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 0.8,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (canEdit)
                TextButton.icon(
                  onPressed: () => _request(components: components, permits: permits),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Request permit…'),
                ),
            ],
          ),
          if (mine.isEmpty)
            const Text('No permits for this block yet.', style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted)),
          for (final p in mine) _permit(p, rowsById[p.activityId], block, now),
        ],
      ),
    );
  }

  Widget _need(PermitNeed n, bool canEdit, List<TwinComponent> components, List<WorkPermit> permits, DateTime now) {
    final a = n.activity;
    final running = a.isActive || !dateOnly(a.plannedStart).isAfter(dateOnly(now));
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.outline)),
      ),
      child: Row(
        children: [
          Icon(n.type.icon, size: 18, color: n.type.color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${n.type.label} · ${a.stage.label}', style: const TextStyle(fontSize: 12.5)),
                Text(
                  '${running ? 'running' : 'starts ${formatDate(a.plannedStart)}'} · until ${formatDate(a.plannedEnd)}'
                  '${n.covered ? ' · ${n.permits.map((p) => '${p.permitNo} ${p.status.label.toLowerCase()}').join(', ')}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          if (n.covered)
            const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF22C55E))
          else if (canEdit)
            FilledButton.tonal(
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => _request(components: components, permits: permits, need: n),
              child: const Text('Request'),
            )
          else
            Text(
              'missing',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: running ? const Color(0xFFEF4444) : const Color(0xFFF59E0B),
              ),
            ),
        ],
      ),
    );
  }

  Widget _permit(WorkPermit p, ProductionActivity? row, TwinComponent? block, DateTime now) {
    final live = p.isLive(now);
    final expired = p.isExpired(now);
    final color = live
        ? const Color(0xFF22C55E)
        : expired
        ? const Color(0xFFEF4444)
        : p.status == PermitStatus.closed
        ? AppTheme.textMuted
        : const Color(0xFFF59E0B);
    return InkWell(
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => PermitDialog(permit: p, component: block),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.outline)),
        ),
        child: Row(
          children: [
            Icon(p.type.icon, size: 18, color: p.type.color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${p.permitNo} · ${p.type.label} · ${p.description}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  Text(
                    [
                      '${formatDateTime(p.validFrom)} → ${formatDateTime(p.validTo)}',
                      if (row != null) row.stage.label,
                      if (p.issuedTo != null) p.issuedTo!,
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
              live
                  ? 'Live'
                  : expired
                  ? 'Expired'
                  : p.status.label,
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }
}
