import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'dashboard/dashboard_tab.dart';
import 'hse/hse_tab.dart';
import 'materials/materials_tab.dart';
import 'organization/organization_tab.dart';
import 'production/production_tab.dart';
import 'quality/quality_tab.dart';
import 'resources/resources_tab.dart';
import 'scene_actions.dart';

enum DockMode { collapsed, normal, maximized }

/// Tabbed shipyard operations panel under the 3D viewport.
class OperationsDock extends StatefulWidget {
  const OperationsDock({
    super.key,
    required this.projectId,
    required this.actions,
    required this.mode,
    required this.onModeChanged,
  });

  final String projectId;
  final SceneActions actions;
  final DockMode mode;
  final ValueChanged<DockMode> onModeChanged;

  @override
  State<OperationsDock> createState() => _OperationsDockState();
}

class _DockTab {
  const _DockTab(this.label, this.icon, this.builder);
  final String label;
  final IconData icon;
  final Widget Function(String projectId, SceneActions actions) builder;
}

class _OperationsDockState extends State<OperationsDock> with SingleTickerProviderStateMixin {
  static final _tabs = <_DockTab>[
    _DockTab('Dashboard', Icons.dashboard_outlined, (p, a) => DashboardTab(projectId: p, actions: a)),
    _DockTab('Production', Icons.view_timeline_outlined, (p, a) => ProductionTab(projectId: p, actions: a)),
    _DockTab('Organization', Icons.groups_outlined, (p, a) => OrganizationTab(projectId: p, actions: a)),
    _DockTab('Cranes & docks', Icons.precision_manufacturing_outlined, (p, a) => ResourcesTab(projectId: p, actions: a)),
    _DockTab('Materials', Icons.inventory_2_outlined, (p, a) => MaterialsTab(projectId: p, actions: a)),
    _DockTab('Quality', Icons.fact_check_outlined, (p, a) => QualityTab(projectId: p, actions: a)),
    _DockTab('HSE', Icons.health_and_safety_outlined, (p, a) => HseTab(projectId: p, actions: a)),
  ];

  late final _controller = TabController(length: _tabs.length, vsync: this);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = widget.mode == DockMode.collapsed;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.outline)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 40,
            child: Row(
              children: [
                const SizedBox(width: 10),
                const Icon(Icons.precision_manufacturing_outlined, size: 16, color: AppTheme.accent),
                const SizedBox(width: 6),
                const Text(
                  'YARD OPERATIONS',
                  style: TextStyle(fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: AppTheme.textMuted),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TabBar(
                    controller: _controller,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    dividerHeight: 0,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                    onTap: (_) {
                      if (collapsed) widget.onModeChanged(DockMode.normal);
                    },
                    tabs: [
                      for (final t in _tabs)
                        Tab(
                          height: 38,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [Icon(t.icon, size: 16), const SizedBox(width: 6), Text(t.label)],
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: widget.mode == DockMode.maximized ? 'Restore panel' : 'Maximize panel',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => widget.onModeChanged(
                    widget.mode == DockMode.maximized ? DockMode.normal : DockMode.maximized,
                  ),
                  icon: Icon(widget.mode == DockMode.maximized ? Icons.close_fullscreen : Icons.open_in_full, size: 17),
                ),
                IconButton(
                  tooltip: collapsed ? 'Show panel' : 'Hide panel',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => widget.onModeChanged(collapsed ? DockMode.normal : DockMode.collapsed),
                  icon: Icon(collapsed ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 20),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          if (!collapsed) ...[
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                controller: _controller,
                physics: const NeverScrollableScrollPhysics(),
                children: [for (final t in _tabs) t.builder(widget.projectId, widget.actions)],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
