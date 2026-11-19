import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../../digital_twin/presentation/providers/twin_providers.dart';
import '../../../domain/entities/block_entities.dart';
import '../../../domain/entities/material_entities.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/entities/quality_entities.dart';
import '../../../domain/repositories/shipyard_repository.dart';
import '../../../domain/services/block_breakdown.dart';
import '../../../domain/services/block_weights.dart';
import '../../../domain/services/lift_plan.dart';
import '../../providers/shipyard_providers.dart';
import 'block_dialog.dart';

/// Block list of a hull: shows the existing blocks (delete; edit names and
/// weights) and adds new ones from the block type catalogue. The user enters
/// how many blocks of each type (port / starboard separately for sided types);
/// default codes and names are generated and can be changed before saving.
/// Saved weights are carried into the hull's `planned` erection lifts
/// ([LiftPlan.syncLoads]: load, lift window, crane). Returns a summary for a snack bar.
class BlocksDialog extends ConsumerStatefulWidget {
  const BlocksDialog({super.key, required this.projectId, required this.hulls, this.initialHullId});

  final String projectId;
  final List<Hull> hulls;
  final String? initialHullId;

  static Future<String?> show(
    BuildContext context, {
    required String projectId,
    required List<Hull> hulls,
    String? initialHullId,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocksDialog(projectId: projectId, hulls: hulls, initialHullId: initialHullId),
    );
  }

  @override
  ConsumerState<BlocksDialog> createState() => _BlocksDialogState();
}

/// Weight in tonnes as typed in the dialog (`12.5`, up to 3 decimals = kg).
String _tonnes(double? kg) {
  if (kg == null) return '';
  final s = (kg / 1000).toStringAsFixed(3);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// Hint of a weight field: the estimate that is saved when the field stays empty.
String _estimateHint(double? t) => t == null ? '—' : '≈ ${t.toStringAsFixed(1)}';

/// What the weight estimate is based on.
class _Basis extends StatelessWidget {
  const _Basis(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      '$text Empty weight fields (≈ grey) are saved with this estimate.',
      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
    ),
  );
}

/// Editable fields of one generated block (keyed by its default code) or of
/// an existing block (keyed by its component id).
class _RowFields {
  _RowFields(String code, String name, {String weight = ''})
    : code = TextEditingController(text: code),
      name = TextEditingController(text: name),
      weight = TextEditingController(text: weight);

  final TextEditingController code;
  final TextEditingController name;
  final TextEditingController weight;

  void dispose() {
    code.dispose();
    name.dispose();
    weight.dispose();
  }
}

class _BlocksDialogState extends ConsumerState<BlocksDialog> {
  late String? _hullId = widget.hulls.any((h) => h.id == widget.initialHullId)
      ? widget.initialHullId
      : (widget.hulls.where((h) => !h.isRepair).firstOrNull ?? widget.hulls.firstOrNull)?.id;

  /// Requested number of blocks per (type code, side).
  final Map<(String, BlockSide), int> _counts = {};
  final Map<String, _RowFields> _fields = {};

  /// Edit mode: fields of the existing blocks by component id.
  final Map<String, _RowFields> _editFields = {};
  bool _editing = false;
  bool _saving = false;
  String? _progress;
  String? _deletingId;
  List<String> _errors = const [];

  /// Result of the last save that the user should read before closing.
  List<String> _notices = const [];
  String? _summary;

  Hull? get _hull => widget.hulls.where((h) => h.id == _hullId).firstOrNull;

  @override
  void dispose() {
    for (final f in [..._fields.values, ..._editFields.values]) {
      f.dispose();
    }
    super.dispose();
  }

  void _startEditing(List<HullBlock> existing) {
    setState(() {
      for (final b in existing) {
        _editFields[b.componentId] = _RowFields(b.blockNo, b.name, weight: _tonnes(b.weightKg));
      }
      _editing = true;
      _errors = const [];
      _notices = const [];
    });
  }

  void _stopEditing() {
    setState(() {
      for (final f in _editFields.values) {
        f.dispose();
      }
      _editFields.clear();
      _editing = false;
      _errors = const [];
    });
  }

  /// Saves the changed names / weights, then brings the hull's planned erection
  /// lifts in line with the weights (also lifts left behind by an earlier save).
  Future<void> _saveEdits(
    Hull hull,
    List<HullBlock> existing,
    List<TwinComponent> components,
    Map<String, double> estimates,
  ) async {
    final edits = <BlockEdit>[];
    final errors = <String>[];
    var estimated = 0;
    for (final b in existing) {
      final f = _editFields[b.componentId];
      if (f == null) continue;
      final text = f.weight.text.trim();
      final typed = _weight(f);
      if (text.isNotEmpty && typed == null) {
        errors.add('Weight of block ${b.blockNo} is not a number.');
        continue;
      }
      // An empty weight field takes the estimate.
      final edit = BlockEdit(block: b, name: f.name.text, weightT: typed ?? estimates[b.componentId]);
      if (!edit.hasChanges) continue;
      errors.addAll(edit.validationErrors());
      edits.add(edit);
      if (typed == null && edit.weightChanged) estimated++;
    }
    final activities = ref.read(activitiesProvider(widget.projectId)).value;
    final bookings = ref.read(bookingsProvider(widget.projectId)).value;
    if (activities == null || bookings == null) errors.add('Schedule and bookings are still loading - try again.');
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }

    final sync = LiftPlan.syncLoads(
      hull: hull,
      activities: activities!,
      components: components,
      bookings: bookings!,
      now: DateTime.now(),
      weightKgOverrides: {
        for (final e in edits)
          if (e.weightChanged) e.block.componentId: e.weightKg,
      },
    );
    if (edits.isEmpty && sync.updates.isEmpty) {
      setState(() => _errors = ['Nothing to save: no name or weight was changed.', ...sync.warnings]);
      return;
    }

    final repo = ref.read(shipyardRepositoryProvider);
    setState(() {
      _saving = true;
      _errors = const [];
      _progress = edits.isEmpty ? null : 'Saving ${edits.length} block${edits.length == 1 ? '' : 's'}…';
    });
    try {
      await Future.wait([
        for (final e in edits) repo.updateBlock(e.block.componentId, name: e.name, weightKg: e.weightKg),
      ]);
    } on ShipyardException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _progress = null;
          _errors = [e.message];
        });
      }
      return;
    }

    var done = 0;
    try {
      for (final u in sync.updates) {
        if (!mounted) return;
        setState(() => _progress = 'Updating crane lifts ${done + 1} / ${sync.updates.length}…');
        await repo.updateBookingPlan(
          u.booking.id,
          componentId: u.componentId,
          startsAt: u.startsAt,
          endsAt: u.endsAt,
          loadT: u.loadT,
          notes: u.notes,
        );
        done++;
      }
    } on ShipyardException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _progress = null;
          _errors = [
            '${edits.length} block change${edits.length == 1 ? '' : 's'} saved, but the lift update stopped after '
                '$done of ${sync.updates.length} lifts (lift of ${sync.updates[done].blockNo}): ${e.message}',
            'Save again to update the remaining lifts.',
            ...sync.warnings,
          ];
        });
      }
      return;
    }

    final moved = sync.updates.where((u) => u.movedStart || u.movedCrane).length;
    final summary = [
      if (edits.isNotEmpty)
        '${edits.length} block${edits.length == 1 ? '' : 's'} saved'
            '${estimated == 0 ? '' : ' ($estimated weight${estimated == 1 ? '' : 's'} from the estimate)'}',
      if (sync.updates.isNotEmpty)
        '${sync.updates.length} crane lift${sync.updates.length == 1 ? '' : 's'} updated'
            '${moved == 0 ? '' : ' ($moved moved to a new window / crane)'}',
    ].join(', ');
    if (!mounted) return;
    if (sync.warnings.isEmpty) {
      Navigator.of(context).pop('$summary.');
      return;
    }
    // Keep the dialog open so the warnings can be read.
    for (final f in _editFields.values) {
      f.dispose();
    }
    setState(() {
      _editFields.clear();
      _editing = false;
      _saving = false;
      _progress = null;
      _summary = '$summary.';
      _notices = sync.warnings;
    });
  }

  void _setCount(BlockType type, BlockSide side, int value) {
    setState(() {
      _counts[(type.code, side)] = value.clamp(0, BlockBreakdown.maxPerRequest);
      _errors = const [];
    });
  }

  void _selectHull(String? id) {
    if (id == _hullId) return;
    setState(() {
      _hullId = id;
      _counts.clear();
      for (final f in [..._fields.values, ..._editFields.values]) {
        f.dispose();
      }
      _fields.clear();
      _editFields.clear();
      _editing = false;
      _errors = const [];
      _notices = const [];
      _summary = null;
    });
  }

  /// Generated drafts (default codes) for the current counts.
  List<BlockDraft> _generated(Hull hull, List<HullBlock> existing) {
    return BlockBreakdown.generate(
      projectId: widget.projectId,
      hullNo: hull.hullNo,
      requests: [
        for (final entry in _counts.entries)
          if (entry.value > 0) BlockRequest(BlockType.byCode(entry.key.$1)!, entry.key.$2, entry.value),
      ],
      existingBlockNos: existing.map((b) => b.blockNo),
      lastSequence: existing.fold<int>(
        0,
        (m, b) => b.erectionSequence > m && b.erectionSequence < 999 ? b.erectionSequence : m,
      ),
    );
  }

  _RowFields _fieldsFor(BlockDraft d) => _fields.putIfAbsent(d.blockNo, () => _RowFields(d.blockNo, d.name));

  double? _weight(_RowFields f) => double.tryParse(f.weight.text.trim().replaceAll(',', '.'));

  /// Estimate key of a generated block (existing blocks use their component id).
  static String _newKey(BlockDraft d) => 'new:${d.blockNo}';

  /// Generated drafts with the user's edits applied; an empty weight takes the estimate.
  List<BlockDraft> _edited(List<BlockDraft> generated, Map<String, double> estimates) => [
    for (final d in generated)
      d.copyWith(
        blockNo: _fieldsFor(d).code.text,
        name: _fieldsFor(d).name.text,
        weightT: _weight(_fieldsFor(d)) ?? estimates[_newKey(d)],
      ),
  ];

  Future<void> _create(List<BlockDraft> generated, List<HullBlock> existing, Map<String, double> estimates) async {
    final drafts = _edited(generated, estimates);
    final errors = [
      for (final d in generated)
        if (_fieldsFor(d).weight.text.trim().isNotEmpty && _weight(_fieldsFor(d)) == null)
          'Weight of block ${_fieldsFor(d).code.text.trim().toUpperCase()} is not a number.',
      ...BlockBreakdown.validate(drafts, existingBlockNos: existing.map((b) => b.blockNo)),
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
      await ref.read(shipyardRepositoryProvider).createBlocks(drafts);
      if (mounted) {
        Navigator.of(context).pop(
          '${drafts.length} block${drafts.length == 1 ? '' : 's'} created. Plan their schedule next (Plan).',
        );
      }
    } on ShipyardException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errors = [e.message];
        });
      }
    }
  }

  Future<void> _delete(HullBlock block) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete block ${block.blockNo}?'),
        content: const Text(
          'Its schedule rows and material reservations are deleted as well (reserved stock becomes free). '
          'Bookings, inspections, punch items and permits linked to the block stay, without the link.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _deletingId = block.componentId;
      _errors = const [];
    });
    try {
      await ref.read(shipyardRepositoryProvider).deleteBlock(block.componentId);
      ref.invalidate(reservationsProvider(widget.projectId));
      ref.invalidate(materialsProvider(widget.projectId));
    } on ShipyardException catch (e) {
      if (mounted) setState(() => _errors = [e.message]);
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final components = ref.watch(componentsProvider(widget.projectId)).value ?? const <TwinComponent>[];
    // Kept alive for the lift update after saving weights.
    ref.watch(activitiesProvider(widget.projectId));
    ref.watch(bookingsProvider(widget.projectId));
    final reserved = {
      for (final r in ref.watch(reservationsProvider(widget.projectId)).value ?? const <MaterialReservation>[])
        if (r.isOpen) r.componentId,
    };
    final inspections = ref.watch(inspectionsProvider(widget.projectId)).value ?? const <QualityInspection>[];
    final failed = {
      for (final q in inspections)
        if (q.result == InspectionResult.fail) q.componentId,
    };
    final openHold = {
      for (final q in inspections)
        if (q.isOpenHold) q.componentId,
    };
    final hull = _hull;
    final existing = hull == null ? const <HullBlock>[] : blocksOfHull(components, hull.hullNo);
    final generated = hull == null || _editing ? const <BlockDraft>[] : _generated(hull, existing);
    final estimate = hull == null
        ? null
        : BlockWeights.estimate(hull, [
            for (final b in existing) (b.componentId, b.type, b.side),
            for (final d in generated) (_newKey(d), d.type, d.side),
          ]);
    final estimates = estimate?.blockT ?? const <String, double>{};
    final weighed = existing.where((b) => b.weightKg != null && b.weightKg! > 0).toList();
    final totalT = weighed.fold<double>(0, (s, b) => s + b.weightKg!) / 1000;

    return AlertDialog(
      title: Text(hull == null ? 'Hull blocks' : 'Blocks of ${hull.displayName}'),
      content: SizedBox(
        width: 900,
        child: widget.hulls.isEmpty
            ? const Text('Create a hull first (Production → New hull).')
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey(_hullId),
                      initialValue: _hullId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Hull'),
                      items: [
                        for (final h in widget.hulls)
                          DropdownMenuItem(
                            value: h.id,
                            child: Text(h.displayName, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: _saving || _editing ? null : _selectHull,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _Section(
                            'EXISTING BLOCKS (${existing.length})'
                            '${weighed.isEmpty ? '' : '  ·  ${totalT.toStringAsFixed(1)} t steel, '
                                      '${weighed.length} of ${existing.length} weighed'}',
                          ),
                        ),
                        if (existing.isNotEmpty && !_editing)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: TextButton.icon(
                              onPressed: _saving || _deletingId != null ? null : () => _startEditing(existing),
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              label: const Text('Edit names / weights'),
                            ),
                          ),
                      ],
                    ),
                    if (_summary != null) _Notices(summary: _summary!, lines: _notices),
                    if (existing.isEmpty)
                      const Text(
                        'No blocks yet. Enter below how many blocks of each type the hull has.',
                        style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                      )
                    else if (_editing)
                      _ExistingEditor(
                        blocks: existing,
                        fieldsFor: (b) => _editFields[b.componentId],
                        estimates: estimates,
                        basis: estimate?.basis,
                        enabled: !_saving,
                        onUseEstimates: () {
                          for (final f in _editFields.values) {
                            f.weight.clear();
                          }
                          setState(() => _errors = const []);
                        },
                      )
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final b in existing)
                            Tooltip(
                              message: '${b.name}\nTap for materials and inspections',
                              child: InputChip(
                                label: Text(b.blockNo),
                                visualDensity: VisualDensity.compact,
                                avatar: failed.contains(b.componentId)
                                    ? const Icon(Icons.error_outline, size: 14, color: Color(0xFFEF4444))
                                    : openHold.contains(b.componentId)
                                    ? const Icon(Icons.pan_tool_outlined, size: 13, color: Color(0xFFF59E0B))
                                    : reserved.contains(b.componentId)
                                    ? const Icon(Icons.inventory_2_outlined, size: 14, color: AppTheme.accent)
                                    : null,
                                onPressed: _saving || _deletingId != null
                                    ? null
                                    : () => BlockDialog.show(
                                        context,
                                        projectId: widget.projectId,
                                        block: b,
                                        hull: hull,
                                      ),
                                onDeleted: _saving || _deletingId != null ? null : () => _delete(b),
                                deleteIcon: _deletingId == b.componentId
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.close, size: 16),
                                deleteButtonTooltipMessage: 'Delete ${b.blockNo}',
                              ),
                            ),
                        ],
                      ),
                    if (!_editing) ...[
                      const _Section('ADD BLOCKS - number of blocks per type'),
                      _Catalog(counts: _counts, enabled: !_saving, onChanged: _setCount),
                      _Section('NEW BLOCKS (${generated.length})'),
                      if (generated.isEmpty)
                        const Text(
                          'Default codes follow the zone numbering: 1xx bottom, 2xx side, 3xx engine room, 4xx decks, '
                          '5xx fore, 6xx superstructure, 7xx aft, 8xx bulkheads; P / S = port / starboard. '
                          'Codes and names can be changed before saving.',
                          style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                        )
                      else ...[
                        if (estimate != null) _Basis(estimate.basis),
                        _Preview(
                          drafts: generated,
                          fieldsFor: _fieldsFor,
                          estimateOf: (d) => estimates[_newKey(d)],
                          enabled: !_saving,
                        ),
                      ],
                    ],
                    if (_errors.isNotEmpty) _Problems(lines: _errors),
                  ],
                ),
              ),
      ),
      actions: [
        if (_progress != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(_progress!, style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted)),
          ),
        if (_editing) ...[
          TextButton(onPressed: _saving ? null : _stopEditing, child: const Text('Back')),
          FilledButton(
            onPressed: _saving || hull == null ? null : () => _saveEdits(hull, existing, components, estimates),
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save changes'),
          ),
        ] else
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(_summary),
            child: Text(generated.isEmpty ? 'Close' : 'Cancel'),
          ),
        if (hull != null && generated.isNotEmpty)
          FilledButton(
            onPressed: _saving ? null : () => _create(generated, existing, estimates),
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Create ${generated.length} block${generated.length == 1 ? '' : 's'}'),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 6),
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
}

/// Block type catalogue grouped by zone, with a counter per type and side.
class _Catalog extends StatelessWidget {
  const _Catalog({required this.counts, required this.enabled, required this.onChanged});

  final Map<(String, BlockSide), int> counts;
  final bool enabled;
  final void Function(BlockType type, BlockSide side, int value) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final zone in BlockZone.values) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 2),
            child: Text(
              '${zone.label}  ·  ${zone.series}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.accent),
            ),
          ),
          for (final type in blockTypeCatalog.where((t) => t.zone == zone))
            Container(
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.outline)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 46,
                    child: Text(type.code, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(type.label, style: const TextStyle(fontSize: 12.5)),
                        Text(
                          type.description,
                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  for (final side
                      in type.sided ? const [BlockSide.port, BlockSide.starboard] : const [BlockSide.centre])
                    _Counter(
                      key: ValueKey('${type.code}-${side.name}'),
                      label: type.sided ? side.shortLabel : null,
                      value: counts[(type.code, side)] ?? 0,
                      enabled: enabled,
                      onChanged: (v) => onChanged(type, side, v),
                    ),
                  if (!type.sided) const SizedBox(width: _Counter.width),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// `[-] n [+]` with an optional side label; the number can also be typed.
class _Counter extends StatefulWidget {
  const _Counter({super.key, required this.value, required this.onChanged, required this.enabled, this.label});

  static const width = 128.0;

  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;
  final String? label;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  late final _controller = TextEditingController(text: widget.value == 0 ? '' : '${widget.value}');

  @override
  void didUpdateWidget(_Counter old) {
    super.didUpdateWidget(old);
    final text = widget.value == 0 ? '' : '${widget.value}';
    if (int.tryParse(_controller.text) != widget.value && _controller.text != text) _controller.text = text;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _step(int delta) {
    final next = (widget.value + delta).clamp(0, BlockBreakdown.maxPerRequest);
    _controller.text = next == 0 ? '' : '$next';
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.value > 0;
    return SizedBox(
      width: _Counter.width,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (widget.label != null)
            SizedBox(
              width: 24,
              child: Text(
                widget.label!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: active ? AppTheme.accent : AppTheme.textMuted,
                ),
              ),
            ),
          IconButton(
            tooltip: 'One less',
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            onPressed: widget.enabled && active ? () => _step(-1) : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 30,
            child: TextField(
              controller: _controller,
              enabled: widget.enabled,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                isDense: true,
                hintText: '0',
                contentPadding: EdgeInsets.symmetric(vertical: 6),
              ),
              onChanged: (t) => widget.onChanged(int.tryParse(t) ?? 0),
            ),
          ),
          IconButton(
            tooltip: 'One more',
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            onPressed: widget.enabled && widget.value < BlockBreakdown.maxPerRequest ? () => _step(1) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

/// Generated blocks with editable code, name and weight.
class _Preview extends StatelessWidget {
  const _Preview({required this.drafts, required this.fieldsFor, required this.estimateOf, required this.enabled});

  final List<BlockDraft> drafts;
  final _RowFields Function(BlockDraft) fieldsFor;
  final double? Function(BlockDraft) estimateOf;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted);
    const dense = InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            SizedBox(width: 34, child: Text('#', style: head)),
            SizedBox(width: 120, child: Text('CODE', style: head)),
            SizedBox(width: 8),
            Expanded(child: Text('NAME', style: head)),
            SizedBox(width: 8),
            SizedBox(width: 84, child: Text('WEIGHT t', style: head)),
          ],
        ),
        for (final d in drafts)
          Padding(
            key: ValueKey(d.blockNo),
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  child: Text('${d.erectionSequence}', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                ),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: fieldsFor(d).code,
                    enabled: enabled,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                    decoration: dense,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: fieldsFor(d).name,
                    enabled: enabled,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: dense,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 84,
                  child: TextField(
                    controller: fieldsFor(d).weight,
                    enabled: enabled,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontSize: 12.5),
                    decoration: dense.copyWith(hintText: _estimateHint(estimateOf(d))),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Existing blocks in erection order with editable name and weight (the code is fixed).
class _ExistingEditor extends StatelessWidget {
  const _ExistingEditor({
    required this.blocks,
    required this.fieldsFor,
    required this.estimates,
    required this.basis,
    required this.enabled,
    required this.onUseEstimates,
  });

  final List<HullBlock> blocks;
  final _RowFields? Function(HullBlock) fieldsFor;

  /// Estimated weight (t) by component id.
  final Map<String, double> estimates;
  final String? basis;
  final bool enabled;
  final VoidCallback onUseEstimates;

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted);
    const dense = InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Weights in tonnes (steel weight of the erected block). Saving also updates the planned erection lifts '
          'of these blocks: load, lift window length and - if the block is too heavy - the crane. '
          'Stage days of schedule rows drafted afterwards follow the weight.',
          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
        const SizedBox(height: 6),
        if (basis != null) ...[
          _Basis(basis!),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: enabled ? onUseEstimates : null,
              icon: const Icon(Icons.auto_fix_high_outlined, size: 16),
              label: const Text('Use estimates for all'),
            ),
          ),
        ] else
          const Text(
            'Enter length and beam of the hull to get estimated weights.',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
        const SizedBox(height: 4),
        const Row(
          children: [
            SizedBox(width: 34, child: Text('#', style: head)),
            SizedBox(width: 96, child: Text('CODE', style: head)),
            SizedBox(width: 8),
            Expanded(child: Text('NAME', style: head)),
            SizedBox(width: 8),
            SizedBox(width: 84, child: Text('WEIGHT t', style: head)),
          ],
        ),
        for (final b in blocks)
          if (fieldsFor(b) case final f?)
            Padding(
              key: ValueKey(b.componentId),
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 34,
                    child: Text(
                      b.erectionSequence >= 999 ? '–' : '${b.erectionSequence}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ),
                  SizedBox(
                    width: 96,
                    child: Text(b.blockNo, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: f.name,
                      enabled: enabled,
                      style: const TextStyle(fontSize: 12.5),
                      decoration: dense,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 84,
                    child: TextField(
                      controller: f.weight,
                      enabled: enabled,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(fontSize: 12.5),
                      decoration: dense.copyWith(hintText: _estimateHint(estimates[b.componentId])),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

/// Outcome of a save with notes on lifts that were left unchanged.
class _Notices extends StatelessWidget {
  const _Notices({required this.summary, required this.lines});

  final String summary;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFF422006), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(summary, style: const TextStyle(color: Color(0xFFFDE68A), fontSize: 12.5, fontWeight: FontWeight.w700)),
          for (final l in lines) Text('• $l', style: const TextStyle(color: Color(0xFFFDE68A), fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _Problems extends StatelessWidget {
  const _Problems({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFF450A0A), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in lines) Text('• $l', style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12.5)),
        ],
      ),
    );
  }
}
