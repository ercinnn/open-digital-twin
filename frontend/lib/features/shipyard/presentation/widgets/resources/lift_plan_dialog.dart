import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/entities/resource_entities.dart';
import '../../../domain/repositories/shipyard_repository.dart';
import '../../../domain/services/lift_plan.dart';
import '../../../domain/services/outfitting_lifts.dart';
import '../../providers/shipyard_providers.dart';

/// What the lift plan books.
enum LiftPlanKind {
  erection('Block erection'),
  outfitting('Outfitting at the quay');

  const LiftPlanKind(this.label);
  final String label;
}

/// Books crane lifts after a preview: the erection lifts of a hull's blocks
/// ([LiftPlan]) or the quay lifts of its afloat outfitting work packages
/// ([OutfittingLifts]). Returns the start of the first booked lift, so the
/// calendar can jump there.
class LiftPlanDialog extends ConsumerStatefulWidget {
  const LiftPlanDialog({
    super.key,
    required this.hulls,
    required this.activities,
    required this.components,
    required this.bookings,
  });

  final List<Hull> hulls;
  final List<ProductionActivity> activities;
  final List<TwinComponent> components;
  final List<ResourceBooking> bookings;

  static Future<DateTime?> show(
    BuildContext context, {
    required List<Hull> hulls,
    required List<ProductionActivity> activities,
    required List<TwinComponent> components,
    required List<ResourceBooking> bookings,
  }) {
    return showDialog<DateTime>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LiftPlanDialog(hulls: hulls, activities: activities, components: components, bookings: bookings),
    );
  }

  @override
  ConsumerState<LiftPlanDialog> createState() => _LiftPlanDialogState();
}

class _LiftPlanDialogState extends ConsumerState<LiftPlanDialog> {
  final _now = DateTime.now();
  late final Map<LiftPlanKind, Map<String, LiftPlanResult>> _plans = {
    LiftPlanKind.erection: {
      for (final h in widget.hulls)
        h.id: LiftPlan.forHull(
          hull: h,
          activities: widget.activities,
          components: widget.components,
          bookings: widget.bookings,
          now: _now,
        ),
    },
    LiftPlanKind.outfitting: {
      for (final h in widget.hulls)
        h.id: OutfittingLifts.forHull(
          hull: h,
          activities: widget.activities,
          components: widget.components,
          bookings: widget.bookings,
          now: _now,
        ),
    },
  };
  late final Map<LiftPlanKind, List<Hull>> _candidatesByKind = {
    for (final k in LiftPlanKind.values)
      k: widget.hulls
          .where((h) => _plans[k]![h.id]!.bookings.isNotEmpty || _plans[k]![h.id]!.warnings.isNotEmpty)
          .toList(),
  };
  late LiftPlanKind _kind =
      _candidatesByKind[LiftPlanKind.erection]!.isEmpty && _candidatesByKind[LiftPlanKind.outfitting]!.isNotEmpty
      ? LiftPlanKind.outfitting
      : LiftPlanKind.erection;
  late String? _hullId = _candidates.firstOrNull?.id;

  List<Hull> get _candidates => _candidatesByKind[_kind]!;

  void _setKind(LiftPlanKind kind) => setState(() {
    _kind = kind;
    if (!_candidates.any((h) => h.id == _hullId)) _hullId = _candidates.firstOrNull?.id;
  });
  bool _saving = false;
  String? _error;

  Future<void> _create(LiftPlanResult plan) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(shipyardRepositoryProvider).createBookings(plan.bookings);
      if (mounted) Navigator.of(context).pop(plan.bookings.first.startsAt);
    } on ShipyardException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  static const _erectionText =
      'Each lift lies in the first free window (${LiftPlan.dayStartHour}:00-${LiftPlan.dayEndHour}:00) '
      'of its erection days.';
  static const _outfittingText =
      'The items of a package are spread over its days, each in the first free window '
      '(${LiftPlan.dayStartHour}:00-${LiftPlan.dayEndHour}:00) of the smallest quay crane that carries its '
      'estimated weight.';

  @override
  Widget build(BuildContext context) {
    final plan = _hullId == null ? null : _plans[_kind]![_hullId];
    final erection = _kind == LiftPlanKind.erection;
    final names = {for (final c in widget.components) c.id: c.name};
    const muted = TextStyle(fontSize: 12.5, color: AppTheme.textMuted);
    return AlertDialog(
      title: const Text('Plan crane lifts'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<LiftPlanKind>(
                      segments: [
                        for (final k in LiftPlanKind.values) ButtonSegment(value: k, label: Text(k.label)),
                      ],
                      selected: {_kind},
                      showSelectedIcon: false,
                      onSelectionChanged: _saving ? null : (v) => _setKind(v.first),
                    ),
                    const SizedBox(height: 12),
                    if (_candidates.isEmpty)
                      Text(
                        erection
                            ? 'No erection rows without a lift. Draft a block schedule first (Production > Plan), '
                                  'or every erection already has its crane booking.'
                            : 'No outfitting work package lifts left to book. Plan the work packages first '
                                  '(Production > Plan > Outfitting work packages), or every package item already '
                                  'has its crane booking.',
                      )
                    else ...[
                    DropdownButtonFormField<String>(
                      key: ValueKey(_kind),
                      initialValue: _hullId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Hull',
                        helperText: erection
                            ? 'Block erection rows that have no crane booking yet.'
                            : 'Work package items (hatch covers, winches, generators, ...) without a quay crane booking.',
                      ),
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
                    if (plan != null && plan.bookings.isNotEmpty) ...[
                      Text(
                        '${plan.bookings.length} lift${plan.bookings.length == 1 ? '' : 's'}, '
                        '${formatDateTime(plan.bookings.first.startsAt)} → '
                        '${formatDateTime(plan.bookings.last.endsAt)}. '
                        '${erection ? _erectionText : _outfittingText} Lifts start as "Planned"; confirm, correct '
                        'the load or cancel single lifts in the calendar.',
                        style: muted,
                      ),
                      const SizedBox(height: 8),
                      for (final e in plan.cranes.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Icon(BookingType.lift.icon, size: 16, color: BookingType.lift.color),
                              const SizedBox(width: 8),
                              Expanded(child: Text(names[e.key] ?? e.key, style: const TextStyle(fontSize: 13))),
                              Text('${e.value} lifts', style: const TextStyle(fontSize: 13)),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      _LiftTable(bookings: plan.bookings),
                    ],
                    if (plan != null && plan.warnings.isNotEmpty)
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
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text('Not booked: $_error', style: const TextStyle(color: Color(0xFFFCA5A5))),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        if (plan != null && plan.bookings.isNotEmpty)
          FilledButton(
            onPressed: _saving ? null : () => _create(plan),
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Book ${plan.bookings.length} lifts'),
          ),
      ],
    );
  }
}

/// First lifts of the plan (the full list is in the calendar afterwards).
class _LiftTable extends StatelessWidget {
  const _LiftTable({required this.bookings});

  static const _shown = 8;

  final List<BookingDraft> bookings;

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted);
    const cell = TextStyle(fontSize: 12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Table(
          columnWidths: const {0: FlexColumnWidth(), 1: FixedColumnWidth(150), 2: FixedColumnWidth(60)},
          children: [
            const TableRow(
              children: [
                Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text('LIFT', style: head),
                ),
                Text('WINDOW', style: head),
                Text('LOAD', style: head, textAlign: TextAlign.end),
              ],
            ),
            for (final b in bookings.take(_shown))
              TableRow(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppTheme.outline)),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(b.title, style: cell, overflow: TextOverflow.ellipsis),
                  ),
                  Text('${formatDateTime(b.startsAt)}-${b.endsAt.hour.toString().padLeft(2, '0')}:00', style: cell),
                  Text(
                    b.loadT == null ? '—' : '${b.loadT!.toStringAsFixed(0)} t',
                    style: cell,
                    textAlign: TextAlign.end,
                  ),
                ],
              ),
          ],
        ),
        if (bookings.length > _shown)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '+ ${bookings.length - _shown} more',
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ),
      ],
    );
  }
}
