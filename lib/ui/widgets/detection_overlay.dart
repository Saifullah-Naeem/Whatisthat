import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../models/detection.dart';

/// Paints crisp dark-mode bounding boxes, corner brackets, and object label pills.
class DetectionOverlayPainter extends CustomPainter {
  const DetectionOverlayPainter({
    required this.detections,
    required this.showConfidence,
    this.minLabelTop = 66.0,
  });

  final List<Detection> detections;
  final bool showConfidence;
  final double minLabelTop;

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty || size.isEmpty) return;

    for (final det in detections) {
      final Color accent = colorForClass(det.classId);
      final Rect rect = Rect.fromLTRB(
        det.box.left * size.width,
        det.box.top * size.height,
        det.box.right * size.width,
        det.box.bottom * size.height,
      );

      // Subtle translucent fill
      final fillPaint = Paint()
        ..color = accent.withValues(alpha: 0.10)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        fillPaint,
      );

      // Thin outer box border
      final borderPaint = Paint()
        ..color = accent.withValues(alpha: 0.72)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        borderPaint,
      );

      // Brighter corner brackets for modern AI viewfinder feel
      _drawCornerBrackets(canvas, rect, accent);

      // Label pill
      final String labelText = showConfidence
          ? '${det.label} ${(det.confidence * 100).round()}%'
          : det.label;

      final textPainter = TextPainter(
        text: TextSpan(
          text: labelText,
          style: const TextStyle(
            color: Color(0xFF06090F),
            fontFamily: 'Roboto',
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();

      const double padH = 8.0;
      const double padV = 3.5;
      final double pillW = textPainter.width + padH * 2;
      final double pillH = textPainter.height + padV * 2;

      double pillLeft = rect.left.clamp(
        4.0,
        math.max(4.0, size.width - pillW - 4.0),
      );
      double pillTop = rect.top - pillH - 4.0;
      if (pillTop < 4.0) {
        pillTop = rect.top + 6.0;
      }
      if (pillTop < minLabelTop && rect.bottom > minLabelTop + pillH + 12.0) {
        pillTop = minLabelTop;
      }

      final pillRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(pillLeft, pillTop, pillW, pillH),
        const Radius.circular(6),
      );

      final pillPaint = Paint()
        ..color = accent
        ..style = PaintingStyle.fill;
      canvas.drawRRect(pillRect, pillPaint);

      textPainter.paint(canvas, Offset(pillLeft + padH, pillTop + padV));
    }
  }

  void _drawCornerBrackets(Canvas canvas, Rect rect, Color color) {
    final double len = math.min(18.0, math.min(rect.width, rect.height) * 0.28);
    if (len < 4) return;

    final cornerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final path = Path()
      // Top-left
      ..moveTo(rect.left, rect.top + len)
      ..lineTo(rect.left, rect.top)
      ..lineTo(rect.left + len, rect.top)
      // Top-right
      ..moveTo(rect.right - len, rect.top)
      ..lineTo(rect.right, rect.top)
      ..lineTo(rect.right, rect.top + len)
      // Bottom-right
      ..moveTo(rect.right, rect.bottom - len)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.right - len, rect.bottom)
      // Bottom-left
      ..moveTo(rect.left + len, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..lineTo(rect.left, rect.bottom - len);

    canvas.drawPath(path, cornerPaint);
  }

  @override
  bool shouldRepaint(covariant DetectionOverlayPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.showConfidence != showConfidence ||
        oldDelegate.minLabelTop != minLabelTop;
  }
}
