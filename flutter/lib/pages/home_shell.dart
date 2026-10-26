// =====================================================================
// 底部导航壳（App 主框架，四栏切换）—— 1:1 复刻「学在重邮」底部导航
// ---------------------------------------------------------------------
// 结构：IndexedStack 装四个页面（切 tab 不丢状态）+ 自绘底部导航条
//       （首页 | 班级 | 作业[99+ 角标] | 我的，选中态青绿）。
// =====================================================================

import 'package:flutter/material.dart';

import 'class_list_page.dart';
import 'home_page.dart';
import 'profile_page.dart';
import 'work_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  // 品牌青绿（学在重邮同款）
  static const Color teal = Color(0xFF2BC8B7);
  static const Color badgeRed = Color(0xFFF86C6C);

  int _index = 0;

  static const List<Widget> _pages = <Widget>[
    HomePage(),
    ClassListPage(),
    WorkPage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack：四个页面都常驻内存，切 tab 不丢各自状态
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  /// 自绘底部导航条：白底 + 四个 item（图标 + 文字，选中青绿）
  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: <Widget>[
              Expanded(child: _navItem(0, Icons.home_filled, '首页')),
              Expanded(child: _navItem(1, Icons.menu_book_outlined, '班级')),
              // 作业 tab 带 99+ 红色角标（1:1 复刻参考图）
              Expanded(child: _navItem(2, Icons.notifications_none, '作业',
                  badge: '99+')),
              Expanded(child: _navItem(3, Icons.school_outlined, '我的')),
            ],
          ),
        ),
      ),
    );
  }

  /// 单个导航 item
  Widget _navItem(int index, IconData icon, String label, {String? badge}) {
    final bool selected = _index == index;
    final Color color = selected ? teal : const Color(0xFF999999);
    return GestureDetector(
      onTap: () => setState(() => _index = index),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          // 图标 + 可选角标
          Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Icon(icon, size: 26, color: color),
              if (badge != null)
                Positioned(
                  top: -6,
                  right: -14,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: badgeRed,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    constraints: const BoxConstraints(minWidth: 18),
                    child: Text(
                      badge,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 10, color: Colors.white, height: 1.4),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.w400,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
