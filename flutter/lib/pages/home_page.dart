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

import 'checkin_launch_page.dart';
import '../models/checkin_status.dart';
import '../models/class_item.dart';
import '../net/api_client.dart';
import '../store/class_store.dart';
import '../store/user_store.dart';
import '../utils/design_tokens.dart';
import '../widgets/gradient_button.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
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
          padding: const EdgeInsets.symmetric(horizontal: kSpaceMD),
          children: <Widget>[
            const SizedBox(height: kSpaceMD),
            // ---------- 1. 问候语 ----------
            Text(
              '${_greeting()}！${_greetName(user)}',
              style: const TextStyle(
                fontSize: kFontHero,
                fontWeight: kWeightBold,
                letterSpacing: -0.5,
                color: kTextPrimary,
              ),
            ),
            const SizedBox(height: kSpaceMD),
            // ---------- 2. 扫码 / 签到 卡片 ----------
            Container(
              padding: const EdgeInsets.all(kSpaceSM),
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(kRadiusCard),
                border: kCardBorder,
                boxShadow: kShadowSm,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: GradientButton(
                      icon: Icons.event_available_outlined,
                      label: '发布签到',
                      onTap: _launchCheckin,
                    ),
                  ),
                  const SizedBox(width: kSpaceSM),
                  Expanded(
                    child: GradientButton(
                      icon: Icons.where_to_vote_outlined,
                      label: '签到',
                      startColor: kCheckinPresent,
                      endColor: kCheckinPresentDark,
                      onTap: _showCheckinDialog,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: kSpaceLG),
            // ---------- 3. 最近访问 ----------
            const Text(
              '最近访问',
              style: TextStyle(
                fontSize: kFontTitle,
                fontWeight: kWeightBold,
                color: kTextPrimary,
              ),
            ),
            const SizedBox(height: kSpaceSM),
            _buildRecentClasses(classStore.classes),
            const SizedBox(height: kSpaceLG),
            // ---------- 4. 待办事项 ----------
            Row(
              children: <Widget>[
                const Text(
                  '待办事项',
                  style: TextStyle(
                    fontSize: kFontTitle,
                    fontWeight: kWeightBold,
                    color: kTextPrimary,
                  ),
                ),
                const Spacer(),
                // 「查看全部」小胶囊
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: kSpaceSM, vertical: kSpaceXXS),
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
            const SizedBox(height: kSpaceSM),
            _buildTodoCard(),
            const SizedBox(height: kSpaceLG),
          ],
        ),
      ),
    );
  }

  /// 老师发布签到：先定班级（多班级弹选班），再进发起页；学生提示仅老师可用
  Future<void> _launchCheckin() async {
    final UserStore user = context.read<UserStore>();
    final ClassStore classStore = context.read<ClassStore>();
    if (user.role != UserRole.teacher) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('仅老师可以发布签到')),
      );
      return;
    }
    final List<ClassItem> classes = classStore.classes;
    if (classes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有班级，先去「班级」建班或加入')),
      );
      return;
    }
    ClassItem target;
    if (classes.length == 1) {
      target = classes.first;
    } else {
      final ClassItem? picked = await showModalBottomSheet<ClassItem>(
        context: context,
        builder: (BuildContext context) {
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.all(kSpaceMD),
                  child: Text(
                    '选择要发布签到的班级',
                    style: TextStyle(
                      fontSize: kFontTitle,
                      fontWeight: kWeightBold,
                      color: kTextPrimary,
                    ),
                  ),
                ),
                for (final ClassItem c in classes)
                  ListTile(
                    leading: const Icon(Icons.groups_outlined, color: kTeal),
                    title: Text(
                      c.name,
                      style: const TextStyle(color: kTextPrimary),
                    ),
                    subtitle: Text(
                      '班级码: ${c.code}',
                      style: const TextStyle(color: kTextHint),
                    ),
                    onTap: () => Navigator.pop(context, c),
                  ),
              ],
            ),
          );
        },
      );
      if (picked == null) return;
      target = picked;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckinLaunchPage(
          classId: target.id,
          className: target.name,
        ),
      ),
    );
  }

  /// 学生输码签到：弹输入框 → 调后端签到
  Future<void> _showCheckinDialog() async {
    final UserStore user = context.read<UserStore>();
    final ApiClient api = context.read<ApiClient>();
    final TextEditingController controller = TextEditingController();
    final FocusNode focusNode = FocusNode();
    String? code;
    try {
      code = await showDialog<String>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('签到'),
            content: TextField(
              controller: controller,
              focusNode: focusNode,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(fontSize: kFontTitle, letterSpacing: 4),
              decoration: const InputDecoration(
                hintText: '请输入 6 位签到码',
                counterText: '',
                floatingLabelBehavior: FloatingLabelBehavior.never,
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context, controller.text);
                },
                child: const Text('签到'),
              ),
            ],
          );
        },
      );
    } finally {
      focusNode.dispose();
      controller.dispose();
    }
    if (code == null) return;
    final String trimmed = code.trim();
    if (trimmed.length != 6 || int.tryParse(trimmed) == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入 6 位数字签到码')),
      );
      return;
    }
    final ApiResult<void> result = await api.checkin(user.uid, trimmed);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.ok ? '签到成功' : result.message)),
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
        separatorBuilder: (_, _) => const SizedBox(width: kSpaceSM),
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
            color: kTealSoft,
            child: const Center(
              child: Icon(Icons.collections, color: kTeal, size: kIconLG),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(kSpaceSM),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  cls.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: kFontBody,
                    fontWeight: kWeightBold,
                    color: kTextPrimary,
                  ),
                ),
                const SizedBox(height: kSpaceXXS),
                Text(
                  '班级码: ${cls.code}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: kFontCaption, color: kTextHint),
                ),
                const SizedBox(height: kSpaceXXS),
                Text(
                  '教师: ${cls.teacherName ?? '未知'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: kFontCaption, color: kTextHint),
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
      padding: const EdgeInsets.all(kSpaceSM),
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
                    color: Color(0xFFF5A623), size: kIconMD),
              ),
              const SizedBox(width: kSpaceSM),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '第一讲',
                      style: TextStyle(
                        fontSize: kFontTitle,
                        fontWeight: kWeightBold,
                        color: kTextPrimary,
                      ),
                    ),
                    SizedBox(height: kSpaceXXS),
                    Text(
                      '课程名称: 待接入作业功能',
                      style: TextStyle(fontSize: kFontBody, color: kTextHint),
                    ),
                    SizedBox(height: kSpaceXXS),
                    Text(
                      '课程代码: --',
                      style: TextStyle(fontSize: kFontBody, color: kTextHint),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: kSpaceSM),
          // 底部：截止日期 + 状态
          Row(
            children: <Widget>[
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('截止日期',
                      style: TextStyle(fontSize: kFontCaption, color: kTextHint)),
                  SizedBox(height: kSpaceXXS),
                  Text(
                    '--',
                    style: TextStyle(
                      fontSize: kFontBody,
                      fontWeight: kWeightBold,
                      color: kTextPrimary,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              const Text(
                '待提交',
                style: TextStyle(
                  fontSize: kFontTitle,
                  fontWeight: kWeightBold,
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
