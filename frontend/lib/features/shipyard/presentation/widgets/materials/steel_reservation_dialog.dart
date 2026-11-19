import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../../digital_twin/presentation/providers/twin_providers.dart';
import '../../../domain/entities/block_entities.dart';
import '../../../domain/entities/material_entities.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/repositories/shipyard_repository.dart';
import '../../../domain/services/block_materials.dart';
import '../../../domain/services/block_weights.dart';
import '../../providers/shipyard_providers.dart';

String _qty(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Drafts the steel reservations of a hull's blocks ([SteelReservationPlan]):
/// plates per steel grade and profiles from the block weights (estimates for
/// blocks without one), needed at each block's first shop stage. Blocks that
/// already have a reservation of an item are skipped. Returns a summary.
class SteelReservationDialog extends ConsumerStatefulWidget {
  const SteelReservationDialog({super.key, required this.projectId, required this.hulls, this.initialHullId});

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
      builder: (_) => SteelReservationDialog(projectId: projectId, hulls: hulls, initialHullId: initialHullId),
    );
  }

  @override
  ConsumerState<SteelReservationDialog> createState() => _SteelReservationDialogState();
}

/// Choice "no item" in the dropdowns.
const _none = '';

class _SteelReservationDialogState extends ConsumerState<SteelReservationDialog> {
  String? _hullId;

  /// User choice per grade (item id, [_none] = no plates); absent = default.
  final Map<String, String> _plateChoice = {};
  String? _profileChoice;
  bool _saving = false;
  List<String> _errors = const [];

  List<Hull> _hullsWithBlocks(List<TwinComponent> components) =>
      widget.hulls.where((h) => blocksOfHull(components, h.hullNo).isNotEmpty).toList();

  String? _effectiveHullId(List<Hull> candidates) {
    final current = _hullId ?? widget.initialHullId;
    if (candidates.any((h) => h.id == current)) return current;
    return candidates.firstOrNull?.id;
  }

  Future<void> _save(SteelReservationResult plan) async {
    setState(() {
      _saving = true;
      _errors = const [];
    });
    try {
      await ref.read(shipyardRepositoryProvider).createReservations(plan.drafts);
      ref.invalidate(reservationsProvider(widget.projectId));
      ref.invalidate(materialsProvider(widget.projectId));
      final blocks = plan.drafts.map((d) => d.componentId).toSet().length;
      if (mounted) {
        Navigator.of(context).pop(
          '${plan.drafts.length} reservation${plan.drafts.length == 1 ? '' : 's'} for $blocks '
          'block${blocks == 1 ? '' : 's'} created.',
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

  @override
  Widget build(BuildContext context) {
    final projectId = widget.projectId;
    final components = ref.watch(componentsProvider(projectId)).value ?? const <TwinComponent>[];
    final itemsAsync = ref.watch(materialsProvider(projectId));
    final reservationsAsync = ref.watch(reservationsProvider(projectId));
    final activities = ref.watch(activitiesProvider(projectId)).value ?? const <ProductionActivity>[];
    final items = itemsAsync.value ?? const <MaterialItem>[];
    final itemsById = {for (final i in items) i.id: i};
    final loading = !itemsAsync.hasValue || !reservationsAsync.hasValue;

    final candidates = _hullsWithBlocks(components);
    final hullId = _effectiveHullId(candidates);
    final hull = candidates.where((h) => h.id == hullId).firstOrNull;
    final blocks = hull == null ? const <HullBlock>[] : blocksOfHull(components, hull.hullNo);
    final estimate = hull == null
        ? null
        : BlockWeights.estimate(hull, [for (final b in blocks) (b.componentId, b.type, b.side)]);
    final grades = {for (final b in blocks) SteelReservationPlan.gradeOf(b.type)}.toList()..sort();
    final plates = SteelReservationPlan.candidates(items, StockCategory.plate);
    final profiles = SteelReservationPlan.candidates(items, StockCategory.profile);

    final plateByGrade = <String, MaterialItem>{};
    for (final g in grades) {
      final choice = _plateChoice[g];
      final item = choice == null ? SteelReservationPlan.defaultPlate(items, g) : itemsById[choice];
      if (item != null) plateByGrade[g] = item;
    }
    final profile = _profileChoice == null ? SteelReservationPlan.defaultProfile(items) : itemsById[_profileChoice];

    final plan = hull == null || loading
        ? null
        : SteelReservationPlan.draft(
            hull: hull,
            blocks: blocks,
            estimatesT: estimate?.blockT ?? const {},
            activities: activities,
            plateByGrade: plateByGrade,
            profile: profile,
            existing: reservationsAsync.value!,
          );
    final shortages = plan == null
        ? const <MaterialItem, double>{}
        : SteelReservationPlan.shortages(items, plan.totalByItem);
    final steelT = plan?.needs.fold<double>(0, (s, n) => s + n.weightT) ?? 0;
    final estimated = plan?.needs.where((n) => n.estimated).length ?? 0;

    Widget itemDropdown({
      required String label,
      required String? value,
      required List<MaterialItem> options,
      required ValueChanged<String> onChanged,
    }) => DropdownButtonFormField<String>(
      key: ValueKey('$label-$value-${options.length}'),
      initialValue: value ?? _none,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem(value: _none, child: Text('— none')),
        for (final i in options)
          DropdownMenuItem(
            value: i.id,
            child: Text(
              '${i.itemCode} · ${i.grade ?? ''} · ${_qty(i.available)} ${i.unit} free',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: _saving ? null : (v) => onChanged(v ?? _none),
    );

    return AlertDialog(
      title: const Text('Reserve steel for blocks'),
      content: SizedBox(
        width: 760,
        child: candidates.isEmpty
            ? const Text('No hull has blocks yet (Production → Blocks).')
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey('hull-$hullId'),
                      initialValue: hullId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Hull'),
                      items: [
                        for (final h in candidates)
                          DropdownMenuItem(
                            value: h.id,
                            child: Text(h.displayName, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: _saving
                          ? null
                          : (v) => setState(() {
                              _hullId = v;
                              _errors = const [];
                            }),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Block weight → ${(SteelReservationPlan.plateShare * 100).round()} % plates, '
                      '${((1 - SteelReservationPlan.plateShare) * 100).round()} % profiles, '
                      '+${(SteelReservationPlan.allowance * 100).round()} % cutting allowance; blocks without a saved '
                      'weight use the estimate. Needed by = start of the block\'s first schedule row. '
                      'Blocks that already have a reservation of an item are skipped.',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 8),
                    for (final g in grades)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: itemDropdown(
                          label:
                              'Plates, grade $g '
                              '(${blocks.where((b) => SteelReservationPlan.gradeOf(b.type) == g).length} blocks)',
                          value: _plateChoice[g] ?? plateByGrade[g]?.id,
                          options: plates,
                          onChanged: (v) => setState(() => _plateChoice[g] = v),
                        ),
                      ),
                    itemDropdown(
                      label: 'Profiles',
                      value: _profileChoice ?? profile?.id,
                      options: profiles,
                      onChanged: (v) => setState(() => _profileChoice = v),
                    ),
                    const SizedBox(height: 12),
                    if (loading)
                      const Center(
                        child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()),
                      )
                    else if (plan != null) ...[
                      Text(
                        '${plan.needs.length} blocks · ${steelT.toStringAsFixed(0)} t steel'
                        '${estimated == 0 ? '' : ' ($estimated from the estimate)'} · '
                        '${plan.drafts.length} reservations to create'
                        '${plan.skippedExisting == 0 ? '' : ', ${plan.skippedExisting} already reserved'}',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      for (final e in plan.totalByItem.entries)
                        if (itemsById[e.key] case final item?)
                          _TotalRow(item: item, quantity: e.value, missing: shortages[item]),
                      if (shortages.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            'Shortages can be reserved anyway: the item shows as "shortage" (to order) until stock is received.',
                            style: TextStyle(fontSize: 12, color: Color(0xFFF59E0B)),
                          ),
                        ),
                      for (final w in plan.warnings)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('• $w', style: const TextStyle(fontSize: 12, color: Color(0xFFFDE68A))),
                        ),
                      if (plan.needs.isNotEmpty)
                        Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: Text('Per block (${plan.needs.length})', style: const TextStyle(fontSize: 12.5)),
                            children: [for (final n in plan.needs) _NeedRow(need: n)],
                          ),
                        ),
                    ],
                    if (_errors.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF450A0A),
                          borderRadius: BorderRadius.circular(8),
                        ),
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
              ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving || plan == null || plan.drafts.isEmpty ? null : () => _save(plan),
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text('Reserve ${plan?.drafts.length ?? 0}'),
        ),
      ],
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.item, required this.quantity, this.missing});

  final MaterialItem item;
  final double quantity;
  final double? missing;

  @override
  Widget build(BuildContext context) {
    final short = missing != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(item.type.icon, size: 16, color: short ? const Color(0xFFEF4444) : const Color(0xFF22C55E)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${item.itemCode} · ${item.description}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          Text(
            '${_qty(quantity)} ${item.unit} of ${_qty(item.available)} free'
            '${short ? ' · ${_qty(missing!)} ${item.unit} short' : ''}',
            style: TextStyle(
              fontSize: 12.5,
              color: short ? const Color(0xFFFCA5A5) : null,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _NeedRow extends StatelessWidget {
  const _NeedRow({required this.need});

  final BlockSteelNeed need;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 12);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(need.block.blockNo, style: style.copyWith(fontWeight: FontWeight.w700)),
          ),
          SizedBox(
            width: 110,
            child: Text(
              '${need.weightT.toStringAsFixed(1)} t${need.estimated ? ' ≈' : ''}',
              style: style.copyWith(color: need.estimated ? AppTheme.textMuted : null),
            ),
          ),
          SizedBox(width: 130, child: Text('plates ${need.plateT.toStringAsFixed(1)} t (${need.grade})', style: style)),
          SizedBox(width: 110, child: Text('profiles ${need.profileT.toStringAsFixed(1)} t', style: style)),
          Expanded(
            child: Text(
              need.neededBy == null ? 'no schedule' : 'by ${formatDate(need.neededBy)}',
              style: style.copyWith(color: AppTheme.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
