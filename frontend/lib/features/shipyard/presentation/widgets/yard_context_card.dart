import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/async_states.dart';
import '../../../digital_twin/domain/entities/twin_entities.dart';
import '../../domain/entities/production_entities.dart';
import '../../domain/entities/resource_entities.dart';
import '../../domain/services/production_schedule.dart';
import '../providers/scene_view_providers.dart';
import '../providers/shipyard_providers.dart';

/// Inspector card: what the yard operations data says about the selected node.
class YardContextCard extends ConsumerWidget {
  const YardContextCard({super.key, required this.projectId, required this.component});

  final String projectId;
  final TwinComponent component;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(shipyardEnabledProvider(projectId))) return const SizedBox.shrink();
    final today = ref.watch(todayProvider);
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final org = ref.watch(organizationProvider(projectId)).value;
    final schedule = ref.watch(scheduleProvider(projectId));
    final bookings = ref.watch(bookingsProvider(projectId)).value ?? const <ResourceBooking>[];
    final permits = ref.watch(permitsProvider(projectId)).value ?? const [];
    final punch = ref.watch(punchItemsProvider(projectId)).value ?? const [];
    final sceneDate = ref.watch(sceneDateProvider(projectId));

    final rows = <(String, String)>[];

    // Block: placement at the scene date + current activity.
    final own = schedule.forComponent(component.id, today);
    if (own.isNotEmpty) {
      final placement = ProductionSchedule.placementFor(own, sceneDate, today);
      final a = placement.activity;
      rows.add(('Stage (${formatDate(sceneDate)})', a == null ? 'Not started' : '${a.stage.label} · ${a.progressPct.round()} %'));
      final late = own.where((x) => !x.isDone && x.isLate(today)).length;
      if (late > 0) rows.add(('Late activities', '$late'));
    }

    // Area: work running there today.
    final runningHere = schedule.runningAt(today, today).where((a) => a.locationNodeId == component.meshNodeId).toList();
    if (runningHere.isNotEmpty) {
      rows.add(('Running here', runningHere.map((a) => a.name).take(4).join('\n')));
    }

    // Organization.
    if (org != null) {
      final staffing = org.forComponent(component.id);
      final responsible = staffing.where((s) => s.isResponsible).map((s) => org.byId[s.departmentId]?.name).whereType<String>().toSet();
      if (responsible.isNotEmpty) rows.add(('Responsible', responsible.join(', ')));
      if (staffing.isNotEmpty) {
        final perShift = <String, int>{};
        for (final s in staffing) {
          final code = org.shifts.where((x) => x.id == s.shiftId).firstOrNull?.code ?? '-';
          perShift[code] = (perShift[code] ?? 0) + s.headcount;
        }
        rows.add(('Headcount', perShift.entries.map((e) => '${e.key}: ${e.value}').join('  ')));
      }
    }

    // Resource calendar.
    final mine = bookings.where((b) => b.componentId == component.id && !b.isCancelled && b.endsAt.isAfter(now)).toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    if (mine.isNotEmpty) {
      final b = mine.first;
      rows.add((
        b.startsAt.isAfter(now) ? 'Next booking' : 'Current booking',
        '${b.title}\n${formatDateTime(b.startsAt)} → ${formatDateTime(b.endsAt)} · ${b.effectiveStatus(now).label}',
      ));
    }

    final livePermits = permits.where((p) => p.componentId == component.id && p.isLive(now)).toList();
    if (livePermits.isNotEmpty) {
      rows.add(('Live permits', livePermits.map((p) => '${p.permitNo} ${p.type.label}').join('\n')));
    }
    final openPunch = punch.where((p) => p.componentId == component.id && p.isOpen).length;
    if (openPunch > 0) rows.add(('Open punch items', '$openPunch'));

    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SectionCard(
        title: 'Yard context',
        icon: Icons.precision_manufacturing_outlined,
        child: Column(
          children: [
            for (final (k, v) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 120, child: Text(k, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted))),
                    Expanded(child: Text(v, style: const TextStyle(fontSize: 12.5))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
