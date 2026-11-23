import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/status/component_status.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/async_states.dart';
import '../../../../../shared/widgets/status_badge.dart';
import '../../../../auth/presentation/providers/auth_providers.dart';
import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../../digital_twin/presentation/providers/twin_providers.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/entities/resource_entities.dart';
import '../../providers/shipyard_providers.dart';
import '../scene_actions.dart';
import 'booking_dialogs.dart';
import 'lift_plan_dialog.dart';

const _resourceCategories = ['crane', 'docks_and_berths', 'floating_dock', 'outfitting_quay'];

enum _ResourceFilter { all, cranes, docks }

/// Crane / dock / berth calendar with utilization and automatic wind stops.
class ResourcesTab extends ConsumerStatefulWidget {
  const ResourcesTab({super.key, required this.projectId, required this.actions});

  final String projectId;
  final SceneActions actions;

  @override
  ConsumerState<ResourcesTab> createState() => _ResourcesTabState();
}

class _ResourcesTabState extends ConsumerState<ResourcesTab> {
  static const _windowDays = 14;
  static const _labelWidth = 210.0;
  static const _laneHeight = 26.0;

  late DateTime _from = addDays(dateOnly(DateTime.now()), -2);
  _ResourceFilter _filter = _ResourceFilter.all;

  DateTime get _to => addDays(_from, _windowDays);

  Future<void> _newBooking(List<TwinComponent> resources, List<Hull> hulls, {String? resourceId}) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => NewBookingDialog(
        projectId: widget.projectId,
        resources: resources,
        hulls: hulls,
        initialResourceId: resourceId,
      ),
    );
  }

  Future<void> _planLifts(List<Hull> hulls, List<TwinComponent> components, List<ResourceBooking> bookings) async {
    final activities = ref.read(activitiesProvider(widget.projectId)).value ?? const <ProductionActivity>[];
    final first = await LiftPlanDialog.show(
      context,
      hulls: hulls,
      activities: activities,
      components: components,
      bookings: bookings,
    );
    if (first == null || !mounted) return;
    setState(() => _from = addDays(dateOnly(first), -1));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Erection lifts booked as "Planned". Tap a lift to confirm or cancel it.')),
    );
  }

  Future<void> _pickWeek() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: addDays(_from, 2),
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 6),
      helpText: 'Show the calendar from',
    );
    if (date != null && mounted) setState(() => _from = addDays(date, -1));
  }

  @override
  Widget build(BuildContext context) {
    final bookings = ref.watch(bookingsProvider(widget.projectId));
    final components = ref.watch(componentsProvider(widget.projectId)).value ?? const <TwinComponent>[];
    final hulls = ref.watch(hullsProvider(widget.projectId)).value ?? const <Hull>[];
    final canEdit = ref.watch(isEditorProvider);
    if (bookings.hasError) return ErrorView(error: bookings.error!);
    if (!bookings.hasValue) return const LoadingView();

    final resources = components.where((c) => _resourceCategories.contains(c.category)).where((c) {
      return switch (_filter) {
        _ResourceFilter.all => true,
        _ResourceFilter.cranes => c.category == 'crane',
        _ResourceFilter.docks => c.category != 'crane',
      };
    }).toList()
      ..sort((a, b) {
        final ca = a.category == 'crane' ? 0 : 1;
        final cb = b.category == 'crane' ? 0 : 1;
        return ca != cb ? ca.compareTo(cb) : a.name.compareTo(b.name);
      });
    final all = bookings.value!.where((b) => !b.isCancelled).toList();
    final hullById = {for (final h in hulls) h.id: h};
    final suspended = all.where((b) => b.status == BookingStatus.suspended).length;
    final allResources = components.where((c) => _resourceCategories.contains(c.category)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Previous week',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _from = addDays(_from, -7)),
                icon: const Icon(Icons.chevron_left),
              ),
              TextButton(
                onPressed: () => setState(() => _from = addDays(dateOnly(DateTime.now()), -2)),
                child: const Text('Today'),
              ),
              IconButton(
                tooltip: 'Next week',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _from = addDays(_from, 7)),
                icon: const Icon(Icons.chevron_right),
              ),
              Tooltip(
                message: 'Go to a date',
                child: InkWell(
                  onTap: _pickWeek,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${formatDate(_from)} – ${formatDate(addDays(_to, -1))}', style: const TextStyle(fontSize: 12.5)),
                        const SizedBox(width: 4),
                        const Icon(Icons.calendar_month_outlined, size: 16, color: AppTheme.textMuted),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SegmentedButton<_ResourceFilter>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: _ResourceFilter.all, label: Text('All')),
                  ButtonSegment(value: _ResourceFilter.cranes, label: Text('Cranes')),
                  ButtonSegment(value: _ResourceFilter.docks, label: Text('Docks & berths')),
                ],
                selected: {_filter},
                onSelectionChanged: (s) => setState(() => _filter = s.first),
              ),
              const Spacer(),
              if (suspended > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.air, size: 16, color: Color(0xFFFDBA74)),
                    label: Text('$suspended suspended (crane alarm)', style: const TextStyle(fontSize: 11.5)),
                  ),
                ),
              if (canEdit)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: OutlinedButton.icon(
                    onPressed: () => _planLifts(hulls, components, bookings.value!),
                    icon: const Icon(Icons.precision_manufacturing_outlined, size: 18),
                    label: const Text('Plan lifts'),
                  ),
                ),
              Tooltip(
                message: canEdit ? 'Overlaps and overloads are rejected by the database' : 'Editors only',
                child: FilledButton.icon(
                  onPressed: canEdit && allResources.isNotEmpty ? () => _newBooking(allResources, hulls) : null,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New booking'),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final trackWidth = math.max(200.0, constraints.maxWidth - _labelWidth);
              final pxPerHour = trackWidth / (_windowDays * 24);
              return ListView(
                children: [
                  _DayHeader(from: _from, days: _windowDays, labelWidth: _labelWidth, pxPerHour: pxPerHour),
                  for (final r in resources)
                    _ResourceRow(
                      resource: r,
                      bookings: all.where((b) => b.componentId == r.id).toList(),
                      from: _from,
                      to: _to,
                      labelWidth: _labelWidth,
                      laneHeight: _laneHeight,
                      pxPerHour: pxPerHour,
                      onSelectResource: () => widget.actions.selectNode(r.meshNodeId),
                      onTapBooking: (b) => showDialog<void>(
                        context: context,
                        builder: (_) => BookingDetailsDialog(
                          booking: b,
                          resource: r,
                          hullName: b.hullId == null ? null : hullById[b.hullId]?.displayName,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.from, required this.days, required this.labelWidth, required this.pxPerHour});

  final DateTime from;
  final int days;
  final double labelWidth;
  final double pxPerHour;

  @override
  Widget build(BuildContext context) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final today = dateOnly(DateTime.now());
    return SizedBox(
      height: 26,
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: const Padding(
              padding: EdgeInsets.only(left: 12, top: 6),
              child: Text('RESOURCE · UTILIZATION', style: TextStyle(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
            ),
          ),
          for (var i = 0; i < days; i++)
            Container(
              width: pxPerHour * 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: addDays(from, i) == today ? AppTheme.accent.withValues(alpha: 0.12) : null,
                border: const Border(left: BorderSide(color: AppTheme.outline)),
              ),
              child: Text(
                pxPerHour * 24 > 46 ? '${names[addDays(from, i).weekday - 1]} ${addDays(from, i).day}' : '${addDays(from, i).day}',
                style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}

class _ResourceRow extends StatelessWidget {
  const _ResourceRow({
    required this.resource,
    required this.bookings,
    required this.from,
    required this.to,
    required this.labelWidth,
    required this.laneHeight,
    required this.pxPerHour,
    required this.onSelectResource,
    required this.onTapBooking,
  });

  final TwinComponent resource;
  final List<ResourceBooking> bookings;
  final DateTime from;
  final DateTime to;
  final double labelWidth;
  final double laneHeight;
  final double pxPerHour;
  final VoidCallback onSelectResource;
  final ValueChanged<ResourceBooking> onTapBooking;

  @override
  Widget build(BuildContext context) {
    final slots = math.max(
      resource.category == 'outfitting_quay' ? 2 : 1,
      bookings.fold<int>(1, (m, b) => math.max(m, b.slot)),
    );
    final now = DateTime.now();
    final util = utilization(bookings, from, to, slots: slots);
    final capacity = resourceCapacity(resource);
    final alarm = resource.category == 'crane' && resource.status == ComponentStatus.alert;
    final height = slots * laneHeight + 8;
    final nowX = now.difference(from).inMinutes / 60 * pxPerHour;
    final trackWidth = pxPerHour * to.difference(from).inHours;

    return Container(
      height: height,
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.outline))),
      child: Row(
        children: [
          InkWell(
            onTap: onSelectResource,
            child: SizedBox(
              width: labelWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    StatusDot(status: resource.status, size: 9),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(shortComponentName(resource), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                          Text(
                            [
                              '${(util * 100).round()} % booked',
                              if (capacity != null) '${capacity.toStringAsFixed(0)} t',
                            ].join(' · '),
                            style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                    if (alarm)
                      const Tooltip(
                        message: 'Crane in ALERT - lifts suspended automatically',
                        child: Icon(Icons.air, size: 18, color: Color(0xFFF87171)),
                      ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: trackWidth,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                for (var d = 0; d < to.difference(from).inDays; d++)
                  Positioned(
                    left: d * 24 * pxPerHour,
                    top: 0,
                    bottom: 0,
                    child: const VerticalDivider(width: 1, color: AppTheme.outline),
                  ),
                for (final b in bookings)
                  if (b.overlaps(from, to)) _bar(b, now, trackWidth),
                if (nowX >= 0 && nowX <= trackWidth)
                  Positioned(left: nowX, top: 0, bottom: 0, child: Container(width: 1.5, color: AppTheme.accent)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(ResourceBooking b, DateTime now, double trackWidth) {
    final left = math.max(0.0, b.startsAt.difference(from).inMinutes / 60 * pxPerHour);
    final right = math.min(trackWidth, b.endsAt.difference(from).inMinutes / 60 * pxPerHour);
    final status = b.effectiveStatus(now);
    final suspended = status == BookingStatus.suspended;
    final unconfirmed = b.isUnconfirmed(now);
    final color = suspended ? const Color(0xFFF87171) : b.type.color;
    final faded = status == BookingStatus.done || status == BookingStatus.planned;
    final border = suspended ? Colors.white : (unconfirmed ? const Color(0xFFF59E0B) : color);
    return Positioned(
      left: left,
      width: math.max(4, right - left),
      top: 4 + (b.slot - 1) * laneHeight,
      height: laneHeight - 6,
      child: Tooltip(
        message: '${b.title}\n${formatDateTime(b.startsAt)} → ${formatDateTime(b.endsAt)}\n${status.label}'
            '${unconfirmed ? ' - not confirmed' : ''}'
            '${b.loadT == null ? '' : ' · ${b.loadT!.toStringAsFixed(0)} t'}'
            '${suspended && b.suspendedReason != null ? '\n${b.suspendedReason}' : ''}',
        child: InkWell(
          onTap: () => onTapBooking(b),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: color.withValues(alpha: faded ? 0.35 : 0.85),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: border, width: suspended || unconfirmed ? 1.5 : 1),
            ),
            child: Text(
              '${suspended ? '⏸ ' : (unconfirmed ? '? ' : '')}${b.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: faded ? Colors.white : const Color(0xFF0B1220)),
            ),
          ),
        ),
      ),
    );
  }
}
