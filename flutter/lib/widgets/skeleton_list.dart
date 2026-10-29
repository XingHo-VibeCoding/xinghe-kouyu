// 骨架屏列表：圆形徽章 + 两行灰条，模拟真实素材卡片的布局
// 用于列表页加载态，数据到达时布局不跳动（动效·第三批 C1）
import 'package:flutter/material.dart';

import '../utils/design_tokens.dart';

/// 骨架屏列表：默认 6 行，每行「圆形徽章 + 标题条 + 副标题条」
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.itemCount = 6});

  /// 骨架行数
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(kSpaceSM),
      itemCount: itemCount,
      itemBuilder: (_, _) => const _SkeletonRow(),
    );
  }
}

/// 骨架屏的一行：圆形头像 + 两行灰条，模拟真实素材卡片的布局
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(kSpaceSM),
        child: Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: kBorder,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: kSpaceSM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(width: double.infinity, height: 14, color: kBorder),
                  const SizedBox(height: kSpaceXS),
                  FractionallySizedBox(
                    widthFactor: 0.5,
                    alignment: Alignment.centerLeft,
                    child: Container(height: 12, color: kBorder),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
