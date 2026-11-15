import '../entities/hse_entities.dart';
import '../entities/material_entities.dart';
import '../entities/organization_entities.dart';
import '../entities/production_entities.dart';
import '../entities/quality_entities.dart';
import '../entities/resource_entities.dart';
import '../services/yard_kpis.dart' show LatestReading;

/// Shipyard operations data of one yard project (migrations 005..011).
/// User-facing database error (constraint / trigger messages translated).
class ShipyardException implements Exception {
  const ShipyardException(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract interface class ShipyardRepository {
  // ---- Production (005) -------------------------------------------------------
  Future<List<Hull>> fetchHulls(String projectId);

  /// Creates a hull (editors). Throws [ShipyardException] e.g. for a duplicate hull number.
  Future<Hull> createHull(HullDraft draft);

  /// Updates the particulars, milestones, status and location of a hull (editors).
  Future<Hull> updateHull(String hullId, HullDraft draft);

  /// Realtime schedule rows of a project.
  Stream<List<ProductionActivity>> watchActivities(String projectId);

  Future<void> updateActivityProgress(ProductionActivity activity);

  /// Inserts schedule rows in one request (all or nothing). Throws [ShipyardException].
  Future<void> createActivities(List<ActivityDraft> drafts);

  /// Changes name, stage, location and planned dates of a schedule row.
  Future<void> updateActivityPlan(String activityId, ActivityDraft draft);

  /// Deletes a schedule row (linked resource bookings keep their time, the link is cleared).
  Future<void> deleteActivity(String activityId);

  // ---- Organization (006) -----------------------------------------------------
  Future<Organization> fetchOrganization(String projectId);

  // ---- Resources (007) --------------------------------------------------------
  /// Realtime bookings (status changes by the crane-alarm trigger arrive live).
  Stream<List<ResourceBooking>> watchBookings(String projectId);

  /// Throws [ShipyardException] on double booking or capacity violations.
  Future<void> createBooking(BookingDraft draft);

  Future<void> setBookingStatus(String bookingId, BookingStatus status);

  // ---- Materials (008) --------------------------------------------------------
  Future<List<MaterialItem>> fetchMaterials(String projectId);

  /// Full history of a tag (normalized with [normalizeTag]), oldest first.
  Future<List<TraceEvent>> fetchTrace(String projectId, String tagCode);

  /// Most recently used tags (for quick access).
  Future<List<String>> fetchRecentTags(String projectId, {int limit = 8});

  Future<void> addTraceEvent({
    required String projectId,
    required String tagCode,
    required TraceEventType type,
    String? itemId,
    String? componentId,
    double? quantity,
    String? notes,
  });

  Future<void> setStock(String itemId, {required double onHand, required double reserved});

  // ---- Quality (009) ----------------------------------------------------------
  Future<List<QualityInspection>> fetchInspections(String projectId);

  /// Realtime punch list.
  Stream<List<PunchItem>> watchPunchItems(String projectId);

  Future<void> setPunchStatus(String punchId, PunchStatus status);

  /// Creates a punch item (item number derived from the creation time, e.g. PI-261114-093012).
  Future<void> createPunchItem(PunchDraft draft);

  // ---- HSE (010) ----------------------------------------------------------------
  /// Realtime work permits.
  Stream<List<WorkPermit>> watchPermits(String projectId);

  Future<List<HseZone>> fetchZones(String projectId);

  Future<List<HseIncident>> fetchIncidents(String projectId);

  /// Throws [ShipyardException] when a hot work / confined space permit is
  /// activated without a valid gas test.
  Future<void> setPermitStatus(String permitId, PermitStatus status, {double? gasO2, double? gasLel});

  Future<void> reportIncident({
    required String projectId,
    required String? componentId,
    required IncidentSeverity severity,
    required String description,
  });

  // ---- Dashboard (011) ----------------------------------------------------------
  /// Newest reading per component and metric (RPC `latest_telemetry`).
  Future<List<LatestReading>> fetchLatestTelemetry(String projectId);
}
