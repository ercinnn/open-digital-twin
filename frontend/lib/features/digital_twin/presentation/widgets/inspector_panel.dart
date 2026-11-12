import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/status/component_status.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/async_states.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../domain/entities/twin_entities.dart';
import '../providers/twin_providers.dart';
import 'documents_section.dart';
import 'telemetry_panel.dart';

/// Right-hand inspector: properties, status switcher, documents and live telemetry.
class InspectorPanel extends ConsumerWidget {
  const InspectorPanel({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final component = ref.watch(selectedComponentProvider(projectId));
    if (component == null) {
      return const EmptyView(
        icon: Icons.ads_click,
        message: 'Select a component in the 3D view\nor in the component tree.',
      );
    }
    return ListView(
      key: ValueKey(component.id),
      padding: const EdgeInsets.all(14),
      children: [
        _Header(component: component),
        const SizedBox(height: 12),
        _StatusSwitcher(component: component),
        const SizedBox(height: 12),
        _PropertiesCard(component: component),
        const SizedBox(height: 12),
        TelemetryPanel(componentId: component.id),
        const SizedBox(height: 12),
        DocumentsSection(projectId: projectId, component: component),
        if (component.metadata.isNotEmpty) ...[
          const SizedBox(height: 12),
          _MetadataCard(metadata: component.metadata),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.component});

  final TwinComponent component;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(component.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.25)),
        const SizedBox(height: 8),
        Row(
          children: [
            StatusBadge(status: component.status),
            const SizedBox(width: 8),
            Flexible(
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: component.meshNodeId));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Copied ${component.meshNodeId}'), duration: const Duration(seconds: 2)),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          component.meshNodeId,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppTheme.textMuted),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.copy, size: 12, color: AppTheme.textMuted),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusSwitcher extends ConsumerStatefulWidget {
  const _StatusSwitcher({required this.component});

  final TwinComponent component;

  @override
  ConsumerState<_StatusSwitcher> createState() => _StatusSwitcherState();
}

class _StatusSwitcherState extends ConsumerState<_StatusSwitcher> {
  bool _saving = false;

  Future<void> _set(ComponentStatus status) async {
    if (status == widget.component.status) return;
    setState(() => _saving = true);
    try {
      await ref.read(twinRepositoryProvider).updateStatus(widget.component.id, status);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status update failed: $e'), backgroundColor: const Color(0xFF7F1D1D)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Status',
      icon: Icons.traffic_outlined,
      trailing: _saving
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          : const Tooltip(
              message: 'Writes components.status – Supabase Realtime recolors the 3D mesh on every client.',
              child: Icon(Icons.info_outline, size: 16, color: AppTheme.textMuted),
            ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final s in ComponentStatus.values)
            ChoiceChip(
              selected: widget.component.status == s,
              onSelected: _saving ? null : (_) => _set(s),
              avatar: Icon(s.icon, size: 16, color: s.color),
              label: Text(s.label),
              selectedColor: s.color.withValues(alpha: 0.22),
              side: BorderSide(color: widget.component.status == s ? s.color : AppTheme.outline),
              showCheckmark: false,
            ),
        ],
      ),
    );
  }
}

class _PropertiesCard extends StatelessWidget {
  const _PropertiesCard({required this.component});

  final TwinComponent component;

  String _num(double? v, String unit, {int digits = 2}) => v == null ? '—' : '${v.toStringAsFixed(digits)} $unit';

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Category', component.category?.replaceAll('_', ' ') ?? '—'),
      ('Material', component.material ?? '—'),
      ('Weight', _num(component.weightKg, 'kg', digits: 1)),
      ('Volume', _num(component.volumeM3, 'm³', digits: 4)),
      ('Updated', component.updatedAt.toString().substring(0, 19)),
    ];
    return SectionCard(
      title: 'Properties',
      icon: Icons.tune,
      child: _KeyValueTable(rows: rows),
    );
  }
}

class _MetadataCard extends StatelessWidget {
  const _MetadataCard({required this.metadata});

  final Map<String, dynamic> metadata;

  @override
  Widget build(BuildContext context) {
    final keys = metadata.keys.toList()..sort();
    return SectionCard(
      title: 'Metadata',
      icon: Icons.data_object,
      child: _KeyValueTable(
        rows: [
          for (final k in keys)
            (
              k.replaceAll('_', ' '),
              metadata[k] is Map || metadata[k] is List ? '${metadata[k]}'.replaceAll(RegExp(r'\s+'), ' ') : '${metadata[k]}',
            ),
        ],
      ),
    );
  }
}

class _KeyValueTable extends StatelessWidget {
  const _KeyValueTable({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (k, v) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(k, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                ),
                Expanded(
                  child: SelectableText(v, style: const TextStyle(fontSize: 12.5)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
