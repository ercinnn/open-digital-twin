import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/repositories/shipyard_repository.dart';
import '../../../domain/services/draft_schedule.dart';
import '../../providers/shipyard_providers.dart';
import '../date_field.dart';

/// Yard areas a schedule row can run at (components with an `area_no`), by area number.
List<TwinComponent> yardAreas(List<TwinComponent> components) {
  int areaNo(TwinComponent c) => (c.metadata['area_no'] as num?)?.toInt() ?? 999;
  return components.where((c) => c.metadata['area_no'] != null).toList()
    ..sort((a, b) => areaNo(a).compareTo(areaNo(b)));
}

/// Adds one schedule row ([activity] == null) or edits the plan of an existing one
/// (name, stage, location, planned dates). Progress / actual dates stay in [ActivityDialog].
/// Returns true when saved.
class ActivityFormDialog extends ConsumerStatefulWidget {
  const ActivityFormDialog({
    super.key,
    required this.projectId,
    required this.hulls,
    required this.areas,
    required this.existing,
    this.activity,
    this.initialHullId,
  });

  final String projectId;
  final List<Hull> hulls;
  final List<TwinComponent> areas;

  /// All schedule rows of the project (activity codes are unique per project).
  final List<ProductionActivity> existing;
  final ProductionActivity? activity;
  final String? initialHullId;

  static Future<bool?> show(
    BuildContext context, {
    required String projectId,
    required List<Hull> hulls,
    required List<TwinComponent> areas,
    required List<ProductionActivity> existing,
    ProductionActivity? activity,
    String? initialHullId,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ActivityFormDialog(
        projectId: projectId,
        hulls: hulls,
        areas: areas,
        existing: existing,
        activity: activity,
        initialHullId: initialHullId,
      ),
    );
  }

  @override
  ConsumerState<ActivityFormDialog> createState() => _ActivityFormDialogState();
}

class _ActivityFormDialogState extends ConsumerState<ActivityFormDialog> {
  late final ProductionActivity? _initial = widget.activity;
  late String? _hullId = _initial?.hullId ?? widget.initialHullId ?? widget.hulls.firstOrNull?.id;
  late ProductionStage _stage = _initial?.stage ?? ProductionStage.cutting;
  late String? _locationNodeId = _initial == null ? _defaultLocation(_stage) : _initial.locationNodeId;
  late final _name = TextEditingController(text: _initial?.name ?? _suggestedName());
  late final _notes = TextEditingController(text: _initial?.notes ?? '');
  late DateTime _start = _initial?.plannedStart ?? addDays(ref.read(todayProvider), 1);
  late DateTime _end = _initial?.plannedEnd ?? addDays(_start, 7);

  /// The name follows the stage until the user types an own name.
  late bool _nameEdited = _initial != null;
  bool _saving = false;
  List<String> _errors = const [];

  bool get _isEdit => _initial != null;

  Hull? get _hull => widget.hulls.where((h) => h.id == _hullId).firstOrNull;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? _defaultLocation(ProductionStage stage) {
    final node = stageDefaultLocations[stage];
    return widget.areas.any((a) => a.meshNodeId == node) ? node : null;
  }

  String _suggestedName() {
    final hullNo = _hull?.hullNo;
    final name = stageDefaultNames[_stage] ?? _stage.label;
    return hullNo == null ? name : '$hullNo $name';
  }

  void _setStage(ProductionStage stage) {
    setState(() {
      _stage = stage;
      _locationNodeId = _defaultLocation(stage);
      if (!_nameEdited) _name.text = _suggestedName();
    });
  }

  void _setHull(String? hullId) {
    setState(() {
      _hullId = hullId;
      if (!_nameEdited) _name.text = _suggestedName();
    });
  }

  Future<void> _save() async {
    final hull = _hull;
    final codes = {for (final a in widget.existing) a.code};
    final draft = ActivityDraft(
      projectId: widget.projectId,
      hullId: _isEdit ? _initial!.hullId : _hullId,
      code: _isEdit ? _initial!.code : activityCodeFor(hull?.hullNo ?? 'YARD', _stage, codes),
      name: _name.text,
      stage: _stage,
      plannedStart: _start,
      plannedEnd: _end,
      locationNodeId: _locationNodeId,
      componentId: _initial?.componentId,
      sortOrder: widget.existing.fold<int>(0, (m, a) => a.sortOrder > m ? a.sortOrder : m) + 1,
      notes: _notes.text,
    );
    final errors = [
      if (!_isEdit && hull == null) 'Choose a hull.',
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
      final repository = ref.read(shipyardRepositoryProvider);
      if (_isEdit) {
        await repository.updateActivityPlan(_initial!.id, draft);
      } else {
        await repository.createActivities([draft]);
      }
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

  @override
  Widget build(BuildContext context) {
    final enabled = !_saving;
    final storedLocationMissing =
        _locationNodeId != null && !widget.areas.any((a) => a.meshNodeId == _locationNodeId);
    return AlertDialog(
      title: Text(_isEdit ? 'Edit plan · ${_initial!.code}' : 'New activity'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_isEdit) ...[
                DropdownButtonFormField<String>(
                  initialValue: _hullId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Hull'),
                  items: [
                    for (final h in widget.hulls)
                      DropdownMenuItem(value: h.id, child: Text(h.displayName, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: enabled ? _setHull : null,
                ),
                const SizedBox(height: 10),
              ],
              DropdownButtonFormField<ProductionStage>(
                initialValue: _stage,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Stage'),
                items: [
                  for (final s in ProductionStage.values)
                    DropdownMenuItem(
                      value: s,
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Text(s.label),
                        ],
                      ),
                    ),
                ],
                onChanged: enabled ? (v) => _setStage(v ?? _stage) : null,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _name,
                enabled: enabled,
                onChanged: (_) => _nameEdited = true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                // Re-created when the stage proposes another default location.
                key: ValueKey('location-$_stage'),
                initialValue: _locationNodeId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Location (yard area)'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('— (outside the yard / none)')),
                  if (storedLocationMissing)
                    DropdownMenuItem<String?>(value: _locationNodeId, child: Text(_locationNodeId!)),
                  for (final a in widget.areas)
                    DropdownMenuItem<String?>(
                      value: a.meshNodeId,
                      child: Text(a.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: enabled ? (v) => setState(() => _locationNodeId = v) : null,
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DateField(
                      label: 'Planned start',
                      value: _start,
                      initial: _start,
                      enabled: enabled,
                      clearable: false,
                      onChanged: (d) => setState(() {
                        if (d == null) return;
                        // Keep the duration when the start moves.
                        final days = daysBetween(_start, _end);
                        _start = d;
                        _end = addDays(d, days);
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DateField(
                      label: 'Planned end',
                      value: _end,
                      initial: _end,
                      enabled: enabled,
                      clearable: false,
                      helper: '${daysBetween(_start, _end)} days',
                      onChanged: (d) => setState(() => _end = d ?? _end),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _notes,
                enabled: enabled,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
              ),
              if (_isEdit && _initial!.actualStart != null)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Progress and actual dates are kept; report them in the activity details.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              if (_errors.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFF450A0A), borderRadius: BorderRadius.circular(8)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in _errors)
                        Text('• $e', style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12.5)),
                    ],
                  ),
                ),
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
              : Text(_isEdit ? 'Save plan' : 'Add activity'),
        ),
      ],
    );
  }
}
