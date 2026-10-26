// =====================================================================
// 页面「作业」：1:1 复刻「学在重邮」动态页（Day 20 视觉对齐）
// ---------------------------------------------------------------------
// 结构：顶部分类 tab（公告/预警/作业/测试/讨论/其它，带红色数字角标）
//       → 居中日期 → 白色公告卡片（标题 + 正文，正文带青绿链接色文字）。
//
// 说明：tab 可切换（选中态跟随），卡片内容为静态占位，后续接真实作业数据。
// =====================================================================

import 'package:flutter/material.dart';

class WorkPage extends StatefulWidget {
  const WorkPage({super.key});

  @override
  State<WorkPage> createState() => _WorkPageState();
}

class _WorkPageState extends State<WorkPage> {
  // 品牌青绿（学在重邮同款）
  static const Color teal = Color(0xFF2BC8B7);
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
      backgroundColor: const Color(0xFFF4F6F8),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: 8),
            // ---------- 顶部分类 tab（横向可滚动） ----------
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: List<Widget>.generate(_categories.length,
                    (int i) => _categoryTab(_categories[i].$1, _categories[i].$2, i)),
              ),
            ),
            const SizedBox(height: 4),
            const Divider(height: 1, color: Color(0xFFEEEEEE)),
            // ---------- 居中日期 ----------
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  _todayString(),
                  style:
                      const TextStyle(fontSize: 14, color: Color(0xFF999999)),
                ),
              ),
            ),
            // ---------- 公告卡片（静态占位） ----------
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          children: <Widget>[
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w400,
                    color: selected
                        ? const Color(0xFF333333)
                        : const Color(0xFF999999),
                  ),
                ),
                if (badge != null) const SizedBox(width: 2),
                if (badge != null) _badge(badge),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              width: 28,
              height: 3,
              decoration: BoxDecoration(
                color: selected ? teal : Colors.transparent,
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
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: badgeRed,
        borderRadius: BorderRadius.circular(9),
      ),
      constraints: const BoxConstraints(minWidth: 18),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 10, color: Colors.white),
      ),
    );
  }

  /// 公告卡片：标题 + 竖点菜单 + 正文（含青绿链接色文字）
  Widget _announcementCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF333333),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {}, // 占位：后续接「更多操作」
                child: const Icon(Icons.more_vert,
                    size: 20, color: Color(0xFFBBBBBB)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 正文：灰字 + 黑字 + 青绿链接字（1:1 复刻参考图配色）
          const Text.rich(
            TextSpan(
              style: TextStyle(fontSize: 14, height: 1.6),
              children: <InlineSpan>[
                TextSpan(
                  text: '课程 ',
                  style: TextStyle(color: Color(0xFF999999)),
                ),
                TextSpan(
                  text: '【示例课程】',
                  style: TextStyle(color: Color(0xFF333333)),
                ),
                TextSpan(
                  text: ' 发布公告 ',
                  style: TextStyle(color: Color(0xFF999999)),
                ),
                TextSpan(
                  text: '作业功能即将上线，届时这里会展示老师发布的作业与通知',
                  style: TextStyle(color: teal),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
