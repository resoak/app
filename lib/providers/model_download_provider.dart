// Re-export the service classes for convenience
// Note: Riverpod state management had issues in this project
// State management is handled directly in the UI using setState
export '../services/model_download_service.dart' show ModelDownloadService, ModelDownloadInfo, ModelDownloadProgress;