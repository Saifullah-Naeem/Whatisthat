import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../models/detection.dart';

/// Decodes raw YOLOv8 [1, 4 + numClasses, numAnchors] output into [Detection]s.
List<Detection> decodeYoloOutput({
  required Float32List output,
  required int numClasses,
  required int numAnchors,
  required List<String> labels,
  required int inputSize,
  required double scale,
  required double padX,
  required double padY,
  required int orientedWidth,
  required int orientedHeight,
  double confidenceThreshold = 0.30,
  double iouThreshold = 0.45,
  int maxDetections = 25,
  bool mirrorHorizontal = false,
  Set<int>? allowedClassIds,
}) {
  final bestScores = Float32List(numAnchors);
  final bestClasses = Int32List(numAnchors)..fillRange(0, numAnchors, -1);

  // Cache-friendly class-outer scan over contiguous [numAnchors] slices.
  if (allowedClassIds != null) {
    for (final int c in allowedClassIds) {
      if (c < 0 || c >= numClasses) continue;
      final int offset = (4 + c) * numAnchors;
      for (int a = 0; a < numAnchors; a++) {
        final double score = output[offset + a];
        if (score > bestScores[a]) {
          bestScores[a] = score;
          bestClasses[a] = c;
        }
      }
    }
  } else {
    for (int c = 0; c < numClasses; c++) {
      final int offset = (4 + c) * numAnchors;
      for (int a = 0; a < numAnchors; a++) {
        final double score = output[offset + a];
        if (score > bestScores[a]) {
          bestScores[a] = score;
          bestClasses[a] = c;
        }
      }
    }
  }

  final List<Detection> candidates = [];
  final int cyOffset = numAnchors;
  final int wOffset = numAnchors * 2;
  final int hOffset = numAnchors * 3;
  final double invOrientedW = 1.0 / orientedWidth;
  final double invOrientedH = 1.0 / orientedHeight;
  final double invScale = 1.0 / scale;

  for (int a = 0; a < numAnchors; a++) {
    final double score = bestScores[a];
    if (score < confidenceThreshold) continue;
    final int classId = bestClasses[a];
    if (classId < 0 || classId >= labels.length) continue;

    final double cx = output[a];
    final double cy = output[cyOffset + a];
    final double w = output[wOffset + a];
    final double h = output[hOffset + a];

    // Undo letterbox padding & scale back to normalized [0, 1] display space.
    double left = ((cx - w * 0.5 - padX) * invScale) * invOrientedW;
    double top = ((cy - h * 0.5 - padY) * invScale) * invOrientedH;
    double right = ((cx + w * 0.5 - padX) * invScale) * invOrientedW;
    double bottom = ((cy + h * 0.5 - padY) * invScale) * invOrientedH;

    left = left.clamp(0.0, 1.0);
    top = top.clamp(0.0, 1.0);
    right = right.clamp(0.0, 1.0);
    bottom = bottom.clamp(0.0, 1.0);

    if (mirrorHorizontal) {
      final double mirroredLeft = 1.0 - right;
      final double mirroredRight = 1.0 - left;
      left = mirroredLeft;
      right = mirroredRight;
    }

    if (right - left < 0.01 || bottom - top < 0.01) continue;

    candidates.add(
      Detection(
        classId: classId,
        label: labels[classId],
        confidence: score,
        box: Rect.fromLTRB(left, top, right, bottom),
      ),
    );
  }

  if (candidates.isEmpty) return const [];

  candidates.sort((a, b) => b.confidence.compareTo(a.confidence));

  final List<Detection> kept = [];
  final List<bool> suppressed = List<bool>.filled(candidates.length, false);

  for (int i = 0; i < candidates.length; i++) {
    if (suppressed[i]) continue;
    final Detection current = candidates[i];
    kept.add(current);
    if (kept.length >= maxDetections) break;

    for (int j = i + 1; j < candidates.length; j++) {
      if (suppressed[j]) continue;
      if (candidates[j].classId != current.classId) continue;
      if (computeIoU(current.box, candidates[j].box) > iouThreshold) {
        suppressed[j] = true;
      }
    }
  }

  return kept;
}

double computeIoU(Rect a, Rect b) {
  final double interLeft = math.max(a.left, b.left);
  final double interTop = math.max(a.top, b.top);
  final double interRight = math.min(a.right, b.right);
  final double interBottom = math.min(a.bottom, b.bottom);

  final double interW = math.max(0.0, interRight - interLeft);
  final double interH = math.max(0.0, interBottom - interTop);
  final double interArea = interW * interH;
  if (interArea <= 0.0) return 0.0;

  final double unionArea =
      (a.width * a.height) + (b.width * b.height) - interArea;
  return unionArea > 0.0 ? interArea / unionArea : 0.0;
}
