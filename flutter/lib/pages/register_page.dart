// =====================================================================
// 页面「注册」：手机号短信验证码注册（Day 24 新增，PRD 3.7 节 F11）
// ---------------------------------------------------------------------
// 两步式（SDK 原生用法，绝不能先手动 getVerification 再 signUp，否则双短信）：
//   第一步：一次填齐 手机号 + 用户名 + 密码 → 点「获取验证码」
//           → AuthService.requestSignUpCode（此刻 SDK 发 1 条短信）
//   第二步：填收到的验证码 → 点「完成注册」
//           → AuthService.completeSignUp（内部：新用户注册+自动登录；
//             手机号已注册过则自动转为验证码登录，不报错）
//
// 校验规则（云端实测为准，Day 24 修正）：
//   手机号 = 1 开头 11 位；
//   用户名 = 云端正则 ^[a-z][0-9a-z_-]{5,24}$：小写字母开头，总长 6–25 位，
//            只能含小写字母/数字/下划线/连字符（官方文档写的「1–32 位」与
//            云端实际不符，以报错正则为准）；
//   密码 = 8–32 位且同时含字母和数字。
// 防误触：发送按钮 60 秒倒计时（省短信钱，也防手抖连发）。
// =====================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../net/auth_service.dart';
import '../store/user_store.dart';
import '../utils/design_tokens.dart';
import 'profile_setup_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();

  bool _codeSent = false; // 是否已发码（决定验证码框是否出现）
  bool _sending = false; // 发码请求进行中
  bool _loading = false; // 完成注册请求进行中
  int _countdown = 0; // 倒计时秒数
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _phoneCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  // ---------------- 表单校验（PRD 3.7.1 规则） ----------------

  String? _validatePhone(String? v) {
    final String s = v?.trim() ?? '';
    if (s.isEmpty) return '请输入手机号';
    if (!RegExp(r'^1\d{10}$').hasMatch(s)) return '手机号格式不对（1 开头 11 位）';
    return null;
  }

  String? _validateUsername(String? v) {
    final String s = v?.trim() ?? '';
    if (s.isEmpty) return '请输入用户名';
    // 与云端正则完全一致：^[a-z][0-9a-z_-]{5,24}$
    if (!RegExp(r'^[a-z][0-9a-z_-]{5,24}$').hasMatch(s)) {
      return '6–25 位，小写字母开头，仅限小写字母/数字/_/-';
    }
    return null;
  }

  String? _validatePassword(String? v) {
    final String s = v ?? '';
    if (s.isEmpty) return '请输入密码';
    if (s.length < 8 || s.length > 32) return '密码 8–32 位';
    if (!RegExp(r'^(?=.*[A-Za-z])(?=.*\d)').hasMatch(s)) return '密码需同时包含字母和数字';
    return null;
  }

  // ---------------- 动作 ----------------

  /// 第一步：获取验证码（内部走 signUp，SDK 发 1 条短信）
  Future<void> _sendCode() async {
    // 只校验前三项（验证码框还没出现/内容为空是正常的）
    if (_phoneCtrl.text.trim().isEmpty ||
        _usernameCtrl.text.trim().isEmpty ||
        _passwordCtrl.text.isEmpty ||
        _validatePhone(_phoneCtrl.text) != null ||
        _validateUsername(_usernameCtrl.text) != null ||
        _validatePassword(_passwordCtrl.text) != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先正确填写手机号、用户名和密码')),
      );
      return;
    }

    setState(() => _sending = true);
    final AuthResult result = await AuthService.requestSignUpCode(
      phone: _phoneCtrl.text.trim(),
      username: _usernameCtrl.text.trim(),
      password: _passwordCtrl.text,
    );
    if (!mounted) return;
    setState(() => _sending = false);

    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送验证码失败：${result.message}')),
      );
      return;
    }

    // 成功：显示验证码框、启动 60 秒倒计时
    _codeCtrl.clear();
    setState(() {
      _codeSent = true;
      _countdown = 60;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _countdown = _countdown - 1);
      if (_countdown <= 0) t.cancel();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('验证码已发送，请查看手机短信')),
    );
  }

  /// 第二步：完成注册（并自动登录）
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final String code = _codeCtrl.text.trim();
    if (!RegExp(r'^\d{4,8}$').hasMatch(code)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入短信验证码')));
      return;
    }

    setState(() => _loading = true);
    final AuthResult result = await AuthService.completeSignUp(code);
    if (!mounted) return;
    setState(() => _loading = false);

    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('注册失败：${result.message}')),
      );
      return;
    }

    // 注册成功 = 已自动登录：同步账号身份（uid 换源）+ 拉云端资料，
    // 然后把注册页和登录页一起退掉，直接回到底部导航主界面。
    final UserStore userStore = context.read<UserStore>();
    await userStore.syncAccount();
    if (!mounted) return;

    final NavigatorState nav = Navigator.of(context);
    nav.popUntil((Route<dynamic> route) => route.isFirst);

    // 新账号云端没有 users 记录 → 直接进「完善资料」，
    // 否则建班/加入会报「用户不存在，请先登记身份」
    if (!userStore.profileReady) {
      nav.push(MaterialPageRoute<void>(
          builder: (_) => const ProfileSetupPage()));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('注册成功，已自动登录')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: kTextPrimary),
        title: const Text('注册',
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
              const Text('创建你的账号',
                  style: TextStyle(
                      fontSize: kFontHero,
                      fontWeight: FontWeight.bold,
                      color: kTextPrimary)),
              const SizedBox(height: 8),
              const Text('注册后可加入班级；本地素材不受影响，游客也能继续用',
                  style: TextStyle(fontSize: kFontBody, color: kTextSecondary)),
              const SizedBox(height: 32),

              // ---------- 手机号 ----------
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                maxLength: 11,
                decoration: const InputDecoration(
                  labelText: '手机号',
                  prefixIcon: Icon(Icons.phone_outlined),
                  counterText: '', // 隐藏右下角字数统计
                  border: OutlineInputBorder(),
                ),
                validator: _validatePhone,
              ),
              const SizedBox(height: 16),

              // ---------- 用户名 ----------
              TextFormField(
                controller: _usernameCtrl,
                maxLength: 25,
                decoration: const InputDecoration(
                  labelText: '用户名（登录用，注册后不可改）',
                  hintText: '如 ethan2026：小写字母开头，6–25 位',
                  prefixIcon: Icon(Icons.alternate_email),
                  counterText: '', // 隐藏右下角字数统计
                  border: OutlineInputBorder(),
                ),
                validator: _validateUsername,
              ),
              const SizedBox(height: 16),

              // ---------- 密码 ----------
              TextFormField(
                controller: _passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '密码（8–32 位，含字母和数字）',
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder(),
                ),
                validator: _validatePassword,
              ),
              const SizedBox(height: 16),

              // ---------- 验证码（发码成功后才出现） ----------
              if (_codeSent) ...<Widget>[
                TextFormField(
                  controller: _codeCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: '短信验证码',
                    prefixIcon: Icon(Icons.sms_outlined),
                    counterText: '',
                    border: OutlineInputBorder(),
                  ),
                  validator: (String? v) =>
                      (v == null || v.trim().isEmpty) ? '请输入验证码' : null,
                ),
                const SizedBox(height: 8),
                // 重发倒计时提示
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _countdown > 0
                        ? '$_countdown 秒后可重新发送'
                        : '收不到？重新点上方「获取验证码」',
                    style: const TextStyle(
                        fontSize: kFontCaption, color: kTextHint),
                  ),
                ),
              ],
              const SizedBox(height: 8),

              // ---------- 获取验证码 ----------
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: kTeal,
                  side: const BorderSide(color: kTeal),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(kRadiusBtn)),
                ),
                onPressed: (_sending || _countdown > 0) ? null : _sendCode,
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(
                        _codeSent
                            ? (_countdown > 0 ? '已发送（$_countdown s）' : '重新发送验证码')
                            : '获取验证码',
                        style: const TextStyle(fontSize: kFontTitle)),
              ),
              const SizedBox(height: 12),

              // ---------- 完成注册 ----------
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
                    : const Text('完成注册',
                        style: TextStyle(fontSize: kFontTitle)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
