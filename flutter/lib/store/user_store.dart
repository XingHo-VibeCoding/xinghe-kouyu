// =====================================================================
// 用户身份仓库（班级管理 MVP 的身份层，Provider 状态中枢）
// ---------------------------------------------------------------------
// 职责：管理「这台设备」的身份三要素 —— uid / nickname / role。
//
// 关键设计（方案 A，本地生成 UID）：
//   - uid：首次启动本地生成一个 UUID，存进 shared_preferences，之后一直复用。
//     它标识「这台设备」，作为业务用户身份的凭证传给后端（后端只当字符串用，
//     不校验它是否来自真登录）。将来换真用户登录，只改「uid 从哪来」这一处。
//   - nickname / role：首次进入 App 时让用户填一次，之后记住。
//
// 语言：Dart。存储用 shared_preferences（键值对），不写 SQLite——身份信息
//       是「全局一份、结构固定」，用键值对最省事。
// =====================================================================

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 用户角色：老师（可建班）/ 学生（可加入）
enum UserRole { teacher, student }

/// 用户身份仓库：提供 uid/nickname/role 的读写 + 是否已完成首次登记
class UserStore extends ChangeNotifier {
  static const String _kUid = 'user.uid';
  static const String _kNickname = 'user.nickname';
  static const String _kRole = 'user.role';

  String _uid = '';
  String _nickname = '';
  UserRole? _role;

  String get uid => _uid;
  String get nickname => _nickname;
  UserRole? get role => _role;

  /// 是否已完成首次登记（填过昵称 + 选过角色）
  bool get isRegistered => _nickname.isNotEmpty && _role != null;

  /// 启动时调用一次：从本地读身份；首次则生成 uid
  Future<void> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    _uid = prefs.getString(_kUid) ?? '';
    if (_uid.isEmpty) {
      // 首次启动：本地生成一个 uid（去掉 UUID 里的横线，更短、更干净）
      _uid = _genUid();
      await prefs.setString(_kUid, _uid);
    }

    _nickname = prefs.getString(_kNickname) ?? '';
    final String? roleStr = prefs.getString(_kRole);
    _role = roleStr == null ? null : UserRole.values.firstWhere(
      (UserRole r) => r.name == roleStr,
      orElse: () => UserRole.student,
    );

    notifyListeners();
  }

  /// 登记身份（首次进入填昵称 + 选角色后调用）
  Future<void> register({
    required String nickname,
    required UserRole role,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _nickname = nickname.trim();
    _role = role;
    await prefs.setString(_kNickname, _nickname);
    await prefs.setString(_kRole, role.name);
    notifyListeners();
  }

  /// 生成一个本地 uid：时间戳 + 随机数拼起来，足够当「设备身份」用
  String _genUid() {
    final int ts = DateTime.now().millisecondsSinceEpoch;
    final int rand = Random().nextInt(0x7fffffff);
    return 'dev-$ts-$rand';
  }
}
