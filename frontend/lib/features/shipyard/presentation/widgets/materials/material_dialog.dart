import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../domain/entities/material_entities.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/repositories/shipyard_repository.dart';
import '../../providers/shipyard_providers.dart';

/// New stock item ([item] == null) or edit of all its fields (editors).
/// Returns true when saved.
class MaterialItemDialog extends ConsumerStatefulWidget {
  const MaterialItemDialog({
    super.key,
    required this.projectId,
    required this.existing,
    required this.hulls,
    required this.stores,
    this.item,
    this.initialHullId,
  });

  final String projectId;

  /// All items of the project (item codes are unique per project).
  final List<MaterialItem> existing;
  final List<Hull> hulls;

  /// Yard areas stock can be kept at.
  final List<TwinComponent> stores;
  final MaterialItem? item;
  final String? initialHullId;

  static Future<bool?> show(
    BuildContext context, {
    required String projectId,
    required List<MaterialItem> existing,
    required List<Hull> hulls,
    required List<TwinComponent> stores,
    MaterialItem? item,
    String? initialHullId,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MaterialItemDialog(
        projectId: projectId,
        existing: existing,
        hulls: hulls,
        stores: stores,
        item: item,
        initialHullId: initialHullId,
      ),
    );
  }

  @override
  ConsumerState<MaterialItemDialog> createState() => _MaterialItemDialogState();
}

class _MaterialItemDialogState extends ConsumerState<MaterialItemDialog> {
  late final MaterialItem? _initial = widget.item;
  late final _code = TextEditingController(text: _initial?.itemCode ?? '');
  late final _description = TextEditingController(text: _initial?.description ?? '');
  late final _grade = TextEditingController(text: _initial?.grade ?? '');
  late final _dimensions = TextEditingController(text: _initial?.dimensions ?? '');
  late final _onHand = TextEditingController(text: _numberText(_initial?.onHand ?? 0));
  late final _reserved = TextEditingController(text: _numberText(_initial?.reserved ?? 0));
  late final _reorder = TextEditingController(text: _numberText(_initial?.reorderLevel ?? 0));
  late final _heat = TextEditingController(text: _initial?.heatNumber ?? '');
  late final _certificate = TextEditingController(text: _initial?.certificateNo ?? '');
  late final _supplier = TextEditingController(text: _initial?.supplier ?? '');

  late StockCategory _type = _initial?.type ?? StockCategory.plate;
  late String _unit = _initial?.unit ?? defaultUnitFor(_type);
  late String? _hullId = _initial == null ? widget.initialHullId : _initial.hullId;
  late String? _storeId = _initial == null ? _defaultStore(_type) : _initial.locationComponentId;

  bool _saving = false;
  List<String> _errors = const [];

  bool get _isEdit => _initial != null;

  static String _numberText(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  @override
  void dispose() {
    for (final c in [
      _code,
      _description,
      _grade,
      _dimensions,
      _onHand,
      _reserved,
      _reorder,
      _heat,
      _certificate,
      _supplier,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _defaultStore(StockCategory type) {
    final node = defaultStoreFor(type);
    return widget.stores.where((s) => s.meshNodeId == node).firstOrNull?.id;
  }

  /// A new item follows the category with its unit and store until the user picks them.
  void _setType(StockCategory type) {
    setState(() {
      final unitWasDefault = _unit == defaultUnitFor(_type);
      final storeWasDefault = _storeId == _defaultStore(_type);
      _type = type;
      if (!_isEdit && unitWasDefault) _unit = defaultUnitFor(type);
      if (!_isEdit && storeWasDefault) _storeId = _defaultStore(type);
    });
  }

  double? _number(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? 0 : double.tryParse(t.replaceAll(',', '.'));
  }

  Future<void> _save() async {
    final numbers = {'On hand': _onHand, 'Reserved': _reserved, 'Reorder level': _reorder};
    final draft = MaterialDraft(
      projectId: widget.projectId,
      itemCode: _code.text,
      description: _description.text,
      type: _type,
      unit: _unit,
      onHand: _number(_onHand) ?? 0,
      reserved: _number(_reserved) ?? 0,
      reorderLevel: _number(_reorder) ?? 0,
      grade: _grade.text,
      dimensions: _dimensions.text,
      locationComponentId: _storeId,
      hullId: _hullId,
      heatNumber: _heat.text,
      certificateNo: _certificate.text,
      supplier: _supplier.text,
    );
    final errors = [
      for (final e in numbers.entries)
        if (_number(e.value) == null) '${e.key} is not a number.',
      ...draft.validationErrors(
        existingCodes: widget.existing.where((i) => i.id != _initial?.id).map((i) => i.itemCode),
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
      if (_isEdit) {
        await repository.updateMaterialItem(_initial!.id, draft);
      } else {
        await repository.createMaterialItem(draft);
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

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Text(
      title,
      style: const TextStyle(fontSize: 10.5, letterSpacing: 0.8, color: AppTheme.textMuted, fontWeight: FontWeight.w700),
    ),
  );

  Widget _text(TextEditingController c, String label, {String? hint, bool number = false}) => TextField(
    controller: c,
    enabled: !_saving,
    keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
    decoration: InputDecoration(labelText: label, hintText: hint),
  );

  Widget _row(List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, c) in children.indexed) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: c),
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final enabled = !_saving;
    final stores = [...widget.stores]..sort((a, b) => a.name.compareTo(b.name));
    final storeMissing = _storeId != null && !stores.any((s) => s.id == _storeId);
    return AlertDialog(
      title: Text(_isEdit ? 'Edit ${_initial!.itemCode}' : 'New stock item'),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _section('ITEM'),
              _row([
                _text(_code, 'Item code *', hint: 'e.g. PL-AH36-14-N4'),
                DropdownButtonFormField<StockCategory>(
                  initialValue: _type,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    for (final t in StockCategory.values)
                      DropdownMenuItem(
                        value: t,
                        child: Row(
                          children: [Icon(t.icon, size: 16), const SizedBox(width: 8), Text(t.label)],
                        ),
                      ),
                  ],
                  onChanged: enabled ? (v) => _setType(v ?? _type) : null,
                ),
              ]),
              _row([_text(_description, 'Description *', hint: 'e.g. Shipbuilding plate 14 mm (NB-1004)')]),
              _row([
                _text(_grade, 'Grade', hint: 'e.g. AH36'),
                _text(_dimensions, 'Dimensions', hint: 'e.g. 14 x 2500 x 12000 mm'),
              ]),
              _section('STOCK'),
              _row([
                DropdownButtonFormField<String>(
                  // Re-created when the category proposes another unit.
                  key: ValueKey('unit-$_unit'),
                  initialValue: _unit,
                  decoration: const InputDecoration(labelText: 'Unit'),
                  items: [for (final u in stockUnits) DropdownMenuItem(value: u, child: Text(u))],
                  onChanged: enabled ? (v) => setState(() => _unit = v ?? _unit) : null,
                ),
                _text(_onHand, 'On hand', number: true),
                _text(_reserved, 'Reserved (manual)', number: true),
                _text(_reorder, 'Reorder level', number: true),
              ]),
              Text(
                'Free stock = on hand − reserved (manual) − reserved for blocks'
                '${(_initial?.blockReserved ?? 0) > 0 ? ' (${_numberText(_initial!.blockReserved)} $_unit, from the block reservations)' : ''}. '
                'Below the reorder level the item is "low", below zero a "shortage" (to be ordered).',
                style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
              ),
              _section('WHERE & FOR WHOM'),
              _row([
                DropdownButtonFormField<String?>(
                  key: ValueKey('store-$_storeId'),
                  initialValue: _storeId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Stored at'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('— (not received yet)')),
                    if (storeMissing) DropdownMenuItem<String?>(value: _storeId, child: Text(_storeId!)),
                    for (final s in stores)
                      DropdownMenuItem<String?>(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: enabled ? (v) => setState(() => _storeId = v) : null,
                ),
                DropdownButtonFormField<String?>(
                  initialValue: _hullId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'For hull'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('— (general stock)')),
                    for (final h in widget.hulls)
                      DropdownMenuItem<String?>(
                        value: h.id,
                        child: Text(h.displayName, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: enabled ? (v) => setState(() => _hullId = v) : null,
                ),
              ]),
              _section('TRACEABILITY'),
              _row([
                _text(_heat, 'Heat no.'),
                _text(_certificate, 'Certificate no.', hint: 'e.g. EN10204-3.1-…'),
                _text(_supplier, 'Supplier'),
              ]),
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
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_isEdit ? 'Save changes' : 'Create item'),
        ),
      ],
    );
  }
}
