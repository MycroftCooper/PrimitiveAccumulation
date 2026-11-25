import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/models.dart';
import '../core/theme.dart';
import 'widgets.dart';

class ChartValue {
  final String label;
  final int amount;
  final VoidCallback onTap;
  final Color color;
  const ChartValue(this.label, this.amount, this.color, this.onTap);
}

class BalancePoint {
  final Snapshot snapshot;
  final int amount;
  final VoidCallback onTap;
  const BalancePoint(this.snapshot, this.amount, this.onTap);
}

class BalanceChart extends StatelessWidget {
  final List<BalancePoint> points;
  final String title;
  final bool calendar;
  const BalanceChart(
    this.title,
    this.points, {
    super.key,
    this.calendar = false,
  });
  @override
  Widget build(BuildContext c) {
    if (points.isEmpty) return const Blank('暂无走势', '完成第一次盘点后即可查看。');
    final values = points.map((p) => p.amount),
        lo = values.reduce(math.min),
        hi = values.reduce(math.max);
    final first = points.first.snapshot.time.millisecondsSinceEpoch,
        last = points.last.snapshot.time.millisecondsSinceEpoch;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(c).textTheme.titleMedium),
          Text(
            points.length == 1
                ? '首次盘点'
                : '${day(points.first.snapshot.time)} 至 ${day(points.last.snapshot.time)}',
          ),
          LayoutBuilder(
            builder: (c, box) {
              final w = math.max(box.maxWidth, points.length * 94.0);
              // Keep each observation reachable, even for multiple submissions on one date.
              final slack = w - points.length * 94.0;
              final coords = List.generate(points.length, (i) {
                double x = points.length == 1
                    ? w / 2
                    : 47 + i * (w - 94) / (points.length - 1);
                if (calendar && points.length > 1 && last > first) {
                  x =
                      47 +
                      i * 94 +
                      slack *
                          (points[i].snapshot.time.millisecondsSinceEpoch -
                              first) /
                          (last - first);
                }
                return Offset(
                  x,
                  hi == lo ? 64 : 97 - (points[i].amount - lo) / (hi - lo) * 60,
                );
              });
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: w,
                  height: 161,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _Line(
                            coords,
                            Theme.of(c).colorScheme.primary,
                            Theme.of(c).dividerColor,
                          ),
                        ),
                      ),
                      for (int i = 0; i < points.length; i++) ...[
                        Positioned(
                          left: coords[i].dx - 47,
                          top: coords[i].dy - 33,
                          width: 94,
                          height: 46,
                          child: InkWell(
                            onTap: points[i].onTap,
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(money(points[i].amount)),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: coords[i].dx - 47,
                          top: 108,
                          width: 94,
                          height: 51,
                          child: TextButton(
                            onPressed: points[i].onTap,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '${day(points[i].snapshot.time)}\n第 ${points[i].snapshot.id} 期',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Line extends CustomPainter {
  final List<Offset> points;
  final Color color, grid;
  _Line(this.points, this.color, this.grid);
  @override
  void paint(Canvas c, Size s) {
    final paint = Paint()..color = grid;
    for (final y in [37.0, 97.0]) {
      c.drawLine(Offset(24, y), Offset(s.width - 24, y), paint);
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    c.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    for (final p in points) {
      c.drawCircle(p, 4.5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_Line old) => true;
}

class ShareChart extends StatelessWidget {
  final String title;
  final List<ChartValue> parts;
  const ShareChart(this.title, this.parts, {super.key});
  @override
  Widget build(BuildContext c) {
    final total = parts.fold(0, (v, p) => v + p.amount);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(c).textTheme.titleMedium),
          Text('合计 ${money(total)}'),
          if (total > 0)
            Center(
              child: Semantics(
                label: title,
                child: GestureDetector(
                  onTapUp: (e) {
                    final pos = e.localPosition - const Offset(76, 76);
                    if (pos.distance > 71) return;
                    final portion =
                        ((math.atan2(pos.dy, pos.dx) + math.pi / 2) %
                            (math.pi * 2)) /
                        (2 * math.pi);
                    double end = 0;
                    for (final p in parts) {
                      end += p.amount / total;
                      if (portion < end) {
                        p.onTap();
                        return;
                      }
                    }
                  },
                  child: CustomPaint(
                    size: const Size(152, 152),
                    painter: _Pie(
                      parts,
                      total,
                      Theme.of(c).colorScheme.surface,
                    ),
                  ),
                ),
              ),
            ),
          if (total == 0) const Text('合计为零，暂无占比。'),
          for (final p in parts)
            DataRowLink(
              p.label,
              percent(p.amount, total),
              dot: p.color,
              subtitle: money(p.amount),
              onTap: p.onTap,
            ),
        ],
      ),
    );
  }
}

class _Pie extends CustomPainter {
  final List<ChartValue> parts;
  final int total;
  final Color border;
  _Pie(this.parts, this.total, this.border);
  @override
  void paint(Canvas c, Size size) {
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: 71);
    double start = -math.pi / 2;
    for (final p in parts) {
      if (p.amount == 0) continue;
      final sweep = math.pi * 2 * p.amount / total;
      c.drawArc(rect, start, sweep, true, Paint()..color = p.color);
      if (sweep < math.pi * 2) {
        c.drawArc(
          rect,
          start,
          sweep,
          true,
          Paint()
            ..color = border
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3,
        );
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_Pie old) => true;
}

class RadarChart extends StatelessWidget {
  final List<ChartValue> parts;
  final Map<String, double> previous;
  const RadarChart(this.parts, this.previous, {super.key});
  @override
  Widget build(BuildContext c) {
    final total = parts.fold(0, (n, p) => n + p.amount);
    final keys = parts.map((p) => p.label).toList();
    final current = parts
        .map((p) => total == 0 ? 0.0 : p.amount / total)
        .toList();
    final old = keys.map((k) => previous[k] ?? 0.0).toList();
    final scale = ([.25, ...current, ...old].reduce(math.max) * 4).ceil() / 4;
    Offset at(int i, double radius) => Offset(
      math.cos(i * 2 * math.pi / keys.length - math.pi / 2) * radius,
      math.sin(i * 2 * math.pi / keys.length - math.pi / 2) * radius,
    );
    return Column(
      children: [
        if (total > 0 && keys.length >= 3) ...[
          LayoutBuilder(
            builder: (ctx, b) {
              final w = math.min(320.0, b.maxWidth),
                  r = math.min(w * .29, 72.0);
              return SizedBox(
                width: w,
                height: 208,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _Radar(
                          current,
                          old,
                          scale,
                          r,
                          Theme.of(c).colorScheme.primary,
                          Theme.of(c).dividerColor,
                        ),
                      ),
                    ),
                    for (int i = 0; i < keys.length; i++)
                      Positioned(
                        left: (w / 2 + at(i, r + 26).dx - 35).clamp(0, w - 70),
                        top: 104 + at(i, r + 19).dy - 22,
                        width: 70,
                        height: 44,
                        child: TextButton(
                          onPressed: parts[i].onTap,
                          child: Text(
                            keys[i],
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          Text(
            '实线 本期　·　${previous.isEmpty ? "" : "虚线 上期　·　"}外圈 ${(scale * 100).round()}%',
          ),
        ] else
          Text(total == 0 ? '本期总资产为零，暂无占比。' : '记录三个资产类别后显示雷达图。'),
        for (final p in parts)
          DataRowLink(
            p.label,
            percent(p.amount, total),
            subtitle: money(p.amount),
            onTap: p.onTap,
          ),
      ],
    );
  }
}

class _Radar extends CustomPainter {
  final List<double> values, old;
  final double cap, r;
  final Color ink, grid;
  _Radar(this.values, this.old, this.cap, this.r, this.ink, this.grid);
  @override
  void paint(Canvas c, Size s) {
    c.translate(s.width / 2, s.height / 2);
    Offset point(int i, double n) {
      final a = i * 2 * math.pi / values.length - math.pi / 2;
      return Offset(math.cos(a) * r * n, math.sin(a) * r * n);
    }

    Path ring(List<double> v) => Path()
      ..addPolygon(List.generate(v.length, (i) => point(i, v[i] / cap)), true);
    final axis = Paint()
      ..color = grid
      ..style = PaintingStyle.stroke;
    for (final n in [.5, 1.0]) {
      c.drawPath(ring(List.filled(values.length, n * cap)), axis);
    }
    for (int i = 0; i < values.length; i++) {
      c.drawLine(Offset.zero, point(i, 1), axis);
    }
    final oldPath = ring(old);
    for (final metric in oldPath.computeMetrics()) {
      for (double at = 0; at < metric.length; at += 7) {
        c.drawPath(
          metric.extractPath(at, math.min(at + 4, metric.length)),
          Paint()
            ..color = ink.withValues(alpha: .65)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
    c.drawPath(ring(values), Paint()..color = ink.withValues(alpha: .18));
    c.drawPath(
      ring(values),
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_Radar old) => true;
}

Color seriesColor(BuildContext c, int index) {
  final colors = WealthColors.of(c).series;
  return colors[index % colors.length];
}
