// =====================================================================
// 页面「签到历史」：老师看某班历史签到记录（Day 25 签到功能）
// ---------------------------------------------------------------------
// 从发起页 AppBar「历史」点进来，列该班所有签到场次（时间倒序），
// 每场显示四态汇总，点展开看学生明细。
// =====================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/checkin_record.dart';
import '../models/checkin_session.dart';
import '../models/checkin_status.dart';
import '../net/api_client.dart';
import '../utils/design_tokens.dart';
import '../widgets/checkin_status_tag.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/skeleton_list.dart';

class CheckinHistoryPage extends StatefulWidget {
  final String classId;
  final String className;

  const CheckinHistoryPage({
    super.key,
    required this.classId,
    required this.className,
  });

  @override
  State<CheckinHistoryPage> createState() => _CheckinHistoryPageState();
}

class _CheckinHistoryPageState extends State<CheckinHistoryPage> {
  bool _loading = true;
  String? _error;
  List<CheckinSession> _sessions = <CheckinSession>[];
  final Set<int> _expanded = <int>{}; // 展开的场次下标

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ApiClient api = context.read<ApiClient>();
    final ApiResult<List<CheckinSession>> result =
        await api.checkinHistory(widget.classId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result.ok) {
        _sessions = result.data!;
      } else {
        _error = result.message;
      }
    });
  }

  void _toggle(int index) {
    setState(() {
      if (!_expanded.remove(index)) _expanded.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kCard,
        foregroundColor: kTextPrimary,
        elevation: 0,
        title: const Text('签到历史', style: TextStyle(fontSize: kFontTitle)),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: KeyedSubtree(
        key: ValueKey<String>(_loading
            ? 'loading'
            : (_error != null
                ? 'error'
                : (_sessions.isEmpty ? 'empty' : 'data'))),
        child: _buildBodyContent(),
      ),
    );
  }

  Widget _buildBodyContent() {
    if (_loading) return const SkeletonList();
    if (_error != null) {
      return ErrorState(message: _error!, onRetry: _load);
    }
    if (_sessions.isEmpty) {
      return const EmptyState(
        icon: Icons.history,
        title: '还没有签到记录',
        description: '发起签到后，历史记录会显示在这里。',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(kSpaceSM),
      itemCount: _sessions.length,
      separatorBuilder: (_, _) => const SizedBox(height: kSpaceXS),
      itemBuilder: (BuildContext context, int index) {
        return _sessionCard(_sessions[index], index);
      },
    );
  }

  /// 单个场次卡片：时间 + 状态标签 + 四态汇总；点标题行展开明细
  Widget _sessionCard(CheckinSession session, int index) {
    final bool expanded = _expanded.contains(index);
    final CheckinSummary s = session.summary ?? const CheckinSummary();
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: kCardBorder,
        boxShadow: kShadowSm,
      ),
      child: Column(
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(kRadiusCard),
            onTap: () => _toggle(index),
            child: Padding(
              padding: const EdgeInsets.all(kSpaceSM),
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _fmtTime(session.createdAt),
                          style: const TextStyle(
                            fontSize: kFontTitle,
                            fontWeight: kWeightBold,
                            color: kTextPrimary,
                          ),
                        ),
                      ),
                      CheckinStatusTag(ended: session.isEnded),
                      const SizedBox(width: kSpaceXXS),
                      Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        size: kIconSM,
                        color: kTextHint,
                      ),
                    ],
                  ),
                  const SizedBox(height: kSpaceSM),
                  _summaryRow(s),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                        kSpaceSM, 0, kSpaceSM, kSpaceSM),
                    child: Column(
                      children: session.records.map(_recordRow).toList(),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// 四态汇总行：缺勤 / 迟到 / 请假 / 已到
  Widget _summaryRow(CheckinSummary s) {
    return Row(
      children: <Widget>[
        _miniStat('缺勤', s.absent, kError),
        _miniStat('迟到', s.lateArrival, kCoral),
        _miniStat('请假', s.leave, kCheckinLeave),
        _miniStat('已到', s.present, kCheckinPresent),
      ],
    );
  }

  Widget _miniStat(String label, int count, Color color) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            '$count',
            style: TextStyle(
              fontSize: kFontTitle,
              fontWeight: kWeightBold,
              color: color,
            ),
          ),
          const SizedBox(width: kSpaceXXS),
          Text(label,
              style:
                  const TextStyle(fontSize: kFontCaption, color: kTextHint)),
        ],
      ),
    );
  }

  /// 明细行：色点 + 昵称 + 状态
  Widget _recordRow(CheckinRecord r) {
    final String nickname = r.nickname ?? '未知用户';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: kSpaceXXS),
      child: Row(
        children: <Widget>[
          Icon(Icons.circle, size: kIconXS, color: r.status.color),
          const SizedBox(width: kSpaceXS),
          Expanded(
            child: Text(
              nickname,
              style: const TextStyle(fontSize: kFontBody, color: kTextPrimary),
            ),
          ),
          Text(
            r.status.label,
            style: TextStyle(
              fontSize: kFontBody,
              fontWeight: kWeightMedium,
              color: r.status.color,
            ),
          ),
        ],
      ),
    );
  }

  /// ISO 时间 → 本地「MM-dd HH:mm」
  String _fmtTime(String? iso) {
    final DateTime? dt = iso == null ? null : DateTime.tryParse(iso);
    if (dt == null) return '--';
    final DateTime local = dt.toLocal();
    final String mm = local.month.toString().padLeft(2, '0');
    final String dd = local.day.toString().padLeft(2, '0');
    final String hh = local.hour.toString().padLeft(2, '0');
    final String mi = local.minute.toString().padLeft(2, '0');
    return '$mm-$dd $hh:$mi';
  }
}
