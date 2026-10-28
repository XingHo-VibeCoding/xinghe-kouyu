// =====================================================================
// 用户身份仓库（Provider 状态中枢）—— Day 24 重构：认证与资料对接
// ---------------------------------------------------------------------
// 这个类管两件不同的事，理解它们分开才不糊涂：
//
//   ① 认证（Authentication）：「你是谁」——uid 从哪来。
//      已登录 = CloudBase 会话里的 UID（跨设备一致）；
//      游客   = 本地生成的设备 uid（重装即失效）。
//
//   ② 资料（Profile）：「你叫什么、你是老师还是学生」——users 表。
//      昵称/角色存在云端 users 表，按 uid 关联。
//      【真相源是云端】：本地只是缓存，登录后必须拉一次对齐，
//      写入时也必须云端成功才更新本地（否则会出现"本地以为成功、
//      云端没有"的分裂状态，建班时才发现用户不存在）。
//
// 三个状态（UI 据此决定「班级」栏显示什么）：
//   isSignedIn   = false               → 登录引导页（游客态）
//   isSignedIn   = true, profileReady=false → 完善资料页（填昵称+角色）
//   isSignedIn   = true, profileReady=true  → 真正的班级列表
//
// 为什么这么设计：建班/加入在云函数里都要先查 users 表（存在 + 角色对），
// 资料没完善就放进去，用户只会撞上「用户不存在，请先登记身份」这种死路。
// =====================================================================

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';
import '../models/user_role.dart';
import '../net/api_client.dart';
import '../net/auth_service.dart';

// 兼容旧代码：原先 UserRole 定义在本文件，profile_page / api_client 等
// 都从 store/user_store.dart 引入。这里再导出一次，避免大面积改 import。
export '../models/user_role.dart';

/// 用户身份仓库
class UserStore extends ChangeNotifier {
  UserStore({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  /// 设备级 uid 的存储键（Day 20 起沿用，不要改名——改了老设备会生成新
  /// uid，导致旧班级记录"丢失"）
  static const String _kUid = 'user.uid';
  static const String _kNickname = 'user.nickname';
  static const String _kRole = 'user.role';

  String _deviceUid = ''; // 设备级 uid（游客态身份）
  String _accountUid = ''; // CloudBase UID（空 = 未登录）
  String _nickname = '';
  UserRole? _role;
  bool _profileReady = false; // 云端 users 表里是否有本账号的资料

  /// 当前业务身份：已登录 = CloudBase UID；游客 = 设备 uid
  String get uid => _accountUid.isNotEmpty ? _accountUid : _deviceUid;

  /// 设备级 uid（联调、排查问题时用；业务逻辑请用 uid）
  String get deviceUid => _deviceUid;

  /// 是否已登录（有有效账号会话）
  bool get isSignedIn => _accountUid.isNotEmpty;

  /// 云端资料是否已就绪（昵称 + 角色已从 users 表取到）
  bool get profileReady => _profileReady;

  String get nickname => _nickname;
  UserRole? get role => _role;

  /// 是否已完成资料登记（本地口径，仅用于兼容旧调用）
  bool get isRegistered => _nickname.isNotEmpty && _role != null;

  // ------------------------------------------------------------------
  // 启动
  // ------------------------------------------------------------------

  /// 启动时调用一次：先读本地缓存（快，不阻塞首屏），再异步对齐云端
  Future<void> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    _deviceUid = prefs.getString(_kUid) ?? '';
    if (_deviceUid.isEmpty) {
      // 首次启动：本地生成一个 uid（去掉 UUID 里的横线，更短、更干净）
      _deviceUid = _genUid();
      await prefs.setString(_kUid, _deviceUid);
    }

    _nickname = prefs.getString(_kNickname) ?? '';
    _role = userRoleFromName(prefs.getString(_kRole));

    // 先让界面用本地缓存立刻渲染，再后台确认登录态 + 拉云端资料
    notifyListeners();
    await syncAccount();
  }

  // ------------------------------------------------------------------
  // 认证：登录态同步
  // ------------------------------------------------------------------

  /// 同步登录态（App 启动 / 登录成功 / 注册成功后调用）
  ///
  /// 拿到 uid 后立刻拉云端资料——只同步 uid 不同步资料，App 就是「知道
  /// 你是谁但不知道你叫什么、什么角色」，建班/加入全都会失败。
  Future<void> syncAccount() async {
    final String? accountUid = await AuthService.currentUid();
    final String next = accountUid ?? '';
    if (next == _accountUid) return; // 身份没变，不重复请求

    _accountUid = next;
    if (next.isEmpty) {
      // 未登录：资料态一并失效（游客没有云端资料）
      _profileReady = false;
      notifyListeners();
      return;
    }

    notifyListeners(); // 先让界面切到「已登录」，再等资料
    await syncProfileFromCloud();
  }

  /// 从云端 users 表拉本账号资料，覆盖本地缓存
  ///
  /// 三种结果：
  ///   - 云端有记录 → profileReady = true，昵称/角色以云端为准（写回本地缓存）
  ///   - 云端无记录 → profileReady = false，清空本地残留昵称/角色（可能是
  ///     别的账号留下的，留着会误导用户）
  ///   - 网络失败   → 保持现状（不能因为一次网络抖动就把已登录用户当成
  ///     「资料未完善」，那样用户会被反复要求填资料）
  Future<void> syncProfileFromCloud() async {
    if (_accountUid.isEmpty) {
      _profileReady = false;
      notifyListeners();
      return;
    }

    final ApiResult<UserProfile?> res = await _api.fetchUser(_accountUid);
    if (!res.ok) return;

    final UserProfile? profile = res.data;
    if (profile == null) {
      _profileReady = false;
      _nickname = '';
      _role = null;
      await _clearProfileCache();
    } else {
      _profileReady = true;
      _nickname = profile.nickname;
      _role = profile.role;
      await _cacheProfile();
    }
    notifyListeners();
  }

  /// 登出：清云端会话 + 账号资料；本地素材/播放进度不受影响
  ///
  /// 注意：昵称和角色属于「账号资料」，登出后必须清掉——否则游客态会
  /// 顶着上一个账号的昵称，看起来像没登出。
  Future<void> signOut() async {
    try {
      await AuthService.signOut();
    } catch (_) {
      // 登出请求失败也要清本地登录态，否则用户会被困在"登不出去"的状态
    }
    _accountUid = '';
    _profileReady = false;
    _nickname = '';
    _role = null;
    await _clearProfileCache();
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // 资料：登记 / 修改昵称与角色
  // ------------------------------------------------------------------

  /// 保存资料：**先写云端，成功后才更新本地**
  ///
  /// 顺序不能反。先写本地的话，云端一失败就出现「App 认为你是老师、
  /// 数据库里没你这人」的分裂状态，下次建班才暴露，排查成本极高。
  Future<ApiResult<void>> saveProfile({
    required String nickname,
    required UserRole role,
  }) async {
    if (_accountUid.isEmpty) {
      return ApiResult.fail('请先登录后再设置昵称和身份');
    }
    final String trimmed = nickname.trim();
    final ApiResult<void> res =
        await _api.registerUser(_accountUid, trimmed, role);
    if (!res.ok) return res; // 云端失败：本地一个字都不改

    _nickname = trimmed;
    _role = role;
    _profileReady = true;
    await _cacheProfile();
    notifyListeners();
    return res;
  }

  // ------------------------------------------------------------------
  // 本地缓存（只是加速首屏，权威数据在云端）
  // ------------------------------------------------------------------

  Future<void> _cacheProfile() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kNickname, _nickname);
    if (_role != null) await prefs.setString(_kRole, _role!.name);
  }

  Future<void> _clearProfileCache() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kNickname);
    await prefs.remove(_kRole);
  }

  /// 生成一个本地 uid：时间戳 + 随机数拼起来，足够当「设备身份」用
  String _genUid() {
    final int ts = DateTime.now().millisecondsSinceEpoch;
    final int rand = Random().nextInt(0x7fffffff);
    return 'dev-$ts-$rand';
  }
}
