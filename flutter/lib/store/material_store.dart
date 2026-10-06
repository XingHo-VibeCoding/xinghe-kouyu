// =====================================================================
// 素材仓库（数据层核心，Provider 模式的状态中枢）
// ---------------------------------------------------------------------
// 这层是什么：承上启下。上面给界面层（pages）提供状态和操作；
// 下面调用存储层（DatabaseHelper）去读写 SQLite。
// 它不写 SQL，也不画界面，只负责「业务状态 + 转发数据操作」。
//
// 语言：Dart。它和数据库的沟通方式：调用 DatabaseHelper 里封装好的方法，
//       由 DatabaseHelper 去执行真正的 SQL。
// =====================================================================

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/database_helper.dart';
import '../models/material_item.dart';

/// 列表的四种状态：加载中 / 空 / 错误 / 正常有数据
enum ListStatus { loading, empty, error, data }

/// 一个文件夹
class Folder {
  final int id;
  final String name;
  const Folder({required this.id, required this.name});

  /// 从数据库查出来的一行转成 Folder 对象
  factory Folder.fromMap(Map<String, Object?> map) {
    return Folder(id: map['id'] as int, name: map['name'] as String);
  }
}

/// 素材仓库：页面通过 Provider 读写这里的 status / items / folders
class MaterialStore extends ChangeNotifier {
  ListStatus _status = ListStatus.loading;
  ListStatus get status => _status;

  final List<MaterialItem> _items = <MaterialItem>[];
  List<MaterialItem> get items => List.unmodifiable(_items);

  final List<Folder> _folders = <Folder>[];
  List<Folder> get folders => List.unmodifiable(_folders);

  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  /// 加载素材和文件夹（真实从 SQLite 读）
  /// 打开 App 时调用一次，之后每次增删改后也调用刷新
  Future<void> load() async {
    _status = ListStatus.loading; // 先进入「加载中」
    notifyListeners();

    try {
      // 同时读两张表：素材 + 文件夹（真实 SQL，不再是假数据）
      final List<Map<String, Object?>> materialRows =
          await DatabaseHelper.instance.queryAllMaterials();
      final List<Map<String, Object?>> folderRows =
          await DatabaseHelper.instance.queryAllFolders();

      _items
        ..clear()
        ..addAll(materialRows.map(MaterialItem.fromMap));
      _folders
        ..clear()
        ..addAll(folderRows.map(Folder.fromMap));

      // 读出来的素材是否为空，决定显示「空」还是「有数据」
      _status = _items.isEmpty ? ListStatus.empty : ListStatus.data;
    } catch (e) {
      _errorMessage = '读取素材失败：$e';
      _status = ListStatus.error;
    }
    notifyListeners();
  }

  /// 新建文件夹，成功后刷新列表
  Future<void> addFolder(String name) async {
    await DatabaseHelper.instance.insertFolder(name);
    await load();
  }

  /// 重命名文件夹
  Future<void> renameFolder(int id, String newName) async {
    await DatabaseHelper.instance.renameFolder(id, newName);
    await load();
  }

  /// 删除文件夹（连同其下素材）
  Future<void> deleteFolder(int id) async {
    await DatabaseHelper.instance.deleteFolder(id);
    await load();
  }

  /// 新增一条素材（板块③导入时用）
  Future<void> addMaterial({
    required String title,
    required int folderId,
    required String format,
    required String filePath,
  }) async {
    await DatabaseHelper.instance.insertMaterial(
      title: title,
      folderId: folderId,
      format: format,
      filePath: filePath,
    );
    await load();
  }

  /// 【数据导入】从系统文件选择器挑一个音视频文件，导入到指定文件夹。
  /// 完整链路分三步（对应「选文件 → 复制进仓库 → 写库」）：
  ///   1. file_picker 调起系统文件选择器，拿到用户选的文件的原始路径；
  ///   2. 把文件复制一份到 App 私有目录（这样微信/下载目录的原文件被清理后，
  ///      我们这儿的拷贝还在，素材不会丢）；
  ///   3. 把「标题、所属文件夹、格式、私有目录里的新路径」写进 SQLite。
  /// 返回 null 表示用户取消；返回标题字符串表示成功。出错时抛出异常，由界面层接住提示。
  Future<String?> importMaterial(int folderId) async {
    // —— 第一步：调起文件选择器（限定音视频格式，单文件）——
    // 注：file_picker 13.x 起 API 变为静态方法 FilePicker.pickFiles，返回 List<PlatformFile>；
    //     用户取消时返回空列表（不再有 FilePickerResult 类型）。
    final List<PlatformFile> files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['mp3', 'm4a', 'wav', 'aac', 'mp4', 'mov', 'webm', 'm4v'],
    );
    // 用户没选（空列表）就返回 null，界面层据此不做任何事
    if (files.isEmpty) return null;

    // 原始文件路径（安卓上是从系统文件选择器拿到的 content:// 或 file:// 路径）
    final PlatformFile picked = files.first;
    final String? srcPath = picked.path;
    if (srcPath == null) {
      throw Exception('无法读取所选文件路径');
    }

    // 从文件名里拆出「标题」和「格式扩展名」（如 lesson1.mp3 → 标题 lesson1、格式 mp3）
    final String fileName = picked.name;
    final String ext = p.extension(fileName).replaceFirst('.', '').toLowerCase();
    final String title = p.basenameWithoutExtension(fileName);

    // —— 第二步：复制到 App 私有目录 ——
    // 先确保 App 的「素材仓库」目录存在（不存在就建）
    final Directory appDir = await getApplicationDocumentsDirectory();
    final Directory materialDir = Directory(p.join(appDir.path, 'materials'));
    if (!await materialDir.exists()) {
      await materialDir.create(recursive: true);
    }
    // 目标文件名带上时间戳，避免同名文件互相覆盖
    final String destPath = p.join(
      materialDir.path,
      '${DateTime.now().millisecondsSinceEpoch}_$fileName',
    );
    await File(srcPath).copy(destPath);

    // —— 第三步：写库 + 刷新列表 ——
    await addMaterial(
      title: title,
      folderId: folderId,
      format: ext.isEmpty ? 'unknown' : ext,
      filePath: destPath,
    );
    return title;
  }

  /// 把素材移动到另一个文件夹
  Future<void> moveMaterial(int materialId, int newFolderId) async {
    await DatabaseHelper.instance.moveMaterial(materialId, newFolderId);
    await load();
  }

  /// 重命名素材（带后缀保护：用户没打后缀时自动补原格式后缀）
  /// 规则沿用 PWA 版：新名不含 `.` 就拼上原格式扩展名；含 `.` 原样保留。
  Future<void> renameMaterial(MaterialItem item, String newName) async {
    String finalName = newName.trim();
    if (finalName.isEmpty) return; // 空名不做任何事，交给界面层拦截

    // 后缀保护：只有「用户没手动写后缀」时才补（判断标准：名字里有没有 `.`）
    if (!finalName.contains('.')) {
      finalName = '$finalName.${item.format}';
    }
    await DatabaseHelper.instance.renameMaterial(item.id, finalName);
    await load();
  }

  /// 删除素材（连带删除 App 私有目录里的拷贝文件，不留孤儿文件）
  /// 顺序：先删文件、后删数据库记录；任一步失败都抛异常由界面层提示。
  Future<void> deleteMaterial(MaterialItem item) async {
    // 1. 删本地文件（filePath 是导入时复制的带时间戳路径）
    final File file = File(item.filePath);
    if (await file.exists()) {
      await file.delete();
    }
    // 2. 删数据库记录
    await DatabaseHelper.instance.deleteMaterial(item.id);
    await load();
  }

  /// 根据文件夹 id 找出文件夹名字（界面显示用）
  String folderNameOf(int folderId) {
    for (final Folder f in _folders) {
      if (f.id == folderId) return f.name;
    }
    return '未分类';
  }

  /// 【开发用】直接把状态拨到某一档，配合底部状态预览条逐个截图。
  /// 现在数据是真实的，「空/有数据」本来就会随真实数据自然出现；
  /// 这个方法只用于强制预览「出错」这类平时难触发的状态，上线前会随预览条一起删。
  void preview(ListStatus target) {
    _status = target;
    if (target == ListStatus.error && _errorMessage.isEmpty) {
      _errorMessage = '预览错误：这是开发用假错误，不是真的坏了';
    }
    notifyListeners();
  }
}
