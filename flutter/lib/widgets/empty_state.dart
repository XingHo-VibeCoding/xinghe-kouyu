// =====================================================================
// 空状态组件：统一「图标 + 标题 + 可选说明 + 可选 CTA」
// ---------------------------------------------------------------------
// 为什么抽出来：空态在 6 个页面重复（班级列表/班级文件/班级成员/素材列表/
// 文件夹内容/文件夹管理），且形态参差——有的有图标有的没有、有的有说明有的
// 没有、图标尺寸 64/72 混、标题字号也不齐。统一成一个组件，改样式只改这一处。
// =====================================================================

import 'package:flutter/material.dart';

import '../utils/design_tokens.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
  });

  /// 空态图标（如「还没有素材」用叶子图标）
  final IconData icon;

  /// 空态标题（如「还没有素材」）
  final String title;

  /// 可选：标题下方的说明文字
  final String? description;

  /// 可选：CTA 按钮（如「导入素材」）
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 72, color: kTextHint),
          const SizedBox(height: kSpaceSM),
          Text(
            title,
            style: const TextStyle(fontSize: kFontLarge, fontWeight: kWeightBold),
          ),
          if (description != null) ...<Widget>[
            const SizedBox(height: kSpaceXS),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kSpaceXL),
              child: Text(
                description!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: kTextSecondary),
              ),
            ),
          ],
          if (action != null) ...<Widget>[
            const SizedBox(height: kSpaceMD),
            action!,
          ],
        ],
      ),
    );
  }
}
