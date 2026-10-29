// =====================================================================
// 排序菜单组件：统一的排序四选一 PopupMenuButton
// ---------------------------------------------------------------------
// 为什么抽出来：素材列表页和文件夹内容页各写了一套几乎一样的排序菜单，
// folder_content 注释里自己都写了「和主列表页共用同一套排序逻辑与菜单样式」，
// 但没抽。抽成一个组件，两处只传「当前选项 + 回调」。
// =====================================================================

import 'package:flutter/material.dart';

import '../utils/design_tokens.dart';
import '../utils/sort_option.dart';

class SortMenu extends StatelessWidget {
  const SortMenu({
    super.key,
    required this.option,
    required this.onChanged,
  });

  /// 当前选中的排序维度
  final SortOption option;

  /// 选中新排序维度后的回调
  final ValueChanged<SortOption> onChanged;

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;
    return PopupMenuButton<SortOption>(
      icon: const Icon(Icons.sort),
      tooltip: '排序',
      initialValue: option,
      onSelected: onChanged,
      // 自定义菜单项（不用默认的 CheckedPopupMenuItem——它的勾是灰色、
      // 和主题脱节）。这里用主题色勾 + 每项自己的图标，视觉统一。
      itemBuilder: (BuildContext context) {
        return SortOption.values.map((SortOption opt) {
          final bool selected = opt == option;
          return PopupMenuItem<SortOption>(
            value: opt,
            height: 48,
            child: Row(
              children: <Widget>[
                // 选中列：固定宽度放勾，未选中时占位透明，保持文字对齐
                SizedBox(
                  width: 28,
                  child: selected
                      ? Icon(Icons.check, size: kIconSM, color: primary)
                      : null,
                ),
                Icon(opt.icon, size: kIconSM,
                    color: selected ? primary : kTextHint),
                const SizedBox(width: kSpaceSM),
                Text(
                  opt.label,
                  style: TextStyle(
                    fontSize: kFontBody,
                    fontWeight: selected ? kWeightMedium : kWeightRegular,
                    color: selected ? primary : kTextPrimary,
                  ),
                ),
              ],
            ),
          );
        }).toList();
      },
    );
  }
}
