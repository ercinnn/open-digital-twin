import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/file_utils.dart';
import '../../../../shared/widgets/async_states.dart';
import '../../domain/entities/twin_entities.dart';
import '../providers/twin_providers.dart';

/// Certificates / photos / manuals / inspections stored in `component-docs`.
class DocumentsSection extends ConsumerStatefulWidget {
  const DocumentsSection({super.key, required this.projectId, required this.component});

  final String projectId;
  final TwinComponent component;

  @override
  ConsumerState<DocumentsSection> createState() => _DocumentsSectionState();
}

class _DocumentsSectionState extends ConsumerState<DocumentsSection> {
  bool _uploading = false;

  IconData _icon(DocumentType t) => switch (t) {
        DocumentType.certificate => Icons.verified_outlined,
        DocumentType.photo => Icons.photo_outlined,
        DocumentType.manual => Icons.menu_book_outlined,
        DocumentType.inspection => Icons.fact_check_outlined,
      };

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: error ? const Color(0xFF7F1D1D) : null),
    );
  }

  Future<void> _upload() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Attach a certificate, photo, manual or inspection report',
      type: FileType.custom,
      allowedExtensions: FileUtils.documentExtensions,
    );
    if (files.isEmpty || !mounted) return;
    final file = files.first;
    final ext = FileUtils.extensionOf(file.name);
    final isImage = const ['png', 'jpg', 'jpeg', 'webp'].contains(ext);
    final meta = await showDialog<(String, DocumentType)>(
      context: context,
      builder: (_) => _DocumentMetaDialog(
        initialTitle: file.name.replaceAll(RegExp(r'\.[^.]+$'), '').replaceAll('_', ' '),
        initialType: isImage ? DocumentType.photo : DocumentType.certificate,
      ),
    );
    if (meta == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      await ref.read(twinRepositoryProvider).uploadDocument(
            projectId: widget.projectId,
            component: widget.component,
            title: meta.$1,
            docType: meta.$2,
            fileName: file.name,
            bytes: bytes,
          );
      ref.invalidate(documentsProvider(widget.component.id));
      if (mounted) _toast('Uploaded "${meta.$1}" (${FileUtils.formatBytes(bytes.length)})');
    } catch (e) {
      if (mounted) _toast('Upload failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _delete(TwinDocument doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text('"${doc.title}" will be removed from storage.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(twinRepositoryProvider).deleteDocument(doc);
      ref.invalidate(documentsProvider(widget.component.id));
    } catch (e) {
      if (mounted) _toast('Delete failed: $e', error: true);
    }
  }

  Future<void> _open(TwinDocument doc) async {
    final ok = await launchUrl(Uri.parse(doc.fileUrl), mode: LaunchMode.externalApplication);
    if (!ok && mounted) _toast('Could not open ${doc.fileUrl}', error: true);
  }

  @override
  Widget build(BuildContext context) {
    final docs = ref.watch(documentsProvider(widget.component.id));
    return SectionCard(
      title: 'Documents',
      icon: Icons.folder_open_outlined,
      trailing: _uploading
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : IconButton(
              tooltip: 'Upload certificate / photo',
              visualDensity: VisualDensity.compact,
              onPressed: _upload,
              icon: const Icon(Icons.add_circle_outline, size: 20),
            ),
      child: docs.when(
        loading: () => const SizedBox(height: 60, child: LoadingView()),
        error: (e, _) => Text('$e', style: const TextStyle(color: Color(0xFFF87171))),
        data: (items) {
          if (items.isEmpty) {
            return const Text('No documents attached.', style: TextStyle(color: AppTheme.textMuted));
          }
          return Column(
            children: [
              for (final d in items)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_icon(d.docType), color: AppTheme.accent),
                  title: Text(d.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${d.docType.label} · ${d.uploadedAt.toString().substring(0, 16)}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                  onTap: () => _open(d),
                  trailing: IconButton(
                    tooltip: 'Delete',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _delete(d),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DocumentMetaDialog extends StatefulWidget {
  const _DocumentMetaDialog({required this.initialTitle, required this.initialType});

  final String initialTitle;
  final DocumentType initialType;

  @override
  State<_DocumentMetaDialog> createState() => _DocumentMetaDialogState();
}

class _DocumentMetaDialogState extends State<_DocumentMetaDialog> {
  late final TextEditingController _title = TextEditingController(text: widget.initialTitle);
  late DocumentType _type = widget.initialType;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Document details'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 16),
            DropdownButtonFormField<DocumentType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final t in DocumentType.values) DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged: (t) => setState(() => _type = t ?? _type),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final title = _title.text.trim();
            if (title.isEmpty) return;
            Navigator.pop(context, (title, _type));
          },
          child: const Text('Upload'),
        ),
      ],
    );
  }
}
