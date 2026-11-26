import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:whatisthat/models/detection.dart';
import 'package:whatisthat/services/box_tracker.dart';
import 'package:whatisthat/services/image_preprocess.dart';
import 'package:whatisthat/services/yolo_postprocess.dart';

void main() {
  group('preprocessFrame', () {
    test('converts BGRA8888 with stride and 90-degree rotation into NCHW tensor', () {
      // 4x2 BGRA frame with 4 extra padding bytes per row.
      const int w = 4;
      const int h = 2;
      const int stride = w * 4 + 4;
      final bytes = Uint8List(h * stride);
      // Set pixel (0, 1) -> pure red (B=0, G=0, R=255, A=255)
      final int idx = 1 * stride + 0 * 4;
      bytes[idx] = 0;
      bytes[idx + 1] = 0;
      bytes[idx + 2] = 255;
      bytes[idx + 3] = 255;

      final result = preprocessFrame(
        RawFrameData(
          format: RawPixelFormat.bgra8888,
          width: w,
          height: h,
          rotationDegrees: 90,
          planes: [bytes],
          bytesPerRow: [stride],
          bytesPerPixel: [4],
        ),
        inputSize: 416,
      );

      expect(result.orientedWidth, 2);
      expect(result.orientedHeight, 4);
      expect(result.tensor.length, 3 * 416 * 416);
      // Pixel (0, 1) rotates 90 deg CW to top-left (ox=0, oy=0), padX=104, padY=0
      final int dstIdx = 0 * 416 + result.padX.round();
      expect(result.tensor[dstIdx], closeTo(1.0, 0.01)); // R channel
      expect(result.tensor[416 * 416 + dstIdx], closeTo(0.0, 0.01)); // G channel
    });

    test('converts YUV420 frame without out-of-bounds errors', () {
      const int w = 8;
      const int h = 8;
      final y = Uint8List(w * h)..fillRange(0, w * h, 180);
      final u = Uint8List((w ~/ 2) * (h ~/ 2))..fillRange(0, 16, 128);
      final v = Uint8List((w ~/ 2) * (h ~/ 2))..fillRange(0, 16, 128);

      final result = preprocessFrame(
        RawFrameData(
          format: RawPixelFormat.yuv420,
          width: w,
          height: h,
          rotationDegrees: 0,
          planes: [y, u, v],
          bytesPerRow: [w, w ~/ 2, w ~/ 2],
          bytesPerPixel: [1, 1, 1],
        ),
        inputSize: 416,
      );

      expect(result.tensor.length, 3 * 416 * 416);
      // Neutral gray (Y=180, U=128, V=128) -> ~0.706
      expect(result.tensor[0], closeTo(180 / 255.0, 0.02));
    });
  });

  group('decodeYoloOutput', () {
    test('decodes synthetic 601-class tensor, applies NMS and mirrors X', () {
      const int numClasses = 601;
      const int numAnchors = 10;
      final output = Float32List((4 + numClasses) * numAnchors);
      final labels = List<String>.generate(numClasses, (i) => 'Class$i');
      labels[217] = 'Glasses';
      labels[267] = 'Human hand';

      // Anchor 0: Glasses at left quarter [cx=104, cy=208, w=80, h=40], score 0.92
      output[0] = 104.0;
      output[numAnchors + 0] = 208.0;
      output[2 * numAnchors + 0] = 80.0;
      output[3 * numAnchors + 0] = 40.0;
      output[(4 + 217) * numAnchors + 0] = 0.92;

      // Anchor 1: Overlapping duplicate Glasses box, lower score 0.65 -> suppressed by NMS
      output[1] = 108.0;
      output[numAnchors + 1] = 208.0;
      output[2 * numAnchors + 1] = 82.0;
      output[3 * numAnchors + 1] = 42.0;
      output[(4 + 217) * numAnchors + 1] = 0.65;

      // Anchor 2: Human hand at right side, score 0.85
      output[2] = 312.0;
      output[numAnchors + 2] = 208.0;
      output[2 * numAnchors + 2] = 60.0;
      output[3 * numAnchors + 2] = 100.0;
      output[(4 + 267) * numAnchors + 2] = 0.85;

      final detections = decodeYoloOutput(
        output: output,
        numClasses: numClasses,
        numAnchors: numAnchors,
        labels: labels,
        inputSize: 416,
        scale: 1.0,
        padX: 0.0,
        padY: 0.0,
        orientedWidth: 416,
        orientedHeight: 416,
        confidenceThreshold: 0.30,
        mirrorHorizontal: true,
      );

      expect(detections.length, 2);
      expect(detections[0].label, 'Glasses');
      // Originally centered at x=0.25 -> mirrored to x=0.75
      expect(detections[0].box.center.dx, closeTo(0.75, 0.02));
      expect(detections[1].label, 'Human hand');
      expect(detections[1].box.center.dx, closeTo(0.25, 0.02));
    });
  });

  group('BoxTracker', () {
    test('maintains trackId and smooths coordinates without dropping', () {
      final tracker = BoxTracker(maxMissedFrames: 1);
      final first = tracker.update([
        const Detection(
          classId: 217,
          label: 'Glasses',
          confidence: 0.8,
          box: Rect.fromLTRB(0.2, 0.2, 0.4, 0.4),
        ),
      ]);
      expect(first.length, 1);
      final trackId = first[0].trackId;

      final second = tracker.update([
        const Detection(
          classId: 217,
          label: 'Glasses',
          confidence: 0.9,
          box: Rect.fromLTRB(0.22, 0.22, 0.42, 0.42),
        ),
      ]);
      expect(second.length, 1);
      expect(second[0].trackId, trackId);
      expect(second[0].box.left, greaterThan(0.2));
      expect(second[0].box.left, lessThan(0.22));
    });
  });
}
