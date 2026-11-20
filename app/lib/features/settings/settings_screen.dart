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
  }

  @override
  void dispose() {
    _ipController.dispose();
    _httpPortController.dispose();
    _streamPortController.dispose();
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
  }

  Future<void> _saveConnectionSettings() async {
    if (!_formKey.currentState!.validate()) return;
    final notifier = ref.read(settingsProvider.notifier);
    await notifier.updateCameraIp(_ipController.text.trim());
    await notifier.updateHttpPort(int.parse(_httpPortController.text.trim()));
    await notifier.updateStreamPort(int.parse(_streamPortController.text.trim()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
    }
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isTesting = true;
      _testResult = null;
    });
    final ip = _ipController.text.trim();
    final port = int.tryParse(_httpPortController.text.trim()) ?? 80;
    try {
      final status = await _controlSvc.testConnection(ip, port: port);
      setState(() {
        _testSuccess = true;
        _testResult = 'Connected! Framesize: ${status.framesize}, Quality: ${status.quality}';
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
                _SectionHeader('Camera Connection'),
                // IP field
                TextFormField(
                  controller: _ipController,
                  decoration: const InputDecoration(
                    labelText: 'ESP32-CAM IP Address',
                    hintText: '192.168.1.100',
                    prefixIcon: Icon(Icons.router_rounded),
                  ),
                  keyboardType: TextInputType.number,
                  validator: Validators.validateIPv4,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _httpPortController,
                        decoration: const InputDecoration(labelText: 'HTTP Port'),
                        keyboardType: TextInputType.number,
                        validator: Validators.validatePort,
                      ),
                    ),
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
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _saveConnectionSettings,
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Save Connection Settings'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _isTesting ? null : _testConnection,
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
                const SizedBox(height: 16),
                _SectionHeader('Stream Settings'),
                // Stream mode
                _DropdownTile<StreamMode>(
                  label: 'Stream Mode',
                  value: settings.streamMode,
                  items: StreamMode.values,
                  itemLabel: (m) => m.displayName,
                  onChanged: (m) => ref.read(settingsProvider.notifier).updateStreamMode(m),
                ),
                const SizedBox(height: 12),
                // Resolution
                _DropdownTile<CameraResolution>(
                  label: 'Resolution',
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
                _SectionHeader('Camera Quality'),
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

