import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/async_states.dart';
import '../../../../auth/presentation/providers/auth_providers.dart';
import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../../digital_twin/presentation/providers/twin_providers.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/services/hull_position.dart';
import '../../../domain/services/production_schedule.dart';
import '../../providers/shipyard_providers.dart';
import '../scene_actions.dart';
import 'activity_dialog.dart';
import 'activity_form_dialog.dart';
import 'block_dialog.dart';
import 'blocks_dialog.dart';
import 'checklist_dialog.dart';
import 'draft_schedule_dialog.dart';
import 'gantt_chart.dart';
import 'hull_dialog.dart';
import 'outfitting_packages_dialog.dart';
import 'timeline_bar.dart';

/// Production schedule: Gantt per hull / block + 3D timeline scrubber.
class ProductionTab extends ConsumerStatefulWidget {
  const ProductionTab({super.key, required this.projectId, required this.actions});

  final String projectId;
  final SceneActions actions;

  @override
  ConsumerState<ProductionTab> createState() => _ProductionTabState();
}

class _ProductionTabState extends ConsumerState<ProductionTab> {
  final _gantt = GlobalKey<GanttChartState>();
  String? _hullFilter;
  String? _selectedActivityId;

  List<GanttRow> _rows(
    List<Hull> hulls,
    ProductionSchedule schedule,
    Map<String, TwinComponent> byId,
    Map<String, TwinComponent> byNode,
    DateTime today,
    DateTime sceneDate,
    HullPositionMap positions,
  ) {
    final rows = <GanttRow>[];
    for (final hull in hulls) {
      if (_hullFilter != null && hull.id != _hullFilter) continue;
      final items = schedule.activities.where((a) => a.hullId == hull.id).toList();
      if (items.isEmpty) continue;
      final progress = ProductionSchedule.progressOf(items, today);
      rows.add(GanttRow.header(label: hull.displayName, trailing: '${progress.earnedPct.round()} %'));

      final byComponent = <String, List<ProductionActivity>>{};
      final hullLevel = <ProductionActivity>[];
      final byPackage = <WorkPackage, List<ProductionActivity>>{};
      for (final a in items) {
        if (a.workPackage != null) {
          byPackage.putIfAbsent(a.workPackage!, () => []).add(a);
        } else if (a.componentId == null) {
          hullLevel.add(a);
        } else {
          byComponent.putIfAbsent(a.componentId!, () => []).add(a);
        }
      }
      int sequence(String componentId) {
        final v = byId[componentId]?.metadata['erection_sequence'];
        return v is num ? v.toInt() : 999;
      }

      final componentIds = byComponent.keys.toList()..sort((a, b) => sequence(a).compareTo(sequence(b)));
      for (final id in componentIds) {
        final placement = ProductionSchedule.placementFor(schedule.forComponent(id, today), sceneDate, today);
        rows.add(
          GanttRow(
            label: shortComponentName(byId[id]),
            sublabel: _placementText(placement, byNode),
            activities: byComponent[id]!,
          ),
        );
      }
      if (hullLevel.isNotEmpty) {
        rows.add(
          GanttRow(
            label: hull.isRepair ? 'Docking & repair' : 'Hull milestones',
            sublabel: _hullPositionText(positions[hull.id], byNode) ??
                (componentIds.isEmpty ? (hull.shipType ?? '') : 'Launching, outfitting, trials'),
            activities: hullLevel,
          ),
        );
      }
      // Afloat outfitting work packages, one row each (on board at the quay).
      for (final p in WorkPackage.values) {
        final rowsOfPackage = byPackage[p];
        if (rowsOfPackage == null) continue;
        rows.add(
          GanttRow(
            label: p.label,
            sublabel: 'Outfitting · ${shortComponentName(byNode[p.shopNodeId], fallback: p.shopNodeId)}',
            activities: rowsOfPackage,
          ),
        );
      }
    }
    return rows;
  }

  /// Where the hull lies at the scene date, e.g. "Afloat · Outfitting Quay".
  String? _hullPositionText(HullPosition? p, Map<String, TwinComponent> byNode) {
    if (p == null) return null;
    final area = p.areaNodeId;
    return area == null ? p.kind.label : '${p.kind.label} · ${shortComponentName(byNode[area], fallback: area)}';
  }

  String _placementText(BlockPlacement p, Map<String, TwinComponent> byNode) => switch (p.kind) {
    PlacementKind.hidden => 'Not started',
    PlacementKind.erected => p.activity?.stage == ProductionStage.erection && p.activity?.isDone != true
        ? 'Erection on berth'
        : 'Erected',
    PlacementKind.area => '${p.ghost ? 'Parts at ' : 'At '}${shortComponentName(byNode[p.areaNodeId], fallback: p.areaNodeId)}',
  };

  Future<void> _onTap(
    ProductionActivity a,
    Map<String, TwinComponent> byId,
    Map<String, TwinComponent> byNode,
    List<Hull> hulls,
    List<TwinComponent> components,
    List<ProductionActivity> activities,
  ) async {
    setState(() => _selectedActivityId = a.id);
    final block = a.componentId == null ? null : byId[a.componentId];
    if (block != null) {
      widget.actions.selectNode(block.meshNodeId);
    } else if (a.locationNodeId != null && byNode.containsKey(a.locationNodeId)) {
      widget.actions.selectNode(a.locationNodeId!);
    }
    final result = await ActivityDialog.show(
      context,
      activity: a,
      blockName: block?.name,
      locationName: a.locationNodeId == null ? null : byNode[a.locationNodeId]?.name,
    );
    if (!mounted) return;
    switch (result) {
      case ActivityDialogResult.editPlan:
        await ActivityFormDialog.show(
          context,
          projectId: widget.projectId,
          hulls: hulls,
          areas: yardAreas(components),
          existing: activities,
          activity: a,
        );
      case ActivityDialogResult.deleted:
        setState(() => _selectedActivityId = null);
        _snack('${a.code} deleted.');
      case ActivityDialogResult.checklist:
        final hull = hulls.where((h) => h.id == a.hullId).firstOrNull;
        if (hull != null) await ChecklistDialog.show(context, projectId: widget.projectId, row: a, hull: hull);
      case ActivityDialogResult.packageWork:
        await BlockDialog.showPackage(
          context,
          projectId: widget.projectId,
          row: a,
          hull: hulls.where((h) => h.id == a.hullId).firstOrNull,
        );
      case null:
        break;
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _addActivity(List<Hull> hulls, List<TwinComponent> components, List<ProductionActivity> activities) async {
    final saved = await ActivityFormDialog.show(
      context,
      projectId: widget.projectId,
      hulls: hulls,
      areas: yardAreas(components),
      existing: activities,
      initialHullId: _hullFilter,
    );
    if (saved == true && mounted) _snack('Activity added.');
  }

  Future<void> _draftSchedule(List<Hull> hulls, List<TwinComponent> components, List<ProductionActivity> activities) async {
    final hullId = await DraftScheduleDialog.show(
      context,
      hulls: hulls,
      existing: activities,
      areas: yardAreas(components),
      components: components,
      initialHullId: _hullFilter,
    );
    if (hullId == null || !mounted) return;
    // Show the new plan on its own.
    setState(() => _hullFilter = hullId);
    _snack('Draft schedule created. Tap a bar to adjust or delete it.');
  }

  Future<void> _outfittingPackages(List<Hull> hulls, List<ProductionActivity> activities) async {
    final message = await OutfittingPackagesDialog.show(
      context,
      hulls: hulls,
      existing: activities,
      initialHullId: _hullFilter,
    );
    if (message == null || !mounted) return;
    _snack(message);
  }

  Widget _planMenu(List<Hull> hulls, List<TwinComponent> components, List<ProductionActivity> activities) =>
      PopupMenuButton<String>(
        tooltip: 'Plan activities',
        onSelected: (v) => switch (v) {
          'add' => _addActivity(hulls, components, activities),
          'packages' => _outfittingPackages(hulls, activities),
          _ => _draftSchedule(hulls, components, activities),
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'add',
            child: ListTile(dense: true, leading: Icon(Icons.add_task), title: Text('Add activity…')),
          ),
          PopupMenuItem(
            value: 'draft',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.auto_awesome_motion_outlined),
              title: Text('Draft schedule from milestones…'),
            ),
          ),
          PopupMenuItem(
            value: 'packages',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.handyman_outlined),
              title: Text('Outfitting work packages…'),
            ),
          ),
        ],
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit_calendar_outlined, size: 18),
              SizedBox(width: 4),
              Text('Plan'),
              Icon(Icons.arrow_drop_down, size: 18),
            ],
          ),
        ),
      );

  Future<void> _newHull(List<Hull> hulls, List<TwinComponent> components) async {
    final hull = await HullDialog.show(
      context,
      projectId: widget.projectId,
      existingHulls: hulls,
      locations: components.where((c) => hullLocationCategories.contains(c.category)).toList(),
    );
    if (hull == null || !mounted) return;
    ref.invalidate(hullsProvider(widget.projectId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Hull ${hull.displayName} created. It is listed on the Dashboard; '
          'it appears here once it has schedule rows.',
        ),
      ),
    );
  }

  Future<void> _blocks(List<Hull> hulls) async {
    final message = await BlocksDialog.show(
      context,
      projectId: widget.projectId,
      hulls: hulls,
      initialHullId: _hullFilter,
    );
    if (message == null || !mounted) return;
    _snack(message);
  }

  Widget _blocksButton(List<Hull> hulls) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: OutlinedButton.icon(
      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
      onPressed: hulls.isEmpty ? null : () => _blocks(hulls),
      icon: const Icon(Icons.view_module_outlined, size: 18),
      label: const Text('Blocks'),
    ),
  );

  Widget _newHullButton(List<Hull> hulls, List<TwinComponent> components) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: FilledButton.tonalIcon(
      style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
      onPressed: () => _newHull(hulls, components),
      icon: const Icon(Icons.add, size: 18),
      label: const Text('New hull'),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final projectId = widget.projectId;
    final hulls = ref.watch(hullsProvider(projectId));
    final activities = ref.watch(activitiesProvider(projectId));
    final components = ref.watch(componentsProvider(projectId)).value ?? const <TwinComponent>[];
    final schedule = ref.watch(scheduleProvider(projectId));
    final today = ref.watch(todayProvider);
    final sceneDate = ref.watch(sceneDateProvider(projectId));
    final selectedComponent = ref.watch(selectedComponentProvider(projectId));
    final canEdit = ref.watch(isEditorProvider);

    if (hulls.hasError) return ErrorView(error: hulls.error!);
    if (activities.hasError) return ErrorView(error: activities.error!);
    if (!hulls.hasValue || !activities.hasValue) return const LoadingView();
    final range = schedule.range(today);
    if (range == null) {
      return Column(
        children: [
          if (canEdit)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 6, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _planMenu(hulls.value!, components, activities.value!),
                    _blocksButton(hulls.value!),
                    _newHullButton(hulls.value!, components),
                  ],
                ),
              ),
            ),
          const Expanded(
            child: EmptyView(icon: Icons.view_timeline_outlined, message: 'No production schedule for this project.'),
          ),
        ],
      );
    }

    final byId = componentsById(components);
    final byNode = componentsByNode(components);
    final hullList = hulls.value!;
    final rows = _rows(hullList, schedule, byId, byNode, today, sceneDate, ref.watch(hullPositionsProvider(widget.projectId)));
    final running = schedule.runningAt(sceneDate, today).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 0),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('All hulls'),
                        selected: _hullFilter == null,
                        onSelected: (_) => setState(() => _hullFilter = null),
                      ),
                      for (final h in hullList)
                        if (schedule.activities.any((a) => a.hullId == h.id))
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: ChoiceChip(
                              label: Text(h.hullNo),
                              selected: _hullFilter == h.id,
                              onSelected: (_) => setState(() => _hullFilter = h.id),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
              Tooltip(
                message: [for (final s in ProductionStage.values) '■ ${s.label}'].join('\n'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text('$running running · legend', style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
                ),
              ),
              IconButton(
                tooltip: 'Zoom out',
                visualDensity: VisualDensity.compact,
                onPressed: () => _gantt.currentState?.zoom(1 / 1.4),
                icon: const Icon(Icons.zoom_out, size: 18),
              ),
              IconButton(
                tooltip: 'Zoom in',
                visualDensity: VisualDensity.compact,
                onPressed: () => _gantt.currentState?.zoom(1.4),
                icon: const Icon(Icons.zoom_in, size: 18),
              ),
              IconButton(
                tooltip: 'Scroll to the timeline date',
                visualDensity: VisualDensity.compact,
                onPressed: () => _gantt.currentState?.scrollToDate(sceneDate),
                icon: const Icon(Icons.center_focus_strong, size: 18),
              ),
              if (canEdit) ...[
                _planMenu(hullList, components, activities.value!),
                _blocksButton(hullList),
                _newHullButton(hullList, components),
              ],
            ],
          ),
        ),
        TimelineBar(projectId: projectId),
        const Divider(height: 1),
        Expanded(
          child: GanttChart(
            key: _gantt,
            rows: rows,
            rangeStart: range.$1,
            rangeEnd: range.$2,
            today: today,
            cursor: sceneDate,
            selectedActivityId: _selectedActivityId,
            highlightComponentId: selectedComponent?.id,
            onScrub: (d) => ref.read(timelineProvider(projectId).notifier).setDate(d),
            onTapActivity: (a) => _onTap(a, byId, byNode, hullList, components, activities.value!),
          ),
        ),
      ],
    );
  }
}
