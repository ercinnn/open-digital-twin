import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/async_states.dart';
import '../../../../auth/presentation/providers/auth_providers.dart';
import '../../../../digital_twin/domain/entities/twin_entities.dart';
import '../../../../digital_twin/presentation/providers/twin_providers.dart';
import '../../../domain/entities/material_entities.dart';
import '../../../domain/entities/production_entities.dart';
import '../../../domain/repositories/shipyard_repository.dart';
import '../../providers/shipyard_providers.dart';
import '../production/activity_form_dialog.dart' show yardAreas;
import '../scene_actions.dart';
import 'material_dialog.dart';
import 'steel_reservation_dialog.dart';

/// Hull filter value for items without a hull.
const _generalStock = '__general__';

/// Stock levels per item and the traceability history of tagged pieces.
class MaterialsTab extends ConsumerStatefulWidget {
  const MaterialsTab({super.key, required this.projectId, required this.actions});

  final String projectId;
  final SceneActions actions;

  @override
  ConsumerState<MaterialsTab> createState() => _MaterialsTabState();
}

class _MaterialsTabState extends ConsumerState<MaterialsTab> {
  StockCategory? _type;

  /// null = all items, [_generalStock] = items without a hull, else a hull id.
  String? _hullFilter;
  bool _alertsOnly = false;
  String _query = '';
  String? _tag;
  final _scan = TextEditingController();

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  void _lookup(String raw) {
    final tag = normalizeTag(raw);
    if (tag.isEmpty) return;
    setState(() => _tag = tag);
    _scan.text = tag;
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  Future<void> _editStock(MaterialItem item) async {
    final onHand = TextEditingController(text: _fmt(item.onHand));
    final reserved = TextEditingController(text: _fmt(item.reserved));
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: Text('${item.itemCode} stock'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: onHand,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'On hand (${item.unit})'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: reserved,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Reserved, manual (${item.unit})',
                    helperText: item.blockReserved > 0
                        ? '+ ${_fmt(item.blockReserved)} ${item.unit} reserved for blocks (from the block reservations)'
                        : 'Block reservations are added on top (Blocks → tap a block).',
                    helperMaxLines: 2,
                  ),
                ),
                if (error != null)
                  Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(color: Color(0xFFFCA5A5)))),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final a = double.tryParse(onHand.text.replaceAll(',', '.'));
                final b = double.tryParse(reserved.text.replaceAll(',', '.'));
                if (a == null || b == null || a < 0 || b < 0) {
                  setLocal(() => error = 'Enter non-negative numbers.');
                  return;
                }
                try {
                  await ref.read(shipyardRepositoryProvider).setStock(item.id, onHand: a, reserved: b);
                  ref.invalidate(materialsProvider(widget.projectId));
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                } on ShipyardException catch (e) {
                  setLocal(() => error = e.message);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    onHand.dispose();
    reserved.dispose();
  }

  Future<void> _openItem({
    required List<MaterialItem> items,
    required List<Hull> hulls,
    required List<TwinComponent> components,
    MaterialItem? item,
  }) async {
    final saved = await MaterialItemDialog.show(
      context,
      projectId: widget.projectId,
      existing: items,
      hulls: hulls,
      stores: yardAreas(components),
      item: item,
      initialHullId: _hullFilter == _generalStock ? null : _hullFilter,
    );
    if (saved != true || !mounted) return;
    ref.invalidate(materialsProvider(widget.projectId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(item == null ? 'Stock item created.' : '${item.itemCode} saved.')),
    );
  }

  Future<void> _reserveSteel(List<Hull> hulls) async {
    final summary = await SteelReservationDialog.show(
      context,
      projectId: widget.projectId,
      hulls: hulls,
      initialHullId: _hullFilter == _generalStock ? null : _hullFilter,
    );
    if (summary == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(summary)));
  }

  Widget _hullMenu(List<Hull> hulls) {
    final label = switch (_hullFilter) {
      null => 'All hulls',
      _generalStock => 'General stock',
      final id => hulls.where((h) => h.id == id).firstOrNull?.hullNo ?? 'Hull',
    };
    return PopupMenuButton<String>(
      tooltip: 'Filter by hull',
      onSelected: (v) => setState(() => _hullFilter = v.isEmpty ? null : v),
      itemBuilder: (_) => [
        const PopupMenuItem(value: '', child: Text('All hulls')),
        const PopupMenuItem(value: _generalStock, child: Text('General stock (no hull)')),
        for (final h in hulls) PopupMenuItem(value: h.id, child: Text(h.displayName)),
      ],
      child: Chip(
        avatar: const Icon(Icons.directions_boat_outlined, size: 16),
        label: Row(mainAxisSize: MainAxisSize.min, children: [Text(label), const Icon(Icons.arrow_drop_down, size: 18)]),
        side: BorderSide(color: _hullFilter == null ? AppTheme.outline : AppTheme.accent),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(materialsProvider(widget.projectId));
    final components = ref.watch(componentsProvider(widget.projectId)).value ?? const <TwinComponent>[];
    final hulls = ref.watch(hullsProvider(widget.projectId)).value ?? const <Hull>[];
    final hullNos = {for (final h in hulls) h.id: h.hullNo};
    final byId = componentsById(components);
    final canEdit = ref.watch(isEditorProvider);
    final reservations = ref.watch(reservationsProvider(widget.projectId)).value ?? const <MaterialReservation>[];
    // Blocks with an open reservation, per item.
    final blocksByItem = <String, Set<String>>{};
    for (final r in reservations.where((r) => r.isOpen)) {
      (blocksByItem[r.itemId] ??= {}).add(r.componentId);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 6,
          child: items.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(materialsProvider(widget.projectId))),
            data: (list) {
              final shortages = list.where((i) => i.state != StockState.ok).length;
              final q = _query.toLowerCase();
              final filtered = list.where((i) {
                if (_type != null && i.type != _type) return false;
                if (_hullFilter == _generalStock && i.hullId != null) return false;
                if (_hullFilter != null && _hullFilter != _generalStock && i.hullId != _hullFilter) return false;
                if (_alertsOnly && i.state == StockState.ok) return false;
                return q.isEmpty || i.itemCode.toLowerCase().contains(q) || i.description.toLowerCase().contains(q);
              }).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 200,
                          child: TextField(
                            onChanged: (v) => setState(() => _query = v),
                            decoration: const InputDecoration(hintText: 'Search items', prefixIcon: Icon(Icons.search, size: 18)),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _hullMenu(hulls),
                                const SizedBox(width: 6),
                                FilterChip(
                                  selected: _alertsOnly,
                                  avatar: const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFF59E0B)),
                                  label: Text('Low / shortage ($shortages)'),
                                  onSelected: (v) => setState(() => _alertsOnly = v),
                                ),
                                for (final t in StockCategory.values)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: ChoiceChip(
                                      label: Text(t.label),
                                      selected: _type == t,
                                      onSelected: (v) => setState(() => _type = v ? t : null),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (canEdit)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                              onPressed: () => _reserveSteel(hulls),
                              icon: const Icon(Icons.view_in_ar_outlined, size: 18),
                              label: const Text('Reserve steel'),
                            ),
                          ),
                        if (canEdit)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                              onPressed: () => _openItem(items: list, hulls: hulls, components: components),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('New item'),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final item = filtered[i];
                        final loc = item.locationComponentId == null ? null : byId[item.locationComponentId];
                        final color = switch (item.state) {
                          StockState.ok => const Color(0xFF22C55E),
                          StockState.low => const Color(0xFFF59E0B),
                          StockState.shortage => const Color(0xFFEF4444),
                        };
                        return ListTile(
                          dense: true,
                          onTap: canEdit
                              ? () => _openItem(items: list, hulls: hulls, components: components, item: item)
                              : null,
                          leading: Icon(item.type.icon, color: color, size: 20),
                          title: Text('${item.itemCode} · ${item.description}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                          subtitle: Text(
                            [
                              if (item.hullId != null) 'for ${hullNos[item.hullId] ?? 'hull'}',
                              if (blocksByItem[item.id] case final b?) '${b.length} block${b.length == 1 ? '' : 's'}',
                              if (item.grade != null) item.grade!,
                              if (item.dimensions != null) item.dimensions!,
                              if (item.heatNumber != null) 'heat ${item.heatNumber}',
                              if (item.certificateNo != null) item.certificateNo!,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: SizedBox(
                            width: 230,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('${_fmt(item.available)} ${item.unit} free', style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w700)),
                                    Text('${_fmt(item.onHand)} on hand · ${_fmt(item.totalReserved)} reserved', style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted)),
                                  ],
                                ),
                                if (loc != null)
                                  IconButton(
                                    tooltip: 'Show ${loc.name} in 3D',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => widget.actions.selectNode(loc.meshNodeId),
                                    icon: const Icon(Icons.place_outlined, size: 18),
                                  ),
                                if (canEdit)
                                  IconButton(
                                    tooltip: 'Edit stock',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => _editStock(item),
                                    icon: const Icon(Icons.edit_outlined, size: 17),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 4,
          child: _TracePanel(
            projectId: widget.projectId,
            tag: _tag,
            scan: _scan,
            onLookup: _lookup,
            byId: byId,
            actions: widget.actions,
            items: items.value ?? const [],
          ),
        ),
      ],
    );
  }
}

class _TracePanel extends ConsumerWidget {
  const _TracePanel({
    required this.projectId,
    required this.tag,
    required this.scan,
    required this.onLookup,
    required this.byId,
    required this.actions,
    required this.items,
  });

  final String projectId;
  final String? tag;
  final TextEditingController scan;
  final ValueChanged<String> onLookup;
  final Map<String, TwinComponent> byId;
  final SceneActions actions;
  final List<MaterialItem> items;

  Future<void> _record(BuildContext context, WidgetRef ref, List<TraceEvent> history) async {
    final itemId = history.map((e) => e.itemId).whereType<String>().lastOrNull;
    final areas = byId.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    var type = TraceEventType.inspected;
    String? componentId;
    final notes = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: Text('Record event · $tag'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<TraceEventType>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Event'),
                  items: [for (final t in TraceEventType.values) DropdownMenuItem(value: t, child: Text(t.label))],
                  onChanged: (v) => setLocal(() => type = v ?? type),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: componentId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Location / block'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('—')),
                    for (final c in areas) DropdownMenuItem<String?>(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setLocal(() => componentId = v),
                ),
                const SizedBox(height: 10),
                TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes')),
                if (error != null)
                  Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(color: Color(0xFFFCA5A5)))),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                try {
                  await ref.read(shipyardRepositoryProvider).addTraceEvent(
                    projectId: projectId,
                    tagCode: tag!,
                    type: type,
                    itemId: itemId,
                    componentId: componentId,
                    notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
                  );
                  ref.invalidate(traceProvider((projectId, tag!)));
                  ref.invalidate(recentTagsProvider(projectId));
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                } on ShipyardException catch (e) {
                  setLocal(() => error = e.message);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    notes.dispose();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentTagsProvider(projectId)).value ?? const <String>[];
    final canEdit = ref.watch(isEditorProvider);
    final history = tag == null ? null : ref.watch(traceProvider((projectId, tag!)));
    final itemsById = {for (final i in items) i.id: i};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: scan,
            textInputAction: TextInputAction.search,
            onSubmitted: onLookup,
            decoration: InputDecoration(
              hintText: 'Scan or type a tag (QR / RFID / heat no.)',
              prefixIcon: const Icon(Icons.qr_code_scanner, size: 18),
              suffixIcon: IconButton(icon: const Icon(Icons.search, size: 18), onPressed: () => onLookup(scan.text)),
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final t in recent)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(t, style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace')),
                  onPressed: () => onLookup(t),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        const Divider(height: 1),
        Expanded(
          child: history == null
              ? const EmptyView(
                  icon: Icons.qr_code_2,
                  message: 'Scan a tag to see where the piece came from\nand which block it was built into.',
                )
              : history.when(
                  loading: () => const LoadingView(),
                  error: (e, _) => ErrorView(error: e),
                  data: (events) {
                    final item = events.map((e) => itemsById[e.itemId]).whereType<MaterialItem>().firstOrNull;
                    return ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(tag!, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800)),
                            ),
                            if (canEdit)
                              TextButton.icon(
                                onPressed: () => _record(context, ref, events),
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Record event'),
                              ),
                          ],
                        ),
                        if (item != null)
                          Text(
                            '${item.itemCode} · ${item.description}${item.heatNumber == null ? '' : ' · heat ${item.heatNumber}'}',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          ),
                        if (events.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 16),
                            child: Text('No events recorded for this tag yet.', style: TextStyle(color: AppTheme.textMuted)),
                          ),
                        const SizedBox(height: 8),
                        for (final (i, e) in events.indexed)
                          _TraceStep(
                            event: e,
                            last: i == events.length - 1,
                            location: e.componentId == null ? null : byId[e.componentId],
                            onShow: (c) => actions.selectNode(c.meshNodeId),
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

class _TraceStep extends StatelessWidget {
  const _TraceStep({required this.event, required this.last, required this.location, required this.onShow});

  final TraceEvent event;
  final bool last;
  final TwinComponent? location;
  final ValueChanged<TwinComponent> onShow;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Icon(event.type.icon, size: 18, color: last ? AppTheme.accent : AppTheme.textMuted),
                if (!last) const Expanded(child: VerticalDivider(width: 1, thickness: 1.5)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.type.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                  Text(formatDateTime(event.recordedAt), style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  if (location != null)
                    InkWell(
                      onTap: () => onShow(location!),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.place_outlined, size: 14, color: AppTheme.accent),
                            const SizedBox(width: 4),
                            Text(shortComponentName(location), style: const TextStyle(fontSize: 12, color: AppTheme.accent)),
                          ],
                        ),
                      ),
                    ),
                  if (event.notes != null) Text(event.notes!, style: const TextStyle(fontSize: 11.5)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
