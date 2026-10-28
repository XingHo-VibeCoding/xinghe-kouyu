// =====================================================================
// 账号服务封装（CloudBase v2 身份认证，Day 24 新增）
// ---------------------------------------------------------------------
// 职责：注册（手机号短信验证码，顺带设用户名+密码）、密码登录、登出、
//       查当前登录态和 uid。页面层只调这里，不直接碰 SDK 类型。
//
// 关键认知（读 SDK 1.2.3 源码 + 官方文档双重确认，写代码前已验证）：
//   1. CloudBase 不允许直接「用户名+密码」注册（防恶意注册），必须走
//      手机号/邮箱验证码，注册时可顺带设置 username / password。
//   2. SDK 的 signUp() 内部自己会调发码接口——千万不要先手动
//      getVerification() 再 signUp()，否则手机会收到两条短信、扣两次费。
//      正确两步用法：
//        signUp(SignUpReq(phone, username, password))  → SDK 发 1 条短信
//        → 用户填码 → signUpRes.data!.verifyOtp(验证码) → 完成注册并自动登录
//      若该手机号已注册过，verifyOtp 内部自动转为「验证码登录」，不报错。
//   3. 会话（access_token 2小时 / refresh_token 30天）由 SDK 自动持久化到
//      SharedPreferences 并在过期前自动续期，App 重启仍是登录态，
//      本类不需要自己管理持久化。
//   4. uid = session.user.id（即官方 token 响应里的 sub），全局唯一、跨设备一致，
//      这是业务 users 表要用的用户标识。
// =====================================================================

import 'package:cloudbase_flutter/cloudbase_flutter.dart';

import 'tcb_service.dart';

/// 账号操作结果：页面层只看 ok / message，不接触 SDK 类型
class AuthResult {
  final bool ok;
  final String message;

  const AuthResult._({required this.ok, required this.message});

  const AuthResult.ok() : this._(ok: true, message: 'ok');
  const AuthResult.fail(String msg) : this._(ok: false, message: msg);
}

/// 账号服务（静态类：整个 App 共用一个 CloudBase 实例即可）
class AuthService {
  AuthService._();

  /// 拿共享的 CloudBase 应用实例（初始化逻辑收敛在 TcbService）
  static Future<CloudBase> _app() => TcbService.app();

  /// 注册第一步的上下文（SDK 的 verifyOtp 回调存在 signUpRes 里）。
  /// 全 App 同时只会有一个注册流程在走，存静态字段即可；完成注册后清空。
  static SignUpRes? _pendingSignUp;

  // ------------------------------------------------------------------
  // 注册：两步式（发码 → 验码完成注册）
  // ------------------------------------------------------------------

  /// 第一步：申请注册（SDK 会向该手机号发送 1 条短信验证码）
  /// 用户名/密码在此一并传入：新用户注册时写入账号；已注册用户忽略。
  static Future<AuthResult> requestSignUpCode({
    required String phone,
    required String username,
    required String password,
  }) async {
    try {
      final CloudBase app = await _app();
      final SignUpRes res = await app.auth.signUp(SignUpReq(
        phone: phone, // SDK 内部自动补 "+86 " 前缀
        username: username,
        password: password,
      ));
      if (res.error != null) {
        return AuthResult.fail(res.error!.message ?? '操作失败');
      }
      _pendingSignUp = res; // 存好上下文，等第二步用
      return const AuthResult.ok();
    } catch (e) {
      return AuthResult.fail('网络异常：$e');
    }
  }

  /// 第二步：用户填入收到的验证码，完成注册（并自动登录）
  static Future<AuthResult> completeSignUp(String code) async {
    final SignUpRes? pending = _pendingSignUp;
    final callback = pending?.data?.verifyOtp;
    if (callback == null) {
      return const AuthResult.fail('请先获取验证码');
    }
    try {
      final SignInRes res = await callback(VerifyOtpParams(token: code));
      if (res.error != null) {
        return AuthResult.fail(res.error!.message ?? '操作失败');
      }
      _pendingSignUp = null; // 注册流程结束，清掉上下文
      return const AuthResult.ok();
    } catch (e) {
      return AuthResult.fail('网络异常：$e');
    }
  }

  // ------------------------------------------------------------------
  // 登录 / 登出
  // ------------------------------------------------------------------

  /// 密码登录：账号可以是「用户名」或「手机号」（纯 11 位数字按手机号处理）
  static Future<AuthResult> signInWithPassword({
    required String account,
    required String password,
  }) async {
    try {
      final CloudBase app = await _app();
      final bool isPhone = RegExp(r'^1\d{10}$').hasMatch(account);
      final SignInRes res = await app.auth.signInWithPassword(SignInWithPasswordReq(
        username: isPhone ? null : account,
        phone: isPhone ? account : null,
        password: password,
      ));
      if (res.error != null) {
        // 统一口径的通用提示由页面决定，这里透传原始信息
        return AuthResult.fail(res.error!.message ?? '操作失败');
      }
      return const AuthResult.ok();
    } catch (e) {
      return AuthResult.fail('网络异常：$e');
    }
  }

  /// 登出：SDK 内部会吊销 token 并清掉本地会话
  static Future<void> signOut() async {
    final CloudBase app = await _app();
    await app.auth.signOut();
  }

  // ------------------------------------------------------------------
  // 登录态查询
  // ------------------------------------------------------------------

  /// 当前是否已登录（本地有会话且能查到用户信息）
  static Future<bool> isSignedIn() async {
    return (await currentUid()) != null;
  }

  /// 当前登录用户的 uid（未登录返回 null）
  ///
  /// 实现：问 SDK 要当前会话。注意 SDK 的 getSession 会先检查 token 是否
  /// 过期、过期自动续期，所以这里拿到的 uid 一定是「有效会话」的。
  static Future<String?> currentUid() async {
    try {
      final CloudBase app = await _app();
      final SignInRes res = await app.auth.getSession();
      if (res.error != null) return null;
      return res.data?.session?.user?.id;
    } catch (_) {
      // 无会话/网络异常等一律视为未登录
      return null;
    }
  }
}
