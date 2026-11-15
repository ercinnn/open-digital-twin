import '../../domain/entities/hse_entities.dart';
import 'json_utils.dart';
import 'quality_models.dart' show readMarker;

class WorkPermitModel {
  const WorkPermitModel._();

  static WorkPermit fromJson(Map<String, dynamic> json) => WorkPermit(
    id: json['id'] as String,
    componentId: json['component_id'] as String,
    hullId: json['hull_id'] as String?,
    permitNo: json['permit_no'] as String,
    type: PermitType.fromDb(json['permit_type'] as String?),
    description: json['description'] as String,
    status: PermitStatus.fromDb(json['status'] as String?),
    validFrom: readTimestamp(json['valid_from']) ?? DateTime.now(),
    validTo: readTimestamp(json['valid_to']) ?? DateTime.now(),
    issuedTo: json['issued_to'] as String?,
    gasO2: readDouble(json['gas_test_o2_pct']),
    gasLel: readDouble(json['gas_test_lel_pct']),
    gasTestedAt: readTimestamp(json['gas_tested_at']),
    precautions: json['precautions'] as String?,
    position: readMarker(json),
  );
}

class HseZoneModel {
  const HseZoneModel._();

  static HseZone fromJson(Map<String, dynamic> json) => HseZone(
    id: json['id'] as String,
    componentId: json['component_id'] as String,
    type: ZoneType.fromDb(json['zone_type'] as String?),
    name: json['name'] as String,
    description: json['description'] as String?,
    active: json['active'] != false,
  );
}

class HseIncidentModel {
  const HseIncidentModel._();

  static HseIncident fromJson(Map<String, dynamic> json) => HseIncident(
    id: json['id'] as String,
    componentId: json['component_id'] as String?,
    incidentNo: json['incident_no'] as String,
    severity: IncidentSeverity.fromDb(json['severity'] as String?),
    occurredAt: readTimestamp(json['occurred_at']) ?? DateTime.now(),
    description: json['description'] as String,
    status: json['status'] as String? ?? 'open',
    correctiveAction: json['corrective_action'] as String?,
    position: readMarker(json),
  );
}
