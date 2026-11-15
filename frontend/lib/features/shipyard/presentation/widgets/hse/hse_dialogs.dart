import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../auth/presentation/providers/auth_providers.dart';
import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../domain/entities/hse_entities.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/repositories/shipyard_repository.dart';
import '../../providers/shipyard_providers.dart';

Widget _kv(String k, String v) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 3),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(width: 110, child: Text(k, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5))),
      Expanded(child: SelectableText(v, style: const TextStyle(fontSize: 13))),
    ],
  ),
);

String formatRemaining(Duration d) {
  if (d.isNegative) return 'expired';
  if (d.inHours >= 24) return '${d.inDays} d ${d.inHours % 24} h left';
  if (d.inHours >= 1) return '${d.inHours} h ${d.inMinutes % 60} min left';
  return '${d.inMinutes} min left';
}

/// Permit-to-work details. Activating hot work / confined space asks for a gas
/// test; the database rejects unsafe readings.
class PermitDialog extends ConsumerStatefulWidget {
  const PermitDialog({super.key, required this.permit, required this.component});

  final WorkPermit permit;
  final TwinComponent? component;

  @override
  ConsumerState<PermitDialog> createState() => _PermitDialogState();
}

class _PermitDialogState extends ConsumerState<PermitDialog> {
  late final _o2 = TextEditingController(text: widget.permit.gasO2?.toString() ?? '');
  late final _lel = TextEditingController(text: widget.permit.gasLel?.toString() ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _o2.dispose();
    _lel.dispose();
    super.dispose();
  }

  Future<void> _set(PermitStatus status) async {
    double? o2;
    double? lel;
    if (status == PermitStatus.active && widget.permit.type.needsGasTest) {
      o2 = double.tryParse(_o2.text.replaceAll(',', '.'));
      lel = double.tryParse(_lel.text.replaceAll(',', '.'));
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(shipyardRepositoryProvider).setPermitStatus(widget.permit.id, status, gasO2: o2, gasLel: lel);
      if (mounted) Navigator.of(context).pop();
    } on ShipyardException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.permit;
    final canEdit = ref.watch(isEditorProvider);
    final now = DateTime.now();
    final showGas = p.type.needsGasTest && p.status != PermitStatus.closed;
    return AlertDialog(
      title: Row(
        children: [
          Icon(p.type.icon, color: p.type.color),
          const SizedBox(width: 10),
          Expanded(child: Text('${p.permitNo} · ${p.type.label}', style: const TextStyle(fontSize: 17))),
          Chip(visualDensity: VisualDensity.compact, label: Text(p.status.label)),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(p.description, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              _kv('Location', widget.component?.name ?? '—'),
              _kv('Valid', '${formatDateTime(p.validFrom)} → ${formatDateTime(p.validTo)}'),
              if (p.status == PermitStatus.active) _kv('Remaining', formatRemaining(p.remaining(now))),
              if (p.issuedTo != null) _kv('Issued to', p.issuedTo!),
              if (p.gasO2 != null || p.gasLel != null)
                _kv('Gas test', 'O₂ ${p.gasO2 ?? '—'} % · LEL ${p.gasLel ?? '—'} %'
                    '${p.gasTestedAt == null ? '' : ' · ${formatDateTime(p.gasTestedAt!)}'}'),
              if (p.precautions != null) _kv('Precautions', p.precautions!),
              if (showGas && canEdit && p.status != PermitStatus.active) ...[
                const SizedBox(height: 10),
                const Text('Gas test before activation (O₂ 19.5–23.5 %, LEL < 10 %)', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _o2,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'O₂ %'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _lel,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'LEL %'),
                      ),
                    ),
                  ],
                ),
              ],
              if (_error != null)
                Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: Color(0xFFFCA5A5)))),
            ],
          ),
        ),
      ),
      actions: [
        if (canEdit) ...[
          if (p.status == PermitStatus.requested)
            OutlinedButton(onPressed: _busy ? null : () => _set(PermitStatus.approved), child: const Text('Approve')),
          if (p.status == PermitStatus.approved || p.status == PermitStatus.suspended)
            OutlinedButton(onPressed: _busy ? null : () => _set(PermitStatus.active), child: const Text('Activate')),
          if (p.status == PermitStatus.active)
            OutlinedButton(onPressed: _busy ? null : () => _set(PermitStatus.suspended), child: const Text('Suspend')),
          if (p.status != PermitStatus.closed)
            OutlinedButton(onPressed: _busy ? null : () => _set(PermitStatus.closed), child: const Text('Close permit')),
        ],
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}

class IncidentDialog extends StatelessWidget {
  const IncidentDialog({super.key, required this.incident, required this.component});

  final HseIncident incident;
  final TwinComponent? component;

  @override
  Widget build(BuildContext context) {
    final i = incident;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.report_outlined, color: i.severity.color),
          const SizedBox(width: 10),
          Expanded(child: Text('${i.incidentNo} · ${i.severity.label}', style: const TextStyle(fontSize: 17))),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(i.description, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _kv('Location', component?.name ?? '—'),
            _kv('Occurred', formatDateTime(i.occurredAt)),
            _kv('Status', i.status),
            if (i.correctiveAction != null) _kv('Corrective action', i.correctiveAction!),
          ],
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  }
}

/// Report an incident / near miss at the selected component (editors).
class ReportIncidentDialog extends ConsumerStatefulWidget {
  const ReportIncidentDialog({super.key, required this.projectId, required this.component});

  final String projectId;
  final TwinComponent? component;

  @override
  ConsumerState<ReportIncidentDialog> createState() => _ReportIncidentDialogState();
}

class _ReportIncidentDialogState extends ConsumerState<ReportIncidentDialog> {
  final _description = TextEditingController();
  IncidentSeverity _severity = IncidentSeverity.nearMiss;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_description.text.trim().isEmpty) {
      setState(() => _error = 'Describe what happened.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(shipyardRepositoryProvider).reportIncident(
        projectId: widget.projectId,
        componentId: widget.component?.id,
        severity: _severity,
        description: _description.text.trim(),
      );
      ref.invalidate(incidentsProvider(widget.projectId));
      if (mounted) Navigator.of(context).pop();
    } on ShipyardException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Report incident${widget.component == null ? '' : ' · ${widget.component!.name}'}', style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<IncidentSeverity>(
              initialValue: _severity,
              decoration: const InputDecoration(labelText: 'Severity'),
              items: [for (final s in IncidentSeverity.values) DropdownMenuItem(value: s, child: Text(s.label))],
              onChanged: (v) => setState(() => _severity = v ?? _severity),
            ),
            const SizedBox(height: 10),
            TextField(controller: _description, maxLines: 3, decoration: const InputDecoration(labelText: 'What happened?')),
            const SizedBox(height: 6),
            const Text('Do not enter names or other personal data.', style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
            if (_error != null)
              Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: Color(0xFFFCA5A5)))),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Report')),
      ],
    );
  }
}
