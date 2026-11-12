import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/async_states.dart';
import '../../domain/entities/twin_entities.dart';
import '../providers/twin_providers.dart';

/// Live `telemetry_logs` for one component: per-metric tiles with sparklines and
/// a feed of the most recent readings. Updates through Supabase Realtime.
class TelemetryPanel extends ConsumerWidget {
  const TelemetryPanel({super.key, required this.componentId});

  final String componentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final telemetry = ref.watch(telemetryProvider(componentId));
    return SectionCard(
      title: 'Live telemetry',
      icon: Icons.sensors,
      trailing: const _LiveDot(),
      child: telemetry.when(
        loading: () => const SizedBox(height: 80, child: LoadingView()),
        error: (e, _) => Text('Telemetry unavailable: $e', style: const TextStyle(color: Color(0xFFF87171))),
        data: (readings) {
          if (readings.isEmpty) {
            return const Text('No readings yet. Use "Simulate Live Sensor".',
                style: TextStyle(color: AppTheme.textMuted));
          }
          final byMetric = <String, List<TelemetryReading>>{};
          for (final r in readings) {
            byMetric.putIfAbsent(r.metricName, () => []).add(r);
          }
          final metrics = byMetric.keys.toList()..sort();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final m in metrics) ...[
                _MetricTile(readings: byMetric[m]!),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 4),
              const Text('RECENT READINGS',
                  style: TextStyle(fontSize: 10.5, letterSpacing: 0.8, color: AppTheme.textMuted)),
              const SizedBox(height: 4),
              for (final r in readings.take(8))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 64,
                        child: Text(_time(r.recordedAt),
                            style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted, fontFamily: 'monospace')),
                      ),
                      Expanded(
                        child: Text(r.metricLabel, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                      ),
                      Text('${_fmt(r.metricValue)} ${r.unit ?? ''}',
                          style: const TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()])),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}

String _fmt(double v) => v.abs() >= 100 ? v.toStringAsFixed(1) : v.toStringAsFixed(2);

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.readings});

  /// Newest first.
  final List<TelemetryReading> readings;

  @override
  Widget build(BuildContext context) {
    final latest = readings.first;
    final series = readings.take(40).toList().reversed.map((r) => r.metricValue).toList();
    final previous = readings.length > 1 ? readings[1].metricValue : latest.metricValue;
    final delta = latest.metricValue - previous;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(latest.metricLabel,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(_fmt(latest.metricValue), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 4),
                    Text(latest.unit ?? '', style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
                  ],
                ),
                Text(
                  '${delta >= 0 ? '▲' : '▼'} ${_fmt(delta.abs())}',
                  style: TextStyle(fontSize: 10.5, color: delta >= 0 ? const Color(0xFFFBBF24) : const Color(0xFF60A5FA)),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 6,
            child: SizedBox(height: 44, child: CustomPaint(painter: _SparklinePainter(series))),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final span = (maxV - minV).abs() < 1e-9 ? 1.0 : maxV - minV;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height - ((values[i] - minV) / span) * (size.height - 4) - 2;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppTheme.accent.withValues(alpha: 0.28), AppTheme.accent.withValues(alpha: 0.0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = AppTheme.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
    final last = Offset(size.width, size.height - ((values.last - minV) / span) * (size.height - 4) - 2);
    canvas.drawCircle(last, 2.8, Paint()..color = AppTheme.accent);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.values != values;
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_c),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: Color(0xFF22C55E)),
          SizedBox(width: 4),
          Text('REALTIME', style: TextStyle(fontSize: 10, color: Color(0xFF22C55E), letterSpacing: 0.8)),
        ],
      ),
    );
  }
}
