import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

enum AppBackgroundStyle {
  darkDefault,
  white,
}

enum AppSummaryMethod {
  extractive,
  androidLocalLlm,
}

extension AppBackgroundStyleX on AppBackgroundStyle {
  String get storageValue => name;

  String get label {
    switch (this) {
      case AppBackgroundStyle.darkDefault:
        return '預設背景';
      case AppBackgroundStyle.white:
        return '白色背景';
    }
  }

  String get description {
    switch (this) {
      case AppBackgroundStyle.darkDefault:
        return '原本預設深色背景。';
      case AppBackgroundStyle.white:
        return '真正的純白背景。';
    }
  }

  static AppBackgroundStyle fromStorage(String? raw) {
    if (raw == 'black' ||
        raw == 'darkDefault' ||
        raw == 'aurora' ||
        raw == 'blueprint') {
      return AppBackgroundStyle.darkDefault;
    }
    for (final style in AppBackgroundStyle.values) {
      if (style.storageValue == raw) {
        return style;
      }
    }
    return AppBackgroundStyle.darkDefault;
  }
}

extension AppSummaryMethodX on AppSummaryMethod {
  String get storageValue => name;

  String get label {
    switch (this) {
      case AppSummaryMethod.extractive:
        return 'Extractive 摘要';
      case AppSummaryMethod.androidLocalLlm:
        return 'Android 本機 LLM';
    }
  }

  String get badgeLabel {
    switch (this) {
      case AppSummaryMethod.extractive:
        return 'CURRENT DEFAULT';
      case AppSummaryMethod.androidLocalLlm:
        return 'ANDROID-FIRST';
    }
  }

  String get description {
    switch (this) {
      case AppSummaryMethod.extractive:
        return '沿用目前的 extractive 摘要流程，直到後續執行期整合完成前都維持這條路徑。';
      case AppSummaryMethod.androidLocalLlm:
        return '先儲存 Android 優先走本機 LLM 的偏好；執行期接上後會由這個設定決定摘要策略。';
    }
  }

  static AppSummaryMethod fromStorage(String? raw) {
    if (raw == 'localLlm' || raw == 'androidLocal') {
      return AppSummaryMethod.androidLocalLlm;
    }
    for (final method in AppSummaryMethod.values) {
      if (method.storageValue == raw) {
        return method;
      }
    }
    return AppSettings.defaultSummaryMethod;
  }
}

extension WhisperModelSettingsX on WhisperModel {
  String get storageValue => name;

  static WhisperModel fromStorage(String? raw) {
    for (final model in AppSettings.availableWhisperModels) {
      if (model.name == raw) {
        return model;
      }
    }
    return AppSettings.defaultWhisperModel;
  }
}

class AppProfileSettings {
  const AppProfileSettings({
    this.displayName = '',
    this.organization = '',
    this.note = '',
  });

  final String displayName;
  final String organization;
  final String note;

  AppProfileSettings copyWith({
    String? displayName,
    String? organization,
    String? note,
  }) {
    return AppProfileSettings(
      displayName: displayName ?? this.displayName,
      organization: organization ?? this.organization,
      note: note ?? this.note,
    );
  }

  String get initials {
    final source = displayName.trim().isNotEmpty
        ? displayName.trim()
        : organization.trim();
    if (source.isEmpty) {
      return 'LV';
    }

    final parts = source.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
    final initials = parts.take(2).map((part) => part.characters.first).join();
    return initials.toUpperCase();
  }
}

class AppSettings {
  const AppSettings({
    required this.profile,
    required this.preferredWhisperModel,
    required this.summaryMethod,
    required this.lectureLabels,
    required this.timelineLabels,
    required this.backgroundStyle,
  });

  static const WhisperModel defaultWhisperModel = WhisperModel.base;
  static const AppSummaryMethod defaultSummaryMethod =
      AppSummaryMethod.extractive;
  static const List<WhisperModel> availableWhisperModels = [
    WhisperModel.base,
    WhisperModel.small,
  ];
  static const List<AppSummaryMethod> availableSummaryMethods =
      AppSummaryMethod.values;

  static WhisperModel resolveAvailableWhisperModel(WhisperModel model) {
    if (availableWhisperModels.contains(model)) {
      return model;
    }
    return defaultWhisperModel;
  }

  static const List<String> defaultLectureLabels = [
    '一般',
    '重點',
    '考試',
    '作業',
  ];
  static const List<String> defaultTimelineLabels = [
    '開場',
    '定義',
    '例題',
    '重點',
    '總結',
  ];

  final AppProfileSettings profile;
  final WhisperModel preferredWhisperModel;
  final AppSummaryMethod summaryMethod;
  final List<String> lectureLabels;
  final List<String> timelineLabels;
  final AppBackgroundStyle backgroundStyle;

  factory AppSettings.defaults() {
    return const AppSettings(
      profile: AppProfileSettings(),
      preferredWhisperModel: defaultWhisperModel,
      summaryMethod: defaultSummaryMethod,
      lectureLabels: defaultLectureLabels,
      timelineLabels: defaultTimelineLabels,
      backgroundStyle: AppBackgroundStyle.darkDefault,
    );
  }

  factory AppSettings.fromStorage(Map<String, String> raw) {
    final defaults = AppSettings.defaults();
    return AppSettings(
      profile: AppProfileSettings(
        displayName: raw[AppSettingsKeys.profileDisplayName] ?? '',
        organization: raw[AppSettingsKeys.profileOrganization] ?? '',
        note: raw[AppSettingsKeys.profileNote] ?? '',
      ),
      preferredWhisperModel: WhisperModelSettingsX.fromStorage(
        raw[AppSettingsKeys.preferredWhisperModel],
      ),
      summaryMethod: AppSummaryMethodX.fromStorage(
        raw[AppSettingsKeys.summaryMethod],
      ),
      lectureLabels: _decodeLabelList(
        raw,
        AppSettingsKeys.lectureLabels,
        defaults.lectureLabels,
      ),
      timelineLabels: _decodeLabelList(
        raw,
        AppSettingsKeys.timelineLabels,
        defaults.timelineLabels,
      ),
      backgroundStyle: AppBackgroundStyleX.fromStorage(
        raw[AppSettingsKeys.backgroundStyle],
      ),
    );
  }

  AppSettings copyWith({
    AppProfileSettings? profile,
    WhisperModel? preferredWhisperModel,
    AppSummaryMethod? summaryMethod,
    List<String>? lectureLabels,
    List<String>? timelineLabels,
    AppBackgroundStyle? backgroundStyle,
  }) {
    return AppSettings(
      profile: profile ?? this.profile,
      preferredWhisperModel:
          preferredWhisperModel ?? this.preferredWhisperModel,
      summaryMethod: summaryMethod ?? this.summaryMethod,
      lectureLabels: lectureLabels == null
          ? this.lectureLabels
          : _normalizeLabels(lectureLabels),
      timelineLabels: timelineLabels == null
          ? this.timelineLabels
          : _normalizeLabels(timelineLabels),
      backgroundStyle: backgroundStyle ?? this.backgroundStyle,
    );
  }

  Map<String, String> toStorageMap() {
    return {
      AppSettingsKeys.profileDisplayName: profile.displayName.trim(),
      AppSettingsKeys.profileOrganization: profile.organization.trim(),
      AppSettingsKeys.profileNote: profile.note.trim(),
      AppSettingsKeys.preferredWhisperModel: preferredWhisperModel.storageValue,
      AppSettingsKeys.summaryMethod: summaryMethod.storageValue,
      AppSettingsKeys.lectureLabels: jsonEncode(lectureLabels),
      AppSettingsKeys.timelineLabels: jsonEncode(timelineLabels),
      AppSettingsKeys.backgroundStyle: backgroundStyle.storageValue,
    };
  }

  static List<String> _decodeLabelList(
    Map<String, String> raw,
    String key,
    List<String> fallback,
  ) {
    if (!raw.containsKey(key)) {
      return fallback;
    }

    final storedValue = raw[key];
    if (storedValue == null || storedValue.trim().isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(storedValue);
      if (decoded is! List) {
        return fallback;
      }
      return _normalizeLabels(decoded.whereType<String>());
    } catch (_) {
      return fallback;
    }
  }

  static List<String> _normalizeLabels(Iterable<String> input) {
    final normalized = <String>[];
    final seen = <String>{};

    for (final raw in input) {
      final value = raw.trim();
      if (value.isEmpty || seen.contains(value)) {
        continue;
      }
      seen.add(value);
      normalized.add(value);
    }

    return List.unmodifiable(normalized);
  }
}

abstract final class AppSettingsKeys {
  static const String profileDisplayName = 'profile.displayName';
  static const String profileOrganization = 'profile.organization';
  static const String profileNote = 'profile.note';
  static const String preferredWhisperModel = 'transcription.preferredModel';
  static const String summaryMethod = 'summary.method';
  static const String lectureLabels = 'labels.lecture';
  static const String timelineLabels = 'labels.timeline';
  static const String backgroundStyle = 'background.style';
}
