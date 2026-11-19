import '../entities/block_entities.dart';
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

  /// Inserts the blocks of a hull as `components` rows in one request (all or
  /// nothing). Throws [ShipyardException] e.g. when a block code is taken.
  Future<void> createBlocks(List<BlockDraft> drafts);

  /// Changes name and weight (`weight_kg`, `null` clears it) of a block (editors).
  Future<void> updateBlock(String componentId, {required String name, required double? weightKg});

  /// Deletes a block; its schedule rows are deleted with it, bookings,
  /// inspections, punch items and permits keep their row without the block.
  Future<void> deleteBlock(String componentId);

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

  /// Inserts all bookings or none (one statement).
  Future<void> createBookings(List<BookingDraft> drafts);

  Future<void> setBookingStatus(String bookingId, BookingStatus status);

  /// Moves a booking to another resource / window and sets its load and notes.
  /// Throws [ShipyardException] on double booking or when the load exceeds the
  /// resource capacity (database checks).
  Future<void> updateBookingPlan(
    String bookingId, {
    required String componentId,
    required DateTime startsAt,
    required DateTime endsAt,
    required double? loadT,
    required String? notes,
  });

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

  /// Creates a stock item (editors). Throws [ShipyardException] e.g. for a duplicate item code.
  Future<void> createMaterialItem(MaterialDraft draft);

  /// Updates all fields of a stock item (editors).
  Future<void> updateMaterialItem(String itemId, MaterialDraft draft);

  // ---- Block material reservations (012) ---------------------------------------
  Future<List<MaterialReservation>> fetchReservations(String projectId);

  /// Reserves stock for blocks in one request (the database keeps the item totals).
  Future<void> createReservations(List<ReservationDraft> drafts);

  /// Changes quantity / needed-by date of an open reservation.
  Future<void> updateReservation(String reservationId, {required double quantity, DateTime? neededBy});

  /// Hands the material out to the block: stock on hand goes down and a trace
  /// event `issued` is recorded (database). Fails when not enough is on hand.
  Future<void> issueReservation(String reservationId);

  Future<void> deleteReservation(String reservationId);

  // ---- Quality (009) ----------------------------------------------------------
  Future<List<QualityInspection>> fetchInspections(String projectId);

  /// Plans inspections (result `pending`) in one request.
  Future<void> createInspections(List<InspectionDraft> drafts);

  /// Records a result. With a measured value inside / outside the acceptance band and
  /// [result] `pending`, the database sets pass / fail. Returns the stored row.
  Future<QualityInspection> recordInspectionResult(
    String inspectionId, {
    required InspectionResult result,
    required DateTime inspectedAt,
    double? measuredValue,
    String? notes,
  });

  Future<void> deleteInspection(String inspectionId);

  /// Realtime punch list.
  Stream<List<PunchItem>> watchPunchItems(String projectId);

  Future<void> setPunchStatus(String punchId, PunchStatus status);

  /// Creates a punch item (item number derived from the creation time, e.g. PI-261114-093012).
  Future<void> createPunchItem(PunchDraft draft);

  // ---- HSE (010) ----------------------------------------------------------------
  /// Realtime work permits.
  Stream<List<WorkPermit>> watchPermits(String projectId);

  Future<List<HseZone>> fetchZones(String projectId);

  /// Requests a permit-to-work (status `requested`). Throws [ShipyardException]
  /// when the permit number is taken.
  Future<void> createPermit(PermitDraft draft);

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
