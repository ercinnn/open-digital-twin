import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../../digital_twin/presentation/providers/twin_providers.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/services/yard_kpis.dart';
import '../../providers/shipyard_providers.dart';
import '../scene_actions.dart';

/// Management dashboard: all hulls, yard KPIs and what needs attention now.
class DashboardTab extends ConsumerWidget {
  const DashboardTab({super.key, required this.projectId, required this.actions});

  final String projectId;
  final SceneActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpis = ref.watch(yardKpisProvider(projectId));
    final components = ref.watch(componentsProvider(projectId)).value ?? const <TwinComponent>[];
    final byId = componentsById(components);
    final today = ref.watch(todayProvider);

    String pct(double? v) => v == null ? '—' : '${v.toStringAsFixed(0)} %';

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 900;
        final hullCards = SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: kpis.hulls.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) => _HullCard(
              health: kpis.hulls[i],
              today: today,
              onTap: () {
                final node = kpis.hulls[i].hull.locationNodeId;
                if (node != null) actions.selectNode(node);
              },
            ),
          ),
        );
        final tiles = Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _Kpi(label: 'Avg OEE (shops)', value: pct(kpis.avgOee), icon: Icons.speed, color: (kpis.avgOee ?? 100) < 65 ? const Color(0xFFF59E0B) : const Color(0xFF22C55E)),
            _Kpi(label: 'Avg utilization', value: pct(kpis.avgUtilization), icon: Icons.factory_outlined, color: (kpis.avgUtilization ?? 0) > 95 ? const Color(0xFFF59E0B) : AppTheme.accent),
            _Kpi(label: 'Bottleneck shops', value: '${kpis.bottlenecks.length}', icon: Icons.filter_alt_outlined, color: kpis.bottlenecks.isEmpty ? const Color(0xFF22C55E) : const Color(0xFFF59E0B)),
            _Kpi(label: 'Cranes available', value: '${kpis.cranesAvailable}/${kpis.cranesTotal}', icon: Icons.precision_manufacturing_outlined, color: kpis.cranesAvailable < kpis.cranesTotal ? const Color(0xFFEF4444) : const Color(0xFF22C55E)),
            _Kpi(label: 'Docks & berths occupied', value: '${kpis.docksOccupied}/${kpis.docksTotal}', icon: Icons.anchor, color: AppTheme.marine),
            _Kpi(label: 'Late activities', value: '${kpis.lateActivities}', icon: Icons.schedule, color: kpis.lateActivities == 0 ? const Color(0xFF22C55E) : const Color(0xFFF59E0B)),
            _Kpi(label: 'Headcount (all shifts)', value: '${kpis.headcount}', icon: Icons.groups_outlined, color: AppTheme.textMuted),
            _Kpi(label: 'Stock alerts', value: '${kpis.stockAlerts}', icon: Icons.inventory_2_outlined, color: kpis.stockAlerts == 0 ? const Color(0xFF22C55E) : const Color(0xFFF59E0B)),
            _Kpi(label: 'Open punch / overdue', value: '${kpis.openPunch} / ${kpis.overduePunch}', icon: Icons.fact_check_outlined, color: kpis.overduePunch == 0 ? AppTheme.accent : const Color(0xFFEF4444)),
            _Kpi(label: 'Days without LTI', value: kpis.hse.daysSinceLostTime?.toString() ?? '—', icon: Icons.health_and_safety_outlined, color: const Color(0xFF22C55E)),
            _Kpi(label: 'Live work permits', value: '${kpis.hse.livePermits}', icon: Icons.local_fire_department_outlined, color: const Color(0xFFF97316)),
          ],
        );
        final attention = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 6),
              child: Text('NEEDS ATTENTION', style: TextStyle(fontSize: 10.5, letterSpacing: 0.8, color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
            ),
            if (kpis.attention.isEmpty)
              const Text('Nothing critical right now.', style: TextStyle(color: AppTheme.textMuted)),
            for (final a in kpis.attention.take(14))
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    switch (a.severity) {
                      Severity.critical => Icons.error_outline,
                      Severity.warning => Icons.warning_amber_rounded,
                      Severity.info => Icons.info_outline,
                    },
                    color: switch (a.severity) {
                      Severity.critical => const Color(0xFFEF4444),
                      Severity.warning => const Color(0xFFF59E0B),
                      Severity.info => AppTheme.accent,
                    },
                  ),
                  title: Text(a.title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  subtitle: Text(a.detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5)),
                  onTap: a.componentId == null || byId[a.componentId] == null
                      ? null
                      : () => actions.selectNode(byId[a.componentId]!.meshNodeId),
                ),
              ),
          ],
        );

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 10),
          children: [
            hullCards,
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 6, child: tiles),
                        const SizedBox(width: 14),
                        Expanded(flex: 5, child: attention),
                      ],
                    )
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [tiles, const SizedBox(height: 14), attention]),
            ),
          ],
        );
      },
    );
  }
}

class _HullCard extends StatelessWidget {
  const _HullCard({required this.health, required this.today, required this.onTap});

  final HullHealth health;
  final DateTime today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final h = health.hull;
    final p = health.progress;
    final delay = health.delayDays ?? 0;
    final days = health.daysToDelivery(today);
    final risk = health.atRisk;
    return SizedBox(
      width: 270,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: risk ? const Color(0xFFF59E0B) : AppTheme.outline),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(h.hullNo, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(h.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    ),
                    if (risk) const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFF59E0B)),
                  ],
                ),
                Text('${h.status.label} · ${h.shipType ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                const SizedBox(height: 8),
                if (p.plannedPct > 0 || p.earnedPct > 0) ...[
                  Stack(
                    children: [
                      Container(height: 8, decoration: BoxDecoration(color: AppTheme.surfaceHigh, borderRadius: BorderRadius.circular(4))),
                      FractionallySizedBox(
                        widthFactor: (p.earnedPct / 100).clamp(0, 1),
                        child: Container(height: 8, decoration: BoxDecoration(color: AppTheme.accent, borderRadius: BorderRadius.circular(4))),
                      ),
                      FractionallySizedBox(
                        widthFactor: (p.plannedPct / 100).clamp(0, 1),
                        child: Align(alignment: Alignment.centerRight, child: Container(width: 2, height: 12, color: Colors.white)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Earned ${p.earnedPct.round()} % · plan ${p.plannedPct.round()} %'
                    '${p.spi == null ? '' : ' · SPI ${p.spi!.toStringAsFixed(2)}'}',
                    style: TextStyle(fontSize: 11, color: p.variancePct < -5 ? const Color(0xFFFBBF24) : AppTheme.textMuted),
                  ),
                ] else
                  const Text('No schedule yet', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                const Spacer(),
                Text(
                  'Delivery ${formatDate(h.forecastDeliveryDate ?? h.contractDeliveryDate)}'
                  '${days == null ? '' : ' (${days >= 0 ? 'in $days d' : '${-days} d ago'})'}',
                  style: const TextStyle(fontSize: 11.5),
                ),
                Text(
                  delay > 0 ? 'Forecast +$delay d vs contract' : 'On contract date',
                  style: TextStyle(fontSize: 11, color: delay > 0 ? const Color(0xFFFCA5A5) : const Color(0xFF86EFAC)),
                ),
                if (health.nextMilestone != null)
                  Text(
                    'Next: ${health.nextMilestone} ${formatDate(health.nextMilestoneDate)}'
                    '${health.openPunchA > 0 ? ' · ${health.openPunchA} punch A' : ''}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, required this.icon, required this.color});

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 168,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
                Text(label, style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
