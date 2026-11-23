import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../auth/presentation/providers/auth_providers.dart';
import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/entities/resource_entities.dart';
import '../../../domain/repositories/shipyard_repository.dart';
import '../../../domain/services/lift_plan.dart';
import '../../providers/shipyard_providers.dart';

double? resourceCapacity(TwinComponent c) => resourceCapacityT(c);

/// Details of a booking; editors can confirm, finish or cancel it.
class BookingDetailsDialog extends ConsumerStatefulWidget {
  const BookingDetailsDialog({super.key, required this.booking, required this.resource, this.hullName});

  final ResourceBooking booking;
  final TwinComponent? resource;
  final String? hullName;

  @override
  ConsumerState<BookingDetailsDialog> createState() => _BookingDetailsDialogState();
}

class _BookingDetailsDialogState extends ConsumerState<BookingDetailsDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _set(BookingStatus status) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(shipyardRepositoryProvider).setBookingStatus(widget.booking.id, status);
      if (mounted) Navigator.of(context).pop();
    } on ShipyardException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    final canEdit = ref.watch(isEditorProvider);
    final now = DateTime.now();
    final status = b.effectiveStatus(now);
    final unconfirmed = b.isUnconfirmed(now);
    final over = !b.endsAt.isAfter(now);
    final capacity = widget.resource == null ? null : resourceCapacity(widget.resource!);
    final rows = <(String, String)>[
      ('Resource', widget.resource?.name ?? b.componentId),
      ('Type', b.type.label),
      if (b.slot > 1 || widget.resource?.category == 'outfitting_quay') ('Berth slot', '${b.slot}'),
      ('Window', '${formatDateTime(b.startsAt)} → ${formatDateTime(b.endsAt)}'),
      ('Status', unconfirmed ? '${status.label} - not confirmed' : status.label),
      if (b.loadT != null) ('Load', '${b.loadT!.toStringAsFixed(0)} t${capacity == null ? '' : ' of ${capacity.toStringAsFixed(0)} t capacity'}'),
      if (widget.hullName != null) ('Hull', widget.hullName!),
      if ((b.notes ?? '').isNotEmpty) ('Notes', b.notes!),
    ];
    return AlertDialog(
      title: Row(
        children: [
          Icon(b.type.icon, color: b.type.color),
          const SizedBox(width: 10),
          Expanded(child: Text(b.title, style: const TextStyle(fontSize: 17))),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (b.status == BookingStatus.suspended)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C2D12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.air, color: Color(0xFFFDBA74)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(b.suspendedReason ?? 'Suspended', style: const TextStyle(fontSize: 12.5))),
                  ],
                ),
              ),
            if (unconfirmed || b.needsConfirmation(now))
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: unconfirmed ? const Color(0xFF78350F) : AppTheme.surfaceHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.help_outline, color: unconfirmed ? const Color(0xFFFCD34D) : AppTheme.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        unconfirmed
                            ? 'The window ${over ? 'is over' : 'has started'} but the booking was never confirmed, '
                                'so it was not started. Confirm it if the work took place, else cancel or re-plan it.'
                            : 'Starts within ${ResourceBooking.confirmBeforeHours} h and is not confirmed yet. '
                                'Only confirmed bookings start and finish with their window.',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            for (final (k, v) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 100, child: Text(k, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5))),
                    Expanded(child: SelectableText(v, style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: Color(0xFFFCA5A5))),
              ),
          ],
        ),
      ),
      actions: [
        if (canEdit && b.status != BookingStatus.cancelled && b.status != BookingStatus.done) ...[
          TextButton(
            onPressed: _busy ? null : () => _set(BookingStatus.cancelled),
            child: const Text('Cancel booking', style: TextStyle(color: Color(0xFFFCA5A5))),
          ),
          if (b.status == BookingStatus.planned)
            OutlinedButton(onPressed: _busy ? null : () => _set(BookingStatus.confirmed), child: const Text('Confirm')),
          if (b.status != BookingStatus.suspended)
            OutlinedButton(onPressed: _busy ? null : () => _set(BookingStatus.done), child: const Text('Mark done')),
        ],
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}

/// New booking (editors). Double bookings and overloads are rejected by the database.
class NewBookingDialog extends ConsumerStatefulWidget {
  const NewBookingDialog({super.key, required this.projectId, required this.resources, required this.hulls, this.initialResourceId});

  final String projectId;
  final List<TwinComponent> resources;
  final List<Hull> hulls;
  final String? initialResourceId;

  @override
  ConsumerState<NewBookingDialog> createState() => _NewBookingDialogState();
}

class _NewBookingDialogState extends ConsumerState<NewBookingDialog> {
  final _title = TextEditingController();
  final _load = TextEditingController();
  late String _resourceId = widget.initialResourceId ?? widget.resources.first.id;
  BookingType _type = BookingType.lift;
  int _slot = 1;
  String? _hullId;
  late DateTime _start = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day + 1, 8);
  int _hours = 4;
  bool _saving = false;
  String? _error;

  TwinComponent get _resource => widget.resources.firstWhere((r) => r.id == _resourceId);

  @override
  void dispose() {
    _title.dispose();
    _load.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay(hour: _start.hour, minute: _start.minute));
    if (!mounted) return;
    setState(() => _start = DateTime(date.year, date.month, date.day, time?.hour ?? _start.hour, time?.minute ?? 0));
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Enter a title.');
      return;
    }
    final load = double.tryParse(_load.text.replaceAll(',', '.'));
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(shipyardRepositoryProvider).createBooking(
        BookingDraft(
          projectId: widget.projectId,
          componentId: _resourceId,
          hullId: _hullId,
          title: title,
          type: _type,
          slot: _slot,
          startsAt: _start,
          endsAt: _start.add(Duration(hours: _hours)),
          loadT: load,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
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
    final capacity = resourceCapacity(_resource);
    final slots = _resource.category == 'outfitting_quay' ? 2 : 1;
    return AlertDialog(
      title: const Text('New resource booking'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _resourceId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Resource'),
                items: [
                  for (final r in widget.resources) DropdownMenuItem(value: r.id, child: Text(r.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: _saving ? null : (v) => setState(() {
                  _resourceId = v ?? _resourceId;
                  _slot = 1;
                  _type = _resource.category == 'crane' ? BookingType.lift : BookingType.docking;
                }),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<BookingType>(
                      initialValue: _type,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: [for (final t in BookingType.values) DropdownMenuItem(value: t, child: Text(t.label))],
                      onChanged: _saving ? null : (v) => setState(() => _type = v ?? _type),
                    ),
                  ),
                  if (slots > 1) ...[
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 110,
                      child: DropdownButtonFormField<int>(
                        initialValue: _slot,
                        decoration: const InputDecoration(labelText: 'Berth slot'),
                        items: [for (var i = 1; i <= slots; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                        onChanged: _saving ? null : (v) => setState(() => _slot = v ?? 1),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              TextField(controller: _title, enabled: !_saving, decoration: const InputDecoration(labelText: 'Title')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                initialValue: _hullId,
                decoration: const InputDecoration(labelText: 'Hull (optional)'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('—')),
                  for (final h in widget.hulls) DropdownMenuItem<String?>(value: h.id, child: Text(h.displayName)),
                ],
                onChanged: _saving ? null : (v) => setState(() => _hullId = v),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _pickStart,
                      icon: const Icon(Icons.schedule, size: 18),
                      label: Text('Start ${formatDateTime(_start)}'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 120,
                    child: DropdownButtonFormField<int>(
                      initialValue: _hours,
                      decoration: const InputDecoration(labelText: 'Duration'),
                      items: [
                        for (final h in const [1, 2, 4, 6, 8, 12, 24, 48, 72, 168, 336])
                          DropdownMenuItem(value: h, child: Text(h < 24 ? '$h h' : '${h ~/ 24} d')),
                      ],
                      onChanged: _saving ? null : (v) => setState(() => _hours = v ?? _hours),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _load,
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Load (t, optional)',
                  helperText: capacity == null ? null : 'Capacity ${capacity.toStringAsFixed(0)} t - checked by the database',
                ),
              ),
              if (_resource.status.dbValue == 'alert')
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    'This crane is in ALERT: bookings starting within 2 hours are created as suspended.',
                    style: TextStyle(color: Color(0xFFFDBA74), fontSize: 12.5),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error!, style: const TextStyle(color: Color(0xFFFCA5A5))),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Book'),
        ),
      ],
    );
  }
}
