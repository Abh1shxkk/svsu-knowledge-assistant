/// Single-series charts in one ink colour, so they work in light and dark mode. Values are printed
/// on the chart, so nothing depends on hovering.
library;

import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';

typedef Pt = ({String label, int value});

class AreaChart extends StatelessWidget {
  const AreaChart({super.key, required this.points, this.height = 130});
  final List<Pt> points;
  final double height;
  @override
  Widget build(BuildContext context) => Semantics(
        label: points.map((p) => '${p.label}: ${p.value}').join(', '),
        child: SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: _AreaPainter(points, context.pal))),
      );
}

class _AreaPainter extends CustomPainter {
  _AreaPainter(this.points, this.p);
  final List<Pt> points;
  final Pal p;
  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const padB = 20.0, padT = 18.0, padX = 12.0;
    final w = size.width - padX * 2;
    final maxV = max(1, points.map((e) => e.value).reduce(max));
    final step = points.length > 1 ? w / (points.length - 1) : w;
    final xy = [
      for (var i = 0; i < points.length; i++) Offset(padX + i * step, size.height - padB - points[i].value / maxV * (size.height - padB - padT)),
    ];
    final line = Path()..moveTo(xy.first.dx, xy.first.dy);
    for (final o in xy.skip(1)) {
      line.lineTo(o.dx, o.dy);
    }
    final area = Path.from(line)
      ..lineTo(xy.last.dx, size.height - padB)
      ..lineTo(xy.first.dx, size.height - padB)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [p.chart.withValues(alpha: .22), p.chart.withValues(alpha: 0)])
            .createShader(Offset.zero & size),
    );
    canvas.drawPath(line, Paint()..color = p.chart..style = PaintingStyle.stroke..strokeWidth = 2.25..strokeJoin = StrokeJoin.round);
    for (var i = 0; i < xy.length; i++) {
      canvas.drawCircle(xy[i], 3.5, Paint()..color = p.surface);
      canvas.drawCircle(xy[i], 3.5, Paint()..color = p.chart..style = PaintingStyle.stroke..strokeWidth = 2);
      _text(canvas, '${points[i].value}', Offset(xy[i].dx, xy[i].dy - 16), p.fg2, 10.5);
      _text(canvas, points[i].label, Offset(xy[i].dx, size.height - 14), p.fg3, 10);
    }
  }

  @override
  bool shouldRepaint(covariant _AreaPainter old) => old.points != points || old.p != p;
}

class BarChart extends StatelessWidget {
  const BarChart({super.key, required this.points, this.thin = false, this.height = 130});
  final List<Pt> points;
  final bool thin;
  final double height;
  @override
  Widget build(BuildContext context) => Semantics(
        label: points.map((p) => '${p.label}: ${p.value}').join(', '),
        child: SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: _BarPainter(points, context.pal, thin))),
      );
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.points, this.p, this.thin);
  final List<Pt> points;
  final Pal p;
  final bool thin;
  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const padB = 20.0, padT = 18.0;
    final base = size.height - padB;
    final maxV = max(1, points.map((e) => e.value).reduce(max));
    final slot = size.width / points.length;
    final bw = min(thin ? 6.0 : 26.0, slot * (thin ? .3 : .62));
    canvas.drawLine(Offset(0, base + .5), Offset(size.width, base + .5), Paint()..color = p.line);
    for (var i = 0; i < points.length; i++) {
      final v = points[i].value;
      final h = v == 0 ? 0.0 : max(4.0, v / maxV * (base - padT));
      final x = i * slot + (slot - bw) / 2;
      if (h > 0) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(Rect.fromLTWH(x, base - h, bw, h), topLeft: Radius.circular(min(4, bw / 2)), topRight: Radius.circular(min(4, bw / 2))),
          Paint()..color = p.chart,
        );
      }
      _text(canvas, '$v', Offset(x + bw / 2, base - h - 15), p.fg2, 10.5);
      _text(canvas, points[i].label, Offset(x + bw / 2, size.height - 14), p.fg3, 10);
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => old.points != points || old.p != p;
}

void _text(Canvas canvas, String s, Offset center, Color color, double size) {
  final tp = TextPainter(text: TextSpan(text: s, style: TextStyle(color: color, fontSize: size)), textDirection: TextDirection.ltr)..layout();
  tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy));
}

/// Horizontal bars with the full label, each tappable (e.g. to the library filtered by that subject).
class HBars extends StatelessWidget {
  const HBars({super.key, required this.points, required this.onTap});
  final List<Pt> points;
  final void Function(String label) onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final maxV = max(1, points.isEmpty ? 1 : points.map((e) => e.value).reduce(max));
    return Column(children: [
      for (final pt in points)
        InkWell(
          onTap: () => onTap(pt.label),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              SizedBox(width: 110, child: Text(pt.label, style: TextStyle(fontSize: 12.5, color: p.fg2), maxLines: 1, overflow: TextOverflow.ellipsis)),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(value: pt.value / maxV, minHeight: 8, color: p.chart, backgroundColor: p.surface3),
                ),
              ),
              SizedBox(width: 34, child: Text('${pt.value}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
            ]),
          ),
        ),
    ]);
  }
}
