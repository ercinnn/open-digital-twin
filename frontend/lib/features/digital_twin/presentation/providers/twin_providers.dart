import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/core_providers.dart';
import '../../data/repositories/twin_repository_impl.dart';
import '../../domain/entities/twin_entities.dart';
import '../../domain/repositories/twin_repository.dart';

final twinRepositoryProvider = Provider<TwinRepository>((ref) {
  return TwinRepositoryImpl(supabase: ref.watch(supabaseClientProvider), backend: ref.watch(backendApiClientProvider));
});

/// Realtime BOM of a project; status changes arrive through Supabase Realtime.
final componentsProvider = StreamProvider.autoDispose.family<List<TwinComponent>, String>((ref, projectId) {
  return ref.watch(twinRepositoryProvider).watchComponents(projectId);
});

/// Realtime telemetry of one component (newest first).
final telemetryProvider = StreamProvider.autoDispose.family<List<TelemetryReading>, String>((ref, componentId) {
  return ref.watch(twinRepositoryProvider).watchTelemetry(componentId);
});

final documentsProvider = FutureProvider.autoDispose.family<List<TwinDocument>, String>((ref, componentId) {
  return ref.watch(twinRepositoryProvider).fetchDocuments(componentId);
});

/// Currently selected `mesh_node_id` in a project's twin view.
class SelectedNodeNotifier extends Notifier<String?> {
  SelectedNodeNotifier(this.projectId);

  final String projectId;

  @override
  String? build() => null;

  void select(String? meshNodeId) => state = meshNodeId;
}

final selectedNodeProvider = NotifierProvider.autoDispose.family<SelectedNodeNotifier, String?, String>(
  SelectedNodeNotifier.new,
);

/// Selected component resolved from the realtime component list.
final selectedComponentProvider = Provider.autoDispose.family<TwinComponent?, String>((ref, projectId) {
  final nodeId = ref.watch(selectedNodeProvider(projectId));
  final components = ref.watch(componentsProvider(projectId)).value;
  if (nodeId == null || components == null) return null;
  for (final c in components) {
    if (c.meshNodeId == nodeId) return c;
  }
  return null;
});

/// "Simulate Live Sensor": single shots or a continuous live feed.
class SimulationState {
  const SimulationState({this.running = false, this.live = false, this.lastResult, this.error, this.ticks = 0});

  final bool running;
  final bool live;
  final SimulationResult? lastResult;
  final String? error;
  final int ticks;

  SimulationState copyWith({bool? running, bool? live, SimulationResult? lastResult, String? error, int? ticks}) {
    return SimulationState(
      running: running ?? this.running,
      live: live ?? this.live,
      lastResult: lastResult ?? this.lastResult,
      error: error,
      ticks: ticks ?? this.ticks,
    );
  }
}

class SimulationNotifier extends Notifier<SimulationState> {
  SimulationNotifier(this.projectId);

  static const liveInterval = Duration(seconds: 3);

  final String projectId;
  Timer? _timer;

  @override
  SimulationState build() {
    ref.onDispose(() => _timer?.cancel());
    return const SimulationState();
  }

  Future<SimulationResult?> simulateOnce() async {
    if (state.running) return null;
    state = state.copyWith(running: true);
    try {
      final result = await ref.read(twinRepositoryProvider).simulateTelemetry(projectId);
      if (!ref.mounted) return result;
      state = state.copyWith(running: false, lastResult: result, ticks: state.ticks + 1);
      return result;
    } catch (e) {
      if (ref.mounted) state = state.copyWith(running: false, error: '$e', live: false);
      _timer?.cancel();
      return null;
    }
  }

  void setLive(bool enabled) {
    _timer?.cancel();
    state = state.copyWith(live: enabled);
    if (enabled) {
      simulateOnce();
      _timer = Timer.periodic(liveInterval, (_) => simulateOnce());
    }
  }
}

final simulationProvider = NotifierProvider.autoDispose.family<SimulationNotifier, SimulationState, String>(
  SimulationNotifier.new,
);
