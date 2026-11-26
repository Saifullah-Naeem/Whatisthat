import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../models/detection.dart';
import 'box_tracker.dart';
import 'image_preprocess.dart';
import 'yolo_postprocess.dart';

class DetectionFrameResult {
  const DetectionFrameResult({
    required this.detections,
    required this.inferenceMs,
    required this.providerLabel,
  });

  final List<Detection> detections;
  final int inferenceMs;
  final String providerLabel;
}

class _PostprocessInput {
  const _PostprocessInput({
    required this.output,
    required this.numClasses,
    required this.numAnchors,
    required this.labels,
    required this.inputSize,
    required this.scale,
    required this.padX,
    required this.padY,
    required this.orientedWidth,
    required this.orientedHeight,
    required this.confidenceThreshold,
    required this.mirrorHorizontal,
    required this.allowedClassIds,
  });

  final Float32List output;
  final int numClasses;
  final int numAnchors;
  final List<String> labels;
  final int inputSize;
  final double scale;
  final double padX;
  final double padY;
  final int orientedWidth;
  final int orientedHeight;
  final double confidenceThreshold;
  final bool mirrorHorizontal;
  final Set<int>? allowedClassIds;
}

/// Manages the offline YOLOv8n-OIV7 ONNX model and low-latency frame pipeline.
class DetectorService {
  DetectorService({
    this.modelAssetPath = 'assets/models/yolov8n_oiv7_416.onnx',
    this.labelsAssetPath = 'assets/models/oiv7_labels.txt',
    this.inputSize = 416,
  });

  final String modelAssetPath;
  final String labelsAssetPath;
  final int inputSize;

  final OnnxRuntime _ort = OnnxRuntime();
  final BoxTracker _tracker = BoxTracker();

  OrtSession? _session;
  String _inputName = 'images';
  String _outputName = 'output0';
  String _providerLabel = 'CPU';
  List<String> _labels = const [];
  Set<int> _deskAndPeopleIds = const {};

  bool _isReady = false;
  bool _isInferring = false;

  bool get isReady => _isReady;
  String get providerLabel => _providerLabel;
  int get labelCount => _labels.length;

  Future<void> initialize() async {
    if (_isReady) return;

    final rawLabels = await rootBundle.loadString(labelsAssetPath);
    _labels = rawLabels
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    final deskIds = <int>{};
    for (int i = 0; i < _labels.length; i++) {
      if (kDeskAndPeopleLabels.contains(_labels[i])) {
        deskIds.add(i);
      }
    }
    _deskAndPeopleIds = deskIds;

    final sessionAndProvider = await _createBestSession();
    _session = sessionAndProvider.$1;
    _providerLabel = sessionAndProvider.$2;

    if (_session!.inputNames.isNotEmpty) {
      _inputName = _session!.inputNames.first;
    }
    if (_session!.outputNames.isNotEmpty) {
      _outputName = _session!.outputNames.first;
    }

    _isReady = true;
  }

  Future<(OrtSession, String)> _createBestSession() async {
    final candidates = <(OrtProvider, String)>[];
    if (!kIsWeb && Platform.isAndroid) {
      candidates.add((OrtProvider.NNAPI, 'NNAPI'));
      candidates.add((OrtProvider.XNNPACK, 'XNNPACK'));
    } else if (!kIsWeb && Platform.isWindows) {
      candidates.add((OrtProvider.DIRECT_ML, 'DirectML'));
    }
    candidates.add((OrtProvider.CPU, 'CPU'));

    for (final (provider, name) in candidates) {
      try {
        final options = OrtSessionOptions(
          intraOpNumThreads: 4,
          interOpNumThreads: 1,
          providers: [provider],
        );
        final session = await _ort.createSessionFromAsset(
          modelAssetPath,
          options: options,
        );
        return (session, name);
      } catch (_) {
        // Fall through to next execution provider.
      }
    }

    final fallback = await _ort.createSessionFromAsset(modelAssetPath);
    return (fallback, 'CPU');
  }

  void resetTracker() {
    _tracker.reset();
  }

  /// Processes the latest frame if idle; returns null if an inference is already running.
  Future<DetectionFrameResult?> processFrame({
    required RawFrameData frame,
    required double confidenceThreshold,
    required bool mirrorHorizontal,
    required PresetFilter presetFilter,
  }) async {
    if (!_isReady || _session == null || _isInferring) {
      return null;
    }

    _isInferring = true;
    final sw = Stopwatch()..start();

    try {
      final int targetSize = inputSize;
      final prep = await Isolate.run(
        () => preprocessFrame(frame, inputSize: targetSize),
      );

      final inputTensor = await OrtValue.fromList(
        prep.tensor,
        [1, 3, targetSize, targetSize],
      );

      Map<String, OrtValue> outputs = const {};
      try {
        outputs = await _session!.run({_inputName: inputTensor});
        final outValue = outputs[_outputName] ?? outputs.values.first;
        final rawShape = outValue.shape;
        final List<dynamic> flatDynamic = await outValue.asFlattenedList();

        final Float32List outputFloats = Float32List(flatDynamic.length);
        for (int i = 0; i < flatDynamic.length; i++) {
          outputFloats[i] = (flatDynamic[i] as num).toDouble();
        }

        final int channels = rawShape.length >= 2 ? rawShape[1] : (_labels.length + 4);
        final int numAnchors = rawShape.length >= 3
            ? rawShape[2]
            : (outputFloats.length ~/ channels);
        final int numClasses = channels - 4;

        final allowedIds = presetFilter == PresetFilter.deskAndPeople
            ? _deskAndPeopleIds
            : null;
        final labelsCopy = _labels;

        final postInput = _PostprocessInput(
          output: outputFloats,
          numClasses: numClasses,
          numAnchors: numAnchors,
          labels: labelsCopy,
          inputSize: targetSize,
          scale: prep.scale,
          padX: prep.padX,
          padY: prep.padY,
          orientedWidth: prep.orientedWidth,
          orientedHeight: prep.orientedHeight,
          confidenceThreshold: confidenceThreshold,
          mirrorHorizontal: mirrorHorizontal,
          allowedClassIds: allowedIds,
        );

        final rawDetections = await Isolate.run(
          () => decodeYoloOutput(
            output: postInput.output,
            numClasses: postInput.numClasses,
            numAnchors: postInput.numAnchors,
            labels: postInput.labels,
            inputSize: postInput.inputSize,
            scale: postInput.scale,
            padX: postInput.padX,
            padY: postInput.padY,
            orientedWidth: postInput.orientedWidth,
            orientedHeight: postInput.orientedHeight,
            confidenceThreshold: postInput.confidenceThreshold,
            mirrorHorizontal: postInput.mirrorHorizontal,
            allowedClassIds: postInput.allowedClassIds,
          ),
        );

        final tracked = _tracker.update(rawDetections);
        sw.stop();

        return DetectionFrameResult(
          detections: tracked,
          inferenceMs: sw.elapsedMilliseconds,
          providerLabel: _providerLabel,
        );
      } finally {
        await inputTensor.dispose();
        for (final val in outputs.values) {
          await val.dispose();
        }
      }
    } finally {
      _isInferring = false;
    }
  }

  Future<void> dispose() async {
    _isReady = false;
    await _session?.close();
    _session = null;
  }
}
