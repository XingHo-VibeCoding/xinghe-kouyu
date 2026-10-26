// =====================================================================
// 页面「班级详情」：1:1 复刻「学在重邮」课程详情页（Day 21）
// ---------------------------------------------------------------------
// 结构：青绿渐变头部（返回按钮 + 班级名 + 老师胶囊）→ 白色圆角卡片上移
//       → 三组宫格：课程信息（4 个）/ 课件活动（10 个）/ 教学成果（3 个）。
//
// 说明：宫格图标 1:1 复刻配色与布局；点击暂为占位提示，
//       后续按 MVP 优先级逐个接入真实功能（课件→班级文件、班级成员→成员列表）。
// =====================================================================

import 'package:flutter/material.dart';

import '../models/class_item.dart';

class ClassDetailPage extends StatelessWidget {
  final ClassItem cls;

  const ClassDetailPage({super.key, required this.cls});

  // 品牌青绿（学在重邮同款）
  static const Color teal = Color(0xFF2BC8B7);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            // ---------- 渐变头部 ----------
            _buildHeader(context),
            // ---------- 白色圆角卡片（上移叠住渐变底部） ----------
            Transform.translate(
              offset: const Offset(0, -24),
              child: Column(
                children: <Widget>[
                  _section(
                    title: '课程信息',
                    items: const <_GridItem>[
                      _GridItem(Icons.menu_book, '章节', Color(0xFFF0A637)),
                      _GridItem(Icons.campaign, '公告', Color(0xFF5B8DEF)),
                      _GridItem(Icons.groups, '班级成员', Color(0xFFF2765E)),
                      _GridItem(Icons.description, '课程信息', Color(0xFF3FC8C0)),
                    ],
                  ),
                  _section(
                    title: '课件活动',
                    items: const <_GridItem>[
                      _GridItem(Icons.book_outlined, '课件', Color(0xFF7BC64E)),
                      _GridItem(Icons.assignment_outlined, '作业', Color(0xFF6BBF59)),
                      _GridItem(Icons.quiz_outlined, '测试', Color(0xFFF2765E)),
                      _GridItem(Icons.chat_bubble, '讨论', Color(0xFF5B8DEF)),
                      _GridItem(Icons.fact_check_outlined, '问卷', Color(0xFF5B8DEF)),
                      _GridItem(Icons.hub_outlined, '互动', Color(0xFF3FC8C0)),
                      _GridItem(Icons.how_to_reg, '点名记录', Color(0xFF6A7FDB)),
                      _GridItem(Icons.diversity_3, '分组学习', Color(0xFF3FB8A0)),
                      _GridItem(Icons.receipt_long, '课堂报告', Color(0xFF4FC8C8)),
                      _GridItem(Icons.rule, '练习本', Color(0xFF35C0A8)),
                    ],
                  ),
                  _section(
                    title: '教学成果',
                    items: const <_GridItem>[
                      _GridItem(Icons.leaderboard, '成绩', Color(0xFFF2765E)),
                      _GridItem(Icons.insights, '学习分析', Color(0xFF5B8DEF)),
                      _GridItem(Icons.emoji_events, '教学评价', Color(0xFF3FC8C0)),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 渐变头部：返回按钮 + 班级名 + 右下老师胶囊
  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 210,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[Color(0xFF3FC8C0), Color(0xFF2FB5C9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 返回按钮
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            const Spacer(),
            // 班级名（白色大字）
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                cls.name,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 老师胶囊（右下角）：小白圈头像 + 老师名
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 24),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.white,
                        child: Text(
                          (cls.teacherName ?? '师').characters.first,
                          style: const TextStyle(
                            fontSize: 12,
                            color: teal,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        cls.teacherName ?? '未知老师',
                        style: const TextStyle(
                            fontSize: 13, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// 一个分区：标题 + 白色圆角卡片包住宫格
  Widget _section({required String title, required List<_GridItem> items}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF333333),
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 0.85,
            children:
                items.map((_GridItem item) => _gridCell(item)).toList(),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  /// 单个宫格：彩色圆底白图标 + 下方文字；点击占位
  Widget _gridCell(_GridItem item) {
    return Builder(
      builder: (BuildContext context) {
        return GestureDetector(
          onTap: () {
            // 占位：后续按 MVP 优先级接入真实功能
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${item.label} 功能开发中')),
            );
          },
          behavior: HitTestBehavior.opaque,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: item.color,
                  shape: BoxShape.circle,
                ),
                child: Icon(item.icon, color: Colors.white, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                item.label,
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF666666)),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 宫格项数据：图标 + 文字 + 主题色
class _GridItem {
  final IconData icon;
  final String label;
  final Color color;
  const _GridItem(this.icon, this.label, this.color);
}
