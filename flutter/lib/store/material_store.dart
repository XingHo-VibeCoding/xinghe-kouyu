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

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/database_helper.dart';
import '../models/material_item.dart';

/// 列表的四种状态：加载中 / 空 / 错误 / 正常有数据
enum ListStatus { loading, empty, error, data }

/// 一次「批量导入」的结果
/// ---------------------------------------------------------------------
/// 为什么要有这个类：用户一次勾了 10 个文件，界面不能只说「已导入」，
/// 得说清「成了几个 / 跳过几个（非音视频）/ 哪几个失败、为什么」。
/// imported = 成功写进库的条数；skipped = 不是音视频被忽略的条数；
/// failures = 失败明细（文件名 + 原因），一条一个人看得懂的字符串。
class ImportResult {
  final int imported;
  final int skipped;
  final List<String> failures;

  const ImportResult({
    required this.imported,
    required this.skipped,
    this.failures = const <String>[],
  });

  /// 拼一句给用户看的汇总（避免每个页面各写一套文案）
  String summary(String folderName) {
    final StringBuffer sb = StringBuffer();
    if (imported > 0) {
      sb.write('已导入 $imported 个素材到「$folderName」');
    } else {
      sb.write('没有导入任何素材');
    }
    if (skipped > 0) sb.write('，$skipped 个非音视频已忽略');
    if (failures.isNotEmpty) sb.write('，${failures.length} 个失败');
    return sb.toString();
  }
}

/// 文件夹重名异常：名字重复时抛它，界面层直接把 toString() 给用户看
/// ---------------------------------------------------------------------
/// 为什么要自定义类型而不是抛 Exception('...')：
/// 默认的 Exception 打印出来会带「Exception: 」前缀，提示语会变丑。
/// 这里让 toString() 直接是一句人话，界面层不用专门判断类型也能用好它。
class DuplicateFolderNameException implements Exception {
  final String name;
  const DuplicateFolderNameException(this.name);

  @override
  String toString() => '「$name」这个文件夹已经存在了';
}

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

  /// 新建文件夹，成功后刷新列表。
  /// 名字（去掉首尾空格后）已存在则抛 DuplicateFolderNameException，不建重复的。
  /// 为什么在这里拦：新建入口有三处（列表页导入弹窗、文件夹管理页、将来的其他入口），
  /// 放数据层拦一次，三处都拦得住，不会有人漏写。
  Future<void> addFolder(String name) async {
    final String trimmed = name.trim();
    if (_folders.any((Folder f) => f.name == trimmed)) {
      throw DuplicateFolderNameException(trimmed);
    }
    await DatabaseHelper.instance.insertFolder(trimmed);
    await load();
  }

  /// 重命名文件夹（同样拦重名，但要排除自己——改成原名不算重复）
  Future<void> renameFolder(int id, String newName) async {
    final String trimmed = newName.trim();
    if (_folders.any((Folder f) => f.id != id && f.name == trimmed)) {
      throw DuplicateFolderNameException(trimmed);
    }
    await DatabaseHelper.instance.renameFolder(id, trimmed);
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

  /// App 认可的素材扩展名（和文件选择器的过滤条件保持一致）
  static const Set<String> kMediaExtensions = <String>{
    'mp3', 'm4a', 'wav', 'aac', 'mp4', 'mov', 'webm', 'm4v',
  };

  /// 【数据导入】从系统文件选择器挑选**一个或多个**音视频文件，全部导入到指定文件夹。
  /// 完整链路分三步（对应「选文件 → 复制进仓库 → 写库」）：
  ///   1. file_picker 调起系统文件选择器（13.x 的 pickFiles 本身允许多选）；
  ///   2. 逐个把文件复制一份到 App 私有目录（微信/下载目录的原文件被清理后，拷贝还在）；
  ///   3. 逐个把元数据写进 SQLite，**整批只刷新一次列表**（10 个文件刷新 10 次会明显卡顿）。
  /// 返回 null = 用户取消（一个文件都没选）；否则返回 ImportResult 汇总。
  /// 单个文件失败不会中断整批——把失败原因记进 failures，其余照常导入（沿用 PWA 版行为）。
  Future<ImportResult?> importMaterials(int folderId) async {
    // —— 第一步：调起文件选择器（限定音视频格式；13.x 起为静态方法、天然多选）——
    final List<PlatformFile> files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: kMediaExtensions.toList(),
    );
    // 用户没选（空列表）就返回 null，界面层据此显示「已取消导入」
    if (files.isEmpty) return null;

    // —— 第二步预备：素材仓库目录只确保一次（不再每个文件判断一遍）——
    final Directory appDir = await getApplicationDocumentsDirectory();
    final Directory materialDir = Directory(p.join(appDir.path, 'materials'));
    if (!await materialDir.exists()) {
      await materialDir.create(recursive: true);
    }
    // 同一批共用一个毫秒基准，再拼上下标：避免同一毫秒内多个文件互相覆盖
    final int stamp = DateTime.now().millisecondsSinceEpoch;

    int imported = 0; // 成功条数
    int skipped = 0; // 非音视频，静默跳过
    final List<String> failures = <String>[]; // 失败明细

    // —— 逐个文件：筛格式 → 复制 → 写库 ——
    for (int i = 0; i < files.length; i++) {
      final PlatformFile picked = files[i];
      final String fileName = picked.name;

      // 有些平台的文件选择器过滤不严格（如安卓某些文件管理器），这里再筛一道
      final String ext = p.extension(fileName).replaceFirst('.', '').toLowerCase();
      if (!kMediaExtensions.contains(ext)) {
        skipped++;
        continue;
      }

      final String? srcPath = picked.path;
      if (srcPath == null) {
        failures.add('$fileName（读不到文件路径）');
        continue;
      }

      try {
        final String destPath = p.join(materialDir.path, '${stamp}_${i}_$fileName');
        await File(srcPath).copy(destPath);
        // 直接调存储层写入，不走 addMaterial：addMaterial 每次都 load()，批量时太浪费
        await DatabaseHelper.instance.insertMaterial(
          title: p.basenameWithoutExtension(fileName),
          folderId: folderId,
          format: ext,
          filePath: destPath,
        );
        imported++;
      } catch (e) {
        // 单个失败不影响其他文件
        failures.add('$fileName（$e）');
      }
    }

    await load(); // 整批导入完成后统一刷新一次
    return ImportResult(imported: imported, skipped: skipped, failures: failures);
  }

  /// 把素材移动到另一个文件夹
  Future<void> moveMaterial(int materialId, int newFolderId) async {
    await DatabaseHelper.instance.moveMaterial(materialId, newFolderId);
    await load();
  }

  /// 【班级文件下载】把云端班级文件下载到本地素材库，注册成一条素材。
  /// 完整链路：拿下载 URL → 下载到 materials 目录 → 写进 sqflite → 刷新。
  /// 归属「班级下载」专用文件夹（不存在则自动建），与本地导入的素材分开。
  /// 之后该文件就和本地素材一样，能被播放器、文件夹管理统一处理（离线可用）。
  Future<void> downloadClassFile({
    required String title,
    required String format,
    required String downloadUrl,
  }) async {
    // 1. 确保「班级下载」文件夹存在（不存在则建，拿到 folderId）
    int folderId = -1;
    for (final Folder f in _folders) {
      if (f.name == '班级下载') {
        folderId = f.id;
        break;
      }
    }
    if (folderId == -1) {
      folderId = await DatabaseHelper.instance.insertFolder('班级下载');
    }

    // 2. 下载文件到 App 私有目录的 materials 子目录（和导入素材同一目录约定）
    final Directory appDir = await getApplicationDocumentsDirectory();
    final Directory materialDir = Directory(p.join(appDir.path, 'materials'));
    if (!await materialDir.exists()) {
      await materialDir.create(recursive: true);
    }
    final String safeName =
        title.replaceAll(RegExp(r'[^\w\u4e00-\u9fa5.-]'), '_');
    final String destPath = p.join(
      materialDir.path,
      '${DateTime.now().millisecondsSinceEpoch}_$safeName',
    );

    // 用 http 下载（dio 的 download 需要 dio，这里用 HttpClient 避免额外依赖判断）
    final dioClient = Dio();
    await dioClient.download(
      downloadUrl,
      destPath,
      options: Options(
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 5),
      ),
    );

    // 3. 写库 + 刷新
    await addMaterial(
      title: title,
      folderId: folderId,
      format: format.isEmpty ? 'unknown' : format,
      filePath: destPath,
    );
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
