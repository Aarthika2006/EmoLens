import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/settings_provider.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/services/esp32_control_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/validators.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _ipController;
  late TextEditingController _httpPortController;
  late TextEditingController _streamPortController;
  late TextEditingController _streamPathController;
  late TextEditingController _capturePathController;

  bool _isTesting = false;
  bool _isScanning = false;
  String? _testResult;
  bool _testSuccess = false;
  List<String> _foundDevices = [];

  final _controlSvc = Esp32ControlService();

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController();
    _httpPortController = TextEditingController(text: '80');
    _streamPortController = TextEditingController(text: '81');
    _streamPathController = TextEditingController(text: AppConstants.defaultEsp32StreamPath);
    _capturePathController = TextEditingController(text: AppConstants.defaultEsp32CapturePath);
  }

  @override
  void dispose() {
    _ipController.dispose();
    _httpPortController.dispose();
    _streamPortController.dispose();
    _streamPathController.dispose();
    _capturePathController.dispose();
    super.dispose();
  }

  void _populateControllers(AppSettings settings) {
    if (_ipController.text.isEmpty && settings.cameraIp != null) {
      _ipController.text = settings.cameraIp!;
    }
    if (_httpPortController.text == '80' && settings.httpPort != 80) {
      _httpPortController.text = settings.httpPort.toString();
    }
    if (_streamPortController.text == '81' && settings.streamPort != 81) {
      _streamPortController.text = settings.streamPort.toString();
    }
    if (_streamPathController.text == AppConstants.defaultEsp32StreamPath &&
        settings.streamPath != AppConstants.defaultEsp32StreamPath) {
      _streamPathController.text = settings.streamPath;
    }
    if (_capturePathController.text == AppConstants.defaultEsp32CapturePath &&
        settings.capturePath != AppConstants.defaultEsp32CapturePath) {
      _capturePathController.text = settings.capturePath;
    }
  }

  void _onIpChanged(String value) {
    // Auto-parser: if user pastes full URL like http://192.168.1.50:8080/video
    var text = value.trim();
    if (text.startsWith('http://') || text.startsWith('https://')) {
      final parsed = Uri.tryParse(text);
      if (parsed != null && parsed.host.isNotEmpty) {
        _ipController.text = parsed.host;
        if (parsed.hasPort) {
          _httpPortController.text = parsed.port.toString();
          _streamPortController.text = parsed.port.toString();
        }
        if (parsed.path.isNotEmpty && parsed.path != '/') {
          _streamPathController.text = parsed.path;
        }
        if (parsed.path.contains('video') || parsed.port == 8080) {
          ref.read(settingsProvider.notifier).updateCameraSourceType(CameraSourceType.ipWebcam);
        } else if (parsed.path.contains('stream') || parsed.port == 81 || parsed.port == 80) {
          ref.read(settingsProvider.notifier).updateCameraSourceType(CameraSourceType.esp32Cam);
        }
      }
    } else if (text.contains(':')) {
      final parts = text.split(':');
      if (parts.length == 2 && int.tryParse(parts[1]) != null) {
        _ipController.text = parts[0];
        _httpPortController.text = parts[1];
        _streamPortController.text = parts[1];
        if (int.tryParse(parts[1]) == 8080) {
          ref.read(settingsProvider.notifier).updateCameraSourceType(CameraSourceType.ipWebcam);
        }
      }
    }
  }

  Future<void> _saveConnectionSettings() async {
    if (!_formKey.currentState!.validate()) return;
    final notifier = ref.read(settingsProvider.notifier);
    await notifier.updateCameraIp(_ipController.text.trim());
    await notifier.updateHttpPort(int.parse(_httpPortController.text.trim()));
    await notifier.updateStreamPort(int.parse(_streamPortController.text.trim()));
    await notifier.updateStreamPath(_streamPathController.text.trim());
    await notifier.updateCapturePath(_capturePathController.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved successfully')),
      );
    }
  }

  Future<void> _testConnection(AppSettings settings) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isTesting = true;
      _testResult = null;
    });
    final ip = _ipController.text.trim();
    final port = int.tryParse(_httpPortController.text.trim()) ??
        (settings.isIpWebcam ? 8080 : 80);
    try {
      final msg = await _controlSvc.testCameraConnection(
        ip,
        port: port,
        type: settings.cameraSourceType,
      );
      setState(() {
        _testSuccess = true;
        _testResult = msg;
      });
    } catch (e) {
      setState(() {
        _testSuccess = false;
        _testResult = 'Failed: ${e.toString().replaceAll('Exception: ', '')}';
      });
    } finally {
      setState(() => _isTesting = false);
    }
  }

  Future<void> _scanNetwork() async {
    setState(() {
      _isScanning = true;
      _foundDevices = [];
    });
    final subnet = AppConstants.defaultSubnet;
    await for (final ip in _controlSvc.scanSubnet(subnet)) {
      if (mounted) {
        setState(() => _foundDevices.add(ip));
      }
    }
    if (mounted) setState(() => _isScanning = false);
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (settings) {
          _populateControllers(settings);
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SectionHeader('Camera Source'),
                SegmentedButton<CameraSourceType>(
                  segments: const [
                    ButtonSegment<CameraSourceType>(
                      value: CameraSourceType.esp32Cam,
                      label: Text('ESP32-CAM'),
                      icon: Icon(Icons.memory_rounded),
                    ),
                    ButtonSegment<CameraSourceType>(
                      value: CameraSourceType.ipWebcam,
                      label: Text('Phone IP Cam'),
                      icon: Icon(Icons.phone_android_rounded),
                    ),
                    ButtonSegment<CameraSourceType>(
                      value: CameraSourceType.custom,
                      label: Text('Custom'),
                      icon: Icon(Icons.tune_rounded),
                    ),
                  ],
                  selected: {settings.cameraSourceType},
                  onSelectionChanged: (newSelection) async {
                    final selectedType = newSelection.first;
                    final notifier = ref.read(settingsProvider.notifier);
                    await notifier.updateCameraSourceType(selectedType);

                    if (selectedType == CameraSourceType.ipWebcam) {
                      _httpPortController.text = '8080';
                      _streamPortController.text = '8080';
                      _streamPathController.text = AppConstants.defaultIpWebcamStreamPath;
                      _capturePathController.text = AppConstants.defaultIpWebcamCapturePath;
                      await notifier.updateHttpPort(8080);
                      await notifier.updateStreamPort(8080);
                      await notifier.updateStreamPath(AppConstants.defaultIpWebcamStreamPath);
                      await notifier.updateCapturePath(AppConstants.defaultIpWebcamCapturePath);
                    } else if (selectedType == CameraSourceType.esp32Cam) {
                      _httpPortController.text = '80';
                      _streamPortController.text = '81';
                      _streamPathController.text = AppConstants.defaultEsp32StreamPath;
                      _capturePathController.text = AppConstants.defaultEsp32CapturePath;
                      await notifier.updateHttpPort(80);
                      await notifier.updateStreamPort(81);
                      await notifier.updateStreamPath(AppConstants.defaultEsp32StreamPath);
                      await notifier.updateCapturePath(AppConstants.defaultEsp32CapturePath);
                    }
                  },
                ),
                if (settings.isIpWebcam) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary.withOpacity(0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Row(
                          children: [
                            Icon(Icons.phone_android_rounded, color: AppColors.primary, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'How to use another Phone as Camera:',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text(
                          '1. Install free "IP Webcam" app (by Pavel Khlebovich) on any phone from Play Store.\n'
                          '2. Connect both phones to the same Wi-Fi network or Mobile Hotspot.\n'
                          '3. Open IP Webcam on that phone, scroll to bottom and tap "Start server".\n'
                          '4. Enter the IP shown on that phone screen below (e.g. 192.168.1.50).',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (settings.isEsp32) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.wifi_rounded, color: AppColors.textSecondary, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Ensure your ESP32-CAM module and this phone are on the same Wi-Fi network.',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _SectionHeader('Connection Details'),
                // IP field
                TextFormField(
                  controller: _ipController,
                  decoration: InputDecoration(
                    labelText: settings.isIpWebcam
                        ? 'Phone IP Webcam Address'
                        : (settings.isEsp32 ? 'ESP32-CAM IP Address' : 'Camera IP Address'),
                    hintText: settings.isIpWebcam ? '192.168.1.50' : '192.168.1.100',
                    prefixIcon: Icon(
                      settings.isIpWebcam ? Icons.phone_android_rounded : Icons.router_rounded,
                    ),
                    helperText: 'Enter IP or paste full URL (e.g. http://192.168.1.50:8080)',
                  ),
                  keyboardType: TextInputType.text,
                  onChanged: _onIpChanged,
                  validator: Validators.validateIPv4,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _httpPortController,
                        decoration: InputDecoration(
                          labelText: settings.isIpWebcam ? 'Webcam Port' : 'HTTP Port',
                        ),
                        keyboardType: TextInputType.number,
                        validator: Validators.validatePort,
                      ),
                    ),
                    if (!settings.isIpWebcam) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _streamPortController,
                          decoration: const InputDecoration(labelText: 'Stream Port'),
                          keyboardType: TextInputType.number,
                          validator: Validators.validatePort,
                        ),
                      ),
                    ],
                  ],
                ),
                if (settings.cameraSourceType == CameraSourceType.custom) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _streamPathController,
                          decoration: const InputDecoration(
                            labelText: 'Stream Path',
                            hintText: '/stream or /video',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _capturePathController,
                          decoration: const InputDecoration(
                            labelText: 'Capture Path',
                            hintText: '/capture or /shot.jpg',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _saveConnectionSettings,
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Save Connection Settings'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _isTesting ? null : () => _testConnection(settings),
                  icon: _isTesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_find_rounded),
                  label: Text(_isTesting ? 'Testing…' : 'Test Connection'),
                ),
                if (_testResult != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (_testSuccess ? AppColors.happy : AppColors.error)
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _testSuccess ? AppColors.happy : AppColors.error,
                      ),
                    ),
                    child: Text(
                      _testResult!,
                      style: TextStyle(
                        color: _testSuccess ? AppColors.happy : AppColors.error,
                      ),
                    ),
                  ),
                ],
                if (settings.isEsp32) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _isScanning ? null : _scanNetwork,
                    icon: _isScanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search_rounded),
                    label: Text(_isScanning
                        ? 'Scanning ${AppConstants.defaultSubnet}.x…'
                        : 'Find Camera on Network'),
                  ),
                  if (_foundDevices.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...(_foundDevices.map((ip) => ListTile(
                          title: Text(ip),
                          subtitle: const Text('ESP32-CAM found'),
                          trailing: TextButton(
                            onPressed: () => setState(() => _ipController.text = ip),
                            child: const Text('Use'),
                          ),
                        ))),
                  ],
                ],
                const SizedBox(height: 16),
                _SectionHeader('Stream Settings'),
                _DropdownTile<StreamMode>(
                  label: 'Stream Mode',
                  value: settings.streamMode,
                  items: StreamMode.values,
                  itemLabel: (m) => m.displayName,
                  onChanged: (m) => ref.read(settingsProvider.notifier).updateStreamMode(m),
                ),
                if (settings.isEsp32) ...[
                  const SizedBox(height: 12),
                  _DropdownTile<CameraResolution>(
                    label: 'Resolution (ESP32-CAM)',
                    value: CameraResolution.values.firstWhere(
                      (r) => r.value == settings.resolution,
                      orElse: () => CameraResolution.vga,
                    ),
                    items: CameraResolution.values,
                    itemLabel: (r) => r.displayName,
                    onChanged: (r) {
                      ref.read(settingsProvider.notifier).updateResolution(r.value);
                    },
                  ),
                  const SizedBox(height: 16),
                  _SectionHeader('Camera Quality (ESP32-CAM)'),
                  _SliderTile(
                    label: 'JPEG Quality',
                    value: settings.jpegQuality.toDouble(),
                    min: 4,
                    max: 63,
                    divisions: 59,
                    format: (v) => v.round().toString(),
                    onChanged: (v) =>
                        ref.read(settingsProvider.notifier).updateJpegQuality(v.round()),
                  ),
                  _SliderTile(
                    label: 'LED Flash Intensity',
                    value: settings.ledIntensity.toDouble(),
                    min: 0,
                    max: 255,
                    divisions: 255,
                    format: (v) => v.round().toString(),
                    onChanged: (v) =>
                        ref.read(settingsProvider.notifier).updateLedIntensity(v.round()),
                  ),
                ],
                const SizedBox(height: 16),
                _SectionHeader('Inference Settings'),
                _SliderTile(
                  label: 'Confidence Threshold',
                  value: settings.confidenceThreshold,
                  min: 0.3,
                  max: 0.95,
                  divisions: 65,
                  format: (v) => '${(v * 100).round()}%',
                  onChanged: (v) =>
                      ref.read(settingsProvider.notifier).updateConfidenceThreshold(v),
                ),
                _SliderTile(
                  label: 'Smoothing Window',
                  value: settings.smoothingWindow.toDouble(),
                  min: 3,
                  max: 15,
                  divisions: 12,
                  format: (v) => '${v.round()} frames',
                  onChanged: (v) =>
                      ref.read(settingsProvider.notifier).updateSmoothingWindow(v.round()),
                ),
                _SwitchTile(
                  label: 'Alert on Sustained Sadness',
                  subtitle: 'Vibrate if Sad detected for >10 seconds',
                  value: settings.sadAlertEnabled,
                  onChanged: (v) =>
                      ref.read(settingsProvider.notifier).updateSadAlert(v),
                ),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  const _SliderTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textPrimary)),
            Text(format(value),
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(label, style: const TextStyle(color: AppColors.textPrimary)),
      subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textSecondary)),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
    );
  }
}

class _DropdownTile<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T> onChanged;

  const _DropdownTile({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      decoration: InputDecoration(labelText: label),
      dropdownColor: AppColors.surface,
      items: items
          .map((item) => DropdownMenuItem<T>(
                value: item,
                child: Text(itemLabel(item)),
              ))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
