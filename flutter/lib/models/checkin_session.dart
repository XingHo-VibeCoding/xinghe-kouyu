// 签到场次数据模型（Day 25 签到功能）
// 对应后端 checkin_sessions 表 + 发布/实时/历史接口返回的结构

import 'checkin_record.dart';

/// 一场签到（老师发起，学生输码签到）
class CheckinSession {
  final String id; // 场次 id（uuid）
  final String classId; // 班级 id
  final String teacherId; // 发起老师 uid
  final String code; // 6 位纯数字签到码
  final String status; // ongoing 进行中 / closed 已终止
  final String? createdAt; // 发起时间（ISO 8601）
  final String? closedAt; // 手动终止时间（可空）
  final bool expired; // 是否已超时（后端惰性终止标记）
  final int? studentCount; // 学生数（发布接口返回；实时/历史接口为 null）
  final CheckinSummary? summary; // 四态汇总（实时/历史接口才有，可空）
  final List<CheckinRecord> records; // 明细（实时/历史接口才有，可空）

  const CheckinSession({
    required this.id,
    required this.classId,
    required this.teacherId,
    required this.code,
    required this.status,
    this.createdAt,
    this.closedAt,
    this.expired = false,
    this.studentCount,
    this.summary,
    this.records = const [],
  });

  /// 从后端接口返回的一行 JSON 转成 CheckinSession
  factory CheckinSession.fromJson(Map<String, dynamic> json) {
    final List<dynamic> recordsJson = (json['records'] as List<dynamic>?) ?? const [];
    final Map<String, dynamic>? summaryJson = json['summary'] as Map<String, dynamic>?;
    return CheckinSession(
      id: json['id'] as String,
      classId: json['class_id'] as String,
      teacherId: json['teacher_id'] as String,
      code: json['code'] as String,
      status: json['status'] as String,
      createdAt: json['created_at'] as String?,
      closedAt: json['closed_at'] as String?,
      expired: json['expired'] == true,
      studentCount: (json['student_count'] as num?)?.toInt(),
      summary: summaryJson == null ? null : CheckinSummary.fromJson(summaryJson),
      records: recordsJson
          .map((dynamic e) => CheckinRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 是否还能签到（进行中且未超时）
  bool get isActive => status == 'ongoing' && !expired;

  /// 是否已结束（手动终止或超时）
  bool get isEnded => status == 'closed' || expired;
}
