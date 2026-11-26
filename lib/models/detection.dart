import 'dart:ui';

/// A single detected object in normalized display coordinates ([0, 1]).
class Detection {
  const Detection({
    required this.classId,
    required this.label,
    required this.confidence,
    required this.box,
    this.trackId = 0,
  });

  final int classId;
  final String label;
  final double confidence;
  final Rect box;
  final int trackId;

  Detection copyWith({
    int? classId,
    String? label,
    double? confidence,
    Rect? box,
    int? trackId,
  }) {
    return Detection(
      classId: classId ?? this.classId,
      label: label ?? this.label,
      confidence: confidence ?? this.confidence,
      box: box ?? this.box,
      trackId: trackId ?? this.trackId,
    );
  }
}

/// Optional quick class filters for testing common desk/everyday objects.
enum PresetFilter {
  all('All 601'),
  deskAndPeople('PC, Glasses & Hands');

  const PresetFilter(this.displayName);
  final String displayName;
}

/// Curated everyday/tech/body labels when [PresetFilter.deskAndPeople] is chosen.
const Set<String> kDeskAndPeopleLabels = {
  'Glasses',
  'Sunglasses',
  'Goggles',
  'Human hand',
  'Person',
  'Human face',
  'Laptop',
  'Computer monitor',
  'Computer keyboard',
  'Computer mouse',
  'Desktop computer',
  'Tablet computer',
  'Mobile phone',
  'Telephone',
  'Headphones',
  'Microphone',
  'Webcam',
  'Television',
  'Camera',
  'Watch',
  'Mug',
  'Coffee cup',
  'Bottle',
  'Book',
  'Pen',
  'Chair',
  'Desk',
  'Backpack',
};

const List<Color> _kBoxPalette = [
  Color(0xFF22D3EE), // Cyan
  Color(0xFF818CF8), // Indigo
  Color(0xFF34D399), // Emerald
  Color(0xFFFBBF24), // Amber
  Color(0xFFF472B6), // Pink
  Color(0xFFA78BFA), // Violet
  Color(0xFF38BDF8), // Sky
  Color(0xFFFB7185), // Rose
  Color(0xFF4ADE80), // Green
  Color(0xFFFB923C), // Orange
];

Color colorForClass(int classId) => _kBoxPalette[classId.abs() % _kBoxPalette.length];
