import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../domain/entities/production_entities.dart';
import '../../providers/shipyard_providers.dart';

/// Play / scrub the 3D production timeline. "Live" returns to today.
class TimelineBar extends ConsumerWidget {
  const TimelineBar({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeline = ref.watch(timelineProvider(projectId));
    final notifier = ref.read(timelineProvider(projectId).notifier);
    final today = ref.watch(todayProvider);
    final range = ref.watch(scheduleProvider(projectId)).range(today);
    if (range == null) return const SizedBox.shrink();
    final (start, end) = range;
    final total = daysBetween(start, end).toDouble();
    final date = timeline.date ?? today;
    final value = daysBetween(start, date).clamp(0, total.toInt()).toDouble();
    final offset = daysBetween(today, date);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'One week back',
            visualDensity: VisualDensity.compact,
            onPressed: () => notifier.step(-7),
            icon: const Icon(Icons.fast_rewind, size: 18),
          ),
          IconButton.filledTonal(
            tooltip: timeline.playing ? 'Pause' : 'Play the production timeline in 3D',
            visualDensity: VisualDensity.compact,
            onPressed: notifier.togglePlay,
            icon: Icon(timeline.playing ? Icons.pause : Icons.play_arrow, size: 20),
          ),
          IconButton(
            tooltip: 'One week forward',
            visualDensity: VisualDensity.compact,
            onPressed: () => notifier.step(7),
            icon: const Icon(Icons.fast_forward, size: 18),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                activeTrackColor: timeline.isLive ? AppTheme.accent : AppTheme.construction,
                thumbColor: timeline.isLive ? AppTheme.accent : AppTheme.construction,
              ),
              child: Slider(
                min: 0,
                max: total,
                value: value,
                onChanged: (v) => notifier.setDate(addDays(start, v.round())),
              ),
            ),
          ),
          SizedBox(
            width: 128,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formatDate(date), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                Text(
                  timeline.isLive
                      ? 'Live (today)'
                      : offset == 0
                      ? 'Today'
                      : offset > 0
                      ? 'Plan: +$offset days'
                      : 'History: $offset days',
                  style: TextStyle(fontSize: 10.5, color: timeline.isLive ? AppTheme.accent : AppTheme.construction),
                ),
              ],
            ),
          ),
          FilterChip(
            selected: timeline.isLive,
            showCheckmark: false,
            avatar: Icon(Icons.sensors, size: 16, color: timeline.isLive ? AppTheme.accent : AppTheme.textMuted),
            label: const Text('Live'),
            onSelected: (_) => notifier.goLive(),
          ),
        ],
      ),
    );
  }
}
