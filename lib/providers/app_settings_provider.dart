import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import '../models/app_setting.dart';
import '../models/app_settings.dart';
import '../services/settings_service.dart';

final settingsServiceProvider = Provider<SettingsService>((ref) {
  return SettingsService();
});

final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);

class AppSettingsNotifier extends AsyncNotifier<AppSettings> {
  SettingsService get _settingsService => ref.read(settingsServiceProvider);

  @override
  Future<AppSettings> build() async {
    final storedSettings = await _settingsService.getAllSettings();
    final settingsMap = {
      for (final setting in storedSettings) setting.key: setting.value,
    };
    return AppSettings.fromStorage(settingsMap);
  }

  AppSettings get _currentSettings =>
      state.asData?.value ?? AppSettings.defaults();

  Future<void> updateProfile({
    required String displayName,
    required String organization,
    required String note,
  }) async {
    final nextSettings = _currentSettings.copyWith(
      profile: _currentSettings.profile.copyWith(
        displayName: displayName,
        organization: organization,
        note: note,
      ),
    );
    await _persist(nextSettings);
  }

  Future<void> updatePreferredWhisperModel(WhisperModel model) async {
    final nextSettings = _currentSettings.copyWith(
      preferredWhisperModel: model,
    );
    await _persist(nextSettings);
  }

  Future<void> addLectureLabel(String label) async {
    final nextSettings = _currentSettings.copyWith(
      lectureLabels: [..._currentSettings.lectureLabels, label],
    );
    await _persist(nextSettings);
  }

  Future<void> removeLectureLabel(String label) async {
    final nextSettings = _currentSettings.copyWith(
      lectureLabels: _currentSettings.lectureLabels
          .where((item) => item != label)
          .toList(growable: false),
    );
    await _persist(nextSettings);
  }

  Future<void> addTimelineLabel(String label) async {
    final nextSettings = _currentSettings.copyWith(
      timelineLabels: [..._currentSettings.timelineLabels, label],
    );
    await _persist(nextSettings);
  }

  Future<void> removeTimelineLabel(String label) async {
    final nextSettings = _currentSettings.copyWith(
      timelineLabels: _currentSettings.timelineLabels
          .where((item) => item != label)
          .toList(growable: false),
    );
    await _persist(nextSettings);
  }

  Future<void> updateBackgroundStyle(AppBackgroundStyle style) async {
    final nextSettings = _currentSettings.copyWith(backgroundStyle: style);
    await _persist(nextSettings);
  }

  Future<void> resetToDefaults() async {
    await _persist(AppSettings.defaults());
  }

  Future<void> _persist(AppSettings nextSettings) async {
    final previousSettings = _currentSettings;
    state = AsyncData(nextSettings);

    try {
      final persistedValues = nextSettings.toStorageMap();
      final keysToSync = [
        AppSettingsKeys.profileDisplayName,
        AppSettingsKeys.profileOrganization,
        AppSettingsKeys.profileNote,
        AppSettingsKeys.preferredWhisperModel,
        AppSettingsKeys.lectureLabels,
        AppSettingsKeys.timelineLabels,
        AppSettingsKeys.backgroundStyle,
      ];

      for (final key in keysToSync) {
        final value = persistedValues[key]?.trim();
        if (value == null || value.isEmpty) {
          await _settingsService.deleteSetting(key);
          continue;
        }

        await _settingsService.saveSetting(AppSetting(key: key, value: value));
      }
    } catch (error, stackTrace) {
      state = AsyncData(previousSettings);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
