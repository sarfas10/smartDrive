import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'branding.dart';

/// A reusable animated, multi-blob gradient background.
/// Just place it in a Stack as the first child.
class AnimatedBlobBackground extends StatefulWidget {
  const AnimatedBlobBackground({
    super.key,
    this.duration = const Duration(seconds: 18),
  });

  final Duration duration;

  @override
  State<AnimatedBlobBackground> createState() => _AnimatedBlobBackgroundState();
}

class _AnimatedBlobBackgroundState extends State<AnimatedBlobBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bgController;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _bgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: BlobGradientPainter(animation: _bgController),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Public painter so you can reuse/compose elsewhere if needed.
class BlobGradientPainter extends CustomPainter {
  final Animation<double> animation;

  BlobGradientPainter({required this.animation}) : super(repaint: animation);

  double _wave(double t, {double amp = 0.25, double phase = 0}) {
    return 0.5 + amp * math.sin(2 * math.pi * (t + phase));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final time = animation.value;

    // Base
    final basePaint = Paint()..color = AppColors.backgroundDark;
    canvas.drawRect(Offset.zero & size, basePaint);

    // Centers
    final c1 = Offset(
      _wave(time, amp: 0.30, phase: 0.00) * size.width,
      _wave(time, amp: 0.22, phase: 0.15) * size.height,
    );
    final c2 = Offset(
      _wave(time, amp: 0.28, phase: 0.35) * size.width,
      _wave(time, amp: 0.24, phase: 0.55) * size.height,
    );
    final c3 = Offset(
      _wave(time, amp: 0.26, phase: 0.65) * size.width,
      _wave(time, amp: 0.20, phase: 0.85) * size.height,
    );
    final c4 = Offset(
      _wave(time, amp: 0.32, phase: 0.20) * size.width,
      _wave(time, amp: 0.18, phase: 0.40) * size.height,
    );

    final r = size.shortestSide;
    final r1 = r * 0.75;
    final r2 = r * 0.70;
    final r3 = r * 0.65;
    final r4 = r * 0.80;

    // Blobs
    final paint1 = Paint()
      ..shader = ui.Gradient.radial(
        c1,
        r1,
        [const Color(0xFF6D28D9).withOpacity(0.65), const Color(0x006D28D9)],
        const [0.0, 1.0],
      )
      ..blendMode = BlendMode.plus;

    final paint2 = Paint()
      ..shader = ui.Gradient.radial(
        c2,
        r2,
        [const Color(0xFF2563EB).withOpacity(0.60), const Color(0x002563EB)],
        const [0.0, 1.0],
      )
      ..blendMode = BlendMode.plus;

    final paint3 = Paint()
      ..shader = ui.Gradient.radial(
        c3,
        r3,
        [const Color(0xFFF43F5E).withOpacity(0.55), const Color(0x00F43F5E)],
        const [0.0, 1.0],
      )
      ..blendMode = BlendMode.plus;

    final paint4 = Paint()
      ..shader = ui.Gradient.radial(
        c4,
        r4,
        [const Color(0xFF06B6D4).withOpacity(0.55), const Color(0x0006B6D4)],
        const [0.0, 1.0],
      )
      ..blendMode = BlendMode.plus;

    canvas.drawCircle(c1, r1, paint1);
    canvas.drawCircle(c2, r2, paint2);
    canvas.drawCircle(c3, r3, paint3);
    canvas.drawCircle(c4, r4, paint4);

    // Top glow
    final highlight = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(0, size.height),
        [Colors.white.withOpacity(0.05), Colors.transparent],
        const [0.0, 1.0],
      )
      ..blendMode = BlendMode.plus;

    canvas.drawRect(Offset.zero & size, highlight);
  }

  @override
  bool shouldRepaint(covariant BlobGradientPainter oldDelegate) =>
      oldDelegate.animation != animation;
}
