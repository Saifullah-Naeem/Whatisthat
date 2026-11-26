import 'package:material_ui/material_ui.dart';

import '../../models/detection.dart';

/// Bottom dark glassmorphic bar summarizing currently visible objects on screen.
class StatusDock extends StatelessWidget {
  const StatusDock({
    super.key,
    required this.detections,
    required this.isModelReady,
  });

  final List<Detection> detections;
  final bool isModelReady;

  @override
  Widget build(BuildContext context) {
    final Map<String, (int count, int classId)> grouped = {};
    for (final det in detections) {
      final existing = grouped[det.label];
      if (existing == null) {
        grouped[det.label] = (1, det.classId);
      } else {
        grouped[det.label] = (existing.$1 + 1, existing.$2);
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14).withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: !isModelReady
          ? const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF22D3EE),
                  ),
                ),
                SizedBox(width: 10),
                Text(
                  'Loading WhatIsThat AI (601 classes)...',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            )
          : grouped.isEmpty
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.center_focus_weak_rounded,
                      color: Color(0xFF22D3EE),
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Point camera at objects (PC, glasses, hands...)',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: grouped.entries.map((entry) {
                      final label = entry.key;
                      final count = entry.value.$1;
                      final color = colorForClass(entry.value.$2);
                      return Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: color.withValues(alpha: 0.55),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              count > 1 ? '$label ×$count' : label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(growable: false),
                  ),
                ),
    );
  }
}
