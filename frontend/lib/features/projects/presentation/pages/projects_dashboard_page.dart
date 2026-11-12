import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/async_states.dart';
import '../../../digital_twin/presentation/pages/digital_twin_page.dart';
import '../../domain/entities/project.dart';
import '../providers/project_providers.dart';
import '../widgets/create_project_dialog.dart';
import '../widgets/project_card.dart';

class ProjectsDashboardPage extends ConsumerWidget {
  const ProjectsDashboardPage({super.key});

  void _toast(BuildContext context, String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? const Color(0xFF7F1D1D) : null,
        duration: Duration(seconds: error ? 8 : 4),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final input = await showDialog<CreateProjectInput>(
      context: context,
      builder: (_) => const CreateProjectDialog(),
    );
    if (input == null || !context.mounted) return;
    try {
      final project = await ref.read(projectRepositoryProvider).createProject(
            name: input.name,
            domainType: input.domainType,
            description: input.description,
          );
      ref.invalidate(projectsProvider);
      if (input.fileName != null && input.fileBytes != null) {
        final summary = await ref
            .read(ingestProvider(project.id).notifier)
            .uploadAndIngest(fileName: input.fileName, bytes: input.fileBytes);
        if (context.mounted) _reportIngest(context, ref, project.id, summary != null);
      } else if (context.mounted) {
        _toast(context, 'Project "${project.name}" created. Upload a CAD file to build its twin.');
      }
    } catch (e) {
      if (context.mounted) _toast(context, 'Could not create project: $e', error: true);
    }
  }

  Future<void> _upload(BuildContext context, WidgetRef ref, Project project) async {
    final picked = await pickCadFile();
    if (picked == null || !context.mounted) return;
    final ok = await ref
        .read(ingestProvider(project.id).notifier)
        .uploadAndIngest(fileName: picked.$1, bytes: picked.$2);
    if (context.mounted) _reportIngest(context, ref, project.id, ok != null);
  }

  Future<void> _reingest(BuildContext context, WidgetRef ref, Project project) async {
    final ok = await ref.read(ingestProvider(project.id).notifier).uploadAndIngest();
    if (context.mounted) _reportIngest(context, ref, project.id, ok != null);
  }

  void _reportIngest(BuildContext context, WidgetRef ref, String projectId, bool ok) {
    final state = ref.read(ingestProvider(projectId));
    _toast(context, ok ? 'Ingest complete: ${state.message}' : 'Ingest failed: ${state.message}', error: !ok);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Project project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete project?'),
        content: Text(
          '"${project.name}" and all of its components, documents, telemetry and stored models '
          'will be permanently deleted.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(projectRepositoryProvider).deleteProject(project.id);
      ref.invalidate(projectsProvider);
      if (context.mounted) _toast(context, 'Deleted "${project.name}".');
    } catch (e) {
      if (context.mounted) _toast(context, 'Delete failed: $e', error: true);
    }
  }

  void _open(BuildContext context, Project project) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DigitalTwinPage(projectId: project.id)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Row(
          children: [
            Icon(Icons.hub_outlined, color: AppTheme.accent),
            SizedBox(width: 10),
            Text('Open Digital Twin', style: TextStyle(fontWeight: FontWeight.w800)),
            SizedBox(width: 10),
            Text('Marine & AEC', style: TextStyle(color: AppTheme.textMuted, fontSize: 14)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(projectsProvider),
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New Project'),
      ),
      body: projects.when(
        loading: () => const LoadingView(label: 'Loading projects ...'),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(projectsProvider)),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyView(
              icon: Icons.view_in_ar,
              message: 'No projects yet.\nCreate one and upload a .step, .ifc, .ocx or .obj file.',
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(projectsProvider.future),
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 440,
                mainAxisExtent: 270,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final project = items[i];
                return ProjectCard(
                  project: project,
                  onOpen: () => _open(context, project),
                  onUpload: () => _upload(context, ref, project),
                  onReingest: () => _reingest(context, ref, project),
                  onDelete: () => _delete(context, ref, project),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
