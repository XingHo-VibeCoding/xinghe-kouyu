// =====================================================================
// 页面「首页」：1:1 复刻「学在重邮」首页（Day 20 视觉对齐）
// ---------------------------------------------------------------------
// 结构（自上而下）：
//   1. 问候语（按当前时段：上午好/下午好/晚上好 + 昵称）
//   2. 白卡片：两个渐变大按钮「扫码」「签到」（图标占位，点击逻辑暂不做）
//   3. 「最近访问」横向滚动卡片（数据 = 真实班级列表）
//   4. 「待办事项」占位卡片（静态示例，后续接作业功能）
// =====================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/class_item.dart';
import '../store/class_store.dart';
import '../store/user_store.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // 品牌青绿（学在重邮同款）
  static const Color teal = Color(0xFF2BC8B7);
  static const Color tealDark = Color(0xFF23B9A9);
  static const Color green = Color(0xFF6FCF3F);
  static const Color greenDark = Color(0xFF4CBB3F);

  /// 按当前时段返回问候语
  String _greeting() {
    final int hour = DateTime.now().hour;
    if (hour < 12) return '上午好';
    if (hour < 18) return '下午好';
    return '晚上好';
  }

  @override
  Widget build(BuildContext context) {
    final UserStore user = context.watch<UserStore>();
    final ClassStore classStore = context.watch<ClassStore>();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: <Widget>[
            const SizedBox(height: 16),
            // ---------- 1. 问候语 ----------
            Text(
              '${_greeting()}！${user.nickname.isEmpty ? '同学' : user.nickname}同学',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF333333),
              ),
            ),
            const SizedBox(height: 16),
            // ---------- 2. 扫码 / 签到 卡片 ----------
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: _gradientButton(
                      icon: Icons.qr_code_scanner,
                      label: '扫码',
                      start: const Color(0xFF45CFC4),
                      end: tealDark,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _gradientButton(
                      icon: Icons.where_to_vote_outlined,
                      label: '签到',
                      start: green,
                      end: greenDark,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // ---------- 3. 最近访问 ----------
            const Text(
              '最近访问',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF333333),
              ),
            ),
            const SizedBox(height: 10),
            _buildRecentClasses(classStore.classes),
            const SizedBox(height: 20),
            // ---------- 4. 待办事项 ----------
            Row(
              children: <Widget>[
                const Text(
                  '待办事项',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF333333),
                  ),
                ),
                const Spacer(),
                // 「查看全部」小胶囊（占位）
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F2F4),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    '查看全部',
                    style: TextStyle(fontSize: 12, color: Color(0xFF888888)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildTodoCard(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// 渐变大按钮（扫码 / 签到）：点击逻辑暂不接，先占位
  Widget _gradientButton({
    required IconData icon,
    required String label,
    required Color start,
    required Color end,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          // 占位：后续接扫码 / 签到逻辑
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$label 功能开发中')),
          );
        },
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[start, end],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 最近访问：横向滚动的班级卡片（真实数据）
  Widget _buildRecentClasses(List<ClassItem> classes) {
    if (classes.isEmpty) {
      // 没有班级时给一句引导，保持版面不空
      return Container(
        height: 90,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          '加入班级后，这里会显示最近访问的班级',
          style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
        ),
      );
    }
    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: classes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (BuildContext context, int index) {
          final ClassItem cls = classes[index];
          return _recentCard(cls);
        },
      ),
    );
  }

  /// 单张「最近访问」卡片：上部插画占位 + 下部班级信息
  Widget _recentCard(ClassItem cls) {
    return Container(
      width: 170,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 上部插画占位（学在重邮是卡通插画，这里用浅蓝底+图标代替）
          Container(
            height: 92,
            color: const Color(0xFFD9EEF9),
            child: const Center(
              child: Icon(Icons.collections, color: Color(0xFF7FB8D4), size: 36),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  cls.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF333333),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '班级码: ${cls.code}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF999999)),
                ),
                const SizedBox(height: 2),
                Text(
                  '教师: ${cls.teacherName ?? '未知'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF999999)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 待办事项占位卡（静态示例，后续接作业功能）
  Widget _buildTodoCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 黄色圆形图标
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF3D6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.campaign_outlined,
                    color: Color(0xFFF5A623), size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '第一讲',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF333333),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '课程名称: 待接入作业功能',
                      style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '课程代码: --',
                      style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 底部：截止日期 + 状态
          Row(
            children: <Widget>[
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('截止日期',
                      style: TextStyle(fontSize: 12, color: Color(0xFF999999))),
                  SizedBox(height: 2),
                  Text(
                    '--',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF333333),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              const Text(
                '待提交',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: teal,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
