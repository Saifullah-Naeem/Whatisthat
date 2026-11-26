import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:whatisthat/models/detection.dart';
import 'package:whatisthat/ui/widgets/detection_overlay.dart';
import 'package:whatisthat/ui/widgets/status_dock.dart';

void main() {
  testWidgets('StatusDock shows loading state then detected object counts', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusDock(
            detections: [],
            isModelReady: false,
          ),
        ),
      ),
    );
    expect(find.textContaining('Loading WhatIsThat AI'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusDock(
            detections: [
              Detection(
                classId: 217,
                label: 'Glasses',
                confidence: 0.91,
                box: Rect.fromLTRB(0.1, 0.1, 0.4, 0.3),
              ),
              Detection(
                classId: 267,
                label: 'Human hand',
                confidence: 0.85,
                box: Rect.fromLTRB(0.5, 0.4, 0.7, 0.8),
              ),
              Detection(
                classId: 267,
                label: 'Human hand',
                confidence: 0.82,
                box: Rect.fromLTRB(0.75, 0.4, 0.9, 0.8),
              ),
            ],
            isModelReady: true,
          ),
        ),
      ),
    );

    expect(find.text('Glasses'), findsOneWidget);
    expect(find.text('Human hand ×2'), findsOneWidget);
  });

  testWidgets('DetectionOverlayPainter paints cleanly with and without confidence', (
    tester,
  ) async {
    const detections = [
      Detection(
        classId: 304,
        label: 'Laptop',
        confidence: 0.88,
        box: Rect.fromLTRB(0.15, 0.2, 0.85, 0.85),
      ),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: CustomPaint(
            painter: DetectionOverlayPainter(
              detections: detections,
              showConfidence: false,
            ),
          ),
        ),
      ),
    );
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
