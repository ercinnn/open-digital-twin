import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/block_entities.dart';
import '../../domain/entities/hse_entities.dart';
import '../../domain/entities/material_entities.dart';
import '../../domain/entities/organization_entities.dart';
import '../../domain/entities/production_entities.dart';
import '../../domain/entities/quality_entities.dart';
import '../../domain/entities/resource_entities.dart';
import '../../domain/repositories/shipyard_repository.dart';
import '../../domain/services/yard_kpis.dart' show LatestReading;
import '../models/block_models.dart';
import '../models/json_utils.dart';
import '../models/hse_models.dart';
import '../models/material_models.dart';
import '../models/organization_models.dart';
import '../models/production_models.dart';
import '../models/quality_models.dart';
import '../models/resource_models.dart';

class ShipyardRepositoryImpl implements ShipyardRepository {
  ShipyardRepositoryImpl({required this.supabase});

  final SupabaseClient supabase;

  /// Translates constraint / trigger errors into readable messages.
  static Never _rethrow(Object error) {
    if (error is PostgrestException) {
      switch (error.code) {
        case '23P01':
          throw const ShipyardException(
            'Conflict: the resource (and slot) is already booked in this time window. '
            'Choose another time, slot or resource.',
          );
        case '23514':
        case 'P0001':
          throw ShipyardException(error.message);
        case '42501':
          throw const ShipyardException('Not allowed: sign in with an editor account.');
      }
      throw ShipyardException(error.message);
    }
    throw ShipyardException('$error');
  }

  // ---- Production ---------------------------------------------------------------
  @override
  Future<List<Hull>> fetchHulls(String projectId) async {
    final rows = await supabase.from('hulls').select().eq('project_id', projectId).order('hull_no', ascending: true);
    return rows.map(HullModel.fromJson).toList();
  }

  @override
  Future<Hull> createHull(HullDraft draft) =>
      _saveHull(draft, () => supabase.from('hulls').insert(HullModel.insert(draft)).select().single());

  @override
  Future<Hull> updateHull(String hullId, HullDraft draft) =>
      _saveHull(draft, () => supabase.from('hulls').update(HullModel.update(draft)).eq('id', hullId).select().single());

  Future<Hull> _saveHull(HullDraft draft, Future<Map<String, dynamic>> Function() write) async {
    try {
      return HullModel.fromJson(await write());
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw ShipyardException('Hull number ${draft.normalizedHullNo} already exists in this yard.');
      }
      // No row returned: RLS hid the update (not an editor) or the hull was deleted meanwhile.
      if (e.code == 'PGRST116') throw const ShipyardException('Not saved: sign in with an editor account and reload.');
      _rethrow(e);
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Stream<List<ProductionActivity>> watchActivities(String projectId) {
    return supabase
        .from('production_activities')
        .stream(primaryKey: ['id'])
        .eq('project_id', projectId)
        .order('sort_order', ascending: true)
        .map((rows) => rows.map(ProductionActivityModel.fromJson).toList());
  }

  @override
  Future<void> updateActivityProgress(ProductionActivity activity) async {
    await supabase
        .from('production_activities')
        .update(ProductionActivityModel.progressUpdate(activity))
        .eq('id', activity.id);
  }

  @override
  Future<void> createBlocks(List<BlockDraft> drafts) async {
    if (drafts.isEmpty) return;
    try {
      await supabase.from('components').insert([for (final d in drafts) BlockModel.insert(d)]);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const ShipyardException(
          'A block code (mesh id) already exists in this yard. Reload the block list and change the code.',
        );
      }
      _rethrow(e);
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<void> deleteBlock(String componentId) async {
    try {
      final rows = await supabase.from('components').delete().eq('id', componentId).select('id');
      // RLS hides the row from non-editors: nothing deleted, no error.
      if (rows.isEmpty) throw const ShipyardException('Not deleted: sign in with an editor account and reload.');
    } on ShipyardException {
      rethrow;
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<void> createActivities(List<ActivityDraft> drafts) async {
    if (drafts.isEmpty) return;
    try {
      await supabase.from('production_activities').insert([for (final d in drafts) ProductionActivityModel.insert(d)]);
    } on PostgrestException catch (e) {
      if (e.code == '23505') throw const ShipyardException('An activity with this code already exists. Reload and try again.');
      _rethrow(e);
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<void> updateActivityPlan(String activityId, ActivityDraft draft) async {
    try {
      await supabase.from('production_activities').update(ProductionActivityModel.planUpdate(draft)).eq('id', activityId);
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<void> deleteActivity(String activityId) async {
    try {
      await supabase.from('production_activities').delete().eq('id', activityId);
    } catch (e) {
      _rethrow(e);
    }
  }

  // ---- Organization -------------------------------------------------------------
  @override
  Future<Organization> fetchOrganization(String projectId) async {
    final results = await Future.wait([
      supabase.from('departments').select().eq('project_id', projectId).order('sort_order', ascending: true),
      supabase.from('shifts').select().eq('project_id', projectId).order('code', ascending: true),
      supabase.from('area_assignments').select().eq('project_id', projectId),
    ]);
    return Organization(
      departments: results[0].map(DepartmentModel.fromJson).toList(),
      shifts: results[1].map(ShiftModel.fromJson).toList(),
      assignments: results[2].map(AreaAssignmentModel.fromJson).toList(),
    );
  }

  // ---- Resources ----------------------------------------------------------------
  @override
  Stream<List<ResourceBooking>> watchBookings(String projectId) {
    return supabase
        .from('resource_bookings')
        .stream(primaryKey: ['id'])
        .eq('project_id', projectId)
        .order('starts_at', ascending: true)
        .map((rows) => rows.map(ResourceBookingModel.fromJson).toList());
  }

  @override
  Future<void> createBooking(BookingDraft draft) async {
    try {
      await supabase.from('resource_bookings').insert(ResourceBookingModel.insert(draft));
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<void> setBookingStatus(String bookingId, BookingStatus status) async {
    try {
      await supabase
          .from('resource_bookings')
          .update({'status': status.dbValue, if (status != BookingStatus.suspended) 'suspended_reason': null})
          .eq('id', bookingId);
    } catch (e) {
      _rethrow(e);
    }
  }

  // ---- Materials ----------------------------------------------------------------
  @override
  Future<List<MaterialItem>> fetchMaterials(String projectId) async {
    final rows = await supabase.from('material_items').select().eq('project_id', projectId).order('item_code', ascending: true);
    return rows.map(MaterialItemModel.fromJson).toList();
  }

  @override
  Future<List<TraceEvent>> fetchTrace(String projectId, String tagCode) async {
    final rows = await supabase
        .from('material_trace_events')
        .select()
        .eq('project_id', projectId)
        .eq('tag_code', normalizeTag(tagCode)) // tags are stored normalized
        .order('recorded_at', ascending: true);
    return rows.map(TraceEventModel.fromJson).toList();
  }

  @override
  Future<List<String>> fetchRecentTags(String projectId, {int limit = 8}) async {
    final rows = await supabase
        .from('material_trace_events')
        .select('tag_code, recorded_at')
        .eq('project_id', projectId)
        .order('recorded_at', ascending: false)
        .limit(200);
    final tags = <String>[];
    for (final r in rows) {
      final tag = normalizeTag(r['tag_code'] as String);
      if (!tags.contains(tag)) tags.add(tag);
      if (tags.length >= limit) break;
    }
    return tags;
  }

  @override
  Future<void> addTraceEvent({
    required String projectId,
    required String tagCode,
    required TraceEventType type,
    String? itemId,
    String? componentId,
    double? quantity,
    String? notes,
  }) async {
    try {
      await supabase.from('material_trace_events').insert({
        'project_id': projectId,
        'tag_code': normalizeTag(tagCode),
        'event_type': type.dbValue,
        'item_id': itemId,
        'component_id': componentId,
        'quantity': quantity,
        'notes': notes,
      });
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<void> setStock(String itemId, {required double onHand, required double reserved}) async {
    try {
      await supabase
          .from('material_items')
          .update({'quantity_on_hand': onHand, 'quantity_reserved': reserved})
          .eq('id', itemId);
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<void> createMaterialItem(MaterialDraft draft) =>
      _saveMaterial(draft, () => supabase.from('material_items').insert(MaterialItemModel.insert(draft)));

  @override
  Future<void> updateMaterialItem(String itemId, MaterialDraft draft) =>
      _saveMaterial(draft, () => supabase.from('material_items').update(MaterialItemModel.update(draft)).eq('id', itemId));

  Future<void> _saveMaterial(MaterialDraft draft, Future<void> Function() write) async {
    try {
      await write();
    } on PostgrestException catch (e) {
      if (e.code == '23505') throw ShipyardException('Item code ${draft.normalizedCode} already exists.');
      _rethrow(e);
    } catch (e) {
      _rethrow(e);
    }
  }

  // ---- Quality ------------------------------------------------------------------
  @override
  Future<List<QualityInspection>> fetchInspections(String projectId) async {
    final rows = await supabase
        .from('quality_inspections')
        .select()
        .eq('project_id', projectId)
        .order('inspected_at', ascending: false);
    return rows.map(QualityInspectionModel.fromJson).toList();
  }

  @override
  Future<void> createInspections(List<InspectionDraft> drafts) async {
    if (drafts.isEmpty) return;
    try {
      await supabase.from('quality_inspections').insert([for (final d in drafts) QualityInspectionModel.insert(d)]);
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<QualityInspection> recordInspectionResult(
    String inspectionId, {
    required InspectionResult result,
    required DateTime inspectedAt,
    double? measuredValue,
    String? notes,
  }) async {
    try {
      final row = await supabase
          .from('quality_inspections')
          .update(
            QualityInspectionModel.resultUpdate(
              result: result,
              inspectedAt: inspectedAt,
              measuredValue: measuredValue,
              notes: notes,
            ),
          )
          .eq('id', inspectionId)
          .select()
          .single();
      return QualityInspectionModel.fromJson(row);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST116') throw const ShipyardException('Not saved: sign in with an editor account and reload.');
      _rethrow(e);
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<void> deleteInspection(String inspectionId) async {
    try {
      await supabase.from('quality_inspections').delete().eq('id', inspectionId);
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Stream<List<PunchItem>> watchPunchItems(String projectId) {
    return supabase
        .from('punch_items')
        .stream(primaryKey: ['id'])
        .eq('project_id', projectId)
        .order('raised_at', ascending: false)
        .map((rows) => rows.map(PunchItemModel.fromJson).toList());
  }

  @override
  Future<void> setPunchStatus(String punchId, PunchStatus status) async {
    try {
      await supabase.from('punch_items').update({'status': status.dbValue}).eq('id', punchId);
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<void> createPunchItem(PunchDraft draft) async {
    try {
      // Timestamp-based number: unique per project without a read-before-write race.
      final t = DateTime.now().toUtc();
      String two(int v) => v.toString().padLeft(2, '0');
      final itemNo = 'PI-${t.year % 100}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}';
      await supabase.from('punch_items').insert(PunchItemModel.insert(draft, itemNo));
    } catch (e) {
      _rethrow(e);
    }
  }

  // ---- HSE ----------------------------------------------------------------------
  @override
  Stream<List<WorkPermit>> watchPermits(String projectId) {
    return supabase
        .from('work_permits')
        .stream(primaryKey: ['id'])
        .eq('project_id', projectId)
        .order('valid_from', ascending: false)
        .map((rows) => rows.map(WorkPermitModel.fromJson).toList());
  }

  @override
  Future<List<HseZone>> fetchZones(String projectId) async {
    final rows = await supabase.from('hse_zones').select().eq('project_id', projectId).order('name', ascending: true);
    return rows.map(HseZoneModel.fromJson).toList();
  }

  @override
  Future<List<HseIncident>> fetchIncidents(String projectId) async {
    final rows = await supabase
        .from('hse_incidents')
        .select()
        .eq('project_id', projectId)
        .order('occurred_at', ascending: false);
    return rows.map(HseIncidentModel.fromJson).toList();
  }

  @override
  Future<void> createPermit(PermitDraft draft) async {
    try {
      await supabase.from('work_permits').insert(WorkPermitModel.insert(draft));
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw ShipyardException('Permit number ${draft.permitNo} was just taken - close and open the form again.');
      }
      _rethrow(e);
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<void> setPermitStatus(String permitId, PermitStatus status, {double? gasO2, double? gasLel}) async {
    try {
      await supabase
          .from('work_permits')
          .update({
            'status': status.dbValue,
            'gas_test_o2_pct': ?gasO2,
            'gas_test_lel_pct': ?gasLel,
            if (gasO2 != null || gasLel != null) 'gas_tested_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', permitId);
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<void> reportIncident({
    required String projectId,
    required String? componentId,
    required IncidentSeverity severity,
    required String description,
  }) async {
    final t = DateTime.now().toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    try {
      await supabase.from('hse_incidents').insert({
        'project_id': projectId,
        'component_id': componentId,
        'incident_no': 'INC-${t.year % 100}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}',
        'severity': severity.dbValue,
        'occurred_at': t.toIso8601String(),
        'description': description,
        'marker_u': 0.5,
        'marker_v': 0.5,
        'marker_w': 1,
      });
    } catch (e) {
      _rethrow(e);
    }
  }

  // ---- Dashboard ----------------------------------------------------------------
  @override
  Future<List<LatestReading>> fetchLatestTelemetry(String projectId) async {
    final rows = await supabase.rpc('latest_telemetry', params: {'p_project_id': projectId}) as List<dynamic>;
    return rows
        .whereType<Map<String, dynamic>>()
        .map(
          (r) => LatestReading(
            componentId: r['component_id'] as String,
            metricName: r['metric_name'] as String,
            value: readDouble(r['metric_value']) ?? 0,
            unit: r['unit'] as String?,
            recordedAt: readTimestamp(r['recorded_at']) ?? DateTime.now(),
          ),
        )
        .toList();
  }
}
