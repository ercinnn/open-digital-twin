import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../auth/presentation/providers/auth_providers.dart';
import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../../digital_twin/presentation/providers/twin_providers.dart';
import '../../../domain/entities/material_entities.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/entities/work_scope.dart';
import '../../../domain/repositories/shipyard_repository.dart';
import '../../providers/shipyard_providers.dart';
import '../date_field.dart';

String _qty(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

double? _parse(String text) => double.tryParse(text.trim().replaceAll(',', '.'));

/// Material reserved for one hull block or afloat outfitting work package (tab
/// of the block / package dialog): reserve stock items, change the quantity /
/// needed-by date, issue to the shop or on board (stock goes down) or delete.
class BlockMaterialsPanel extends ConsumerStatefulWidget {
  const BlockMaterialsPanel({super.key, required this.projectId, required this.scope, this.hullId});

  final String projectId;
  final WorkScope scope;
  final String? hullId;

  @override
  ConsumerState<BlockMaterialsPanel> createState() => _BlockMaterialsPanelState();
}

class _BlockMaterialsPanelState extends ConsumerState<BlockMaterialsPanel> {
  String? _itemId;
  final _quantity = TextEditingController();
  DateTime? _neededBy;
  bool _neededByTouched = false;
  String? _busyId;
  bool _adding = false;
  List<String> _errors = const [];

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(reservationsProvider(widget.projectId));
    ref.invalidate(materialsProvider(widget.projectId));
  }

  /// Start of the first schedule row of the block / package.
  DateTime? _firstStart(List<ProductionActivity> activities) {
    DateTime? first;
    for (final a in activities.where(widget.scope.ownsRow)) {
      if (first == null || a.plannedStart.isBefore(first)) first = dateOnly(a.plannedStart);
    }
    return first;
  }

  Future<void> _run(String busyId, Future<void> Function(ShipyardRepository repo) action) async {
    setState(() {
      _busyId = busyId;
      _errors = const [];
    });
    try {
      await action(ref.read(shipyardRepositoryProvider));
      _refresh();
    } on ShipyardException catch (e) {
      if (mounted) setState(() => _errors = [e.message]);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _add(List<MaterialReservation> mine, DateTime? defaultNeededBy, String? componentId) async {
    final draft = ReservationDraft(
      projectId: widget.projectId,
      itemId: _itemId,
      componentId: componentId,
      hullId: widget.hullId,
      activityId: widget.scope.activityId,
      quantity: _parse(_quantity.text) ?? 0,
      neededBy: _neededByTouched ? _neededBy : defaultNeededBy,
    );
    final errors = draft.validationErrors(openItemIds: mine.where((r) => r.isOpen).map((r) => r.itemId));
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    setState(() {
      _adding = true;
      _errors = const [];
    });
    try {
      await ref.read(shipyardRepositoryProvider).createReservations([draft]);
      _refresh();
      if (mounted) {
        setState(() {
          _itemId = null;
          _quantity.clear();
        });
      }
    } on ShipyardException catch (e) {
      if (mounted) setState(() => _errors = [e.message]);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _edit(MaterialReservation r, MaterialItem? item) async {
    final quantity = TextEditingController(text: _qty(r.quantity));
    var neededBy = r.neededBy;
    String? error;
    final saved = await showDialog<(double, DateTime?)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: Text('${item?.itemCode ?? 'Item'} for ${widget.scope.code}'),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: quantity,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Quantity (${item?.unit ?? ''})'),
                ),
                const SizedBox(height: 10),
                DateField(
                  label: 'Needed by',
                  value: neededBy,
                  initial: neededBy ?? ref.read(todayProvider),
                  enabled: true,
                  onChanged: (v) => setLocal(() => neededBy = v),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(error!, style: const TextStyle(color: Color(0xFFFCA5A5))),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final q = _parse(quantity.text);
                if (q == null || q <= 0) {
                  setLocal(() => error = 'Enter a quantity above 0.');
                  return;
                }
                Navigator.of(dialogContext).pop((q, neededBy));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    quantity.dispose();
    if (saved == null || !mounted) return;
    await _run(r.id, (repo) => repo.updateReservation(r.id, quantity: saved.$1, neededBy: saved.$2));
  }

  Future<void> _issue(MaterialReservation r, MaterialItem? item) async {
    final unit = item?.unit ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Issue ${_qty(r.quantity)} $unit ${item?.itemCode ?? ''}?'),
        content: Text(
          'Hands the material out for ${widget.scope.code}: stock on hand goes down by ${_qty(r.quantity)} $unit '
          'and the trace history records "issued". An issued reservation cannot be changed.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Issue')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(r.id, (repo) => repo.issueReservation(r.id));
  }

  @override
  Widget build(BuildContext context) {
    final projectId = widget.projectId;
    final reservations = ref.watch(reservationsProvider(projectId));
    final items = ref.watch(materialsProvider(projectId)).value ?? const <MaterialItem>[];
    final activities = ref.watch(activitiesProvider(projectId)).value ?? const <ProductionActivity>[];
    final canEdit = ref.watch(isEditorProvider);
    final today = ref.watch(todayProvider);
    final itemsById = {for (final i in items) i.id: i};
    final components = ref.watch(componentsProvider(projectId)).value ?? const <TwinComponent>[];
    final componentId = widget.scope.componentIdIn({for (final c in components) c.meshNodeId: c.id});
    final mine =
        (reservations.value ?? const <MaterialReservation>[])
            .where(widget.scope.ownsReservation)
            .toList()
          ..sort((a, b) {
            if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
            return (itemsById[a.itemId]?.itemCode ?? '').compareTo(itemsById[b.itemId]?.itemCode ?? '');
          });
    final defaultNeededBy = _firstStart(activities);
    final selected = itemsById[_itemId];
    final busy = _busyId != null || _adding;
    final block = widget.scope.block;
    final weight = block?.weightKg;
    final package = widget.scope.package;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            [
              block?.name ?? package?.scope ?? widget.scope.code,
              if (weight != null && weight > 0) '${(weight / 1000).toStringAsFixed(1)} t steel',
              if (defaultNeededBy != null)
                '${block != null ? 'first shop stage' : 'package starts'} ${formatDate(defaultNeededBy)}',
            ].join(' · '),
            style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 10),
          if (reservations.isLoading && !reservations.hasValue)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (reservations.hasError)
            Text('Could not load reservations: ${reservations.error}', style: const TextStyle(color: Color(0xFFFCA5A5)))
          else if (mine.isEmpty)
            Text(
              block != null
                  ? 'Nothing reserved for this block yet. Materials → "Reserve steel" drafts plates and '
                        'profiles from the block weights; other items can be added below.'
                  : 'Nothing reserved for this work package yet. Materials → "Reserve outfitting" drafts the '
                        'typical warehouse items of the packages; other items can be added below. The package '
                        'cannot be reported finished while a reservation is not issued.',
              style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
            )
          else
            for (final r in mine) _row(r, itemsById[r.itemId], canEdit, busy, today),
          if (canEdit) ...[
            const SizedBox(height: 14),
            const Text(
              'RESERVE STOCK',
              style: TextStyle(
                fontSize: 10.5,
                letterSpacing: 0.8,
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('item-$_itemId'),
                    initialValue: _itemId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Stock item'),
                    items: [
                      for (final i in [...items]..sort((a, b) => a.itemCode.compareTo(b.itemCode)))
                        DropdownMenuItem(
                          value: i.id,
                          child: Text(
                            '${i.itemCode} · ${i.description} (${_qty(i.available)} ${i.unit} free)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: busy ? null : (v) => setState(() => _itemId = v),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _quantity,
                    enabled: !busy,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(labelText: 'Quantity', suffixText: selected?.unit),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 150,
                  child: DateField(
                    label: 'Needed by',
                    value: _neededByTouched ? _neededBy : defaultNeededBy,
                    initial: (_neededByTouched ? _neededBy : defaultNeededBy) ?? today,
                    enabled: !busy,
                    onChanged: (v) => setState(() {
                      _neededBy = v;
                      _neededByTouched = true;
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: FilledButton.tonal(
                    onPressed: busy ? null : () => _add(mine, defaultNeededBy, componentId),
                    child: _adding
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Reserve'),
                  ),
                ),
              ],
            ),
            if (selected != null && (_parse(_quantity.text) ?? 0) > selected.available)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'More than the free stock (${_qty(selected.available)} ${selected.unit}): '
                  'the item becomes a shortage to order.',
                  style: const TextStyle(fontSize: 12, color: Color(0xFFF59E0B)),
                ),
              ),
          ],
          if (_errors.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFF450A0A), borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final l in _errors)
                    Text('• $l', style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12.5)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(MaterialReservation r, MaterialItem? item, bool canEdit, bool busy, DateTime today) {
    final unit = item?.unit ?? '';
    final due = r.isDue(today);
    final statusColor = r.isOpen ? (due ? const Color(0xFFF59E0B) : AppTheme.accent) : const Color(0xFF22C55E);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.outline)),
      ),
      child: Row(
        children: [
          Icon(item?.type.icon ?? Icons.inventory_2_outlined, size: 18, color: statusColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item?.itemCode ?? 'Deleted item'} · ${item?.description ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5),
                ),
                Text(
                  [
                    r.isOpen
                        ? 'reserved${r.neededBy == null ? '' : ', needed by ${formatDate(r.neededBy)}'}${due ? ' (due)' : ''}'
                        : 'issued ${r.issuedAt == null ? '' : formatDate(r.issuedAt)}',
                    if (r.notes != null) r.notes!,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: due ? const Color(0xFFF59E0B) : AppTheme.textMuted),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              '${_qty(r.quantity)} $unit',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
          if (_busyId == r.id)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (canEdit && r.isOpen) ...[
            IconButton(
              tooltip: 'Change quantity / date',
              visualDensity: VisualDensity.compact,
              onPressed: busy ? null : () => _edit(r, item),
              icon: const Icon(Icons.edit_outlined, size: 17),
            ),
            IconButton(
              tooltip: 'Issue to the shop',
              visualDensity: VisualDensity.compact,
              onPressed: busy ? null : () => _issue(r, item),
              icon: const Icon(Icons.output, size: 17),
            ),
            IconButton(
              tooltip: 'Delete reservation',
              visualDensity: VisualDensity.compact,
              onPressed: busy ? null : () => _run(r.id, (repo) => repo.deleteReservation(r.id)),
              icon: const Icon(Icons.delete_outline, size: 17),
            ),
          ] else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}
