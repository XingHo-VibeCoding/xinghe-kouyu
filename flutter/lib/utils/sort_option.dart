// =====================================================================
// 素材列表排序工具（纯前端逻辑，不碰数据库）
// ---------------------------------------------------------------------
// 为什么放这里：主列表页、文件夹内容页都要用同一套排序，抽成公共枚举避免两处重复。
// 排序只发生在「界面展示」这一层：数据照旧从 store 拿，展示前按用户选的维度排一遍。
// 不写回数据库、不改变原始顺序（id 顺序仍是默认的「导入顺序」）。
// =====================================================================

import 'package:flutter/material.dart';

import '../models/material_item.dart';

/// 排序维度：用户可选的四种排序方式
enum SortOption {
  importOrder('导入顺序'), // 默认：按 id 升序 = 导入先后
  name('名称'), // 按标题字母序（中文按 Unicode 排序）
  type('类型'), // 按格式扩展名
  duration('时长'); // 按时长（短→长）

  const SortOption(this.label);
  final String label; // 菜单里显示的中文名

  /// 菜单项图标：给每个排序维度一个视觉锚点，菜单不再光秃秃
  IconData get icon => switch (this) {
        SortOption.importOrder => Icons.history,
        SortOption.name => Icons.abc,
        SortOption.type => Icons.category_outlined,
        SortOption.duration => Icons.schedule,
      };
}

/// 把一段「02:35」这样的时长文本转成秒数，用于排序比较。
/// 解析失败（空串、格式异常）返回 0，让没时长的素材排在最前面。
int _durationToSeconds(String duration) {
  if (duration.isEmpty) return 0;
  final List<String> parts = duration.split(':');
  try {
    if (parts.length >= 3) {
      // 形如 01:02:35（时:分:秒）
      return int.parse(parts[0]) * 3600 +
          int.parse(parts[1]) * 60 +
          int.parse(parts[2]);
    }
    if (parts.length == 2) {
      // 形如 02:35（分:秒）
      return int.parse(parts[0]) * 60 + int.parse(parts[1]);
    }
    return int.parse(parts[0]);
  } catch (_) {
    return 0;
  }
}

/// 按指定维度排序素材列表。
/// 返回一个新的、排好序的列表，不改动传入的原始列表。
List<MaterialItem> sortMaterials(
  List<MaterialItem> source,
  SortOption option,
) {
  final List<MaterialItem> result = List<MaterialItem>.from(source);
  switch (option) {
    case SortOption.importOrder:
      result.sort((MaterialItem a, MaterialItem b) => a.id.compareTo(b.id));
      break;
    case SortOption.name:
      result.sort((MaterialItem a, MaterialItem b) => a.title.compareTo(b.title));
      break;
    case SortOption.type:
      result.sort((MaterialItem a, MaterialItem b) => a.format.compareTo(b.format));
      break;
    case SortOption.duration:
      result.sort((MaterialItem a, MaterialItem b) =>
          _durationToSeconds(a.duration).compareTo(_durationToSeconds(b.duration)));
      break;
  }
  return result;
}
