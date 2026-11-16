import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/async_states.dart';
import '../../../../auth/presentation/providers/auth_providers.dart';
import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../../digital_twin/presentation/providers/twin_providers.dart';
import '../../../domain/entities/hse_entities.dart';
import '../../../domain/entities/production_entities.dart';
import '../../providers/scene_view_providers.dart';
import '../../providers/shipyard_providers.dart';
import '../scene_actions.dart';
import 'hse_dialogs.dart';
import 'new_permit_dialog.dart';

/// Work permits, hazard zones and incidents with their 3D layers.
class HseTab extends ConsumerWidget {
  const HseTab({super.key, required this.projectId, required this.actions});

  final String projectId;
  final SceneActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permits = ref.watch(permitsProvider(projectId));
    final zones = ref.watch(zonesProvider(projectId)).value ?? const <HseZone>[];
    final incidents = ref.watch(incidentsProvider(projectId)).value ?? const <HseIncident>[];
    final components = ref.watch(componentsProvider(projectId)).value ?? const <TwinComponent>[];
    final byId = componentsById(components);
    final view = ref.watch(sceneViewProvider(projectId));
    final notifier = ref.read(sceneViewProvider(projectId).notifier);
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final canEdit = ref.watch(isEditorProvider);
    final selected = ref.watch(selectedComponentProvider(projectId));
    final hulls = ref.watch(hullsProvider(projectId)).value ?? const <Hull>[];

    if (permits.hasError) return ErrorView(error: permits.error!);
    if (!permits.hasValue) return const LoadingView();
    final permitList = permits.value!.where((p) => p.status != PermitStatus.closed).toList()
      ..sort((a, b) => a.status.index.compareTo(b.status.index) != 0
          ? b.status.index.compareTo(a.status.index)
          : a.validTo.compareTo(b.validTo));
    final summary = HseSummary.of(incidents, permits.value!, now);

    Widget kpi(String label, String value, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted)),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      kpi('days without lost-time injury', summary.daysSinceLostTime?.toString() ?? '—', const Color(0xFF22C55E)),
                      kpi('live permits', '${summary.livePermits}', const Color(0xFFF97316)),
                      kpi('open incidents', '${summary.openIncidents}', const Color(0xFFEF4444)),
                      kpi('near misses (30 d)', '${summary.nearMisses30d}', const Color(0xFFFACC15)),
                      const SizedBox(width: 8),
                      FilterChip(label: const Text('Pins'), selected: view.hsePins, onSelected: notifier.setHsePins),
                      const SizedBox(width: 6),
                      FilterChip(label: const Text('Blink permit areas'), selected: view.permitBlink, onSelected: notifier.setPermitBlink),
                      const SizedBox(width: 6),
                      FilterChip(
                        label: const Text('Zones overlay'),
                        selected: view.overlay == SceneOverlay.hseZones,
                        onSelected: (v) => notifier.setOverlay(v ? SceneOverlay.hseZones : null),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (canEdit) ...[
                FilledButton.icon(
                  onPressed: () async {
                    final saved = await NewPermitDialog.show(
                      context,
                      projectId: projectId,
                      hulls: hulls,
                      components: components,
                      zones: zones,
                      existing: permits.value!,
                      initialComponentId: selected?.id,
                    );
                    if (saved == true && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Permit requested. Tap it to approve and activate it.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.assignment_add, size: 18),
                  label: const Text('Request permit'),
                ),
                const SizedBox(width: 6),
              ],
              FilledButton.tonalIcon(
                onPressed: canEdit
                    ? () => showDialog<void>(
                        context: context,
                        builder: (_) => ReportIncidentDialog(projectId: projectId, component: selected),
                      )
                    : null,
                icon: const Icon(Icons.report_outlined, size: 18),
                label: const Text('Report'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: ListView(
                  children: [
                    const _Header('WORK PERMITS'),
                    for (final p in permitList)
                      ListTile(
                        dense: true,
                        leading: Icon(p.type.icon, color: p.status == PermitStatus.suspended ? AppTheme.textMuted : p.type.color),
                        title: Text('${p.permitNo} · ${p.description}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                        subtitle: Text(
                          '${shortComponentName(byId[p.componentId])} · ${p.status.label}'
                          '${p.status == PermitStatus.active ? ' · ${formatRemaining(p.remaining(now))}' : ' · from ${formatDateTime(p.validFrom)}'}'
                          '${p.gasO2 == null ? '' : ' · O₂ ${p.gasO2}% LEL ${p.gasLel}%'}',
                          style: TextStyle(fontSize: 11, color: p.isExpired(now) ? const Color(0xFFFCA5A5) : AppTheme.textMuted),
                        ),
                        onTap: () {
                          final c = byId[p.componentId];
                          if (c != null) actions.selectNode(c.meshNodeId);
                          showDialog<void>(context: context, builder: (_) => PermitDialog(permit: p, component: c));
                        },
                      ),
                    if (permitList.isEmpty)
                      const Padding(padding: EdgeInsets.all(16), child: Text('No open permits.', style: TextStyle(color: AppTheme.textMuted))),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                flex: 4,
                child: ListView(
                  children: [
                    const _Header('INCIDENTS'),
                    for (final i in incidents)
                      ListTile(
                        dense: true,
                        leading: Icon(Icons.report_outlined, color: i.severity.color, size: 20),
                        title: Text(i.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                        subtitle: Text(
                          '${i.incidentNo} · ${i.severity.label} · ${formatDate(i.occurredAt)} · ${i.status}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onTap: () {
                          final c = i.componentId == null ? null : byId[i.componentId];
                          if (c != null) actions.selectNode(c.meshNodeId);
                          showDialog<void>(context: context, builder: (_) => IncidentDialog(incident: i, component: c));
                        },
                      ),
                    const _Header('HAZARD ZONES'),
                    for (final z in zones.where((z) => z.active))
                      ListTile(
                        dense: true,
                        leading: Container(width: 12, height: 12, decoration: BoxDecoration(color: z.type.color, borderRadius: BorderRadius.circular(3))),
                        title: Text('${z.name} · ${z.type.label}', style: const TextStyle(fontSize: 12.5)),
                        subtitle: z.description == null ? null : Text(z.description!, style: const TextStyle(fontSize: 11)),
                        onTap: () {
                          final c = byId[z.componentId];
                          if (c != null) actions.selectNode(c.meshNodeId);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
    child: Text(text, style: const TextStyle(fontSize: 10.5, letterSpacing: 0.8, color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
  );
}
