import '../../../../core/status/component_status.dart';
import '../../domain/entities/twin_entities.dart';

double? _toDouble(Object? v) => switch (v) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };

DateTime _toDate(Object? v) => DateTime.tryParse('${v ?? ''}')?.toLocal() ?? DateTime.now();

class TwinComponentModel {
  const TwinComponentModel._();

  static TwinComponent fromJson(Map<String, dynamic> json) {
    final meta = json['metadata'];
    return TwinComponent(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      meshNodeId: json['mesh_node_id'] as String,
      name: json['name'] as String,
      category: json['category'] as String?,
      material: json['material'] as String?,
      weightKg: _toDouble(json['weight_kg']),
      volumeM3: _toDouble(json['volume_m3']),
      status: ComponentStatus.fromDb(json['status'] as String?),
      metadata: meta is Map ? Map<String, dynamic>.from(meta) : <String, dynamic>{},
      updatedAt: _toDate(json['updated_at']),
    );
  }
}

class TwinDocumentModel {
  const TwinDocumentModel._();

  static TwinDocument fromJson(Map<String, dynamic> json, String Function(String) resolveUrl) {
    return TwinDocument(
      id: json['id'] as String,
      componentId: json['component_id'] as String,
      title: json['title'] as String,
      docType: DocumentType.fromDb(json['doc_type'] as String?),
      fileUrl: resolveUrl(json['file_url'] as String),
      uploadedAt: _toDate(json['uploaded_at']),
    );
  }
}

class TelemetryReadingModel {
  const TelemetryReadingModel._();

  static TelemetryReading fromJson(Map<String, dynamic> json) {
    return TelemetryReading(
      id: (json['id'] as num).toInt(),
      componentId: json['component_id'] as String,
      metricName: json['metric_name'] as String,
      metricValue: _toDouble(json['metric_value']) ?? 0,
      unit: json['unit'] as String?,
      recordedAt: _toDate(json['recorded_at']),
    );
  }
}

class SimulationResultModel {
  const SimulationResultModel._();

  static SimulationResult fromJson(Map<String, dynamic> json) {
    final changes = (json['status_changes'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((c) => ('${c['mesh_node_id']}', '${c['from_status']}', '${c['to_status']}'))
        .toList();
    return SimulationResult(
      readingsInserted: (json['readings_inserted'] as num?)?.toInt() ?? 0,
      statusChanges: changes,
    );
  }
}
