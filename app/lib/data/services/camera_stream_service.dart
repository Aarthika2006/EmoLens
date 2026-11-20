import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../../core/constants/app_constants.dart';

/// Service for connecting to ESP32-CAM and receiving frames.
///
/// Supports two modes:
/// 1. MJPEG stream parsing (multipart/x-mixed-replace)
/// 2. Capture polling fallback (GET /capture at ~3-5 fps)
class CameraStreamService {
  http.Client? _client;
  StreamSubscription? _streamSubscription;
  Timer? _pollingTimer;

  bool _isStreaming = false;
  bool get isStreaming => _isStreaming;

  // Reconnection state
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  // FPS / latency tracking
  final List<DateTime> _frameTimes = [];
  DateTime? _lastFrameTime;
  double _currentFps = 0;
  double get currentFps => _currentFps;

  int _latencyMs = 0;
  int get latencyMs => _latencyMs;

  /// Stream of JPEG frame bytes.
  final _frameController = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get frameStream => _frameController.stream;

  /// Stream of connection status changes.
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  Stream<ConnectionStatus> get statusStream => _statusController.stream;

  /// Start streaming from the ESP32-CAM.
  Future<void> startStream({
    required String ip,
    int httpPort = AppConstants.defaultHttpPort,
    int streamPort = AppConstants.defaultStreamPort,
    StreamMode mode = StreamMode.mjpeg,
  }) async {
    await stopStream();
    _isStreaming = true;
    _reconnectAttempts = 0;
    _statusController.add(ConnectionStatus.connecting);

    if (mode == StreamMode.mjpeg) {
      await _startMjpegStream(ip, streamPort);
    } else {
      _startCapturePolling(ip, httpPort);
    }
  }

  /// Start MJPEG stream parsing.
  Future<void> _startMjpegStream(String ip, int port) async {
    try {
      _client = http.Client();
      final uri = Uri.parse('http://$ip:$port/stream');
      final request = http.Request('GET', uri);
      final response = await _client!.send(request).timeout(
            const Duration(seconds: 10),
          );

      if (response.statusCode != 200) {
        _handleStreamError('HTTP ${response.statusCode}');
        return;
      }

      _statusController.add(ConnectionStatus.connected);
      _reconnectAttempts = 0;

      // Parse MJPEG stream
      _streamSubscription = response.stream
          .transform(MjpegStreamTransformer())
          .listen(
        (frameBytes) {
          _updateFps();
          _frameController.add(frameBytes);
        },
        onError: (error) {
          _handleStreamError(error.toString());
        },
        onDone: () {
          if (_isStreaming) {
            _handleStreamError('Stream ended');
          }
        },
        cancelOnError: false,
      );
    } catch (e) {
      _handleStreamError(e.toString());
    }
  }

  /// Start capture polling fallback.
  void _startCapturePolling(String ip, int port) {
    _statusController.add(ConnectionStatus.connected);

    _pollingTimer = Timer.periodic(
      const Duration(milliseconds: AppConstants.capturePollingIntervalMs),
      (_) => _fetchSingleFrame(ip, port),
    );

    // Fetch first frame immediately
    _fetchSingleFrame(ip, port);
  }

  Future<void> _fetchSingleFrame(String ip, int port) async {
    try {
      final startTime = DateTime.now();
      final response = await http
          .get(Uri.parse('http://$ip:$port/capture'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        _latencyMs =
            DateTime.now().difference(startTime).inMilliseconds;
        _updateFps();
        _statusController.add(ConnectionStatus.connected);
        _reconnectAttempts = 0;
        _frameController.add(response.bodyBytes);
      }
    } catch (e) {
      _statusController.add(ConnectionStatus.offline);
    }
  }

  void _updateFps() {
    final now = DateTime.now();
    if (_lastFrameTime != null) {
      _latencyMs = now.difference(_lastFrameTime!).inMilliseconds;
    }
    _lastFrameTime = now;

    _frameTimes.add(now);
    // Keep only last 2 seconds of frame times
    _frameTimes.removeWhere(
      (t) => now.difference(t).inMilliseconds > 2000,
    );
    if (_frameTimes.length > 1) {
      final span =
          _frameTimes.last.difference(_frameTimes.first).inMilliseconds;
      if (span > 0) {
        _currentFps = (_frameTimes.length - 1) * 1000.0 / span;
      }
    }
  }

  void _handleStreamError(String error) {
    _statusController.add(ConnectionStatus.offline);
    _cleanupCurrentStream();

    if (!_isStreaming) return;

    // Exponential backoff reconnect
    final delay = _calculateReconnectDelay();
    _reconnectAttempts++;

    _reconnectTimer = Timer(Duration(milliseconds: delay), () {
      if (_isStreaming) {
        _statusController.add(ConnectionStatus.connecting);
        // The caller should handle reconnection by calling startStream again
        // For now, we emit offline and let the provider handle retry
      }
    });
  }

  int _calculateReconnectDelay() {
    final delay = (AppConstants.initialReconnectDelayMs *
            _pow(AppConstants.reconnectBackoffMultiplier, _reconnectAttempts))
        .round();
    return delay.clamp(
      AppConstants.initialReconnectDelayMs,
      AppConstants.maxReconnectDelayMs,
    );
  }

  static double _pow(double base, int exp) {
    double result = 1;
    for (var i = 0; i < exp; i++) {
      result *= base;
    }
    return result;
  }

  /// Stop streaming and clean up resources.
  Future<void> stopStream() async {
    _isStreaming = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _cleanupCurrentStream();
    _statusController.add(ConnectionStatus.offline);
    _currentFps = 0;
    _latencyMs = 0;
    _frameTimes.clear();
    _lastFrameTime = null;
    _reconnectAttempts = 0;
  }

  void _cleanupCurrentStream() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _client?.close();
    _client = null;
  }

  /// Dispose all resources.
  void dispose() {
    stopStream();
    _frameController.close();
    _statusController.close();
  }
}

/// StreamTransformer that parses an MJPEG multipart stream into individual
/// JPEG frames.
///
/// Parses `multipart/x-mixed-replace` with boundary
/// `123456789000000000000987654321`.
class MjpegStreamTransformer
    extends StreamTransformerBase<List<int>, Uint8List> {
  @override
  Stream<Uint8List> bind(Stream<List<int>> stream) {
    return Stream.eventTransformed(stream, (sink) => _MjpegSink(sink));
  }
}

class _MjpegSink implements EventSink<List<int>> {
  final EventSink<Uint8List> _outputSink;
  final _buffer = BytesBuilder(copy: false);
  bool _headerParsed = false;

  // JPEG markers
  static const int _jpegStart1 = 0xFF;
  static const int _jpegStart2 = 0xD8;
  static const int _jpegEnd1 = 0xFF;
  static const int _jpegEnd2 = 0xD9;

  _MjpegSink(this._outputSink);

  @override
  void add(List<int> data) {
    _buffer.add(data);
    _processBuffer();
  }

  void _processBuffer() {
    final bytes = _buffer.toBytes();
    _buffer.clear();

    int offset = 0;

    while (offset < bytes.length - 1) {
      // Look for JPEG start marker (0xFF 0xD8)
      if (!_headerParsed) {
        final jpegStart = _findJpegStart(bytes, offset);
        if (jpegStart == -1) {
          // Keep the last byte in case it's 0xFF
          if (bytes.length > 0) {
            _buffer.add([bytes.last]);
          }
          return;
        }
        _headerParsed = true;
        offset = jpegStart;
      }

      // Look for JPEG end marker (0xFF 0xD9)
      final jpegEnd = _findJpegEnd(bytes, offset + 2);
      if (jpegEnd == -1) {
        // Incomplete frame, keep remaining bytes
        _buffer.add(bytes.sublist(offset));
        return;
      }

      // Extract complete JPEG frame
      final frameEnd = jpegEnd + 2;
      final frame = Uint8List.fromList(bytes.sublist(offset, frameEnd));
      _outputSink.add(frame);

      _headerParsed = false;
      offset = frameEnd;
    }

    // Keep remaining bytes
    if (offset < bytes.length) {
      _buffer.add(bytes.sublist(offset));
    }
  }

  int _findJpegStart(Uint8List bytes, int from) {
    for (int i = from; i < bytes.length - 1; i++) {
      if (bytes[i] == _jpegStart1 && bytes[i + 1] == _jpegStart2) {
        return i;
      }
    }
    return -1;
  }

  int _findJpegEnd(Uint8List bytes, int from) {
    for (int i = from; i < bytes.length - 1; i++) {
      if (bytes[i] == _jpegEnd1 && bytes[i + 1] == _jpegEnd2) {
        return i;
      }
    }
    return -1;
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _outputSink.addError(error, stackTrace);
  }

  @override
  void close() {
    _buffer.clear();
    _outputSink.close();
  }
}
