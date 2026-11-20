import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/camera_settings.dart';

/// Service for controlling ESP32-CAM via HTTP.
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

  /// Tests the connection to the ESP32-CAM.
  /// Returns the camera settings if successful, throws on failure.
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
