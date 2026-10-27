// 班级成员数据模型（班级管理 MVP）
// 对应后端「某班成员列表」接口返回的结构

/// 一个班级成员（老师或学生）
class ClassMember {
  final String userId; // 成员 uid
  final String? nickname; // 昵称（拼自 users 表，可能为 null）
  final String role; // 班内角色：teacher / student
  final String? joinedAt; // 加入时间（ISO 8601）

  const ClassMember({
    required this.userId,
    this.nickname,
    required this.role,
    this.joinedAt,
  });

  /// 从后端接口返回的一行 JSON 转成 ClassMember
  factory ClassMember.fromJson(Map<String, dynamic> json) {
    return ClassMember(
      userId: json['user_id'] as String,
      nickname: json['nickname'] as String?,
      role: json['role'] as String,
      joinedAt: json['joined_at'] as String?,
    );
  }

  /// 是否老师
  bool get isTeacher => role == 'teacher';
}
