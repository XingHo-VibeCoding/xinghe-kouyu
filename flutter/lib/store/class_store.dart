// =====================================================================
// 班级仓库（Provider 状态中枢，管理「我的班级列表」的加载与增删）
// ---------------------------------------------------------------------
// 职责：页面通过 Provider 读写这里的 status / classes，触发联网加载、
//       建班、加入等操作，并把结果回传给页面。
//
// 依赖：ApiClient（发请求）。uid 由调用方传入（页面从 UserStore 拿），
//       保持本仓库职责单一，不反向依赖 UserStore。
// 语言：Dart。不碰 SQL，不画界面，只做「业务状态 + 调接口」。
// =====================================================================

import 'package:flutter/foundation.dart';

import '../models/class_item.dart';
import '../net/api_client.dart';

/// 班级列表的加载状态：加载中 / 空 / 出错 / 有数据（沿用素材列表的四态约定）
enum ClassListStatus { loading, empty, error, data }

/// 班级仓库
class ClassStore extends ChangeNotifier {
  final ApiClient _api;

  ClassListStatus _status = ClassListStatus.loading;
  ClassListStatus get status => _status;

  final List<ClassItem> _classes = <ClassItem>[];
  List<ClassItem> get classes => List.unmodifiable(_classes);

  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  ClassStore({required ApiClient api}) : _api = api;

  /// 加载我的班级列表（联网查，uid 由调用方传入）
  Future<void> load(String uid) async {
    // 双保险：uid 未就绪（本地身份还没读出来）时不发请求，
    // 避免后端报「缺少 uid 参数」。等 uid 就绪后页面会再次触发加载。
    if (uid.isEmpty) return;
    _status = ClassListStatus.loading;
    notifyListeners();
    try {
      final ApiResult<List<ClassItem>> result = await _api.myClasses(uid);
      if (!result.ok) {
        _errorMessage = result.message;
        _status = ClassListStatus.error;
      } else {
        _classes
          ..clear()
          ..addAll(result.data!);
        _status = _classes.isEmpty ? ClassListStatus.empty : ClassListStatus.data;
      }
    } catch (e) {
      _errorMessage = '网络异常：$e';
      _status = ClassListStatus.error;
    }
    notifyListeners();
  }

  /// 建班（老师）：成功返回带班级码的新班级
  Future<ApiResult<ClassItem>> createClass(String uid, String name) async {
    return _api.createClass(uid, name);
  }

  /// 加入班级（学生）
  Future<ApiResult<void>> joinClass(String uid, String code) async {
    return _api.joinClass(uid, code);
  }

  /// 判断「我是否已有班级记录」（用于锁定身份：有记录后禁止改角色）
  Future<ApiResult<bool>> hasAnyClass(String uid) async {
    return _api.hasAnyClass(uid);
  }
}
