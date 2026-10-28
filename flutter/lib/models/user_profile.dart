// =====================================================================
// 模型「云端用户资料」（对应数据库 users 表的一行）
// ---------------------------------------------------------------------
// 这是「身份认证」和「数据库」之间的桥：
//   身份认证（CloudBase Auth）负责回答「你是谁」（uid）；
//   users 表负责回答「你叫什么、你是老师还是学生」（nickname / role）。
// 两者通过 uid ↔ users.id 关联。登录后必须来这里取一次资料，
// 否则 App 只知道 uid，不知道昵称和角色（建班/加入都会失败）。
// =====================================================================

import 'user_role.dart';

/// 云端用户资料（users 表一行）
class UserProfile {
  final String id; // = 账号 uid
  final String nickname;
  final UserRole role;

  const UserProfile({
    required this.id,
    required this.nickname,
    required this.role,
  });

  /// 从接口 JSON 构造。role 非法时按学生兜底（数据库有 NOT NULL 约束，
  /// 正常不会出现脏值；兜底只为不崩）。
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: (json['id'] ?? '').toString(),
      nickname: (json['nickname'] ?? '').toString(),
      role: userRoleFromName(json['role']?.toString()) ?? UserRole.student,
    );
  }
}
