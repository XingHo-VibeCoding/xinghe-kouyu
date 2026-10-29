// =====================================================================
// 素材卡片组件：统一的素材列表项
// ---------------------------------------------------------------------
// 为什么抽出来：素材列表页和文件夹内容页的素材卡几乎逐行相同
// （Card + ListTile + 媒体徽章 + 标题 + 副标题 + chevron + 长按菜单 + 点击进播放页），
// 只有副标题拼接和 folderName 来源两处不同。抽成组件，两处只传差异部分。
// =====================================================================

import 'package:flutter/material.dart';

import '../models/material_item.dart';
import '../utils/design_tokens.dart';

class MaterialCard extends StatelessWidget {
  const MaterialCard({
    super.key,
    required this.item,
    required this.subtitle,
    required this.onOpen,
    required this.onLongPress,
  });

  /// 素材数据
  final MaterialItem item;

  /// 副标题文案（「文件夹 · 格式 · 时长」或「格式 · 时长」，由调用方拼接）
  final String subtitle;

  /// 点击回调（进播放页）
  final VoidCallback onOpen;

  /// 长按回调（弹操作菜单：重命名 / 移动 / 删除）
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final bool isVideo = item.format == 'mp4' ||
        item.format == 'mov' ||
        item.format == 'webm';
    return Card(
      child: ListTile(
        leading: _mediaBadge(context, isVideo),
        title: Text(item.title),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: kFontCaption, color: kTextSecondary),
        ),
        trailing: const Icon(Icons.chevron_right),
        onLongPress: onLongPress,
        onTap: onOpen,
      ),
    );
  }

  /// 素材类型徽章：圆角彩色底 + 白图标
  Widget _mediaBadge(BuildContext context, bool isVideo) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(kRadiusSM),
      ),
      child: Icon(
        isVideo ? Icons.movie_outlined : Icons.audiotrack,
        color: Colors.white,
        size: kIconSM,
      ),
    );
  }
}
