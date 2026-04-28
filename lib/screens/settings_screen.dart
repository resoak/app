import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import '../models/app_settings.dart';
import '../providers/app_settings_provider.dart';
import '../providers/drive_backup_provider.dart';
import '../theme/lecture_vault_theme.dart';
import '../widgets/lecture_vault_background.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _organizationController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _lectureLabelController = TextEditingController();
  final TextEditingController _timelineLabelController =
      TextEditingController();

  bool _didHydrateProfile = false;
  bool _isSavingProfile = false;

  @override
  void dispose() {
    _displayNameController.dispose();
    _organizationController.dispose();
    _noteController.dispose();
    _lectureLabelController.dispose();
    _timelineLabelController.dispose();
    super.dispose();
  }

  void _hydrateProfileDraft(AppSettings settings) {
    if (_didHydrateProfile) {
      return;
    }

    _displayNameController.text = settings.profile.displayName;
    _organizationController.text = settings.profile.organization;
    _noteController.text = settings.profile.note;
    _didHydrateProfile = true;
  }

  Future<void> _saveProfile() async {
    setState(() => _isSavingProfile = true);

    try {
      await ref.read(appSettingsProvider.notifier).updateProfile(
            displayName: _displayNameController.text,
            organization: _organizationController.text,
            note: _noteController.text,
          );
      if (!mounted) {
        return;
      }
      _showMessage('個人資訊已儲存在本機');
    } finally {
      if (mounted) {
        setState(() => _isSavingProfile = false);
      }
    }
  }

  Future<void> _addLectureLabel(AppSettings settings) async {
    final label = _lectureLabelController.text.trim();
    if (label.isEmpty) {
      _showMessage('請先輸入課程標籤');
      return;
    }
    if (settings.lectureLabels.contains(label)) {
      _showMessage('課程標籤已存在');
      return;
    }

    await ref.read(appSettingsProvider.notifier).addLectureLabel(label);
    _lectureLabelController.clear();
    if (!mounted) {
      return;
    }
    _showMessage('已加入課程標籤');
  }

  Future<void> _addTimelineLabel(AppSettings settings) async {
    final label = _timelineLabelController.text.trim();
    if (label.isEmpty) {
      _showMessage('請先輸入時間軸標籤');
      return;
    }
    if (settings.timelineLabels.contains(label)) {
      _showMessage('時間軸標籤已存在');
      return;
    }

    await ref.read(appSettingsProvider.notifier).addTimelineLabel(label);
    _timelineLabelController.clear();
    if (!mounted) {
      return;
    }
    _showMessage('已加入時間軸標籤');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _whisperModelLabel(WhisperModel model) {
    switch (model) {
      case WhisperModel.base:
        return 'BASE';
      case WhisperModel.small:
        return 'SMALL';
      default:
        return model.name.toUpperCase();
    }
  }

  Future<void> _handleDriveSignIn() async {
    try {
      final account =
          await ref.read(driveBackupControllerProvider.notifier).signIn();
      if (!mounted) {
        return;
      }
      _showMessage(
          account.email.isEmpty ? '已連線 Google 帳號' : '已連線 ${account.email}');
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(error.toString());
    }
  }

  Future<void> _handleDriveSignOut() async {
    try {
      await ref.read(driveBackupControllerProvider.notifier).signOut();
      if (!mounted) {
        return;
      }
      _showMessage('已登出 Google 帳號');
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(error.toString());
    }
  }

  Future<void> _handleDriveBackup() async {
    try {
      final metadata =
          await ref.read(driveBackupControllerProvider.notifier).createBackup();
      if (!mounted) {
        return;
      }
      _showMessage('已上傳雲端備份（${metadata.audioFileCount} 個音檔）');
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(error.toString());
    }
  }

  Future<void> _handleDriveRestore() async {
    try {
      await ref
          .read(driveBackupControllerProvider.notifier)
          .restoreLatestBackup();
      ref.invalidate(appSettingsProvider);
      if (!mounted) {
        return;
      }
      _showMessage('已從 Google Drive 還原最新備份');
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(error.toString());
    }
  }

  String _formatDriveTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildDriveBackupSection() {
    final driveState = ref.watch(driveBackupControllerProvider);

    return _SettingsSectionCard(
      child: driveState.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              eyebrow: 'GOOGLE DRIVE BACKUP',
              title: 'Google Drive appDataFolder 備份',
              description: 'Google OAuth 尚未設定完成時，這裡會顯示可閱讀的錯誤訊息而不是直接崩潰。',
            ),
            const SizedBox(height: 14),
            Text(
              '$error',
              style: lvMono(12, color: Colors.white.withValues(alpha: 0.74)),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () =>
                  ref.read(driveBackupControllerProvider.notifier).refresh(),
              child: Text(
                '重新整理',
                style: lvMono(12, color: LectureVaultColors.blueElectric),
              ),
            ),
          ],
        ),
        data: (state) {
          final latestBackup = state.latestBackup;
          final lastError = state.lastError ?? state.account.userMessage;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHeader(
                eyebrow: 'GOOGLE DRIVE BACKUP',
                title: 'Google Drive appDataFolder 備份',
                description: '支援登入、檢查帳號狀態、上傳最新本機資料、讀取最新備份資訊與還原。',
              ),
              const SizedBox(height: 14),
              Text(
                state.account.isSignedIn
                    ? '目前帳號：${state.account.email.isEmpty ? state.account.label : state.account.email}'
                    : '目前尚未連線 Google 帳號',
                style: lvMono(12, color: Colors.white.withValues(alpha: 0.88)),
              ),
              const SizedBox(height: 8),
              Text(
                latestBackup == null
                    ? '尚未找到雲端最新備份資訊。'
                    : '最新備份：${_formatDriveTimestamp(latestBackup.createdAt)} · ${latestBackup.audioFileCount} 個音檔 · ${latestBackup.totalBytes} bytes',
                style: lvMono(11, color: LectureVaultColors.textMuted),
              ),
              if (lastError != null && lastError.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  lastError,
                  style: lvMono(11, color: LectureVaultColors.stopRed),
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  TextButton(
                    onPressed: state.isBusy
                        ? null
                        : (state.account.isSignedIn
                            ? _handleDriveSignOut
                            : _handleDriveSignIn),
                    child: Text(
                      state.account.isSignedIn ? '登出 Google' : '登入 Google',
                      style: lvMono(12, color: LectureVaultColors.blueElectric),
                    ),
                  ),
                  TextButton(
                    onPressed:
                        state.canRunDriveActions ? _handleDriveBackup : null,
                    child: Text(
                      '立即備份',
                      style: lvMono(12, color: LectureVaultColors.purpleBright),
                    ),
                  ),
                  TextButton(
                    onPressed: state.canRunDriveActions && latestBackup != null
                        ? _handleDriveRestore
                        : null,
                    child: Text(
                      '還原最新備份',
                      style: lvMono(12, color: LectureVaultColors.blueElectric),
                    ),
                  ),
                  TextButton(
                    onPressed: state.isBusy
                        ? null
                        : () => ref
                            .read(driveBackupControllerProvider.notifier)
                            .refresh(),
                    child: Text(
                      '重新整理狀態',
                      style: lvMono(12, color: LectureVaultColors.textMuted),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsState = ref.watch(appSettingsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LectureVaultBackground(
        child: SafeArea(
          child: settingsState.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _SettingsSectionCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('無法讀取設定', style: lvHeading(20)),
                      const SizedBox(height: 10),
                      Text(
                        '$error',
                        textAlign: TextAlign.center,
                        style: lvMono(12,
                            color: Colors.white.withValues(alpha: 0.7)),
                      ),
                      const SizedBox(height: 18),
                      TextButton(
                        onPressed: () => ref.invalidate(appSettingsProvider),
                        child: Text(
                          '重新載入',
                          style: lvMono(12,
                              color: LectureVaultColors.blueElectric),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            data: (settings) {
              _hydrateProfileDraft(settings);
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: LectureVaultColors.bgCard,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Profile & Settings', style: lvHeading(24)),
                            const SizedBox(height: 4),
                            Text(
                              '本機個人偏好、模型與背景設定',
                              style: lvMono(
                                11,
                                color: LectureVaultColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildProfileHero(settings),
                  const SizedBox(height: 18),
                  _buildDriveBackupSection(),
                  const SizedBox(height: 18),
                  _SettingsSectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionHeader(
                          eyebrow: 'LOCAL PROFILE',
                          title: '只保存在這台裝置上的個人資訊',
                          description: '適合先存顯示名稱、班級或備註，之後再接分享 / 同步功能。',
                        ),
                        const SizedBox(height: 16),
                        _SettingsTextField(
                          controller: _displayNameController,
                          label: '顯示名稱',
                          hint: '例如：王小明',
                        ),
                        const SizedBox(height: 12),
                        _SettingsTextField(
                          controller: _organizationController,
                          label: '學校 / 團隊 / 課程',
                          hint: '例如：NTU / Data Structures',
                        ),
                        const SizedBox(height: 12),
                        _SettingsTextField(
                          controller: _noteController,
                          label: '個人備註',
                          hint: '例如：偏好摘要精簡、錄音前先確認麥克風',
                          maxLines: 3,
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _isSavingProfile ? null : _saveProfile,
                            child: Text(
                              _isSavingProfile ? '儲存中…' : '儲存個人資訊',
                              style: lvMono(
                                12,
                                color: _isSavingProfile
                                    ? LectureVaultColors.textMuted
                                    : LectureVaultColors.blueElectric,
                                weight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _SettingsSectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionHeader(
                          eyebrow: 'TRANSCRIPTION',
                          title: '預設 Whisper 模型',
                          description: 'Home 與錄音流程都會直接讀取這個偏好。',
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: AppSettings.availableWhisperModels
                              .map(
                                (model) => ChoiceChip(
                                  label: Text(_whisperModelLabel(model)),
                                  selected:
                                      settings.preferredWhisperModel == model,
                                  showCheckmark: false,
                                  onSelected: (_) {
                                    ref
                                        .read(appSettingsProvider.notifier)
                                        .updatePreferredWhisperModel(model);
                                  },
                                  labelStyle: lvMono(
                                    11,
                                    color:
                                        settings.preferredWhisperModel == model
                                            ? Colors.white
                                            : LectureVaultColors.textMuted,
                                    weight: FontWeight.w600,
                                  ),
                                  selectedColor: LectureVaultColors.purple
                                      .withValues(alpha: 0.34),
                                  backgroundColor: Colors.transparent,
                                  side: BorderSide(
                                    color: settings.preferredWhisperModel ==
                                            model
                                        ? LectureVaultColors.purpleBright
                                        : Colors.white.withValues(alpha: 0.16),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _EditableLabelSection(
                    eyebrow: 'LECTURE LABELS',
                    title: '課程標籤清單',
                    description: '為之後的標籤編輯與篩選流程先建立可管理的本機清單。',
                    controller: _lectureLabelController,
                    hint: '新增課程標籤',
                    labels: settings.lectureLabels,
                    emptyLabel: '目前沒有自訂課程標籤',
                    onAdd: () => _addLectureLabel(settings),
                    onRemove: (label) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .removeLectureLabel(label);
                    },
                  ),
                  const SizedBox(height: 18),
                  _EditableLabelSection(
                    eyebrow: 'TIMELINE LABELS',
                    title: '時間軸標籤清單',
                    description: '先整理常用標題，後續標記時間軸時可以直接套用。',
                    controller: _timelineLabelController,
                    hint: '新增時間軸標籤',
                    labels: settings.timelineLabels,
                    emptyLabel: '目前沒有自訂時間軸標籤',
                    onAdd: () => _addTimelineLabel(settings),
                    onRemove: (label) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .removeTimelineLabel(label);
                    },
                  ),
                  const SizedBox(height: 18),
                  _SettingsSectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionHeader(
                          eyebrow: 'BACKGROUND',
                          title: '背景風格',
                          description: 'Home、錄音與講義詳情頁都會讀這個設定，不影響主要內容排版。',
                        ),
                        const SizedBox(height: 16),
                        ...AppBackgroundStyle.values.map(
                          (style) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _BackgroundStyleTile(
                              style: style,
                              selected: settings.backgroundStyle == style,
                              onTap: () {
                                ref
                                    .read(appSettingsProvider.notifier)
                                    .updateBackgroundStyle(style);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHero(AppSettings settings) {
    final name = settings.profile.displayName.trim().isEmpty
        ? 'LOCAL USER'
        : settings.profile.displayName.trim();
    final subtitle = settings.profile.organization.trim().isEmpty
        ? 'LectureVault keeps these settings only on this device.'
        : settings.profile.organization.trim();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            LectureVaultColors.blueElectric.withValues(alpha: 0.18),
            LectureVaultColors.purple.withValues(alpha: 0.2),
          ],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: LectureVaultColors.purple.withValues(alpha: 0.12),
            blurRadius: 26,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.08),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Text(
              settings.profile.initials,
              style: lvHeading(20, weight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: lvHeading(20, weight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.76),
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'LOCAL-FIRST · SQLITE ONLY',
                    style:
                        lvMono(10, color: Colors.white.withValues(alpha: 0.82)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSectionCard extends StatelessWidget {
  const _SettingsSectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: LectureVaultColors.bgCard.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.eyebrow,
    required this.title,
    required this.description,
  });

  final String eyebrow;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(eyebrow, style: lvMono(10, color: LectureVaultColors.textMuted)),
        const SizedBox(height: 6),
        Text(title, style: lvHeading(18, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          description,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.68),
            fontSize: 13,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _SettingsTextField extends StatelessWidget {
  const _SettingsTextField({
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: lvMono(10, color: LectureVaultColors.textMuted)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.03),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide:
                  const BorderSide(color: LectureVaultColors.purpleBright),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }
}

class _EditableLabelSection extends StatelessWidget {
  const _EditableLabelSection({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.controller,
    required this.hint,
    required this.labels,
    required this.emptyLabel,
    required this.onAdd,
    required this.onRemove,
  });

  final String eyebrow;
  final String title;
  final String description;
  final TextEditingController controller;
  final String hint;
  final List<String> labels;
  final String emptyLabel;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return _SettingsSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            eyebrow: eyebrow,
            title: title,
            description: description,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _SettingsTextField(
                  controller: controller,
                  label: '新增項目',
                  hint: hint,
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: SizedBox(
                  height: 52,
                  width: 52,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          LectureVaultColors.blueElectric,
                          LectureVaultColors.purple,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: IconButton(
                      onPressed: onAdd,
                      icon: const Icon(Icons.add_rounded, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (labels.isEmpty)
            Text(
              emptyLabel,
              style: lvMono(12, color: LectureVaultColors.textMuted),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: labels
                  .map(
                    (label) => InputChip(
                      label: Text(label),
                      onDeleted: () => onRemove(label),
                      labelStyle: lvMono(
                        11,
                        color: LectureVaultColors.blueElectric,
                        weight: FontWeight.w600,
                      ),
                      backgroundColor: LectureVaultColors.blueElectric
                          .withValues(alpha: 0.12),
                      deleteIconColor: LectureVaultColors.textMuted,
                      side: BorderSide(
                        color: LectureVaultColors.blueElectric
                            .withValues(alpha: 0.24),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }
}

class _BackgroundStyleTile extends StatelessWidget {
  const _BackgroundStyleTile({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final AppBackgroundStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? LectureVaultColors.bgCardActive
                : Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? LectureVaultColors.borderActive
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              _BackgroundPreview(style: style),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(style.label,
                        style: lvHeading(15, weight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                      style.description,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.68),
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected
                    ? LectureVaultColors.purpleBright
                    : LectureVaultColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackgroundPreview extends StatelessWidget {
  const _BackgroundPreview({required this.style});

  final AppBackgroundStyle style;

  @override
  Widget build(BuildContext context) {
    final decoration = switch (style) {
      AppBackgroundStyle.darkDefault => BoxDecoration(
          color: LectureVaultColors.bgDeep,
          borderRadius: BorderRadius.circular(16),
        ),
      AppBackgroundStyle.aurora => BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              LectureVaultColors.bgDeep,
              LectureVaultColors.purple.withValues(alpha: 0.7),
              LectureVaultColors.blueElectric.withValues(alpha: 0.75),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      AppBackgroundStyle.blueprint => BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              const Color(0xFF08101F),
              LectureVaultColors.blueElectric.withValues(alpha: 0.4),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
    };

    return Container(
      width: 72,
      height: 72,
      decoration: decoration,
      child: style == AppBackgroundStyle.blueprint
          ? const CustomPaint(painter: _PreviewGridPainter())
          : null,
    );
  }
}

class _PreviewGridPainter extends CustomPainter {
  const _PreviewGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 1;

    for (double dx = 12; dx < size.width; dx += 12) {
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
    }
    for (double dy = 12; dy < size.height; dy += 12) {
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
