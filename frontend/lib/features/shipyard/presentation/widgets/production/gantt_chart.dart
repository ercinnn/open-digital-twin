import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../domain/entities/production_entities.dart';

/// One Gantt row: a hull header or a block / hull-activities lane group.
class GanttRow {
  const GanttRow.header({required this.label, this.trailing}) : activities = const [], sublabel = null, isHeader = true;

  const GanttRow({required this.label, required this.activities, this.sublabel})
    : isHeader = false,
      trailing = null;

  final String label;
  final String? sublabel;
  final String? trailing;
  final bool isHeader;
  final List<ProductionActivity> activities;
}

/// Pannable / zoomable Gantt chart painted on one canvas (fixed label column and
/// date header). Drag on the header scrubs the 3D timeline cursor.
class GanttChart extends StatefulWidget {
  const GanttChart({
    super.key,
    required this.rows,
    required this.rangeStart,
    required this.rangeEnd,
    required this.today,
    required this.cursor,
    required this.onScrub,
    required this.onTapActivity,
    this.selectedActivityId,
    this.highlightComponentId,
  });

  final List<GanttRow> rows;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final DateTime today;
  final DateTime cursor;
  final ValueChanged<DateTime> onScrub;
  final ValueChanged<ProductionActivity> onTapActivity;
  final String? selectedActivityId;
  final String? highlightComponentId;

  @override
  State<GanttChart> createState() => GanttChartState();
}

class GanttChartState extends State<GanttChart> {
  static const labelWidth = 178.0;
  static const headerHeight = 34.0;
  static const laneHeight = 22.0;
  static const headerRowHeight = 24.0;

  /// Bars narrower than this get no text inside.
  static const minLabelledBarWidth = 46.0;

  /// Half diagonal of the milestone diamond.
  static const milestoneHalf = 7.0;

  double _pxPerDay = 9;
  double _scrollX = 0;
  double _scrollY = 0;
  bool _initialized = false;
  bool _scrubbing = false;
  Size _size = Size.zero;

  double get pxPerDay => _pxPerDay;

  void zoom(double factor) {
    setState(() {
      final centerDay = (_scrollX + (_size.width - labelWidth) / 2) / _pxPerDay;
      _pxPerDay = (_pxPerDay * factor).clamp(2.0, 40.0);
      _scrollX = centerDay * _pxPerDay - (_size.width - labelWidth) / 2;
      _clampScroll();
    });
  }

  void scrollToDate(DateTime date) {
    setState(() {
      _scrollX = daysBetween(widget.rangeStart, date) * _pxPerDay - (_size.width - labelWidth) * 0.35;
      _clampScroll();
    });
  }

  int get _totalDays => math.max(1, daysBetween(widget.rangeStart, widget.rangeEnd));

  _GanttLayout _layout() => _GanttLayout.build(widget.rows, widget.today, _pxPerDay);

  void _clampScroll() {
    final layout = _layout();
    final maxX = math.max(0.0, _totalDays * _pxPerDay - (_size.width - labelWidth));
    final maxY = math.max(0.0, layout.contentHeight - (_size.height - headerHeight));
    _scrollX = _scrollX.clamp(0.0, maxX);
    _scrollY = _scrollY.clamp(0.0, maxY);
  }

  DateTime _dateAtX(double x) {
    final day = ((x - labelWidth + _scrollX) / _pxPerDay).floor();
    return addDays(widget.rangeStart, day.clamp(0, _totalDays));
  }

  ProductionActivity? _hit(Offset p) {
    if (p.dx < labelWidth || p.dy < headerHeight) return null;
    final layout = _layout();
    for (final bar in layout.bars) {
      final rect = bar.isMilestone ? _milestoneRect(bar) : _barRect(bar);
      if (rect.inflate(2).contains(p)) return bar.activity;
    }
    return null;
  }

  /// Diamond + label of a milestone bar ([_Bar.isMilestone]).
  Rect _milestoneRect(_Bar bar) {
    final rect = _barRect(bar);
    final cx = rect.center.dx;
    final labelX = math.max(rect.right, cx + milestoneHalf) + 4;
    return Rect.fromLTRB(math.min(rect.left, cx - milestoneHalf), rect.top, labelX + bar.labelWidth, rect.bottom);
  }

  Rect _barRect(_Bar bar) {
    final x0 = labelWidth + daysBetween(widget.rangeStart, bar.start) * _pxPerDay - _scrollX;
    final x1 = labelWidth + daysBetween(widget.rangeStart, bar.end) * _pxPerDay - _scrollX;
    final y = headerHeight + bar.top - _scrollY;
    return Rect.fromLTWH(x0, y + 3, math.max(3, x1 - x0), laneHeight - 8);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        if (!_initialized && _size.width > labelWidth) {
          _initialized = true;
          _scrollX = daysBetween(widget.rangeStart, widget.today) * _pxPerDay - (_size.width - labelWidth) * 0.35;
        }
        _clampScroll();
        return Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              setState(() {
                final horizontal = HardwareKeyboard.instance.isShiftPressed || event.scrollDelta.dx.abs() > 0;
                if (horizontal) {
                  _scrollX += event.scrollDelta.dx != 0 ? event.scrollDelta.dx : event.scrollDelta.dy;
                } else {
                  _scrollY += event.scrollDelta.dy;
                }
                _clampScroll();
              });
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              if (d.localPosition.dy < headerHeight && d.localPosition.dx > labelWidth) {
                widget.onScrub(_dateAtX(d.localPosition.dx));
                return;
              }
              final hit = _hit(d.localPosition);
              if (hit != null) widget.onTapActivity(hit);
            },
            onPanStart: (d) => _scrubbing = d.localPosition.dy < headerHeight && d.localPosition.dx > labelWidth,
            onPanUpdate: (d) {
              if (_scrubbing) {
                widget.onScrub(_dateAtX(d.localPosition.dx));
                return;
              }
              setState(() {
                _scrollX -= d.delta.dx;
                _scrollY -= d.delta.dy;
                _clampScroll();
              });
            },
            onPanEnd: (_) => _scrubbing = false,
            child: CustomPaint(
              size: _size,
              painter: _GanttPainter(
                layout: _layout(),
                rangeStart: widget.rangeStart,
                totalDays: _totalDays,
                today: widget.today,
                cursor: widget.cursor,
                pxPerDay: _pxPerDay,
                scrollX: _scrollX,
                scrollY: _scrollY,
                selectedActivityId: widget.selectedActivityId,
                highlightComponentId: widget.highlightComponentId,
                barRect: _barRect,
                milestoneRect: _milestoneRect,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Bar {
  const _Bar(this.activity, this.start, this.end, this.top, {this.label, this.labelWidth = 0});
  final ProductionActivity activity;
  final DateTime start;
  final DateTime end;
  final double top;

  /// Set for a milestone drawn as a diamond with this text beside it.
  final String? label;
  final double labelWidth;

  bool get isMilestone => label != null;
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

const _milestoneStyle = TextStyle(fontSize: 10, fontWeight: FontWeight.w700);

class _RowBox {
  const _RowBox(this.row, this.top, this.height);
  final GanttRow row;
  final double top;
  final double height;
}

class _GanttLayout {
  const _GanttLayout(this.rows, this.bars, this.contentHeight);

  final List<_RowBox> rows;
  final List<_Bar> bars;
  final double contentHeight;

  /// Text of a milestone diamond, e.g. "Launching 31 Dec".
  static String milestoneLabel(ProductionActivity a, DateTime today) {
    final d = a.forecastStart(today);
    return '${a.stage.label} ${d.day} ${_months[d.month - 1]}';
  }

  static _GanttLayout build(List<GanttRow> rows, DateTime today, double pxPerDay) {
    final boxes = <_RowBox>[];
    final bars = <_Bar>[];
    var y = 0.0;
    for (final row in rows) {
      if (row.isHeader) {
        boxes.add(_RowBox(row, y, GanttChartState.headerRowHeight));
        y += GanttChartState.headerRowHeight;
        continue;
      }
      // Greedy lane packing of overlapping bars. A short milestone (launching,
      // sea trials, delivery) too narrow to read becomes a diamond with a
      // label; the label takes room in its lane so no other bar covers it.
      final items = row.activities.toList()
        ..sort((a, b) => a.forecastStart(today).compareTo(b.forecastStart(today)));
      final laneEnds = <DateTime>[];
      final placed = <(ProductionActivity, int, String?, double)>[];
      for (final a in items) {
        final s = a.forecastStart(today);
        var end = a.forecastEnd(today);
        String? label;
        var labelWidth = 0.0;
        final barPx = daysBetween(s, end) * pxPerDay;
        if (a.stage.isMilestone && barPx < GanttChartState.minLabelledBarWidth) {
          label = milestoneLabel(a, today);
          final painter = TextPainter(
            text: TextSpan(text: label, style: _milestoneStyle),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout();
          labelWidth = painter.width;
          painter.dispose();
          final markerPx = math.max(barPx, barPx / 2 + GanttChartState.milestoneHalf) + 4 + labelWidth + 6;
          final reserved = addDays(s, (markerPx / pxPerDay).ceil());
          if (reserved.isAfter(end)) end = reserved;
        }
        var lane = laneEnds.indexWhere((laneEnd) => !s.isBefore(laneEnd));
        if (lane < 0) {
          laneEnds.add(end);
          lane = laneEnds.length - 1;
        } else {
          laneEnds[lane] = end;
        }
        placed.add((a, lane, label, labelWidth));
      }
      final lanes = math.max(1, laneEnds.length);
      final height = lanes * GanttChartState.laneHeight + 4;
      for (final (a, lane, label, labelWidth) in placed) {
        bars.add(
          _Bar(
            a,
            a.forecastStart(today),
            a.forecastEnd(today),
            y + 2 + lane * GanttChartState.laneHeight,
            label: label,
            labelWidth: labelWidth,
          ),
        );
      }
      boxes.add(_RowBox(row, y, height));
      y += height;
    }
    return _GanttLayout(boxes, bars, y + 8);
  }
}

class _GanttPainter extends CustomPainter {
  _GanttPainter({
    required this.layout,
    required this.rangeStart,
    required this.totalDays,
    required this.today,
    required this.cursor,
    required this.pxPerDay,
    required this.scrollX,
    required this.scrollY,
    required this.selectedActivityId,
    required this.highlightComponentId,
    required this.barRect,
    required this.milestoneRect,
  });

  final _GanttLayout layout;
  final DateTime rangeStart;
  final int totalDays;
  final DateTime today;
  final DateTime cursor;
  final double pxPerDay;
  final double scrollX;
  final double scrollY;
  final String? selectedActivityId;
  final String? highlightComponentId;
  final Rect Function(_Bar) barRect;
  final Rect Function(_Bar) milestoneRect;

  static const _late = Color(0xFFEF4444);

  double _x(DateTime d) => GanttChartState.labelWidth + daysBetween(rangeStart, d) * pxPerDay - scrollX;

  void _text(Canvas canvas, String text, Offset at, {double size = 11, Color color = AppTheme.textMuted, FontWeight weight = FontWeight.w500, double? maxWidth}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: size, color: color, fontWeight: weight)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? double.infinity);
    tp.paint(canvas, at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    const lw = GanttChartState.labelWidth;
    const hh = GanttChartState.headerHeight;
    canvas.drawRect(Offset.zero & size, Paint()..color = AppTheme.background);

    // ---- body (clipped)
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(lw, hh, size.width, size.height));
    for (final box in layout.rows) {
      final top = hh + box.top - scrollY;
      if (top > size.height || top + box.height < hh) continue;
      if (box.row.isHeader) {
        canvas.drawRect(Rect.fromLTWH(lw, top, size.width, box.height), Paint()..color = AppTheme.surfaceHigh);
      }
      canvas.drawLine(Offset(lw, top + box.height), Offset(size.width, top + box.height), Paint()..color = AppTheme.outline.withValues(alpha: 0.5));
    }
    // weekly grid
    final firstDay = (scrollX / pxPerDay).floor();
    final lastDay = ((scrollX + size.width - lw) / pxPerDay).ceil();
    final grid = Paint()..color = AppTheme.outline.withValues(alpha: 0.35);
    for (var day = firstDay; day <= lastDay && day <= totalDays; day++) {
      final d = addDays(rangeStart, day);
      if (d.weekday == DateTime.monday) {
        final x = _x(d);
        canvas.drawLine(Offset(x, hh), Offset(x, size.height), grid);
      }
    }
    // bars
    for (final bar in layout.bars) {
      final rect = barRect(bar);
      final extent = bar.isMilestone ? milestoneRect(bar) : rect;
      if (extent.right < lw || extent.left > size.width || extent.bottom < hh || extent.top > size.height) continue;
      if (bar.isMilestone) {
        _milestone(canvas, bar, rect);
        continue;
      }
      final a = bar.activity;
      final color = a.stage.color;
      // planned window (thin line under the bar)
      final px0 = _x(a.plannedStart);
      final px1 = _x(a.plannedEnd);
      canvas.drawRect(
        Rect.fromLTWH(px0, rect.bottom + 1, math.max(2, px1 - px0), 2.5),
        Paint()..color = AppTheme.textMuted.withValues(alpha: 0.55),
      );
      final r = RRect.fromRectAndRadius(rect, const Radius.circular(4));
      canvas.drawRRect(r, Paint()..color = color.withValues(alpha: a.isNotStarted ? 0.22 : 0.38));
      final progress = (a.isDone ? 100 : a.progressPct).clamp(0, 100) / 100;
      if (progress > 0) {
        canvas.save();
        canvas.clipRRect(r);
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, rect.width * progress, rect.height), Paint()..color = color.withValues(alpha: 0.92));
        canvas.restore();
      }
      final late = a.isLate(today);
      final selected = a.id == selectedActivityId;
      final related = highlightComponentId != null && a.componentId == highlightComponentId;
      if (late || selected || related) {
        canvas.drawRRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = selected ? 2.2 : 1.4
            ..color = selected ? Colors.white : (late ? _late : AppTheme.accent),
        );
      }
      if (rect.width > 46) {
        _text(
          canvas,
          '${a.stage.label}${a.isDone ? '' : ' ${a.progressPct.round()}%'}',
          Offset(rect.left + 5, rect.top + 1),
          size: 10,
          color: progress > 0.5 ? const Color(0xFF0B1220) : Colors.white,
          weight: FontWeight.w600,
          maxWidth: rect.width - 8,
        );
      }
    }
    // today + cursor
    final tx = _x(today);
    canvas.drawLine(Offset(tx, hh), Offset(tx, size.height), Paint()..color = AppTheme.accent..strokeWidth = 1.5);
    if (cursor != today) {
      final cx = _x(cursor);
      canvas.drawLine(Offset(cx, hh), Offset(cx, size.height), Paint()..color = AppTheme.construction..strokeWidth = 1.5);
    }
    canvas.restore();

    // ---- header
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, hh), Paint()..color = AppTheme.surface);
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(lw, 0, size.width, hh));
    for (var day = firstDay; day <= lastDay && day <= totalDays; day++) {
      final d = addDays(rangeStart, day);
      final x = _x(d);
      if (d.day == 1 || day == firstDay) {
        _text(canvas, '${_months[d.month - 1]} ${d.year}', Offset(x + 3, 2), size: 10.5, color: Colors.white70, weight: FontWeight.w700);
        canvas.drawLine(Offset(x, 0), Offset(x, hh), Paint()..color = AppTheme.outline);
      }
      if (d.weekday == DateTime.monday && pxPerDay >= 4) {
        _text(canvas, '${d.day}', Offset(x + 2, 18), size: 9.5);
      }
    }
    _marker(canvas, tx, AppTheme.accent, 'Today');
    if (cursor != today) _marker(canvas, _x(cursor), AppTheme.construction, formatDate(cursor));
    canvas.restore();
    canvas.drawLine(Offset(0, hh), Offset(size.width, hh), Paint()..color = AppTheme.outline);

    // ---- label column
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, hh, lw, size.height));
    canvas.drawRect(Rect.fromLTRB(0, hh, lw, size.height), Paint()..color = AppTheme.surface);
    for (final box in layout.rows) {
      final top = hh + box.top - scrollY;
      if (top > size.height || top + box.height < hh) continue;
      if (box.row.isHeader) {
        canvas.drawRect(Rect.fromLTWH(0, top, lw, box.height), Paint()..color = AppTheme.surfaceHigh);
        _text(canvas, box.row.label, Offset(8, top + 5), size: 11.5, color: Colors.white, weight: FontWeight.w800, maxWidth: lw - 70);
        if (box.row.trailing != null) {
          _text(canvas, box.row.trailing!, Offset(lw - 64, top + 6), size: 10.5, color: AppTheme.accent, weight: FontWeight.w700, maxWidth: 60);
        }
      } else {
        _text(canvas, box.row.label, Offset(14, top + 3), size: 11.5, color: const Color(0xFFE2E8F0), weight: FontWeight.w600, maxWidth: lw - 20);
        if (box.row.sublabel != null && box.height > 26) {
          _text(canvas, box.row.sublabel!, Offset(14, top + 17), size: 9.5, maxWidth: lw - 20);
        }
      }
      canvas.drawLine(Offset(0, top + box.height), Offset(lw, top + box.height), Paint()..color = AppTheme.outline.withValues(alpha: 0.5));
    }
    canvas.restore();
    canvas.drawLine(const Offset(lw, 0), Offset(lw, size.height), Paint()..color = AppTheme.outline);
    _text(canvas, 'HULL / BLOCK', const Offset(10, 11), size: 10, weight: FontWeight.w700);
  }

  /// Diamond on the (narrow) bar plus its label: hollow = not started, left
  /// half filled = running, filled = done; outline red = late, white = selected.
  void _milestone(Canvas canvas, _Bar bar, Rect rect) {
    final a = bar.activity;
    final color = a.stage.color;
    // planned window (thin line under the marker) and the actual / forecast span
    final px0 = _x(a.plannedStart);
    final px1 = _x(a.plannedEnd);
    canvas.drawRect(
      Rect.fromLTWH(px0, rect.bottom + 1, math.max(2, px1 - px0), 2.5),
      Paint()..color = AppTheme.textMuted.withValues(alpha: 0.55),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(rect.left, rect.center.dy - 2, rect.width, 4), const Radius.circular(2)),
      Paint()..color = color.withValues(alpha: 0.45),
    );
    const h = GanttChartState.milestoneHalf;
    final c = rect.center;
    final diamond = Path()
      ..moveTo(c.dx, c.dy - h)
      ..lineTo(c.dx + h, c.dy)
      ..lineTo(c.dx, c.dy + h)
      ..lineTo(c.dx - h, c.dy)
      ..close();
    canvas.drawPath(diamond, Paint()..color = AppTheme.background);
    if (a.isDone) {
      canvas.drawPath(diamond, Paint()..color = color);
    } else {
      canvas.drawPath(diamond, Paint()..color = color.withValues(alpha: a.isNotStarted ? 0.22 : 0.38));
      if (a.isActive) {
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(c.dx - h, c.dy - h, c.dx, c.dy + h));
        canvas.drawPath(diamond, Paint()..color = color);
        canvas.restore();
      }
    }
    final late = a.isLate(today);
    final selected = a.id == selectedActivityId;
    final related = highlightComponentId != null && a.componentId == highlightComponentId;
    canvas.drawPath(
      diamond,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2.2 : 1.4
        ..color = selected ? Colors.white : (late ? _late : (related ? AppTheme.accent : color)),
    );
    _text(
      canvas,
      bar.label!,
      Offset(math.max(rect.right, c.dx + h) + 4, rect.top + 1),
      size: _milestoneStyle.fontSize!,
      color: late ? const Color(0xFFFCA5A5) : const Color(0xFFE2E8F0),
      weight: _milestoneStyle.fontWeight!,
    );
  }

  void _marker(Canvas canvas, double x, Color color, String text) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(fontSize: 9.5, color: Color(0xFF0B1220), fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = RRect.fromRectAndRadius(Rect.fromLTWH(x - tp.width / 2 - 4, 18, tp.width + 8, 14), const Radius.circular(4));
    canvas.drawRRect(rect, Paint()..color = color);
    tp.paint(canvas, Offset(x - tp.width / 2, 19));
  }

  @override
  bool shouldRepaint(covariant _GanttPainter old) => true;
}
