import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../../digital_twin/presentation/providers/twin_providers.dart';
import '../../../domain/entities/block_entities.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/repositories/shipyard_repository.dart';
import '../../../domain/services/block_breakdown.dart';
import '../../providers/shipyard_providers.dart';

/// Block list of a hull: shows the existing blocks (delete) and adds new ones
/// from the block type catalogue. The user enters how many blocks of each type
/// (port / starboard separately for sided types); default codes and names are
/// generated and can be changed before saving. Returns the number of created blocks.
class BlocksDialog extends ConsumerStatefulWidget {
  const BlocksDialog({super.key, required this.projectId, required this.hulls, this.initialHullId});

  final String projectId;
  final List<Hull> hulls;
  final String? initialHullId;

  static Future<int?> show(
    BuildContext context, {
    required String projectId,
    required List<Hull> hulls,
    String? initialHullId,
  }) {
    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocksDialog(projectId: projectId, hulls: hulls, initialHullId: initialHullId),
    );
  }

  @override
  ConsumerState<BlocksDialog> createState() => _BlocksDialogState();
}

/// Editable fields of one generated block, keyed by its default code.
class _RowFields {
  _RowFields(String code, String name)
    : code = TextEditingController(text: code),
      name = TextEditingController(text: name);

  final TextEditingController code;
  final TextEditingController name;
  final TextEditingController weight = TextEditingController();

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
  bool _saving = false;
  String? _deletingId;
  List<String> _errors = const [];

  Hull? get _hull => widget.hulls.where((h) => h.id == _hullId).firstOrNull;

  @override
  void dispose() {
    for (final f in _fields.values) {
      f.dispose();
    }
    super.dispose();
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
      for (final f in _fields.values) {
        f.dispose();
      }
      _fields.clear();
      _errors = const [];
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

  /// Generated drafts with the user's edits applied.
  List<BlockDraft> _edited(List<BlockDraft> generated) => [
    for (final d in generated)
      d.copyWith(blockNo: _fieldsFor(d).code.text, name: _fieldsFor(d).name.text, weightT: _weight(_fieldsFor(d))),
  ];

  Future<void> _create(List<BlockDraft> generated, List<HullBlock> existing) async {
    final drafts = _edited(generated);
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
      if (mounted) Navigator.of(context).pop(drafts.length);
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
          'Its schedule rows are deleted as well. Bookings, inspections, punch items and permits '
          'linked to the block stay, without the link.',
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
    } on ShipyardException catch (e) {
      if (mounted) setState(() => _errors = [e.message]);
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final components = ref.watch(componentsProvider(widget.projectId)).value ?? const <TwinComponent>[];
    final hull = _hull;
    final existing = hull == null ? const <HullBlock>[] : blocksOfHull(components, hull.hullNo);
    final generated = hull == null ? const <BlockDraft>[] : _generated(hull, existing);

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
                      onChanged: _saving ? null : _selectHull,
                    ),
                    _Section('EXISTING BLOCKS (${existing.length})'),
                    if (existing.isEmpty)
                      const Text(
                        'No blocks yet. Enter below how many blocks of each type the hull has.',
                        style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                      )
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final b in existing)
                            Tooltip(
                              message: b.name,
                              child: InputChip(
                                label: Text(b.blockNo),
                                visualDensity: VisualDensity.compact,
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
                    else
                      _Preview(drafts: generated, fieldsFor: _fieldsFor, enabled: !_saving),
                    if (_errors.isNotEmpty) _Problems(lines: _errors),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(generated.isEmpty ? 'Close' : 'Cancel'),
        ),
        if (hull != null && generated.isNotEmpty)
          FilledButton(
            onPressed: _saving ? null : () => _create(generated, existing),
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
  const _Preview({required this.drafts, required this.fieldsFor, required this.enabled});

  final List<BlockDraft> drafts;
  final _RowFields Function(BlockDraft) fieldsFor;
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
                    decoration: dense.copyWith(hintText: 'optional'),
                  ),
                ),
              ],
            ),
          ),
      ],
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
