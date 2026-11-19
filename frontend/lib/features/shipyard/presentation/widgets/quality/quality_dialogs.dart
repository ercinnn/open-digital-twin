import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../auth/presentation/providers/auth_providers.dart';
import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/entities/quality_entities.dart';
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

/// Punch item details; editors move it through open -> in progress -> closed.
class PunchItemDialog extends ConsumerStatefulWidget {
  const PunchItemDialog({super.key, required this.item, required this.component});

  final PunchItem item;
  final TwinComponent? component;

  @override
  ConsumerState<PunchItemDialog> createState() => _PunchItemDialogState();
}

class _PunchItemDialogState extends ConsumerState<PunchItemDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _set(PunchStatus status) async {
    setState(() => _busy = true);
    try {
      await ref.read(shipyardRepositoryProvider).setPunchStatus(widget.item.id, status);
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
    final p = widget.item;
    final canEdit = ref.watch(isEditorProvider);
    final today = ref.watch(todayProvider);
    return AlertDialog(
      title: Row(
        children: [
          CircleAvatar(radius: 13, backgroundColor: p.priority.color, child: Text(p.priority.dbValue, style: const TextStyle(color: Color(0xFF0B1220), fontWeight: FontWeight.w800, fontSize: 13))),
          const SizedBox(width: 10),
          Expanded(child: Text(p.itemNo, style: const TextStyle(fontSize: 17))),
          if (p.isOverdue(today))
            const Chip(visualDensity: VisualDensity.compact, label: Text('Overdue', style: TextStyle(color: Color(0xFFFCA5A5)))),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(p.description, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            _kv('Location', widget.component?.name ?? '—'),
            _kv('Category', p.category),
            _kv('Raised by', '${p.raisedByLabel} · ${formatDate(p.raisedAt)}'),
            _kv('Priority', '${p.priority.dbValue} – ${p.priority.meaning}'),
            _kv('Due', formatDate(p.dueDate)),
            _kv('Status', p.closedAt == null ? p.status.label : '${p.status.label} · ${formatDate(p.closedAt)}'),
            if (_error != null) Text(_error!, style: const TextStyle(color: Color(0xFFFCA5A5))),
          ],
        ),
      ),
      actions: [
        if (canEdit) ...[
          if (p.status == PunchStatus.open)
            OutlinedButton(onPressed: _busy ? null : () => _set(PunchStatus.inProgress), child: const Text('Start work')),
          if (p.isOpen)
            OutlinedButton(onPressed: _busy ? null : () => _set(PunchStatus.closed), child: const Text('Close item')),
          if (!p.isOpen)
            OutlinedButton(onPressed: _busy ? null : () => _set(PunchStatus.open), child: const Text('Re-open')),
        ],
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}

/// Inspection details; editors record the result (measured value -> automatic
/// pass / fail from the acceptance band) or delete a planned inspection.
class InspectionDialog extends ConsumerStatefulWidget {
  const InspectionDialog({super.key, required this.inspection, required this.component});

  final QualityInspection inspection;
  final TwinComponent? component;

  @override
  ConsumerState<InspectionDialog> createState() => _InspectionDialogState();
}

/// Result choice when recording; [auto] lets the acceptance band decide.
enum _ResultChoice { auto, pass, fail, conditional }

class _InspectionDialogState extends ConsumerState<InspectionDialog> {
  late QualityInspection _q = widget.inspection;
  bool _recording = false;
  bool _saving = false;
  String? _error;
  late final _measured = TextEditingController(text: _q.measuredValue?.toString() ?? '');
  late final _notes = TextEditingController(text: _q.notes ?? '');
  late _ResultChoice _choice = _hasBand ? _ResultChoice.auto : _ResultChoice.pass;

  bool get _hasBand => _q.acceptanceMin != null || _q.acceptanceMax != null;

  String get _projectId => widget.component?.projectId ?? '';

  @override
  void dispose() {
    _measured.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _record() async {
    final text = _measured.text.trim();
    final measured = text.isEmpty ? null : double.tryParse(text.replaceAll(',', '.'));
    if (text.isNotEmpty && measured == null) {
      setState(() => _error = 'The measured value is not a number.');
      return;
    }
    if (_choice == _ResultChoice.auto && measured == null) {
      setState(() => _error = 'Enter the measured value, or choose the result yourself.');
      return;
    }
    final result = switch (_choice) {
      _ResultChoice.auto => InspectionResult.pending, // the trigger turns it into pass / fail
      _ResultChoice.pass => InspectionResult.pass,
      _ResultChoice.fail => InspectionResult.fail,
      _ResultChoice.conditional => InspectionResult.conditional,
    };
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await ref.read(shipyardRepositoryProvider).recordInspectionResult(
        _q.id,
        result: result,
        inspectedAt: DateTime.now(),
        measuredValue: measured,
        notes: _notes.text,
      );
      ref.invalidate(inspectionsProvider(_projectId));
      if (!mounted) return;
      setState(() {
        _q = saved;
        _saving = false;
        _recording = false;
      });
    } on ShipyardException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete inspection?'),
        content: Text('${_q.referenceNo} · ${_q.description ?? _q.type.label}\n\nThis cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB91C1C)),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(shipyardRepositoryProvider).deleteInspection(_q.id);
      ref.invalidate(inspectionsProvider(_projectId));
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

  List<Widget> _recordForm() => [
    const Divider(height: 24),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _measured,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: InputDecoration(
              labelText: 'Measured value${_q.unit == null ? '' : ' (${_q.unit})'}',
              helperText: _hasBand ? 'Acceptance ${_q.acceptanceText}' : 'Optional',
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButtonFormField<_ResultChoice>(
            initialValue: _choice,
            decoration: const InputDecoration(labelText: 'Result'),
            items: [
              if (_hasBand) const DropdownMenuItem(value: _ResultChoice.auto, child: Text('Auto (from band)')),
              const DropdownMenuItem(value: _ResultChoice.pass, child: Text('Pass')),
              const DropdownMenuItem(value: _ResultChoice.fail, child: Text('Fail')),
              const DropdownMenuItem(value: _ResultChoice.conditional, child: Text('Conditional')),
            ],
            onChanged: _saving ? null : (v) => setState(() => _choice = v ?? _choice),
          ),
        ),
      ],
    ),
    const SizedBox(height: 10),
    TextField(
      controller: _notes,
      enabled: !_saving,
      maxLines: 2,
      decoration: const InputDecoration(labelText: 'Notes'),
    ),
    if (_hasBand)
      const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text(
          'A value outside the acceptance band is always stored as "Fail" (database rule).',
          style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
        ),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final q = _q;
    final canEdit = ref.watch(isEditorProvider);
    final planned = q.result == InspectionResult.pending && q.inspectedAt.isAfter(DateTime.now());
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.fact_check_outlined, color: q.result.color),
          const SizedBox(width: 10),
          Expanded(child: Text('${q.referenceNo} · ${q.type.label}', style: const TextStyle(fontSize: 17))),
          Chip(
            visualDensity: VisualDensity.compact,
            label: Text(q.result.label, style: TextStyle(color: q.result.color, fontWeight: FontWeight.w700)),
            side: BorderSide(color: q.result.color),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (q.description != null) Text(q.description!, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              _kv('Location', widget.component?.name ?? '—'),
              if (q.holdPoint)
                _kv(
                  'ITP point',
                  q.isOpenHold
                      ? 'Hold point (H) - its schedule row cannot be finished before this inspection passes'
                      : 'Hold point (H) - released',
                )
              else if (q.activityId != null)
                _kv('ITP point', 'Witness / review point'),
              _kv(planned ? 'Planned' : 'Inspected', formatDateTime(q.inspectedAt)),
              if (q.measuredValue != null) _kv('Measured', '${q.measuredValue} ${q.unit ?? ''}'),
              if (q.acceptanceText != null) _kv('Acceptance', q.acceptanceText!),
              if (q.inspector != null) _kv('Inspector', q.inspector!),
              if (q.witnessedBy != null) _kv('Witnessed by', q.witnessedBy!),
              if (q.notes != null && !_recording) _kv('Notes', q.notes!),
              if (_recording) ..._recordForm(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: const TextStyle(color: Color(0xFFFCA5A5))),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (canEdit && !_recording) ...[
          TextButton(
            onPressed: _saving ? null : _delete,
            child: const Text('Delete', style: TextStyle(color: Color(0xFFFCA5A5))),
          ),
          OutlinedButton(
            onPressed: _saving ? null : () => setState(() => _recording = true),
            child: const Text('Record result'),
          ),
        ],
        if (_recording) ...[
          TextButton(onPressed: _saving ? null : () => setState(() => _recording = false), child: const Text('Back')),
          FilledButton(
            onPressed: _saving ? null : _record,
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save result'),
          ),
        ] else
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}

/// Raise a punch item on the selected component (editors).
class NewPunchDialog extends ConsumerStatefulWidget {
  const NewPunchDialog({super.key, required this.projectId, required this.component, required this.hulls});

  final String projectId;
  final TwinComponent component;
  final List<Hull> hulls;

  @override
  ConsumerState<NewPunchDialog> createState() => _NewPunchDialogState();
}

class _NewPunchDialogState extends ConsumerState<NewPunchDialog> {
  final _description = TextEditingController();
  String _category = 'hull';
  String _raisedBy = 'yard_qa';
  PunchPriority _priority = PunchPriority.b;
  String? _hullId;
  int _dueDays = 7;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final hullNo = widget.component.metadata['hull_no'];
    _hullId = widget.hulls.where((h) => h.hullNo == hullNo).firstOrNull?.id;
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_description.text.trim().isEmpty) {
      setState(() => _error = 'Describe the finding.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(shipyardRepositoryProvider).createPunchItem(
        PunchDraft(
          projectId: widget.projectId,
          componentId: widget.component.id,
          hullId: _hullId,
          description: _description.text.trim(),
          category: _category,
          raisedBy: _raisedBy,
          priority: _priority,
          dueDate: addDays(ref.read(todayProvider), _dueDays),
        ),
      );
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
      title: Text('Raise punch item · ${widget.component.name}', style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _description, maxLines: 2, decoration: const InputDecoration(labelText: 'Finding')),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _category,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: [
                        for (final c in const ['hull', 'machinery', 'piping', 'electrical', 'outfitting', 'paint', 'safety'])
                          DropdownMenuItem(value: c, child: Text(c)),
                      ],
                      onChanged: (v) => setState(() => _category = v ?? _category),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _raisedBy,
                      decoration: const InputDecoration(labelText: 'Raised by'),
                      items: const [
                        DropdownMenuItem(value: 'yard_qa', child: Text('Yard QA')),
                        DropdownMenuItem(value: 'owner', child: Text('Owner')),
                        DropdownMenuItem(value: 'class', child: Text('Class')),
                        DropdownMenuItem(value: 'flag', child: Text('Flag state')),
                      ],
                      onChanged: (v) => setState(() => _raisedBy = v ?? _raisedBy),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<PunchPriority>(
                      showSelectedIcon: false,
                      segments: [for (final p in PunchPriority.values) ButtonSegment(value: p, label: Text(p.dbValue), tooltip: p.meaning)],
                      selected: {_priority},
                      onSelectionChanged: (s) => setState(() => _priority = s.first),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 130,
                    child: DropdownButtonFormField<int>(
                      initialValue: _dueDays,
                      decoration: const InputDecoration(labelText: 'Due in'),
                      items: [for (final d in const [1, 3, 7, 14, 30]) DropdownMenuItem(value: d, child: Text('$d days'))],
                      onChanged: (v) => setState(() => _dueDays = v ?? _dueDays),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                initialValue: _hullId,
                decoration: const InputDecoration(labelText: 'Hull'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('—')),
                  for (final h in widget.hulls) DropdownMenuItem<String?>(value: h.id, child: Text(h.displayName)),
                ],
                onChanged: (v) => setState(() => _hullId = v),
              ),
              if (_error != null)
                Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: Color(0xFFFCA5A5)))),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Raise')),
      ],
    );
  }
}
