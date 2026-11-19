import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../domain/entities/block_entities.dart';
import '../../../domain/entities/hse_entities.dart';
import '../../../domain/entities/material_entities.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/entities/quality_entities.dart';
import '../../../domain/services/permit_plan.dart';
import '../../providers/shipyard_providers.dart';
import '../hse/block_permits_panel.dart';
import '../materials/block_materials_panel.dart';
import '../quality/block_inspections_panel.dart';

/// Everything linked to one hull block, one tab per module: material
/// reservations, ITP inspections and permits-to-work.
class BlockDialog extends ConsumerWidget {
  const BlockDialog({super.key, required this.projectId, required this.block, required this.hull, this.initialTab = 0});

  final String projectId;
  final HullBlock block;
  final Hull? hull;

  /// 0 = materials, 1 = inspections, 2 = permits.
  final int initialTab;

  static Future<void> show(
    BuildContext context, {
    required String projectId,
    required HullBlock block,
    required Hull? hull,
    int initialTab = 0,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => BlockDialog(projectId: projectId, block: block, hull: hull, initialTab: initialTab),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reservations = (ref.watch(reservationsProvider(projectId)).value ?? const <MaterialReservation>[])
        .where((r) => r.componentId == block.componentId)
        .toList();
    final inspections = (ref.watch(inspectionsProvider(projectId)).value ?? const <QualityInspection>[])
        .where((q) => q.componentId == block.componentId)
        .toList();
    final openHolds = inspections.where((q) => q.isOpenHold).length;
    final now = DateTime.now();
    final permits = ref.watch(permitsProvider(projectId)).value ?? const <WorkPermit>[];
    final livePermits = permits.where((p) => p.componentId == block.componentId && p.isLive(now)).length;
    final missingPermits = PermitPlan.forBlock(
      block: block,
      activities: ref.watch(activitiesProvider(projectId)).value ?? const <ProductionActivity>[],
      permits: permits,
      now: now,
    ).where((n) => !n.covered).length;
    final weight = block.weightKg;
    final size = MediaQuery.sizeOf(context);

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Block ${block.blockNo}'),
          Text(
            [
              block.name,
              if (weight != null && weight > 0) '${(weight / 1000).toStringAsFixed(1)} t',
              if (block.erectionSequence < 999) 'erection #${block.erectionSequence}',
            ].join(' · '),
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
                    BlockMaterialsPanel(projectId: projectId, block: block, hullId: hull?.id),
                    BlockInspectionsPanel(projectId: projectId, block: block, hull: hull),
                    BlockPermitsPanel(projectId: projectId, block: block, hull: hull),
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
