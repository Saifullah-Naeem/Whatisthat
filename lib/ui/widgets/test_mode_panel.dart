import 'package:material_ui/material_ui.dart';

/// Telemetry and confidence-tuning panel shown only when Test Mode is enabled.
class TestModePanel extends StatelessWidget {
  const TestModePanel({
    super.key,
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
              min: 0.15,
              max: 0.70,
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
