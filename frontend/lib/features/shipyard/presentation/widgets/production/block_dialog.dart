import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../../digital_twin/presentation/providers/twin_providers.dart';
import '../../../domain/entities/block_entities.dart';
import '../../../domain/entities/hse_entities.dart';
import '../../../domain/entities/material_entities.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/entities/quality_entities.dart';
import '../../../domain/entities/work_scope.dart';
import '../../../domain/services/permit_plan.dart';
import '../../providers/shipyard_providers.dart';
import '../hse/block_permits_panel.dart';
import '../materials/block_materials_panel.dart';
import '../quality/block_inspections_panel.dart';
import '../scene_actions.dart';

/// Everything linked to one hull block or one afloat outfitting work package,
/// one tab per module: material reservations, ITP inspections and
/// permits-to-work.
class BlockDialog extends ConsumerWidget {
  const BlockDialog({super.key, required this.projectId, required this.scope, required this.hull, this.initialTab = 0});

  final String projectId;
  final WorkScope scope;
  final Hull? hull;

  /// 0 = materials, 1 = inspections, 2 = permits.
  final int initialTab;

  static Future<void> show(
    BuildContext context, {
    required String projectId,
    required HullBlock block,
    required Hull? hull,
    int initialTab = 0,
  }) => _show(context, projectId, WorkScope.block(block), hull, initialTab);

  /// The dialog of an afloat outfitting work package row.
  static Future<void> showPackage(
    BuildContext context, {
    required String projectId,
    required ProductionActivity row,
    required Hull? hull,
    int initialTab = 0,
  }) => _show(context, projectId, WorkScope.package(row), hull, initialTab);

  static Future<void> _show(BuildContext context, String projectId, WorkScope scope, Hull? hull, int initialTab) {
    return showDialog<void>(
      context: context,
      builder: (_) => BlockDialog(projectId: projectId, scope: scope, hull: hull, initialTab: initialTab),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reservations = (ref.watch(reservationsProvider(projectId)).value ?? const <MaterialReservation>[])
        .where(scope.ownsReservation)
        .toList();
    final inspections = (ref.watch(inspectionsProvider(projectId)).value ?? const <QualityInspection>[])
        .where(scope.ownsInspection)
        .toList();
    final openHolds = inspections.where((q) => q.isOpenHold).length;
    final now = DateTime.now();
    final permits = ref.watch(permitsProvider(projectId)).value ?? const <WorkPermit>[];
    final livePermits = permits.where((p) => scope.ownsPermit(p) && p.isLive(now)).length;
    final missingPermits = PermitPlan.forScope(
      scope: scope,
      activities: ref.watch(activitiesProvider(projectId)).value ?? const <ProductionActivity>[],
      permits: permits,
      now: now,
    ).where((n) => !n.covered).length;
    final size = MediaQuery.sizeOf(context);

    final block = scope.block;
    final row = scope.packageRow;
    final String title;
    final List<String> subtitle;
    if (block != null) {
      final weight = block.weightKg;
      title = 'Block ${block.blockNo}';
      subtitle = [
        block.name,
        if (weight != null && weight > 0) '${(weight / 1000).toStringAsFixed(1)} t',
        if (block.erectionSequence < 999) 'erection #${block.erectionSequence}',
      ];
    } else {
      final components = ref.watch(componentsProvider(projectId)).value ?? const <TwinComponent>[];
      final shop = row!.workPackage?.shopNodeId;
      title = '${hull?.hullNo ?? ''} ${scope.code}'.trim();
      subtitle = [
        row.code,
        '${formatDate(row.plannedStart)} → ${formatDate(row.plannedEnd)}',
        if (shop != null)
          'shop: ${shortComponentName(components.where((c) => c.meshNodeId == shop).firstOrNull, fallback: shop)}',
        if (row.isDone) 'finished' else if (row.isActive) 'running',
      ];
    }

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          Text(
            subtitle.join(' · '),
            style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted, fontWeight: FontWeight.w400),
          ),
        ],
      ),
      content: SizedBox(
        width: 760,
        height: (size.height * 0.6).clamp(320.0, 620.0),
        child: DefaultTabController(
          length: 3,
          initialIndex: initialTab.clamp(0, 2),
          child: Column(
            children: [
              TabBar(
                tabs: [
                  Tab(text: 'Materials (${reservations.where((r) => r.isOpen).length} open)'),
                  Tab(text: 'Inspections (${inspections.length}${openHolds == 0 ? '' : ', $openHolds H open'})'),
                  Tab(text: 'Permits ($livePermits live${missingPermits == 0 ? '' : ', $missingPermits missing'})'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    BlockMaterialsPanel(projectId: projectId, scope: scope, hullId: hull?.id),
                    BlockInspectionsPanel(projectId: projectId, scope: scope, hull: hull),
                    BlockPermitsPanel(projectId: projectId, scope: scope, hull: hull),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  }
}
