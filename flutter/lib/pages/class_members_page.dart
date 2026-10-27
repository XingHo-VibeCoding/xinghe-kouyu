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
        foregroundColor: const Color(0xFF333333),
        elevation: 0,
        title: Text('班级成员', style: const TextStyle(fontSize: 17)),
      ),
      body: _buildBody(),
    );
  }

  /// 按状态渲染：加载中 / 出错 / 空 / 列表
  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kTeal));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.error_outline, size: 64, color: Colors.orange),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFF999999))),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kTeal),
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_members.isEmpty) {
      return const Center(
        child: Text('这个班还没有成员', style: TextStyle(color: Color(0xFF999999))),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _members.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final ClassMember m = _members[index];
        return _memberCard(m);
      },
    );
  }

  /// 单个成员卡片：头像（首字）+ 昵称 + 身份标签
  Widget _memberCard(ClassMember m) {
    final String nickname = m.nickname ?? '未知用户';
    final String initial = nickname.isEmpty ? '?' : nickname.characters.first;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
            backgroundColor: m.isTeacher ? kTeal : const Color(0xFF8FB8D8),
            child: Text(
              initial,
              style: const TextStyle(
                  fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          // 昵称
          Expanded(
            child: Text(
              nickname,
              style: const TextStyle(
                  fontSize: 15, color: Color(0xFF333333), fontWeight: FontWeight.w600),
            ),
          ),
          // 身份标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: m.isTeacher
                  ? const Color(0xFFE0F5F1)
                  : const Color(0xFFE8F1F8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              m.isTeacher ? '老师' : '学生',
              style: TextStyle(
                fontSize: 12,
                color: m.isTeacher ? kTeal : const Color(0xFF5B8FC9),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
