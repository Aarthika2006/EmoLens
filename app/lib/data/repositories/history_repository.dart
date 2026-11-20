import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/session.dart';

/// Repository for session history using SQLite.
class HistoryRepository {
  static const String _tableName = 'sessions';
  static const String _dbName = 'emolens_history.db';
  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start_time TEXT NOT NULL,
            end_time TEXT,
            total_frames INTEGER DEFAULT 0,
            happy_count INTEGER DEFAULT 0,
            neutral_count INTEGER DEFAULT 0,
            sad_count INTEGER DEFAULT 0,
            notes TEXT
          )
        ''');
      },
    );
  }

  /// Insert a new session and return its ID.
  Future<int> insertSession(Session session) async {
    final db = await database;
    return await db.insert(_tableName, session.toMap());
  }

  /// Update an existing session.
  Future<void> updateSession(Session session) async {
    if (session.id == null) return;
    final db = await database;
    await db.update(
      _tableName,
      session.toMap(),
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  /// Get all sessions ordered by most recent first.
  Future<List<Session>> getAllSessions() async {
    final db = await database;
    final rows = await db.query(
      _tableName,
      orderBy: 'start_time DESC',
    );
    return rows.map((row) => Session.fromMap(row)).toList();
  }

  /// Get a specific session by ID.
  Future<Session?> getSession(int id) async {
    final db = await database;
    final rows = await db.query(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return Session.fromMap(rows.first);
  }

  /// Delete a session by ID.
  Future<void> deleteSession(int id) async {
    final db = await database;
    await db.delete(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete all sessions.
  Future<void> deleteAll() async {
    final db = await database;
    await db.delete(_tableName);
  }

  /// Get session count.
  Future<int> getSessionCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM $_tableName');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Close the database.
  Future<void> close() async {
    final db = await database;
    await db.close();
    _db = null;
  }
}
