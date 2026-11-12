import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/project.dart';
import '../providers/project_providers.dart';

class ProjectCard extends ConsumerWidget {
  const ProjectCard({
    super.key,
    required this.project,
    required this.onOpen,
    required this.onUpload,
    required this.onReingest,
    required this.onDelete,
  });

  final Project project;
  final VoidCallback onOpen;
  final VoidCallback onUpload;
  final VoidCallback onReingest;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ingest = ref.watch(ingestProvider(project.id));
    final isMarine = project.domainType == DomainType.marine;
    final domainColor = isMarine ? AppTheme.marine : AppTheme.construction;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: project.hasModel && !ingest.isBusy ? onOpen : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: domainColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(isMarine ? Icons.directions_boat : Icons.villa, color: domainColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${project.domainType.label} · created ${_date(project.createdAt)}',
                          style: TextStyle(color: domainColor, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Project actions',
                    enabled: !ingest.isBusy,
                    onSelected: (v) {
                      if (v == 'reingest') onReingest();
                      if (v == 'delete') onDelete();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'reingest',
                        enabled: project.hasRawFile,
                        child: const ListTile(
                          dense: true,
                          leading: Icon(Icons.replay),
                          title: Text('Re-run ingest'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.delete_outline, color: Color(0xFFF87171)),
                          title: Text('Delete project'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Text(
                  project.description?.isNotEmpty == true ? project.description! : 'No description.',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.4),
                ),
              ),
              const SizedBox(height: 8),
              _ModelStatusLine(project: project, ingest: ingest),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: ingest.isBusy ? null : onUpload,
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: const Text('Upload CAD'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: project.hasModel && !ingest.isBusy ? onOpen : null,
                      icon: const Icon(Icons.view_in_ar, size: 18),
                      label: const Text('Open Twin'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _ModelStatusLine extends StatelessWidget {
  const _ModelStatusLine({required this.project, required this.ingest});

  final Project project;
  final IngestState ingest;

  @override
  Widget build(BuildContext context) {
    if (ingest.isBusy) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinearProgressIndicator(minHeight: 3),
          const SizedBox(height: 6),
          Text(ingest.message ?? '', style: const TextStyle(fontSize: 12, color: AppTheme.accent)),
        ],
      );
    }
    final (IconData icon, Color color, String text) = switch (ingest.phase) {
      IngestPhase.failed => (Icons.error_outline, const Color(0xFFF87171), 'Ingest failed: ${ingest.message}'),
      IngestPhase.done => (Icons.check_circle_outline, const Color(0xFF22C55E), ingest.message ?? 'Ingest complete'),
      _ when project.hasModel => (Icons.view_in_ar, const Color(0xFF22C55E), '3D model ready'),
      _ when project.hasRawFile =>
        (Icons.hourglass_bottom, const Color(0xFFF59E0B), '${project.rawFileName} uploaded – not ingested'),
      _ => (Icons.cloud_upload_outlined, AppTheme.textMuted, 'No CAD file yet'),
    };
    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: color)),
        ),
      ],
    );
  }
}
