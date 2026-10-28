// =====================================================================
// 用户角色枚举（Day 24 从 user_store.dart 抽出）
// ---------------------------------------------------------------------
// 为什么单独一个文件：
//   角色要同时被三层用——models（云端资料）、net（接口参数）、store（状态）。
//   如果它留在 store 里，net 和 models 都要 import store，会形成
//   store → net → store 的循环依赖。抽到 models 层，三层都往下依赖，干净。
// 字符串值（teacher / student）与数据库 users.role 完全一致，可直接互转。
// =====================================================================

/// 用户角色：老师（可建班）/ 学生（可加入）
enum UserRole { teacher, student }

/// 字符串 → 角色；非法/空值返回 null（不猜、不默认，交由调用方决定兜底）
UserRole? userRoleFromName(String? name) {
  if (name == null) return null;
  for (final UserRole role in UserRole.values) {
    if (role.name == name) return role;
  }
  return null;
}
