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
      version: 4,
      onCreate: (db, version) async {
        await _createLecturesTable(db);
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
        timelineJson TEXT DEFAULT ''
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

  Future<List<Lecture>> getAllLectures() async {
    final database = await db;
    final maps = await database.query('lectures', orderBy: 'date DESC');
    return maps.map((m) => Lecture.fromMap(m)).toList();
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

  Future<File> resolveAudioFile(Lecture lecture) async {
    return File(await resolveAudioPath(lecture));
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

  Future<void> deleteLecture(int id) async {
    final database = await db;
    await database.delete('lectures', where: 'id = ?', whereArgs: [id]);
    _emitChange();
  }
}
