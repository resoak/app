import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import '../models/app_settings.dart';
import '../providers/app_settings_provider.dart';
import '../providers/drive_backup_provider.dart';
import '../providers/model_download_provider.dart';
import '../services/android_local_llm_runtime_service.dart';
import '../services/model_download_service.dart';
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

  // Model download state - managed directly without Riverpod
  final ModelDownloadService _modelService = ModelDownloadService();
  Map<String, ModelDownloadProgress> _downloadProgress = {};
  List<String> _downloadedModelIds = [];
  String? _selectedModelId;
  bool _isLoadingModels = true;

  @override
  void initState() {
    super.initState();
    _loadDownloadedModels();
  }

  Future<void> _loadDownloadedModels() async {
    setState(() => _isLoadingModels = true);
    try {
      final ids = await _modelService.getDownloadedModelIds();
      if (mounted) {
        setState(() {
          _downloadedModelIds = ids;
          _selectedModelId = AndroidLocalLlmRuntimeService.selectedModelId;
          _isLoadingModels = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingModels = false);
      }
    }
  }

  Future<void> _downloadModel(String modelId) async {
    // Don't start if already downloading
    if (_downloadProgress[modelId]?.isDownloading == true) {
      return;
    }

    setState(() {
      _downloadProgress = {
        ..._downloadProgress,
        modelId: ModelDownloadProgress(
          modelId: modelId,
          isDownloading: true,
        ),
      };
    });

    try {
      await _modelService.downloadModel(
        modelId,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = {..._downloadProgress, modelId: progress};
            });
          }
        },
      );
      // Refresh downloaded models
      await _loadDownloadedModels();
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadProgress = {
            ..._downloadProgress,
            modelId: ModelDownloadProgress(
              modelId: modelId,
              isDownloading: false,
              hasError: true,
              errorMessage: e.toString(),
            ),
          };
        });
      }
    }
  }

  Future<void> _deleteModel(String modelId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除模型'),
        content: const Text('確定要刪除嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _modelService.deleteModel(modelId);
      final newProgress =
          Map<String, ModelDownloadProgress>.from(_downloadProgress);
      newProgress.remove(modelId);
      setState(() => _downloadProgress = newProgress);
      await _loadDownloadedModels();
    }
  }

  void _selectModel(String modelId) {
    setState(() => _selectedModelId = modelId);
    AndroidLocalLlmRuntimeService.selectedModelId = modelId;
    _showMessage('已選擇模型');
  }

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

  Widget _buildModelDownloadSection() {
    final palette = context.lvPalette;
    const availableModels = ModelDownloadInfo.availableModels;

    if (_isLoadingModels) {
      return const _SettingsSectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              eyebrow: 'LLM MODEL',
              title: '下載摘要模型',
              description: '下載後的模型會儲存在手機內部空間，佔用約 1-2GB。',
            ),
            SizedBox(height: 16),
            Center(child: CircularProgressIndicator()),
          ],
        ),
      );
    }

    return _SettingsSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            eyebrow: 'LLM MODEL',
            title: '下載摘要模型',
            description: '下載後的模型會儲存在手機內部空間，佔用約 1-2GB。',
          ),
          const SizedBox(height: 16),
          // List of available models
          ...availableModels.map((model) {
            final progress = _downloadProgress[model.id];
            final isDownloaded = _downloadedModelIds.contains(model.id);
            final isDownloading = progress?.isDownloading ?? false;
            final downloadProgressValue = progress?.progress ?? 0.0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ModelDownloadTile(
                model: model,
                isDownloaded: isDownloaded,
                isDownloading: isDownloading,
                progress: downloadProgressValue,
                isSelected: _selectedModelId == model.id,
                onDownload: () => _downloadModel(model.id),
                onDelete: () => _deleteModel(model.id),
                onSelect: isDownloaded ? () => _selectModel(model.id) : null,
              ),
            );
          }),
          if (_downloadProgress.values.any((p) => p.isDownloading)) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _downloadProgress.values
                  .firstWhere(
                    (p) => p.isDownloading,
                    orElse: () => const ModelDownloadProgress(modelId: ''),
                  )
                  .progress,
              backgroundColor: palette.borderSubtle,
              valueColor:
                  const AlwaysStoppedAnimation(LectureVaultColors.purpleBright),
            ),
            const SizedBox(height: 4),
            Text(
              '下載中...',
              style: context.lvMono(10, color: palette.textMuted),
            ),
          ],
        ],
      ),
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

  Widget _buildSummaryMethodSection(AppSettings settings) {
    return _SettingsSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            eyebrow: 'SUMMARY',
            title: '預設摘要方式',
            description:
                '建議使用 Android 本機 LLM 直接產生條列重點；extractive 只保留作為 fallback。',
          ),
          const SizedBox(height: 16),
          ...AppSettings.availableSummaryMethods.map(
            (method) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SummaryMethodTile(
                method: method,
                selected: settings.summaryMethod == method,
                onTap: () {
                  ref
                      .read(appSettingsProvider.notifier)
                      .updateSummaryMethod(method);
                },
              ),
            ),
          ),
        ],
      ),
    );
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
    final palette = context.lvPalette;

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
              description:
                  'Google OAuth 失敗時會顯示可閱讀的錯誤；若出現 SHA-1 / developer_error，代表 Android OAuth client 尚未綁定目前安裝版本的 SHA-1。',
            ),
            const SizedBox(height: 14),
            Text(
              '$error',
              style: context.lvMono(12, color: palette.textSecondary),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () =>
                  ref.read(driveBackupControllerProvider.notifier).refresh(),
              child: Text(
                '重新整理',
                style:
                    context.lvMono(12, color: LectureVaultColors.blueElectric),
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
                description:
                    '支援登入、檢查帳號狀態、上傳最新本機資料、讀取最新備份資訊與還原。若登入失敗，先到 Google Cloud / Firebase 補齊 Android package name 與 SHA-1。',
              ),
              const SizedBox(height: 14),
              Text(
                state.account.isSignedIn
                    ? '目前帳號：${state.account.email.isEmpty ? state.account.label : state.account.email}'
                    : '目前尚未連線 Google 帳號',
                style: context.lvMono(12, color: palette.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                latestBackup == null
                    ? '尚未找到雲端最新備份資訊。'
                    : '最新備份：${_formatDriveTimestamp(latestBackup.createdAt)} · ${latestBackup.audioFileCount} 個音檔 · ${latestBackup.totalBytes} bytes',
                style: context.lvMono(11, color: palette.textMuted),
              ),
              if (lastError != null && lastError.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  lastError,
                  style: context.lvMono(11, color: LectureVaultColors.stopRed),
                ),
              ],
              if (state.isBusy) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: palette.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Google Drive 處理中，請稍候…',
                        style: context.lvMono(11, color: palette.textMuted),
                      ),
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(
                        minHeight: 3,
                        backgroundColor: LectureVaultColors.stopRed,
                        valueColor: AlwaysStoppedAnimation(
                          LectureVaultColors.purpleBright,
                        ),
                      ),
                    ],
                  ),
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
                      style: context.lvMono(
                        12,
                        color: LectureVaultColors.blueElectric,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed:
                        state.canRunDriveActions ? _handleDriveBackup : null,
                    child: Text(
                      '立即備份',
                      style: context.lvMono(
                        12,
                        color: LectureVaultColors.purpleBright,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: state.canRunDriveActions && latestBackup != null
                        ? _handleDriveRestore
                        : null,
                    child: Text(
                      '還原最新備份',
                      style: context.lvMono(
                        12,
                        color: LectureVaultColors.blueElectric,
                      ),
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
                      style: context.lvMono(12, color: palette.textMuted),
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
    final palette = context.lvPalette;

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
                      Text('無法讀取設定', style: context.lvHeading(20)),
                      const SizedBox(height: 10),
                      Text(
                        '$error',
                        textAlign: TextAlign.center,
                        style: context.lvMono(12, color: palette.textSecondary),
                      ),
                      const SizedBox(height: 18),
                      TextButton(
                        onPressed: () => ref.invalidate(appSettingsProvider),
                        child: Text(
                          '重新載入',
                          style: context.lvMono(
                            12,
                            color: LectureVaultColors.blueElectric,
                          ),
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
                          color: palette.surface,
                          border: Border.all(color: palette.borderSubtle),
                        ),
                        child: IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: palette.textPrimary,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Profile & Settings',
                              style: context.lvHeading(24),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '本機個人偏好、模型與背景設定',
                              style:
                                  context.lvMono(11, color: palette.textMuted),
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
                              style: context.lvMono(
                                12,
                                color: _isSavingProfile
                                    ? palette.textMuted
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
                                  labelStyle: context.lvMono(
                                    11,
                                    color:
                                        settings.preferredWhisperModel == model
                                            ? Colors.white
                                            : palette.textMuted,
                                    weight: FontWeight.w600,
                                  ),
                                  selectedColor: LectureVaultColors.purple
                                      .withValues(alpha: 0.34),
                                  backgroundColor: Colors.transparent,
                                  side: BorderSide(
                                    color:
                                        settings.preferredWhisperModel == model
                                            ? LectureVaultColors.purpleBright
                                            : palette.borderSubtle,
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
                  _buildSummaryMethodSection(settings),
                  const SizedBox(height: 18),
                  _buildModelDownloadSection(),
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
                          description: '選擇你喜歡的介面風格顏色。',
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
    final palette = context.lvPalette;

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
        border: Border.all(color: palette.borderSubtle),
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
              color: palette.surface.withValues(alpha: 0.42),
              border: Border.all(color: palette.borderSubtle),
            ),
            child: Text(
              settings.profile.initials,
              style: context.lvHeading(20, weight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: context.lvHeading(20, weight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: palette.surface.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'LOCAL-FIRST · SQLITE ONLY',
                    style: context.lvMono(10, color: palette.textPrimary),
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
    final palette = context.lvPalette;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.borderSubtle),
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
    final palette = context.lvPalette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(eyebrow, style: context.lvMono(10, color: palette.textMuted)),
        const SizedBox(height: 6),
        Text(title, style: context.lvHeading(18, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          description,
          style: TextStyle(
            color: palette.textSecondary,
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
    final palette = context.lvPalette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.lvMono(10, color: palette.textMuted)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: TextStyle(color: palette.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                TextStyle(color: palette.textMuted.withValues(alpha: 0.55)),
            filled: true,
            fillColor: palette.inputFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: palette.borderSubtle),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: palette.borderSubtle),
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
    final palette = context.lvPalette;

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
              style: context.lvMono(12, color: palette.textMuted),
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
                      labelStyle: context.lvMono(
                        11,
                        color: LectureVaultColors.blueElectric,
                        weight: FontWeight.w600,
                      ),
                      backgroundColor: LectureVaultColors.blueElectric
                          .withValues(alpha: 0.12),
                      deleteIconColor: palette.textMuted,
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

class _SummaryMethodTile extends StatelessWidget {
  const _SummaryMethodTile({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  final AppSummaryMethod method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.lvPalette;
    final accent = method == AppSummaryMethod.extractive
        ? LectureVaultColors.blueElectric
        : LectureVaultColors.purpleBright;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? palette.surfaceSelected : palette.surfaceAlt,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? palette.borderStrong : palette.borderSubtle,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          method.label,
                          style: context.lvHeading(15, weight: FontWeight.w700),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.24),
                            ),
                          ),
                          child: Text(
                            method.badgeLabel,
                            style: context.lvMono(
                              9,
                              color: accent,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      method.description,
                      style: TextStyle(
                        color: palette.textSecondary,
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
                color: selected ? accent : palette.textMuted,
              ),
            ],
          ),
        ),
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
    final palette = context.lvPalette;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? palette.surfaceSelected : palette.surfaceAlt,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? palette.borderStrong : palette.borderSubtle,
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
                        style: context.lvHeading(15, weight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                      style.description,
                      style: TextStyle(
                        color: palette.textSecondary,
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
                    : palette.textMuted,
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
          color: LectureVaultPalette.black.backgroundBase,
          borderRadius: BorderRadius.circular(16),
        ),
      AppBackgroundStyle.white => BoxDecoration(
          color: LectureVaultPalette.white.backgroundBase,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.12),
          ),
        ),
    };

    return Container(
      width: 72,
      height: 72,
      decoration: decoration,
      child: const SizedBox.expand(),
    );
  }
}

class _ModelDownloadTile extends StatelessWidget {
  const _ModelDownloadTile({
    required this.model,
    required this.isDownloaded,
    required this.isDownloading,
    required this.progress,
    required this.isSelected,
    required this.onDownload,
    required this.onDelete,
    required this.onSelect,
  });

  final ModelDownloadInfo model;
  final bool isDownloaded;
  final bool isDownloading;
  final double progress;
  final bool isSelected;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.lvPalette;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isDownloaded ? onSelect : null,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected ? palette.surfaceSelected : palette.surfaceAlt,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? LectureVaultColors.purpleBright
                  : palette.borderSubtle,
            ),
          ),
          child: Row(
            children: [
              // Status icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isDownloaded
                      ? Colors.green.withValues(alpha: 0.12)
                      : palette.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isDownloaded
                      ? Icons.check_circle_rounded
                      : (isDownloading
                          ? Icons.downloading_rounded
                          : Icons.cloud_download_outlined),
                  color: isDownloaded
                      ? Colors.green
                      : (isDownloading
                          ? LectureVaultColors.purpleBright
                          : palette.textMuted),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              // Model info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          model.name,
                          style: context.lvHeading(14, weight: FontWeight.w600),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: LectureVaultColors.purpleBright
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '已選',
                              style: context.lvMono(9,
                                  color: LectureVaultColors.purpleBright),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      model.description,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                    if (isDownloading) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: palette.borderSubtle,
                          valueColor: const AlwaysStoppedAnimation(
                              LectureVaultColors.purpleBright),
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Action buttons
              if (isDownloaded)
                IconButton(
                  onPressed: onDelete,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: LectureVaultColors.stopRed.withValues(alpha: 0.7),
                    size: 20,
                  ),
                  tooltip: '刪除模型',
                )
              else
                IconButton(
                  onPressed: isDownloading ? null : onDownload,
                  icon: Icon(
                    Icons.download_rounded,
                    color: isDownloading
                        ? palette.textMuted
                        : LectureVaultColors.blueElectric,
                    size: 20,
                  ),
                  tooltip: '下載模型',
                ),
            ],
          ),
        ),
      ),
    );
  }
}
