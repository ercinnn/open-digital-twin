import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../../digital_twin/presentation/providers/twin_providers.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/repositories/shipyard_repository.dart';
import '../../../domain/services/outfitting_packages.dart';
import '../../providers/scene_view_providers.dart';
import '../../providers/shipyard_providers.dart';
import '../scene_actions.dart';

/// Splits the afloat outfitting of a scheduled hull into system work packages
/// ([OutfittingPackages.forHull]): preview, then the generic outfitting row is
/// turned into the piping package and the other packages are inserted.
/// Returns a message for the snack bar when something was saved.
class OutfittingPackagesDialog extends ConsumerStatefulWidget {
  const OutfittingPackagesDialog({super.key, required this.hulls, required this.existing, this.initialHullId});

  final List<Hull> hulls;
  final List<ProductionActivity> existing;
  final String? initialHullId;

  static Future<String?> show(
    BuildContext context, {
    required List<Hull> hulls,
    required List<ProductionActivity> existing,
    String? initialHullId,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OutfittingPackagesDialog(hulls: hulls, existing: existing, initialHullId: initialHullId),
    );
  }

  @override
  ConsumerState<OutfittingPackagesDialog> createState() => _OutfittingPackagesDialogState();
}

class _OutfittingPackagesDialogState extends ConsumerState<OutfittingPackagesDialog> {
  late final List<Hull> _candidates = widget.hulls
      .where((h) => !h.isRepair && widget.existing.any((a) => a.hullId == h.id))
      .toList();
  late String? _hullId = _candidates.any((h) => h.id == widget.initialHullId)
      ? widget.initialHullId
      : _candidates.firstOrNull?.id;
  bool _saving = false;
  String? _error;

  Hull? get _hull => _candidates.where((h) => h.id == _hullId).firstOrNull;

  OutfittingPlan? _plan(Map<String, String> departmentIdByCode) {
    final hull = _hull;
    if (hull == null) return null;
    return OutfittingPackages.forHull(
      hull,
      widget.existing,
      existingCodes: {for (final a in widget.existing) a.code},
      firstSortOrder: widget.existing.fold<int>(0, (m, a) => a.sortOrder > m ? a.sortOrder : m) + 1,
      departmentIdByCode: departmentIdByCode,
    );
  }

  Future<void> _save(Hull hull, OutfittingPlan plan) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(shipyardRepositoryProvider);
    try {
      // Converted row first: a failed insert can be resumed (packages already
      // planned are skipped next time).
      if (plan.convert case final c?) await repo.updateActivityPlan(c.row.id, c.draft);
      await repo.createActivities(plan.create);
      if (mounted) {
        Navigator.of(context)
            .pop('${plan.rows.length} work package${plan.rows.length == 1 ? '' : 's'} planned for ${hull.hullNo}.');
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
    final hull = _hull;
    final org = hull == null ? null : ref.watch(organizationProvider(hull.projectId)).value;
    final departments = org?.departments ?? const [];
    final departmentIdByCode = {for (final d in departments) d.code: d.id};
    final departmentNames = {for (final d in departments) d.id: d.name};
    final components = hull == null
        ? const <TwinComponent>[]
        : ref.watch(componentsProvider(hull.projectId)).value ?? const <TwinComponent>[];
    final byNode = {for (final c in components) c.meshNodeId: c};
    final plan = _plan(departmentIdByCode);
    return AlertDialog(
      title: const Text('Afloat outfitting work packages'),
      content: SizedBox(
        width: 720,
        child: _candidates.isEmpty
            ? const Text(
                'No newbuild has schedule rows yet. Draft the schedule of a hull first (Plan > Draft schedule).',
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _hullId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Hull', helperText: 'Newbuilds with schedule rows.'),
                      items: [
                        for (final h in _candidates)
                          DropdownMenuItem(
                            value: h.id,
                            child: Text(h.displayName, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: _saving ? null : (v) => setState(() => _hullId = v),
                    ),
                    const SizedBox(height: 12),
                    if (plan != null && !plan.isValid)
                      _Message(lines: plan.problems, error: true)
                    else if (plan != null) ...[
                      Text(_summary(plan), style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted)),
                      const SizedBox(height: 8),
                      _Preview(rows: plan.rows, byNode: byNode, departmentNames: departmentNames),
                    ],
                    if (_error != null) _Message(lines: ['Not saved: $_error'], error: true),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        if (hull != null && plan != null && plan.isValid)
          FilledButton(
            onPressed: _saving ? null : () => _save(hull, plan),
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Plan ${plan.rows.length} package${plan.rows.length == 1 ? '' : 's'}'),
          ),
      ],
    );
  }

  String _summary(OutfittingPlan plan) {
    final window = '${formatDate(plan.start)} → ${formatDate(plan.end)}';
    final convert = plan.convert == null
        ? ''
        : ' ${plan.convert!.row.code} becomes the ${OutfittingPackages.convertedPackage.label} package '
              '(same row: its inspections stay linked).';
    return 'The afloat outfitting window $window is split into system work packages, all worked on board '
        'at the quay.$convert Commissioning can only be reported finished once every package is finished. '
        'Tap a bar in the Gantt to adjust a package.';
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.rows, required this.byNode, required this.departmentNames});

  final List<ActivityDraft> rows;
  final Map<String, TwinComponent> byNode;
  final Map<String, String> departmentNames;

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted);
    const cell = TextStyle(fontSize: 12);
    const muted = TextStyle(fontSize: 11, color: AppTheme.textMuted);
    final sorted = [...rows]..sort((a, b) => a.workPackage!.index.compareTo(b.workPackage!.index));
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2.6),
        1: FlexColumnWidth(1.6),
        2: FixedColumnWidth(86),
        3: FixedColumnWidth(86),
        4: FixedColumnWidth(44),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        const TableRow(
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text('WORK PACKAGE', style: head),
            ),
            Text('SHOP', style: head),
            Text('START', style: head),
            Text('END', style: head),
            Text('DAYS', style: head, textAlign: TextAlign.end),
          ],
        ),
        for (final a in sorted)
          TableRow(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppTheme.outline)),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.workPackage!.label, style: cell, overflow: TextOverflow.ellipsis),
                    Text(a.workPackage!.scope, style: muted, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shortComponentName(byNode[a.workPackage!.shopNodeId], fallback: a.workPackage!.shopNodeId),
                    style: cell,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (departmentNames[a.departmentId] case final dept?)
                    Text(dept, style: muted, overflow: TextOverflow.ellipsis),
                ],
              ),
              Text(formatDate(a.plannedStart), style: cell),
              Text(formatDate(a.plannedEnd), style: cell),
              Text('${a.plannedDays}', style: cell, textAlign: TextAlign.end),
            ],
          ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.lines, this.error = false});

  final List<String> lines;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? const Color(0xFFFCA5A5) : AppTheme.textMuted;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: error ? const Color(0xFF450A0A) : AppTheme.outline,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final l in lines) Text('• $l', style: TextStyle(color: color, fontSize: 12.5))],
      ),
    );
  }
}
