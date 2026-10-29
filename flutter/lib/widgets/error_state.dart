// =====================================================================
// 错误状态组件：统一「图标 + 『加载失败』标题 + 错误文案 + 重试按钮」
// ---------------------------------------------------------------------
// 为什么抽出来：错误态在 4 个页面重复（班级列表/班级文件/班级成员/素材列表），
// 且细节不统一——图标尺寸 64/72 混、只有素材列表有标题、颜色硬编码 Colors.orange。
// 统一后错误图标用 kError 红，语义与登录页错误红一致。
// =====================================================================

import 'package:flutter/material.dart';

import '../utils/design_tokens.dart';

class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    required this.onRetry,
    this.title = '加载失败',
  });

  /// 错误详情（store.errorMessage 或页面持有的 _error 文案）
  final String message;

  /// 点击「重试」的回调
  final VoidCallback onRetry;

  /// 标题，默认「加载失败」
  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.error_outline, size: kIconXL, color: kError),
          const SizedBox(height: kSpaceSM),
          Text(
            title,
            style: const TextStyle(fontSize: kFontLarge, fontWeight: kWeightBold),
          ),
          const SizedBox(height: kSpaceXS),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kSpaceXL),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: kFontBody, color: kTextHint),
            ),
          ),
          const SizedBox(height: kSpaceMD),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kTeal),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
