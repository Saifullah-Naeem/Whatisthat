import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/detection.dart';
import '../services/detector_service.dart';
import '../services/image_preprocess.dart';
import 'widgets/detection_overlay.dart';
import 'widgets/status_dock.dart';

class CameraDetectionScreen extends StatefulWidget {
  const CameraDetectionScreen({
    super.key,
    this.detectorService,
    this.initialTestMode = false,
  });

  final DetectorService? detectorService;
  final bool initialTestMode;

  @override
  State<CameraDetectionScreen> createState() => _CameraDetectionScreenState();
}

class _CameraDetectionScreenState extends State<CameraDetectionScreen>
    with WidgetsBindingObserver {
  late final DetectorService _detector;
  final GlobalKey _captureKey = GlobalKey();

  List<CameraDescription> _cameras = const [];
  int _selectedCameraIndex = 0;
  CameraController? _cameraController;

  bool _isInitializingCamera = true;
  String? _errorMessage;

  List<Detection> _detections = const [];
  bool _testMode = false;
  double _confidenceThreshold = 0.34;
  PresetFilter _presetFilter = PresetFilter.all;

  double _fps = 0.0;
  int _inferenceMs = 0;
  DateTime _lastResultTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _testMode = widget.initialTestMode;
    _detector = widget.detectorService ?? DetectorService();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _initModel(),
      _initCameras(),
    ]);
  }

  Future<void> _initModel() async {
    try {
      await _detector.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Failed to load AI model: $e');
      }
    }
  }

  Future<void> _initCameras() async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        final status = await Permission.camera.request();
        if (!status.isGranted) {
          if (mounted) {
            setState(() {
              _isInitializingCamera = false;
              _errorMessage = 'Camera permission is required for WhatIsThat.';
            });
          }
          return;
        }
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _isInitializingCamera = false;
            _errorMessage = 'No camera found on this device.';
          });
        }
        return;
      }

      // Prefer back camera on mobile; first webcam on desktop.
      int initialIndex = 0;
      if (!kIsWeb && Platform.isAndroid) {
        final backIdx = cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
        );
        if (backIdx >= 0) initialIndex = backIdx;
      }

      _cameras = cameras;
      await _startCameraAtIndex(initialIndex);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializingCamera = false;
          _errorMessage = 'Camera initialization failed: $e';
        });
      }
    }
  }

  Future<void> _startCameraAtIndex(int index) async {
    setState(() {
      _isInitializingCamera = true;
      _errorMessage = null;
      _detections = const [];
    });

    final oldController = _cameraController;
    _cameraController = null;
    if (oldController != null) {
      try {
        if (oldController.value.isStreamingImages) {
          await oldController.stopImageStream();
        }
      } catch (_) {}
      await oldController.dispose();
    }

    _detector.resetTracker();
    _selectedCameraIndex = index;

    final controller = CameraController(
      _cameras[index],
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: (!kIsWeb && Platform.isAndroid)
          ? ImageFormatGroup.yuv420
          : ImageFormatGroup.bgra8888,
    );

    try {
      await controller.initialize();
      await controller.startImageStream(_onCameraFrame);
      if (mounted) {
        setState(() {
          _cameraController = controller;
          _isInitializingCamera = false;
        });
      } else {
        await controller.dispose();
      }
    } catch (e) {
      await controller.dispose();
      if (mounted) {
        setState(() {
          _isInitializingCamera = false;
          _errorMessage = 'Could not start camera stream: $e';
        });
      }
    }
  }

  void _onCameraFrame(CameraImage image) {
    if (!_detector.isReady || _cameras.isEmpty) return;

    final camera = _cameras[_selectedCameraIndex];
    final bool isAndroid = !kIsWeb && Platform.isAndroid;
    final bool isWindows = !kIsWeb && Platform.isWindows;

    final RawPixelFormat format = image.format.group == ImageFormatGroup.yuv420
        ? RawPixelFormat.yuv420
        : RawPixelFormat.bgra8888;

    if (format == RawPixelFormat.yuv420 && image.planes.length < 3) return;
    if (format == RawPixelFormat.bgra8888 && image.planes.isEmpty) return;

    // Copy plane buffers synchronously before returning from stream callback.
    final planes = image.planes
        .map((p) => Uint8List.fromList(p.bytes))
        .toList(growable: false);
    final bytesPerRow =
        image.planes.map((p) => p.bytesPerRow).toList(growable: false);
    final bytesPerPixel = image.planes
        .map((p) => p.bytesPerPixel ?? 1)
        .toList(growable: false);

    final int rotation = isAndroid ? camera.sensorOrientation : 0;
    final bool mirrorHorizontal =
        (isAndroid && camera.lensDirection == CameraLensDirection.front) ||
            isWindows;

    final rawFrame = RawFrameData(
      format: format,
      width: image.width,
      height: image.height,
      rotationDegrees: rotation,
      planes: planes,
      bytesPerRow: bytesPerRow,
      bytesPerPixel: bytesPerPixel,
    );

    unawaited(
      _detector
          .processFrame(
        frame: rawFrame,
        confidenceThreshold: _confidenceThreshold,
        mirrorHorizontal: mirrorHorizontal,
        presetFilter: _presetFilter,
      )
          .then((result) {
        if (result == null || !mounted) return;
        final now = DateTime.now();
        final elapsedUs = now.difference(_lastResultTime).inMicroseconds;
        _lastResultTime = now;
        final double instantFps = elapsedUs > 0 ? 1000000.0 / elapsedUs : 0.0;

        setState(() {
          _detections = result.detections;
          _inferenceMs = result.inferenceMs;
          _fps = _fps == 0.0
              ? instantFps
              : (_fps * 0.75 + instantFps * 0.25);
        });
      }),
    );
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _isInitializingCamera) return;
    final nextIndex = (_selectedCameraIndex + 1) % _cameras.length;
    await _startCameraAtIndex(nextIndex);
  }

  Future<void> _saveSnapshot() async {
    try {
      final boundary = _captureKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) return;

      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/WhatIsThat_$ts.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF161B26),
            behavior: SnackBarBehavior.floating,
            content: Text(
              'Saved snapshot: ${file.path}',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Snapshot failed: $e')),
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _cameraController = null;
    } else if (state == AppLifecycleState.resumed && _cameras.isNotEmpty) {
      _startCameraAtIndex(_selectedCameraIndex);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _detector.dispose();
    super.dispose();
  }

  double _previewAspectRatio(CameraController controller, Orientation ori) {
    final rawRatio = controller.value.aspectRatio;
    if (!kIsWeb && Platform.isAndroid && ori == Orientation.portrait) {
      return 1.0 / rawRatio;
    }
    return rawRatio;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;

    return Scaffold(
      backgroundColor: const Color(0xFF07090E),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Camera viewport + Bounding Box overlay
            Center(
              child: _errorMessage != null
                  ? _ErrorState(
                      message: _errorMessage!,
                      onRetry: _initCameras,
                    )
                  : (controller == null ||
                          !controller.value.isInitialized ||
                          _isInitializingCamera)
                      ? const _LoadingCameraState()
                      : OrientationBuilder(
                          builder: (context, orientation) {
                            return RepaintBoundary(
                              key: _captureKey,
                              child: AspectRatio(
                                aspectRatio: _previewAspectRatio(
                                  controller,
                                  orientation,
                                ),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    CameraPreview(controller),
                                    CustomPaint(
                                      painter: DetectionOverlayPainter(
                                        detections: _detections,
                                        showConfidence: _testMode,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),

            // Top Glass Control Bar
            Positioned(
              top: 10,
              left: 12,
              right: 12,
              child: _TopControlBar(
                canSwitchCamera: _cameras.length > 1,
                onSwitchCamera: _switchCamera,
                onSnapshot: _saveSnapshot,
                presetFilter: _presetFilter,
                onTogglePreset: () {
                  setState(() {
                    _presetFilter = _presetFilter == PresetFilter.all
                        ? PresetFilter.deskAndPeople
                        : PresetFilter.all;
                  });
                },
                testMode: _testMode,
                onToggleTestMode: (val) => setState(() => _testMode = val),
              ),
            ),

            // Optional Test Mode Telemetry + Confidence Slider
            if (_testMode)
              Positioned(
                top: 72,
                left: 14,
                right: 14,
                child: _TestModePanel(
                  fps: _fps,
                  inferenceMs: _inferenceMs,
                  providerLabel: _detector.providerLabel,
                  confidenceThreshold: _confidenceThreshold,
                  onConfidenceChanged: (val) {
                    setState(() => _confidenceThreshold = val);
                  },
                ),
              ),

            // Bottom Detected Objects Dock
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: StatusDock(
                detections: _detections,
                isModelReady: _detector.isReady,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopControlBar extends StatelessWidget {
  const _TopControlBar({
    required this.canSwitchCamera,
    required this.onSwitchCamera,
    required this.onSnapshot,
    required this.presetFilter,
    required this.onTogglePreset,
    required this.testMode,
    required this.onToggleTestMode,
  });

  final bool canSwitchCamera;
  final VoidCallback onSwitchCamera;
  final VoidCallback onSnapshot;
  final PresetFilter presetFilter;
  final VoidCallback onTogglePreset;
  final bool testMode;
  final ValueChanged<bool> onToggleTestMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14).withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF22D3EE), Color(0xFF6366F1)],
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'WhatIsThat',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const Spacer(),
          // Optional quick class filter chip
          InkWell(
            onTap: onTogglePreset,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: presetFilter == PresetFilter.deskAndPeople
                    ? const Color(0xFF6366F1).withValues(alpha: 0.30)
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: presetFilter == PresetFilter.deskAndPeople
                      ? const Color(0xFF818CF8)
                      : Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Text(
                presetFilter.displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Save snapshot',
            onPressed: onSnapshot,
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.camera_alt_outlined,
              color: Colors.white,
              size: 20,
            ),
          ),
          if (canSwitchCamera)
            IconButton(
              tooltip: 'Switch camera',
              onPressed: onSwitchCamera,
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.cameraswitch_outlined,
                color: Colors.white,
                size: 20,
              ),
            ),
          const SizedBox(width: 2),
          // Test Mode toggle (OFF by default)
          InkWell(
            onTap: () => onToggleTestMode(!testMode),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: testMode
                    ? const Color(0xFF22D3EE).withValues(alpha: 0.22)
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: testMode
                      ? const Color(0xFF22D3EE)
                      : Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 14,
                    color: testMode ? const Color(0xFF22D3EE) : Colors.white70,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Test',
                    style: TextStyle(
                      color: testMode ? const Color(0xFF22D3EE) : Colors.white70,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TestModePanel extends StatelessWidget {
  const _TestModePanel({
    required this.fps,
    required this.inferenceMs,
    required this.providerLabel,
    required this.confidenceThreshold,
    required this.onConfidenceChanged,
  });

  final double fps;
  final int inferenceMs;
  final String providerLabel;
  final double confidenceThreshold;
  final ValueChanged<double> onConfidenceChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14).withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF22D3EE).withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _MetricBadge(
                label: 'FPS',
                value: fps.toStringAsFixed(1),
                color: const Color(0xFF22D3EE),
              ),
              const SizedBox(width: 8),
              _MetricBadge(
                label: 'Latency',
                value: '${inferenceMs}ms',
                color: const Color(0xFF818CF8),
              ),
              const SizedBox(width: 8),
              _MetricBadge(
                label: 'Engine',
                value: providerLabel,
                color: const Color(0xFF34D399),
              ),
              const Spacer(),
              Text(
                'Conf ${(confidenceThreshold * 100).round()}%',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF22D3EE),
              inactiveTrackColor: Colors.white12,
              thumbColor: const Color(0xFF22D3EE),
              overlayColor: const Color(0xFF22D3EE).withValues(alpha: 0.2),
              trackHeight: 3,
            ),
            child: Slider(
              value: confidenceThreshold,
              min: 0.20,
              max: 0.75,
              divisions: 11,
              onChanged: onConfidenceChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricBadge extends StatelessWidget {
  const _MetricBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _LoadingCameraState extends StatelessWidget {
  const _LoadingCameraState();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: Color(0xFF22D3EE)),
        SizedBox(height: 14),
        Text(
          'Starting camera feed...',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.videocam_off_outlined,
            color: Color(0xFFFB7185),
            size: 46,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry Camera'),
          ),
        ],
      ),
    );
  }
}
