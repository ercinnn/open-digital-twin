import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../../digital_twin/presentation/providers/twin_providers.dart';
import '../../../domain/entities/material_entities.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/repositories/shipyard_repository.dart';
import '../../../domain/services/outfitting_materials.dart';
import '../../providers/shipyard_providers.dart';

String _qty(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Drafts the warehouse material of a hull's afloat outfitting work packages
/// ([OutfittingMaterialPlan]) after a preview: one reservation per package and
/// stock item, needed at the package start. Returns a summary.
class OutfittingMaterialDialog extends ConsumerStatefulWidget {
  const OutfittingMaterialDialog({super.key, required this.projectId, required this.hulls, this.initialHullId});

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
      builder: (_) => OutfittingMaterialDialog(projectId: projectId, hulls: hulls, initialHullId: initialHullId),
    );
  }

  @override
  ConsumerState<OutfittingMaterialDialog> createState() => _OutfittingMaterialDialogState();
}

class _OutfittingMaterialDialogState extends ConsumerState<OutfittingMaterialDialog> {
  String? _hullId;
  bool _saving = false;
  String? _error;

  Future<void> _save(OutfittingMaterialResult plan) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(shipyardRepositoryProvider).createReservations(plan.drafts);
      ref.invalidate(reservationsProvider(widget.projectId));
      ref.invalidate(materialsProvider(widget.projectId));
      final packages = plan.drafts.map((d) => d.activityId).toSet().length;
      if (mounted) {
        Navigator.of(context).pop(
          '${plan.drafts.length} reservation${plan.drafts.length == 1 ? '' : 's'} for $packages '
          'work package${packages == 1 ? '' : 's'} created.',
        );
      }
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
    final projectId = widget.projectId;
    final components = ref.watch(componentsProvider(projectId)).value ?? const <TwinComponent>[];
    final itemsAsync = ref.watch(materialsProvider(projectId));
    final reservationsAsync = ref.watch(reservationsProvider(projectId));
    final activities = ref.watch(activitiesProvider(projectId)).value ?? const <ProductionActivity>[];
    final items = itemsAsync.value ?? const <MaterialItem>[];
    final loading = !itemsAsync.hasValue || !reservationsAsync.hasValue;
    final candidates = widget.hulls
        .where((h) => activities.any((a) => a.hullId == h.id && a.workPackage != null))
        .toList();
    final current = _hullId ?? widget.initialHullId;
    final hull = candidates.where((h) => h.id == current).firstOrNull ?? candidates.firstOrNull;
    final plan = hull == null || loading
        ? null
        : OutfittingMaterialPlan.forHull(
            hull: hull,
            activities: activities,
            items: items,
            reservations: reservationsAsync.value!,
            componentIdByNode: {for (final c in components) c.meshNodeId: c.id},
          );
    final itemsById = {for (final i in items) i.id: i};
    final rowsById = {for (final a in activities) a.id: a};
    // Demand of this draft per item, to show the free stock afterwards.
    final demand = <String, double>{};
    for (final d in plan?.drafts ?? const <ReservationDraft>[]) {
      demand[d.itemId!] = (demand[d.itemId!] ?? 0) + d.quantity;
    }
    const head = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted);
    const cell = TextStyle(fontSize: 12);

    return AlertDialog(
      title: const Text('Reserve outfitting material'),
      content: SizedBox(
        width: 700,
        child: candidates.isEmpty
            ? const Text(
                'No hull has afloat outfitting work packages yet. Plan them first '
                '(Production > Plan > Outfitting work packages).',
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey(hull?.id),
                      initialValue: hull?.id,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Hull', helperText: 'Hulls with work packages.'),
                      items: [
                        for (final h in candidates)
                          DropdownMenuItem(
                            value: h.id,
                            child: Text(h.displayName, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: _saving ? null : (v) => setState(() => _hullId = v),
                    ),
                    const SizedBox(height: 12),
                    if (loading)
                      const Center(child: CircularProgressIndicator())
                    else if (plan != null && plan.drafts.isEmpty && plan.warnings.isEmpty)
                      const Text(
                        'Every open work package already has its material reserved.',
                        style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                      )
                    else if (plan != null) ...[
                      const Text(
                        'Typical warehouse items per work package, quantities scaled by the hull size. Each package '
                        'gets one reservation per item, needed at its start; issue it in the package dialog '
                        '(Production: tap a package bar). A package cannot be reported finished before its material '
                        'is issued.',
                        style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                      ),
                      const SizedBox(height: 8),
                      Table(
                        columnWidths: const {
                          0: FlexColumnWidth(1.6),
                          1: FlexColumnWidth(2.4),
                          2: FixedColumnWidth(90),
                          3: FixedColumnWidth(86),
                          4: FixedColumnWidth(90),
                        },
                        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                        children: [
                          const TableRow(
                            children: [
                              Padding(
                                padding: EdgeInsets.only(bottom: 4),
                                child: Text('PACKAGE', style: head),
                              ),
                              Text('ITEM', style: head),
                              Text('QUANTITY', style: head, textAlign: TextAlign.end),
                              Text('  NEEDED BY', style: head),
                              Text('FREE AFTER', style: head, textAlign: TextAlign.end),
                            ],
                          ),
                          for (final d in plan.drafts)
                            TableRow(
                              decoration: const BoxDecoration(
                                border: Border(top: BorderSide(color: AppTheme.outline)),
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Text(
                                    rowsById[d.activityId]?.workPackage?.label ?? '—',
                                    style: cell,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '${itemsById[d.itemId]?.itemCode} · ${itemsById[d.itemId]?.description}',
                                  style: cell,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${_qty(d.quantity)} ${itemsById[d.itemId]?.unit ?? ''}',
                                  style: cell,
                                  textAlign: TextAlign.end,
                                ),
                                Text('  ${formatDate(d.neededBy)}', style: cell),
                                _free(itemsById[d.itemId], demand[d.itemId] ?? 0),
                              ],
                            ),
                        ],
                      ),
                      if (plan.warnings.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF422006),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final w in plan.warnings)
                                Text('• $w', style: const TextStyle(color: Color(0xFFFDE68A), fontSize: 12.5)),
                            ],
                          ),
                        ),
                    ],
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text('Not reserved: $_error', style: const TextStyle(color: Color(0xFFFCA5A5))),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        if (plan != null && plan.drafts.isNotEmpty)
          FilledButton(
            onPressed: _saving ? null : () => _save(plan),
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Reserve ${plan.drafts.length} item${plan.drafts.length == 1 ? '' : 's'}'),
          ),
      ],
    );
  }

  /// Free stock of [item] after this draft (negative = shortage, orange).
  Widget _free(MaterialItem? item, double demand) {
    if (item == null) return const SizedBox.shrink();
    final free = item.available - demand;
    return Text(
      '${_qty(free)} ${item.unit}',
      textAlign: TextAlign.end,
      style: TextStyle(fontSize: 12, color: free < 0 ? const Color(0xFFF59E0B) : null),
    );
  }
}
