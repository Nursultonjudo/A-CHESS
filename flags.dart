// Bayroqlar va rangli globus (CustomPaint, rasm fayllarisiz).
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Til kodi bo'yicha bayroq(lar): uz, ru, en (AQSh + Buyuk Britaniya).
class LangFlags extends StatelessWidget {
  const LangFlags({super.key, required this.lang, this.height = 18});
  final String lang;
  final double height;

  @override
  Widget build(BuildContext context) {
    final codes = switch (lang) {
      'uz' => ['uz'],
      'ru' => ['ru'],
      _ => ['us', 'gb'],
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < codes.length; i++) ...[
          if (i > 0) SizedBox(width: height * 0.2),
          FlagIcon(code: codes[i], height: height),
        ],
      ],
    );
  }
}

class FlagIcon extends StatelessWidget {
  const FlagIcon({super.key, required this.code, this.height = 18});
  final String code;
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: height * 1.5,
        height: height,
        child: CustomPaint(painter: _FlagPainter(code)),
      );
}

class _FlagPainter extends CustomPainter {
  const _FlagPainter(this.code);
  final String code;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rr = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(h * 0.14));
    canvas.save();
    canvas.clipRRect(rr);
    Paint f(int c) => Paint()..color = Color(c);
    switch (code) {
      case 'uz':
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h / 3), f(0xFF0099B5));
        canvas.drawRect(Rect.fromLTWH(0, h / 3, w, h / 3), f(0xFFFFFFFF));
        canvas.drawRect(Rect.fromLTWH(0, 2 * h / 3, w, h / 3), f(0xFF1EB53A));
        final red = f(0xFFCE1126);
        canvas.drawRect(Rect.fromLTWH(0, h / 3 - h * 0.03, w, h * 0.03), red);
        canvas.drawRect(Rect.fromLTWH(0, 2 * h / 3, w, h * 0.03), red);
        final c = Offset(w * 0.17, h * 0.17);
        canvas.drawCircle(c, h * 0.1, f(0xFFFFFFFF));
        canvas.drawCircle(c + Offset(h * 0.035, 0), h * 0.085, f(0xFF0099B5));
        for (var i = 0; i < 3; i++) {
          canvas.drawCircle(Offset(w * (0.30 + i * 0.07), h * 0.12), h * 0.025, f(0xFFFFFFFF));
        }
        break;
      case 'ru':
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h / 3), f(0xFFFFFFFF));
        canvas.drawRect(Rect.fromLTWH(0, h / 3, w, h / 3), f(0xFF0039A6));
        canvas.drawRect(Rect.fromLTWH(0, 2 * h / 3, w, h / 3), f(0xFFD52B1E));
        break;
      case 'us':
        for (var i = 0; i < 13; i++) {
          canvas.drawRect(Rect.fromLTWH(0, h * i / 13, w, h / 13 + 0.5),
              f(i.isEven ? 0xFFB22234 : 0xFFFFFFFF));
        }
        final cw = w * 0.42, ch = h * 7 / 13;
        canvas.drawRect(Rect.fromLTWH(0, 0, cw, ch), f(0xFF3C3B6E));
        final star = f(0xFFFFFFFF);
        for (var r = 0; r < 4; r++) {
          for (var c = 0; c < 5; c++) {
            canvas.drawCircle(
                Offset(cw * (0.12 + c * 0.19), ch * (0.15 + r * 0.23)), h * 0.028, star);
          }
        }
        break;
      default: // gb
        canvas.drawRect(Offset.zero & size, f(0xFF012169));
        final white = Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = h * 0.22;
        final red = Paint()
          ..color = const Color(0xFFC8102E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = h * 0.08;
        canvas.drawLine(const Offset(0, 0), Offset(w, h), white);
        canvas.drawLine(Offset(w, 0), Offset(0, h), white);
        canvas.drawLine(const Offset(0, 0), Offset(w, h), red);
        canvas.drawLine(Offset(w, 0), Offset(0, h), red);
        white.strokeWidth = h * 0.36;
        canvas.drawLine(Offset(w / 2, 0), Offset(w / 2, h), white);
        canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), white);
        red.strokeWidth = h * 0.2;
        canvas.drawLine(Offset(w / 2, 0), Offset(w / 2, h), red);
        canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), red);
    }
    canvas.restore();
    canvas.drawRRect(
        rr.deflate(0.4),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = const Color(0x55000000));
  }

  @override
  bool shouldRepaint(covariant _FlagPainter old) => old.code != code;
}

/// Rangli globus: okean, qit'alar, meridianlar.
class GlobeIcon extends StatelessWidget {
  const GlobeIcon({super.key, this.size = 24});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: const _GlobePainter()),
      );
}

class _GlobePainter extends CustomPainter {
  const _GlobePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 0.5;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.4, -0.45),
          radius: 1.05,
          colors: [Color(0xFF6FD3FF), Color(0xFF1E88E5), Color(0xFF0B3D91)],
        ).createShader(rect),
    );
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    final land = Paint()..color = const Color(0xFF43A047);
    final s = size.width;
    // Qit'alar (sodda shakllar)
    canvas.drawPath(
      Path()
        ..moveTo(s * 0.18, s * 0.28)
        ..cubicTo(s * 0.30, s * 0.16, s * 0.48, s * 0.20, s * 0.46, s * 0.34)
        ..cubicTo(s * 0.44, s * 0.46, s * 0.36, s * 0.46, s * 0.34, s * 0.58)
        ..cubicTo(s * 0.32, s * 0.70, s * 0.24, s * 0.62, s * 0.22, s * 0.50)
        ..cubicTo(s * 0.18, s * 0.42, s * 0.12, s * 0.36, s * 0.18, s * 0.28)
        ..close(),
      land,
    );
    canvas.drawPath(
      Path()
        ..moveTo(s * 0.58, s * 0.26)
        ..cubicTo(s * 0.70, s * 0.20, s * 0.86, s * 0.28, s * 0.84, s * 0.42)
        ..cubicTo(s * 0.82, s * 0.52, s * 0.70, s * 0.50, s * 0.66, s * 0.62)
        ..cubicTo(s * 0.62, s * 0.74, s * 0.56, s * 0.64, s * 0.56, s * 0.52)
        ..cubicTo(s * 0.54, s * 0.40, s * 0.52, s * 0.32, s * 0.58, s * 0.26)
        ..close(),
      land..color = const Color(0xFF66BB6A),
    );
    canvas.drawOval(
        Rect.fromLTWH(s * 0.32, s * 0.78, s * 0.34, s * 0.12), land..color = const Color(0xFF388E3C));
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.5, s * 0.026)
      ..color = const Color(0x55FFFFFF);
    canvas.drawOval(Rect.fromCenter(center: c, width: r * 1.0, height: r * 2), grid);
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), grid);
    canvas.restore();
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.8, s * 0.04)
          ..color = const Color(0xCC0B3D91));
  }

  @override
  bool shouldRepaint(covariant _GlobePainter old) => false;
}


/// Yarim 3D ko'rinishdagi rangli ikonka: gradient, yaltirash va soya.
class Icon3D extends StatelessWidget {
  const Icon3D({
    super.key,
    required this.icon,
    required this.color,
    this.size = 34,
    this.circle = false,
  });
  final IconData icon;
  final Color color;
  final double size;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final light = Color.lerp(color, Colors.white, 0.38)!;
    final dark = Color.lerp(color, Colors.black, 0.32)!;
    final r = BorderRadius.circular(size * 0.3);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : r,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [light, color, dark],
          stops: const [0, 0.5, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: dark.withAlpha(0x88),
            blurRadius: size * 0.16,
            offset: Offset(0, size * 0.08),
          ),
        ],
        border: Border.all(color: Colors.white.withAlpha(0x55), width: 0.8),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: size * 0.1,
            right: size * 0.1,
            top: size * 0.05,
            height: size * 0.34,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size * 0.25),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white.withAlpha(0x70), Colors.white.withAlpha(0x00)],
                ),
              ),
            ),
          ),
          Icon(icon, size: size * 0.58, color: Colors.white, shadows: const [
            Shadow(color: Color(0x66000000), blurRadius: 2, offset: Offset(0, 1)),
          ]),
        ],
      ),
    );
  }
}

/// Bo'lim rangi (panel ikonkalari uchun).
Color tabColor(int i) => const [
      Color(0xFF2E9E4F), // o'yin
      Color(0xFFE59A14), // reyting
      Color(0xFF2F7FD6), // statistika
      Color(0xFF8A52CC), // vazifalar
      Color(0xFF12A39A), // darsliklar
      Color(0xFF6B7785), // sozlamalar
      Color(0xFF18B5D8), // AI
      Color(0xFFD9473B), // turnirlar
    ][i.clamp(0, 7)];

/// Ilovani yopish: qizil dumaloq X tugmasi.
class CloseAppButton extends StatelessWidget {
  const CloseAppButton({super.key, required this.onTap, this.tooltip = ''});
  final VoidCallback onTap;
  final String tooltip;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const Icon3D(
            icon: Icons.close_rounded,
            color: Color(0xFFD93025),
            size: 38,
            circle: true,
          ),
        ),
      );
}
