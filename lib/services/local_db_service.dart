import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalDbService {
  static Database? _database;
  static const String _dbName = 'cobalto_edge.db';
  static const int _dbVersion = 1;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE local_entries (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            source TEXT NOT NULL,
            summary TEXT,
            published TEXT,
            link TEXT,
            image TEXT,
            timestamp TEXT,
            keywords_matched TEXT,
            relevance_score INTEGER,
            type TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE local_alerts (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            severity TEXT NOT NULL,
            category TEXT,
            description TEXT,
            timestamp TEXT,
            is_read INTEGER DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE field_reports (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            description TEXT,
            threat_level TEXT NOT NULL,
            lat REAL,
            lng REAL,
            image_path TEXT,
            timestamp TEXT NOT NULL,
            synced INTEGER DEFAULT 0
          )
        ''');
      },
    );
  }

  // ── ENTRIES (Noticias / SITREP local) ──

  static Future<int> insertEntries(List<Map<String, dynamic>> entries) async {
    try {
      final db = await database;
      final batch = db.batch();
      for (final entry in entries) {
        final title = entry['title'] ?? '';
        if (title.isEmpty) continue;

        final id = entry['id'] ?? title.hashCode.toString();
        final kwList = entry['keywords_matched'] is List
            ? json.encode(entry['keywords_matched'])
            : (entry['keywords_matched']?.toString() ?? '[]');

        batch.insert(
          'local_entries',
          {
            'id': id.toString(),
            'title': title,
            'source': entry['source'] ?? 'Local',
            'summary': entry['summary'] ?? '',
            'published': entry['published'] ?? '',
            'link': entry['link'] ?? '',
            'image': entry['image'] ?? '',
            'timestamp': entry['timestamp'] ?? DateTime.now().toIso8601String(),
            'keywords_matched': kwList,
            'relevance_score': entry['relevance_score'] ?? 50,
            'type': entry['type'] ?? 'rss',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      final results = await batch.commit();

      // Respaldar también en SharedPreferences para máxima compatibilidad
      await _syncSharedPreferences(entries);

      return results.length;
    } catch (e) {
      // Fallback a SharedPreferences si SQLite falla en un entorno embebido
      await _syncSharedPreferences(entries);
      return entries.length;
    }
  }

  static Future<List<Map<String, dynamic>>> getEntries({int limit = 100}) async {
    try {
      final db = await database;
      final maps = await db.query(
        'local_entries',
        orderBy: 'timestamp DESC',
        limit: limit,
      );
      return maps.map((map) {
        final Map<String, dynamic> mutable = Map.from(map);
        if (mutable['keywords_matched'] != null) {
          try {
            mutable['keywords_matched'] = json.decode(mutable['keywords_matched'].toString());
          } catch (_) {
            mutable['keywords_matched'] = [];
          }
        }
        return mutable;
      }).toList();
    } catch (e) {
      // Fallback a SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString('cached_sitrep_news');
      if (str != null && str.isNotEmpty) {
        try {
          final decoded = json.decode(str);
          if (decoded is List) return List<Map<String, dynamic>>.from(decoded);
        } catch (_) {}
      }
      return [];
    }
  }

  // ── FIELD REPORTS (HUMINT Móvil) ──

  static Future<void> saveFieldReport(Map<String, dynamic> report) async {
    try {
      final db = await database;
      await db.insert(
        'field_reports',
        {
          'id': report['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
          'title': report['title'] ?? 'Reporte de Campo',
          'description': report['description'] ?? '',
          'threat_level': report['threat_level'] ?? 'ELEVATED',
          'lat': report['lat'] ?? 0.0,
          'lng': report['lng'] ?? 0.0,
          'image_path': report['image_path'] ?? '',
          'timestamp': report['timestamp'] ?? DateTime.now().toIso8601String(),
          'synced': report['synced'] == true ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString('local_field_reports');
      List<dynamic> list = [];
      if (str != null && str.isNotEmpty) {
        try {
          list = json.decode(str);
        } catch (_) {}
      }
      list.insert(0, report);
      await prefs.setString('local_field_reports', json.encode(list));
    }
  }

  static Future<List<Map<String, dynamic>>> getFieldReports() async {
    try {
      final db = await database;
      final maps = await db.query('field_reports', orderBy: 'timestamp DESC');
      return maps.map((m) => Map<String, dynamic>.from(m)).toList();
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString('local_field_reports');
      if (str != null && str.isNotEmpty) {
        try {
          final decoded = json.decode(str);
          if (decoded is List) return List<Map<String, dynamic>>.from(decoded);
        } catch (_) {}
      }
      return [];
    }
  }

  // ── MANTENIMIENTO ──

  static Future<void> purgeOldData({int maxDays = 30}) async {
    try {
      final db = await database;
      final cutoff = DateTime.now().subtract(Duration(days: maxDays)).toIso8601String();
      await db.delete('local_entries', where: 'timestamp < ?', whereArgs: [cutoff]);
      await db.delete('local_alerts', where: 'timestamp < ?', whereArgs: [cutoff]);
    } catch (_) {}
  }

  static Future<void> _syncSharedPreferences(List<Map<String, dynamic>> entries) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingStr = prefs.getString('cached_sitrep_news');
      List<dynamic> combined = [];
      if (existingStr != null && existingStr.isNotEmpty) {
        try {
          combined = json.decode(existingStr);
        } catch (_) {}
      }
      final Set<String> existingTitles = combined.map((e) => (e['title'] ?? '').toString()).toSet();
      for (final newEntry in entries) {
        final t = (newEntry['title'] ?? '').toString();
        if (t.isNotEmpty && !existingTitles.contains(t)) {
          combined.insert(0, newEntry);
          existingTitles.add(t);
        }
      }
      if (combined.length > 200) combined = combined.sublist(0, 200);
      await prefs.setString('cached_sitrep_news', json.encode(combined));
    } catch (_) {}
  }
}
