import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/async_states.dart';
import '../../../../auth/presentation/providers/auth_providers.dart';
import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../../digital_twin/presentation/providers/twin_providers.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/entities/quality_entities.dart';
import '../../providers/scene_view_providers.dart';
import '../../providers/shipyard_providers.dart';
import '../scene_actions.dart';
import 'quality_dialogs.dart';

/// Punch list + inspection log, both pinned in 3D.
class QualityTab extends ConsumerStatefulWidget {
  const QualityTab({super.key, required this.projectId, required this.actions});

  final String projectId;
  final SceneActions actions;

  @override
  ConsumerState<QualityTab> createState() => _QualityTabState();
}

class _QualityTabState extends ConsumerState<QualityTab> {
  bool _openOnly = true;
  String? _hullId;

  @override
  Widget build(BuildContext context) {
    final projectId = widget.projectId;
    final punch = ref.watch(punchItemsProvider(projectId));
    final inspections = ref.watch(inspectionsProvider(projectId));
    final hulls = ref.watch(hullsProvider(projectId)).value ?? const <Hull>[];
    final components = ref.watch(componentsProvider(projectId)).value ?? const <TwinComponent>[];
    final byId = componentsById(components);
    final view = ref.watch(sceneViewProvider(projectId));
    final selected = ref.watch(selectedComponentProvider(projectId));
    final canEdit = ref.watch(isEditorProvider);
    final today = ref.watch(todayProvider);

    final items = (punch.value ?? const <PunchItem>[])
        .where((p) => (!_openOnly || p.isOpen) && (_hullId == null || p.hullId == _hullId))
        .toList()
      ..sort((a, b) {
        final s = a.status.index.compareTo(b.status.index);
        if (s != 0) return s;
        return a.priority.index.compareTo(b.priority.index);
      });
    final open = (punch.value ?? const <PunchItem>[]).where((p) => p.isOpen).toList();
    final insp = (inspections.value ?? const <QualityInspection>[]).where((q) => _hullId == null || q.hullId == _hullId).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
          child: Row(
            children: [
              for (final p in PunchPriority.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: CircleAvatar(radius: 8, backgroundColor: p.color),
                    label: Text('${p.dbValue}: ${open.where((i) => i.priority == p).length}', style: const TextStyle(fontSize: 11.5)),
                  ),
                ),
              Chip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.event_busy, size: 15, color: Color(0xFFF87171)),
                label: Text('Overdue: ${open.where((i) => i.isOverdue(today)).length}', style: const TextStyle(fontSize: 11.5)),
              ),
              const SizedBox(width: 10),
              DropdownButton<String?>(
                value: _hullId,
                underline: const SizedBox.shrink(),
                hint: const Text('All hulls', style: TextStyle(fontSize: 12.5)),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('All hulls', style: TextStyle(fontSize: 12.5))),
                  for (final h in hulls) DropdownMenuItem<String?>(value: h.id, child: Text(h.hullNo, style: const TextStyle(fontSize: 12.5))),
                ],
                onChanged: (v) => setState(() => _hullId = v),
              ),
              const SizedBox(width: 8),
              FilterChip(label: const Text('Open only'), selected: _openOnly, onSelected: (v) => setState(() => _openOnly = v)),
              const Spacer(),
              const Text('Pins in 3D', style: TextStyle(fontSize: 12)),
              Switch(
                value: view.qualityPins,
                onChanged: ref.read(sceneViewProvider(projectId).notifier).setQualityPins,
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: selected == null ? 'Select a block or area first' : 'Raise a punch item on ${selected.name}',
                child: FilledButton.icon(
                  onPressed: canEdit && selected != null
                      ? () => showDialog<void>(
                          context: context,
                          builder: (_) => NewPunchDialog(projectId: projectId, component: selected, hulls: hulls),
                        )
                      : null,
                  icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                  label: const Text('Raise item'),
                ),
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
                flex: 6,
                child: punch.when(
                  loading: () => const LoadingView(),
                  error: (e, _) => ErrorView(error: e),
                  data: (_) => items.isEmpty
                      ? const EmptyView(icon: Icons.task_alt, message: 'No punch items.')
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final p = items[i];
                            final c = byId[p.componentId];
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 12,
                                backgroundColor: p.isOpen ? p.priority.color : AppTheme.outline,
                                child: Text(p.priority.dbValue, style: const TextStyle(fontSize: 11, color: Color(0xFF0B1220), fontWeight: FontWeight.w800)),
                              ),
                              title: Text(
                                p.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12.5, decoration: p.isOpen ? null : TextDecoration.lineThrough),
                              ),
                              subtitle: Text(
                                '${p.itemNo} · ${shortComponentName(c)} · ${p.raisedByLabel} · due ${formatDate(p.dueDate)}',
                                style: TextStyle(fontSize: 11, color: p.isOverdue(today) ? const Color(0xFFFCA5A5) : AppTheme.textMuted),
                              ),
                              trailing: Text(p.status.label, style: const TextStyle(fontSize: 11.5)),
                              onTap: () {
                                if (c != null) widget.actions.selectNode(c.meshNodeId);
                                showDialog<void>(context: context, builder: (_) => PunchItemDialog(item: p, component: c));
                              },
                            );
                          },
                        ),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                flex: 5,
                child: inspections.when(
                  loading: () => const LoadingView(),
                  error: (e, _) => ErrorView(error: e),
                  data: (_) => ListView.separated(
                    itemCount: insp.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final q = insp[i];
                      final c = byId[q.componentId];
                      return ListTile(
                        dense: true,
                        leading: Icon(Icons.fact_check_outlined, color: q.result.color, size: 20),
                        title: Text('${q.type.label} · ${q.description ?? q.referenceNo}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                        subtitle: Text(
                          '${q.referenceNo} · ${shortComponentName(c)}'
                          '${q.measuredValue == null ? '' : ' · ${q.measuredValue} ${q.unit ?? ''}'}'
                          '${q.acceptanceText == null ? '' : ' (${q.acceptanceText})'}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Text(q.result.label, style: TextStyle(fontSize: 11.5, color: q.result.color, fontWeight: FontWeight.w700)),
                        onTap: () {
                          if (c != null) widget.actions.selectNode(c.meshNodeId);
                          showDialog<void>(context: context, builder: (_) => InspectionDialog(inspection: q, component: c));
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
