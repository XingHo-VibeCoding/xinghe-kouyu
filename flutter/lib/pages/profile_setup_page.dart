// =====================================================================
// 页面「完善资料」：填写昵称 + 选择身份（Day 24 新增，补齐认证与数据库的断点）
// ---------------------------------------------------------------------
// 为什么需要这一页（本次 bug 修复的核心）：
//   身份认证（CloudBase Auth）只回答「你是谁」（uid）。
//   「你叫什么、你是老师还是学生」存在云端 users 表里。
//   而建班/加入班级的云函数第一件事就是查 users 表：查不到就返回
//   「用户不存在，请先登记身份」——如果不在登录后立刻补这一步，
//   用户会卡在一个看不懂的报错上。
//
// 两种使用方式（同一份代码）：
//   1. 当「班级」栏的内容：已登录但 profileReady=false 时显示；
//      保存成功后 UserStore 通知重建，自动换成真正的班级列表。
//   2. 被 push 进来：从「我的」点头像修改资料时使用，保存后 pop 回去。
//
// 身份一旦有班级记录就锁定（沿用原逻辑），避免老师误改成学生丢权限。
// =====================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../net/api_client.dart';
import '../store/class_store.dart';
import '../store/user_store.dart';
import '../utils/design_tokens.dart';

class ProfileSetupPage extends StatefulWidget {
  const ProfileSetupPage({super.key});

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nicknameCtrl;
  UserRole _role = UserRole.student;

  bool _loading = false;
  bool _roleLocked = false; // 已有班级记录 → 身份不可改

  @override
  void initState() {
    super.initState();
    final UserStore userStore = context.read<UserStore>();
    _nicknameCtrl = TextEditingController(text: userStore.nickname);
    _role = userStore.role ?? UserRole.student;
    _checkRoleLock(userStore);
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    super.dispose();
  }

  /// 查「我是否已有班级记录」：有则锁定身份（沿用 Day 20 的规则）
  Future<void> _checkRoleLock(UserStore userStore) async {
    if (!userStore.isSignedIn) return;
    final ClassStore classStore = context.read<ClassStore>();
    final ApiResult<bool> res = await classStore.hasAnyClass(userStore.uid);
    if (!mounted) return;
    if (res.ok && res.data == true) {
      setState(() => _roleLocked = true);
    } else if (!res.ok && userStore.profileReady) {
      // 查询失败（断网 / 云函数抖动）但本地已有完整资料：说明之前云端
      // 确实有这个账号的记录，保守锁定角色——宁可暂时改不了身份，
      // 也不能让老师在不知情的情况下把自己改成学生、丢掉建班权限。
      setState(() => _roleLocked = true);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final UserStore userStore = context.read<UserStore>();
    final ApiResult<void> res = await userStore.saveProfile(
      nickname: _nicknameCtrl.text.trim(),
      role: _role,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    if (!res.ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：${res.message}')));
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('资料已保存')));
    // 被 push 进来时退回上一页；作为班级栏内容时无需跳转，
    // UserStore 的 notify 会让外层自动换成班级列表。
    final NavigatorState nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    // 被 push 进来时（能 pop）显示返回箭头；作为 tab 内容时不显示
    final bool canPop = Navigator.of(context).canPop();
    final UserStore userStore = context.watch<UserStore>();

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        automaticallyImplyLeading: canPop,
        iconTheme: const IconThemeData(color: kTextPrimary),
        title: const Text(
          '完善资料',
          style: TextStyle(
            color: kTextPrimary,
            fontSize: kFontTitle,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                '还差一步',
                style: TextStyle(
                  fontSize: kFontHero,
                  fontWeight: FontWeight.bold,
                  color: kTextPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '账号已登录成功，再填个昵称、选一下身份就能用班级了。\n身份决定你能不能建班，请按真实情况选。',
                style: TextStyle(
                  fontSize: kFontBody,
                  height: 1.5,
                  color: kTextSecondary,
                ),
              ),
              const SizedBox(height: 32),

              // ---------- 昵称 ----------
              TextFormField(
                controller: _nicknameCtrl,
                maxLength: 20,
                decoration: const InputDecoration(
                  labelText: '昵称（班级里显示给别人看）',
                  hintText: '如：小明 / 王老师',
                  prefixIcon: Icon(Icons.badge_outlined),
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
                validator: (String? v) {
                  final String s = v?.trim() ?? '';
                  if (s.isEmpty) return '请填一个昵称';
                  if (s.length > 50) return '昵称最长 50 个字';
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // ---------- 身份 ----------
              const Text(
                '我的身份',
                style: TextStyle(
                  fontSize: kFontBody,
                  fontWeight: FontWeight.w600,
                  color: kTextPrimary,
                ),
              ),
              const SizedBox(height: 10),
              if (_roleLocked)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.lock_outline, size: 14, color: kTextHint),
                      SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '你已有班级记录，身份已锁定不可修改',
                          style: TextStyle(
                            fontSize: kFontCaption,
                            color: kTextHint,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              // 本地已有身份（说明之前登记过）时给一句提醒：
              // 这一页正常不该出现，出现说明是网络问题导致资料没同步上，
              // 让用户知道「直接保存 = 覆盖云端记录」，别误点。
              else if (userStore.role != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.info_outline,
                        size: 14,
                        color: kTextHint,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '你之前登记的身份是「'
                          '${userStore.role == UserRole.teacher ? '老师' : '学生'}」'
                          '，改动会覆盖云端记录',
                          style: const TextStyle(
                            fontSize: kFontCaption,
                            color: kTextHint,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _roleChip(
                      label: '我是老师',
                      icon: Icons.school,
                      selected: _role == UserRole.teacher,
                      enabled: !_roleLocked,
                      onTap: () => setState(() => _role = UserRole.teacher),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _roleChip(
                      label: '我是学生',
                      icon: Icons.face,
                      selected: _role == UserRole.student,
                      enabled: !_roleLocked,
                      onTap: () => setState(() => _role = UserRole.student),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _role == UserRole.teacher
                    ? '老师可以创建班级、上传音视频'
                    : '学生可以输班级码加入、下载老师发的音频',
                style: const TextStyle(
                  fontSize: kFontCaption,
                  color: kTextHint,
                ),
              ),
              const SizedBox(height: 32),

              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: kTeal,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(kRadiusBtn),
                  ),
                ),
                onPressed: _loading ? null : _save,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '保存并进入',
                        style: TextStyle(fontSize: kFontTitle),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 身份选择 chip；enabled=false 时置灰不可点
  Widget _roleChip({
    required String label,
    required IconData icon,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final bool effective = enabled && selected;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: effective ? kTeal : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: effective
                ? kTeal
                : (enabled ? Colors.black26 : Colors.black12),
          ),
        ),
        child: Column(
          children: <Widget>[
            Icon(
              icon,
              color: effective
                  ? Colors.white
                  : (enabled ? Colors.black54 : Colors.black26),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: effective
                    ? Colors.white
                    : (enabled ? Colors.black87 : Colors.black26),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
