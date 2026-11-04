// =====================================================================
// 页面「签到」：老师端发起签到的入口（Day 25 签到功能）
// ---------------------------------------------------------------------
// 从「班级详情页」的「签到」宫格点进来。进入后先查该班有没有进行中
// 的签到：
//   - 有 → 显示签到码 + 「查看监控」按钮，跳监控页
//   - 无 → 显示「发起签到」大按钮，发布后跳监控页
// AppBar 右侧「历史」按钮跳签到历史页。
// =====================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/checkin_session.dart';
import '../net/api_client.dart';
import '../store/user_store.dart';
import '../utils/design_tokens.dart';
import '../widgets/error_state.dart';
import '../widgets/gradient_button.dart';
import '../widgets/skeleton_list.dart';
import 'checkin_history_page.dart';
import 'checkin_monitor_page.dart';

class CheckinLaunchPage extends StatefulWidget {
  final String classId;
  final String className;

  const CheckinLaunchPage({
    super.key,
    required this.classId,
    required this.className,
  });

  @override
  State<CheckinLaunchPage> createState() => _CheckinLaunchPageState();
}

class _CheckinLaunchPageState extends State<CheckinLaunchPage> {
  bool _loading = true;
  String? _error;
  CheckinSession? _active; // 该班进行中的签到
  bool _creating = false; // 是否正在发起

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 查该班是否有进行中签到
  Future<void> _load() async {
    final ApiClient api = context.read<ApiClient>();
    final ApiResult<CheckinSession?> result =
        await api.activeCheckin(widget.classId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result.ok) {
        _active = result.data;
      } else {
        _error = result.message;
      }
    });
  }

  /// 发起签到：成功后跳监控页
  Future<void> _launch() async {
    final UserStore user = context.read<UserStore>();
    final ApiClient api = context.read<ApiClient>();
    setState(() => _creating = true);
    final ApiResult<CheckinSession> result =
        await api.createCheckin(user.uid, widget.classId);
    if (!mounted) return;
    setState(() => _creating = false);
    if (result.ok) {
      await _gotoMonitor(result.data!);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
  }

  Future<void> _gotoMonitor(CheckinSession session) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckinMonitorPage(
          classId: widget.classId,
          className: widget.className,
          sessionId: session.id,
          initialSession: session,
        ),
      ),
    );
    if (!mounted) return;
    _load(); // 返回后刷新：可能刚发起了签到，立即显示「已有进行中签到」
  }

  void _gotoHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckinHistoryPage(
          classId: widget.classId,
          className: widget.className,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kCard,
        foregroundColor: kTextPrimary,
        elevation: 0,
        title: const Text('签到', style: TextStyle(fontSize: kFontTitle)),
        actions: <Widget>[
          TextButton(
            onPressed: _gotoHistory,
            child: const Text('历史',
                style: TextStyle(color: kTeal, fontSize: kFontBody)),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: KeyedSubtree(
        key: ValueKey<String>(
            _loading ? 'loading' : (_error != null ? 'error' : 'data')),
        child: _buildBodyContent(),
      ),
    );
  }

  Widget _buildBodyContent() {
    if (_loading) return const SkeletonList();
    if (_error != null) {
      return ErrorState(message: _error!, onRetry: _load);
    }
    return Padding(
      padding: const EdgeInsets.all(kSpaceMD),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 班级名
          Text(
            widget.className,
            style: const TextStyle(
              fontSize: kFontTitle,
              fontWeight: kWeightBold,
              color: kTextPrimary,
            ),
          ),
          const SizedBox(height: kSpaceLG),
          if (_active != null)
            _activeCard(_active!)
          else ...<Widget>[
            GradientButton(
              icon: Icons.fact_check_outlined,
              label: _creating ? '发起中…' : '发起签到',
              onTap: _creating ? null : _launch,
              height: 56,
            ),
            const SizedBox(height: kSpaceMD),
            const Text(
              '点击发起签到，生成 6 位签到码，学生 10 分钟内输码完成签到。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: kFontBody, color: kTextHint),
            ),
          ],
        ],
      ),
    );
  }

  /// 已有进行中签到：显示签到码 + 查看监控按钮
  Widget _activeCard(CheckinSession session) {
    return Container(
      padding: const EdgeInsets.all(kSpaceMD),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: kCardBorder,
        boxShadow: kShadowSm,
      ),
      child: Column(
        children: <Widget>[
          const Text(
            '该班已有进行中签到',
            style: TextStyle(
                fontSize: kFontTitle,
                fontWeight: kWeightBold,
                color: kTextPrimary),
          ),
          const SizedBox(height: kSpaceSM),
          Text(
            '签到码：${session.code}',
            style: const TextStyle(
              fontSize: kFontDisplay,
              fontWeight: kWeightBold,
              color: kTeal,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: kSpaceLG),
          GradientButton(
            icon: Icons.visibility_outlined,
            label: '查看监控',
            onTap: () => _gotoMonitor(session),
            height: 56,
          ),
        ],
      ),
    );
  }

}
