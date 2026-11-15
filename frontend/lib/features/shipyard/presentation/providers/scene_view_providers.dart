import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../digital_twin/presentation/providers/twin_providers.dart';
import '../../../digital_twin/presentation/viewer/three_viewer_controller.dart';
import '../../domain/entities/hse_entities.dart';
import '../../domain/entities/organization_entities.dart';
import '../../domain/entities/quality_entities.dart';
import '../widgets/scene_actions.dart' show shortComponentName;
import 'shipyard_providers.dart';

/// Color overlays the twin view can show instead of status / material colors.
enum SceneOverlay {
  department('Color by department'),
  hseZones('HSE zones');

  const SceneOverlay(this.label);
  final String label;
}

/// View options of the shipyard 3D scene (overlay, focused department, layers).
class SceneViewState {
  const SceneViewState({
    this.overlay,
    this.focusDepartmentId,
    this.qualityPins = true,
    this.hsePins = true,
    this.permitBlink = true,
    this.labels = false,
    this.hiddenLayers = const {},
  });

  final SceneOverlay? overlay;
  final String? focusDepartmentId;

  /// Open punch items + failed inspections as 3D pins.
  final bool qualityPins;

  /// Active work permits + open incidents as 3D pins.
  final bool hsePins;

  /// Areas with an active work permit blink.
  final bool permitBlink;

  /// Area / crane name labels in 3D.
  final bool labels;

  /// Hidden component categories (layer filter), e.g. {'crane'}.
  final Set<String> hiddenLayers;

  SceneViewState copyWith({
    SceneOverlay? overlay,
    bool clearOverlay = false,
    String? focusDepartmentId,
    bool clearFocusDepartment = false,
    bool? qualityPins,
    bool? hsePins,
    bool? permitBlink,
    bool? labels,
    Set<String>? hiddenLayers,
  }) {
    return SceneViewState(
      overlay: clearOverlay ? null : (overlay ?? this.overlay),
      focusDepartmentId: clearFocusDepartment ? null : (focusDepartmentId ?? this.focusDepartmentId),
      qualityPins: qualityPins ?? this.qualityPins,
      hsePins: hsePins ?? this.hsePins,
      permitBlink: permitBlink ?? this.permitBlink,
      labels: labels ?? this.labels,
      hiddenLayers: hiddenLayers ?? this.hiddenLayers,
    );
  }
}

class SceneViewNotifier extends Notifier<SceneViewState> {
  SceneViewNotifier(this.projectId);

  final String projectId;

  @override
  SceneViewState build() => const SceneViewState();

  void setOverlay(SceneOverlay? overlay) =>
      state = overlay == null ? state.copyWith(clearOverlay: true) : state.copyWith(overlay: overlay);

  void setQualityPins(bool v) => state = state.copyWith(qualityPins: v);

  void setHsePins(bool v) => state = state.copyWith(hsePins: v);

  void setPermitBlink(bool v) => state = state.copyWith(permitBlink: v);

  void setLabels(bool v) => state = state.copyWith(labels: v);

  void toggleLayer(String category) {
    final next = {...state.hiddenLayers};
    if (!next.remove(category)) next.add(category);
    state = state.copyWith(hiddenLayers: next);
  }

  /// Focus a department: its areas are colored, everything else dimmed.
  void focusDepartment(String? departmentId) {
    state = departmentId == null
        ? state.copyWith(clearFocusDepartment: true)
        : state.copyWith(focusDepartmentId: departmentId, overlay: SceneOverlay.department);
  }
}

final sceneViewProvider = NotifierProvider.autoDispose.family<SceneViewNotifier, SceneViewState, String>(
  SceneViewNotifier.new,
);

final organizationProvider = FutureProvider.autoDispose.family<Organization, String>((ref, projectId) {
  return ref.watch(shipyardRepositoryProvider).fetchOrganization(projectId);
});

/// mesh_node_id -> '#rrggbb' for the active overlay (empty when none).
final overlayColorsProvider = Provider.autoDispose.family<Map<String, String>, String>((ref, projectId) {
  final view = ref.watch(sceneViewProvider(projectId));
  final components = ref.watch(componentsProvider(projectId)).value ?? const [];
  switch (view.overlay) {
    case null:
      return const {};
    case SceneOverlay.department:
      final org = ref.watch(organizationProvider(projectId)).value;
      if (org == null) return const {};
      final focus = view.focusDepartmentId;
      if (focus != null) {
        final dept = org.byId[focus];
        final involved = org.componentsOf(org.subtreeIds(focus));
        return {
          for (final c in components)
            if (involved.containsKey(c.id)) c.meshNodeId: dept?.colorHex ?? '#22d3ee',
        };
      }
      final responsible = org.responsibleByComponent();
      return {
        for (final c in components)
          if (responsible[c.id] != null) c.meshNodeId: responsible[c.id]!.colorHex,
      };
    case SceneOverlay.hseZones:
      final zones = ref.watch(zonesProvider(projectId)).value ?? const <HseZone>[];
      final nodeById = {for (final c in components) c.id: c.meshNodeId};
      final result = <String, String>{};
      // Applied from least to most severe, so the most severe zone type wins (enum order).
      final active = zones.where((z) => z.active).toList()..sort((a, b) => b.type.index.compareTo(a.type.index));
      for (final z in active) {
        final node = nodeById[z.componentId];
        if (node != null) result[node] = z.type.hex;
      }
      return result;
  }
});

String _hex(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Blinking areas: components with a live work permit (permit type color).
final sceneHighlightsProvider = Provider.autoDispose.family<Map<String, String>, String>((ref, projectId) {
  final view = ref.watch(sceneViewProvider(projectId));
  if (!view.permitBlink) return const {};
  final now = ref.watch(nowProvider).value ?? DateTime.now();
  final components = ref.watch(componentsProvider(projectId)).value ?? const [];
  final nodeById = {for (final c in components) c.id: c.meshNodeId};
  final result = <String, String>{};
  for (final p in ref.watch(permitsProvider(projectId)).value ?? const <WorkPermit>[]) {
    final node = nodeById[p.componentId];
    if (node == null || !p.isLive(now)) continue;
    result[node] = _hex(p.type.color.toARGB32());
  }
  return result;
});

/// 3D pins of the enabled layers. Ids are prefixed by kind ('punch:', 'qi:', ...).
final sceneMarkersProvider = Provider.autoDispose.family<List<ViewerMarker>, String>((ref, projectId) {
  final view = ref.watch(sceneViewProvider(projectId));
  final components = ref.watch(componentsProvider(projectId)).value ?? const [];
  final nodeById = {for (final c in components) c.id: c.meshNodeId};
  final markers = <ViewerMarker>[];
  if (view.qualityPins) {
    for (final p in ref.watch(punchItemsProvider(projectId)).value ?? const <PunchItem>[]) {
      final node = nodeById[p.componentId];
      if (node == null || !p.isOpen) continue;
      markers.add(ViewerMarker(
        id: 'punch:${p.id}',
        meshNodeId: node,
        color: _hex(p.priority.color.toARGB32()),
        label: p.priority.dbValue,
        u: p.position.u,
        v: p.position.v,
        w: p.position.w,
      ));
    }
    for (final q in ref.watch(inspectionsProvider(projectId)).value ?? const <QualityInspection>[]) {
      final node = nodeById[q.componentId];
      if (node == null || (q.result != InspectionResult.fail && q.result != InspectionResult.conditional)) continue;
      markers.add(ViewerMarker(
        id: 'qi:${q.id}',
        meshNodeId: node,
        color: q.result == InspectionResult.fail ? '#a855f7' : '#c4b5fd',
        label: 'Q',
        u: q.position.u,
        v: q.position.v,
        w: q.position.w,
      ));
    }
  }
  if (view.hsePins) {
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    for (final p in ref.watch(permitsProvider(projectId)).value ?? const <WorkPermit>[]) {
      final node = nodeById[p.componentId];
      if (node == null || !(p.isLive(now) || p.status == PermitStatus.suspended)) continue;
      markers.add(ViewerMarker(
        id: 'permit:${p.id}',
        meshNodeId: node,
        color: p.status == PermitStatus.suspended ? '#94a3b8' : _hex(p.type.color.toARGB32()),
        label: p.type.letter,
        u: p.position.u,
        v: p.position.v,
        w: p.position.w,
      ));
    }
    for (final i in ref.watch(incidentsProvider(projectId)).value ?? const <HseIncident>[]) {
      final node = i.componentId == null ? null : nodeById[i.componentId];
      if (node == null || !i.isOpen) continue;
      markers.add(ViewerMarker(
        id: 'incident:${i.id}',
        meshNodeId: node,
        color: '#ef4444',
        label: '!',
        u: i.position.u,
        v: i.position.v,
        w: i.position.w,
      ));
    }
  }
  return markers;
});

/// Short 3D labels for areas, cranes and blocks.
final sceneLabelsProvider = Provider.autoDispose.family<Map<String, String>, String>((ref, projectId) {
  final components = ref.watch(componentsProvider(projectId)).value ?? const [];
  return {for (final c in components) c.meshNodeId: shortComponentName(c)};
});

/// Nodes hidden by the category layer filter.
final sceneHiddenProvider = Provider.autoDispose.family<Set<String>, String>((ref, projectId) {
  final hidden = ref.watch(sceneViewProvider(projectId)).hiddenLayers;
  if (hidden.isEmpty) return const {};
  final components = ref.watch(componentsProvider(projectId)).value ?? const [];
  return {
    for (final c in components)
      if (hidden.contains(c.category)) c.meshNodeId,
  };
});
