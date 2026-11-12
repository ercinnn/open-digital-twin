import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/status/component_status.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/async_states.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../projects/domain/entities/project.dart';
import '../../../projects/presentation/providers/project_providers.dart';
import '../../domain/entities/twin_entities.dart';
import '../providers/twin_providers.dart';
import '../viewer/three_viewer_controller.dart';
import '../viewer/three_viewport.dart';
import '../widgets/component_tree.dart';
import '../widgets/inspector_panel.dart';

/// Split view: left 70% (component tree + Three.js viewport + simulation),
/// right 30% inspector. Narrow screens stack the viewport over tabbed panels.
class DigitalTwinPage extends ConsumerStatefulWidget {
  const DigitalTwinPage({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<DigitalTwinPage> createState() => _DigitalTwinPageState();
}

class _DigitalTwinPageState extends ConsumerState<DigitalTwinPage> {
  final _viewer = ThreeViewerController();
  StreamSubscription<ViewerEvent>? _events;

  bool _viewerReady = false;
  bool _modelLoading = false;
  double? _loadProgress;
  String? _viewerError;
  List<String> _meshNodesInModel = const [];

  String get _projectId => widget.projectId;

  @override
  void initState() {
    super.initState();
    _events = _viewer.events.listen(_onViewerEvent);

    // Drive the 3D scene from Riverpod state (model URL + realtime statuses).
    ref.listenManual<AsyncValue<Project>>(projectProvider(_projectId), (_, next) {
      final url = next.value?.glbModelUrl;
      if (url != null && url.isNotEmpty) _viewer.loadModel(url);
    }, fireImmediately: true);
    ref.listenManual<AsyncValue<List<TwinComponent>>>(componentsProvider(_projectId), (_, next) {
      final list = next.value;
      if (list != null) _viewer.setStatuses({for (final c in list) c.meshNodeId: c.status.dbValue});
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _events?.cancel();
    _viewer.dispose();
    super.dispose();
  }

  void _onViewerEvent(ViewerEvent event) {
    if (!mounted) return;
    switch (event) {
      case ViewerReady():
        setState(() {
          _viewerReady = true;
          _modelLoading = _viewer.modelUrl != null;
        });
      case ModelProgress(:final fraction):
        setState(() {
          _modelLoading = true;
          _loadProgress = fraction;
        });
      case ModelLoaded(:final meshNodeIds):
        setState(() {
          _modelLoading = false;
          _loadProgress = null;
          _viewerError = null;
          _meshNodesInModel = meshNodeIds;
        });
      case ModelError(:final message):
        setState(() {
          _modelLoading = false;
          _viewerError = 'Model failed to load: $message';
        });
      case ViewerFailure(:final message):
        setState(() => _viewerError = message);
      case NodeSelected(:final meshNodeId):
        ref.read(selectedNodeProvider(_projectId).notifier).select(meshNodeId);
    }
  }

  void _selectFromTree(TwinComponent component) {
    ref.read(selectedNodeProvider(_projectId).notifier).select(component.meshNodeId);
    _viewer.selectNode(component.meshNodeId, focus: true);
  }

  Future<void> _simulateOnce() async {
    final result = await ref.read(simulationProvider(_projectId).notifier).simulateOnce();
    if (!mounted) return;
    final error = ref.read(simulationProvider(_projectId)).error;
    final messenger = ScaffoldMessenger.of(context);
    if (result == null) {
      if (error != null) {
        messenger.showSnackBar(SnackBar(content: Text(error), backgroundColor: const Color(0xFF7F1D1D)));
      }
      return;
    }
    final changes = result.statusChanges.map((c) => '${c.$1}: ${c.$2} → ${c.$3}').join('\n');
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${result.readingsInserted} sensor readings pushed'
          '${changes.isEmpty ? '' : '\n$changes'}',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectProvider(_projectId));
    final components = ref.watch(componentsProvider(_projectId));
    final selectedNode = ref.watch(selectedNodeProvider(_projectId));

    ref.listen<SimulationState>(simulationProvider(_projectId), (previous, next) {
      if (next.error != null && next.error != previous?.error && previous?.live == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Live feed stopped: ${next.error}'), backgroundColor: const Color(0xFF7F1D1D)),
        );
      }
    });

    final title = project.value?.name ?? 'Digital Twin';
    final componentList = components.value ?? const <TwinComponent>[];

    final viewport = _ViewportStack(
      viewer: _viewer,
      ready: _viewerReady,
      loading: _modelLoading,
      progress: _loadProgress,
      error: _viewerError,
      hasModel: project.value?.hasModel ?? true,
      unmappedCount: componentList.where((c) => !_meshNodesInModel.contains(c.meshNodeId)).length,
      modelLoaded: _meshNodesInModel.isNotEmpty,
    );
    final tree = components.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(error: e),
      data: (list) => ComponentTree(components: list, selectedNodeId: selectedNode, onSelect: _selectFromTree),
    );
    final inspector = InspectorPanel(projectId: _projectId);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            if (project.value != null)
              Text(
                '${project.value!.domainType.label} twin · ${componentList.length} components',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
          ],
        ),
        actions: [
          _StatusSummary(components: componentList),
          const SizedBox(width: 8),
          _SimulationControls(projectId: _projectId, onSimulateOnce: _simulateOnce),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            tooltip: 'View options',
            icon: const Icon(Icons.palette_outlined),
            onSelected: (v) {
              setState(() {
                switch (v) {
                  case 'status':
                    _viewer.setColorMode(ViewerColorMode.status);
                  case 'material':
                    _viewer.setColorMode(ViewerColorMode.material);
                  case 'reset':
                    _viewer.resetCamera();
                }
              });
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'status',
                checked: _viewer.colorMode == ViewerColorMode.status,
                child: const Text('Color by status'),
              ),
              CheckedPopupMenuItem(
                value: 'material',
                checked: _viewer.colorMode == ViewerColorMode.material,
                child: const Text('Original materials'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'reset', child: Text('Reset camera')),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: project.hasError
          ? ErrorView(error: project.error!, onRetry: () => ref.invalidate(projectProvider(_projectId)))
          : LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 1000) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 7,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: 270,
                              child: DecoratedBox(
                                decoration: const BoxDecoration(color: AppTheme.surface),
                                child: tree,
                              ),
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(child: viewport),
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        flex: 3,
                        child: DecoratedBox(decoration: const BoxDecoration(color: AppTheme.background), child: inspector),
                      ),
                    ],
                  );
                }
                return Column(
                  children: [
                    Expanded(flex: 5, child: viewport),
                    const Divider(height: 1),
                    Expanded(
                      flex: 5,
                      child: DefaultTabController(
                        length: 2,
                        initialIndex: selectedNode == null ? 0 : 1,
                        child: Column(
                          children: [
                            const TabBar(tabs: [Tab(text: 'Components'), Tab(text: 'Inspector')]),
                            Expanded(child: TabBarView(children: [tree, inspector])),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _ViewportStack extends StatelessWidget {
  const _ViewportStack({
    required this.viewer,
    required this.ready,
    required this.loading,
    required this.progress,
    required this.error,
    required this.hasModel,
    required this.unmappedCount,
    required this.modelLoaded,
  });

  final ThreeViewerController viewer;
  final bool ready;
  final bool loading;
  final double? progress;
  final String? error;
  final bool hasModel;
  final int unmappedCount;
  final bool modelLoaded;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ThreeViewport(controller: viewer),
        if (!ready || loading)
          IgnorePointer(
            child: Container(
              color: AppTheme.background.withValues(alpha: ready ? 0.35 : 1),
              child: Center(
                child: SizedBox(
                  width: 240,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LinearProgressIndicator(value: progress, minHeight: 3),
                      const SizedBox(height: 10),
                      Text(
                        !ready ? 'Starting 3D engine (Three.js) ...' : 'Loading model ...',
                        style: const TextStyle(color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (!hasModel)
          const Center(
            child: Text('This project has no processed model yet.\nUpload a CAD file from the dashboard.',
                textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textMuted)),
          ),
        if (error != null)
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Material(
              color: const Color(0xFF7F1D1D),
              borderRadius: BorderRadius.circular(8),
              child: Padding(padding: const EdgeInsets.all(10), child: Text(error!)),
            ),
          ),
        Positioned(right: 12, bottom: 12, child: _Legend(unmappedCount: modelLoaded ? unmappedCount : 0)),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.unmappedCount});

  final int unmappedCount;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surface.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in ComponentStatus.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusDot(status: s, size: 9),
                    const SizedBox(width: 6),
                    Text(
                      s == ComponentStatus.alert ? '${s.label} (pulsing)' : s.label,
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            if (unmappedCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('$unmappedCount BOM rows without mesh',
                    style: const TextStyle(fontSize: 11, color: Color(0xFFFBBF24))),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusSummary extends StatelessWidget {
  const _StatusSummary({required this.components});

  final List<TwinComponent> components;

  @override
  Widget build(BuildContext context) {
    final counts = {for (final s in ComponentStatus.values) s: 0};
    for (final c in components) {
      counts[c.status] = counts[c.status]! + 1;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final s in ComponentStatus.values)
          if (counts[s]! > 0)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Tooltip(
                message: s.label,
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: StatusDot(status: s, size: 8),
                  label: Text('${counts[s]}'),
                ),
              ),
            ),
      ],
    );
  }
}

class _SimulationControls extends ConsumerWidget {
  const _SimulationControls({required this.projectId, required this.onSimulateOnce});

  final String projectId;
  final VoidCallback onSimulateOnce;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sim = ref.watch(simulationProvider(projectId));
    final notifier = ref.read(simulationProvider(projectId).notifier);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.icon(
          onPressed: sim.running || sim.live ? null : onSimulateOnce,
          icon: sim.running
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.sensors, size: 18),
          label: const Text('Simulate Live Sensor'),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'Continuous feed every ${SimulationNotifier.liveInterval.inSeconds}s',
          child: FilterChip(
            selected: sim.live,
            onSelected: notifier.setLive,
            avatar: Icon(sim.live ? Icons.stop_circle_outlined : Icons.play_circle_outline, size: 18),
            label: Text(sim.live ? 'Live · ${sim.ticks}' : 'Live'),
            showCheckmark: false,
          ),
        ),
      ],
    );
  }
}
