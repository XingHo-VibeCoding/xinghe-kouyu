// 素材条目模型：对应一条音视频素材
// 当前阶段只做「壳」，字段够界面展示用即可；接真实存储时再按需补充（如时长秒数、文件路径）

/// 一条音视频素材
class MaterialItem {
  final String id; // 唯一标识（演示用）
  final String title; // 标题（文件名）
  final String folder; // 所属文件夹
  final String format; // 格式：mp3 / m4a / wav / mp4 / mov
  final String duration; // 时长文本，如 02:35

  const MaterialItem({
    required this.id,
    required this.title,
    required this.folder,
    required this.format,
    required this.duration,
  });
}
