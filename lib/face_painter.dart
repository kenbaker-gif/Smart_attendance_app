import 'package:flutter/material.dart';

class FacePainter extends CustomPainter {
  final List<dynamic>? bbox;
  final List<dynamic>? kps;
  final double imageWidth;
  final double imageHeight;

  FacePainter({
    required this.bbox,
    required this.kps,
    required this.imageWidth,
    required this.imageHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bbox == null || bbox!.isEmpty) return;

    // 1. Calculate Scale Factor
    // This ensures the box matches the face regardless of screen size
    final double scaleX = size.width / imageWidth;
    final double scaleY = size.height / imageHeight;

    // 2. Setup "Sci-Fi" Paint Styles
    final boxPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final dotPaint = Paint()
      ..color = Colors.yellowAccent
      ..style = PaintingStyle.fill;

    // 3. Draw the Bounding Box
    final Rect rect = Rect.fromLTRB(
      bbox![0] * scaleX,
      bbox![1] * scaleY,
      bbox![2] * scaleX,
      bbox![3] * scaleY,
    );
    
    // Draw corners only for a "Tech" look, or full rect
    canvas.drawRect(rect, boxPaint);

    // 4. Draw the Face Mesh Dots
    if (kps != null) {
      for (var point in kps!) {
        canvas.drawCircle(
          Offset(point[0] * scaleX, point[1] * scaleY),
          4.0, // Dot size
          dotPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}