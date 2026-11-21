import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/camera_provider.dart';
import '../../providers/settings_provider.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/services/face_detection_service.dart';
import '../../data/models/emotion_result.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with WidgetsBindingObserver {
  Timer? _inferenceTimer;
  bool _inferring = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startStreamIfReady();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _stopAll();
    } else if (state == AppLifecycleState.resumed) {
      _startStreamIfReady();
    }
  }

  Future<void> _startStreamIfReady() async {
    final settings = await ref.read(settingsProvider.future);
    if (settings.hasCameraIp && ref.read(isStreamingProvider)) {
      _startStream(settings);
    }
  }

  Future<void> _startStream(AppSettings settings) async {
    final streamSvc = ref.read(cameraStreamServiceProvider);
    ref.read(isStreamingProvider.notifier).state = true;
    await streamSvc.startStream(
      ip: settings.cameraIp!,
      httpPort: settings.httpPort,
      streamPort: settings.streamPort,
      mode: settings.streamMode,
      streamPath: settings.streamPath,
      capturePath: settings.capturePath,
    );
    _startInferenceLoop();
  }

  void _startInferenceLoop() {
    _inferenceTimer?.cancel();
    _inferenceTimer = Timer.periodic(
      const Duration(milliseconds: AppConstants.inferenceThrottleMs),
      (_) => _runInference(),
    );
  }

  Future<void> _runInference() async {
    if (_inferring) return;
    _inferring = true;
    try {
      final frame = ref.read(frameStreamProvider).valueOrNull;
      if (frame == null) return;

      final faceDetSvc = ref.read(faceDetectionServiceProvider);
      final classifierAsync = ref.read(emotionClassifierProvider);

      final classifier = classifierAsync.valueOrNull;
      if (classifier == null || !classifier.isInitialized) return;

      final detResult = await faceDetSvc.detectFace(frame);
      if (detResult.faceDetected && detResult.boundingBox != null) {
        ref.read(detectedFaceBoundingBoxProvider.notifier).state =
            detResult.boundingBox;
        ref.read(originalFrameSizeProvider.notifier).state = (
          width: detResult.imageWidth.toDouble(),
          height: detResult.imageHeight.toDouble()
        );
      } else {
        ref.read(detectedFaceBoundingBoxProvider.notifier).state = null;
      }

      if (!detResult.faceDetected || detResult.faceCrop == null) return;

      final emotionResult = classifier.classify(detResult.faceCrop!);
      final settings = ref.read(settingsProvider).valueOrNull;
      final window =
          settings?.smoothingWindow ?? AppConstants.defaultSmoothingWindow;

      ref.read(emotionProvider.notifier).addResult(emotionResult, window);
    } finally {
      _inferring = false;
    }
  }

  void _stopAll() {
    _inferenceTimer?.cancel();
    final streamSvc = ref.read(cameraStreamServiceProvider);
    streamSvc.stopStream();
    ref.read(isStreamingProvider.notifier).state = false;
    ref.read(detectedFaceBoundingBoxProvider.notifier).state = null;
  }

  Future<void> _toggleStream() async {
    final isStreaming = ref.read(isStreamingProvider);
    if (isStreaming) {
      _stopAll();
    } else {
      final settings = await ref.read(settingsProvider.future);
      if (!mounted) return;
      if (!settings.hasCameraIp) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please set camera IP in Settings first')),
        );
        return;
      }
      await _startStream(settings);
    }
  }

  void _takeSnapshot() {
    final frame = ref.read(frameStreamProvider).valueOrNull;
    if (frame != null) {
      ref.read(snapshotProvider.notifier).state = frame;
      final emotion = ref.read(emotionProvider);
      context.push('/feedback', extra: {
        'snapshotBytes': frame,
        'predictedLabel': emotion.smoothedLabel,
        'confidence': emotion.smoothedConfidence,
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inferenceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final connectionStatus = ref.watch(connectionStatusProvider);
    final frameAsync = ref.watch(frameStreamProvider);
    final emotionState = ref.watch(emotionProvider);
    final isStreaming = ref.watch(isStreamingProvider);
    final streamSvc = ref.read(cameraStreamServiceProvider);
    final bbox = ref.watch(detectedFaceBoundingBoxProvider);
    final frameSize = ref.watch(originalFrameSizeProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/app_icon.png',
              width: 28,
              height: 28,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.remove_red_eye_rounded,
                color: AppColors.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'EmoLens',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
          ],
        ),
        actions: [
          _ConnectionChip(
            status: connectionStatus.valueOrNull ?? ConnectionStatus.offline,
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.history_rounded),
            onPressed: () => context.push('/history'),
            tooltip: 'History',
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => context.push('/settings'),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (settings) {
          if (!settings.hasCameraIp) {
            return _NoCameraSetupCard(onSetup: () => context.push('/settings'));
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 720 ||
                  MediaQuery.of(context).orientation == Orientation.landscape;

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: isWide
                      ? _DesktopLandscapeDashboard(
                          frameAsync: frameAsync,
                          emotionState: emotionState,
                          isStreaming: isStreaming,
                          fps: streamSvc.currentFps,
                          latencyMs: streamSvc.latencyMs,
                          bbox: bbox,
                          frameSize: frameSize,
                          onToggleStream: _toggleStream,
                          onSnapshot: _takeSnapshot,
                        )
                      : _MobilePortraitDashboard(
                          frameAsync: frameAsync,
                          emotionState: emotionState,
                          isStreaming: isStreaming,
                          fps: streamSvc.currentFps,
                          latencyMs: streamSvc.latencyMs,
                          bbox: bbox,
                          frameSize: frameSize,
                          onToggleStream: _toggleStream,
                          onSnapshot: _takeSnapshot,
                        ),
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        onTap: (i) {
          if (i == 1) context.push('/history');
          if (i == 2) context.push('/settings');
          if (i == 3) context.push('/about');
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_rounded),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.info_rounded),
            label: 'About',
          ),
        ],
      ),
    );
  }
}

/// Responsive layout for PC / Tablets / Landscape Phones
class _DesktopLandscapeDashboard extends StatelessWidget {
  final AsyncValue<Uint8List> frameAsync;
  final EmotionState emotionState;
  final bool isStreaming;
  final double fps;
  final int latencyMs;
  final FaceBoundingBox? bbox;
  final ({double width, double height}) frameSize;
  final VoidCallback onToggleStream;
  final VoidCallback onSnapshot;

  const _DesktopLandscapeDashboard({
    required this.frameAsync,
    required this.emotionState,
    required this.isStreaming,
    required this.fps,
    required this.latencyMs,
    required this.bbox,
    required this.frameSize,
    required this.onToggleStream,
    required this.onSnapshot,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Column (Camera + Controls)
          Expanded(
            flex: 6,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _CameraFeedCard(
                    frameAsync: frameAsync,
                    bbox: bbox,
                    frameSize: frameSize,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _StatChip(label: 'FPS', value: fps.toStringAsFixed(1)),
                      const SizedBox(width: 8),
                      _StatChip(label: 'Latency', value: '${latencyMs}ms'),
                      const SizedBox(width: 8),
                      _StatChip(
                        label: 'Mode',
                        value: isStreaming ? 'Live' : 'Stopped',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ControlsRow(
                    isStreaming: isStreaming,
                    onToggle: onToggleStream,
                    onSnapshot: onSnapshot,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Right Column (Emotion metrics + Timeline)
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _EmotionCard(emotionState: emotionState),
                  const SizedBox(height: 8),
                  _TimelineCard(results: emotionState.recentResults),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Responsive layout for Mobile Portrait
class _MobilePortraitDashboard extends StatelessWidget {
  final AsyncValue<Uint8List> frameAsync;
  final EmotionState emotionState;
  final bool isStreaming;
  final double fps;
  final int latencyMs;
  final FaceBoundingBox? bbox;
  final ({double width, double height}) frameSize;
  final VoidCallback onToggleStream;
  final VoidCallback onSnapshot;

  const _MobilePortraitDashboard({
    required this.frameAsync,
    required this.emotionState,
    required this.isStreaming,
    required this.fps,
    required this.latencyMs,
    required this.bbox,
    required this.frameSize,
    required this.onToggleStream,
    required this.onSnapshot,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _CameraFeedCard(
            frameAsync: frameAsync,
            bbox: bbox,
            frameSize: frameSize,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                _StatChip(label: 'FPS', value: fps.toStringAsFixed(1)),
                const SizedBox(width: 8),
                _StatChip(label: 'Latency', value: '${latencyMs}ms'),
              ],
            ),
          ),
          _EmotionCard(emotionState: emotionState),
          _TimelineCard(results: emotionState.recentResults),
          _ControlsRow(
            isStreaming: isStreaming,
            onToggle: onToggleStream,
            onSnapshot: onSnapshot,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _NoCameraSetupCard extends StatelessWidget {
  final VoidCallback onSetup;
  const _NoCameraSetupCard({required this.onSetup});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/app_icon.png',
                  width: 96,
                  height: 96,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.videocam_off_rounded,
                    size: 80,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Camera Not Configured',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Set up your ESP32-CAM or Mobile IP Webcam in Settings to connect.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: onSetup,
                  icon: const Icon(Icons.settings_rounded),
                  label: const Text('Go to Settings'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraFeedCard extends StatelessWidget {
  final AsyncValue<Uint8List> frameAsync;
  final FaceBoundingBox? bbox;
  final ({double width, double height}) frameSize;

  const _CameraFeedCard({
    required this.frameAsync,
    this.bbox,
    required this.frameSize,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: AppColors.border.withOpacity(0.5)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: frameAsync.when(
            loading: () => const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  SizedBox(height: 12),
                  Text(
                    'Connecting to camera…',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            error: (e, _) => Center(
              child: Text(
                'Stream error: $e',
                style: const TextStyle(color: AppColors.error),
              ),
            ),
            data: (bytes) => Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
                if (bbox != null)
                  CustomPaint(
                    painter: _FaceBracketPainter(
                      bbox: bbox!,
                      imageSize: Size(frameSize.width, frameSize.height),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter that draws modern viewfinder corner brackets around face
class _FaceBracketPainter extends CustomPainter {
  final FaceBoundingBox bbox;
  final Size imageSize;

  _FaceBracketPainter({required this.bbox, required this.imageSize});

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.width == 0 || imageSize.height == 0) return;

    // Calculate aspect fit scaling
    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;
    final double scale = scaleX < scaleY ? scaleX : scaleY;

    final double offsetX = (size.width - (imageSize.width * scale)) / 2;
    final double offsetY = (size.height - (imageSize.height * scale)) / 2;

    final Rect rect = Rect.fromLTWH(
      offsetX + (bbox.left * scale),
      offsetY + (bbox.top * scale),
      bbox.width * scale,
      bbox.height * scale,
    );

    final paint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final double corner = (rect.width * 0.22).clamp(12.0, 36.0);

    // Top-Left corner
    canvas.drawLine(rect.topLeft, Offset(rect.left + corner, rect.top), paint);
    canvas.drawLine(rect.topLeft, Offset(rect.left, rect.top + corner), paint);

    // Top-Right corner
    canvas.drawLine(rect.topRight, Offset(rect.right - corner, rect.top), paint);
    canvas.drawLine(rect.topRight, Offset(rect.right, rect.top + corner), paint);

    // Bottom-Left corner
    canvas.drawLine(
        rect.bottomLeft, Offset(rect.left + corner, rect.bottom), paint);
    canvas.drawLine(
        rect.bottomLeft, Offset(rect.left, rect.bottom - corner), paint);

    // Bottom-Right corner
    canvas.drawLine(
        rect.bottomRight, Offset(rect.right - corner, rect.bottom), paint);
    canvas.drawLine(
        rect.bottomRight, Offset(rect.right, rect.bottom - corner), paint);
  }

  @override
  bool shouldRepaint(covariant _FaceBracketPainter oldDelegate) {
    return oldDelegate.bbox != bbox || oldDelegate.imageSize != imageSize;
  }
}

class _EmotionCard extends StatelessWidget {
  final EmotionState emotionState;
  const _EmotionCard({required this.emotionState});

  Color _colorForLabel(String label) {
    switch (label.toLowerCase()) {
      case 'happy':
        return AppColors.happy;
      case 'sad':
        return AppColors.sad;
      default:
        return AppColors.neutral;
    }
  }

  String _emojiForLabel(String label) {
    switch (label.toLowerCase()) {
      case 'happy':
        return '😊';
      case 'sad':
        return '😢';
      default:
        return '😐';
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = emotionState.smoothedLabel;
    final confidence = emotionState.smoothedConfidence;
    final color = _colorForLabel(label);

    final probs = emotionState.latest?.probabilities ?? {
      'Happy': label == 'Happy' ? confidence : 0.0,
      'Neutral': label == 'Neutral' ? confidence : 0.0,
      'Sad': label == 'Sad' ? confidence : 0.0,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: color.withOpacity(0.4), width: 2),
                  ),
                  child: Center(
                    child: Text(
                      _emojiForLabel(label),
                      style: const TextStyle(fontSize: 42),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              color: color,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${(confidence * 100).toStringAsFixed(1)}% confidence',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: confidence.clamp(0.0, 1.0),
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 12,
              ),
            ),
            const SizedBox(height: 16),
            // Multi-class probabilities breakdown
            Row(
              children: [
                _EmotionProbChip(
                  emoji: '😊',
                  name: 'Happy',
                  prob: probs['Happy'] ?? 0.0,
                  activeColor: AppColors.happy,
                ),
                const SizedBox(width: 8),
                _EmotionProbChip(
                  emoji: '😐',
                  name: 'Neutral',
                  prob: probs['Neutral'] ?? 0.0,
                  activeColor: AppColors.neutral,
                ),
                const SizedBox(width: 8),
                _EmotionProbChip(
                  emoji: '😢',
                  name: 'Sad',
                  prob: probs['Sad'] ?? 0.0,
                  activeColor: AppColors.sad,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmotionProbChip extends StatelessWidget {
  final String emoji;
  final String name;
  final double prob;
  final Color activeColor;

  const _EmotionProbChip({
    required this.emoji,
    required this.name,
    required this.prob,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.inputBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: prob > 0.4 ? activeColor.withOpacity(0.5) : AppColors.border,
          ),
        ),
        child: Column(
          children: [
            Text('$emoji $name',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(
              '${(prob * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: prob > 0.4 ? activeColor : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  final List<EmotionResult> results;
  const _TimelineCard({required this.results});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final spots = results.asMap().entries.map((e) {
      final secsAgo = now.difference(e.value.timestamp).inSeconds.toDouble();
      final yVal = e.value.label == 'Happy'
          ? 1.0
          : e.value.label == 'Neutral'
              ? 0.5
              : 0.0;
      return FlSpot(60 - secsAgo.clamp(0, 60), yVal);
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Emotion Timeline (Last 60s)',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${results.length} frames',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 100,
              child: spots.isEmpty
                  ? const Center(
                      child: Text(
                        'Start streaming to see emotion timeline',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    )
                  : LineChart(
                      LineChartData(
                        minX: 0,
                        maxX: 60,
                        minY: -0.1,
                        maxY: 1.1,
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            color: AppColors.primary,
                            barWidth: 2.5,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: AppColors.primary.withOpacity(0.12),
                            ),
                          ),
                        ],
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              interval: 0.5,
                              reservedSize: 32,
                              getTitlesWidget: (value, _) {
                                if (value == 1.0) {
                                  return const Text('😊',
                                      style: TextStyle(fontSize: 12));
                                }
                                if (value == 0.5) {
                                  return const Text('😐',
                                      style: TextStyle(fontSize: 12));
                                }
                                if (value == 0.0) {
                                  return const Text('😢',
                                      style: TextStyle(fontSize: 12));
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ),
                          bottomTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        gridData: FlGridData(
                          show: true,
                          drawHorizontalLine: true,
                          horizontalInterval: 0.5,
                          getDrawingHorizontalLine: (_) => FlLine(
                            color: AppColors.border.withOpacity(0.35),
                            strokeWidth: 1,
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlsRow extends StatelessWidget {
  final bool isStreaming;
  final VoidCallback onToggle;
  final VoidCallback onSnapshot;

  const _ControlsRow({
    required this.isStreaming,
    required this.onToggle,
    required this.onSnapshot,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: onToggle,
            icon: Icon(isStreaming ? Icons.stop_rounded : Icons.play_arrow_rounded),
            label: Text(isStreaming ? 'Stop Streaming' : 'Start Streaming'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isStreaming ? AppColors.sad : AppColors.primary,
              minimumSize: const Size(0, 52),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: isStreaming ? onSnapshot : null,
            icon: const Icon(Icons.camera_alt_rounded),
            label: const Text('Snapshot'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 52),
            ),
          ),
        ),
      ],
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  final ConnectionStatus status;
  const _ConnectionChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status == ConnectionStatus.connected
        ? AppColors.connected
        : status == ConnectionStatus.connecting
            ? AppColors.connecting
            : AppColors.disconnected;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            status.displayName,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
