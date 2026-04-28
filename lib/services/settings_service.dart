import 'package:sqflite/sqflite.dart';

import '../models/app_setting.dart';
import 'db_service.dart';

class SettingsService {
  SettingsService({DbService? dbService})
      : _dbService = dbService ?? DbService();

  final DbService _dbService;

  Future<void> saveSetting(AppSetting setting) async {
    final database = await _dbService.db;
    await database.insert(
      'app_settings',
      setting.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<AppSetting?> getSetting(String key) async {
    final database = await _dbService.db;
    final rows = await database.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return AppSetting.fromMap(rows.first);
  }

  Future<String?> getValue(String key) async {
    final setting = await getSetting(key);
    return setting?.value;
  }

  Future<List<AppSetting>> getAllSettings() async {
    final database = await _dbService.db;
    final rows = await database.query('app_settings', orderBy: 'key ASC');
    return rows.map(AppSetting.fromMap).toList(growable: false);
  }

  Future<void> deleteSetting(String key) async {
    final database = await _dbService.db;
    await database.delete(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
    );
  }
}
