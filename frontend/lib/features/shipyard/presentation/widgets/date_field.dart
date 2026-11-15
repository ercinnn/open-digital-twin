import 'package:flutter/material.dart';

import '../../domain/entities/production_entities.dart';

/// Date picker field; [clearable] fields get a clear button (optional dates).
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.initial,
    required this.enabled,
    required this.onChanged,
    this.helper,
    this.clearable = true,
  });

  final String label;
  final DateTime? value;
  final DateTime initial;
  final bool enabled;
  final ValueChanged<DateTime?> onChanged;
  final String? helper;
  final bool clearable;

  Future<void> _pick(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) onChanged(dateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => _pick(context) : null,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        isEmpty: value == null,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          enabled: enabled,
          suffixIcon: value == null || !clearable
              ? const Icon(Icons.event, size: 18)
              : IconButton(
                  tooltip: 'Clear',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: enabled ? () => onChanged(null) : null,
                ),
        ),
        child: Text(value == null ? '' : formatDate(value)),
      ),
    );
  }
}
