// lib/services/db_service.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/lecture.dart';

class DbService {
  static final DbService _instance = DbService._();
  static Database? _db;

  DbService._();
  factory DbService() => _instance;

  Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      join(dbPath, 'lecture_vault.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE lectures (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            date TEXT NOT NULL,
            audioPath TEXT NOT NULL,
            transcript TEXT DEFAULT '',
            summary TEXT DEFAULT '',
            durationSeconds INTEGER DEFAULT 0
          )
        ''');
      },
    );
  }

  Future<int> insertLecture(Lecture lecture) async {
    final database = await db;
    return database.insert('lectures', lecture.toMap());
  }

  Future<List<Lecture>> getAllLectures() async {
    final database = await db;
    final maps = await database.query('lectures', orderBy: 'date DESC');
    return maps.map((m) => Lecture.fromMap(m)).toList();
  }

  Future<void> updateLecture(Lecture lecture) async {
    final database = await db;
    await database.update(
      'lectures',
      lecture.toMap(),
      where: 'id = ?',
      whereArgs: [lecture.id],
    );
  }

  Future<void> deleteLecture(int id) async {
    final database = await db;
    await database.delete('lectures', where: 'id = ?', whereArgs: [id]);
  }
}
