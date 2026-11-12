import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/network/backend_api_client.dart';
import '../../../../core/utils/file_utils.dart';
import '../../domain/entities/project.dart';
import '../../domain/repositories/project_repository.dart';
import '../models/project_model.dart';

class ProjectRepositoryImpl implements ProjectRepository {
  ProjectRepositoryImpl({required this.supabase, required this.backend});

  final SupabaseClient supabase;
  final BackendApiClient backend;

  @override
  Future<List<Project>> fetchProjects() async {
    final rows = await supabase.from('projects').select().order('created_at', ascending: false);
    return rows.map(ProjectModel.fromJson).toList();
  }

  @override
  Future<Project> fetchProject(String id) async {
    final row = await supabase.from('projects').select().eq('id', id).single();
    return ProjectModel.fromJson(row);
  }

  @override
  Future<Project> createProject({required String name, required DomainType domainType, String? description}) async {
    final row = await supabase
        .from('projects')
        .insert(
          ProjectModel.toInsertJson(
            name: name,
            domainType: domainType,
            description: description,
            ownerId: supabase.auth.currentUser?.id,
          ),
        )
        .select()
        .single();
    return ProjectModel.fromJson(row);
  }

  @override
  Future<void> deleteProject(String id) async {
    final storage = supabase.storage;
    for (final bucket in [AppConfig.rawCadBucket, AppConfig.processedModelsBucket]) {
      final objects = await storage.from(bucket).list(path: id);
      if (objects.isNotEmpty) {
        await storage.from(bucket).remove(objects.map((o) => '$id/${o.name}').toList());
      }
    }
    await supabase.from('projects').delete().eq('id', id);
  }

  @override
  Future<String> uploadRawCadFile({
    required String projectId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final path = '$projectId/${FileUtils.safeName(fileName)}';
    await supabase.storage
        .from(AppConfig.rawCadBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: FileUtils.contentType(fileName), upsert: true),
        );
    await supabase.from('projects').update({'raw_file_url': path}).eq('id', projectId);
    return path;
  }

  @override
  Future<IngestSummary> triggerIngest(String projectId, {String? storagePath}) async {
    final json = await backend.postJson('/api/v1/ingest/$projectId', body: {'storage_path': ?storagePath});
    return IngestSummaryModel.fromJson(json);
  }
}
