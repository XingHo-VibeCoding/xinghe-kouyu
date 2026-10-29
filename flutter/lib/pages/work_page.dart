// =====================================================================
// 页面「作业」：1:1 复刻「学在重邮」动态页（Day 20 视觉对齐）
// ---------------------------------------------------------------------
// 结构：顶部分类 tab（公告/预警/作业/测试/讨论/其它，带红色数字角标）
//       → 居中日期 → 白色公告卡片（标题 + 正文，正文带青绿链接色文字）。
//
// 说明：tab 可切换（选中态跟随），卡片内容为静态占位，后续接真实作业数据。
// =====================================================================

import 'package:flutter/material.dart';

import '../utils/design_tokens.dart';

class WorkPage extends StatefulWidget {
  const WorkPage({super.key});

  @override
  State<WorkPage> createState() => _WorkPageState();
}

class _WorkPageState extends State<WorkPage> {
  // 品牌青绿见 design_tokens.kTeal；badgeRed 为语义红角标，保留
  static const Color badgeRed = Color(0xFFF86C6C);

  // 分类定义：名称 + 角标数字（null = 没有角标）
  static const List<(String, int?)> _categories = <(String, int?)>[
    ('公告', null),
    ('预警', null),
    ('作业', 64),
    ('测试', 45),
    ('讨论', null),
    ('其它', 93),
  ];

  int _selected = 0; // 当前选中的分类下标

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: kSpaceXS),
            // ---------- 顶部分类 tab（横向可滚动） ----------
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: kSpaceMD),
              child: Row(
                children: List<Widget>.generate(_categories.length,
                    (int i) => _categoryTab(_categories[i].$1, _categories[i].$2, i)),
              ),
            ),
            const SizedBox(height: kSpaceXXS),
            const Divider(height: 1, color: kBorder),
            // ---------- 居中日期 ----------
            Padding(
              padding: const EdgeInsets.symmetric(vertical: kSpaceMD),
              child: Center(
                child: Text(
                  _todayString(),
                  style:
                      const TextStyle(fontSize: kFontBody, color: kTextHint),
                ),
              ),
            ),
            // ---------- 公告卡片（静态占位） ----------
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kSpaceMD),
              child: _announcementCard(),
            ),
          ],
        ),
      ),
    );
  }

  /// 今天的日期字符串（yyyy-MM-dd）
  String _todayString() {
    final DateTime now = DateTime.now();
    final String mm = now.month.toString().padLeft(2, '0');
    final String dd = now.day.toString().padLeft(2, '0');
    return '${now.year}-$mm-$dd';
  }

  /// 单个分类 tab：选中加粗黑字 + 青绿下划线；角标是红色小圆数字
  Widget _categoryTab(String label, int? badge, int index) {
    final bool selected = _selected == index;
    return GestureDetector(
      onTap: () => setState(() => _selected = index),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: kSpaceSM, vertical: kSpaceXXS),
        child: Column(
          children: <Widget>[
            const SizedBox(height: kSpaceXS),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style: TextStyle(
                    fontSize: kFontTitle,
                    fontWeight: selected ? kWeightBold : kWeightRegular,
                    color: selected
                        ? kTextPrimary
                        : kTextHint,
                  ),
                ),
                if (badge != null) const SizedBox(width: kSpaceXXS),
                if (badge != null) _badge(badge),
              ],
            ),
            const SizedBox(height: kSpaceXS),
            Container(
              width: 28,
              height: 3,
              decoration: BoxDecoration(
                color: selected ? kTeal : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 红色数字角标
  Widget _badge(int count) {
    final String text = count > 99 ? '99+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: kSpaceXXS, vertical: kSpaceXXS),
      decoration: BoxDecoration(
        color: badgeRed,
        borderRadius: BorderRadius.circular(kRadiusXS),
      ),
      constraints: const BoxConstraints(minWidth: 18),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: kFontMicro, color: Colors.white),
      ),
    );
  }

  /// 公告卡片：标题 + 竖点菜单 + 正文（含青绿链接色文字）
  Widget _announcementCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(kSpaceMD),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kRadiusSM),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 标题行 + 竖点
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  '公告发布',
                  style: TextStyle(
                    fontSize: kFontTitle,
                    fontWeight: kWeightBold,
                    color: kTextPrimary,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {}, // 占位：后续接「更多操作」
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.all(kSpaceSM),
                  child: Icon(Icons.more_vert,
                      size: kIconSM, color: kTextHint, semanticLabel: '更多'),
                ),
              ),
            ],
          ),
          const SizedBox(height: kSpaceXS),
          // 正文：灰字 + 黑字 + 青绿链接字（1:1 复刻参考图配色）
          const Text.rich(
            TextSpan(
              style: TextStyle(fontSize: kFontBody, height: 1.6),
              children: <InlineSpan>[
                TextSpan(
                  text: '课程 ',
                  style: TextStyle(color: kTextHint),
                ),
                TextSpan(
                  text: '【示例课程】',
                  style: TextStyle(color: kTextPrimary),
                ),
                TextSpan(
                  text: ' 发布公告 ',
                  style: TextStyle(color: kTextHint),
                ),
                TextSpan(
                  text: '作业功能即将上线，届时这里会展示老师发布的作业与通知',
                  style: TextStyle(color: kTeal),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
