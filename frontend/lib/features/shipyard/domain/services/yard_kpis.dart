import '../../../../core/status/component_status.dart';
import '../../../digital_twin/domain/entities/twin_entities.dart';
import '../entities/hse_entities.dart';
import '../entities/material_entities.dart';
import '../entities/organization_entities.dart';
import '../entities/production_entities.dart';
import '../entities/quality_entities.dart';
import '../entities/resource_entities.dart';
import 'production_schedule.dart';

/// Latest value of one metric of one component (RPC `latest_telemetry`).
class LatestReading {
  const LatestReading({required this.componentId, required this.metricName, required this.value, required this.recordedAt, this.unit});

  final String componentId;
  final String metricName;
  final double value;
  final String? unit;
  final DateTime recordedAt;
}

enum Severity { info, warning, critical }

/// One line of the "needs attention" list.
class AttentionItem {
  const AttentionItem({required this.severity, required this.title, required this.detail, this.componentId});

  final Severity severity;
  final String title;
  final String detail;
  final String? componentId;
}

/// Progress and delivery risk of one hull.
class HullHealth {
  const HullHealth({
    required this.hull,
    required this.progress,
    required this.openPunchA,
    this.nextMilestone,
    this.nextMilestoneDate,
  });

  final Hull hull;
  final ScheduleProgress progress;
  final int openPunchA;
  final String? nextMilestone;
  final DateTime? nextMilestoneDate;

  int? get delayDays => hull.deliveryDelayDays;

  int? daysToDelivery(DateTime today) =>
      hull.forecastDeliveryDate == null ? null : daysBetween(today, hull.forecastDeliveryDate!);

  /// Behind plan by more than 5 % or forecast delivery after the contract date.
  bool get atRisk => (delayDays ?? 0) > 0 || progress.variancePct < -5;
}

/// Yard-wide key figures computed from the operations data (pure, testable).
class YardKpis {
  const YardKpis({
    required this.hulls,
    required this.avgOee,
    required this.avgUtilization,
    required this.bottlenecks,
    required this.cranesAvailable,
    required this.cranesTotal,
    required this.docksOccupied,
    required this.docksTotal,
    required this.headcount,
    required this.stockAlerts,
    required this.openPunch,
    required this.overduePunch,
    required this.lateActivities,
    required this.hse,
    required this.attention,
  });

  final List<HullHealth> hulls;
  final double? avgOee;
  final double? avgUtilization;
  final List<TwinComponent> bottlenecks;
  final int cranesAvailable;
  final int cranesTotal;
  final int docksOccupied;
  final int docksTotal;
  final int headcount;
  final int stockAlerts;
  final int openPunch;
  final int overduePunch;
  final int lateActivities;
  final HseSummary hse;
  final List<AttentionItem> attention;

  static const productionCategories = {'steel_fabrication', 'block_assembly', 'outfitting_shops', 'surface_treatment'};
  static const dockCategories = {'docks_and_berths', 'floating_dock', 'outfitting_quay'};

  static YardKpis compute({
    required DateTime now,
    required List<Hull> hulls,
    required List<ProductionActivity> activities,
    required List<TwinComponent> components,
    required List<LatestReading> readings,
    required List<ResourceBooking> bookings,
    Organization? organization,
    List<MaterialItem> materials = const [],
    List<PunchItem> punch = const [],
    List<QualityInspection> inspections = const [],
    List<WorkPermit> permits = const [],
    List<HseIncident> incidents = const [],
  }) {
    final today = dateOnly(now);
    final schedule = ProductionSchedule(activities);
    final byId = {for (final c in components) c.id: c};

    // ---- hulls
    final health = <HullHealth>[];
    for (final h in hulls) {
      final milestones = <(String, DateTime?)>[
        ('Steel cutting', h.steelCuttingDate),
        ('Keel laying', h.keelLayingDate),
        ('Launching', h.launchingDate),
        ('Delivery', h.forecastDeliveryDate ?? h.contractDeliveryDate),
      ].where((m) => m.$2 != null && !m.$2!.isBefore(today)).toList()
        ..sort((a, b) => a.$2!.compareTo(b.$2!));
      health.add(
        HullHealth(
          hull: h,
          progress: schedule.progressForHull(h.id, today),
          openPunchA: punch.where((p) => p.hullId == h.id && p.isOpen && p.priority == PunchPriority.a).length,
          nextMilestone: milestones.isEmpty ? null : milestones.first.$1,
          nextMilestoneDate: milestones.isEmpty ? null : milestones.first.$2,
        ),
      );
    }

    // ---- shop performance from the latest telemetry
    double? avg(String metric, Set<String> categories) {
      final values = readings
          .where((r) => r.metricName == metric && categories.contains(byId[r.componentId]?.category))
          .map((r) => r.value)
          .toList();
      return values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;
    }

    final bottlenecks = components
        .where((c) => productionCategories.contains(c.category))
        .where((c) => c.status == ComponentStatus.warning || c.status == ComponentStatus.alert ||
            readings.any((r) => r.componentId == c.id && r.metricName == 'wip_backlog_days' && r.value > 5))
        .toList();

    final cranes = components.where((c) => c.category == 'crane').toList();
    final docks = components.where((c) => dockCategories.contains(c.category)).toList();
    final activeBookings = bookings.where((b) => !b.isCancelled && !b.startsAt.isAfter(now) && b.endsAt.isAfter(now));
    final occupiedDocks = docks.where((d) => activeBookings.any((b) => b.componentId == d.id && b.type != BookingType.maintenance)).length;

    final headcount = organization == null ? 0 : organization.headcount(organization.departments.map((d) => d.id).toSet());
    final stockAlerts = materials.where((m) => m.state != StockState.ok).toList();
    final openPunch = punch.where((p) => p.isOpen).toList();
    final late = activities.where((a) => !a.isDone && a.isLate(today)).toList();
    final hse = HseSummary.of(incidents, permits, now);

    // ---- attention list
    final attention = <AttentionItem>[];
    for (final c in cranes.where((c) => c.status == ComponentStatus.alert)) {
      final suspended = bookings.where((b) => b.componentId == c.id && b.status == BookingStatus.suspended).length;
      attention.add(AttentionItem(
        severity: Severity.critical,
        title: '${c.name} in ALERT',
        detail: suspended == 0 ? 'Crane alarm (wind / overload)' : '$suspended lift(s) suspended automatically',
        componentId: c.id,
      ));
    }
    for (final h in health.where((h) => (h.delayDays ?? 0) > 0)) {
      attention.add(AttentionItem(
        severity: Severity.critical,
        title: '${h.hull.hullNo} delivery forecast +${h.delayDays} days',
        detail: 'Earned ${h.progress.earnedPct.round()} % vs planned ${h.progress.plannedPct.round()} %',
      ));
    }
    for (final c in bottlenecks) {
      attention.add(AttentionItem(
        severity: c.status == ComponentStatus.alert ? Severity.critical : Severity.warning,
        title: 'Bottleneck: ${c.name}',
        detail: '${c.metadata['warning_reason'] ?? 'Utilization / WIP above threshold'}',
        componentId: c.id,
      ));
    }
    late.sort((a, b) => a.plannedEnd.compareTo(b.plannedEnd));
    for (final a in late.take(5)) {
      attention.add(AttentionItem(
        severity: Severity.warning,
        title: 'Late: ${a.name}',
        detail: 'Planned end ${formatDate(a.plannedEnd)}, ${a.progressPct.round()} % done',
        componentId: a.componentId,
      ));
    }
    for (final q in inspections.where((q) => q.result == InspectionResult.fail)) {
      attention.add(AttentionItem(
        severity: Severity.warning,
        title: 'Failed inspection ${q.referenceNo}',
        detail: q.description ?? q.type.label,
        componentId: q.componentId,
      ));
    }
    for (final m in stockAlerts.where((m) => m.state == StockState.shortage)) {
      attention.add(AttentionItem(
        severity: Severity.warning,
        title: 'Shortage: ${m.itemCode}',
        detail: '${m.description} - ${(-m.available).toStringAsFixed(0)} ${m.unit} missing for reservations',
        componentId: m.locationComponentId,
      ));
    }
    for (final p in permits.where((p) => p.isLive(now) && p.remaining(now).inMinutes <= 120)) {
      attention.add(AttentionItem(
        severity: Severity.info,
        title: 'Permit ${p.permitNo} expires soon',
        detail: '${p.type.label}: ${p.remaining(now).inMinutes} min left',
        componentId: p.componentId,
      ));
    }
    attention.sort((a, b) => b.severity.index.compareTo(a.severity.index));

    return YardKpis(
      hulls: health,
      avgOee: avg('oee', productionCategories),
      avgUtilization: avg('capacity_utilization', productionCategories),
      bottlenecks: bottlenecks,
      cranesAvailable: cranes.where((c) => c.status != ComponentStatus.alert).length,
      cranesTotal: cranes.length,
      docksOccupied: occupiedDocks,
      docksTotal: docks.length,
      headcount: headcount,
      stockAlerts: stockAlerts.length,
      openPunch: openPunch.length,
      overduePunch: openPunch.where((p) => p.isOverdue(today)).length,
      lateActivities: late.length,
      hse: hse,
      attention: attention,
    );
  }
}
