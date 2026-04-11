// lib/services/db_service.dart

import 'dart:async';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/lecture.dart';

class DbService {
  static final DbService _instance = DbService._();
  static Database? _db;
  static const String _dbName = 'lecture_vault.db';
  final StreamController<void> _changesController =
      StreamController<void>.broadcast();

  DbService._();
  factory DbService() => _instance;

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
    final dbPath = await getDatabasesPath();
    return openDatabase(
      join(dbPath, _dbName),
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE lectures (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            date TEXT NOT NULL,
            audioPath TEXT NOT NULL,
            transcript TEXT DEFAULT '',
            summary TEXT DEFAULT '',
            durationSeconds INTEGER DEFAULT 0,
            tag TEXT DEFAULT '',
            timelineJson TEXT DEFAULT ''
          )
        ''');
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
      },
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<void> resetForTests() async {
    await close();
    final dbPath = await getDatabasesPath();
    await deleteDatabase(join(dbPath, _dbName));
  }

  Future<int> insertLecture(Lecture lecture) async {
    final database = await db;
    final id = await database.insert('lectures', lecture.toMap());
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
    await database.update(
      'lectures',
      lecture.toMap(),
      where: 'id = ?',
      whereArgs: [lecture.id],
    );
    _emitChange();
  }

  Future<void> deleteLecture(int id) async {
    final database = await db;
    await database.delete('lectures', where: 'id = ?', whereArgs: [id]);
    _emitChange();
  }
}
