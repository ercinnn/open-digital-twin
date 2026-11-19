import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/core_providers.dart';
import '../../../digital_twin/presentation/providers/twin_providers.dart';
import '../../data/repositories/shipyard_repository_impl.dart';
import '../../domain/entities/hse_entities.dart';
import '../../domain/entities/material_entities.dart';
import '../../domain/entities/production_entities.dart';
import '../../domain/entities/quality_entities.dart';
import '../../domain/entities/resource_entities.dart';
import '../../domain/repositories/shipyard_repository.dart';
import '../../domain/services/production_schedule.dart';
import '../../domain/services/yard_kpis.dart';
import 'scene_view_providers.dart' show organizationProvider;

final shipyardRepositoryProvider = Provider<ShipyardRepository>((ref) {
  return ShipyardRepositoryImpl(supabase: ref.watch(supabaseClientProvider));
});

/// Today's calendar day (overridable in tests).
final todayProvider = Provider<DateTime>((ref) => dateOnly(DateTime.now()));

final hullsProvider = FutureProvider.autoDispose.family<List<Hull>, String>((ref, projectId) {
  return ref.watch(shipyardRepositoryProvider).fetchHulls(projectId);
});

/// The operations dock is shown for projects that have shipyard data: hulls or a
/// yard organization (departments). A yard without any hull keeps the dock, so
/// the first hull can be created from the Production tab.
final shipyardEnabledProvider = Provider.autoDispose.family<bool, String>((ref, projectId) {
  final hasHulls = ref.watch(hullsProvider(projectId)).value?.isNotEmpty ?? false;
  final hasOrganization = !(ref.watch(organizationProvider(projectId)).value?.isEmpty ?? true);
  return hasHulls || hasOrganization;
});

final activitiesProvider = StreamProvider.autoDispose.family<List<ProductionActivity>, String>((ref, projectId) {
  return ref.watch(shipyardRepositoryProvider).watchActivities(projectId);
});

final scheduleProvider = Provider.autoDispose.family<ProductionSchedule, String>((ref, projectId) {
  return ProductionSchedule(ref.watch(activitiesProvider(projectId)).value ?? const []);
});

/// 3D timeline: `date == null` means live (today).
class TimelineState {
  const TimelineState({this.date, this.playing = false});

  final DateTime? date;
  final bool playing;

  bool get isLive => date == null;
}

class TimelineNotifier extends Notifier<TimelineState> {
  TimelineNotifier(this.projectId);

  static const tick = Duration(milliseconds: 110);

  final String projectId;
  Timer? _timer;

  @override
  TimelineState build() {
    ref.onDispose(() => _timer?.cancel());
    return const TimelineState();
  }

  DateTime get _today => ref.read(todayProvider);

  void setDate(DateTime date) {
    final d = dateOnly(date);
    state = TimelineState(date: d == _today && !state.playing ? null : d, playing: state.playing);
  }

  void goLive() {
    _timer?.cancel();
    state = const TimelineState();
  }

  void step(int days) => setDate(addDays(state.date ?? _today, days));

  void togglePlay() => state.playing ? pause() : play();

  void play() {
    final range = ref.read(scheduleProvider(projectId)).range(_today);
    if (range == null) return;
    var start = state.date ?? _today;
    if (!start.isBefore(range.$2)) start = range.$1;
    state = TimelineState(date: start, playing: true);
    _timer?.cancel();
    _timer = Timer.periodic(tick, (_) {
      if (!ref.mounted) return;
      final next = addDays(state.date ?? _today, 1);
      if (next.isAfter(range.$2)) {
        pause();
        return;
      }
      state = TimelineState(date: next, playing: true);
    });
  }

  void pause() {
    _timer?.cancel();
    _timer = null;
    state = TimelineState(date: state.date, playing: false);
  }
}

final timelineProvider = NotifierProvider.autoDispose.family<TimelineNotifier, TimelineState, String>(
  TimelineNotifier.new,
);

/// Date shown in 3D (timeline date or today).
final sceneDateProvider = Provider.autoDispose.family<DateTime, String>((ref, projectId) {
  return ref.watch(timelineProvider(projectId)).date ?? ref.watch(todayProvider);
});

/// Block placements keyed by mesh_node_id for the scene date.
final blockPlacementsProvider = Provider.autoDispose.family<Map<String, BlockPlacement>, String>((ref, projectId) {
  final components = ref.watch(componentsProvider(projectId)).value ?? const [];
  final schedule = ref.watch(scheduleProvider(projectId));
  final date = ref.watch(sceneDateProvider(projectId));
  final today = ref.watch(todayProvider);
  final byComponent = schedule.placementsAt(date, today);
  return {
    for (final c in components)
      if (byComponent[c.id] != null) c.meshNodeId: byComponent[c.id]!,
  };
});

final bookingsProvider = StreamProvider.autoDispose.family<List<ResourceBooking>, String>((ref, projectId) {
  return ref.watch(shipyardRepositoryProvider).watchBookings(projectId);
});

final materialsProvider = FutureProvider.autoDispose.family<List<MaterialItem>, String>((ref, projectId) {
  return ref.watch(shipyardRepositoryProvider).fetchMaterials(projectId);
});

/// Block material reservations (012). Invalidate together with [materialsProvider]
/// after a change: the database updates the item totals.
final reservationsProvider = FutureProvider.autoDispose.family<List<MaterialReservation>, String>((ref, projectId) {
  return ref.watch(shipyardRepositoryProvider).fetchReservations(projectId);
});

final recentTagsProvider =FutureProvider.autoDispose.family<List<String>, String>((ref, projectId) {
  return ref.watch(shipyardRepositoryProvider).fetchRecentTags(projectId);
});

/// History of one tag: key = (projectId, normalized tag).
final traceProvider = FutureProvider.autoDispose.family<List<TraceEvent>, (String, String)>((ref, key) {
  return ref.watch(shipyardRepositoryProvider).fetchTrace(key.$1, key.$2);
});

final inspectionsProvider = FutureProvider.autoDispose.family<List<QualityInspection>, String>((ref, projectId) {
  return ref.watch(shipyardRepositoryProvider).fetchInspections(projectId);
});

final punchItemsProvider = StreamProvider.autoDispose.family<List<PunchItem>, String>((ref, projectId) {
  return ref.watch(shipyardRepositoryProvider).watchPunchItems(projectId);
});

final permitsProvider = StreamProvider.autoDispose.family<List<WorkPermit>, String>((ref, projectId) {
  return ref.watch(shipyardRepositoryProvider).watchPermits(projectId);
});

final zonesProvider = FutureProvider.autoDispose.family<List<HseZone>, String>((ref, projectId) {
  return ref.watch(shipyardRepositoryProvider).fetchZones(projectId);
});

final incidentsProvider = FutureProvider.autoDispose.family<List<HseIncident>, String>((ref, projectId) {
  return ref.watch(shipyardRepositoryProvider).fetchIncidents(projectId);
});

/// Clock for time-dependent HSE / booking views (ticks every minute).
final nowProvider = StreamProvider.autoDispose<DateTime>((ref) {
  return Stream<DateTime>.periodic(const Duration(minutes: 1), (_) => DateTime.now());
});

/// Latest telemetry, refreshed every minute (the simulator writes one reading per minute).
final latestTelemetryProvider = FutureProvider.autoDispose.family<List<LatestReading>, String>((ref, projectId) {
  ref.watch(nowProvider);
  return ref.watch(shipyardRepositoryProvider).fetchLatestTelemetry(projectId);
});

/// Yard-wide KPIs for the management dashboard.
final yardKpisProvider = Provider.autoDispose.family<YardKpis, String>((ref, projectId) {
  return YardKpis.compute(
    now: ref.watch(nowProvider).value ?? DateTime.now(),
    hulls: ref.watch(hullsProvider(projectId)).value ?? const [],
    activities: ref.watch(activitiesProvider(projectId)).value ?? const [],
    components: ref.watch(componentsProvider(projectId)).value ?? const [],
    readings: ref.watch(latestTelemetryProvider(projectId)).value ?? const [],
    bookings: ref.watch(bookingsProvider(projectId)).value ?? const [],
    organization: ref.watch(organizationProvider(projectId)).value,
    materials: ref.watch(materialsProvider(projectId)).value ?? const [],
    punch: ref.watch(punchItemsProvider(projectId)).value ?? const [],
    inspections: ref.watch(inspectionsProvider(projectId)).value ?? const [],
    permits: ref.watch(permitsProvider(projectId)).value ?? const [],
    incidents: ref.watch(incidentsProvider(projectId)).value ?? const [],
  );
});
