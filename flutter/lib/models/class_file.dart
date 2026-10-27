// 班级文件数据模型（班级管理 MVP）
// 对应后端「某班文件列表」接口返回的结构

/// 一个班级文件（元数据账本，本体在云存储）
class ClassFile {
  final String id; // 文件记录 id（uuid）
  final String title; // 展示名
  final String cloudPath; // 云存储 fileID（cloud://...）
  final int? size; // 字节数
  final String? format; // mp3 / mp4 等
  final String uploaderId; // 上传者 uid
  final String? createdAt; // 上传时间

  const ClassFile({
    required this.id,
    required this.title,
    required this.cloudPath,
    this.size,
    this.format,
    required this.uploaderId,
    this.createdAt,
  });

  /// 从后端接口返回的一行 JSON 转成 ClassFile
  factory ClassFile.fromJson(Map<String, dynamic> json) {
    return ClassFile(
      id: json['id'] as String,
      title: json['title'] as String,
      cloudPath: json['cloud_path'] as String,
      size: json['size'] as int?,
      format: json['format'] as String?,
      uploaderId: json['uploader_id'] as String,
      createdAt: json['created_at'] as String?,
    );
  }

  /// 是否视频（用于显示图标）
  bool get isVideo => format == 'mp4' || format == 'mov' || format == 'webm';

  /// 人类可读的文件大小
  String get sizeLabel {
    if (size == null) return '';
    final double kb = size! / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}
