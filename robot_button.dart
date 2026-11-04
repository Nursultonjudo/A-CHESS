import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Jonli robot belgisi: nafas oluvchi nur, miltillovchi antenna va ko'zlar.
class RobotFace extends StatefulWidget {
  const RobotFace({super.key, required this.size, required this.color});
  final double size;
  final Color color;

  @override
  State<RobotFace> createState() => _RobotFaceState();
}

class _RobotFaceState extends State<RobotFace>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  widget.color.withAlpha(0x55),
                  widget.color.withAlpha(0x11),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withAlpha((0x40 + 0x70 * pulse).round()),
                  blurRadius: 10 + 12 * pulse,
                  spreadRadius: 1 + 2 * pulse,
                ),
              ],
              border: Border.all(color: widget.color.withAlpha(0xCC), width: 1.6),
            ),
            child: CustomPaint(
              painter: _RobotPainter(t: t, color: widget.color),
            ),
          ),
        );
      },
    );
  }
}

class _RobotPainter extends CustomPainter {
  _RobotPainter({required this.t, required this.color});
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = Paint()
      ..color = Colors.white.withAlpha(0xEE)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.045
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = const Color(0xFF0B1220).withAlpha(0xDD);

    // Bosh
    final head = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.2, h * 0.3, w * 0.6, h * 0.46),
      Radius.circular(w * 0.14),
    );
    canvas.drawRRect(head, fill);
    canvas.drawRRect(head, stroke);

    // Antenna
    canvas.drawLine(Offset(w * 0.5, h * 0.3), Offset(w * 0.5, h * 0.17), stroke);
    final blink = 0.5 + 0.5 * math.sin(t * 2 * math.pi * 2);
    canvas.drawCircle(
      Offset(w * 0.5, h * 0.14),
      w * (0.04 + 0.025 * blink),
      Paint()..color = const Color(0xFFFF5A5A).withAlpha((0x88 + 0x77 * blink).round()),
    );

    // Quloqlar
    final ear = Paint()..color = Colors.white.withAlpha(0xCC);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.1, h * 0.43, w * 0.07, h * 0.18), Radius.circular(w * 0.03)),
      ear,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.83, h * 0.43, w * 0.07, h * 0.18), Radius.circular(w * 0.03)),
      ear,
    );

    // Ko'zlar (vaqti-vaqti bilan pirpiraydi)
    final blinking = (t % 0.5) > 0.46;
    final eyeH = blinking ? h * 0.012 : h * 0.1;
    final eye = Paint()..color = const Color(0xFF58E6FF);
    final glow = Paint()
      ..color = const Color(0xFF58E6FF).withAlpha(0x66)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.04);
    for (final cx in [0.37, 0.63]) {
      final r = Rect.fromCenter(
        center: Offset(w * cx, h * 0.5),
        width: w * 0.1,
        height: eyeH,
      );
      canvas.drawOval(r.inflate(w * 0.015), glow);
      canvas.drawOval(r, eye);
    }

    // Og'iz
    final mouth = Path()
      ..moveTo(w * 0.4, h * 0.65)
      ..quadraticBezierTo(w * 0.5, h * 0.7, w * 0.6, h * 0.65);
    canvas.drawPath(
      mouth,
      Paint()
        ..color = const Color(0xFF58E6FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.03
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RobotPainter old) => old.t != t || old.color != color;
}
