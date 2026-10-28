// =====================================================================
// 页面「登录」：账号密码登录（Day 24 新增，PRD 3.7 节 F11）
// ---------------------------------------------------------------------
// 逻辑：账号（用户名或 11 位手机号）+ 密码 → AuthService.signInWithPassword
//       → 成功：同步账号身份（UserStore.syncAccount）后返回上一页
//       → 失败：统一提示「账号或密码不对」（不区分用户不存在/密码错，防撞库探测）
// 底部入口：「没有账号？去注册」→ 注册页。
// =====================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../net/auth_service.dart';
import '../store/user_store.dart';
import '../utils/design_tokens.dart';
import 'profile_setup_page.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _accountCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _loading = false; // 防重复提交
  bool _obscure = true; // 密码可见切换

  @override
  void dispose() {
    _accountCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  /// 提交登录
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final AuthResult res = await AuthService.signInWithPassword(
      account: _accountCtrl.text.trim(),
      password: _passwordCtrl.text,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (!res.ok) {
      // 统一口径：不区分「用户不存在」和「密码错误」，防撞库探测
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('账号或密码不对')),
      );
      return;
    }

    // 登录成功：让 UserStore 去 SDK 取 CloudBase UID（uid 换源），
    // 并拉一次云端 users 表资料——只换 uid 不拉资料，App 就是
    // 「知道你是谁、但不知道你叫什么/什么角色」。
    final UserStore userStore = context.read<UserStore>();
    await userStore.syncAccount();
    if (!mounted) return;

    // 云端还没有资料（新账号首次登录）→ 直接引导完善，
    // 别让用户到班级栏才撞上「用户不存在，请先登记身份」
    if (!userStore.profileReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登录成功，还需填写昵称和身份')),
      );
      final NavigatorState nav = Navigator.of(context);
      await nav.push(MaterialPageRoute<void>(
          builder: (_) => const ProfileSetupPage()));
      if (!mounted) return;
      nav.pop(); // 完善资料后回到上一页（我的）
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('登录成功')));
    Navigator.of(context).pop(); // 返回上一页（我的 / 班级引导页）
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: kTextPrimary),
        title: const Text('登录',
            style: TextStyle(
                color: kTextPrimary,
                fontSize: kFontTitle,
                fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text('欢迎回来',
                  style: TextStyle(
                      fontSize: kFontHero,
                      fontWeight: FontWeight.bold,
                      color: kTextPrimary)),
              const SizedBox(height: 8),
              const Text('登录后可以加入班级、接收老师发的课件',
                  style: TextStyle(fontSize: kFontBody, color: kTextSecondary)),
              const SizedBox(height: 32),

              // ---------- 账号 ----------
              TextFormField(
                controller: _accountCtrl,
                keyboardType: TextInputType.text,
                decoration: const InputDecoration(
                  labelText: '用户名 / 手机号',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                validator: (String? v) =>
                    (v == null || v.trim().isEmpty) ? '请输入账号' : null,
              ),
              const SizedBox(height: 16),

              // ---------- 密码 ----------
              TextFormField(
                controller: _passwordCtrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: '密码',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (String? v) =>
                    (v == null || v.isEmpty) ? '请输入密码' : null,
              ),
              const SizedBox(height: 32),

              // ---------- 登录按钮 ----------
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: kTeal,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(kRadiusBtn)),
                ),
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('登录', style: TextStyle(fontSize: kFontTitle)),
              ),
              const SizedBox(height: 16),

              // ---------- 去注册 ----------
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => const RegisterPage()));
                },
                child: const Text('没有账号？去注册',
                    style: TextStyle(color: kTeal, fontSize: kFontBody)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
