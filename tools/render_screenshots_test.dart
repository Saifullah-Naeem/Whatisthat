import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:whatisthat/models/detection.dart';
import 'package:whatisthat/ui/widgets/detection_overlay.dart';
import 'package:whatisthat/ui/widgets/status_dock.dart';
import 'package:whatisthat/ui/widgets/test_mode_panel.dart';
import 'package:whatisthat/ui/widgets/top_control_bar.dart';

Future<void> _loadRealFonts() async {
  final home = Platform.environment['HOME'] ?? '/home/falcon';
  final fontsDir = '$home/development/flutter/bin/cache/artifacts/material_fonts';

  Future<ByteData> loadBytes(String fileName) async {
    final bytes = await File('$fontsDir/$fileName').readAsBytes();
    return ByteData.view(bytes.buffer);
  }

  final roboto = FontLoader('Roboto')
    ..addFont(loadBytes('Roboto-Regular.ttf'))
    ..addFont(loadBytes('Roboto-Medium.ttf'))
    ..addFont(loadBytes('Roboto-Bold.ttf'));
  await roboto.load();

  final icons = FontLoader('MaterialIcons')
    ..addFont(loadBytes('MaterialIcons-Regular.otf'));
  await icons.load();
}

/// Renders real WhatIsThat Flutter UI screenshots over ONNX-verified test frames.
void main() {
  testWidgets('render WhatIsThat app screenshots', (tester) async {
    await tester.runAsync(_loadRealFonts);

    Future<void> renderFrame({
      required String imagePath,
      required String goldenName,
      required Size viewportSize,
      required List<Detection> detections,
      required bool testMode,
      required PresetFilter presetFilter,
      required String providerLabel,
      required int inferenceMs,
      required double fps,
    }) async {
      final key = GlobalKey();
      final bytes = await tester.runAsync(() => File(imagePath).readAsBytes());
      final imageProvider = MemoryImage(bytes!);

      tester.view.physicalSize = viewportSize;
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark(useMaterial3: true).copyWith(
            textTheme: ThemeData.dark(useMaterial3: true)
                .textTheme
                .apply(fontFamily: 'Roboto'),
          ),
          home: RepaintBoundary(
            key: key,
            child: DefaultTextStyle(
              style: const TextStyle(fontFamily: 'Roboto', color: Colors.white),
              child: Scaffold(
                backgroundColor: const Color(0xFF07090E),
                body: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image(image: imageProvider, fit: BoxFit.cover),
                            CustomPaint(
                              painter: DetectionOverlayPainter(
                                detections: detections,
                                showConfidence: testMode,
                                minLabelTop: testMode ? 174.0 : 66.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 12,
                      right: 12,
                      child: TopControlBar(
                        canSwitchCamera: true,
                        onSwitchCamera: () {},
                        onSnapshot: () {},
                        presetFilter: presetFilter,
                        onTogglePreset: () {},
                        testMode: testMode,
                        onToggleTestMode: (_) {},
                      ),
                    ),
                    if (testMode)
                      Positioned(
                        top: 72,
                        left: 14,
                        right: 14,
                        child: TestModePanel(
                          fps: fps,
                          inferenceMs: inferenceMs,
                          providerLabel: providerLabel,
                          confidenceThreshold: 0.25,
                          onConfidenceChanged: (_) {},
                        ),
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: StatusDock(
                        detections: detections,
                        isModelReady: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.runAsync(() async {
        await precacheImage(
          imageProvider,
          tester.element(find.byType(Image)),
        );
      });
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(key),
        matchesGoldenFile(goldenName),
      );
    }

    await renderFrame(
      imagePath:
          '/home/falcon/.gemini/antigravity-cli/brain/5d310ef7-3a81-4636-acdd-ff45a002c1fb/webcam_developer_desk_1795714909858.jpg',
      goldenName: '../docs/screenshots/whatisthat_default_mode.png',
      viewportSize: const Size(1280, 720),
      testMode: false,
      presetFilter: PresetFilter.all,
      providerLabel: 'DirectML',
      inferenceMs: 41,
      fps: 24.4,
      detections: const [
        Detection(
          classId: 217,
          label: 'Glasses',
          confidence: 0.4143,
          box: Rect.fromLTRB(0.435, 0.2276, 0.5682, 0.3231),
        ),
        Detection(
          classId: 268,
          label: 'Human face',
          confidence: 0.4925,
          box: Rect.fromLTRB(0.4461, 0.1435, 0.5638, 0.4336),
        ),
        Detection(
          classId: 589,
          label: 'Woman',
          confidence: 0.549,
          box: Rect.fromLTRB(0.2867, 0.0607, 0.6576, 0.9963),
        ),
        Detection(
          classId: 280,
          label: 'Houseplant',
          confidence: 0.3692,
          box: Rect.fromLTRB(0.0422, 0.2995, 0.1942, 0.5811),
        ),
      ],
    );

    await renderFrame(
      imagePath:
          '/home/falcon/.gemini/antigravity-cli/brain/5d310ef7-3a81-4636-acdd-ff45a002c1fb/desk_workspace_objects_1795714729968.jpg',
      goldenName: '../docs/screenshots/whatisthat_test_mode.png',
      viewportSize: const Size(1280, 720),
      testMode: true,
      presetFilter: PresetFilter.deskAndPeople,
      providerLabel: 'DirectML',
      inferenceMs: 40,
      fps: 25.0,
      detections: const [
        Detection(
          classId: 304,
          label: 'Laptop',
          confidence: 0.848,
          box: Rect.fromLTRB(0.1299, 0.0648, 0.6441, 0.8413),
        ),
        Detection(
          classId: 127,
          label: 'Computer keyboard',
          confidence: 0.613,
          box: Rect.fromLTRB(0.2630, 0.4592, 0.6005, 0.6938),
        ),
        Detection(
          classId: 158,
          label: 'Desk',
          confidence: 0.297,
          box: Rect.fromLTRB(0.0, 0.3, 0.9919, 0.994),
        ),
      ],
    );
  });
}
