// lib/models/lecture.dart

class Lecture {
  final int? id;
  final String title;
  final String date;
  final String audioPath;
  final String transcript;
  final String summary;
  final int durationSeconds;

  Lecture({
    this.id,
    required this.title,
    required this.date,
    required this.audioPath,
    this.transcript = '',
    this.summary = '',
    this.durationSeconds = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'date': date,
        'audioPath': audioPath,
        'transcript': transcript,
        'summary': summary,
        'durationSeconds': durationSeconds,
      };

  factory Lecture.fromMap(Map<String, dynamic> map) => Lecture(
        id: map['id'],
        title: map['title'],
        date: map['date'],
        audioPath: map['audioPath'],
        transcript: map['transcript'] ?? '',
        summary: map['summary'] ?? '',
        durationSeconds: map['durationSeconds'] ?? 0,
      );

  Lecture copyWith({
    String? title,
    String? transcript,
    String? summary,
    int? durationSeconds,
  }) =>
      Lecture(
        id: id,
        title: title ?? this.title,
        date: date,
        audioPath: audioPath,
        transcript: transcript ?? this.transcript,
        summary: summary ?? this.summary,
        durationSeconds: durationSeconds ?? this.durationSeconds,
      );
}
