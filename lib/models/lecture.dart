import 'dart:convert';

enum LectureProcessingStatus { pending, processing, completed, failed }

extension LectureProcessingStatusX on LectureProcessingStatus {
  String get dbValue => name;

  static LectureProcessingStatus? tryParse(dynamic raw) {
    final value = raw as String?;
    if (value == null || value.trim().isEmpty) return null;

    for (final status in LectureProcessingStatus.values) {
      if (status.name == value) return status;
    }
    return null;
  }
}

class Lecture {
  final int? id;
  final String uid;
  final String title;
  final String date;
  final String audioPath;
  final String managedAudioPath;
  final String transcript;
  final String summary;
  final LectureProcessingStatus transcriptionStatus;
  final LectureProcessingStatus summaryStatus;
  final int durationSeconds;
  final String tag;
  final List<LectureTimelineEntry> timeline;

  Lecture({
    this.id,
    this.uid = '',
    required this.title,
    required this.date,
    required this.audioPath,
    this.managedAudioPath = '',
    this.transcript = '',
    this.summary = '',
    this.transcriptionStatus = LectureProcessingStatus.pending,
    this.summaryStatus = LectureProcessingStatus.pending,
    this.durationSeconds = 0,
    this.tag = '一般',
    this.timeline = const [],
  });

  Lecture copyWith({
    int? id,
    String? uid,
    String? title,
    String? date,
    String? audioPath,
    String? managedAudioPath,
    String? transcript,
    String? summary,
    LectureProcessingStatus? transcriptionStatus,
    LectureProcessingStatus? summaryStatus,
    int? durationSeconds,
    String? tag,
    List<LectureTimelineEntry>? timeline,
  }) {
    return Lecture(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      title: title ?? this.title,
      date: date ?? this.date,
      audioPath: audioPath ?? this.audioPath,
      managedAudioPath: managedAudioPath ?? this.managedAudioPath,
      transcript: transcript ?? this.transcript,
      summary: summary ?? this.summary,
      transcriptionStatus: transcriptionStatus ?? this.transcriptionStatus,
      summaryStatus: summaryStatus ?? this.summaryStatus,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      tag: tag ?? this.tag,
      timeline: timeline ?? this.timeline,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uid': uid,
      'title': title,
      'date': date,
      'audioPath': audioPath,
      'managedAudioPath': managedAudioPath,
      'transcript': transcript,
      'summary': summary,
      'transcriptionStatus': transcriptionStatus.dbValue,
      'summaryStatus': summaryStatus.dbValue,
      'durationSeconds': durationSeconds,
      'tag': tag,
      'timelineJson':
          jsonEncode(timeline.map((entry) => entry.toMap()).toList()),
    };
  }

  factory Lecture.fromMap(Map<String, dynamic> map) {
    final transcript = map['transcript'] as String? ?? '';
    final summary = map['summary'] as String? ?? '';

    return Lecture(
      id: map['id'],
      uid: _parseUid(map),
      title: map['title'],
      date: map['date'],
      audioPath: map['audioPath'],
      managedAudioPath: map['managedAudioPath'] as String? ?? '',
      transcript: transcript,
      summary: summary,
      transcriptionStatus: _parseTranscriptionStatus(map, transcript, summary),
      summaryStatus: _parseSummaryStatus(map, transcript, summary),
      durationSeconds: map['durationSeconds'] ?? 0,
      tag: map['tag'] ?? '一般',
      timeline: _parseTimeline(map['timelineJson']),
    );
  }

  static String _parseUid(Map<String, dynamic> map) {
    final raw = map['uid'] as String?;
    if (raw != null && raw.trim().isNotEmpty) {
      return raw;
    }
    final legacyId = map['id'] as int?;
    if (legacyId != null) {
      return 'legacy-$legacyId';
    }
    return '';
  }

  static LectureProcessingStatus _parseTranscriptionStatus(
    Map<String, dynamic> map,
    String transcript,
    String summary,
  ) {
    return LectureProcessingStatusX.tryParse(map['transcriptionStatus']) ??
        _inferLegacyTranscriptionStatus(transcript, summary);
  }

  static LectureProcessingStatus _parseSummaryStatus(
    Map<String, dynamic> map,
    String transcript,
    String summary,
  ) {
    return LectureProcessingStatusX.tryParse(map['summaryStatus']) ??
        _inferLegacySummaryStatus(transcript, summary);
  }

  static LectureProcessingStatus _inferLegacyTranscriptionStatus(
    String transcript,
    String summary,
  ) {
    final normalizedSummary = summary.trim();

    if (transcript.trim().isNotEmpty) {
      return LectureProcessingStatus.completed;
    }
    if (normalizedSummary == '背景轉錄中…') {
      return LectureProcessingStatus.processing;
    }
    if (normalizedSummary == '背景轉錄失敗，請稍後再試。') {
      return LectureProcessingStatus.failed;
    }
    return LectureProcessingStatus.pending;
  }

  static LectureProcessingStatus _inferLegacySummaryStatus(
    String transcript,
    String summary,
  ) {
    final normalizedSummary = summary.trim();

    if (normalizedSummary == '背景轉錄中…') {
      return LectureProcessingStatus.processing;
    }
    if (normalizedSummary == '背景轉錄失敗，請稍後再試。') {
      return LectureProcessingStatus.failed;
    }
    if (normalizedSummary.isNotEmpty) {
      return LectureProcessingStatus.completed;
    }
    if (transcript.trim().isNotEmpty) {
      return LectureProcessingStatus.pending;
    }
    return LectureProcessingStatus.pending;
  }

  static List<LectureTimelineEntry> _parseTimeline(dynamic raw) {
    if (raw is! String || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (item) => LectureTimelineEntry.fromMap(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}

class LectureTimelineEntry {
  const LectureTimelineEntry({
    required this.text,
    required this.startMs,
    required this.endMs,
    this.label,
    this.isEstimated = false,
  });

  final String text;
  final int startMs;
  final int endMs;
  final String? label;
  final bool isEstimated;

  LectureTimelineEntry copyWith({
    String? text,
    int? startMs,
    int? endMs,
    String? label,
    bool clearLabel = false,
    bool? isEstimated,
  }) {
    return LectureTimelineEntry(
      text: text ?? this.text,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      label: clearLabel ? null : (label ?? this.label),
      isEstimated: isEstimated ?? this.isEstimated,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'startMs': startMs,
      'endMs': endMs,
      if (label != null) 'label': label,
      'isEstimated': isEstimated,
    };
  }

  factory LectureTimelineEntry.fromMap(Map<String, dynamic> map) {
    return LectureTimelineEntry(
      text: map['text'] as String? ?? '',
      startMs: (map['startMs'] as num?)?.toInt() ?? 0,
      endMs: (map['endMs'] as num?)?.toInt() ?? 0,
      label: map['label'] as String?,
      isEstimated: map['isEstimated'] as bool? ?? false,
    );
  }
}
