import '../../../../core/status/component_status.dart';

/// A BOM entry (table `components`). [meshNodeId] equals the glTF node name.
class TwinComponent {
  const TwinComponent({
    required this.id,
    required this.projectId,
    required this.meshNodeId,
    required this.name,
    required this.status,
    required this.metadata,
    required this.updatedAt,
    this.category,
    this.material,
    this.weightKg,
    this.volumeM3,
  });

  final String id;
  final String projectId;
  final String meshNodeId;
  final String name;
  final String? category;
  final String? material;
  final double? weightKg;
  final double? volumeM3;
  final ComponentStatus status;
  final Map<String, dynamic> metadata;
  final DateTime updatedAt;
}

enum DocumentType {
  certificate('certificate', 'Certificate'),
  photo('photo', 'Photo'),
  manual('manual', 'Manual'),
  inspection('inspection', 'Inspection');

  const DocumentType(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static DocumentType fromDb(String? value) =>
      DocumentType.values.firstWhere((d) => d.dbValue == value, orElse: () => DocumentType.certificate);
}

/// A file attached to a component (table `documents`).
class TwinDocument {
  const TwinDocument({
    required this.id,
    required this.componentId,
    required this.title,
    required this.docType,
    required this.fileUrl,
    required this.uploadedAt,
  });

  final String id;
  final String componentId;
  final String title;
  final DocumentType docType;

  /// Resolved public URL (object paths are resolved by the repository).
  final String fileUrl;
  final DateTime uploadedAt;
}

/// One sensor reading (table `telemetry_logs`).
class TelemetryReading {
  const TelemetryReading({
    required this.id,
    required this.componentId,
    required this.metricName,
    required this.metricValue,
    required this.recordedAt,
    this.unit,
  });

  final int id;
  final String componentId;
  final String metricName;
  final double metricValue;
  final String? unit;
  final DateTime recordedAt;

  String get metricLabel {
    final words = metricName.split('_');
    return words.map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  }
}

/// Result of the Supabase RPC `simulate_telemetry` (same shape as the backend's
/// `POST /api/v1/telemetry/simulate/{project_id}`).
class SimulationResult {
  const SimulationResult({required this.readingsInserted, required this.statusChanges});

  final int readingsInserted;

  /// (mesh_node_id, from, to)
  final List<(String, String, String)> statusChanges;
}
