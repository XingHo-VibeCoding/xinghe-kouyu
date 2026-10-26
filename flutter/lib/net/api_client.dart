// =====================================================================
// 后端接口客户端（网络层，封装所有对云函数 HTTP API 的调用）
// ---------------------------------------------------------------------
// 职责：把「调后端」这件脏活（拼 URL、发请求、解析三件套、判错）集中在这里，
//       页面层只调用「登记身份 / 建班 / 加入 / 查班级列表」这几个语义清晰的方法。
//
// 约定（见 api-contract.md 第 1 节）：
//   - 所有接口响应都是 { code, message, data } 三件套；
//   - 判断成败只看 code（0 = 成功），不依赖 HTTP 状态码；
//   - 业务用户身份 uid 走请求体/查询参数传递（不走自定义头，防网关拦截）。
//
// 语言：Dart。用 http 包发请求，返回类型都用语义化的结果。
// =====================================================================

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/class_item.dart';
import '../store/user_store.dart';

/// 后端基础地址（云函数 HTTP 访问服务，见 api-contract.md 1.2）
const String kApiBase =
    'https://xinghe-kouyu-d7gi1d7ttc7e032ba-1501128141.ap-shanghai.app.tcloudbase.com/api';

/// 接口调用结果：成功时 data 有值；失败时 message 是给人看的原因
class ApiResult<T> {
  final bool ok;
  final String message;
  final T? data;

  const ApiResult._({required this.ok, required this.message, this.data});

  factory ApiResult.success(T data) =>
      ApiResult._(ok: true, message: 'ok', data: data);
  factory ApiResult.fail(String message) =>
      ApiResult._(ok: false, message: message);
}

/// 后端接口客户端
class ApiClient {
  final http.Client _client;

  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  /// 发一个 POST JSON 请求，返回 { code, message, data }
  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final Uri uri = Uri.parse('$kApiBase$path');
    final http.Response resp = await _client
        .post(uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 10));
    return _decode(resp);
  }

  /// 发一个 GET 请求，返回 { code, message, data }
  Future<Map<String, dynamic>> _getJson(
    String path,
    Map<String, String> query,
  ) async {
    final Uri uri = Uri.parse('$kApiBase$path').replace(queryParameters: query);
    final http.Response resp =
        await _client.get(uri).timeout(const Duration(seconds: 10));
    return _decode(resp);
  }

  /// 解析响应：先看 HTTP 是否成功，再解析 JSON，抽成三件套
  Map<String, dynamic> _decode(http.Response resp) {
    if (resp.statusCode != 200) {
      return {'code': -1, 'message': '网络请求失败（HTTP ${resp.statusCode}）', 'data': {}};
    }
    try {
      final dynamic body = jsonDecode(utf8.decode(resp.bodyBytes));
      if (body is Map<String, dynamic>) return body;
      return {'code': -1, 'message': '响应格式异常', 'data': {}};
    } catch (_) {
      return {'code': -1, 'message': '响应解析失败', 'data': {}};
    }
  }

  // ------------------------------------------------------------------
  // 业务方法（每个返回 ApiResult，页面只关心 ok / message / data）
  // ------------------------------------------------------------------

  /// 登记身份：首次进入填昵称+角色后，同步到云端 users 表
  Future<ApiResult<void>> registerUser(
      String uid, String nickname, UserRole role) async {
    final Map<String, dynamic> r = await _postJson('/users', {
      'uid': uid,
      'nickname': nickname,
      'role': role.name,
    });
    if (r['code'] == 0) return ApiResult.success(null);
    return ApiResult.fail(r['message']?.toString() ?? '登记失败');
  }

  /// 老师建班：返回新班级（含班级码）
  Future<ApiResult<ClassItem>> createClass(
      String uid, String name) async {
    final Map<String, dynamic> r =
        await _postJson('/classes', {'action': 'create', 'uid': uid, 'name': name});
    if (r['code'] == 0) {
      return ApiResult.success(ClassItem.fromJson(r['data'] as Map<String, dynamic>));
    }
    return ApiResult.fail(r['message']?.toString() ?? '建班失败');
  }

  /// 学生按班级码加入班级
  Future<ApiResult<void>> joinClass(String uid, String code) async {
    final Map<String, dynamic> r = await _postJson('/classes', {
      'action': 'join',
      'uid': uid,
      'code': code,
    });
    if (r['code'] == 0) return ApiResult.success(null);
    return ApiResult.fail(r['message']?.toString() ?? '加入失败');
  }

  /// 查「我的班级列表」
  Future<ApiResult<List<ClassItem>>> myClasses(String uid) async {
    final Map<String, dynamic> r = await _getJson('/classes', {'uid': uid});
    if (r['code'] == 0) {
      final List<dynamic> list = (r['data'] as List<dynamic>? ?? const []);
      return ApiResult.success(list
          .map((dynamic e) => ClassItem.fromJson(e as Map<String, dynamic>))
          .toList());
    }
    return ApiResult.fail(r['message']?.toString() ?? '查询失败');
  }

  /// 判断「我是否已有班级记录」（建过班或加入过班）。
  /// 复用 /classes 列表接口：列表非空 = 有记录。用于锁定身份（有记录后禁止改角色）。
  Future<ApiResult<bool>> hasAnyClass(String uid) async {
    final ApiResult<List<ClassItem>> result = await myClasses(uid);
    if (result.ok) {
      return ApiResult.success(result.data!.isNotEmpty);
    }
    return ApiResult.fail(result.message);
  }
}
