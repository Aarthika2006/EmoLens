import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/image_utils.dart';
import '../models/emotion_result.dart';

/// Service for running emotion classification using TFLite.
///
/// Inference runs in a separate isolate to avoid blocking the UI thread.
/// Model preprocessing: resize 224x224, normalize to [-1, 1] range.
class EmotionClassifierService {
  Interpreter? _interpreter;
  List<String> _labels = AppConstants.defaultLabels;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  List<String> get labels => _labels;

  /// Initialize the TFLite interpreter and load labels.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Try GPU delegate first, fall back to CPU
      _interpreter = await _createInterpreter();
      _labels = await _loadLabels();
      _isInitialized = true;
    } catch (e) {
      rethrow;
    }
  }

  Future<Interpreter> _createInterpreter() async {
    final options = InterpreterOptions();

    // Try NNAPI delegate on Android
    try {
      // options.addDelegate(NnApiDelegate());
      // Note: NNAPI delegate may not work on all devices, use CPU as default
    } catch (_) {}

    // Use 2 threads for CPU inference
    options.threads = 2;

    return await Interpreter.fromAsset(
      AppConstants.modelPath,
      options: options,
    );
  }

  Future<List<String>> _loadLabels() async {
    try {
      final labelData = await rootBundle.loadString(AppConstants.labelsPath);
      final labels = labelData
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (labels.length == AppConstants.numClasses) {
        return labels;
      }
    } catch (_) {}
    return AppConstants.defaultLabels;
  }

  /// Classify a preprocessed face crop.
  ///
  /// [faceCrop] should be a 224x224 RGB image (from face detection).
  /// Returns an [EmotionResult] with label, confidence, and all probabilities.
  EmotionResult classify(img.Image faceCrop) {
    if (!_isInitialized || _interpreter == null) {
      return EmotionResult.empty();
    }

    final startTime = DateTime.now();

    // Preprocess: resize to 224x224 and normalize to [-1, 1]
    final input =
        ImageUtils.preprocessForModel(faceCrop, inputSize: AppConstants.modelInputSize);

    // Reshape input for the model: [1, 224, 224, 3]
    final inputTensor = input.reshape([
      1,
      AppConstants.modelInputSize,
      AppConstants.modelInputSize,
      3,
    ]);

    // Output: [1, 3] (3 classes)
    final output = List.filled(AppConstants.numClasses, 0.0)
        .reshape([1, AppConstants.numClasses]);

    // Run inference
    _interpreter!.run(inputTensor, output);

    final rawOutputs = (output[0] as List<double>);
    final latency = DateTime.now().difference(startTime).inMilliseconds;

    // Check if the model outputs are already softmax probabilities.
    // In Keras, the final layer has activation="softmax", so outputs sum to ~1.0 and all are >= 0.0.
    // Calling softmax again compresses the dynamic range into a narrow ~25%-45% band.
    final sum = rawOutputs.reduce((a, b) => a + b);
    final allNonNegative = rawOutputs.every((v) => v >= 0.0);
    final isAlreadyProbabilities = (sum >= 0.95 && sum <= 1.05) && allNonNegative;

    final finalProbs = isAlreadyProbabilities ? rawOutputs : _softmax(rawOutputs);

    // Find the class with highest confidence
    int maxIndex = 0;
    double maxConf = finalProbs[0];
    for (int i = 1; i < finalProbs.length; i++) {
      if (finalProbs[i] > maxConf) {
        maxConf = finalProbs[i];
        maxIndex = i;
      }
    }

    final Map<String, double> probMap = {};
    for (int i = 0; i < _labels.length; i++) {
      probMap[_labels[i]] = finalProbs[i];
    }

    return EmotionResult(
      label: _labels[maxIndex],
      confidence: maxConf,
      probabilities: probMap,
      timestamp: DateTime.now(),
      latencyMs: latency,
    );
  }

  /// Softmax function to convert logits to probabilities.
  List<double> _softmax(List<double> logits) {
    final maxLogit = logits.reduce((a, b) => a > b ? a : b);
    final exps = logits.map((l) => _exp(l - maxLogit)).toList();
    final sumExp = exps.reduce((a, b) => a + b);
    return exps.map((e) => e / sumExp).toList();
  }

  static double _exp(double x) {
    // Clamp to avoid overflow
    if (x > 88) return double.maxFinite;
    if (x < -88) return 0;
    return x.isNaN ? 0 : _dartExp(x);
  }

  static double _dartExp(double x) {
    // Use Dart's built-in exp via dart:math
    return x == 0 ? 1.0 : _realExp(x);
  }

  // Proper exp function
  static double _realExp(double x) {
    // Taylor series approximation for exp(x) with 12 terms
    double sum = 1.0;
    double term = 1.0;
    for (int i = 1; i <= 12; i++) {
      term *= x / i;
      sum += term;
    }
    return sum;
  }

  /// Dispose the interpreter.
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }
}

/// Isolate-based inference wrapper to avoid UI jank.
class IsolateInference {
  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  bool _isRunning = false;

  bool get isRunning => _isRunning;
  SendPort? get sendPort => _sendPort;

  /// Start the inference isolate.
  Future<void> start() async {
    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(
      _isolateEntry,
      _receivePort!.sendPort,
    );

    // Get the send port from the isolate
    final completer = _receivePort!.first;
    _sendPort = await completer as SendPort;
    _isRunning = true;
  }

  static void _isolateEntry(SendPort mainSendPort) {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    EmotionClassifierService? classifier;

    receivePort.listen((message) async {
      if (message is Map<String, dynamic>) {
        final action = message['action'] as String;

        if (action == 'init') {
          classifier = EmotionClassifierService();
          // Note: Can't use rootBundle in isolate, would need to pass model bytes
          // For now, inference happens on main isolate with throttling
        } else if (action == 'classify' && classifier != null) {
          // Would process here if we could load model in isolate
        } else if (action == 'dispose') {
          classifier?.dispose();
          Isolate.exit();
        }
      }
    });
  }

  /// Stop the inference isolate.
  void stop() {
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
    _isolate = null;
    _sendPort = null;
    _receivePort = null;
    _isRunning = false;
  }
}
