import 'dart:math' as math;
import 'dart:typed_data';

/// Supported raw camera pixel layouts passed to preprocessing.
enum RawPixelFormat { yuv420, bgra8888 }

/// Isolate-friendly raw camera frame snapshot.
class RawFrameData {
  const RawFrameData({
    required this.format,
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.planes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
  });

  final RawPixelFormat format;
  final int width;
  final int height;
  final int rotationDegrees;
  final List<Uint8List> planes;
  final List<int> bytesPerRow;
  final List<int> bytesPerPixel;
}

/// Output of letterbox preprocessing ready for ONNX Runtime NCHW Float32 input.
class PreprocessResult {
  const PreprocessResult({
    required this.tensor,
    required this.inputSize,
    required this.scale,
    required this.padX,
    required this.padY,
    required this.orientedWidth,
    required this.orientedHeight,
  });

  final Float32List tensor;
  final int inputSize;
  final double scale;
  final double padX;
  final double padY;
  final int orientedWidth;
  final int orientedHeight;
}

/// Converts a raw camera frame directly into a letterboxed [1, 3, S, S] Float32 tensor.
///
/// Samples only the pixels inside the scaled destination rectangle so high-res
/// camera feeds (e.g. 1080p) don't waste CPU converting unused pixels.
PreprocessResult preprocessFrame(RawFrameData frame, {int inputSize = 416}) {
  final rot = ((frame.rotationDegrees % 360) + 360) % 360;
  final bool swapDims = rot == 90 || rot == 270;
  final int orientedW = swapDims ? frame.height : frame.width;
  final int orientedH = swapDims ? frame.width : frame.height;

  final double scale = math.min(inputSize / orientedW, inputSize / orientedH);
  final int scaledW = math.max(1, (orientedW * scale).round());
  final int scaledH = math.max(1, (orientedH * scale).round());
  final int padXInt = (inputSize - scaledW) >> 1;
  final int padYInt = (inputSize - scaledH) >> 1;

  final int planeArea = inputSize * inputSize;
  final tensor = Float32List(3 * planeArea);
  // YOLO letterbox padding constant: 114 / 255.0
  const double padVal = 114.0 / 255.0;
  tensor.fillRange(0, tensor.length, padVal);

  const double inv255 = 1.0 / 255.0;
  final int gOffset = planeArea;
  final int bOffset = planeArea * 2;

  if (frame.format == RawPixelFormat.bgra8888) {
    final Uint8List bytes = frame.planes[0];
    final int rowStride = frame.bytesPerRow[0];

    for (int dy = 0; dy < scaledH; dy++) {
      final int oy = ((dy * orientedH) ~/ scaledH).clamp(0, orientedH - 1);
      final int dstRow = (dy + padYInt) * inputSize + padXInt;

      for (int dx = 0; dx < scaledW; dx++) {
        final int ox = ((dx * orientedW) ~/ scaledW).clamp(0, orientedW - 1);
        final (int sx, int sy) = _mapOrientedToSource(
          ox,
          oy,
          frame.width,
          frame.height,
          rot,
        );

        final int pIdx = sy * rowStride + sx * 4;
        final int dstIdx = dstRow + dx;
        tensor[dstIdx] = bytes[pIdx + 2] * inv255; // R
        tensor[gOffset + dstIdx] = bytes[pIdx + 1] * inv255; // G
        tensor[bOffset + dstIdx] = bytes[pIdx] * inv255; // B
      }
    }
  } else {
    final Uint8List yPlane = frame.planes[0];
    final Uint8List uPlane = frame.planes[1];
    final Uint8List vPlane = frame.planes[2];
    final int yStride = frame.bytesPerRow[0];
    final int uStride = frame.bytesPerRow[1];
    final int vStride = frame.bytesPerRow[2];
    final int uPixStride = frame.bytesPerPixel[1];
    final int vPixStride = frame.bytesPerPixel[2];

    for (int dy = 0; dy < scaledH; dy++) {
      final int oy = ((dy * orientedH) ~/ scaledH).clamp(0, orientedH - 1);
      final int dstRow = (dy + padYInt) * inputSize + padXInt;

      for (int dx = 0; dx < scaledW; dx++) {
        final int ox = ((dx * orientedW) ~/ scaledW).clamp(0, orientedW - 1);
        final (int sx, int sy) = _mapOrientedToSource(
          ox,
          oy,
          frame.width,
          frame.height,
          rot,
        );

        final int yVal = yPlane[sy * yStride + sx];
        final int uvX = sx >> 1;
        final int uvY = sy >> 1;
        final int uVal = uPlane[uvY * uStride + uvX * uPixStride] - 128;
        final int vVal = vPlane[uvY * vStride + uvX * vPixStride] - 128;

        int r = yVal + ((1436 * vVal) >> 10);
        int g = yVal - ((352 * uVal + 731 * vVal) >> 10);
        int b = yVal + ((1815 * uVal) >> 10);

        if (r < 0) {
          r = 0;
        } else if (r > 255) {
          r = 255;
        }
        if (g < 0) {
          g = 0;
        } else if (g > 255) {
          g = 255;
        }
        if (b < 0) {
          b = 0;
        } else if (b > 255) {
          b = 255;
        }

        final int dstIdx = dstRow + dx;
        tensor[dstIdx] = r * inv255;
        tensor[gOffset + dstIdx] = g * inv255;
        tensor[bOffset + dstIdx] = b * inv255;
      }
    }
  }

  return PreprocessResult(
    tensor: tensor,
    inputSize: inputSize,
    scale: scale,
    padX: padXInt.toDouble(),
    padY: padYInt.toDouble(),
    orientedWidth: orientedW,
    orientedHeight: orientedH,
  );
}

(int, int) _mapOrientedToSource(
  int ox,
  int oy,
  int srcW,
  int srcH,
  int rotationDegrees,
) {
  switch (rotationDegrees) {
    case 90:
      return (oy, srcH - 1 - ox);
    case 180:
      return (srcW - 1 - ox, srcH - 1 - oy);
    case 270:
      return (srcW - 1 - oy, ox);
    default:
      return (ox, oy);
  }
}
