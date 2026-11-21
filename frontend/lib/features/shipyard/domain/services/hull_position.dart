import 'package:flutter/foundation.dart' show mapEquals;

import '../entities/production_entities.dart';
import 'draft_schedule.dart';

/// Where a hull is in its life: on the berth / in the building dock, afloat at a
/// quay, docked after launching (or for a repair), out on sea trials, delivered.
enum HullPositionKind {
  building('Building'),
  afloat('Afloat'),
  docked('Docked'),
  atSea('At sea'),
  delivered('Delivered');

  const HullPositionKind(this.label);
  final String label;
}

/// Position of a hull at a date: the yard area it lies at ([areaNodeId], `null`
/// when the hull is not in the yard) and the schedule row that decides it.
class HullPosition {
  const HullPosition(this.kind, {this.areaNodeId, this.activity});

  final HullPositionKind kind;
  final String? areaNodeId;
  final ProductionActivity? activity;

  bool get inYard => areaNodeId != null;

  @override
  bool operator ==(Object other) => other is HullPosition && other.kind == kind && other.areaNodeId == areaNodeId;

  @override
  int get hashCode => Object.hash(kind, areaNodeId);
}

/// Positions of all hulls of a yard keyed by hull id (value equality, so the 3D
/// geometry is only rebuilt when a hull actually moves).
class HullPositionMap {
  const HullPositionMap(this.byHullId);

  final Map<String, HullPosition> byHullId;

  HullPosition? operator [](String hullId) => byHullId[hullId];

  @override
  bool operator ==(Object other) => other is HullPositionMap && mapEquals(other.byHullId, byHullId);

  @override
  int get hashCode => Object.hashAllUnordered(byHullId.entries.map((e) => Object.hash(e.key, e.value)));
}

/// Moves a hull through the yard by its hull-level schedule rows:
///  * before launching ends: where it is built (the area of its erection rows;
///    the dry dock if the hull lies there, else the building berth)
///  * after launching: at the area of the running afloat row (outfitting /
///    commissioning / delivery at the quay, docking in a dock); between rows at
///    the outfitting quay
///  * a running row without an area (sea trials) = at sea; after the delivery
///    row ended the hull has left the yard
/// Hulls without a launching row lie at their `location_node_id`.
class HullPositions {
  const HullPositions._();

  static final berth = stageDefaultLocations[ProductionStage.erection]!;
  static final dryDock = stageDefaultLocations[ProductionStage.dockingRepair]!;
  static final quay = stageDefaultLocations[ProductionStage.outfitting]!;
  static const floatingDock = 'NODE_A18_FLOATING_DOCK';

  /// Area the hull is built at: its erection rows, else the dry dock if it lies
  /// there, else the building berth.
  static String buildSite(Hull hull, Iterable<ProductionActivity> activities) {
    for (final a in activities) {
      if (a.hullId == hull.id && a.stage == ProductionStage.erection && _isBuildSite(a.locationNodeId)) {
        return a.locationNodeId!;
      }
    }
    return hull.locationNodeId == dryDock ? dryDock : berth;
  }

  static bool _isBuildSite(String? node) => node == berth || node == dryDock;

  /// Position of every hull at [date] ([activities] of the whole yard).
  static HullPositionMap all(List<Hull> hulls, List<ProductionActivity> activities, DateTime date, DateTime today) {
    final byHull = <String, List<ProductionActivity>>{};
    for (final a in activities) {
      if (a.hullId != null) (byHull[a.hullId!] ??= []).add(a);
    }
    return HullPositionMap({for (final h in hulls) h.id: at(h, byHull[h.id] ?? const [], date, today)});
  }

  /// Position of [hull] at [date] from its [activities] (forecast dates).
  static HullPosition at(Hull hull, List<ProductionActivity> activities, DateTime date, DateTime today) {
    final d = dateOnly(date);
    final own = activities.where((a) => a.hullId == hull.id).toList();
    final hullRows = own.where((a) => a.componentId == null).toList();
    bool running(ProductionActivity a) => !d.isBefore(a.forecastStart(today)) && d.isBefore(a.forecastEnd(today));
    bool finished(ProductionActivity a) => !a.forecastEnd(today).isAfter(d);

    final launches = hullRows.where((a) => a.stage == ProductionStage.launching).toList()
      ..sort((a, b) => a.forecastEnd(today).compareTo(b.forecastEnd(today)));
    if (launches.isEmpty) return fromLocation(hull, own);

    final launch = launches.last;
    if (!finished(launch)) {
      final site = buildSite(hull, own);
      return HullPosition(
        site == dryDock && hull.isRepair ? HullPositionKind.docked : HullPositionKind.building,
        areaNodeId: site,
        activity: running(launch) ? launch : null,
      );
    }

    final afloat = hullRows.where((a) => a.stage.index > ProductionStage.launching.index).toList();
    final current = afloat.where(running).toList()
      ..sort((a, b) => a.forecastStart(today).compareTo(b.forecastStart(today)));
    if (current.isNotEmpty) {
      final a = current.last;
      if (a.locationNodeId == null) return HullPosition(HullPositionKind.atSea, activity: a);
      return _afloatAt(a.locationNodeId!, a);
    }
    final done = afloat.where(finished).toList()..sort((a, b) => a.forecastEnd(today).compareTo(b.forecastEnd(today)));
    final last = done.isEmpty ? launch : done.last;
    if (last.stage == ProductionStage.delivery) return HullPosition(HullPositionKind.delivered, activity: last);
    return HullPosition(HullPositionKind.afloat, areaNodeId: quay, activity: last);
  }

  /// Afloat hull during a row at [node]: docks keep it, everything else is at the quay.
  static HullPosition _afloatAt(String node, ProductionActivity activity) => node == dryDock || node == floatingDock
      ? HullPosition(HullPositionKind.docked, areaNodeId: node, activity: activity)
      : HullPosition(HullPositionKind.afloat, areaNodeId: quay, activity: activity);

  /// Position from `location_node_id` alone (no launching row): quay, floating dock,
  /// else where the hull is built.
  static HullPosition fromLocation(Hull hull, [List<ProductionActivity> own = const []]) {
    final node = hull.locationNodeId;
    if (node == quay) return HullPosition(HullPositionKind.afloat, areaNodeId: quay);
    if (node == floatingDock) return HullPosition(HullPositionKind.docked, areaNodeId: floatingDock);
    final site = buildSite(hull, own);
    return HullPosition(
      site == dryDock && hull.isRepair ? HullPositionKind.docked : HullPositionKind.building,
      areaNodeId: site,
    );
  }
}
