import '../../domain/entities/project.dart';
import '../../domain/repositories/project_repository.dart';

class ProjectModel {
  const ProjectModel._();

  static Project fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String,
      name: json['name'] as String,
      domainType: DomainType.fromDb(json['domain_type'] as String?),
      description: json['description'] as String?,
      rawFileUrl: json['raw_file_url'] as String?,
      glbModelUrl: json['glb_model_url'] as String?,
      ownerId: json['owner_id'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
    );
  }

  static Map<String, dynamic> toInsertJson({
    required String name,
    required DomainType domainType,
    String? description,
    String? ownerId,
  }) {
    return {
      'name': name,
      'domain_type': domainType.dbValue,
      if (description != null && description.isNotEmpty) 'description': description,
      'owner_id': ?ownerId,
    };
  }
}

class IngestSummaryModel {
  const IngestSummaryModel._();

  static IngestSummary fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) => (json[key] as List<dynamic>? ?? const []).map((e) => '$e').toList();
    return IngestSummary(
      componentsUpserted: (json['components_upserted'] as num?)?.toInt() ?? 0,
      optimizer: json['optimizer'] as String? ?? 'unknown',
      glbModelUrl: json['glb_model_url'] as String? ?? '',
      meshNodeIds: strings('mesh_node_ids'),
      warnings: strings('warnings'),
      elapsedSeconds: (json['elapsed_s'] as num?)?.toDouble() ?? 0,
      staleComponents: strings('stale_components'),
    );
  }
}
