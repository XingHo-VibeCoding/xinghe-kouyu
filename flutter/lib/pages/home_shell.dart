// =====================================================================
// 底部导航壳（App 主框架，四栏切换）
// ---------------------------------------------------------------------
// 结构：IndexedStack 装四个页面（切 tab 不丢状态）+ 自绘底部导航条
//       （首页 | 班级 | 播放 | 我的，选中态青绿胶囊 + 填充图标）
//
// 登录门槛（Day 24，PRD 3.7.1）：「班级」栏需要「登录 + 云端资料就绪」
//   状态 1：未登录            → LoginRequiredView（登录引导）
//   状态 2：已登录、资料未完善 → ProfileSetupPage（填昵称 + 选身份）
//   状态 3：都就绪            → ClassListPage（真正的班级列表）
//   三个状态全靠 UserStore 通知自动切换，不需要手动跳转——
//   登录成功后从状态 1 走到 2 或 3，登出后自动退回 1。
// =====================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../store/user_store.dart';
import '../utils/design_tokens.dart';
import 'class_list_page.dart';
import 'home_page.dart';
import 'login_required_view.dart';
import 'material_list_page.dart';
import 'profile_page.dart';
import 'profile_setup_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// 班级栏：按「登录态 + 资料态」三态渲染
  Widget _buildClassTab(UserStore userStore) {
    // 启动引导中：登录态还没确认完。此时显示加载态而不是「请先登录」，
    // 否则冷启动会先闪一下登录引导再跳走（Day 24 修 BUG）。
    if (userStore.booting) return _buildLoading();

    if (!userStore.isSignedIn) return const LoginRequiredView();

    // 已登录、正在向云端确认资料：显示加载态。
    // 不能在这里先渲染完善资料页——网络慢时会闪一下「还差一步」，
    // 让资料齐全的老用户以为身份丢了（Day 24 修 BUG）。
    if (!userStore.profileReady && userStore.profileLoading) {
      return _buildLoading();
    }

    if (!userStore.profileReady) return const ProfileSetupPage();
    return const ClassListPage();
  }

  /// 轻量加载态（居中细圈，避免整页白屏让人觉得卡死）
  Widget _buildLoading() {
    return const Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2, color: kTeal),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final UserStore userStore = context.watch<UserStore>();
    return Scaffold(
      // IndexedStack：四个页面都常驻内存，切 tab 不丢各自状态
      body: IndexedStack(
        index: _index,
        children: <Widget>[
          const HomePage(),
          _buildClassTab(userStore),
          const MaterialListPage(),
          const ProfilePage(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  /// 自绘底部导航条：白底 + 四个 item（选中态 = 青绿胶囊 + 填充图标）
  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: kCard,
        border: Border(top: BorderSide(color: kBorder)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: <Widget>[
              Expanded(child: _navItem(0, Icons.home_filled, '首页')),
              Expanded(child: _navItem(1, Icons.menu_book_outlined, '班级')),
              // 原「作业」栏换成播放器（素材列表），承接班级文件下载后的本地播放
              Expanded(child: _navItem(2, Icons.library_music_outlined, '播放')),
              Expanded(child: _navItem(3, Icons.school_outlined, '我的')),
            ],
          ),
        ),
      ),
    );
  }

  /// 单个导航 item：选中态 = 青绿浅底胶囊 + 实心图标 + 加粗文字
  Widget _navItem(int index, IconData icon, String label) {
    final bool selected = _index == index;
    return GestureDetector(
      onTap: () => setState(() => _index = index),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          // 选中态：青绿浅底胶囊包住图标，形成「被点亮」的聚焦感
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: 44,
            height: 30,
            decoration: BoxDecoration(
              color: selected ? kTealSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, size: 22, color: selected ? kTeal : kTextHint),
          ),
          const SizedBox(height: 3),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: kFontCaption,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: selected ? kTeal : kTextHint,
            ),
            child: Text(label),
          ),
        ],
      ),
    );
  }
}
