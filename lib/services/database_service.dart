import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/item.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'finbuk.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE items(
            id TEXT,
            name TEXT,
            type TEXT,
            collectionType TEXT,
            parentId TEXT,
            category TEXT,
            json TEXT,
            updatedAt INTEGER,
            PRIMARY KEY (id, category)
          )
        ''');
        await db.execute('''
          CREATE TABLE downloads(
            itemId TEXT PRIMARY KEY,
            filename TEXT,
            downloadedAt INTEGER
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE downloads(
              itemId TEXT PRIMARY KEY,
              filename TEXT,
              downloadedAt INTEGER
            )
          ''');
        }
      },
    );
  }

  Future<void> saveItems(List<Item> items, String category) async {
    final db = await database;
    final batch = db.batch();
    for (var item in items) {
      batch.insert(
        'items',
        item.toDbMap(category),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Item>> getItemsByCategory(
    String category, {
    String? parentId,
  }) async {
    final db = await database;
    String where = 'category = ?';
    List<dynamic> whereArgs = [category];

    if (parentId != null) {
      where += ' AND parentId = ?';
      whereArgs.add(parentId);
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'items',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'updatedAt DESC',
    );

    return List.generate(maps.length, (i) {
      return Item.fromDbMap(maps[i]);
    });
  }

  Future<void> clearCategory(String category, {String? parentId}) async {
    final db = await database;
    String where = 'category = ?';
    List<dynamic> whereArgs = [category];

    if (parentId != null) {
      where += ' AND parentId = ?';
      whereArgs.add(parentId);
    }

    await db.delete('items', where: where, whereArgs: whereArgs);
  }

  Future<Item?> getItemById(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'items',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return Item.fromDbMap(maps[0]);
  }

  Future<Map<String, Item>> getItemsMapByIds(List<String> ids) async {
    if (ids.isEmpty) return {};
    final db = await database;
    const batchSize = 500;
    final Map<String, Item> result = {};
    for (var i = 0; i < ids.length; i += batchSize) {
      final batch = ids.sublist(
        i,
        i + batchSize > ids.length ? ids.length : i + batchSize,
      );
      final placeholders = List.filled(batch.length, '?').join(',');
      final maps = await db.query(
        'items',
        where: 'id IN ($placeholders)',
        whereArgs: batch,
      );
      for (var map in maps) {
        final item = Item.fromDbMap(map);
        result[item.id] = item;
      }
    }
    return result;
  }

  Future<void> saveDownload(String itemId, String filename) async {
    final db = await database;
    await db.insert('downloads', {
      'itemId': itemId,
      'filename': filename,
      'downloadedAt': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getDownload(String itemId) async {
    final db = await database;
    final maps = await db.query(
      'downloads',
      where: 'itemId = ?',
      whereArgs: [itemId],
      limit: 1,
    );
    if (maps.isNotEmpty) return maps.first;
    return null;
  }

  Future<List<Map<String, dynamic>>> getAllDownloads() async {
    final db = await database;
    return await db.query('downloads', orderBy: 'downloadedAt DESC');
  }

  Future<void> deleteDownload(String itemId) async {
    final db = await database;
    await db.delete('downloads', where: 'itemId = ?', whereArgs: [itemId]);
  }
}
