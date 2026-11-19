import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/entities/quality_entities.dart';
import '../../../domain/repositories/shipyard_repository.dart';
import '../../../domain/services/inspection_plan.dart';
import '../../providers/shipyard_providers.dart';
import '../date_field.dart';
import '../scene_actions.dart';

Widget _problems(List<String> lines) => Container(
  margin: const EdgeInsets.only(top: 10),
  padding: const EdgeInsets.all(10),
  decoration: BoxDecoration(color: const Color(0xFF450A0A), borderRadius: BorderRadius.circular(8)),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [for (final l in lines) Text('• $l', style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12.5))],
  ),
);

/// Plans one inspection (editors): what, where, when, acceptance band and witness.
/// Returns true when saved.
class NewInspectionDialog extends ConsumerStatefulWidget {
  const NewInspectionDialog({
    super.key,
    required this.projectId,
    required this.hulls,
    required this.components,
    required this.existing,
    this.initialHullId,
    this.initialComponentId,
  });

  final String projectId;
  final List<Hull> hulls;

  /// Blocks and yard areas an inspection can be pinned to.
  final List<TwinComponent> components;
  final List<QualityInspection> existing;
  final String? initialHullId;
  final String? initialComponentId;

  static Future<bool?> show(
    BuildContext context, {
    required String projectId,
    required List<Hull> hulls,
    required List<TwinComponent> components,
    required List<QualityInspection> existing,
    String? initialHullId,
    String? initialComponentId,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NewInspectionDialog(
        projectId: projectId,
        hulls: hulls,
        components: components,
        existing: existing,
        initialHullId: initialHullId,
        initialComponentId: initialComponentId,
      ),
    );
  }

  @override
  ConsumerState<NewInspectionDialog> createState() => _NewInspectionDialogState();
}

class _NewInspectionDialogState extends ConsumerState<NewInspectionDialog> {
  late String? _hullId = widget.initialHullId;
  late String? _componentId = widget.initialComponentId ?? _hullLocation(_hullId);
  InspectionType _type = InspectionType.visualWeld;
  late final _reference = TextEditingController(text: _suggestedReference());
  final _description = TextEditingController();
  late final _unit = TextEditingController();
  final _min = TextEditingController();
  final _max = TextEditingController();
  late final _inspector = TextEditingController(text: inspectionPresets[_type]!.inspector);
  final _witness = TextEditingController();
  final _notes = TextEditingController();
  late DateTime _date = addDays(ref.read(todayProvider), 1);
  bool _referenceEdited = false;
  bool _saving = false;
  List<String> _errors = const [];

  @override
  void dispose() {
    for (final c in [_reference, _description, _unit, _min, _max, _inspector, _witness, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Hull? get _hull => widget.hulls.where((h) => h.id == _hullId).firstOrNull;

  String? _hullLocation(String? hullId) {
    final node = widget.hulls.where((h) => h.id == hullId).firstOrNull?.locationNodeId;
    return widget.components.where((c) => c.meshNodeId == node).firstOrNull?.id;
  }

  String _suggestedReference() =>
      nextInspectionReference(_hull?.hullNo ?? 'YARD', widget.existing.map((q) => q.referenceNo));

  String _numberText(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v');

  /// Unit, band and inspector follow the type (they stay editable).
  void _setType(InspectionType type) {
    final preset = inspectionPresets[type]!;
    setState(() {
      _type = type;
      _unit.text = preset.unit ?? '';
      _min.text = _numberText(preset.min);
      _max.text = _numberText(preset.max);
      _inspector.text = preset.inspector;
    });
  }

  void _setHull(String? hullId) {
    setState(() {
      _hullId = hullId;
      _componentId ??= _hullLocation(hullId);
      if (!_referenceEdited) _reference.text = _suggestedReference();
    });
  }

  double? _number(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    final draft = InspectionDraft(
      projectId: widget.projectId,
      componentId: _componentId,
      hullId: _hullId,
      type: _type,
      referenceNo: _reference.text,
      description: _description.text,
      unit: _unit.text,
      acceptanceMin: _number(_min),
      acceptanceMax: _number(_max),
      inspector: _inspector.text,
      witnessedBy: _witness.text,
      plannedAt: DateTime(_date.year, _date.month, _date.day, InspectionPlan.plannedHour),
      notes: _notes.text,
    );
    final errors = [
      for (final (label, c) in [('Acceptance min', _min), ('Acceptance max', _max)])
        if (c.text.trim().isNotEmpty && _number(c) == null) '$label is not a number.',
      ...draft.validationErrors(),
    ];
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    setState(() {
      _saving = true;
      _errors = const [];
    });
    try {
      await ref.read(shipyardRepositoryProvider).createInspections([draft]);
      if (mounted) Navigator.of(context).pop(true);
    } on ShipyardException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errors = [e.message];
        });
      }
    }
  }

  Widget _field(TextEditingController c, String label, {String? hint, bool number = false, ValueChanged<String>? onChanged}) =>
      TextField(
        controller: c,
        enabled: !_saving,
        onChanged: onChanged,
        keyboardType: number ? const TextInputType.numberWithOptions(decimal: true, signed: true) : TextInputType.text,
        decoration: InputDecoration(labelText: label, hintText: hint),
      );

  Widget _row(List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, c) in children.indexed) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: c)],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final enabled = !_saving;
    final components = [...widget.components]..sort((a, b) => a.name.compareTo(b.name));
    return AlertDialog(
      title: const Text('Plan inspection'),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _row([
                DropdownButtonFormField<String?>(
                  initialValue: _hullId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Hull'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('— (yard / no hull)')),
                    for (final h in widget.hulls)
                      DropdownMenuItem<String?>(value: h.id, child: Text(h.displayName, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: enabled ? _setHull : null,
                ),
                DropdownButtonFormField<InspectionType>(
                  initialValue: _type,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [for (final t in InspectionType.values) DropdownMenuItem(value: t, child: Text(t.label))],
                  onChanged: enabled ? (v) => _setType(v ?? _type) : null,
                ),
              ]),
              _row([
                DropdownButtonFormField<String?>(
                  key: ValueKey('component-$_componentId'),
                  initialValue: _componentId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Block / area *', helperText: 'The 3D pin is placed here.'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('— choose —')),
                    for (final c in components)
                      DropdownMenuItem<String?>(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: enabled ? (v) => setState(() => _componentId = v) : null,
                ),
                DateField(
                  label: 'Planned date',
                  value: _date,
                  initial: _date,
                  enabled: enabled,
                  clearable: false,
                  onChanged: (d) => setState(() => _date = d ?? _date),
                ),
              ]),
              _row([
                _field(_reference, 'Reference no. *', onChanged: (_) => _referenceEdited = true),
                _field(_description, 'Description', hint: 'e.g. DB-101 butt welds, UT 100 %'),
              ]),
              _row([
                _field(_unit, 'Unit', hint: 'mm, um, bar'),
                _field(_min, 'Acceptance min', number: true),
                _field(_max, 'Acceptance max', number: true),
              ]),
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  'With an acceptance band the result is set automatically when a measured value is recorded '
                  '(outside the band = fail). Leave it empty for NDT / visual / surveys.',
                  style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                ),
              ),
              _row([
                _field(_inspector, 'Inspector (role / company)'),
                _field(_witness, 'Witnessed by', hint: 'e.g. Class surveyor, Owner representative'),
              ]),
              _field(_notes, 'Notes'),
              if (_errors.isNotEmpty) _problems(_errors),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Plan inspection'),
        ),
      ],
    );
  }
}

/// Drafts an inspection & test plan of a hull from its schedule rows (preview, then insert).
/// Offered for hulls with schedule rows that still have unplanned inspection points
/// (rows added later get theirs on a second draft). Returns the hull id when created.
class DraftInspectionPlanDialog extends ConsumerStatefulWidget {
  const DraftInspectionPlanDialog({
    super.key,
    required this.hulls,
    required this.activities,
    required this.components,
    required this.existing,
    this.initialHullId,
  });

  final List<Hull> hulls;
  final List<ProductionActivity> activities;
  final List<TwinComponent> components;
  final List<QualityInspection> existing;
  final String? initialHullId;

  static Future<String?> show(
    BuildContext context, {
    required List<Hull> hulls,
    required List<ProductionActivity> activities,
    required List<TwinComponent> components,
    required List<QualityInspection> existing,
    String? initialHullId,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DraftInspectionPlanDialog(
        hulls: hulls,
        activities: activities,
        components: components,
        existing: existing,
        initialHullId: initialHullId,
      ),
    );
  }

  @override
  ConsumerState<DraftInspectionPlanDialog> createState() => _DraftInspectionPlanDialogState();
}

class _DraftInspectionPlanDialogState extends ConsumerState<DraftInspectionPlanDialog> {
  late final List<Hull> _candidates = widget.hulls.where((h) => _draftsFor(h).isNotEmpty).toList();
  late String? _hullId = _candidates.any((h) => h.id == widget.initialHullId)
      ? widget.initialHullId
      : _candidates.firstOrNull?.id;
  bool _saving = false;
  String? _error;

  List<InspectionDraft> _drafts() {
    final hull = _candidates.where((h) => h.id == _hullId).firstOrNull;
    return hull == null ? const [] : _draftsFor(hull);
  }

  List<InspectionDraft> _draftsFor(Hull hull) {
    final byNode = {for (final c in widget.components) c.meshNodeId: c.id};
    return InspectionPlan.fromSchedule(
      hull: hull,
      activities: widget.activities,
      componentIdByNode: byNode,
      // Work outside the yard (sea trials) is pinned to the hull's berth, else the quay.
      fallbackComponentId: byNode[hull.locationNodeId] ?? byNode['NODE_A19_OUTFITTING_QUAY'],
      existingReferences: widget.existing.map((q) => q.referenceNo),
      existing: widget.existing,
    );
  }

  Future<void> _create(List<InspectionDraft> drafts) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(shipyardRepositoryProvider).createInspections(drafts);
      if (mounted) Navigator.of(context).pop(_hullId);
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
    final drafts = _drafts();
    final names = {for (final c in widget.components) c.id: shortComponentName(c)};
    const head = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted);
    const cell = TextStyle(fontSize: 12);
    return AlertDialog(
      title: const Text('Draft inspection plan from schedule'),
      content: SizedBox(
        width: 720,
        child: _candidates.isEmpty
            ? const Text(
                'No hull qualifies: every inspection point of the schedule rows is planned already. '
                'Plan single inspections instead.',
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _hullId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Hull',
                        helperText: 'Hulls with schedule rows whose inspection points are not planned yet.',
                      ),
                      items: [
                        for (final h in _candidates)
                          DropdownMenuItem(value: h.id, child: Text(h.displayName, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: _saving ? null : (v) => setState(() => _hullId = v),
                    ),
                    const SizedBox(height: 12),
                    if (drafts.isEmpty)
                      const Text('The schedule of this hull has no stages with inspection points.')
                    else ...[
                      Text(
                        '${drafts.length} inspections (result "pending", ${drafts.where((d) => d.holdPoint).length} '
                        'hold points H), planned on the last day of each activity. A row with an open hold point '
                        'cannot be reported finished. Every one can be recorded or deleted afterwards.',
                        style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                      ),
                      const SizedBox(height: 8),
                      Table(
                        columnWidths: const {
                          0: FixedColumnWidth(104),
                          1: FixedColumnWidth(96),
                          2: FlexColumnWidth(3),
                          3: FlexColumnWidth(1.6),
                          4: FixedColumnWidth(80),
                          5: FixedColumnWidth(86),
                        },
                        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                        children: [
                          const TableRow(
                            children: [
                              Padding(padding: EdgeInsets.only(bottom: 4), child: Text('REFERENCE · H', style: head)),
                              Text('TYPE', style: head),
                              Text('DESCRIPTION', style: head),
                              Text('WHERE', style: head),
                              Text('BAND', style: head),
                              Text('PLANNED', style: head),
                            ],
                          ),
                          for (final d in drafts)
                            TableRow(
                              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppTheme.outline))),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 5),
                                  child: Text('${d.referenceNo}${d.holdPoint ? ' · H' : ''}', style: cell),
                                ),
                                Text(d.type.label, style: cell),
                                Text(d.description ?? '', style: cell, overflow: TextOverflow.ellipsis),
                                Text(names[d.componentId] ?? '—', style: cell, overflow: TextOverflow.ellipsis),
                                Text(_band(d), style: cell),
                                Text(formatDate(d.plannedAt), style: cell),
                              ],
                            ),
                        ],
                      ),
                    ],
                    if (_error != null) _problems([_error!]),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        if (drafts.isNotEmpty)
          FilledButton(
            onPressed: _saving ? null : () => _create(drafts),
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Plan ${drafts.length} inspections'),
          ),
      ],
    );
  }

  static String _band(InspectionDraft d) {
    String n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
    final u = d.unit == null ? '' : ' ${d.unit}';
    if (d.acceptanceMin != null && d.acceptanceMax != null) return '${n(d.acceptanceMin!)}–${n(d.acceptanceMax!)}$u';
    if (d.acceptanceMin != null) return '≥ ${n(d.acceptanceMin!)}$u';
    if (d.acceptanceMax != null) return '≤ ${n(d.acceptanceMax!)}$u';
    return '—';
  }
}
