// =====================================================================
// 数据库帮助类（存储层）
// ---------------------------------------------------------------------
// 这层是什么：整个 App 唯一「直接跟 SQLite 说话」的地方。
// 它负责：打开数据库 → 建表 → 提供增删改查的方法。
// 界面层（pages）和数据层（store）都不直接写 SQL，而是调用这里的方法，
// 这样 SQL 集中在一处，以后要改表结构只动这一个文件。
//
// 语言：Dart（星禾口语没有前后端之分，整个 App 都是 Dart。
//       这里的「数据库接口」= App 代码 ↔ SQLite 的读写，通过 sqflite 库完成）。
// =====================================================================

import 'dart:io';

import 'package:path/path.dart' as p; // 用 p.join() 拼接路径，兼容安卓/Windows 不同的路径分隔符
import 'package:path_provider/path_provider.dart'; // 拿到 App 的私有目录
import 'package:sqflite/sqflite.dart'; // SQLite 数据库库

/// 数据库帮助类：单例（整个 App 只用一个数据库实例）
class DatabaseHelper {
  // 私有构造，禁止外部 new，只能通过下面的 instance 拿同一个实例
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _db;

  /// 数据库名和版本号
  static const String _dbName = 'xinghe_kouyu.db';
  static const int _dbVersion = 1;

  /// 拿到数据库实例（没打开就先打开）
  Future<Database> get database async {
    if (_db != null) return _db!; // 已经打开过就直接复用，不重复开

    _db = await _open();
    return _db!;
  }

  /// 打开（或首次创建）数据库，并建表
  Future<Database> _open() async {
    // 1. 拿到 App 的私有目录（安卓上是 /data/data/com.xinghe.kouyu/... 这种，
    //    用户看不到、别的 App 也碰不到，素材放这里最安全）
    final Directory dir = await getApplicationDocumentsDirectory();
    // 2. 拼接数据库文件的完整路径
    final String path = p.join(dir.path, _dbName);

    // 3. 打开数据库：如果文件不存在会自动创建；
    //    onCreate 回调只在「第一次创建」时触发一次，用来建表
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
    );
  }

  /// 第一次建库时执行：创建两张表
  Future<void> _onCreate(Database db, int version) async {
    // 文件夹表：id 主键，name 文件夹名（重命名就改这里）
    await db.execute('''
      CREATE TABLE folders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL
      )
    ''');

    // 素材表：folder_id 是外键，指向 folders.id
    // 用「文件夹的 id」而不是「文件夹的名字」来关联 ——
    // 这样以后文件夹改名，素材的归属自动跟着变，不用逐条改素材
    await db.execute('''
      CREATE TABLE materials (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        folder_id INTEGER NOT NULL,
        format TEXT NOT NULL,
        file_path TEXT NOT NULL,
        duration TEXT,
        FOREIGN KEY (folder_id) REFERENCES folders(id)
      )
    ''');
  }

  // ===================================================================
  // 下面是「增删改查」的方法，界面层/数据层调这些，而不是自己拼 SQL
  // ===================================================================

  /// 查：返回所有文件夹（按 id 排序，保持建文件夹的先后顺序）
  Future<List<Map<String, Object?>>> queryAllFolders() async {
    final Database db = await database;
    return db.query('folders', orderBy: 'id ASC');
  }

  /// 增：新建一个文件夹，返回它的 id
  Future<int> insertFolder(String name) async {
    final Database db = await database;
    return db.insert('folders', {'name': name});
  }

  /// 改：重命名文件夹（按 id 定位）
  Future<void> renameFolder(int id, String newName) async {
    final Database db = await database;
    await db.update(
      'folders',
      {'name': newName},
      where: 'id = ?', // ? 是占位符，防止 SQL 注入；后面的参数按顺序填入
      whereArgs: [id],
    );
  }

  /// 删：删除文件夹（连同它下面的素材一起删）
  Future<void> deleteFolder(int id) async {
    final Database db = await database;
    // 先删该文件夹下的素材，再删文件夹本身（顺序不能反，否则外键约束报错）
    await db.delete('materials', where: 'folder_id = ?', whereArgs: [id]);
    await db.delete('folders', where: 'id = ?', whereArgs: [id]);
  }

  /// 查：返回所有素材（按 id 排序）
  Future<List<Map<String, Object?>>> queryAllMaterials() async {
    final Database db = await database;
    return db.query('materials', orderBy: 'id ASC');
  }

  /// 增：插入一条素材记录，返回它的 id
  Future<int> insertMaterial({
    required String title,
    required int folderId,
    required String format,
    required String filePath,
    String? duration,
  }) async {
    final Database db = await database;
    return db.insert('materials', {
      'title': title,
      'folder_id': folderId,
      'format': format,
      'file_path': filePath,
      'duration': duration,
    });
  }

  /// 改：把素材移动到另一个文件夹
  Future<void> moveMaterial(int materialId, int newFolderId) async {
    final Database db = await database;
    await db.update(
      'materials',
      {'folder_id': newFolderId},
      where: 'id = ?',
      whereArgs: [materialId],
    );
  }

  /// 改：重命名素材（只改 title 字段，文件本身不动）
  Future<void> renameMaterial(int materialId, String newName) async {
    final Database db = await database;
    await db.update(
      'materials',
      {'title': newName},
      where: 'id = ?',
      whereArgs: [materialId],
    );
  }

  /// 删：删除一条素材
  Future<void> deleteMaterial(int materialId) async {
    final Database db = await database;
    await db.delete('materials', where: 'id = ?', whereArgs: [materialId]);
  }
}
