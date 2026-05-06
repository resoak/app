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
  final List<LectureTimelineEntry> timeline;
  final List<String> tags;
  final List<double>? embedding;

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
    this.tags = const ['一般'],
    this.timeline = const [],
    this.embedding,
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
    List<String>? tags,
    List<LectureTimelineEntry>? timeline,
    List<double>? embedding,
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
      tags: tags ?? this.tags,
      timeline: timeline ?? this.timeline,
      embedding: embedding ?? this.embedding,
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
      'tagsJson': jsonEncode(tags),
      'timelineJson':
          jsonEncode(timeline.map((entry) => entry.toMap()).toList()),
      'embeddingJson': embedding != null ? jsonEncode(embedding) : null,
    };
  }

  factory Lecture.fromMap(
    Map<String, dynamic> map, {
    bool includeEmbedding = true,
  }) {
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
      tags: _parseTags(map),
      timeline: _parseTimeline(map['timelineJson']),
      embedding:
          includeEmbedding ? parseEmbeddingJson(map['embeddingJson']) : null,
    );
  }

  static List<double>? parseEmbeddingJson(dynamic raw) {
    if (raw is! String || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;

      final embedding = <double>[];
      for (final value in decoded) {
        if (value is! num) return null;
        embedding.add(value.toDouble());
      }
      return embedding;
    } catch (_) {
      return null;
    }
  }

  static List<String> _parseTags(Map<String, dynamic> map) {
    final tagsJson = map['tagsJson'] as String?;
    if (tagsJson != null && tagsJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(tagsJson);
        if (decoded is List) {
          return decoded.whereType<String>().toList();
        }
      } catch (_) {}
    }

    // Fallback to legacy 'tag' column
    final legacyTag = map['tag'] as String?;
    if (legacyTag != null && legacyTag.trim().isNotEmpty) {
      return [legacyTag.trim()];
    }

    return const ['一般'];
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
    this.labels = const [],
    this.isEstimated = false,
  });

  final String text;
  final int startMs;
  final int endMs;
  final List<String> labels;
  final bool isEstimated;

  LectureTimelineEntry copyWith({
    String? text,
    int? startMs,
    int? endMs,
    List<String>? labels,
    bool clearLabels = false,
    bool? isEstimated,
  }) {
    return LectureTimelineEntry(
      text: text ?? this.text,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      labels: clearLabels ? const [] : (labels ?? this.labels),
      isEstimated: isEstimated ?? this.isEstimated,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'startMs': startMs,
      'endMs': endMs,
      'labels': labels,
      'isEstimated': isEstimated,
    };
  }

  factory LectureTimelineEntry.fromMap(Map<String, dynamic> map) {
    return LectureTimelineEntry(
      text: map['text'] as String? ?? '',
      startMs: (map['startMs'] as num?)?.toInt() ?? 0,
      endMs: (map['endMs'] as num?)?.toInt() ?? 0,
      labels: _parseTimelineLabels(map),
      isEstimated: map['isEstimated'] as bool? ?? false,
    );
  }

  static List<String> _parseTimelineLabels(Map<String, dynamic> map) {
    final rawLabels = map['labels'];
    if (rawLabels is List) {
      return rawLabels.whereType<String>().toList();
    }
    // Fallback for legacy single label
    final legacyLabel = map['label'] as String?;
    if (legacyLabel != null && legacyLabel.trim().isNotEmpty) {
      return [legacyLabel.trim()];
    }
    return const [];
  }
}
