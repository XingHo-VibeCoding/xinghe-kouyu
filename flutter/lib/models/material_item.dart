// =====================================================================
// 素材条目模型（数据层里的一行数据）
// ---------------------------------------------------------------------
// 这层是什么：把数据库里 materials 表的一行，变成一个 Dart 对象，
// 方便界面层直接 .title、.format 这样读字段，而不是去翻 Map。
//
// 语言：Dart（纯数据类，不碰数据库，只负责「装数据」）。
// =====================================================================

/// 一条音视频素材
class MaterialItem {
  final int id; // 数据库主键（唯一标识，不再用字符串演示 id）
  final String title; // 标题（文件名）
  final int folderId; // 所属文件夹的 id（外键，指向 folders.id）
  final String format; // 格式：mp3 / m4a / wav / mp4 / mov
  final String filePath; // 文件在 App 私有目录里的完整路径
  final String duration; // 时长文本，如 02:35（当前可能为空，播放接入后回填）

  const MaterialItem({
    required this.id,
    required this.title,
    required this.folderId,
    required this.format,
    required this.filePath,
    this.duration = '',
  });

  /// 从数据库查出来的一行（Map）转成 MaterialItem 对象
  /// 这就是「数据库数据」到「代码对象」的桥梁
  factory MaterialItem.fromMap(Map<String, Object?> map) {
    return MaterialItem(
      id: map['id'] as int,
      title: map['title'] as String,
      folderId: map['folder_id'] as int,
      format: map['format'] as String,
      filePath: map['file_path'] as String,
      duration: (map['duration'] as String?) ?? '',
    );
  }
}
