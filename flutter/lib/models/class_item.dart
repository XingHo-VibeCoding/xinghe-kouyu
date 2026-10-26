// 班级数据模型（班级管理 MVP）
// 对应后端 classes 表 + 我的班级列表接口返回的结构

/// 一个班级（老师创建，学生凭班级码加入）
class ClassItem {
  final String id; // 班级 id（uuid）
  final String name; // 班级名
  final String code; // 6 位班级码（学生加入凭证）
  final String teacherId; // 建班老师 uid
  final String? teacherName; // 老师昵称（列表接口拼好的，可能为 null）
  final String? createdAt; // 创建时间（ISO 8601 字符串）

  const ClassItem({
    required this.id,
    required this.name,
    required this.code,
    required this.teacherId,
    this.teacherName,
    this.createdAt,
  });

  /// 从后端接口返回的一行 JSON 转成 ClassItem
  factory ClassItem.fromJson(Map<String, dynamic> json) {
    return ClassItem(
      id: json['id'] as String,
      name: json['name'] as String,
      code: json['code'] as String,
      teacherId: json['teacher_id'] as String,
      teacherName: json['teacher_name'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }
}
