import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../domain/entities/twin_entities.dart';

/// BOM grouped by category; tapping a row selects + focuses the mesh in 3D.
class ComponentTree extends StatefulWidget {
  const ComponentTree({
    super.key,
    required this.components,
    required this.selectedNodeId,
    required this.onSelect,
  });

  final List<TwinComponent> components;
  final String? selectedNodeId;
  final ValueChanged<TwinComponent> onSelect;

  @override
  State<ComponentTree> createState() => _ComponentTreeState();
}

class _ComponentTreeState extends State<ComponentTree> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final filtered = widget.components
        .where((c) => q.isEmpty || c.name.toLowerCase().contains(q) || c.meshNodeId.toLowerCase().contains(q))
        .toList();
    final groups = <String, List<TwinComponent>>{};
    for (final c in filtered) {
      groups.putIfAbsent(c.category ?? 'uncategorized', () => []).add(c);
    }
    final categories = groups.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              const Icon(Icons.account_tree_outlined, size: 16, color: AppTheme.accent),
              const SizedBox(width: 8),
              const Text('COMPONENTS',
                  style: TextStyle(fontSize: 11.5, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: AppTheme.textMuted)),
              const Spacer(),
              Text('${widget.components.length}', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              hintText: 'Filter by name or node id',
              prefixIcon: Icon(Icons.search, size: 18),
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              for (final category in categories) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                  child: Text(
                    category.replaceAll('_', ' ').toUpperCase(),
                    style: const TextStyle(fontSize: 10.5, letterSpacing: 0.8, color: AppTheme.textMuted),
                  ),
                ),
                for (final c in groups[category]!)
                  _ComponentRow(
                    component: c,
                    selected: c.meshNodeId == widget.selectedNodeId,
                    onTap: () => widget.onSelect(c),
                  ),
              ],
              if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No matching components.', style: TextStyle(color: AppTheme.textMuted)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ComponentRow extends StatelessWidget {
  const _ComponentRow({required this.component, required this.selected, required this.onTap});

  final TwinComponent component;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Material(
        color: selected ? AppTheme.accent.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                StatusDot(status: component.status, size: 9),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        component.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                      ),
                      Text(
                        component.meshNodeId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
