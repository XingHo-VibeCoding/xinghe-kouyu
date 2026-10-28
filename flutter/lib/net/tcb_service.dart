// =====================================================================
// CloudBase 云服务封装（单例）
// ---------------------------------------------------------------------
// 职责：初始化 + 匿名登录 + 文件直传云存储（PG 桶模型）。
//
// 关键背景（PG 模式存储，与旧 NoSQL 存储不同）：
//   1. 文件路径 = "<桶名>/<文件key>"，桶需在控制台建好（本项目桶名 class-files）。
//   2. 「获取上传信息」接口要求请求体带 signedHeader（content-length/content-type
//      的数组），否则报 STORAGE_CONTENT_LENGTH_REQUIRED——官方 Flutter SDK 1.2.3
//      没做这一步，所以这里不用 SDK 的 storage，改为直接走 HTTP。
//   3. RLS：storage.objects 表默认全拒，已配 public_select / public_insert 策略。
//
// 认证：
//   - accessKey 是「Publishable Key（可发布密钥）」，角色 anon，可安全写进 App。
//   - 匿名登录拿 access_token 当鉴权头。
// =====================================================================

import 'dart:typed_data';

import 'package:cloudbase_flutter/cloudbase_flutter.dart';
import 'package:dio/dio.dart' as dio_pkg;

/// 环境配置（env + Publishable Key）
const String kTcbEnvId = 'xinghe-kouyu-d7gi1d7ttc7e032ba';
const String kTcbAccessKey = 'eyJhbGciOiJSUzI1NiIsImtpZCI6ImRmNTc2NDFiLTdiYjMtNGViYy1hNDY1LWMyOGRmZTEyOGI4NCJ9.eyJpc3MiOiJodHRwczovL3hpbmdoZS1rb3V5dS1kN2dpMWQ3dHRjN2UwMzJiYS5hcC1zaGFuZ2hhaS50Y2ItYXBpLnRlbmNlbnRjbG91ZGFwaS5jb20iLCJzdWIiOiJhbm9uIiwiYXVkIjoieGluZ2hlLWtvdXl1LWQ3Z2kxZDd0dGM3ZTAzMmJhIiwiZXhwIjo0MDk2Nzg4MzY2LCJpYXQiOjE3OTMxMDUxNjYsIm5vbmNlIjoiT0R0ek5FZjdRSG1nYVBfZGdRSUtKZyIsImF0X2hhc2giOiJPRHR6TkVmN1FIbWdhUF9kZ1FJS0pnIiwibmFtZSI6IkFub255bW91cyIsInNjb3BlIjoiYW5vbnltb3VzIiwicHJvamVjdF9pZCI6InhpbmdoZS1rb3V5dS1kN2dpMWQ3dHRjN2UwMzJiYSIsIm1ldGEiOnsicGxhdGZvcm0iOiJQdWJsaXNoYWJsZUtleSJ9LCJyb2xlIjoiYW5vbiIsImlzX2Fub255bW91cyI6dHJ1ZSwiYXBwX21ldGFkYXRhIjp7InByb3ZpZGVyIjoiYW5vbnltb3VzIiwicHJvdmlkZXJzIjpbImFub255bW91cyJdfSwidXNlcl9tZXRhZGF0YSI6eyJuYW1lIjoiQW5vbnltb3VzIn0sInVzZXJfdHlwZSI6IiIsImNsaWVudF90eXBlIjoiY2xpZW50X3VzZXIiLCJpc19zeXN0ZW1fYWRtaW4iOmZhbHNlfQ.tUJIsK3LVPVdkHTXROyHBtSytmu_FCUPJVK1KR_RHTqytsvM1dWf34xh15F3r_8cyTtuS0mp0KScbFUZZvmSMZ3Evzay6_MEfsY4OsYAVnYQLnUaRXzoMnhJriV5LtRrNSulj32ix1HhHOLcVJe_wHikc0VFf3-5ghy5TDk_ygEBFNTzu5JYQKJOEF5YVs7Y3XYIAGaxBomTGYVaLlG0V3LRMd8w0yR1fU__qDOGDNeQhylONC0lpImdeSha4JkkkGpoRrpsHEwcm0Y9pmQjphQPrvPPxmQtzKY6ZRVS4IVVLsXGFWc-xBAHZjlNV5tducDGhtAsyqf4abltC8gaLg';

/// 存储桶名（控制台已创建，PG 模式路径第一段就是桶名）
const String kTcbBucket = 'class-files';

/// 桶 ID（固定，用于拼正确的 cloudObjectId；download-info 接口要求带桶 ID 后缀）
const String _bucketId = '7869-$kTcbEnvId-1501128141';

/// CloudBase 云服务单例
class TcbService {
  TcbService._();

  static CloudBase? _app;
  static String? _accessToken; // 匿名登录拿到的会话 token

  static String get _gateway => 'https://$kTcbEnvId.api.tcloudbasegateway.com';

  /// 拿共享的 CloudBase 应用实例（懒初始化，只 init 不登录）
  ///
  /// Day 24 起账号服务（AuthService）也用这个实例——全 App 只有一个
  /// CloudBase 实例，会话（含登录态）只有一份，避免两个实例的本地会话
  /// 互相覆盖（SDK 的会话持久化按环境 ID 存，同环境共用一份）。
  static Future<CloudBase> app() async {
    _app ??= await CloudBase.init(
      env: kTcbEnvId,
      region: 'ap-shanghai',
      accessKey: kTcbAccessKey,
    );
    return _app!;
  }

  /// 初始化 + 匿名登录（幂等：重复调用不重复做）
  static Future<void> ensureReady() async {
    if (_accessToken != null) return;

    // 用 SDK 做初始化 + 匿名登录，拿到会话 token（SDK 的登录是好的，只有 storage 有 bug）
    final CloudBase cloud = await app();
    final result = await cloud.auth.signInAnonymously();
    if (!result.isSuccess) {
      throw Exception('匿名登录失败: ${result.error?.message}');
    }
    // 从登录结果里取会话 access token（后续自己走 HTTP 时当 Authorization）
    _accessToken =
        result.data?.session?.accessToken ?? kTcbAccessKey;
  }

  /// 统一的超时配置（不加超时的请求一旦挂起，界面会永远转圈）
  static dio_pkg.Options _opts({Map<String, dynamic>? headers}) {
    return dio_pkg.Options(
      headers: headers,
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    );
  }

  /// 直传文件到云存储（PG 桶模型，完全走 HTTP，绕开 SDK storage 的 signedHeader bug）
  ///
  /// 流程：匿名登录拿 token → get-objects-upload-info（带 signedHeader）
  ///       → PUT 字节到 COS uploadUrl → 返回 fileID（cloud://...）
  static Future<String> uploadBytes(
    String key, // 桶内的文件 key（不含桶名）
    Uint8List bytes, {
    String contentType = 'application/octet-stream',
  }) async {
    await ensureReady();

    final dio = dio_pkg.Dio();

    // 1. 获取上传信息（PG 模式必须带 signedHeader，否则报 CONTENT_LENGTH_REQUIRED）
    final String objectId = '$kTcbBucket/$key';
    final uploadInfoResp = await dio.post<dynamic>(
      '$_gateway/v1/storages/get-objects-upload-info',
      queryParameters: {'client_id': kTcbEnvId},
      data: <Map<String, dynamic>>[
        <String, dynamic>{
          'objectId': objectId,
          'signedHeader': <String, dynamic>{
            'content-length': <String>['${bytes.length}'],
            'content-type': <String>[contentType],
          },
        },
      ],
      options: _opts(headers: <String, dynamic>{
        'Authorization': 'Bearer $_accessToken',
        'x-device-id': 'xinghe-flutter-app',
      }),
    );

    final List<dynamic> list = (uploadInfoResp.data as List<dynamic>);
    final Map<String, dynamic> info = list.first as Map<String, dynamic>;
    if (info['code'] != null) {
      throw Exception('获取上传信息失败: ${info['message'] ?? info['code']}');
    }

    final String uploadUrl = info['uploadUrl'] as String;
    final String? authorization = info['authorization'] as String?;
    final String? token = info['token'] as String?;

    // 2. 直传 COS（PUT 字节数组，dio 自动带 Content-Length）
    await dio.put<void>(
      uploadUrl,
      data: bytes,
      options: dio_pkg.Options(
        headers: <String, dynamic>{
          'Content-Type': contentType,
          'Authorization': ?authorization,
          'x-cos-security-token': ?token,
        },
        sendTimeout: const Duration(minutes: 5),
        receiveTimeout: const Duration(minutes: 5),
      ),
    );

    // 3. 拼出 fileID（cloud://envId.桶/key），这就是账本 cloud_path 要存的值
    return 'cloud://$kTcbEnvId/$objectId';
  }

  /// 拿文件的临时下载 URL（供播放/下载）
  ///
  /// cloudPath 是账本里存的 `cloud://envId/桶/key`（上传时拼的），
  /// 但 download-info 接口要求带桶 ID 后缀的 `cloud://envId.<桶ID>/桶/key`，
  /// 这里做字符串转换后调接口，返回带签名的直接下载链接。
  static Future<String> getDownloadUrl(String cloudPath) async {
    await ensureReady();

    // 转成带桶 ID 后缀的 cloudObjectId
    final String cloudObjectId = cloudPath.replaceFirst(
      'cloud://$kTcbEnvId/',
      'cloud://$kTcbEnvId.$_bucketId/',
    );

    final dio = dio_pkg.Dio();
    final resp = await dio.post<dynamic>(
      '$_gateway/v1/storages/get-objects-download-info',
      queryParameters: {'client_id': kTcbEnvId},
      data: <Map<String, String>>[
        <String, String>{'cloudObjectId': cloudObjectId},
      ],
      options: _opts(headers: <String, dynamic>{
        'Authorization': 'Bearer $_accessToken',
        'x-device-id': 'xinghe-flutter-app',
      }),
    );

    final List<dynamic> list = resp.data as List<dynamic>;
    final Map<String, dynamic> info = list.first as Map<String, dynamic>;
    if (info['code'] != null) {
      throw Exception('获取下载链接失败: ${info['message'] ?? info['code']}');
    }
    return info['downloadUrl'] as String;
  }
}
