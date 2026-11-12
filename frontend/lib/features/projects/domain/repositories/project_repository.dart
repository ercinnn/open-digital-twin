import 'dart:typed_data';

import '../entities/project.dart';

/// Summary returned by the backend ingest endpoint.
class IngestSummary {
  const IngestSummary({
    required this.componentsUpserted,
    required this.optimizer,
    required this.glbModelUrl,
    required this.meshNodeIds,
    required this.warnings,
    required this.elapsedSeconds,
    required this.staleComponents,
  });

  final int componentsUpserted;
  final String optimizer;
  final String glbModelUrl;
  final List<String> meshNodeIds;
  final List<String> warnings;
  final double elapsedSeconds;
  final List<String> staleComponents;
}

abstract interface class ProjectRepository {
  Future<List<Project>> fetchProjects();

  Future<Project> fetchProject(String id);

  Future<Project> createProject({required String name, required DomainType domainType, String? description});

  Future<void> deleteProject(String id);

  /// Uploads a CAD file to `raw-cad-files` and stores its path in `projects.raw_file_url`.
  Future<String> uploadRawCadFile({required String projectId, required String fileName, required Uint8List bytes});

  /// Calls `POST /api/v1/ingest/{project_id}`.
  Future<IngestSummary> triggerIngest(String projectId, {String? storagePath});
}
