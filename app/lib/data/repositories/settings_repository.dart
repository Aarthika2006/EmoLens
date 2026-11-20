import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';

/// Repository for persisting app settings using SharedPreferences.
class SettingsRepository {
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _preferences async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // --- Camera IP ---
  Future<String?> getCameraIp() async {
    final prefs = await _preferences;
    return prefs.getString(AppConstants.keyCameraIp);
  }

  Future<void> setCameraIp(String ip) async {
    final prefs = await _preferences;
    await prefs.setString(AppConstants.keyCameraIp, ip);
  }

  // --- HTTP Port ---
  Future<int> getHttpPort() async {
    final prefs = await _preferences;
    return prefs.getInt(AppConstants.keyHttpPort) ??
        AppConstants.defaultHttpPort;
  }

  Future<void> setHttpPort(int port) async {
    final prefs = await _preferences;
    await prefs.setInt(AppConstants.keyHttpPort, port);
  }

  // --- Stream Port ---
  Future<int> getStreamPort() async {
    final prefs = await _preferences;
    return prefs.getInt(AppConstants.keyStreamPort) ??
        AppConstants.defaultStreamPort;
  }

  Future<void> setStreamPort(int port) async {
    final prefs = await _preferences;
    await prefs.setInt(AppConstants.keyStreamPort, port);
  }

  // --- Stream Mode ---
  Future<StreamMode> getStreamMode() async {
    final prefs = await _preferences;
    final idx = prefs.getInt(AppConstants.keyStreamMode) ?? 0;
    return StreamMode.values[idx.clamp(0, StreamMode.values.length - 1)];
  }

  Future<void> setStreamMode(StreamMode mode) async {
    final prefs = await _preferences;
    await prefs.setInt(AppConstants.keyStreamMode, mode.index);
  }

  // --- Resolution ---
  Future<int> getResolution() async {
    final prefs = await _preferences;
    return prefs.getInt(AppConstants.keyResolution) ?? 8; // VGA default
  }

  Future<void> setResolution(int framesize) async {
    final prefs = await _preferences;
    await prefs.setInt(AppConstants.keyResolution, framesize);
  }

  // --- JPEG Quality ---
  Future<int> getJpegQuality() async {
    final prefs = await _preferences;
    return prefs.getInt(AppConstants.keyJpegQuality) ?? 10;
  }

  Future<void> setJpegQuality(int quality) async {
    final prefs = await _preferences;
    await prefs.setInt(AppConstants.keyJpegQuality, quality);
  }

  // --- LED Intensity ---
  Future<int> getLedIntensity() async {
    final prefs = await _preferences;
    return prefs.getInt(AppConstants.keyLedIntensity) ?? 0;
  }

  Future<void> setLedIntensity(int intensity) async {
    final prefs = await _preferences;
    await prefs.setInt(AppConstants.keyLedIntensity, intensity);
  }

  // --- Confidence Threshold ---
  Future<double> getConfidenceThreshold() async {
    final prefs = await _preferences;
    return prefs.getDouble(AppConstants.keyConfidenceThreshold) ??
        AppConstants.defaultConfidenceThreshold;
  }

  Future<void> setConfidenceThreshold(double threshold) async {
    final prefs = await _preferences;
    await prefs.setDouble(AppConstants.keyConfidenceThreshold, threshold);
  }

  // --- Smoothing Window ---
  Future<int> getSmoothingWindow() async {
    final prefs = await _preferences;
    return prefs.getInt(AppConstants.keySmoothingWindow) ??
        AppConstants.defaultSmoothingWindow;
  }

  Future<void> setSmoothingWindow(int window) async {
    final prefs = await _preferences;
    await prefs.setInt(AppConstants.keySmoothingWindow, window);
  }

  // --- Sad Alert ---
  Future<bool> getSadAlertEnabled() async {
    final prefs = await _preferences;
    return prefs.getBool(AppConstants.keySadAlert) ?? false;
  }

  Future<void> setSadAlertEnabled(bool enabled) async {
    final prefs = await _preferences;
    await prefs.setBool(AppConstants.keySadAlert, enabled);
  }

  // --- Onboarding ---
  Future<bool> isOnboardingComplete() async {
    final prefs = await _preferences;
    return prefs.getBool(AppConstants.keyOnboardingComplete) ?? false;
  }

  Future<void> setOnboardingComplete(bool complete) async {
    final prefs = await _preferences;
    await prefs.setBool(AppConstants.keyOnboardingComplete, complete);
  }

  /// Load all settings at once.
  Future<AppSettings> loadAll() async {
    return AppSettings(
      cameraIp: await getCameraIp(),
      httpPort: await getHttpPort(),
      streamPort: await getStreamPort(),
      streamMode: await getStreamMode(),
      resolution: await getResolution(),
      jpegQuality: await getJpegQuality(),
      ledIntensity: await getLedIntensity(),
      confidenceThreshold: await getConfidenceThreshold(),
      smoothingWindow: await getSmoothingWindow(),
      sadAlertEnabled: await getSadAlertEnabled(),
      onboardingComplete: await isOnboardingComplete(),
    );
  }
}

/// Immutable snapshot of all app settings.
class AppSettings {
  final String? cameraIp;
  final int httpPort;
  final int streamPort;
  final StreamMode streamMode;
  final int resolution;
  final int jpegQuality;
  final int ledIntensity;
  final double confidenceThreshold;
  final int smoothingWindow;
  final bool sadAlertEnabled;
  final bool onboardingComplete;

  const AppSettings({
    this.cameraIp,
    this.httpPort = AppConstants.defaultHttpPort,
    this.streamPort = AppConstants.defaultStreamPort,
    this.streamMode = StreamMode.mjpeg,
    this.resolution = 8,
    this.jpegQuality = 10,
    this.ledIntensity = 0,
    this.confidenceThreshold = AppConstants.defaultConfidenceThreshold,
    this.smoothingWindow = AppConstants.defaultSmoothingWindow,
    this.sadAlertEnabled = false,
    this.onboardingComplete = false,
  });

  bool get hasCameraIp => cameraIp != null && cameraIp!.isNotEmpty;

  AppSettings copyWith({
    String? cameraIp,
    int? httpPort,
    int? streamPort,
    StreamMode? streamMode,
    int? resolution,
    int? jpegQuality,
    int? ledIntensity,
    double? confidenceThreshold,
    int? smoothingWindow,
    bool? sadAlertEnabled,
    bool? onboardingComplete,
  }) {
    return AppSettings(
      cameraIp: cameraIp ?? this.cameraIp,
      httpPort: httpPort ?? this.httpPort,
      streamPort: streamPort ?? this.streamPort,
      streamMode: streamMode ?? this.streamMode,
      resolution: resolution ?? this.resolution,
      jpegQuality: jpegQuality ?? this.jpegQuality,
      ledIntensity: ledIntensity ?? this.ledIntensity,
      confidenceThreshold: confidenceThreshold ?? this.confidenceThreshold,
      smoothingWindow: smoothingWindow ?? this.smoothingWindow,
      sadAlertEnabled: sadAlertEnabled ?? this.sadAlertEnabled,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
    );
  }
}
