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

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/class_file.dart';
import '../models/class_item.dart';
import '../models/class_member.dart';
import '../models/user_profile.dart';
import '../models/user_role.dart';

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
  ///
  /// 网络异常一律翻译成 code=-1 的结果，**不让异常穿透到调用方**。
  /// 原因（Day 24 修 BUG）：调用方普遍是 `if (!res.ok)` 的写法，一旦这里
  /// 抛异常，整条调用链会在 await 处中断，后面的状态更新全部不执行——
  /// 典型后果就是「断网启动 App，资料同步被打断，界面永久停在完善资料页」。
  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final Uri uri = Uri.parse('$kApiBase$path');
      final http.Response resp = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      return _decode(resp);
    } on TimeoutException {
      return _netFail('网络连接超时，请检查网络后重试');
    } catch (e) {
      return _netFail('网络连接失败，请检查网络后重试');
    }
  }

  /// 发一个 GET 请求，返回 { code, message, data }（异常处理同 _postJson）
  Future<Map<String, dynamic>> _getJson(
    String path,
    Map<String, String> query,
  ) async {
    try {
      final Uri uri = Uri.parse('$kApiBase$path')
          .replace(queryParameters: query);
      final http.Response resp = await _client
          .get(uri)
          .timeout(const Duration(seconds: 10));
      return _decode(resp);
    } on TimeoutException {
      return _netFail('网络连接超时，请检查网络后重试');
    } catch (e) {
      return _netFail('网络连接失败，请检查网络后重试');
    }
  }

  /// 统一的网络失败返回体（形状与后端三件套一致，调用方无需区分来源）
  Map<String, dynamic> _netFail(String message) => <String, dynamic>{
    'code': -1,
    'message': message,
    'data': {},
  };

  /// 解析响应：先看 HTTP 是否成功，再解析 JSON，抽成三件套
  Map<String, dynamic> _decode(http.Response resp) {
    if (resp.statusCode != 200) {
      return {
        'code': -1,
        'message': '网络请求失败（HTTP ${resp.statusCode}）',
        'data': {},
      };
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
  ///
  /// 云端是 upsert（同一 uid 重复登记 = 更新），所以「登记」和「改昵称」
  /// 共用这一个接口。
  Future<ApiResult<void>> registerUser(
    String uid,
    String nickname,
    UserRole role, {
    String? username,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'uid': uid,
      'nickname': nickname,
      'role': role.name,
      // username 可选：注册时设置的登录用户名（Day 24 加进 users 表），
      // 空值不传，后端不会拿空把已有用户名抹掉
      if (username != null && username.isNotEmpty) 'username': username,
    };
    final Map<String, dynamic> r = await _postJson('/users', body);
    if (r['code'] == 0) return ApiResult.success(null);
    return ApiResult.fail(r['message']?.toString() ?? '登记失败');
  }

  /// 查「本账号在 users 表的资料」（昵称 + 角色）。
  ///
  /// 返回 null 表示云端没有这个 uid 的记录 = 资料未完善。
  /// 登录后必须调一次：认证只告诉我们 uid，昵称和角色只有这张表知道。
  ///
  /// 注意：这里按 id 精确匹配，不能取 list.first。原因——如果云函数还没
  /// 部署「?uid=」新版本，后端会忽略该参数返回全部用户，取 first 就会把
  /// 别人的昵称和角色当成自己的（把学生显示成老师，权限全乱）。
  Future<ApiResult<UserProfile?>> fetchUser(String uid) async {
    final Map<String, dynamic> r = await _getJson('/users', {'uid': uid});
    if (r['code'] != 0) {
      return ApiResult.fail(r['message']?.toString() ?? '查询资料失败');
    }
    final List<dynamic> list = (r['data'] as List<dynamic>? ?? const []);
    for (final dynamic item in list) {
      final Map<String, dynamic> row = item as Map<String, dynamic>;
      if (row['id']?.toString() == uid) {
        return ApiResult.success(UserProfile.fromJson(row));
      }
    }
    return ApiResult.success(null); // 云端确实没有这个 uid
  }

  /// 老师建班：返回新班级（含班级码）
  Future<ApiResult<ClassItem>> createClass(String uid, String name) async {
    final Map<String, dynamic> r = await _postJson('/classes', {
      'action': 'create',
      'uid': uid,
      'name': name,
    });
    if (r['code'] == 0) {
      return ApiResult.success(
        ClassItem.fromJson(r['data'] as Map<String, dynamic>),
      );
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
      return ApiResult.success(
        list
            .map((dynamic e) => ClassItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
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

  /// 查「某班成员列表」
  Future<ApiResult<List<ClassMember>>> classMembers(String classId) async {
    final Map<String, dynamic> r = await _getJson('/classes/members', {
      'class_id': classId,
    });
    if (r['code'] == 0) {
      final List<dynamic> list = (r['data'] as List<dynamic>? ?? const []);
      return ApiResult.success(
        list
            .map((dynamic e) => ClassMember.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    }
    return ApiResult.fail(r['message']?.toString() ?? '查询失败');
  }

  /// 查「某班文件列表」
  Future<ApiResult<List<ClassFile>>> classFiles(String classId) async {
    final Map<String, dynamic> r = await _getJson('/classes/files', {
      'class_id': classId,
    });
    if (r['code'] == 0) {
      final List<dynamic> list = (r['data'] as List<dynamic>? ?? const []);
      return ApiResult.success(
        list
            .map((dynamic e) => ClassFile.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    }
    return ApiResult.fail(r['message']?.toString() ?? '查询失败');
  }

  /// 上传文件记元数据（文件本体已直传云存储后调用）
  Future<ApiResult<ClassFile>> addClassFile({
    required String classId,
    required String title,
    required String cloudPath,
    int? size,
    String? format,
    required String uploaderId,
  }) async {
    final Map<String, dynamic> r = await _postJson('/classes/files', {
      'class_id': classId,
      'title': title,
      'cloud_path': cloudPath,
      'size': size,
      'format': format,
      'uploader_id': uploaderId,
    });
    if (r['code'] == 0) {
      return ApiResult.success(
        ClassFile.fromJson(r['data'] as Map<String, dynamic>),
      );
    }
    return ApiResult.fail(r['message']?.toString() ?? '上传失败');
  }
}
