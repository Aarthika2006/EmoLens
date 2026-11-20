import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/camera_stream_service.dart';
import '../data/services/face_detection_service.dart';
import '../data/services/emotion_classifier_service.dart';
import '../data/models/emotion_result.dart';
import '../core/constants/app_constants.dart';

// --- Service providers ---

final cameraStreamServiceProvider = Provider<CameraStreamService>((ref) {
  final svc = CameraStreamService();
  ref.onDispose(svc.dispose);
  return svc;
});

final faceDetectionServiceProvider = Provider<FaceDetectionService>((ref) {
  final svc = FaceDetectionService();
  ref.onDispose(svc.dispose);
  return svc;
});

final emotionClassifierProvider =
    FutureProvider<EmotionClassifierService>((ref) async {
  final svc = EmotionClassifierService();
  await svc.initialize();
  ref.onDispose(svc.dispose);
  return svc;
});

// --- Connection status ---

final connectionStatusProvider = StreamProvider<ConnectionStatus>((ref) {
  final streamSvc = ref.watch(cameraStreamServiceProvider);
  return streamSvc.statusStream;
});

// --- Raw frame stream ---

final frameStreamProvider = StreamProvider<Uint8List>((ref) {
  final streamSvc = ref.watch(cameraStreamServiceProvider);
  return streamSvc.frameStream;
});

// --- FPS / latency ---

final fpsProvider = Provider<double>((ref) {
  ref.watch(frameStreamProvider); // rebuild on each frame
  return ref.read(cameraStreamServiceProvider).currentFps;
});

// --- Emotion result with EMA smoothing ---

class EmotionState {
  final EmotionResult? latest;
  final String smoothedLabel;
  final double smoothedConfidence;
  final List<EmotionResult> recentResults;

  const EmotionState({
    this.latest,
    this.smoothedLabel = 'Unknown',
    this.smoothedConfidence = 0.0,
    this.recentResults = const [],
  });

  EmotionState copyWith({
    EmotionResult? latest,
    String? smoothedLabel,
    double? smoothedConfidence,
    List<EmotionResult>? recentResults,
  }) {
    return EmotionState(
      latest: latest ?? this.latest,
      smoothedLabel: smoothedLabel ?? this.smoothedLabel,
      smoothedConfidence: smoothedConfidence ?? this.smoothedConfidence,
      recentResults: recentResults ?? this.recentResults,
    );
  }
}

class EmotionNotifier extends Notifier<EmotionState> {
  // EMA smoothed probabilities per class
  Map<String, double> _emaProbs = {
    'Happy': 0.0,
    'Neutral': 0.0,
    'Sad': 0.0,
  };

  // Consecutive frames where Sad has met its strict threshold.
  // Sad is only announced after sadSustainFrames consecutive hits to prevent
  // transient low-light false positives.
  int _sadSustainCount = 0;

  @override
  EmotionState build() => const EmotionState();

  void addResult(EmotionResult result, int smoothingWindow) {
    // ── 1. EMA smoothing ──────────────────────────────────────────────────
    final alpha = 2.0 / (smoothingWindow + 1);
    for (final label in _emaProbs.keys) {
      final prob = result.probabilities[label] ?? 0.0;
      _emaProbs[label] = alpha * prob + (1 - alpha) * _emaProbs[label]!;
    }

    final happyEma   = _emaProbs['Happy']   ?? 0.0;
    final neutralEma = _emaProbs['Neutral'] ?? 0.0;
    final sadEma     = _emaProbs['Sad']     ?? 0.0;

    // ── 2. Sad sustain gate ───────────────────────────────────────────────
    // Sad only wins when it has been above its strict threshold for
    // sadSustainFrames consecutive frames (≈ 3 s at ~4 fps).
    if (sadEma >= AppConstants.sadThreshold) {
      _sadSustainCount++;
    } else {
      _sadSustainCount = 0;
    }
    final sadGateOpen = _sadSustainCount >= AppConstants.sadSustainFrames;

    // ── 3. Per-emotion threshold winner selection ─────────────────────────
    //
    // Priority order: Sad (strict + gate) → Happy (lenient) → Neutral → Unknown
    //
    // Why this order?
    //   • Sad is high-stakes (caregiver alert) → needs strict gating.
    //   • Happy is under-detected by the model on non-DS faces → lower bar.
    //   • Neutral is the "safe" fallback when nothing is clear.
    //   • Unknown fires when even Neutral hasn't reached its threshold.
    String smoothedLabel;
    double smoothedConf;

    if (sadGateOpen && sadEma >= AppConstants.sadThreshold) {
      smoothedLabel = 'Sad';
      smoothedConf  = sadEma;
    } else if (happyEma >= AppConstants.happyThreshold &&
               happyEma >= neutralEma) {
      // Happy wins when it exceeds its threshold AND leads Neutral.
      smoothedLabel = 'Happy';
      smoothedConf  = happyEma;
    } else if (neutralEma >= AppConstants.neutralThreshold) {
      smoothedLabel = 'Neutral';
      smoothedConf  = neutralEma;
    } else {
      // All classes below their thresholds → too uncertain to declare.
      smoothedLabel = 'Unknown';
      smoothedConf  = [happyEma, neutralEma, sadEma]
          .reduce((a, b) => a > b ? a : b);
    }

    // ── 4. Update timeline (last 60 s) ────────────────────────────────────
    final cutoff = DateTime.now().subtract(
      Duration(seconds: AppConstants.timelineWindowSeconds),
    );
    final recent = [
      ...state.recentResults.where((r) => r.timestamp.isAfter(cutoff)),
      result,
    ];

    state = state.copyWith(
      latest: result,
      smoothedLabel: smoothedLabel,
      smoothedConfidence: smoothedConf,
      recentResults: recent,
    );
  }

  void reset() {
    _emaProbs = {'Happy': 0.0, 'Neutral': 0.0, 'Sad': 0.0};
    _sadSustainCount = 0;
    state = const EmotionState();
  }
}

final emotionProvider = NotifierProvider<EmotionNotifier, EmotionState>(
  EmotionNotifier.new,
);

// --- Streaming active flag ---

final isStreamingProvider = StateProvider<bool>((ref) => false);

// --- Detected face bounding box & frame dimensions for overlay ---

final detectedFaceBoundingBoxProvider =
    StateProvider<FaceBoundingBox?>((ref) => null);

final originalFrameSizeProvider =
    StateProvider<({double width, double height})>(
        (ref) => (width: 320, height: 240));

// --- Snapshot ---

final snapshotProvider = StateProvider<Uint8List?>((ref) => null);
