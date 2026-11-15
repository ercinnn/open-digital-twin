import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/async_states.dart';
import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../../digital_twin/presentation/providers/twin_providers.dart';
import '../../../domain/entities/organization_entities.dart';
import '../../providers/scene_view_providers.dart';
import '../../providers/shipyard_providers.dart';
import '../scene_actions.dart';

/// Organization chart: departments, shift headcount and the areas they run.
/// Selecting a department colors its areas in 3D (department overlay).
class OrganizationTab extends ConsumerWidget {
  const OrganizationTab({super.key, required this.projectId, required this.actions});

  final String projectId;
  final SceneActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final org = ref.watch(organizationProvider(projectId));
    return org.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(organizationProvider(projectId))),
      data: (o) => o.isEmpty
          ? const EmptyView(icon: Icons.groups_outlined, message: 'No organization data for this project.')
          : _OrganizationView(projectId: projectId, org: o, actions: actions),
    );
  }
}

class _OrganizationView extends ConsumerWidget {
  const _OrganizationView({required this.projectId, required this.org, required this.actions});

  final String projectId;
  final Organization org;
  final SceneActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(sceneViewProvider(projectId));
    final notifier = ref.read(sceneViewProvider(projectId).notifier);
    final components = ref.watch(componentsProvider(projectId)).value ?? const <TwinComponent>[];
    final byId = componentsById(components);
    final selected = view.focusDepartmentId == null ? null : org.byId[view.focusDepartmentId];
    final allIds = org.departments.map((d) => d.id).toSet();
    final totals = org.headcountByShift(allIds);

    void select(Department? d) {
      notifier.focusDepartment(d?.id);
      if (d == null) return;
      final nodes = org.componentsOf(org.subtreeIds(d.id)).keys.map((id) => byId[id]?.meshNodeId).whereType<String>();
      if (nodes.isNotEmpty) actions.focusNodes(nodes);
    }

    final tree = <Widget>[];
    void addLevel(String? parentId, int depth) {
      for (final d in org.childrenOf(parentId)) {
        tree.add(
          _DepartmentRow(
            department: d,
            depth: depth,
            headcount: org.headcount(org.subtreeIds(d.id)),
            selected: d.id == view.focusDepartmentId,
            onTap: () => select(d.id == view.focusDepartmentId ? null : d),
          ),
        );
        addLevel(d.id, depth + 1);
      }
    }

    addLevel(null, 0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 300,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
                child: Row(
                  children: [
                    Text(
                      '${org.headcount(allIds)} people · ${org.departments.length} departments',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    const Spacer(),
                    Tooltip(
                      message: 'Color areas by responsible department',
                      child: Switch(
                        value: view.overlay == SceneOverlay.department,
                        onChanged: (v) {
                          notifier.setOverlay(v ? SceneOverlay.department : null);
                          if (!v) notifier.focusDepartment(null);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final s in org.shifts)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text('${s.code} ${s.window}: ${totals[s.id] ?? 0}', style: const TextStyle(fontSize: 11)),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(child: ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: tree)),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: selected == null
              ? const EmptyView(
                  icon: Icons.account_tree_outlined,
                  message: 'Select a department to see its staffing\nand highlight its areas in 3D.',
                )
              : _DepartmentDetails(projectId: projectId, org: org, department: selected, byId: byId, actions: actions),
        ),
      ],
    );
  }
}

class _DepartmentRow extends StatelessWidget {
  const _DepartmentRow({
    required this.department,
    required this.depth,
    required this.headcount,
    required this.selected,
    required this.onTap,
  });

  final Department department;
  final int depth;
  final int headcount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? department.color.withValues(alpha: 0.16) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12.0 + depth * 16, 7, 12, 7),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: department.color, borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 34,
                child: Text(department.code, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontFamily: 'monospace')),
              ),
              Expanded(
                child: Text(
                  department.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                ),
              ),
              Text('$headcount', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DepartmentDetails extends ConsumerWidget {
  const _DepartmentDetails({
    required this.projectId,
    required this.org,
    required this.department,
    required this.byId,
    required this.actions,
  });

  final String projectId;
  final Organization org;
  final Department department;
  final Map<String, TwinComponent> byId;
  final SceneActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = org.subtreeIds(department.id);
    final byShift = org.headcountByShift(ids);
    final areas = org.componentsOf(ids).entries.toList()
      ..sort((a, b) => (byId[a.key]?.name ?? '').compareTo(byId[b.key]?.name ?? ''));
    final schedule = ref.watch(scheduleProvider(projectId));
    final today = ref.watch(todayProvider);
    final running = schedule.runningAt(today, today).where((a) => ids.contains(a.departmentId)).toList();
    final parent = department.parentId == null ? null : org.byId[department.parentId];

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          children: [
            Container(width: 14, height: 14, decoration: BoxDecoration(color: department.color, borderRadius: BorderRadius.circular(4))),
            const SizedBox(width: 10),
            Expanded(
              child: Text(department.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            Text(department.code, style: const TextStyle(color: AppTheme.textMuted, fontFamily: 'monospace')),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          [
            if (department.managerTitle != null) 'Led by: ${department.managerTitle}',
            if (parent != null) 'Reports to: ${parent.name}',
          ].join('   ·   '),
          style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
        ),
        if (department.description != null) ...[
          const SizedBox(height: 4),
          Text(department.description!, style: const TextStyle(fontSize: 12.5)),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in org.shifts)
              _Stat(label: '${s.name} (${s.window})', value: '${byShift[s.id] ?? 0}'),
            _Stat(label: 'Total headcount', value: '${org.headcount(ids)}', accent: true),
            _Stat(label: 'Running activities', value: '${running.length}'),
          ],
        ),
        const SizedBox(height: 14),
        const Text('AREAS & CRANES', style: TextStyle(fontSize: 11, letterSpacing: 0.8, color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final e in areas)
              if (byId[e.key] != null)
                ActionChip(
                  avatar: Icon(e.value ? Icons.verified_outlined : Icons.support_agent, size: 16, color: department.color),
                  label: Text(shortComponentName(byId[e.key]), style: const TextStyle(fontSize: 12)),
                  tooltip: e.value ? 'Responsible department' : 'Supporting staff',
                  onPressed: () => actions.selectNode(byId[e.key]!.meshNodeId),
                ),
          ],
        ),
        if (running.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('RUNNING TODAY', style: TextStyle(fontSize: 11, letterSpacing: 0.8, color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          for (final a in running)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.circle, size: 10, color: a.stage.color),
              title: Text(a.name, style: const TextStyle(fontSize: 12.5)),
              trailing: Text('${a.progressPct.round()} %', style: const TextStyle(fontSize: 12)),
              onTap: () {
                final node = a.componentId == null ? a.locationNodeId : byId[a.componentId]?.meshNodeId;
                if (node != null) actions.selectNode(node);
              },
            ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.accent = false});

  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent ? AppTheme.accent : AppTheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: accent ? AppTheme.accent : null)),
          Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        ],
      ),
    );
  }
}
