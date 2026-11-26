import 'dart:math' as math;
import 'dart:ui';

import '../models/detection.dart';
import 'yolo_postprocess.dart';

class _TrackState {
  _TrackState({
    required this.trackId,
    required this.detection,
    required this.missedFrames,
  });

  final int trackId;
  Detection detection;
  int missedFrames;
}

/// Smooths bounding boxes across inference ticks using IoU association + adaptive EMA.
///
/// Fast-moving objects (e.g. hands waving) snap quickly so boxes don't lag behind,
/// while stationary objects get gentle damping to eliminate micro-jitter.
class BoxTracker {
  BoxTracker({this.maxMissedFrames = 1, this.matchIouThreshold = 0.20});

  final int maxMissedFrames;
  final double matchIouThreshold;

  int _nextTrackId = 1;
  final List<_TrackState> _tracks = [];

  void reset() {
    _tracks.clear();
  }

  List<Detection> update(List<Detection> detections) {
    final Set<int> matchedTrackIndices = {};
    final List<_TrackState> nextTracks = [];

    for (final det in detections) {
      int bestIdx = -1;
      double bestScore = -1.0;

      for (int i = 0; i < _tracks.length; i++) {
        if (matchedTrackIndices.contains(i)) continue;
        final prev = _tracks[i].detection;
        if (prev.classId != det.classId) continue;

        final double iou = computeIoU(prev.box, det.box);
        final double centerDist = (prev.box.center - det.box.center).distance;

        if (iou >= matchIouThreshold || centerDist < 0.14) {
          final double matchScore = iou + (0.2 - math.min(0.2, centerDist));
          if (matchScore > bestScore) {
            bestScore = matchScore;
            bestIdx = i;
          }
        }
      }

      if (bestIdx >= 0) {
        matchedTrackIndices.add(bestIdx);
        final track = _tracks[bestIdx];
        final Rect prevBox = track.detection.box;
        final double shift = (prevBox.center - det.box.center).distance;

        // Higher alpha on fast movement prevents trailing lag.
        final double alpha = shift > 0.05 ? 0.78 : 0.45;
        final Rect smoothedBox = Rect.lerp(prevBox, det.box, alpha) ?? det.box;
        final double smoothedConf =
            track.detection.confidence * (1 - alpha) + det.confidence * alpha;

        final updated = det.copyWith(
          box: smoothedBox,
          confidence: smoothedConf,
          trackId: track.trackId,
        );
        nextTracks.add(
          _TrackState(
            trackId: track.trackId,
            detection: updated,
            missedFrames: 0,
          ),
        );
      } else {
        final int id = _nextTrackId++;
        nextTracks.add(
          _TrackState(
            trackId: id,
            detection: det.copyWith(trackId: id),
            missedFrames: 0,
          ),
        );
      }
    }

    // Briefly retain tracks missed for 1 frame to avoid single-frame flicker.
    for (int i = 0; i < _tracks.length; i++) {
      if (matchedTrackIndices.contains(i)) continue;
      final track = _tracks[i];
      if (track.missedFrames < maxMissedFrames) {
        nextTracks.add(
          _TrackState(
            trackId: track.trackId,
            detection: track.detection,
            missedFrames: track.missedFrames + 1,
          ),
        );
      }
    }

    _tracks
      ..clear()
      ..addAll(nextTracks);

    return _tracks.map((t) => t.detection).toList(growable: false);
  }
}
