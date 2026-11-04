// 签到记录数据模型 + 四态汇总（Day 25 签到功能）
// 对应后端 checkin_records 表 + 实时/历史接口返回的结构

import 'checkin_status.dart';

/// 一条签到记录（一场次 × 一名学生）
class CheckinRecord {
  final String id; // 记录 id（uuid）
  final String sessionId; // 所属场次 id
  final String studentId; // 学生 uid
  final String? nickname; // 学生昵称（拼自 users 表，可能为 null）
  final CheckinStatus status; // 状态：缺勤 / 迟到 / 请假 / 已到
  final String? checkedAt; // 签到时间（ISO 8601，可空）

  const CheckinRecord({
    required this.id,
    required this.sessionId,
    required this.studentId,
    this.nickname,
    required this.status,
    this.checkedAt,
  });

  /// 从后端接口返回的一行 JSON 转成 CheckinRecord
  factory CheckinRecord.fromJson(Map<String, dynamic> json) {
    return CheckinRecord(
      id: json['id'] as String,
      // session_id 允许缺失（兜底空串）：后端个别接口曾漏带此字段，
      // 硬性 as String 会让解析抛异常、整页冻结（Day 25 签到 BUG 教训）
      sessionId: (json['session_id'] as String?) ?? '',
      studentId: json['student_id'] as String,
      nickname: json['nickname'] as String?,
      // 未知状态兜底为缺勤（不抛异常，保证列表能渲染出来）
      status: checkinStatusFromWire(json['status'] as String?) ?? CheckinStatus.absent,
      checkedAt: json['checked_at'] as String?,
    );
  }
}

/// 四态汇总（某场签到的已到/迟到/请假/缺勤人数）
class CheckinSummary {
  final int present; // 已到人数
  final int lateArrival; // 迟到人数
  final int leave; // 请假人数
  final int absent; // 缺勤人数

  const CheckinSummary({
    this.present = 0,
    this.lateArrival = 0,
    this.leave = 0,
    this.absent = 0,
  });

  /// 从后端返回的 summary JSON 转成 CheckinSummary
  factory CheckinSummary.fromJson(Map<String, dynamic> json) {
    return CheckinSummary(
      present: (json['present'] as num?)?.toInt() ?? 0,
      lateArrival: (json['late'] as num?)?.toInt() ?? 0,
      leave: (json['leave'] as num?)?.toInt() ?? 0,
      absent: (json['absent'] as num?)?.toInt() ?? 0,
    );
  }

  /// 班级总人数（四种状态人数之和）
  int get total => present + lateArrival + leave + absent;
}
