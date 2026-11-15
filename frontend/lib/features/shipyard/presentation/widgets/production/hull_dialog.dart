import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/repositories/shipyard_repository.dart';
import '../../providers/shipyard_providers.dart';
import '../date_field.dart';

/// Hull particulars, milestones, status and current berth / dock.
/// [hull] == null creates a new hull; otherwise the hull is edited (editors)
/// or shown read-only ([readOnly]). Returns the saved [Hull].
class HullDialog extends ConsumerStatefulWidget {
  const HullDialog({
    super.key,
    required this.projectId,
    required this.existingHulls,
    required this.locations,
    this.hull,
    this.readOnly = false,
  });

  final String projectId;
  final List<Hull> existingHulls;
  final Hull? hull;
  final bool readOnly;

  /// Berths, docks and quays (components in [hullLocationCategories]).
  final List<TwinComponent> locations;

  static Future<Hull?> show(
    BuildContext context, {
    required String projectId,
    required List<Hull> existingHulls,
    required List<TwinComponent> locations,
    Hull? hull,
    bool readOnly = false,
  }) {
    return showDialog<Hull>(
      context: context,
      barrierDismissible: readOnly,
      builder: (_) => HullDialog(
        projectId: projectId,
        existingHulls: existingHulls,
        locations: locations,
        hull: hull,
        readOnly: readOnly,
      ),
    );
  }

  @override
  ConsumerState<HullDialog> createState() => _HullDialogState();
}

class _HullDialogState extends ConsumerState<HullDialog> {
  late final Hull? _initial = widget.hull;
  late final _hullNo = TextEditingController(text: _initial?.hullNo ?? '');
  late final _name = TextEditingController(text: _initial?.name ?? '');
  late final _shipType = TextEditingController(text: _initial?.shipType ?? '');
  late final _owner = TextEditingController(text: _initial?.ownerName ?? '');
  late final _classSociety = TextEditingController(text: _initial?.classSociety ?? '');
  late final _length = TextEditingController(text: _numberText(_initial?.lengthM));
  late final _beam = TextEditingController(text: _numberText(_initial?.beamM));
  late final _deadweight = TextEditingController(text: _numberText(_initial?.deadweightT));

  late HullContractType _contractType = HullContractType.fromDb(_initial?.contractType);
  late HullStatus _status = _initial?.status ?? HullStatus.planned;
  late String? _locationNodeId = _initial?.locationNodeId;
  late DateTime? _contractDate = _initial == null ? ref.read(todayProvider) : _initial.contractDate;
  late DateTime? _steelCutting = _initial?.steelCuttingDate;
  late DateTime? _keelLaying = _initial?.keelLayingDate;
  late DateTime? _launching = _initial?.launchingDate;
  late DateTime? _contractDelivery = _initial?.contractDeliveryDate;
  late DateTime? _forecastDelivery = _initial?.forecastDeliveryDate;

  bool _saving = false;
  List<String> _errors = const [];

  bool get _isEdit => _initial != null;

  /// Fields are locked while saving and in read-only mode.
  bool get _enabled => !_saving && !widget.readOnly;

  static String _numberText(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
  }

  @override
  void dispose() {
    for (final c in [_hullNo, _name, _shipType, _owner, _classSociety, _length, _beam, _deadweight]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _number(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

  /// Text that is not empty but is no number (shown as an error instead of being dropped).
  bool _invalidNumber(TextEditingController c) => c.text.trim().isNotEmpty && _number(c) == null;

  HullDraft _draft() => HullDraft(
    projectId: widget.projectId,
    hullNo: _hullNo.text,
    contractType: _contractType,
    status: _status,
    name: _name.text,
    shipType: _shipType.text,
    ownerName: _owner.text,
    classSociety: _classSociety.text,
    lengthM: _number(_length),
    beamM: _number(_beam),
    deadweightT: _number(_deadweight),
    contractDate: _contractDate,
    steelCuttingDate: _steelCutting,
    keelLayingDate: _keelLaying,
    launchingDate: _launching,
    contractDeliveryDate: _contractDelivery,
    forecastDeliveryDate: _forecastDelivery,
    locationNodeId: _locationNodeId,
  );

  void _onContractType(HullContractType type) {
    setState(() {
      _contractType = type;
      // A repair arrives in a dock; a new build starts as planned.
      if (type == HullContractType.repair && _status == HullStatus.planned) _status = HullStatus.docked;
      if (type != HullContractType.repair && _status == HullStatus.docked) _status = HullStatus.planned;
    });
  }

  Future<void> _save() async {
    final draft = _draft();
    final errors = [
      for (final (label, c) in [('Length', _length), ('Beam', _beam), ('Deadweight', _deadweight)])
        if (_invalidNumber(c)) '$label is not a number.',
      ...draft.validationErrors(
        // The edited hull may keep its own number.
        existingHullNos: widget.existingHulls.where((h) => h.id != _initial?.id).map((h) => h.hullNo),
      ),
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
      final hull = _isEdit ? await repository.updateHull(_initial!.id, draft) : await repository.createHull(draft);
      if (mounted) Navigator.of(context).pop(hull);
    } on ShipyardException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errors = [e.message];
        });
      }
    }
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 10.5,
        letterSpacing: 0.8,
        color: AppTheme.textMuted,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _text(TextEditingController c, String label, {String? hint, bool number = false}) => TextField(
    controller: c,
    enabled: _enabled,
    keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
    decoration: InputDecoration(labelText: label, hintText: hint),
  );

  Widget _date(String label, DateTime? value, ValueChanged<DateTime?> onChanged, {String? helper}) => DateField(
    label: label,
    value: value,
    helper: helper,
    enabled: _enabled,
    initial: value ?? _contractDelivery ?? _contractDate ?? ref.read(todayProvider),
    onChanged: (d) => setState(() => onChanged(d)),
  );

  Widget _pair(Widget a, Widget b) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a),
        const SizedBox(width: 10),
        Expanded(child: b),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final build = _contractType != HullContractType.repair;
    final locations = [...widget.locations]..sort((a, b) => a.name.compareTo(b.name));
    return AlertDialog(
      title: Text(
        !_isEdit
            ? 'New hull'
            : widget.readOnly
            ? _initial!.displayName
            : 'Edit ${_initial!.hullNo}',
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _section('IDENTIFICATION'),
              _pair(
                _text(_hullNo, 'Hull no. *', hint: 'e.g. NB-1004'),
                _text(_name, 'Name', hint: 'e.g. MV Demo Aurora or TBN'),
              ),
              _pair(
                DropdownButtonFormField<HullContractType>(
                  initialValue: _contractType,
                  decoration: const InputDecoration(labelText: 'Contract type'),
                  items: [for (final t in HullContractType.values) DropdownMenuItem(value: t, child: Text(t.label))],
                  onChanged: !_enabled ? null : (v) => _onContractType(v ?? _contractType),
                ),
                _text(_shipType, 'Ship type', hint: 'e.g. Bulk carrier 28,000 dwt'),
              ),
              _pair(_text(_owner, 'Owner'), _text(_classSociety, 'Class society')),
              _section('MAIN PARTICULARS'),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _text(_length, 'Length (m)', number: true)),
                    const SizedBox(width: 10),
                    Expanded(child: _text(_beam, 'Beam (m)', number: true)),
                    const SizedBox(width: 10),
                    Expanded(child: _text(_deadweight, 'Deadweight (t)', number: true)),
                  ],
                ),
              ),
              _section('MILESTONES'),
              _pair(
                _date('Contract', _contractDate, (d) => _contractDate = d),
                build ? _date('Steel cutting', _steelCutting, (d) => _steelCutting = d) : const SizedBox.shrink(),
              ),
              if (build)
                _pair(
                  _date('Keel laying', _keelLaying, (d) => _keelLaying = d),
                  _date('Launching', _launching, (d) => _launching = d),
                ),
              _pair(
                _date('Contract delivery', _contractDelivery, (d) => _contractDelivery = d),
                _date(
                  'Forecast delivery',
                  _forecastDelivery,
                  (d) => _forecastDelivery = d,
                  helper: _forecastDelivery == null ? 'Empty = contract delivery' : null,
                ),
              ),
              _section('STATUS & LOCATION'),
              _pair(
                DropdownButtonFormField<HullStatus>(
                  // initialValue is only read once: re-create the field when the
                  // contract type changes the status programmatically.
                  key: ValueKey(_contractType),
                  initialValue: _status,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [
                    for (final s in HullStatus.values) DropdownMenuItem(value: s, child: Text(s.label)),
                  ],
                  onChanged: !_enabled ? null : (v) => setState(() => _status = v ?? _status),
                ),
                DropdownButtonFormField<String?>(
                  initialValue: _locationNodeId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Current location'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('— (not in the yard yet)')),
                    // Keep a stored location that is not a berth / dock / quay mesh selectable.
                    if (_locationNodeId != null && !locations.any((c) => c.meshNodeId == _locationNodeId))
                      DropdownMenuItem<String?>(value: _locationNodeId, child: Text(_locationNodeId!)),
                    for (final c in locations)
                      DropdownMenuItem<String?>(
                        value: c.meshNodeId,
                        child: Text(c.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: !_enabled ? null : (v) => setState(() => _locationNodeId = v),
                ),
              ),
              if (_errors.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 6),
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
        if (widget.readOnly)
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))
        else ...[
          TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_isEdit ? 'Save changes' : 'Create hull'),
          ),
        ],
      ],
    );
  }
}
