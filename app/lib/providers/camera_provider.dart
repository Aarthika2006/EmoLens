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

  @override
  EmotionState build() => const EmotionState();

  void addResult(EmotionResult result, int smoothingWindow) {
    // ── 1. EMA smoothing ──────────────────────────────────────────────────
    final alpha = 2.0 / (smoothingWindow + 1);
    for (final label in _emaProbs.keys) {
      final prob = result.probabilities[label] ?? 0.0;
      _emaProbs[label] = alpha * prob + (1 - alpha) * _emaProbs[label]!;
    }

    // ── 2. Determine highest smoothed emotion ─────────────────────────────
    String smoothedLabel = 'Unknown';
    double smoothedConf = 0.0;
    _emaProbs.forEach((label, prob) {
      if (prob > smoothedConf) {
        smoothedConf = prob;
        smoothedLabel = label;
      }
    });

    // ── 3. Update timeline (last 60 s) ────────────────────────────────────
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
