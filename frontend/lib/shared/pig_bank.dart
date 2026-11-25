import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';
import '../core/theme.dart';

class PigBank extends StatefulWidget {
  final int cents;
  const PigBank(this.cents, {super.key});
  @override
  State<PigBank> createState() => _PigBankState();
}

class _PigBankState extends State<PigBank> with SingleTickerProviderStateMixin {
  late final shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );
  bool touched = false;
  @override
  void didUpdateWidget(PigBank old) {
    super.didUpdateWidget(old);
    if (old.cents != widget.cents) touched = false;
  }

  @override
  void dispose() {
    shake.dispose();
    super.dispose();
  }

  void tap() {
    setState(() => touched = true);
    if (!MediaQuery.disableAnimationsOf(context)) shake.forward(from: 0);
  }

  @override
  Widget build(BuildContext c) {
    final palette = WealthColors.of(c), amount = math.max(0, widget.cents);
    final full = amount == 0 ? 0 : (amount - 1) ~/ 100000000,
        coins = (amount - full * 100000000) / 1000000;
    return Column(
      children: [
        Semantics(
          button: true,
          label: '摇一摇存钱罐',
          child: InkWell(
            onTap: tap,
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              width: double.infinity,
              height: 176,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: coins),
                duration: Duration(
                  milliseconds: MediaQuery.disableAnimationsOf(c) ? 0 : 400,
                ),
                builder: (_, count, _) => AnimatedBuilder(
                  animation: shake,
                  builder: (_, _) => CustomPaint(
                    painter: _PigPainter(palette, count, shake.value),
                  ),
                ),
              ),
            ),
          ),
        ),
        Text(
          touched
              ? (amount == 0 ? '这一笔，也值得认真记下。' : '叮当，你攒下的都在这里。')
              : '轻点存钱罐，摇一摇',
          style: TextStyle(color: palette.onStage),
        ),
        Text(
          '${full > 0 ? "另有 $full 个满罐 · " : ""}每枚代表 1 万元',
          style: TextStyle(
            color: palette.onStage.withValues(alpha: .8),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _PigPainter extends CustomPainter {
  final WealthColors p;
  final double coins, t;
  _PigPainter(this.p, this.coins, this.t);
  static final _paths = <String, Path>{};
  @override
  void paint(Canvas c, Size size) {
    final scale = math.min(size.width / 340, size.height / 182);
    c.translate(
      (size.width - 340 * scale) / 2,
      (size.height - 182 * scale) / 2,
    );
    c.scale(scale);
    void oval(double x, double y, double rx, double ry, Color color) =>
        c.drawOval(
          Rect.fromCenter(center: Offset(x, y), width: 2 * rx, height: 2 * ry),
          Paint()..color = color,
        );
    Path path(String d) => _paths.putIfAbsent(d, () => parseSvgPathData(d));
    void line(String d, Color color, [double width = 1.5]) => c.drawPath(
      path(d),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
    void shape(String d, Color a, Color b) {
      final v = path(d);
      c.drawPath(
        v,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [a, b, p.glass],
          ).createShader(v.getBounds()),
      );
      line(d, p.onStage.withValues(alpha: .82), 1.4);
    }

    void star(double x, double y, double r, Color color) {
      final v = Path()
        ..moveTo(x, y - r)
        ..quadraticBezierTo(x, y, x + r, y)
        ..quadraticBezierTo(x, y, x, y + r)
        ..quadraticBezierTo(x, y, x - r, y)
        ..quadraticBezierTo(x, y, x, y - r);
      c.drawPath(v, Paint()..color = color);
    }

    final energy = t > 0 && t < 1 ? math.pow(1 - t, 1.7).toDouble() : 0.0;
    for (final pos in const [
      Offset(40, 55),
      Offset(80, 25),
      Offset(292, 51),
      Offset(279, 104),
      Offset(55, 114),
      Offset(228, 22),
    ]) {
      star(pos.dx, pos.dy, 2.5, p.glass);
    }
    oval(168, 165, 90, 5, p.ink);
    c.save();
    c.translate(168, 146);
    c.rotate(math.sin(t * 23) * .115 * energy);
    c.translate(-168, -146 - math.sin(t * 12).abs() * 5 * energy);
    line(
      'M91 96 C70 94 69 73 81 75 C89 76 84 86 76 84 C69 82 67 76 68 73',
      p.glass,
      3,
    );
    shape(
      'M87 100 C87 72 104 53 131 48 C155 42 184 45 201 55 C214 51 225 56 235 66 C244 76 249 89 251 103 C251 121 240 134 223 141 L221 154 Q220 159 214 159 L207 159 Q202 159 202 153 L201 147 C175 157 149 157 123 149 L120 156 Q118 160 113 159 L106 158 Q103 157 103 152 L104 139 C92 129 86 115 87 100 Z',
      p.glass,
      p.stageGlow,
    );
    const chamber =
        'M98 101 C99 74 119 55 153 54 C182 51 207 65 215 87 C227 116 203 142 171 147 C136 153 101 137 98 110 Z';
    c.drawPath(path(chamber), Paint()..color = p.stageGlow);
    line(chamber, p.glass);
    c.save();
    c.clipPath(path(chamber));
    const order = [3, 4, 2, 5, 1, 6, 0, 7],
        bottom = [127, 134, 140, 144, 144, 140, 134, 126];
    for (int k = 0; k < coins.ceil(); k++) {
      final row = k ~/ 8, col = order[(k % 8 + row * 3) % 8];
      final wobble = math.sin(t * 25 + k * .77) * energy;
      c.save();
      c.translate(
        107 + col * 14.1 + wobble * 3,
        bottom[col] - row * 5.15 - wobble.abs() * (1 + row * .53),
      );
      c.rotate(.07 * math.sin(col * 9) + wobble * .12);
      c.clipRect(Rect.fromLTWH(-8.5, -6, 17 * math.min(1.0, coins - k), 12));
      final shade = Color.lerp(p.gold, p.ink, .22)!;
      c.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-8, -1.7, 16, 5.6),
          const Radius.circular(2.5),
        ),
        Paint()..color = shade,
      );
      oval(0, -1.4, 8, 2.65, p.gold);
      oval(0, -1.4, 5, 1.25, Color.lerp(p.gold, shade, .55)!);
      c.restore();
    }
    line(
      'M104 82 Q130 44 168 59 M103 87 L101 95',
      p.onStage.withValues(alpha: .65),
      2,
    );
    c.restore();
    shape(
      'M204 69 Q199 59 201 40 Q203 31 209 35 Q221 40 227 56 L222 68',
      p.glass,
      p.stageGlow,
    );
    oval(242, 100, 16, 12, p.glass);
    oval(240, 100, 1.8, 3, p.stageGlow);
    oval(247, 99, 1.7, 3, p.stageGlow);
    oval(229, 84, 3.1, 3.8, p.ink);
    oval(230, 83, 1, 1, p.onStage);
    line('M224 110 Q229 114 233 109', p.stageGlow);
    line('M134 48 Q147 44 160 46', p.ink, 3);
    line('M148 44 Q149 32 153 26', p.glass, 2);
    shape('M151 34 Q134 34 133 23 Q146 22 151 34 Z', p.gold, p.glass);
    shape('M152 30 Q154 16 170 16 Q168 28 152 30 Z', p.glass, p.gold);
    c.restore();
    if (energy > 0) {
      for (int j = 0; j < 10; j++) {
        final a = math.pi + j / 9 * math.pi, r = 67 + t * 43;
        star(
          169 + math.cos(a) * r * 1.47,
          101 + math.sin(a) * r,
          3.4 * energy,
          p.gold.withValues(alpha: energy),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PigPainter o) => coins != o.coins || t != o.t || p != o.p;
}
