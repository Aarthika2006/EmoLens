/// Represents a recorded session of emotion analysis.
class Session {
  final int? id;
  final DateTime startTime;
  final DateTime? endTime;
  final int totalFrames;
  final int happyCount;
  final int neutralCount;
  final int sadCount;
  final String? notes;

  const Session({
    this.id,
    required this.startTime,
    this.endTime,
    this.totalFrames = 0,
    this.happyCount = 0,
    this.neutralCount = 0,
    this.sadCount = 0,
    this.notes,
  });

  Duration get duration {
    if (endTime == null) return Duration.zero;
    return endTime!.difference(startTime);
  }

  String get durationFormatted {
    final d = duration;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  double get happyPercent =>
      totalFrames > 0 ? (happyCount / totalFrames) * 100 : 0;
  double get neutralPercent =>
      totalFrames > 0 ? (neutralCount / totalFrames) * 100 : 0;
  double get sadPercent =>
      totalFrames > 0 ? (sadCount / totalFrames) * 100 : 0;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'start_time': startTime.toIso8601String(),
        'end_time': endTime?.toIso8601String(),
        'total_frames': totalFrames,
        'happy_count': happyCount,
        'neutral_count': neutralCount,
        'sad_count': sadCount,
        'notes': notes,
      };

  factory Session.fromMap(Map<String, dynamic> map) {
    return Session(
      id: map['id'] as int?,
      startTime: DateTime.parse(map['start_time'] as String),
      endTime: map['end_time'] != null
          ? DateTime.parse(map['end_time'] as String)
          : null,
      totalFrames: (map['total_frames'] as int?) ?? 0,
      happyCount: (map['happy_count'] as int?) ?? 0,
      neutralCount: (map['neutral_count'] as int?) ?? 0,
      sadCount: (map['sad_count'] as int?) ?? 0,
      notes: map['notes'] as String?,
    );
  }

  Session copyWith({
    int? id,
    DateTime? startTime,
    DateTime? endTime,
    int? totalFrames,
    int? happyCount,
    int? neutralCount,
    int? sadCount,
    String? notes,
  }) {
    return Session(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      totalFrames: totalFrames ?? this.totalFrames,
      happyCount: happyCount ?? this.happyCount,
      neutralCount: neutralCount ?? this.neutralCount,
      sadCount: sadCount ?? this.sadCount,
      notes: notes ?? this.notes,
    );
  }

  /// Export to CSV row.
  List<String> toCsvRow() => [
        id?.toString() ?? '',
        startTime.toIso8601String(),
        endTime?.toIso8601String() ?? '',
        durationFormatted,
        totalFrames.toString(),
        happyCount.toString(),
        neutralCount.toString(),
        sadCount.toString(),
        happyPercent.toStringAsFixed(1),
        neutralPercent.toStringAsFixed(1),
        sadPercent.toStringAsFixed(1),
        notes ?? '',
      ];

  static List<String> csvHeaders() => [
        'ID',
        'Start Time',
        'End Time',
        'Duration',
        'Total Frames',
        'Happy Count',
        'Neutral Count',
        'Sad Count',
        'Happy %',
        'Neutral %',
        'Sad %',
        'Notes',
      ];
}
