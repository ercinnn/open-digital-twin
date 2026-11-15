import 'package:flutter/material.dart';

import 'quality_entities.dart' show MarkerPosition;

enum PermitType {
  hotWork('hot_work', 'Hot work', 'H', Color(0xFFF97316), Icons.local_fire_department_outlined),
  confinedSpace('confined_space', 'Confined space', 'C', Color(0xFF38BDF8), Icons.sensor_door_outlined),
  workAtHeight('work_at_height', 'Work at height', 'W', Color(0xFFFACC15), Icons.height),
  lifting('lifting', 'Lifting', 'L', Color(0xFFEAB308), Icons.precision_manufacturing_outlined),
  electricalIsolation('electrical_isolation', 'Electrical isolation', 'E', Color(0xFFA3E635), Icons.power_off_outlined),
  painting('painting', 'Painting', 'P', Color(0xFF60A5FA), Icons.format_paint_outlined);

  const PermitType(this.dbValue, this.label, this.letter, this.color, this.icon);

  final String dbValue;
  final String label;
  final String letter;
  final Color color;
  final IconData icon;

  /// Hot work and confined space need a valid gas test before activation.
  bool get needsGasTest => this == PermitType.hotWork || this == PermitType.confinedSpace;

  static PermitType fromDb(String? v) => PermitType.values.firstWhere((t) => t.dbValue == v, orElse: () => PermitType.hotWork);
}

enum PermitStatus {
  requested('requested', 'Requested'),
  approved('approved', 'Approved'),
  active('active', 'Active'),
  suspended('suspended', 'Suspended'),
  closed('closed', 'Closed');

  const PermitStatus(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static PermitStatus fromDb(String? v) => PermitStatus.values.firstWhere((s) => s.dbValue == v, orElse: () => PermitStatus.requested);
}

/// Table `work_permits`.
class WorkPermit {
  const WorkPermit({
    required this.id,
    required this.componentId,
    required this.permitNo,
    required this.type,
    required this.description,
    required this.status,
    required this.validFrom,
    required this.validTo,
    required this.position,
    this.hullId,
    this.issuedTo,
    this.gasO2,
    this.gasLel,
    this.gasTestedAt,
    this.precautions,
  });

  final String id;
  final String componentId;
  final String? hullId;
  final String permitNo;
  final PermitType type;
  final String description;
  final PermitStatus status;
  final DateTime validFrom;
  final DateTime validTo;
  final String? issuedTo;
  final double? gasO2;
  final double? gasLel;
  final DateTime? gasTestedAt;
  final String? precautions;
  final MarkerPosition position;

  /// Active and inside its validity window.
  bool isLive(DateTime now) => status == PermitStatus.active && !now.isBefore(validFrom) && now.isBefore(validTo);

  bool isExpired(DateTime now) => status == PermitStatus.active && !now.isBefore(validTo);

  Duration remaining(DateTime now) => validTo.difference(now);
}

enum ZoneType {
  restricted('restricted', 'Restricted', '#ef4444'),
  hazardousAtmosphere('hazardous_atmosphere', 'Hazardous atmosphere', '#f97316'),
  overheadLifting('overhead_lifting', 'Overhead lifting', '#facc15'),
  noise('noise', 'Noise', '#a78bfa'),
  ppeMandatory('ppe_mandatory', 'PPE mandatory', '#38bdf8'),
  confinedSpace('confined_space', 'Confined space', '#22d3ee');

  const ZoneType(this.dbValue, this.label, this.hex);

  final String dbValue;
  final String label;
  final String hex;

  Color get color => Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));

  static ZoneType fromDb(String? v) => ZoneType.values.firstWhere((t) => t.dbValue == v, orElse: () => ZoneType.restricted);
}

/// Table `hse_zones`.
class HseZone {
  const HseZone({required this.id, required this.componentId, required this.type, required this.name, required this.active, this.description});

  final String id;
  final String componentId;
  final ZoneType type;
  final String name;
  final String? description;
  final bool active;
}

enum IncidentSeverity {
  nearMiss('near_miss', 'Near miss', Color(0xFFFACC15)),
  firstAid('first_aid', 'First aid', Color(0xFFFB923C)),
  medicalTreatment('medical_treatment', 'Medical treatment', Color(0xFFF97316)),
  lostTime('lost_time', 'Lost time injury', Color(0xFFEF4444)),
  propertyDamage('property_damage', 'Property damage', Color(0xFF94A3B8)),
  environmental('environmental', 'Environmental', Color(0xFF22C55E));

  const IncidentSeverity(this.dbValue, this.label, this.color);

  final String dbValue;
  final String label;
  final Color color;

  static IncidentSeverity fromDb(String? v) =>
      IncidentSeverity.values.firstWhere((s) => s.dbValue == v, orElse: () => IncidentSeverity.nearMiss);
}

/// Table `hse_incidents`.
class HseIncident {
  const HseIncident({
    required this.id,
    required this.incidentNo,
    required this.severity,
    required this.occurredAt,
    required this.description,
    required this.status,
    required this.position,
    this.componentId,
    this.correctiveAction,
  });

  final String id;
  final String? componentId;
  final String incidentNo;
  final IncidentSeverity severity;
  final DateTime occurredAt;
  final String description;
  final String status;
  final String? correctiveAction;
  final MarkerPosition position;

  bool get isOpen => status != 'closed';
}

/// HSE key figures.
class HseSummary {
  const HseSummary({required this.daysSinceLostTime, required this.nearMisses30d, required this.openIncidents, required this.livePermits});

  /// null = no lost-time injury on record.
  final int? daysSinceLostTime;
  final int nearMisses30d;
  final int openIncidents;
  final int livePermits;

  static HseSummary of(List<HseIncident> incidents, List<WorkPermit> permits, DateTime now) {
    final lti = incidents.where((i) => i.severity == IncidentSeverity.lostTime).map((i) => i.occurredAt).fold<DateTime?>(
      null,
      (latest, d) => latest == null || d.isAfter(latest) ? d : latest,
    );
    return HseSummary(
      daysSinceLostTime: lti == null ? null : now.difference(lti).inDays,
      nearMisses30d: incidents
          .where((i) => i.severity == IncidentSeverity.nearMiss && now.difference(i.occurredAt).inDays <= 30)
          .length,
      openIncidents: incidents.where((i) => i.isOpen).length,
      livePermits: permits.where((p) => p.isLive(now)).length,
    );
  }
}
