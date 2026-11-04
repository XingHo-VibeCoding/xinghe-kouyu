// =====================================================================
// 页面「签到监控」：老师实时看全班签到状态（Day 25 签到功能）
// ---------------------------------------------------------------------
// 从发起页点进来，2.5 秒轮询后端拉最新状态：
//   - 顶部：签到码 + 进行中/已结束标签
//   - 四态汇总（已到/迟到/请假/缺勤）
//   - 学生列表（点某行弹状态选择，手动调整四态）
//   - 底部「终止签到」按钮（进行中才可点）
// =====================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/checkin_record.dart';
import '../models/checkin_session.dart';
import '../models/checkin_status.dart';
import '../net/api_client.dart';
import '../store/user_store.dart';
import '../utils/design_tokens.dart';
import '../widgets/checkin_status_tag.dart';
import '../widgets/error_state.dart';
import '../widgets/skeleton_list.dart';

class CheckinMonitorPage extends StatefulWidget {
  final String classId;
  final String className;
  final String sessionId;
  final CheckinSession? initialSession; // 发起/查看时传入，免首屏 loading

  const CheckinMonitorPage({
    super.key,
    required this.classId,
    required this.className,
    required this.sessionId,
    this.initialSession,
  });

  @override
  State<CheckinMonitorPage> createState() => _CheckinMonitorPageState();
}

class _CheckinMonitorPageState extends State<CheckinMonitorPage> {
  bool _loading = true;
  String? _error;
  CheckinSession? _session;
  bool _closing = false; // 是否正在终止
  bool _endNotified = false; // 是否已提示「签到已结束」
  Timer? _timer; // 2.5 秒轮询

  @override
  void initState() {
    super.initState();
    // 发起/查看时已带上 session，直接渲染（不经过 loading），轮询只做后续刷新
    if (widget.initialSession != null) {
      _session = widget.initialSession;
      _loading = false;
    } else {
      _load();
    }
    _timer = Timer.periodic(
      const Duration(milliseconds: 2500),
      (_) => _poll(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// 提示一次「签到已结束」并自动退出监控页（自动结束或手动终止）
  void _notifyEnd() {
    if (_endNotified) return;
    _endNotified = true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('签到已结束')),
    );
    // 延迟 1.5 秒自动退出监控页，让老师看到提示
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  /// 首次加载（带 loading 态）
  Future<void> _load() async {
    final ApiClient api = context.read<ApiClient>();
    final ApiResult<CheckinSession> result =
        await api.checkinSession(widget.sessionId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result.ok) {
        _session = result.data!;
      } else {
        _error = result.message;
      }
    });
    if (result.ok && result.data!.isEnded) {
      _timer?.cancel();
      _notifyEnd();
    }
  }

  /// 轮询刷新（不显示 loading，避免闪烁）
  Future<void> _poll() async {
    final ApiClient api = context.read<ApiClient>();
    final ApiResult<CheckinSession> result =
        await api.checkinSession(widget.sessionId);
    if (!mounted) return;
    if (result.ok) {
      final CheckinSession session = result.data!;
      setState(() {
        _session = session;
        _loading = false;
        _error = null;
      });
      if (session.isEnded) {
        _timer?.cancel();
        _notifyEnd();
      }
    }
    // 轮询失败静默忽略：保持上次数据，不打断用户正在做的调整
  }

  /// 老师手动调整某学生状态
  Future<void> _updateRecord(CheckinRecord record, CheckinStatus status) async {
    final UserStore user = context.read<UserStore>();
    final ApiClient api = context.read<ApiClient>();
    final ApiResult<void> result = await api.updateCheckinRecord(
      uid: user.uid,
      sessionId: widget.sessionId,
      studentId: record.studentId,
      status: status,
    );
    if (!mounted) return;
    if (result.ok) {
      _poll(); // 立即刷新
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
  }

  /// 终止签到
  Future<void> _close() async {
    final UserStore user = context.read<UserStore>();
    final ApiClient api = context.read<ApiClient>();
    setState(() => _closing = true);
    final ApiResult<void> result =
        await api.closeCheckin(user.uid, widget.sessionId);
    if (!mounted) return;
    setState(() => _closing = false);
    if (result.ok) {
      _poll();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
  }

  /// 弹状态选择底部弹层
  void _showStatusSheet(CheckinRecord record) {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: kSpaceMD),
              Text(
                '调整「${record.nickname ?? '学生'}」的签到状态',
                style: const TextStyle(
                    fontSize: kFontTitle,
                    fontWeight: kWeightBold,
                    color: kTextPrimary),
              ),
              const SizedBox(height: kSpaceSM),
              ...CheckinStatus.values.map((CheckinStatus s) {
                return ListTile(
                  leading: Icon(Icons.circle, color: s.color, size: kIconSM),
                  title: Text(s.label),
                  trailing: record.status == s
                      ? Icon(Icons.check, color: kTeal, size: kIconMD)
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    _updateRecord(record, s);
                  },
                );
              }),
              const SizedBox(height: kSpaceXS),
            ],
          ),
        );
      },
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
        title:
            const Text('签到监控', style: TextStyle(fontSize: kFontTitle)),
      ),
      body: _buildBody(),
      bottomNavigationBar: _session == null ? null : _bottomBar(_session!),
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
    final CheckinSession session = _session!;
    return ListView(
      padding: const EdgeInsets.all(kSpaceSM),
      children: <Widget>[
        _headerCard(session),
        const SizedBox(height: kSpaceSM),
        _summaryBar(session),
        const SizedBox(height: kSpaceSM),
        const Text(
          '学生状态（点击可手动调整）',
          style: TextStyle(
              fontSize: kFontTitle,
              fontWeight: kWeightBold,
              color: kTextPrimary),
        ),
        const SizedBox(height: kSpaceXS),
        ...session.records.map((CheckinRecord r) => _recordCard(r)),
        const SizedBox(height: kSpaceLG),
      ],
    );
  }

  /// 顶部：班级名 + 签到码 + 进行中/已结束标签
  Widget _headerCard(CheckinSession session) {
    final bool ended = session.isEnded;
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
          Text(
            widget.className,
            style: const TextStyle(
                fontSize: kFontBody, color: kTextSecondary),
          ),
          const SizedBox(height: kSpaceXS),
          Text(
            session.code,
            style: const TextStyle(
              fontSize: kFontDisplay,
              fontWeight: kWeightBold,
              color: kTeal,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: kSpaceSM),
          CheckinStatusTag(ended: ended),
        ],
      ),
    );
  }

  /// 四态汇总条
  Widget _summaryBar(CheckinSession session) {
    final CheckinSummary s = session.summary ?? const CheckinSummary();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: kSpaceMD),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: kCardBorder,
        boxShadow: kShadowSm,
      ),
      child: Row(
        children: <Widget>[
          _statCell('缺勤', s.absent, kError),
          _statCell('迟到', s.lateArrival, kCoral),
          _statCell('请假', s.leave, kCheckinLeave),
          _statCell('已到', s.present, kCheckinPresent),
        ],
      ),
    );
  }

  /// 汇总条单格：数字 + 标签
  Widget _statCell(String label, int count, Color color) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            '$count',
            style: TextStyle(
                fontSize: kFontHero, fontWeight: kWeightBold, color: color),
          ),
          const SizedBox(height: kSpaceXXS),
          Text(label,
              style:
                  const TextStyle(fontSize: kFontCaption, color: kTextSecondary)),
        ],
      ),
    );
  }

  /// 单条学生记录：头像 + 昵称 + 状态标签
  Widget _recordCard(CheckinRecord r) {
    final String nickname = r.nickname ?? '未知用户';
    final String initial = nickname.isEmpty ? '?' : nickname.characters.first;
    return Container(
      margin: const EdgeInsets.only(bottom: kSpaceXS),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: kCardBorder,
        boxShadow: kShadowSm,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadiusCard),
        onTap: () => _showStatusSheet(r),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: kSpaceSM, vertical: kSpaceSM),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 20,
                backgroundColor: kTextSecondary,
                child: Text(
                  initial,
                  style: const TextStyle(
                      fontSize: kFontBody,
                      color: Colors.white,
                      fontWeight: kWeightBold),
                ),
              ),
              const SizedBox(width: kSpaceSM),
              Expanded(
                child: Text(
                  nickname,
                  style: const TextStyle(
                      fontSize: kFontTitle,
                      color: kTextPrimary,
                      fontWeight: kWeightMedium),
                ),
              ),
              // 状态标签：色点 + 文字
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: kSpaceSM, vertical: kSpaceXXS),
                decoration: BoxDecoration(
                  color: r.status.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(kRadiusSM),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.circle, size: kIconXS, color: r.status.color),
                    const SizedBox(width: kSpaceXXS),
                    Text(
                      r.status.label,
                      style: TextStyle(
                        fontSize: kFontCaption,
                        color: r.status.color,
                        fontWeight: kWeightMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 底部终止按钮
  Widget _bottomBar(CheckinSession session) {
    final bool ended = session.isEnded;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            kSpaceMD, kSpaceXS, kSpaceMD, kSpaceSM),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(kRadiusSM),
            onTap: ended || _closing ? null : _close,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: ended ? kBorder : kError.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(kRadiusSM),
              ),
              child: Center(
                child: Text(
                  ended
                      ? '签到已结束'
                      : (_closing ? '终止中…' : '终止签到'),
                  style: TextStyle(
                    fontSize: kFontTitle,
                    fontWeight: kWeightBold,
                    color: ended ? kTextHint : kError,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
