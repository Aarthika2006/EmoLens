import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repositories/settings_repository.dart';
import '../core/constants/app_constants.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository();
});

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final repo = ref.read(settingsRepositoryProvider);
    return repo.loadAll();
  }

  Future<void> updateCameraIp(String ip) async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.setCameraIp(ip);
    state = AsyncData(state.value!.copyWith(cameraIp: ip));
  }

  Future<void> updateHttpPort(int port) async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.setHttpPort(port);
    state = AsyncData(state.value!.copyWith(httpPort: port));
  }

  Future<void> updateStreamPort(int port) async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.setStreamPort(port);
    state = AsyncData(state.value!.copyWith(streamPort: port));
  }

  Future<void> updateStreamMode(StreamMode mode) async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.setStreamMode(mode);
    state = AsyncData(state.value!.copyWith(streamMode: mode));
  }

  Future<void> updateResolution(int framesize) async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.setResolution(framesize);
    state = AsyncData(state.value!.copyWith(resolution: framesize));
  }

  Future<void> updateJpegQuality(int quality) async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.setJpegQuality(quality);
    state = AsyncData(state.value!.copyWith(jpegQuality: quality));
  }

  Future<void> updateLedIntensity(int intensity) async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.setLedIntensity(intensity);
    state = AsyncData(state.value!.copyWith(ledIntensity: intensity));
  }

  Future<void> updateConfidenceThreshold(double threshold) async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.setConfidenceThreshold(threshold);
    state = AsyncData(state.value!.copyWith(confidenceThreshold: threshold));
  }

  Future<void> updateSmoothingWindow(int window) async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.setSmoothingWindow(window);
    state = AsyncData(state.value!.copyWith(smoothingWindow: window));
  }

  Future<void> updateSadAlert(bool enabled) async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.setSadAlertEnabled(enabled);
    state = AsyncData(state.value!.copyWith(sadAlertEnabled: enabled));
  }

  Future<void> markOnboardingComplete() async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.setOnboardingComplete(true);
    state = AsyncData(state.value!.copyWith(onboardingComplete: true));
  }
}

