import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/core_providers.dart';
import '../../data/repositories/project_repository_impl.dart';
import '../../domain/entities/project.dart';
import '../../domain/repositories/project_repository.dart';

final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  return ProjectRepositoryImpl(
    supabase: ref.watch(supabaseClientProvider),
    backend: ref.watch(backendApiClientProvider),
  );
});

final projectsProvider = FutureProvider<List<Project>>((ref) {
  return ref.watch(projectRepositoryProvider).fetchProjects();
});

final projectProvider = FutureProvider.family<Project, String>((ref, id) {
  return ref.watch(projectRepositoryProvider).fetchProject(id);
});

/// Upload + ingest progress for one project card.
enum IngestPhase { idle, uploading, ingesting, done, failed }

class IngestState {
  const IngestState({this.phase = IngestPhase.idle, this.message, this.summary});

  final IngestPhase phase;
  final String? message;
  final IngestSummary? summary;

  bool get isBusy => phase == IngestPhase.uploading || phase == IngestPhase.ingesting;
}

class IngestNotifier extends Notifier<IngestState> {
  IngestNotifier(this.projectId);

  final String projectId;

  @override
  IngestState build() => const IngestState();

  /// Uploads [bytes] to `raw-cad-files` (when given) then runs the backend ingest.
  Future<IngestSummary?> uploadAndIngest({String? fileName, Uint8List? bytes}) async {
    final repo = ref.read(projectRepositoryProvider);
    try {
      String? storagePath;
      if (fileName != null && bytes != null) {
        state = IngestState(phase: IngestPhase.uploading, message: 'Uploading $fileName ...');
        storagePath = await repo.uploadRawCadFile(projectId: projectId, fileName: fileName, bytes: bytes);
      }
      state = const IngestState(
        phase: IngestPhase.ingesting,
        message: 'Parsing BOM & optimizing mesh (Headless Blender) ...',
      );
      final summary = await repo.triggerIngest(
        projectId,
        storagePath: storagePath,
        onProgress: (message) {
          if (ref.mounted) state = IngestState(phase: IngestPhase.ingesting, message: message);
        },
      );
      state = IngestState(
        phase: IngestPhase.done,
        summary: summary,
        message:
            '${summary.componentsUpserted} components ingested via ${summary.optimizer} '
            'in ${summary.elapsedSeconds.toStringAsFixed(1)} s',
      );
      ref.invalidate(projectsProvider);
      ref.invalidate(projectProvider(projectId));
      return summary;
    } catch (e) {
      state = IngestState(phase: IngestPhase.failed, message: '$e');
      ref.invalidate(projectsProvider);
      return null;
    }
  }

  void reset() => state = const IngestState();
}

final ingestProvider = NotifierProvider.family<IngestNotifier, IngestState, String>(IngestNotifier.new);
