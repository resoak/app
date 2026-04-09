import 'dart:convert';

class Lecture {
  final int? id;
  final String title;
  final String date;
  final String audioPath;
  final String transcript;
  final String summary;
  final int durationSeconds;
  final String tag;
  final List<LectureTimelineEntry> timeline;

  Lecture({
    this.id,
    required this.title,
    required this.date,
    required this.audioPath,
    this.transcript = '',
    this.summary = '',
    this.durationSeconds = 0,
    this.tag = '一般',
    this.timeline = const [],
  });

  Lecture copyWith({
    int? id,
    String? title,
    String? date,
    String? audioPath,
    String? transcript,
    String? summary,
    int? durationSeconds,
    String? tag,
    List<LectureTimelineEntry>? timeline,
  }) {
    return Lecture(
      id: id ?? this.id,
      title: title ?? this.title,
      date: date ?? this.date,
      audioPath: audioPath ?? this.audioPath,
      transcript: transcript ?? this.transcript,
      summary: summary ?? this.summary,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      tag: tag ?? this.tag,
      timeline: timeline ?? this.timeline,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'date': date,
      'audioPath': audioPath,
      'transcript': transcript,
      'summary': summary,
      'durationSeconds': durationSeconds,
      'tag': tag,
      'timelineJson':
          jsonEncode(timeline.map((entry) => entry.toMap()).toList()),
    };
  }

  factory Lecture.fromMap(Map<String, dynamic> map) {
    return Lecture(
      id: map['id'],
      title: map['title'],
      date: map['date'],
      audioPath: map['audioPath'],
      transcript: map['transcript'] ?? '',
      summary: map['summary'] ?? '',
      durationSeconds: map['durationSeconds'] ?? 0,
      tag: map['tag'] ?? '一般',
      timeline: _parseTimeline(map['timelineJson']),
    );
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
    this.isEstimated = false,
  });

  final String text;
  final int startMs;
  final int endMs;
  final bool isEstimated;

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'startMs': startMs,
      'endMs': endMs,
      'isEstimated': isEstimated,
    };
  }

  factory LectureTimelineEntry.fromMap(Map<String, dynamic> map) {
    return LectureTimelineEntry(
      text: map['text'] as String? ?? '',
      startMs: (map['startMs'] as num?)?.toInt() ?? 0,
      endMs: (map['endMs'] as num?)?.toInt() ?? 0,
      isEstimated: map['isEstimated'] as bool? ?? false,
    );
  }
}
