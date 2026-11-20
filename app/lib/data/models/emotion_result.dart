/// Represents the result of emotion classification on a single frame.
class EmotionResult {
  /// The detected emotion label (Happy, Neutral, Sad).
  final String label;

  /// Confidence score [0.0, 1.0].
  final double confidence;

  /// All class probabilities.
  final Map<String, double> probabilities;

  /// Timestamp of this result.
  final DateTime timestamp;

  /// Inference latency in milliseconds.
  final int latencyMs;

  const EmotionResult({
    required this.label,
    required this.confidence,
    required this.probabilities,
    required this.timestamp,
    this.latencyMs = 0,
  });

  /// Creates an empty/unknown result.
  factory EmotionResult.empty() => EmotionResult(
        label: 'Unknown',
        confidence: 0.0,
        probabilities: {'Happy': 0.0, 'Neutral': 0.0, 'Sad': 0.0},
        timestamp: DateTime.now(),
      );

  /// Whether this result meets the confidence threshold.
  bool meetsThreshold(double threshold) => confidence >= threshold;

  /// Returns the emoji for this emotion.
  String get emoji {
    switch (label.toLowerCase()) {
      case 'happy':
        return '😊';
      case 'sad':
        return '😢';
      case 'neutral':
        return '😐';
      default:
        return '❓';
    }
  }

  EmotionResult copyWith({
    String? label,
    double? confidence,
    Map<String, double>? probabilities,
    DateTime? timestamp,
    int? latencyMs,
  }) {
    return EmotionResult(
      label: label ?? this.label,
      confidence: confidence ?? this.confidence,
      probabilities: probabilities ?? this.probabilities,
      timestamp: timestamp ?? this.timestamp,
      latencyMs: latencyMs ?? this.latencyMs,
    );
  }

  Map<String, dynamic> toMap() => {
        'label': label,
        'confidence': confidence,
        'probabilities': probabilities.map((k, v) => MapEntry(k, v)),
        'timestamp': timestamp.toIso8601String(),
        'latencyMs': latencyMs,
      };

  factory EmotionResult.fromMap(Map<String, dynamic> map) {
    return EmotionResult(
      label: map['label'] as String,
      confidence: (map['confidence'] as num).toDouble(),
      probabilities: (map['probabilities'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toDouble())),
      timestamp: DateTime.parse(map['timestamp'] as String),
      latencyMs: (map['latencyMs'] as int?) ?? 0,
    );
  }

  @override
  String toString() =>
      'EmotionResult($label: ${(confidence * 100).toStringAsFixed(1)}%)';
}
