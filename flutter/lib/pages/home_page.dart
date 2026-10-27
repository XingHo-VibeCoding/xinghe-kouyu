// =====================================================================
// 页面「首页」
// ---------------------------------------------------------------------
// 结构（自上而下）：
//   1. 问候语（按当前时段 + 身份称谓）
//   2. 白卡片：两个渐变大按钮「扫码」「签到」
//   3. 「最近访问」横向滚动卡片（真实班级列表）
//   4. 「待办事项」占位卡片
// =====================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/class_item.dart';
import '../store/class_store.dart';
import '../store/user_store.dart';
import '../utils/design_tokens.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const Color green = Color(0xFF6FCF3F);
  static const Color greenDark = Color(0xFF4CBB3F);

  /// 按当前时段返回问候语
  String _greeting() {
    final int hour = DateTime.now().hour;
    if (hour < 12) return '上午好';
    if (hour < 18) return '下午好';
    return '晚上好';
  }

  /// 按身份返回称呼：老师 → 「昵称+老师」，学生 → 「昵称+同学」；
  /// 没填昵称或未登记身份时，统一用「同学」兜底
  String _greetName(UserStore user) {
    final String nick = user.nickname;
    if (nick.isEmpty) return '同学';
    return user.role == UserRole.teacher ? '$nick老师' : '$nick同学';
  }

  @override
  Widget build(BuildContext context) {
    final UserStore user = context.watch<UserStore>();
    final ClassStore classStore = context.watch<ClassStore>();

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: <Widget>[
            const SizedBox(height: 16),
            // ---------- 1. 问候语 ----------
            Text(
              '${_greeting()}！${_greetName(user)}',
              style: const TextStyle(
                fontSize: kFontHero,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: kTextPrimary,
              ),
            ),
            const SizedBox(height: 16),
            // ---------- 2. 扫码 / 签到 卡片 ----------
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(kRadiusCard),
                border: kCardBorder,
                boxShadow: kShadowSm,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: _gradientButton(
                      icon: Icons.qr_code_scanner,
                      label: '扫码',
                      start: const Color(0xFF45CFC4),
                      end: kTealDark,
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
                fontSize: kFontTitle,
                fontWeight: FontWeight.w700,
                color: kTextPrimary,
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
                    fontSize: kFontTitle,
                    fontWeight: FontWeight.w700,
                    color: kTextPrimary,
                  ),
                ),
                const Spacer(),
                // 「查看全部」小胶囊
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: kTealSoft,
                    borderRadius: BorderRadius.circular(kRadiusBtn),
                  ),
                  child: const Text(
                    '查看全部',
                    style: TextStyle(fontSize: kFontCaption, color: kTeal),
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
            boxShadow: kShadowSm,
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
                  fontWeight: FontWeight.w700,
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
      return Container(
        height: 90,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: kCardBorder,
        ),
        child: const Text(
          '加入班级后，这里会显示最近访问的班级',
          style: TextStyle(fontSize: kFontBody, color: kTextHint),
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
        color: kCard,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: kCardBorder,
        boxShadow: kShadowSm,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 上部插画占位：青绿浅底 + 图标
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
                    fontSize: kFontBody,
                    fontWeight: FontWeight.w700,
                    color: kTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '班级码: ${cls.code}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: kTextHint),
                ),
                const SizedBox(height: 2),
                Text(
                  '教师: ${cls.teacherName ?? '未知'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: kTextHint),
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
        color: kCard,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: kCardBorder,
        boxShadow: kShadowSm,
      ),
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 圆形图标
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
                        fontWeight: FontWeight.w700,
                        color: kTextPrimary,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '课程名称: 待接入作业功能',
                      style: TextStyle(fontSize: kFontBody, color: kTextHint),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '课程代码: --',
                      style: TextStyle(fontSize: kFontBody, color: kTextHint),
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
                      style: TextStyle(fontSize: kFontCaption, color: kTextHint)),
                  SizedBox(height: 2),
                  Text(
                    '--',
                    style: TextStyle(
                      fontSize: kFontBody,
                      fontWeight: FontWeight.w700,
                      color: kTextPrimary,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              const Text(
                '待提交',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: kCoral,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
