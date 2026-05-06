// lib/services/db_service.dart

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/lecture.dart';

class DbService {
  static final DbService _instance = DbService._();
  static Database? _db;
  static const String databaseName = 'lecture_vault.db';
  static const List<String> _lectureColumnsWithoutEmbedding = [
    'id',
    'uid',
    'title',
    'date',
    'audioPath',
    'managedAudioPath',
    'transcript',
    'summary',
    'transcriptionStatus',
    'summaryStatus',
    'durationSeconds',
    'tag',
    'tagsJson',
    'timelineJson',
  ];
  final StreamController<void> _changesController =
      StreamController<void>.broadcast();
  final Future<Directory> Function() _documentsDirectory;
  final Future<String> Function()? _databasePathResolver;
  final Random _random;

  DbService._({
    Future<Directory> Function()? documentsDirectory,
    Future<String> Function()? databasePathResolver,
    Random? random,
  })  : _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory,
        _databasePathResolver = databasePathResolver,
        _random = random ?? Random.secure();

  factory DbService({
    Future<Directory> Function()? documentsDirectory,
    Future<String> Function()? databasePathResolver,
    Random? random,
  }) {
    if (documentsDirectory == null &&
        databasePathResolver == null &&
        random == null) {
      return _instance;
    }
    return DbService._(
      documentsDirectory: documentsDirectory,
      databasePathResolver: databasePathResolver,
      random: random,
    );
  }

  Stream<void> get changes => _changesController.stream;

  void _emitChange() {
    if (!_changesController.isClosed) {
      _changesController.add(null);
    }
  }

  Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    return openDatabase(
      await getDatabasePath(),
      version: 7,
      onCreate: (db, version) async {
        await _createLecturesTable(db);
        await _createLectureIndexes(db);
        await _createAppSettingsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE lectures ADD COLUMN tag TEXT DEFAULT ""',
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE lectures ADD COLUMN timelineJson TEXT DEFAULT ""',
          );
        }
        if (oldVersion < 4) {
          await db.execute(
            'ALTER TABLE lectures ADD COLUMN uid TEXT NOT NULL DEFAULT ""',
          );
          await db.execute(
            'ALTER TABLE lectures ADD COLUMN transcriptionStatus TEXT NOT NULL DEFAULT ""',
          );
          await db.execute(
            'ALTER TABLE lectures ADD COLUMN summaryStatus TEXT NOT NULL DEFAULT ""',
          );
          await db.execute(
            'ALTER TABLE lectures ADD COLUMN managedAudioPath TEXT DEFAULT ""',
          );
          await db.execute(
            "UPDATE lectures SET uid = 'legacy-' || id WHERE uid = ''",
          );
          await _createAppSettingsTable(db);
        }
        if (oldVersion < 5) {
          await db.execute(
            'ALTER TABLE lectures ADD COLUMN tagsJson TEXT DEFAULT ""',
          );
        }
        if (oldVersion < 6) {
          await db.execute(
            'ALTER TABLE lectures ADD COLUMN embeddingJson TEXT',
          );
        }
        if (oldVersion < 7) {
          await _createLectureIndexes(db);
        }
      },
    );
  }

  Future<void> _createLecturesTable(Database db) async {
    await db.execute('''
      CREATE TABLE lectures (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uid TEXT NOT NULL,
        title TEXT NOT NULL,
        date TEXT NOT NULL,
        audioPath TEXT NOT NULL,
        managedAudioPath TEXT DEFAULT '',
        transcript TEXT DEFAULT '',
        summary TEXT DEFAULT '',
        transcriptionStatus TEXT NOT NULL DEFAULT 'pending',
        summaryStatus TEXT NOT NULL DEFAULT 'pending',
        durationSeconds INTEGER DEFAULT 0,
        tag TEXT DEFAULT '',
        tagsJson TEXT DEFAULT '',
        timelineJson TEXT DEFAULT '',
        embeddingJson TEXT
      )
    ''');
  }

  Future<void> _createAppSettingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createLectureIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_lectures_date_desc ON lectures(date DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_lectures_managed_audio_path ON lectures(managedAudioPath)',
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<String> getDatabasePath() async {
    if (_db != null) {
      return _db!.path;
    }
    if (_databasePathResolver != null) {
      return _databasePathResolver();
    }
    final dbPath = await getDatabasesPath();
    return join(dbPath, databaseName);
  }

  Future<void> resetForTests() async {
    await close();
    final dbPath = await getDatabasesPath();
    await deleteDatabase(join(dbPath, databaseName));
  }

  Future<int> insertLecture(Lecture lecture) async {
    final database = await db;
    final lectureToPersist = _prepareLectureForPersistence(lecture);
    final id = await database.insert('lectures', lectureToPersist.toMap());
    _emitChange();
    return id;
  }

  Future<List<Lecture>> getAllLectures({bool includeEmbeddings = true}) async {
    final database = await db;
    final maps = await database.query(
      'lectures',
      columns: includeEmbeddings ? null : _lectureColumnsWithoutEmbedding,
      orderBy: 'date DESC',
    );
    return maps
        .map((m) => Lecture.fromMap(m, includeEmbedding: includeEmbeddings))
        .toList();
  }

  /// 語義搜尋：計算相似度並排序
  Future<List<Lecture>> searchLecturesBySimilarity(
    List<double> queryVector, {
    double threshold = 0.3,
  }) async {
    if (queryVector.isEmpty) return const [];

    final database = await db;
    final maps = await database.query(
      'lectures',
      where: "embeddingJson IS NOT NULL AND TRIM(embeddingJson) <> ''",
    );
    final results = <MapEntry<Lecture, double>>[];

    for (final map in maps) {
      final emb = Lecture.parseEmbeddingJson(map['embeddingJson']);
      if (emb == null || emb.length != queryVector.length) continue;

      // 計算點積 (Cosine Similarity，因為我們儲存的是單位向量)
      double score = 0.0;
      for (int i = 0; i < queryVector.length; i++) {
        score += queryVector[i] * emb[i];
      }

      if (score >= threshold) {
        results.add(
          MapEntry(
            Lecture.fromMap(map, includeEmbedding: false),
            score,
          ),
        );
      }
    }

    // 按分數由高到低排序
    results.sort((a, b) => b.value.compareTo(a.value));
    return results.map((e) => e.key).toList();
  }

  Future<Set<String>> getManagedAudioPaths() async {
    final database = await db;
    final maps = await database.query(
      'lectures',
      columns: const ['managedAudioPath'],
      where: "managedAudioPath IS NOT NULL AND TRIM(managedAudioPath) <> ''",
    );

    return maps
        .map((map) => (map['managedAudioPath'] as String? ?? '').trim())
        .where((path) => path.isNotEmpty)
        .toSet();
  }

  Future<Lecture?> getLectureById(int id) async {
    final database = await db;
    final maps = await database.query(
      'lectures',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Lecture.fromMap(maps.first);
  }

  Future<void> updateLecture(Lecture lecture) async {
    final database = await db;
    final lectureToPersist = _prepareLectureForPersistence(lecture);
    await database.update(
      'lectures',
      lectureToPersist.toMap(),
      where: 'id = ?',
      whereArgs: [lecture.id],
    );
    _emitChange();
  }

  Future<void> updateLectureTag(String oldTag, String newTag) async {
    final database = await db;
    final cleanOld = oldTag.trim();
    final cleanNew = newTag.trim();
    if (cleanOld == cleanNew || cleanNew.isEmpty) return;

    // 1. 更新舊有的 legacy 'tag' 欄位
    await database.update(
      'lectures',
      {'tag': cleanNew},
      where: 'tag = ?',
      whereArgs: [cleanOld],
    );

    // 2. 更新 tagsJson - 使用 LIKE 進行初步過濾以應對大數據集
    final maps = await database.query(
      'lectures',
      where: 'tagsJson LIKE ?',
      whereArgs: ['%$cleanOld%'],
    );

    if (maps.isNotEmpty) {
      final batch = database.batch();
      for (final m in maps) {
        final lecture = Lecture.fromMap(m);
        if (lecture.tags.contains(cleanOld)) {
          final newTags =
              lecture.tags.map((t) => t == cleanOld ? cleanNew : t).toList();
          final updated = lecture.copyWith(tags: newTags);
          batch.update(
            'lectures',
            updated.toMap(),
            where: 'id = ?',
            whereArgs: [lecture.id],
          );
        }
      }
      await batch.commit(noResult: true);
    }
    _emitChange();
  }

  Lecture _prepareLectureForPersistence(Lecture lecture) {
    if (lecture.uid.trim().isNotEmpty) {
      return lecture;
    }
    return lecture.copyWith(uid: _generateLectureUid());
  }

  String _generateLectureUid() {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final randomPart =
        _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return 'lec_${micros}_$randomPart';
  }

  Future<String> resolveAudioPath(Lecture lecture) async {
    final relativePath = lecture.managedAudioPath.trim();

    if (relativePath.isEmpty) {
      return lecture.audioPath;
    }

    final documentsDirectory = await _documentsDirectory();
    return normalize(join(documentsDirectory.path, relativePath));
  }

  Future<String> resolveSafeAudioPath(Lecture lecture) async {
    final managedAudioDirectory = await getManagedAudioDirectory();
    final managedAudioRoot = normalize(managedAudioDirectory.path);
    final relativePath = lecture.managedAudioPath.trim();

    if (relativePath.isNotEmpty) {
      final documentsDirectory = await _documentsDirectory();
      final resolvedManagedPath =
          normalize(join(documentsDirectory.path, relativePath));
      if (_isPathWithinRoot(managedAudioRoot, resolvedManagedPath)) {
        return resolvedManagedPath;
      }
      throw StateError('Lecture audio path is outside managed storage.');
    }

    final normalizedAudioPath = normalize(lecture.audioPath);
    if (_isPathWithinRoot(managedAudioRoot, normalizedAudioPath)) {
      return normalizedAudioPath;
    }
    throw StateError('Lecture audio path is outside managed storage.');
  }

  Future<File> resolveAudioFile(Lecture lecture) async {
    return File(await resolveAudioPath(lecture));
  }

  Future<File> resolveSafeAudioFile(Lecture lecture) async {
    return File(await resolveSafeAudioPath(lecture));
  }

  Future<Directory> getDocumentsDirectory() async {
    return _documentsDirectory();
  }

  Future<File> getDatabaseFile() async {
    return File(await getDatabasePath());
  }

  Future<Directory> getManagedAudioDirectory() async {
    final documentsDirectory = await _documentsDirectory();
    return Directory(join(documentsDirectory.path, 'media', 'audio'));
  }

  void notifyExternalDataMutation() {
    _emitChange();
  }

  Future<void> deleteLecture(Lecture lecture) async {
    final id = lecture.id;
    if (id == null) {
      return;
    }

    final database = await db;
    await database.delete('lectures', where: 'id = ?', whereArgs: [id]);

    final deletionTarget = await _resolveDeletionTarget(lecture);
    if (deletionTarget == null) {
      _emitChange();
      return;
    }

    try {
      if (await deletionTarget.exists()) {
        await deletionTarget.delete();
      }
    } on FileSystemException {
      // Ignore missing or concurrently removed audio files after the row is gone.
    }

    _emitChange();
  }

  Future<File?> _resolveDeletionTarget(Lecture lecture) async {
    if (lecture.managedAudioPath.trim().isEmpty) {
      return null;
    }

    final managedAudioDirectory = await getManagedAudioDirectory();
    final managedAudioRoot = normalize(managedAudioDirectory.path);

    final resolvedManagedPath = await resolveAudioPath(lecture);
    if (_isPathWithinRoot(managedAudioRoot, resolvedManagedPath)) {
      return File(resolvedManagedPath);
    }
    return null;
  }

  bool _isPathWithinRoot(String rootPath, String candidatePath) {
    final relativePath = relative(candidatePath, from: rootPath);
    return relativePath != '..' &&
        !relativePath.startsWith('..${Platform.pathSeparator}');
  }
}
