import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../domain/entities/hse_entities.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/repositories/shipyard_repository.dart';
import '../../providers/shipyard_providers.dart';

/// Requests a permit-to-work (editors). The permit starts as "requested"; approval
/// and activation (gas test for hot work / confined space) follow in its details.
/// From a block, the request is prefilled for one schedule row ([activity]: type,
/// window, description); zone warnings then follow the area the block is in
/// ([zoneComponentId]). Returns true when saved.
class NewPermitDialog extends ConsumerStatefulWidget {
  const NewPermitDialog({
    super.key,
    required this.projectId,
    required this.hulls,
    required this.components,
    required this.zones,
    required this.existing,
    this.initialComponentId,
    this.initialHullId,
    this.activity,
    this.initialType,
    this.initialDescription,
    this.initialFrom,
    this.initialHours,
    this.zoneComponentId,
  });

  final String projectId;
  final List<Hull> hulls;

  /// Blocks and yard areas the work can take place at.
  final List<TwinComponent> components;
  final List<HseZone> zones;
  final List<WorkPermit> existing;
  final String? initialComponentId;
  final String? initialHullId;

  /// Schedule row the permit covers (`work_permits.activity_id`).
  final ProductionActivity? activity;
  final PermitType? initialType;
  final String? initialDescription;
  final DateTime? initialFrom;
  final int? initialHours;

  /// Area whose HSE zones apply besides the chosen component (e.g. the hall a block is in).
  final String? zoneComponentId;

  static Future<bool?> show(
    BuildContext context, {
    required String projectId,
    required List<Hull> hulls,
    required List<TwinComponent> components,
    required List<HseZone> zones,
    required List<WorkPermit> existing,
    String? initialComponentId,
    String? initialHullId,
    ProductionActivity? activity,
    PermitType? initialType,
    String? initialDescription,
    DateTime? initialFrom,
    int? initialHours,
    String? zoneComponentId,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NewPermitDialog(
        projectId: projectId,
        hulls: hulls,
        components: components,
        zones: zones,
        existing: existing,
        initialComponentId: initialComponentId,
        initialHullId: initialHullId,
        activity: activity,
        initialType: initialType,
        initialDescription: initialDescription,
        initialFrom: initialFrom,
        initialHours: initialHours,
        zoneComponentId: zoneComponentId,
      ),
    );
  }

  @override
  ConsumerState<NewPermitDialog> createState() => _NewPermitDialogState();
}

class _NewPermitDialogState extends ConsumerState<NewPermitDialog> {
  late final List<int> _durations = {2, 4, 6, 8, 10, 12, 24, ?widget.initialHours}.toList()..sort();

  late PermitType _type = widget.initialType ?? PermitType.hotWork;
  late String? _componentId = widget.initialComponentId;
  late String? _hullId = widget.initialHullId ?? _hullOf(widget.initialComponentId);
  late final _permitNo = TextEditingController(
    text: nextPermitNumber(widget.existing.map((p) => p.permitNo), DateTime.now()),
  );
  late final _description = TextEditingController(text: widget.initialDescription ?? '');
  final _issuedTo = TextEditingController();
  late final _precautions = TextEditingController(text: permitPrecautions[_type]);
  bool _precautionsEdited = false;

  /// Next full hour; a shift permit of 8 h by default.
  late DateTime _from =
      widget.initialFrom ??
      () {
        final n = DateTime.now();
        return DateTime(n.year, n.month, n.day, n.hour + 1);
      }();
  late int _hours = widget.initialHours ?? 8;
  bool _saving = false;
  List<String> _errors = const [];

  @override
  void dispose() {
    for (final c in [_permitNo, _description, _issuedTo, _precautions]) {
      c.dispose();
    }
    super.dispose();
  }

  /// A block belongs to its hull (`metadata.hull_no`), e.g. NB-1001 blocks.
  String? _hullOf(String? componentId) {
    final hullNo = widget.components.where((c) => c.id == componentId).firstOrNull?.metadata['hull_no'];
    return widget.hulls.where((h) => h.hullNo == hullNo).firstOrNull?.id;
  }

  void _setType(PermitType type) {
    setState(() {
      _type = type;
      if (!_precautionsEdited) _precautions.text = permitPrecautions[type] ?? '';
    });
  }

  Future<void> _pickStart() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay(hour: _from.hour, minute: _from.minute));
    if (!mounted) return;
    setState(() => _from = DateTime(date.year, date.month, date.day, time?.hour ?? _from.hour, time?.minute ?? 0));
  }

  Future<void> _save() async {
    final draft = PermitDraft(
      projectId: widget.projectId,
      componentId: _componentId,
      hullId: _hullId,
      activityId: widget.activity?.id,
      permitNo: _permitNo.text,
      type: _type,
      description: _description.text,
      validFrom: _from,
      validTo: _from.add(Duration(hours: _hours)),
      issuedTo: _issuedTo.text,
      precautions: _precautions.text,
    );
    final errors = draft.validationErrors();
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    setState(() {
      _saving = true;
      _errors = const [];
    });
    try {
      await ref.read(shipyardRepositoryProvider).createPermit(draft);
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
    final components = [...widget.components]..sort((a, b) => a.name.compareTo(b.name));
    final warnings = [
      ...permitZoneWarnings(_type, _componentId, widget.zones),
      if (widget.zoneComponentId != null && widget.zoneComponentId != _componentId)
        ...permitZoneWarnings(_type, widget.zoneComponentId, widget.zones),
    ]..sort((a, b) => (b.conflict ? 1 : 0) - (a.conflict ? 1 : 0));
    final activity = widget.activity;
    return AlertDialog(
      title: const Text('Request work permit'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (activity != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'For ${activity.name} (${formatDate(activity.plannedStart)} → ${formatDate(activity.plannedEnd)})',
                    style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<PermitType>(
                      initialValue: _type,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Permit type'),
                      items: [
                        for (final t in PermitType.values)
                          DropdownMenuItem(
                            value: t,
                            child: Row(
                              children: [Icon(t.icon, size: 16, color: t.color), const SizedBox(width: 8), Text(t.label)],
                            ),
                          ),
                      ],
                      onChanged: enabled ? (v) => _setType(v ?? _type) : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _permitNo,
                      enabled: enabled,
                      decoration: const InputDecoration(labelText: 'Permit no.'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _componentId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Block / area *', helperText: 'The 3D pin is placed here.'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('— choose —')),
                        for (final c in components)
                          DropdownMenuItem<String?>(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: enabled && activity == null
                          ? (v) => setState(() {
                              _componentId = v;
                              _hullId = _hullOf(v) ?? _hullId;
                            })
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      key: ValueKey('hull-$_hullId'),
                      initialValue: _hullId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Hull'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('— (yard work)')),
                        for (final h in widget.hulls)
                          DropdownMenuItem<String?>(value: h.id, child: Text(h.displayName, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: enabled ? (v) => setState(() => _hullId = v) : null,
                    ),
                  ),
                ],
              ),
              for (final w in warnings)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: w.conflict ? const Color(0xFF450A0A) : AppTheme.surfaceHigh,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: w.conflict ? const Color(0xFFEF4444) : w.zone.type.color),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        w.conflict ? Icons.dangerous_outlined : Icons.info_outline,
                        size: 18,
                        color: w.conflict ? const Color(0xFFFCA5A5) : w.zone.type.color,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${w.zone.name} (${w.zone.type.label}): ${w.message}',
                          style: TextStyle(fontSize: 12, color: w.conflict ? const Color(0xFFFCA5A5) : null),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: _description,
                enabled: enabled,
                decoration: const InputDecoration(labelText: 'Work description *', hintText: 'e.g. NB-1004 plasma cutting of bottom plates'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: enabled ? _pickStart : null,
                      icon: const Icon(Icons.schedule, size: 18),
                      label: Text('Valid from ${formatDateTime(_from)}'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 130,
                    child: DropdownButtonFormField<int>(
                      initialValue: _hours,
                      decoration: const InputDecoration(labelText: 'Duration'),
                      items: [for (final h in _durations) DropdownMenuItem(value: h, child: Text('$h h'))],
                      onChanged: enabled ? (v) => setState(() => _hours = v ?? _hours) : null,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Valid until ${formatDateTime(_from.add(Duration(hours: _hours)))}',
                  style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _issuedTo,
                enabled: enabled,
                decoration: const InputDecoration(
                  labelText: 'Issued to (crew / contractor)',
                  hintText: 'e.g. Hull crew H-3 - no personal names',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _precautions,
                enabled: enabled,
                maxLines: 2,
                onChanged: (_) => _precautionsEdited = true,
                decoration: const InputDecoration(labelText: 'Precautions'),
              ),
              if (_type == PermitType.lifting && activity?.stage == ProductionStage.erection)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Activation needs a crane lift of this erection booked inside the permit window (database rule).',
                    style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                  ),
                ),
              if (_type.needsGasTest)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Activation needs a gas test (O₂ 19.5–23.5 %, LEL < 10 %); the database rejects unsafe readings.',
                    style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
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
              : const Text('Request permit'),
        ),
      ],
    );
  }
}
