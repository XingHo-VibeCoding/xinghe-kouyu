// =====================================================================
// 视图「需要登录」：游客点「班级」栏时的引导页（Day 24 新增，PRD 3.7.1）
// ---------------------------------------------------------------------
// 为什么单独一页而不是弹窗：
//   1. 班级栏是常驻 tab，弹窗关掉后用户会看到半截空白列表，逻辑上不成立；
//   2. 用一页明确的空态，用户知道「这里需要登录」，且随时能点按钮登录；
//   3. 登录成功后 UserStore 通知重建，本页自动被真正的班级列表替换，
//      不需要任何 Navigator 操作。
// 游客可用的功能（本地素材、播放、复读）都在「播放」栏，不受影响。
// =====================================================================

import 'package:flutter/material.dart';

import '../utils/design_tokens.dart';
import 'login_page.dart';

class LoginRequiredView extends StatelessWidget {
  const LoginRequiredView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                // 圆形浅青底 + 书本图标
                Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(
                    color: kTealSoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.menu_book_outlined,
                      size: 44, color: kTeal),
                ),
                const SizedBox(height: 24),
                const Text(
                  '登录后可加入班级',
                  style: TextStyle(
                    fontSize: kFontTitle,
                    fontWeight: FontWeight.bold,
                    color: kTextPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '班级需要把你的身份同步到云端，\n所以要先登录账号。\n\n本地素材、播放与复读不受影响，\n不登录也能一直用。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: kFontBody,
                    height: 1.6,
                    color: kTextSecondary,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: kTeal,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(kRadiusBtn)),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => const LoginPage()));
                    },
                    child: const Text('登录 / 注册',
                        style: TextStyle(fontSize: kFontTitle)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
