import '../../domain/entities/production_entities.dart';
import 'json_utils.dart';

class HullModel {
  const HullModel._();

  static Hull fromJson(Map<String, dynamic> json) => Hull(
    id: json['id'] as String,
    projectId: json['project_id'] as String,
    hullNo: json['hull_no'] as String,
    name: json['name'] as String?,
    shipType: json['ship_type'] as String?,
    contractType: json['contract_type'] as String? ?? 'newbuild',
    ownerName: json['owner_name'] as String?,
    classSociety: json['class_society'] as String?,
    lengthM: readDouble(json['length_m']),
    beamM: readDouble(json['beam_m']),
    deadweightT: readDouble(json['deadweight_t']),
    contractDate: readDate(json['contract_date']),
    steelCuttingDate: readDate(json['steel_cutting_date']),
    keelLayingDate: readDate(json['keel_laying_date']),
    launchingDate: readDate(json['launching_date']),
    contractDeliveryDate: readDate(json['contract_delivery_date']),
    forecastDeliveryDate: readDate(json['forecast_delivery_date']),
    status: HullStatus.fromDb(json['status'] as String?),
    locationNodeId: json['location_node_id'] as String?,
    metadata: readMap(json['metadata']),
  );

  /// Row for `insert into hulls`. Build milestones are dropped for repairs.
  static Map<String, dynamic> insert(HullDraft d) {
    String? text(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
    final build = d.hasBuildMilestones;
    return {
      'project_id': d.projectId,
      'hull_no': d.normalizedHullNo,
      'name': text(d.name),
      'ship_type': text(d.shipType),
      'contract_type': d.contractType.dbValue,
      'owner_name': text(d.ownerName),
      'class_society': text(d.classSociety),
      'length_m': d.lengthM,
      'beam_m': d.beamM,
      'deadweight_t': d.deadweightT,
      'contract_date': writeDate(d.contractDate),
      'steel_cutting_date': build ? writeDate(d.steelCuttingDate) : null,
      'keel_laying_date': build ? writeDate(d.keelLayingDate) : null,
      'launching_date': build ? writeDate(d.launchingDate) : null,
      'contract_delivery_date': writeDate(d.contractDeliveryDate),
      'forecast_delivery_date': writeDate(d.effectiveForecastDelivery),
      'status': d.status.dbValue,
      'location_node_id': text(d.locationNodeId),
    };
  }

  /// Columns an editor may change on an existing hull (`metadata` is kept).
  static Map<String, dynamic> update(HullDraft d) => insert(d)..remove('project_id');
}

class ProductionActivityModel {
  const ProductionActivityModel._();

  static ProductionActivity fromJson(Map<String, dynamic> json) => ProductionActivity(
    id: json['id'] as String,
    projectId: json['project_id'] as String,
    hullId: json['hull_id'] as String?,
    componentId: json['component_id'] as String?,
    code: json['activity_code'] as String,
    name: json['name'] as String,
    stage: ProductionStage.fromDb(json['stage'] as String?),
    locationNodeId: json['location_node_id'] as String?,
    plannedStart: readDate(json['planned_start']) ?? DateTime.now(),
    plannedEnd: readDate(json['planned_end']) ?? DateTime.now(),
    actualStart: readDate(json['actual_start']),
    actualEnd: readDate(json['actual_end']),
    progressPct: readDouble(json['progress_pct']) ?? 0,
    sortOrder: readInt(json['sort_order']) ?? 0,
    departmentId: json['department_id'] as String?,
    notes: json['notes'] as String?,
    workPackage: WorkPackage.fromDb(json['work_package'] as String?),
    slotNo: readInt(json['slot_no']),
  );

  /// Row for `insert into production_activities`.
  static Map<String, dynamic> insert(ActivityDraft d) => {
    'project_id': d.projectId,
    'hull_id': d.hullId,
    'component_id': d.componentId,
    'activity_code': d.code.trim(),
    'sort_order': d.sortOrder,
    ...planUpdate(d),
  };

  /// Plan columns an editor may change (progress and actual dates stay untouched).
  static Map<String, dynamic> planUpdate(ActivityDraft d) => {
    'name': d.name.trim(),
    'stage': d.stage.dbValue,
    'location_node_id': d.locationNodeId,
    'planned_start': writeDate(d.plannedStart),
    'planned_end': writeDate(d.plannedEnd),
    'notes': d.notes == null || d.notes!.trim().isEmpty ? null : d.notes!.trim(),
    'work_package': d.workPackage?.dbValue,
    if (d.departmentId != null) 'department_id': d.departmentId,
  };

  /// Columns an editor may change from the app.
  static Map<String, dynamic> progressUpdate(ProductionActivity a) => {
    'progress_pct': a.progressPct,
    'actual_start': writeDate(a.actualStart),
    'actual_end': writeDate(a.actualEnd),
    'notes': a.notes,
  };
}
