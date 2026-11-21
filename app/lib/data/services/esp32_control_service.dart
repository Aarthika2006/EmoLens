import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/constants/app_constants.dart';
import '../models/camera_settings.dart';

/// Service for controlling ESP32-CAM and testing IP cameras via HTTP.
///
/// Endpoints:
/// - GET /status (port 80) → JSON with camera settings
/// - GET /control?var=<name>&val=<value> (port 80) → set camera params
class Esp32ControlService {
  /// Fetches the current camera status/settings.
  Future<CameraSettings> getStatus(String ip, {int port = 80}) async {
    final uri = Uri.parse('http://$ip:$port/status');
    final response = await http.get(uri).timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) {
      throw Exception('Failed to get status: HTTP ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return CameraSettings.fromJson(json);
  }

  /// Tests the connection to the camera (supports both ESP32-CAM and Phone IP Webcam).
  Future<String> testCameraConnection(
    String ip, {
    int port = 80,
    CameraSourceType type = CameraSourceType.esp32Cam,
  }) async {
    if (type == CameraSourceType.esp32Cam) {
      try {
        final settings = await getStatus(ip, port: port);
        return 'ESP32-CAM connected! (Settings OK)';
      } catch (e) {
        // Fallback: check if /capture responds
        try {
          final resp = await http
              .get(Uri.parse('http://$ip:$port/capture'))
              .timeout(const Duration(seconds: 4));
          if (resp.statusCode == 200) {
            return 'ESP32-CAM connected! (Capture endpoint responding)';
          }
        } catch (_) {}
        throw Exception('Could not connect to ESP32-CAM at http://$ip:$port');
      }
    } else {
      // Probing Phone IP Webcam endpoints: /shot.jpg, /video, /
      for (final path in ['/shot.jpg', '/video', '/']) {
        try {
          final resp = await http
              .get(Uri.parse('http://$ip:$port$path'))
              .timeout(const Duration(seconds: 4));
          if (resp.statusCode == 200) {
            return 'Mobile IP Webcam connected! ($path active)';
          }
        } catch (_) {}
      }
      throw Exception(
        'Could not connect to Phone IP Webcam at http://$ip:$port. '
        'Ensure the IP Webcam app is running on the other phone and Wi-Fi is connected.',
      );
    }
  }

  /// Tests the connection to the ESP32-CAM (backward-compatible).
  Future<CameraSettings> testConnection(String ip, {int port = 80}) async {
    return await getStatus(ip, port: port);
  }

  /// Sets a camera control parameter.
  Future<bool> setControl(
    String ip, {
    required String variable,
    required int value,
    int port = 80,
  }) async {
    final uri = Uri.parse(
        'http://$ip:$port/control?var=$variable&val=$value');
    final response = await http.get(uri).timeout(const Duration(seconds: 5));
    return response.statusCode == 200;
  }

  /// Set frame size (resolution).
  Future<bool> setFrameSize(String ip, int value, {int port = 80}) =>
      setControl(ip, variable: 'framesize', value: value, port: port);

  /// Set JPEG quality (0-63, lower = better quality).
  Future<bool> setQuality(String ip, int value, {int port = 80}) =>
      setControl(ip, variable: 'quality', value: value, port: port);

  /// Set brightness (-2 to 2).
  Future<bool> setBrightness(String ip, int value, {int port = 80}) =>
      setControl(ip, variable: 'brightness', value: value, port: port);

  /// Set contrast (-2 to 2).
  Future<bool> setContrast(String ip, int value, {int port = 80}) =>
      setControl(ip, variable: 'contrast', value: value, port: port);

  /// Set LED flash intensity (0-255).
  Future<bool> setLedIntensity(String ip, int value, {int port = 80}) =>
      setControl(ip, variable: 'led_intensity', value: value, port: port);

  /// Scans a subnet for ESP32-CAM devices by probing /status.
  ///
  /// Scans 192.168.[subnet].1 through 192.168.[subnet].254.
  Stream<String> scanSubnet(String subnet, {int port = 80, int timeoutMs = 500}) async* {
    final futures = <Future<String?>>[];

    for (int i = 1; i <= 254; i++) {
      final ip = '$subnet.$i';
      futures.add(_probeDevice(ip, port: port, timeoutMs: timeoutMs));
    }

    final results = await Future.wait(futures);
    for (final ip in results) {
      if (ip != null) yield ip;
    }
  }

  Future<String?> _probeDevice(String ip,
      {int port = 80, int timeoutMs = 500}) async {
    try {
      final uri = Uri.parse('http://$ip:$port/status');
      final response = await http
          .get(uri)
          .timeout(Duration(milliseconds: timeoutMs));
      if (response.statusCode == 200) {
        // Verify it looks like ESP32-CAM JSON
        final body = jsonDecode(response.body);
        if (body is Map && body.containsKey('framesize')) {
          return ip;
        }
      }
    } catch (_) {}
    return null;
  }
}
