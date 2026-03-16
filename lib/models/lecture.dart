class Lecture {
  final int? id;
  final String title;
  final String date;
  final String audioPath;
  final String transcript;
  final String summary;
  final int durationSeconds;
  final String tag;

  Lecture({
    this.id,
    required this.title,
    required this.date,
    required this.audioPath,
    this.transcript = '',
    this.summary = '',
    this.durationSeconds = 0,
    this.tag = '一般',
  });

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
    );
  }
}