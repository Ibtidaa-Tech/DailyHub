import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// The DailyHub mark: four tiles of a "hub" — a checked task, two modules
/// and a round dot — on the accent colour. Same geometry as the launcher icon.
class BrandMark extends StatelessWidget {
  final double size;
  final Color? color;
  const BrandMark({super.key, this.size = 56, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.cs.primary;
    final hsl = HSLColor.fromColor(c);
    final c2 = hsl.withHue((hsl.hue + 28) % 360).withLightness((hsl.lightness * 0.92).clamp(0.0, 1.0)).toColor();
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MarkPainter(c, c2)),
    );
  }
}

class _MarkPainter extends CustomPainter {
  final Color a, b;
  _MarkPainter(this.a, this.b);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final bg = RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(w * 0.28));
    canvas.drawRRect(
      bg,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [a, b],
        ).createShader(Offset.zero & s),
    );
    final tile = w * 0.245;
    final gap = w * 0.055;
    final start = (w - (tile * 2 + gap)) / 2;
    final r = Radius.circular(tile * 0.26);
    Rect at(int col, int row) =>
        Rect.fromLTWH(start + col * (tile + gap), start + row * (tile + gap), tile, tile);

    // Top-left: solid tile with a check.
    canvas.drawRRect(RRect.fromRectAndRadius(at(0, 0), r), Paint()..color = Colors.white);
    final t = at(0, 0);
    final check = Path()
      ..moveTo(t.left + tile * 0.26, t.top + tile * 0.53)
      ..lineTo(t.left + tile * 0.44, t.top + tile * 0.70)
      ..lineTo(t.left + tile * 0.75, t.top + tile * 0.34);
    canvas.drawPath(
      check,
      Paint()
        ..color = a
        ..style = PaintingStyle.stroke
        ..strokeWidth = tile * 0.14
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    // Two soft module tiles.
    final soft = Paint()..color = Colors.white.withValues(alpha: 0.42);
    canvas.drawRRect(RRect.fromRectAndRadius(at(1, 0), r), soft);
    canvas.drawRRect(RRect.fromRectAndRadius(at(0, 1), r), soft);
    // The hub dot.
    final d = at(1, 1);
    canvas.drawCircle(d.center, tile * 0.5, Paint()..color = Colors.white.withValues(alpha: 0.9));
    canvas.drawCircle(d.center, tile * 0.2, Paint()..color = a.withValues(alpha: 0.9));
  }

  @override
  bool shouldRepaint(_MarkPainter o) => o.a != a || o.b != b;
}

/// Logo + name.
class Wordmark extends StatelessWidget {
  final double size;
  const Wordmark({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      BrandMark(size: size),
      SizedBox(width: size * 0.3),
      Text('DailyHub',
          style: context.tt.headlineSmall?.copyWith(fontSize: size * 0.62, fontWeight: FontWeight.w800)),
    ]);
  }
}

/// Launch/loading screen.
class SplashView extends StatefulWidget {
  const SplashView({super.key});
  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) => Transform.scale(
            scale: 1 + 0.05 * math.sin(_c.value * math.pi),
            child: child,
          ),
          child: const BrandMark(size: 84),
        ),
      ),
    );
  }
}
