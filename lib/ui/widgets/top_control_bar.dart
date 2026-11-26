import 'package:material_ui/material_ui.dart';

import '../../models/detection.dart';

/// Top glassmorphic bar with WhatIsThat branding, preset filter, snapshot, camera switch, and Test Mode toggle.
class TopControlBar extends StatelessWidget {
  const TopControlBar({
    super.key,
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
