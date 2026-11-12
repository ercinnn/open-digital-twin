import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/file_utils.dart';
import '../../domain/entities/project.dart';

/// Result of the "New project" dialog.
class CreateProjectInput {
  const CreateProjectInput({
    required this.name,
    required this.domainType,
    this.description,
    this.fileName,
    this.fileBytes,
  });

  final String name;
  final DomainType domainType;
  final String? description;
  final String? fileName;
  final Uint8List? fileBytes;
}

/// Opens the native/web picker for CAD files. Returns null when cancelled.
Future<(String, Uint8List)?> pickCadFile() async {
  final files = await FilePicker.pickFiles(
    dialogTitle: 'Select a CAD / BIM / mesh file',
    type: FileType.custom,
    allowedExtensions: FileUtils.cadExtensions,
  );
  if (files.isEmpty) return null;
  final file = files.first;
  return (file.name, await file.readAsBytes());
}

class CreateProjectDialog extends StatefulWidget {
  const CreateProjectDialog({super.key});

  @override
  State<CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<CreateProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  DomainType _domain = DomainType.marine;
  String? _fileName;
  Uint8List? _fileBytes;
  bool _picking = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() => _picking = true);
    try {
      final picked = await pickCadFile();
      if (picked != null && mounted) {
        setState(() {
          _fileName = picked.$1;
          _fileBytes = picked.$2;
        });
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      CreateProjectInput(
        name: _name.text.trim(),
        domainType: _domain,
        description: _description.text.trim(),
        fileName: _fileName,
        fileBytes: _fileBytes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New digital twin project'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Project name'),
                validator: (v) => (v == null || v.trim().length < 3) ? 'Enter at least 3 characters' : null,
              ),
              const SizedBox(height: 16),
              SegmentedButton<DomainType>(
                segments: const [
                  ButtonSegment(value: DomainType.marine, label: Text('Marine'), icon: Icon(Icons.directions_boat)),
                  ButtonSegment(
                    value: DomainType.construction,
                    label: Text('Construction'),
                    icon: Icon(Icons.apartment),
                  ),
                ],
                selected: {_domain},
                onSelectionChanged: (s) => setState(() => _domain = s.first),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _description,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Description (optional)'),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _picking ? null : _pick,
                icon: const Icon(Icons.upload_file),
                label: Text(_fileName == null ? 'Attach CAD file (.step / .ifc / .ocx / .obj / .stl)' : 'Change file'),
              ),
              if (_fileName != null) ...[
                const SizedBox(height: 8),
                Text(
                  '$_fileName  ·  ${FileUtils.formatBytes(_fileBytes!.length)}  — will be uploaded and ingested',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton.icon(onPressed: _submit, icon: const Icon(Icons.add), label: const Text('Create')),
      ],
    );
  }
}
