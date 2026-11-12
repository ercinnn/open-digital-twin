import 'package:flutter/material.dart';

import '../../core/status/component_status.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status, this.dense = false});

  final ComponentStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 10, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: status.color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: dense ? 12 : 14, color: status.color),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: TextStyle(color: status.color, fontSize: dense ? 11 : 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.status, this.size = 10});

  final ComponentStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: status.color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: status.color.withValues(alpha: 0.5), blurRadius: 6)],
      ),
    );
  }
}
