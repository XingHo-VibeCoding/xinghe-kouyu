// =====================================================================
// 签到状态枚举（Day 25 签到功能）
// ---------------------------------------------------------------------
// 四态：缺勤（红）/ 迟到（橙）/ 请假（浅橙）/ 已到（绿）。
//   - 初态 = 缺勤；学生签到只能签成「已到」；
//   - 「迟到」「请假」由老师手动标注（学生端不自动产生）。
// 为什么用 wire 字段而不直接用 enum.name：
//   「迟到」的英文是 late，而 late 是 Dart 内置标识符，不能作成员名；
//   成员名用 lateArrival，wire 存 'late' 与数据库 checkin_records.status 一致。
// =====================================================================

import 'package:flutter/material.dart';

import '../utils/design_tokens.dart';

/// 签到状态：缺勤 / 迟到 / 请假 / 已到
enum CheckinStatus {
  absent('absent'),
  lateArrival('late'),
  leave('leave'),
  present('present');

  const CheckinStatus(this.wire);

  /// 与数据库 checkin_records.status 完全一致的字符串值
  final String wire;
}

/// 字符串 → 状态；非法/空值返回 null（不猜、不默认，交由调用方决定兜底）
CheckinStatus? checkinStatusFromWire(String? wire) {
  if (wire == null) return null;
  for (final CheckinStatus s in CheckinStatus.values) {
    if (s.wire == wire) return s;
  }
  return null;
}

/// 签到专属语义色（迟到橙复用全局 kCoral、缺勤红复用全局 kError；
/// 请假浅橙、已到绿是签到模块专属，定义在这里保持内聚）
const Color kCheckinLeave = Color(0xFFFFB74D); // 请假浅橙
const Color kCheckinPresent = Color(0xFF6FCF3F); // 已到绿
const Color kCheckinPresentDark = Color(0xFF4CBB3F); // 已到绿·深（首页签到按钮渐变）

/// 状态 → 展示文案 / 状态色
extension CheckinStatusText on CheckinStatus {
  /// 中文文案（监控列表、历史明细、汇总条都显示）
  String get label {
    switch (this) {
      case CheckinStatus.absent:
        return '缺勤';
      case CheckinStatus.lateArrival:
        return '迟到';
      case CheckinStatus.leave:
        return '请假';
      case CheckinStatus.present:
        return '已到';
    }
  }

  /// 状态色（色点 / 标签底色）
  Color get color {
    switch (this) {
      case CheckinStatus.absent:
        return kError;
      case CheckinStatus.lateArrival:
        return kCoral;
      case CheckinStatus.leave:
        return kCheckinLeave;
      case CheckinStatus.present:
        return kCheckinPresent;
    }
  }
}
