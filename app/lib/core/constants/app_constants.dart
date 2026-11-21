/// App-wide constants for EmoLens.
class AppConstants {
  AppConstants._();

  // App info
  static const String appName = 'EmoLens';
  static const String appVersion = '1.0.0';
  static const String modelVersion = '1.0.0';

  // Model config
  static const String modelPath = 'assets/models/emotion_model.tflite';
  static const String labelsPath = 'assets/models/labels.txt';
  static const int modelInputSize = 224;
  static const int numClasses = 3;
  static const List<String> defaultLabels = ['Happy', 'Neutral', 'Sad'];

  // ESP32-CAM defaults
  static const int defaultHttpPort = 80;
  static const int defaultStreamPort = 81;
  static const String mjpegBoundary = '123456789000000000000987654321';

  // Inference / streaming
  static const int inferenceThrottleMs = 250; // ms between inferences
  static const int capturePollingIntervalMs = 300; // ~3.3 fps
  static const double defaultConfidenceThreshold = 0.5;
  static const int defaultSmoothingWindow = 5;
  static const double emaAlpha = 0.3; // EMA smoothing factor

  // Reconnect
  static const int initialReconnectDelayMs = 1000;
  static const int maxReconnectDelayMs = 30000;
  static const double reconnectBackoffMultiplier = 2.0;

  // History
  static const int timelineWindowSeconds = 60;

  // Alert
  static const int sadAlertDurationSeconds = 10;

  // Face detection
  static const double faceCropMargin = 0.2; // 20% extra around face

  // Network scan
  static const String defaultSubnet = '192.168.1';
  static const int scanTimeoutMs = 500;

  // Settings keys (shared_preferences)
  static const String keyCameraIp = 'camera_ip';
  static const String keyCameraSourceType = 'camera_source_type';
  static const String keyHttpPort = 'http_port';
  static const String keyStreamPort = 'stream_port';
  static const String keyStreamPath = 'stream_path';
  static const String keyCapturePath = 'capture_path';

  // Default camera paths
  static const String defaultEsp32StreamPath = '/stream';
  static const String defaultEsp32CapturePath = '/capture';
  static const String defaultIpWebcamStreamPath = '/video';
  static const String defaultIpWebcamCapturePath = '/shot.jpg';
  static const String keyStreamMode = 'stream_mode';
  static const String keyResolution = 'resolution';
  static const String keyJpegQuality = 'jpeg_quality';
  static const String keyLedIntensity = 'led_intensity';
  static const String keyConfidenceThreshold = 'confidence_threshold';
  static const String keySmoothingWindow = 'smoothing_window';
  static const String keySadAlert = 'sad_alert_enabled';
  static const String keyOnboardingComplete = 'onboarding_complete';

  // Privacy
  static const String privacyStatement =
      'All processing is done on-device. No images leave your phone. '
      'EmoLens uses your local Wi-Fi network to connect to the ESP32-CAM '
      'and runs emotion recognition entirely on your device.';
}

/// Stream mode options.
enum StreamMode {
  mjpeg,
  capturePolling;

  String get displayName {
    switch (this) {
      case StreamMode.mjpeg:
        return 'MJPEG Stream';
      case StreamMode.capturePolling:
        return 'Capture Polling';
    }
  }
}

/// Camera resolution options (ESP32-CAM framesize values).
enum CameraResolution {
  qqvga(0, 'QQVGA (160x120)'),
  qvga(5, 'QVGA (320x240)'),
  cif(6, 'CIF (400x296)'),
  vga(8, 'VGA (640x480)'),
  svga(9, 'SVGA (800x600)'),
  xga(10, 'XGA (1024x768)'),
  sxga(12, 'SXGA (1280x1024)'),
  uxga(13, 'UXGA (1600x1200)');

  final int value;
  final String displayName;
  const CameraResolution(this.value, this.displayName);
}

/// Connection state for the camera.
enum ConnectionStatus {
  connected,
  connecting,
  offline;

  String get displayName {
    switch (this) {
      case ConnectionStatus.connected:
        return 'Connected';
      case ConnectionStatus.connecting:
        return 'Connecting…';
      case ConnectionStatus.offline:
        return 'Offline';
    }
  }

  String get icon {
    switch (this) {
      case ConnectionStatus.connected:
        return '✅';
      case ConnectionStatus.connecting:
        return '🔄';
      case ConnectionStatus.offline:
        return '❌';
    }
  }
}

/// Supported camera source types (ESP32-CAM hardware vs Mobile Phone IP Webcam).
enum CameraSourceType {
  esp32Cam,
  ipWebcam,
  custom;

  String get displayName {
    switch (this) {
      case CameraSourceType.esp32Cam:
        return 'ESP32-CAM';
      case CameraSourceType.ipWebcam:
        return 'Phone IP Webcam';
      case CameraSourceType.custom:
        return 'Custom Stream';
    }
  }

  String get subtitle {
    switch (this) {
      case CameraSourceType.esp32Cam:
        return 'ESP32 hardware module (ports 80 & 81, /stream)';
      case CameraSourceType.ipWebcam:
        return 'Android IP Webcam app / Phone camera (port 8080, /video)';
      case CameraSourceType.custom:
        return 'Direct MJPEG or Snapshot HTTP stream';
    }
  }

  int get defaultHttpPort {
    switch (this) {
      case CameraSourceType.esp32Cam:
        return 80;
      case CameraSourceType.ipWebcam:
      case CameraSourceType.custom:
        return 8080;
    }
  }

  int get defaultStreamPort {
    switch (this) {
      case CameraSourceType.esp32Cam:
        return 81;
      case CameraSourceType.ipWebcam:
      case CameraSourceType.custom:
        return 8080;
    }
  }

  String get defaultStreamPath {
    switch (this) {
      case CameraSourceType.esp32Cam:
        return '/stream';
      case CameraSourceType.ipWebcam:
      case CameraSourceType.custom:
        return '/video';
    }
  }

  String get defaultCapturePath {
    switch (this) {
      case CameraSourceType.esp32Cam:
        return '/capture';
      case CameraSourceType.ipWebcam:
      case CameraSourceType.custom:
        return '/shot.jpg';
    }
  }
}
