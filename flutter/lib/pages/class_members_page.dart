// =====================================================================
// 页面「班级成员」：某班的成员列表（班级管理 MVP）
// ---------------------------------------------------------------------
// 从「班级详情页」的「班级成员」宫格点进来，调后端 /classes/members 接口，
// 展示这个班的老师 + 学生成员（头像 + 昵称 + 身份标签）。
//
// 四种状态：加载中 / 空 / 出错（可重试）/ 有数据。
// =====================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/class_member.dart';
import '../net/api_client.dart';
import '../utils/design_tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/skeleton_list.dart';

class ClassMembersPage extends StatefulWidget {
  final String classId;
  final String className;

  const ClassMembersPage({
    super.key,
    required this.classId,
    required this.className,
  });

  @override
  State<ClassMembersPage> createState() => _ClassMembersPageState();
}

class _ClassMembersPageState extends State<ClassMembersPage> {
  // 品牌青绿（学在重邮同款）
  

  // 加载状态
  bool _loading = true;
  String? _error;
  List<ClassMember> _members = <ClassMember>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 调后端查成员列表
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final ApiClient api = context.read<ApiClient>();
    final ApiResult<List<ClassMember>> result =
        await api.classMembers(widget.classId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result.ok) {
        _members = result.data!;
      } else {
        _error = result.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: kTextPrimary,
        elevation: 0,
        title: Text('班级成员', style: const TextStyle(fontSize: kFontTitle)),
      ),
      body: _buildBody(),
    );
  }

  /// 按状态渲染：加载中 / 出错 / 空 / 列表
  Widget _buildBody() {
    final Widget child;
    final String stateKey;
    if (_loading) {
      child = const SkeletonList();
      stateKey = 'loading';
    } else if (_error != null) {
      child = ErrorState(message: _error!, onRetry: _load);
      stateKey = 'error';
    } else if (_members.isEmpty) {
      child = const EmptyState(
        icon: Icons.group_outlined,
        title: '这个班还没有成员',
        description: '成员加入后，这里会显示老师和学生。',
      );
      stateKey = 'empty';
    } else {
      child = ListView.separated(
        padding: const EdgeInsets.all(kSpaceSM),
        itemCount: _members.length,
        separatorBuilder: (_, _) => const SizedBox(height: kSpaceXS),
        itemBuilder: (BuildContext context, int index) {
          final ClassMember m = _members[index];
          return _memberCard(m);
        },
      );
      stateKey = 'data';
    }
    // AnimatedSwitcher 让四态切换淡入淡出（动效·第三批 B1）；KeyedSubtree 用状态 key 触发过渡
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: KeyedSubtree(key: ValueKey(stateKey), child: child),
    );
  }

  /// 单个成员卡片：头像（首字）+ 昵称 + 身份标签
  Widget _memberCard(ClassMember m) {
    final String nickname = m.nickname ?? '未知用户';
    final String initial = nickname.isEmpty ? '?' : nickname.characters.first;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: kSpaceSM, vertical: kSpaceSM),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: kCardBorder,
        boxShadow: kShadowSm,
      ),
      child: Row(
        children: <Widget>[
          // 头像：圆底 + 昵称首字
          CircleAvatar(
            radius: 22,
            backgroundColor: m.isTeacher ? kTeal : kTextSecondary,
            child: Text(
              initial,
              style: const TextStyle(
                  fontSize: kFontTitle, color: Colors.white, fontWeight: kWeightBold),
            ),
          ),
          const SizedBox(width: kSpaceSM),
          // 昵称
          Expanded(
            child: Text(
              nickname,
              style: const TextStyle(
                  fontSize: kFontTitle, color: kTextPrimary, fontWeight: kWeightMedium),
            ),
          ),
          // 身份标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: kSpaceSM, vertical: kSpaceXXS),
            decoration: BoxDecoration(
              color: m.isTeacher
                  ? kTealSoft
                  : kBorder,
              borderRadius: BorderRadius.circular(kRadiusSM),
            ),
            child: Text(
              m.isTeacher ? '老师' : '学生',
              style: TextStyle(
                fontSize: kFontCaption,
                color: m.isTeacher ? kTeal : kTextSecondary,
                fontWeight: kWeightMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
