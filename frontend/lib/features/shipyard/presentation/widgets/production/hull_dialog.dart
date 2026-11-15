import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/repositories/shipyard_repository.dart';
import '../../providers/shipyard_providers.dart';

/// New hull (editors): particulars, milestones, status and current berth / dock.
/// Returns the created [Hull] when saved.
class NewHullDialog extends ConsumerStatefulWidget {
  const NewHullDialog({super.key, required this.projectId, required this.existingHulls, required this.locations});

  final String projectId;
  final List<Hull> existingHulls;

  /// Berths, docks and quays (components in [hullLocationCategories]).
  final List<TwinComponent> locations;

  static Future<Hull?> show(
    BuildContext context, {
    required String projectId,
    required List<Hull> existingHulls,
    required List<TwinComponent> locations,
  }) {
    return showDialog<Hull>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NewHullDialog(projectId: projectId, existingHulls: existingHulls, locations: locations),
    );
  }

  @override
  ConsumerState<NewHullDialog> createState() => _NewHullDialogState();
}

class _NewHullDialogState extends ConsumerState<NewHullDialog> {
  final _hullNo = TextEditingController();
  final _name = TextEditingController();
  final _shipType = TextEditingController();
  final _owner = TextEditingController();
  final _classSociety = TextEditingController();
  final _length = TextEditingController();
  final _beam = TextEditingController();
  final _deadweight = TextEditingController();

  HullContractType _contractType = HullContractType.newbuild;
  HullStatus _status = HullStatus.planned;
  String? _locationNodeId;
  late DateTime? _contractDate = ref.read(todayProvider);
  DateTime? _steelCutting;
  DateTime? _keelLaying;
  DateTime? _launching;
  DateTime? _contractDelivery;
  DateTime? _forecastDelivery;

  bool _saving = false;
  List<String> _errors = const [];

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
      ...draft.validationErrors(existingHullNos: widget.existingHulls.map((h) => h.hullNo)),
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
      final hull = await ref.read(shipyardRepositoryProvider).createHull(draft);
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
    enabled: !_saving,
    keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
    decoration: InputDecoration(labelText: label, hintText: hint),
  );

  Widget _date(String label, DateTime? value, ValueChanged<DateTime?> onChanged, {String? helper}) => _DateField(
    label: label,
    value: value,
    helper: helper,
    enabled: !_saving,
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
      title: const Text('New hull'),
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
                  onChanged: _saving ? null : (v) => _onContractType(v ?? _contractType),
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
                    for (final s in HullStatus.values)
                      if (build ? s != HullStatus.docked : true) DropdownMenuItem(value: s, child: Text(s.label)),
                  ],
                  onChanged: _saving ? null : (v) => setState(() => _status = v ?? _status),
                ),
                DropdownButtonFormField<String?>(
                  initialValue: _locationNodeId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Current location'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('— (not in the yard yet)')),
                    for (final c in locations)
                      DropdownMenuItem<String?>(
                        value: c.meshNodeId,
                        child: Text(c.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _saving ? null : (v) => setState(() => _locationNodeId = v),
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
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create hull'),
        ),
      ],
    );
  }
}

/// Date picker field with a clear button (all milestones are optional).
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.initial,
    required this.enabled,
    required this.onChanged,
    this.helper,
  });

  final String label;
  final DateTime? value;
  final DateTime initial;
  final bool enabled;
  final ValueChanged<DateTime?> onChanged;
  final String? helper;

  Future<void> _pick(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) onChanged(dateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => _pick(context) : null,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        isEmpty: value == null,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          enabled: enabled,
          suffixIcon: value == null
              ? const Icon(Icons.event, size: 18)
              : IconButton(
                  tooltip: 'Clear',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: enabled ? () => onChanged(null) : null,
                ),
        ),
        child: Text(value == null ? '' : formatDate(value)),
      ),
    );
  }
}
